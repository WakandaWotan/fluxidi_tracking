/**
 * Booking Worker RateHawk facade.
 *
 * Public app route stays POST /public/hotels/ratehawk/hotelpage.
 * This module must not resolve RateHawk credentials, construct provider
 * Authorization, call the provider host, decrypt offer references, or
 * normalize raw provider payloads.
 */

import { sha256Hex } from "./crypto_utils.js";
import {
  issueRatehawkViewStayContext,
  verifyRatehawkViewStayContext,
} from "../../ratehawk-hotels/modules/ratehawk_view_stay_context.mjs";

export const RATEHAWK_HOTELPAGE_PUBLIC_PATH =
  "/public/hotels/ratehawk/hotelpage";
export const RATEHAWK_HOTELS_BINDING = "RATEHAWK_HOTELS";
export const RATEHAWK_HOTELS_SERVICE_NAME = "fluxidi-ratehawk-hotels-api";
export const RATEHAWK_HOTELS_INTERNAL_PROXY = "booking_worker_v1";
export const RATEHAWK_SEARCH_SOURCES = Object.freeze([
  "ratehawk",
  "rate-hawk",
  "etg",
  "emerging-travel",
]);

const HOTELPAGE_RATE_MAX = 20;
const HOTELPAGE_RATE_WINDOW_SECONDS = 60;

function _text(value, max = 200) {
  const text = String(value ?? "").trim();
  if (!text) return "";
  return text.length > max ? text.slice(0, max) : text;
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
  };
}

export { issueRatehawkViewStayContext, verifyRatehawkViewStayContext };
