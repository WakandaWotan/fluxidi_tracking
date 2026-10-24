import { applyVehicleDutyCommand, completedDutySummary } from '../../booking/modules/company_vehicle_duty.mjs';

export const VEHICLE_DUTY_STATE_KEY = 'vehicle_duty_active_v1';
export const VEHICLE_DUTY_PROJECTION_KEY = 'vehicle_duty_projection_v1';
const encode = value => encodeURIComponent(value);
const receiptKey = id => `vehicle_duty_command_v1:${encode(id)}`;
const archiveKey = id => `vehicle_duty_archive_v1:${encode(id)}`;
// at_ms is stamped by the gateway and may change on an HTTP retry.
const fingerprint = (command, actor, audit) => JSON.stringify([command.action, command.vehicle_id, command.duty_id, command.expected_version, actor.driver_id,
  ...(audit ? [audit.role, audit.company_id, audit.reason, audit.device_id] : [])]);

export async function vehicleDutyCommandReplay(storage, command, actor, { recoveryAudit } = {}) {
  const state = await storage.get(VEHICLE_DUTY_STATE_KEY);
  if (state && (state.tenant_id !== actor.tenant_id || state.company_id !== actor.company_id)) return { ok: false, error: 'duty_scope_mismatch' };
  if (typeof command?.command_id !== 'string' || !command.command_id.trim() || command.command_id.length > 160) return { ok: false, error: 'duty_command_invalid' };
  const receipt = await storage.get(receiptKey(command.command_id));
  if (!receipt) return null;
  return receipt.fingerprint === fingerprint(command, actor, recoveryAudit)
    ? { ok: true, replay: true, version: receipt.version, duty: receipt.duty }
    : { ok: false, error: 'duty_command_conflict' };
}

// Called inside the same company occupancy queue as reservation/dispatch writes.
// Sparse duty commands only: GPS publication does not call this adapter.
export async function persistVehicleDutyCommand(storage, command, actor, { projectAvailability = false, recoveryAudit } = {}) {
  if (!storage?.transaction) return { ok: false, error: 'duty_transaction_unavailable' };
  return storage.transaction(async tx => {
    // Gateway authentication may precede a concurrent device transition.
    // Revalidate its trusted actor inside the transaction that writes duty.
    // Administrative recovery has its own revoked-device authorization path.
    if (actor?.vehicle_device_id && !recoveryAudit) {
      const scope = await tx.get('vehicle_device_scope_v1');
      const device = await tx.get(`vehicle_device_v1:${actor.vehicle_device_id}`);
      if (scope?.tenant_id !== actor.tenant_id || scope?.company_id !== actor.company_id
        || !device || device.revoked || device.expires_at_ms <= Date.now()
        || device.vehicle_id !== command.vehicle_id) return {ok:false,error:'vehicle_device_auth_required'};
    }
    const state = await tx.get(VEHICLE_DUTY_STATE_KEY);
    if (!actor?.tenant_id || !actor?.company_id || !actor?.driver_id
      || command?.tenant_id !== actor.tenant_id || command?.company_id !== actor.company_id
      || state && (state.tenant_id !== actor.tenant_id || state.company_id !== actor.company_id)) {
      return { ok: false, error: 'duty_scope_mismatch' };
    }
    if (typeof command?.command_id !== 'string' || !command.command_id.trim() || command.command_id.length > 160) return { ok: false, error: 'duty_command_invalid' };
    const receipt = await tx.get(receiptKey(command.command_id));
    if (receipt) return receipt.fingerprint === fingerprint(command, actor, recoveryAudit)
      ? { ok: true, replay: true, version: receipt.version, duty: receipt.duty }
      : { ok: false, error: 'duty_command_conflict' };
    if (projectAvailability && await tx.get(VEHICLE_DUTY_PROJECTION_KEY)) return { ok: false, error: 'duty_projection_pending' };
    if (command.action === 'start' && await tx.get(archiveKey(command.duty_id))) return { ok: false, error: 'duty_id_conflict' };
    const decision = applyVehicleDutyCommand(state, command, actor);
    if (!decision.ok) return decision;
    let duty = decision.state.duties.find(row => row.duty_id === command.duty_id);
    if (recoveryAudit) duty = { ...duty, recovery: { ...recoveryAudit, at_ms: command.at_ms } };
    const next = { ...decision.state, receipts: [], duties: decision.state.duties.filter(row => row.ended_at_ms === null) };
    if (duty.ended_at_ms !== null) {
      const archived = { ...duty, tenant_id: actor.tenant_id, company_id: actor.company_id, summary: completedDutySummary(duty) };
      await tx.put(archiveKey(duty.duty_id), archived);
      await tx.put(`vehicle_duty_driver_v1:${encode(actor.driver_id)}:${String(duty.started_at_ms).padStart(16,'0')}:${encode(duty.duty_id)}`, { archive_key: archiveKey(duty.duty_id) });
    }
    const result = { ok: true, replay: false, version: next.version, duty };
    await tx.put(VEHICLE_DUTY_STATE_KEY, next);
    if (projectAvailability) await tx.put(VEHICLE_DUTY_PROJECTION_KEY, {
      tenant_id: actor.tenant_id, company_id: actor.company_id,
      driver_id: actor.driver_id, vehicle_id: duty.vehicle_id, duty_id: duty.duty_id,
      version: next.version, action: command.action, at_ms: command.at_ms,
    });
    await tx.put(receiptKey(command.command_id), { fingerprint: fingerprint(command, actor, recoveryAudit), version: next.version, duty });
    return result;
  });
}

export async function readVehicleDutyHistory(storage, scope, driverId, { limit = 50, cursor = '' } = {}) {
  if (!scope?.tenant_id || !scope?.company_id || typeof driverId !== 'string' || !driverId.trim()) return { ok: false, error: 'duty_scope_required' };
  const state = await storage.get(VEHICLE_DUTY_STATE_KEY);
  if (state && (state.tenant_id !== scope.tenant_id || state.company_id !== scope.company_id)) return { ok: false, error: 'duty_scope_mismatch' };
  const prefix = `vehicle_duty_driver_v1:${encode(driverId)}:`;
  if (cursor && !cursor.startsWith(prefix)) return { ok: false, error: 'duty_cursor_invalid' };
  const count = Math.max(1, Math.min(100, Number.isSafeInteger(limit) ? limit : 50));
  const rows = await storage.list({ prefix, limit: count + 1, ...(cursor ? { startAfter: cursor } : {}) });
  const entries = [...rows.entries()];
  const items = [];
  for (const [, index] of entries.slice(0, count)) {
    const duty = await storage.get(index.archive_key);
    if (!duty || duty.tenant_id !== scope.tenant_id || duty.company_id !== scope.company_id || duty.driver_id !== driverId) return { ok: false, error: 'duty_history_inconsistent' };
    items.push(duty);
  }
  return { ok: true, items, cursor: entries.length > count ? entries[count - 1][0] : null };
}
