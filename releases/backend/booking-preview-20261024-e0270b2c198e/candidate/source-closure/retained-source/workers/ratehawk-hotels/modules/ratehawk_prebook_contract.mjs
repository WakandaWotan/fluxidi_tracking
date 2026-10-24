/**
 * RateHawk prebook revalidation and acceptance contract.
 *
 * Official path: POST /api/b2b/v3/hotel/prebook/
 * Request body is only the sealed book_hash (`hash`). This module does
 * not call RateHawk, book, finish, cancel, or collect payment.
 */

import { RATEHAWK_PREBOOK_PATH } from "./ratehawk_provider.mjs";
import { RATEHAWK_DISCLOSURE_LOCALES } from "./ratehawk_content_freshness_contract.mjs";

export { RATEHAWK_PREBOOK_PATH };

export const RATEHAWK_PREBOOK_TTL_MS = 15 * 60 * 1000;
export const RATEHAWK_PREBOOK_ACCEPT_TTL_MS = 15 * 60 * 1000;
export const RATEHAWK_PREBOOK_TIMEOUT_MS = 30_000;
export const RATEHAWK_PREBOOK_REF_PREFIX = "rhp1";
export const RATEHAWK_ACCEPTED_REF_PREFIX = "rha1";
export const RATEHAWK_PREBOOK_TRIGGER = "prebook_revalidation";
export const RATEHAWK_PREBOOK_ACCEPT_TRIGGER = "accept_prebook_terms";
export const RATEHAWK_OFFER_REF_PURPOSE = "hotelpage_offer";
export const RATEHAWK_PREBOOK_PURPOSE = "prebook";
export const RATEHAWK_ACCEPTED_PURPOSE = "accepted_prebook";

export const RATEHAWK_PREBOOK_FORBIDDEN_CLIENT_KEYS = Object.freeze([
  "host",
  "base_url",
  "api_key",
  "apiKey",
  "authorization",
  "endpoint",
  "url",
  "path",
  "book_hash",
  "match_hash",
  "hash",
  "hid",
  "checkin",
  "checkout",
  "residency",
  "currency",
  "guests",
  "price",
  "price_override",
  "show_amount",
  "payment_type",
  "cancellation",
  "RATEHAWK_API_KEY",
  "RATEHAWK_KEY_ID",
]);

export const RATEHAWK_PREBOOK_CHANGE_CODES = Object.freeze([
  "price_changed",
  "currency_changed",
  "taxes_changed",
  "additional_fees_changed",
  "room_changed",
  "occupancy_changed",
  "beds_changed",
  "meal_changed",
  "payment_type_changed",
  "payment_recipient_changed",
  "payment_timing_changed",
  "card_requirement_changed",
  "deposit_changed",
  "cancellation_changed",
  "free_cancellation_deadline_changed",
  "no_show_changed",
  "availability_changed",
  "important_terms_changed",
]);

const CHANGE_LABELS = Object.freeze({
  price_changed: L("Prijs", "Price", "Prix", "Precio"),
  currency_changed: L("Valuta", "Currency", "Devise", "Divisa"),
  taxes_changed: L("Belastingen", "Taxes", "Taxes", "Impuestos"),
  additional_fees_changed: L(
    "Extra kosten",
    "Additional fees",
    "Frais supplémentaires",
    "Cargos adicionales",
  ),
  room_changed: L("Kamer", "Room", "Chambre", "Habitación"),
  occupancy_changed: L("Bezetting", "Occupancy", "Occupation", "Ocupación"),
  beds_changed: L("Bedden", "Beds", "Lits", "Camas"),
  meal_changed: L("Maaltijd", "Meal", "Repas", "Comida"),
  payment_type_changed: L(
    "Betalingstype",
    "Payment type",
    "Type de paiement",
    "Tipo de pago",
  ),
  payment_recipient_changed: L(
    "Betalingsontvanger",
    "Payment recipient",
    "Destinataire du paiement",
    "Destinatario del pago",
  ),
  payment_timing_changed: L(
    "Betaalmoment",
    "Payment timing",
    "Moment du paiement",
    "Momento del pago",
  ),
  card_requirement_changed: L(
    "Kaartvereiste",
    "Card requirement",
    "Exigence de carte",
    "Requisito de tarjeta",
  ),
  deposit_changed: L("Hoteldeposito", "Hotel deposit", "Dépôt hôtelier", "Depósito"),
  cancellation_changed: L("Annulering", "Cancellation", "Annulation", "Cancelación"),
  free_cancellation_deadline_changed: L(
    "Gratis-annuleringstermijn",
    "Free-cancellation deadline",
    "Délai d’annulation gratuite",
    "Plazo de cancelación gratuita",
  ),
  no_show_changed: L("No-show", "No-show", "No-show", "No-show"),
  availability_changed: L(
    "Beschikbaarheid",
    "Availability",
    "Disponibilité",
    "Disponibilidad",
  ),
  important_terms_changed: L(
    "Belangrijke voorwaarden",
    "Important terms",
    "Conditions importantes",
    "Condiciones importantes",
  ),
});

