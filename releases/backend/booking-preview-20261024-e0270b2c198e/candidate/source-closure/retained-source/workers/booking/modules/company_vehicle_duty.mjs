// Domain reducer only. The persistence adapter must serialize commands per
// company and verify driver/device membership before calling this function.
// Device possession is never proof of a driver's personal authentication.
const deny = error => ({ ok: false, error });
const sameScope = (a, b) => a?.tenant_id === b?.tenant_id && a?.company_id === b?.company_id;
const id = value => typeof value === 'string' && value.trim() && value.length <= 160;

export function applyVehicleDutyCommand(state, command, actor) {
  if (!actor?.tenant_id || !actor?.company_id || !id(actor.driver_id)) return deny('driver_auth_required');
  if (!sameScope(command, actor) || state && !sameScope(state, actor)) return deny('duty_scope_mismatch');
  if (!['start', 'pause', 'resume', 'end'].includes(command?.action)
    || !id(command?.command_id) || !id(command?.vehicle_id) || !id(command?.duty_id)
    || !Number.isSafeInteger(command?.at_ms) || command.at_ms < 0) return deny('duty_command_invalid');
  const current = state ?? { tenant_id: actor.tenant_id, company_id: actor.company_id, version: 0, duties: [], receipts: [] };
  const fingerprint = JSON.stringify([command.action, command.vehicle_id, command.duty_id, command.at_ms, actor.driver_id]);
  const receipt = current.receipts.find(row => row.command_id === command.command_id);
  if (receipt) return receipt.fingerprint === fingerprint
    ? { ok: true, state: current, replay: true } : deny('duty_command_conflict');
  if (command.expected_version !== current.version) return deny('duty_version_conflict');
  const active = current.duties.filter(row => row.ended_at_ms === null);
  let duties;
  if (command.action === 'start') {
    if (current.duties.some(row => row.duty_id === command.duty_id)) return deny('duty_id_conflict');
    if (active.some(row => row.vehicle_id === command.vehicle_id)) return deny('vehicle_duty_conflict');
    if (active.some(row => row.driver_id === actor.driver_id)) return deny('driver_duty_conflict');
    duties = [...current.duties, { duty_id: command.duty_id, driver_id: actor.driver_id, vehicle_id: command.vehicle_id,
      ...(id(actor.vehicle_device_id) ? { vehicle_device_id: actor.vehicle_device_id } : {}),
      started_at_ms: command.at_ms, ended_at_ms: null, paused_at_ms: null, pause_intervals: [] }];
  } else {
    const duty = active.find(row => row.duty_id === command.duty_id && row.vehicle_id === command.vehicle_id && row.driver_id === actor.driver_id);
    if (!duty) return deny('duty_not_owned');
    const latest = duty.paused_at_ms ?? duty.pause_intervals.at(-1)?.end_ms ?? duty.started_at_ms;
    if (command.at_ms < latest) return deny('duty_time_conflict');
    if (command.action === 'pause' && duty.paused_at_ms !== null) return deny('duty_already_paused');
    if (command.action === 'resume' && duty.paused_at_ms === null) return deny('duty_not_paused');
    const next = { ...duty, pause_intervals: [...duty.pause_intervals] };
    if (command.action === 'pause') next.paused_at_ms = command.at_ms;
    else {
      if (duty.paused_at_ms !== null) next.pause_intervals.push({ start_ms: duty.paused_at_ms, end_ms: command.at_ms });
      next.paused_at_ms = null;
      if (command.action === 'end') next.ended_at_ms = command.at_ms;
    }
    duties = current.duties.map(row => row.duty_id === next.duty_id ? next : row);
  }
  return { ok: true, replay: false, state: { ...current, version: current.version + 1, duties,
    receipts: [...current.receipts, { command_id: command.command_id, fingerprint }] } };
}

export function dutyForRideExecution(state, actor, vehicleId) {
  if (!actor?.driver_id || !sameScope(state, actor)) return deny('driver_auth_required');
  const matches = state.duties.filter(row => row.driver_id === actor.driver_id && row.vehicle_id === vehicleId && row.ended_at_ms === null);
  if (matches.length !== 1 || matches[0].paused_at_ms !== null) return deny('active_duty_required');
  const duty = matches[0];
  return { ok: true, execution_identity: Object.freeze({ tenant_id: actor.tenant_id, company_id: actor.company_id,
    driver_id: duty.driver_id, vehicle_id: duty.vehicle_id, duty_id: duty.duty_id }) };
}

export function completedDutySummary(duty) {
  if (duty?.ended_at_ms == null) return deny('duty_not_completed');
  const elapsed_ms = duty.ended_at_ms - duty.started_at_ms;
  const pause_ms = duty.pause_intervals.reduce((total, row) => total + row.end_ms - row.start_ms, 0);
  return { ok: true, driver_id: duty.driver_id, vehicle_id: duty.vehicle_id, duty_id: duty.duty_id,
    elapsed_ms, pause_ms, duty_ms: elapsed_ms - pause_ms };
}
