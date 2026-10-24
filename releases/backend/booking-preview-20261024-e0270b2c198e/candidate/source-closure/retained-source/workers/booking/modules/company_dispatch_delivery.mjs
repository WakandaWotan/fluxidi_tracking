import { companyTrackingObjectName } from '../../tracking/modules/company_tracking_room.mjs';
import { agendaCapacityClaims } from './company_agenda.mjs';
import { applyAgendaLegAssignment, resolveRoundtripDispatchMode } from './company_roundtrip.mjs';
import { stampTrackingAssignment } from './customer_tracking_access.mjs';
import { commitCompanyCapacity } from './company_capacity_commit.mjs';
import { completeCanonicalDispatchHandoff, canonicalBookingAuthorityEnabled } from './canonical_booking_authority.mjs';
import { dispatchLegCandidateRecord } from './dispatch_leg_candidate.mjs';
import { dispatchOfferBasis } from './dispatch_offer_basis.mjs';
import { bookingRequiresLimousineCompanyConfirmation } from './limousine_operational_handoff.mjs';
import { hasOpenDispatchAmendment as scopedOpen, initialDispatchAmendmentTarget } from './dispatch_booking_open.mjs';
import { comparableDispatchClaim } from '../../tracking/modules/company_dispatch_amendment.mjs';
import { asapSearchState, applyAsapPickup } from './asap_dispatch_timing.mjs';
import { scheduledReadinessReceiptsV1 } from './scheduled_dispatch_readiness_v1.mjs';
import { sanitizeAsapEtaAdvisory } from './pickup_timing_attention.mjs';
import { acceptedRideExecutionIdentities } from './company_ride_execution_identity.mjs';
import { readVehicleDispatchPreparation } from './company_vehicle_dispatch_policy.mjs';
import { missionDispatchPricingConstraint } from './company_mission_dispatch_pricing.mjs';
import { recordFirstOperationalUse } from './company_first_operational_use.mjs';
import {readFinancialDispatchPriceV2} from './financial_dispatch_price_v2.mjs';

async function parkVehicleDispatchReview(env, bookingId, record, preparation, reason) {
  if (record.do_not_dispatch === true && record.vehicle_dispatch_review?.reason === reason
    && record.dispatch_search?.state === 'manager_review') {
    return { ok: true, assigned: false, manager_review: true, reason };
  }
  record.vehicle_operating_policy_snapshot = preparation.policy;
  record.vehicle_dispatch_review = { reason, requested_at: new Date().toISOString() };
  record.do_not_dispatch = true;
  record.dispatch_search = { state: 'manager_review', reason };
  record.revision = (Number(record.revision) || 1) + 1;
  await env.BOOKING_KV.put(`booking:${bookingId}`, JSON.stringify(record));
  return { ok: true, assigned: false, manager_review: true, reason };
}

const failure = (error, status = 503) => ({ ok: false, error, status });
const matchesScope = (record, scope) => record?.tenant_id === scope.tenant_id && record?.company_id === scope.company_id;
const terminal = record => ['COMPLETED', 'CANCELLED', 'CANCELED', 'NO_SHOW', 'REJECTED', 'EXPIRED']
  .includes(String(record?.status || record?.lifecycle_status || '').toUpperCase());
const assigned = record => Boolean(record?.assigned_driver_id || record?.assignedDriverId
  || record?.assigned_vehicle_id || record?.assignedVehicleId || record?.booking?.assigned_driver_id
  || record?.booking?.assigned_vehicle_id);
const open = record => !terminal(record) && (!assigned(record) || scopedOpen(record));
const newerUnassignedCanonical = (env, record, offer) => canonicalBookingAuthorityEnabled(env)
  && Number.isSafeInteger(offer?.record_canonical_version) && offer.record_canonical_version > 0
  && Number.isSafeInteger(record?._canonical_version) && record._canonical_version > offer.record_canonical_version
  && open(record);
const changedCanonicalOffer = async (env, record, offer) => newerUnassignedCanonical(env, record, offer)
  && (record.dispatch_offer?.offer_id !== offer.offer_id || record.revision !== offer.record_revision
    || await dispatchOfferBasis(record) !== offer.record_dispatch_basis);

async function persistAsapWindow(env, bookingId, record, candidate) {
  if (!asapSearchState(record).asap || !candidate?.ok || !Number.isFinite(candidate.alloc?.pickup_ms)) return record;
  if (!applyAsapPickup(record, candidate.alloc.pickup_ms)) return record;
  record.revision = (Number(record.revision) || 1) + 1;
  await env.BOOKING_KV.put(`booking:${bookingId}`, JSON.stringify(record));
  return env.BOOKING_KV.get(`booking:${bookingId}`, { type: 'json' });
}

async function refreshAsapOfferWindow(env, bookingId, record, selectCandidate) {
  const search = asapSearchState(record), intent = record.dispatch_offer;
  if (!search.asap || !open(record) || !['prepared', 'offered'].includes(intent?.state)
    || intent.amendment && !intent.assignments?.some(row => row.leg === 'outbound')) return record;
  if (search.expired) {
    if (record.dispatch_timing_attention?.reason !== 'asap_search_expired') {
      record.dispatch_timing_attention = { reason: 'asap_search_expired', leg_types: ['outbound'],
        detected_at: new Date().toISOString() };
      record.revision = (Number(record.revision) || 1) + 1;
      await env.BOOKING_KV.put(`booking:${bookingId}`, JSON.stringify(record));
      return env.BOOKING_KV.get(`booking:${bookingId}`, { type: 'json' });
    }
    return record;
  }
  const leg = (record.operational_legs || record.booking?.operational_legs || [])
    .find(row => row.leg_type === 'outbound');
  const copy = resolveRoundtripDispatchMode(record) === 'split_no_wait' && leg
    ? dispatchLegCandidateRecord(record, leg) : structuredClone(record);
  copy.customer_requested_vehicle_id = (intent.assignments || []).find(row => row.leg === 'outbound')?.vehicle_id
    || intent.vehicle_id;
  const candidate = await selectCandidate(copy, bookingId);
  if (asapSearchState(record).expired) return refreshAsapOfferWindow(env, bookingId, record, selectCandidate);
  return persistAsapWindow(env, bookingId, record, candidate);
}

async function refreshCanonicalOffer(env, scope, bookingId, record, oldOffer) {
  // Queue recovery before releasing an acknowledged-but-uncommitted hold.
  // A crash at either side leaves positive durable work for the same booking.
  if (!record.dispatch_offer_revalidation) {
    if (!newerUnassignedCanonical(env, record, oldOffer)) return failure('dispatch_refresh_unconfirmed', 409);
    record.dispatch_offer_revalidation = { ...oldOffer };
    if (record.dispatch_offer?.offer_id === oldOffer.offer_id) record.dispatch_offer = {
      ...record.dispatch_offer, state: 'cancelled', reason: 'canonical_changed' };
    record.revision = Math.max(Number(record.revision) || 1, oldOffer.version) + 1;
    record.dispatch_search = { state: 'pending', version: record.revision + 1, created_at: new Date().toISOString() };
    await env.BOOKING_KV.put(`booking:${bookingId}`, JSON.stringify(record));
    record = await env.BOOKING_KV.get(`booking:${bookingId}`, { type: 'json' });
  }
  const retired = record.dispatch_offer_revalidation;
  if (!newerUnassignedCanonical(env, record, retired)) return failure('dispatch_refresh_unconfirmed', 409);
  const released = await callDispatchRoom(env, scope, 'dispatch-offer', { ...retired, action: 'refresh',
    canonical_resolution: { offer_id: retired.offer_id, version: retired.version, reason: 'canonical_changed',
      record_canonical_version: record._canonical_version, unassigned: true,
      ...(retired.amendment ? { capacity_version: record.dispatch_capacity_checkpoint?.version,
        canonical_claims: record.dispatch_capacity_checkpoint?.claims } : {}) } });
  if (!released.ok) return released;
  delete record.dispatch_offer_revalidation;
  await env.BOOKING_KV.put(`booking:${bookingId}`, JSON.stringify(record));
  return { ok: true };
}

