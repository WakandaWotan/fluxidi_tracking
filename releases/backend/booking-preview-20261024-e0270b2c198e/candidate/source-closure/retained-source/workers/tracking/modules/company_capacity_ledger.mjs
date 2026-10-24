// One company-wide decision point, including reservations that cross midnight.
// Called only through the private Durable Object binding by authenticated Workers.
import { claimsForResource, claimsForOwner, invalidateCapacityResourceIndex } from './capacity_resource_index.mjs';
export function sameCapacityResource(left, right) {
  return Boolean(left.vehicle_id && left.vehicle_id === right.vehicle_id
    || left.driver_id && left.driver_id === right.driver_id);
}

// Bootstrap adds positive canonical reservations. It can never erase or change
// a newer in-flight reservation; missing KV records are not release evidence.
export function capacityBaselineDecision(ledger, input) {
  if (!input.tenant_id || !input.company_id || input.inventory_verified !== true
    || !Array.isArray(input.bookings) || input.bookings.length > 5000) {
    return { ok: false, error: 'capacity_baseline_invalid', status: 400 };
  }
  let next = structuredClone(ledger);
  for (const booking of input.bookings) {
    // Validate every positive record, including retries for existing owners.
    // A prior initialization must not certify malformed or contradictory input.
    const checked = capacityClaimDecision({ claims: {}, owners: {} }, { ...booking,
      tenant_id: input.tenant_id, company_id: input.company_id, action: 'reserve', replace_owner: false }, []);
    if (!checked.ok) return checked;
    if (next.owners[booking.owner_id]) {
      const previous = next.owners[booking.owner_id];
      if (previous.tenant_id !== input.tenant_id || previous.company_id !== input.company_id) {
        return { ok: false, error: 'capacity_scope_conflict', status: 409 };
      }
      if (previous.version < booking.version || previous.pending) {
        return { ok: false, error: 'capacity_baseline_owner_unresolved', status: 409 };
      }
      if (!previous.released && previous.version === booking.version) {
        const comparable = claim => JSON.stringify({ claim_id: claim.claim_id, driver_id: claim.driver_id || '',
          vehicle_id: claim.vehicle_id || '', start_ms: claim.start_ms, end_ms: claim.end_ms, active: claim.active === true });
        const held = claimsForOwner(next.claims, booking.owner_id).filter(claim => !claim.retiring).map(comparable).sort();
        if (JSON.stringify(held) !== JSON.stringify((booking.claims || []).map(comparable).sort())) {
          return { ok: false, error: 'capacity_baseline_owner_unresolved', status: 409 };
        }
      }
      continue;
    }
    // Validate each record independently. Existing historical overlaps must
    // stay represented so bootstrap cannot silently make either car free.
    if (Object.keys(checked.ledger.claims).some(id => next.claims[id])) {
      return { ok: false, error: 'capacity_owner_conflict', status: 409 };
    }
    next = { ...next, claims: { ...next.claims, ...checked.ledger.claims }, owners: { ...next.owners, ...checked.ledger.owners } };
  }
  return { ok: true, ledger: next };
}
// A confirmed reservation has a bounded late-arrival margin. A missing START
// cannot turn an old planned window into perpetual physical occupancy. Keep
// unfinished atomic replacements protected until their checkpoint is confirmed.
export const UNSTARTED_CAPACITY_GRACE_MS = 15 * 60 * 1000;
export function unstartedCapacityExpired(claim, nowMs = Date.now(), owner = null) {
  return claim?.active !== true && !claim?.retiring && claim?.capacity_pending !== true && owner?.pending !== true
    && Number.isFinite(claim?.start_ms) && Number.isFinite(claim?.end_ms)
    && claim.start_ms < claim.end_ms && nowMs >= claim.end_ms + UNSTARTED_CAPACITY_GRACE_MS;
}
export function overdueCapacityHold(claim, nowMs = Date.now(), owner = null) {
  return claim?.active !== true && Number.isFinite(claim?.start_ms) && Number.isFinite(claim?.end_ms)
    && claim.start_ms < claim.end_ms && claim.end_ms <= nowMs && !unstartedCapacityExpired(claim, nowMs, owner);
}

