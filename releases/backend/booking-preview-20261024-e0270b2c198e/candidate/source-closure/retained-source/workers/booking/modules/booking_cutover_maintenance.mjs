// Authenticated HTTP maintenance routes mint short-lived, payload-bound
// service capabilities. JSON fields and client headers cannot enable them.
const context = Symbol('bookingCutoverMaintenance');
const header = 'x-fluxidi-cutover-proof';
const names = { COMPANY_CUSTOMER_IMPORT_COORDINATOR: 'company',
  CANONICAL_BOOKING_DIRECTORY: 'directory', DRIVER_INDEX_COORDINATOR: 'driver', FLEET_ALLOCATOR: 'fleet' };
const scopeOf = body => body?.scope || body;
const same = (a, b) => a?.tenant_id === b?.tenant_id && a?.company_id === b?.company_id;
const valid = scope => typeof scope?.tenant_id === 'string' && typeof scope?.company_id === 'string'
  && scope.tenant_id.length > 0 && scope.company_id.length > 0 && scope.tenant_id.length <= 80 && scope.company_id.length <= 80;
const encode = value => btoa(String.fromCharCode(...new TextEncoder().encode(value)));
const decode = value => new TextDecoder().decode(Uint8Array.from(atob(value), c => c.charCodeAt(0)));
const hex = bytes => [...new Uint8Array(bytes)].map(n => n.toString(16).padStart(2, '0')).join('');
async function key(env) {
  if (!env.ADMIN_TOKEN) throw Error('cutover_admin_secret_unavailable');
  return crypto.subtle.importKey('raw', new TextEncoder().encode(env.ADMIN_TOKEN), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign', 'verify']);
}
function allowed(target, body, permission) {
  const id = body?.bookingId || body?.booking_id;
  if (permission.bookingId && id && permission.bookingId !== id) return false;
  if (target !== 'directory' || body.operation === 'claim') {
    if (!same(scopeOf(body), permission.scope)) return false;
  }
  if (target === 'company') return body.action === 'canonical_booking'
    && ['inspect', 'read', 'write'].includes(body.operation)
    || body.action === 'tracking_booking_mutation'
    && ['capacity_baseline', 'cancelled_leg_reconciliation', 'capacity_projection_rebuild'].includes(body.kind);
  if (target === 'directory') return ['read', 'claim'].includes(body.operation)
    && (!permission.bookingId || body.bookingId === permission.bookingId);
  if (target === 'fleet') return body.action === 'release' && Boolean(permission.bookingId)
    && body.booking_id === permission.bookingId;
  if (target === 'driver') return body.action === 'read' || body.action === 'mutate'
    && Boolean(permission.bookingId) && body.mutation?.op === 'sync_dispatch_availability';
  return false;
}
export function withBookingCutoverMaintenance(env, scope, bookingId = null) {
  if (env.BOOKING_WRITER_PAUSE_ENABLED !== '1') return env;
  if (!valid(scope)) throw Error('cutover_scope_required');
  const permission = { scope: { tenant_id: scope.tenant_id, company_id: scope.company_id }, bookingId };
  const wrapped = { ...env, [context]: permission };
  for (const [name, target] of Object.entries(names)) {
    const binding = env[name]; if (!binding?.get) continue;
    wrapped[name] = new Proxy(binding, { get(object, property) {
      if (property !== 'get') { const value = Reflect.get(object, property); return typeof value === 'function' ? value.bind(object) : value; }
      return id => {
        const stub = binding.get(id);
        return new Proxy(stub, { get(object, property) {
          if (property !== 'fetch') { const value = Reflect.get(object, property); return typeof value === 'function' ? value.bind(object) : value; }
          return async (input, init) => {
            const req = input instanceof Request && !init ? input : new Request(input, init);
            const text = await req.clone().text(); let body;
            try { body = JSON.parse(text); } catch { throw Error('cutover_request_invalid'); }
            if (!allowed(target, body, permission)) throw Error('cutover_operation_forbidden');
            const proof = encode(JSON.stringify({ schema: 1, target, ...permission, expires: Date.now() + 120_000,
              digest: hex(await crypto.subtle.digest('SHA-256', new TextEncoder().encode(text))) }));
            const signature = hex(await crypto.subtle.sign('HMAC', await key(env), new TextEncoder().encode(proof)));
            const headers = new Headers(req.headers); headers.set(header, `${proof}.${signature}`);
            return stub.fetch(new Request(req, { headers }));
          };
        } });
      };
    } });
  }
  return wrapped;
}
export async function verifyBookingCutoverRequest(env, request, target) {
  if (env.BOOKING_WRITER_PAUSE_ENABLED !== '1') return null;
  try {
    const parts = (request.headers.get(header) || '').split('.');
    if (parts.length !== 2 || !/^[a-f0-9]{64}$/.test(parts[1]) || parts[0].length > 1600) return null;
    const signature = Uint8Array.from(parts[1].match(/../g), s => parseInt(s, 16));
    if (!await crypto.subtle.verify('HMAC', await key(env), signature, new TextEncoder().encode(parts[0]))) return null;
    const proof = JSON.parse(decode(parts[0]));
    if (proof.schema !== 1 || proof.target !== target || !valid(proof.scope)
      // Different Worker/DO hosts can have slightly different wall clocks.
      // Keep the capability short-lived while allowing bounded clock skew.
      || !Number.isSafeInteger(proof.expires) || proof.expires < Date.now() - 5_000
      || proof.expires > Date.now() + 125_000) return null;
    const text = await request.clone().text();
    if (proof.digest !== hex(await crypto.subtle.digest('SHA-256', new TextEncoder().encode(text)))
      || !allowed(target, JSON.parse(text), proof)) return null;
    return { scope: proof.scope, bookingId: proof.bookingId || null };
  } catch { return null; }
}

// Inspection-only use of the existing payload-bound service capability pattern.
// Separate target/header: this grants no cutover permission and does not pause writers.
const inspectionHeader = 'x-fluxidi-inspection-proof';
const inspectionTarget = 'tracking-canonical-inspection';
export async function signCanonicalInspectionRequest(env, request) {
  const text = await request.clone().text(), body = JSON.parse(text);
  if (request.method !== 'POST' || new URL(request.url).pathname !== '/canonical-inspection'
    || body.action !== 'canonical_booking_inspection' || !valid(body.scope) || !body.bookingId) {
    throw Error('inspection_capability_scope_invalid');
  }
  const proof = encode(JSON.stringify({ schema: 1, target: inspectionTarget, scope: body.scope,
    bookingId: body.bookingId, expires: Date.now() + 120_000, method: 'POST', path: '/canonical-inspection',
    digest: hex(await crypto.subtle.digest('SHA-256', new TextEncoder().encode(text))) }));
  const signature = hex(await crypto.subtle.sign('HMAC', await key(env), new TextEncoder().encode(proof)));
  // Never forward the long-lived administrator credential across this boundary.
  return new Request(request.url, { method: 'POST', body: text,
    headers: { 'content-type': 'application/json', [inspectionHeader]: `${proof}.${signature}` } });
}
export async function verifyCanonicalInspectionRequest(env, request) {
  try {
    const parts = (request.headers.get(inspectionHeader) || '').split('.');
    if (parts.length !== 2 || parts[0].length > 1600 || !/^[a-f0-9]{64}$/.test(parts[1])) return null;
    const signature = Uint8Array.from(parts[1].match(/../g), s => parseInt(s, 16));
    if (!await crypto.subtle.verify('HMAC', await key(env), signature, new TextEncoder().encode(parts[0]))) return null;
    const proof = JSON.parse(decode(parts[0])), now = Date.now();
    if (proof.schema !== 1 || proof.target !== inspectionTarget || !valid(proof.scope)
      || proof.method !== 'POST' || request.method !== proof.method || proof.path !== '/canonical-inspection'
      || new URL(request.url).pathname !== proof.path || !Number.isSafeInteger(proof.expires)
      || proof.expires <= now || proof.expires > now + 125_000) return null;
    const text = await request.clone().text(), body = JSON.parse(text);
    if (body.action !== 'canonical_booking_inspection' || !same(body.scope, proof.scope)
      || body.bookingId !== proof.bookingId
      || proof.digest !== hex(await crypto.subtle.digest('SHA-256', new TextEncoder().encode(text)))) return null;
    return { scope: proof.scope, bookingId: proof.bookingId };
  } catch { return null; }
}
