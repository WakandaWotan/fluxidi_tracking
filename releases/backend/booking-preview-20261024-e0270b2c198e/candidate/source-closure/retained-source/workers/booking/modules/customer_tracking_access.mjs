// Customer tracking access issued from a booking record the caller already
// authorized. The live poll does not use this module and does not read Booking KV.

import { publicDriverPreviewFromFleet } from "./fleet_roster_availability.mjs";
import { projectPublicBookingVehicle, resolvePublicBookingPhotoUrl } from "./public_booking_vehicles.mjs";
import { _companyDriverIndexKey } from "./driver_ops.js";
import { companyFleetVehiclesKey, driverFromFleet, vehicleFromFleet } from "./company_dispatch.mjs";
import { publicDriver, publicVehicle, publicOperationalRoute } from "../../tracking/modules/customer_live_snapshot.mjs";
import { _normLifecycleStatus } from "./booking_utils.js";
import { companyTrackingObjectName } from "../../tracking/modules/company_tracking_room.mjs";
import { trackingPhaseForStatus } from "../../tracking/modules/customer_live_snapshot.mjs";
import { nextOperationalPoint } from './operational_itinerary.mjs';
import {customerBookedRouteGeometryV1} from './customer_booked_route_geometry_v1.mjs';

// Missing revisions have one deterministic baseline in both readers and writers.
// Bootstrap must never persist its earlier booking snapshot to initialize them.
function trackingRevision(source) {
  return {
    lifecycle_seq: Number(source?.customer_tracking_seq) || 1,
    assignment_version: Number(source?.customer_tracking_assignment_version) || 1,
  };
}

export function stampTrackingLifecycle(rec, { assignmentChanged = false, bookingStatus = "" } = {}) {
  const revision = trackingRevision(rec);
  const seq = revision.lifecycle_seq;
  let version = revision.assignment_version;
  if (assignmentChanged) version += 1;
  if (!version) version = 1;
  rec.customer_tracking_seq = seq + 1;
  rec.customer_tracking_assignment_version = version;
  rec.customer_tracking_phase = trackingPhaseForStatus(bookingStatus);
  return {
    lifecycle_seq: rec.customer_tracking_seq,
    assignment_version: rec.customer_tracking_assignment_version,
  };
}

// Read complete coordinate pairs only. Never combine unrelated sources or
// coerce a missing/blank coordinate to zero.
function trackingPoint(value) {
  const lat = value?.latitude ?? value?.lat;
  const lng = value?.longitude ?? value?.lng ?? value?.lon;
  const numeric = v => (typeof v === "number" || typeof v === "string") && String(v).trim() !== "" && Number.isFinite(Number(v));
  if (!numeric(lat) || !numeric(lng) || Math.abs(Number(lat)) > 90 || Math.abs(Number(lng)) > 180) return null;
  return { latitude: Number(lat), longitude: Number(lng) };
}

export function trackingRoutePoint(rec, side) {
  const names = side === "pickup" ? ["from", "pickup"] : ["to", "dropoff", "destination"];
  for (const source of [rec, rec?.booking]) {
    if (!source) continue;
    for (const name of names) {
      const point = trackingPoint({
        lat: source[`${name}_lat`] ?? source[`${name}Lat`],
        lng: source[`${name}_lng`] ?? source[`${name}Lng`] ?? source[`${name}_lon`] ?? source[`${name}Lon`],
      });
      if (point) return point;
    }
    const point = trackingPoint(source[side]);
    if (point) return point;
  }
  return null;
}