// A deadline only for evidence reads. Mutation requests keep their existing
// durable intent/retry contract: timing out a write cannot prove it did not commit.
export async function readTrackingEvidenceV1(operation) {
  let timer;
  try {
    return await Promise.race([Promise.resolve().then(operation), new Promise((_, reject) => {
      timer = setTimeout(() => reject(Error('tracking_evidence_timeout')), 1500);
    })]);
  } catch (_) {
    const error = Error('tracking_evidence_unavailable');
    error.code = 'tracking_evidence_unavailable';
    throw error;
  } finally { clearTimeout(timer); }
}

export async function callDispatchRoom(env, scope, path, body) {
  if (!env.COMPANY_TRACKING || !scope?.tenant_id || !scope?.company_id) return failure('dispatch_room_unavailable');
  try {
    const room = env.COMPANY_TRACKING.get(env.COMPANY_TRACKING.idFromName(companyTrackingObjectName(scope.tenant_id, scope.company_id)));
    const query = new URLSearchParams(scope);
    const evidenceRead = path === 'live' || path === 'vehicle-device' && body?.action === 'authenticate';
    const perform = async () => {
      const response = await room.fetch(`https://room/${path}${body ? '' : `?${query}`}`, body ? {
        method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ ...body, ...scope }),
      } : undefined);
      const result = await response.json();
      if (evidenceRead && (response.status >= 500 || response.status === 405
        || response.status === 404 && ['not_found', 'not_supported', 'unsupported_contract'].includes(result?.error)
        || !result || typeof result !== 'object' || Array.isArray(result) || typeof result.ok !== 'boolean')) {
        return { ...failure('tracking_evidence_unavailable'), dependency_unavailable: true };
      }
      return response.ok && result?.ok === true ? result : failure(result?.error || 'dispatch_room_unavailable', response.status);
    };
    return evidenceRead ? await readTrackingEvidenceV1(perform) : await perform();
  } catch (_) { return { ...failure('dispatch_room_unavailable'), dependency_unavailable: true }; }
}

