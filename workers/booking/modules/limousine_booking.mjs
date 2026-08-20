// LIMOUSINE-MARKETPLACE-P2C1 — authoritative Limousine totals, quote result,
// /book recompute-and-compare and the accepted-price snapshot.
//
// Pure and fully testable. It never calculates a route itself: the caller must
// pass SERVER-computed route results. It never reads a client total, never
// falls back to taxi pricing and never uses the street meter.
//
// All money is integer minor units (cents). The final customer total is rounded
// exactly once with the shared Fluxidi €0.10 leg finalizer.

import { finalizeLegPricingInclVat } from "./leg_pricing_finalize.mjs";
import {
  LIMOUSINE_MOBILISATION_METHODS,
  LIMOUSINE_PRICE_PRESENTATIONS,
  normalizeLimousineOffer,
  offerCanProduceResolvedPrice,
  offerSupportedPricingModes,
  selectLimousineOfferForRequest,
} from "./limousine_offers.mjs";
import { normalizeLimousineToken } from "./limousine_provider_eligibility.mjs";
import {
  computeOfferHourlyCents,
  normalizeLimousinePricingSection,
} from "./limousine_pricing_resolver.mjs";

export const LIMOUSINE_COMPONENT_TYPES = Object.freeze({
  MAIN_JOURNEY: "main_journey",
  RETURN_JOURNEY: "return_journey",
  HOURLY_PACKAGE: "hourly_package",
  EXCESS_HOURS: "excess_hours",
  PAID_EXTRA: "paid_extra",
  MOBILISATION_OUTBOUND: "mobilisation_outbound",
  MOBILISATION_RETURN: "mobilisation_return",
});

export const LIMOUSINE_BOOK_REASONS = Object.freeze({
  OK: "ok",
  BOOK_GATE_OFF: "book_gate_off",
  NOT_ELIGIBLE: "not_eligible",
  UNKNOWN_OFFER: "unknown_offer",
  OFFER_DISABLED: "offer_disabled",
  NOT_DIRECTLY_BOOKABLE: "not_directly_bookable",
  MANUAL_QUOTE_REQUIRED: "manual_quote_required",
  UNAVAILABLE: "unavailable",
  ROUTE_FAILED: "route_failed",
  CURRENCY_MISMATCH: "currency_mismatch",
  INVALID_EXTRA: "invalid_extra",
  MOBILISATION_INCOMPLETE: "mobilisation_incomplete",
  MAX_DURATION_EXCEEDED: "max_duration_exceeded",
  STALE_REVISION: "stale_revision",
  QUOTE_MISMATCH: "quote_refresh_required",
  MISSING_QUOTE_REFERENCE: "missing_quote_reference",
});

function asObject(raw) {
  return raw && typeof raw === "object" && !Array.isArray(raw) ? raw : {};
}

function toInt(value) {
  const n = Number(value);
  return Number.isFinite(n) ? Math.trunc(n) : null;
}

function normalizeCurrency(value) {
  const c = String(value ?? "").trim().toUpperCase();
  return /^[A-Z]{3}$/.test(c) ? c : "";
}

function routeIsUsable(route) {
  const r = asObject(route);
  return Number.isFinite(Number(r.distance_km)) && Number.isFinite(Number(r.duration_min));
}

function component({ type, reference, amountCents, currency, vatRate, pricingSource, sourceRevision }) {
  return {
    type,
    reference: String(reference ?? ""),
    amount_cents: toInt(amountCents) ?? 0,
    currency,
    vat_rate: Number(vatRate) || 0,
    pricing_source: pricingSource,
    source_revision: toInt(sourceRevision) ?? 0,
  };
}

function failed(reason, extra = {}) {
  const manual = reason === LIMOUSINE_BOOK_REASONS.MANUAL_QUOTE_REQUIRED;
  return {
    ok: false,
    manual_quote_required: manual,
    unavailable: !manual,
    reason,
    components: [],
    ...extra,
  };
}

