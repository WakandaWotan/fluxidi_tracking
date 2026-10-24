// Customer live snapshot for one owned booking.
// Room state only. No fleet list, no GPS history, no Booking-KV reads.
import { normalizeVehicleFallbackAsset } from "../../booking/modules/vehicle_fallback_asset.mjs";
import { createBoundedRouteCache } from '../../booking/modules/scoped_route_cache.mjs';

export async function sha256Hex(text) {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(String(text || "")));
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

export const SNAPSHOT_CONTRACT_VERSION = 1;
export const GRANT_ACCESS_TTL_MS = 90_000;
export const ETA_CACHE_TTL_MS = 45_000;
export const ETA_POSITION_BUCKET_DEG = 0.002;

export const LIVE_PHASES = new Set(["en_route_pickup", "arrived_pickup", "in_progress"]);
export const TERMINAL_PHASES = new Set(["stopped", "completed", "cancelled"]);

const PUBLIC_DRIVER_FIELDS = ["display_name"];
const PUBLIC_VEHICLE_FIELDS = ["label", "color", "license_plate"];

export function trackingPhaseForStatus(status) {
  const token = String(status || "").trim().toLowerCase().replace(/[\s-]+/g, "_");
  if (!token || token === "unassigned" || token === "quoted" || token === "pending") return "unassigned";
  if (token === "assigned" || token === "accepted" || token === "confirmed") return "assigned";
  if (token === "en_route" || token === "en_route_pickup" || token === "on_the_way" || token === "driving_to_pickup") {
    return "en_route_pickup";
  }
  if (token === "arrived_pickup") return "arrived_pickup";
  if (token === "started" || token === "in_progress" || token === "on_trip" || token === "picked_up" || token === "driving") {
    return "in_progress";
  }
  if (token === "stopped" || token === "stop") return "stopped";
  if (token === "completed" || token === "complete") return "completed";
  if (["cancelled", "canceled", "no_show", "rejected", "expired"].includes(token)) return "cancelled";
  return "assigned";
}

export function etaTargetForPhase(phase) {
  if (phase === "en_route_pickup") return "pickup";
  if (phase === "in_progress") return "destination";
  return null;
}

export function publicDriver(input) {
  const source = input && typeof input === "object" ? input : {};
  const out = {};
  for (const key of PUBLIC_DRIVER_FIELDS) {
    const value = source[key] ?? source.public_driver?.[key];
    if (value) out[key] = String(value).slice(0, 80);
  }
  const photo = publicPhotoUrl(source.photo_url ?? source.public_photo_url ?? source.public_driver?.photo_url);
  if (photo) out.photo_url = photo;
  // Separate explicit customer capability. Raw internal phone is never a fallback.
  const contact = source.customer_contact;
  if (contact?.customer_allowed === true && /^\+[1-9][0-9]{6,14}$/.test(String(contact.phone_e164 || "")) &&
      (contact.call_allowed === true || contact.whatsapp_allowed === true)) {
    out.customer_contact = {customer_allowed:true,phone_e164:contact.phone_e164,
      call_allowed:contact.call_allowed === true,whatsapp_allowed:contact.whatsapp_allowed === true};
  }
  const average = Number(source.rating_average), count = Number(source.rating_count);
  if (Number.isFinite(average) && average > 0 && average <= 5 && Number.isInteger(count) && count > 0) {
    out.rating_average = average; out.rating_count = count;
  }
  return out;
}

function publicPhotoUrl(value) {
  try {
    const url = new URL(String(value ?? ""));
    return url.protocol === "https:" && !url.username && !url.password && url.href.length <= 2048 ? url.href : "";
  } catch { return ""; }
}

export function publicVehicle(input) {
  const source = input && typeof input === "object" ? input : {};
  const assigned = source.assigned_vehicle || source.vehicle || source;
  const out = {};
  for (const key of PUBLIC_VEHICLE_FIELDS) {
    const value = assigned[key] ?? assigned[`vehicle_${key}`];
    if (value) out[key] = String(value).slice(0, 80);
  }
  const vehicleId = text(assigned.vehicle_id ?? assigned.vehicleId, 96);
  if (vehicleId) out.vehicle_id = vehicleId;
  const fallbackAsset = normalizeVehicleFallbackAsset(assigned.fallback_asset ?? assigned.fallbackAsset);
  if (fallbackAsset) out.fallback_asset = fallbackAsset;
  const photo = publicPhotoUrl(assigned.photo_url ?? assigned.public_photo_url);
  if (photo) out.photo_url = photo;
  return out;
}

