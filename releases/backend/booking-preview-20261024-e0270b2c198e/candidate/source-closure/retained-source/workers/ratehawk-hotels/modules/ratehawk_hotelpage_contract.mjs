/**
 * RateHawk hotelpage contract for the existing View stay flow (P1, mocked).
 *
 * HotelStayDetailPage already exists. This module does not create a second
 * detail page and does not render Flutter UI. Hotelpage may be requested
 * only after the customer opens one hid-backed hotel via View stay.
 *
 * Official path: POST /api/b2b/v3/search/hp/
 * Official recommended rate lifetime: 30 minutes.
 * match_hash is analytics-only and never proves a SERP rate is bookable.
 * Later prebook remains authoritative.
 *
 * This module does not call RateHawk, prebook, book, or cancel.
 */

import {
  EXISTING_HOTEL_PAGE_ACTIONS,
  normalizeRatehawkRateOffer,
} from "./ratehawk_affiliate_contract.mjs";
import {
  RATEHAWK_DISCLOSURE_LOCALES,
  RATEHAWK_LIVE_PRICE_PIPELINE,
  RATEHAWK_REFRESH_FAILED_PRICE_LABEL,
  annotateLiveRateFreshness,
  disclosureLabelsFor,
  inspectRatehawkContentCompleteness,
  normalizeStaticHotelPolicies,
  resolveLiveRatePresentation,
} from "./ratehawk_content_freshness_contract.mjs";
import { RATEHAWK_TEST_HOTEL_HID } from "./ratehawk_market_search_limits.mjs";

export const RATEHAWK_HOTELPAGE_PATH = "/api/b2b/v3/search/hp/";
export const RATEHAWK_HOTELPAGE_HOST = "https://api.ratehawk.com";
export const RATEHAWK_HOTELPAGE_TTL_MS = 30 * 60 * 1000;
export const RATEHAWK_HOTELPAGE_TIMEOUT_SECONDS = 30;

export const RATEHAWK_HOTELPAGE_ALLOWED_TRIGGER = "view_stay";

export const RATEHAWK_HOTELPAGE_FORBIDDEN_TRIGGERS = Object.freeze([
  "list_card",
  "card_render",
  "hotels_page_open",
  "serp_list",
  "nearby_events",
  "saved",
]);

export const RATEHAWK_HOTELPAGE_STATES = Object.freeze([
  "loading",
  "ready",
  "unavailable",
  "stale",
  "retryable",
]);

export const EXISTING_HOTEL_DETAIL_ACTIONS = Object.freeze([
  "saved",
  "nearby_events",
  "taxi_to_this_event",
  "taxi_to_this_stay",
  "airport_transfer",
  "stay22_fallback_availability",
]);

export const RATEHAWK_HOTELPAGE_LANGUAGES = Object.freeze([
  "ar", "bg", "cs", "da", "de", "el", "en", "es", "fi", "fr", "he", "hu",
  "it", "ja", "kk", "ko", "nl", "no", "pl", "pt", "pt_PT", "ro", "ru",
  "sq", "sr", "sv", "th", "tr", "uk", "vi", "zh_CN", "zh_TW",
]);

export const RATEHAWK_HOTELPAGE_FILTER_KEYS = Object.freeze([
  "star_rating",
  "kind",
  "meal_type",
]);

const DATE_RE = /^\d{4}-\d{2}-\d{2}$/;
const ISO2_RE = /^[a-z]{2}$/;
const CURRENCY_RE = /^[A-Z]{3}$/;

function _text(value, max = 200) {
  const text = String(value ?? "").trim();
  if (!text) return "";
  return text.length > max ? text.slice(0, max) : text;
}

function _lower(value) {
  return _text(value, 80).toLowerCase();
}

function _fail(reason, extra = {}) {
  return { ok: false, hard_stop: true, reason, executed: false, ...extra };
}

function parseHid(raw) {
  if (raw == null || raw === "") {
    return { ok: false, reason: "hid_required" };
  }
  if (typeof raw === "string" && /[a-z]/i.test(raw) && !/^\d+$/.test(raw.trim())) {
    return { ok: false, reason: "hotel_name_identification_forbidden" };
  }
  const hid = String(raw).trim();
  if (!/^\d{1,10}$/.test(hid) || Number(hid) <= 0) {
    return { ok: false, reason: "hid_invalid" };
  }
  return { ok: true, hid: Number(hid) };
}

function parseDate(raw, field) {
  const text = _text(raw, 10);
  if (!DATE_RE.test(text)) {
    return { ok: false, reason: `${field}_invalid` };
  }
  const ms = Date.parse(`${text}T00:00:00.000Z`);
  if (!Number.isFinite(ms)) {
    return { ok: false, reason: `${field}_invalid` };
  }
  return { ok: true, value: text, ms };
}