// Only the company booking coordinator calls these canonical mutations. A
// persisted intent precedes device delivery; absence from KV never frees a claim.
export async function prepareCanonicalDispatchOffer(env, scope, bookingId, { selectCandidate, validateSplitAssignments, publishAssignment, requireHumanAcceptance = false } = {}) {
  if (env.DISPATCH_DEVICE_ACK_ENABLED !== '1') return failure('dispatch_creation_paused');
  let record = await env.BOOKING_KV.get(`booking:${bookingId}`, { type: 'json' });
  if (!matchesScope(record, scope)) return failure('dispatch_booking_unavailable', 409);
  if (record.dispatch_assignment_revalidation) {
    const recovered = await finishConfirmedRevalidation(env, scope, bookingId, record, publishAssignment);
    if (!recovered.ok) return recovered;
    return prepareCanonicalDispatchOffer(env, scope, bookingId, { selectCandidate, validateSplitAssignments, publishAssignment });
  }
  if (bookingRequiresLimousineCompanyConfirmation(record)) return failure('company_confirmation_required', 409);
  if (!terminal(record) && !scopedOpen(record) && !record.dispatch_offer_revalidation
    && !['prepared', 'offered'].includes(record.dispatch_offer?.state)) {
    const target = initialDispatchAmendmentTarget(record);
    if (target?.error) return failure(target.error, 409);
    if (target) {
      if (record.do_not_dispatch === true || record.booking?.do_not_dispatch === true
        || record.airport_scheduled_dispatch_mode === 'manager_first') return failure('dispatch_manual_only', 409);
      const checkpoint = record.dispatch_capacity_checkpoint, built = agendaCapacityClaims(record, bookingId);
      const same = (a, b) => Array.isArray(a) && Array.isArray(b)
        && JSON.stringify(a.map(comparableDispatchClaim).sort()) === JSON.stringify(b.map(comparableDispatchClaim).sort());
      // START activates the existing Room hold at the same capacity version.
      // Adopt that monotonic physical fact only when the canonical leg and
      // live hold agree; a stale checkpoint may never deactivate a driver.
      const canonicalMatches = Array.isArray(checkpoint?.claims) && checkpoint.claims.every(claim => claim && typeof claim === 'object')
        && same(built.claims?.map(claim => ({ ...claim, active: false })),
        checkpoint.claims.map(claim => ({ ...claim, active: false })))
        && !checkpoint.claims.some(claim => claim.active && !built.claims.some(next => next.claim_id === claim.claim_id && next.active));
      if (!built.ok || !Number.isSafeInteger(checkpoint?.version) || checkpoint.version < 1
        || checkpoint.version > (Number(record.revision) || 1) + 1 || built.claims.length !== 1
        || !canonicalMatches) return failure('dispatch_partial_reconciliation_required', 409);
      const live = await callDispatchRoom(env, scope, 'live');
      if (!live.ok) return live;
      if (live.capacity_contract_version !== 1 || !matchesScope(live.capacity_baseline, scope)) return failure('capacity_baseline_required');
      const held = (live.capacity_reservations || []).filter(claim => claim.owner_id === bookingId);
      if (!same(held, built.claims) || held.some(claim => claim.capacity_version !== checkpoint.version
        || claim.capacity_pending || claim.retiring || !matchesScope(claim, scope))) return failure('dispatch_amendment_conflict', 409);
      // Persist the scoped search before any candidate/network work. Recovery
      // remains possible even though the root belongs to the manual sibling.
      record.dispatch_amendment = { leg_types: [target.leg_type] };
      record.dispatch_capacity_checkpoint = { version: checkpoint.version, claims: built.claims };
      record.dispatch_search = { state: 'pending', version: (Number(record.revision) || 1) + 1,
        created_at: new Date().toISOString() };
      if (!record.operational_legs) record.operational_legs = structuredClone(record.booking.operational_legs);
      await env.BOOKING_KV.put(`booking:${bookingId}`, JSON.stringify(record));
      record = await env.BOOKING_KV.get(`booking:${bookingId}`, { type: 'json' });
    }
  }
  if (!open(record)) return failure('dispatch_booking_not_open', 409);
  let priceProof;
  try {priceProof=await readFinancialDispatchPriceV2(env,scope,record,bookingId);}catch(error){return failure(error.message,409);}
  const vehiclePreparation = await readVehicleDispatchPreparation(env, scope, record, {bookingId,priceProof});
  if (!vehiclePreparation.ok) return failure(vehiclePreparation.error, 409);
  const pricedVehicles = missionDispatchPricingConstraint(record, scope, priceProof);
  if (!pricedVehicles.ok) return parkVehicleDispatchReview(env, bookingId, record,
    vehiclePreparation, pricedVehicles.reason);
  if (vehiclePreparation.mode === 'manager_first') {
    if (['prepared', 'offered'].includes(record.dispatch_offer?.state)) return failure('dispatch_policy_transition_required', 409);
    return parkVehicleDispatchReview(env, bookingId, record, vehiclePreparation, vehiclePreparation.reason);
  }
  record = await refreshAsapOfferWindow(env, bookingId, record, selectCandidate);
  if (record.dispatch_offer_revalidation || ['prepared', 'offered'].includes(record.dispatch_offer?.state)
    && await changedCanonicalOffer(env, record, record.dispatch_offer)) {
    const refreshed = await refreshCanonicalOffer(env, scope, bookingId, record,
      record.dispatch_offer_revalidation || record.dispatch_offer);
    if (!refreshed.ok) return refreshed;
    return prepareCanonicalDispatchOffer(env, scope, bookingId, { selectCandidate, validateSplitAssignments, publishAssignment });
  }
  const split = resolveRoundtripDispatchMode(record) === 'split_no_wait';
  const amendment = scopedOpen(record);
  let intent = record.dispatch_offer;
  if (!intent || !['prepared', 'offered'].includes(intent.state)) {
    const splitLegs = split ? [...(record.operational_legs || record.booking?.operational_legs || [])]
      .sort((a, b) => a.leg_type === 'outbound' ? -1 : b.leg_type === 'outbound' ? 1 : 0) : [];
    if (split && (splitLegs.length !== 2 || !['outbound', 'return'].every(type => splitLegs.some(leg => leg.leg_type === type)))) {
      return failure('dispatch_offer_window_invalid', 409);
    }
    const selectedLegs = amendment ? splitLegs.filter(leg => record.dispatch_amendment.leg_types.includes(leg.leg_type)) : splitLegs;
    const candidates = split ? await Promise.all(selectedLegs.map(async leg => ({
      leg: leg.leg_type, ...(await selectCandidate(dispatchLegCandidateRecord(record, leg), bookingId)) }))) : [];
    let primaryCandidate = null;
    if (!split && vehiclePreparation.primary_vehicle_id) {
      if (pricedVehicles.constrained && !pricedVehicles.vehicle_ids.includes(vehiclePreparation.primary_vehicle_id)) {
        return parkVehicleDispatchReview(env, bookingId, record, vehiclePreparation, 'mission_vehicle_price_review_required');
      }
      primaryCandidate = await selectCandidate({ ...record, customer_requested_vehicle_id: vehiclePreparation.primary_vehicle_id }, bookingId);
      if (primaryCandidate?.assignedVehicleId !== vehiclePreparation.primary_vehicle_id) primaryCandidate = null;
    }
    let candidate = split ? candidates[0] : primaryCandidate?.ok ? primaryCandidate : await selectCandidate(record, bookingId);
    if (split && candidates.some(row => !row.ok || !row.assignedDriverId || !row.assignedVehicleId)) {
      candidate = candidates.find(row=>row.error==='p12_dispatcher_review') ?? { ok: false, error: 'dispatch_split_candidate_missing',
        ...(candidates.some(row => row.allocator_reason === 'pickup_time_in_past') ? { allocator_reason: 'pickup_time_in_past' } : {}) };
    }
    if (candidate?.ok && (split ? candidates.some(row=>{const constraint=missionDispatchPricingConstraint(record,scope,priceProof,row.leg);return !constraint.ok||constraint.constrained&&!constraint.vehicle_ids.includes(row.assignedVehicleId);}) : pricedVehicles.constrained&&!pricedVehicles.vehicle_ids.includes(candidate.assignedVehicleId))) {
      return parkVehicleDispatchReview(env, bookingId, record, vehiclePreparation, 'mission_vehicle_price_review_required');
    }
    if (!candidate?.ok || !candidate.assignedDriverId || !candidate.assignedVehicleId) {
      // Trusted local P12 selector only; no customer request can supply a callback.
      if (candidate?.error === 'p12_dispatcher_review' && typeof candidate.enqueueDispatcher === 'function'
        && record.p12_reliable_choice?.schema === 'fluxidi-reliable-choice-v1') {
        record.p12_dispatcher_review = await candidate.enqueueDispatcher();
        return parkVehicleDispatchReview(env, bookingId, record, vehiclePreparation, candidate.allocator_reason || 'p12_manual_review');
      }
      if (vehiclePreparation.mode === 'human_offer') return parkVehicleDispatchReview(env, bookingId, record,
        vehiclePreparation, 'no_staffed_live_vehicle');
      const asapExpired = (!split || selectedLegs.some(leg => leg.leg_type === 'outbound'))
        && asapSearchState(record).asap && asapSearchState(record).expired;
      if (asapExpired && record.dispatch_timing_attention?.reason !== 'asap_search_expired') {
        record.dispatch_timing_attention = { reason: 'asap_search_expired', leg_types: ['outbound'],
          detected_at: new Date().toISOString() };
        await env.BOOKING_KV.put(`booking:${bookingId}`, JSON.stringify(record));
      }
      const lateLegs = (split ? selectedLegs.map(row => row.leg_type) : ['outbound'])
        .filter(type => pickupOverdue(record, type));
      if (lateLegs.length) await preservePickupTimingAttention(env, bookingId, record, lateLegs);
      const version = (Number(record.revision) || 1) + 1;
      if (record.dispatch_search?.state !== 'pending' || record.dispatch_search.version !== version) {
        record.dispatch_search = { state: 'pending', version, created_at: new Date().toISOString() };
        await env.BOOKING_KV.put(`booking:${bookingId}`, JSON.stringify(record));
      }
      const queued = await callDispatchRoom(env, scope, 'dispatch-search', { owner_id: bookingId, version,
        ...(amendment ? { amendment: true, base_version: record.dispatch_capacity_checkpoint.version,
          retained_claims: record.dispatch_capacity_checkpoint.claims } : {}) });
      if (queued.ok) await completeCanonicalDispatchHandoff(env, scope, bookingId,
        { type: 'search', id: queued.search_id, version });
      if (queued.ok && (lateLegs.length || asapExpired)) {
        const published = await publishAssignment?.(bookingId, record, []);
        if (!published?.ok) return failure('dispatch_timing_publication_pending');
        const parked = await callDispatchRoom(env, scope, 'dispatch-events', { ...queued.event, event_id:queued.search_id,
          owner_id:bookingId,offer_id:queued.search_id,version,
          pickup_timing_attention:asapExpired ? 'asap_search_expired' : 'pickup_overdue' });
        if (!parked.ok) return parked;
      }
      return queued.ok ? { ok: true, pending_search: true, assigned: false, search_id: queued.search_id,
        ...(lateLegs.length ? { pickup_overdue:true, planner_attention:true } : {}),
        ...(asapExpired ? { asap_search_expired:true, planner_attention:true } : {}),
        reason: candidate?.allocator_reason || candidate?.error || 'dispatch_no_candidate' } : queued;
    }
    if (!split || selectedLegs.some(leg => leg.leg_type === 'outbound')) {
      record = await persistAsapWindow(env, bookingId, record, candidate);
    }
    const copy = structuredClone(record);
    if (record.dispatch_timing_attention?.reason === 'pickup_overdue') delete record.dispatch_timing_attention;
    if (split && !amendment) copy.operational_legs = structuredClone(record.operational_legs || record.booking?.operational_legs || splitLegs);
    const assignments = split ? candidates.map(row => ({ leg: row.leg, driver_id: row.assignedDriverId, vehicle_id: row.assignedVehicleId }))
      : [{ leg: 'outbound', driver_id: candidate.assignedDriverId, vehicle_id: candidate.assignedVehicleId }];
    for (const assignment of assignments) applyAgendaLegAssignment(copy, { leg: assignment.leg,
      driverId: assignment.driver_id, vehicleId: assignment.vehicle_id, now: new Date().toISOString() });
    const claims = agendaCapacityClaims(copy, bookingId);
    const offeredClaims = amendment ? claims.claims.filter(claim => record.dispatch_amendment.leg_types
      .some(type => claim.claim_id === `${bookingId}:${type.toUpperCase()}`)) : claims.claims;
    if (!claims.ok || offeredClaims.length !== (amendment ? 1 : split ? 2 : 1)
      || offeredClaims.some(row => row.active)) return failure('dispatch_offer_window_invalid', 409);
    if (split && claims.claims.length > 1 && (!validateSplitAssignments || !(await validateSplitAssignments(copy, claims.claims))?.ok)) {
      return failure('dispatch_split_route_unproven', 409);
    }
    const live = await callDispatchRoom(env, scope, 'live');
    if (!live.ok || live.capacity_contract_version !== 1) return failure('dispatch_capacity_contract_unavailable');
    if (!matchesScope(live.capacity_baseline, scope)) return failure('capacity_baseline_required');
    const preceding = (live.capacity_reservations || []).filter(claim => claim.active
      && assignments.some(row => row.driver_id === claim.driver_id && row.vehicle_id === claim.vehicle_id));
    if (assignments.some(row => preceding.filter(claim => claim.driver_id === row.driver_id && claim.vehicle_id === row.vehicle_id).length > 1)
      || preceding.some(claim => claim.end_ms > Math.min(...offeredClaims.filter(row =>
        row.driver_id === claim.driver_id && row.vehicle_id === claim.vehicle_id).map(row => row.start_ms)))) {
      return failure('dispatch_prerequisite_conflict', 409);
    }
    const revision = (Number(record.revision) || 1) + 1;
    intent = { offer_id: `offer:${bookingId}:${revision}`, owner_id: bookingId, version: revision + 1,
      ...((vehiclePreparation.mode === 'human_offer' || requireHumanAcceptance === true
        || record.financial_evidence?.version === 2 && record.financial_evidence?.inputs?.pricing_options?.booking_mode === 'provider_automatic'
        || record.p12_reliable_choice?.schema === 'fluxidi-reliable-choice-v1') ? { human_acceptance_required: true,
        ack_timeout_ms: vehiclePreparation.ack_timeout_ms ?? 30_000, response_starts_on_display: offeredClaims.length === 1 } : {}),
      ...(asapSearchState(record).asap && (!amendment || selectedLegs.some(leg => leg.leg_type === 'outbound')) ? {
        asap_requested_ms: Date.parse(record.asap_requested_at),
        asap_search_expires_ms: Date.parse(record.asap_search_expires_at),
      } : {}),
      driver_id: candidate.assignedDriverId, vehicle_id: candidate.assignedVehicleId,
      claims: offeredClaims, state: 'prepared', record_revision: revision,
      ...(amendment ? { amendment: true, base_version: record.dispatch_capacity_checkpoint.version,
        retained_claims: record.dispatch_capacity_checkpoint.claims } : {}),
      ...(canonicalBookingAuthorityEnabled(env) && Number(record._canonical_version) > 0
        ? { record_canonical_version: record._canonical_version + 1, record_dispatch_basis: await dispatchOfferBasis(record) } : {}),
      ...(split ? { assignments, prerequisites: preceding.map(claim => ({ claim_id: claim.claim_id,
        version: claim.capacity_version, driver_id: claim.driver_id, vehicle_id: claim.vehicle_id })) } : {}),
      ...(preceding[0] ? { prerequisite_claim_id: preceding[0].claim_id, prerequisite_version: preceding[0].capacity_version } : {}),
      created_at: new Date().toISOString(), ...scope };
    record.revision = revision;
    if (vehiclePreparation.mode === 'human_offer') record.vehicle_operating_policy_snapshot = vehiclePreparation.policy;
    record.dispatch_offer = intent;
    if (record.dispatch_search?.state === 'pending') record.dispatch_search = {
      ...record.dispatch_search, state: 'offered', offer_id: intent.offer_id };
    await env.BOOKING_KV.put(`booking:${bookingId}`, JSON.stringify(record));
  }
  const offered = await callDispatchRoom(env, scope, 'dispatch-offer', { ...intent, action: 'offer' });
  if (!offered.ok) {
    if (offered.error === 'asap_search_expired') {
      record = await refreshAsapOfferWindow(env, bookingId, record, selectCandidate);
      const retired = await refreshCanonicalOffer(env, scope, bookingId, record, intent);
      if (!retired.ok) return retired;
      return prepareCanonicalDispatchOffer(env, scope, bookingId, { selectCandidate, validateSplitAssignments, publishAssignment });
    }
    if (!['capacity_conflict', 'capacity_completion_unconfirmed', 'active_ride_end_unknown', 'dispatch_offer_location_stale', 'dispatch_prerequisite_conflict', 'dispatch_device_unavailable'].includes(offered.error)) return offered;
    // The candidate can become occupied between ranking and its atomic claim.
    // Retain a durable search event rather than strand the prepared intent.
    const deferred = await callDispatchRoom(env, scope, 'dispatch-offer', { ...intent, action: 'defer' });
    if (deferred.ok) await completeCanonicalDispatchHandoff(env, scope, bookingId,
      { type: 'offer', id: intent.offer_id, version: intent.version });
    return deferred.ok ? { ok: true, pending_search: true, assigned: false, offer_id: intent.offer_id } : deferred;
  }
  await completeCanonicalDispatchHandoff(env, scope, bookingId,
    { type: 'offer', id: intent.offer_id, version: intent.version });
  // No second KV write is needed: the Room owns delivery and deadline state.
  return { ok: true, pending_receipt: true, assigned: false, offer_id: intent.offer_id };
}

