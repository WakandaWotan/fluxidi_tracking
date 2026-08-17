/**
 * RateHawk performance and market-scope contract (P1, mocked only).
 *
 * Server-owned market enablement and search limits for the existing
 * HotelsPage. This module never calls RateHawk, never invents hotel pages,
 * and never hardcodes a production city list. Example markets belong in
 * tests only.
 *
 * Live RateHawk search is allowed only after destination, dates and guests
 * are complete. Opening HotelsPage must not issue a provider request.
 */

export const RATEHAWK_SEARCH_TRIGGERS = Object.freeze({
  PAGE_OPEN: "page_open",
  LIVE_SEARCH: "live_search",
  LOAD_MORE: "load_more",
});

export const RATEHAWK_SERP_HOTELS_PATH = "/api/b2b/v3/search/serp/hotels/";
export const RATEHAWK_SERP_REGION_PATH = "/api/b2b/v3/search/serp/region/";
export const RATEHAWK_SERP_GEO_PATH = "/api/b2b/v3/search/serp/geo/";
export const RATEHAWK_TEST_HOST = "https://api.ratehawk.com";
export const RATEHAWK_TEST_HOTEL_HID = "8473727";

export const RATEHAWK_DEFAULT_SEARCH_LIMITS = Object.freeze({
  initial_hotel_limit: 20,
  load_more_increment: 20,
  absolute_maximum: 100,
  debounce_ms: 400,
  rate_cache_ttl_ms: 120_000,
  search_timeout_ms: 30_000,
  max_hids_per_request: 300,
});

const RATE_CACHE_NAMESPACE = "ratehawk_live_rates";
const STATIC_CONTENT_NAMESPACE = "ratehawk_offline_static";

function _text(value, max = 200) {
  const text = String(value ?? "").trim();
  if (!text) return "";
  return text.length > max ? text.slice(0, max) : text;
}

function _int(value, fallback) {
  const n = Number(value);
  if (!Number.isFinite(n)) return fallback;
  return Math.trunc(n);
}

function _clamp(value, min, max) {
  return Math.min(max, Math.max(min, value));
}

function _finite(value) {
  const n = typeof value === "number" ? value : Number(value);
  return Number.isFinite(n) ? n : null;
}

/**
 * Numeric limits only. Markets stay empty unless the server supplies them.
 * Never ships a baked-in city list.
 */
export function resolveMarketSearchConfig(env = {}, { markets = null } = {}) {
  const limits = {
    initial_hotel_limit: _clamp(
      _int(env.RATEHAWK_SEARCH_INITIAL_LIMIT, RATEHAWK_DEFAULT_SEARCH_LIMITS.initial_hotel_limit),
      1,
      RATEHAWK_DEFAULT_SEARCH_LIMITS.max_hids_per_request,
    ),
    load_more_increment: _clamp(
      _int(
        env.RATEHAWK_SEARCH_LOAD_MORE_INCREMENT,
        RATEHAWK_DEFAULT_SEARCH_LIMITS.load_more_increment,
      ),
      1,
      RATEHAWK_DEFAULT_SEARCH_LIMITS.max_hids_per_request,
    ),
    absolute_maximum: _clamp(
      _int(env.RATEHAWK_SEARCH_ABSOLUTE_MAX, RATEHAWK_DEFAULT_SEARCH_LIMITS.absolute_maximum),
      1,
      RATEHAWK_DEFAULT_SEARCH_LIMITS.max_hids_per_request,
    ),
    debounce_ms: _clamp(
      _int(env.RATEHAWK_SEARCH_DEBOUNCE_MS, RATEHAWK_DEFAULT_SEARCH_LIMITS.debounce_ms),
      0,
      10_000,
    ),
    rate_cache_ttl_ms: _clamp(
      _int(env.RATEHAWK_RATE_CACHE_TTL_MS, RATEHAWK_DEFAULT_SEARCH_LIMITS.rate_cache_ttl_ms),
      1_000,
      15 * 60_000,
    ),
    search_timeout_ms: _clamp(
      _int(env.RATEHAWK_SEARCH_TIMEOUT_MS, RATEHAWK_DEFAULT_SEARCH_LIMITS.search_timeout_ms),
      5_000,
      60_000,
    ),
    max_hids_per_request: RATEHAWK_DEFAULT_SEARCH_LIMITS.max_hids_per_request,
  };
  if (limits.absolute_maximum < limits.initial_hotel_limit) {
    limits.absolute_maximum = limits.initial_hotel_limit;
  }

  const supplied = Array.isArray(markets) ? markets : [];
  return {
    limits,
    enabled_markets: supplied.map(_normalizeMarket).filter(Boolean),
  };
}

