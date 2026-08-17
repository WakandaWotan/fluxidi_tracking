/**
 * RateHawk hotel booking orchestration contract (P3A, mocked only).
 *
 * Official provider paths are known from the existing test-denied
 * allowlist and authorized portal metadata. Exact request/response
 * field shapes are not locally documented, so transport seams stay
 * typed, unresolved, and fail closed. This module must not call
 * RateHawk, book, finish, cancel, download a voucher, or collect
 * hotel money.
 */

import { envFlag } from "./parsing_utils.js";
import {
  RATEHAWK_ALLOWED_AFFILIATE_PAYMENT_TYPES,
  RATEHAWK_REJECTED_PAYMENT_TYPES,
  classifyRatehawkPaymentType,
} from "./ratehawk_affiliate_contract.mjs";
import {
  RATEHAWK_ACCEPTED_PURPOSE,
  RATEHAWK_ACCEPTED_REF_PREFIX,
} from "./ratehawk_prebook_contract.mjs";
import {
  RATEHAWK_WORKER_SURFACE_PRODUCTION,
  RATEHAWK_WORKER_SURFACE_TEST,
  resolveRatehawkWorkerSurface,
} from "./ratehawk_test_activation.mjs";

export const RATEHAWK_BOOKING_FORM_PATH =
  "/api/b2b/v3/hotel/order/booking/form/";
export const RATEHAWK_BOOKING_FINISH_PATH =
  "/api/b2b/v3/hotel/order/booking/finish/";
export const RATEHAWK_BOOKING_FINISH_STATUS_PATH =
  "/api/b2b/v3/hotel/order/booking/finish/status/";
export const RATEHAWK_ORDER_INFO_PATH = "/api/b2b/v3/hotel/order/info/";
export const RATEHAWK_ORDER_CANCEL_PATH = "/api/b2b/v3/hotel/order/cancel/";
export const RATEHAWK_ORDER_VOUCHER_DOWNLOAD_PATH =
  "/api/b2b/v3/hotel/order/document/voucher/download/";
export const RATEHAWK_ORDER_VOUCHER_PATH =
  "/api/b2b/v3/hotel/order/document/voucher/";

export const RATEHAWK_BOOKING_PROVIDER_PATHS = Object.freeze([
  RATEHAWK_BOOKING_FORM_PATH,
  RATEHAWK_BOOKING_FINISH_PATH,
  RATEHAWK_BOOKING_FINISH_STATUS_PATH,
  RATEHAWK_ORDER_INFO_PATH,
  RATEHAWK_ORDER_CANCEL_PATH,
  RATEHAWK_ORDER_VOUCHER_DOWNLOAD_PATH,
]);

export const RATEHAWK_BOOKING_FORM_GATE = "RATEHAWK_BOOKING_FORM_ENABLED";
export const RATEHAWK_BOOKING_FINISH_GATE = "RATEHAWK_BOOKING_FINISH_ENABLED";
export const RATEHAWK_BOOKING_STATUS_GATE = "RATEHAWK_BOOKING_STATUS_ENABLED";
export const RATEHAWK_BOOKING_CANCEL_GATE = "RATEHAWK_BOOKING_CANCEL_ENABLED";
export const RATEHAWK_BOOKING_VOUCHER_GATE = "RATEHAWK_BOOKING_VOUCHER_ENABLED";

export const RATEHAWK_BOOKING_FORM_TRIGGER = "prepare_booking_form";
export const RATEHAWK_BOOKING_CONFIRM_TRIGGER = "confirm_hotel_booking";
export const RATEHAWK_BOOKING_STATUS_TRIGGER = "booking_status";

export const RATEHAWK_BOOKING_ATTEMPT_PREFIX = "rhb1";
export const RATEHAWK_BOOKING_PAYMENT_REF_PREFIX = "rhpay1";
export const RATEHAWK_BOOKING_SNAPSHOT_KIND = "ratehawk_booking_confirmation_v1";
export const RATEHAWK_BOOKING_INTENT_SCHEMA = "ratehawk_booking_intent_v1";