function L(nl, en, fr, es) {
  return Object.freeze({ nl, en, fr, es });
}

function _stable(value) {
  return JSON.stringify(value ?? null);
}

function _money(value) {
  if (!value || typeof value !== "object") {
    return { amount_minor: null, currency: null, label: null };
  }
  if (value.amount_minor != null || value.currency) {
    return {
      amount_minor: value.amount_minor ?? null,
      currency: value.currency ?? null,
      label: value.label ?? value.customer_total_label ?? null,
    };
  }
  if (value.amount != null && typeof value.amount === "object") {
    return _money(value.amount);
  }
  return { amount_minor: null, currency: null, label: String(value) };
}

function _taxLines(list) {
  return (Array.isArray(list) ? list : []).map((tax) => ({
    name: tax?.name ?? null,
    amount: tax?.amount ?? tax?.show_amount ?? null,
    included_by_supplier: tax?.included_by_supplier === true,
    payable_where: tax?.payable_where ?? null,
  }));
}

export function hasForbiddenPublicPrebookClientControl(input = {}) {
  if (!input || typeof input !== "object" || Array.isArray(input)) return false;
  for (const key of RATEHAWK_PREBOOK_FORBIDDEN_CLIENT_KEYS) {
    if (!Object.prototype.hasOwnProperty.call(input, key)) continue;
    const value = input[key];
    if (value == null || value === "") continue;
    if (Array.isArray(value) && value.length === 0) continue;
    return true;
  }
  return false;
}

export function buildOfferDisplaySnapshot(offer = {}) {
  const payment = offer.payment && typeof offer.payment === "object" ? offer.payment : {};
  const deposit = offer.deposit && typeof offer.deposit === "object" ? offer.deposit : {};
  const noShow = offer.no_show && typeof offer.no_show === "object" ? offer.no_show : {};
  const cancellation =
    offer.cancellation && typeof offer.cancellation === "object"
      ? offer.cancellation
      : {};
  return {
    room_name: offer.room_name ?? null,
    room_description: offer.room_description ?? null,
    occupancy: offer.occupancy ?? null,
    beds: offer.bed_information ?? offer.beds ?? null,
    meal_plan: offer.meal_plan ?? null,
    breakfast_included: offer.breakfast_included === true,
    remaining_availability: offer.remaining_availability ?? null,
    customer_total: {
      amount_minor: offer.customer_total?.amount_minor ?? null,
      currency: offer.customer_total?.currency ?? null,
      label: offer.customer_total_label ?? null,
    },
    included_taxes: _taxLines(offer.included_taxes),
    excluded_taxes: _taxLines(offer.excluded_taxes),
    vat_included: offer.vat?.included === true,
    payment: {
      type: payment.payment_type ?? payment.type ?? null,
      recipient: payment.payment_recipient ?? payment.recipient ?? null,
      timing: payment.payment_timing ?? payment.timing ?? null,
    },
    card_data_required: offer.card_data_required === true,
    cvc_required: offer.cvc_required === true,
    deposit: {
      disclosed: deposit.disclosed === true,
      amount: _money(deposit.amount ?? deposit),
      currency: deposit.currency ?? deposit.amount?.currency ?? null,
      refundable: deposit.refundable === true,
      recipient: deposit.payment_recipient ?? deposit.recipient ?? null,
      timing: deposit.payment_timing ?? deposit.timing ?? null,
    },
    cancellation: {
      refundable:
        cancellation.refundable === true || offer.refundable === true,
      free_cancellation_before:
        cancellation.free_cancellation_before ??
        offer.free_cancellation_before ??
        null,
      penalties: Array.isArray(cancellation.penalties)
        ? cancellation.penalties
        : Array.isArray(offer.cancellation_penalties)
          ? offer.cancellation_penalties
          : [],
    },
    no_show: {
      disclosed: noShow.disclosed === true,
      amount: _money(noShow.amount ?? noShow),
      currency: noShow.currency ?? noShow.amount?.currency ?? null,
      from_time: noShow.from_time ?? null,
      timezone_context: noShow.timezone_context ?? null,
    },
    important_terms: Array.isArray(offer.unmapped_field_names)
      ? [...offer.unmapped_field_names].sort()
      : [],
  };
}

