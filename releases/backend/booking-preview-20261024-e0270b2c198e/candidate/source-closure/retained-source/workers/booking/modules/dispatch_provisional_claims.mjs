// The coordinator constructs this envelope from its locked canonical record.
// Public booking payloads are never copied into it. Reading that coordinator
// again from Fleet would deadlock the very receipt we are validating.
export function currentProvisionalClaimIds(snapshot, scope, body) {
  const intent = body.revalidation_offer;
  if (!intent || !['prepared', 'offered'].includes(intent.state)
    || !Number.isSafeInteger(body.revalidation_canonical_version)
    || !Number.isSafeInteger(intent.record_canonical_version) || intent.record_canonical_version < 1
    || body.revalidation_canonical_version < intent.record_canonical_version
    || body.revalidation_record_revision !== intent.record_revision
    || !Array.isArray(intent.claims) || !intent.claims.length
    || snapshot?.tenant_id !== scope.tenant_id || snapshot?.company_id !== scope.company_id) return [];
  const offer = (snapshot.dispatch_offers || []).find(row => row.offer_id === intent.offer_id
    && row.owner_id === body.booking_id && row.version === intent.version
    && row.tenant_id === scope.tenant_id && row.company_id === scope.company_id
    && ['offered', 'received', 'committing'].includes(row.state));
  if (!offer || offer.record_canonical_version !== intent.record_canonical_version
    || offer.record_revision !== intent.record_revision || offer.record_dispatch_basis !== intent.record_dispatch_basis
    || JSON.stringify(offer.claims) !== JSON.stringify(intent.claims)) return [];
  const held = (snapshot.capacity_reservations || []).filter(row => row.owner_id === body.booking_id
    && row.offer_id === intent.offer_id);
  if (held.length !== intent.claims.length || held.some(row => row.active
    || row.capacity_version !== intent.version || offer.state === 'committing' && row.capacity_pending !== true
    || !intent.claims.some(claim => claim.claim_id === row.claim_id && claim.driver_id === row.driver_id
      && claim.vehicle_id === row.vehicle_id && claim.start_ms === row.start_ms && claim.end_ms === row.end_ms))) return [];
  return held.map(row => row.claim_id);
}

// A locked canonical caller rechecks an already accepted ASAP appointment at
// its fixed time. This is not discovery or permission to ignore other claims.
// Room's exact committed resource is the authority; no coordinator re-read
// (which would deadlock the caller) or persisted capacity change is needed.
export function currentConfirmedAsapClaimIds(snapshot, scope, body) {
  const intent = body.revalidation_offer, checkpoint = body.revalidation_checkpoint;
  if (!scope?.tenant_id || !scope?.company_id
    || body.revalidation_confirmed_asap !== true || body.action !== 'suggest'
    || body.pickup_mode !== 'scheduled' || typeof body.booking_id !== 'string' || !body.booking_id || body.booking_id.startsWith('RC-')
    || intent?.state !== 'committed' || intent.owner_id !== body.booking_id
    || typeof intent.offer_id !== 'string' || !intent.offer_id
    || !Number.isSafeInteger(intent.version) || intent.version < 1
    || !Number.isSafeInteger(intent.record_revision) || intent.record_revision < 1
    || !Number.isSafeInteger(intent.record_canonical_version) || intent.record_canonical_version < 1
    || !Number.isSafeInteger(body.revalidation_canonical_version)
    || body.revalidation_canonical_version < Math.max(intent.version, intent.record_canonical_version)
    || body.revalidation_record_revision !== intent.record_revision
    || !Number.isFinite(intent.asap_requested_ms)
    || intent.asap_search_expires_ms !== intent.asap_requested_ms + 600000
    || checkpoint?.version !== intent.version || !Array.isArray(checkpoint.claims)
    || !Array.isArray(intent.claims) || !body.required_vehicle_id
    || !Number.isSafeInteger(body.service_min) || body.service_min < 1
    || snapshot?.tenant_id !== scope?.tenant_id || snapshot?.company_id !== scope?.company_id) return [];
  const same = (a, b) => a.claim_id === b.claim_id && a.driver_id === b.driver_id
    && a.vehicle_id === b.vehicle_id && a.start_ms === b.start_ms && a.end_ms === b.end_ms;
  const selected = intent.claims.filter(claim => claim.active === false
    && claim.vehicle_id === body.required_vehicle_id && claim.start_ms === body.pickup_ms
    && claim.driver_id && Number.isSafeInteger(claim.start_ms) && Number.isSafeInteger(claim.end_ms)
    && claim.end_ms >= claim.start_ms + body.service_min * 60000);
  if (selected.length !== 1 || !checkpoint.claims.some(claim => !claim.active && same(claim, selected[0]))) return [];
  const held = (snapshot.capacity_reservations || []).filter(row => row.claim_id === selected[0].claim_id);
  if (held.length !== 1 || held[0].owner_id !== body.booking_id || held[0].offer_id !== intent.offer_id
    || held[0].tenant_id !== scope.tenant_id || held[0].company_id !== scope.company_id
    || held[0].capacity_version !== intent.version || held[0].capacity_pending !== false
    || held[0].capacity_offer_state !== 'committed' || held[0].active || held[0].retiring
    || held[0].completion_unconfirmed || held[0].reservation_expired
    || !same(held[0], selected[0])) return [];
  return [held[0].claim_id];
}