export const RATEHAWK_BOOKING_STATUS_MAX_POLLS = 3;
export const RATEHAWK_BOOKING_STATUS_MAX_DURATION_MS = 15_000;
export const RATEHAWK_BOOKING_STATUS_MIN_INTERVAL_MS = 1_000;

export {
  RATEHAWK_ACCEPTED_PURPOSE,
  RATEHAWK_ACCEPTED_REF_PREFIX,
  RATEHAWK_ALLOWED_AFFILIATE_PAYMENT_TYPES,
  RATEHAWK_REJECTED_PAYMENT_TYPES,
};

export const RATEHAWK_BOOKING_STATES = Object.freeze({
  ACCEPTED_PREBOOK: "accepted_prebook",
  FORM_REQUIRED: "form_required",
  FORM_READY: "form_ready",
  CUSTOMER_CONFIRMATION_REQUIRED: "customer_confirmation_required",
  FINISH_SUBMITTED: "finish_submitted",
  PROVIDER_PENDING: "provider_pending",
  CONFIRMED: "confirmed",
  REJECTED: "rejected",
  EXPIRED: "expired",
  PROVIDER_DECLINED: "provider_declined",
  CONFIRMATION_UNKNOWN: "confirmation_unknown",
  CANCELLED: "cancelled",
});

export const RATEHAWK_BOOKING_TERMINAL_STATES = Object.freeze([
  RATEHAWK_BOOKING_STATES.REJECTED,
  RATEHAWK_BOOKING_STATES.EXPIRED,
  RATEHAWK_BOOKING_STATES.PROVIDER_DECLINED,
  RATEHAWK_BOOKING_STATES.CONFIRMATION_UNKNOWN,
  RATEHAWK_BOOKING_STATES.CANCELLED,
  RATEHAWK_BOOKING_STATES.CONFIRMED,
]);

const ALLOWED_TRANSITIONS = Object.freeze({
  [RATEHAWK_BOOKING_STATES.ACCEPTED_PREBOOK]: Object.freeze([
    RATEHAWK_BOOKING_STATES.FORM_REQUIRED,
    RATEHAWK_BOOKING_STATES.FORM_READY,
    RATEHAWK_BOOKING_STATES.CUSTOMER_CONFIRMATION_REQUIRED,
    RATEHAWK_BOOKING_STATES.REJECTED,
    RATEHAWK_BOOKING_STATES.EXPIRED,
  ]),
  [RATEHAWK_BOOKING_STATES.FORM_REQUIRED]: Object.freeze([
    RATEHAWK_BOOKING_STATES.FORM_REQUIRED,
    RATEHAWK_BOOKING_STATES.FORM_READY,
    RATEHAWK_BOOKING_STATES.CUSTOMER_CONFIRMATION_REQUIRED,
    RATEHAWK_BOOKING_STATES.REJECTED,
    RATEHAWK_BOOKING_STATES.EXPIRED,
  ]),
  [RATEHAWK_BOOKING_STATES.FORM_READY]: Object.freeze([
    RATEHAWK_BOOKING_STATES.FORM_REQUIRED,
    RATEHAWK_BOOKING_STATES.FORM_READY,
    RATEHAWK_BOOKING_STATES.CUSTOMER_CONFIRMATION_REQUIRED,
    RATEHAWK_BOOKING_STATES.REJECTED,
    RATEHAWK_BOOKING_STATES.EXPIRED,
  ]),
  [RATEHAWK_BOOKING_STATES.CUSTOMER_CONFIRMATION_REQUIRED]: Object.freeze([
    RATEHAWK_BOOKING_STATES.CUSTOMER_CONFIRMATION_REQUIRED,
    RATEHAWK_BOOKING_STATES.FINISH_SUBMITTED,
    RATEHAWK_BOOKING_STATES.REJECTED,
    RATEHAWK_BOOKING_STATES.EXPIRED,
  ]),
  [RATEHAWK_BOOKING_STATES.FINISH_SUBMITTED]: Object.freeze([
    RATEHAWK_BOOKING_STATES.PROVIDER_PENDING,
    RATEHAWK_BOOKING_STATES.CONFIRMED,
    RATEHAWK_BOOKING_STATES.PROVIDER_DECLINED,
    RATEHAWK_BOOKING_STATES.CONFIRMATION_UNKNOWN,
  ]),
  [RATEHAWK_BOOKING_STATES.PROVIDER_PENDING]: Object.freeze([
    RATEHAWK_BOOKING_STATES.PROVIDER_PENDING,
    RATEHAWK_BOOKING_STATES.CONFIRMED,
    RATEHAWK_BOOKING_STATES.PROVIDER_DECLINED,
    RATEHAWK_BOOKING_STATES.CONFIRMATION_UNKNOWN,
  ]),
  [RATEHAWK_BOOKING_STATES.CONFIRMED]: Object.freeze([
    RATEHAWK_BOOKING_STATES.CANCELLED,
  ]),
  [RATEHAWK_BOOKING_STATES.CONFIRMATION_UNKNOWN]: Object.freeze([]),
  [RATEHAWK_BOOKING_STATES.REJECTED]: Object.freeze([]),
  [RATEHAWK_BOOKING_STATES.EXPIRED]: Object.freeze([]),
  [RATEHAWK_BOOKING_STATES.PROVIDER_DECLINED]: Object.freeze([]),
  [RATEHAWK_BOOKING_STATES.CANCELLED]: Object.freeze([]),
});

