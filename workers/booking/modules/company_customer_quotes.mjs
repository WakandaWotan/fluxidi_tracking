// COMPANY-CUSTOMER-OPS-P0 — company-issued quotes for CRM customers.
//
// Reuses customer scope, document branding fields, and a booking handoff
// record. This is not a second limousine marketplace. Opening a public link
// never accepts; accept requires POST confirm=true. CUSTOMER_QUOTE_MAIL_SINK
// is test sending only. CUSTOMER_QUOTE_MAIL_SEND is adapter-accepted, not
// proven delivery. Without either, send fails closed. This module never
// calls Resend.

import { safeStr, sanitizeTenantString } from "./parsing_utils.js";
import { sha256Hex } from "./crypto_utils.js";
import { html, json } from "./http_response.js";
import { renderPdfFromHtml } from "./pdf_render.mjs";
import { putBookingCreateIfAbsent } from "./human_booking_id_allocator.mjs";
import { upsertCompanyBookingsListIndexBestEffort } from "./booking_indexes.js";
import {
  companyCustomerRecordKey,
  isUsableCustomerEmail,
  maskCustomerEmail,
  normalizeCustomerEmail,
  normalizeCustomerPhone,
  normalizeCustomerScope,
} from "./company_customers.mjs";
import {
  applyCompanyRoundtripFields,
  formatQuoteRoundtripHtml,
  parseCompanyRoundtripWrite,
  quoteRoundtripPublicFields,
  quoteWriteRoundtripValue,
} from "./company_roundtrip.mjs";
import {
  companyFixedPriceTotalsDiffer,
  resolveCompanyFixedPrice,
  stampCompanyFixedPriceSnapshot,
} from "./company_fixed_prices.mjs";

export const CUSTOMER_QUOTE_STATES = Object.freeze({
  DRAFT: "draft",
  SENT: "sent",
  VIEWED: "viewed",
  ACCEPTED: "accepted",
  EXPIRED: "expired",
  WITHDRAWN: "withdrawn",
});

export const CUSTOMER_QUOTE_DELIVERY = Object.freeze({
  TEST_ADAPTER: "test_adapter",
  ADAPTER_ACCEPTED: "adapter_accepted",
  NOT_CONFIGURED: "mail_not_configured",
  FAILED: "send_failed",
});

const VAT_TREATMENTS = new Set(["incl", "excl", "none", "zero"]);
const RIDE_SERVICES = new Set(["airport", "passenger", "business", "courier", "care", "event"]);
const RIDE_TIERS = new Set(["comfort", "private", "premium"]);
const RIDE_EXTRAS = new Set(["none", "drinks", "worktable"]);
const RIDE_DIRECTIONS = new Set(["from_airport", "to_airport"]);
const QUOTE_LIST_MAX = 40;

const RIDE_OPTION_LABELS_NL = Object.freeze({
  airport: "Luchthaven",
  passenger: "Personenvervoer",
  business: "Zakelijk",
  courier: "Spoedkoerier",
  care: "Zorgvervoer",
  event: "Evenement",
  comfort: "Comfort",
  private: "Private",
  premium: "Premium",
  drinks: "Drankservice (water/fris — alcohol op aanvraag)",
  worktable: "Werktafel (laptop)",
  from_airport: "Vanaf de luchthaven",
  to_airport: "Naar de luchthaven",
});

const VAT_TREATMENT_LABELS_NL = Object.freeze({
  incl: "Inclusief btw",
  excl: "Exclusief btw",
  none: "Geen btw",
  zero: "0% btw",
});

export function quoteAddressIsComplete(text) {
  const value = clip(text, 200);
  if (!value) return false;
  if (value.length < 3) return false;
  if (/^[1-9]\d{3}$/.test(value)) return false;
  if (!/[A-Za-zÀ-ÿ]/.test(value)) return false;
  if (!/[\s,]/.test(value) && value.length < 12) return false;
  if (value.length < 8) return false;
  if (!/[\s,]/.test(value)) return false;
  return true;
}

function rideOptionLabelNl(id) {
  const key = clip(id, 32).toLowerCase();
  if (!key) return "";
  return RIDE_OPTION_LABELS_NL[key] || "";
}

export function formatQuoteRideOptionsNl(options) {
  const src = options && typeof options === "object" ? options : {};
  const bags = Number(src.bags);
  const wait = Number(src.wait_min ?? src.waitMin);
  const parts = [
    rideOptionLabelNl(src.service),
    rideOptionLabelNl(src.tier),
    Number.isInteger(bags) && bags > 0 ? `${bags} bagage` : "",
    Number.isInteger(wait) && wait > 0 ? `${wait} min` : "",
    rideOptionLabelNl(src.airport_direction || src.airportDirection),
    clip(src.flight_number || src.flightNumber, 16).toUpperCase(),
    rideOptionLabelNl(src.extra),
    src.meet_and_greet === true || src.meetAndGreet === true ? "Meet-and-greet" : "",
    clip(src.name_board || src.nameBoard, 80),
  ].filter(Boolean);
  return parts.join(" · ");
}

export function computeQuoteVatBreakdown(record) {
  const cents = Number(record?.entered_amount_cents);
  const treatment = clip(record?.vat_treatment, 12).toLowerCase();
  const rateRaw = record?.vat_rate;
  const rate = Number(rateRaw);
  const hasRate = Number.isFinite(rate) && rate > 0 && rate <= 100;
  if (!Number.isInteger(cents) || cents < 0) {
    return {
      treatment,
      entered_cents: null,
      vat_rate: null,
      rate_missing: false,
      excl_cents: null,
      vat_cents: null,
      incl_cents: null,
    };
  }
  if (treatment === "none" || treatment === "zero") {
    return {
      treatment,
      entered_cents: cents,
      vat_rate: treatment === "zero" ? 0 : null,
      rate_missing: false,
      excl_cents: cents,
      vat_cents: 0,
      incl_cents: cents,
    };
  }
  if (!hasRate) {
    return {
      treatment: treatment || "incl",
      entered_cents: cents,
      vat_rate: null,
      rate_missing: true,
      excl_cents: null,
      vat_cents: null,
      incl_cents: null,
    };
  }
  if (treatment === "excl") {
    const vatCents = Math.round((cents * rate) / 100);
    return {
      treatment,
      entered_cents: cents,
      vat_rate: rate,
      rate_missing: false,
      excl_cents: cents,
      vat_cents: vatCents,
      incl_cents: cents + vatCents,
    };
  }
  const exclCents = Math.round((cents * 100) / (100 + rate));
  return {
    treatment: treatment || "incl",
    entered_cents: cents,
    vat_rate: rate,
    rate_missing: false,
    excl_cents: exclCents,
    vat_cents: cents - exclCents,
    incl_cents: cents,
  };
}

function eurosFromCents(cents) {
  if (!Number.isInteger(cents) || cents < 0) return null;
  return Math.round(cents) / 100;
}

