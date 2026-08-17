/**
 * Server-owned RateHawk test-activation allowlist.
 *
 * These checks are independent of RATEHAWK_ENABLED / RATEHAWK_HOTELPAGE_ENABLED.
 * Public customer routes must never import this module as an enablement path.
 */

import { envFlag } from "./parsing_utils.js";
import { resolveRatehawkConfig } from "./ratehawk_provider.mjs";
import {
  RATEHAWK_SERP_GEO_PATH,
  RATEHAWK_SERP_HOTELS_PATH,
  RATEHAWK_SERP_REGION_PATH,
  RATEHAWK_TEST_HOST,
  RATEHAWK_TEST_HOTEL_HID,
} from "./ratehawk_market_search_limits.mjs";
import { RATEHAWK_HOTELPAGE_PATH } from "./ratehawk_hotelpage_contract.mjs";

export const RATEHAWK_TEST_SEARCH_GATE = "RATEHAWK_TEST_SEARCH_ENABLED";
export const RATEHAWK_TEST_HOTELPAGE_GATE = "RATEHAWK_TEST_HOTELPAGE_ENABLED";
export const RATEHAWK_TEST_PREBOOK_GATE = "RATEHAWK_TEST_PREBOOK_ENABLED";
export const RATEHAWK_WORKER_SURFACE_PRODUCTION = "production";
export const RATEHAWK_WORKER_SURFACE_TEST = "test";
export const RATEHAWK_PRODUCTION_WORKER_NAME = "fluxidi-ratehawk-hotels-api";
export const RATEHAWK_TEST_WORKER_NAME = "fluxidi-ratehawk-hotels-api-test";
export const RATEHAWK_TEST_OPERATION_SERP = "test_serp_hotels";
export const RATEHAWK_TEST_OPERATION_HOTELPAGE = "test_hotelpage";
export const RATEHAWK_TEST_OPERATION_PREBOOK = "test_prebook";
export const RATEHAWK_TEST_TOKEN_SURFACE = "test";
export const RATEHAWK_TEST_PREBOOK_TRIGGER = "test_prebook_revalidation";
export const RATEHAWK_TEST_PREBOOK_ACCEPT_TRIGGER = "test_accept_prebook_terms";
export const RATEHAWK_TEST_HID = Number(RATEHAWK_TEST_HOTEL_HID);
export const RATEHAWK_TEST_RESIDENCY = "be";
export const RATEHAWK_TEST_CURRENCY = "EUR";
export const RATEHAWK_TEST_LANGUAGE = "en";
export const RATEHAWK_TEST_ADULTS = 2;
export const RATEHAWK_TEST_LEAD_DAYS = 14;
export const RATEHAWK_TEST_WEEKDAY = 4;
export const RATEHAWK_TEST_NIGHTS = 1;
export const RATEHAWK_TEST_TIMEOUT_MS = 30_000;

export const RATEHAWK_TEST_DENIED_PATHS = Object.freeze([
  RATEHAWK_SERP_REGION_PATH,
  RATEHAWK_SERP_GEO_PATH,
  "/api/b2b/v3/hotel/info/dump/",
  "/api/b2b/v3/hotel/info/incremental_dump/",
  "/api/content/v1/hotel_content_by_ids/",
  "/api/b2b/v3/hotel/prebook/",
  "/api/b2b/v3/hotel/order/booking/form/",
  "/api/b2b/v3/hotel/order/booking/finish/",
  "/api/b2b/v3/hotel/order/cancel/",
  "/api/b2b/v3/hotel/order/document/voucher/",
]);

export const RATEHAWK_TEST_FORBIDDEN_CLIENT_KEYS = Object.freeze([
  "host",
  "base_url",
  "baseUrl",
  "api_key",
  "apiKey",
  "authorization",
  "endpoint",
  "url",
  "path",
  "hid",
  "hids",
  "ids",
  "checkin",
  "checkout",
  "guests",
  "residency",
  "currency",
  "region_id",
  "longitude",
  "latitude",
  "book_hash",
  "match_hash",
  "hash",
  "price",
  "price_override",
  "show_amount",
  "payment_type",
  "cancellation",
  "RATEHAWK_API_KEY",
  "RATEHAWK_KEY_ID",
]);

export const RATEHAWK_TEST_HOTEL_IDENTITY = Object.freeze({
  hid: RATEHAWK_TEST_HID,
  name: "Warwick Brussels",
  type: "hotel",
  address: "Rue Duquesnoy 5, 1000 Brussels, Belgium",
  city: "Brussel",
  region: "Brussels Hoofdstedelijk Gewest",
  country: "Belgium",
  lat: 50.845,
  lng: 4.3543,
  image_url: null,
  image_ref: null,
  star_rating: 4,
  content_source: "test_allowlist",
});

export const RATEHAWK_TEST_STAY22_FALLBACK_URL =
  "https://www.stay22.com/embed/gm?aid=fluxidi";

function _ymd(date) {
  return date.toISOString().slice(0, 10);
}

