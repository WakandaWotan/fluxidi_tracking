import { inspectLegacyOwnership, legacyScopeEvidenceDigest, validLegacyBookingId,
  unresolvedLegacyScopeTransition } from './legacy_scope_evidence.mjs';

const fail = (error, status = 409) => ({ ok: false, error, status });
const normalize = value => String(value || '').trim().toUpperCase().replace(/[ -]+/g, '_').replace(/^CANCELED$/, 'CANCELLED');
const lifecycleNames = ['status', 'stage', 'lifecycle_status', 'lifecycleStatus', 'booking_status', 'bookingStatus'];
const cancellationNames = ['cancelled_at', 'cancelledAt', 'canceled_at', 'canceledAt'];

// This narrow migration proves an existing whole-booking cancellation. It
// never interprets elapsed pickup time, a completed sibling or a missing GPS
// position as permission to cancel a trip. Active or ambiguous legs need a
// separate operator decision, including multi-leg return groups.
export async function prepareCancelledLegReconciliation(record, scope, bookingId) {
  if (!validLegacyBookingId(bookingId)) return fail('cancelled_leg_booking_invalid', 400);
  const ownership = inspectLegacyOwnership(record);
  if (ownership.invalid || ownership.conflicting || ownership.tenant_raw !== scope?.tenant_id
    || ownership.company_raw !== scope?.company_id) return fail('cancelled_leg_scope_conflict', 403);
  if (unresolvedLegacyScopeTransition(record, bookingId) || record.dispatch_capacity_checkpoint?.claims?.length) {
    return fail('cancelled_leg_transition_pending');
  }
  const containers = [record, record.booking].filter(Boolean);
  const stamps = [];
  for (const container of containers) {
    const statuses = lifecycleNames.filter(key => container[key] != null && container[key] !== '')
      .map(key => normalize(container[key]));
    if (!statuses.length || statuses.some(value => value !== 'CANCELLED')) return fail('cancelled_parent_proof_missing');
    for (const key of cancellationNames) {
      if (container[key] != null && container[key] !== '') stamps.push(Date.parse(container[key]));
    }
    // Reapplying the ordinary status flow must not trigger a provider calendar
    // cleanup. These records have no external event to remove.
    if (Object.entries(container).some(([key, value]) => /calendar|event_?id|eventId/.test(key)
      && value != null && value !== '' && value !== false)) return fail('cancelled_leg_calendar_review_required');
  }
  if (!stamps.length || stamps.some(value => !Number.isFinite(value) || value > Date.now() || value !== stamps[0])) {
    return fail('cancelled_parent_timestamp_conflict');
  }
  const modes = containers.flatMap(container => [container.roundtrip_dispatch_mode, container.roundtripDispatchMode])
    .filter(value => value != null && value !== '');
  if (!modes.length || modes.some(value => value !== 'single')
    || containers.some(container => container.return_enabled === true || container.returnEnabled === true)) {
    return fail('cancelled_leg_single_execution_required');
  }
  const arrays = containers.flatMap(container => ['operational_legs', 'operationalLegs']
    .filter(key => Object.hasOwn(container, key)).map(key => container[key]));
  if (!arrays.length || arrays.some(legs => !Array.isArray(legs) || legs.length !== 1)) {
    return fail('cancelled_leg_shape_conflict');
  }
  let legId = '', alreadyReconciled = true;
  for (const legs of arrays) {
    const leg = legs[0], id = leg?.leg_id ?? leg?.legId;
    if (!leg || typeof leg !== 'object' || Array.isArray(leg) || typeof id !== 'string'
      || !id || id.length > 200 || (legId && id !== legId)
      || leg.leg_id && leg.legId && leg.leg_id !== leg.legId
      || String(leg.leg_type ?? leg.legType).toLowerCase() !== 'outbound') return fail('cancelled_leg_shape_conflict');
    if (leg.started_at || leg.startedAt || leg.dispatch_activity_id || leg.dispatchActivityId
      || leg.active === true) return fail('cancelled_leg_active_or_ambiguous');
    for (const key of cancellationNames) {
      if (leg[key] != null && leg[key] !== '' && Date.parse(leg[key]) !== stamps[0]) {
        return fail('cancelled_leg_timestamp_conflict');
      }
    }
    legId = id;
    const statuses = lifecycleNames.filter(key => leg[key] != null && leg[key] !== '')
      .map(key => normalize(leg[key]));
    if (!statuses.length || statuses.some(value => !['PENDING', 'CANCELLED'].includes(value))) {
      return fail('cancelled_leg_active_or_ambiguous');
    }
    if (statuses.some(value => value !== statuses[0])) return fail('cancelled_leg_lifecycle_conflict');
    if (statuses[0] !== 'CANCELLED') alreadyReconciled = false;
  }
  return { ok: true, booking_id: bookingId, leg_id: legId,
    reconciliation_digest: await legacyScopeEvidenceDigest({ scope, bookingId, record }),
    cancellation_at: new Date(stamps[0]).toISOString(), already_reconciled: alreadyReconciled };
}

export function cancelledLegReviewMatches(record, prepared, reviewDigest) {
  if (typeof reviewDigest !== 'string' || !/^[a-f0-9]{64}$/.test(reviewDigest)) return false;
  if (reviewDigest === prepared.reconciliation_digest) return true;
  const previous = record?.cancelled_leg_reconciliation;
  return prepared.already_reconciled && previous?.review_digest === reviewDigest
    && previous.leg_id === prepared.leg_id && previous.cancellation_at === prepared.cancellation_at;
}