// Public route metadata never includes the actor, update id or dispatch state.
export function publicOperationalRoute(value) {
  const address = value?.destination_address ?? value?.destination?.address;
  const end = value?.expected_end_iso, updated = value?.updated_at;
  if (typeof address !== 'string' || !address.trim() || address.length > 400
    || typeof end !== 'string' || !Number.isFinite(Date.parse(end))) return null;
  return { destination_address: address.trim(), expected_end_iso: new Date(end).toISOString(),
    ...(typeof updated === 'string' && Number.isFinite(Date.parse(updated)) ? { updated_at: new Date(updated).toISOString() } : {}) };
}

function text(value, max) {
  const raw = String(value ?? "").trim();
  return raw ? raw.slice(0, max) : "";
}

export function grantKey(bookingId, leg) {
  return `${text(bookingId, 96)}|${text(leg, 200) || "primary"}`;
}

export function emptyGrantStore() {
  return { grants: {} };
}

export function applyCustomerLifecycle(store, event, nowMs) {
  const result = applyScopedCustomerLifecycle(store, event, nowMs);
  if (result.applied && event?.disable_primary === true && result.grant && TERMINAL_PHASES.has(result.grant.tracking_phase)) {
    const grant = result.grant;
    grant.revoked_token_hashes = [...new Set([...(grant.revoked_token_hashes || []), ...(grant.access_token_hashes || []), grant.access_token_hash].filter(Boolean))];
    grant.access_token_hash = "";
    grant.access_token_hashes = [];
  }
  // A concrete multi-leg scope permanently retires the legacy parent alias.
  // This is atomic with an accepted booking event, never a second lifecycle clock.
  if (result.applied && event?.disable_primary === true && event.operational_leg && event.operational_leg !== "primary") {
    const key = grantKey(event.booking_id, "primary");
    const old = result.store.grants[key];
    result.store.grants[key] = { ...old, leg_scope_retired: true, position_allowed: false,
      access_token_hash: "", access_token_hashes: [], tracking_phase: "stopped" };
  }
  return result;
}
function applyScopedCustomerLifecycle(store, event, nowMs) {
  const next = { grants: { ...(store?.grants || {}) } };
  const bookingId = text(event?.booking_id, 96);
  const tenantId = text(event?.tenant_id, 80);
  const companyId = text(event?.company_id, 80);
  if (!bookingId || !tenantId || !companyId) {
    return { store: next, applied: false, reason: "identity_missing" };
  }
  const leg = text(event?.operational_leg, 200) || "primary";
  const key = grantKey(bookingId, leg);
  const current = next.grants[key] || null;
  if (current?.leg_scope_retired) return { store: next, applied: false, confirmed: false, reason: "leg_scope_retired", grant: current };
  const seq = Number(event?.lifecycle_seq);
  if (!Number.isFinite(seq)) {
    return { store: next, applied: false, reason: "lifecycle_seq_required" };
  }
  const kind = text(event?.kind, 20) || "lifecycle";
  const phase = trackingPhaseForStatus(event?.tracking_phase || event?.booking_status);
  const assignmentVersion = Number(event?.assignment_version);
  const tokenHash = text(event?.access_token_hash, 128);
  if (event?.sync_ok === false) {
    return {
      store: next,
      applied: false,
      confirmed: false,
      reason: "sync_report_ignored",
      grant: current,
    };
  }
  // STOP closes a bound session inside the current booking revision. Only the
  // booking worker advances lifecycle_seq; a wall clock is never a revision.
  if (kind === "session_start" || kind === "session_stop") {
    const sessionId = text(event?.session_id, 128);
    const matches = current && current.tenant_id === tenantId && current.company_id === companyId &&
      assignmentVersion > 0 && assignmentVersion === current.assignment_version &&
      text(event?.driver_id, 96) === current.driver_id && sessionId;
    if (!matches || (kind === "session_start" && seq !== current.lifecycle_seq) ||
        (kind === "session_stop" && sessionId !== current.session_id)) {
      return { store: next, applied: false, confirmed: false, reason: "session_assignment_mismatch", grant: current };
    }
    if (TERMINAL_PHASES.has(current.tracking_phase)) {
      return { store: next, applied: false, confirmed: kind === "session_stop", reason: "session_already_closed", grant: current };
    }
    const grant = { ...current, session_id: sessionId, updated_at: new Date(nowMs).toISOString() };
    if (kind === "session_stop") {
      grant.tracking_phase = "stopped";
      grant.position_allowed = false;
      grant.revoked_token_hashes = [...new Set([
        ...(current.revoked_token_hashes || []), ...(current.access_token_hashes || []), current.access_token_hash,
      ].filter(Boolean))];
    }
    next.grants[key] = grant;
    return { store: next, applied: true, confirmed: true, reason: kind, grant };
  }
  if (current && Number.isFinite(assignmentVersion) && assignmentVersion < current.assignment_version) {
    return { store: next, applied: false, confirmed: false, reason: "stale_assignment_version", grant: current };
  }
  // A later metadata/lifecycle number cannot reopen a physically closed
  // assignment. Completion/cancellation and a newer confirmed assignment remain
  // valid booking events; STOP, COMPLETED and CANCELLED all close GPS access.
  if (current && TERMINAL_PHASES.has(current.tracking_phase) &&
      !(assignmentVersion > current.assignment_version) && !TERMINAL_PHASES.has(phase)) {
    return { store: next, applied: false, confirmed: false, reason: "session_closed", grant: current };
  }
  if (current && seq < current.lifecycle_seq) {
    return { store: next, applied: false, confirmed: false, reason: "stale_lifecycle_seq", grant: current };
  }
  // A historical booking may become observably terminal without advancing its
  // cached tracking revision. Within the SAME assignment/revision, canonical
  // terminal facts dominate a stale live phase. Older events remain rejected.
  const terminalCorrection = current && assignmentVersion === current.assignment_version &&
    seq === current.lifecycle_seq && ["completed", "cancelled"].includes(phase) &&
    trackingPhaseForStatus(event.booking_status) === phase &&
    !TERMINAL_PHASES.has(current.tracking_phase);
  if (current && seq === current.lifecycle_seq && kind === "lifecycle" && !terminalCorrection) {
    return { store: next, applied: false, confirmed: true, reason: "duplicate_lifecycle_seq", grant: current };
  }
  if (current && seq === current.lifecycle_seq && !terminalCorrection && (kind === "renew" || kind === "issue")) {
    const versionOk = !Number.isFinite(assignmentVersion) || assignmentVersion === current.assignment_version;
    const phaseOk = phase === current.tracking_phase;
    if (!versionOk || !phaseOk) {
      return { store: next, applied: false, confirmed: false, reason: "renew_mismatch", grant: current };
    }
    const hashes = Array.isArray(current.access_token_hashes) ? [...current.access_token_hashes] : [];
    if (current.access_token_hash && !hashes.includes(current.access_token_hash)) hashes.push(current.access_token_hash);
    const grant = {
      ...current,
      // Metadata only: refresh the confirmed assignment, never a prior label.
      ...(assignmentVersion === current.assignment_version &&
          text(event?.driver_id, 96) === current.driver_id ? {
        driver: publicDriver(event?.driver),
        vehicle: publicVehicle(event?.assigned_vehicle || event?.vehicle),
      } : {}),
      access_until_ms: TERMINAL_PHASES.has(current.tracking_phase) ? current.access_until_ms : nowMs + GRANT_ACCESS_TTL_MS,
      updated_at: new Date(nowMs).toISOString(),
    };
    if (kind === "issue" && tokenHash && !TERMINAL_PHASES.has(current.tracking_phase) && !(grant.revoked_token_hashes || []).includes(tokenHash)) {
      if (!hashes.includes(tokenHash)) hashes.push(tokenHash);
      grant.access_token_hash = tokenHash;
      grant.access_token_hashes = hashes;
    }
    next.grants[key] = grant;
    return { store: next, applied: true, confirmed: true, reason: kind, grant };
  }
  const reassigned =
    current &&
    Number.isFinite(assignmentVersion) &&
    assignmentVersion !== current.assignment_version;
  const grant = {
    contract_version: SNAPSHOT_CONTRACT_VERSION,
    tenant_id: tenantId,
    company_id: companyId,
    booking_id: bookingId,
    operational_leg: leg,
    customer_id: text(event?.customer_id, 96) || current?.customer_id || "",
    assignment_version: Number.isFinite(assignmentVersion) ? assignmentVersion : current?.assignment_version || 0,
    tracking_phase: phase,
    booking_status: text(event?.booking_status, 40),
    session_id: text(event?.session_id, 128) || (reassigned ? "" : current?.session_id || ""),
    driver_id: text(event?.driver_id, 96),
    access_token_hash: tokenHash || (reassigned ? "" : current?.access_token_hash || ""),
    access_token_hashes: tokenHash ? [tokenHash] : (reassigned ? [] : [...(current?.access_token_hashes || [])]),
    revoked_token_hashes: reassigned
      ? [...new Set([...(current?.revoked_token_hashes || []), ...(current?.access_token_hashes || []), current?.access_token_hash].filter(Boolean))]
      : [...(current?.revoked_token_hashes || [])],
    driver: publicDriver(event?.driver),
    vehicle: publicVehicle(event?.assigned_vehicle || event?.vehicle),
    pickup: pointOrNull(event?.pickup),
    destination: pointOrNull(event?.destination),
    operational_route: phase === "in_progress" ? publicOperationalRoute(event?.operational_route) : null,
    position_allowed: LIVE_PHASES.has(phase),
    sync_state: "ok",
    lifecycle_seq: seq,
    access_until_ms: nowMs + GRANT_ACCESS_TTL_MS,
    updated_at: new Date(nowMs).toISOString(),
  };
  if (event?.revoke_access_token_hash) {
    grant.revoked_token_hashes = [...new Set([...grant.revoked_token_hashes, text(event.revoke_access_token_hash, 128)])];
    if (grant.access_token_hash === text(event.revoke_access_token_hash, 128)) grant.access_token_hash = "";
  }
  next.grants[key] = grant;
  return { store: next, applied: true, confirmed: true, reason: reassigned ? "reassigned" : "applied", grant };
}

