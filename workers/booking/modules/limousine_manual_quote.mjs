// LIMOUSINE-MARKETPLACE-P2C2 — manual quote lifecycle, terms revision and audit.
//
// Pure and fully testable. Covers the human-priced path for:
//   * quote_required offers;
//   * indicative / from-price offers needing confirmation;
//   * quote-required extras;
//   * exceptional journeys that explicitly allow manual quotation.
//
// Acceptance feeds the SHARED Fluxidi booking lifecycle — this is not a second
// booking engine. A human-approved total is never recomputed with taxi pricing,
// and a customer-supplied total is never trusted.

import { projectLimousineQuotationAvailability } from "./limousine_quotation_snapshot.mjs";
import { offerAllowsPublishedJourneyType } from "./limousine_offers.mjs";
import { normalizeLimousineToken } from "./limousine_provider_eligibility.mjs";
import {
  attachLimousineItineraryEndpoints,
  limousineItineraryConflictsWithJourney,
} from "./limousine_transfer_endpoint.mjs";
import {
  LIMOUSINE_INTENT_KIND,
  LIMOUSINE_SERVICE_TYPE,
  LIMOUSINE_UNIFIED_REASONS,
  assertLimousineOfferStillPublished,
  assertLimousineOfferVehicleScope,
  buildLimousineQuoteIntentSnapshot,
  classifyLimousinePublishedPricingMode,
} from "./limousine_unified_intent.mjs";

export const LIMOUSINE_QUOTE_STATES = Object.freeze({
  REQUESTED: "requested",
  VIEWED_BY_COMPANY: "viewed_by_company",
  QUOTED: "quoted",
  CUSTOMER_ACCEPTANCE_REQUIRED: "customer_acceptance_required",
  ACCEPTED: "accepted",
  BOOKING_CREATED: "booking_created",
  DECLINED: "declined",
  EXPIRED: "expired",
  WITHDRAWN: "withdrawn",
  SUPERSEDED: "superseded",
  CANCELLED: "cancelled",
});

const S = LIMOUSINE_QUOTE_STATES;

export const LIMOUSINE_QUOTE_TERMINAL_STATES = Object.freeze([
  S.BOOKING_CREATED,
  S.DECLINED,
  S.EXPIRED,
  S.WITHDRAWN,
  S.SUPERSEDED,
  S.CANCELLED,
]);

/// Terminal-from-any-active states (company withdrawal, expiry, cancellation).
const ALWAYS_ALLOWED_TERMINALS = [S.DECLINED, S.EXPIRED, S.WITHDRAWN, S.CANCELLED];

const TRANSITIONS = Object.freeze({
  [S.REQUESTED]: [S.VIEWED_BY_COMPANY, S.QUOTED, ...ALWAYS_ALLOWED_TERMINALS],
  [S.VIEWED_BY_COMPANY]: [S.QUOTED, ...ALWAYS_ALLOWED_TERMINALS],
  [S.QUOTED]: [S.CUSTOMER_ACCEPTANCE_REQUIRED, S.SUPERSEDED, ...ALWAYS_ALLOWED_TERMINALS],
  // Re-quote: company replaces an unaccepted quote. SUPERSEDED remains the
  // terminal kill for the whole request; the live record stays one document
  // and records superseded_revision on the replacement.
  [S.CUSTOMER_ACCEPTANCE_REQUIRED]: [S.ACCEPTED, S.QUOTED, S.SUPERSEDED, ...ALWAYS_ALLOWED_TERMINALS],
  // Once accepted the quote may only become a booking or be cancelled.
  [S.ACCEPTED]: [S.BOOKING_CREATED, S.CANCELLED, S.EXPIRED],
  [S.BOOKING_CREATED]: [],
  [S.DECLINED]: [],
  [S.EXPIRED]: [],
  [S.WITHDRAWN]: [],
  [S.SUPERSEDED]: [],
  [S.CANCELLED]: [],
});

export const LIMOUSINE_QUOTE_REASONS = Object.freeze({
  OK: "ok",
  GATE_OFF: "manual_quote_gate_off",
  NOT_ELIGIBLE: "not_eligible",
  OFFER_NOT_BOOKABLE_MANUALLY: "offer_not_manual_quotable",
  UNKNOWN_OFFER: "unknown_offer",
  OFFER_UNPUBLISHED: "offer_unpublished",
  INVALID_EXTRA: "invalid_extra",
  INVALID_REQUEST: "invalid_request",
  CLIENT_PRICING_REJECTED: "client_pricing_rejected",
  UNAUTHORIZED_SCOPE: "unauthorized_scope",
  INVALID_TRANSITION: "invalid_transition",
  STALE_REVISION: "stale_revision",
  IDEMPOTENT_REPLAY: "idempotent_replay",
  NOT_ACCEPTABLE_STATE: "not_acceptable_state",
  QUOTE_EXPIRED: "quote_expired",
  BINDING_MISMATCH: "binding_mismatch",
  INVALID_AMOUNT: "invalid_amount",
  INVALID_CURRENCY: "invalid_currency",
  MISSING_TERMS: "missing_terms",
  QUOTE_TERMS_INCOMPLETE: "quote_terms_incomplete",
  STALE_TERMS_REVISION: "stale_terms_revision",
  UNKNOWN_CRITICAL_FIELD: "unknown_critical_field",
  QUOTATION_SNAPSHOT_CONFLICT: "quotation_snapshot_conflict",
  QUOTATION_SNAPSHOT_MISSING: "quotation_snapshot_missing",
  JOURNEY_TYPE_NOT_ALLOWED: "journey_type_not_allowed",
  VEHICLE_SCOPE_MISMATCH: LIMOUSINE_UNIFIED_REASONS.VEHICLE_SCOPE_MISMATCH,
  VEHICLE_NOT_PUBLISHED: LIMOUSINE_UNIFIED_REASONS.VEHICLE_NOT_PUBLISHED,
});

const ISO_CURRENCY = /^[A-Z]{3}$/;
const LANGS = ["nl", "en", "fr", "es"];

function asObject(raw) {
  return raw && typeof raw === "object" && !Array.isArray(raw) ? raw : {};
}

function toInt(value) {
  const n = Number(value);
  return Number.isFinite(n) ? Math.trunc(n) : null;
}

function isNonNegInt(value) {
  if (typeof value === "boolean" || value == null || value === "") return false;
  const n = Number(value);
  return Number.isInteger(n) && n >= 0;
}

function isPositiveInt(value) {
  if (typeof value === "boolean" || value == null || value === "") return false;
  const n = Number(value);
  return Number.isInteger(n) && n > 0;
}

function safeText(value, max) {
  return String(value ?? "").trim().slice(0, max);
}