function nowIso(env) {
  const forced = Number(env?.CUSTOMER_NOW_MS);
  const date = Number.isFinite(forced) && forced > 0 ? new Date(forced) : new Date();
  return date.toISOString();
}

function clip(value, max) {
  return sanitizeTenantString(value, max);
}

function newId(prefix) {
  const bytes = new Uint8Array(16);
  crypto.getRandomValues(bytes);
  let hex = "";
  for (const byte of bytes) hex += byte.toString(16).padStart(2, "0");
  return `${prefix}${hex}`;
}

export function companyCustomerQuoteKey(scope, quoteId) {
  const s = normalizeCustomerScope(scope);
  const id = safeStr(quoteId);
  if (!s.hasScope || !id) return "";
  return `tenant:${s.tenant_id}:company:${s.company_id}:customer-quote:v1:${id}`;
}

export function companyCustomerQuoteIdempotencyKey(scope, hashed) {
  const s = normalizeCustomerScope(scope);
  const raw = safeStr(hashed);
  if (!s.hasScope || !raw) return "";
  return `tenant:${s.tenant_id}:company:${s.company_id}:customer-quotes:idem:v1:${raw}`;
}

function readQuoteIdempotencyKey(request, body) {
  const header = safeStr(
    request?.headers?.get?.("Idempotency-Key") ||
      request?.headers?.get?.("idempotency-key"),
  );
  if (header) return clip(header, 200);
  return clip(body?.idempotency_key || body?.idempotencyKey, 200);
}

export function companyCustomerQuoteListKey(scope, customerId) {
  const s = normalizeCustomerScope(scope);
  const id = safeStr(customerId);
  if (!s.hasScope || !id) return "";
  return `tenant:${s.tenant_id}:company:${s.company_id}:customer:${id}:quotes:v1`;
}

export function companyCustomerQuoteTokenKey(tokenHash) {
  const hash = safeStr(tokenHash);
  if (!hash) return "";
  return `customer-quote-public:v1:${hash}`;
}

export function companyCustomerQuoteMailCaptureKey(scope, quoteId) {
  const s = normalizeCustomerScope(scope);
  const id = safeStr(quoteId);
  if (!s.hasScope || !id) return "";
  return `tenant:${s.tenant_id}:company:${s.company_id}:customer-quote-mail:v1:${id}`;
}

export function companyCustomerQuoteBookingKey(bookingId) {
  const id = safeStr(bookingId);
  return id ? `booking:${id}` : "";
}

function isValidQuoteId(value) {
  return /^cqq_[a-f0-9]{32}$/.test(safeStr(value));
}

function asInt(value) {
  const n = Number(value);
  if (!Number.isInteger(n)) return null;
  return n;
}

function normalizeRideOptions(raw) {
  const src = raw && typeof raw === "object" ? raw : {};
  const bags = asInt(src.bags);
  const wait = asInt(src.wait_min ?? src.waitMin);
  const service = clip(src.service || src.service_id, 32).toLowerCase();
  const tier = clip(src.tier || src.vehicle_tier || src.tier_id, 32).toLowerCase();
  const extra = clip(src.extra || src.extra_option, 32).toLowerCase();
  const direction = clip(src.airport_direction || src.airportDirection, 32).toLowerCase();
  return {
    service: RIDE_SERVICES.has(service) ? service : "",
    tier: RIDE_TIERS.has(tier) ? tier : "",
    bags: bags != null && bags >= 0 && bags <= 8 ? bags : 0,
    wait_min: wait != null && wait >= 0 && wait <= 240 ? wait : 0,
    flight_number: clip(src.flight_number || src.flightNumber, 16).toUpperCase(),
    airport_direction: RIDE_DIRECTIONS.has(direction) ? direction : "",
    extra: RIDE_EXTRAS.has(extra) && extra !== "none" ? extra : "",
    meet_and_greet: src.meet_and_greet === true || src.meetAndGreet === true,
    name_board: clip(src.name_board || src.nameBoard, 80),
    airport_iata: clip(src.airport_iata || src.airportIata, 8).toUpperCase(),
    airport_country: clip(src.airport_country || src.airportCountry, 8).toUpperCase(),
    flight_at: clip(src.flight_at || src.flightAt, 40),
    pickup_arrangement: clip(
      src.pickup_arrangement || src.pickupArrangement,
      32,
    ).toLowerCase(),
    pickup_after_min: asInt(src.pickup_after_min ?? src.pickupAfterMin) || 0,
    flight_timezone: clip(src.flight_timezone || src.flightTimezone, 64) || "Europe/Brussels",
    return_airport_iata: clip(
      src.return_airport_iata || src.returnAirportIata,
      8,
    ).toUpperCase(),
    return_flight_number: clip(
      src.return_flight_number || src.returnFlightNumber,
      16,
    ).toUpperCase(),
    return_flight_at: clip(src.return_flight_at || src.returnFlightAt, 40),
    return_pickup_arrangement: clip(
      src.return_pickup_arrangement || src.returnPickupArrangement,
      32,
    ).toLowerCase(),
  };
}

function stampRideFields(target, options, note) {
  if (!target || !options) return target;
  if (options.service) target.service = options.service;
  if (options.tier) target.tier = options.tier;
  if (options.bags != null) target.bags = options.bags;
  if (options.wait_min != null) target.wait_min = options.wait_min;
  if (options.flight_number) target.flight_number = options.flight_number;
  if (options.airport_direction) target.airport_direction = options.airport_direction;
  if (options.extra) target.extra = options.extra;
  if (options.meet_and_greet) target.meet_and_greet = true;
  if (options.name_board) target.name_board = options.name_board;
  if (options.airport_iata) target.airport_iata = options.airport_iata;
  if (options.flight_at) target.flight_at = options.flight_at;
  if (options.pickup_arrangement) target.pickup_arrangement = options.pickup_arrangement;
  if (note) target.note = clip(note, 500);
  target.ride_options = options;
  return target;
}

function snapshotFromBody(body) {
  const raw = body?.fixed_price_snapshot || body?.fixedPriceSnapshot;
  if (!raw || typeof raw !== "object") return null;
  const ruleId = safeStr(raw.fixed_fare_rule_id || raw.fixedFareRuleId, 96);
  if (!ruleId) return null;
  return raw;
}

function parseAmountCents(value) {
  if (value == null || value === "") return null;
  const n = Number(value);
  if (!Number.isInteger(n) || n < 0 || n > 99_999_999) return null;
  return n;
}

function optionalCoord(value) {
  if (value == null || value === "") return null;
  const n = Number(value);
  return Number.isFinite(n) ? n : null;
}

