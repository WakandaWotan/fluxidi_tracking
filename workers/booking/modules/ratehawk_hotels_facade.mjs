/**
 * Booking Worker RateHawk facade.
 *
 * Public app routes stay POST /public/hotels/ratehawk/hotelpage,
 * POST /public/hotels/ratehawk/prebook and
 * POST /public/hotels/ratehawk/prebook/accept.
 * This module must not resolve RateHawk credentials, construct provider
 * Authorization, call the provider host, decrypt offer references, or
 * normalize raw provider payloads.
 */

import { sha256Hex } from "./crypto_utils.js";
import {
  issueRatehawkViewStayContext,
  openRatehawkViewStayContext,
  verifyRatehawkViewStayContext,
} from "../../ratehawk-hotels/modules/ratehawk_view_stay_context.mjs";
import {
  assertRatehawkTestStay,
  hasForbiddenRatehawkTestClientControl,
} from "../../ratehawk-hotels/modules/ratehawk_test_activation.mjs";
import { hasForbiddenPublicSearchClientControl } from "../../ratehawk-hotels/modules/ratehawk_market_search_limits.mjs";
import { hasForbiddenPublicPrebookClientControl } from "../../ratehawk-hotels/modules/ratehawk_prebook_contract.mjs";
import {
  RATEHAWK_HOTELS_PREBOOK_ACCEPT_PATH,
  RATEHAWK_HOTELS_PREBOOK_PATH,
} from "../../ratehawk-hotels/modules/ratehawk_prebook_worker.mjs";

export const RATEHAWK_HOTELPAGE_PUBLIC_PATH =
  "/public/hotels/ratehawk/hotelpage";
export const RATEHAWK_PREBOOK_PUBLIC_PATH =
  "/public/hotels/ratehawk/prebook";
export const RATEHAWK_PREBOOK_ACCEPT_PUBLIC_PATH =
  "/public/hotels/ratehawk/prebook/accept";
export const RATEHAWK_HOTELS_BINDING = "RATEHAWK_HOTELS";
export const RATEHAWK_HOTELS_SERVICE_NAME = "fluxidi-ratehawk-hotels-api";
export const RATEHAWK_HOTELS_TEST_BINDING = "RATEHAWK_HOTELS_TEST";
export const RATEHAWK_HOTELS_TEST_SERVICE_NAME =
  "fluxidi-ratehawk-hotels-api-test";
export const RATEHAWK_HOTELS_INTERNAL_PROXY = "booking_worker_v1";
export const RATEHAWK_TEST_VIEW_STAY_CONTEXT_SECRET_NAME =
  "RATEHAWK_TEST_VIEW_STAY_CONTEXT_SECRET";
export const RATEHAWK_HOTELS_SEARCH_PATH = "/internal/search";
export const RATEHAWK_HOTELS_TEST_SEARCH_PATH = "/internal/test-search";
export const RATEHAWK_HOTELS_TEST_HOTELPAGE_PATH = "/internal/test-hotelpage";
export const RATEHAWK_ADMIN_TEST_SEARCH_PATH =
  "/admin/hotels/ratehawk/test/search";
export const RATEHAWK_ADMIN_TEST_HOTELPAGE_PATH =
  "/admin/hotels/ratehawk/test/hotelpage";
export const RATEHAWK_SEARCH_SOURCES = Object.freeze([
  "ratehawk",
  "rate-hawk",
  "etg",
  "emerging-travel",
]);

const HOTELPAGE_RATE_MAX = 20;
const HOTELPAGE_RATE_WINDOW_SECONDS = 60;
const SEARCH_RATE_MAX = 20;
const SEARCH_RATE_WINDOW_SECONDS = 60;

function _text(value, max = 200) {
  const text = String(value ?? "").trim();
  if (!text) return "";
  return text.length > max ? text.slice(0, max) : text;
}

function _flag(value) {
  return ["1", "true", "yes", "on"].includes(String(value ?? "").trim().toLowerCase());
}

