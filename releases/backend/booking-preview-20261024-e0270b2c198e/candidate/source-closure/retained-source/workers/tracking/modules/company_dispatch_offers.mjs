import { driverDispatchDevices, dispatchDeviceDeadline } from './dispatch_device_capability.mjs';
import { capacityClaimDecision, sameCapacityResource } from './company_capacity_ledger.mjs';
import { amendmentBaseMatches, holdAmendmentClaims, promoteAmendmentClaims, rollbackAmendmentPromotion } from './company_dispatch_amendment.mjs';

// Native duty heartbeats currently run every 90 seconds. The background lease
// includes one heartbeat, its bounded request and delivery jitter. A shorter
// deadline is allowed only when the caller has a live delivery channel.
export const DISPATCH_ACK_TIMEOUT_MS = 150_000;
export const DISPATCH_POSITION_TTL_MS = 180_000;
const PROVISIONAL = new Set(['offered', 'received']);
const fail = (error, status = 409) => ({ ok: false, error, status });
const scopeMatches = (row, input) => row?.tenant_id === input.tenant_id && row?.company_id === input.company_id;

export function dispatchOfferResources(offer) {
  const pairs = new Map();
  for (const claim of offer.claims || []) pairs.set(`${claim.driver_id}\n${claim.vehicle_id}`,
    { driver_id: claim.driver_id, vehicle_id: claim.vehicle_id });
  return [...pairs.values()];
}
const touches = (offer, row) => dispatchOfferResources(offer).some(resource => sameCapacityResource(resource, row));
const prerequisites = offer => offer.prerequisites || (offer.prerequisite_claim_id
  ? [{ claim_id: offer.prerequisite_claim_id, version: offer.prerequisite_version,
    driver_id: offer.driver_id, vehicle_id: offer.vehicle_id }] : []);
function resourceFresh(offer, drivers, dispatchDevices, nowMs) {
  for (const resource of dispatchOfferResources(offer)) {
    const position = drivers[resource.driver_id];
    if (!scopeMatches(position, offer) || position.vehicle_id !== resource.vehicle_id
      || !freshDispatchPosition(position, nowMs)) return { reason: 'location_stale', driver_id: resource.driver_id };
    if (!driverDispatchDevices(dispatchDevices, offer, resource.driver_id, nowMs).length) return { reason: 'device_unavailable', driver_id: resource.driver_id };
  }
  return null;
}

// A search has no guessed driver, car or capacity claim. It is retained until
// Booking positively creates a replacement offer or closes the booking.
export function dispatchSearchDecision(ledger, input, nowMs) {
  if (!input.tenant_id || !input.company_id || typeof input.owner_id !== 'string'
    || !input.owner_id.trim() || input.owner_id.length > 160 || !Number.isSafeInteger(input.version)
    || input.version < 1 || !Number.isFinite(nowMs)) return fail('dispatch_search_invalid', 400);
  const eventId = `search:${input.owner_id}:${input.version}`;
  const existing = ledger.dispatch_events?.[eventId];
  if (existing) return scopeMatches(existing, input)
    ? { ok: true, ledger, event: existing } : fail('dispatch_event_conflict');
  if (input.amendment === true ? !amendmentBaseMatches(ledger, input)
    : ledger.owners[input.owner_id] && !ledger.owners[input.owner_id].released
      || Object.values(ledger.claims).some(claim => claim.owner_id === input.owner_id)) return fail('dispatch_search_hard_assignment');
  const event = { ...input, event_id: eventId, offer_id: eventId, type: 'dispatch_search',
    state: 'pending', reason: 'no_candidate', created_at_ms: nowMs };
  return { ok: true, event, ledger: { ...ledger, dispatch_events: { ...ledger.dispatch_events, [eventId]: event } } };
}

export function freshDispatchPosition(row, nowMs) {
  if (!row) return false;
  const captured = Date.parse(row.position_captured_at || row.captured_at || '');
  const seen = Date.parse(row.last_seen_at || '');
  const lat = row.latitude, lng = row.longitude;
  return Number.isFinite(lat) && Number.isFinite(lng) && Math.abs(lat) <= 90 && Math.abs(lng) <= 180
    && !(lat === 0 && lng === 0) && row.reliable_for_eta !== false && row.stale !== true
    && [captured, seen].every(at => Number.isFinite(at) && nowMs - at <= DISPATCH_POSITION_TTL_MS && at - nowMs <= 120_000);
}

