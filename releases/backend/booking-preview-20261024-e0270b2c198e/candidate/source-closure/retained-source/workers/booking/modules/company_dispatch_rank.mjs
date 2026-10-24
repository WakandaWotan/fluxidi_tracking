// Proposal ranking only. Does not assign a booking.
// The customer pickup is the reference. Lowest feasible drive time to that
// point wins. Straight-line distance is never the score.

import {
  ASSIGNMENT_SAFETY_MARGIN_MIN,
  evaluateDriverEligibility,
  resolveDispatchOperationalBufferMin,
  rideIsSoon,
} from "./company_dispatch.mjs";
import { companyTrackingObjectName } from "../../tracking/modules/company_tracking_room.mjs";
import { vehicleFitsServiceCapacity } from "./vehicle_service_capacity.mjs";
import { freshDispatchPosition } from '../../tracking/modules/company_dispatch_offers.mjs';
import { plannerRouteKey } from './scoped_route_cache.mjs';
import { indexDispatchVehicles } from './dispatch_prefilter.mjs';

export const DISPATCH_MAPBOX_CAP = 8;
export const DISPATCH_ETA_CACHE_MS = 30_000;

export async function readCompanyHotState(namespace, tenantId, companyId, freshnessSeconds) {
  if (!namespace || typeof namespace.idFromName !== "function" || typeof namespace.get !== "function") {
    return { ok: false, requests: 0, liveByDriver: {} };
  }
  const stub = namespace.get(namespace.idFromName(companyTrackingObjectName(tenantId, companyId)));
  const url = new URL("https://company-tracking.internal/live");
  url.searchParams.set("tenant_id", String(tenantId || ""));
  url.searchParams.set("company_id", String(companyId || ""));
  if (freshnessSeconds != null && String(freshnessSeconds).trim() !== "") {
    url.searchParams.set("freshness_seconds", String(freshnessSeconds));
  }
  const response = await stub.fetch(url.toString(), { method: "GET" });
  const body = await response.json();
  if (!response.ok || body?.ok !== true || body.tenant_id !== tenantId || body.company_id !== companyId
    || !Array.isArray(body.drivers)) throw new Error('company_live_scope_unconfirmed');
  const liveByDriver = {};
  for (const row of body?.drivers || []) {
    if (!row?.driver_id || row.company_id !== companyId || row.tenant_id !== tenantId) continue;
    liveByDriver[row.driver_id] = {
      driver_id: row.driver_id,
      tenant_id: row.tenant_id,
      company_id: row.company_id,
      vehicle_id: row.vehicle_id || null,
      latitude: row.latitude,
      longitude: row.longitude,
      position_captured_at: row.position_captured_at || row.captured_at || null,
      last_seen_at: row.last_seen_at || null,
      location_feed: row.location_feed || (row.stale ? "stale" : "live"),
      reliable_for_eta: row.reliable_for_eta === true,
    };
  }
  return { ok: true, requests: 1, liveByDriver, activeDirectRides: (body?.active_direct_rides || [])
    .filter(ride => ride.tenant_id === tenantId && ride.company_id === companyId) };
}

export function dispatchScoreV1(candidate) {
  const raw = candidate?.arrival_seconds ?? candidate?.eta_seconds;
  const eta = raw == null || String(raw).trim() === '' ? NaN : Number(raw);
  return {
    eta_seconds: Number.isFinite(eta) ? eta : Number.POSITIVE_INFINITY,
    tie: String(candidate?.driver_id || ""),
  };
}

function num(value) {
  if (value == null || String(value).trim() === '') return null;
  const n = Number(value);
  return Number.isFinite(n) ? n : null;
}

function point(raw) {
  if (!raw) return null;
  const latitude = num(raw.latitude ?? raw.lat);
  const longitude = num(raw.longitude ?? raw.lng ?? raw.lon);
  if (latitude === null || longitude === null || Math.abs(latitude) > 90 || Math.abs(longitude) > 180
    || latitude === 0 && longitude === 0) return null;
  return { latitude, longitude };
}

