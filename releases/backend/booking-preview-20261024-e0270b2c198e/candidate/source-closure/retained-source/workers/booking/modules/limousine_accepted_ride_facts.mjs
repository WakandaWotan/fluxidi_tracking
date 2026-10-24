// Frozen ride facts for an accepted limousine quotation.
// Pax/bags and cancellation terms come from the quotation snapshot (or the
// live quote record when a legacy booking has no snapshot). Taxi defaults
// and later company policy never rewrite these values.

function asObject(value) {
  return value && typeof value === "object" && !Array.isArray(value) ? value : {};
}

function toInt(value) {
  if (value == null || value === "") return null;
  const n = Number(value);
  if (!Number.isFinite(n)) return null;
  return Math.trunc(n);
}

function clampInt(value, min, max, fallback = min) {
  const n = toInt(value);
  if (n == null) return fallback;
  return Math.max(min, Math.min(max, n));
}

export const LIMOUSINE_ACCEPTED_PAX_MIN = 1;
export const LIMOUSINE_ACCEPTED_PAX_MAX = 16;
export const LIMOUSINE_ACCEPTED_BAGS_MIN = 0;
export const LIMOUSINE_ACCEPTED_BAGS_MAX = 99;
export const LIMOUSINE_FROZEN_CANCELLATION_SOURCE = "frozen_quotation";

export function clampLimousineAcceptedPax(raw) {
  return clampInt(raw, LIMOUSINE_ACCEPTED_PAX_MIN, LIMOUSINE_ACCEPTED_PAX_MAX, LIMOUSINE_ACCEPTED_PAX_MIN);
}

export function clampLimousineAcceptedBags(raw) {
  return clampInt(raw, LIMOUSINE_ACCEPTED_BAGS_MIN, LIMOUSINE_ACCEPTED_BAGS_MAX, LIMOUSINE_ACCEPTED_BAGS_MIN);
}

/// Passenger/baggage authority for an accepted quotation.
export function freezeLimousineAcceptedPassengerFacts({
  requestSnapshot = null,
  request = null,
} = {}) {
  const req = asObject(requestSnapshot || request);
  if (toInt(req.pax) == null && toInt(req.bags) == null) return {};
  return {
    pax: clampLimousineAcceptedPax(req.pax),
    bags: clampLimousineAcceptedBags(req.bags),
  };
}

/// Cancellation authority frozen at quotation send/accept.
export function freezeLimousineAcceptedCancellationTerms({
  offerTerms = null,
  quote = null,
  totals = null,
  termsRevision = 0,
} = {}) {
  const terms = asObject(offerTerms || asObject(quote).terms);
  const tot = asObject(totals);
  const q = asObject(quote);
  const hours = toInt(terms.cancellation_deadline_hours);
  const penalty = toInt(terms.cancellation_penalty_percent);
  const noShow = toInt(terms.no_show_penalty_percent);
  if (hours == null && penalty == null && noShow == null) return {};
  const gross =
    toInt(tot.total_incl_vat_cents) ??
    toInt(q.total_incl_vat_cents) ??
    0;
  return {
    cancellation_deadline_hours: hours ?? 0,
    cancellation_penalty_percent: penalty ?? 0,
    no_show_penalty_percent: noShow ?? 0,
    cancellation_canonical_gross_cents: Math.max(0, gross),
    terms_revision: toInt(terms.terms_revision ?? termsRevision) ?? 0,
    cancellation_terms_source: LIMOUSINE_FROZEN_CANCELLATION_SOURCE,
  };
}

export function freezeLimousineAcceptedRideFacts(input = {}) {
  return {
    ...freezeLimousineAcceptedPassengerFacts(input),
    ...freezeLimousineAcceptedCancellationTerms(input),
  };
}

function firstInt(...values) {
  for (const value of values) {
    const n = toInt(value);
    if (n != null) return n;
  }
  return null;
}

/// Reads frozen terms from a persisted booking. Absent → null (legacy path).
export function readFrozenLimousineCancellationTerms(rec) {
  const record = asObject(rec);
  const booking = asObject(record.booking);
  const quote = asObject(record.quote);
  const snapshot = asObject(
    quote.limousine_accepted_price || record.limousine_accepted_price,
  );
  const source = snapshot.cancellation_terms_source ||
    record.cancellation_terms_source ||
    booking.cancellation_terms_source;
  const hours = firstInt(
    snapshot.cancellation_deadline_hours,
    record.cancellation_deadline_hours,
    booking.cancellation_deadline_hours,
  );
  const penalty = firstInt(
    snapshot.cancellation_penalty_percent,
    record.cancellation_penalty_percent,
    booking.cancellation_penalty_percent,
  );
  const noShow = firstInt(
    snapshot.no_show_penalty_percent,
    record.no_show_penalty_percent,
    booking.no_show_penalty_percent,
  );
  if (hours == null && penalty == null && noShow == null) return null;
  if (
    source &&
    source !== LIMOUSINE_FROZEN_CANCELLATION_SOURCE
  ) {
    return null;
  }
  const serviceType = String(
    record.service_type ||
      record.serviceType ||
      booking.service_type ||
      booking.serviceType ||
      snapshot.service_category ||
      "",
  ).toLowerCase();
  if (serviceType && serviceType !== "limousine") return null;
  const gross = firstInt(
    snapshot.cancellation_canonical_gross_cents,
    record.cancellation_canonical_gross_cents,
    booking.cancellation_canonical_gross_cents,
    snapshot.total_incl_vat_cents,
    Math.round(Number(snapshot.price_incl_vat || 0) * 100),
  );
  return {
    cancellation_deadline_hours: hours ?? 0,
    cancellation_penalty_percent: penalty ?? 0,
    no_show_penalty_percent: noShow ?? 0,
    cancellation_canonical_gross_cents: Math.max(0, gross ?? 0),
    terms_revision: firstInt(
      snapshot.terms_revision,
      record.cancellation_terms_revision,
      record.terms_revision,
    ) ?? 0,
    cancellation_terms_source: LIMOUSINE_FROZEN_CANCELLATION_SOURCE,
  };
}