function normalizeCurrency(value) {
  const c = String(value ?? "").trim().toUpperCase();
  return ISO_CURRENCY.test(c) ? c : "";
}

function localized(raw, max = 600) {
  const src = asObject(raw);
  const out = {};
  for (const lang of LANGS) {
    const text = safeText(src[lang], max);
    if (text) out[lang] = text;
  }
  return out;
}

// ---------------------------------------------------------------------------
// State machine
// ---------------------------------------------------------------------------

export function isTerminalLimousineQuoteState(state) {
  return LIMOUSINE_QUOTE_TERMINAL_STATES.includes(normalizeLimousineToken(state));
}

/// Unknown or contradictory transitions fail closed.
export function canTransitionLimousineQuote(from, to) {
  const f = normalizeLimousineToken(from);
  const t = normalizeLimousineToken(to);
  if (!Object.prototype.hasOwnProperty.call(TRANSITIONS, f)) return false;
  if (!Object.values(S).includes(t)) return false;
  return TRANSITIONS[f].includes(t);
}

/// Applies a transition with server-owned monotonic revision control.
///   * an expected revision below the current one is a stale conflict (no write);
///   * an identical replay of the SAME transition at the SAME revision is
///     idempotent and writes nothing;
///   * a valid transition bumps the revision by exactly one.
export function applyLimousineQuoteTransition(record, {
  to,
  expectedRevision = null,
  actorType = "system",
  reasonCode = "",
  nowIso = null,
  patch = null,
} = {}) {
  const R = LIMOUSINE_QUOTE_REASONS;
  const current = asObject(record);
  const from = normalizeLimousineToken(current.state);
  const target = normalizeLimousineToken(to);
  const currentRevision = toInt(current.revision) ?? 0;
  const now = nowIso || new Date().toISOString();

  if (expectedRevision != null) {
    const expected = toInt(expectedRevision);
    if (expected == null || expected < currentRevision) {
      return { ok: false, reason: R.STALE_REVISION, current_revision: currentRevision };
    }
    if (expected > currentRevision) {
      return { ok: false, reason: R.STALE_REVISION, current_revision: currentRevision };
    }
  }

  // Idempotent replay: the record is already in the target state at this
  // revision because of the same transition.
  if (from === target && current.last_transition_to === target) {
    return {
      ok: true,
      changed: false,
      reason: R.IDEMPOTENT_REPLAY,
      record: current,
      audit: null,
    };
  }

  if (!canTransitionLimousineQuote(from, target)) {
    return { ok: false, reason: R.INVALID_TRANSITION, from, to: target };
  }

  const nextRevision = currentRevision + 1;
  const next = {
    ...current,
    ...(asObject(patch)),
    state: target,
    revision: nextRevision,
    last_transition_from: from,
    last_transition_to: target,
    updated_at: now,
    ...(target === S.ACCEPTED ? { accepted_at: now } : {}),
    ...(target === S.BOOKING_CREATED ? { booking_created_at: now } : {}),
  };
  const audit = buildLimousineQuoteAuditEntry({
    from,
    to: target,
    revision: nextRevision,
    actorType,
    reasonCode,
    nowIso: now,
    amountCents: next.quote?.total_incl_vat_cents,
    currency: next.quote?.currency,
    termsRevision: next.quote?.terms_revision,
    bookingReference: next.booking_reference,
  });
  return { ok: true, changed: true, record: next, audit };
}

// ---------------------------------------------------------------------------
// Terms revision contract
// ---------------------------------------------------------------------------

/// Booking-critical terms. A missing or unknown key fails closed — no legal
/// text or commercial default is ever invented here.
export const LIMOUSINE_REQUIRED_TERMS_KEYS = Object.freeze([
  "cancellation_deadline_hours",
  "cancellation_penalty_percent",
  "waiting_time_included_minutes",
  "waiting_time_overage_cents_per_minute",
  "no_show_penalty_percent",
  "overtime_cents_per_hour",
]);

export const LIMOUSINE_KNOWN_TERMS_KEYS = Object.freeze([
  "terms_revision",
  "termsRevision",
  ...LIMOUSINE_REQUIRED_TERMS_KEYS,
  "cancellationDeadlineHours",
  "cancellationPenaltyPercent",
  "waitingTimeIncludedMinutes",
  "waitingTimeOverageCentsPerMinute",
  "noShowPenaltyPercent",
  "overtimeCentsPerHour",
  "included_services",
  "includedServices",
  "paid_extras",
  "paidExtras",
  "mobilisation_disclosure",
  "mobilisationDisclosure",
  "customer_obligations",
  "customerObligations",
  "important_information",
  "importantInformation",
]);

export const LIMOUSINE_PUBLIC_FORBIDDEN_KEYS = Object.freeze([
  "authorization",
  "headers",
  "cookie",
  "card",
  "cvc",
  "pan",
  "api_key",
  "secret",
  "token",
  "acceptance_reference",
  "status_ref",
  "status_access",
  "customer_fingerprint",
  "email",
  "phone",
  "customer_name",
  "customer_reference",
  "operating_base_address",
  "internal_cost",
  "margin",
  "provider_payload",
  "audit",
  "itinerary_fingerprint",
  "vat_rate_source",
]);

export function normalizeLimousineTerms(raw) {
  const src = asObject(raw);
  const out = {
    terms_revision: toInt(src.terms_revision ?? src.termsRevision) ?? 0,
    cancellation_deadline_hours: toInt(src.cancellation_deadline_hours),
    cancellation_penalty_percent: toInt(src.cancellation_penalty_percent),
    waiting_time_included_minutes: toInt(src.waiting_time_included_minutes),
    waiting_time_overage_cents_per_minute: toInt(
      src.waiting_time_overage_cents_per_minute,
    ),
    no_show_penalty_percent: toInt(src.no_show_penalty_percent),
    overtime_cents_per_hour: toInt(src.overtime_cents_per_hour),
    included_services: Array.isArray(src.included_services)
      ? src.included_services.slice(0, 20).map((s) => ({
          item_id: safeText(asObject(s).item_id, 64),
          label: localized(asObject(s).label, 120),
        }))
      : [],
    paid_extras: Array.isArray(src.paid_extras)
      ? src.paid_extras.slice(0, 20).map((e) => ({
          extra_id: safeText(asObject(e).extra_id, 64),
          label: localized(asObject(e).label, 120),
          amount_cents: toInt(asObject(e).amount_cents),
          quote_required: asObject(e).quote_required === true,
        }))
      : [],
    mobilisation_disclosure: localized(src.mobilisation_disclosure, 240),
    customer_obligations: localized(src.customer_obligations, 600),
    important_information: localized(src.important_information, 600),
  };
  return out;
}

