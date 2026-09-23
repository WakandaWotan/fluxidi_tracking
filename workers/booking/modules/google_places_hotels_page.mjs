import { buildGooglePlacesTextQuery } from "./google_places_country.mjs";
import {
  HOTEL_PLACES_ACTIVATION_DELAY_MS,
  HOTEL_PLACES_MAX_PAGES,
  consumeHotelPlacesCursor,
  googlePlacesSearchCenter,
  hotelPlacesQueryFingerprint,
  isUsableProviderToken,
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

const kPlacesNearbyFieldMask = [
  "places.id",
  "places.displayName",
  "places.formattedAddress",
  "places.location",
  "places.rating",
  "places.userRatingCount",
  "places.photos",
  "places.primaryType",
  "places.types",
].join(",");

// Legacy Nearby Search omits photos for these lodging results. Places API
// (New) searchNearby returns photos[].name, which the public hotel mapper
// already turns into the photo proxy. The key stays in the header.
async function fetchPlacesApiNearbySearch({ center, apiKey, fetchImpl }) {
  try {
    const res = await fetchImpl(
      "https://places.googleapis.com/v1/places:searchNearby",
      {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-Goog-Api-Key": apiKey,
          "X-Goog-FieldMask": kPlacesNearbyFieldMask,
        },
        body: JSON.stringify({
          includedTypes: ["lodging"],
          maxResultCount: 20,
          rankPreference: "POPULARITY",
          locationRestriction: {
            circle: {
              center: { latitude: center.lat, longitude: center.lng },
              radius: center.radiusMeters,
            },
          },
        }),
      },
    );
    if (!res?.ok) {
      return {
        places: [],
        nextPageToken: "",
        called: true,
        error: "google_places_nearby_http_not_ok",
        status: Number(res?.status || 0),
      };
    }
    const payload = await res.json().catch(() => null);
    return {
      places: Array.isArray(payload?.places) ? payload.places : [],
      nextPageToken: "",
      called: true,
      status: "OK",
    };
  } catch (_) {
    return {
      places: [],
      nextPageToken: "",
      called: true,
      error: "google_places_nearby_http_not_ok",
      status: 0,
    };
  }
}

function usablePlacePhoto(place) {
  const photos = Array.isArray(place?.photos) ? place.photos : [];
  for (const photo of photos) {
    const reference = String(photo?.photo_reference ?? "").trim();
    if (/^[A-Za-z0-9_-]{8,600}$/.test(reference)) return true;
    const name = String(photo?.name ?? "").trim();
    if (/^legacy:[A-Za-z0-9_-]{8,600}$/.test(name)) return true;
    if (/^places\/[\w-]+\/photos\/[\w-]+$/.test(name)) return true;
  }
  return false;
}

function legacyPhotoReference(raw) {
  const text = String(raw ?? "").trim();
  if (!/^[A-Za-z0-9_-]{8,600}$/.test(text)) return "";
  return text;
}