function cancellation(ledger, offer, reason, nowMs, failedDriverId = offer.driver_id) {
  const claims = Object.fromEntries(Object.entries(ledger.claims).filter(([, claim]) =>
    !(claim.owner_id === offer.owner_id && claim.offer_id === offer.offer_id)));
  const eventId = `${offer.offer_id}:${reason}`;
  return { ...ledger, claims, owners: { ...ledger.owners,
    [offer.owner_id]: offer.amendment ? ledger.owners[offer.owner_id]
      : { ...ledger.owners[offer.owner_id], released: true, pending: false } },
    offers: { ...ledger.offers, [offer.offer_id]: { ...offer, state: reason === 'ack_timeout' ? 'expired' : 'cancelled',
      reason, ended_at_ms: nowMs } },
    dispatch_events: { ...ledger.dispatch_events, [eventId]: {
      event_id: eventId, type: 'redispatch', ...offer, state: 'pending', reason, created_at_ms: nowMs,
      failed_driver_id: failedDriverId,
    } } };
}

// The outbox and released soft capacity are one durable Room write. Booking KV
// repair is acknowledged separately; an interrupted bridge cannot lose a ride.
export function expireDispatchOffers(ledger, nowMs) {
  let next = ledger;
  for (const offer of Object.values(ledger.offers || {})) {
    if (PROVISIONAL.has(offer.state) && offer.ack_deadline_ms <= nowMs) {
      const missing = dispatchOfferResources(offer).find(resource => !offer.receipts?.[resource.driver_id]?.ready);
      next = cancellation(next, offer, 'ack_timeout', nowMs, missing?.driver_id || offer.driver_id);
    }
  }
  return next;
}

export function preemptOwnerAmendments(ledger, input, nowMs) {
  let next = ledger;
  for (const offer of Object.values(ledger.offers || {})) {
    if (offer.amendment && offer.owner_id === input.owner_id && scopeMatches(offer, input)
      && PROVISIONAL.has(offer.state) && ['reserve', 'activate', 'release'].includes(input.action)) {
      next = cancellation(next, offer, 'canonical_changed', nowMs);
    }
  }
  return next;
}

export function preemptDispatchOffers(ledger, street, nowMs) {
  let next = ledger;
  for (const offer of Object.values(ledger.offers || {})) {
    if (!scopeMatches(offer, street) || !PROVISIONAL.has(offer.state)) continue;
    if (touches(offer, street)) next = cancellation(next, offer, 'street_hail', nowMs, street.driver_id);
  }
  return next;
}

export function revalidateDispatchOffers(ledger, drivers, nowMs, dispatchDevices) {
  let next = expireDispatchOffers(ledger, nowMs);
  for (const offer of Object.values(next.offers || {})) {
    if (!PROVISIONAL.has(offer.state)) continue;
    const stale = resourceFresh(offer, drivers, dispatchDevices, nowMs);
    let reason = offer.amendment && !amendmentBaseMatches(next, offer) ? 'canonical_changed' : stale?.reason;
    let failedDriverId = stale?.driver_id;
    for (const required of prerequisites(offer)) {
      const prior = next.claims[required.claim_id];
      if (!reason && prior && next.owners[prior.owner_id]?.version !== required.version) {
        reason = 'destination_changed'; failedDriverId = required.driver_id;
      }
      const start = Math.min(...offer.claims.filter(claim => sameCapacityResource(claim, required)).map(claim => claim.start_ms));
      if (!reason && prior && prior.end_ms > start) { reason = 'forecast_late'; failedDriverId = required.driver_id; }
    }
    if (reason) next = cancellation(next, offer, reason, nowMs, failedDriverId || offer.driver_id);
  }
  return next;
}

// A change to the preceding hard reservation supersedes its prediction. Revoke
// its provisional successor in the same write as the new canonical capacity.
export function preemptPrerequisiteOffers(ledger, input, nowMs) {
  if (!['reserve', 'activate'].includes(input.action)) return ledger;
  let next = ledger;
  for (const offer of Object.values(ledger.offers || {})) {
    if (PROVISIONAL.has(offer.state) && scopeMatches(offer, input) && prerequisites(offer).some(required =>
      ledger.claims[required.claim_id]?.owner_id === input.owner_id && required.version !== input.version)) {
      const changed = prerequisites(offer).find(required => ledger.claims[required.claim_id]?.owner_id === input.owner_id);
      next = cancellation(next, offer, 'destination_changed', nowMs, changed?.driver_id || offer.driver_id);
    }
  }
  return next;
}

