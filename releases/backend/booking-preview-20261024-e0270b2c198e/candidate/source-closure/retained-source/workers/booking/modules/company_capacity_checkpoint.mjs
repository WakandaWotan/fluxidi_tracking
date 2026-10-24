import { agendaCapacityClaims } from './company_agenda.mjs';
import { canonicalBookingAuthorityEnabled } from './canonical_booking_authority.mjs';
import { operationalLegsOf, resolveRoundtripDispatchMode } from './company_roundtrip.mjs';
import { companyTrackingObjectName } from '../../tracking/modules/company_tracking_room.mjs';
import { comparableDispatchClaim } from '../../tracking/modules/company_dispatch_amendment.mjs';

const failure = (error, status = 409) => ({ ok: false, error, status });
const sameScope = (record, scope) => record?.tenant_id === scope?.tenant_id && record?.company_id === scope?.company_id;
export const sameCheckpointClaims = (left, right) => Array.isArray(left) && Array.isArray(right)
  && left.every(claim => claim && typeof claim === 'object' && !Array.isArray(claim))
  && right.every(claim => claim && typeof claim === 'object' && !Array.isArray(claim))
  && JSON.stringify(left.map(comparableDispatchClaim).sort()) === JSON.stringify(right.map(comparableDispatchClaim).sort());

// A split legacy record may inherit a resource from its parent. That is useful
// for conservative occupancy, but cannot prove an individually assigned leg.
function explicitSplitResources(record) {
  if (resolveRoundtripDispatchMode(record) !== 'split_no_wait') return true;
  const legs = operationalLegsOf(record);
  return legs.length === 2 && ['outbound', 'return'].every(type => legs.some(leg =>
    String(leg.leg_type || leg.legType).toLowerCase() === type))
    && legs.every(leg => ['driver', 'vehicle'].every(type => {
      const snake = `assigned_${type}_id`, camel = `assigned${type[0].toUpperCase()}${type.slice(1)}Id`;
      return (Object.hasOwn(leg, snake) || Object.hasOwn(leg, camel))
        && !(Object.hasOwn(leg, snake) && Object.hasOwn(leg, camel) && (leg[snake] || '') !== (leg[camel] || ''));
    }));
}

async function proof(env, scope, bookingId) {
  if (!canonicalBookingAuthorityEnabled(env)) return failure('canonical_authority_required', 503);
  if (typeof bookingId !== 'string' || !bookingId || bookingId.length > 160 || /\s/.test(bookingId)) {
    return failure('capacity_checkpoint_booking_invalid', 400);
  }
  const record = await env.BOOKING_KV.get(`booking:${bookingId}`, { type: 'json' });
  if (!sameScope(record, scope)) return failure('capacity_checkpoint_scope_conflict', 403);
  if (record.alias_of || record.canonical_booking_id && record.canonical_booking_id !== bookingId) {
    return failure('capacity_checkpoint_canonical_target_required');
  }
  if (!Number.isSafeInteger(record._canonical_version) || record._canonical_version < 1) {
    return failure('canonical_authority_required', 503);
  }
  if (record.dispatch_assignment_revalidation || record.dispatch_offer_revalidation
    || ['prepared', 'offered'].includes(record.dispatch_offer?.state)) {
    return failure('capacity_checkpoint_transition_pending');
  }
  const built = agendaCapacityClaims(record, bookingId);
  if (!built.ok || !built.claims.length || !explicitSplitResources(record)) {
    return failure('capacity_checkpoint_canonical_unresolved');
  }
  if (!env.COMPANY_TRACKING) return failure('capacity_commit_unavailable', 503);
  const room = env.COMPANY_TRACKING.get(env.COMPANY_TRACKING.idFromName(companyTrackingObjectName(scope.tenant_id, scope.company_id)));
  const response = await room.fetch(`https://room/live?${new URLSearchParams(scope)}`);
  const live = await response.json();
  if (!response.ok || live.ok !== true || live.capacity_contract_version !== 1
    || !sameScope(live.capacity_baseline, scope)) return failure('capacity_baseline_required', 503);
  const held = (live.capacity_reservations || []).filter(claim => claim.owner_id === bookingId);
  if (!sameCheckpointClaims(held, built.claims) || held.some(claim => !sameScope(claim, scope)
    || claim.capacity_pending || claim.retiring || claim.offer_id && claim.capacity_offer_state !== 'committed')
    || (live.dispatch_offers || []).some(offer => offer.owner_id === bookingId)) {
    return failure('capacity_checkpoint_hold_conflict');
  }
  const version = held[0]?.capacity_version;
  if (!Number.isSafeInteger(version) || version < 1 || version > (Number(record.revision) || 1) + 1
    || held.some(claim => claim.capacity_version !== version)) return failure('capacity_checkpoint_version_conflict');
  const checkpoint = { version, claims: built.claims };
  if (record.dispatch_capacity_checkpoint && (record.dispatch_capacity_checkpoint.version !== version
    || !sameCheckpointClaims(record.dispatch_capacity_checkpoint.claims, built.claims))) {
    return failure('capacity_checkpoint_existing_conflict');
  }
  const bytes = new TextEncoder().encode(JSON.stringify({ scope, bookingId, record, checkpoint }));
  const digest = [...new Uint8Array(await crypto.subtle.digest('SHA-256', bytes))]
    .map(value => value.toString(16).padStart(2, '0')).join('');
  return { ok: true, record, checkpoint, digest };
}

// Explicit administrative reconciliation, called in the same serialized
// company coordinator as START/assignment. It never reserves or releases a
// resource and cannot replace an existing conflicting checkpoint.
export async function reconcileCompanyCapacityCheckpoint(env, scope, bookingId, body = {}) {
  try {
    const checked = await proof(env, scope, bookingId);
    if (!checked.ok) return checked;
    const summary = { ok: true, booking_id: bookingId, checkpoint_digest: checked.digest,
      capacity_version: checked.checkpoint.version, claim_count: checked.checkpoint.claims.length };
    if (body.dry_run !== false) return { ...summary, dry_run: true,
      already_reconciled: Boolean(checked.record.dispatch_capacity_checkpoint) };
    // Exact replay after a lost response is safe only with the same positive
    // canonical and physical proof; no write or version increment is needed.
    if (checked.record.dispatch_capacity_checkpoint) return { ...summary, already_reconciled: true };
    if (!body.checkpoint_digest || body.checkpoint_digest !== checked.digest) return failure('capacity_checkpoint_review_changed');
    await env.BOOKING_KV.put(`booking:${bookingId}`, JSON.stringify({ ...checked.record,
      dispatch_capacity_checkpoint: checked.checkpoint }));
    return { ...summary, reconciled: true };
  } catch (error) {
    return failure(error.code || 'capacity_checkpoint_unavailable', error.status || 503);
  }
}