// ---------------------------------------------------------------------------
// Fixed-journey matching (offer scoped)
// ---------------------------------------------------------------------------

function ruleActive(rule, nowMs) {
  const now = Number.isFinite(nowMs) ? nowMs : Date.now();
  if (rule.active_from_ms && now < rule.active_from_ms) return false;
  if (rule.active_until_ms && now > rule.active_until_ms) return false;
  return true;
}

function matchFixedRule(offer, { journeyType, direction, airportIata, nowMs }) {
  const wantedDirection = normalizeLimousineToken(direction);
  const wantedIata = String(airportIata ?? "").trim().toUpperCase();
  const candidates = offer.fixed_rules.filter((rule) => {
    if (!rule.enabled) return false;
    if (rule.amount_cents == null || rule.amount_cents <= 0) return false;
    if (rule.journey_type !== journeyType) return false;
    if (journeyType === "airport_transfer") {
      if (!rule.airport_iata || !wantedIata || rule.airport_iata !== wantedIata) return false;
      if (rule.direction && rule.direction !== "both" && rule.direction !== wantedDirection) {
        return false;
      }
    }
    if (!ruleActive(rule, nowMs)) return false;
    return true;
  });
  if (candidates.length === 0) return { rule: null, ambiguous: false };
  if (candidates.length > 1) {
    const distinct = new Set(candidates.map((r) => r.rule_id));
    if (distinct.size !== candidates.length) return { rule: null, ambiguous: true };
  }
  const sorted = [...candidates].sort((a, b) =>
    String(a.rule_id).localeCompare(String(b.rule_id)),
  );
  return { rule: sorted[0], ambiguous: false };
}

// ---------------------------------------------------------------------------
// Mobilisation
// ---------------------------------------------------------------------------

