// LIMOUSINE-UNIFIED-BOOKING-P3A — one canonical price/intent contract.
//
// Limousine is only `service_type = limousine` inside the existing Fluxidi
// quote + /book aggregates. This module classifies the five published price
// modes and builds immutable snapshots. It never invents a second datastore,
// inbox, booking aggregate or status machine.
//
// Client tenant/company/partner IDs and client totals are ignored.

import { normalizeLimousineToken } from "./limousine_provider_eligibility.mjs";
import { computeOfferHourlyCents } from "./limousine_pricing_resolver.mjs";
import { LIMOUSINE_PRICE_PRESENTATIONS } from "./limousine_offers.mjs";

export const LIMOUSINE_SERVICE_TYPE = "limousine";

export const LIMOUSINE_PUBLISHED_PRICING_MODES = Object.freeze({
  QUOTE_REQUIRED: "quote_required",
  FROM_PRICE: "from_price",
  EXACT_FIXED: "exact_fixed",
  HOURLY: "hourly",
  PACKAGE: "package",
});

export const LIMOUSINE_INTENT_KIND = Object.freeze({
  QUOTE_REQUEST: "quote_request",
  BOOKING_REQUEST: "booking_request",
});

export const LIMOUSINE_UNIFIED_REASONS = Object.freeze({
  OK: "ok",
  UNAVAILABLE: "unavailable",
  OFFER_UNPUBLISHED: "offer_unpublished",
  UNKNOWN_OFFER: "unknown_offer",
  VEHICLE_SCOPE_MISMATCH: "vehicle_scope_mismatch",
  VEHICLE_NOT_PUBLISHED: "vehicle_not_published",
  MANUAL_QUOTE_REQUIRED: "manual_quote_required",
  NOT_DIRECTLY_BOOKABLE: "not_directly_bookable",
  INVALID_DURATION: "invalid_duration",
  PACKAGE_OVERAGE_RULE_MISSING: "package_overage_rule_missing",
  CLIENT_PRICING_REJECTED: "client_pricing_rejected",
  STALE_OFFER: "stale_offer",
});

const M = LIMOUSINE_PUBLISHED_PRICING_MODES;
const I = LIMOUSINE_INTENT_KIND;
const R = LIMOUSINE_UNIFIED_REASONS;
const P = LIMOUSINE_PRICE_PRESENTATIONS;

const ISO_CURRENCY = /^[A-Z]{3}$/;

function asObject(raw) {
  return raw && typeof raw === "object" && !Array.isArray(raw) ? raw : {};
}

function toInt(value) {
  const n = Number(value);
  return Number.isFinite(n) ? Math.trunc(n) : null;
}

function normalizeCurrency(value) {
  const c = String(value ?? "").trim().toUpperCase();
  return ISO_CURRENCY.test(c) ? c : "";
}

function safeText(value, max) {
  return String(value ?? "").trim().slice(0, max);
}

function localized(raw, max = 240) {
  const src = asObject(raw);
  const out = {};
  for (const lang of ["nl", "en", "fr", "es"]) {
    const text = safeText(src[lang], max);
    if (text) out[lang] = text;
  }
  return out;
}

function offerVehicleIds(offer) {
  const o = asObject(offer);
  const raw = Array.isArray(o.vehicle_ids) && o.vehicle_ids.length
    ? o.vehicle_ids
    : o.vehicle_id
      ? [o.vehicle_id]
      : [];
  return raw.map((id) => safeText(id, 96)).filter((id) => id);
}

function hourlyBlock(offer) {
  return asObject(asObject(offer).hourly);
}

function packageConfigured(hourly) {
  const amount = toInt(hourly.package_amount_cents);
  const duration = toInt(hourly.package_duration_minutes);
  return amount != null && amount > 0 && duration != null && duration > 0;
}