export async function registerDriverDispatchDevice(env, scope, session, protocol) {
  return callDispatchRoom(env, scope, 'dispatch-device', { driver_id: session.driver_id,
    ...(session.vehicle_device_id ? { vehicle_device_id: session.vehicle_device_id } : {}),
    device_key: session.token_hash, session_expires_ms: Date.parse(session.expires_at), protocol });
}

export async function listDriverDispatchOffers(env, scope, driverId, deviceKey = '') {
  return callDispatchRoom(env, { ...scope, driver_id: driverId, device_key: deviceKey }, 'driver-offers');
}

export async function acknowledgeDriverDispatchOffer(env, scope, driverId, input, action = 'ack', requireHuman = false, personalExecutionAuth = null, legacyReceiptSession = null) {
  if (!['ack', 'accept', 'decline'].includes(action)) return failure('dispatch_offer_invalid', 400);
  const delivery = await listDriverDispatchOffers(env, scope, driverId, input.device_key);
  if (!delivery.ok) return delivery;
  const offer = delivery.offers.find(row => row.offer_id === input.offer_id && row.version === input.version);
  if (!offer) return failure('dispatch_offer_not_owned', 409);
  if(personalExecutionAuth&&personalExecutionAuth.vehicle_id!==offer.vehicle_id)return failure('vehicle_session_mismatch',409);
  if (action === 'accept') {
    // Do not cross the durable acceptance barrier without current technical
    // evidence. Room still enforces the actual duty, GPS and device lease.
    const live = await callDispatchRoom(env, scope, 'live');
    if (!live.ok) return live;
    if (live.tenant_id !== scope.tenant_id || live.company_id !== scope.company_id)
      return failure('company_live_scope_invalid', 403);
    if (live.capacity_contract_version !== 1 || live.dispatch_device_contract_version !== 1
      || !Array.isArray(live.capacity_reservations) || !Array.isArray(live.dispatch_devices)
      || !Array.isArray(live.drivers) || !Array.isArray(live.active_direct_rides))
      return { ...failure('tracking_evidence_unavailable'), dependency_unavailable: true };
  }
  if (requireHuman && !offer.human_acceptance_required) {
    const receipts = action === 'ack' && legacyReceiptSession?.driver_id === driverId
      ? await scheduledReadinessReceiptsV1(env,scope,legacyReceiptSession,[offer]) : [];
    if (!receipts.some(r=>r.offer_id===offer.offer_id&&r.version===offer.version)) return failure('dispatch_human_acceptance_required', 409);
  }
  return callDispatchRoom(env, scope, 'dispatch-offer', { ...offer, driver_id: driverId, device_key: input.device_key, action,
    ...(action==='accept'&&personalExecutionAuth?{personal_execution_auth:personalExecutionAuth}:{}) });
}