function assignedDriverId(source) {
  if (source && "assigned_driver_id" in source) return source.assigned_driver_id || "";
  if (source && "assignedDriverId" in source) return source.assignedDriverId || "";
  const driver = source?.assigned_driver || source?.assignedDriver;
  return source?.assigned_driver_id || source?.assignedDriverId ||
    driver?.driver_id || driver?.driverId || driver?.id || source?.driver_id || source?.driverId || "";
}
export function trackingLegs(rec) {
  return [rec?.operational_legs, rec?.operationalLegs, rec?.booking?.operational_legs, rec?.booking?.operationalLegs]
    .find(Array.isArray)?.filter(v => v && typeof v === "object") || [];
}
export function trackingLegId(leg) { return String(leg?.leg_id || leg?.legId || ""); }
// Only canonical status fields establish terminality; tracking hints never do.
function terminalRecordPhase(record) {
  for (const value of [record?.status, record?.stage, record?.lifecycle_status, record?.lifecycleStatus]) {
    const status = _normLifecycleStatus(value);
    if (status === "COMPLETED" || status === "CANCELLED") return status.toLowerCase();
  }
  return "";
}
function terminalParentPhase(rec) {
  return terminalRecordPhase(rec) || terminalRecordPhase(rec?.booking);
}
export function trackingSource(rec, requested = "") {
  const legs = trackingLegs(rec);
  if (legs.length <= 1) {
    return !requested || requested === "primary" || requested === trackingLegId(legs[0]) ? rec : null;
  }
  // An explicit leg never falls back to the parent summary or its sibling.
  if (requested && requested !== "primary") return legs.find(l => trackingLegId(l) === requested) || null;
  const open = legs.filter(l => !terminalRecordPhase(l) && !["completed", "cancelled", "stopped"].includes(trackingPhaseForStatus(l.status || l.customer_tracking_phase)));
  const selected = open.find(l => String(l.leg_type || l.legType).toLowerCase() === "outbound") || open[0] || legs[0];
  return trackingLegId(selected) ? selected : null;
}
export function mirrorTrackingLeg(rec, source) {
  if (!source || source === rec) return;
  for (const list of [rec.operational_legs, rec.operationalLegs, rec.booking?.operational_legs, rec.booking?.operationalLegs]) {
    for (const leg of Array.isArray(list) ? list : []) {
      if (trackingLegId(leg) === trackingLegId(source)) Object.assign(leg, source);
    }
  }
}
// Assignment writers use the same booking-owned lifecycle as all other events.
// A split mutation passes its selected leg; a shared assignment passes all legs.
// Retained trip facts belong to their original assignment, not every future
// assignment of this booking/leg. Legacy unstamped facts remain readable until
// the next assignment writer records their original revision.
export function currentTrackingTrip(source) {
  const trip = source?.trip;
  if (!trip || typeof trip !== "object") return null;
  if (trip.assignment_version != null && Number(trip.assignment_version) !== trackingRevision(source).assignment_version) return null;
  if (trip.operational_leg && trip.operational_leg !== (trackingLegId(source) || "primary")) return null;
  return trip;
}

export function stampTrackingAssignment(rec, { leg = "", legs = null, publicFactsFresh = false } = {}) {
  const rows = trackingLegs(rec);
  const targets = rows.length > 1
    ? rows.filter(row => legs ? legs.includes(String(row.leg_type || row.legType).toLowerCase()) : !leg || trackingLegId(row) === leg || String(row.leg_type || row.legType).toLowerCase() === leg)
    : [rec];
  for (const target of targets) {
    const facts = trackingFactsFromRecord(rec, null, target === rec ? "" : trackingLegId(target));
    const terminal = ["completed", "cancelled", "stopped"].includes(facts.tracking_phase);
    // Stamp before incrementing; never relabel an already-retired trip on a
    // second unassign/reassign. Keep the historical facts intact.
    if (target.trip && typeof target.trip === "object") {
      target.trip.assignment_version ??= trackingRevision(target).assignment_version;
      target.trip.operational_leg ??= target === rec ? "primary" : trackingLegId(target);
    }
    if (target.tracking_session_id) {
      target.customer_tracking_session_assignment_version ??= trackingRevision(target).assignment_version;
    }
    stampTrackingLifecycle(target, { assignmentChanged: true,
      bookingStatus: terminal ? facts.tracking_phase : facts.driver_id ? "assigned" : "unassigned" });
    if (!publicFactsFresh) target.customer_tracking_public_assignment_fresh = false;
    mirrorTrackingLeg(rec, target);
  }
  return targets.map(target => target === rec ? "" : trackingLegId(target));
}

export async function syncTrackingAssignments(env, rec, scopes) {
  const results = [];
  for (const leg of scopes) results.push(await syncTrackingLifecycle(env, rec, { leg }));
  return results.length === 1 ? results[0] : {
    confirmed: results.every(result => result.confirmed), legs: results,
    room_writes: results.reduce((sum, result) => sum + (result.room_writes || 0), 0),
  };
}

