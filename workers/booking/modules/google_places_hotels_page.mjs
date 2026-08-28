import { buildGooglePlacesTextQuery } from "./google_places_country.mjs";
import {
  HOTEL_PLACES_ACTIVATION_DELAY_MS,
  HOTEL_PLACES_MAX_PAGES,
  consumeHotelPlacesCursor,
  hotelPlacesQueryFingerprint,
  normalizeHotelPlacesCursorId,
  publicHotelPlacesPagination,
  readHotelPlacesCursor,
  sanitizeGooglePlacesLogDetails,
  storeHotelPlacesCursor,
  validateHotelPlacesCursorRecord,
} from "./google_places_pagination.mjs";

function asPlaces(payload) {
  return Array.isArray(payload?.results) ? payload.results : [];
}

function providerPageToken(payload) {
  const token = String(payload?.next_page_token ?? "").trim();
  return token || "";
}

export async function fetchGooglePlacesTextSearchPage({
  query,
  apiKey,
  pageToken = "",
  fetchImpl = globalThis.fetch,
} = {}) {
  if (!apiKey) {
    return { places: [], nextPageToken: "", called: false, error: "missing_api_key" };
  }
  const url = new URL("https://maps.googleapis.com/maps/api/place/textsearch/json");
  const token = String(pageToken ?? "").trim();
  if (token) {
    url.searchParams.set("pagetoken", token);
  } else {
    url.searchParams.set("query", buildGooglePlacesTextQuery(query));
    url.searchParams.set("type", "lodging");
  }
  url.searchParams.set("key", apiKey);

  const res = await fetchImpl(url.toString());
  if (!res?.ok) {
    return {
      places: [],
      nextPageToken: "",
      called: true,
      error: "google_places_http_not_ok",
      status: Number(res?.status || 0),
    };
  }
  const payload = await res.json().catch(() => null);
  return {
    places: asPlaces(payload),
    nextPageToken: providerPageToken(payload),
    called: true,
    status: String(payload?.status || ""),
  };
}

export async function resolveGooglePlacesHotelsSearch({
  query,
  env,
  nowMs = Date.now(),
  fetchImpl = globalThis.fetch,
  randomBytesFn,
} = {}) {
  const apiKey = String(env?.GOOGLE_PLACES_API_KEY ?? "").trim();
  if (!apiKey) {
    return {
      ok: true,
      http_status: 200,
      places: [],
      pagination: publicHotelPlacesPagination({ page: 1 }),
      google_called: false,
      warnings: ["google_places_not_configured"],
    };
  }

  const rawCursor = String(query?.cursor ?? "").trim();
  if (rawCursor) {
    const cursorId = normalizeHotelPlacesCursorId(rawCursor);
    if (!cursorId) {
      return {
        ok: false,
        http_status: 400,
        error: "malformed_cursor",
        places: [],
        google_called: false,
      };
    }
    return await resolveGooglePlacesHotelsPage2({
      query,
      env,
      cursorId,
      apiKey,
      nowMs,
      fetchImpl,
    });
  }

  const first = await fetchGooglePlacesTextSearchPage({
    query,
    apiKey,
    fetchImpl,
  });
  const places = Array.isArray(first.places) ? first.places.slice(0, 20) : [];
  let stored = null;
  if (first.nextPageToken && env?.BOOKING_KV) {
    stored = await storeHotelPlacesCursor(
      env,
      {
        providerToken: first.nextPageToken,
        fingerprint: hotelPlacesQueryFingerprint(query),
        countryCode: query?.countryCode || query?.country_code || "",
        issuedAtMs: nowMs,
        availableAtMs: nowMs + HOTEL_PLACES_ACTIVATION_DELAY_MS,
        page: 2,
      },
      { nowMs, randomBytesFn },
    );
  }

  return {
    ok: true,
    http_status: 200,
    places,
    pagination: publicHotelPlacesPagination({
      page: 1,
      nextCursor: stored?.ok === true ? stored.cursor : "",
      availableAtMs: stored?.ok === true ? stored.available_at : null,
      hasMore: stored?.ok === true,
    }),
    google_called: first.called === true,
    warnings: first.error ? [first.error] : [],
  };
}

async function resolveGooglePlacesHotelsPage2({
  query,
  env,
  cursorId,
  apiKey,
  nowMs,
  fetchImpl,
}) {
  const loaded = await readHotelPlacesCursor(env, cursorId);
  if (loaded.ok !== true) {
    return {
      ok: false,
      http_status: loaded.http_status || 400,
      error: loaded.error || "unknown_cursor",
      places: [],
      google_called: false,
    };
  }
  const validated = validateHotelPlacesCursorRecord(loaded.record, {
    nowMs,
    query,
  });
  if (validated.ok !== true) {
    return {
      ok: false,
      http_status: validated.http_status || 400,
      error: validated.error,
      retry_after_ms: validated.retry_after_ms,
      available_at: validated.available_at,
      places: [],
      google_called: false,
    };
  }

  await consumeHotelPlacesCursor(env, loaded.key, validated.record);

  const second = await fetchGooglePlacesTextSearchPage({
    query,
    apiKey,
    pageToken: validated.record.provider_token,
    fetchImpl,
  });
  const places = Array.isArray(second.places) ? second.places.slice(0, 20) : [];
  return {
    ok: true,
    http_status: 200,
    places,
    pagination: publicHotelPlacesPagination({
      page: 2,
      hasMore: false,
    }),
    google_called: second.called === true,
    preserved_country_code: validated.record.country_code,
    preserved_fingerprint: validated.record.fingerprint,
    max_pages: HOTEL_PLACES_MAX_PAGES,
    warnings: second.error ? [second.error] : [],
  };
}

export function hotelPlacesSafeLog(event, details) {
  return {
    event,
    ...sanitizeGooglePlacesLogDetails(details),
  };
}