export function dispatchOfferDecision(ledger, input, { nowMs, directRides = [], driverPosition, drivers = {}, dispatchDevices } = {}) {
  if (!Number.isFinite(nowMs) || !input.tenant_id || !input.company_id
    || typeof input.offer_id !== 'string' || !input.offer_id.trim() || input.offer_id.length > 200
    || !Number.isInteger(input.version) || input.version < 1) return fail('dispatch_offer_invalid', 400);
  if (input.prerequisites != null && (!Array.isArray(input.prerequisites) || input.prerequisites.length > 2
    || input.prerequisites.some(row => !row || typeof row.claim_id !== 'string' || !row.claim_id
      || !Number.isSafeInteger(row.version) || row.version < 1 || !row.driver_id || !row.vehicle_id)
    || new Set(input.prerequisites.map(row => row.claim_id)).size !== input.prerequisites.length)) {
    return fail('dispatch_prerequisite_invalid', 400);
  }
  const current = ledger.offers?.[input.offer_id];
  if (current && (!scopeMatches(current, input) || current.version !== input.version
    || current.owner_id !== input.owner_id || (['ack', 'accept', 'decline'].includes(input.action)
      ? !dispatchOfferResources(current).some(resource => resource.driver_id === input.driver_id && resource.vehicle_id === input.vehicle_id)
      : current.driver_id !== input.driver_id || current.vehicle_id !== input.vehicle_id))) return fail('dispatch_offer_conflict');
  const next = expireDispatchOffers(ledger, nowMs);
  const offer = next.offers?.[input.offer_id];
  if (input.action === 'refresh' && offer?.amendment) {
    const proof = input.canonical_resolution;
    if (offer.state === 'aborted') return { ok: true, ledger: next, offer };
    if (proof?.offer_id !== offer.offer_id || proof.version !== offer.version || proof.reason !== 'canonical_changed'
      || proof.unassigned !== true || !Number.isSafeInteger(proof.record_canonical_version)
      || proof.record_canonical_version <= offer.record_canonical_version
      || !['offered', 'received', 'committing', 'cancelled', 'expired'].includes(offer.state)) return fail('dispatch_refresh_unconfirmed');
    const rolled = offer.state === 'committing' ? rollbackAmendmentPromotion(next, offer, proof, directRides)
      : { ok: true, ledger: next };
    if (!rolled.ok) return rolled;
    const cancelled = cancellation({ ...next, ...rolled.ledger }, offer, 'canonical_changed', nowMs);
    const aborted = { ...offer, state: 'aborted', reason: 'canonical_changed', ended_at_ms: nowMs };
    return { ok: true, offer: aborted, ledger: { ...cancelled,
      offers: { ...cancelled.offers, [offer.offer_id]: aborted } } };
  }
  if (input.action === 'refresh') {
    const proof = input.canonical_resolution;
    if (offer?.state === 'aborted') return { ok: true, ledger: next, offer };
    if (proof?.offer_id !== input.offer_id || proof?.version !== input.version
      || proof?.reason !== 'canonical_changed' || proof.unassigned !== true
      || !Number.isSafeInteger(proof.record_canonical_version)
      || !Number.isSafeInteger(input.record_canonical_version) || input.record_canonical_version < 1
      || proof.record_canonical_version <= input.record_canonical_version
      || offer && (offer.record_canonical_version !== input.record_canonical_version
        || !['offered', 'received', 'committing', 'cancelled', 'expired'].includes(offer.state))
      || Object.values(next.claims).some(claim => claim.owner_id === input.owner_id
        && (!offer || claim.offer_id !== offer.offer_id))) return fail('dispatch_refresh_unconfirmed');
    if (!offer) return { ok: true, ledger: next };
    const owner = next.owners[offer.owner_id];
    if (owner?.version !== offer.version) return fail('dispatch_refresh_unconfirmed');
    const claims = Object.fromEntries(Object.entries(next.claims).filter(([, claim]) =>
      !(claim.owner_id === offer.owner_id && claim.offer_id === offer.offer_id)));
    const aborted = { ...offer, state: 'aborted', reason: 'canonical_changed', ended_at_ms: nowMs };
    return { ok: true, offer: aborted, ledger: { ...next, claims,
      owners: { ...next.owners, [offer.owner_id]: { ...owner, pending: false, released: true } },
      offers: { ...next.offers, [offer.offer_id]: aborted } } };
  }
  if (input.action === 'defer') {
    if (offer) return offer.state === 'cancelled' && offer.reason === 'candidate_unavailable'
      ? { ok: true, ledger: next, offer } : fail('dispatch_offer_conflict');
    if (input.amendment === true ? !amendmentBaseMatches(next, input)
      : next.owners[input.owner_id] && (!next.owners[input.owner_id].released || next.owners[input.owner_id].version >= input.version)
        || Object.values(next.claims).some(claim => claim.owner_id === input.owner_id)) return fail('dispatch_offer_hard_assignment');
    const checked = capacityClaimDecision({ claims: {}, owners: {} }, { ...input, action: 'reserve' }, []);
    if (!checked.ok || !input.driver_id || !input.vehicle_id || ![1, 2].includes(input.claims.length)) return fail('dispatch_offer_invalid', 400);
    const deferred = { tenant_id: input.tenant_id, company_id: input.company_id,
      offer_id: input.offer_id, owner_id: input.owner_id, version: input.version,
      driver_id: input.driver_id, vehicle_id: input.vehicle_id, claims: input.claims,
      ...(input.amendment ? { amendment: true, base_version: input.base_version, retained_claims: input.retained_claims } : {}),
      created_at_ms: nowMs, state: 'offered' };
    const released = cancellation({ ...next, owners: { ...next.owners,
      [input.owner_id]: input.amendment ? next.owners[input.owner_id] : checked.ledger.owners[input.owner_id] } }, deferred, 'candidate_unavailable', nowMs);
    return { ok: true, ledger: released, offer: released.offers[input.offer_id] };
  }
  if (input.action === 'offer') {
    const asapDeadline = input.asap_search_expires_ms;
    if (asapDeadline != null && (!Number.isSafeInteger(asapDeadline)
      || !Number.isSafeInteger(input.asap_requested_ms) || input.asap_requested_ms > nowMs
      || asapDeadline !== input.asap_requested_ms + 600_000)) return fail('dispatch_asap_deadline_invalid', 400);
    if (asapDeadline != null && asapDeadline <= nowMs && (!offer || PROVISIONAL.has(offer.state))) {
      return fail('asap_search_expired');
    }
    const timeout = input.ack_timeout_ms ?? DISPATCH_ACK_TIMEOUT_MS;
    if (input.response_starts_on_display === true && (input.human_acceptance_required !== true
      || input.claims?.length !== 1)) return fail('dispatch_delivery_invalid', 400);
    if (input.human_acceptance_required === true
      ? !Number.isSafeInteger(timeout) || timeout <= 0 || !Number.isSafeInteger(nowMs + timeout)
      : !Number.isInteger(timeout) || timeout < 30_000 || timeout > 180_000
        || timeout < DISPATCH_ACK_TIMEOUT_MS && input.delivery_mode !== 'live') return fail('dispatch_delivery_invalid', 400);
    if (offer) {
      if (!PROVISIONAL.has(offer.state) && !['committing', 'committed'].includes(offer.state)) return fail('dispatch_offer_closed');
      if (JSON.stringify(prerequisites(offer)) !== JSON.stringify(prerequisites(input))
        || offer.asap_search_expires_ms !== input.asap_search_expires_ms
        || offer.asap_requested_ms !== input.asap_requested_ms
        || JSON.stringify(offer.claims) !== JSON.stringify(input.claims)
        || offer.prerequisite_claim_id !== (input.prerequisite_claim_id || null)
        || offer.prerequisite_version !== (input.prerequisite_version ?? null)
        || offer.ack_timeout_ms !== timeout || Boolean(offer.amendment) !== Boolean(input.amendment)
        || Boolean(offer.human_acceptance_required) !== Boolean(input.human_acceptance_required)
        || Boolean(offer.response_starts_on_display) !== Boolean(input.response_starts_on_display)
        || offer.amendment && (offer.base_version !== input.base_version
          || JSON.stringify(offer.retained_claims) !== JSON.stringify(input.retained_claims))) return fail('dispatch_offer_conflict');
      return { ok: true, ledger: next, offer };
    }
    if (Object.values(next.offers || {}).some(row => row.owner_id === input.owner_id
      && ['offered', 'received', 'committing'].includes(row.state))) return fail('dispatch_offer_pending');
    // Never downgrade a hard reservation or a canonical-write checkpoint to a
    // revocable offer. This API is for unassigned canonical bookings only.
    if (!input.amendment && Object.values(next.claims).some(claim => claim.owner_id === input.owner_id)) return fail('dispatch_offer_hard_assignment');
    if (typeof input.driver_id !== 'string' || !input.driver_id || typeof input.vehicle_id !== 'string' || !input.vehicle_id
      || !Array.isArray(input.claims) || ![1, 2].includes(input.claims.length)
      || input.claims.some(claim => !claim.driver_id || !claim.vehicle_id || claim.active)
      || input.claims[0].driver_id !== input.driver_id || input.claims[0].vehicle_id !== input.vehicle_id
      || new Set(input.claims.map(claim => claim.claim_id)).size !== input.claims.length) {
      return fail('dispatch_offer_invalid', 400);
    }
    const positions = { ...drivers, ...(driverPosition ? { [input.driver_id]: driverPosition } : {}) };
    const freshness = resourceFresh(input, positions, dispatchDevices, nowMs);
    if (freshness) return fail(freshness.reason === 'device_unavailable' ? 'dispatch_device_unavailable' : 'dispatch_offer_location_stale');
    const held = input.amendment ? holdAmendmentClaims(next, input, directRides)
      : capacityClaimDecision(next, { ...input, action: 'reserve', replace_owner: false }, directRides);
    if (!held.ok) return held;
    const created = { tenant_id: input.tenant_id, company_id: input.company_id,
      offer_id: input.offer_id, owner_id: input.owner_id, version: input.version,
      driver_id: input.driver_id, vehicle_id: input.vehicle_id, claims: input.claims,
      ...(input.human_acceptance_required === true ? { human_acceptance_required: true } : {}),
      ...(input.response_starts_on_display === true ? { response_starts_on_display: true } : {}),
      prerequisite_claim_id: input.prerequisite_claim_id || null,
      prerequisite_version: input.prerequisite_version ?? null,
      ...(input.record_canonical_version ? { record_canonical_version: input.record_canonical_version,
        record_revision: input.record_revision, record_dispatch_basis: input.record_dispatch_basis } : {}),
      ...(input.prerequisites ? { prerequisites: input.prerequisites } : {}),
      ...(asapDeadline != null ? { asap_requested_ms: input.asap_requested_ms, asap_search_expires_ms: asapDeadline } : {}),
      ...(input.amendment ? { amendment: true, base_version: input.base_version, retained_claims: input.retained_claims } : {}),
      state: 'offered', created_at_ms: nowMs, ack_timeout_ms: timeout,
      ack_deadline_ms: Math.min(nowMs + (input.response_starts_on_display === true ? DISPATCH_ACK_TIMEOUT_MS : timeout), asapDeadline ?? Infinity) };
    for (const required of prerequisites(created)) {
      const prior = next.claims[required.claim_id];
      if (!prior?.active || prior.driver_id !== required.driver_id || prior.vehicle_id !== required.vehicle_id
        || !scopeMatches(prior, input) || next.owners[prior.owner_id]?.version !== required.version
        || !dispatchOfferResources(created).some(resource => sameCapacityResource(resource, required))) {
        return fail('dispatch_prerequisite_conflict');
      }
    }
    const claims = { ...held.ledger.claims };
    for (const claim of created.claims) claims[claim.claim_id] = { ...claims[claim.claim_id], offer_id: created.offer_id };
    return { ok: true, offer: created, ledger: { ...next, ...held.ledger, claims,
      offers: { ...next.offers, [created.offer_id]: created } } };
  }
  if (!offer) return fail('dispatch_offer_missing', 404);
  if (input.action === 'supersede') {
    const owner = next.owners[offer.owner_id];
    if (offer.state === 'superseded') return { ok: true, ledger: next, offer };
    if (!['committed', 'cancelled'].includes(offer.state) || !owner || owner.version <= offer.version || owner.pending
      || input.canonical_version !== owner.version
      || Object.values(next.claims).some(claim => claim.owner_id === offer.owner_id && claim.offer_id === offer.offer_id)) {
      return fail('dispatch_superseded_unconfirmed');
    }
    const superseded = { ...offer, state: 'superseded', reason: 'canonical_reassignment', ended_at_ms: nowMs };
    return { ok: true, offer: superseded, ledger: { ...next, offers: { ...next.offers, [offer.offer_id]: superseded } } };
  }
  if (input.action === 'abort') {
    const proof = input.canonical_resolution;
    if (offer.state === 'aborted') return { ok: true, ledger: next, offer };
    if (!['committing', 'committed'].includes(offer.state) && !(offer.state === 'cancelled' && offer.reason === 'canonical_release')
      || Object.values(next.claims).some(claim => claim.owner_id === offer.owner_id && claim.offer_id !== offer.offer_id)
      || proof?.offer_id !== offer.offer_id || proof?.version !== offer.version
      || !Number.isInteger(proof.record_revision) || proof.record_revision < offer.version - 1
      || proof.reason !== 'terminal' || !['COMPLETED', 'CANCELLED', 'CANCELED', 'NO_SHOW', 'REJECTED', 'EXPIRED']
        .includes(String(proof.status || '').toUpperCase())) return fail('dispatch_abort_unconfirmed');
    const claims = Object.fromEntries(Object.entries(next.claims).filter(([, claim]) =>
      !(claim.owner_id === offer.owner_id && claim.offer_id === offer.offer_id)));
    const aborted = { ...offer, state: 'aborted', reason: 'canonical_terminal', ended_at_ms: nowMs };
    return { ok: true, offer: aborted, ledger: { ...next, claims,
      owners: { ...next.owners, [offer.owner_id]: { ...next.owners[offer.owner_id], pending: false, released: true } },
      offers: { ...next.offers, [offer.offer_id]: aborted } } };
  }
  if (input.action === 'revoke') {
    if (!PROVISIONAL.has(offer.state)) return fail('dispatch_offer_hard_assignment');
    const reason = ['destination_changed', 'forecast_late', 'location_stale', 'driver_declined'].includes(input.reason)
      ? input.reason : 'revalidation_failed';
    return { ok: true, ledger: cancellation(next, offer, reason, nowMs), offer: { ...offer, state: 'cancelled' } };
  }
  if (input.action === 'decline') {
    if (!offer.human_acceptance_required || !PROVISIONAL.has(offer.state)) return fail('dispatch_offer_closed');
    return { ok: true, ledger: cancellation(next, offer, 'driver_declined', nowMs, input.driver_id), offer: { ...offer, state: 'cancelled' } };
  }
  if (!['ack', 'accept'].includes(input.action)) return fail('dispatch_offer_invalid', 400);
  if (input.action === 'accept' && (!offer.human_acceptance_required || !input.execution_identity
    || input.execution_identity.driver_id !== input.driver_id || input.execution_identity.vehicle_id !== input.vehicle_id
    || !scopeMatches(input.execution_identity, input))) return fail('dispatch_human_acceptance_required');
  if (!['offered', 'received', 'committing', 'committed'].includes(offer.state)) return fail('dispatch_offer_closed');
  if (['committing', 'committed'].includes(offer.state)) return { ok: true, ledger: next, offer };
  if (!scopeMatches(driverPosition, input) || driverPosition.driver_id !== input.driver_id
    || driverPosition.vehicle_id !== input.vehicle_id || !freshDispatchPosition(driverPosition, nowMs)) return fail('dispatch_offer_location_stale');
  if (!input.device_key || !driverDispatchDevices(dispatchDevices, input, input.driver_id, nowMs, input.device_key).length) return fail('dispatch_device_unavailable');
  if (directRides.some(ride => scopeMatches(ride, input) && touches(offer, ride))) return fail('dispatch_driver_busy');
  const required = prerequisites(offer).filter(row => row.driver_id === input.driver_id);
  const prior = required.map(row => ({ row, claim: next.claims[row.claim_id] })).filter(pair => pair.claim);
  if (prior.some(({ row, claim }) => !claim.active || next.owners[claim.owner_id]?.version !== row.version
    || !scopeMatches(claim, input) || !sameCapacityResource(claim, input))) return fail('dispatch_prerequisite_conflict');
  const previousReceipt = offer.receipts?.[input.driver_id];
  const firstDisplay = offer.response_starts_on_display === true && previousReceipt?.displayed_at_ms == null;
  const displayedAt = firstDisplay ? nowMs : previousReceipt?.displayed_at_ms;
  const accepted = input.action === 'accept' || previousReceipt?.accepted === true;
  const receipts = { ...offer.receipts, [input.driver_id]: { at_ms: nowMs,
    ready: prior.length === 0 && (!offer.human_acceptance_required || accepted),
    ...(offer.human_acceptance_required ? { accepted,
      ...(offer.response_starts_on_display === true ? { displayed_at_ms: displayedAt } : {}),
      ...(input.action === 'accept' ? { execution_identity: input.execution_identity } : previousReceipt?.execution_identity ? { execution_identity: previousReceipt.execution_identity } : {}) } : {}) } };
  const resources = dispatchOfferResources(offer);
  const received = { ...offer, receipts, state: 'received', acknowledged_at_ms: offer.acknowledged_at_ms || nowMs,
    ...(firstDisplay ? { ack_deadline_ms: Math.min(nowMs + offer.ack_timeout_ms, offer.asap_search_expires_ms ?? Infinity) } : {}) };
  if (!resources.every(resource => receipts[resource.driver_id]?.ready === true)) {
    return { ok: true, ledger: { ...next, offers: { ...next.offers, [offer.offer_id]: received } }, offer: received };
  }
  if (Object.values(next.claims).some(claim => claim.owner_id !== offer.owner_id && claim.active
    && scopeMatches(claim, input) && touches(offer, claim))) return fail('dispatch_driver_busy');
  const freshness = resourceFresh(offer, { ...drivers, ...(driverPosition ? { [input.driver_id]: driverPosition } : {}) }, dispatchDevices, nowMs);
  if (freshness) return fail(freshness.reason === 'device_unavailable' ? 'dispatch_device_unavailable' : 'dispatch_offer_location_stale');
  const promoted = offer.amendment ? promoteAmendmentClaims(next, offer, directRides) : { ok: true, ledger: next };
  if (!promoted.ok) return promoted;
  const committedClaims = { ...promoted.ledger.claims };
  for (const claim of offer.claims) committedClaims[claim.claim_id] = { ...committedClaims[claim.claim_id], offer_id: offer.offer_id };
  const committing = { ...received, state: 'committing' };
  const eventId = `${offer.offer_id}:commit`;
  return { ok: true, offer: committing, ledger: { ...next,
    claims: committedClaims,
    owners: { ...promoted.ledger.owners, [offer.owner_id]: { ...promoted.ledger.owners[offer.owner_id], pending: true } },
    offers: { ...next.offers, [offer.offer_id]: committing },
    dispatch_events: { ...next.dispatch_events, [eventId]: { ...committing,
      event_id: eventId, type: 'assignment_commit', state: 'pending', created_at_ms: nowMs } } } };
}