export function unknownLimousineTermsKeys(raw) {
  const src = asObject(raw);
  return Object.keys(src).filter((key) => !LIMOUSINE_KNOWN_TERMS_KEYS.includes(key));
}

const TERMS_CAMEL = Object.freeze({
  terms_revision: "termsRevision",
  cancellation_deadline_hours: "cancellationDeadlineHours",
  cancellation_penalty_percent: "cancellationPenaltyPercent",
  waiting_time_included_minutes: "waitingTimeIncludedMinutes",
  waiting_time_overage_cents_per_minute: "waitingTimeOverageCentsPerMinute",
  no_show_penalty_percent: "noShowPenaltyPercent",
  overtime_cents_per_hour: "overtimeCentsPerHour",
});

function rawTermsValue(src, key) {
  if (Object.prototype.hasOwnProperty.call(src, key)) return src[key];
  const camel = TERMS_CAMEL[key];
  if (camel && Object.prototype.hasOwnProperty.call(src, camel)) return src[camel];
  return undefined;
}

export function validateLimousineTerms(raw) {
  const src = asObject(raw);
  const terms = normalizeLimousineTerms(src);
  const missing = [];
  for (const key of LIMOUSINE_REQUIRED_TERMS_KEYS) {
    const rawValue = rawTermsValue(src, key);
    if (!isNonNegInt(rawValue)) missing.push(key);
  }
  const rawRevision = rawTermsValue(src, "terms_revision");
  if (!isPositiveInt(rawRevision)) missing.push("terms_revision");
  if (Array.isArray(src.paid_extras ?? src.paidExtras)) {
    for (const extra of terms.paid_extras) {
      if (!isNonNegInt(extra.amount_cents)) {
        missing.push("paid_extras");
        break;
      }
    }
  }
  const unknown = unknownLimousineTermsKeys(src);
  return {
    valid: missing.length === 0 && unknown.length === 0,
    missing,
    unknown,
    terms,
  };
}

/// Projects the stored terms object for the public DTO. Required booking-
/// critical keys are always present; missing values stay `null` rather than
/// being omitted or invented.
export function projectPublicLimousineQuoteTerms(quote) {
  const q = asObject(quote);
  const rawTerms = asObject(q.terms);
  const normalized = normalizeLimousineTerms(rawTerms);
  const unknown = unknownLimousineTermsKeys(rawTerms);
  const missing = [];
  const terms = {
    terms_revision: isPositiveInt(q.terms_revision ?? normalized.terms_revision)
      ? toInt(q.terms_revision ?? normalized.terms_revision)
      : null,
    cancellation_deadline_hours: isNonNegInt(normalized.cancellation_deadline_hours)
      ? normalized.cancellation_deadline_hours
      : null,
    cancellation_penalty_percent: isNonNegInt(normalized.cancellation_penalty_percent)
      ? normalized.cancellation_penalty_percent
      : null,
    waiting_time_included_minutes: isNonNegInt(normalized.waiting_time_included_minutes)
      ? normalized.waiting_time_included_minutes
      : null,
    waiting_time_overage_cents_per_minute: isNonNegInt(
      normalized.waiting_time_overage_cents_per_minute,
    )
      ? normalized.waiting_time_overage_cents_per_minute
      : null,
    no_show_penalty_percent: isNonNegInt(normalized.no_show_penalty_percent)
      ? normalized.no_show_penalty_percent
      : null,
    overtime_cents_per_hour: isNonNegInt(normalized.overtime_cents_per_hour)
      ? normalized.overtime_cents_per_hour
      : null,
  };
  if (terms.terms_revision == null) missing.push("terms_revision");
  for (const key of LIMOUSINE_REQUIRED_TERMS_KEYS) {
    if (terms[key] == null) missing.push(key);
  }
  if (normalized.included_services.length) {
    terms.included_services = normalized.included_services;
  }
  if (normalized.paid_extras.length) {
    terms.paid_extras = normalized.paid_extras;
  }
  if (Object.keys(normalized.mobilisation_disclosure).length) {
    terms.mobilisation_disclosure = normalized.mobilisation_disclosure;
  }
  if (Object.keys(normalized.customer_obligations).length) {
    terms.customer_obligations = normalized.customer_obligations;
  }
  if (Object.keys(normalized.important_information).length) {
    terms.important_information = normalized.important_information;
  }
  return { terms, missing, unknown };
}

/// Completeness of the authoritative stored quote. Does not invent defaults.
export function evaluateLimousineQuoteTermsCompleteness(quote) {
  const R = LIMOUSINE_QUOTE_REASONS;
  const q = asObject(quote);
  if (!Object.keys(q).length) {
    return { ok: false, reason: R.QUOTE_TERMS_INCOMPLETE, missing: ["quote"], unknown: [] };
  }
  if (!isNonNegInt(q.total_incl_vat_cents) || Number(q.total_incl_vat_cents) <= 0) {
    return { ok: false, reason: R.INVALID_AMOUNT, missing: [], unknown: [] };
  }
  if (!normalizeCurrency(q.currency)) {
    return { ok: false, reason: R.INVALID_CURRENCY, missing: [], unknown: [] };
  }
  const termsCheck = validateLimousineTerms(q.terms);
  const missing = [...termsCheck.missing];
  const quoteRev = q.terms_revision;
  const innerRev = termsCheck.terms.terms_revision;
  if (!isPositiveInt(quoteRev) || !isPositiveInt(innerRev) || toInt(quoteRev) !== toInt(innerRev)) {
    if (!missing.includes("terms_revision")) missing.push("terms_revision");
  }
  if (termsCheck.unknown.length) {
    return {
      ok: false,
      reason: R.UNKNOWN_CRITICAL_FIELD,
      missing,
      unknown: termsCheck.unknown,
    };
  }
  if (missing.length) {
    return { ok: false, reason: R.QUOTE_TERMS_INCOMPLETE, missing, unknown: [] };
  }
  if (!Number.isFinite(Date.parse(safeText(q.expires_at, 40)))) {
    return { ok: false, reason: R.QUOTE_TERMS_INCOMPLETE, missing: ["expires_at"], unknown: [] };
  }
  return { ok: true, reason: R.OK, missing: [], unknown: [], terms: termsCheck.terms };
}

