/**
 * Stay22 Europe P1C — opaque Google Places page-2 cursors.
 *
 * Stores provider next_page_token in BOOKING_KV only.
 * Never returns the provider token or a complete Google URL to clients.
 *
 * KV limitation: get-then-put is not strictly atomic. A parallel page-2 race
 * can theoretically pass validation twice. Flutter double-submit locking and
 * best-effort consume/delete are the complementary controls.
 */

export const HOTEL_PLACES_CURSOR_PREFIX = "hotel_places_cursor:v1:";
export const HOTEL_PLACES_CURSOR_TTL_SECONDS = 600;
export const HOTEL_PLACES_ACTIVATION_DELAY_MS = 2000;
export const HOTEL_PLACES_MAX_PAGES = 2;
export const EVENT_VENUE_GEOCODE_PREFIX = "event_venue_geocode:v1:";

const CURSOR_ID_RE = /^[A-Za-z0-9_-]{16,80}$/;
const PROVIDER_TOKEN_RE = /^[A-Za-z0-9_-]{10,800}$/;

export function normalizeHotelPlacesCursorId(raw) {
  const text = String(raw ?? "").trim();
  if (!text) return "";
  const stripped = text.startsWith(HOTEL_PLACES_CURSOR_PREFIX)
    ? text.slice(HOTEL_PLACES_CURSOR_PREFIX.length)
    : text;
  if (!CURSOR_ID_RE.test(stripped)) return "";
  return stripped;
}

export function hotelPlacesCursorKey(cursorId) {
  const id = normalizeHotelPlacesCursorId(cursorId);
  if (!id) return "";
  return `${HOTEL_PLACES_CURSOR_PREFIX}${id}`;
}

export function isHotelPlacesCursorKey(key) {
  const text = String(key ?? "");
  return text.startsWith(HOTEL_PLACES_CURSOR_PREFIX) &&
    !text.startsWith(EVENT_VENUE_GEOCODE_PREFIX);
}

export function createHotelPlacesCursorId(randomBytesFn = defaultRandomBytes) {
  const bytes = randomBytesFn(18);
  return toUrlSafe(bytes);
}

function defaultRandomBytes(size) {
  if (globalThis.crypto?.getRandomValues) {
    const out = new Uint8Array(size);
    globalThis.crypto.getRandomValues(out);
    return out;
  }
  throw new Error("random_unavailable");
}

function toUrlSafe(bytes) {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/g, "");
}

export function hotelPlacesQueryFingerprint(query = {}) {
  const parts = [
    String(query.source ?? "google-places").trim().toLowerCase(),
    String(query.countryCode || query.country_code || "").trim().toUpperCase(),
    String(query.country ?? "").trim().toLowerCase(),
    String(query.city ?? "").trim().toLowerCase(),
    String(query.region ?? "").trim().toLowerCase(),
    String(query.destination ?? "").trim().toLowerCase(),
    String(query.searchText ?? query.q ?? "").trim().toLowerCase(),
  ];
  return parts.join("|");
}

export function fingerprintsMatch(left, right) {
  return String(left ?? "") === String(right ?? "");
}

export function queryConflictsWithCursor(query, record) {
  if (!record?.fingerprint) return true;
  const incoming = hotelPlacesQueryFingerprint(query);
  if (!incoming || incoming.split("|").slice(1).every((part) => part === "")) {
    return false;
  }
  return incoming !== record.fingerprint;
}

export function isUsableProviderToken(token) {
  return PROVIDER_TOKEN_RE.test(String(token ?? "").trim());
}

export function buildHotelPlacesCursorRecord({
  providerToken,
  fingerprint,
  countryCode,
  issuedAtMs,
  availableAtMs,
  page = 2,
}) {
  const token = String(providerToken ?? "").trim();
  if (!isUsableProviderToken(token)) return null;
  const issued = Number(issuedAtMs);
  const available = Number(availableAtMs);
  if (!Number.isFinite(issued) || !Number.isFinite(available)) return null;
  return {
    version: 1,
    page: page === 2 ? 2 : 0,
    issued_at: issued,
    available_at: available,
    fingerprint: String(fingerprint ?? ""),
    country_code: String(countryCode ?? "").trim().toUpperCase(),
    provider_token: token,
    consumed: false,
  };
}

export function publicHotelPlacesPagination({
  page,
  nextCursor = "",
  availableAtMs = null,
  hasMore = false,
}) {
  const safePage = page === 2 ? 2 : 1;
  const cursor = normalizeHotelPlacesCursorId(nextCursor);
  const more = hasMore === true && Boolean(cursor) && safePage === 1;
  const payload = {
    page: safePage,
    has_more: more,
    next_cursor: more ? cursor : null,
    max_pages: HOTEL_PLACES_MAX_PAGES,
  };
  if (more && Number.isFinite(Number(availableAtMs))) {
    payload.available_at = Number(availableAtMs);
  }
  return payload;
}