// Only unstarted automatic legs are candidates for revalidation. A sibling
// START/completion may advance the owner version. Booking independently checks
// the original per-leg assignment generation before removing any assignment.
const CONFIRMED_RECHECK_MS = 60_000;
const CONFIRMED_RECHECK_HORIZON_MS = 15 * 60_000;
function monitoredClaims(ledger, offer) {
  const owner = ledger.owners[offer.owner_id];
  const split = offer.claims?.every(claim => ['OUTBOUND', 'RETURN'].some(type => claim.claim_id === `${offer.owner_id}:${type}`));
  if (offer.state !== 'committed' || offer.revalidation_paused_reason === 'pickup_overdue' || !Number.isSafeInteger(offer.record_canonical_version)
    || offer.record_canonical_version < 1 || !Number.isSafeInteger(offer.version)
    || !Number.isSafeInteger(owner?.version) || owner.version < offer.version
    || !scopeMatches(owner, offer) || owner.pending || owner.released
    || !split && owner.version !== offer.version) return [];
  return (offer.claims || []).filter(claim => {
    const held = ledger.claims[claim.claim_id];
    return held?.owner_id === offer.owner_id && scopeMatches(held, offer) && (split || held.offer_id === offer.offer_id)
      && held.driver_id === claim.driver_id && held.vehicle_id === claim.vehicle_id
      && held.start_ms === claim.start_ms && held.end_ms === claim.end_ms
      && Number.isFinite(claim.start_ms) && Number.isFinite(claim.end_ms) && !held.active && !held.retiring;
  });
}
function confirmedAssignments(ledger) {
  return Object.values(ledger.offers || {}).filter(offer => monitoredClaims(ledger, offer).length);
}
function confirmedRecheckAt(offer, ledger) {
  return Math.max(Math.min(...monitoredClaims(ledger, offer).map(claim => claim.start_ms)) - CONFIRMED_RECHECK_HORIZON_MS,
    (offer.last_revalidated_at_ms || 0) + CONFIRMED_RECHECK_MS);
}