/// Read-only acceptance gate used by the public view and accept path.
export function evaluateLimousineQuoteAcceptanceReadiness(record, { nowIso = null } = {}) {
  const R = LIMOUSINE_QUOTE_REASONS;
  const rec = asObject(record);
  const state = normalizeLimousineToken(rec.state);
  const quote = rec.quote && typeof rec.quote === "object" && !Array.isArray(rec.quote)
    ? rec.quote
    : null;
  const currentRevision = toInt(rec.revision) ?? 0;
  const base = { acceptance_allowed: false, state, current_revision: currentRevision };

  if (!quote) {
    if (state !== S.QUOTED && state !== S.CUSTOMER_ACCEPTANCE_REQUIRED) {
      return { ok: false, ...base, reason: R.NOT_ACCEPTABLE_STATE };
    }
    return { ok: false, ...base, reason: R.QUOTE_TERMS_INCOMPLETE, missing: ["quote"] };
  }

  const completeness = evaluateLimousineQuoteTermsCompleteness(quote);
  if (!completeness.ok) {
    return {
      ok: false,
      ...base,
      reason: completeness.reason,
      missing: completeness.missing,
      unknown: completeness.unknown,
    };
  }

  if (state !== S.QUOTED && state !== S.CUSTOMER_ACCEPTANCE_REQUIRED) {
    return { ok: false, ...base, reason: R.NOT_ACCEPTABLE_STATE };
  }

  const now = Date.parse(nowIso || new Date().toISOString());
  const expiry = Date.parse(safeText(quote.expires_at, 40));
  if (Number.isFinite(expiry) && Number.isFinite(now) && now > expiry) {
    return { ok: false, ...base, reason: R.QUOTE_EXPIRED };
  }

  const binding = buildLimousineAcceptanceBinding(rec);
  if ((toInt(binding.terms_revision) ?? 0) !== (toInt(quote.terms_revision) ?? 0)) {
    return { ok: false, ...base, reason: R.QUOTE_TERMS_INCOMPLETE, missing: ["terms_revision"] };
  }
  if ((toInt(binding.quote_revision) ?? 0) !== currentRevision) {
    return { ok: false, ...base, reason: R.STALE_REVISION };
  }

  return {
    ok: true,
    acceptance_allowed: true,
    reason: R.OK,
    state,
    current_revision: currentRevision,
    binding,
  };
}

// ---------------------------------------------------------------------------
// Customer request
// ---------------------------------------------------------------------------

/// Fields a customer may never assert. Their presence is rejected outright so
/// a client can never smuggle pricing authority into the lifecycle.
export const LIMOUSINE_FORBIDDEN_REQUEST_FIELDS = Object.freeze([
  "total_incl_vat_cents",
  "price_incl_vat",
  "price_ex_vat",
  "price_vat",
  "vat_rate",
  "vat_amount",
  "mobilisation_amount_cents",
  "mobilisation_fee_cents",
  "pricing_revision",
  "offer_source_revision",
  "pricing_section_revision",
  "readiness",
  "limousine_entitled",
  "company_readiness",
]);

export function itineraryFingerprint(request) {
  const r = asObject(request);
  const parts = [
    safeText(r.public_partner_id ?? r.publicPartnerId, 120),
    safeText(r.offer_id ?? r.offerId, 64),
    safeText(r.vehicle_id ?? r.vehicleId, 96),
    normalizeLimousineToken(r.journey_type),
    normalizeLimousineToken(r.direction),
    safeText(r.from, 240).toLowerCase(),
    safeText(r.to, 240).toLowerCase(),
    (Array.isArray(r.stops) ? r.stops : []).map((s) => safeText(s, 240).toLowerCase()).join(">"),
    safeText(r.scheduled_pickup_iso, 40),
    r.roundtrip === true ? "rt" : "ow",
    safeText(r.return_pickup_iso, 40),
    toInt(r.requested_duration_minutes) ?? "",
    toInt(r.pax) ?? "",
    toInt(r.bags) ?? "",
    safeText(r.occasion, 80).toLowerCase(),
    safeText(r.itinerary_endpoint_fingerprint, 160),
    (Array.isArray(r.selected_extra_ids) ? [...r.selected_extra_ids] : [])
      .map((e) => normalizeLimousineToken(e))
      .sort()
      .join(","),
  ];
  const raw = parts.join("~");
  let hash = 0x811c9dc5;
  for (let i = 0; i < raw.length; i++) {
    hash ^= raw.charCodeAt(i);
    hash = Math.imul(hash, 0x01000193) >>> 0;
  }
  return `limi_${hash.toString(16)}`;
}

/// Validates a customer manual-quote request. Only booking intent is accepted;
/// any pricing/readiness assertion is rejected.
function httpsOnly(raw) {
  const text = safeText(raw, 400);
  return text.startsWith("https://") ? text : "";
}

export function buildLimousinePublicVehicleSnapshot({
  offer = null,
  vehicleId = "",
  publishedVehicles = [],
} = {}) {
  const id = safeText(vehicleId, 96);
  if (!id) return null;
  const catalog = Array.isArray(publishedVehicles) ? publishedVehicles : [];
  const offerObj = asObject(offer);
  const offerVehicles = Array.isArray(offerObj.vehicles) ? offerObj.vehicles : [];
  const match = [...catalog, ...offerVehicles].find((item) => {
    const src = asObject(item);
    return normalizeLimousineToken(src.vehicle_id || src.vehicleId || src.id) ===
      normalizeLimousineToken(id);
  });
  const src = asObject(match) || asObject(offerObj.vehicle);
  const photo = httpsOnly(
    src.photo_url || src.photoUrl || src.primary_photo_url || offerObj.photo_url,
  );
  const name = safeText(
    src.name || src.display_name || src.displayName || src.brand_model,
    120,
  );
  return {
    vehicle_id: id,
    ...(name ? { public_name: name } : {}),
    ...(normalizeLimousineToken(src.service_class_id || src.serviceClassId || src.service_class || offerObj.service_class_id)
      ? {
          service_class_id: normalizeLimousineToken(
            src.service_class_id || src.serviceClassId || src.service_class || offerObj.service_class_id,
          ),
        }
      : {}),
    ...(photo ? { photo_url: photo } : {}),
    ...(toInt(src.passenger_capacity ?? src.pax ?? offerObj.passenger_capacity) != null
      ? { passenger_capacity: toInt(src.passenger_capacity ?? src.pax ?? offerObj.passenger_capacity) }
      : {}),
    ...(toInt(src.luggage_capacity ?? src.bags ?? offerObj.luggage_capacity) != null
      ? { luggage_capacity: toInt(src.luggage_capacity ?? src.bags ?? offerObj.luggage_capacity) }
      : {}),
  };
}

export function assertLimousinePublishedVehicle(vehicleId, publishedVehicles) {
  const catalog = Array.isArray(publishedVehicles) ? publishedVehicles : [];
  if (!catalog.length) return { ok: true };
  const id = normalizeLimousineToken(vehicleId);
  const found = catalog.find((item) => {
    const src = asObject(item);
    return normalizeLimousineToken(src.vehicle_id || src.vehicleId || src.id) === id;
  });
  if (!found) return { ok: false, reason: LIMOUSINE_QUOTE_REASONS.VEHICLE_NOT_PUBLISHED };
  const src = asObject(found);
  if (src.is_active === false || src.active === false || src.published === false || src.public === false) {
    return { ok: false, reason: LIMOUSINE_QUOTE_REASONS.VEHICLE_NOT_PUBLISHED };
  }
  return { ok: true, vehicle: src };
}

