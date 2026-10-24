import { overdueCapacityHold } from '../../tracking/modules/company_capacity_ledger.mjs';

// Durable in-flight capacity must be visible before eventually consistent KV
// projections catch up. Never erase richer canonical route/lifecycle facts.
export function mergeCapacityDemand(items, snapshot, scope, nowMs = Date.now()) {
  const result = items.map(item => ({ ...item }));
  for (const claim of snapshot?.capacity_reservations || []) {
    if (claim.tenant_id !== scope.tenant_id || claim.company_id !== scope.company_id
      || (!claim.vehicle_id && !claim.driver_id) || !Number.isFinite(claim.start_ms) || !Number.isFinite(claim.end_ms)
      || claim.end_ms <= claim.start_ms) continue;
    const existing = result.find(item => item.booking_id === claim.claim_id
      && item.assigned_vehicle_id === claim.vehicle_id && item.assigned_driver_id === (claim.driver_id || null));
    if (existing) {
      const end = Math.max(existing.pickupMs + existing.serviceMin * 60000, claim.end_ms);
      existing.pickupMs = Math.min(existing.pickupMs, claim.start_ms);
      existing.serviceMin = (end - existing.pickupMs) / 60000;
      existing.dropoffAtMs = Math.max(existing.dropoffAtMs || 0, end);
      if (!existing.activeRide && overdueCapacityHold(claim, nowMs)) {
        existing.occupancyEndUnknown = true;
        existing.reservationCompletionUnconfirmed = true;
      }
    } else {
      result.push({ booking_id: claim.claim_id, parent_booking_id: claim.owner_id,
        assigned_driver_id: claim.driver_id || null, assigned_vehicle_id: claim.vehicle_id || null,
        pickupMs: claim.start_ms, serviceMin: (claim.end_ms - claim.start_ms) / 60000,
        dropoffAtMs: claim.end_ms, occupancyEndUnknown: claim.active === true || overdueCapacityHold(claim, nowMs),
        reservationCompletionUnconfirmed: overdueCapacityHold(claim, nowMs), activeRide: claim.active === true,
        tier: 'comfort', pax: 1, bags: 0, lifecycle: 'pending', capacityOnly: true });
    }
  }
  return result;
}

export function capacityBlockedDriverIds(items, pickupMs, serviceMin, selfId = '') {
  const end = pickupMs + serviceMin * 60000;
  return new Set(items.filter(item => item.assigned_driver_id && item.booking_id !== selfId
    && Number.isFinite(item.pickupMs) && (item.occupancyEndUnknown === true && end > item.pickupMs
      || pickupMs < item.pickupMs + item.serviceMin * 60000 && item.pickupMs < end))
    .map(item => item.assigned_driver_id));
}