export function resolveRatehawkTestStayDates(now = Date.now()) {
  const start = new Date(Number(now));
  start.setUTCHours(0, 0, 0, 0);
  start.setUTCDate(start.getUTCDate() + RATEHAWK_TEST_LEAD_DAYS);
  const add = (RATEHAWK_TEST_WEEKDAY - start.getUTCDay() + 7) % 7;
  start.setUTCDate(start.getUTCDate() + add);
  const checkin = _ymd(start);
  start.setUTCDate(start.getUTCDate() + RATEHAWK_TEST_NIGHTS);
  return { checkin, checkout: _ymd(start) };
}

export function resolveRatehawkTestStay(now = Date.now()) {
  const dates = resolveRatehawkTestStayDates(now);
  return {
    source: "ratehawk",
    hid: RATEHAWK_TEST_HID,
    checkin: dates.checkin,
    checkout: dates.checkout,
    residency: RATEHAWK_TEST_RESIDENCY,
    currency: RATEHAWK_TEST_CURRENCY,
    language: RATEHAWK_TEST_LANGUAGE,
    guests: [{ adults: RATEHAWK_TEST_ADULTS, children: [] }],
  };
}

export function resolveRatehawkWorkerSurface(env) {
  const value = String(env?.RATEHAWK_WORKER_SURFACE || "").trim().toLowerCase();
  return value === RATEHAWK_WORKER_SURFACE_TEST
    ? RATEHAWK_WORKER_SURFACE_TEST
    : RATEHAWK_WORKER_SURFACE_PRODUCTION;
}

export function isRatehawkIsolatedTestWorker(env) {
  return resolveRatehawkWorkerSurface(env) === RATEHAWK_WORKER_SURFACE_TEST;
}

export function resolveRatehawkWorkerName(env) {
  return isRatehawkIsolatedTestWorker(env)
    ? RATEHAWK_TEST_WORKER_NAME
    : RATEHAWK_PRODUCTION_WORKER_NAME;
}

export function isRatehawkTestSearchEnabled(env) {
  return envFlag(env?.[RATEHAWK_TEST_SEARCH_GATE]);
}

export function isRatehawkTestHotelpageEnabled(env) {
  return envFlag(env?.[RATEHAWK_TEST_HOTELPAGE_GATE]);
}

export function isRatehawkTestPrebookEnabled(env) {
  return envFlag(env?.[RATEHAWK_TEST_PREBOOK_GATE]);
}

export function isRatehawkTestPathDenied(path) {
  const value = String(path || "").trim();
  return RATEHAWK_TEST_DENIED_PATHS.includes(value);
}

export function hasForbiddenRatehawkTestClientControl(body) {
  if (!body || typeof body !== "object" || Array.isArray(body)) return false;
  if (body.stay && typeof body.stay === "object") return true;
  if (body.selected_stay && typeof body.selected_stay === "object") return true;
  return RATEHAWK_TEST_FORBIDDEN_CLIENT_KEYS.some((key) =>
    Object.prototype.hasOwnProperty.call(body, key),
  );
}

export function assertRatehawkTestProviderPath(path, expected) {
  const value = String(path || "").trim();
  if (isRatehawkTestPathDenied(value)) {
    return { ok: false, reason: "test_path_denied" };
  }
  if (value !== expected) {
    return { ok: false, reason: "test_path_not_allowlisted" };
  }
  return { ok: true, reason: null, path: value };
}

export function assertRatehawkTestHid(hid) {
  const numeric = Number(hid);
  if (!Number.isInteger(numeric) || numeric !== RATEHAWK_TEST_HID) {
    return { ok: false, reason: "test_hid_not_allowlisted" };
  }
  return { ok: true, hid: numeric };
}

export function assertRatehawkTestHids(hids) {
  if (!Array.isArray(hids) || hids.length !== 1) {
    return { ok: false, reason: "test_multiple_hids_forbidden" };
  }
  return assertRatehawkTestHid(hids[0]);
}

export function assertRatehawkTestGuests(guests) {
  if (!Array.isArray(guests) || guests.length !== 1) {
    return { ok: false, reason: "test_guests_not_allowlisted" };
  }
  const room = guests[0] || {};
  const adults = Number(room.adults);
  const children = Array.isArray(room.children) ? room.children : null;
  if (!Number.isInteger(adults) || adults < 1 || adults > 2) {
    return { ok: false, reason: "test_guests_not_allowlisted" };
  }
  if (!children || children.length !== 0) {
    return { ok: false, reason: "test_children_forbidden" };
  }
  return { ok: true, guests: [{ adults, children: [] }] };
}