export const RATEHAWK_BOOKING_READINESS = Object.freeze({
  CUSTOMER_INPUT_REQUIRED: "customer_input_required",
  PROVIDER_PAYMENT_TOKEN_ACTION_REQUIRED: "provider_payment_token_action_required",
  READY_FOR_DELIBERATE_CONFIRMATION: "ready_for_deliberate_confirmation",
  UNAVAILABLE: "unavailable",
});

export const RATEHAWK_BOOKING_FORM_REQUIREMENT_KINDS = Object.freeze([
  "guest_first_name",
  "guest_last_name",
  "contact_email",
  "contact_phone",
  "provider_payment_token",
]);

export const RATEHAWK_BOOKING_UNRESOLVED_PROVIDER_FIELDS = Object.freeze({
  form_request: Object.freeze([
    "hash",
    "partner_order_id",
    "user",
    "rooms",
    "payment_type",
  ]),
  form_response: Object.freeze(["item_id", "order_id", "payment_types"]),
  finish_request: Object.freeze([
    "hash",
    "partner_order_id",
    "user",
    "rooms",
    "payment_type",
    "credit_card_data",
  ]),
  finish_response: Object.freeze(["percent", "data"]),
  finish_status_request: Object.freeze(["partner_order_id"]),
  order_info_request: Object.freeze(["partner_order_id", "language"]),
  cancel_request: Object.freeze(["partner_order_id"]),
  voucher_request: Object.freeze(["partner_order_id"]),
});

export const RATEHAWK_BOOKING_FORBIDDEN_CLIENT_KEYS = Object.freeze([
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
  "taxes",
  "commission",
  "reconciliation",
  "reconciliation_amount",
  "payment_type",
  "payment_recipient",
  "payment_timing",
  "cancellation",
  "no_show",
  "deposit",
  "order_id",
  "partner_order_id",
  "provider_order_id",
  "status",
  "card_number",
  "pan",
  "cvc",
  "cvv",
  "credit_card",
  "card_data",
  "RATEHAWK_API_KEY",
  "RATEHAWK_KEY_ID",
]);

export const RATEHAWK_BOOKING_PAN_CVC_KEYS = Object.freeze([
  "card_number",
  "pan",
  "cvc",
  "cvv",
  "credit_card",
  "card_data",
  "card",
]);

