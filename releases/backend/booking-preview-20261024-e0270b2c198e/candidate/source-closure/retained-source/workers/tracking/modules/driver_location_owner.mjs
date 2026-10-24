// Bearer identity is supplied only by Tracking's authenticated session loader.
// Activation/device are opaque generation labels, never authentication claims.
export const LOCATION_RETIRED_OWNER_LIMIT = 512;
const label = value => typeof value === 'string' && /^[A-Za-z0-9_-]{1,128}$/.test(value);

export function driverLocationOwner(session, body = {}, { requireActivation = false } = {}) {
  const activation = body.activation_id;
  const suppliedDevice = body.native_device_id;
  if (activation != null && !label(activation) || suppliedDevice != null && !label(suppliedDevice)
    || requireActivation && !label(activation)) return { ok: false, status: 400, error: 'location_owner_invalid' };
  const boundDevice = session?.native_device_id || null;
  if (boundDevice && suppliedDevice !== boundDevice) {
    return { ok: false, status: 403, error: 'location_device_mismatch' };
  }
  if (!/^[a-f0-9]{64}$/.test(session?.token_hash || '') || !Number.isFinite(session?.expires_ms)) {
    return requireActivation ? { ok: false, status: 401, error: 'unauthorized' } : { ok: true, owner: null };
  }
  return { ok: true, owner: {
    session_hash: session.token_hash, activation_id: activation || null,
    native_device_id: boundDevice || suppliedDevice || null,
    session_expires_ms: session.expires_ms,
  } };
}

export function boundLocationOwner(owner, nowMs) {
  return Boolean(owner && /^[a-f0-9]{64}$/.test(owner.session_hash || '') && label(owner.activation_id)
    && (owner.native_device_id == null || label(owner.native_device_id))
    && Number.isFinite(owner.session_expires_ms) && owner.session_expires_ms > nowMs);
}

export function sameLocationOwner(left, right) {
  return Boolean(left && right && left.session_hash === right.session_hash
    && left.activation_id === right.activation_id && left.native_device_id === right.native_device_id);
}

export function retainedLocationOwners(row, nowMs) {
  return (Array.isArray(row?.retired_publications) ? row.retired_publications : [])
    .filter(owner => boundLocationOwner(owner, nowMs)).slice(0, LOCATION_RETIRED_OWNER_LIMIT);
}

export function locationOwnerRetired(row, owner, nowMs) {
  return Boolean(boundLocationOwner(owner, nowMs) && (
    row?.location_withdrawn === true && sameLocationOwner(row.publication_owner, owner)
    || retainedLocationOwners(row, nowMs).some(retired => sameLocationOwner(retired, owner))));
}

export function nextRetiredLocationOwners(row, owner, nowMs) {
  const retained = retainedLocationOwners(row, nowMs);
  const previous = row?.publication_owner;
  if (boundLocationOwner(previous, nowMs) && !sameLocationOwner(previous, owner)
    && !retained.some(retired => sameLocationOwner(retired, previous))) {
    if (retained.length >= LOCATION_RETIRED_OWNER_LIMIT) return null;
    retained.push(previous);
  }
  return retained;
}