/// Mobilisation is priced separately from the passenger itinerary:
///   operating base -> pickup -> customer route -> operating base
/// The private base address never leaves the Worker; only an itemized amount
/// and a safe disclosure are returned.
function mobilisationComponents(offer, { routes, currency, nowMsUnused }) {
  const mob = asObject(offer.mobilisation);
  const method = normalizeLimousineToken(mob.method);
  const outboundCharged = mob.outbound_charged === true;
  const returnCharged = mob.return_charged === true;
  const out = [];

  if (!outboundCharged && !returnCharged) {
    // Included (or simply not charged) => €0, no component rows.
    if (method && method !== LIMOUSINE_MOBILISATION_METHODS.INCLUDED) {
      // A configured method with nothing charged is still €0, not an error.
      return { ok: true, components: [] };
    }
    return { ok: true, components: [] };
  }

  if (!method || method === LIMOUSINE_MOBILISATION_METHODS.INCLUDED) {
    // Charged but "included" is contradictory.
    return { ok: false, reason: LIMOUSINE_BOOK_REASONS.MOBILISATION_INCOMPLETE };
  }
  if (mob.currency && normalizeCurrency(mob.currency) !== currency) {
    return { ok: false, reason: LIMOUSINE_BOOK_REASONS.CURRENCY_MISMATCH };
  }

  if (method === LIMOUSINE_MOBILISATION_METHODS.FIXED_FEE) {
    const fee = toInt(mob.fee_cents);
    if (fee == null || fee <= 0) {
      return { ok: false, reason: LIMOUSINE_BOOK_REASONS.MOBILISATION_INCOMPLETE };
    }
    if (outboundCharged) {
      out.push(
        component({
          type: LIMOUSINE_COMPONENT_TYPES.MOBILISATION_OUTBOUND,
          reference: `${offer.offer_id}:mobilisation:fixed_fee`,
          amountCents: fee,
          currency,
          vatRate: 0,
          pricingSource: "limousine_mobilisation_fixed_fee",
          sourceRevision: offer.source_revision,
        }),
      );
    }
    if (returnCharged) {
      out.push(
        component({
          type: LIMOUSINE_COMPONENT_TYPES.MOBILISATION_RETURN,
          reference: `${offer.offer_id}:mobilisation:fixed_fee`,
          amountCents: fee,
          currency,
          vatRate: 0,
          pricingSource: "limousine_mobilisation_fixed_fee",
          sourceRevision: offer.source_revision,
        }),
      );
    }
    return { ok: true, components: out };
  }

  if (method === LIMOUSINE_MOBILISATION_METHODS.DISTANCE_TIME) {
    const dt = asObject(offer.distance_time);
    const complete =
      dt.enabled === true &&
      toInt(dt.per_km_incl_vat_cents) != null &&
      toInt(dt.per_minute_incl_vat_cents) != null &&
      normalizeCurrency(dt.currency) === currency;
    if (!complete) {
      return { ok: false, reason: LIMOUSINE_BOOK_REASONS.MOBILISATION_INCOMPLETE };
    }
    const includedKm = Number(mob.included_distance_km) || 0;
    const includedMin = toInt(mob.included_minutes) ?? 0;
    const price = (legRoute, type) => {
      if (!routeIsUsable(legRoute)) {
        return { ok: false, reason: LIMOUSINE_BOOK_REASONS.MOBILISATION_INCOMPLETE };
      }
      const km = Math.max(0, Number(legRoute.distance_km) - includedKm);
      const min = Math.max(0, Number(legRoute.duration_min) - includedMin);
      const cents =
        Math.round(km * toInt(dt.per_km_incl_vat_cents)) +
        Math.round(min * toInt(dt.per_minute_incl_vat_cents));
      return {
        ok: true,
        row: component({
          type,
          reference: `${offer.offer_id}:mobilisation:distance_time`,
          amountCents: cents,
          currency,
          vatRate: dt.vat_rate,
          pricingSource: "limousine_mobilisation_distance_time",
          sourceRevision: offer.source_revision,
        }),
      };
    };
    if (outboundCharged) {
      const r = price(routes?.mobilisation_outbound, LIMOUSINE_COMPONENT_TYPES.MOBILISATION_OUTBOUND);
      if (!r.ok) return { ok: false, reason: r.reason };
      out.push(r.row);
    }
    if (returnCharged) {
      const r = price(routes?.mobilisation_return, LIMOUSINE_COMPONENT_TYPES.MOBILISATION_RETURN);
      if (!r.ok) return { ok: false, reason: r.reason };
      out.push(r.row);
    }
    return { ok: true, components: out };
  }

  return { ok: false, reason: LIMOUSINE_BOOK_REASONS.MOBILISATION_INCOMPLETE };
}

/// Safe customer-facing mobilisation statement. Never the base address.
export function safeMobilisationDisclosure(offer) {
  const mob = asObject(offer?.mobilisation);
  const charged = mob.outbound_charged === true || mob.return_charged === true;
  return {
    included: !charged,
    charged_separately: charged,
    disclosure: asObject(mob.disclosure),
  };
}

// ---------------------------------------------------------------------------
// Paid extras
// ---------------------------------------------------------------------------

function extraComponents(offer, selectedExtraIds, currency) {
  const ids = Array.isArray(selectedExtraIds)
    ? Array.from(new Set(selectedExtraIds.map((id) => normalizeLimousineToken(id)).filter((i) => i)))
    : [];
  if (ids.length === 0) return { ok: true, components: [], labels: [] };
  const out = [];
  const labels = [];
  for (const id of ids) {
    const extra = offer.paid_extras.find((e) => normalizeLimousineToken(e.extra_id) === id);
    // Unknown, inactive or non-public extras fail closed.
    if (!extra || extra.active !== true || extra.public !== true) {
      return { ok: false, reason: LIMOUSINE_BOOK_REASONS.INVALID_EXTRA };
    }
    // A quote-required extra makes the whole request manual.
    if (extra.quote_required === true) {
      return { ok: false, reason: LIMOUSINE_BOOK_REASONS.MANUAL_QUOTE_REQUIRED };
    }
    if (extra.currency && normalizeCurrency(extra.currency) !== currency) {
      return { ok: false, reason: LIMOUSINE_BOOK_REASONS.CURRENCY_MISMATCH };
    }
    const amount = toInt(extra.amount_cents);
    if (amount == null || amount < 0) {
      return { ok: false, reason: LIMOUSINE_BOOK_REASONS.INVALID_EXTRA };
    }
    out.push(
      component({
        type: LIMOUSINE_COMPONENT_TYPES.PAID_EXTRA,
        reference: `${offer.offer_id}:extra:${extra.extra_id}`,
        amountCents: amount,
        currency,
        vatRate: 0,
        pricingSource: "limousine_paid_extra",
        sourceRevision: offer.source_revision,
      }),
    );
    labels.push({ extra_id: extra.extra_id, label: asObject(extra.label) });
  }
  return { ok: true, components: out, labels };
}