/// Maps a published offer onto one of the five product price modes.
/// Hourly/package win over presentation so a hire offer is never CTA-less.
export function classifyLimousinePublishedPricingMode(offer) {
  const o = asObject(offer);
  if (!o.offer_id && !o.offerId) {
    return { ok: false, reason: R.UNKNOWN_OFFER };
  }
  const presentation = normalizeLimousineToken(
    o.price_presentation ?? o.pricePresentation,
  );
  if (presentation === P.UNAVAILABLE) {
    return { ok: false, reason: R.UNAVAILABLE, pricing_mode: P.UNAVAILABLE };
  }
  const hourly = hourlyBlock(o);
  const hourlyOn = hourly.enabled === true;
  if (hourlyOn && packageConfigured(hourly)) {
    return {
      ok: true,
      pricing_mode: M.PACKAGE,
      intent_kind: I.BOOKING_REQUEST,
    };
  }
  if (hourlyOn) {
    return {
      ok: true,
      pricing_mode: M.HOURLY,
      intent_kind: I.BOOKING_REQUEST,
    };
  }
  if (presentation === P.EXACT_FIXED) {
    return {
      ok: true,
      pricing_mode: M.EXACT_FIXED,
      intent_kind: I.BOOKING_REQUEST,
    };
  }
  if (presentation === P.FROM_PRICE || presentation === P.INDICATIVE) {
    return {
      ok: true,
      pricing_mode: M.FROM_PRICE,
      intent_kind: I.QUOTE_REQUEST,
    };
  }
  return {
    ok: true,
    pricing_mode: M.QUOTE_REQUIRED,
    intent_kind: I.QUOTE_REQUEST,
  };
}

export function limousineIntentKindForPricingMode(pricingMode) {
  const mode = normalizeLimousineToken(pricingMode);
  if (mode === M.EXACT_FIXED || mode === M.HOURLY || mode === M.PACKAGE) {
    return I.BOOKING_REQUEST;
  }
  return I.QUOTE_REQUEST;
}

/// Vehicle-targeted offers must bind the selected vehicle. Class offers may
/// omit a vehicle. Wrong scope fails closed.
export function assertLimousineOfferVehicleScope(offer, selectedVehicleId) {
  const o = asObject(offer);
  const bound = offerVehicleIds(o);
  const target = normalizeLimousineToken(o.target_type ?? o.targetType);
  const selected = safeText(selectedVehicleId, 96);
  if (target === "vehicle" || bound.length) {
    if (!selected) return { ok: false, reason: R.VEHICLE_SCOPE_MISMATCH };
    const allowed = new Set(bound.map((id) => normalizeLimousineToken(id)));
    if (!allowed.has(normalizeLimousineToken(selected))) {
      return { ok: false, reason: R.VEHICLE_SCOPE_MISMATCH };
    }
  }
  return { ok: true, vehicle_id: selected || bound[0] || "" };
}

export function assertLimousineOfferStillPublished(offer) {
  const o = asObject(offer);
  if (!o.offer_id && !o.offerId) return { ok: false, reason: R.UNKNOWN_OFFER };
  if (o.enabled !== true || o.published !== true) {
    return { ok: false, reason: R.OFFER_UNPUBLISHED };
  }
  return { ok: true };
}

/// Optional client revision is compared only when the customer actually sent
/// one. The server always freezes the current published revision.
export function assertLimousineOfferRevisionFresh(offer, expectedRevision) {
  const current = toInt(asObject(offer).source_revision) ?? 0;
  const expected = toInt(expectedRevision);
  if (expected == null) return { ok: true, offer_source_revision: current };
  if (expected !== current) return { ok: false, reason: R.STALE_OFFER };
  return { ok: true, offer_source_revision: current };
}

export function rejectLimousineClientPricingAuthority(input) {
  const src = asObject(input);
  const forbidden = [
    "total_incl_vat_cents",
    "price_incl_vat",
    "price_ex_vat",
    "price_vat",
    "vat_amount",
    "taxi_price",
    "display_total_cents",
  ];
  for (const field of forbidden) {
    if (src[field] !== undefined) {
      return { ok: false, reason: R.CLIENT_PRICING_REJECTED, field };
    }
  }
  return { ok: true };
}