export function capacityClaimDecision(ledger, input, directRides) {
  const { tenant_id, company_id, owner_id, action, claims = [], version = 1 } = input;
  if (!tenant_id || !company_id || typeof owner_id !== 'string' || !owner_id.trim() || owner_id.length > 200
    || !['reserve', 'release', 'confirm', 'activate'].includes(action) || !Number.isSafeInteger(version) || version < 1 || !Array.isArray(claims)) {
    return { ok: false, error: 'capacity_request_invalid', status: 400 };
  }
  const previous = ledger.owners[owner_id];
  if (previous && (previous.tenant_id !== tenant_id || previous.company_id !== company_id)) {
    return { ok: false, error: 'capacity_scope_conflict', status: 409 };
  }
  if (previous?.released && action === 'release' && version <= previous.version) return { ok: true, ledger };
  if (previous && version < previous.version) return { ok: false, error: 'capacity_revision_conflict', status: 409 };
  if (previous?.pending && action === 'release') return { ok: false, error: 'capacity_update_pending', status: 409, pending_version: previous.version };
  if (previous?.pending && version !== previous.version) return { ok: false, error: 'capacity_update_pending', status: 409, pending_version: previous.version };
  if (action === 'activate') {
    let claim = ledger.claims[input.claim_id];
    if (!claim && !previous && typeof input.claim_id === 'string' && input.claim_id.length <= 240 && input.driver_id && input.vehicle_id) {
      // A legacy assigned ride may have no usable duration. START still needs
      // a durable physical hold; this one is not a promised completion time.
      claim = { claim_id: input.claim_id, driver_id: input.driver_id, vehicle_id: input.vehicle_id,
        start_ms: Date.now(), end_ms: Date.now() + 1, tenant_id, company_id, owner_id };
    }
    if (previous?.pending || previous?.released || previous && previous.version !== version
      || !claim || claim.owner_id !== owner_id || claim.retiring
      || claim.driver_id !== input.driver_id || claim.vehicle_id !== input.vehicle_id) {
      return { ok: false, error: 'capacity_revision_conflict', status: 409 };
    }
    if (unstartedCapacityExpired(claim, Date.now(), previous)) {
      return { ok: false, error: 'capacity_reservation_expired', status: 409 };
    }
    if (directRides.some(ride => ride.tenant_id === tenant_id && ride.company_id === company_id && sameCapacityResource(ride, claim))
      || claimsForResource(ledger.claims, claim).some(other => other.owner_id !== owner_id && (other.active || overdueCapacityHold(other, Date.now(), ledger.owners[other.owner_id]))
        && other.tenant_id === tenant_id && other.company_id === company_id && sameCapacityResource(other, claim))) {
      return { ok: false, error: 'capacity_conflict', status: 409 };
    }
    return { ok: true, ledger: { ...ledger, claims: { ...ledger.claims, [input.claim_id]: { ...claim, active: true } },
      owners: { ...ledger.owners, [owner_id]: previous || { tenant_id, company_id, version, signature: 'activated', pending: false, released: false } } } };
  }
  if (action === 'confirm') {
    if (!previous || previous.version !== version) return { ok: false, error: 'capacity_revision_conflict', status: 409 };
    if (previous.released) return { ok: true, ledger };
    if (input.canonical_claims) {
      const comparable = claim => JSON.stringify({ claim_id: claim.claim_id, driver_id: claim.driver_id || '',
        vehicle_id: claim.vehicle_id || '', start_ms: claim.start_ms, end_ms: claim.end_ms, active: claim.active === true });
      const current = claimsForOwner(ledger.claims, owner_id).filter(claim => !claim.retiring).map(comparable).sort();
      if (!Array.isArray(input.canonical_claims) || JSON.stringify(current) !== JSON.stringify(input.canonical_claims.map(comparable).sort())) {
        return { ok: false, error: 'capacity_checkpoint_conflict', status: 409 };
      }
    }
    const confirmedClaims = Object.fromEntries(Object.entries(ledger.claims).filter(([, claim]) =>
      claim.owner_id !== owner_id || !claim.retiring));
    return { ok: true, ledger: { claims: confirmedClaims, owners: { ...ledger.owners,
      [owner_id]: { ...previous, pending: false, released: !Object.values(confirmedClaims).some(claim => claim.owner_id === owner_id) } } } };
  }
  if (action === 'reserve' && ((!claims.length && input.replace_owner !== true) || claims.length > 8)) {
    return { ok: false, error: 'capacity_request_invalid', status: 400 };
  }
  if (claims.some(claim => !claim || typeof claim !== 'object' || Array.isArray(claim))) {
    return { ok: false, error: 'capacity_request_invalid', status: 400 };
  }
  const normalized = claims.map(claim => ({
    claim_id: claim.claim_id, driver_id: claim.driver_id || '', vehicle_id: claim.vehicle_id || '',
    start_ms: claim.start_ms, end_ms: claim.end_ms, active: claim.active === true, tenant_id, company_id, owner_id,
  }));
  if (action === 'reserve' && normalized.some(claim => !claim.claim_id || claim.claim_id.length > 240
    || typeof claim.claim_id !== 'string' || (!claim.driver_id && !claim.vehicle_id)
    || claim.driver_id && (typeof claim.driver_id !== 'string' || claim.driver_id.length > 128)
    || claim.vehicle_id && (typeof claim.vehicle_id !== 'string' || claim.vehicle_id.length > 128)
    || !Number.isFinite(claim.start_ms) || !Number.isFinite(claim.end_ms) || claim.end_ms <= claim.start_ms)) {
    return { ok: false, error: 'capacity_request_invalid', status: 400 };
  }
  if (action === 'reserve' && new Set(normalized.map(claim => claim.claim_id)).size !== normalized.length) {
    return { ok: false, error: 'capacity_request_invalid', status: 400 };
  }
  const ended = input.ended_claim_ids === undefined ? [] : input.ended_claim_ids;
  if (!Array.isArray(ended) || ended.length > 8 || new Set(ended).size !== ended.length
    || ended.some(id => typeof id !== 'string' || !id.trim() || id.length > 240)) {
    return { ok: false, error: 'capacity_request_invalid', status: 400 };
  }
  // Completion evidence is supplied by the authenticated booking writer from
  // terminal lifecycle facts. It belongs to the same preparation/checkpoint;
  // a replay may not change which physical holds are being ended.
  const signature = JSON.stringify({ action, replace_owner: input.replace_owner === true, claims: normalized,
    ...(ended.length ? { ended_claim_ids: [...ended].sort() } : {}) });
  // A partial allocator retry must never clear the canonical-write barrier or
  // change its prepared claims. Only the exact full preparation may replay.
  if (action === 'reserve' && previous?.pending && previous.signature !== signature) {
    return { ok: false, error: 'capacity_update_pending', status: 409, pending_version: previous.version };
  }
  if (action === 'reserve' && previous?.version === version && !previous.pending && previous.signature === signature) {
    return { ok: true, ledger };
  }
  if (previous?.version === version && previous.signature !== signature
    && (previous.released || action === 'reserve' && input.replace_owner === true)) {
    return { ok: false, error: 'capacity_revision_conflict', status: 409 };
  }
  if (action === 'reserve') {
    for (const held of claimsForOwner(ledger.claims, owner_id)) {
      if (held.owner_id !== owner_id || held.retiring || !held.active) continue;
      const next = normalized.find(claim => claim.claim_id === held.claim_id);
      if (input.replace_owner !== true && !next) continue;
      // START is physical occupancy even when canonical persistence has not
      // caught up. A later scheduled assignment cannot downgrade, rename or
      // transfer that hold. An ending keeps the old hold retiring until the
      // persisted terminal checkpoint is confirmed.
      const preserved = next?.active === true && next.driver_id === held.driver_id && next.vehicle_id === held.vehicle_id;
      if (!preserved && !(ended.includes(held.claim_id) && !next)) {
        return { ok: false, error: 'active_assignment_change_requires_completion', status: 409 };
      }
    }
  }
  const nextClaims = { ...ledger.claims };
  if (action === 'release' || input.replace_owner === true) {
    for (const [id, claim] of Object.entries(nextClaims)) {
      if (claim.owner_id === owner_id && claim.tenant_id === tenant_id && claim.company_id === company_id
        && (action !== 'release' || !Array.isArray(input.claim_ids) || input.claim_ids.includes(id))) {
        if (action === 'reserve' && !claim.retiring && !normalized.some(next => JSON.stringify(next) === JSON.stringify(claim))) {
          const retiringId = `${id}:retiring:${version}`;
          nextClaims[retiringId] = { ...claim, claim_id: retiringId, retiring: true };
        }
        if (!claim.retiring || action === 'release') delete nextClaims[id];
      }
    }
  }
  for (const claim of action === 'reserve' ? normalized : []) {
    const existing = nextClaims[claim.claim_id];
    if (existing && existing.owner_id !== owner_id) return { ok: false, error: 'capacity_owner_conflict', status: 409 };
    if (directRides.some(ride => ride.tenant_id === tenant_id && ride.company_id === company_id
      && sameCapacityResource(ride, claim))) return { ok: false, error: 'active_ride_end_unknown', status: 409 };
    if (claim.end_ms > Date.now() && claimsForResource(nextClaims, claim).some(other => other.claim_id !== claim.claim_id
      && !(other.owner_id === owner_id && other.retiring)
      && other.tenant_id === tenant_id && other.company_id === company_id && sameCapacityResource(other, claim)
      && overdueCapacityHold(other, Date.now(), ledger.owners[other.owner_id]))) {
      return { ok: false, error: 'capacity_completion_unconfirmed', status: 409 };
    }
    if (claimsForResource(nextClaims, claim).some(other => other.claim_id !== claim.claim_id
      && !(other.owner_id === owner_id && other.retiring)
      && other.tenant_id === tenant_id && other.company_id === company_id && sameCapacityResource(other, claim)
      && claim.start_ms < other.end_ms && other.start_ms < claim.end_ms)) {
      return { ok: false, error: 'capacity_conflict', status: 409 };
    }
    if (existing && previous?.version === version && JSON.stringify(existing) !== JSON.stringify(claim)) {
      return { ok: false, error: 'capacity_revision_conflict', status: 409 };
    }
    if (existing && JSON.stringify(existing) !== JSON.stringify(claim)) {
      const retiringId = `${claim.claim_id}:retiring:${version}`;
      nextClaims[retiringId] = { ...existing, claim_id: retiringId, retiring: true };
    }
    nextClaims[claim.claim_id] = claim;
    invalidateCapacityResourceIndex(nextClaims);
  }
  return { ok: true, ledger: { claims: nextClaims, owners: { ...ledger.owners,
    [owner_id]: { tenant_id, company_id, version, signature, pending: action === 'reserve' && input.replace_owner === true,
      released: action === 'release' && !Object.values(nextClaims).some(claim => claim.owner_id === owner_id) } } } };
}