function validateQuoteWrite(body, { partial = false } = {}) {
  const fields = {};
  const pickup = clip(body?.pickup, 200);
  const dropoff = clip(body?.dropoff, 200);
  const startAt = clip(body?.start_at, 40);
  const description = clip(body?.description, 500);
  const passengerName = clip(body?.passenger_name, 120);
  const passengerEmail = normalizeCustomerEmail(body?.passenger_email);
  const phone = normalizeCustomerPhone(body?.passenger_phone, body?.country_calling_code);
  const passengers = asInt(body?.passengers);
  const amount = parseAmountCents(body?.entered_amount_cents);
  const currency = clip(body?.currency || "EUR", 3).toUpperCase();
  const vatTreatment = clip(body?.vat_treatment, 12).toLowerCase();
  const vatRateRaw = body?.vat_rate;
  const validUntil = clip(body?.valid_until, 40);
  const issuerName = clip(body?.issuer_name, 160);
  if (!partial || body?.pickup != null) {
    if (!pickup) fields.pickup = "required";
  }
  if (!partial || body?.dropoff != null) {
    if (!dropoff) fields.dropoff = "required";
  }
  if (!partial || body?.start_at != null) {
    if (!startAt || !Number.isFinite(Date.parse(startAt))) fields.start_at = "invalid";
  }
  if (!partial || body?.passengers != null) {
    if (passengers == null || passengers < 1 || passengers > 20) fields.passengers = "invalid";
  }
  if (body?.passenger_email != null && body.passenger_email !== "" && !isUsableCustomerEmail(passengerEmail)) {
    fields.passenger_email = "invalid";
  }
  if (body?.entered_amount_cents != null && amount == null) {
    fields.entered_amount_cents = "invalid";
  }
  if (body?.currency != null && !/^[A-Z]{3}$/.test(currency)) {
    fields.currency = "invalid";
  }
  if (vatTreatment && !VAT_TREATMENTS.has(vatTreatment)) {
    fields.vat_treatment = "invalid";
  }
  if (vatRateRaw != null && vatRateRaw !== "") {
    const rate = Number(vatRateRaw);
    if (!Number.isFinite(rate) || rate < 0 || rate > 100) fields.vat_rate = "invalid";
  }
  if (validUntil && !Number.isFinite(Date.parse(validUntil))) {
    fields.valid_until = "invalid";
  }
  if (Object.keys(fields).length) return { ok: false, fields };
  const roundtrip = quoteWriteRoundtripValue({
    ...body,
    pickup,
    dropoff,
    start_at: startAt,
  });
  if (!roundtrip.ok) {
    return { ok: false, fields: { ...fields, ...roundtrip.fields } };
  }
  return {
    ok: true,
    value: {
      pickup,
      dropoff,
      start_at: startAt,
      description,
      passenger_name: passengerName,
      passenger_email: passengerEmail,
      passenger_phone: phone.raw,
      country_calling_code: phone.country_calling_code,
      passengers: passengers || 1,
      entered_amount_cents: amount,
      currency: currency || "EUR",
      vat_treatment: VAT_TREATMENTS.has(vatTreatment) ? vatTreatment : "",
      vat_rate: vatRateRaw == null || vatRateRaw === "" ? null : Number(vatRateRaw),
      valid_until: validUntil,
      issuer_name: issuerName,
      pickup_lat: optionalCoord(body?.pickup_lat ?? body?.pickupLat),
      pickup_lon: optionalCoord(body?.pickup_lon ?? body?.pickupLon),
      pickup_place_id: clip(body?.pickup_place_id ?? body?.pickupPlaceId, 80),
      dropoff_lat: optionalCoord(body?.dropoff_lat ?? body?.dropoffLat),
      dropoff_lon: optionalCoord(body?.dropoff_lon ?? body?.dropoffLon),
      dropoff_place_id: clip(body?.dropoff_place_id ?? body?.dropoffPlaceId, 80),
      ride_options: normalizeRideOptions(body?.ride_options ?? body?.rideOptions),
      ...roundtrip.value,
    },
  };
}

function publicQuote(record, { includeToken = false } = {}) {
  const out = {
    quote_id: record.quote_id,
    customer_id: record.customer_id,
    state: record.state,
    revision: Number(record.revision || 1),
    issuer_name: record.issuer_name || "",
    pickup: record.pickup || "",
    dropoff: record.dropoff || "",
    start_at: record.start_at || "",
    passengers: Number(record.passengers || 1),
    description: record.description || "",
    passenger_name: record.passenger_name || "",
    passenger_email: record.passenger_email || "",
    passenger_phone: record.passenger_phone || "",
    entered_amount_cents: record.entered_amount_cents,
    currency: record.currency || "EUR",
    vat_treatment: record.vat_treatment || "",
    vat_rate: record.vat_rate,
    valid_until: record.valid_until || "",
    pickup_lat: optionalCoord(record.pickup_lat),
    pickup_lon: optionalCoord(record.pickup_lon),
    pickup_place_id: record.pickup_place_id || "",
    dropoff_lat: optionalCoord(record.dropoff_lat),
    dropoff_lon: optionalCoord(record.dropoff_lon),
    dropoff_place_id: record.dropoff_place_id || "",
    created_at: record.created_at,
    updated_at: record.updated_at,
    sent_at: record.sent_at || null,
    accepted_at: record.accepted_at || null,
    booking_id: record.booking_id || null,
    booking_list_ready: record.state === CUSTOMER_QUOTE_STATES.ACCEPTED && record.booking_list_ready === true,
    booking_dispatch_blocked: true,
    delivery: record.delivery || "",
    delivery_proven: false,
    test_send: record.delivery === CUSTOMER_QUOTE_DELIVERY.TEST_ADAPTER || record.test_send === true,
    ride_options: record.ride_options || normalizeRideOptions(record),
    pricing_source: record.pricing_source || "",
    fixed_fare_rule_id: record.fixed_fare_rule_id || "",
    fixed_price_snapshot: record.fixed_price_snapshot || null,
    ...quoteRoundtripPublicFields(record),
  };
  if (includeToken && record.public_token) out.public_token = record.public_token;
  return out;
}

function publicCustomerQuoteView(record, brand) {
  return {
    quote_id: record.quote_id,
    state: record.state,
    revision: Number(record.revision || 1),
    issuer_name: record.issuer_name || brand?.company_name || "",
    pickup: record.pickup || "",
    dropoff: record.dropoff || "",
    start_at: record.start_at || "",
    passengers: Number(record.passengers || 1),
    description: record.description || "",
    passenger_name: record.passenger_name || "",
    entered_amount_cents: record.entered_amount_cents,
    currency: record.currency || "EUR",
    vat_treatment: record.vat_treatment || "",
    vat_rate: record.vat_rate,
    valid_until: record.valid_until || "",
    accepted: record.state === CUSTOMER_QUOTE_STATES.ACCEPTED,
    ride_options: record.ride_options || normalizeRideOptions(record),
    ...quoteRoundtripPublicFields(record),
  };
}

async function kvGetJson(kv, key) {
  if (!key || !kv?.get) return null;
  return kv.get(key, "json");
}

async function kvPutJson(kv, key, value) {
  if (!key) return;
  await kv.put(key, JSON.stringify(value));
}

