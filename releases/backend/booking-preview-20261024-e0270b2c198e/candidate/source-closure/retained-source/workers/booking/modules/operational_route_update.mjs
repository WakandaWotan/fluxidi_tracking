// Operational changes describe the running ride, never rewrite a quote or
// count a predicted end as positive completion. Called by the company writer.
import { normalizeRemainingItinerary, operationalRideBlocking as blocking, activeItineraryLeg } from './operational_itinerary.mjs';
import { unstartedCapacityExpired } from '../../tracking/modules/company_capacity_ledger.mjs';
const failed = (error, status = 400) => ({ ok: false, error, status });
const sameClaim = (left, right) => left?.claim_id === right?.claim_id
  && left.driver_id === right.driver_id && left.vehicle_id === right.vehicle_id
  && left.start_ms === right.start_ms && left.end_ms === right.end_ms && left.active === right.active;

export function buildOperationalRouteUpdate(record, bookingId, body, actor, nowMs = Date.now()) {
  if (!actor || !['driver', 'company', 'admin'].includes(actor.role)) return failed('forbidden', 403);
  if (record?.financial_evidence || record?.booking?.financial_evidence) return failed('booking_requote_required',409);
  if (!Number.isSafeInteger(body?.revision) || body.revision < 1) return failed('revision_required');
  if (typeof body.update_id !== 'string' || !/^[A-Za-z0-9_-]{1,100}$/.test(body.update_id)) return failed('operational_update_id_required');
  const destination = body.destination;
  if (!destination || typeof destination !== 'object' || Array.isArray(destination)
    || typeof destination.lat !== 'number' || !Number.isFinite(destination.lat) || Math.abs(destination.lat) > 90
    || typeof destination.lng !== 'number' || !Number.isFinite(destination.lng) || Math.abs(destination.lng) > 180
    || typeof destination.address !== 'string' || !destination.address.trim() || destination.address.length > 400) {
    return failed('operational_destination_invalid');
  }
  const endMs = typeof body.expected_end_iso === 'string' ? Date.parse(body.expected_end_iso) : NaN;
  if (!Number.isFinite(endMs)) return failed('operational_end_invalid');
  const handling = body.remaining_handling_seconds ?? 0;
  if (typeof handling !== 'number' || !Number.isFinite(handling) || handling < 0 || handling > 3600) return failed('operational_handling_invalid');
  const legs = Array.isArray(record.operational_legs) ? record.operational_legs : [];
  const split = record.roundtrip_dispatch_mode === 'split_no_wait' || record.booking?.roundtrip_dispatch_mode === 'split_no_wait';
  const requested = body.operational_leg;
  if (split && (typeof requested !== 'string' || !requested)) return failed('operational_leg_required');
  const multi = legs.length > 1;
  if(multi && !split && !activeItineraryLeg(record)) return failed('operational_ride_not_running',409);
  const target = split || multi ? (requested && requested !== bookingId
    ? legs.find(leg => requested === leg.leg_id || requested === leg.leg_type) : activeItineraryLeg(record)) : record;
  if (!target || !multi && !split && requested && requested !== bookingId) return failed('operational_leg_invalid');
  const claimId = split ? `${bookingId}:${String(target.leg_type).toUpperCase()}` : bookingId;
  const held = record.dispatch_capacity_checkpoint?.claims?.find(claim => claim.claim_id === claimId);
  if (['COMPLETED', 'CANCELLED', 'NO_SHOW', 'STOPPED'].includes(String(record.status).toUpperCase())
    || !blocking(target) || held?.active !== true || !held.driver_id || !held.vehicle_id) return failed('operational_ride_not_running', 409);
  const driver = target.assigned_driver_id || (!split ? record.booking?.assigned_driver_id : null);
  const vehicle = target.assigned_vehicle_id || (!split ? record.booking?.assigned_vehicle_id : null);
  if (driver !== held.driver_id || vehicle !== held.vehicle_id) return failed('operational_capacity_unresolved', 409);
  if (actor.role === 'driver' && actor.driver_id !== held.driver_id) return failed('forbidden', 403);
  // A continuous roundtrip/waypoint route needs explicit remaining stop order.
  // Do not invent a straight-line route for it from a single destination.
  const itinerary = normalizeRemainingItinerary(body);
  if (!itinerary.ok) return failed(itinerary.error);
  if (itinerary.stops.some(stop => stop.not_before_iso && Date.parse(stop.not_before_iso) > endMs)) return failed('operational_itinerary_invalid');
  if (!itinerary.declared && (record.return_enabled && !split || !split && legs.length > 1 || record.booking?.return_enabled && !split
    || Number(record.stop_count || record.booking?.stop_count) > 0 || record.booking?.stops?.length)) {
    return failed('operational_route_complex', 409);
  }
  const route = { update_id: body.update_id, destination: { lat: destination.lat, lng: destination.lng, address: destination.address.trim() },
    expected_end_iso: new Date(endMs).toISOString(), remaining_handling_seconds: handling,
    ...(itinerary.declared ? { remaining_route_complete: true, remaining_stops: itinerary.stops } : {}) };
  const previous = target.operational_route;
  const comparable = value => JSON.stringify(value && { update_id: value.update_id, destination: value.destination,
    expected_end_iso: value.expected_end_iso, remaining_handling_seconds: value.remaining_handling_seconds,
    ...(value.remaining_route_complete === true ? { remaining_route_complete: true, remaining_stops: value.remaining_stops } : {}) });
  if (previous?.update_id === route.update_id) {
    if (comparable(previous) !== comparable(route)) return failed('operational_update_conflict', 409);
    return { ok: true, idempotent: true, record, route: previous, claim_id: claimId, tracking_leg: multi ? target.leg_id : '' };
  }
  if (endMs <= nowMs || endMs > nowMs + 24 * 60 * 60_000) return failed('operational_end_invalid');
  if (body.revision !== record.revision) return failed('revision_conflict', 409);
  const copy = structuredClone(record), now = new Date(nowMs).toISOString();
  const updatedTarget = multi || split ? copy.operational_legs.find(leg => leg.leg_id === target.leg_id && leg.leg_type === target.leg_type) : copy;
  updatedTarget.operational_route = { ...route, updated_at: now, actor_role: actor.role, actor_driver_id: actor.driver_id || null };
  if (multi && !split) copy.operational_route = { ...updatedTarget.operational_route, operational_leg: target.leg_id };
  // Route publication advances only the current leg's lifecycle clock.
  // The assignment/session remains identical; replay uses this same number.
  updatedTarget.customer_tracking_seq = (Number(target.customer_tracking_seq) || 1) + 1;
  copy.revision = record.revision + 1;
  copy.updated_at = now;
  return { ok: true, record: copy, route: updatedTarget.operational_route, claim_id: claimId, tracking_leg: multi ? target.leg_id : '' };
}