export const RATEHAWK_BOOKING_PRIVACY_OMISSIONS = Object.freeze([
  "card_data",
  "cvc",
  "pan",
  "api_credentials",
  "authorization",
  "guest_document_numbers",
  "guest_full_name",
  "guest_email",
  "guest_phone",
  "raw_provider_payload",
  "book_hash",
  "match_hash",
  "reconciliation_amount",
  "commission",
  "fluxidi_affiliate_remuneration",
]);

const PAYMENT_CRITICAL_HINTS = Object.freeze([
  "payment",
  "amount",
  "currency",
  "tax",
  "vat",
  "commission",
  "reconcil",
  "card",
  "cvc",
  "pan",
]);

function _text(value, max = 200) {
  const text = String(value ?? "").trim();
  if (!text) return "";
  return text.length > max ? text.slice(0, max) : text;
}

function _lower(value) {
  return _text(value, 200).toLowerCase();
}

export function isRatehawkBookingFormEnabled(env = {}) {
  return envFlag(env?.[RATEHAWK_BOOKING_FORM_GATE]);
}

export function isRatehawkBookingFinishEnabled(env = {}) {
  return envFlag(env?.[RATEHAWK_BOOKING_FINISH_GATE]);
}

export function isRatehawkBookingStatusEnabled(env = {}) {
  return envFlag(env?.[RATEHAWK_BOOKING_STATUS_GATE]);
}

export function isRatehawkBookingCancelEnabled(env = {}) {
  return envFlag(env?.[RATEHAWK_BOOKING_CANCEL_GATE]);
}

export function isRatehawkBookingVoucherEnabled(env = {}) {
  return envFlag(env?.[RATEHAWK_BOOKING_VOUCHER_GATE]);
}

export function hasForbiddenPublicBookingClientControl(input = {}) {
  if (!input || typeof input !== "object" || Array.isArray(input)) return false;
  for (const key of RATEHAWK_BOOKING_FORBIDDEN_CLIENT_KEYS) {
    if (!Object.prototype.hasOwnProperty.call(input, key)) continue;
    const value = input[key];
    if (value == null || value === "") continue;
    if (Array.isArray(value) && value.length === 0) continue;
    return true;
  }
  return false;
}

export function hasPublicBookingPanOrCvc(input = {}) {
  if (!input || typeof input !== "object" || Array.isArray(input)) return false;
  const stack = [input];
  while (stack.length) {
    const current = stack.pop();
    if (!current || typeof current !== "object") continue;
    for (const [key, value] of Object.entries(current)) {
      if (RATEHAWK_BOOKING_PAN_CVC_KEYS.includes(_lower(key))) {
        if (value == null || value === "") continue;
        return true;
      }
      if (value && typeof value === "object") stack.push(value);
    }
  }
  return false;
}

export function applyRatehawkBookingTransition(currentState, nextState, {
  revision = 0,
  nextRevision = null,
} = {}) {
  const current = _text(currentState, 64);
  const next = _text(nextState, 64);
  const currentRev = Number(revision);
  const incomingRev =
    nextRevision == null ? currentRev + 1 : Number(nextRevision);
  if (!Number.isFinite(currentRev) || !Number.isFinite(incomingRev)) {
    return { ok: false, reason: "revision_unmapped" };
  }
  if (incomingRev < currentRev) {
    return { ok: false, reason: "stale_revision" };
  }
  if (incomingRev === currentRev) {
    if (current === next) {
      return { ok: true, idempotent: true, state: current, revision: currentRev };
    }
    return { ok: false, reason: "contradictory_same_revision" };
  }
  const allowed = ALLOWED_TRANSITIONS[current];
  if (!allowed) {
    return { ok: false, reason: "unknown_state" };
  }
  if (!allowed.includes(next)) {
    return { ok: false, reason: "illegal_transition" };
  }
  return {
    ok: true,
    idempotent: false,
    state: next,
    revision: incomingRev,
  };
}

