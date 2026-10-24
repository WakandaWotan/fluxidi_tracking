import { createRatehawkD1ContentRepository, assertPersistableHotelContent } from './ratehawk_content_store.mjs';
import { readRatehawkContentCatalog } from './ratehawk_content_catalog.mjs';
import { TEST_CONTENT_READ, TEST_CONTENT_IMPORT, verifyTestContentContext } from './ratehawk_test_content_context.mjs';

export const TEST_CONTENT_READ_PATH = '/internal/test-content-catalog';
export const TEST_CONTENT_IMPORT_PATH = '/internal/test-content-import';
const LOCALES = ['en', 'nl', 'fr', 'es'];
const MAX_BYTES = 1024 * 1024;
const response = (body, status = 200) => Response.json(body, { status,
  headers: { 'cache-control': 'private, no-store' } });
const blocked = () => response({ ok: false, reason: 'test_content_forbidden' }, 403);
// References only: no image download, provider request or production DTO change.
function privateGalleryImages(hotel) {
  const images = []; const seen = new Set();
  for (const item of (Array.isArray(hotel?.image_refs) ? hotel.image_refs : []).slice(0, 100)) {
    if (typeof item?.ref !== 'string' || item.ref.length > 2048 || !validTestImage(item)) continue;
    try {
      const url = new URL(item.ref.trim().replaceAll('{size}', 'x500'));
      const path = url.pathname.toLowerCase();
      if (url.protocol !== 'https:' || !url.hostname || url.username || url.password || url.hash ||
          path.includes('/public/hotels/google-place-photo') ||
          (url.hostname === 'maps.googleapis.com' && path.includes('/place/photo')) ||
          (url.hostname === 'places.googleapis.com' && path.includes('/photos/'))) continue;
      const ref = url.href;
      if (!seen.has(ref)) { seen.add(ref); images.push(ref); }
    } catch { /* Invalid references cannot become gallery requests. */ }
  }
  return images;
}
function validTestImage(ref) {
  try {
    const url = new URL(ref?.ref);
    return ref.binary === false && url.protocol === 'https:' && url.hostname === 'cdn.worldota.net' &&
      !url.username && !url.password && !url.port && !url.search && !url.hash && url.pathname.startsWith('/t/');
  } catch { return false; }
}
function allowedHids(env) {
  try {
    const ids = JSON.parse(env.RATEHAWK_TEST_CONTENT_HIDS ?? '[]');
    if (!Array.isArray(ids) || ids.length < 1 || ids.length > 20 ||
        ids.some(id => !Number.isInteger(id) || id < 1 || id > 9999999999)) return null;
    return new Set(ids);
  } catch { return null; }
}
function testSurface(env) {
  return env.RATEHAWK_WORKER_SURFACE === 'test' && env.RATEHAWK_ENVIRONMENT === 'test' &&
    env.RATEHAWK_BASE_URL === 'https://api.ratehawk.com' &&
    env.RATEHAWK_TEST_CONTENT_STORAGE_DOMAIN === 'test' &&
    ['RATEHAWK_ENABLED', 'RATEHAWK_BOOKING_FORM_ENABLED', 'RATEHAWK_BOOKING_FINISH_ENABLED',
      'RATEHAWK_BOOKING_STATUS_ENABLED', 'RATEHAWK_PREBOOK_ENABLED', 'RATEHAWK_TEST_PREBOOK_ENABLED']
      .every(key => env[key] === '0' || env[key] === false);
}