// KV demand pages are projections. A changed committed capacity generation,
// including a future reservation, must read its exact canonical route before
// prediction. Expired unstarted reservations need no read or route refresh.
// No GPS writes or global booking scan.
export async function refreshActiveCapacityDemand({ items, snapshot, scope, loadRecord, buildItems, buildClaims, maxOwners = 128, nowMs = Date.now() }) {
  let result = items.map(item => ({ ...item }));
  const claims = (snapshot.capacity_reservations || []).filter(claim => !claim.retiring
    && (claim.active === true || !unstartedCapacityExpired(claim, nowMs))
    && claim.tenant_id === scope.tenant_id && claim.company_id === scope.company_id);
  const matches = (item, claim) => item.booking_id === claim.claim_id
    && item.assigned_driver_id === claim.driver_id && item.assigned_vehicle_id === claim.vehicle_id;
  const unknown = claim => {
    for (const item of result.filter(item => matches(item, claim))) {
      if (claim.active === true) {
        item.activeRide = true; item.occupancyEndUnknown = true;
      } else {
        // Keep the committed time/actor occupancy, but never route using a
        // destination from an unverified older assignment or generation.
        item.reservationRouteUnresolved = true;
        delete item.pickupPoint; delete item.dropoffPoint;
      }
      delete item.operationalRoute;
    }
  };
  const needed = claims.filter(claim => claim.capacity_pending || !Number.isSafeInteger(claim.capacity_version)
    || !result.some(item => matches(item, claim) && (item.activeRide === true) === (claim.active === true)
      && item.capacityOnly !== true && item.capacityVersion === claim.capacity_version));
  const owners = [...new Set(needed.map(claim => claim.owner_id))];
  if (owners.length > maxOwners) { for (const claim of needed) unknown(claim); return result; }
  let cursor = 0;
  await Promise.all(Array.from({ length: Math.min(4, owners.length) }, async () => {
    while (cursor < owners.length) {
      const owner = owners[cursor++], owned = needed.filter(claim => claim.owner_id === owner);
      if (owned.some(claim => claim.capacity_pending || !Number.isSafeInteger(claim.capacity_version))) {
        for (const claim of owned) unknown(claim); continue;
      }
      try {
        const record = await loadRecord(owner);
        if (record?.tenant_id !== scope.tenant_id || record?.company_id !== scope.company_id) throw Error('scope');
        const built = buildItems(record, owner);
        for (const claim of owned) {
          let checkpoint = record.dispatch_capacity_checkpoint;
          const baseline = snapshot.capacity_baseline;
          // Reviewed legacy bootstrap committed revision+1 in the ledger,
          // without adding a checkpoint to the old canonical record. It can
          // supply route facts only while that exact pre-bootstrap record and
          // its reconstructed physical claim still match the committed hold.
          // Running rides and later mutations require an explicit checkpoint.
          if (!checkpoint && claim.active !== true && buildClaims
            && Number.isSafeInteger(record._canonical_version) && record._canonical_version > 0
            && Number.isSafeInteger(record.revision) && record.revision > 0
            && record.revision + 1 === claim.capacity_version
            && baseline?.tenant_id === scope.tenant_id && baseline?.company_id === scope.company_id
            && /^[a-f0-9]{64}$/.test(baseline.inventory_digest || '')
            && Number.isFinite(Date.parse(record.updated_at))
            && Date.parse(record.updated_at) <= Date.parse(baseline.initialized_at)) {
            const rebuilt = buildClaims(record, owner);
            if (rebuilt?.ok) checkpoint = { version: record.revision + 1, claims: rebuilt.claims };
          }
          const held = checkpoint?.claims?.find(row => sameClaim(row, claim));
          const fresh = built.filter(item => matches(item, claim) && (item.activeRide === true) === (claim.active === true));
          if (checkpoint?.version !== claim.capacity_version || !held || fresh.length !== 1) { unknown(claim); continue; }
          // A stale page may still expose the same leg as unassigned or under
          // an old actor, alongside the ledger placeholder. Once the exact
          // committed claim is verified, retain only its canonical row.
          const position = result.findIndex(item => matches(item, claim));
          if (position < 0) { unknown(claim); continue; }
          result = result.filter(item => item.booking_id !== claim.claim_id);
          result.splice(Math.min(position, result.length), 0, { ...fresh[0], capacityVersion: claim.capacity_version,
            serviceMin: Math.max(fresh[0].serviceMin, (claim.end_ms - fresh[0].pickupMs) / 60000) });
        }
      } catch (_) { for (const claim of owned) unknown(claim); }
    }
  }));
  return result;
}