export function isRatehawkBookingTerminalState(state) {
  return RATEHAWK_BOOKING_TERMINAL_STATES.includes(_text(state, 64));
}

export function confirmationUnknownMustNotRetry(state) {
  return _text(state, 64) === RATEHAWK_BOOKING_STATES.CONFIRMATION_UNKNOWN;
}

export function classifyRatehawkBookingPayment(snapshot = {}) {
  const type =
    snapshot?.payment?.type ??
    snapshot?.payment?.payment_type ??
    null;
  const classified = classifyRatehawkPaymentType(type);
  if (classified.payment_type === "deposit" || classified.hard_stop === true) {
    return {
      ...classified,
      fluxidi_is_merchant_of_record: false,
      mollie_involved: false,
      customer_pays_fluxidi: false,
    };
  }
  return {
    ...classified,
    fluxidi_is_merchant_of_record: false,
    mollie_involved: false,
    customer_pays_fluxidi: false,
    payment_rail_forbidden: Object.freeze([
      "mollie",
      "fluxidi_subscription",
      "tenant_mollie",
      "fluxidi_hotel_invoice",
    ]),
  };
}

export function findUnmappedPaymentCriticalFields(snapshot = {}) {
  const names = Array.isArray(snapshot?.important_terms)
    ? snapshot.important_terms
    : [];
  return names.filter((name) => {
    const hint = _lower(name);
    return PAYMENT_CRITICAL_HINTS.some((part) => hint.includes(part));
  });
}

export function assertOpaqueAcceptedRef(value) {
  const text = _text(value, 4000);
  if (!text || /\s/.test(text)) return "";
  const parts = text.split(".");
  if (
    parts.length !== 3 ||
    parts[0] !== RATEHAWK_ACCEPTED_REF_PREFIX ||
    !parts[1] ||
    !parts[2]
  ) {
    return "";
  }
  return text;
}

export function assertApprovedOpaquePaymentRef(value) {
  const text = _text(value, 4000);
  if (!text || /\s/.test(text)) {
    return { ok: false, reason: "provider_payment_ref_required" };
  }
  if (/^\d{12,19}$/.test(text.replace(/\s+/g, ""))) {
    return { ok: false, reason: "pan_or_cvc_forbidden" };
  }
  const parts = text.split(".");
  if (
    parts.length !== 3 ||
    parts[0] !== RATEHAWK_BOOKING_PAYMENT_REF_PREFIX ||
    !parts[1] ||
    !parts[2]
  ) {
    return { ok: false, reason: "provider_payment_token_unresolved" };
  }
  return { ok: true, token: text, unresolved_official_field: true };
}