async function loadQuote(kv, scope, quoteId) {
  return kvGetJson(kv, companyCustomerQuoteKey(scope, quoteId));
}

async function saveQuote(kv, scope, record) {
  await kvPutJson(kv, companyCustomerQuoteKey(scope, record.quote_id), record);
}

async function listQuoteIds(kv, scope, customerId) {
  const rec = await kvGetJson(kv, companyCustomerQuoteListKey(scope, customerId));
  return Array.isArray(rec?.quote_ids) ? rec.quote_ids.map((id) => safeStr(id)).filter(Boolean) : [];
}

async function appendQuoteId(kv, scope, customerId, quoteId) {
  const ids = await listQuoteIds(kv, scope, customerId);
  if (!ids.includes(quoteId)) ids.unshift(quoteId);
  await kvPutJson(kv, companyCustomerQuoteListKey(scope, customerId), {
    quote_ids: ids.slice(0, QUOTE_LIST_MAX),
  });
}

function issuerName(env, body) {
  return clip(body?.issuer_name, 160) || clip(env?.COMPANY_QUOTE_BRAND?.company_name, 160);
}

function isExpired(record, now) {
  if (!record?.valid_until) return false;
  const until = Date.parse(record.valid_until);
  const nowMs = Date.parse(now);
  return Number.isFinite(until) && Number.isFinite(nowMs) && nowMs >= until;
}

function markExpiredIfNeeded(record, now) {
  if (
    record &&
    isExpired(record, now) &&
    record.state !== CUSTOMER_QUOTE_STATES.ACCEPTED &&
    record.state !== CUSTOMER_QUOTE_STATES.WITHDRAWN
  ) {
    record.state = CUSTOMER_QUOTE_STATES.EXPIRED;
  }
  return record;
}

export async function createCompanyCustomerQuote(env, { scope, customerId, body, request }) {
  const s = normalizeCustomerScope(scope);
  if (!s.hasScope) return { ok: false, status: 400, error: "missing_tenant_scope" };
  const id = safeStr(customerId);
  if (!id) return { ok: false, status: 404, error: "not_found" };
  const customer = await kvGetJson(env.BOOKING_KV, companyCustomerRecordKey(s, id));
  if (!customer?.customer_id) return { ok: false, status: 404, error: "not_found" };
  const rawIdem = readQuoteIdempotencyKey(request, body);
  let hashed = "";
  if (rawIdem) {
    hashed = await sha256Hex(`${s.tenant_id}|${s.company_id}|quote_create|${rawIdem}`);
    const existing = await kvGetJson(
      env.BOOKING_KV,
      companyCustomerQuoteIdempotencyKey(s, hashed),
    );
    if (existing?.quote_id) {
      const record = markExpiredIfNeeded(
        await loadQuote(env.BOOKING_KV, s, existing.quote_id),
        nowIso(env),
      );
      if (record?.quote_id && record.customer_id === customer.customer_id) {
        return { ok: true, status: 200, body: { ok: true, quote: publicQuote(record) } };
      }
    }
  }
  const validated = validateQuoteWrite({
    ...body,
    passenger_name: body?.passenger_name || customer.display_name,
    passenger_email: body?.passenger_email ?? customer.email,
    passenger_phone: body?.passenger_phone ?? customer.phone,
    country_calling_code: body?.country_calling_code ?? customer.country_calling_code,
    pickup: body?.pickup,
    dropoff: body?.dropoff,
    start_at: body?.start_at,
    pickup_lat: body?.pickup_lat ?? body?.pickupLat,
    pickup_lon: body?.pickup_lon ?? body?.pickupLon,
    pickup_place_id: body?.pickup_place_id ?? body?.pickupPlaceId,
    dropoff_lat: body?.dropoff_lat ?? body?.dropoffLat,
    dropoff_lon: body?.dropoff_lon ?? body?.dropoffLon,
    dropoff_place_id: body?.dropoff_place_id ?? body?.dropoffPlaceId,
    passengers: body?.passengers ?? 1,
    description: body?.description,
    entered_amount_cents: body?.entered_amount_cents,
    currency: body?.currency,
    vat_treatment: body?.vat_treatment,
    vat_rate: body?.vat_rate,
    valid_until: body?.valid_until,
    issuer_name: issuerName(env, body),
    ride_options: body?.ride_options ?? body?.rideOptions,
  });
  if (!validated.ok) {
    return { ok: false, status: 400, error: "invalid_quote", fields: validated.fields };
  }
  const now = nowIso(env);
  const record = {
    quote_id: newId("cqq_"),
    tenant_id: s.tenant_id,
    company_id: s.company_id,
    customer_id: customer.customer_id,
    state: CUSTOMER_QUOTE_STATES.DRAFT,
    revision: 1,
    ...validated.value,
    issuer_name: validated.value.issuer_name || s.company_id,
    created_at: now,
    updated_at: now,
    sent_at: null,
    accepted_at: null,
    booking_id: null,
    public_token: null,
    public_token_hash: null,
  };
  const createdSnapshot = snapshotFromBody(body);
  if (createdSnapshot) {
    record.pricing_source = createdSnapshot.pricing_source || "company_fixed_price";
    record.fixed_fare_rule_id = createdSnapshot.fixed_fare_rule_id;
    record.fixed_price_snapshot = createdSnapshot;
  }
  await saveQuote(env.BOOKING_KV, s, record);
  await appendQuoteId(env.BOOKING_KV, s, customer.customer_id, record.quote_id);
  if (hashed) {
    await kvPutJson(env.BOOKING_KV, companyCustomerQuoteIdempotencyKey(s, hashed), {
      quote_id: record.quote_id,
    });
  }
  return { ok: true, status: 201, body: { ok: true, quote: publicQuote(record) } };
}

export async function listCompanyCustomerQuotes(env, { scope, customerId }) {
  const s = normalizeCustomerScope(scope);
  if (!s.hasScope) return { ok: false, status: 400, error: "missing_tenant_scope" };
  const id = safeStr(customerId);
  if (!id) return { ok: false, status: 404, error: "not_found" };
  const customer = await kvGetJson(env.BOOKING_KV, companyCustomerRecordKey(s, id));
  if (!customer?.customer_id) return { ok: false, status: 404, error: "not_found" };
  const ids = await listQuoteIds(env.BOOKING_KV, s, id);
  const now = nowIso(env);
  const items = [];
  for (const quoteId of ids.slice(0, QUOTE_LIST_MAX)) {
    const record = markExpiredIfNeeded(await loadQuote(env.BOOKING_KV, s, quoteId), now);
    if (!record?.quote_id) continue;
    items.push(publicQuote(record));
  }
  return { ok: true, status: 200, body: { ok: true, items } };
}