function scheduledDispatchPickup(record, type) {
  const leg = (record.operational_legs || record.booking?.operational_legs || []).find(leg => leg.leg_type === type);
  return leg?.pickup_iso || leg?.pickupIso || (type === 'return'
    ? record.return_pickup_iso || record.booking?.return_pickup_iso
    : record.pickup_iso || record.booking?.pickup_iso) || null;
}
const pickupOverdue = (record, type) => !(type === 'outbound' && asapSearchState(record).asap
  && record.dispatch_offer?.state !== 'committed' && open(record))
  && Number.isFinite(Date.parse(scheduledDispatchPickup(record, type)))
  && Date.parse(scheduledDispatchPickup(record, type)) <= Date.now();

async function preservePickupTimingAttention(env, ownerId, record, legTypes) {
  const timing = { reason: 'pickup_overdue', leg_types: [...new Set(legTypes)].sort(),
    scheduled_pickups: Object.fromEntries(legTypes.map(type => [type, scheduledDispatchPickup(record, type)])) };
  const previous = record.dispatch_timing_attention;
  if (previous?.reason === timing.reason && JSON.stringify(previous.leg_types) === JSON.stringify(timing.leg_types)
    && JSON.stringify(previous.scheduled_pickups) === JSON.stringify(timing.scheduled_pickups)) return;
  record.dispatch_timing_attention = { ...timing, detected_at: new Date(Date.now()).toISOString() };
  // No assignment, schedule, revision or capacity change. The same company
  // writer protects this attention marker against START and manual rescheduling.
  await env.BOOKING_KV.put(`booking:${ownerId}`, JSON.stringify(record));
}

async function validateReceiptCandidates(record, intent, ownerId, selectCandidate, validateSplitAssignments) {
  if (typeof selectCandidate !== 'function') return failure('dispatch_revalidation_unavailable');
  const split = resolveRoundtripDispatchMode(record) === 'split_no_wait';
  const assignments = intent.assignments || [{ leg: 'outbound', driver_id: intent.driver_id, vehicle_id: intent.vehicle_id }];
  const etaUpdates = [];
  for (const assignment of assignments) {
    const leg = (record.operational_legs || record.booking?.operational_legs || []).find(row => row.leg_type === assignment.leg);
    if (split && !leg) return failure('dispatch_canonical_window_changed');
    const candidateRecord = split ? dispatchLegCandidateRecord(record, leg) : structuredClone(record);
    // Keep the canonical capacity window, never restart discovery after commit.
    // Its ASAP arrival estimate is advisory; a scheduled/return appointment is
    // still hard. The allocator must prove every non-ETA gate for this resource.
    const etaAdvisory = intent.state === 'committed' && record.pickup_mode === 'asap'
      && assignment.leg === 'outbound'
      && record.p12_reliable_choice?.request_context?.deadlineAt == null;
    if (intent.state === 'committed' && candidateRecord.pickup_mode === 'asap') candidateRecord.pickup_mode = 'scheduled';
    // Verify the offered resource against current GPS, roster and road time.
    // This is request-local: the customer's sealed vehicle choice is unchanged.
    candidateRecord.customer_requested_vehicle_id = assignment.vehicle_id;
    const candidate = await selectCandidate(candidateRecord, ownerId, {
      confirmedAsapRevalidation: intent.state === 'committed' && record.pickup_mode === 'asap' && assignment.leg === 'outbound',
      confirmedAsapEtaAdvisory: etaAdvisory,
    });
    const missingEvidence = new Set(['allocator_error', 'asap_dispatch_unavailable', 'dispatch_device_snapshot_unavailable',
      'company_live_unavailable', 'capacity_snapshot_unavailable', 'tracking_evidence_unavailable']);
    if ([candidate?.reason, candidate?.error, candidate?.allocator_reason, candidate?.alloc?.reason]
      .some(reason => missingEvidence.has(reason))) {
      return { ...failure('dispatch_revalidation_unavailable'), temporarily_unavailable: true };
    }
    if (intent.state !== 'committed' && assignment.leg === 'outbound' && asapSearchState(record).asap
      && (asapSearchState(record).expired || candidate?.ok
        && Number.isFinite(candidate.alloc?.pickup_ms)
        && candidate.alloc.pickup_ms !== Date.parse(scheduledDispatchPickup(record, assignment.leg)))) {
      return { ok: false, obsolete: true, timing_candidate: candidate };
    }
    if (candidate?.allocator_reason === 'pickup_time_in_past' || !etaAdvisory && !candidate?.ok && pickupOverdue(record, assignment.leg)) {
      return { ...failure('dispatch_pickup_overdue', 409), attention_leg: assignment.leg };
    }
    if (!candidate?.ok || candidate.assignedDriverId !== assignment.driver_id || candidate.assignedVehicleId !== assignment.vehicle_id) {
      return { ok: false, obsolete: true, failed_driver_id: assignment.driver_id, failed_leg: assignment.leg };
    }
    if (etaAdvisory) etaUpdates.push(sanitizeAsapEtaAdvisory(candidate.alloc?.asap_eta_advisory));
  }
  if (split && [...(intent.retained_claims || []), ...intent.claims].length > 1) {
    const transfer = await validateSplitAssignments?.(record, [...(intent.retained_claims || []), ...intent.claims]);
    if (transfer?.temporarily_unavailable) return failure('dispatch_revalidation_unavailable');
    if (!transfer?.ok) return { ok: false, obsolete: true };
  }
  return { ok: true, ...(etaUpdates.length ? { etaUpdates } : {}) };
}

async function preserveConfirmedAsapEta(env, ownerId, record, eta, publishAssignment) {
  const timing = { reason:'asap_eta_updated', leg_types:['outbound'],
    scheduled_pickups:{outbound:scheduledDispatchPickup(record,'outbound')}, eta };
  const previous = record.dispatch_timing_attention;
  if (JSON.stringify(previous && {...previous,detected_at:undefined}) !== JSON.stringify(timing)) {
    record.dispatch_timing_attention = {...timing,detected_at:new Date().toISOString()};
    await env.BOOKING_KV.put(`booking:${ownerId}`,JSON.stringify(record));
  }
  // Retry publication even when a prior attempt already stored the same ETA.
  // No assignment generation, price, pickup or capacity claim is changed.
  const published = await publishAssignment?.(ownerId,record,[]);
  return published?.ok ? {ok:true,eta_updated:true} : failure('dispatch_timing_publication_pending');
}