function cacheKey(origin, pickup, departAt) {
  const r = (n) => Number(n).toFixed(4);
  const depart = departAt ? String(departAt) : "";
  return `${r(origin.latitude)},${r(origin.longitude)}>${r(pickup.latitude)},${r(pickup.longitude)}@${depart}`;
}

function liveRow(liveByDriver, driverId) {
  const row = liveByDriver?.[driverId];
  return row && typeof row === "object" ? row : null;
}

function originForCandidate({ timing, live, activeRide, expectedPosition, nowMs }) {
  if (activeRide && !freshDispatchPosition(live, nowMs)) return { ok: false, reason: 'location_feed_stale' };
  if (activeRide && !(Date.parse(activeRide.ends_at || '') >= nowMs)) return { ok: false, reason: 'insufficient_eta_data' };
  if (timing === "now") {
    if (activeRide?.end) {
      const end = point(activeRide.end);
      if (!end || !Number.isFinite(Date.parse(activeRide.ends_at || ''))) return { ok: false, reason: "insufficient_eta_data" };
      return { ok: true, position: end, source: "active_ride_end", ready_at: activeRide.ends_at || null };
    }
    if (live?.reliable_for_eta === true && live?.location_feed !== "stale") {
      const position = point(live);
      if (!position) return { ok: false, reason: "insufficient_eta_data" };
      return { ok: true, position, source: "live", ready_at: null };
    }
    return { ok: false, reason: live ? "location_feed_stale" : "location_missing" };
  }
  if (activeRide?.end) {
    const end = point(activeRide.end);
    const depart = activeRide.ends_at || null;
    if (!end || !depart) return { ok: false, reason: "insufficient_eta_data" };
    return { ok: true, position: end, source: "active_ride_end", ready_at: depart };
  }
  const expected = point(expectedPosition);
  const depart = expectedPosition?.at || null;
  if (!expected || !depart) return { ok: false, reason: "insufficient_eta_data" };
  return { ok: true, position: expected, source: "expected_position", ready_at: depart };
}

function vehicleOf(driver, vehicles) {
  const id = String(driver?.assigned_vehicle_id || driver?.vehicle_ids?.[0] || "");
  return vehicles.get(id) || null;
}