// No fetch, credential resolver or production DB fallback. Store injection is
// test-only dependency injection, never accepted from HTTP/env data.
export async function handleTestContentRequest(request, env, { now = Date.now(), store = null } = {}) {
  const path = new URL(request.url).pathname;
  if (![TEST_CONTENT_READ_PATH, TEST_CONTENT_IMPORT_PATH].includes(path) || request.method !== 'POST')
    return response({ ok: false }, 404);
  if (!testSurface(env)) return blocked();
  const hids = allowedHids(env);
  if (!hids) return blocked();
  let body;
  try {
    const declared = Number(request.headers.get('content-length'));
    if (declared > MAX_BYTES) return response({ ok: false, reason: 'body_too_large' }, 413);
    // Bounded streaming: do not allocate an unbounded body before checking size.
    const reader = request.body?.getReader();
    if (!reader) return response({ ok: false, reason: 'invalid_body' }, 400);
    const chunks = []; let size = 0;
    while (true) {
      const { value, done } = await reader.read(); if (done) break;
      size += value.byteLength;
      if (size > MAX_BYTES) { await reader.cancel(); return response({ ok: false, reason: 'body_too_large' }, 413); }
      chunks.push(value);
    }
    const bytes = new Uint8Array(size); let offset = 0;
    for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.byteLength; }
    body = JSON.parse(new TextDecoder().decode(bytes));
  } catch { return response({ ok: false, reason: 'invalid_body' }, 400); }
  if (!body || typeof body !== 'object' || Array.isArray(body) ||
      Object.keys(body).some(key => !['context', 'payload'].includes(key))) return blocked();
  const purpose = path === TEST_CONTENT_IMPORT_PATH ? TEST_CONTENT_IMPORT : TEST_CONTENT_READ;
  const auth = await verifyTestContentContext(env, body.context, purpose, body.payload, { now });
  if (!auth.ok) return blocked();
  const db = env.RATEHAWK_TEST_CONTENT_DB;
  if (!store && !db?.prepare) return response({ ok: false, reason: 'test_content_storage_missing' }, 503);
  const repository = store ?? createRatehawkD1ContentRepository(db);
  const payload = body.payload;
  if (!payload || typeof payload !== 'object' || Array.isArray(payload))
    return response({ ok: false, reason: 'invalid_payload' }, 400);
  try {
    if (purpose === TEST_CONTENT_IMPORT) {
      if (Object.keys(payload).some(key => !['evidence', 'projections'].includes(key)) ||
          payload.evidence?.host !== 'api.ratehawk.com' || payload.evidence?.keyId !== '18292' ||
          payload.evidence?.surface !== 'isolated_test' || payload.evidence?.production_allowed !== false ||
          payload.evidence?.live_rates !== false || !Array.isArray(payload.projections) ||
          payload.projections.length < 1 || payload.projections.length > 80)
        return response({ ok: false, reason: 'invalid_import' }, 400);
      const keys = new Set();
      for (const projection of payload.projections) {
        const key = `${projection.hid}:${projection.locale}`;
        if (keys.has(key) || !hids.has(projection.hid) || !LOCALES.includes(projection.locale) ||
            !assertPersistableHotelContent(projection).ok || projection.ok !== true ||
            projection.kind !== 'offline_static' || projection.tombstone !== false ||
            projection.live_price_excluded !== true || projection.has_live_rates !== false ||
            projection.description_indexed !== false || !/^((BE)|(NL)):[^:]{1,100}$/.test(projection.market_key) ||
            !Array.isArray(projection.image_refs) || projection.image_refs.length > 100 ||
            projection.image_refs.some(ref => !validTestImage(ref)) ||
            !Number.isFinite(projection.coordinates?.lat) || Math.abs(projection.coordinates.lat) > 90 ||
            !Number.isFinite(projection.coordinates?.lng) || Math.abs(projection.coordinates.lng) > 180)
          return response({ ok: false, reason: 'invalid_projection' }, 400);
        keys.add(key);
      }
      const run = await repository.allocateRun({ now, market_key: 'isolated_test_seed' });
      let applied = 0;
      for (const projection of payload.projections) {
        const outcome = await repository.applyNormalized({ projection, generation: run.generation,
          now, market_key: projection.market_key });
        if (!outcome.written && outcome.reason !== 'unchanged')
          return response({ ok: false, reason: 'test_content_import_incomplete', applied }, 503);
        applied++;
      }
      return response({ ok: true, applied, surface: 'test', provider_requested: false });
    }
    if (Object.keys(payload).some(key => !['language', 'country', 'city', 'searchText', 'cursor', 'limit'].includes(key)) ||
        !LOCALES.includes(payload.language) ||
        (payload.country != null && !['BE', 'NL'].includes(payload.country)) ||
        (payload.limit != null && (!Number.isInteger(payload.limit) || payload.limit < 1 || payload.limit > 20)) ||
        (payload.cursor != null && (typeof payload.cursor !== 'string' || !/^(0|[1-9]|1[0-9]|20)$/.test(payload.cursor))) ||
        ['city', 'searchText'].some(key => payload[key] != null &&
          (typeof payload[key] !== 'string' || payload[key].length > 100)))
      return response({ ok: false, reason: 'invalid_query' }, 400);
    // Production catalog's environment guard is unchanged. Reuse its pure
    // renderer against this independently authorized PRIVATE TEST repository.
    const readHotels = new Map();
    const renderingStore = {
      applyNormalized: repository.applyNormalized.bind(repository),
      listSearchIndex: async () => (await repository.listSearchIndex()).filter(row => hids.has(row.hid)),
      readPublic: async args => {
        const hotel = await repository.readPublic(args);
        readHotels.set(args.hid, hotel);
        return hotel;
      },
    };
    const catalog = await readRatehawkContentCatalog({ store: renderingStore, query: payload });
    const stays = [];
    for (const stay of catalog.stays.filter(stay => hids.has(stay.hid))) {
      const hotel = readHotels.get(stay.hid);
      const imageUrls = privateGalleryImages(hotel);
      stays.push({ ...stay, type: 'stay', property_kind: hotel.categories?.property_kind ?? null,
        image_url: imageUrls[0] ?? null, image_urls: imageUrls,
        is_real_approved: false, surface: 'test', test_content: true,
        booking_enabled: false, has_live_rates: false });
    }
    const offset = Number(payload.cursor ?? 0);
    const limit = payload.limit ?? 20;
    const page = stays.slice(offset, offset + limit);
    return response({ ...catalog, source: 'ratehawk-test-content', stays: page, count: page.length,
      total_count: stays.length, next_cursor: offset + page.length < stays.length ? String(offset + page.length) : null,
      surface: 'test', test_content: true, booking_enabled: false });
  } catch { return response({ ok: false, reason: 'test_content_storage_unavailable' }, 503); }
}