/// Existing published hourly contract: first hour + additional started hours,
/// after `billable = max(selected, minimum)`. Integer cents only.
export function computeLimousineHourlyHireSnapshot(hourlyRaw, requestedMinutes) {
  const hourly = asObject(hourlyRaw);
  const requested = toInt(requestedMinutes);
  const minimum = toInt(hourly.minimum_duration_minutes);
  const step = toInt(hourly.duration_step_minutes);
  if (requested == null || requested <= 0) {
    return { ok: false, reason: R.INVALID_DURATION };
  }
  if (minimum == null || minimum <= 0) {
    return { ok: false, reason: R.INVALID_DURATION };
  }
  if (step != null && step > 0 && requested % step !== 0) {
    return { ok: false, reason: R.INVALID_DURATION };
  }
  const cents = computeOfferHourlyCents(hourly, requested);
  if (cents == null) return { ok: false, reason: R.MANUAL_QUOTE_REQUIRED };
  const billable = Math.max(requested, minimum);
  return {
    ok: true,
    pricing_mode: M.HOURLY,
    selected_duration_minutes: requested,
    minimum_duration_minutes: minimum,
    billable_duration_minutes: billable,
    first_hour_cents: toInt(hourly.first_hour_cents),
    additional_hour_cents: toInt(hourly.additional_hour_cents),
    duration_step_minutes: step,
    amount_cents: cents,
    currency: normalizeCurrency(hourly.currency),
  };
}

export function computeLimousinePackageSnapshot(offer, requestedMinutes) {
  const o = asObject(offer);
  const hourly = hourlyBlock(o);
  if (!packageConfigured(hourly)) {
    return { ok: false, reason: R.MANUAL_QUOTE_REQUIRED };
  }
  const requested = toInt(requestedMinutes);
  const included = toInt(hourly.package_duration_minutes);
  const amount = toInt(hourly.package_amount_cents);
  if (requested == null || requested <= 0) {
    return { ok: false, reason: R.INVALID_DURATION };
  }
  if (requested > included) {
    const excess = toInt(hourly.excess_hour_cents);
    if (excess == null || excess < 0) {
      return { ok: false, reason: R.PACKAGE_OVERAGE_RULE_MISSING };
    }
  }
  const includedDistance = toInt(
    hourly.included_distance_km ?? o.included_distance_km,
  );
  return {
    ok: true,
    pricing_mode: M.PACKAGE,
    package_name: localized(o.title ?? o.package_name),
    included_duration_minutes: included,
    ...(includedDistance != null ? { included_distance_km: includedDistance } : {}),
    included_services: Array.isArray(o.included_services) ? o.included_services : [],
    vehicle_scope: offerVehicleIds(o),
    extras: Array.isArray(o.paid_extras) ? o.paid_extras : [],
    overage_rules: {
      excess_hour_cents: toInt(hourly.excess_hour_cents),
      excess_km_cents: toInt(hourly.excess_km_cents),
    },
    selected_duration_minutes: requested,
    package_amount_cents: amount,
    currency: normalizeCurrency(hourly.currency || o.currency),
    amount_cents: amount,
  };
}

/// Passenger Mapbox is required only when the published offer prices a route.
export function limousineBookingRequestNeedsPassengerRoute(offer, journeyType) {
  const classified = classifyLimousinePublishedPricingMode(offer);
  if (classified.pricing_mode === M.HOURLY || classified.pricing_mode === M.PACKAGE) {
    return false;
  }
  const type = normalizeLimousineToken(journeyType);
  if (type === "hourly_package") return false;
  const o = asObject(offer);
  const rules = Array.isArray(o.fixed_rules) ? o.fixed_rules : [];
  const matchingFixed = rules.some((rule) => {
    const r = asObject(rule);
    return r.enabled === true && (!r.journey_type || normalizeLimousineToken(r.journey_type) === type);
  });
  if (matchingFixed) return false;
  return asObject(o.distance_time).enabled === true || classified.pricing_mode === M.EXACT_FIXED;
}

export function buildLimousineQuoteIntentSnapshot({
  offer,
  request = {},
  pricingSectionRevision = 0,
} = {}) {
  const classified = classifyLimousinePublishedPricingMode(offer);
  if (!classified.ok) return { ok: false, reason: classified.reason };
  if (classified.intent_kind !== I.QUOTE_REQUEST) {
    return { ok: false, reason: R.NOT_DIRECTLY_BOOKABLE };
  }
  const o = asObject(offer);
  const currency = normalizeCurrency(o.currency);
  const shown = toInt(o.display_amount_cents);
  return {
    ok: true,
    service_type: LIMOUSINE_SERVICE_TYPE,
    intent_kind: I.QUOTE_REQUEST,
    pricing_mode: classified.pricing_mode,
    offer_id: safeText(o.offer_id || o.offerId, 64),
    vehicle_id: safeText(o.vehicle_id || request.vehicle_id, 96),
    offer_source_revision: toInt(o.source_revision) ?? 0,
    pricing_section_revision: toInt(pricingSectionRevision) ?? 0,
    currency,
    guaranteed: false,
    payable: false,
    invoiceable: false,
    ...(classified.pricing_mode === M.FROM_PRICE && shown != null && shown > 0
      ? { shown_from_price_cents: shown, shown_from_price_guaranteed: false }
      : {}),
    occasion: safeText(request.occasion, 80),
    scheduled_pickup_iso: safeText(request.scheduled_pickup_iso, 40),
    selected_extra_ids: Array.isArray(request.selected_extra_ids)
      ? request.selected_extra_ids
      : [],
  };
}