export const RATEHAWK_PUBLIC_SEARCH_FORBIDDEN_CLIENT_KEYS = Object.freeze([
  "host",
  "base_url",
  "api_key",
  "apiKey",
  "authorization",
  "endpoint",
  "url",
  "path",
  "hid",
  "hids",
  "ids",
  "region_id",
  "regionId",
  "latitude",
  "longitude",
  "lat",
  "lng",
  "radius",
  "radius_m",
  "radius_km",
  "radiusKm",
  "book_hash",
  "match_hash",
  "RATEHAWK_API_KEY",
  "RATEHAWK_KEY_ID",
  "provider_host",
  "search_endpoint",
  "hotels_path",
]);

export const RATEHAWK_PUBLIC_SEARCH_DATE_BOUNDS = Object.freeze({
  max_nights: 30,
  max_lead_days: 365,
  past_slack_days: 1,
});

export const RATEHAWK_PUBLIC_SEARCH_GUEST_BOUNDS = Object.freeze({
  max_rooms: 8,
  max_adults: 6,
  max_children: 4,
  min_child_age: 0,
  max_child_age: 17,
});

export const RATEHAWK_PUBLIC_SEARCH_LANGUAGES = Object.freeze({
  nl: "nl",
  en: "en",
  fr: "fr",
  es: "es",
});

const COUNTRY_NAME_ALIASES = Object.freeze({
  BE: Object.freeze(["belgium", "belgie", "belgique", "belgica"]),
  NL: Object.freeze(["netherlands", "nederland", "pays bas", "holanda"]),
  FR: Object.freeze(["france", "frankrijk"]),
  ES: Object.freeze(["spain", "spanje", "espana"]),
  DE: Object.freeze(["germany", "duitsland", "deutschland", "allemagne"]),
  GB: Object.freeze(["united kingdom", "uk", "great britain", "britain"]),
});

function _aliasKey(value) {
  const text = String(value ?? "")
    .normalize("NFD")
    .replace(/\p{M}/gu, "")
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, " ")
    .trim();
  return text.length > 80 ? text.slice(0, 80) : text;
}

function _uniqueAliases(values) {
  const seen = new Set();
  const out = [];
  for (const value of values) {
    const key = _aliasKey(value);
    if (!key || seen.has(key)) continue;
    seen.add(key);
    out.push(key);
  }
  return out;
}

function _normalizeCountryCode(value) {
  const raw = _text(value, 80);
  if (!raw) return "";
  if (/^[A-Za-z]{2}$/.test(raw)) return raw.toUpperCase();
  const alias = _aliasKey(raw);
  for (const [code, names] of Object.entries(COUNTRY_NAME_ALIASES)) {
    if (names.includes(alias)) return code;
  }
  return "";
}

function _ymdParts(value) {
  const text = _text(value, 10);
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(text);
  if (!match) return null;
  const year = Number(match[1]);
  const month = Number(match[2]);
  const day = Number(match[3]);
  const utc = Date.UTC(year, month - 1, day);
  const check = new Date(utc);
  if (
    check.getUTCFullYear() !== year ||
    check.getUTCMonth() !== month - 1 ||
    check.getUTCDate() !== day
  ) {
    return null;
  }
  return { ymd: text, utc };
}

