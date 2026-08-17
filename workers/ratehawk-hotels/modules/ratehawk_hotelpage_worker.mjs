/**
 * Live RateHawk hotelpage Worker orchestration (P1).
 *
 * Called only after View stay on exactly one hid-backed hotel. Card/list
 * and HotelsPage open must never reach transport. Browser input is
 * normalized customer context only — never host, credentials, endpoint,
 * reconciliation, or settlement instructions.
 *
 * Offer references are AES-GCM sealed, context-bound, and expire at or
 * below the committed 30-minute hotelpage lifetime. book_hash / match_hash
 * never leave the server in the clear.
 */

import {
  base64urlDecodeToBytes,
  base64urlEncodeBytes,
} from "./crypto_utils.js";
import {
  EXISTING_HOTEL_PAGE_ACTIONS,
  RATEHAWK_STAY_CARD_SOURCE,
} from "./ratehawk_affiliate_contract.mjs";
import {
  RATEHAWK_HOTELPAGE_ALLOWED_TRIGGER,
  RATEHAWK_HOTELPAGE_PATH,
  RATEHAWK_HOTELPAGE_TTL_MS,
  RATEHAWK_REFRESH_FAILED_PRICE_LABEL,
  buildHotelStayDetailAdapter,
  buildRatehawkHotelpageRequest,
  normalizeRatehawkHotelpageResponse,
  shouldRequestRatehawkHotelpage,
} from "./ratehawk_hotelpage_contract.mjs";
import {
  RATEHAWK_SEARCH_SOURCES,
  fetchRatehawkHotelpage,
  isRatehawkHotelpageInvocationAllowed,
  redactRatehawkSecrets,
} from "./ratehawk_provider.mjs";

export const RATEHAWK_HOTELPAGE_PUBLIC_PATH =
  "/public/hotels/ratehawk/hotelpage";

const OFFER_REF_PREFIX = "rh1";
const OFFER_REF_PURPOSE = "ratehawk_hp_offer_v1";

const FORBIDDEN_CLIENT_KEYS = Object.freeze([
  "host",
  "base_url",
  "baseUrl",
  "api_key",
  "apiKey",
  "authorization",
  "endpoint",
  "url",
  "path",
  "reconciliation_amount",
  "commission",
  "commission_percent",
  "affiliate_percent",
  "settlement",
  "RATEHAWK_API_KEY",
  "RATEHAWK_KEY_ID",
  "book_hash",
  "match_hash",
]);

function _text(value, max = 200) {
  const text = String(value ?? "").trim();
  if (!text) return "";
  return text.length > max ? text.slice(0, max) : text;
}

function _lower(value) {
  return _text(value, 80).toLowerCase();
}

function _isRatehawkSource(value) {
  return RATEHAWK_SEARCH_SOURCES.includes(_lower(value).replace(/_/g, "-"));
}

function _hasForbiddenClientControl(body) {
  if (!body || typeof body !== "object" || Array.isArray(body)) return false;
  return FORBIDDEN_CLIENT_KEYS.some((key) =>
    Object.prototype.hasOwnProperty.call(body, key),
  );
}

function _stayFromBody(body) {
  return body?.stay && typeof body.stay === "object"
    ? body.stay
    : body?.selected_stay && typeof body.selected_stay === "object"
      ? body.selected_stay
      : {};
}

export function isRatehawkBackedStay(stay = {}, hid = null) {
  const provider = _lower(stay.provider ?? stay.source).replace(/_/g, "-");
  if (!_isRatehawkSource(provider)) return false;
  if (hid == null || hid === "") return false;
  const stayHid = _text(stay.provider_id ?? stay.hid, 16);
  return stayHid === String(hid).trim();
}

function _resolveHid(body, stay) {
  if (Array.isArray(body?.hid) || Array.isArray(body?.hids)) {
    const list = Array.isArray(body.hids) ? body.hids : body.hid;
    if (list.length !== 1) return { ok: false, reason: "hotelpage_requires_exactly_one_hid" };
    return { ok: true, hid: list[0] };
  }
  const hid = body?.hid ?? stay?.provider_id ?? stay?.hid ?? null;
  if (hid == null || hid === "") {
    return { ok: false, reason: "hid_required" };
  }
  return { ok: true, hid };
}

export function hasRatehawkOfferRefSecret(env) {
  return Boolean(_text(env?.RATEHAWK_OFFER_REF_SECRET, 800));
}

export function isRatehawkContentSyncAllowedOnCustomerRequest() {
  return false;
}

const _hotelpageInflight = new Map();

