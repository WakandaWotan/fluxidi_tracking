// The existing navigation surface delegates only to the authenticated Booking
// authority. No public provider, coordinate cache or caller-selected host.
const json = (value, status = 200) => new Response(JSON.stringify(value), {status, headers: {
  'content-type': 'application/json; charset=utf-8', 'cache-control': 'no-store',
  'access-control-allow-origin': '*', ...(status === 429 ? {'retry-after': '10'} : {}),
}});
const fail = (error, status) => json({ok:false, error, provider_fallback:false}, status);
const hex = value => typeof value === 'string' && /^[a-f0-9]{64}$/.test(value);
const scopePart = value => typeof value === 'string' && value.length > 0 && value.length <= 200 && !/[\r\n\0]/.test(value);

export async function boundedNavigationJson(message, limit, timeoutMs = 5000) {
  const length = message.headers.get('content-length');
  if (length !== null && (!/^\d+$/.test(length) || Number(length) > limit)) throw Error('body_limit');
  if (!message.body) throw Error('body_invalid');
  const reader = message.body.getReader(), chunks = []; let size = 0, expired = false;
  const cancel = () => {void reader.cancel().catch(() => {});};
  const timer = setTimeout(() => {expired = true; cancel();}, timeoutMs);
  message.signal?.addEventListener('abort', cancel, {once:true});
  try {
    for (;;) {
      const {done, value} = await reader.read(); if (done) break;
      size += value.byteLength;
      if (size > limit) {await reader.cancel(); throw Error('body_limit');}
      chunks.push(value);
    }
    if (expired || message.signal?.aborted) throw Error('body_deadline');
    const bytes = new Uint8Array(size); let offset = 0;
    for (const chunk of chunks) {bytes.set(chunk, offset); offset += chunk.byteLength;}
    return JSON.parse(new TextDecoder('utf-8', {fatal:true}).decode(bytes));
  } finally {
    clearTimeout(timer); message.signal?.removeEventListener('abort', cancel); reader.releaseLock();
  }
}

async function storeSummary(env, scope, tripId, route) {
  if (!tripId || !env.ROUTE_SESSION) return false;
  if (!scopePart(scope?.tenant_id) || !scopePart(scope?.company_id) || scope.driver_id != null && !scopePart(scope.driver_id)) return false;
  // Full identity, including tenant and driver, is hashed rather than truncated.
  const bytes = new TextEncoder().encode(JSON.stringify(['national-v1', scope.tenant_id, scope.company_id, scope.driver_id ?? null, tripId]));
  const digest = await crypto.subtle.digest('SHA-256', bytes);
  const key = Array.from(new Uint8Array(digest), b => b.toString(16).padStart(2,'0')).join('');
  try {
    const stub = env.ROUTE_SESSION.get(env.ROUTE_SESSION.idFromName('national-v1:' + key));
    const response = await stub.fetch(new Request('https://route-session.internal/summary', {
      method:'PUT', headers:{'content-type':'application/json'}, signal:AbortSignal.timeout(2000),
      body:JSON.stringify({trip_id:tripId, route_hash:route.route_hash, distance_m:route.distance_m, duration_s:route.duration_s, profile:'driving'}),
    }));
    if (response.status !== 200) {await response.body?.cancel(); return false;}
    const ack = await boundedNavigationJson(response, 2048, 2000);
    return ack?.ok === true && ack.stored === true;
  } catch {return false;}
}

export async function relayNationalNavigation(request, env, {clock = Date.now} = {}) {
  const path = new URL(request.url).pathname;
  if (!['/route','/reroute'].includes(path)) return null;
  if (request.method !== 'POST') return fail('method_not_allowed', 405);
  const auth = request.headers.get('authorization');
  if (!auth || !/^Bearer [^\s]{1,4096}$/.test(auth)) return fail('unauthorized', 401);
  if (typeof env.BOOKING_ROUTER?.fetch !== 'function') return fail('national_navigation_unavailable', 503);
  if (request.headers.has('content-encoding') || !/^application\/json(?:\s*;\s*charset=utf-8)?$/i.test(request.headers.get('content-type') ?? '')) return fail('navigation_input_invalid',400);
  let body;
  try {body = await boundedNavigationJson(request,8192);} catch (e) {return fail('navigation_input_invalid', e.message === 'body_limit' ? 413 : e.message === 'body_deadline' ? 408 : 400);}
  if (!body || typeof body !== 'object' || Array.isArray(body) || body.trip_id != null && (!scopePart(body.trip_id) || body.trip_id.length > 160)) return fail('navigation_input_invalid',400);
  const controller = new AbortController();
  const cancel = () => controller.abort(); request.signal.addEventListener('abort', cancel, {once:true});
  const timer = setTimeout(cancel, 20000);
  try {
    if (request.signal.aborted) return fail('navigation_cancelled',499);
    const headers = new Headers({'content-type':'application/json','authorization':auth});
    // Do not forward arbitrary identity/host/proxy headers supplied by callers.
    const ip = request.headers.get('cf-connecting-ip'); if (ip && ip.length <= 64) headers.set('cf-connecting-ip',ip);
    const response = await env.BOOKING_ROUTER.fetch(new Request('https://fluxidi-booking-api.fluxidi.workers.dev/company/navigation' + path, {
      method:'POST', headers, body:JSON.stringify(body), signal:controller.signal,
    }));
    const result = await boundedNavigationJson(response,8 * 1024 * 1024,15000);
    if (controller.signal.aborted) return fail('navigation_deadline',504);
    if (response.status !== 200) {
      const error = typeof result?.error === 'string' && /^[a-z][a-z0-9_]{0,100}$/.test(result.error) ? result.error : 'navigation_route_unavailable';
      return fail(error, [400,401,403,408,409,413,422,429,503,504].includes(response.status) ? response.status : 502);
    }
    if (result?.ok !== true || result.source !== 'fluxidi-national' || result.provider_source != null || result.route_basis !== 'owned_immutable_route'
      || !hex(result.route_hash) || !hex(result.navigation_metadata_sha256) || !scopePart(result.graph_version) || !scopePart(result.evidence_revision)
      || !Number.isFinite(result.valid_until_ms) || result.valid_until_ms <= clock() || !scopePart(result.session_scope?.tenant_id) || !scopePart(result.session_scope?.company_id)
      || !Number.isFinite(result.distance_m) || result.distance_m < 0 || !Number.isFinite(result.duration_s) || result.duration_s < 0
      || result.geometry?.type !== 'LineString' || !Array.isArray(result.geometry.coordinates) || result.geometry.coordinates.length < 2 || !Array.isArray(result.legs) || !result.legs.length) return fail('navigation_contract_invalid',502);
    const stored = await storeSummary(env,result.session_scope,body.trip_id,result);
    if (request.signal.aborted) return fail('navigation_cancelled',499);
    if (result.valid_until_ms <= clock()) return fail('navigation_route_lease_expired',409);
    const {session_scope: omitted, ...publicResult} = result;
    return json({...publicResult, route_session_updated:stored});
  } catch {return fail(request.signal.aborted ? 'navigation_cancelled' : 'navigation_route_unavailable',request.signal.aborted ? 499 : 503);}
  finally {clearTimeout(timer); request.signal.removeEventListener('abort',cancel);}
}