export function trackingFactsFromRecord(rec, session, leg = "") {
  const booking = rec?.booking && typeof rec.booking === "object" ? rec.booking : {};
  const source = trackingSource(rec, leg);
  const multi = trackingLegs(rec).length > 1;
  const detail = multi ? {} : booking;
  const driverId = String(multi && source && ("assigned_driver_id" in source || "assignedDriverId" in source)
    ? ("assigned_driver_id" in source ? source.assigned_driver_id : source.assignedDriverId) || "" : (source && ("assigned_driver_id" in source || "assignedDriverId" in source) ? assignedDriverId(source) : assignedDriverId(source) || assignedDriverId(detail)));
  const activeTrip = currentTrackingTrip(source);
  // Identity comes from the selected assignment, never its sibling/parent.
  const vehicleId = String(source && ("assigned_vehicle_id" in source || "assignedVehicleId" in source)
    ? ("assigned_vehicle_id" in source ? source.assigned_vehicle_id : source.assignedVehicleId) || ""
    : detail.assigned_vehicle_id || detail.assignedVehicleId || "");
  const recordStatus = source?.status || detail.status || source?.stage || detail.stage || "assigned";
  const recordPhase = trackingPhaseForStatus(recordStatus);
  const parentPhase = terminalParentPhase(rec);
  const terminal = parentPhase || terminalRecordPhase(source) ||
    (!multi ? terminalRecordPhase(trackingLegs(rec)[0]) : "");
  const status = terminal || (!multi
    ? source?.customer_tracking_phase || (["completed", "cancelled", "stopped"].includes(recordPhase) ? recordPhase : activeTrip?.started_at ? "in_progress" : recordStatus)
    : !source ? "unassigned"
    : ["completed", "cancelled"].includes(parentPhase) ? parentPhase
    : ["completed", "cancelled", "stopped"].includes(recordPhase) ? recordPhase
    : source?.customer_tracking_phase || (activeTrip?.started_at ? "in_progress" : multi && driverId && recordPhase === "unassigned" ? "assigned" : recordPhase));
  const resolvedPhase = trackingPhaseForStatus(status);
  // Some booking flows retain pending as their order status after the
  // company assigns a driver. Keep the identity visible before pickup,
  // without granting GPS/ETA permissions.
  const publicPhase = !terminal && driverId && resolvedPhase === "unassigned"
    ? "assigned"
    : resolvedPhase;
  return {
    tenant_id: String(rec?.tenant_id || rec?.tenantId || booking.tenant_id || ""),
    company_id: String(rec?.company_id || rec?.companyId || booking.company_id || ""),
    booking_id: String(rec?.booking_id || rec?.bookingId || rec?.id || booking.booking_id || booking.bookingId || booking.id || ""),
    operational_leg: multi ? trackingLegId(source) : "primary",
    disable_primary: multi,
    customer_id: String(session?.customer_id || rec?.customer_id || booking.customer_id || ""),
    driver_id: driverId,
    ...trackingRevision(source),
    booking_status: terminal || String(recordStatus),
    tracking_phase: publicPhase,
    session_id: String(activeTrip?.session_id ||
      ((!source?.trip || activeTrip) && (source?.customer_tracking_session_assignment_version == null ||
        Number(source.customer_tracking_session_assignment_version) === trackingRevision(source).assignment_version)
        ? source?.tracking_session_id : "") || ""),
    vehicle_id: vehicleId,
    // Flat historical labels have no assignment binding. Hydrate only the
    // current scoped IDs before publishing a grant; never trust these labels.
    driver: {},
    assigned_vehicle: {},
    pickup: trackingRoutePoint(source, "pickup"),
    destination: publicPhase === "in_progress" && source?.operational_route
      ? trackingPoint(nextOperationalPoint(source.operational_route)) : trackingRoutePoint(source, "destination"),
    operational_route: publicPhase === "in_progress" ? publicOperationalRoute(source?.operational_route) : null,
  };
}

// Resolve only the existing public media reference format against the server
// request origin. Consent is checked by the existing public driver projector
// before this function; never resolve an internal portrait or client origin.
function trackingPublicPhotoUrl(ref, requestOrigin) {
  const raw = String(ref || "").trim();
  const relative = raw.startsWith("/public/media/") || raw.startsWith("public-media/");
  try {
    const origin = new URL(requestOrigin);
    if (origin.protocol !== "https:" || origin.username || origin.password) return relative ? "" : raw;
    const resolved = resolvePublicBookingPhotoUrl(raw, origin.origin);
    if (!resolved) return "";
    const url = new URL(resolved);
    if (relative && (url.origin !== origin.origin || !url.pathname.startsWith("/public/media/"))) return "";
    return resolved;
  } catch { return relative ? "" : raw; }
}