export async function getCompanyCustomerQuote(env, { scope, quoteId }) {
  const s = normalizeCustomerScope(scope);
  if (!s.hasScope) return { ok: false, status: 400, error: "missing_tenant_scope" };
  if (!isValidQuoteId(quoteId)) return { ok: false, status: 404, error: "not_found" };
  const now = nowIso(env);
  const record = markExpiredIfNeeded(await loadQuote(env.BOOKING_KV, s, quoteId), now);
  if (!record?.quote_id) return { ok: false, status: 404, error: "not_found" };
  return { ok: true, status: 200, body: { ok: true, quote: publicQuote(record) } };
}

export async function updateCompanyCustomerQuote(env, { scope, quoteId, body }) {
  const s = normalizeCustomerScope(scope);
  if (!s.hasScope) return { ok: false, status: 400, error: "missing_tenant_scope" };
  if (!isValidQuoteId(quoteId)) return { ok: false, status: 404, error: "not_found" };
  const record = await loadQuote(env.BOOKING_KV, s, quoteId);
  if (!record?.quote_id) return { ok: false, status: 404, error: "not_found" };
  if (record.state !== CUSTOMER_QUOTE_STATES.DRAFT) {
    return { ok: false, status: 409, error: "quote_not_draft" };
  }
  const incomingRevision = Number(body?.revision);
  if (!Number.isInteger(incomingRevision) || incomingRevision !== Number(record.revision)) {
    return { ok: false, status: 409, error: "revision_conflict", revision: record.revision };
  }
  const validated = validateQuoteWrite({ ...record, ...body }, { partial: false });
  if (!validated.ok) {
    return { ok: false, status: 400, error: "invalid_quote", fields: validated.fields };
  }
  const now = nowIso(env);
  Object.assign(record, validated.value, {
    issuer_name: validated.value.issuer_name || record.issuer_name,
    updated_at: now,
  });
  const updatedSnapshot = snapshotFromBody(body);
  if (updatedSnapshot) {
    record.pricing_source = updatedSnapshot.pricing_source || "company_fixed_price";
    record.fixed_fare_rule_id = updatedSnapshot.fixed_fare_rule_id;
    record.fixed_price_snapshot = updatedSnapshot;
  }
  await saveQuote(env.BOOKING_KV, s, record);
  return { ok: true, status: 200, body: { ok: true, quote: publicQuote(record) } };
}

export async function deliverCompanyCustomerQuoteMail(env, payload) {
  if (typeof env?.CUSTOMER_QUOTE_MAIL_SEND === "function") {
    try {
      const result = await env.CUSTOMER_QUOTE_MAIL_SEND(payload);
      if (result?.ok) {
        return {
          ok: true,
          delivery: CUSTOMER_QUOTE_DELIVERY.ADAPTER_ACCEPTED,
          delivery_proven: false,
          test_send: false,
        };
      }
      return {
        ok: false,
        status: 502,
        error: result?.error || CUSTOMER_QUOTE_DELIVERY.FAILED,
        delivery: CUSTOMER_QUOTE_DELIVERY.FAILED,
        delivery_proven: false,
      };
    } catch {
      return {
        ok: false,
        status: 502,
        error: CUSTOMER_QUOTE_DELIVERY.FAILED,
        delivery: CUSTOMER_QUOTE_DELIVERY.FAILED,
        delivery_proven: false,
      };
    }
  }
  if (Array.isArray(env?.CUSTOMER_QUOTE_MAIL_SINK)) {
    env.CUSTOMER_QUOTE_MAIL_SINK.push({
      ...payload,
      delivery: CUSTOMER_QUOTE_DELIVERY.TEST_ADAPTER,
      test_send: true,
      delivery_proven: false,
    });
    return {
      ok: true,
      delivery: CUSTOMER_QUOTE_DELIVERY.TEST_ADAPTER,
      delivery_proven: false,
      test_send: true,
    };
  }
  return {
    ok: false,
    status: 503,
    error: CUSTOMER_QUOTE_DELIVERY.NOT_CONFIGURED,
    delivery: CUSTOMER_QUOTE_DELIVERY.NOT_CONFIGURED,
    delivery_proven: false,
  };
}

export async function sendCompanyCustomerQuote(env, { scope, quoteId, publicBaseUrl = "" }) {
  const s = normalizeCustomerScope(scope);
  if (!s.hasScope) return { ok: false, status: 400, error: "missing_tenant_scope" };
  if (!isValidQuoteId(quoteId)) return { ok: false, status: 404, error: "not_found" };
  const record = await loadQuote(env.BOOKING_KV, s, quoteId);
  if (!record?.quote_id) return { ok: false, status: 404, error: "not_found" };
  if (record.state !== CUSTOMER_QUOTE_STATES.DRAFT && record.state !== CUSTOMER_QUOTE_STATES.SENT) {
    return { ok: false, status: 409, error: "quote_not_sendable" };
  }
  if (!isUsableCustomerEmail(record.passenger_email)) {
    return { ok: false, status: 400, error: "invalid_quote", fields: { passenger_email: "required" } };
  }
  if (record.entered_amount_cents == null) {
    return { ok: false, status: 400, error: "invalid_quote", fields: { entered_amount_cents: "required" } };
  }
  const addressFields = {};
  if (!quoteAddressIsComplete(record.pickup)) addressFields.pickup = "incomplete";
  if (!quoteAddressIsComplete(record.dropoff)) addressFields.dropoff = "incomplete";
  if (Object.keys(addressFields).length) {
    return { ok: false, status: 400, error: "invalid_quote", fields: addressFields };
  }
  const currency = clip(record.currency, 3).toUpperCase();
  if (!/^[A-Z]{3}$/.test(currency)) {
    return { ok: false, status: 400, error: "invalid_quote", fields: { currency: "required" } };
  }
  const now = nowIso(env);
  if (!record.valid_until) {
    record.valid_until = new Date(Date.parse(now) + 14 * 24 * 60 * 60 * 1000).toISOString();
  }
  if (isExpired(record, now)) {
    record.state = CUSTOMER_QUOTE_STATES.EXPIRED;
    await saveQuote(env.BOOKING_KV, s, record);
    return { ok: false, status: 410, error: "quote_expired" };
  }
  const token = newId("").slice(4);
  const tokenHash = await sha256Hex(token);
  const base = clip(publicBaseUrl || env?.CUSTOMER_QUOTE_PUBLIC_BASE || "https://example.test", 200);
  const publicPath = `/public/customer-quotes/${token}`;
  const publicUrl = `${base.replace(/\/$/, "")}${publicPath}`;
  const mail = await deliverCompanyCustomerQuoteMail(env, {
    scope: s,
    quote_id: record.quote_id,
    to: record.passenger_email,
    to_masked: maskCustomerEmail(record.passenger_email),
    issuer_name: record.issuer_name,
    public_path: publicPath,
    public_url: publicUrl,
    entered_amount_cents: record.entered_amount_cents,
    currency,
  });
  if (!mail?.ok) {
    return {
      ok: false,
      status: mail?.status || 502,
      error: mail?.error || CUSTOMER_QUOTE_DELIVERY.FAILED,
      delivery: mail?.delivery || CUSTOMER_QUOTE_DELIVERY.FAILED,
      delivery_proven: false,
    };
  }
  record.public_token = token;
  record.public_token_hash = tokenHash;
  record.state = CUSTOMER_QUOTE_STATES.SENT;
  record.sent_at = now;
  record.updated_at = now;
  record.currency = currency;
  record.delivery = mail.delivery;
  record.delivery_proven = false;
  record.test_send = mail.test_send === true;
  await kvPutJson(env.BOOKING_KV, companyCustomerQuoteTokenKey(tokenHash), {
    tenant_id: s.tenant_id,
    company_id: s.company_id,
    quote_id: record.quote_id,
    revision: record.revision,
  });
  await saveQuote(env.BOOKING_KV, s, record);
  return {
    ok: true,
    status: 200,
    body: {
      ok: true,
      quote: publicQuote(record, { includeToken: true }),
      public_path: publicPath,
      public_url: publicUrl,
      delivery: mail.delivery,
      delivery_proven: false,
      test_send: mail.test_send === true,
    },
  };
}