function _singleFlightHotelpage(key, fn) {
  const existing = _hotelpageInflight.get(key);
  if (existing) return existing;
  const pending = Promise.resolve()
    .then(fn)
    .finally(() => {
      _hotelpageInflight.delete(key);
    });
  _hotelpageInflight.set(key, pending);
  return pending;
}

async function _deriveOfferAesKey(env) {
  const secret = _text(env?.RATEHAWK_OFFER_REF_SECRET, 800);
  if (!secret) return null;
  const material = new TextEncoder().encode(`${secret}|${OFFER_REF_PURPOSE}`);
  const digest = await crypto.subtle.digest("SHA-256", material);
  return crypto.subtle.importKey(
    "raw",
    digest,
    { name: "AES-GCM" },
    false,
    ["encrypt", "decrypt"],
  );
}

export async function sealRatehawkOfferReference(env, claims) {
  const key = await _deriveOfferAesKey(env);
  if (!key) return { ok: false, reason: "offer_ref_secret_unavailable" };
  const iv = crypto.getRandomValues(new Uint8Array(12));
  const plaintext = new TextEncoder().encode(JSON.stringify(claims));
  const cipher = await crypto.subtle.encrypt(
    { name: "AES-GCM", iv },
    key,
    plaintext,
  );
  return {
    ok: true,
    offer_ref: `${OFFER_REF_PREFIX}.${base64urlEncodeBytes(iv)}.${base64urlEncodeBytes(new Uint8Array(cipher))}`,
  };
}

export async function openRatehawkOfferReference(
  env,
  token,
  { now = Date.now(), hid = null } = {},
) {
  const key = await _deriveOfferAesKey(env);
  if (!key) return { ok: false, reason: "offer_ref_secret_unavailable" };
  const parts = String(token || "").split(".");
  if (parts.length !== 3 || parts[0] !== OFFER_REF_PREFIX) {
    return { ok: false, reason: "offer_ref_malformed" };
  }
  try {
    const iv = base64urlDecodeToBytes(parts[1]);
    const cipher = base64urlDecodeToBytes(parts[2]);
    const plain = await crypto.subtle.decrypt(
      { name: "AES-GCM", iv },
      key,
      cipher,
    );
    const claims = JSON.parse(new TextDecoder().decode(plain));
    if (Number(now) >= Number(claims.expires_at)) {
      return { ok: false, reason: "offer_expired", bookable: false };
    }
    if (hid != null && Number(claims.hid) !== Number(hid)) {
      return { ok: false, reason: "offer_hid_mismatch" };
    }
    return { ok: true, claims, bookable: true };
  } catch {
    return { ok: false, reason: "offer_ref_invalid" };
  }
}

function _customerTaxLine(tax) {
  if (!tax) return null;
  return {
    name: tax.name ?? null,
    included_by_supplier: tax.included_by_supplier === true,
    payable_where: tax.payable_where ?? null,
    amount: tax.amount ?? null,
  };
}

function _customerPenalty(policy) {
  if (!policy) return null;
  return {
    start_at: policy.start_at ?? null,
    end_at: policy.end_at ?? null,
    show_amount: policy.show_amount ?? null,
  };
}

function _customerPayment(payment) {
  if (!payment) return null;
  return {
    type: payment.payment_type ?? null,
    recipient: payment.payment_recipient ?? null,
    timing: payment.payment_timing ?? null,
    customer_pays: payment.customer_pays ?? null,
  };
}

function _customerDeposit(deposit) {
  if (!deposit || deposit.ok !== true) return { disclosed: false };
  return {
    disclosed: deposit.disclosed === true,
    amount: deposit.amount ?? null,
    currency: deposit.currency ?? null,
    refundable: deposit.refundable === true,
    payment_recipient: deposit.payment_recipient ?? null,
    payment_timing: deposit.payment_timing ?? null,
    customer_disclosure_required: deposit.customer_disclosure_required === true,
  };
}

function _customerNoShow(noShow) {
  if (!noShow || noShow.ok !== true) return { disclosed: false };
  return {
    disclosed: noShow.disclosed === true,
    obligation_kind: noShow.obligation_kind ?? null,
    amount: noShow.amount ?? null,
    currency: noShow.currency ?? null,
    from_time: noShow.from_time ?? null,
    timezone_context: noShow.timezone_context ?? null,
    included_in_room_total: noShow.included_in_room_total === true,
    converted: false,
    customer_disclosure_required: noShow.customer_disclosure_required === true,
  };
}