// ---------------------------------------------------------------------------
// Journey pricing (one leg)
// ---------------------------------------------------------------------------

function priceJourneyLeg(offer, { journeyType, direction, airportIata, route, requestedDurationMinutes, currency, nowMs, componentType }) {
  // 1) Fixed journey rule.
  const { rule, ambiguous } = matchFixedRule(offer, {
    journeyType,
    direction,
    airportIata,
    nowMs,
  });
  if (ambiguous) return { ok: false, reason: LIMOUSINE_BOOK_REASONS.UNAVAILABLE };
  if (rule) {
    if (rule.currency && normalizeCurrency(rule.currency) !== currency) {
      return { ok: false, reason: LIMOUSINE_BOOK_REASONS.CURRENCY_MISMATCH };
    }
    return {
      ok: true,
      pricing_mode: "fixed_route_or_airport_fare",
      components: [
        component({
          type: componentType,
          reference: `${offer.offer_id}:${rule.rule_id}`,
          amountCents: rule.amount_cents,
          currency,
          vatRate: rule.vat_rate,
          pricingSource: "limousine_fixed_fare",
          sourceRevision: offer.source_revision,
        }),
      ],
    };
  }

  // 2) Hourly hire / package (only for an hourly journey).
  if (journeyType === "hourly_package") {
    const hourly = asObject(offer.hourly);
    if (hourly.enabled !== true) {
      return { ok: false, reason: LIMOUSINE_BOOK_REASONS.UNAVAILABLE };
    }
    if (hourly.currency && normalizeCurrency(hourly.currency) !== currency) {
      return { ok: false, reason: LIMOUSINE_BOOK_REASONS.CURRENCY_MISMATCH };
    }
    const requested = Math.max(0, toInt(requestedDurationMinutes) ?? 0);
    const maximum = toInt(hourly.maximum_duration_minutes);
    if (maximum != null && maximum > 0 && requested > maximum) {
      return { ok: false, reason: LIMOUSINE_BOOK_REASONS.MAX_DURATION_EXCEEDED };
    }
    const packageDuration = toInt(hourly.package_duration_minutes);
    const packageAmount = toInt(hourly.package_amount_cents);
    const hasPackage =
      packageAmount != null && packageAmount > 0 && packageDuration != null && packageDuration > 0;

    if (hasPackage && requested > packageDuration) {
      // Package covers its own duration; the remainder is authoritative excess.
      const excessPerHour = toInt(hourly.excess_hour_cents);
      if (excessPerHour == null || excessPerHour < 0) {
        return { ok: false, reason: LIMOUSINE_BOOK_REASONS.MANUAL_QUOTE_REQUIRED };
      }
      const excessMinutes = requested - packageDuration;
      // Whole-hour ceiling: the committed offer contract bills per started hour.
      const excessHours = Math.ceil(excessMinutes / 60);
      return {
        ok: true,
        pricing_mode: "hourly_or_package",
        charged_duration_minutes: requested,
        components: [
          component({
            type: LIMOUSINE_COMPONENT_TYPES.HOURLY_PACKAGE,
            reference: `${offer.offer_id}:hourly:package`,
            amountCents: packageAmount,
            currency,
            vatRate: hourly.vat_rate,
            pricingSource: "limousine_package",
            sourceRevision: offer.source_revision,
          }),
          component({
            type: LIMOUSINE_COMPONENT_TYPES.EXCESS_HOURS,
            reference: `${offer.offer_id}:hourly:excess`,
            amountCents: excessPerHour * excessHours,
            currency,
            vatRate: hourly.vat_rate,
            pricingSource: "limousine_excess_hours",
            sourceRevision: offer.source_revision,
          }),
        ],
      };
    }

    const cents = computeOfferHourlyCents(hourly, requested);
    if (cents == null) {
      return { ok: false, reason: LIMOUSINE_BOOK_REASONS.MANUAL_QUOTE_REQUIRED };
    }
    const minimum = toInt(hourly.minimum_duration_minutes) ?? 0;
    return {
      ok: true,
      pricing_mode: "hourly_or_package",
      charged_duration_minutes: Math.max(requested, minimum),
      components: [
        component({
          type: hasPackage
            ? LIMOUSINE_COMPONENT_TYPES.HOURLY_PACKAGE
            : componentType,
          reference: `${offer.offer_id}:hourly`,
          amountCents: cents,
          currency,
          vatRate: hourly.vat_rate,
          pricingSource: hasPackage ? "limousine_package" : "limousine_hourly",
          sourceRevision: offer.source_revision,
        }),
      ],
    };
  }

  // 3) Limousine distance/time using the SERVER route only.
  const dt = asObject(offer.distance_time);
  if (dt.enabled === true) {
    const complete =
      toInt(dt.base_incl_vat_cents) != null &&
      toInt(dt.per_km_incl_vat_cents) != null &&
      toInt(dt.per_minute_incl_vat_cents) != null &&
      toInt(dt.minimum_incl_vat_cents) != null &&
      !!normalizeCurrency(dt.currency);
    if (!complete) return { ok: false, reason: LIMOUSINE_BOOK_REASONS.UNAVAILABLE };
    if (normalizeCurrency(dt.currency) !== currency) {
      return { ok: false, reason: LIMOUSINE_BOOK_REASONS.CURRENCY_MISMATCH };
    }
    if (!routeIsUsable(route)) {
      return { ok: false, reason: LIMOUSINE_BOOK_REASONS.ROUTE_FAILED };
    }
    const km = Math.max(0, Number(route.distance_km));
    const min = Math.max(0, Number(route.duration_min));
    const raw =
      toInt(dt.base_incl_vat_cents) +
      Math.round(km * toInt(dt.per_km_incl_vat_cents)) +
      Math.round(min * toInt(dt.per_minute_incl_vat_cents));
    return {
      ok: true,
      pricing_mode: "limousine_distance_time",
      components: [
        component({
          type: componentType,
          reference: `${offer.offer_id}:distance_time`,
          amountCents: Math.max(toInt(dt.minimum_incl_vat_cents), raw),
          currency,
          vatRate: dt.vat_rate,
          pricingSource: "limousine_distance_time",
          sourceRevision: offer.source_revision,
        }),
      ],
    };
  }

  return { ok: false, reason: LIMOUSINE_BOOK_REASONS.UNAVAILABLE };
}