async function loadQuoteByToken(env, token) {
  const hash = await sha256Hex(safeStr(token));
  const binding = await kvGetJson(env.BOOKING_KV, companyCustomerQuoteTokenKey(hash));
  if (!binding?.quote_id) return { ok: false, status: 404, error: "not_found" };
  const scope = { tenant_id: binding.tenant_id, company_id: binding.company_id };
  const record = await loadQuote(env.BOOKING_KV, scope, binding.quote_id);
  if (!record?.quote_id) return { ok: false, status: 404, error: "not_found" };
  return { ok: true, record, scope, binding };
}

function quoteHtml(record, { acceptEnabled = false } = {}) {
  const amount = Number(record.entered_amount_cents || 0) / 100;
  const currency = record.currency || "EUR";
  const issuer = record.issuer_name || "";
  const vat = computeQuoteVatBreakdown(record);
  const vatLabel = VAT_TREATMENT_LABELS_NL[vat.treatment] || "";
  const rideSummary = formatQuoteRideOptionsNl(record.ride_options);
  const description = clip(record.description, 500);
  const accept = acceptEnabled
    ? `<button type="button" id="accept">Accepteren</button><script>document.getElementById("accept").addEventListener("click",async()=>{const r=await fetch(new URL("accept", location.href.endsWith("/") ? location.href : location.href + "/"),{method:"POST",headers:{"content-type":"application/json"},body:JSON.stringify({confirm:true})});const j=await r.json();if(j.ok){document.getElementById("accept").replaceWith(Object.assign(document.createElement("p"),{id:"accepted",textContent:"Geaccepteerd"}));}});</script>`
    : record.state === CUSTOMER_QUOTE_STATES.ACCEPTED
      ? `<p id="accepted">Geaccepteerd</p>`
      : `<p id="closed">${record.state}</p>`;
  const vatLines = [];
  if (vatLabel) vatLines.push(`<p id="vat">${vatLabel}</p>`);
  if (vat.rate_missing) {
    vatLines.push(`<p id="vat-missing">Btw-percentage ontbreekt. Er wordt geen totaal berekend.</p>`);
  } else if (vat.vat_rate > 0) {
    vatLines.push(`<p id="vat-rate">Btw ${vat.vat_rate}%</p>`);
    if (vat.treatment === "excl" && vat.vat_cents != null && vat.incl_cents != null) {
      vatLines.push(`<p id="vat-amount">Btw ${currency} ${(vat.vat_cents / 100).toFixed(2)}</p>`);
      vatLines.push(`<p id="vat-total">Totaal incl. btw ${currency} ${(vat.incl_cents / 100).toFixed(2)}</p>`);
    } else if (vat.treatment === "incl" && vat.excl_cents != null && vat.vat_cents != null) {
      vatLines.push(`<p id="vat-excl">Excl. btw ${currency} ${(vat.excl_cents / 100).toFixed(2)}</p>`);
      vatLines.push(`<p id="vat-amount">Btw ${currency} ${(vat.vat_cents / 100).toFixed(2)}</p>`);
    }
  }
  return `<!doctype html><html lang="nl"><head><meta charset="utf-8"/><meta name="viewport" content="width=device-width,initial-scale=1"/><title>Offerte ${issuer}</title>
<style>body{font-family:sans-serif;margin:24px;color:#111}h1{font-size:1.4rem}.price{font-size:1.8rem;font-weight:700}button{min-height:44px;padding:12px 20px}</style>
</head><body>
<p id="issuer">${issuer}</p>
<h1>Offerte</h1>
<p>${record.passenger_name || ""}</p>
<p>${record.pickup || ""} → ${record.dropoff || ""}</p>
<p>${record.start_at || ""} · ${record.passengers || 1} pax</p>
${formatQuoteRoundtripHtml(record)}
${rideSummary ? `<p id="included-services-label">Inbegrepen diensten</p><p id="ride-options">${rideSummary}</p>` : ""}
${description ? `<p id="price-conditions-label">Prijsvoorwaarden</p><p id="price-conditions">${description}</p>` : ""}
<p class="price" id="price">${currency} ${amount.toFixed(2)}</p>
${vatLines.join("")}
<p>Geldig tot ${record.valid_until || ""}</p>
${accept}
</body></html>`;
}

export async function viewPublicCustomerQuote(env, { token, markViewed = true }) {
  const loaded = await loadQuoteByToken(env, token);
  if (!loaded.ok) return loaded;
  const now = nowIso(env);
  const record = markExpiredIfNeeded(loaded.record, now);
  if (record.state === CUSTOMER_QUOTE_STATES.EXPIRED) {
    return { ok: false, status: 410, error: "quote_expired", record };
  }
  if (record.state === CUSTOMER_QUOTE_STATES.WITHDRAWN) {
    return { ok: false, status: 409, error: "quote_withdrawn", record };
  }
  if (
    markViewed &&
    (record.state === CUSTOMER_QUOTE_STATES.SENT || record.state === CUSTOMER_QUOTE_STATES.VIEWED)
  ) {
    record.state = CUSTOMER_QUOTE_STATES.VIEWED;
    record.updated_at = now;
    await saveQuote(env.BOOKING_KV, loaded.scope, record);
  }
  return { ok: true, status: 200, record, scope: loaded.scope };
}

export async function customerQuoteBookingId(quoteId) {
  const hex = await sha256Hex(safeStr(quoteId));
  return hex ? `cqb_${hex.slice(0, 32)}` : "";
}

function quoteAmountEuros(cents) {
  const n = Number(cents);
  if (!Number.isInteger(n) || n < 0) return null;
  return Math.round(n) / 100;
}

function sameQuoteBooking(existing, quoteId) {
  const id = safeStr(quoteId);
  if (!existing || typeof existing !== "object" || !id) return false;
  return (
    safeStr(existing.quote_id) === id ||
    safeStr(existing.booking?.quote_id) === id ||
    safeStr(existing.quote?.quote_id) === id
  );
}

