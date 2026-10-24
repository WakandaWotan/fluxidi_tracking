import { parseCompanyOperatingPolicy } from './company_operating_policy.mjs';
import { freshDispatchPosition } from '../../tracking/modules/company_dispatch_offers.mjs';

// Hot position/device leases are separate from a persisted shift. An open
// shift never makes a disconnected or unattended vehicle dispatchable.
const observeDutyDecision=(sink,row)=>{try{sink?.(row);}catch{}};
export function filterLiveVehicleDutyFleet(projection, { snapshot, scope, nowMs, observeDecision } = {}) {
  if (!projection?.ok || projection.mode !== 'manual_duty') return projection;
  if (snapshot?.dispatch_device_contract_version !== 1
    || !Array.isArray(snapshot.dispatch_devices) || !Array.isArray(snapshot.drivers)) {
    for(const driver of projection.drivers)observeDutyDecision(observeDecision,{candidate_id:driver.assigned_vehicle_id,driver_id:driver.driver_id,phase:'live_projection',reason:'dispatch_device_contract_unavailable'});
    return { ...projection, drivers: [] };
  }
  const positions = new Map(snapshot.drivers.filter(row => row?.tenant_id === scope?.tenant_id
    && row?.company_id === scope?.company_id && freshDispatchPosition(row, nowMs))
    .map(row => [row.driver_id, row.vehicle_id]));
  const connected = new Set(snapshot.dispatch_devices.filter(row => row?.protocol === 1
    && Number.isFinite(row.valid_until_ms) && row.valid_until_ms > nowMs).map(row => row.driver_id));
  return { ...projection, drivers: projection.drivers.filter(driver => {
    const device=connected.has(driver.driver_id),position=positions.has(driver.driver_id),match=positions.get(driver.driver_id)===driver.assigned_vehicle_id;
    const allowed=device&&match;
    observeDutyDecision(observeDecision,{candidate_id:driver.assigned_vehicle_id,driver_id:driver.driver_id,phase:'live_projection',
      reason:!device?'dispatch_device_lease_unavailable':!position?'dispatch_position_unavailable':!match?'dispatch_position_vehicle_mismatch':'manual_duty_live_ready',
      lease_valid:device,gps_fresh:position,vehicle_match:match});
    return allowed;
  }) };
}

// Request-local projection only. Never persist these transient driver/vehicle
// links or overwrite the company's stored roster and permanent assignments.
// The caller supplies a server-loaded profile and authenticated company scope.
export function projectVehicleDutyFleet({ enabled = false, profile, scope,
  drivers = [], vehicles = [], scheduled, nowMs, observeDecision } = {}) {
  const existing = () => ({ ok: true, mode: 'existing', drivers, vehicles });
  if (enabled !== true) return existing();
  const parsed = parseCompanyOperatingPolicy(profile?.operating_policy);
  if (!parsed.ok) return parsed;
  if (parsed.policy?.device_binding !== 'vehicle'
    || parsed.policy?.availability_source !== 'manual_duty') return existing();
  if (!scope?.tenant_id || !scope?.company_id) return { ok: false, error: 'company_scope_required' };
  if (typeof scheduled !== 'boolean' || !Number.isSafeInteger(nowMs)) return { ok: false, error: 'booking_timing_required' };
  // An active shift now cannot prove future availability. Scheduled requests
  // must use central intake, not this immediate vehicle projection.
  if (scheduled) return { ok: true, mode: 'manager_first', drivers: [], vehicles: [] };
  const ids = new Set(vehicles.map(row => row?.vehicle_id ?? row?.vehicleId ?? row?.id).filter(Boolean));
  const byVehicle = new Map();
  const byDriver = new Map();
  for (const driver of drivers) {
    const duty = driver?.operating_duty;
    const id = driver?.driver_id ?? driver?.driverId ?? driver?.id;
    if (!id || duty?.driver_id !== id || duty.tenant_id !== scope.tenant_id
      || duty.company_id !== scope.company_id || !ids.has(duty.vehicle_id)
      || !duty.duty_id || !Number.isSafeInteger(duty.version) || duty.version < 1
      || !Number.isSafeInteger(duty.at_ms) || duty.at_ms < 0 || duty.at_ms > nowMs
      || !['start', 'resume'].includes(duty.action)) continue;
    const list = byVehicle.get(duty.vehicle_id) ?? [];
    list.push(driver);
    byVehicle.set(duty.vehicle_id, list);
    byDriver.set(id, (byDriver.get(id) ?? 0) + 1);
  }
  const projectedDrivers = [];
  const projectedVehicles = vehicles.map(vehicle => {
    const id = vehicle?.vehicle_id ?? vehicle?.vehicleId ?? vehicle?.id;
    const candidates = byVehicle.get(id) ?? [];
    // Conflicting occupancy fails closed rather than choosing an identity.
    const driver = candidates.length === 1 && byDriver.get(candidates[0].driver_id ?? candidates[0].driverId ?? candidates[0].id) === 1
      ? candidates[0] : null;
    observeDutyDecision(observeDecision,{candidate_id:id,...(driver?{driver_id:driver.driver_id??driver.driverId??driver.id}:{}),phase:'duty_projection',
      reason:driver?'manual_duty_ready':candidates.length?'manual_duty_conflict':'manual_duty_missing'});
    const copy = { ...vehicle };
    for (const key of ['assigned_driver', 'assignedDriver', 'assigned_driver_id', 'assignedDriverId', 'driver_id']) delete copy[key];
    if (driver) {
      const projected = { ...driver, assigned_vehicle_id: id, assignedVehicleId: id,
        vehicle_ids: [id], vehicleIds: [id], linked_vehicle_ids: [id] };
      // Manual duty is the selected scheduling authority. These removals only
      // affect the local evaluation copy; account, blocked, live, pause and
      // on-trip checks remain in the existing eligibility evaluator.
      for (const key of ['weekly_roster', 'weeklyRoster', 'roster_exceptions', 'rosterExceptions',
        'manual_override', 'manualOverride', 'weekly_roster_load_failed', 'weeklyRosterLoadFailed',
        'weekly_roster_status', 'weeklyRosterStatus', 'roster_status']) delete projected[key];
      projectedDrivers.push(projected);
    }
    return copy;
  });
  return { ok: true, mode: 'manual_duty', drivers: projectedDrivers, vehicles: projectedVehicles };
}