export function isBookingRatehawkTestSearchEnabled(env = {}) {
  return _flag(env.RATEHAWK_TEST_SEARCH_ENABLED);
}

export function isBookingRatehawkTestHotelpageEnabled(env = {}) {
  return _flag(env.RATEHAWK_TEST_HOTELPAGE_ENABLED);
}

function _lower(value) {
  return _text(value, 80).toLowerCase();
}

export function isRatehawkSearchSource(source) {
  return RATEHAWK_SEARCH_SOURCES.includes(_lower(source).replace(/_/g, "-"));
}

export function bookingWorkerHasRatehawkCredentials(env = {}) {
  return Boolean(
    _text(env.RATEHAWK_API_KEY, 800) ||
      _text(env.RATEHAWK_KEY_ID, 120) ||
      _text(env.RATEHAWK_OFFER_REF_SECRET, 800),
  );
}

export function bookingWorkerCanConstructRatehawkAuthorization(env = {}) {
  return Boolean(
    _text(env.RATEHAWK_KEY_ID, 120) && _text(env.RATEHAWK_API_KEY, 800),
  );
}

export function buildRatehawkPublicSearchGuardPayload({
  warnings = [],
  source = "ratehawk",
} = {}) {
  const nextWarnings = Array.isArray(warnings) ? [...warnings] : [];
  if (!nextWarnings.includes("ratehawk_invocation_blocked")) {
    nextWarnings.push("ratehawk_invocation_blocked");
  }
  if (!nextWarnings.includes("ratehawk_search_not_implemented")) {
    nextWarnings.push("ratehawk_search_not_implemented");
  }
  const normalizedSource = isRatehawkSearchSource(source)
    ? "ratehawk"
    : _text(source, 64) || "ratehawk";
  return {
    ok: true,
    source: normalizedSource,
    provider: "ratehawk",
    count: 0,
    stays: [],
    warnings: nextWarnings,
    ratehawk: {
      invocation_allowed: false,
      connected: false,
      status: "isolated_hotels_worker",
    },
  };
}

function _safeHotelUnavailable(reason) {
  return {
    ok: true,
    invoked: false,
    reason,
    page: "HotelStayDetailPage",
    rendered: false,
    stay22_fallback_retained: true,
    mobility_independent_of_ratehawk: true,
    saved_retained: true,
    nearby_events_retained: true,
    existing_actions: [
      "saved",
      "nearby_events",
      "taxi_to_this_event",
      "taxi_to_this_stay",
      "airport_transfer",
      "stay22_fallback_availability",
    ],
    ratehawk: {
      section: "optional_room_rate",
      state: "unavailable",
      offers: [],
      retryable: false,
      must_prebook_before_confirmation: true,
    },
    commercial: {
      fluxidi_role: "affiliate",
      customer_pays_fluxidi: false,
      mollie_involved: false,
    },
  };
}

function _expectedContextFromBody(body) {
  const stay = body?.stay && typeof body.stay === "object" ? body.stay : {};
  return {
    source: "ratehawk",
    hid: body?.hid ?? stay.provider_id ?? stay.hid,
    checkin: body?.checkin,
    checkout: body?.checkout,
    residency: body?.residency,
    currency: body?.currency,
    guests: body?.guests,
  };
}

async function _incrementHotelpageRateLimit(env, request) {
  if (!env?.BOOKING_KV || typeof env.BOOKING_KV.get !== "function") {
    return { ok: false, limited: true, reason: "rate_limit_binding_missing" };
  }
  const ip = _text(
    request?.headers?.get("cf-connecting-ip") ||
      request?.headers?.get("x-forwarded-for") ||
      "unknown",
    80,
  );
  const clientHash = await sha256Hex(`ratehawk-hotelpage:${ip}`);
  const rateKey = `ratehawk:hotelpage:${clientHash}`;
  const rawRate = await env.BOOKING_KV.get(rateKey, { type: "json" });
  const rateSource =
    rawRate && typeof rawRate === "object" && !Array.isArray(rawRate)
      ? rawRate
      : {};
  const count = Number.isFinite(Number(rateSource.count))
    ? Math.max(0, Math.round(Number(rateSource.count)))
    : 0;
  if (count >= HOTELPAGE_RATE_MAX) {
    return { ok: true, limited: true, reason: "rate_limited", count };
  }
  await env.BOOKING_KV.put(
    rateKey,
    JSON.stringify({
      count: count + 1,
      updated_at: new Date().toISOString(),
    }),
    { expirationTtl: HOTELPAGE_RATE_WINDOW_SECONDS },
  );
  return { ok: true, limited: false, count: count + 1 };
}