export function toCustomerHotelpageOffer(offer) {
  const freshness = offer?.freshness || {};
  const bookable = freshness.bookable === true;
  return {
    offer_ref: offer?.offer_ref ?? null,
    room_name: offer?.room_name ?? null,
    room_description: offer?.room_description ?? null,
    occupancy: offer?.occupancy ?? null,
    beds: offer?.bed_information ?? null,
    meal_plan: offer?.meal_plan ?? null,
    breakfast_included: offer?.breakfast_included === true,
    customer_total: offer?.customer_total ?? null,
    customer_total_label: offer?.customer_total_label ?? null,
    included_taxes: Array.isArray(offer?.included_taxes)
      ? offer.included_taxes.map(_customerTaxLine)
      : [],
    excluded_taxes: Array.isArray(offer?.excluded_taxes)
      ? offer.excluded_taxes.map(_customerTaxLine)
      : [],
    vat: { included: offer?.vat?.included === true },
    payment: _customerPayment(offer?.payment),
    card_data_required: offer?.card_data_required === true,
    cvc_required: offer?.cvc_required === true,
    refundable: offer?.refundable === true,
    free_cancellation_before: offer?.free_cancellation_before ?? null,
    cancellation: {
      refundable: offer?.refundable === true,
      free_cancellation_before: offer?.free_cancellation_before ?? null,
      penalties: Array.isArray(offer?.cancellation_penalties)
        ? offer.cancellation_penalties.map(_customerPenalty)
        : [],
    },
    deposit: _customerDeposit(offer?.deposit),
    no_show: _customerNoShow(offer?.no_show),
    remaining_availability: offer?.remaining_availability ?? null,
    retrieved_at: freshness.retrieved_at ?? null,
    expires_at: freshness.expires_at ?? null,
    bookable,
    state: bookable ? "ready" : freshness.state ?? "unavailable",
    must_prebook_before_confirmation: true,
  };
}

function _safeDto({
  stay = {},
  state = "unavailable",
  reason = null,
  invoked = false,
  offers = [],
  hotelpage = null,
  locale = "nl",
  refreshFailed = false,
}) {
  const adapter = buildHotelStayDetailAdapter({
    stay,
    hotelpage,
    state,
    locale,
    refresh_failed: refreshFailed,
  });
  const customerOffers = offers.map(toCustomerHotelpageOffer);
  const retrievedAt = hotelpage?.retrieved_at ?? null;
  const expiresAt =
    retrievedAt != null ? retrievedAt + RATEHAWK_HOTELPAGE_TTL_MS : null;
  return {
    ...adapter,
    invoked: invoked === true,
    reason,
    ratehawk: {
      ...adapter.ratehawk,
      offers: state === "ready" ? customerOffers : [],
      retrieved_at: retrievedAt,
      expires_at: expiresAt,
      path: RATEHAWK_HOTELPAGE_PATH,
    },
    commercial: {
      fluxidi_role: "affiliate",
      customer_pays_fluxidi: false,
      mollie_involved: false,
    },
    existing_page_actions_preserved: EXISTING_HOTEL_PAGE_ACTIONS,
  };
}

function _redactDto(dto, env) {
  return redactRatehawkSecrets(dto, env);
}

export async function handleRatehawkHotelpageRequest({
  env,
  body = {},
  fetchImpl = null,
  now = Date.now(),
  timeoutMs = null,
} = {}) {
  const requestBody = body && typeof body === "object" && !Array.isArray(body)
    ? body
    : {};
  const stay = _stayFromBody(requestBody);
  const locale = _text(requestBody.locale, 8) || "nl";

  if (_hasForbiddenClientControl(requestBody)) {
    return _redactDto(
      _safeDto({
        stay,
        state: "unavailable",
        reason: "client_control_forbidden",
        invoked: false,
        locale,
      }),
      env,
    );
  }

  const triggerGate = shouldRequestRatehawkHotelpage(requestBody.trigger);
  if (triggerGate.allowed !== true) {
    return _redactDto(
      _safeDto({
        stay,
        state: "unavailable",
        reason: triggerGate.reason,
        invoked: false,
        locale,
      }),
      env,
    );
  }

  const hidResult = _resolveHid(requestBody, stay);
  if (!hidResult.ok) {
    return _redactDto(
      _safeDto({
        stay,
        state: "unavailable",
        reason: hidResult.reason,
        invoked: false,
        locale,
      }),
      env,
    );
  }

  const sourceHint = requestBody.source ?? requestBody.provider ?? stay.provider ?? stay.source;
  const ratehawkBacked =
    isRatehawkBackedStay(stay, hidResult.hid) ||
    (_isRatehawkSource(sourceHint) &&
      !stay.provider &&
      !stay.source &&
      hidResult.hid != null);

  if (!ratehawkBacked) {
    return _redactDto(
      _safeDto({
        stay,
        state: "unavailable",
        reason: "stay_not_ratehawk_backed",
        invoked: false,
        locale,
      }),
      env,
    );
  }

  if (!isRatehawkHotelpageInvocationAllowed(env)) {
    return _redactDto(
      _safeDto({
        stay,
        state: "unavailable",
        reason: "hotelpage_disabled",
        invoked: false,
        locale,
      }),
      env,
    );
  }

  if (!hasRatehawkOfferRefSecret(env)) {
    return _redactDto(
      _safeDto({
        stay,
        state: "unavailable",
        reason: "offer_ref_secret_missing",
        invoked: false,
        locale,
      }),
      env,
    );
  }

  const request = buildRatehawkHotelpageRequest({
    hid: hidResult.hid,
    hotelName: requestBody.hotel_name ?? requestBody.hotelName ?? null,
    checkin: requestBody.checkin,
    checkout: requestBody.checkout,
    residency: requestBody.residency,
    language: requestBody.language,
    currency: requestBody.currency,
    guests: requestBody.guests,
    filter: requestBody.filter ?? null,
    timeout: requestBody.timeout,
    trigger: requestBody.trigger || RATEHAWK_HOTELPAGE_ALLOWED_TRIGGER,
    selectedCardHid:
      requestBody.selected_card_hid ??
      requestBody.selectedCardHid ??
      stay.provider_id ??
      hidResult.hid,
    searchContext: requestBody.search_context ?? requestBody.searchContext ?? null,
    now,
  });
  if (request.ok !== true) {
    return _redactDto(
      _safeDto({
        stay,
        state: "unavailable",
        reason: request.reason,
        invoked: false,
        locale,
      }),
      env,
    );
  }

  const flightKey = JSON.stringify(request.search_context);
  return _singleFlightHotelpage(flightKey, () =>
    _executeHotelpageTransport({
      env,
      stay,
      locale,
      request,
      fetchImpl,
      timeoutMs,
      now,
    }),
  );
}