export async function proposeDispatchRanking({
  tenantId,
  companyId,
  drivers,
  vehicles,
  liveByDriver,
  pickup,
  nowMs,
  durationMin,
  passengers,
  baggage,
  service,
  presenceByDriver,
  overlapByDriver,
  activeRideByDriver,
  expectedPositionByDriver,
  nextRideByDriver,
  dropoff,
  routeEta,
  etaCache,
  routeCache,
  onRouteCache,
  doReads = 0,
  operationalBufferMin,
} = {}) {
  const stats = {
    candidates_before: Array.isArray(drivers) ? drivers.length : 0,
    candidates_after_filter: 0,
    mapbox_calls: 0,
    mapbox_cache_hits: 0,
    mapbox_cache_misses: 0,
    do_reads: doReads,
    kv_gps_reads: 0,
    kv_gps_writes: 0,
  };
  const pickupPoint = point(pickup);
  const pickupMs = Date.parse(String(pickup?.at || ""));
  const atMs = Number(nowMs);
  const timing = rideIsSoon(pickup?.at, atMs) ? "now" : "future";
  const trafficBufferSec = resolveDispatchOperationalBufferMin(operationalBufferMin) * 60;
  const fallbackBufferSec = ASSIGNMENT_SAFETY_MARGIN_MIN * 60;
  const cache = etaCache instanceof Map ? etaCache : new Map();
  const excluded = [];
  const eligible = [];
  const vehicleIndex = indexDispatchVehicles(vehicles);

  for (const driver of drivers || []) {
    const driverId = String(driver?.driver_id || "");
    if (!driverId) continue;
    if (String(driver.company_id || companyId) !== String(companyId)) {
      excluded.push(baseRow(driver, { eligible: false, exclusion_reason: "other_company" }));
      continue;
    }
    if (activeRideByDriver?.[driverId] && !freshDispatchPosition(liveRow(liveByDriver, driverId), atMs)) {
      excluded.push(baseRow(driver, { eligible: false, exclusion_reason: 'location_feed_stale' }));
      continue;
    }
    const evaluation = evaluateDriverEligibility({
      driver,
      presence: presenceByDriver?.[driverId] || {},
      vehicles,
      drivers,
      atMs,
      pickupIso: pickup?.at,
      durationMin,
      overlap: overlapByDriver?.[driverId],
    });
    const currentRide = activeRideByDriver?.[driverId];
    const canEvaluateRideEnd = point(currentRide?.end)
      && Number.isFinite(Date.parse(String(currentRide?.ends_at || "")))
      && Date.parse(String(currentRide.ends_at)) >= atMs;
    // Being on a known ride is not itself a conflict with a later pickup.
    // Retain roster, presence, overlap and all other eligibility checks.
    const reasons = evaluation.reasons.filter(reason =>
      !(reason === "assignment_driver_on_trip" && canEvaluateRideEnd));
    if (reasons.length) {
      excluded.push(baseRow(driver, {
        eligible: false,
        exclusion_reason: reasons[0] || "not_eligible",
        vehicle_id: evaluation.linked_vehicle_ids?.[0] || "",
      }));
      continue;
    }
    const vehicle = vehicleOf(driver, vehicleIndex);
    const vehicleId = String(vehicle?.vehicle_id || evaluation.linked_vehicle_ids?.[0] || "");
    const seats = num(vehicle?.passenger_capacity);
    const overLegacySeats = passengers != null && seats != null && Number(passengers) > seats
      && vehicle?.service_capacity == null && vehicle?.serviceCapacity == null;
    if (
      overLegacySeats
      || (vehicle && !vehicleFitsServiceCapacity(vehicle, { service, passengers, baggage }))
    ) {
      excluded.push(baseRow(driver, { eligible: false, exclusion_reason: "assignment_vehicle_capacity", vehicle_id: vehicleId }));
      continue;
    }
    if (vehicle && (vehicle.is_active === false || vehicle.active === false)) {
      excluded.push(baseRow(driver, { eligible: false, exclusion_reason: "assignment_vehicle_unavailable", vehicle_id: vehicleId }));
      continue;
    }
    const nextRide = nextRideByDriver?.[driverId];
    if (nextRide && !point(nextRide.pickup)) {
      eligible.push({
        driver,
        driverId,
        vehicleId,
        live: liveRow(liveByDriver, driverId),
        hold: "insufficient_eta_data",
      });
      continue;
    }
    const overlap = overlapByDriver?.[driverId];
    eligible.push({
      driver,
      driverId,
      vehicleId,
      live: liveRow(liveByDriver, driverId),
      nextRide,
      marginConflict: overlap?.margin_conflict === true,
    });
  }
  stats.candidates_after_filter = eligible.length;
  // Cache hits keep the original candidate/leg evaluation budget.
  let sharedRouteQueries = 0;
  const routeBudgetUsed = () => routeCache && tenantId ? sharedRouteQueries : stats.mapbox_calls;

  const sharedRoute = async (args, target) => {
    sharedRouteQueries++;
    const context = { operation: target === 'next_leg' ? 'next_leg' : 'planner',
      source: 'planner', eligible_candidates: eligible.length };
    const key = plannerRouteKey({ tenantId, companyId,
      origin: args.origin, destination: args.destination, departAt: args.depart_at, target });
    const exactQuery = JSON.stringify([key,args.origin.latitude,args.origin.longitude,args.destination.latitude,args.destination.longitude,args.depart_at || null]);
    const result = await routeCache.resolve(key, async () => {
      stats.mapbox_cache_misses++;
      stats.mapbox_calls++;
      return routeEta({ ...args, observability: context });
    }, exactQuery);
    if (result.cache === 'hit' || result.cache === 'joined') {
      stats.mapbox_cache_hits++;
      try { await onRouteCache?.(context,result.cache); } catch { /* diagnostics only */ }
    }
    return result.value;
  };

  const ranked = [];
  const fallback = [];
  for (const row of eligible) {
    const origin = originForCandidate({
      timing,
      live: row.live,
      activeRide: activeRideByDriver?.[row.driverId],
      expectedPosition: expectedPositionByDriver?.[row.driverId],
      nowMs: atMs,
    });
    if (!origin.ok) {
      const held = scheduleHold(row, fallbackBufferSec, { fallback_reason: origin.reason, location_feed: row.live?.location_feed || "stale" });
      if (held.excluded) {
        excluded.push(held.row);
        stats.candidates_after_filter -= 1;
      } else {
        fallback.push(held.row);
      }
      continue;
    }
    if (!pickupPoint) {
      fallback.push(proposal(row, {
        dispatch_mode: "schedule_fallback",
        eta_seconds: null,
        fallback_reason: "pickup_missing",
        reliable_for_eta: false,
        location_feed: row.live?.location_feed || "missing",
      }));
      continue;
    }
    if (routeBudgetUsed() >= DISPATCH_MAPBOX_CAP) {
      fallback.push(proposal(row, {
        dispatch_mode: "schedule_fallback",
        eta_seconds: null,
        fallback_reason: "mapbox_budget",
        reliable_for_eta: false,
        location_feed: row.live?.location_feed || "live",
      }));
      continue;
    }
    const departAt = origin.ready_at || null;
    const key = cacheKey(origin.position, pickupPoint, departAt);
    const hit = cache.get(key);
    let route;
    if (routeCache && tenantId) {
      try { route = await sharedRoute({ origin: origin.position, destination: pickupPoint, depart_at: departAt }, 'pickup'); }
      catch { route = null; }
    } else if (hit && atMs - hit.at <= DISPATCH_ETA_CACHE_MS) {
      stats.mapbox_cache_hits += 1;
      route = hit.route;
    } else {
      stats.mapbox_cache_misses += 1;
      stats.mapbox_calls += 1;
      try {
        route = await routeEta({
          origin: origin.position,
          destination: pickupPoint,
          depart_at: departAt,
          observability: { operation: 'planner', source: 'planner', eligible_candidates: eligible.length },
        });
      } catch {
        route = null;
      }
      if (route) cache.set(key, { at: atMs, route });
    }
    if (!route || !Number.isFinite(Number(route.duration_seconds))) {
      const held = scheduleHold(row, fallbackBufferSec, {
        fallback_reason: "mapbox_failed",
        location_feed: row.live?.location_feed || "live",
      });
      if (held.excluded) {
        excluded.push(held.row);
        stats.candidates_after_filter -= 1;
      } else {
        fallback.push(held.row);
      }
      continue;
    }
    const eta = Number(route.duration_seconds);
    const readyMs = Date.parse(String(origin.ready_at || ""));
    const hasDeparture = Number.isFinite(readyMs);
    const pickupBufferMs = hasDeparture ? trafficBufferSec * 1000 : 0;
    const arriveMs = Math.max(atMs, hasDeparture ? readyMs : atMs) + eta * 1000 + pickupBufferMs;
    // A scheduled pickup has a deadline even when departing from a live fix.
    // An immediate request (pickup <= now) instead asks for the earliest ETA.
    if (pickupMs > atMs && Number.isFinite(pickupMs) && arriveMs > pickupMs) {
      excluded.push(baseRow(row.driver, {
        eligible: false,
        exclusion_reason: "assignment_pickup_unreachable",
        vehicle_id: row.vehicleId,
        feasibility_mode: "traffic_eta",
        operation_buffer_seconds: trafficBufferSec,
        previous_to_pickup_eta_seconds: eta,
        new_dropoff_to_next_eta_seconds: null,
      }));
      stats.candidates_after_filter -= 1;
      continue;
    }
    const next = row.nextRide;
    let nextEta = null;
    if (next && point(next.pickup) && point(dropoff)) {
      const rideEnd = Math.max(Number.isFinite(pickupMs) ? pickupMs : atMs, arriveMs) + (Number(durationMin) || 0) * 60000;
      const nextAt = Date.parse(String(next.at || ""));
      let leg = null;
      if (routeBudgetUsed() < DISPATCH_MAPBOX_CAP) {
        try {
          const args = {
            origin: point(dropoff),
            destination: point(next.pickup),
            depart_at: new Date(rideEnd).toISOString(),
            observability: { operation: 'next_leg', source: 'planner', eligible_candidates: eligible.length },
          };
          if (routeCache && tenantId) leg = await sharedRoute(args, 'next_leg');
          else { stats.mapbox_calls += 1; leg = await routeEta(args); }
        } catch {
          leg = null;
        }
      }
      const legSeconds = Number(leg?.duration_seconds);
      if (!Number.isFinite(legSeconds) || !Number.isFinite(nextAt)) {
        if (Number.isFinite(nextAt) && rideEnd + fallbackBufferSec * 1000 > nextAt) {
          excluded.push(baseRow(row.driver, {
            eligible: false,
            exclusion_reason: "assignment_next_ride_unreachable",
            vehicle_id: row.vehicleId,
            feasibility_mode: "schedule_fallback",
            operation_buffer_seconds: fallbackBufferSec,
            previous_to_pickup_eta_seconds: eta,
            new_dropoff_to_next_eta_seconds: null,
          }));
          stats.candidates_after_filter -= 1;
          continue;
        }
        fallback.push(proposal(row, {
          dispatch_mode: "schedule_fallback",
          eta_seconds: null,
          fallback_reason: "insufficient_eta_data",
          reliable_for_eta: false,
          location_feed: row.live?.location_feed || "live",
          feasibility_mode: "schedule_fallback",
          operation_buffer_seconds: fallbackBufferSec,
          previous_to_pickup_eta_seconds: eta,
          new_dropoff_to_next_eta_seconds: null,
        }));
        continue;
      }
      nextEta = legSeconds;
      if (rideEnd + trafficBufferSec * 1000 + legSeconds * 1000 > nextAt) {
        excluded.push(baseRow(row.driver, {
          eligible: false,
          exclusion_reason: "assignment_next_ride_unreachable",
          vehicle_id: row.vehicleId,
          feasibility_mode: "traffic_eta",
          operation_buffer_seconds: trafficBufferSec,
          previous_to_pickup_eta_seconds: eta,
          new_dropoff_to_next_eta_seconds: legSeconds,
        }));
        stats.candidates_after_filter -= 1;
        continue;
      }
    } else if (next && !point(dropoff)) {
      fallback.push(proposal(row, {
        dispatch_mode: "schedule_fallback",
        eta_seconds: null,
        fallback_reason: "insufficient_eta_data",
        reliable_for_eta: false,
        location_feed: row.live?.location_feed || "live",
      }));
      continue;
    }
    ranked.push(proposal(row, {
      dispatch_mode: "live_eta",
      eta_seconds: eta,
      arrival_seconds: Math.max(0, Math.ceil((arriveMs - atMs) / 1000)),
      arrival_at: new Date(arriveMs).toISOString(),
      distance_meters: Number.isFinite(Number(route.distance_meters)) ? Number(route.distance_meters) : null,
      reliable_for_eta: true,
      location_feed: row.live?.location_feed || "live",
      origin_source: origin.source,
      duration_typical_seconds: Number.isFinite(Number(route.duration_typical_seconds))
        ? Number(route.duration_typical_seconds)
        : null,
      depart_at: departAt,
      feasibility_mode: "traffic_eta",
      operation_buffer_seconds: hasDeparture || nextEta != null ? trafficBufferSec : 0,
      previous_to_pickup_eta_seconds: eta,
      new_dropoff_to_next_eta_seconds: nextEta,
    }));
  }

  ranked.sort((a, b) => {
    const left = dispatchScoreV1(a);
    const right = dispatchScoreV1(b);
    if (left.eta_seconds !== right.eta_seconds) return left.eta_seconds - right.eta_seconds;
    return left.tie.localeCompare(right.tie);
  });
  const usedVehicles = new Set();
  const proposals = [];
  for (const row of ranked) {
    if (row.vehicle_id && usedVehicles.has(row.vehicle_id)) {
      excluded.push({ ...row, eligible: false, dispatch_rank: null, dispatch_mode: "excluded", exclusion_reason: "assignment_vehicle_busy", eta_seconds: null });
      continue;
    }
    if (row.vehicle_id) usedVehicles.add(row.vehicle_id);
    proposals.push({ ...row, dispatch_rank: proposals.length + 1 });
  }
  for (let i = 0; i < proposals.length; i += 1) {
    const next = proposals[i + 1];
    proposals[i].rank_reason = next
      ? `arrival ${proposals[i].arrival_seconds}s voor ${next.driver_id} ${next.arrival_seconds}s`
      : "laagste haalbare ETA naar het ophaalpunt";
  }
  const fallbackRows = fallback
    .sort((a, b) => String(a.driver_id).localeCompare(String(b.driver_id)))
    .map((row) => ({ ...row, dispatch_rank: null }));
  return {
    ok: true,
    assigned: false,
    timing,
    company_id: companyId,
    recommended_driver_id: proposals[0]?.driver_id || null,
    proposals,
    fallback: fallbackRows,
    excluded,
    stats,
  };
}