async function _incrementSearchRateLimit(env, request) {
  if (!env?.BOOKING_KV || typeof env.BOOKING_KV.get !== "function") {
    return { ok: false, limited: true, reason: "rate_limit_binding_missing" };
  }
  const ip = _text(
    request?.headers?.get("cf-connecting-ip") ||
      request?.headers?.get("x-forwarded-for") ||
      "unknown",
    80,
  );
  const clientHash = await sha256Hex(`ratehawk-search:${ip}`);
  const rateKey = `ratehawk:search:${clientHash}`;
  const rawRate = await env.BOOKING_KV.get(rateKey, { type: "json" });
  const rateSource =
    rawRate && typeof rawRate === "object" && !Array.isArray(rawRate)
      ? rawRate
      : {};
  const count = Number.isFinite(Number(rateSource.count))
    ? Math.max(0, Math.round(Number(rateSource.count)))
    : 0;
  if (count >= SEARCH_RATE_MAX) {
    return { ok: true, limited: true, reason: "rate_limited", count };
  }
  await env.BOOKING_KV.put(
    rateKey,
    JSON.stringify({
      count: count + 1,
      updated_at: new Date().toISOString(),
    }),
    { expirationTtl: SEARCH_RATE_WINDOW_SECONDS },
  );
  return { ok: true, limited: false, count: count + 1 };
}

function _safePublicSearchUnavailable({
  reason,
  warnings = [],
  source = "ratehawk",
  retryAfter = null,
} = {}) {
  const nextWarnings = Array.isArray(warnings) ? [...warnings] : [];
  if (!nextWarnings.includes("ratehawk_invocation_blocked")) {
    nextWarnings.push("ratehawk_invocation_blocked");
  }
  return {
    ok: true,
    invoked: false,
    reason,
    source,
    provider: "ratehawk",
    count: 0,
    stays: [],
    warnings: [...new Set(nextWarnings)],
    retry_after:
      retryAfter == null || !Number.isFinite(Number(retryAfter))
        ? null
        : Math.max(1, Math.round(Number(retryAfter))),
    ratehawk: {
      invocation_allowed: false,
      connected: false,
      status: "fail_closed",
    },
    stay22_fallback_retained: true,
    mobility_independent_of_ratehawk: true,
  };
}

export async function fetchRatehawkHotelsStatus(env) {
  if (!env?.RATEHAWK_HOTELS || typeof env.RATEHAWK_HOTELS.fetch !== "function") {
    return {
      configured: false,
      enabled: false,
      invocation_allowed: false,
      connected: false,
      status: "hotels_worker_binding_missing",
      isolated: true,
    };
  }
  try {
    const resp = await env.RATEHAWK_HOTELS.fetch(
      new Request("https://fluxidi-ratehawk-hotels-api.internal/internal/status", {
        method: "GET",
        headers: {
          accept: "application/json",
          "x-fluxidi-internal-proxy": RATEHAWK_HOTELS_INTERNAL_PROXY,
        },
      }),
    );
    const payload = await resp.json();
    return payload?.ratehawk && typeof payload.ratehawk === "object"
      ? { ...payload.ratehawk, isolated: true }
      : {
          configured: false,
          connected: false,
          status: "hotels_worker_status_unavailable",
          isolated: true,
        };
  } catch {
    return {
      configured: false,
      connected: false,
      status: "hotels_worker_status_unavailable",
      isolated: true,
    };
  }
}

