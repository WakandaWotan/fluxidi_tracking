import { json } from './http_response.js';
import { bookingWorkerHasRatehawkCredentials, RATEHAWK_HOTELS_INTERNAL_PROXY } from './ratehawk_hotels_facade.mjs';
import { issueTestContentContext, isTestContentPrincipalAllowed, TEST_CONTENT_READ, TEST_CONTENT_IMPORT } from '../../ratehawk-hotels/modules/ratehawk_test_content_context.mjs';
import { TEST_CONTENT_READ_PATH, TEST_CONTENT_IMPORT_PATH } from '../../ratehawk-hotels/modules/ratehawk_test_content.mjs';

export const CUSTOMER_TEST_CONTENT_PATH = '/customer/hotels/ratehawk/test-content';
export const ADMIN_TEST_CONTENT_IMPORT_PATH = '/admin/hotels/ratehawk/test-content/import';
const QUERY_KEYS = ['language', 'country', 'city', 'searchText', 'cursor', 'limit'];
const MAX_BYTES = 1024 * 1024;

export function testContentResponse(body, status = 200) {
  const response = json(body, status);
  response.headers.set('cache-control', 'private, no-store');
  return response;
}
const fail = (reason, status) => testContentResponse({ ok: false, reason }, status);

function readQuery(request) {
  const params = new URL(request.url).searchParams;
  if ([...params.keys()].some(key => !QUERY_KEYS.includes(key) || params.getAll(key).length !== 1)) return null;
  const payload = Object.fromEntries(params);
  if (!['en', 'nl', 'fr', 'es'].includes(payload.language) ||
      payload.country != null && !['BE', 'NL'].includes(payload.country) ||
      ['city', 'searchText'].some(key => payload[key] != null && payload[key].length > 100) ||
      payload.cursor != null && !/^(0|[1-9]|1[0-9]|20)$/.test(payload.cursor) ||
      payload.limit != null && !/^([1-9]|1[0-9]|20)$/.test(payload.limit)) return null;
  if (payload.limit != null) payload.limit = Number(payload.limit);
  return payload;
}

async function proxyTestContent(env, identity, purpose, payload) {
  // The gateway has no provider transport, credential resolver, payment action,
  // production binding fallback, or client identity override.
  if (!isTestContentPrincipalAllowed(env, identity, purpose)) return fail('test_content_forbidden', 403);
  if (bookingWorkerHasRatehawkCredentials(env) || typeof env.RATEHAWK_TEST_CONTENT_CONTEXT_SECRET !== 'string' ||
      env.RATEHAWK_TEST_CONTENT_CONTEXT_SECRET.length < 32 || !env.RATEHAWK_HOTELS_TEST?.fetch) {
    return fail('test_content_unavailable', 503);
  }
  try {
    const issued = await issueTestContentContext(env, identity, purpose, payload);
    if (!issued.ok) return fail('test_content_forbidden', 403);
    const path = purpose === TEST_CONTENT_IMPORT ? TEST_CONTENT_IMPORT_PATH : TEST_CONTENT_READ_PATH;
    const result = await env.RATEHAWK_HOTELS_TEST.fetch(new Request(`https://fluxidi-ratehawk-hotels-api-test.internal${path}`, {
      method: 'POST', headers: { 'content-type': 'application/json',
        'x-fluxidi-internal-proxy': RATEHAWK_HOTELS_INTERNAL_PROXY },
      body: JSON.stringify({ context: issued.token, payload }),
    }));
    const dto = await result.json();
    if (!result.ok || dto?.ok !== true) {
      const status = [400, 403, 413, 503].includes(result.status) ? result.status : 503;
      const safeReasons = ['test_content_forbidden', 'invalid_query', 'invalid_import', 'invalid_projection',
        'body_too_large', 'test_content_storage_missing', 'test_content_storage_unavailable', 'test_content_import_incomplete'];
      if (purpose === TEST_CONTENT_IMPORT && status === 503 && dto?.reason === 'test_content_import_incomplete' &&
          Number.isInteger(dto.applied) && dto.applied >= 0 && dto.applied <= 80) {
        return testContentResponse({ ok: false, reason: dto.reason, applied: dto.applied }, 503);
      }
      return fail(safeReasons.includes(dto?.reason) ? dto.reason : 'test_content_unavailable', status);
    }
    if (purpose === TEST_CONTENT_IMPORT) {
      if (dto.surface !== 'test' || dto.provider_requested !== false || !Number.isInteger(dto.applied)) return fail('test_content_unavailable', 503);
      return testContentResponse({ ok: true, applied: dto.applied, surface: 'test', provider_requested: false });
    }
    if (dto.source !== 'ratehawk-test-content' || dto.surface !== 'test' || dto.test_content !== true ||
        dto.booking_enabled !== false || dto.provider_requested !== false || !Array.isArray(dto.stays) || dto.stays.length > 20 ||
        dto.stays.some(stay => stay.type !== 'stay' || stay.surface !== 'test' || stay.test_content !== true ||
          stay.booking_enabled !== false || stay.has_live_rates !== false || stay.is_real_approved !== false) ||
        JSON.stringify(dto.stays).includes(issued.token)) return fail('test_content_unavailable', 503);
    return testContentResponse({ ok: true, source: dto.source, stays: dto.stays, count: dto.count,
      total_count: dto.total_count, next_cursor: dto.next_cursor, provider_requested: false,
      content_sync_started: false, surface: 'test', test_content: true, booking_enabled: false });
  } catch { return fail('test_content_unavailable', 503); }
}

// Session is supplied only by the ordinary Worker's authenticated loader.
export async function handleCustomerTestContent({ request, env, session }) {
  if (!session) return fail('unauthorized', 401);
  const payload = readQuery(request);
  if (!payload) return fail('invalid_query', 400);
  return proxyTestContent(env, { subject: session.customer_id, tenant_id: session.tenant_id,
    company_id: session.company_id }, TEST_CONTENT_READ, payload);
}

// Admin authorization MUST run in the entrypoint before reading this body.
export async function handleAdminTestContentImport({ request, env }) {
  let identity;
  try { identity = JSON.parse(env.RATEHAWK_TEST_CONTENT_IMPORT_PRINCIPAL ?? 'null'); } catch { return fail('test_content_unavailable', 503); }
  if (!identity || typeof identity !== 'object' || Array.isArray(identity) ||
      Object.keys(identity).some(key => !['subject', 'tenant_id', 'company_id'].includes(key))) return fail('test_content_unavailable', 503);
  // Check server capability before allocating a request body.
  if (!isTestContentPrincipalAllowed(env, identity, TEST_CONTENT_IMPORT)) return fail('test_content_forbidden', 403);
  let payload;
  try {
    if (Number(request.headers.get('content-length')) > MAX_BYTES) return fail('body_too_large', 413);
    const reader = request.body?.getReader();
    if (!reader) return fail('invalid_import', 400);
    const chunks = []; let size = 0;
    while (true) {
      const { value, done } = await reader.read(); if (done) break;
      size += value.byteLength;
      if (size > MAX_BYTES) { await reader.cancel(); return fail('body_too_large', 413); }
      chunks.push(value);
    }
    const bytes = new Uint8Array(size); let offset = 0;
    for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.byteLength; }
    payload = JSON.parse(new TextDecoder().decode(bytes));
  } catch { return fail('invalid_import', 400); }
  if (!payload || typeof payload !== 'object' || Array.isArray(payload) ||
      Object.keys(payload).some(key => !['evidence', 'projections'].includes(key))) return fail('invalid_import', 400);
  return proxyTestContent(env, identity, TEST_CONTENT_IMPORT, payload);
}