export function validateLimousineQuoteRequest(input, {
  eligible = false,
  offer = null,
  gateEnabled = false,
  publishedVehicles = [],
} = {}) {
  const R = LIMOUSINE_QUOTE_REASONS;
  const src = asObject(input);
  if (!gateEnabled) return { ok: false, reason: R.GATE_OFF };

  for (const forbidden of LIMOUSINE_FORBIDDEN_REQUEST_FIELDS) {
    if (src[forbidden] !== undefined) {
      return { ok: false, reason: R.CLIENT_PRICING_REJECTED, field: forbidden };
    }
  }
  if (!eligible) return { ok: false, reason: R.NOT_ELIGIBLE };

  const authoritativeOffer = asObject(offer);
  if (!authoritativeOffer.offer_id) return { ok: false, reason: R.UNKNOWN_OFFER };
  const published = assertLimousineOfferStillPublished(authoritativeOffer);
  if (!published.ok) return { ok: false, reason: R.OFFER_UNPUBLISHED };
  const classified = classifyLimousinePublishedPricingMode(authoritativeOffer);
  if (!classified.ok || classified.intent_kind !== LIMOUSINE_INTENT_KIND.QUOTE_REQUEST) {
    return { ok: false, reason: R.OFFER_NOT_BOOKABLE_MANUALLY };
  }
  const requestedJourney = normalizeLimousineToken(src.journey_type ?? src.journeyType);
  if (!offerAllowsPublishedJourneyType(authoritativeOffer, requestedJourney)) {
    return { ok: false, reason: R.JOURNEY_TYPE_NOT_ALLOWED, field: "journey_type" };
  }
  const clientVehicle = safeText(src.vehicle_id ?? src.vehicleId, 96);
  const vehicleScope = assertLimousineOfferVehicleScope(
    authoritativeOffer,
    clientVehicle || safeText(authoritativeOffer.vehicle_id, 96),
  );
  if (!vehicleScope.ok) {
    return { ok: false, reason: vehicleScope.reason, field: "vehicle_id" };
  }
  const publishedVehicle = assertLimousinePublishedVehicle(
    vehicleScope.vehicle_id,
    publishedVehicles,
  );
  if (!publishedVehicle.ok) {
    return { ok: false, reason: publishedVehicle.reason, field: "vehicle_id" };
  }

  const from = safeText(src.from, 240);
  const to = safeText(src.to, 240);
  const scheduled = safeText(src.scheduled_pickup_iso ?? src.scheduledPickupIso, 40);
  if (!from || !to || !scheduled) return { ok: false, reason: R.INVALID_REQUEST };

  // Extras must be authoritative, active and public on THIS offer.
  const selected = Array.isArray(src.selected_extra_ids ?? src.selectedExtraIds)
    ? Array.from(
        new Set(
          (src.selected_extra_ids ?? src.selectedExtraIds)
            .map((id) => normalizeLimousineToken(id))
            .filter((id) => id),
        ),
      )
    : [];
  const offerExtras = Array.isArray(authoritativeOffer.paid_extras)
    ? authoritativeOffer.paid_extras
    : [];
  let requiresManualExtra = false;
  for (const id of selected) {
    const extra = offerExtras.find((e) => normalizeLimousineToken(e.extra_id) === id);
    if (!extra || extra.active !== true || extra.public !== true) {
      return { ok: false, reason: R.INVALID_EXTRA, extra_id: id };
    }
    if (extra.quote_required === true) requiresManualExtra = true;
  }

  const request = {
    company_id: safeText(src.company_id ?? src.companyId, 96),
    public_partner_id: safeText(src.public_partner_id ?? src.publicPartnerId, 120),
    offer_id: authoritativeOffer.offer_id,
    service_class_id: normalizeLimousineToken(
      authoritativeOffer.service_class_id ?? src.service_class_id,
    ),
    vehicle_id: safeText(vehicleScope.vehicle_id || authoritativeOffer.vehicle_id || src.vehicle_id, 96),
    vehicle_snapshot: buildLimousinePublicVehicleSnapshot({
      offer: authoritativeOffer,
      vehicleId: safeText(vehicleScope.vehicle_id || authoritativeOffer.vehicle_id || src.vehicle_id, 96),
      publishedVehicles,
    }),
    journey_type: normalizeLimousineToken(src.journey_type ?? src.journeyType),
    direction: normalizeLimousineToken(src.direction ?? src.airport_direction),
    from,
    to,
    stops: (Array.isArray(src.stops) ? src.stops : [])
      .slice(0, 8)
      .map((s) => safeText(s, 240))
      .filter((s) => s),
    scheduled_pickup_iso: scheduled,
    roundtrip: src.roundtrip === true,
    return_pickup_iso: safeText(src.return_pickup_iso ?? src.returnPickupIso, 40),
    requested_duration_minutes: toInt(
      src.requested_duration_minutes ?? src.requestedDurationMinutes,
    ),
    pax: toInt(src.pax),
    bags: toInt(src.bags),
    selected_extra_ids: selected,
    customer_note: safeText(src.customer_note ?? src.customerNote, 500),
    occasion: safeText(src.occasion, 80),
    locale: normalizeLimousineToken(src.locale).slice(0, 8),
    requires_manual_extra: requiresManualExtra,
    service_type: LIMOUSINE_SERVICE_TYPE,
    pricing_mode: classified.pricing_mode,
    intent_kind: classified.intent_kind,
  };
  Object.assign(request, attachLimousineItineraryEndpoints(request, src));
  if (limousineItineraryConflictsWithJourney(request.journey_type, request)) {
    return { ok: false, reason: R.INVALID_REQUEST, field: "to_endpoint" };
  }
  request.itinerary_fingerprint = itineraryFingerprint(request);
  const snapshot = buildLimousineQuoteIntentSnapshot({
    offer: authoritativeOffer,
    request,
  });
  return { ok: true, request, snapshot: snapshot.ok ? snapshot : null };
}

/// Deterministic request identity so a retried submission is idempotent.
export function limousineQuoteRequestKey({ tenantId, companyId, customerRef, request }) {
  const parts = [
    safeText(tenantId, 96),
    safeText(companyId, 96),
    safeText(customerRef, 160).toLowerCase(),
    asObject(request).offer_id,
    asObject(request).itinerary_fingerprint,
  ];
  const raw = parts.join("~");
  let hash = 0x811c9dc5;
  for (let i = 0; i < raw.length; i++) {
    hash ^= raw.charCodeAt(i);
    hash = Math.imul(hash, 0x01000193) >>> 0;
  }
  return `limousine_quote:${safeText(tenantId, 96)}:${safeText(companyId, 96)}:${hash.toString(16)}`;
}