// ---------------------------------------------------------------------------
// Total composition
// ---------------------------------------------------------------------------

/// Composes the complete itemized Limousine total from authoritative state.
/// `routes` must contain SERVER-computed results:
///   { main, return?, mobilisation_outbound?, mobilisation_return? }
export function composeLimousineTotal({
  section = null,
  offerId = "",
  request = {},
  routes = {},
  nowMs = null,
} = {}) {
  const R = LIMOUSINE_BOOK_REASONS;
  const normalizedSection = normalizeLimousinePricingSection(section);
  if (!normalizedSection.enabled) return failed(R.UNAVAILABLE);

  const wantedOfferId = normalizeLimousineToken(offerId);
  let offer = null;
  if (wantedOfferId) {
    offer = normalizedSection.offers.find(
      (o) => normalizeLimousineToken(o.offer_id) === wantedOfferId,
    ) || null;
  } else {
    offer = selectLimousineOfferForRequest(normalizedSection.offers, {
      vehicleId: request.vehicle_id,
      serviceClassId: request.service_class_id,
      journeyType: request.journey_type,
    });
  }
  if (!offer) return failed(R.UNKNOWN_OFFER);
  offer = normalizeLimousineOffer(offer);
  if (!offer.enabled) return failed(R.OFFER_DISABLED);

  // Only directly calculable presentations may produce a total.
  if (offer.price_presentation === LIMOUSINE_PRICE_PRESENTATIONS.UNAVAILABLE) {
    return failed(R.UNAVAILABLE);
  }
  if (!offerCanProduceResolvedPrice(offer)) {
    return failed(R.MANUAL_QUOTE_REQUIRED);
  }

  const currency =
    normalizeCurrency(request.currency) || offer.currency || normalizedSection.currency;
  if (!currency) return failed(R.CURRENCY_MISMATCH);
  if (offer.currency && offer.currency !== currency) return failed(R.CURRENCY_MISMATCH);

  const journeyType = normalizeLimousineToken(request.journey_type);
  const components = [];
  const legs = [];

  // Outbound leg.
  const main = priceJourneyLeg(offer, {
    journeyType,
    direction: request.direction,
    airportIata: request.airport_iata,
    route: routes.main,
    requestedDurationMinutes: request.requested_duration_minutes,
    currency,
    nowMs,
    componentType: LIMOUSINE_COMPONENT_TYPES.MAIN_JOURNEY,
  });
  if (!main.ok) return failed(main.reason);
  components.push(...main.components);
  legs.push({
    leg: "outbound",
    pricing_mode: main.pricing_mode,
    distance_km: asObject(routes.main).distance_km ?? null,
    duration_min: asObject(routes.main).duration_min ?? null,
    ...(main.charged_duration_minutes != null
      ? { charged_duration_minutes: main.charged_duration_minutes }
      : {}),
    amount_cents: main.components.reduce((sum, c) => sum + c.amount_cents, 0),
  });

  // Return leg (explicit roundtrip only).
  const roundtrip = request.roundtrip === true;
  if (roundtrip) {
    const ret = priceJourneyLeg(offer, {
      journeyType,
      // Direction-specific fixed rule for the return leg.
      direction: normalizeLimousineToken(request.return_direction) ||
        (normalizeLimousineToken(request.direction) === "to_airport"
          ? "from_airport"
          : normalizeLimousineToken(request.direction) === "from_airport"
            ? "to_airport"
            : ""),
      airportIata: request.airport_iata,
      route: routes.return,
      requestedDurationMinutes: request.return_requested_duration_minutes,
      currency,
      nowMs,
      componentType: LIMOUSINE_COMPONENT_TYPES.RETURN_JOURNEY,
    });
    // If either leg cannot be priced safely the WHOLE request fails closed —
    // never a partially invented total.
    if (!ret.ok) return failed(ret.reason);
    components.push(...ret.components);
    legs.push({
      leg: "return",
      pricing_mode: ret.pricing_mode,
      distance_km: asObject(routes.return).distance_km ?? null,
      duration_min: asObject(routes.return).duration_min ?? null,
      amount_cents: ret.components.reduce((sum, c) => sum + c.amount_cents, 0),
    });
  }

  // Paid extras (authoritative IDs only).
  const extras = extraComponents(offer, request.selected_extra_ids, currency);
  if (!extras.ok) return failed(extras.reason);
  components.push(...extras.components);

  // Mobilisation (never duplicated: one outbound + one return row at most).
  const mobilisation = mobilisationComponents(offer, { routes, currency });
  if (!mobilisation.ok) return failed(mobilisation.reason);
  components.push(...mobilisation.components);

  // Single compatible currency across every component.
  if (components.some((c) => c.currency !== currency)) return failed(R.CURRENCY_MISMATCH);

  const totalCents = components.reduce((sum, c) => sum + c.amount_cents, 0);
  if (!(totalCents > 0)) return failed(R.UNAVAILABLE);

  // VAT source: the highest configured component rate (all components on one
  // offer share the offer's VAT treatment). Final €0.10 rounding happens once.
  const vatRate = components.reduce((max, c) => Math.max(max, Number(c.vat_rate) || 0), 0);
  const finalized = finalizeLegPricingInclVat({
    rawInclVat: totalCents / 100,
    vatRate,
  });

  return {
    ok: true,
    manual_quote_required: false,
    unavailable: false,
    reason: R.OK,
    offer_id: offer.offer_id,
    offer_source_revision: offer.source_revision,
    pricing_section_revision: normalizedSection.source_revision,
    service_category: "limousine",
    journey_type: journeyType,
    service_class_id: offer.service_class_id,
    vehicle_id: offer.vehicle_id || "",
    pricing_mode: main.pricing_mode,
    pricing_modes: offerSupportedPricingModes(offer),
    components,
    legs,
    selected_extras: extras.labels,
    mobilisation: safeMobilisationDisclosure(offer),
    currency,
    subtotal_cents: totalCents,
    price_incl_vat: finalized.price_incl_vat,
    price_ex_vat: finalized.price_ex_vat,
    price_vat: finalized.price_vat,
    total_incl_vat_cents: Math.round(finalized.price_incl_vat * 100),
    vat_rate: vatRate,
  };
}