function parseGuests(rooms) {
  if (!Array.isArray(rooms) || rooms.length < 1 || rooms.length > 9) {
    return { ok: false, reason: "guests_required" };
  }
  const guests = [];
  for (const room of rooms) {
    const adults = Number(room?.adults);
    if (!Number.isInteger(adults) || adults < 1 || adults > 6) {
      return { ok: false, reason: "adults_invalid" };
    }
    const childrenRaw = room?.children == null ? [] : room.children;
    if (!Array.isArray(childrenRaw) || childrenRaw.length > 4) {
      return { ok: false, reason: "children_invalid" };
    }
    const children = [];
    for (const age of childrenRaw) {
      const n = Number(age);
      if (!Number.isInteger(n) || n < 0 || n > 17) {
        return { ok: false, reason: "child_age_invalid" };
      }
      children.push(n);
    }
    if (adults + children.length > 10) {
      return { ok: false, reason: "guests_per_room_exceeded" };
    }
    guests.push({ adults, children });
  }
  return { ok: true, guests };
}

function parseFilter(filter) {
  if (filter == null) return { ok: true, filter: null };
  if (typeof filter !== "object" || Array.isArray(filter)) {
    return { ok: false, reason: "filter_malformed" };
  }
  const unknown = Object.keys(filter).filter(
    (key) => !RATEHAWK_HOTELPAGE_FILTER_KEYS.includes(key),
  );
  if (unknown.length) {
    return { ok: false, reason: "filter_unknown_field", unknown_field_names: unknown };
  }
  return { ok: true, filter };
}

function searchContextFingerprint(context) {
  return JSON.stringify({
    hid: context.hid,
    checkin: context.checkin,
    checkout: context.checkout,
    residency: context.residency,
    language: context.language,
    currency: context.currency,
    guests: context.guests,
  });
}

export function shouldRequestRatehawkHotelpage(trigger) {
  const value = _lower(trigger);
  if (RATEHAWK_HOTELPAGE_FORBIDDEN_TRIGGERS.includes(value)) {
    return {
      ok: false,
      allowed: false,
      reason: "hotelpage_forbidden_for_list_or_card",
    };
  }
  if (value !== RATEHAWK_HOTELPAGE_ALLOWED_TRIGGER) {
    return { ok: false, allowed: false, reason: "hotelpage_requires_view_stay" };
  }
  return { ok: true, allowed: true, reason: null };
}

/**
 * Validate a hid-backed hotelpage request. Never executed here.
 */
export function buildRatehawkHotelpageRequest({
  hid = null,
  hotelName = null,
  checkin = null,
  checkout = null,
  residency = null,
  language = null,
  currency = null,
  guests = null,
  filter = null,
  timeout = RATEHAWK_HOTELPAGE_TIMEOUT_SECONDS,
  trigger = null,
  selectedCardHid = null,
  searchContext = null,
  now = Date.now(),
} = {}) {
  if (hotelName) {
    return _fail("hotel_name_identification_forbidden");
  }
  const triggerGate = shouldRequestRatehawkHotelpage(trigger);
  if (triggerGate.allowed !== true) {
    return _fail(triggerGate.reason);
  }

  const parsedHid = parseHid(hid);
  if (!parsedHid.ok) return _fail(parsedHid.reason);

  const cardHid = parseHid(selectedCardHid ?? hid);
  if (!cardHid.ok) return _fail("selected_card_hid_required");
  if (cardHid.hid !== parsedHid.hid) {
    return _fail("search_context_hid_mismatch");
  }

  const inDate = parseDate(checkin, "checkin");
  if (!inDate.ok) return _fail(inDate.reason);
  const outDate = parseDate(checkout, "checkout");
  if (!outDate.ok) return _fail(outDate.reason);
  if (outDate.ms <= inDate.ms) return _fail("checkout_before_checkin");
  const stayDays = (outDate.ms - inDate.ms) / 86_400_000;
  if (stayDays > 30) return _fail("stay_exceeds_30_days");
  const aheadDays = (inDate.ms - Number(now)) / 86_400_000;
  if (aheadDays > 730) return _fail("checkin_too_far");

  const residencyCode = _lower(residency);
  if (!ISO2_RE.test(residencyCode)) return _fail("residency_required");

  const lang = _text(language, 8);
  if (!RATEHAWK_HOTELPAGE_LANGUAGES.includes(lang)) {
    return _fail("language_unsupported");
  }

  const currencyCode = _text(currency, 8).toUpperCase();
  if (!CURRENCY_RE.test(currencyCode)) return _fail("currency_required");

  const parsedGuests = parseGuests(guests);
  if (!parsedGuests.ok) return _fail(parsedGuests.reason);

  const parsedFilter = parseFilter(filter);
  if (!parsedFilter.ok) {
    return _fail(parsedFilter.reason, {
      unknown_field_names: parsedFilter.unknown_field_names,
    });
  }

  const timeoutSeconds = Number(timeout);
  if (
    !Number.isFinite(timeoutSeconds) ||
    timeoutSeconds <= 0 ||
    timeoutSeconds > 100
  ) {
    return _fail("timeout_invalid");
  }

  const body = {
    hid: parsedHid.hid,
    checkin: inDate.value,
    checkout: outDate.value,
    residency: residencyCode,
    language: lang,
    currency: currencyCode,
    guests: parsedGuests.guests,
    timeout: timeoutSeconds,
  };
  if (parsedFilter.filter) body.filter = parsedFilter.filter;

  const context = {
    hid: parsedHid.hid,
    checkin: inDate.value,
    checkout: outDate.value,
    residency: residencyCode,
    language: lang,
    currency: currencyCode,
    guests: parsedGuests.guests,
  };
  if (searchContext) {
    const expected = {
      hid: parseHid(searchContext.hid).hid,
      checkin: searchContext.checkin,
      checkout: searchContext.checkout,
      residency: _lower(searchContext.residency),
      language: _text(searchContext.language, 8),
      currency: _text(searchContext.currency, 8).toUpperCase(),
      guests: searchContext.guests,
    };
    if (searchContextFingerprint(context) !== searchContextFingerprint(expected)) {
      return _fail("search_context_mismatch");
    }
  }

  return {
    ok: true,
    executed: false,
    method: "POST",
    host: RATEHAWK_HOTELPAGE_HOST,
    path: RATEHAWK_HOTELPAGE_PATH,
    url: `${RATEHAWK_HOTELPAGE_HOST}${RATEHAWK_HOTELPAGE_PATH}`,
    environment: "test",
    trigger: RATEHAWK_HOTELPAGE_ALLOWED_TRIGGER,
    cacheable: false,
    shared_cache: false,
    body,
    search_context: context,
    must_prebook_before_confirmation: true,
    match_hash_not_bookable_proof: true,
  };
}