function pointOrNull(value) {
  const latitude = Number(value?.latitude ?? value?.lat);
  const longitude = Number(value?.longitude ?? value?.lon ?? value?.lng);
  if (!Number.isFinite(latitude) || !Number.isFinite(longitude)) return null;
  return { latitude, longitude };
}

export function customerAccessAllowed(grant, query) {
  if (!grant || grant.leg_scope_retired) return { ok: false, error: "not_found", status: 404 };
  if (text(query?.tenant_id, 80) !== grant.tenant_id) return { ok: false, error: "not_found", status: 404 };
  if (text(query?.company_id, 80) !== grant.company_id) return { ok: false, error: "not_found", status: 404 };
  if (text(query?.booking_id, 96) !== grant.booking_id) return { ok: false, error: "not_found", status: 404 };
  const leg = text(query?.operational_leg, 200) || "primary";
  if (leg !== grant.operational_leg) return { ok: false, error: "not_found", status: 404 };
  if (text(query?.customer_id, 96) && text(query.customer_id, 96) !== grant.customer_id) {
    return { ok: false, error: "not_found", status: 404 };
  }
  const token = text(query?.access_token_hash, 128);
  const hashes = Array.isArray(grant.access_token_hashes) ? grant.access_token_hashes : [];
  // A known revoked token can identify a superseded assignment, but never
  // authorize its replacement. The customer must use owner bootstrap again.
  const previousVersion = Number(text(query?.assignment_version, 20));
  if (token && (grant.revoked_token_hashes || []).includes(token) &&
      Number.isInteger(previousVersion) && previousVersion > 0 && previousVersion < grant.assignment_version &&
      !TERMINAL_PHASES.has(grant.tracking_phase)) {
    return { ok: false, error: "assignment_changed", status: 409 };
  }
  if (!token || (token !== grant.access_token_hash && !hashes.includes(token))) {
    return { ok: false, error: "not_found", status: 404 };
  }
  if ((grant.revoked_token_hashes || []).includes(token)) return { ok: false, error: "not_found", status: 404 };
  const askedVersionRaw = text(query?.assignment_version, 20);
  const askedVersion = askedVersionRaw ? Number(askedVersionRaw) : NaN;
  if (Number.isFinite(askedVersion) && askedVersion !== grant.assignment_version) {
    return { ok: false, error: "not_found", status: 404 };
  }
  const askedSession = text(query?.session_id, 128);
  if (askedSession && grant.session_id && askedSession !== grant.session_id) {
    return { ok: false, error: "not_found", status: 404 };
  }
  return { ok: true };
}