// ---------------------------------------------------------------------------
// Company response
// ---------------------------------------------------------------------------

/// Validates an authorized company quote. Amounts are integer cents only; no
/// internal cost, base address, driver or subscription data may be included.
export function validateLimousineCompanyQuote(input, { nowIso = null } = {}) {
  const R = LIMOUSINE_QUOTE_REASONS;
  const src = asObject(input);
  const totalCents = toInt(src.total_incl_vat_cents ?? src.totalInclVatCents);
  if (totalCents == null || totalCents <= 0) {
    return { ok: false, reason: R.INVALID_AMOUNT };
  }
  const currency = normalizeCurrency(src.currency);
  if (!currency) return { ok: false, reason: R.INVALID_CURRENCY };

  const termsCheck = validateLimousineTerms(src.terms);
  if (!termsCheck.valid) {
    if (termsCheck.unknown?.length) {
      return { ok: false, reason: R.UNKNOWN_CRITICAL_FIELD, unknown: termsCheck.unknown };
    }
    return { ok: false, reason: R.MISSING_TERMS, missing: termsCheck.missing };
  }

  const now = nowIso || new Date().toISOString();
  const expiresAt = safeText(src.expires_at ?? src.expiresAt, 40) ||
    new Date(Date.parse(now) + 48 * 3600 * 1000).toISOString();

  return {
    ok: true,
    quote: {
      total_incl_vat_cents: totalCents,
      currency,
      vat_treatment: safeText(src.vat_treatment ?? src.vatTreatment, 16) || "incl",
      vat_rate: Number(src.vat_rate ?? src.vatRate) || 0,
      vat_rate_source: safeText(src.vat_rate_source ?? src.vatRateSource, 64) || "company_quote",
      public_text: localized(src.public_text ?? src.publicText, 1200),
      included_services: termsCheck.terms.included_services,
      separately_priced_extras: termsCheck.terms.paid_extras,
      mobilisation_disclosure: termsCheck.terms.mobilisation_disclosure,
      terms: termsCheck.terms,
      terms_revision: termsCheck.terms.terms_revision,
      expires_at: expiresAt,
      quoted_at: now,
    },
  };
}

/// A company decline carries only a safe customer-visible reason.
export function buildLimousineDecline(input) {
  const src = asObject(input);
  return {
    reason_code: safeText(src.reason_code ?? src.reasonCode, 64) || "company_declined",
    public_text: localized(src.public_text ?? src.publicText, 600),
  };
}

// ---------------------------------------------------------------------------
// Acceptance binding
// ---------------------------------------------------------------------------

/// The exact facts a customer acceptance is bound to. Any change invalidates
/// the acceptance.
export function buildLimousineAcceptanceBinding(record) {
  const rec = asObject(record);
  const request = asObject(rec.request);
  const quote = asObject(rec.quote);
  return {
    tenant_id: safeText(rec.tenant_id, 96),
    company_id: safeText(rec.company_id, 96),
    quote_request_id: safeText(rec.quote_request_id, 120),
    quote_revision: toInt(rec.revision) ?? 0,
    total_incl_vat_cents: toInt(quote.total_incl_vat_cents) ?? 0,
    currency: normalizeCurrency(quote.currency),
    vat_treatment: safeText(quote.vat_treatment, 16),
    offer_id: safeText(request.offer_id, 64),
    offer_source_revision: toInt(rec.offer_source_revision) ?? 0,
    pricing_section_revision: toInt(rec.pricing_section_revision) ?? 0,
    itinerary_fingerprint: safeText(request.itinerary_fingerprint, 64),
    service_class_id: safeText(request.service_class_id, 64),
    vehicle_id: safeText(request.vehicle_id, 96),
    selected_extra_ids: Array.isArray(request.selected_extra_ids)
      ? [...request.selected_extra_ids].sort()
      : [],
    mobilisation_disclosure: asObject(quote.mobilisation_disclosure),
    terms_revision: toInt(quote.terms_revision) ?? 0,
    expires_at: safeText(quote.expires_at, 40),
  };
}

/// Guards customer acceptance: state, expiry, complete terms and revision.
export function assertLimousineQuoteAcceptable(record, {
  expectedRevision = null,
  nowIso = null,
} = {}) {
  const readiness = evaluateLimousineQuoteAcceptanceReadiness(record, { nowIso });
  if (!readiness.ok) {
    return {
      ok: false,
      reason: readiness.reason,
      state: readiness.state,
      missing: readiness.missing,
      unknown: readiness.unknown,
      current_revision: readiness.current_revision,
    };
  }
  if (expectedRevision != null) {
    const expected = toInt(expectedRevision);
    const currentRevision = toInt(asObject(record).revision) ?? 0;
    if (expected == null || expected !== currentRevision) {
      return {
        ok: false,
        reason: LIMOUSINE_QUOTE_REASONS.STALE_REVISION,
        current_revision: currentRevision,
      };
    }
  }
  return { ok: true, binding: buildLimousineAcceptanceBinding(record) };
}

// ---------------------------------------------------------------------------
// Audit trail (privacy-minimized, immutable)
// ---------------------------------------------------------------------------

/// Values that must never reach the audit trail.
export const LIMOUSINE_AUDIT_FORBIDDEN_KEYS = Object.freeze([
  "authorization",
  "headers",
  "cookie",
  "card",
  "cvc",
  "pan",
  "api_key",
  "secret",
  "token",
  "email",
  "phone",
  "customer_name",
  "operating_base_address",
  "internal_cost",
  "margin",
  "provider_payload",
]);

export function buildLimousineQuoteAuditEntry({
  from = "",
  to = "",
  revision = 0,
  actorType = "system",
  reasonCode = "",
  nowIso = null,
  amountCents = null,
  currency = "",
  termsRevision = null,
  bookingReference = "",
} = {}) {
  const allowedActors = ["customer", "company", "admin", "system"];
  const actor = allowedActors.includes(normalizeLimousineToken(actorType))
    ? normalizeLimousineToken(actorType)
    : "system";
  return {
    at: nowIso || new Date().toISOString(),
    actor_type: actor,
    from_state: normalizeLimousineToken(from),
    to_state: normalizeLimousineToken(to),
    revision: toInt(revision) ?? 0,
    ...(amountCents != null ? { amount_cents: toInt(amountCents) } : {}),
    ...(currency ? { currency: normalizeCurrency(currency) } : {}),
    ...(termsRevision != null ? { terms_revision: toInt(termsRevision) } : {}),
    ...(reasonCode ? { reason_code: safeText(reasonCode, 64) } : {}),
    ...(bookingReference ? { booking_reference: safeText(bookingReference, 64) } : {}),
  };
}