export function enrichLimousineAcceptedSnapshot(snapshot, {
  offer,
  request = {},
  hourlyHire = null,
  packageHire = null,
  companyConfirmationRequired = true,
} = {}) {
  const base = asObject(snapshot);
  if (!base.offer_id && !base.total_incl_vat_cents) return base;
  const classified = classifyLimousinePublishedPricingMode(offer);
  return {
    ...base,
    service_type: LIMOUSINE_SERVICE_TYPE,
    service_category: LIMOUSINE_SERVICE_TYPE,
    published_pricing_mode: classified.ok ? classified.pricing_mode : base.pricing_mode,
    intent_kind: I.BOOKING_REQUEST,
    company_confirmation_required: companyConfirmationRequired === true,
    occasion: safeText(request.occasion ?? base.occasion, 80),
    customer_note: safeText(request.customer_note ?? request.customerNote, 500),
    requested_duration_minutes: toInt(
      request.requested_duration_minutes ?? request.requestedDurationMinutes,
    ),
    ...(hourlyHire && hourlyHire.ok
      ? {
          hourly_hire: {
            selected_duration_minutes: hourlyHire.selected_duration_minutes,
            minimum_duration_minutes: hourlyHire.minimum_duration_minutes,
            billable_duration_minutes: hourlyHire.billable_duration_minutes,
            first_hour_cents: hourlyHire.first_hour_cents,
            additional_hour_cents: hourlyHire.additional_hour_cents,
            amount_cents: hourlyHire.amount_cents,
          },
        }
      : {}),
    ...(packageHire && packageHire.ok
      ? {
          package_hire: {
            package_name: packageHire.package_name,
            included_duration_minutes: packageHire.included_duration_minutes,
            ...(packageHire.included_distance_km != null
              ? { included_distance_km: packageHire.included_distance_km }
              : {}),
            included_services: packageHire.included_services,
            vehicle_scope: packageHire.vehicle_scope,
            overage_rules: packageHire.overage_rules,
            package_amount_cents: packageHire.package_amount_cents,
          },
        }
      : {}),
  };
}

/// PDF/Command Center lines from an existing booking snapshot. Same document
/// pipeline; no second PDF service.
export function limousineDocumentLinesFromSnapshot(snapshot) {
  const s = asObject(snapshot);
  if (s.service_type !== LIMOUSINE_SERVICE_TYPE && s.service_category !== LIMOUSINE_SERVICE_TYPE) {
    return [];
  }
  const lines = ["Limousine"];
  if (s.offer_id) lines.push(`Aanbod ${s.offer_id}`);
  if (s.vehicle_id) lines.push(`Voertuig ${s.vehicle_id}`);
  if (s.published_pricing_mode || s.pricing_mode) {
    lines.push(`Prijsmodus ${s.published_pricing_mode || s.pricing_mode}`);
  }
  const pack = asObject(s.package_hire);
  if (pack.package_amount_cents != null) {
    lines.push(`Arrangement ${pack.included_duration_minutes || ""} min`);
  }
  const hourly = asObject(s.hourly_hire);
  if (hourly.billable_duration_minutes != null) {
    lines.push(`Duur ${hourly.billable_duration_minutes} min`);
  }
  if (s.occasion) lines.push(`Gelegenheid ${s.occasion}`);
  if (s.currency && s.total_incl_vat_cents != null) {
    lines.push(`${s.currency} ${(Number(s.total_incl_vat_cents) / 100).toFixed(2)}`);
  }
  return lines;
}
