/**
 * Vehicle offers at a pickup time: one card per vehicle, driver from roster.
 *
 * Never-set roster ≠ saved empty. A load failure is not availability.
 * Night shifts that cross midnight stay on the existing weekly_roster maths.
 */

import { driverVehicleRelation } from './driver_vehicle_relation.mjs';
import { operationalRoutingInstalledV1 } from './reliable_operational_routes_v1.mjs';
import { reliableRouteQualityV1, productPickupRangeV1, PRODUCT_ETA_V1 } from './product_estimated_eta_v1.mjs';
import {
  evaluateDriverEligibility,
  linkedVehicleIds,
  rideIsSoon,
  normalizeDispatchAvailability,
  AVAILABILITY,
} from "./company_dispatch.mjs";
import { sanitizeTenantString } from "./parsing_utils.js";

const LIVE_REASONS = new Set([
  "assignment_driver_offline",
  "assignment_driver_not_live",
]);

export function fleetVehicleId(vehicle) {
  return sanitizeTenantString(
    vehicle?.vehicle_id ?? vehicle?.vehicleId ?? vehicle?.id,
    128,
  );
}

export function fleetDriverId(driver) {
  if (!driver || typeof driver !== "object") return "";
  return sanitizeTenantString(
    driver.driver_id ?? driver.driverId ?? driver.id,
    96,
  );
}

export function fleetPassengerSeats(vehicle) {
  if (!vehicle || typeof vehicle !== "object") return null;
  const keys = [
    "passenger_capacity",
    "passengerCapacity",
    "max_passengers",
    "maxPassengers",
    "pax",
    "seats",
    "capacity",
  ];
  for (const key of keys) {
    if (!Object.prototype.hasOwnProperty.call(vehicle, key)) continue;
    const n = Number(vehicle[key]);
    if (Number.isFinite(n) && n >= 0) return Math.trunc(n);
  }
  return null;
}

export function indexRosterDrivers(drivers = []) {
  const byId = new Map(), byVehicle = new Map();
  for (const driver of drivers) {
    const id = fleetDriverId(driver); if (id) byId.set(id, driver);
    for (const vehicleId of linkedVehicleIds(driver)) {
      if (!byVehicle.has(vehicleId)) byVehicle.set(vehicleId, []);
      byVehicle.get(vehicleId).push(driver);
    }
  }
  return { byId, byVehicle };
}

const observeFleetDecision=(sink,row)=>{try{sink?.(row);}catch{}};
export function driversLinkedToVehicle(vehicle, drivers, lookup = indexRosterDrivers(drivers), observeDecision, evaluationStage) {
  const vid = fleetVehicleId(vehicle);
  const owner = fleetDriverId(vehicle?.assigned_driver ?? vehicle?.assignedDriver)
    || sanitizeTenantString(
      vehicle?.assigned_driver_id ?? vehicle?.assignedDriverId ?? vehicle?.driver_id,
      96,
    );
  const byId = lookup.byId;
  const out = [];
  const push = (driver) => {
    const id = fleetDriverId(driver);
    if (!id || out.some((row) => fleetDriverId(row) === id)) return;
    const current = byId.get(id) || driver;
    // Explicit new metadata is checked; untouched legacy relationships keep
    // the existing embedded/roster fallback and need no migration.
    if (current.driver_type) {
      const relation=driverVehicleRelation(current, vehicle);
      if (!relation.ok) {
        observeFleetDecision(observeDecision,{candidate_id:vid,driver_id:id,phase:'driver_relation',reason:relation.error,evaluation_stage:evaluationStage});
        return;
      }
    }
    out.push(current);
  };
  const embedded = vehicle?.assigned_driver ?? vehicle?.assignedDriver;
  if (embedded && typeof embedded === "object") push(embedded);
  if (owner) {
    const indexed = byId.get(owner);
    if (indexed) push(indexed);
  }
  for (const driver of lookup.byVehicle.get(vid) || []) push(driver);
  return out;
}

export function rosterEligibilityReasons(evaluation, { ignoreLive = false } = {}) {
  const reasons = Array.isArray(evaluation?.reasons) ? evaluation.reasons : [];
  if (!ignoreLive) return reasons;
  return reasons.filter((reason) => !LIVE_REASONS.has(reason));
}

