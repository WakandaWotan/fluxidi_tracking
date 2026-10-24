import { resolveRoundtripDispatchMode } from './company_roundtrip.mjs';

const terminal = leg => ['COMPLETED', 'CANCELLED', 'CANCELED', 'NO_SHOW', 'REJECTED', 'EXPIRED']
  .includes(String(leg.status || leg.lifecycle_status || '').toUpperCase());
const resource = (leg, snake, camel) => leg[snake] || leg[camel] || '';

// First automatic delivery may fill one genuinely empty leg beside a manual
// assignment. Ambiguous/terminal legacy shapes need reconciliation, never a
// fresh whole-group offer that could replace the company's existing choice.
export function initialDispatchAmendmentTarget(record) {
  if (resolveRoundtripDispatchMode(record) !== 'split_no_wait') return null;
  const legs = record.operational_legs || record.booking?.operational_legs || [];
  if (legs.length !== 2 || !['outbound', 'return'].every(type => legs.some(leg => leg.leg_type === type))) return null;
  if (legs.some(terminal)) return { error: 'dispatch_partial_reconciliation_required' };
  const assigned = legs.filter(leg => resource(leg, 'assigned_driver_id', 'assignedDriverId')
    || resource(leg, 'assigned_vehicle_id', 'assignedVehicleId'));
  if (assigned.length !== 1) return null;
  const retained = assigned[0], target = legs.find(leg => leg !== retained);
  if (!resource(retained, 'assigned_driver_id', 'assignedDriverId')
    || !resource(retained, 'assigned_vehicle_id', 'assignedVehicleId')
    || ['driver', 'vehicle'].some(type => retained[`assigned_${type}_id`] && retained[`assigned${type[0].toUpperCase()}${type.slice(1)}Id`]
      && retained[`assigned_${type}_id`] !== retained[`assigned${type[0].toUpperCase()}${type.slice(1)}Id`])
    || target.customer_tracking_phase === 'in_progress' || String(target.status).toUpperCase() === 'IN_PROGRESS') {
    return { error: 'dispatch_partial_reconciliation_required' };
  }
  return { leg_type: target.leg_type };
}

// This marker is written only by the serialized canonical dispatch writer.
// Root assignment may belong to a running sibling; it cannot suppress durable
// recovery for a positively unassigned, separately dispatched leg.
export function hasOpenDispatchAmendment(record) {
  const types = record.dispatch_amendment?.leg_types;
  return resolveRoundtripDispatchMode(record) === 'split_no_wait'
    && Array.isArray(types) && types.length === 1 && ['outbound', 'return'].includes(types[0])
    && (record.operational_legs || []).some(leg => leg.leg_type === types[0]
      && !['COMPLETED', 'CANCELLED', 'CANCELED', 'NO_SHOW', 'REJECTED', 'EXPIRED'].includes(String(leg.status || leg.lifecycle_status || '').toUpperCase())
      && !leg.assigned_driver_id && !leg.assignedDriverId && !leg.assigned_vehicle_id && !leg.assignedVehicleId
      && leg.customer_tracking_phase !== 'in_progress');
}