async function _executeHotelpageTransport({
  env,
  stay,
  locale,
  request,
  fetchImpl,
  timeoutMs,
  now,
}) {
  const transport = await fetchRatehawkHotelpage({
    env,
    body: request.body,
    fetchImpl,
    timeoutMs,
  });

  if (transport.invoked !== true) {
    return _redactDto(
      _safeDto({
        stay,
        state: "unavailable",
        reason: transport.reason || "hotelpage_disabled",
        invoked: false,
        locale,
      }),
      env,
    );
  }

  if (transport.ok !== true) {
    const retryable = true;
    return _redactDto(
      _safeDto({
        stay,
        state: "retryable",
        reason: transport.reason || "provider_error",
        invoked: true,
        locale,
        refreshFailed: retryable,
      }),
      env,
    );
  }

  const retrievedAt = Number(now);
  const page = normalizeRatehawkHotelpageResponse({
    requestedHid: request.body.hid,
    retrieved_at: retrievedAt,
    hotels: transport.hotels,
    now: retrievedAt,
  });

  if (page.ok !== true && (!Array.isArray(page.offers) || page.offers.length === 0)) {
    const depositClosed = page.reason === "deposit_requires_fluxidi_to_fund_etg";
    return _redactDto(
      _safeDto({
        stay,
        state: depositClosed ? "unavailable" : "retryable",
        reason: page.reason || "hotelpage_unavailable",
        invoked: true,
        locale,
        refreshFailed: !depositClosed,
        hotelpage: page.ok === true ? page : null,
      }),
      env,
    );
  }

  const sealedOffers = [];
  for (const offer of page.offers || []) {
    if (offer?.freshness?.bookable !== true) continue;
    const sealed = await sealRatehawkOfferReference(env, {
      v: 1,
      hid: page.hid,
      book_hash: offer.book_hash,
      match_hash: offer.match_hash,
      retrieved_at: retrievedAt,
      expires_at: retrievedAt + RATEHAWK_HOTELPAGE_TTL_MS,
      checkin: request.body.checkin,
      checkout: request.body.checkout,
      residency: request.body.residency,
      currency: request.body.currency,
      guests: request.body.guests,
    });
    if (sealed.ok !== true) continue;
    sealedOffers.push({ ...offer, offer_ref: sealed.offer_ref });
  }

  if (sealedOffers.length === 0) {
    return _redactDto(
      _safeDto({
        stay,
        state: "retryable",
        reason: page.reason || "hotelpage_unavailable",
        invoked: true,
        locale,
        refreshFailed: true,
        hotelpage: page,
      }),
      env,
    );
  }

  const readyPage = {
    ...page,
    ok: true,
    offers: sealedOffers,
    bookable_count: sealedOffers.length,
    stale: false,
  };

  return _redactDto(
    _safeDto({
      stay,
      state: "ready",
      reason: null,
      invoked: true,
      offers: sealedOffers,
      hotelpage: readyPage,
      locale,
    }),
    env,
  );
}