// ---------------------------------------------------------------------------
// Quote result + fingerprint
// ---------------------------------------------------------------------------

/// Deterministic fingerprint over the authoritative facts that must not change
/// between quote and book. Contains no private data.
export function limousineQuoteFingerprint(total) {
  if (!total || total.ok !== true) return "";
  const parts = [
    total.offer_id,
    total.offer_source_revision,
    total.pricing_section_revision,
    total.service_class_id,
    total.vehicle_id,
    total.journey_type,
    total.pricing_mode,
    total.currency,
    total.total_incl_vat_cents,
    total.components
      .map((c) => `${c.type}:${c.reference}:${c.amount_cents}`)
      .sort()
      .join("|"),
  ];
  const raw = parts.join("~");
  // FNV-1a 32-bit — stable, dependency-free, non-cryptographic.
  let hash = 0x811c9dc5;
  for (let i = 0; i < raw.length; i++) {
    hash ^= raw.charCodeAt(i);
    hash = Math.imul(hash, 0x01000193) >>> 0;
  }
  return `limq_${hash.toString(16)}`;
}

/// Privacy-safe typed quote result for the customer surface.
export function buildLimousineQuoteResult(total, context = {}) {
  if (!total || total.ok !== true) {
    return {
      resolved: false,
      manual_quote_required: total?.manual_quote_required === true,
      unavailable: total?.unavailable !== false,
      reason: total?.reason ?? LIMOUSINE_BOOK_REASONS.UNAVAILABLE,
    };
  }
  const quotedAt = context.quotedAtIso || new Date().toISOString();
  const expiresAt =
    context.expiresAtIso ||
    new Date(Date.parse(quotedAt) + (context.ttlMinutes ?? 30) * 60000).toISOString();
  return {
    resolved: true,
    manual_quote_required: false,
    unavailable: false,
    reason: LIMOUSINE_BOOK_REASONS.OK,
    quote_reference: limousineQuoteFingerprint(total),
    service_category: "limousine",
    offer_id: total.offer_id,
    service_class_id: total.service_class_id,
    ...(total.vehicle_id ? { vehicle_id: total.vehicle_id } : {}),
    journey_type: total.journey_type,
    pricing_mode: total.pricing_mode,
    pricing_modes: total.pricing_modes,
    distance_km: context.distanceKm ?? null,
    duration_min: context.durationMin ?? null,
    scheduled_pickup_iso: context.scheduledPickupIso || "",
    pax: toInt(context.pax) ?? null,
    bags: toInt(context.bags) ?? null,
    legs: total.legs,
    components: total.components,
    selected_extras: total.selected_extras,
    mobilisation: total.mobilisation,
    subtotal_cents: total.subtotal_cents,
    total_incl_vat_cents: total.total_incl_vat_cents,
    price_incl_vat: total.price_incl_vat,
    price_ex_vat: total.price_ex_vat,
    price_vat: total.price_vat,
    vat_rate: total.vat_rate,
    currency: total.currency,
    offer_source_revision: total.offer_source_revision,
    pricing_section_revision: total.pricing_section_revision,
    quoted_at: quotedAt,
    expires_at: expiresAt,
  };
}