function trackingPublicVehiclePhoto(vehicle, requestOrigin) {
  const absolute = projectPublicBookingVehicle(vehicle)?.photo_url;
  if (absolute) return absolute;
  try {
    const origin = new URL(requestOrigin);
    if (origin.protocol !== "https:" || origin.username || origin.password) return "";
    const photo = projectPublicBookingVehicle(vehicle, origin.origin)?.photo_url;
    if (!photo) return "";
    const resolved = new URL(photo);
    return resolved.origin === origin.origin && resolved.pathname.startsWith("/public/media/") ? resolved.href : "";
  } catch { return ""; }
}

async function trackingPublicAssignment(env, facts, requestOrigin = "") {
  const empty = { driver: {}, assigned_vehicle: {} };
  if (!facts.driver_id || !facts.tenant_id || !facts.company_id ||
      !["assigned", "en_route_pickup", "arrived_pickup", "in_progress"].includes(facts.tracking_phase)) return empty;
  // Cold grant/lifecycle path only: two existing scoped indices, no KV scans,
  // no profile lookup and no reads added to the live GPS/poll hot path.
  const read = async key => {
    try { return await env?.BOOKING_KV?.get(key, { type: "json" }); }
    catch (_) { return null; } // Missing metadata never resurrects old labels.
  };
  const { readCompanyDriverIndex, hasDriverIndexCoordinator } = await import("./driver_index_mutation.mjs");
  const [index, inventory] = await Promise.all([
    hasDriverIndexCoordinator(env) ? readCompanyDriverIndex(env, facts) : read(_companyDriverIndexKey(facts)),
    facts.vehicle_id ? read(companyFleetVehiclesKey(facts)) : null,
  ]);
  const fleet = {
    drivers: Object.values(index?.drivers || {}).filter(row => row && typeof row === "object"),
    vehicles: Array.isArray(inventory) ? inventory : Array.isArray(inventory?.vehicles) ? inventory.vehicles : [],
  };
  const inScope = row => row &&
    (!row.tenant_id && !row.tenantId || String(row.tenant_id || row.tenantId) === facts.tenant_id) &&
    (!row.company_id && !row.companyId || String(row.company_id || row.companyId) === facts.company_id);
  const driver = driverFromFleet(fleet, facts.driver_id);
  const vehicle = vehicleFromFleet(fleet, facts.vehicle_id);
  return {
    driver: inScope(driver) ? publicDriver({
      display_name: driver.display_name || driver.displayName,
      customer_contact:driver.public_customer_contact_enabled === true ? {
        customer_allowed:true,phone_e164:driver.public_customer_contact_phone,
        call_allowed:driver.public_customer_call_enabled === true,
        whatsapp_allowed:driver.public_customer_whatsapp_enabled === true,
      } : null,
      photo_url: trackingPublicPhotoUrl(publicDriverPreviewFromFleet(driver).public_photo_url, requestOrigin),
      rating_average: driver.driver_rating_avg ?? driver.driverRatingAvg ?? driver.rating_avg ?? driver.ratingAvg,
      rating_count: driver.driver_rating_count ?? driver.driverRatingCount ?? driver.rating_count ?? driver.ratingCount,
    }) : {},
    assigned_vehicle: inScope(vehicle) ? publicVehicle({
      vehicle_id: facts.vehicle_id,
      fallback_asset: vehicle.fallback_asset ?? vehicle.fallbackAsset,
      label: vehicle.brand_model || vehicle.brandModel || vehicle.vehicle_name || vehicle.vehicleName || vehicle.name,
      color: vehicle.color,
      photo_url: trackingPublicVehiclePhoto(vehicle, requestOrigin),
      license_plate: vehicle.license_plate || vehicle.licensePlate || vehicle.plate,
    }) : {},
  };
}