function buildAcceptedQuoteBookingRecord(quote, bookingId, now) {
  const pickup = quote.pickup || "";
  const dropoff = quote.dropoff || "";
  const pickupIso = quote.start_at || "";
  const pax = Number(quote.passengers || 1);
  const vat = computeQuoteVatBreakdown(quote);
  const euros = vat.incl_cents != null
    ? eurosFromCents(vat.incl_cents)
    : vat.treatment === "excl"
      ? null
      : quoteAmountEuros(quote.entered_amount_cents);
  const exclEuros = vat.excl_cents != null ? eurosFromCents(vat.excl_cents) : null;
  const vatEuros = vat.vat_cents != null ? eurosFromCents(vat.vat_cents) : null;
  const currency = quote.currency || "EUR";
  const customerName = quote.passenger_name || "";
  const customerEmail = quote.passenger_email || "";
  const customerPhone = quote.passenger_phone || "";
  const rideOptions = quote.ride_options || normalizeRideOptions(quote);
  const booking = {
    tenant_id: quote.tenant_id,
    company_id: quote.company_id,
    from: pickup,
    to: dropoff,
    pickup_iso: pickupIso,
    pickupStartIso: pickupIso,
    pickup_lat: optionalCoord(quote.pickup_lat),
    pickup_lon: optionalCoord(quote.pickup_lon),
    pickup_place_id: quote.pickup_place_id || "",
    dropoff_lat: optionalCoord(quote.dropoff_lat),
    dropoff_lon: optionalCoord(quote.dropoff_lon),
    dropoff_place_id: quote.dropoff_place_id || "",
    from_lat: optionalCoord(quote.pickup_lat),
    from_lon: optionalCoord(quote.pickup_lon),
    to_lat: optionalCoord(quote.dropoff_lat),
    to_lon: optionalCoord(quote.dropoff_lon),
    pax,
    customer_name: customerName,
    customer_email: customerEmail,
    customer_phone: customerPhone,
    customer: {
      name: customerName,
      email: customerEmail,
      phone: customerPhone,
    },
    currency,
    vat_treatment: vat.treatment || "",
    vat_rate: vat.vat_rate,
    price_ex_vat: exclEuros,
    price_vat: vatEuros,
    price_incl_vat: euros,
    status: "PENDING",
    source: "company_customer_quote",
    quote_id: quote.quote_id,
    do_not_dispatch: true,
    note: quote.description || "",
  };
  stampRideFields(booking, rideOptions, quote.description);
  booking.inputs = { ...rideOptions, pax, note: quote.description || "" };
  const quoteSnap = {
    from: pickup,
    to: dropoff,
    pickup_iso: pickupIso,
    quote_id: quote.quote_id,
    inputs: { ...rideOptions, pax },
    pricing: {
      vat_treatment: vat.treatment || "",
      vat_rate: vat.vat_rate,
      price_ex_vat: exclEuros,
      price_vat: vatEuros,
      price_incl_vat: euros,
      currency,
    },
  };
  stampRideFields(quoteSnap, rideOptions, quote.description);
  const record = {
    booking_id: bookingId,
    tenant_id: quote.tenant_id,
    company_id: quote.company_id,
    customer_id: quote.customer_id,
    source: "company_customer_quote",
    status: "PENDING",
    stage: "PENDING",
    lifecycle: "PENDING",
    do_not_dispatch: true,
    ride_started: false,
    quote_id: quote.quote_id,
    quote_revision: quote.revision,
    planning_reference: quote.quote_id,
    public_booking_reference: quote.quote_id,
    pickup_iso: pickupIso,
    pickup_lat: optionalCoord(quote.pickup_lat),
    pickup_lon: optionalCoord(quote.pickup_lon),
    pickup_place_id: quote.pickup_place_id || "",
    dropoff_lat: optionalCoord(quote.dropoff_lat),
    dropoff_lon: optionalCoord(quote.dropoff_lon),
    dropoff_place_id: quote.dropoff_place_id || "",
    vat_treatment: vat.treatment || "",
    vat_rate: vat.vat_rate,
    price_ex_vat: exclEuros,
    price_vat: vatEuros,
    price_incl_vat: euros,
    created_at: now,
    updated_at: now,
    booking,
    quote: quoteSnap,
  };
  stampRideFields(record, rideOptions, quote.description);
  const parsed = parseCompanyRoundtripWrite({
    ...quote,
    pickup_iso: pickupIso,
    from: pickup,
    to: dropoff,
  });
  if (parsed.ok) applyCompanyRoundtripFields(record, parsed, { bookingId, now });
  if (quote.fixed_price_snapshot) {
    stampCompanyFixedPriceSnapshot(record, quote.fixed_price_snapshot);
  }
  return record;
}

async function persistAcceptedQuoteOnCompanyBookingsList(env, quote, now) {
  const bookingId = safeStr(quote.booking_id) || (await customerQuoteBookingId(quote.quote_id));
  if (!bookingId) return { ok: false, error: "booking_id_unavailable" };
  const next = buildAcceptedQuoteBookingRecord(quote, bookingId, now);
  const existing = await kvGetJson(env.BOOKING_KV, companyCustomerQuoteBookingKey(bookingId));
  if (existing && !sameQuoteBooking(existing, quote.quote_id)) {
    return { ok: false, error: "booking_id_collision", booking_id: bookingId };
  }
  if (existing?.created_at || existing?.booking?.created_at) {
    next.created_at = existing.created_at || existing.booking.created_at;
  }
  const put = await putBookingCreateIfAbsent(
    env.BOOKING_KV,
    bookingId,
    JSON.stringify(next),
    { mode: existing ? "upsert_same" : "create" },
  );
  if (!put.ok) {
    return { ok: false, error: put.error || "booking_write_failed", booking_id: bookingId };
  }
  const listed = await upsertCompanyBookingsListIndexBestEffort(env, bookingId, next, {
    tenant_id: quote.tenant_id,
    company_id: quote.company_id,
    hasScope: true,
  });
  return {
    ok: true,
    booking_id: bookingId,
    listed: listed?.ok === true,
    record: next,
  };
}

function acceptedQuoteHandoffBody(record, { bookingId, idempotent = false } = {}) {
  return {
    ok: true,
    quote: publicCustomerQuoteView(record),
    booking_id: bookingId || record.booking_id,
    booking_list_ready: record.booking_list_ready === true,
    booking_dispatch_blocked: true,
    ...(idempotent ? { idempotent: true } : {}),
  };
}

