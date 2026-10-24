import {frozenRideExecutionIdentityV1} from '../../shared/ride_execution_identity_v1.mjs';
// Human acceptance evidence comes from the durable Room event, never a client
// body or the current vehicle/driver profile. Preserve it across later changes.
export function acceptedRideExecutionIdentities(intent, event, scope) {
  if (intent?.human_acceptance_required !== true) {
    return event?.human_acceptance_required === true
      ? { ok: false, error: 'dispatch_acceptance_evidence_conflict' } : { ok: true, identities: null };
  }
  if (event?.human_acceptance_required !== true || event.offer_id !== intent.offer_id
    || event.version !== intent.version || event.tenant_id !== scope?.tenant_id
    || event.company_id !== scope?.company_id) return { ok: false, error: 'dispatch_acceptance_evidence_required' };
  const assignments = intent.assignments ?? [{ leg: 'outbound', driver_id: intent.driver_id, vehicle_id: intent.vehicle_id }];
  const identities = {};
  for (const assignment of assignments) {
    const receipt = event.receipts?.[assignment.driver_id], identity = receipt?.execution_identity;
    if (receipt?.accepted !== true || identity?.tenant_id !== scope.tenant_id
      || identity?.company_id !== scope.company_id || identity?.driver_id !== assignment.driver_id
      || !frozenRideExecutionIdentityV1(identity,scope,assignment.driver_id,assignment.vehicle_id)
      || !['outbound', 'return'].includes(assignment.leg) || identities[assignment.leg]) {
      return { ok: false, error: 'dispatch_acceptance_evidence_required' };
    }
    identities[assignment.leg] = frozenRideExecutionIdentityV1(identity,scope,assignment.driver_id,assignment.vehicle_id);
  }
  return { ok: true, identities };
}

export function rideExecutionIdentityAtStart(record, { scope, driverId, vehicleId, leg = 'outbound' } = {}) {
  if (record?.dispatch_offer?.human_acceptance_required !== true) return { ok: true, identity: null };
  const identity = record.dispatch_offer.execution_identities?.[leg];
  if (!identity || identity.tenant_id !== scope?.tenant_id || identity.company_id !== scope?.company_id
    || !frozenRideExecutionIdentityV1(identity,scope,driverId,vehicleId)) {
    return { ok: false, error: 'ride_execution_identity_required' };
  }
  return { ok: true, identity: frozenRideExecutionIdentityV1(identity,scope,driverId,vehicleId) };
}