function _normalizeMarket(raw) {
  if (!raw || typeof raw !== "object") return null;
  const countryCode = _text(raw.country_code ?? raw.country, 8).toUpperCase();
  const cityKey = _text(raw.city_key ?? raw.city, 80).toLowerCase();
  if (!countryCode || !cityKey) return null;
  const regionId = _text(raw.region_id, 40);
  const lat = _finite(raw.geo?.lat ?? raw.lat);
  const lng = _finite(raw.geo?.lng ?? raw.lng);
  const radiusM = _finite(raw.geo?.radius_m ?? raw.radius_m);
  const hasRegion = Boolean(regionId);
  const hasGeo = lat != null && lng != null && radiusM != null && radiusM > 0;
  if (!hasRegion && !hasGeo) return null;
  const marketKey = _text(raw.market_key, 80).toLowerCase() ||
    `${countryCode.toLowerCase()}:${cityKey}`;
  const aliases = _uniqueAliases([
    cityKey,
    marketKey,
    raw.city,
    raw.city_key,
    raw.name,
    raw.name_nl,
    raw.name_en,
    raw.name_fr,
    raw.name_es,
    ...(Array.isArray(raw.aliases) ? raw.aliases : []),
  ]);
  const countryAliases = _uniqueAliases([
    countryCode,
    raw.country,
    ...(COUNTRY_NAME_ALIASES[countryCode] || []),
    ...(Array.isArray(raw.country_aliases) ? raw.country_aliases : []),
  ]);
  return {
    market_key: marketKey,
    country_code: countryCode,
    city_key: cityKey,
    aliases,
    country_aliases: countryAliases,
    region_id: hasRegion ? regionId : null,
    geo: hasGeo ? { lat, lng, radius_m: radiusM } : null,
    initial_hotel_limit: _clamp(
      _int(raw.initial_hotel_limit, RATEHAWK_DEFAULT_SEARCH_LIMITS.initial_hotel_limit),
      1,
      RATEHAWK_DEFAULT_SEARCH_LIMITS.absolute_maximum,
    ),
    load_more_limit: _clamp(
      _int(raw.load_more_limit ?? raw.load_more_increment, RATEHAWK_DEFAULT_SEARCH_LIMITS.load_more_increment),
      1,
      RATEHAWK_DEFAULT_SEARCH_LIMITS.absolute_maximum,
    ),
    absolute_maximum: _clamp(
      _int(raw.absolute_maximum, RATEHAWK_DEFAULT_SEARCH_LIMITS.absolute_maximum),
      1,
      RATEHAWK_DEFAULT_SEARCH_LIMITS.max_hids_per_request,
    ),
    enabled: raw.enabled !== false,
  };
}

export function resolveEnabledMarket(config, destination = {}) {
  const country = _text(destination.country_code ?? destination.country, 8).toUpperCase();
  const city = _text(destination.city_key ?? destination.city, 80).toLowerCase();
  if (!country || !city) {
    return { ok: false, reason: "destination_incomplete", market: null };
  }
  const markets = Array.isArray(config?.enabled_markets) ? config.enabled_markets : [];
  const market = markets.find(
    (item) =>
      item.enabled !== false &&
      item.country_code === country &&
      item.city_key === city,
  );
  if (!market) {
    return { ok: false, reason: "market_not_enabled", market: null };
  }
  return { ok: true, reason: null, market };
}

export function parseConfiguredSearchMarkets(env = {}, markets = null) {
  if (Array.isArray(markets)) {
    return resolveMarketSearchConfig(env, { markets });
  }
  const raw = _text(env?.RATEHAWK_SEARCH_MARKETS, 8000) ||
    _text(env?.RATEHAWK_CONTENT_MARKETS, 8000);
  if (!raw) return resolveMarketSearchConfig(env, { markets: [] });
  try {
    const parsed = JSON.parse(raw);
    return resolveMarketSearchConfig(env, {
      markets: Array.isArray(parsed) ? parsed : [],
    });
  } catch {
    return resolveMarketSearchConfig(env, { markets: [] });
  }
}