/// Appends immutably (never rewrites history) and bounds the trail length.
export function appendLimousineQuoteAudit(record, entry) {
  const rec = asObject(record);
  if (!entry) return rec;
  const trail = Array.isArray(rec.audit) ? rec.audit : [];
  return { ...rec, audit: [...trail, entry].slice(-100) };
}

/// Reads a "0"/"1" style server gate. Default OFF.
export function limousineManualQuoteGateEnabled(rawValue) {
  const token = normalizeLimousineToken(rawValue);
  return token === "1" || token === "true" || token === "yes" || token === "on";
}

/// Known quote-lifecycle state. Unknown filter values fail closed.
export function isLimousineQuoteState(value) {
  return Object.values(S).includes(normalizeLimousineToken(value));
}

/// Commercial company actions that a suspended company must not perform.
/// History reads and the non-commercial "viewed" ack stay allowed.
export function isLimousineCommercialCompanyAction(action) {
  const token = normalizeLimousineToken(action);
  return token === "quote" || token === "decline" || token === "withdraw";
}

/// Customer/request identity bound into the opaque status reference.
/// Does not include contact data — only scoped identifiers and the itinerary
/// fingerprint already stored on the request.
export function buildLimousineCustomerFingerprint({
  tenantId = "",
  companyId = "",
  customerRef = "",
  quoteRequestId = "",
  itineraryFingerprint = "",
} = {}) {
  const raw = [
    safeText(tenantId, 96),
    safeText(companyId, 96),
    safeText(customerRef, 160).toLowerCase(),
    safeText(quoteRequestId, 120),
    safeText(itineraryFingerprint, 64),
  ].join("~");
  let hash = 0x811c9dc5;
  for (let i = 0; i < raw.length; i++) {
    hash ^= raw.charCodeAt(i);
    hash = Math.imul(hash, 0x01000193) >>> 0;
  }
  return `limcf_${hash.toString(16)}`;
}

/// On-read expiry: if the company-set quote expiry has elapsed and the record
/// can still leave its current state, transition to `expired`. Already-expired
/// and terminal-preserved records are idempotent no-ops. Expired quotes cannot
/// re-enter an active state (the transition matrix forbids it).
export function observeLimousineQuoteExpiry(record, { nowIso = null } = {}) {
  const rec = asObject(record);
  const now = nowIso || new Date().toISOString();
  const state = normalizeLimousineToken(rec.state);
  if (state === S.EXPIRED) {
    return { ok: true, changed: false, reason: LIMOUSINE_QUOTE_REASONS.IDEMPOTENT_REPLAY, record: rec };
  }
  const quote = asObject(rec.quote);
  const expiry = Date.parse(safeText(quote.expires_at, 40));
  const nowMs = Date.parse(now);
  if (!Number.isFinite(expiry) || !Number.isFinite(nowMs) || nowMs <= expiry) {
    return { ok: true, changed: false, record: rec };
  }
  if (!canTransitionLimousineQuote(state, S.EXPIRED)) {
    return { ok: true, changed: false, reason: "terminal_preserved", record: rec };
  }
  return applyLimousineQuoteTransition(rec, {
    to: S.EXPIRED,
    expectedRevision: rec.revision,
    actorType: "system",
    reasonCode: "quote_expired",
    nowIso: now,
  });
}

/// Customer/company-safe projection of a manual-quote record. Never exposes
/// internal costs, the operating-base address, driver data, subscription
/// internals, audit, status tokens, itinerary fingerprints or raw payloads.
export function publicLimousineQuoteView(record, { nowIso = null } = {}) {
  const rec = asObject(record);
  const req = asObject(rec.request);
  const quote = rec.quote && typeof rec.quote === "object" && !Array.isArray(rec.quote)
    ? rec.quote
    : null;
  const readiness = evaluateLimousineQuoteAcceptanceReadiness(rec, { nowIso });
  const termsProjection = quote ? projectPublicLimousineQuoteTerms(quote) : null;
  return {
    quote_request_id: safeText(rec.quote_request_id, 120),
    state: safeText(rec.state, 40),
    revision: toInt(rec.revision) ?? 0,
    offer_id: safeText(req.offer_id, 64),
    service_class_id: safeText(req.service_class_id, 64),
    ...(req.vehicle_id ? { vehicle_id: safeText(req.vehicle_id, 96) } : {}),
    ...(req.vehicle_snapshot ? { vehicle_snapshot: asObject(req.vehicle_snapshot) } : {}),
    journey_type: safeText(req.journey_type, 32),
    service_type: LIMOUSINE_SERVICE_TYPE,
    ...(req.pricing_mode ? { pricing_mode: safeText(req.pricing_mode, 32) } : {}),
    ...(req.occasion ? { occasion: safeText(req.occasion, 80) } : {}),
    ...(rec.pricing_snapshot
      ? { pricing_snapshot: asObject(rec.pricing_snapshot) }
      : {}),
    scheduled_pickup_iso: safeText(req.scheduled_pickup_iso, 40),
    roundtrip: req.roundtrip === true,
    pax: toInt(req.pax),
    bags: toInt(req.bags),
    selected_extra_ids: Array.isArray(req.selected_extra_ids) ? req.selected_extra_ids : [],
    ...(quote
      ? {
          quote: {
            total_incl_vat_cents: toInt(quote.total_incl_vat_cents) ?? 0,
            currency: normalizeCurrency(quote.currency),
            vat_treatment: safeText(quote.vat_treatment, 16),
            vat_rate: Number(quote.vat_rate) || 0,
            public_text: asObject(quote.public_text),
            included_services: Array.isArray(quote.included_services) ? quote.included_services : [],
            separately_priced_extras: Array.isArray(quote.separately_priced_extras)
              ? quote.separately_priced_extras
              : [],
            mobilisation_disclosure: asObject(quote.mobilisation_disclosure),
            terms_revision: toInt(quote.terms_revision) ?? 0,
            expires_at: safeText(quote.expires_at, 40),
            quoted_at: safeText(quote.quoted_at, 40),
            terms: termsProjection.terms,
          },
        }
      : {}),
    ...(rec.decline ? { decline: rec.decline } : {}),
    ...(rec.booking_reference ? { booking_reference: safeText(rec.booking_reference, 64) } : {}),
    created_at: safeText(rec.created_at, 40),
    updated_at: safeText(rec.updated_at, 40),
    acceptance_allowed: readiness.acceptance_allowed === true,
    ...(readiness.acceptance_allowed
      ? {}
      : {
          acceptance_blocked_reason: readiness.reason,
          ...(readiness.missing?.length ? { missing_terms: readiness.missing } : {}),
        }),
    ...projectLimousineQuotationAvailability(rec),
  };
}