export function pickOnDutyDriverForVehicle({
  vehicle,
  drivers,
  pickupMs,
  durationMin = 30,
  nowMs = Date.now(),
  ignoreLive = false,
  presenceMap = {},
  blockedDriverIds = new Set(),
  busyReadyByDriver = new Map(),
  plannedOccupancyVerified = false,
  driverLookup,
  scheduleCache,
  observeDecision,
  evaluationStage,
} = {}) {
  const pickupIso = Number.isFinite(Number(pickupMs))
    ? new Date(Number(pickupMs)).toISOString()
    : "";
  const soon = rideIsSoon(pickupIso, nowMs);
  const candidates = driversLinkedToVehicle(vehicle, drivers, driverLookup, observeDecision, evaluationStage);
  if(observeDecision)observeFleetDecision(observeDecision,{candidate_id:fleetVehicleId(vehicle),phase:'driver_candidates',
    reason:candidates.length?'driver_candidates_ready':'assignment_driver_no_vehicle',linked_driver_ids:candidates.map(fleetDriverId),
    ...(candidates.length?{}:{producer:'empty_candidates'}),evaluation_stage:evaluationStage});
  if (!candidates.length) {
    return { ok: false, error: "assignment_driver_no_vehicle", driver: null };
  }
  let firstError = "";
  for (const driver of candidates) {
    if (blockedDriverIds.has(fleetDriverId(driver))) {
      firstError = firstError || "assignment_driver_on_trip";
      continue;
    }
    const evaluation = evaluateDriverEligibility({
      driver,
      presence: presenceMap[fleetDriverId(driver)],
      vehicles: [vehicle],
      drivers,
      atMs: nowMs,
      pickupIso,
      durationMin,
      soon,
      scheduleCache,
      observeDecision,
      evaluationStage,
    });
    let reasons = rosterEligibilityReasons(evaluation, {
      ignoreLive: ignoreLive || !soon,
    });
    const readyAt = busyReadyByDriver.get(fleetDriverId(driver));
    if (Number.isFinite(readyAt) && Number(pickupMs) >= readyAt) {
      reasons = reasons.filter(reason => reason !== "assignment_driver_on_trip");
    } else if (!(plannedOccupancyVerified === true && !soon && Number(pickupMs) > Number(nowMs))
      && normalizeDispatchAvailability(driver.availability_status ?? driver.availabilityStatus) === AVAILABILITY.ON_TRIP
      && !reasons.includes("assignment_driver_on_trip")) {
      reasons.push("assignment_driver_on_trip");
    }
    if (reasons.length === 0) {
      return { ok: true, error: "", driver, evaluation };
    }
    firstError = firstError || reasons[0];
  }
  return {
    ok: false,
    error: firstError || "assignment_driver_not_scheduled",
    driver: null,
  };
}

export function projectBookableVehicleOffers({
  vehicles = [],
  drivers = [],
  pickupMs,
  durationMin = 30,
  pax = 1,
  nowMs = Date.now(),
  ignoreLive = false,
  presenceMap = {},
  blockedDriverIds = new Set(),
  busyReadyByDriver = new Map(),
  plannedOccupancyVerified = false,
  scheduleCache,
  observeDecision,
  evaluationStage,
} = {}) {
  const seen = new Set();
  const offers = [];
  const driverLookup = indexRosterDrivers(drivers);
  for (const vehicle of Array.isArray(vehicles) ? vehicles : []) {
    const vehicleId = fleetVehicleId(vehicle);
    if (!vehicleId || seen.has(vehicleId)) continue;
    seen.add(vehicleId);
    const seats = fleetPassengerSeats(vehicle);
    if (seats != null && seats > 0 && Number(pax) > seats) {
      offers.push({
        vehicle_id: vehicleId,
        vehicle,
        available: false,
        reason: "assignment_capacity",
        driver: null,
        driver_id: "",
        passenger_seats: seats,
      });
      continue;
    }
    const duty = pickOnDutyDriverForVehicle({
      vehicle,
      drivers,
      pickupMs,
      durationMin,
      nowMs,
      ignoreLive,
      presenceMap,
      blockedDriverIds,
      busyReadyByDriver,
      plannedOccupancyVerified,
      driverLookup,
      scheduleCache,
      observeDecision,
      evaluationStage,
    });
    offers.push({
      vehicle_id: vehicleId,
      vehicle,
      available: duty.ok === true,
      reason: duty.ok ? "" : duty.error,
      driver: duty.driver,
      driver_id: fleetDriverId(duty.driver),
      passenger_seats: seats,
    });
  }
  return offers;
}