// Legacy Nearby Search leaves photos empty for these lodging rows. Place
// Details with fields=photo returns one photo_reference the public proxy
// already accepts. The key stays on the request URL and is not returned.
async function attachMissingPlacePhotos(places, apiKey, fetchImpl) {
  const pending = (Array.isArray(places) ? places : []).filter(
    (place) => !usablePlacePhoto(place),
  );
  await Promise.all(
    pending.map(async (place) => {
      const placeId = String(place?.place_id ?? place?.id ?? "")
        .replace(/^places\//, "")
        .trim();
      if (!placeId) return;
      const url = new URL(
        "https://maps.googleapis.com/maps/api/place/details/json",
      );
      url.searchParams.set("place_id", placeId);
      url.searchParams.set("fields", "photo");
      url.searchParams.set("key", apiKey);
      try {
        const res = await fetchImpl(url.toString());
        if (!res?.ok) return;
        const payload = await res.json().catch(() => null);
        const photos = Array.isArray(payload?.result?.photos)
          ? payload.result.photos
          : [];
        const reference = legacyPhotoReference(photos[0]?.photo_reference);
        if (!reference) return;
        const attributionItems = Array.isArray(photos[0]?.html_attributions)
          ? photos[0].html_attributions
          : [];
        const attributionText = attributionItems
          .map((entry) => String(entry ?? "").replace(/<[^>]*>/g, "").trim())
          .filter(Boolean)
          .join(", ");
        if (place.place_id) {
          place.photos = [
            {
              photo_reference: reference,
              html_attributions: attributionText ? [attributionText] : [],
            },
          ];
          return;
        }
        place.photos = [
          {
            name: `legacy:${reference}`,
            authorAttributions: attributionText
              ? [{ displayName: attributionText }]
              : [],
          },
        ];
      } catch (_) {
        // A missing photo stays a compact card. The hotel row still returns.
      }
    }),
  );
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
  const center = googlePlacesSearchCenter(query);
  const token = String(pageToken ?? "").trim();
  // A fresh coordinate search uses Places Nearby (New) so photo names come
  // back. Page-2 tokens still belong to the legacy Nearby Search call.
  if (center && !token) {
    const nearby = await fetchPlacesApiNearbySearch({
      center,
      apiKey,
      fetchImpl,
    });
    if (!nearby.error) {
      await attachMissingPlacePhotos(nearby.places, apiKey, fetchImpl);
      return nearby;
    }
  }
  const url = new URL(
    center
      ? "https://maps.googleapis.com/maps/api/place/nearbysearch/json"
      : "https://maps.googleapis.com/maps/api/place/textsearch/json",
  );
  // Text Search answers INVALID_REQUEST to a bare pagetoken; the originating
  // query has to be repeated even though the docs call it ignored. Nearby
  // Search gets the same treatment for location and radius.
  if (center) {
    url.searchParams.set("location", `${center.lat},${center.lng}`);
    url.searchParams.set("radius", String(center.radiusMeters));
  } else {
    url.searchParams.set("query", buildGooglePlacesTextQuery(query));
  }
  url.searchParams.set("type", "lodging");
  if (token) {
    url.searchParams.set("pagetoken", token);
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
  const places = asPlaces(payload);
  if (center) await attachMissingPlacePhotos(places, apiKey, fetchImpl);
  return {
    places,
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
  const providerToken = String(first.nextPageToken ?? "").trim();
  // Losing the cursor silently looks identical to "provider has no page 2", so
  // say which one happened. Never emit the token itself.
  const cursorWarnings = [];
  let stored = null;
  if (!providerToken) {
    if (first.called === true && !first.error) {
      cursorWarnings.push("google_places_no_next_page_token");
    }
  } else if (!env?.BOOKING_KV) {
    cursorWarnings.push("hotel_places_cursor_missing_kv");
  } else {
    stored = await storeHotelPlacesCursor(
      env,
      {
        providerToken,
        fingerprint: hotelPlacesQueryFingerprint(query),
        countryCode: query?.countryCode || query?.country_code || "",
        issuedAtMs: nowMs,
        availableAtMs: nowMs + HOTEL_PLACES_ACTIVATION_DELAY_MS,
        page: 2,
      },
      { nowMs, randomBytesFn },
    );
    if (stored?.ok !== true) {
      cursorWarnings.push(`hotel_places_cursor_${stored?.error || "store_failed"}`);
      if (!isUsableProviderToken(providerToken)) {
        cursorWarnings.push("hotel_places_token_rejected");
        cursorWarnings.push(`hotel_places_token_len_${providerToken.length}`);
      }
    }
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
    warnings: first.error ? [first.error, ...cursorWarnings] : cursorWarnings,
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
  const warnings = second.error ? [second.error] : [];
  // Google answers an unusable page token with HTTP 200 and a status field, so
  // an empty page 2 is otherwise indistinguishable from a genuinely short list.
  const providerStatus = String(second.status ?? "").trim();
  if (providerStatus && providerStatus !== "OK") {
    warnings.push(`google_places_page2_${providerStatus.toLowerCase()}`);
  }
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
    warnings,
  };
}

export function hotelPlacesSafeLog(event, details) {
  return {
    event,
    ...sanitizeGooglePlacesLogDetails(details),
  };
}