async function postGrant(env, facts, extra, requestOrigin = "") {
  const ns = env?.COMPANY_TRACKING;
  if (!ns || typeof ns.idFromName !== "function") {
    return { ok: false, confirmed: false, transient: true, reason: "tracking_unavailable", room_writes: 0 };
  }
  try {
  const presentation = await trackingPublicAssignment(env, facts, requestOrigin);
  const stub = ns.get(ns.idFromName(companyTrackingObjectName(facts.tenant_id, facts.company_id)));
  const res = await stub.fetch("https://company-tracking.internal/customer-grant", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ ...facts, ...presentation, ...extra }),
  });
  if (!res.ok) return { confirmed: false, transient: res.status >= 500 || res.status === 429, reason: "tracking_unavailable", room_writes: 0 };
  const body = await res.json();
  return { ...body, room_writes: body.applied ? 1 : 0,
    // Current owner-authorized booking presentation is independent of GPS.
    // Never return stale Room media or internal profile fields.
    public_assignment: body.confirmed === true && body.assignment_version === facts.assignment_version
      && body.tracking_phase === facts.tracking_phase ? {
        tenant_id: facts.tenant_id, company_id: facts.company_id,
        booking_id: facts.booking_id, operational_leg: facts.operational_leg,
        assignment_version: facts.assignment_version,
        driver: presentation.driver, vehicle: presentation.assigned_vehicle,
      } : null,
  };
  } catch (_) { return { confirmed: false, transient: true, reason: "tracking_unavailable", room_writes: 0 }; }
}

export async function syncTrackingLifecycle(env, rec, { leg = "", accessTokenHash = "" } = {}) {
  if (!leg && trackingLegs(rec).length > 1 && Boolean(terminalParentPhase(rec))) {
    const results = [];
    for (const row of trackingLegs(rec)) results.push(await syncTrackingLifecycle(env, rec, { leg: trackingLegId(row), accessTokenHash }));
    return { confirmed: results.every(r => r.confirmed), legs: results, room_writes: results.reduce((n,r) => n + (r.room_writes || 0), 0) };
  }
  const facts = trackingFactsFromRecord(rec, { customer_id: rec?.customer_id }, leg);
  facts.booking_id = facts.booking_id || String(rec?.booking_id || "");
  if (!facts.tenant_id || !facts.company_id || !facts.booking_id || !facts.lifecycle_seq) {
    return { ok: false, confirmed: false, reason: "identity_missing", room_writes: 0 };
  }
  return postGrant(env, facts, { kind: "lifecycle", access_token_hash: accessTokenHash });
}

function tokenFromBytes() {
  const bytes = new Uint8Array(32);
  crypto.getRandomValues(bytes);
  return [...bytes].map((b) => b.toString(16).padStart(2, "0")).join("");
}

async function hashToken(token) {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(token));
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

export async function issueCustomerTrackingAccess(env, rec, session, { bookingId, leg = "", requestOrigin = "" } = {}) {
  const source = trackingSource(rec, leg);
  if (!source) return { ok: false, error: "not_found" };
  const facts = trackingFactsFromRecord(rec, session, leg);
  facts.booking_id = String(bookingId || facts.booking_id);
  // Reliable Choice grants start only after authoritative NAV. Assignment
  // metadata remains available through the existing booking projection.
  if(rec?.p12_reliable_choice?.schema === 'fluxidi-reliable-choice-v1' && facts.tracking_phase === 'assigned') {
    return { ok: false, error: 'tracking_waiting_nav', tracking_phase: facts.tracking_phase,
      tracking_session: null, tracking_sync: { confirmed: false }, booking_kv_reads: 0 };
  }
  if (!facts.driver_id && !["completed", "cancelled", "stopped"].includes(facts.tracking_phase)) {
    return { ok: false, error: "not_assigned", tracking_session: null, tracking_sync: { confirmed: false }, booking_kv_reads: 0 };
  }
  if (facts.tracking_phase === "stopped" || facts.tracking_phase === "completed" || facts.tracking_phase === "cancelled" || facts.tracking_phase === "unassigned") {
    const sync = await syncTrackingLifecycle(env, { ...rec, booking_id: facts.booking_id, customer_id: facts.customer_id }, { leg: terminalParentPhase(rec) ? "" : facts.operational_leg });
    return { ok: false, error: "tracking_closed", tracking_phase: facts.tracking_phase, operational_leg: facts.operational_leg, stamped: false, tracking_session: null, tracking_sync: sync, booking_kv_reads: 0 };
  }
  const token = tokenFromBytes();
  const accessTokenHash = await hashToken(token);
  const sync = await postGrant(env, facts, { kind: "issue", access_token_hash: accessTokenHash }, requestOrigin);
  const issued = sync.confirmed === true && sync.tracking_phase === facts.tracking_phase && sync.assignment_version === facts.assignment_version && sync.position_allowed !== undefined;
  const liveEnough = sync.tracking_phase === facts.tracking_phase && sync.assignment_version === facts.assignment_version && sync.confirmed === true;
  if (!liveEnough || sync.tracking_phase === "completed" || sync.tracking_phase === "cancelled" || sync.tracking_phase === "stopped") {
    return { ok: false, error: "tracking_not_confirmed", transient: sync.transient === true, tracking_session: null, tracking_sync: sync, booking_kv_reads: 0 };
  }
  return {
    ok: true,
    tracking_session: { token, token_type: "Bearer" },
    operational_leg: facts.operational_leg,
    customer_session: "separate",
    booking_status: facts.booking_status,
    tracking_phase: sync.tracking_phase,
    assignment_version: sync.assignment_version,
    lifecycle_seq: sync.lifecycle_seq,
    public_assignment: sync.public_assignment ? {...sync.public_assignment,...await bookedRoutePresentation(rec,source,facts)} : null,
    tracking_sync: { confirmed: sync.confirmed === true, reason: sync.reason, room_writes: sync.room_writes || 0 },
    booking_kv_reads: 0,
    stamped: false,
  };
}

