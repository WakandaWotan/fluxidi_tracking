/**
 * Search plan for GET /public/events.
 *
 * Ticketmaster Discovery often returns an empty page for an unfiltered
 * country query (no classification, no keyword), while the same country
 * returns events as soon as a classification is set. Spain "all categories"
 * vs "music" is that case. A higher `size` is not the fix.
 *
 * Fluxidi launch markets: BE, NL, FR, ES, LU, DE.
 */

export const FLUXIDI_EVENT_COUNTRIES = ["BE", "NL", "FR", "DE", "LU", "ES", "GB"];

export const FLUXIDI_LAUNCH_EVENT_COUNTRIES = ["BE", "NL", "FR", "DE", "LU", "ES"];

const LOCALES = {
  BE: "nl-be",
  NL: "nl-nl",
  FR: "fr-fr",
  DE: "de-de",
  LU: "fr-lu",
  ES: "es-es",
  GB: "en-gb",
  UK: "en-gb",
};

export const ALL_CATEGORY_CLASSIFICATIONS = [
  { classificationName: "music", categoryKey: "music" },
  { classificationName: "sports", categoryKey: "sport" },
  { classificationName: "Arts & Theatre", categoryKey: "theater" },
  { classificationName: "family", categoryKey: "family" },
  { classificationName: "miscellaneous", categoryKey: "culture" },
];

export function ticketmasterLocale(country) {
  const key = String(country || "").trim().toUpperCase();
  if (key === "UK") return LOCALES.GB;
  return LOCALES[key] || "";
}

export function normalizeEventCountry(value, market) {
  const raw = String(value || "").trim().toUpperCase();
  if (raw === "UK") return "GB";
  if (raw) return raw;
  const marketKey = String(market || "").trim().toLowerCase();
  if (marketKey === "uk" || marketKey === "gb") return "GB";
  if (marketKey.length === 2) return marketKey.toUpperCase();
  return "";
}

export function shouldFanOutAllCategories(query) {
  const category = String(query?.category || "").trim();
  const keyword = String(query?.keyword || query?.q || "").trim();
  return !category && !keyword;
}

export function fanOutPageSize() {
  return 20;
}

export function isLuxembourgEvent(event) {
  if (!event || typeof event !== "object") return false;
  if (String(event.country_code || "").toUpperCase() === "LU") return true;
  const hay = [
    event.city,
    event.address,
    event.location_name,
    event.venue_name,
    event.title,
  ]
    .map((value) => String(value || "").toLowerCase())
    .join(" ");
  return /luxembou?rg|l[eë]tzebuerg/.test(hay);
}

export function luxembourgNeighborQueries(query) {
  const keyword = String(query?.keyword || query?.q || "").trim() || "luxembourg";
  return ["BE", "FR", "DE"].map((code) => ({
    ...query,
    country: code,
    market: code.toLowerCase(),
    keyword,
    relaxCountryMatch: true,
    _luFallback: true,
  }));
}

export function publicEventsCacheKey(query) {
  return [
    "tm",
    normalizeEventCountry(query?.country, query?.market) || "XX",
    String(query?.dateMode || "year"),
    String(query?.category || "").trim().toLowerCase() || "all",
    String(query?.keyword || query?.q || "").trim().toLowerCase() || "-",
    String(query?.limit || 50),
  ].join("|");
}

export function isRealPublicEvent(event) {
  if (!event || typeof event !== "object") return false;
  const provider = String(event.provider || event.source || "").toLowerCase();
  if (provider === "worker_seed") return false;
  const title = String(event.title || "").trim();
  if (!title) return false;
  const when = String(event.starts_at_utc || event.startAtUtc || event.date_time_label || "").trim();
  if (!when) return false;
  const location = String(
    event.address || event.location_name || event.locationName || event.city || "",
  ).trim();
  if (!location) return false;
  return true;
}

export function mergePublicEvents(lists, limit) {
  const cap = Math.max(1, Math.min(50, Number(limit) || 50));
  const seen = new Set();
  const merged = [];
  for (const list of lists || []) {
    if (!Array.isArray(list)) continue;
    for (const event of list) {
      if (!isRealPublicEvent(event)) continue;
      const id = String(event.id || event.source_event_id || "").trim();
      if (!id || seen.has(id)) continue;
      seen.add(id);
      merged.push(event);
    }
  }
  merged.sort((a, b) => {
    const aMs = Date.parse(a.starts_at_utc || a.startAtUtc || "") || 0;
    const bMs = Date.parse(b.starts_at_utc || b.startAtUtc || "") || 0;
    return aMs - bMs;
  });
  return merged.slice(0, cap);
}

const cacheStore = new Map();
const CACHE_TTL_MS = 10 * 60 * 1000;

export function readPublicEventsCache(key) {
  const row = cacheStore.get(key);
  if (!row) return null;
  if (Date.now() > row.expiresAt) {
    cacheStore.delete(key);
    return null;
  }
  return row.value;
}

export function writePublicEventsCache(key, value) {
  cacheStore.set(key, { value, expiresAt: Date.now() + CACHE_TTL_MS });
  if (cacheStore.size > 80) {
    const first = cacheStore.keys().next().value;
    cacheStore.delete(first);
  }
}

export function clearPublicEventsCache() {
  cacheStore.clear();
}