export function hasForbiddenPublicSearchClientControl(input = {}) {
  if (!input || typeof input !== "object" || Array.isArray(input)) return false;
  for (const key of RATEHAWK_PUBLIC_SEARCH_FORBIDDEN_CLIENT_KEYS) {
    if (!Object.prototype.hasOwnProperty.call(input, key)) continue;
    const value = input[key];
    if (value == null || value === "") continue;
    if (Array.isArray(value) && value.length === 0) continue;
    return true;
  }
  return false;
}

export function canonicalizePublicSearchLanguage(value) {
  const raw = _text(value, 8).toLowerCase();
  if (!raw) return { ok: true, language: "en", defaulted: true };
  const mapped = RATEHAWK_PUBLIC_SEARCH_LANGUAGES[raw];
  if (!mapped) return { ok: false, reason: "language_unsupported", language: null };
  return { ok: true, language: mapped, defaulted: false };
}

export function canonicalizePublicSearchCurrency(value) {
  const raw = _text(value, 3).toUpperCase();
  if (!raw) return { ok: true, currency: "EUR", defaulted: true };
  if (!/^[A-Z]{3}$/.test(raw)) {
    return { ok: false, reason: "currency_unsupported", currency: null };
  }
  return { ok: true, currency: raw, defaulted: false };
}

export function canonicalizePublicSearchResidency(value, market = null) {
  const raw = _text(value, 2).toLowerCase();
  if (/^[a-z]{2}$/.test(raw)) {
    return { ok: true, residency: raw, defaulted: false };
  }
  const fromMarket = _text(market?.country_code, 2).toLowerCase();
  if (/^[a-z]{2}$/.test(fromMarket)) {
    return { ok: true, residency: fromMarket, defaulted: true };
  }
  return { ok: false, reason: "residency_required", residency: null };
}

export function canonicalizePublicSearchGuests(guests = []) {
  const rooms = Array.isArray(guests) ? guests : [];
  if (!rooms.length) {
    return { ok: false, reason: "guests_incomplete", guests: [] };
  }
  if (rooms.length > RATEHAWK_PUBLIC_SEARCH_GUEST_BOUNDS.max_rooms) {
    return { ok: false, reason: "guests_out_of_bounds", guests: [] };
  }
  const canonical = [];
  for (const room of rooms) {
    const adults = _int(room?.adults, 0);
    const childrenRaw = Array.isArray(room?.children) ? room.children : [];
    if (adults < 1 || adults > RATEHAWK_PUBLIC_SEARCH_GUEST_BOUNDS.max_adults) {
      return { ok: false, reason: "guests_out_of_bounds", guests: [] };
    }
    if (childrenRaw.length > RATEHAWK_PUBLIC_SEARCH_GUEST_BOUNDS.max_children) {
      return { ok: false, reason: "guests_out_of_bounds", guests: [] };
    }
    const children = [];
    for (const age of childrenRaw) {
      const n = _int(age, -1);
      if (
        n < RATEHAWK_PUBLIC_SEARCH_GUEST_BOUNDS.min_child_age ||
        n > RATEHAWK_PUBLIC_SEARCH_GUEST_BOUNDS.max_child_age
      ) {
        return { ok: false, reason: "guests_out_of_bounds", guests: [] };
      }
      children.push(n);
    }
    canonical.push({ adults, children });
  }
  return { ok: true, guests: canonical };
}