export function filterVehiclesByRosterOffers(vehicles, offers) {
  const available = new Set(
    (Array.isArray(offers) ? offers : [])
      .filter((row) => row?.available)
      .map((row) => row.vehicle_id),
  );
  return (Array.isArray(vehicles) ? vehicles : []).filter((vehicle) =>
    available.has(fleetVehicleId(vehicle)),
  );
}

export function publicDriverPreviewFromFleet(driver) {
  const id = fleetDriverId(driver);
  if (!id) return { driver_id: "" };
  const profileOn =
    driver?.public_profile_enabled === true || driver?.publicProfileEnabled === true;
  const photoOn =
    driver?.public_photo_enabled === true || driver?.publicPhotoEnabled === true;
  const name = profileOn
    ? sanitizeTenantString(driver?.public_display_name ?? driver?.publicDisplayName, 160)
    : "";
  const photo = photoOn
    ? sanitizeTenantString(
        driver?.public_portrait_url ?? driver?.publicPortraitUrl ??
          driver?.public_photo_url ?? driver?.publicPhotoUrl,
        400,
      )
    : "";
  return {
    driver_id: id,
    ...(name ? { public_display_name: name } : {}),
    ...(photo ? { public_photo_url: photo } : {}),
  };
}

// Request-local presentation binding. JSON, cloned candidates and planning
// durations cannot grant a Core ETA. No binding changes dispatch eligibility.
const coreApproachInputs = new WeakMap();
const approachCandidateKey = c => JSON.stringify([c?.vehicle_id,c?.assigned_driver?.driver_id,c?.origin_source,
  c?.route_profile,c?.route_evidence_id,c?.route_valid_until_ms,c?.travel_seconds,c?.distance_meters,c?.graph_version,c?.planning_only]);
const approachPoint = p => {
  const latitude=p?.latitude??p?.lat,longitude=p?.longitude??p?.lng??p?.lon;
  if(!Number.isFinite(latitude)||Math.abs(latitude)>90||!Number.isFinite(longitude)||Math.abs(longitude)>180)return null;
  return {latitude,longitude,...(p.access?{access:structuredClone(p.access)}:{}),
    ...(p.address?{address:structuredClone(p.address)}:{}),...(p.official_address?{official_address:structuredClone(p.official_address)}:{})};
};
const approachToken = v => typeof v==='string' && v.length>0 && v.length<=512 && !/[\r\n\0]/.test(v);
const approachGpsFresh = (p,now) => p?.access?.kind==='gps' && Number.isSafeInteger(p.access.capturedAt)
  && p.access.capturedAt<=now && now-p.access.capturedAt<30000 && Number.isFinite(p.access.accuracyMeters)
  && p.access.accuracyMeters>0 && p.access.accuracyMeters<=100;

export function bindPublicCoreApproachV1(candidate,{scope,origin,pickup,liveDriverId,liveVehicleId}={}) {
  const now=Date.now();
  origin=approachPoint(origin);pickup=approachPoint(pickup);
  if(!candidate || candidate.origin_source!=='company_live' || candidate.route_profile!=='fluxidi/local-planning-v1'
    || candidate.planning_only!==true || !approachToken(candidate.vehicle_id) || !approachToken(candidate.assigned_driver?.driver_id)
    || liveDriverId!==candidate.assigned_driver.driver_id || liveVehicleId!==candidate.vehicle_id
    || !approachToken(scope?.tenant_id) || !approachToken(scope?.company_id)
    || !origin || !pickup || !approachGpsFresh(origin,now)
    || !approachToken(candidate.route_evidence_id) || !candidate.route_evidence_id.endsWith(':planning')
    || !Number.isSafeInteger(candidate.route_valid_until_ms) || candidate.route_valid_until_ms<=now) return;
  coreApproachInputs.set(candidate,{key:approachCandidateKey(candidate),scope:structuredClone(scope),
    origin:structuredClone(origin),pickup:structuredClone(pickup),planRef:candidate.route_evidence_id,
    graphVersion:candidate.graph_version,planUntil:candidate.route_valid_until_ms});
}