export async function handlePublicRatehawkSearch({
  env,
  query = {},
  warnings = [],
  request = null,
} = {}) {
  const source = isRatehawkSearchSource(query?.source)
    ? "ratehawk"
    : _text(query?.source, 64) || "ratehawk";
  const nextWarnings = Array.isArray(warnings) ? [...warnings] : [];
  if (Array.isArray(query?.warnings)) {
    nextWarnings.push(...query.warnings);
  }

  if (bookingWorkerHasRatehawkCredentials(env)) {
    return buildRatehawkPublicSearchGuardPayload({
      warnings: nextWarnings,
      source,
    });
  }

  if (hasForbiddenPublicSearchClientControl(query)) {
    return _safePublicSearchUnavailable({
      reason: "client_control_forbidden",
      warnings: nextWarnings,
      source,
    });
  }

  const abuse = await _incrementSearchRateLimit(env, request);
  if (abuse.ok !== true || abuse.limited === true) {
    return _safePublicSearchUnavailable({
      reason: abuse.reason || "rate_limited",
      warnings: nextWarnings,
      source,
    });
  }

  if (!env?.RATEHAWK_HOTELS || typeof env.RATEHAWK_HOTELS.fetch !== "function") {
    return buildRatehawkPublicSearchGuardPayload({
      warnings: [...nextWarnings, "hotels_worker_binding_missing"],
      source,
    });
  }

  const rooms = Number(query?.rooms);
  const adults = Number(query?.adults);
  const children = Number(query?.children);
  const childAges = Array.isArray(query?.child_ages)
    ? query.child_ages
    : String(query?.child_ages || "")
        .split(",")
        .map((value) => Number(String(value).trim()))
        .filter((value) => Number.isFinite(value));
  const guests =
    Number.isFinite(rooms) && rooms >= 1 && Number.isFinite(adults) && adults >= 1
      ? Array.from({ length: Math.min(8, Math.round(rooms)) }, () => ({
          adults: Math.max(1, Math.round(adults)),
          children: childAges.slice(0, Math.max(0, Math.round(children) || 0)),
        }))
      : [];

  try {
    const resp = await env.RATEHAWK_HOTELS.fetch(
      new Request(
        `https://fluxidi-ratehawk-hotels-api.internal${RATEHAWK_HOTELS_SEARCH_PATH}`,
        {
          method: "POST",
          headers: {
            accept: "application/json",
            "content-type": "application/json",
            "x-fluxidi-internal-proxy": RATEHAWK_HOTELS_INTERNAL_PROXY,
          },
          body: JSON.stringify({
            trigger: "live_search",
            city: _text(query?.city, 120),
            country: _text(query?.country, 80),
            region: _text(query?.region, 120),
            destination: _text(query?.searchText, 200),
            market_key: _text(query?.market_key, 80),
            checkin: _text(query?.checkin, 16),
            checkout: _text(query?.checkout, 16),
            residency: _text(query?.residency, 2),
            language: _text(query?.language, 8),
            currency: _text(query?.currency, 3),
            guests,
          }),
        },
      ),
    );
    const dto = await resp.json();
    if (!dto || typeof dto !== "object" || Array.isArray(dto)) {
      return buildRatehawkPublicSearchGuardPayload({
        warnings: nextWarnings,
        source,
      });
    }
    const stays = Array.isArray(dto.stays) ? dto.stays : [];
    const dtoWarnings = Array.isArray(dto.warnings) ? dto.warnings : [];
    return {
      ...dto,
      ok: true,
      source,
      provider: "ratehawk",
      count: stays.length,
      stays,
      warnings: [...new Set([...nextWarnings, ...dtoWarnings])],
    };
  } catch {
    return buildRatehawkPublicSearchGuardPayload({
      warnings: nextWarnings,
      source,
    });
  }
}

