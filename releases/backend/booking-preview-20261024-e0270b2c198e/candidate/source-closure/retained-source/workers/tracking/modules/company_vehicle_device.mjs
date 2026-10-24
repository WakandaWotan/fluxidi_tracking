import { readCapacitySnapshot } from './company_capacity_storage.mjs';
// Only the authenticated Booking gateway supplies role/admin and token hashes.
// A vehicle token grants device identity; it never grants a driver identity.
const validId = value => typeof value === 'string' && /^[a-zA-Z0-9_.-]{1,96}$/.test(value);
const hash = value => typeof value === 'string' && /^[a-f0-9]{64}$/.test(value);
const denied = error => ({ ok: false, error });
export async function vehicleDeviceCommand(storage, input, nowMs) {
  if (!validId(input?.tenant_id) || !validId(input?.company_id) || !Number.isSafeInteger(nowMs)) return denied('vehicle_device_invalid');
  return storage.transaction(async tx => {
    const scopeKey = 'vehicle_device_scope_v1';
    const scope = await tx.get(scopeKey);
    if (scope && (scope.tenant_id !== input.tenant_id || scope.company_id !== input.company_id)) return denied('vehicle_device_scope_mismatch');
    // Transition authority is distinct from ordinary first-pairing authority.
    // Keep its receipt on the one-use grant: an identical lost-response retry
    // returns the same result without creating another binding or extending TTL.
    if (['create_transition', 'transition'].includes(input.action)) {
      if (!scope || !['switch','unlink'].includes(input.operation)
        || !validId(input.device_id) || !validId(input.challenge_id)
        || !hash(input.pairing_hash)) return denied('vehicle_device_transition_invalid');
      const deviceKey = `vehicle_device_v1:${input.device_id}`;
      const device = await tx.get(deviceKey);
      const grantKey = `vehicle_device_transition_v1:${input.challenge_id}`;
      if (input.action === 'create_transition') {
        if (input.role !== 'company_admin') return denied('vehicle_device_admin_required');
        if (!device || device.revoked || device.expires_at_ms <= nowMs) return denied('vehicle_device_auth_required');
        if (input.operation === 'switch' && (!validId(input.vehicle_id) || input.vehicle_id === device.vehicle_id)) return denied('vehicle_device_target_invalid');
        if (await tx.get(grantKey)) return denied('vehicle_device_challenge_conflict');
        const grant = { operation:input.operation, device_id:input.device_id, old_vehicle_id:device.vehicle_id,
          vehicle_id:input.operation === 'switch' ? input.vehicle_id : null,
          pairing_hash:input.pairing_hash, expires_at_ms:nowMs+300000, consumed:false };
        await tx.put(grantKey, grant);
        return {ok:true, expires_at_ms:grant.expires_at_ms};
      }
      const grant = await tx.get(grantKey);
      if (!grant || grant.operation !== input.operation || grant.device_id !== input.device_id
        || grant.pairing_hash !== input.pairing_hash || !hash(input.device_token_hash)
        || !device || device.token_hash !== input.device_token_hash
        || device.vehicle_id !== grant.old_vehicle_id) return denied('vehicle_device_transition_auth_required');
      if (input.operation === 'switch' && (!validId(input.replacement_device_id)
        || input.replacement_device_id === input.device_id || !hash(input.replacement_token_hash)
        || input.vehicle_id !== grant.vehicle_id)) return denied('vehicle_device_transition_invalid');
      const fingerprint = JSON.stringify([input.operation,input.device_id,input.device_token_hash,
        input.replacement_device_id ?? null,input.replacement_token_hash ?? null]);
      if (grant.consumed) return grant.fingerprint === fingerprint
        ? grant.result : denied('vehicle_device_transition_replay_conflict');
      if (grant.expires_at_ms <= nowMs || device.revoked || device.expires_at_ms <= nowMs) return denied('vehicle_device_transition_expired');
      const vehicles = new Set([device.vehicle_id, grant.vehicle_id].filter(Boolean));
      const duty = await tx.get('vehicle_duty_active_v1');
      if (duty && (duty.tenant_id !== input.tenant_id || duty.company_id !== input.company_id
        || !Array.isArray(duty.duties))) return denied('vehicle_device_operational_state_invalid');
      if (duty?.duties.some(row => vehicles.has(row.vehicle_id) && row.ended_at_ms == null)) return denied('active_duty_blocks_device_change');
      if (await tx.get('vehicle_duty_projection_v1')) return denied('duty_projection_pending');
      // No expiry/recovery here. Any retained matching claim is fail-closed;
      // its normal owner must release it through the existing lifecycle.
      const capacity = await readCapacitySnapshot(tx);
      const capacityScope = capacity.scope || capacity.baseline;
      if (capacityScope && (capacityScope.tenant_id !== input.tenant_id || capacityScope.company_id !== input.company_id)) return denied('vehicle_device_scope_mismatch');
      const matches = row => vehicles.has(row?.vehicle_id);
      const direct = await tx.get('direct_occupancy_active_v1');
      if (Object.values(capacity.claims || {}).some(matches)
        || Object.values(capacity.direct_holds || {}).some(matches)
        || Object.values(direct || {}).some(matches)
        || Object.values(capacity.offers || {}).some(row => matches(row)
          && !['cancelled','expired','aborted','superseded'].includes(row.state))) return denied('active_operation_blocks_device_change');
      const newKey = `vehicle_device_v1:${input.replacement_device_id}`;
      if (input.operation === 'switch' && await tx.get(newKey)) return denied('vehicle_device_id_conflict');
      const leases = await tx.get('dispatch_devices_v1');
      if (leases && (leases.scope?.tenant_id !== input.tenant_id || leases.scope?.company_id !== input.company_id)) return denied('vehicle_device_scope_mismatch');
      if (Object.values(leases?.devices || {}).some(row=>vehicles.has(row.vehicle_id)
        && row.vehicle_device_id !== input.device_id && row.valid_until_ms > nowMs)) return denied('active_operation_blocks_device_change');
      const result = {ok:true, operation:input.operation, revoked_device_id:input.device_id,
        ...(input.operation === 'switch' ? {device_id:input.replacement_device_id,vehicle_id:grant.vehicle_id,
          expires_at_ms:nowMs+90*86400000} : {})};
      await tx.put(deviceKey, {...device,revoked:true});
      if (input.operation === 'switch') await tx.put(newKey,{device_id:result.device_id,vehicle_id:result.vehicle_id,
        token_hash:input.replacement_token_hash,expires_at_ms:result.expires_at_ms,revoked:false});
      if (leases) await tx.put('dispatch_devices_v1',{...leases,devices:Object.fromEntries(
        Object.entries(leases.devices || {}).filter(([,row]) => row.vehicle_device_id !== input.device_id))});
      await tx.put(grantKey,{...grant,consumed:true,fingerprint,result});
      return result;
    }
    if (!scope) await tx.put(scopeKey, { tenant_id: input.tenant_id, company_id: input.company_id });
    if (input.action === 'list') {
      if (input.role !== 'company_admin') return denied('vehicle_device_admin_required');
      if (!validId(input.vehicle_id)) return denied('vehicle_device_invalid');
      const prefix = 'vehicle_device_v1:';
      if (input.cursor != null && (typeof input.cursor !== 'string'
        || !input.cursor.startsWith(prefix) || !validId(input.cursor.slice(prefix.length)))) return denied('vehicle_device_cursor_invalid');
      const rows = [...(await tx.list({ prefix, limit: 51,
        ...(input.cursor ? { startAfter: input.cursor } : {}) })).entries()];
      const items = [];
      for (const [, device] of rows.slice(0, 50)) {
        if (device.vehicle_id !== input.vehicle_id) continue;
        items.push({ device_id: device.device_id, vehicle_id: device.vehicle_id,
          expires_at_ms: device.expires_at_ms, revoked: device.revoked === true,
          status: device.revoked ? 'revoked' : device.expires_at_ms <= nowMs ? 'expired' : 'paired' });
      }
      return { ok: true, vehicle_id: input.vehicle_id, items, cursor: rows.length > 50 ? rows[49][0] : null };
    }
    if (input.action === 'create') {
      if (input.role !== 'company_admin') return denied('vehicle_device_admin_required');
      if (!validId(input.vehicle_id) || !validId(input.challenge_id) || !hash(input.pairing_hash)) return denied('vehicle_device_invalid');
      const key = `vehicle_device_challenge_v1:${input.challenge_id}`;
      if (await tx.get(key)) return denied('vehicle_device_challenge_conflict');
      await tx.put(key, { vehicle_id: input.vehicle_id, pairing_hash: input.pairing_hash, expires_at_ms: nowMs + 300000, consumed: false });
      return { ok: true, expires_at_ms: nowMs + 300000 };
    }
    if (input.action === 'redeem') {
      if (!validId(input.challenge_id) || !validId(input.device_id) || !hash(input.pairing_hash) || !hash(input.device_token_hash)) return denied('vehicle_device_invalid');
      const key = `vehicle_device_challenge_v1:${input.challenge_id}`;
      const challenge = await tx.get(key);
      if (!challenge || challenge.consumed || challenge.expires_at_ms <= nowMs || challenge.pairing_hash !== input.pairing_hash) return denied('vehicle_device_pairing_invalid');
      const deviceKey = `vehicle_device_v1:${input.device_id}`;
      if (await tx.get(deviceKey)) return denied('vehicle_device_id_conflict');
      const device = { device_id: input.device_id, vehicle_id: challenge.vehicle_id, token_hash: input.device_token_hash,
        expires_at_ms: nowMs + 90 * 86400000, revoked: false };
      await tx.put(key, { ...challenge, consumed: true });
      await tx.put(deviceKey, device);
      return { ok: true, device_id: device.device_id, vehicle_id: device.vehicle_id, expires_at_ms: device.expires_at_ms };
    }
    if (!validId(input.device_id)) return denied('vehicle_device_invalid');
    const key = `vehicle_device_v1:${input.device_id}`;
    const device = await tx.get(key);
    if (input.action === 'revoke') {
      if (input.role !== 'company_admin') return denied('vehicle_device_admin_required');
      if (!device) return denied('vehicle_device_not_found');
      if (input.vehicle_id != null && input.vehicle_id !== device.vehicle_id) return denied('vehicle_device_vehicle_mismatch');
      await tx.put(key, { ...device, revoked: true });
      const leases = await tx.get('dispatch_devices_v1');
      if (leases?.scope?.tenant_id === input.tenant_id && leases.scope.company_id === input.company_id) {
        await tx.put('dispatch_devices_v1', { ...leases, devices: Object.fromEntries(
          Object.entries(leases.devices || {}).filter(([, lease]) => lease.vehicle_device_id !== input.device_id)) });
      }
      return { ok: true };
    }
    if (input.action !== 'authenticate' || !hash(input.device_token_hash)
      || !device || device.revoked || device.expires_at_ms <= nowMs || device.token_hash !== input.device_token_hash) return denied('vehicle_device_auth_required');
    return { ok: true, device_id: device.device_id, vehicle_id: device.vehicle_id };
  });
}
