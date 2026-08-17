/**
 * Mocked P1 search-contract DTO for the existing hotel card pipeline:
 *   _mapPublicHotelStayToResponse
 *   → hotelStayFromPublicHotelJson
 *   → HotelStay
 *
 * Non-RateHawk sources pass through unchanged. source=ratehawk is optional
 * and gated. This module does not call RateHawk and does not change UI.
 */

import {
  EXISTING_HOTEL_PAGE_ACTIONS,
  FLUXIDI_HOTEL_CARD_FIELDS,
  RATEHAWK_AFFILIATE_REMUNERATION_PERCENT,
  RATEHAWK_GEO_MATCH_MAX_METERS,
  RATEHAWK_STAY_CARD_SOURCE,
  mapRatehawkHotelToExistingStayCard,
  resolveRatehawkHotelMatch,
} from "./ratehawk_affiliate_contract.mjs";

export const EXISTING_HOTEL_SEARCH_SOURCES = Object.freeze([
  "approved-local",
  "partner-approved",
  "google-places",
  "places",
]);

export const RATEHAWK_SEARCH_SOURCE = "ratehawk";

function _cloneJson(value) {
  return JSON.parse(JSON.stringify(value));
}

function _text(value, max = 400) {
  const text = String(value ?? "").trim();
  if (!text) return "";
  return text.length > max ? text.slice(0, max) : text;
}

/**
 * Exact public-card projection used by the booking worker today.
 * Field set and nullability must stay compatible with existing clients.
 */
export function mapExistingStayToPublicHotelCard(stay) {
  const ratingSource =
    stay?.rating_label ?? stay?.ratingLabel ?? stay?.rating;
  const rating =
    ratingSource == null || ratingSource === ""
      ? null
      : String(ratingSource).trim();
  return {
    id: String(stay?.id ?? "").trim(),
    provider:
      String(stay?.provider ?? "approved-local").trim() || "approved-local",
    provider_id:
      String(stay?.source_id ?? stay?.provider_id ?? stay?.id ?? "").trim() ||
      String(stay?.id ?? "").trim(),
    name: String(stay?.name ?? "").trim(),
    type: String(stay?.type ?? "hotel").trim() || "hotel",
    address: String(stay?.address ?? "").trim(),
    city: String(stay?.city ?? "").trim(),
    region: String(stay?.region ?? "").trim(),
    country: String(stay?.country ?? "").trim(),
    lat: Number(stay?.lat),
    lng: Number(stay?.lng),
    image_url: stay?.image_url == null ? null : String(stay.image_url).trim() || null,
    image_ref: stay?.image_ref ? String(stay.image_ref).trim() : null,
    rating_label: rating,
    price_label: stay?.price_hint
      ? String(stay.price_hint).trim()
      : stay?.price_label
        ? String(stay.price_label).trim()
        : null,
    availability_label: stay?.availability_label
      ? String(stay.availability_label).trim()
      : null,
    external_url: stay?.external_url == null
      ? null
      : String(stay.external_url).trim() || null,
    provider_label: stay?.provider_label
      ? String(stay.provider_label).trim()
      : null,
    photo_attribution: stay?.photo_attribution
      ? String(stay.photo_attribution).trim()
      : null,
    source: String(stay?.source ?? "approved_local").trim() || "approved_local",
    is_real_approved: stay?.is_real_approved === true,
  };
}

export function isExistingHotelSearchSource(source) {
  const value = _text(source, 64).toLowerCase();
  return EXISTING_HOTEL_SEARCH_SOURCES.includes(value);
}

export function isRatehawkHotelSearchSource(source) {
  return _text(source, 64).toLowerCase() === RATEHAWK_SEARCH_SOURCE;
}

function _internalSettlement(providerSettlement = null) {
  const percent = Number(
    providerSettlement?.affiliate_remuneration_percent ??
      providerSettlement?.percent ??
      RATEHAWK_AFFILIATE_REMUNERATION_PERCENT,
  );
  return {
    customer_facing: false,
    source: "provider_settlement",
    affiliate_remuneration_percent: Number.isFinite(percent)
      ? percent
      : RATEHAWK_AFFILIATE_REMUNERATION_PERCENT,
    amount_minor:
      providerSettlement?.amount_minor == null
        ? null
        : Number(providerSettlement.amount_minor),
    currency: providerSettlement?.currency ?? null,
  };
}

function _assertNoRemunerationLeak(stay) {
  const price = String(stay?.price_label ?? "");
  if (!price) return true;
  if (/%/.test(price)) return false;
  if (/affiliate|remuneration|commission/i.test(price)) return false;
  return true;
}

/**
 * Build one search-contract row for the existing hotel card pipeline.
 *
 * `search_contract_enabled` is a mocked gate only. Live RateHawk search
 * remains disabled in the worker (`RATEHAWK_ENABLED=0`, overview-only).
 */