function paidAmountCentsFromRecord(rec, fallbackGross) {
  const record = asObject(rec);
  const booking = asObject(record.booking);
  const raw = firstInt(
    record.payment_amount_cents,
    record.paid_amount_cents,
    booking.payment_amount_cents,
    booking.paid_amount_cents,
    Math.round(Number(record.payment_amount || booking.payment_amount || 0) * 100),
  );
  return raw != null && raw > 0 ? raw : fallbackGross;
}

/// Financial preview + allow/deny for frozen limousine terms.
/// After the free-cancellation deadline, cancel remains allowed and the
/// frozen percentage applies. Taxi "window closed" denial is not used.
export function evaluateFrozenLimousineCancellation({
  terms,
  pickupIso,
  now = new Date(),
  paymentClass = "unpaid",
  paidAmountCents = null,
  pickupSource = "none",
  pickupCandidatesPresent = [],
  parsedPickupMs = null,
} = {}) {
  const frozen = asObject(terms);
  const hours = Math.max(0, toInt(frozen.cancellation_deadline_hours) ?? 0);
  const cancelPct = Math.max(0, toInt(frozen.cancellation_penalty_percent) ?? 0);
  const noShowPct = Math.max(0, toInt(frozen.no_show_penalty_percent) ?? 0);
  const gross = Math.max(0, toInt(frozen.cancellation_canonical_gross_cents) ?? 0);
  const cutoffMinutes = hours * 60;
  const parsedMs = Number(parsedPickupMs);
  const pickupMs = parsedPickupMs != null && Number.isFinite(parsedMs)
    ? parsedMs
    : Date.parse(String(pickupIso || ""));
  const nowMs = now instanceof Date ? now.getTime() : Date.parse(String(now || ""));
  const minutesUntilPickup = Number.isFinite(pickupMs) && Number.isFinite(nowMs)
    ? Math.floor((pickupMs - nowMs) / 60000)
    : null;
  const isNoShow = minutesUntilPickup != null && minutesUntilPickup < 0;
  const beforeDeadline =
    minutesUntilPickup != null && minutesUntilPickup >= cutoffMinutes;
  const applicablePercent = isNoShow
    ? noShowPct
    : beforeDeadline
      ? 0
      : cancelPct;
  const penaltyCents = Math.round((gross * applicablePercent) / 100);
  const paidClass = new Set(["paid", "prepaid", "mollie"]).has(
    String(paymentClass || "").toLowerCase(),
  );
  const paidCents = paidClass
    ? Math.max(0, toInt(paidAmountCents) ?? gross)
    : 0;
  const refundCents = paidClass ? Math.max(0, paidCents - penaltyCents) : 0;
  const outstandingCents = paidClass ? 0 : penaltyCents;
  return {
    allowed: true,
    reason: "allowed",
    cutoff_minutes: cutoffMinutes,
    minutes_until_pickup: minutesUntilPickup,
    pickup_iso: pickupIso || null,
    pickup_source: pickupSource,
    pickup_candidates_present: pickupCandidatesPresent,
    parsed_pickup_ms: Number.isFinite(pickupMs) ? pickupMs : null,
    now_ms: Number.isFinite(nowMs) ? nowMs : null,
    limousine_terms_source: LIMOUSINE_FROZEN_CANCELLATION_SOURCE,
    cancellation_deadline_hours: hours,
    cancellation_penalty_percent: cancelPct,
    no_show_penalty_percent: noShowPct,
    cancellation_canonical_gross_cents: gross,
    applicable_penalty_percent: applicablePercent,
    cancellation_penalty_cents: penaltyCents,
    before_free_deadline: beforeDeadline,
    is_no_show: isNoShow,
    refund_required: paidClass && refundCents > 0,
    refund_amount_cents: refundCents,
    outstanding_cancellation_cents: outstandingCents,
    paid_amount_cents: paidCents,
    payment_class: paymentClass,
    terms_revision: toInt(frozen.terms_revision) ?? 0,
  };
}

export function limousineFrozenCancellationFieldsFromDecision(decision) {
  const d = asObject(decision);
  if (d.limousine_terms_source !== LIMOUSINE_FROZEN_CANCELLATION_SOURCE) {
    return {};
  }
  return {
    cancellation_deadline_hours: d.cancellation_deadline_hours,
    cancellation_penalty_percent: d.cancellation_penalty_percent,
    no_show_penalty_percent: d.no_show_penalty_percent,
    cancellation_canonical_gross_cents: d.cancellation_canonical_gross_cents,
    cancellation_terms_source: LIMOUSINE_FROZEN_CANCELLATION_SOURCE,
    applicable_penalty_percent: d.applicable_penalty_percent,
    cancellation_penalty_cents: d.cancellation_penalty_cents,
    refund_required: d.refund_required === true,
    refundRequired: d.refund_required === true,
    refund_amount_cents: d.refund_amount_cents,
    outstanding_cancellation_cents: d.outstanding_cancellation_cents,
    terms_revision: d.terms_revision,
  };
}

export { paidAmountCentsFromRecord };