export async function handlePublicRatehawkHotelpage({
  env,
  request = null,
  body = {},
  now = Date.now(),
} = {}) {
  const requestBody =
    body && typeof body === "object" && !Array.isArray(body) ? body : {};

  if (bookingWorkerHasRatehawkCredentials(env)) {
    return _safeHotelUnavailable("booking_worker_must_not_hold_ratehawk_secrets");
  }

  const rate = await _incrementHotelpageRateLimit(env, request);
  if (rate.ok !== true || rate.limited === true) {
    return _safeHotelUnavailable(rate.reason || "rate_limited");
  }

  const contextSecret = _text(env?.RATEHAWK_VIEW_STAY_CONTEXT_SECRET, 800);
  const context = await verifyRatehawkViewStayContext(
    contextSecret,
    requestBody.view_stay_context ?? requestBody.selected_card_context,
    _expectedContextFromBody(requestBody),
    { now },
  );
  if (context.ok !== true) {
    return _safeHotelUnavailable(context.reason);
  }

  if (!env?.RATEHAWK_HOTELS || typeof env.RATEHAWK_HOTELS.fetch !== "function") {
    return _safeHotelUnavailable("hotels_worker_binding_missing");
  }

  try {
    const resp = await env.RATEHAWK_HOTELS.fetch(
      new Request(
        "https://fluxidi-ratehawk-hotels-api.internal/internal/hotelpage",
        {
          method: "POST",
          headers: {
            accept: "application/json",
            "content-type": "application/json",
            "x-fluxidi-internal-proxy": RATEHAWK_HOTELS_INTERNAL_PROXY,
          },
          body: JSON.stringify(requestBody),
        },
      ),
    );
    const dto = await resp.json();
    if (!dto || typeof dto !== "object") {
      return _safeHotelUnavailable("hotels_worker_unavailable");
    }
    return dto;
  } catch {
    return _safeHotelUnavailable("hotels_worker_unavailable");
  }
}

async function _incrementPrebookRateLimit(env, request) {
  if (!env?.BOOKING_KV || typeof env.BOOKING_KV.get !== "function") {
    return { ok: false, limited: true, reason: "rate_limit_binding_missing" };
  }
  const ip = _text(
    request?.headers?.get("cf-connecting-ip") ||
      request?.headers?.get("x-forwarded-for") ||
      "unknown",
    80,
  );
  const clientHash = await sha256Hex(`ratehawk-prebook:${ip}`);
  const rateKey = `ratehawk:prebook:${clientHash}`;
  const rawRate = await env.BOOKING_KV.get(rateKey, { type: "json" });
  const rateSource =
    rawRate && typeof rawRate === "object" && !Array.isArray(rawRate)
      ? rawRate
      : {};
  const count = Number.isFinite(Number(rateSource.count))
    ? Math.max(0, Math.round(Number(rateSource.count)))
    : 0;
  if (count >= HOTELPAGE_RATE_MAX) {
    return { ok: true, limited: true, reason: "rate_limited", count };
  }
  await env.BOOKING_KV.put(
    rateKey,
    JSON.stringify({
      count: count + 1,
      updated_at: new Date().toISOString(),
    }),
    { expirationTtl: HOTELPAGE_RATE_WINDOW_SECONDS },
  );
  return { ok: true, limited: false, count: count + 1 };
}

function _safePrebookUnavailable(reason) {
  return {
    ok: true,
    invoked: false,
    reason,
    progress_blocked: true,
    acceptance_allowed: false,
    prebook_ref: null,
    accepted_ref: null,
    changes: [],
    stay22_fallback_retained: true,
    mobility_independent_of_ratehawk: true,
    existing_actions: [
      "saved",
      "nearby_events",
      "taxi_to_this_event",
      "taxi_to_this_stay",
      "airport_transfer",
      "stay22_fallback_availability",
    ],
    commercial: {
      fluxidi_role: "affiliate",
      customer_pays_fluxidi: false,
      mollie_involved: false,
    },
  };
}