function baseRow(driver, extra) {
  return {
    driver_id: String(driver?.driver_id || ""),
    vehicle_id: extra.vehicle_id || String(driver?.assigned_vehicle_id || ""),
    eligible: extra.eligible === true,
    dispatch_rank: null,
    eta_seconds: null,
    distance_meters: null,
    location_feed: "none",
    reliable_for_eta: false,
    dispatch_mode: extra.eligible ? "schedule_fallback" : "excluded",
    exclusion_reason: extra.exclusion_reason || "",
    fallback_reason: extra.fallback_reason || "",
    ...extra,
  };
}

function proposal(row, extra) {
  return {
    driver_id: row.driverId,
    vehicle_id: row.vehicleId,
    eligible: true,
    dispatch_rank: null,
    eta_seconds: extra.eta_seconds ?? null,
    arrival_seconds: extra.arrival_seconds ?? null,
    arrival_at: extra.arrival_at ?? null,
    distance_meters: extra.distance_meters ?? null,
    location_feed: extra.location_feed || "live",
    reliable_for_eta: extra.reliable_for_eta === true,
    dispatch_mode: extra.dispatch_mode,
    exclusion_reason: "",
    fallback_reason: extra.fallback_reason || "",
    origin_source: extra.origin_source || "",
    duration_typical_seconds: extra.duration_typical_seconds ?? null,
    depart_at: extra.depart_at || null,
    feasibility_mode: extra.feasibility_mode || "",
    operation_buffer_seconds: extra.operation_buffer_seconds ?? null,
    previous_to_pickup_eta_seconds: extra.previous_to_pickup_eta_seconds ?? null,
    new_dropoff_to_next_eta_seconds: extra.new_dropoff_to_next_eta_seconds ?? null,
    rank_reason: "",
  };
}