// ---------------------------------------------------------------------------
// /book recompute-and-compare
// ---------------------------------------------------------------------------

/// Recomputes the total server-side and compares it with the reference the
/// client is booking against. A stale or changed quote is rejected; a higher or
/// different total is NEVER silently accepted. Client totals are ignored.
export function compareLimousineQuoteForBook({
  recomputed,
  clientQuoteReference = "",
  requireQuoteReference = true,
} = {}) {
  const R = LIMOUSINE_BOOK_REASONS;
  if (!recomputed || recomputed.ok !== true) {
    return {
      ok: false,
      reason: recomputed?.reason ?? R.UNAVAILABLE,
      manual_quote_required: recomputed?.manual_quote_required === true,
    };
  }
  const serverReference = limousineQuoteFingerprint(recomputed);
  const provided = String(clientQuoteReference ?? "").trim();
  if (!provided) {
    if (requireQuoteReference) {
      return { ok: false, reason: R.MISSING_QUOTE_REFERENCE, quote_reference: serverReference };
    }
    return { ok: true, quote_reference: serverReference, recomputed };
  }
  if (provided !== serverReference) {
    // Offer/pricing revision, components, currency or total changed.
    return {
      ok: false,
      reason: R.QUOTE_MISMATCH,
      quote_reference: serverReference,
      refresh_required: true,
    };
  }
  return { ok: true, quote_reference: serverReference, recomputed };
}