export function assertPublicSearchStayDates(checkin, checkout, now = Date.now()) {
  const inDate = _ymdParts(checkin);
  const outDate = _ymdParts(checkout);
  if (!inDate || !outDate) {
    return { ok: false, reason: "live_search_incomplete" };
  }
  if (outDate.utc <= inDate.utc) {
    return { ok: false, reason: "live_search_incomplete" };
  }
  const nights = Math.round((outDate.utc - inDate.utc) / 86_400_000);
  if (nights < 1 || nights > RATEHAWK_PUBLIC_SEARCH_DATE_BOUNDS.max_nights) {
    return { ok: false, reason: "stay_dates_out_of_bounds" };
  }
  const today = new Date(Number(now));
  const todayUtc = Date.UTC(
    today.getUTCFullYear(),
    today.getUTCMonth(),
    today.getUTCDate(),
  );
  const minUtc =
    todayUtc - RATEHAWK_PUBLIC_SEARCH_DATE_BOUNDS.past_slack_days * 86_400_000;
  const maxUtc =
    todayUtc + RATEHAWK_PUBLIC_SEARCH_DATE_BOUNDS.max_lead_days * 86_400_000;
  if (inDate.utc < minUtc || inDate.utc > maxUtc) {
    return { ok: false, reason: "stay_dates_out_of_bounds" };
  }
  return {
    ok: true,
    checkin: inDate.ymd,
    checkout: outDate.ymd,
    nights,
  };
}

export function isPublicLiveSearchCriteriaComplete({
  destination = {},
  checkin = "",
  checkout = "",
  guests = [],
} = {}) {
  const marketKey = _text(destination.market_key, 80);
  const country = _text(destination.country_code ?? destination.country, 80);
  const city = _text(destination.city_key ?? destination.city, 80);
  const region = _text(destination.region, 80);
  const destinationText = _text(destination.destination ?? destination.q, 80);
  const hasDestination = Boolean(
    marketKey || city || region || destinationText || (country && city),
  );
  const dates = assertPublicSearchStayDates(checkin, checkout, Date.now());
  const datesOk = Boolean(_ymdParts(checkin) && _ymdParts(checkout) && _text(checkout, 10) > _text(checkin, 10));
  const guestsOk = canonicalizePublicSearchGuests(guests).ok === true;
  return {
    complete: hasDestination && datesOk && guestsOk,
    has_destination: hasDestination,
    has_dates: datesOk,
    has_guests: guestsOk,
    stay_dates_ok: dates.ok === true,
  };
}

export function resolvePublicSearchMarket(config, destination = {}) {
  const markets = (Array.isArray(config?.enabled_markets) ? config.enabled_markets : [])
    .filter((item) => item && item.enabled !== false);
  if (!markets.length) {
    return { ok: false, reason: "production_markets_unconfigured", market: null };
  }

  const marketKey = _aliasKey(destination.market_key);
  if (marketKey) {
    const exact = markets.filter((item) => _aliasKey(item.market_key) === marketKey);
    if (exact.length === 1) return { ok: true, reason: null, market: exact[0] };
    if (exact.length > 1) {
      return { ok: false, reason: "ambiguous_destination", market: null };
    }
    return { ok: false, reason: "unsupported_market", market: null };
  }

  const country = _normalizeCountryCode(
    destination.country_code ?? destination.country,
  );
  const texts = _uniqueAliases([
    destination.city_key,
    destination.city,
    destination.region,
    destination.destination,
    destination.q,
  ]);
  if (!texts.length) {
    return { ok: false, reason: "destination_incomplete", market: null };
  }

  const matches = markets.filter((item) => {
    if (country && item.country_code !== country) return false;
    return texts.some((text) => item.aliases.includes(text));
  });
  if (matches.length === 1) return { ok: true, reason: null, market: matches[0] };
  if (matches.length > 1) {
    return { ok: false, reason: "ambiguous_destination", market: null };
  }
  return { ok: false, reason: "unsupported_market", market: null };
}

export function resolvePublicSearchResultLimit(config, market, trigger) {
  const limits = config?.limits || RATEHAWK_DEFAULT_SEARCH_LIMITS;
  const initial = _clamp(
    _int(market?.initial_hotel_limit, limits.initial_hotel_limit),
    1,
    RATEHAWK_DEFAULT_SEARCH_LIMITS.absolute_maximum,
  );
  const loadMore = _clamp(
    _int(market?.load_more_limit, limits.load_more_increment),
    1,
    RATEHAWK_DEFAULT_SEARCH_LIMITS.absolute_maximum,
  );
  const absolute = _clamp(
    _int(market?.absolute_maximum, limits.absolute_maximum),
    1,
    RATEHAWK_DEFAULT_SEARCH_LIMITS.max_hids_per_request,
  );
  const size =
    trigger === RATEHAWK_SEARCH_TRIGGERS.LOAD_MORE ? loadMore : initial;
  return {
    initial_hotel_limit: initial,
    load_more_increment: loadMore,
    absolute_maximum: absolute,
    take: Math.min(size, absolute, RATEHAWK_DEFAULT_SEARCH_LIMITS.absolute_maximum),
  };
}