function scheduleHold(row, fallbackBufferSec, extra) {
  if (row.marginConflict) {
    return {
      excluded: true,
      row: baseRow(row.driver, {
        eligible: false,
        exclusion_reason: "assignment_schedule_margin",
        vehicle_id: row.vehicleId,
        feasibility_mode: "schedule_fallback",
        operation_buffer_seconds: fallbackBufferSec,
        previous_to_pickup_eta_seconds: null,
        new_dropoff_to_next_eta_seconds: null,
        fallback_reason: extra.fallback_reason || "",
      }),
    };
  }
  return {
    excluded: false,
    row: proposal(row, {
      dispatch_mode: "schedule_fallback",
      eta_seconds: null,
      reliable_for_eta: false,
      feasibility_mode: "schedule_fallback",
      operation_buffer_seconds: fallbackBufferSec,
      previous_to_pickup_eta_seconds: null,
      new_dropoff_to_next_eta_seconds: null,
      ...extra,
    }),
  };
}

function snapUp(ms, stepMs) {
  return Math.ceil(ms / stepMs) * stepMs;
}

/**
 * First pickup at which one company vehicle can reach the customer and still
 * finish the whole ride before the next commitment. Drive time comes only
 * from routeEta. A missing route, location, or drop-off is reported as missing.
 */