async function retryObsoleteReceipt(env, scope, ownerId, record, intent, failedDriverId, hooks) {
  // The canonical search and retired offer are durable BEFORE the Room may
  // release its ACK barrier. The existing refresh protocol handles restart.
  record.revision = Math.max(Number(record.revision) || 1, intent.version) + 1;
  record.dispatch_offer = { ...intent, state: 'cancelled', reason: hooks.retirementReason || 'pickup_no_longer_feasible' };
  record.dispatch_offer_revalidation = { ...intent };
  if (intent.amendment) record.dispatch_capacity_checkpoint = { version: record.revision + 1,
    claims: intent.retained_claims };
  record.dispatch_search = { state: 'pending', version: record.revision + 1, created_at: new Date().toISOString() };
  if (failedDriverId) record.dispatch_exclusions = [
    ...(record.dispatch_exclusions || []).filter(row => row.until_ms > Date.now() && row.driver_id !== failedDriverId),
    { driver_id: failedDriverId, until_ms: Date.now() + 300_000 },
  ].slice(-16);
  await env.BOOKING_KV.put(`booking:${ownerId}`, JSON.stringify(record));
  const current = await env.BOOKING_KV.get(`booking:${ownerId}`, { type: 'json' });
  const refreshed = await refreshCanonicalOffer(env, scope, ownerId, current, intent);
  if (!refreshed.ok) return refreshed;
  return prepareCanonicalDispatchOffer(env, scope, ownerId, hooks);
}

async function finishConfirmedRevalidation(env, scope, ownerId, record, publishAssignment) {
  const retired = record.dispatch_assignment_revalidation;
  const checkpoint = record.dispatch_capacity_checkpoint;
  if (!retired || !checkpoint || checkpoint.version <= retired.version || !Array.isArray(checkpoint.claims)
    || typeof publishAssignment !== 'function') return failure('dispatch_revalidation_checkpoint_missing');
  // Clear the old customer grant and indexes while its capacity is still held.
  // A publication/storage failure cannot make that resource available early.
  const published = await publishAssignment(ownerId, record, retired.tracking_scopes);
  if (!published?.ok) return failure(published?.error || 'dispatch_publication_incomplete');
  const confirmed = await commitCompanyCapacity(env, scope, { action: 'confirm', owner_id: ownerId,
    version: checkpoint.version, canonical_claims: checkpoint.claims });
  if (!confirmed.ok) return confirmed;
  const superseded = await callDispatchRoom(env, scope, 'dispatch-offer', { ...retired, action: 'supersede',
    canonical_version: checkpoint.version });
  if (!superseded.ok) return superseded;
  delete record.dispatch_assignment_revalidation;
  await env.BOOKING_KV.put(`booking:${ownerId}`, JSON.stringify(record));
  return { ok: true };
}

async function revalidateConfirmedAssignment(env, scope, event, record, hooks) {
  const intent = record.dispatch_offer;
  if (record.dispatch_assignment_revalidation) {
    const finished = await finishConfirmedRevalidation(env, scope, event.owner_id, record, hooks.publishAssignment);
    if (!finished.ok) return finished;
  } else {
    if (!canonicalBookingAuthorityEnabled(env) || terminal(record) || event.offer_state !== 'committed'
      || intent?.state !== 'committed' || intent.offer_id !== event.offer_id || intent.version !== event.version
      || !Number.isSafeInteger(record.dispatch_capacity_checkpoint?.version)
      || record.dispatch_capacity_checkpoint.version < intent.version) return { ok: true };
    const built = agendaCapacityClaims(record, event.owner_id);
    if (!built.ok) return { ok: true };
    const split = resolveRoundtripDispatchMode(record) === 'split_no_wait';
    if ((!split || !intent.tracking_assignment_versions) && (record.dispatch_capacity_checkpoint.version !== intent.version
      || record.assigned_driver_id !== event.driver_id || record.assigned_vehicle_id !== event.vehicle_id)) return { ok: true };
    const partial = split && (built.claims.some(claim => claim.active) || intent.amendment
      || built.claims.length !== intent.claims.length || record.dispatch_capacity_checkpoint.version !== intent.version);
    const monitored = event.revalidation_claim_ids || intent.claims.map(claim => claim.claim_id);
    const candidates = intent.claims.filter(claim => monitored.includes(claim.claim_id)
      && built.claims.some(current => current.claim_id === claim.claim_id && !current.active)
      && (!intent.tracking_assignment_versions || (record.operational_legs || []).some(leg =>
        `${event.owner_id}:${leg.leg_type.toUpperCase()}` === claim.claim_id
        && leg.assigned_driver_id === claim.driver_id && leg.assigned_vehicle_id === claim.vehicle_id
        && (Number(leg.customer_tracking_assignment_version) || 1) === intent.tracking_assignment_versions[claim.claim_id]))
      && (!partial || claim.start_ms <= Date.now() + 15 * 60_000));
    const sameClaim = (left, right) => left.claim_id === right.claim_id && left.driver_id === right.driver_id
      && left.vehicle_id === right.vehicle_id && left.start_ms === right.start_ms && left.end_ms === right.end_ms;
    if (!built.ok || !candidates.length || (!split && (built.claims.some(claim => claim.active)
      || record.customer_tracking_phase === 'in_progress'))
      || candidates.some(claim => !built.claims.some(current => sameClaim(current, claim)))) return { ok: true };
    const inspected = partial ? { ...intent, assignments: (intent.assignments || []).filter(assignment =>
      candidates.some(claim => claim.claim_id === `${event.owner_id}:${assignment.leg.toUpperCase()}`)),
      retained_claims: built.claims.filter(claim => !candidates.some(candidate => candidate.claim_id === claim.claim_id)), claims: candidates } : intent;
    const feasible = await validateReceiptCandidates(record, inspected, event.owner_id, hooks.selectCandidate, hooks.validateSplitAssignments);
    if (feasible.ok) return feasible.etaUpdates?.length
      ? preserveConfirmedAsapEta(env,event.owner_id,record,feasible.etaUpdates[0],hooks.publishAssignment)
      : { ok: true };
    if (feasible.error === 'dispatch_pickup_overdue') {
      await preservePickupTimingAttention(env, event.owner_id, record, [feasible.attention_leg]);
      const published = await hooks.publishAssignment?.(event.owner_id,record,[]);
      if (!published?.ok) return failure('dispatch_timing_publication_pending');
      return { ok:true, pickup_overdue:true };
    }
    if (!feasible.obsolete) return feasible;
    const copy = structuredClone(record);
    const changedAssignments = partial ? inspected.assignments.filter(assignment => assignment.leg === (feasible.failed_leg || 'return'))
      : intent.assignments || [{ leg: 'outbound' }];
    if (!changedAssignments.length) return { ok: true };
    for (const assignment of changedAssignments) {
      applyAgendaLegAssignment(copy, { leg: assignment.leg, driverId: '', vehicleId: '', now: new Date().toISOString() });
    }
    const changedTypes = changedAssignments.map(assignment => assignment.leg);
    const sources = partial ? (copy.operational_legs || []).filter(leg => changedTypes.includes(leg.leg_type))
      : [copy, copy.booking, copy.payload, ...(copy.operational_legs || [])];
    for (const source of sources) {
      if (!source || typeof source !== 'object') continue;
      for (const key of ['assigned_driver', 'assignedDriver', 'assigned_vehicle', 'assignedVehicle',
        'driver_id', 'driverId', 'vehicle_id', 'vehicleId']) delete source[key];
    }
    const scopes = stampTrackingAssignment(copy, partial ? { legs: changedTypes } : {});
    copy.revision = Math.max(Number(record.revision) || 1, intent.version) + 1;
    const retained = agendaCapacityClaims(copy, event.owner_id);
    if (!retained.ok) return failure('dispatch_revalidation_checkpoint_missing');
    copy.dispatch_capacity_checkpoint = { version: copy.revision + 1, claims: retained.claims };
    if (partial) copy.dispatch_amendment = { leg_types: changedTypes };
    copy.dispatch_assignment_revalidation = { ...intent, tracking_scopes: scopes };
    copy.dispatch_offer = { ...intent, state: 'cancelled', reason: 'confirmed_pickup_no_longer_feasible' };
    copy.dispatch_search = { state: 'pending', version: copy.revision + 1, created_at: new Date().toISOString() };
    if (feasible.failed_driver_id) copy.dispatch_exclusions = [
      ...(copy.dispatch_exclusions || []).filter(row => row.until_ms > Date.now() && row.driver_id !== feasible.failed_driver_id),
      { driver_id: feasible.failed_driver_id, until_ms: Date.now() + 300_000 },
    ].slice(-16);
    // Retiring claims remain occupied until canonical unassignment and customer
    // publication succeed. The existing company gate serializes START against it.
    const prepared = await commitCompanyCapacity(env, scope, { action: 'reserve', owner_id: event.owner_id,
      version: copy.dispatch_capacity_checkpoint.version, replace_owner: true, claims: retained.claims });
    if (!prepared.ok) return prepared;
    await env.BOOKING_KV.put(`booking:${event.owner_id}`, JSON.stringify(copy));
    record = copy;
    const finished = await finishConfirmedRevalidation(env, scope, event.owner_id, record, hooks.publishAssignment);
    if (!finished.ok) return finished;
  }
  return env.DISPATCH_DEVICE_ACK_ENABLED === '1'
    ? prepareCanonicalDispatchOffer(env, scope, event.owner_id, hooks)
    : { ok: true, pending_search: true, creation_paused: true };
}