export function assertRatehawkAcceptedBookingClaims(claims = {}, {
  env = {},
  expectedTermsRevision = "",
  context = {},
} = {}) {
  if (!claims || typeof claims !== "object") {
    return { ok: false, reason: "rha1_invalid" };
  }
  if (claims.purpose !== RATEHAWK_ACCEPTED_PURPOSE) {
    return { ok: false, reason: "rha1_purpose_mismatch" };
  }
  const surface = resolveRatehawkWorkerSurface(env);
  const claimSurface = _text(claims.surface, 32).toLowerCase();
  if (
    surface === RATEHAWK_WORKER_SURFACE_PRODUCTION &&
    claimSurface === RATEHAWK_WORKER_SURFACE_TEST
  ) {
    return { ok: false, reason: "test_token_forbidden_on_production" };
  }
  if (
    surface === RATEHAWK_WORKER_SURFACE_TEST &&
    claimSurface !== RATEHAWK_WORKER_SURFACE_TEST
  ) {
    return { ok: false, reason: "production_token_forbidden_on_test" };
  }
  const envName = _text(env?.RATEHAWK_ENVIRONMENT, 32).toLowerCase();
  const claimEnv = _text(claims.environment, 32).toLowerCase();
  if (claimEnv && envName && claimEnv !== envName) {
    return { ok: false, reason: "token_environment_mismatch" };
  }
  if (expectedTermsRevision && expectedTermsRevision !== claims.terms_revision) {
    return { ok: false, reason: "terms_revision_mismatch" };
  }
  if (!claims.terms_revision) {
    return { ok: false, reason: "terms_revision_mismatch" };
  }
  if (
    claims.hid == null ||
    !claims.checkin ||
    !claims.checkout ||
    !claims.guests
  ) {
    return { ok: false, reason: "accepted_binding_incomplete" };
  }
  const snapshot = claims.display_snapshot;
  if (!snapshot || typeof snapshot !== "object") {
    return { ok: false, reason: "accepted_snapshot_missing" };
  }
  if (
    snapshot.customer_total?.amount_minor == null ||
    !snapshot.customer_total?.currency
  ) {
    return { ok: false, reason: "accepted_price_incomplete" };
  }
  const payment = classifyRatehawkBookingPayment(snapshot);
  if (payment.hard_stop === true || payment.allowed !== true) {
    return {
      ok: false,
      reason: payment.reason || "unsupported_payment_type",
      payment,
    };
  }
  const critical = findUnmappedPaymentCriticalFields(snapshot);
  if (critical.length > 0) {
    return {
      ok: false,
      reason: "unknown_payment_critical_field",
      unknown_field_names: critical,
      payment,
    };
  }
  for (const key of ["tenant_id", "customer_id", "session_id"]) {
    const expected = _text(context?.[key], 80);
    const actual = _text(claims[key], 80);
    if (expected && actual && expected !== actual) {
      return { ok: false, reason: "accepted_context_mismatch" };
    }
  }
  return {
    ok: true,
    reason: null,
    claims,
    snapshot,
    payment,
    surface,
  };
}

export function evaluateRatehawkBookingCancelContract() {
  return {
    ok: false,
    available: false,
    invoked: false,
    reason: "booking_cancel_unavailable",
    requires: Object.freeze([
      "current_order_status",
      "explicit_customer_intent",
      "disclosed_penalty_or_result",
      "idempotency",
    ]),
    unresolved_provider_fields:
      RATEHAWK_BOOKING_UNRESOLVED_PROVIDER_FIELDS.cancel_request,
    live_endpoint_authorized: false,
  };
}

export function evaluateRatehawkBookingVoucherContract() {
  return {
    ok: false,
    available: false,
    invoked: false,
    reason: "booking_voucher_unavailable",
    public_unauthenticated_url: false,
    requires: Object.freeze(["authenticated_customer", "privacy_safe_document"]),
    unresolved_provider_fields:
      RATEHAWK_BOOKING_UNRESOLVED_PROVIDER_FIELDS.voucher_request,
    live_endpoint_authorized: false,
  };
}