async function bookedRoutePresentation(rec,source,facts){
  if(facts.tracking_phase!=='in_progress')return {};
  const selected=source===rec?trackingLegs(rec)[0]??rec:source;
  const route=await customerBookedRouteGeometryV1({record:rec,source,
    legType:String(selected.leg_type??selected.legType??'outbound'),customerId:facts.customer_id,
    pickup:facts.pickup,destination:facts.destination});
  return route?{planned_route:route}:{};
}

export async function renewCustomerTrackingAccess(env, rec, session, { bookingId, leg = "", requestOrigin = "" } = {}) {
  const source = trackingSource(rec, leg);
  if (!source) return { ok: false, error: "not_found" };
  const facts = trackingFactsFromRecord(rec, session, leg);
  facts.booking_id = String(bookingId || facts.booking_id);
  // Reliable Choice grants start only after authoritative NAV. Assignment
  // metadata remains available through the existing booking projection.
  if(rec?.p12_reliable_choice?.schema === 'fluxidi-reliable-choice-v1' && facts.tracking_phase === 'assigned') {
    return { ok: false, error: 'tracking_waiting_nav', tracking_phase: facts.tracking_phase,
      tracking_session: null, tracking_sync: { confirmed: false }, booking_kv_reads: 0 };
  }
  if (["completed", "cancelled", "stopped"].includes(facts.tracking_phase)) {
    const sync = await syncTrackingLifecycle(env, { ...rec, booking_id: facts.booking_id },
      { leg: terminalParentPhase(rec) ? "" : facts.operational_leg });
    return { ok: false, tracking_session: null, tracking_phase: facts.tracking_phase,
      operational_leg: facts.operational_leg, assignment_version: facts.assignment_version,
      lifecycle_seq: facts.lifecycle_seq, transient: sync.transient === true,
      tracking_sync: sync, booking_kv_reads: 0 };
  }
  const sync = await postGrant(env, facts, { kind: "renew" }, requestOrigin);
  const renewablePhase = ["assigned", "en_route_pickup", "arrived_pickup", "in_progress"].includes(sync.tracking_phase);
  const renewed = sync.confirmed === true && ["renew", "applied"].includes(sync.reason) &&
    sync.renewal_access_retained === true && renewablePhase && Boolean(facts.driver_id) &&
    facts.assignment_version > 0 && sync.assignment_version === facts.assignment_version &&
    sync.lifecycle_seq === facts.lifecycle_seq && sync.tracking_phase === facts.tracking_phase;
  return {
    operational_leg: facts.operational_leg,
    transient: sync.transient === true,
    ok: renewed,
    public_assignment: renewed && sync.public_assignment ? {...sync.public_assignment,...await bookedRoutePresentation(rec,source,facts)} : null,
    tracking_session: null,
    tracking_phase: sync.tracking_phase,
    assignment_version: sync.assignment_version,
    lifecycle_seq: sync.lifecycle_seq,
    tracking_sync: { confirmed: sync.confirmed === true,
      // Preserve the existing Flutter success contract; expose the Room result separately.
      reason: renewed ? "renew" : sync.reason, lifecycle_reason: sync.reason,
      room_writes: sync.room_writes || 0 },
    booking_kv_reads: 0,
  };
}