export async function consumeCanonicalDispatchEvent(env, scope, input, { selectCandidate, publishAssignment, validateSplitAssignments } = {}) {
  const pending = await callDispatchRoom(env, scope, 'dispatch-events');
  if (!pending.ok) return pending;
  const event = pending.events.find(row => row.event_id === input.event_id);
  // The trusted Room is the event authority, never the bridge request body.
  if (!event) return { ok: true, already_delivered: true };
  let record = await env.BOOKING_KV.get(`booking:${event.owner_id}`, { type: 'json' });
  if (!matchesScope(record, scope)) return failure('dispatch_canonical_evidence_missing');
  // Recheck the accepted sale before committing an offered resource, including
  // retries. A dispatch offer ID is never the financial quote identity.
  if(event.type==='assignment_commit'&&event.offer_state!=='aborted'&&!terminal(record)){
    let proof;
    try{proof=await readFinancialDispatchPriceV2(env,scope,record,event.owner_id);}catch(error){return failure(error.message,409);}
    const assignments=record.dispatch_offer?.assignments??[{leg:'outbound',vehicle_id:record.dispatch_offer?.vehicle_id}];
    for(const assignment of assignments){
      const constraint=missionDispatchPricingConstraint(record,scope,proof,assignment.leg??'outbound');
      if(!constraint.ok||constraint.constrained&&!constraint.vehicle_ids.includes(assignment.vehicle_id))return failure(constraint.reason||'dispatch_financial_vehicle_mismatch',409);
    }
  }
  if (event.type === 'assignment_commit' && event.offer_state !== 'aborted'
    && record.dispatch_offer?.offer_id === event.offer_id && record.dispatch_offer?.version === event.version) {
    record = await refreshAsapOfferWindow(env, event.owner_id, record, selectCandidate);
  }
  const intent = record.dispatch_offer;
  const ownsIntent = intent?.offer_id === event.offer_id && intent.version === event.version
    && intent.driver_id === event.driver_id && intent.vehicle_id === event.vehicle_id;
  let timingAttention = false;
  if (event.type === 'assignment_revalidate') {
    const revalidated = await revalidateConfirmedAssignment(env, scope, event, record,
      { selectCandidate, publishAssignment, validateSplitAssignments });
    if (!revalidated.ok) return revalidated;
    timingAttention = revalidated.pickup_overdue === true;
  } else if (event.type === 'assignment_commit') {
    if (event.offer_state === 'aborted') {
      const acknowledged = await callDispatchRoom(env, scope, 'dispatch-events', event);
      return acknowledged.ok ? { ok: true, retired: true } : acknowledged;
    }
    if (await changedCanonicalOffer(env, record, event)) {
      const refreshed = await refreshCanonicalOffer(env, scope, event.owner_id, record, event);
      if (!refreshed.ok) return refreshed;
      const retried = await prepareCanonicalDispatchOffer(env, scope, event.owner_id, { selectCandidate, validateSplitAssignments, publishAssignment });
      if (!retried.ok) return retried;
      const acknowledged = await callDispatchRoom(env, scope, 'dispatch-events', event);
      return acknowledged.ok ? { ok: true, revalidated: true } : acknowledged;
    }
    const current = record.dispatch_capacity_checkpoint;
    if (current?.version > event.version && current.version === Number(record.revision) + 1 && Array.isArray(current.claims)) {
      const confirmed = await commitCompanyCapacity(env, scope, { action: 'confirm', owner_id: event.owner_id,
        version: current.version, canonical_claims: current.claims });
      if (!confirmed.ok) return confirmed;
      if (!terminal(record)) {
        const published = await publishAssignment(event.owner_id, record, intent?.tracking_scopes || ['']);
        if (!published?.ok) return failure('dispatch_publication_incomplete');
      }
      const superseded = await callDispatchRoom(env, scope, 'dispatch-offer', { ...event, action: 'supersede', canonical_version: current.version });
      if (!superseded.ok) return superseded;
      const acknowledged = await callDispatchRoom(env, scope, 'dispatch-events', event);
      return acknowledged.ok ? { ok: true, superseded: true } : acknowledged;
    }
    if (!ownsIntent) return failure('dispatch_canonical_intent_conflict');
    if (terminal(record)) {
      const aborted = await callDispatchRoom(env, scope, 'dispatch-offer', { ...event, action: 'abort',
        canonical_resolution: { offer_id: intent.offer_id, version: intent.version,
          record_revision: record.revision, reason: 'terminal', status: record.status || record.lifecycle_status } });
      if (!aborted.ok) return aborted;
    } else {
      if (intent.state !== 'committed') {
        if (record.revision !== intent.record_revision || !open(record)) return failure('dispatch_canonical_revision_conflict');
        if (bookingRequiresLimousineCompanyConfirmation(record)) return failure('company_confirmation_required', 409);
        if (canonicalBookingAuthorityEnabled(env)) {
          const feasible = await validateReceiptCandidates(record, intent, event.owner_id, selectCandidate, validateSplitAssignments);
          if (!feasible.ok) {
            if (feasible.error === 'dispatch_pickup_overdue') {
              await preservePickupTimingAttention(env, event.owner_id, record, [feasible.attention_leg]);
              // This ACK has not become a customer assignment. Retire it only
              // after the newer unassigned canonical search is durable, so a
              // manager can reschedule instead of leaving a commit in limbo.
              const retried = await retryObsoleteReceipt(env, scope, event.owner_id, record, intent, null,
                { selectCandidate, validateSplitAssignments, publishAssignment });
              if (!retried.ok) return retried;
              const acknowledged = await callDispatchRoom(env, scope, 'dispatch-events', event);
              return acknowledged.ok ? { ok: true, revalidated: true, pickup_overdue: true } : acknowledged;
            }
            if (feasible.temporarily_unavailable) {
              // A race after preflight may already have a durable receipt.
              // Retain it only to its existing server-owned response deadline;
              // retire via the existing canonical refresh protocol, without
              // attributing a technical failure to the chauffeur.
              if (!Number.isFinite(event.ack_deadline_ms) || Date.now() < event.ack_deadline_ms) return feasible;
              const retired = await retryObsoleteReceipt(env, scope, event.owner_id, record, intent, null,
                { selectCandidate, validateSplitAssignments, publishAssignment, retirementReason: 'tracking_evidence_unavailable' });
              if (!retired.ok) return retired;
              const acknowledged = await callDispatchRoom(env, scope, 'dispatch-events', event);
              return acknowledged.ok ? { ok: true, technical_evidence_expired: true } : acknowledged;
            }
            if (!feasible.obsolete) return feasible;
            if (feasible.timing_candidate) record = await persistAsapWindow(env, event.owner_id, record, feasible.timing_candidate);
            const retried = await retryObsoleteReceipt(env, scope, event.owner_id, record, intent, feasible.failed_driver_id,
              { selectCandidate, validateSplitAssignments, publishAssignment });
            if (!retried.ok) return retried;
            const acknowledged = await callDispatchRoom(env, scope, 'dispatch-events', event);
            return acknowledged.ok ? { ok: true, revalidated: true } : acknowledged;
          }
        }
        const copy = structuredClone(record);
        const acceptedExecution = acceptedRideExecutionIdentities(intent, event, scope);
        if (!acceptedExecution.ok) return failure(acceptedExecution.error, 409);
        for (const assignment of intent.assignments || [{ leg: 'outbound', driver_id: intent.driver_id, vehicle_id: intent.vehicle_id }]) {
          applyAgendaLegAssignment(copy, { leg: assignment.leg, driverId: assignment.driver_id,
            vehicleId: assignment.vehicle_id, now: new Date().toISOString() });
        }
        const computed = agendaCapacityClaims(copy, event.owner_id);
        const expectedClaims = [...(intent.retained_claims || []), ...intent.claims];
        const comparable = claims => JSON.stringify([...claims].sort((a, b) => a.claim_id.localeCompare(b.claim_id)));
        if (!computed.ok || comparable(computed.claims) !== comparable(expectedClaims)) return failure('dispatch_canonical_window_changed');
        const scopes = stampTrackingAssignment(copy, intent.amendment ? { legs: intent.assignments.map(row => row.leg) } : {});
        delete copy.dispatch_amendment;
        copy.dispatch_capacity_checkpoint = { version: intent.version, claims: computed.claims };
        copy.dispatch_offer = { ...intent, state: 'committed', tracking_scopes: scopes,
          ...(acceptedExecution.identities ? { execution_identities: acceptedExecution.identities } : {}),
          ...(resolveRoundtripDispatchMode(copy) === 'split_no_wait' ? { tracking_assignment_versions: Object.fromEntries(
            copy.operational_legs.map(leg => [`${event.owner_id}:${leg.leg_type.toUpperCase()}`, Number(leg.customer_tracking_assignment_version) || 1])) } : {}),
          acknowledged_at: new Date().toISOString() };
        await env.BOOKING_KV.put(`booking:${event.owner_id}`, JSON.stringify(copy));
        Object.assign(record, copy);
      }
      const checkpoint = record.dispatch_capacity_checkpoint;
      const targetOwned = intent.amendment ? intent.assignments.every(assignment => record.operational_legs?.some(leg =>
        leg.leg_type === assignment.leg && leg.assigned_driver_id === assignment.driver_id && leg.assigned_vehicle_id === assignment.vehicle_id))
        : record.assigned_driver_id === event.driver_id && record.assigned_vehicle_id === event.vehicle_id;
      if (checkpoint?.version !== event.version || !targetOwned) return failure('dispatch_canonical_checkpoint_conflict');
      if (event.offer_state !== 'committed') {
        const confirmed = await commitCompanyCapacity(env, scope, { action: 'confirm', owner_id: event.owner_id,
          version: event.version, canonical_claims: checkpoint.claims });
        if (!confirmed.ok) return confirmed;
      }
      // The durable Room event stays unacknowledged on failure, so recovery
      // retries the same committed acceptance and its original timestamp.
      try { await recordFirstOperationalUse(env, scope, record, 'customer_booking_accepted', {bookingId:event.owner_id}); }
      catch (_) { return failure('trial_first_use_publication_pending'); }
      const published = await publishAssignment(event.owner_id, record, intent.tracking_scopes || record.dispatch_offer.tracking_scopes);
      if (!published?.ok) return failure(published?.error || 'dispatch_publication_incomplete');
    }
  } else if (event.type === 'redispatch' || event.type === 'dispatch_search') {
    if (ownsIntent && ['prepared', 'offered'].includes(intent.state) && open(record)) {
      let technicalExpiry = false;
      if (event.reason === 'ack_timeout') {
        // Expiry still releases the Room's soft hold at the original deadline.
        // A missing technical witness cannot establish chauffeur culpability.
        const live = await callDispatchRoom(env, scope, 'live');
        if (live.ok && (live.tenant_id !== scope.tenant_id || live.company_id !== scope.company_id))
          return failure('company_live_scope_invalid', 403);
        technicalExpiry = live.dependency_unavailable === true || live.status >= 500
          || live.ok && (live.capacity_contract_version !== 1 || live.dispatch_device_contract_version !== 1
            || !Array.isArray(live.capacity_reservations) || !Array.isArray(live.dispatch_devices)
            || !Array.isArray(live.drivers) || !Array.isArray(live.active_direct_rides));
        if (!live.ok && !technicalExpiry) return live;
      }
      record.dispatch_offer = { ...intent, state: 'cancelled',
        reason: technicalExpiry ? 'tracking_evidence_unavailable' : event.reason };
      if (intent.human_acceptance_required) record.vehicle_dispatch_attempts = [ ...(record.vehicle_dispatch_attempts || []),
        { offer_id: intent.offer_id, vehicle_id: intent.vehicle_id, driver_id: event.failed_driver_id || intent.driver_id,
          state: event.reason === 'driver_declined' ? 'declined' : 'expired',
          ...(technicalExpiry ? { reason: 'tracking_evidence_unavailable' } : {}) } ];
      record.revision = (Number(record.revision) || 1) + 1;
      if (!technicalExpiry) record.dispatch_exclusions = [...(record.dispatch_exclusions || []).filter(row => row.until_ms > Date.now()),
        { driver_id: event.failed_driver_id || event.driver_id, until_ms: Date.now() + 300_000 }].slice(-16);
      await env.BOOKING_KV.put(`booking:${event.owner_id}`, JSON.stringify(record));
    }
    if (open(record)) {
      if (intent?.human_acceptance_required && event.reason === 'ack_timeout'
        && record.vehicle_operating_policy_snapshot?.unanswered_offer === 'central') {
        const parked = await parkVehicleDispatchReview(env, event.owner_id, record,
          { policy: record.vehicle_operating_policy_snapshot }, 'offer_timed_out');
        if (!parked.ok) return parked;
      }
      const retried = await prepareCanonicalDispatchOffer(env, scope, event.owner_id, { selectCandidate, validateSplitAssignments, publishAssignment });
      if (!retried.ok) return retried;
      // Reusing this same search while no candidate exists is a retry, not
      // positive delivery. A different durable job/offer safely replaces it.
      if (retried.search_id === event.event_id && !retried.pickup_overdue && !retried.asap_search_expired) return failure('dispatch_search_pending');
    }
  } else return failure('dispatch_event_invalid', 400);
  const acknowledged = await callDispatchRoom(env, scope, 'dispatch-events', { ...event,
    ...(timingAttention ? {pickup_timing_attention:'pickup_overdue'} : {}) });
  return acknowledged.ok ? { ok: true, delivered: true } : acknowledged;
}