export function isLiveSearchCriteriaComplete({
  destination = {},
  checkin = "",
  checkout = "",
  guests = [],
} = {}) {
  const country = _text(destination.country_code ?? destination.country, 8);
  const city = _text(destination.city_key ?? destination.city, 80);
  const regionId = _text(destination.region_id, 40);
  const hasDestination = Boolean((country && city) || regionId);
  const inDate = _text(checkin, 16);
  const outDate = _text(checkout, 16);
  const datesOk =
    /^\d{4}-\d{2}-\d{2}$/.test(inDate) &&
    /^\d{4}-\d{2}-\d{2}$/.test(outDate) &&
    outDate > inDate;
  const rooms = Array.isArray(guests) ? guests : [];
  const guestsOk =
    rooms.length > 0 &&
    rooms.every((room) => _int(room?.adults, 0) >= 1);
  return {
    complete: hasDestination && datesOk && guestsOk,
    has_destination: hasDestination,
    has_dates: datesOk,
    has_guests: guestsOk,
  };
}

export function shouldIssueRatehawkSearch({
  trigger,
  criteria,
  market,
} = {}) {
  if (trigger === RATEHAWK_SEARCH_TRIGGERS.PAGE_OPEN) {
    return { issue: false, reason: "page_open_no_request" };
  }
  if (criteria?.complete !== true) {
    return { issue: false, reason: "live_search_incomplete" };
  }
  if (market?.ok !== true) {
    return { issue: false, reason: market?.reason || "market_not_enabled" };
  }
  if (
    trigger !== RATEHAWK_SEARCH_TRIGGERS.LIVE_SEARCH &&
    trigger !== RATEHAWK_SEARCH_TRIGGERS.LOAD_MORE
  ) {
    return { issue: false, reason: "unsupported_trigger" };
  }
  return { issue: true, reason: null };
}

export function planImmediateExistingCards(existingCards = []) {
  const cards = Array.isArray(existingCards) ? existingCards : [];
  return {
    render_immediately: true,
    existing_cards: cards,
    ratehawk: { requested: false, status: "not_requested" },
  };
}

export function dedupeHotelsByHid(items = []) {
  const seen = new Set();
  const out = [];
  for (const item of items) {
    const hid = _text(item?.hid ?? item?.provider_id, 40);
    if (!hid || seen.has(hid)) continue;
    seen.add(hid);
    out.push(item);
  }
  return out;
}

/**
 * Load-more is a slice of a known hid list. No synthetic page tokens,
 * no invented hotel IDs.
 */
export function nextHotelIdChunk({
  hidList = [],
  offset = 0,
  trigger = RATEHAWK_SEARCH_TRIGGERS.LIVE_SEARCH,
  limits = RATEHAWK_DEFAULT_SEARCH_LIMITS,
} = {}) {
  const known = dedupeHotelsByHid(
    (Array.isArray(hidList) ? hidList : []).map((hid) =>
      typeof hid === "object" ? hid : { hid },
    ),
  ).map((item) => _text(item.hid, 40));
  const start = Math.max(0, _int(offset, 0));
  const size =
    trigger === RATEHAWK_SEARCH_TRIGGERS.LOAD_MORE
      ? limits.load_more_increment
      : limits.initial_hotel_limit;
  const remainingBudget = Math.max(0, limits.absolute_maximum - start);
  const take = Math.min(size, remainingBudget, limits.max_hids_per_request);
  const hids = known.slice(start, start + take);
  const nextOffset = start + hids.length;
  return {
    hids,
    offset: start,
    next_offset: nextOffset,
    has_more:
      hids.length > 0 &&
      nextOffset < known.length &&
      nextOffset < limits.absolute_maximum,
    invented: false,
    pagination_token: null,
  };
}