async function _proxyProductionHotelsPath(env, path, body) {
  if (!env?.RATEHAWK_HOTELS || typeof env.RATEHAWK_HOTELS.fetch !== "function") {
    return { ok: false, dto: _safePrebookUnavailable("hotels_worker_binding_missing") };
  }
  try {
    const resp = await env.RATEHAWK_HOTELS.fetch(
      new Request(`https://fluxidi-ratehawk-hotels-api.internal${path}`, {
        method: "POST",
        headers: {
          accept: "application/json",
          "content-type": "application/json",
          "x-fluxidi-internal-proxy": RATEHAWK_HOTELS_INTERNAL_PROXY,
        },
        body: JSON.stringify(body),
      }),
    );
    const dto = await resp.json();
    if (!dto || typeof dto !== "object") {
      return { ok: false, dto: _safePrebookUnavailable("hotels_worker_unavailable") };
    }
    return { ok: true, dto };
  } catch {
    return { ok: false, dto: _safePrebookUnavailable("hotels_worker_unavailable") };
  }
}

export async function handlePublicRatehawkPrebook({
  env,
  request = null,
  body = {},
} = {}) {
  const requestBody =
    body && typeof body === "object" && !Array.isArray(body) ? body : {};
  if (bookingWorkerHasRatehawkCredentials(env)) {
    return _safePrebookUnavailable("booking_worker_must_not_hold_ratehawk_secrets");
  }
  if (hasForbiddenPublicPrebookClientControl(requestBody)) {
    return _safePrebookUnavailable("client_control_forbidden");
  }
  const rate = await _incrementPrebookRateLimit(env, request);
  if (rate.ok !== true || rate.limited === true) {
    return _safePrebookUnavailable(rate.reason || "rate_limited");
  }
  const proxied = await _proxyProductionHotelsPath(
    env,
    RATEHAWK_HOTELS_PREBOOK_PATH,
    {
      trigger: "prebook_revalidation",
      offer_ref: _text(requestBody.offer_ref, 4000),
      locale: _text(requestBody.locale, 8) || "nl",
    },
  );
  return proxied.dto;
}

export async function handlePublicRatehawkPrebookAccept({
  env,
  request = null,
  body = {},
} = {}) {
  const requestBody =
    body && typeof body === "object" && !Array.isArray(body) ? body : {};
  if (bookingWorkerHasRatehawkCredentials(env)) {
    return _safePrebookUnavailable("booking_worker_must_not_hold_ratehawk_secrets");
  }
  if (hasForbiddenPublicPrebookClientControl(requestBody)) {
    return _safePrebookUnavailable("client_control_forbidden");
  }
  const rate = await _incrementPrebookRateLimit(env, request);
  if (rate.ok !== true || rate.limited === true) {
    return _safePrebookUnavailable(rate.reason || "rate_limited");
  }
  const proxied = await _proxyProductionHotelsPath(
    env,
    RATEHAWK_HOTELS_PREBOOK_ACCEPT_PATH,
    {
      trigger: "accept_prebook_terms",
      prebook_ref: _text(requestBody.prebook_ref, 4000),
      terms_revision: _text(requestBody.terms_revision, 120),
      locale: _text(requestBody.locale, 8) || "nl",
    },
  );
  return proxied.dto;
}

function _safeTestUnavailable(reason) {
  return {
    ok: false,
    invoked: false,
    binding_called: false,
    reason,
    source: "ratehawk",
    provider: "ratehawk",
    count: 0,
    stays: [],
    view_stay_context: null,
    stay22_fallback_retained: true,
    mobility_independent_of_ratehawk: true,
    commercial: {
      fluxidi_role: "affiliate",
      customer_pays_fluxidi: false,
      mollie_involved: false,
    },
  };
}