export function fingerprintOfferDisplaySnapshot(snapshot) {
  return _stable(snapshot);
}

export function compareRatehawkPrebookTerms(beforeSnapshot, afterSnapshot) {
  if (!beforeSnapshot || !afterSnapshot) {
    return {
      ok: false,
      reason: "comparison_incomplete",
      progress_blocked: true,
      acceptance_allowed: false,
      changes: [],
      flags: {},
    };
  }
  const beforeTotal = beforeSnapshot.customer_total || {};
  const afterTotal = afterSnapshot.customer_total || {};
  if (
    beforeTotal.amount_minor == null ||
    !beforeTotal.currency ||
    afterTotal.amount_minor == null ||
    !afterTotal.currency
  ) {
    return {
      ok: false,
      reason: "comparison_incomplete",
      progress_blocked: true,
      acceptance_allowed: false,
      changes: [],
      flags: {},
    };
  }

  const flags = {
    price_changed: beforeTotal.amount_minor !== afterTotal.amount_minor,
    currency_changed: beforeTotal.currency !== afterTotal.currency,
    taxes_changed: _stable(beforeSnapshot.included_taxes) !== _stable(afterSnapshot.included_taxes),
    additional_fees_changed:
      _stable(beforeSnapshot.excluded_taxes) !== _stable(afterSnapshot.excluded_taxes),
    room_changed: beforeSnapshot.room_name !== afterSnapshot.room_name,
    occupancy_changed: _stable(beforeSnapshot.occupancy) !== _stable(afterSnapshot.occupancy),
    beds_changed: _stable(beforeSnapshot.beds) !== _stable(afterSnapshot.beds),
    meal_changed:
      beforeSnapshot.meal_plan !== afterSnapshot.meal_plan ||
      beforeSnapshot.breakfast_included !== afterSnapshot.breakfast_included,
    payment_type_changed:
      beforeSnapshot.payment?.type !== afterSnapshot.payment?.type,
    payment_recipient_changed:
      beforeSnapshot.payment?.recipient !== afterSnapshot.payment?.recipient,
    payment_timing_changed:
      beforeSnapshot.payment?.timing !== afterSnapshot.payment?.timing,
    card_requirement_changed:
      beforeSnapshot.card_data_required !== afterSnapshot.card_data_required ||
      beforeSnapshot.cvc_required !== afterSnapshot.cvc_required,
    deposit_changed: _stable(beforeSnapshot.deposit) !== _stable(afterSnapshot.deposit),
    cancellation_changed:
      _stable(beforeSnapshot.cancellation?.penalties) !==
        _stable(afterSnapshot.cancellation?.penalties) ||
      beforeSnapshot.cancellation?.refundable !==
        afterSnapshot.cancellation?.refundable,
    free_cancellation_deadline_changed:
      beforeSnapshot.cancellation?.free_cancellation_before !==
      afterSnapshot.cancellation?.free_cancellation_before,
    no_show_changed: _stable(beforeSnapshot.no_show) !== _stable(afterSnapshot.no_show),
    availability_changed:
      beforeSnapshot.remaining_availability !== afterSnapshot.remaining_availability,
    important_terms_changed:
      _stable(beforeSnapshot.important_terms) !== _stable(afterSnapshot.important_terms),
  };

  const afterRemaining = Number(afterSnapshot.remaining_availability);
  const availabilityLost =
    afterSnapshot.remaining_availability == null ||
    (Number.isFinite(afterRemaining) && afterRemaining <= 0);
  const progressBlocked = flags.currency_changed === true || availabilityLost === true;
  const changes = RATEHAWK_PREBOOK_CHANGE_CODES.filter((code) => flags[code] === true).map(
    (code) => ({
      code,
      before: _displayValue(code, beforeSnapshot),
      after: _displayValue(code, afterSnapshot),
      labels: CHANGE_LABELS[code],
    }),
  );

  return {
    ok: true,
    reason: progressBlocked
      ? flags.currency_changed
        ? "currency_changed"
        : "availability_lost"
      : null,
    changed: changes.length > 0,
    changes,
    flags,
    progress_blocked: progressBlocked,
    acceptance_allowed: progressBlocked !== true,
    must_redisplay_to_customer: changes.length > 0,
    explicit_acceptance_required: true,
    auto_finish_forbidden: true,
  };
}