export async function acceptPublicCustomerQuote(env, { token, confirm = false }) {
  if (confirm !== true) {
    return { ok: false, status: 400, error: "confirm_required" };
  }
  const loaded = await loadQuoteByToken(env, token);
  if (!loaded.ok) return loaded;
  const now = nowIso(env);
  const record = markExpiredIfNeeded(loaded.record, now);
  if (record.state === CUSTOMER_QUOTE_STATES.EXPIRED) {
    return { ok: false, status: 410, error: "quote_expired" };
  }
  const alreadyAccepted = record.state === CUSTOMER_QUOTE_STATES.ACCEPTED && !!record.booking_id;
  if (
    !alreadyAccepted &&
    record.state !== CUSTOMER_QUOTE_STATES.SENT &&
    record.state !== CUSTOMER_QUOTE_STATES.VIEWED
  ) {
    return { ok: false, status: 409, error: "quote_not_acceptable" };
  }
  if (!alreadyAccepted && record.fixed_price_snapshot?.fixed_fare_rule_id) {
    const live = await resolveCompanyFixedPrice(env, loaded.scope, {
      from: record.pickup,
      to: record.dropoff,
      pickup_lat: record.pickup_lat,
      pickup_lon: record.pickup_lon,
      dropoff_lat: record.dropoff_lat,
      dropoff_lon: record.dropoff_lon,
      pax: record.passengers,
      bags: record.ride_options?.bags,
      tier: record.ride_options?.tier,
      airport_iata: record.ride_options?.airport_iata,
      airport_direction: record.ride_options?.airport_direction,
    });
    const storedTotal =
      Number(record.fixed_price_snapshot.total_incl_vat) ||
      Number(record.entered_amount_cents || 0) / 100;
    if (
      !live.matched ||
      companyFixedPriceTotalsDiffer(storedTotal, live.snapshot?.total_incl_vat)
    ) {
      return {
        ok: false,
        status: 409,
        error: "price_changed",
        snapshot: live.snapshot,
      };
    }
  }
  const persist = await persistAcceptedQuoteOnCompanyBookingsList(env, record, now);
  if (!persist.ok) {
    return {
      ok: false,
      status: persist.error === "booking_id_collision" ? 409 : 503,
      error: persist.error,
      booking_id: persist.booking_id,
      booking_list_ready: false,
    };
  }
  if (!persist.listed) {
    if (alreadyAccepted) {
      record.booking_list_ready = false;
      record.updated_at = now;
      await saveQuote(env.BOOKING_KV, loaded.scope, record);
    }
    return {
      ok: false,
      status: 503,
      error: "booking_list_index_failed",
      booking_id: persist.booking_id,
      booking_list_ready: false,
    };
  }
  record.booking_id = persist.booking_id;
  record.booking_list_ready = true;
  record.updated_at = now;
  if (!alreadyAccepted) {
    record.state = CUSTOMER_QUOTE_STATES.ACCEPTED;
    record.accepted_at = now;
  }
  await saveQuote(env.BOOKING_KV, loaded.scope, record);
  return {
    ok: true,
    status: 200,
    body: acceptedQuoteHandoffBody(record, {
      bookingId: persist.booking_id,
      idempotent: alreadyAccepted,
    }),
  };
}

function errorBody(result) {
  const body = { ok: false, error: result.error || "invalid_quote" };
  if (result.fields) body.fields = result.fields;
  if (result.revision != null) body.revision = result.revision;
  if (result.delivery) body.delivery = result.delivery;
  if (result.delivery_proven != null) body.delivery_proven = false;
  if (result.booking_id) body.booking_id = result.booking_id;
  if (result.booking_list_ready != null) body.booking_list_ready = result.booking_list_ready;
  return body;
}

export async function serveCompanyCustomerQuotesHttp({
  env,
  method,
  route,
  body,
  scope,
  request,
}) {
  if (route.kind === "customer_quotes" && method === "GET") {
    const result = await listCompanyCustomerQuotes(env, { scope, customerId: route.customerId });
    if (!result.ok) return json(errorBody(result), result.status);
    return json(result.body, 200);
  }
  if (route.kind === "customer_quotes" && method === "POST") {
    const result = await createCompanyCustomerQuote(env, {
      scope,
      customerId: route.customerId,
      body: body || {},
      request,
    });
    if (!result.ok) return json(errorBody(result), result.status);
    return json(result.body, result.status);
  }
  if (route.kind === "customer_quote" && !route.action && method === "GET") {
    const result = await getCompanyCustomerQuote(env, { scope, quoteId: route.quoteId });
    if (!result.ok) return json(errorBody(result), result.status);
    return json(result.body, 200);
  }
  if (route.kind === "customer_quote" && !route.action && method === "PATCH") {
    const result = await updateCompanyCustomerQuote(env, {
      scope,
      quoteId: route.quoteId,
      body: body || {},
    });
    if (!result.ok) return json(errorBody(result), result.status);
    return json(result.body, 200);
  }
  if (route.kind === "customer_quote" && route.action === "send" && method === "POST") {
    const result = await sendCompanyCustomerQuote(env, {
      scope,
      quoteId: route.quoteId,
      publicBaseUrl: body?.public_base_url,
    });
    if (!result.ok) return json(errorBody(result), result.status);
    return json(result.body, 200);
  }
  if (route.kind === "customer_quote" && route.action === "pdf" && method === "GET") {
    const result = await getCompanyCustomerQuote(env, { scope, quoteId: route.quoteId });
    if (!result.ok) return json(errorBody(result), result.status);
    const page = quoteHtml(result.body.quote, { acceptEnabled: false });
    const pdf = await renderPdfFromHtml(page, env).catch(() => null);
    if (pdf) {
      return new Response(pdf, {
        status: 200,
        headers: { "content-type": "application/pdf" },
      });
    }
    return html(page, 200);
  }
  return json({ ok: false, error: "method_not_allowed" }, 405);
}

export async function servePublicCustomerQuoteHttp({ env, method, token, action, body }) {
  if (!token) return json({ ok: false, error: "not_found" }, 404);
  if (!action && method === "GET") {
    const result = await viewPublicCustomerQuote(env, { token, markViewed: true });
    if (!result.ok) {
      if (result.record) return html(quoteHtml(result.record), result.status);
      return json(errorBody(result), result.status);
    }
    const acceptEnabled =
      result.record.state === CUSTOMER_QUOTE_STATES.SENT ||
      result.record.state === CUSTOMER_QUOTE_STATES.VIEWED ||
      (result.record.state === CUSTOMER_QUOTE_STATES.ACCEPTED &&
        result.record.booking_list_ready !== true);
    return html(quoteHtml(result.record, { acceptEnabled }), 200);
  }
  if (action === "accept" && method === "GET") {
    return json({ ok: false, error: "confirm_required" }, 405);
  }
  if (action === "accept" && method === "POST") {
    const confirm = body?.confirm === true || body?.confirm === "true";
    const result = await acceptPublicCustomerQuote(env, { token, confirm });
    if (!result.ok) return json(errorBody(result), result.status);
    return json(result.body, 200);
  }
  if (action === "pdf" && method === "GET") {
    const result = await viewPublicCustomerQuote(env, { token, markViewed: false });
    if (!result.ok) return json(errorBody(result), result.status);
    return html(quoteHtml(result.record), 200);
  }
  return json({ ok: false, error: "method_not_allowed" }, 405);
}