function annotateHotelpageOffer(offer, rate, retrievedAt, now) {
  const freshness = annotateLiveRateFreshness({
    retrieved_at: retrievedAt,
    book_hash: rate.book_hash,
    match_hash: rate.match_hash,
    search_hash: rate.search_hash,
    stage: "hotelpage",
    now,
  });
  const expiresAt = retrievedAt + RATEHAWK_HOTELPAGE_TTL_MS;
  const expired = Number(now) >= expiresAt;
  const conservative = {
    ...freshness,
    expires_at: expiresAt,
    ttl_ms: RATEHAWK_HOTELPAGE_TTL_MS,
    cacheable: false,
    match_hash_not_bookable_proof: true,
    ok: freshness.ok === true && !expired,
    bookable: freshness.bookable === true && !expired,
    state: expired ? "expired" : freshness.state,
    reason: expired ? "live_rate_expired" : freshness.reason,
  };
  const presentation = resolveLiveRatePresentation({
    freshness: conservative,
    offer,
  });
  return {
    ...offer,
    book_hash: offer.book_hash,
    match_hash: offer.match_hash,
    hashes_opaque: true,
    freshness: conservative,
    presentation,
    must_prebook_before_confirmation: true,
  };
}

export function normalizeRatehawkHotelpageResponse({
  requestedHid,
  retrieved_at,
  hotels = [],
  staticHotel = null,
  now = Date.now(),
} = {}) {
  const hid = parseHid(requestedHid);
  if (!hid.ok) return _fail(hid.reason);
  if (!Number.isFinite(Number(retrieved_at))) {
    return _fail("live_rate_retrieved_at_required");
  }

  if (!Array.isArray(hotels) || hotels.length !== 1) {
    return _fail("hotelpage_hotel_count_invalid");
  }
  const hotel = hotels[0];
  const returnedHid = parseHid(hotel?.hid ?? hotel?.id);
  if (!returnedHid.ok || returnedHid.hid !== hid.hid) {
    return _fail("hotelpage_hid_mismatch");
  }

  const completeness = inspectRatehawkContentCompleteness({
    staticHotel,
    liveRate: null,
  });
  if (completeness.hard_stop) {
    return {
      ok: false,
      hard_stop: true,
      reason: completeness.reason,
      unmapped_critical_field_names: completeness.unmapped_critical_field_names,
    };
  }

  const rates = Array.isArray(hotel.rates) ? hotel.rates : [];
  const offers = [];
  const rejected = [];
  for (const rate of rates) {
    const rateCompleteness = inspectRatehawkContentCompleteness({
      liveRate: rate,
    });
    if (rateCompleteness.hard_stop) {
      rejected.push({
        ok: false,
        hard_stop: true,
        reason: rateCompleteness.reason,
        unmapped_critical_field_names:
          rateCompleteness.unmapped_critical_field_names,
      });
      continue;
    }
    const offer = normalizeRatehawkRateOffer(rate);
    if (offer.ok !== true) {
      rejected.push(offer);
      continue;
    }
    offers.push(annotateHotelpageOffer(offer, rate, Number(retrieved_at), now));
  }

  const bookableOffers = offers.filter((offer) => offer.freshness.bookable);
  const stale = offers.length > 0 && bookableOffers.length === 0;
  return {
    ok: rejected.length === 0,
    hard_stop: rejected.length > 0,
    reason: rejected[0]?.reason ?? null,
    unmapped_critical_field_names: rejected.flatMap(
      (row) => row.unmapped_critical_field_names || [],
    ),
    hid: hid.hid,
    retrieved_at: Number(retrieved_at),
    ttl_ms: RATEHAWK_HOTELPAGE_TTL_MS,
    cacheable: false,
    shared_cache: false,
    match_hash_not_bookable_proof: true,
    must_prebook_before_confirmation: true,
    pipeline: RATEHAWK_LIVE_PRICE_PIPELINE,
    offers,
    rejected,
    bookable_count: bookableOffers.length,
    stale,
    static_policies: staticHotel
      ? normalizeStaticHotelPolicies(staticHotel)
      : null,
  };
}