export async function earliestFeasiblePickup(input = {}) {
  const companyId = String(input.companyId || "");
  const nowMs = Number(input.nowMs);
  const stepMs = Math.max(60_000, (Number(input.stepMin) || 5) * 60_000);
  const horizonMs = Number.isFinite(Date.parse(String(input.horizon || "")))
    ? Date.parse(String(input.horizon))
    : nowMs + 4 * 60 * 60 * 1000;
  const notBefore = Number.isFinite(Date.parse(String(input.notBefore || "")))
    ? Date.parse(String(input.notBefore))
    : nowMs;
  if (!Number.isFinite(nowMs)) return { ok: false, missing: "clock" };
  if (!point(input.pickup)) return { ok: false, missing: "pickup", company_id: companyId };
  if (!point(input.dropoff)) return { ok: false, missing: "dropoff", company_id: companyId };
  if (typeof input.routeEta !== "function") return { ok: false, missing: "driving_time", company_id: companyId };

  const drivers = Array.isArray(input.drivers) ? input.drivers : [];
  let best = null;
  for (const driver of drivers) {
    const driverId = String(driver?.driver_id || "");
    if (!driverId || String(driver.company_id || companyId) !== companyId) continue;
    const timing = rideIsSoon(new Date(notBefore).toISOString(), nowMs) ? "now" : "future";
    const origin = originForCandidate({
      timing,
      live: liveRow(input.liveByDriver, driverId),
      activeRide: input.activeRideByDriver?.[driverId],
      expectedPosition: input.expectedPositionByDriver?.[driverId],
      nowMs,
    });
    if (!origin.ok) {
      best = best || { ok: false, missing: origin.reason, company_id: companyId, driver_id: driverId };
      continue;
    }
    let approach;
    try {
      approach = await input.routeEta({
        origin: origin.position,
        destination: point(input.pickup),
        depart_at: origin.ready_at || new Date(nowMs).toISOString(),
      });
    } catch {
      approach = null;
    }
    const approachSec = Number(approach?.duration_seconds);
    if (approach?.duration_seconds == null || !Number.isFinite(approachSec) || approachSec < 0) {
      if (!best) best = { ok: false, missing: "driving_time", company_id: companyId, driver_id: driverId };
      continue;
    }
    const bufferMs = resolveDispatchOperationalBufferMin(input.operationalBufferMin) * 60 * 1000;
    const readyMs = Number.isFinite(Date.parse(String(origin.ready_at || "")))
      ? Date.parse(String(origin.ready_at))
      : nowMs;
    let cursor = snapUp(Math.max(notBefore, readyMs + approachSec * 1000 + bufferMs), stepMs);
    const expectedPositionByDriver = {
      ...(input.expectedPositionByDriver || {}),
      [driverId]: input.expectedPositionByDriver?.[driverId] || {
        ...origin.position,
        at: origin.ready_at || new Date(readyMs).toISOString(),
      },
    };
    while (cursor <= horizonMs) {
      const ranked = await proposeDispatchRanking({
        ...input,
        drivers: [driver],
        companyId,
        nowMs,
        pickup: { ...point(input.pickup), at: new Date(cursor).toISOString() },
        dropoff: point(input.dropoff),
        expectedPositionByDriver,
      });
      const offer = ranked.proposals?.[0];
      if (offer?.driver_id) {
        const candidate = {
          ok: true,
          missing: null,
          pickup_iso: new Date(cursor).toISOString(),
          company_id: companyId,
          driver_id: offer.driver_id,
          vehicle_id: offer.vehicle_id || "",
          feasibility_mode: offer.feasibility_mode || "",
          approach_seconds: approachSec,
        };
        if (!best?.ok || Date.parse(candidate.pickup_iso) < Date.parse(best.pickup_iso)) best = candidate;
        break;
      }
      const blocked = ranked.excluded?.some((row) => row.exclusion_reason === "assignment_next_ride_unreachable"
        || row.exclusion_reason === "assignment_pickup_unreachable");
      if (!blocked) break;
      cursor += stepMs;
    }
  }
  return best || { ok: false, missing: "no_feasible_pickup", company_id: companyId };
}