function _displayValue(code, snapshot) {
  switch (code) {
    case "price_changed":
      return snapshot.customer_total?.label ?? snapshot.customer_total?.amount_minor ?? null;
    case "currency_changed":
      return snapshot.customer_total?.currency ?? null;
    case "taxes_changed":
      return snapshot.included_taxes;
    case "additional_fees_changed":
      return snapshot.excluded_taxes;
    case "room_changed":
      return snapshot.room_name;
    case "occupancy_changed":
      return snapshot.occupancy;
    case "beds_changed":
      return snapshot.beds;
    case "meal_changed":
      return {
        meal_plan: snapshot.meal_plan,
        breakfast_included: snapshot.breakfast_included,
      };
    case "payment_type_changed":
      return snapshot.payment?.type ?? null;
    case "payment_recipient_changed":
      return snapshot.payment?.recipient ?? null;
    case "payment_timing_changed":
      return snapshot.payment?.timing ?? null;
    case "card_requirement_changed":
      return {
        card: snapshot.card_data_required === true,
        cvc: snapshot.cvc_required === true,
      };
    case "deposit_changed":
      return snapshot.deposit;
    case "cancellation_changed":
      return snapshot.cancellation;
    case "free_cancellation_deadline_changed":
      return snapshot.cancellation?.free_cancellation_before ?? null;
    case "no_show_changed":
      return {
        amount: snapshot.no_show?.amount ?? null,
        currency: snapshot.no_show?.currency ?? null,
        from_time: snapshot.no_show?.from_time ?? null,
      };
    case "availability_changed":
      return snapshot.remaining_availability ?? null;
    case "important_terms_changed":
      return snapshot.important_terms;
    default:
      return null;
  }
}

export function localizePrebookChanges(changes = [], locale = "nl") {
  const key = RATEHAWK_DISCLOSURE_LOCALES.includes(String(locale || "").toLowerCase())
    ? String(locale).toLowerCase()
    : "en";
  return (Array.isArray(changes) ? changes : []).map((row) => ({
    code: row.code,
    before: row.before,
    after: row.after,
    label: row.labels?.[key] || row.code,
  }));
}

export function buildSafePrebookDisputeSnapshot({
  hid,
  snapshot,
  comparison,
  locale = "nl",
  termsRevision = null,
  acceptedAt = null,
} = {}) {
  if (!snapshot) return { ok: false, reason: "offer_required" };
  return {
    ok: true,
    snapshot_kind: "ratehawk_accepted_terms_v1",
    hid: hid == null ? null : Number(hid),
    room_name: snapshot.room_name ?? null,
    meal_plan: snapshot.meal_plan ?? null,
    breakfast_included: snapshot.breakfast_included === true,
    customer_total: snapshot.customer_total ?? null,
    included_taxes: snapshot.included_taxes ?? [],
    excluded_taxes: snapshot.excluded_taxes ?? [],
    payment: snapshot.payment ?? null,
    cancellation: snapshot.cancellation ?? null,
    no_show: snapshot.no_show ?? null,
    deposit: snapshot.deposit ?? null,
    prebook_changes: localizePrebookChanges(comparison?.changes, locale),
    locale,
    terms_revision: termsRevision,
    accepted_at: acceptedAt,
    omitted: Object.freeze([
      "card_data",
      "cvc",
      "api_credentials",
      "guest_document_numbers",
      "raw_provider_payload",
      "book_hash",
      "match_hash",
      "reconciliation_amount",
      "commission",
    ]),
  };
}

export function prebookActionLabels(locale = "nl") {
  const key = RATEHAWK_DISCLOSURE_LOCALES.includes(String(locale || "").toLowerCase())
    ? String(locale).toLowerCase()
    : "en";
  const labels = {
    check: L(
      "Prijs en voorwaarden controleren",
      "Check price and conditions",
      "Vérifier le prix et les conditions",
      "Comprobar precio y condiciones",
    ),
    confirm: L(
      "Voorwaarden bevestigen",
      "Confirm these terms",
      "Confirmer ces conditions",
      "Confirmar estas condiciones",
    ),
    accept_changes: L(
      "Gewijzigde voorwaarden accepteren",
      "Accept changed terms",
      "Accepter les conditions modifiées",
      "Aceptar las condiciones modificadas",
    ),
    refresh: L(
      "Beschikbaarheid vernieuwen",
      "Refresh availability",
      "Actualiser la disponibilité",
      "Actualizar disponibilidad",
    ),
    other_rooms: L(
      "Andere kamers",
      "Other rooms",
      "Autres chambres",
      "Otras habitaciones",
    ),
  };
  const out = {};
  for (const [name, row] of Object.entries(labels)) out[name] = row[key];
  return out;
}