// Read the existing Core product ETA, never the conservative plan duration.
// This is display-only: failures leave availability and financial gates intact.
export async function publicProviderCoreApproachV1({env,row,feasibility,nowMs=Date.now(),committedAsap=false}) {
  const c=feasibility?.next_vehicle_candidate,ctx=coreApproachInputs.get(c);
  if(!ctx || row?.available!==true || feasibility?.would_allow_booking!==true
    || row.vehicle_id!==c.vehicle_id || row.driver_id!==c.assigned_driver?.driver_id
    || ctx.key!==approachCandidateKey(c) || !Number.isFinite(Date.parse(row.pickup_iso)) || (committedAsap!==true&&Date.parse(row.pickup_iso)<=nowMs)
    || !operationalRoutingInstalledV1(env) || !approachGpsFresh(ctx.origin,nowMs) || ctx.planUntil<=nowMs) return null;
  let timer;
  const fresh=now=>ctx.key===approachCandidateKey(c) && approachGpsFresh(ctx.origin,now) && ctx.planUntil>now;
  try {
    const work=async()=>{
      const router=await env.__reliableRegionalRoutes(ctx.scope);
      if(!fresh(Date.now()) || router.scope?.tenant_id!==ctx.scope.tenant_id || router.scope?.company_id!==ctx.scope.company_id) return null;
      await router.resolveForJourney({pickup_lat:ctx.origin.latitude,pickup_lng:ctx.origin.longitude,
        dropoff_lat:ctx.pickup.latitude,dropoff_lng:ctx.pickup.longitude,
        ...(ctx.pickup.official_address?{destination_input:{kind:'address',official_address:ctx.pickup.official_address}}:{})});
      const evidence=await router.route({scope:router.scope,origin:structuredClone(ctx.origin),destination:structuredClone(ctx.pickup),departureAt:Date.now(),gpsRoadContext: ctx.origin.access?.kind === 'gps'});
      const now=Date.now(),q=evidence?.quality,modelSuffix=':'+PRODUCT_ETA_V1;
      // The existing Core producer binds both IDs to the same underlying route
      // and traffic revision. A newer/different route cannot reuse this plan.
      if(!fresh(now) || evidence?.evidenceId!==ctx.planRef.slice(0,-':planning'.length)+modelSuffix
        || evidence.graphVersion!==ctx.graphVersion || evidence.graphVersion!==router.scope.graphVersion
        || evidence.evidenceRevision!==router.scope.evidenceRevision
        || evidence.tenant_id!==ctx.scope.tenant_id || evidence.company_id!==ctx.scope.company_id
        || evidence.planningOnly===true || evidence.etaKind!=='product_estimate' || evidence.certifiedEta!==false
        || evidence.evidenceClass!=='EXACT_STATIC_ROUTE' || !reliableRouteQualityV1(evidence)
        || q?.productGrade!==true || q.modelVersion!==PRODUCT_ETA_V1 || q.incident || q.conflict || q.ambiguous
        || !['AVAILABLE','STALE','UNAVAILABLE'].includes(q.trafficState)
        || !Number.isSafeInteger(evidence.observedAt) || evidence.observedAt>now || now-evidence.observedAt>=15000
        || !Number.isSafeInteger(evidence.validUntil) || evidence.validUntil<=now
        || !Number.isFinite(evidence.seconds) || evidence.seconds<0 || !Number.isFinite(evidence.distanceMeters) || evidence.distanceMeters<0
        || !Number.isFinite(q.errorSeconds) || q.errorSeconds<0 || !approachToken(evidence.productEvidence?.trafficRevision)) return null;
      const until=Math.min(ctx.planUntil,evidence.validUntil,evidence.observedAt+15000,ctx.origin.access.capturedAt+30000);
      const range=productPickupRangeV1({seconds:evidence.seconds,errorSeconds:q.errorSeconds,availabilityErrorSeconds:0,
        confidence:q.tier,conservative:q.conservative,trafficState:q.trafficState,trafficConfidence:q.trafficConfidence});
      if(until<=now || !range || range[1]<=0) return null;
      return {schema:'fluxidi-provider-approach-v1',source:'fluxidi/local-product-estimate',
        vehicle_id:c.vehicle_id,driver_id:c.assigned_driver.driver_id,route_profile:'fluxidi/local-product-estimate',
        distance_meters:evidence.distanceMeters,duration_seconds:evidence.seconds,eta_range_seconds:range,
        arrival_at:new Date(now+range[1]*1000).toISOString(),generated_at_ms:now,valid_until_ms:until,
        route_observed_at_ms:evidence.observedAt,gps_captured_at_ms:ctx.origin.access.capturedAt,gps_accuracy_meters:ctx.origin.access.accuracyMeters,
        route_evidence_id:evidence.evidenceId,graph_version:evidence.graphVersion,evidence_revision:evidence.evidenceRevision,
        traffic_revision:evidence.productEvidence.trafficRevision,traffic_state:q.trafficState,quality_tier:q.tier,
        uncertainty_seconds:q.errorSeconds,estimate_model:PRODUCT_ETA_V1,estimated:true,planning_only:false,calibrated:false,certified_eta:false};
    };
    const deadline=Math.min(ctx.planUntil,ctx.origin.access.capturedAt+30000,nowMs+15000)-Date.now();
    if(deadline<=0)return null;
    return await Promise.race([work(),new Promise(resolve=>{timer=setTimeout(()=>resolve(null),deadline);})]);
  } catch { return null; } finally { clearTimeout(timer); }
}