export function projectCustomerSnapshot({ grant, driver, nowMs, eta, route }) {
  const phase = grant?.tracking_phase || "unassigned";
  const expired = !grant || !Number.isFinite(grant.access_until_ms) || nowMs > grant.access_until_ms;
  const syncClosed = grant?.sync_state === "failed";
  const terminal = TERMINAL_PHASES.has(phase) || expired || syncClosed || grant?.position_allowed !== true;
  const sameDriver = driver && grant?.driver_id && driver.driver_id === grant.driver_id;
  const fresh = sameDriver && driver.position_stale !== true && driver.reliable_for_eta !== false;
  const position = !terminal && fresh
    ? {
        latitude: driver.latitude,
        longitude: driver.longitude,
        heading: driver.heading ?? null,
        captured_at: driver.position_captured_at || driver.captured_at || null,
        accuracy: driver.accuracy ?? null,
      }
    : null;
  const feed = !driver || !sameDriver
    ? "missing"
    : driver.position_stale
      ? "stale"
      : driver.location_feed || "live";
  const target = etaTargetForPhase(phase);
  const etaOut = !terminal && target && eta && eta.target === target
    ? {
        target,
        source: eta.source || "mapbox/driving-traffic",
        duration_seconds: eta.duration_seconds,
        valid_until: eta.valid_until,
        distance_meters: eta.distance_meters ?? null,
      }
    : null;
  return {
    ok: true,
    contract_version: SNAPSHOT_CONTRACT_VERSION,
    tenant_id: grant.tenant_id,
    company_id: grant.company_id,
    booking_id: grant.booking_id,
    operational_leg: grant.operational_leg,
    assignment_version: grant.assignment_version,
    response_version: grant.lifecycle_seq,
    booking_status: grant.booking_status || phase,
    tracking_phase: terminal && expired && LIVE_PHASES.has(phase) ? "expired" : phase,
    position,
    pickup: terminal ? null : grant.pickup ?? null,
    destination: terminal ? null : grant.destination ?? null,
    operational_route: !terminal && phase === "in_progress" ? publicOperationalRoute(grant.operational_route) : null,
    feed: {
      health: terminal ? "closed" : feed,
      position_captured_at: sameDriver ? driver.position_captured_at || driver.captured_at || null : null,
      last_seen_at: sameDriver ? driver.last_seen_at || null : null,
    },
    eta: etaOut,
    route: !terminal && phase !== "arrived_pickup" && route ? route : null,
    driver: terminal ? null : grant.driver,
    vehicle: terminal ? null : grant.vehicle,
    refresh: {
      poll_after_seconds: terminal ? 0 : 10,
      access_until: grant.access_until_ms ? new Date(grant.access_until_ms).toISOString() : null,
    },
  };
}

