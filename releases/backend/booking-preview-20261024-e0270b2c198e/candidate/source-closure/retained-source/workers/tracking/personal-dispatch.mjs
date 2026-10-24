// _flutter_work/fluxidi_booking_live_9af4c215_rc/workers/tracking/modules/dispatch_device_capability.mjs
var matches = (row, scope) => row?.tenant_id === scope.tenant_id && row?.company_id === scope.company_id;
var valid = (row, nowMs) => row?.protocol === 1 && Number.isFinite(row.seen_at_ms) && row.seen_at_ms <= nowMs && nowMs < row.valid_until_ms;
function driverDispatchDevices(store, scope, driverId, nowMs, deviceKey = "") {
  if (!matches(store?.scope, scope)) return [];
  return Object.values(store.devices || {}).filter((row) => matches(row, scope) && row.driver_id === driverId && (!deviceKey || row.device_key === deviceKey) && valid(row, nowMs));
}

// _flutter_work/fluxidi_booking_live_9af4c215_rc/workers/shared/ride_execution_identity_v1.mjs
function frozenRideExecutionIdentityV1(identity, scope, driverId, vehicleId) {
  if (!identity || identity.tenant_id !== scope?.tenant_id || identity.company_id !== scope?.company_id || !driverId || !vehicleId || identity.driver_id !== driverId || identity.vehicle_id !== vehicleId) return null;
  const base = { tenant_id: scope.tenant_id, company_id: scope.company_id, driver_id: driverId, vehicle_id: vehicleId };
  if (identity.kind === "personal_driver_session") {
    if (identity.duty_id != null || typeof identity.acceptance_id !== "string" || !/^acceptance:[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/.test(identity.acceptance_id)) return null;
    return { ...base, kind: identity.kind, acceptance_id: identity.acceptance_id };
  }
  if (identity.kind != null || identity.acceptance_id != null || typeof identity.duty_id !== "string" || !identity.duty_id) return null;
  return { ...base, duty_id: identity.duty_id };
}

// _flutter_work/fluxidi_booking_live_9af4c215_rc/workers/tracking/modules/personal_driver_execution_v1.mjs
function personalDriverExecutionV1({ input, devices, duty, offer, nowMs = Date.now() }) {
  const a = input?.personal_execution_auth;
  if (a?.source !== "booking_personal_driver_session_v1" || a.tenant_id !== input.tenant_id || a.company_id !== input.company_id || a.driver_id !== input.driver_id || a.vehicle_id !== input.vehicle_id || a.device_key !== input.device_key || !Number.isFinite(a.session_expires_ms) || a.session_expires_ms <= nowMs) return null;
  const registered = driverDispatchDevices(devices, input, input.driver_id, nowMs, input.device_key);
  if (registered.length !== 1 || registered[0].vehicle_device_id) return null;
  if (duty?.duties?.some((d) => d.ended_at_ms === null && (d.driver_id === input.driver_id || d.vehicle_id === input.vehicle_id))) return null;
  if (!offer || offer.tenant_id !== input.tenant_id || offer.company_id !== input.company_id || offer.offer_id !== input.offer_id || offer.version !== input.version || offer.human_acceptance_required !== true || !offer.claims?.some((c) => c.driver_id === input.driver_id && c.vehicle_id === input.vehicle_id)) return null;
  const previous = offer.receipts?.[input.driver_id]?.execution_identity;
  if (previous) return frozenRideExecutionIdentityV1(previous, input, input.driver_id, input.vehicle_id);
  return {
    tenant_id: input.tenant_id,
    company_id: input.company_id,
    driver_id: input.driver_id,
    vehicle_id: input.vehicle_id,
    kind: "personal_driver_session",
    acceptance_id: "acceptance:" + crypto.randomUUID()
  };
}
export {
  personalDriverExecutionV1
};
