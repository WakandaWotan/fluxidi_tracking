// Only authenticated Booking heartbeats reach this private Room contract.
// Capability is separate from GPS freshness and from human acceptance.
export const DISPATCH_DEVICE_TTL_MS = 180_000;
// Vehicle offers are polled by the visible cockpit every two seconds. A lost
// process must not remain a candidate for the legacy three-minute lease.
export const VEHICLE_DISPATCH_DEVICE_TTL_MS = 8_000;
const matches = (row, scope) => row?.tenant_id === scope.tenant_id && row?.company_id === scope.company_id;
const valid = (row, nowMs) => row?.protocol === 1 && Number.isFinite(row.seen_at_ms)
  && row.seen_at_ms <= nowMs && nowMs < row.valid_until_ms;

export function driverDispatchDevices(store, scope, driverId, nowMs, deviceKey = '') {
  if (!matches(store?.scope, scope)) return [];
  return Object.values(store.devices || {}).filter(row => matches(row, scope)
    && row.driver_id === driverId && (!deviceKey || row.device_key === deviceKey) && valid(row, nowMs));
}

export function dispatchDeviceDeadline(store, scope, driverId, nowMs) {
  const rows = driverDispatchDevices(store, scope, driverId, nowMs);
  return rows.length ? Math.max(...rows.map(row => row.valid_until_ms)) : null;
}

export function projectDispatchDevices(store, scope, nowMs) {
  if (!matches(store?.scope, scope)) return [];
  const drivers = new Map();
  for (const row of Object.values(store.devices || {})) {
    if (!matches(row, scope) || !valid(row, nowMs)) continue;
    const previous = drivers.get(row.driver_id);
    if (!previous || previous.valid_until_ms < row.valid_until_ms) drivers.set(row.driver_id,
      { driver_id: row.driver_id, protocol: 1, seen_at_ms: row.seen_at_ms, valid_until_ms: row.valid_until_ms });
  }
  return [...drivers.values()];
}

export function updateDispatchDevice(store, input, nowMs) {
  if (!input?.tenant_id || !input.company_id || typeof input.driver_id !== 'string' || !input.driver_id
    || input.driver_id.length > 96 || !/^[a-f0-9]{64}$/.test(input.device_key || '')
    || !Number.isFinite(nowMs) || !Number.isFinite(input.session_expires_ms) || input.session_expires_ms <= nowMs) {
    return { ok: false, error: 'dispatch_device_invalid', status: 400 };
  }
  if (store?.scope && !matches(store.scope, input)) return { ok: false, error: 'dispatch_device_scope_conflict', status: 409 };
  const old = store?.devices?.[input.device_key];
  if (old && (!matches(old, input) || old.driver_id !== input.driver_id)) {
    return { ok: false, error: 'dispatch_device_owner_conflict', status: 409 };
  }
  const devices = Object.fromEntries(Object.entries(store?.devices || {}).filter(([, row]) => valid(row, nowMs)));
  delete devices[input.device_key];
  if (input.protocol === 1) devices[input.device_key] = {
    tenant_id: input.tenant_id, company_id: input.company_id, driver_id: input.driver_id,
    device_key: input.device_key, protocol: 1, seen_at_ms: nowMs,
    ...(input.vehicle_device_id ? { vehicle_device_id: input.vehicle_device_id } : {}),
    valid_until_ms: Math.min(nowMs + (input.vehicle_device_id ? VEHICLE_DISPATCH_DEVICE_TTL_MS : DISPATCH_DEVICE_TTL_MS), input.session_expires_ms),
  };
  // Bound retained sessions per driver without deleting another driver's state.
  const rows = Object.values(devices).filter(row => row.driver_id === input.driver_id)
    .sort((a, b) => b.seen_at_ms - a.seen_at_ms || a.device_key.localeCompare(b.device_key));
  for (const row of rows.slice(4)) delete devices[row.device_key];
  return { ok: true, store: { scope: { tenant_id: input.tenant_id, company_id: input.company_id }, devices } };
}