export function publicLiveMayExposePosition(session, grant, { requireGrant = false } = {}) {
  const status = String(session?.status || "").toLowerCase();
  if (status === "stopped" || status === "completed" || status === "cancelled" || status === "canceled") {
    return false;
  }
  if (!grant) return requireGrant ? false : true;
  if (TERMINAL_PHASES.has(grant.tracking_phase) || grant.position_allowed !== true || grant.sync_state === "failed") {
    return false;
  }
  if (Number.isFinite(grant.access_until_ms) && Date.now() > grant.access_until_ms) return false;
  if (grant.session_id && session?.session_id && grant.session_id !== session.session_id) return false;
  return true;
}

export function positionBucket(latitude, longitude) {
  const lat = Math.round(Number(latitude) / ETA_POSITION_BUCKET_DEG) * ETA_POSITION_BUCKET_DEG;
  const lon = Math.round(Number(longitude) / ETA_POSITION_BUCKET_DEG) * ETA_POSITION_BUCKET_DEG;
  return `${lat.toFixed(3)},${lon.toFixed(3)}`;
}

export function createEtaCache(fetcher, now = () => Date.now(), { maxEntries = 512, maxInflight = 128 } = {}) {
  const bounded = createBoundedRouteCache({ ttlMs: ETA_CACHE_TTL_MS, maxEntries, maxInflight, now });
  const { cache, inflight } = bounded;
  return {
    cache,
    inflight,
    async resolve({ origin, destination, target, context = {}, observability }) {
      if (!origin || !destination || !target) return null;
      const key = JSON.stringify([context.tenant_id,context.company_id,context.booking_id,
        context.operational_leg,context.session_id,context.assignment_version,context.lifecycle_seq,
        'mapbox/driving-traffic','geometry=simplified',target,
        positionBucket(origin.latitude, origin.longitude),destination.latitude,destination.longitude]);
      const result = await bounded.resolve(key, async () => {
          const value = await fetcher({ origin, destination, target, observability });
          if (!value || !Number.isFinite(value.duration_seconds) || value.duration_seconds < 0) throw Error('customer_eta_invalid');
          const stored = {
            target,
            source: "mapbox/driving-traffic",
            duration_seconds: value.duration_seconds,
            distance_meters: value.distance_meters ?? null,
            route: value.route ?? null,
            valid_until: new Date(now() + ETA_CACHE_TTL_MS).toISOString(),
          };
          return stored;
      });
      return { ...result.value, cache: result.cache === 'bypass' ? 'miss' : result.cache };
    },
  };
}