export function assertRatehawkTestStay(stay = {}, now = Date.now()) {
  const expected = resolveRatehawkTestStay(now);
  const hid = assertRatehawkTestHid(stay.hid);
  if (hid.ok !== true) return hid;
  const guests = assertRatehawkTestGuests(stay.guests);
  if (guests.ok !== true) return guests;
  if (stay.checkin !== expected.checkin || stay.checkout !== expected.checkout) {
    return { ok: false, reason: "test_dates_not_server_owned" };
  }
  if (String(stay.residency || "").toLowerCase() !== RATEHAWK_TEST_RESIDENCY) {
    return { ok: false, reason: "test_residency_not_allowlisted" };
  }
  if (String(stay.currency || "").toUpperCase() !== RATEHAWK_TEST_CURRENCY) {
    return { ok: false, reason: "test_currency_not_allowlisted" };
  }
  if (
    stay.language != null &&
    String(stay.language || "").toLowerCase() !== RATEHAWK_TEST_LANGUAGE
  ) {
    return { ok: false, reason: "test_language_not_allowlisted" };
  }
  return { ok: true, stay: expected };
}

export function assertRatehawkTestProviderConfig(env) {
  if (envFlag(env?.RATEHAWK_PRODUCTION_ENABLED)) {
    return { ok: false, reason: "production_gate_must_stay_closed" };
  }
  const config = resolveRatehawkConfig(env);
  if (config.environment !== "test") {
    return { ok: false, reason: "test_environment_required", config };
  }
  if (config.host !== "api.ratehawk.com" || config.base_url !== RATEHAWK_TEST_HOST) {
    return { ok: false, reason: "test_host_required", config };
  }
  if (config.has_key_id !== true || config.has_api_key !== true) {
    return { ok: false, reason: "missing_configuration", config };
  }
  return { ok: true, reason: null, config };
}

export function evaluateRatehawkTestSearchGate(env) {
  if (!isRatehawkTestSearchEnabled(env)) {
    return { ok: false, allowed: false, reason: "test_search_disabled" };
  }
  if (!isRatehawkIsolatedTestWorker(env)) {
    return { ok: false, allowed: false, reason: "test_worker_required" };
  }
  return { ok: true, allowed: true, reason: null };
}

export function evaluateRatehawkTestHotelpageGate(env) {
  if (!isRatehawkTestHotelpageEnabled(env)) {
    return { ok: false, allowed: false, reason: "test_hotelpage_disabled" };
  }
  if (!isRatehawkIsolatedTestWorker(env)) {
    return { ok: false, allowed: false, reason: "test_worker_required" };
  }
  return { ok: true, allowed: true, reason: null };
}

export function evaluateRatehawkTestPrebookGate(env) {
  if (!isRatehawkTestPrebookEnabled(env)) {
    return { ok: false, allowed: false, reason: "test_prebook_disabled" };
  }
  if (!isRatehawkIsolatedTestWorker(env)) {
    return { ok: false, allowed: false, reason: "test_worker_required" };
  }
  return { ok: true, allowed: true, reason: null };
}

export function assertRatehawkTestOfferClaims(claims = {}, now = Date.now()) {
  if (!claims || typeof claims !== "object") {
    return { ok: false, reason: "offer_ref_invalid" };
  }
  if (claims.surface !== RATEHAWK_TEST_TOKEN_SURFACE) {
    return { ok: false, reason: "production_offer_ref_forbidden" };
  }
  if (claims.purpose && claims.purpose !== "hotelpage_offer") {
    return { ok: false, reason: "offer_ref_purpose_mismatch" };
  }
  if (!claims.book_hash || !claims.display_snapshot) {
    return { ok: false, reason: "offer_ref_incomplete" };
  }
  return assertRatehawkTestStay(
    {
      hid: claims.hid,
      checkin: claims.checkin,
      checkout: claims.checkout,
      residency: claims.residency,
      currency: claims.currency,
      guests: claims.guests,
      language: claims.language || RATEHAWK_TEST_LANGUAGE,
    },
    now,
  );
}

export function buildRatehawkTestSerpRequest(now = Date.now()) {
  const stay = resolveRatehawkTestStay(now);
  return {
    ok: true,
    operation: RATEHAWK_TEST_OPERATION_SERP,
    method: "POST",
    path: RATEHAWK_SERP_HOTELS_PATH,
    host: RATEHAWK_TEST_HOST,
    body: {
      checkin: stay.checkin,
      checkout: stay.checkout,
      residency: stay.residency,
      language: stay.language,
      guests: stay.guests,
      hids: [RATEHAWK_TEST_HID],
      timeout: Math.round(RATEHAWK_TEST_TIMEOUT_MS / 1000),
    },
    stay,
  };
}

export function buildRatehawkTestHotelpageRequest(stay, now = Date.now()) {
  const checked = assertRatehawkTestStay(stay, now);
  if (checked.ok !== true) return checked;
  return {
    ok: true,
    operation: RATEHAWK_TEST_OPERATION_HOTELPAGE,
    method: "POST",
    path: RATEHAWK_HOTELPAGE_PATH,
    host: RATEHAWK_TEST_HOST,
    body: {
      hid: checked.stay.hid,
      checkin: checked.stay.checkin,
      checkout: checked.stay.checkout,
      residency: checked.stay.residency,
      language: checked.stay.language,
      currency: checked.stay.currency,
      guests: checked.stay.guests,
      timeout: Math.round(RATEHAWK_TEST_TIMEOUT_MS / 1000),
    },
    stay: checked.stay,
  };
}