function companyQuoteIdentity(quote) {
  const q = asObject(quote);
  return JSON.stringify({
    total_incl_vat_cents: toInt(q.total_incl_vat_cents),
    currency: normalizeCurrency(q.currency),
    vat_treatment: safeText(q.vat_treatment, 16),
    vat_rate: Number(q.vat_rate) || 0,
    public_text: asObject(q.public_text),
    terms: normalizeLimousineTerms(q.terms),
    terms_revision: toInt(q.terms_revision) ?? 0,
    expires_at: safeText(q.expires_at, 40),
  });
}

function hasAuthoritativeCompanyQuote(quote) {
  const q = asObject(quote);
  return (toInt(q.total_incl_vat_cents) ?? 0) > 0 || (toInt(q.terms_revision) ?? 0) > 0;
}

/// Company quote / re-quote orchestrator. First quote and replacement of an
/// unaccepted quote both end at customer_acceptance_required. The live record
/// stays one document; superseded_revision records the replaced revision.
/// SUPERSEDED remains the terminal kill for the whole request.
export function applyLimousineCompanyQuoteAction(record, {
  expectedRevision = null,
  quote = null,
  nowIso = null,
} = {}) {
  const R = LIMOUSINE_QUOTE_REASONS;
  const rec = asObject(record);
  const state = normalizeLimousineToken(rec.state);
  const now = nowIso || new Date().toISOString();
  const nextQuote = asObject(quote);
  if ((toInt(nextQuote.total_incl_vat_cents) ?? 0) <= 0) {
    return { ok: false, reason: R.INVALID_AMOUNT };
  }
  if (!normalizeCurrency(nextQuote.currency)) {
    return { ok: false, reason: R.INVALID_CURRENCY };
  }

  const currentRevision = toInt(rec.revision) ?? 0;
  if (expectedRevision != null) {
    const expected = toInt(expectedRevision);
    if (expected == null || expected !== currentRevision) {
      return { ok: false, reason: R.STALE_REVISION, current_revision: currentRevision };
    }
  }

  const identical = hasAuthoritativeCompanyQuote(rec.quote)
    && companyQuoteIdentity(rec.quote) === companyQuoteIdentity(nextQuote);

  if (identical && state === S.CUSTOMER_ACCEPTANCE_REQUIRED) {
    return {
      ok: true,
      changed: false,
      reason: R.IDEMPOTENT_REPLAY,
      record: rec,
      audit: null,
      audits: [],
    };
  }

  if (state === S.ACCEPTED || isTerminalLimousineQuoteState(state)) {
    return { ok: false, reason: R.INVALID_TRANSITION, from: state, to: S.QUOTED };
  }

  const firstQuoteStates = new Set([S.REQUESTED, S.VIEWED_BY_COMPANY]);
  if (!firstQuoteStates.has(state) && state !== S.QUOTED && state !== S.CUSTOMER_ACCEPTANCE_REQUIRED) {
    return { ok: false, reason: R.INVALID_TRANSITION, from: state, to: S.QUOTED };
  }

  if (
    !identical
    && hasAuthoritativeCompanyQuote(rec.quote)
    && (state === S.QUOTED || state === S.CUSTOMER_ACCEPTANCE_REQUIRED)
  ) {
    const prevTermsRev = toInt(asObject(rec.quote).terms_revision) ?? 0;
    const nextTermsRev = toInt(nextQuote.terms_revision) ?? 0;
    if (nextTermsRev <= prevTermsRev) {
      return {
        ok: false,
        reason: R.STALE_TERMS_REVISION,
        current_terms_revision: prevTermsRev,
      };
    }
  }

  const audits = [];
  let current = rec;

  if (identical && state === S.QUOTED) {
    const awaiting = applyLimousineQuoteTransition(current, {
      to: S.CUSTOMER_ACCEPTANCE_REQUIRED,
      expectedRevision,
      actorType: "system",
      reasonCode: "awaiting_customer_acceptance",
      nowIso: now,
    });
    if (!awaiting.ok) return awaiting;
    return {
      ok: true,
      changed: awaiting.changed === true,
      reason: awaiting.changed ? R.OK : R.IDEMPOTENT_REPLAY,
      record: awaiting.record,
      audit: awaiting.audit,
      audits: awaiting.audit ? [awaiting.audit] : [],
    };
  }

  if (state === S.CUSTOMER_ACCEPTANCE_REQUIRED) {
    const requote = applyLimousineQuoteTransition(current, {
      to: S.QUOTED,
      expectedRevision,
      actorType: "company",
      reasonCode: "requoted",
      nowIso: now,
      patch: {
        quote: nextQuote,
        superseded_revision: current.revision,
      },
    });
    if (!requote.ok) return requote;
    current = requote.record;
    if (requote.audit) audits.push(requote.audit);
  } else if (firstQuoteStates.has(state)) {
    const quoted = applyLimousineQuoteTransition(current, {
      to: S.QUOTED,
      expectedRevision,
      actorType: "company",
      reasonCode: "quoted",
      nowIso: now,
      patch: { quote: nextQuote },
    });
    if (!quoted.ok) return quoted;
    current = quoted.record;
    if (quoted.audit) audits.push(quoted.audit);
  } else if (state === S.QUOTED) {
    const awaiting = applyLimousineQuoteTransition(current, {
      to: S.CUSTOMER_ACCEPTANCE_REQUIRED,
      expectedRevision,
      actorType: "company",
      reasonCode: "requoted",
      nowIso: now,
      patch: {
        quote: nextQuote,
        superseded_revision: current.revision,
      },
    });
    if (!awaiting.ok) return awaiting;
    return {
      ok: true,
      changed: true,
      reason: R.OK,
      record: awaiting.record,
      audit: awaiting.audit,
      audits: awaiting.audit ? [awaiting.audit] : [],
    };
  }

  const awaiting = applyLimousineQuoteTransition(current, {
    to: S.CUSTOMER_ACCEPTANCE_REQUIRED,
    actorType: "system",
    reasonCode: "awaiting_customer_acceptance",
    nowIso: now,
  });
  if (!awaiting.ok) return awaiting;
  if (awaiting.changed && awaiting.audit) audits.push(awaiting.audit);
  return {
    ok: true,
    changed: true,
    reason: R.OK,
    record: awaiting.changed ? awaiting.record : current,
    audit: audits[audits.length - 1] || null,
    audits,
  };
}