// Presentation only: reuse the successful pinned evaluator, never calculate a
// second route or turn an estimate into availability or financial authority.
export function publicProviderApproachV1(row, feasibility, nowMs = Date.now()) {
  const candidate = feasibility?.next_vehicle_candidate;
  const arrivalMs = Date.parse(row?.pickup_iso || '');
  if (row?.available !== true || feasibility?.would_allow_booking !== true
      || !row.driver_id || candidate?.vehicle_id !== row.vehicle_id
      || candidate.assigned_driver?.driver_id !== row.driver_id
      || !['mapbox/driving', 'mapbox/driving-traffic'].includes(candidate.route_profile)
      || !Number.isFinite(candidate.origin_travel_distance_meters) || candidate.origin_travel_distance_meters < 0
      || !Number.isFinite(candidate.origin_travel_seconds) || candidate.origin_travel_seconds < 0
      || !Number.isSafeInteger(candidate.route_valid_until_ms) || candidate.route_valid_until_ms <= nowMs
      || !Number.isFinite(arrivalMs) || arrivalMs <= nowMs) return null;
  return {
    schema: 'fluxidi-provider-approach-v1', source: 'mapbox',
    vehicle_id: row.vehicle_id, driver_id: row.driver_id,
    route_profile: candidate.route_profile,
    distance_meters: candidate.origin_travel_distance_meters,
    duration_seconds: candidate.origin_travel_seconds,
    arrival_at: row.pickup_iso, generated_at_ms: nowMs,
    valid_until_ms: candidate.route_valid_until_ms,
  };
}

export function publicBookableVehicleRows(offers) {
  return (Array.isArray(offers) ? offers : []).map((row) => {
    const preview = publicDriverPreviewFromFleet(row.driver);
    return {
      vehicle_id: row.vehicle_id,
      available: row.available === true,
      reason: row.reason || "",
      driver_id: preview.driver_id || row.driver_id || "",
      ...(preview.public_display_name
        ? { public_display_name: preview.public_display_name }
        : {}),
      ...(preview.public_photo_url ? { public_photo_url: preview.public_photo_url } : {}),
      passenger_seats: row.passenger_seats,
      ...(row.available && row.pickup_iso ? { pickup_iso: row.pickup_iso } : {}),
      ...(row.available && row.approach ? { approach: row.approach } : {}),
    };
  });
}