export function queueConfirmedSuccessorChecks(ledger, nowMs, changed = null) {
  let next = ledger;
  for (const offer of confirmedAssignments(ledger)) {
    const eventId = `${offer.offer_id}:revalidate`;
    const previous = next.dispatch_events?.[eventId];
    const affected = changed && monitoredClaims(next, offer)
      .some(claim => changed.resources.some(resource => scopeMatches(resource, offer) && resource.claim_id !== claim.claim_id
        && sameCapacityResource(claim, resource)));
    if (changed && !affected || previous?.state === 'pending' || !affected && confirmedRecheckAt(offer, next) > nowMs) continue;
    // One reusable job per assignment, not an ever-growing event per GPS ping.
    const event = { ...offer, event_id: eventId, type: 'assignment_revalidate', state: 'pending',
      revalidation_claim_ids: monitoredClaims(next, offer).map(claim => claim.claim_id),
      event_generation: (previous?.event_generation || 0) + 1, created_at_ms: nowMs };
    next = { ...next, dispatch_events: { ...next.dispatch_events, [eventId]: event } };
  }
  return next;
}

export function acknowledgeDispatchEvent(ledger, input) {
  const event = ledger.dispatch_events?.[input.event_id];
  if (!event || !scopeMatches(event, input) || event.offer_id !== input.offer_id
    || event.version !== input.version || event.owner_id !== input.owner_id) return fail('dispatch_event_conflict');
  const offer = ledger.offers?.[event.offer_id];
  if (event.type === 'assignment_commit' && !['committed', 'aborted', 'superseded'].includes(offer?.state)) return fail('dispatch_commit_unconfirmed');
  if (event.type === 'assignment_revalidate' && input.event_generation !== event.event_generation) return fail('dispatch_event_conflict');
  return { ok: true, ledger: { ...ledger,
    ...(event.type === 'assignment_revalidate' && offer ? { offers: { ...ledger.offers,
      [offer.offer_id]: { ...offer, last_revalidated_at_ms: event.created_at_ms,
        ...(input.pickup_timing_attention === 'pickup_overdue' ? { revalidation_paused_reason:'pickup_overdue' } : {}) } } } : {}),
    dispatch_events: { ...ledger.dispatch_events,
    [event.event_id]: { ...event, state: 'delivered' } } } };
}

export function nextDispatchAlarm(ledger, drivers = {}, dispatchDevices) {
  const deadlines = Object.values(ledger.offers || {}).filter(offer => PROVISIONAL.has(offer.state)).flatMap(offer => {
    return [offer.ack_deadline_ms, ...dispatchOfferResources(offer).flatMap(resource => {
      const position = drivers[resource.driver_id];
      const deviceEnd = dispatchDeviceDeadline(dispatchDevices, offer, resource.driver_id, Date.now());
      return [...(deviceEnd == null ? [] : [deviceEnd + 1]), ...[position?.position_captured_at || position?.captured_at, position?.last_seen_at]
        .map(value => Date.parse(value || '') + DISPATCH_POSITION_TTL_MS + 1).filter(Number.isFinite)];
    })];
  });
  deadlines.push(...confirmedAssignments(ledger).filter(offer =>
    ledger.dispatch_events?.[`${offer.offer_id}:revalidate`]?.state !== 'pending')
    .map(offer => Math.max(Date.now() + 1, confirmedRecheckAt(offer, ledger))));
  return deadlines.length ? Math.min(...deadlines) : null;
}