// ---------------------------------------------------------------------------
// Accepted-price snapshot
// ---------------------------------------------------------------------------

/// Immutable accepted-price snapshot written into the existing booking record
/// and operational legs. Contains full provenance and no private data.
export function buildLimousineAcceptedSnapshot({
  total,
  quoteReference,
  acceptedAtIso,
  scheduledPickupIso = "",
  companyId = "",
  publicPartnerId = "",
  termsRevision = 0,
} = {}) {
  if (!total || total.ok !== true) return null;
  return {
    service_category: "limousine",
    journey_type: total.journey_type,
    offer_id: total.offer_id,
    service_class_id: total.service_class_id,
    ...(total.vehicle_id ? { vehicle_id: total.vehicle_id } : {}),
    company_id: companyId,
    ...(publicPartnerId ? { public_partner_id: publicPartnerId } : {}),
    pricing_mode: total.pricing_mode,
    quote_reference: quoteReference || limousineQuoteFingerprint(total),
    offer_source_revision: total.offer_source_revision,
    pricing_section_revision: total.pricing_section_revision,
    components: total.components,
    legs: total.legs,
    selected_extras: total.selected_extras,
    mobilisation: total.mobilisation,
    subtotal_cents: total.subtotal_cents,
    total_incl_vat_cents: total.total_incl_vat_cents,
    price_incl_vat: total.price_incl_vat,
    price_ex_vat: total.price_ex_vat,
    price_vat: total.price_vat,
    vat_rate: total.vat_rate,
    currency: total.currency,
    scheduled_pickup_iso: scheduledPickupIso,
    terms_revision: toInt(termsRevision) ?? 0,
    accepted_at: acceptedAtIso || new Date().toISOString(),
  };
}

/// Reads a "0"/"1" style server gate. Default OFF.
export function limousineBookGateEnabled(rawValue) {
  const token = normalizeLimousineToken(rawValue);
  return token === "1" || token === "true" || token === "yes" || token === "on";
}