function asRecord(raw) {
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) return null;
  return raw;
}

export async function storeHotelPlacesCursor(env, record, {
  nowMs = Date.now(),
  randomBytesFn,
} = {}) {
  if (!env?.BOOKING_KV) return { ok: false, error: "missing_booking_kv" };
  const stored = buildHotelPlacesCursorRecord({
    ...record,
    issuedAtMs: record.issuedAtMs ?? nowMs,
    availableAtMs: record.availableAtMs ?? (nowMs + HOTEL_PLACES_ACTIVATION_DELAY_MS),
  });
  if (!stored || !stored.fingerprint) {
    return { ok: false, error: "invalid_cursor_record" };
  }
  const id = createHotelPlacesCursorId(randomBytesFn);
  const key = hotelPlacesCursorKey(id);
  await env.BOOKING_KV.put(key, JSON.stringify(stored), {
    expirationTtl: HOTEL_PLACES_CURSOR_TTL_SECONDS,
  });
  return {
    ok: true,
    cursor: id,
    key,
    available_at: stored.available_at,
    page: 1,
  };
}

export async function readHotelPlacesCursor(env, cursorId) {
  const key = hotelPlacesCursorKey(cursorId);
  if (!key || !env?.BOOKING_KV) {
    return { ok: false, error: "unknown_cursor", http_status: 400 };
  }
  if (!isHotelPlacesCursorKey(key)) {
    return { ok: false, error: "unknown_cursor", http_status: 400 };
  }
  let raw;
  try {
    raw = await env.BOOKING_KV.get(key, { type: "json" });
  } catch (_) {
    return { ok: false, error: "unknown_cursor", http_status: 400 };
  }
  const record = asRecord(raw);
  if (!record) {
    return { ok: false, error: "unknown_cursor", http_status: 400 };
  }
  return { ok: true, key, record };
}

export function validateHotelPlacesCursorRecord(record, {
  nowMs = Date.now(),
  query = null,
} = {}) {
  const stored = asRecord(record);
  if (!stored) return { ok: false, error: "unknown_cursor", http_status: 400 };
  if (stored.consumed === true) {
    return { ok: false, error: "consumed_cursor", http_status: 409 };
  }
  if (Number(stored.page) !== 2) {
    return { ok: false, error: "invalid_cursor_page", http_status: 400 };
  }
  if (!isUsableProviderToken(stored.provider_token)) {
    return { ok: false, error: "malformed_cursor", http_status: 400 };
  }
  if (!stored.fingerprint) {
    return { ok: false, error: "malformed_cursor", http_status: 400 };
  }
  const issued = Number(stored.issued_at);
  if (!Number.isFinite(issued)) {
    return { ok: false, error: "malformed_cursor", http_status: 400 };
  }
  if (nowMs - issued > HOTEL_PLACES_CURSOR_TTL_SECONDS * 1000) {
    return { ok: false, error: "expired_cursor", http_status: 409 };
  }
  if (query && queryConflictsWithCursor(query, stored)) {
    return { ok: false, error: "conflicting_cursor_query", http_status: 409 };
  }
  const availableAt = Number(stored.available_at);
  if (Number.isFinite(availableAt) && nowMs < availableAt) {
    return {
      ok: false,
      error: "cursor_not_ready",
      http_status: 425,
      retry_after_ms: Math.max(250, availableAt - nowMs),
      available_at: availableAt,
    };
  }
  return { ok: true, record: stored };
}

export async function consumeHotelPlacesCursor(env, key, record) {
  if (!env?.BOOKING_KV || !key) return { ok: false, error: "missing_booking_kv" };
  const consumed = {
    ...record,
    consumed: true,
    consumed_at: Date.now(),
    provider_token: "",
  };
  try {
    await env.BOOKING_KV.put(key, JSON.stringify(consumed), {
      expirationTtl: 60,
    });
  } catch (_) {
    // Best-effort consume. Documented KV race remains.
  }
  try {
    await env.BOOKING_KV.delete(key);
  } catch (_) {
    // Best-effort delete after consume flag.
  }
  return { ok: true };
}

export function sanitizeGooglePlacesLogDetails(details = {}) {
  const out = {};
  for (const [key, value] of Object.entries(details)) {
    const name = String(key).toLowerCase();
    if (
      name.includes("key") ||
      name.includes("token") ||
      name.includes("url") ||
      name.includes("authorization")
    ) {
      continue;
    }
    if (typeof value === "string") out[key] = value.slice(0, 80);
    else if (typeof value === "number" || typeof value === "boolean") out[key] = value;
  }
  return out;
}
