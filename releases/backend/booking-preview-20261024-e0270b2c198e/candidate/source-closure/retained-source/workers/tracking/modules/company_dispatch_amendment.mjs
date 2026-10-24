import { capacityClaimDecision } from './company_capacity_ledger.mjs';

const fail = () => ({ ok: false, error: 'dispatch_amendment_conflict', status: 409 });
export const comparableDispatchClaim = claim => JSON.stringify({ claim_id: claim.claim_id,
  driver_id: claim.driver_id || '', vehicle_id: claim.vehicle_id || '', start_ms: claim.start_ms,
  end_ms: claim.end_ms, active: claim.active === true });
const equalClaims = (left, right) => JSON.stringify(left.map(comparableDispatchClaim).sort())
  === JSON.stringify(right.map(comparableDispatchClaim).sort());

// A replacement leg has a revocable hold beside the existing hard assignment.
// The hard owner's version/pending flag stays unchanged until all new devices
// have acknowledged. Expiry can therefore never release the running sibling.
export function amendmentBaseMatches(ledger, offer) {
  const owner = ledger.owners[offer.owner_id];
  const retained = offer.retained_claims;
  const held = Object.values(ledger.claims).filter(claim => claim.owner_id === offer.owner_id
    && (!offer.offer_id || claim.offer_id !== offer.offer_id));
  return offer.amendment === true && Number.isSafeInteger(offer.base_version)
    && offer.base_version > 0 && offer.version >= offer.base_version
    && owner?.version === offer.base_version && !owner.pending
    && owner.tenant_id === offer.tenant_id && owner.company_id === offer.company_id
    && Array.isArray(retained) && retained.length <= 2 && retained.every(claim => claim && typeof claim === 'object'
      && typeof claim.claim_id === 'string' && Number.isFinite(claim.start_ms) && Number.isFinite(claim.end_ms))
    && (retained.length > 0 || owner.released)
    && held.every(claim => !claim.retiring && claim.tenant_id === offer.tenant_id && claim.company_id === offer.company_id)
    && equalClaims(held, retained);
}

export function holdAmendmentClaims(ledger, input, directRides) {
  if (!amendmentBaseMatches(ledger, input) || input.version <= input.base_version || !Array.isArray(input.claims)
    || input.claims.length !== 1 || !['OUTBOUND', 'RETURN'].some(type => input.claims[0].claim_id === `${input.owner_id}:${type}`)
    || input.retained_claims.some(claim => input.claims.some(next => next.claim_id === claim.claim_id))) return fail();
  const checked = capacityClaimDecision(ledger, { ...input, action: 'reserve', replace_owner: false }, directRides);
  return checked.ok ? { ok: true, ledger: { ...checked.ledger,
    owners: { ...checked.ledger.owners, [input.owner_id]: ledger.owners[input.owner_id] } } } : checked;
}

export function promoteAmendmentClaims(ledger, offer, directRides) {
  if (!amendmentBaseMatches(ledger, offer) || !offer.claims.every(claim => {
    const held = ledger.claims[claim.claim_id];
    return held?.owner_id === offer.owner_id && held.offer_id === offer.offer_id && !held.retiring
      && comparableDispatchClaim(held) === comparableDispatchClaim(claim);
  })) return fail();
  const base = { ...ledger, claims: Object.fromEntries(Object.entries(ledger.claims)
    .filter(([, claim]) => claim.owner_id !== offer.owner_id || claim.offer_id !== offer.offer_id)) };
  return capacityClaimDecision(base, { ...offer, action: 'reserve', replace_owner: true,
    claims: [...offer.retained_claims, ...offer.claims] }, directRides);
}

// The Booking authority has persisted a newer, still-unassigned target leg.
// Only that positive checkpoint can undo an acknowledged promotion. Keep all
// old physical holds until the new canonical claim set is confirmed atomically.
export function rollbackAmendmentPromotion(ledger, offer, proof, directRides) {
  const owner = ledger.owners[offer.owner_id];
  const held = Object.values(ledger.claims).filter(claim => claim.owner_id === offer.owner_id && !claim.retiring);
  if (owner?.version !== offer.version || !owner.pending || !Number.isSafeInteger(proof.capacity_version)
    || proof.capacity_version <= offer.version || !Array.isArray(proof.canonical_claims)
    || !equalClaims(proof.canonical_claims, offer.retained_claims)
    || !equalClaims(held, [...offer.retained_claims, ...offer.claims])) return fail();
  const settled = { ...ledger, owners: { ...ledger.owners, [offer.owner_id]: { ...owner, pending: false } } };
  const reserved = capacityClaimDecision(settled, { ...offer, action: 'reserve', version: proof.capacity_version,
    replace_owner: true, claims: proof.canonical_claims }, directRides);
  if (!reserved.ok) return reserved;
  return capacityClaimDecision(reserved.ledger, { ...offer, action: 'confirm', version: proof.capacity_version,
    canonical_claims: proof.canonical_claims }, directRides);
}