export function createRateCache({ nowFn = () => Date.now(), ttlMs } = {}) {
  const ttl = _int(ttlMs, RATEHAWK_DEFAULT_SEARCH_LIMITS.rate_cache_ttl_ms);
  const entries = new Map();
  return {
    namespace: RATE_CACHE_NAMESPACE,
    ttl_ms: ttl,
    get(key) {
      const row = entries.get(key);
      if (!row) return null;
      if (nowFn() >= row.expires_at) {
        entries.delete(key);
        return null;
      }
      return row.value;
    },
    set(key, value) {
      entries.set(key, { value, expires_at: nowFn() + ttl });
    },
    size() {
      return entries.size;
    },
  };
}

export function createStaticContentStore() {
  return {
    namespace: STATIC_CONTENT_NAMESPACE,
    kind: "offline_sync",
  };
}

export function rateCacheKey({ hid, checkin, checkout, guestsDigest }) {
  return [hid, checkin, checkout, guestsDigest || "g"].join("|");
}

export function createSearchFlightController({ debounceMs = 400 } = {}) {
  let inFlightKey = null;
  let cancelledGeneration = 0;
  let generation = 0;
  let scheduledKey = null;
  return {
    debounce_ms: debounceMs,
    decide({ key, trigger, ready }) {
      if (trigger === RATEHAWK_SEARCH_TRIGGERS.PAGE_OPEN) {
        return { start: false, reason: "page_open_no_request" };
      }
      if (ready !== true) {
        return { start: false, reason: "live_search_incomplete" };
      }
      if (inFlightKey && inFlightKey === key) {
        return { start: false, reason: "single_flight" };
      }
      return { start: true, reason: null, generation: generation + 1 };
    },
    schedule(key) {
      scheduledKey = key;
      return { debounce_ms: debounceMs, key };
    },
    markInFlight(key) {
      generation += 1;
      inFlightKey = key;
      return generation;
    },
    cancel() {
      cancelledGeneration = generation;
      inFlightKey = null;
      scheduledKey = null;
    },
    complete(key) {
      if (inFlightKey === key) inFlightKey = null;
    },
    isCancelled(gen) {
      return gen <= cancelledGeneration;
    },
    inFlightKey() {
      return inFlightKey;
    },
    scheduledKey() {
      return scheduledKey;
    },
  };
}

export function annotateSearchResultMetadata({
  requestedHids = [],
  receivedHids = [],
  timedOut = false,
  elapsedMs = null,
} = {}) {
  const requested = requestedHids.map((hid) => _text(hid, 40)).filter(Boolean);
  const received = dedupeHotelsByHid(
    receivedHids.map((hid) => (typeof hid === "object" ? hid : { hid })),
  ).map((item) => item.hid);
  return {
    timed_out: timedOut === true,
    partial: timedOut === true || received.length < requested.length,
    requested_count: requested.length,
    received_count: received.length,
    elapsed_ms: elapsedMs,
    invented_pagination: false,
  };
}

/**
 * Exact first test-environment search contract. Does not send the request.
 * Uses the official test hotel hid only — no production city list.
 */
export function buildProposedTestSearchRequest({
  checkin,
  checkout,
  residency = "be",
  language = "en",
  guests = [{ adults: 2, children: [] }],
  timeout = 30,
} = {}) {
  return {
    method: "POST",
    host: RATEHAWK_TEST_HOST,
    path: RATEHAWK_SERP_HOTELS_PATH,
    url: `${RATEHAWK_TEST_HOST}${RATEHAWK_SERP_HOTELS_PATH}`,
    environment: "test",
    executed: false,
    body: {
      checkin,
      checkout,
      residency,
      language,
      guests,
      hids: [Number(RATEHAWK_TEST_HOTEL_HID)],
      timeout,
    },
  };
}