async function _proxyHotelsTestPath(env, path, body) {
  if (
    !env?.RATEHAWK_HOTELS_TEST ||
    typeof env.RATEHAWK_HOTELS_TEST.fetch !== "function"
  ) {
    return {
      ok: false,
      dto: _safeTestUnavailable("hotels_test_worker_binding_missing"),
    };
  }
  try {
    const resp = await env.RATEHAWK_HOTELS_TEST.fetch(
      new Request(`https://fluxidi-ratehawk-hotels-api-test.internal${path}`, {
        method: "POST",
        headers: {
          accept: "application/json",
          "content-type": "application/json",
          "x-fluxidi-internal-proxy": RATEHAWK_HOTELS_INTERNAL_PROXY,
        },
        body: JSON.stringify(body),
      }),
    );
    const dto = await resp.json();
    if (!dto || typeof dto !== "object") {
      return { ok: false, dto: _safeTestUnavailable("hotels_worker_unavailable") };
    }
    return { ok: true, dto };
  } catch {
    return { ok: false, dto: _safeTestUnavailable("hotels_worker_unavailable") };
  }
}

export async function handleAdminRatehawkTestSearch({
  env,
  body = {},
  now = Date.now(),
} = {}) {
  const requestBody =
    body && typeof body === "object" && !Array.isArray(body) ? body : {};
  if (bookingWorkerHasRatehawkCredentials(env)) {
    return _safeTestUnavailable("booking_worker_must_not_hold_ratehawk_secrets");
  }
  if (hasForbiddenRatehawkTestClientControl(requestBody)) {
    return _safeTestUnavailable("client_control_forbidden");
  }
  if (!isBookingRatehawkTestSearchEnabled(env)) {
    return _safeTestUnavailable("test_search_disabled");
  }
  if (!_text(env?.RATEHAWK_TEST_VIEW_STAY_CONTEXT_SECRET, 800)) {
    return _safeTestUnavailable("view_stay_context_secret_missing");
  }
  const proxied = await _proxyHotelsTestPath(
    env,
    RATEHAWK_HOTELS_TEST_SEARCH_PATH,
    {},
  );
  return proxied.dto;
}

export async function handleAdminRatehawkTestHotelpage({
  env,
  body = {},
  now = Date.now(),
} = {}) {
  const requestBody =
    body && typeof body === "object" && !Array.isArray(body) ? body : {};
  if (bookingWorkerHasRatehawkCredentials(env)) {
    return _safeTestUnavailable("booking_worker_must_not_hold_ratehawk_secrets");
  }
  if (hasForbiddenRatehawkTestClientControl(requestBody)) {
    return _safeTestUnavailable("client_control_forbidden");
  }
  if (!isBookingRatehawkTestHotelpageEnabled(env)) {
    return _safeTestUnavailable("test_hotelpage_disabled");
  }
  const contextSecret = _text(env?.RATEHAWK_TEST_VIEW_STAY_CONTEXT_SECRET, 800);
  const opened = await openRatehawkViewStayContext(
    contextSecret,
    requestBody.view_stay_context ?? requestBody.selected_card_context,
    { now },
  );
  if (opened.ok !== true) {
    return _safeTestUnavailable(opened.reason);
  }
  const stayCheck = assertRatehawkTestStay(opened.claims, now);
  if (stayCheck.ok !== true) {
    return _safeTestUnavailable(stayCheck.reason);
  }
  const proxied = await _proxyHotelsTestPath(
    env,
    RATEHAWK_HOTELS_TEST_HOTELPAGE_PATH,
    {
      view_stay_context:
        requestBody.view_stay_context ?? requestBody.selected_card_context,
      locale: _text(requestBody.locale, 8) || "nl",
    },
  );
  return proxied.dto;
}

export function runTaxiBookingIsolationProbe(input = {}) {
  const distanceKm = Number(input.distance_km);
  const amountMinor = Number.isFinite(distanceKm)
    ? Math.round(distanceKm * 250)
    : 1250;
  return {
    ok: true,
    kind: "taxi_quote",
    amount_minor: amountMinor,
    currency: "EUR",
    invoked_ratehawk: false,
    invoked_ratehawk_test: false,
  };
}

export {
  issueRatehawkViewStayContext,
  openRatehawkViewStayContext,
  verifyRatehawkViewStayContext,
};