export function buildSafeBookingConfirmationDto({
  intent = {},
  claims = {},
  snapshot = {},
  payment = {},
  locale = "nl",
  confirmedAt = null,
} = {}) {
  const confirmed =
    intent.state === RATEHAWK_BOOKING_STATES.CONFIRMED &&
    Boolean(intent.provider_order_id) &&
    ["finish_status", "order_info"].includes(intent.provider_evidence_kind);
  if (confirmed !== true) {
    return {
      ok: true,
      confirmed: false,
      state: intent.state || null,
      reason:
        intent.state === RATEHAWK_BOOKING_STATES.CONFIRMATION_UNKNOWN
          ? "confirmation_unknown"
          : intent.reason || null,
      booking_attempt_id: intent.booking_attempt_id || null,
      revision: intent.revision ?? null,
      omitted: [...RATEHAWK_BOOKING_PRIVACY_OMISSIONS],
    };
  }
  return {
    ok: true,
    confirmed: true,
    state: RATEHAWK_BOOKING_STATES.CONFIRMED,
    provider_order_id: intent.provider_order_id,
    hid: claims.hid ?? null,
    hotel_identity: {
      hid: claims.hid ?? null,
      name: snapshot.hotel_name ?? null,
    },
    stay_dates: {
      checkin: claims.checkin ?? null,
      checkout: claims.checkout ?? null,
    },
    room_name: snapshot.room_name ?? null,
    meal_plan: snapshot.meal_plan ?? null,
    customer_total: snapshot.customer_total ?? null,
    included_taxes: snapshot.included_taxes ?? [],
    excluded_taxes: snapshot.excluded_taxes ?? [],
    payment: {
      type: payment.payment_type ?? snapshot.payment?.type ?? null,
      recipient: payment.payment_recipient ?? snapshot.payment?.recipient ?? null,
      timing: payment.payment_timing ?? snapshot.payment?.timing ?? null,
    },
    cancellation: snapshot.cancellation ?? null,
    no_show: snapshot.no_show ?? null,
    deposit: snapshot.deposit ?? null,
    booking_status: RATEHAWK_BOOKING_STATES.CONFIRMED,
    confirmed_at: confirmedAt,
    voucher_available: false,
    terms_revision: claims.terms_revision ?? null,
    locale,
    booking_attempt_id: intent.booking_attempt_id || null,
    revision: intent.revision ?? null,
    omitted: [...RATEHAWK_BOOKING_PRIVACY_OMISSIONS],
  };
}

export function buildRatehawkBookingConfirmationSnapshot({
  intent = {},
  claims = {},
  snapshot = {},
  payment = {},
  locale = "nl",
  confirmedAt = null,
} = {}) {
  if (
    intent.state !== RATEHAWK_BOOKING_STATES.CONFIRMED ||
    !intent.provider_order_id ||
    !["finish_status", "order_info"].includes(intent.provider_evidence_kind)
  ) {
    return { ok: false, reason: "provider_confirmation_evidence_required" };
  }
  return {
    ok: true,
    snapshot_kind: RATEHAWK_BOOKING_SNAPSHOT_KIND,
    immutable: true,
    hid: claims.hid ?? null,
    room_name: snapshot.room_name ?? null,
    meal_plan: snapshot.meal_plan ?? null,
    stay_dates: {
      checkin: claims.checkin ?? null,
      checkout: claims.checkout ?? null,
    },
    accepted_total: snapshot.customer_total ?? null,
    confirmed_total: snapshot.customer_total ?? null,
    currency: snapshot.customer_total?.currency ?? null,
    included_taxes: snapshot.included_taxes ?? [],
    excluded_taxes: snapshot.excluded_taxes ?? [],
    payment: {
      type: payment.payment_type ?? snapshot.payment?.type ?? null,
      recipient: payment.payment_recipient ?? snapshot.payment?.recipient ?? null,
      timing: payment.payment_timing ?? snapshot.payment?.timing ?? null,
    },
    cancellation: snapshot.cancellation ?? null,
    no_show: snapshot.no_show ?? null,
    deposit: snapshot.deposit ?? null,
    prebook_changes: claims.change_codes || [],
    terms_revision: claims.terms_revision ?? null,
    provider_order_id: intent.provider_order_id,
    locale,
    accepted_at: claims.accepted_at ?? claims.iat ?? null,
    confirmed_at: confirmedAt,
    booking_attempt_id: intent.booking_attempt_id || null,
    revision: intent.revision ?? null,
    omitted: [...RATEHAWK_BOOKING_PRIVACY_OMISSIONS],
  };
}

export function bookingCommercialBoundary(payment = {}) {
  return {
    fluxidi_role: "affiliate",
    fluxidi_is_merchant_of_record: false,
    customer_pays_fluxidi: false,
    mollie_involved: false,
    payment_type: payment.payment_type ?? null,
    payment_recipient: payment.payment_recipient ?? null,
    payment_timing: payment.payment_timing ?? null,
  };
}