export function buildExistingHotelCardSearchDto({
  source = "approved-local",
  existingStay = null,
  ratehawkHotel = null,
  liveRate = null,
  stay22FallbackUrl = null,
  fluxidiStayId = null,
  catalogHid = null,
  search_contract_enabled = false,
  providerSettlement = null,
} = {}) {
  if (isExistingHotelSearchSource(source)) {
    if (!existingStay) {
      return { ok: false, reason: "existing_stay_required", stay: null };
    }
    const stay = mapExistingStayToPublicHotelCard(existingStay);
    return {
      ok: true,
      source: _text(source, 64),
      stay,
      ratehawk_matched: false,
      has_live_ratehawk_availability: false,
      stay22_fallback: Boolean(stay.external_url),
      existing_page_actions_preserved: EXISTING_HOTEL_PAGE_ACTIONS,
      card_fields: FLUXIDI_HOTEL_CARD_FIELDS,
      internal_settlement: null,
    };
  }

  if (!isRatehawkHotelSearchSource(source)) {
    return { ok: false, reason: "unsupported_source", stay: null };
  }

  if (search_contract_enabled !== true) {
    return {
      ok: true,
      source: RATEHAWK_SEARCH_SOURCE,
      stay: null,
      gated: true,
      reason: "ratehawk_search_contract_gated",
      warnings: ["ratehawk_invocation_blocked"],
      existing_page_actions_preserved: EXISTING_HOTEL_PAGE_ACTIONS,
    };
  }

  if (!ratehawkHotel) {
    return { ok: false, reason: "ratehawk_hotel_required", stay: null };
  }

  const match = resolveRatehawkHotelMatch({
    ratehawkHid: ratehawkHotel.hid ?? ratehawkHotel.id,
    catalogHid,
    ratehawkAddress: ratehawkHotel.address,
    catalogAddress: existingStay?.address,
    ratehawkLat: ratehawkHotel.lat ?? ratehawkHotel.latitude,
    ratehawkLng: ratehawkHotel.lng ?? ratehawkHotel.longitude,
    catalogLat: existingStay?.lat,
    catalogLng: existingStay?.lng,
    ratehawkName: ratehawkHotel.name,
    catalogName: existingStay?.name,
  });

  if (!match.matched) {
    const fallback = existingStay
      ? mapExistingStayToPublicHotelCard({
          ...existingStay,
          price_hint: existingStay.price_hint ?? existingStay.price_label,
          external_url: stay22FallbackUrl || existingStay.external_url,
        })
      : null;
    if (fallback) {
      fallback.price_label = null;
      fallback.availability_label = null;
    }
    return {
      ok: true,
      source: existingStay ? _text(existingStay.source ?? "approved-local", 64) : RATEHAWK_SEARCH_SOURCE,
      stay: fallback,
      ratehawk_matched: false,
      match,
      has_live_ratehawk_availability: false,
      stay22_fallback: Boolean(fallback?.external_url),
      existing_page_actions_preserved: EXISTING_HOTEL_PAGE_ACTIONS,
      reason: match.reason,
    };
  }

  const mapped = mapRatehawkHotelToExistingStayCard({
    hotel: ratehawkHotel,
    liveRate,
    stay22FallbackUrl: stay22FallbackUrl || existingStay?.external_url || null,
    fluxidiStayId: fluxidiStayId || existingStay?.id || null,
  });
  if (!mapped.ok) {
    return {
      ok: false,
      hard_stop: mapped.hard_stop === true,
      reason: mapped.reason,
      stay: null,
    };
  }

  if (!_assertNoRemunerationLeak(mapped.stay)) {
    return {
      ok: false,
      hard_stop: true,
      reason: "affiliate_remuneration_leaked_into_customer_price",
      stay: null,
    };
  }

  return {
    ok: true,
    source: RATEHAWK_SEARCH_SOURCE,
    stay: mapped.stay,
    ratehawk_hid: mapped.ratehawk_hid,
    ratehawk_matched: true,
    match,
    has_live_ratehawk_availability: mapped.has_live_ratehawk_availability,
    stay22_fallback: mapped.stay22_fallback,
    existing_page_actions_preserved: EXISTING_HOTEL_PAGE_ACTIONS,
    card_fields: FLUXIDI_HOTEL_CARD_FIELDS,
    geo_match_max_meters: RATEHAWK_GEO_MATCH_MAX_METERS,
    internal_settlement: _internalSettlement(providerSettlement),
  };
}

export function buildExistingHotelSearchPayload({
  source = "approved-local",
  existingStays = [],
  ratehawkItems = [],
  search_contract_enabled = false,
} = {}) {
  if (isExistingHotelSearchSource(source)) {
    const stays = existingStays.map((stay) =>
      mapExistingStayToPublicHotelCard(stay),
    );
    return {
      ok: true,
      source,
      provider: source,
      count: stays.length,
      stays,
      warnings: [],
    };
  }

  if (!isRatehawkHotelSearchSource(source)) {
    return {
      ok: true,
      source,
      provider: source,
      count: 0,
      stays: [],
      warnings: ["unsupported_source"],
    };
  }

  if (search_contract_enabled !== true) {
    return {
      ok: true,
      source: RATEHAWK_SEARCH_SOURCE,
      provider: RATEHAWK_STAY_CARD_SOURCE,
      count: 0,
      stays: [],
      warnings: ["ratehawk_invocation_blocked"],
    };
  }

  const stays = [];
  const warnings = [];
  const internals = [];
  for (const item of ratehawkItems) {
    const row = buildExistingHotelCardSearchDto({
      source: RATEHAWK_SEARCH_SOURCE,
      search_contract_enabled: true,
      ...item,
    });
    if (row.hard_stop) {
      return {
        ok: false,
        source: RATEHAWK_SEARCH_SOURCE,
        provider: RATEHAWK_STAY_CARD_SOURCE,
        count: 0,
        stays: [],
        warnings: [row.reason],
        hard_stop: true,
        reason: row.reason,
      };
    }
    if (row.stay) stays.push(_cloneJson(row.stay));
    if (row.internal_settlement) internals.push(row.internal_settlement);
    if (row.reason && !row.ratehawk_matched) warnings.push(row.reason);
  }
  return {
    ok: true,
    source: RATEHAWK_SEARCH_SOURCE,
    provider: RATEHAWK_STAY_CARD_SOURCE,
    count: stays.length,
    stays,
    warnings,
    internal: { settlement: internals, customer_facing: false },
  };
}