export function buildHotelStayDetailAdapter({
  stay = {},
  staticHotel = null,
  hotelpage = null,
  state = "unavailable",
  locale = "nl",
  refresh_failed = false,
} = {}) {
  const value = RATEHAWK_HOTELPAGE_STATES.includes(state) ? state : "unavailable";
  const policies = staticHotel
    ? normalizeStaticHotelPolicies(staticHotel)
    : null;
  const staleOrFailed =
    refresh_failed === true ||
    value === "stale" ||
    value === "retryable" ||
    hotelpage?.stale === true;
  const ready = value === "ready" && hotelpage?.ok === true && !staleOrFailed;
  const priceLabel = staleOrFailed
    ? RATEHAWK_REFRESH_FAILED_PRICE_LABEL
    : ready
      ? hotelpage.offers.find((offer) => offer.freshness.bookable)?.customer_total_label ??
        RATEHAWK_REFRESH_FAILED_PRICE_LABEL
      : null;

  return {
    ok: true,
    rendered: false,
    page: "HotelStayDetailPage",
    trigger: RATEHAWK_HOTELPAGE_ALLOWED_TRIGGER,
    hotel: {
      id: stay.id ?? null,
      hid: stay.provider_id ?? stay.hid ?? null,
      name: stay.name ?? null,
      address: stay.address ?? null,
      city: stay.city ?? null,
      image_url: stay.image_url ?? null,
    },
    existing_actions: Object.freeze([...EXISTING_HOTEL_DETAIL_ACTIONS]),
    existing_page_actions_preserved: EXISTING_HOTEL_PAGE_ACTIONS,
    mobility_independent_of_ratehawk: true,
    stay22_fallback_retained: true,
    saved_retained: true,
    nearby_events_retained: true,
    static_policies: policies,
    labels: disclosureLabelsFor(locale),
    ratehawk: {
      section: "optional_room_rate",
      state: value,
      hid: hotelpage?.hid ?? parseHid(stay.provider_id ?? stay.hid).hid ?? null,
      offers: ready ? hotelpage.offers : [],
      price_label: priceLabel,
      loading: value === "loading",
      unavailable: value === "unavailable",
      stale: value === "stale" || staleOrFailed,
      retryable: value === "retryable" || refresh_failed === true,
      must_prebook_before_confirmation: true,
    },
  };
}

export function buildProposedTestHotelpageRequest() {
  return buildRatehawkHotelpageRequest({
    hid: Number(RATEHAWK_TEST_HOTEL_HID),
    selectedCardHid: Number(RATEHAWK_TEST_HOTEL_HID),
    checkin: "2026-09-15",
    checkout: "2026-09-16",
    residency: "be",
    language: "en",
    currency: "EUR",
    guests: [{ adults: 2, children: [] }],
    timeout: RATEHAWK_HOTELPAGE_TIMEOUT_SECONDS,
    trigger: RATEHAWK_HOTELPAGE_ALLOWED_TRIGGER,
    searchContext: {
      hid: Number(RATEHAWK_TEST_HOTEL_HID),
      checkin: "2026-09-15",
      checkout: "2026-09-16",
      residency: "be",
      language: "en",
      currency: "EUR",
      guests: [{ adults: 2, children: [] }],
    },
  });
}

export function existingDetailActionsPreserved() {
  return [...EXISTING_HOTEL_DETAIL_ACTIONS];
}

export { RATEHAWK_DISCLOSURE_LOCALES, RATEHAWK_REFRESH_FAILED_PRICE_LABEL };
