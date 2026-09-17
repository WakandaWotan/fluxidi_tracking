/**
 * Prepared France fallback for GET /public/events.
 * OpenAgenda published agendas are readable with a public account key.
 * Do not call this without OPENAGENDA_API_KEY.
 */

export function openAgendaConfigured(env) {
  return Boolean(String(env?.OPENAGENDA_API_KEY || "").trim());
}

export function openAgendaEventsUrl(query) {
  const params = new URLSearchParams();
  params.set("size", String(Math.max(1, Math.min(50, Number(query?.limit) || 20))));
  params.set("relative[]", "upcoming");
  const keyword = String(query?.keyword || query?.q || "").trim();
  if (keyword) params.set("search", keyword);
  const country = String(query?.country || "FR").toUpperCase();
  if (country) params.set("locationCountry", country);
  return `https://api.openagenda.com/v2/events?${params.toString()}`;
}

function pickLocalized(value, lang) {
  if (!value || typeof value !== "object") return String(value || "").trim();
  const key = String(lang || "fr").toLowerCase().split("-")[0];
  return String(value[key] || value.fr || value.en || value.es || value.de || "").trim();
}

export function mapOpenAgendaEvent(item, receivedAtUtc, lang) {
  if (!item || typeof item !== "object") return null;
  const title = pickLocalized(item.title, lang) || String(item.title || "").trim();
  const location = item.location || {};
  const city = String(location.city || "").trim();
  const address = String(location.address || location.name || city).trim();
  const starts = String(item.nextTiming?.begin || item.firstTiming?.begin || "").trim();
  if (!title || !starts || !address) return null;
  const uid = String(item.uid || item.slug || title).trim();
  return {
    id: `oa_${uid}`,
    title,
    subtitle: pickLocalized(item.description, lang),
    description: pickLocalized(item.longDescription, lang) || pickLocalized(item.description, lang),
    location_name: String(location.name || city).trim(),
    venue_name: String(location.name || "").trim(),
    category: "Cultuur",
    category_key: "culture",
    address,
    city,
    country_code: String(location.countryCode || "FR").toUpperCase() || "FR",
    market_code: "fr",
    latitude: Number.isFinite(Number(location.latitude)) ? Number(location.latitude) : null,
    longitude: Number.isFinite(Number(location.longitude)) ? Number(location.longitude) : null,
    starts_at_utc: new Date(starts).toISOString(),
    provider: "openagenda",
    source_event_id: uid,
    source_url: String(item.canonicalUrl || item.slug || "").trim() || null,
    status: "scheduled",
    updated_at_utc: receivedAtUtc,
  };
}

export async function fetchOpenAgendaPublicEvents({ env, query, receivedAtUtc, fetchImpl }) {
  const apiKey = String(env?.OPENAGENDA_API_KEY || "").trim();
  if (!apiKey) {
    return { ok: false, warnings: ["openagenda_api_key_missing"], events: [] };
  }
  const doFetch = fetchImpl || fetch;
  const response = await doFetch(openAgendaEventsUrl(query), {
    method: "GET",
    headers: { key: apiKey, accept: "application/json" },
  });
  if (!response || !response.ok) {
    return {
      ok: false,
      warnings: [`openagenda_http_status_${response && response.status ? response.status : "error"}`],
      events: [],
    };
  }
  const payload = await response.json();
  const raw = Array.isArray(payload?.events) ? payload.events : [];
  const lang = String(query?.lang || query?.locale || "fr");
  const events = raw.map((item) => mapOpenAgendaEvent(item, receivedAtUtc, lang)).filter(Boolean);
  return { ok: events.length > 0, events, warnings: events.length ? [] : ["openagenda_empty"] };
}
