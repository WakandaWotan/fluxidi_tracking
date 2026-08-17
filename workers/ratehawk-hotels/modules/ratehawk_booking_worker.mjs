/**
 * Production Hotels Worker booking orchestration (P3A, mocked only).
 *
 * Booking proxies here through RATEHAWK_HOTELS only. Live form/finish/
 * status/order/info/cancel/voucher transports are forbidden. Acceptance
 * tokens are unsealed here; Booking never holds RateHawk credentials.
 */

import { isRatehawkIsolatedTestWorker } from "./ratehawk_test_activation.mjs";
import { RATEHAWK_PROVIDER, redactRatehawkSecrets } from "./ratehawk_provider.mjs";
import { openRatehawkAcceptedReference } from "./ratehawk_prebook_tokens.mjs";
import {
  RATEHAWK_BOOKING_CONFIRM_TRIGGER,
  RATEHAWK_BOOKING_FORM_TRIGGER,
  RATEHAWK_BOOKING_PRIVACY_OMISSIONS,
  RATEHAWK_BOOKING_READINESS,
  RATEHAWK_BOOKING_STATES,
  RATEHAWK_BOOKING_STATUS_TRIGGER,
  applyRatehawkBookingTransition,
  assertApprovedOpaquePaymentRef,
  assertRatehawkAcceptedBookingClaims,
  bookingCommercialBoundary,
  buildRatehawkBookingConfirmationSnapshot,
  buildSafeBookingConfirmationDto,
  confirmationUnknownMustNotRetry,
  evaluateRatehawkBookingCancelContract,
  evaluateRatehawkBookingVoucherContract,
  hasForbiddenPublicBookingClientControl,
  hasPublicBookingPanOrCvc,
  isRatehawkBookingFinishEnabled,
  isRatehawkBookingFormEnabled,
  isRatehawkBookingStatusEnabled,
} from "./ratehawk_booking_contract.mjs";
import {
  deriveRatehawkBookingAttemptId,
  emptyRatehawkBookingIntent,
  fingerprintAcceptedRef,
  resolveRatehawkBookingIntentStore,
} from "./ratehawk_booking_intent_store.mjs";
import { fetchRatehawkBookingForm } from "./ratehawk_booking_form_transport.mjs";
import { fetchRatehawkBookingFinish } from "./ratehawk_booking_finish_transport.mjs";
import { pollRatehawkBookingFinishStatus } from "./ratehawk_booking_status_transport.mjs";

export const RATEHAWK_HOTELS_BOOKING_FORM_PATH = "/internal/booking/form";
export const RATEHAWK_HOTELS_BOOKING_CONFIRM_PATH = "/internal/booking/confirm";
export const RATEHAWK_HOTELS_BOOKING_STATUS_PATH = "/internal/booking/status";

function _text(value, max = 200) {
  const text = String(value ?? "").trim();
  if (!text) return "";
  return text.length > max ? text.slice(0, max) : text;
}

function _locale(value) {
  const raw = _text(value, 8).toLowerCase();
  return ["nl", "en", "fr", "es"].includes(raw) ? raw : "nl";
}

function _existingActions() {
  return [
    "saved",
    "nearby_events",
    "taxi_to_this_event",
    "taxi_to_this_stay",
    "airport_transfer",
    "stay22_fallback_availability",
  ];
}

function _guard({ reason, extras = {}, payment = null, ...rest } = {}) {
  const merged = { ...extras, ...rest };
  return redactRatehawkSecrets({
    ok: true,
    invoked: false,
    binding_called: merged.binding_called === true,
    reason: reason || "booking_unavailable",
    state: merged.state || RATEHAWK_BOOKING_STATES.REJECTED,
    readiness: merged.readiness || RATEHAWK_BOOKING_READINESS.UNAVAILABLE,
    progress_blocked: true,
    accepted_ref: null,
    booking_attempt_id: merged.booking_attempt_id || null,
    revision: merged.revision ?? null,
    confirmation: null,
    dispute_snapshot: null,
    cancel: evaluateRatehawkBookingCancelContract(),
    voucher: evaluateRatehawkBookingVoucherContract(),
    stay22_fallback_retained: true,
    mobility_independent_of_ratehawk: true,
    existing_actions: _existingActions(),
    commercial: bookingCommercialBoundary(payment || merged.payment),
    omitted: [...RATEHAWK_BOOKING_PRIVACY_OMISSIONS],
    provider: RATEHAWK_PROVIDER,
    form_invoked: merged.form_invoked === true,
    unresolved_provider_fields: merged.unresolved_provider_fields || null,
  });
}

function _requestBody(body) {
  return body && typeof body === "object" && !Array.isArray(body) ? body : {};
}

function _guestComplete(body, requirements) {
  const guest = body.guest && typeof body.guest === "object" ? body.guest : {};
  const contact =
    body.contact && typeof body.contact === "object" ? body.contact : {};
  const missing = [];
  for (const row of requirements) {
    if (row.required !== true) continue;
    if (row.kind === "guest_first_name" && !_text(guest.first_name, 80)) {
      missing.push(row.kind);
    }
    if (row.kind === "guest_last_name" && !_text(guest.last_name, 80)) {
      missing.push(row.kind);
    }
    if (row.kind === "contact_email" && !_text(contact.email, 120)) {
      missing.push(row.kind);
    }
    if (row.kind === "contact_phone" && !_text(contact.phone, 40)) {
      missing.push(row.kind);
    }
  }
  return { complete: missing.length === 0, missing };
}

function _paymentTokenState(body, requirements, payment) {
  const needsToken =
    payment?.payment_type === "now" ||
    requirements.some((row) => row.kind === "provider_payment_token" && row.required);
  if (!needsToken) {
    return { required: false, present: false, ok: true, reason: null };
  }
  const checked = assertApprovedOpaquePaymentRef(body.provider_payment_ref);
  if (checked.ok !== true) {
    return {
      required: true,
      present: false,
      ok: false,
      reason: checked.reason,
    };
  }
  return { required: true, present: true, ok: true, reason: null };
}

async function _openAccepted(env, body, now) {
  if (hasPublicBookingPanOrCvc(body)) {
    return { ok: false, reason: "pan_or_cvc_forbidden" };
  }
  if (hasForbiddenPublicBookingClientControl(body)) {
    return { ok: false, reason: "client_control_forbidden" };
  }
  const opened = await openRatehawkAcceptedReference(env, body.accepted_ref, {
    now,
  });
  if (opened.ok !== true) {
    return { ok: false, reason: opened.reason || "rha1_invalid" };
  }
  const verified = assertRatehawkAcceptedBookingClaims(opened.claims, {
    env,
    expectedTermsRevision: _text(body.terms_revision, 120),
    context: {
      tenant_id: body.tenant_id,
      customer_id: body.customer_id,
      session_id: body.session_id,
    },
  });
  if (verified.ok !== true) {
    return verified;
  }
  return { ok: true, ...verified };
}

async function _loadOrCreateIntent({
  env,
  acceptedRef,
  claims,
  payment,
  locale,
  now,
  intentStore,
}) {
  const resolved = resolveRatehawkBookingIntentStore(env, intentStore);
  if (resolved.ok !== true) {
    return { ok: false, reason: resolved.reason };
  }
  const bookingAttemptId = await deriveRatehawkBookingAttemptId(acceptedRef);
  const fingerprint = await fingerprintAcceptedRef(acceptedRef);
  let record = await resolved.store.get(bookingAttemptId);
  if (!record) {
    record = emptyRatehawkBookingIntent({
      bookingAttemptId,
      acceptedRefFingerprint: fingerprint,
      hid: claims.hid,
      checkin: claims.checkin,
      checkout: claims.checkout,
      termsRevision: claims.terms_revision,
      paymentType: payment.payment_type,
      locale,
      now,
    });
    await resolved.store.put(record);
  }
  return { ok: true, store: resolved.store, record };
}

async function _advance(store, record, nextState, now, extra = {}) {
  const transition = applyRatehawkBookingTransition(record.state, nextState, {
    revision: record.revision,
    nextRevision: record.revision + 1,
  });
  if (transition.ok !== true) {
    if (transition.reason === "illegal_transition" && record.state === nextState) {
      return { ok: true, idempotent: true, record };
    }
    return transition;
  }
  const next = {
    ...record,
    ...extra,
    state: transition.state,
    revision: transition.revision,
    updated_at: Number(now),
  };
  const saved = await store.compareAndSwap(record.booking_attempt_id, record.revision, next);
  if (saved.ok !== true) {
    return { ok: false, reason: saved.reason || "revision_conflict" };
  }
  return { ok: true, record: saved.record };
}

function _formReadiness({ guest, paymentToken, payment }) {
  if (guest.complete !== true) {
    return {
      state: RATEHAWK_BOOKING_STATES.FORM_REQUIRED,
      readiness: RATEHAWK_BOOKING_READINESS.CUSTOMER_INPUT_REQUIRED,
    };
  }
  if (payment.payment_type === "now" && paymentToken.present !== true) {
    return {
      state: RATEHAWK_BOOKING_STATES.FORM_READY,
      readiness: RATEHAWK_BOOKING_READINESS.PROVIDER_PAYMENT_TOKEN_ACTION_REQUIRED,
    };
  }
  return {
    state: RATEHAWK_BOOKING_STATES.CUSTOMER_CONFIRMATION_REQUIRED,
    readiness: RATEHAWK_BOOKING_READINESS.READY_FOR_DELIBERATE_CONFIRMATION,
  };
}

export async function handleRatehawkBookingFormRequest({
  env = {},
  body = {},
  now = Date.now(),
  formTransport = null,
  intentStore = null,
} = {}) {
  if (isRatehawkIsolatedTestWorker(env)) {
    return _guard({ reason: "production_path_forbidden_on_test_worker" });
  }
  const requestBody = _requestBody(body);
  const trigger = _text(requestBody.trigger, 40) || RATEHAWK_BOOKING_FORM_TRIGGER;
  if (trigger !== RATEHAWK_BOOKING_FORM_TRIGGER) {
    return _guard({ reason: "unsupported_trigger" });
  }
  if (!isRatehawkBookingFormEnabled(env)) {
    return _guard({ reason: "booking_form_disabled" });
  }
  const opened = await _openAccepted(env, requestBody, now);
  if (opened.ok !== true) {
    return _guard({ reason: opened.reason, payment: opened.payment });
  }
  const locale = _locale(requestBody.locale);
  const loaded = await _loadOrCreateIntent({
    env,
    acceptedRef: requestBody.accepted_ref,
    claims: opened.claims,
    payment: opened.payment,
    locale,
    now,
    intentStore,
  });
  if (loaded.ok !== true) {
    return _guard({ reason: loaded.reason, payment: opened.payment });
  }
  if (confirmationUnknownMustNotRetry(loaded.record.state)) {
    return _guard({
      reason: "confirmation_unknown",
      state: loaded.record.state,
      booking_attempt_id: loaded.record.booking_attempt_id,
      revision: loaded.record.revision,
      payment: opened.payment,
    });
  }
  const form = await fetchRatehawkBookingForm({
    formTransport,
    bookHash: opened.claims.book_hash,
    matchHash: opened.claims.match_hash,
  });
  if (form.ok !== true) {
    return _guard({
      reason: form.reason || "booking_form_unavailable",
      extras: {
        booking_attempt_id: loaded.record.booking_attempt_id,
        revision: loaded.record.revision,
        form_invoked: form.invoked === true,
        unresolved_provider_fields: form.unresolved_provider_fields,
      },
      payment: opened.payment,
    });
  }
  const guest = _guestComplete(requestBody, form.requirements);
  const paymentToken = _paymentTokenState(
    requestBody,
    form.requirements,
    opened.payment,
  );
  if (paymentToken.reason === "pan_or_cvc_forbidden") {
    return _guard({
      reason: "pan_or_cvc_forbidden",
      booking_attempt_id: loaded.record.booking_attempt_id,
      payment: opened.payment,
    });
  }
  const readiness = _formReadiness({ guest, paymentToken, payment: opened.payment });
  const advanced = await _advance(
    loaded.store,
    loaded.record,
    readiness.state,
    now,
    {
      guest_fields_complete: guest.complete,
      payment_token_present: paymentToken.present,
    },
  );
  if (advanced.ok !== true) {
    return _guard({
      reason: advanced.reason,
      booking_attempt_id: loaded.record.booking_attempt_id,
      payment: opened.payment,
    });
  }
  return redactRatehawkSecrets({
    ok: true,
    invoked: false,
    form_invoked: true,
    reason: null,
    state: advanced.record.state,
    readiness: readiness.readiness,
    progress_blocked: readiness.readiness !== RATEHAWK_BOOKING_READINESS.READY_FOR_DELIBERATE_CONFIRMATION,
    required_fields: form.requirements,
    missing_fields: guest.missing,
    payment: {
      type: opened.payment.payment_type,
      recipient: opened.payment.payment_recipient,
      timing: opened.payment.payment_timing,
    },
    booking_attempt_id: advanced.record.booking_attempt_id,
    revision: advanced.record.revision,
    hashes_exposed: false,
    unresolved_provider_fields: form.unresolved_provider_fields,
    cancel: evaluateRatehawkBookingCancelContract(),
    voucher: evaluateRatehawkBookingVoucherContract(),
    stay22_fallback_retained: true,
    mobility_independent_of_ratehawk: true,
    existing_actions: _existingActions(),
    commercial: bookingCommercialBoundary(opened.payment),
    omitted: [...RATEHAWK_BOOKING_PRIVACY_OMISSIONS],
    provider: RATEHAWK_PROVIDER,
  });
}

export async function handleRatehawkBookingConfirmRequest({
  env = {},
  body = {},
  now = Date.now(),
  finishTransport = null,
  intentStore = null,
} = {}) {
  if (isRatehawkIsolatedTestWorker(env)) {
    return _guard({ reason: "production_path_forbidden_on_test_worker" });
  }
  const requestBody = _requestBody(body);
  const trigger =
    _text(requestBody.trigger, 40) || RATEHAWK_BOOKING_CONFIRM_TRIGGER;
  if (trigger !== RATEHAWK_BOOKING_CONFIRM_TRIGGER) {
    return _guard({ reason: "unsupported_trigger" });
  }
  if (!isRatehawkBookingFinishEnabled(env)) {
    return _guard({ reason: "booking_finish_disabled" });
  }
  const opened = await _openAccepted(env, requestBody, now);
  if (opened.ok !== true) {
    return _guard({ reason: opened.reason, payment: opened.payment });
  }
  if (requestBody.confirm !== true) {
    return _guard({
      reason: "deliberate_confirmation_required",
      payment: opened.payment,
    });
  }
  const locale = _locale(requestBody.locale);
  const loaded = await _loadOrCreateIntent({
    env,
    acceptedRef: requestBody.accepted_ref,
    claims: opened.claims,
    payment: opened.payment,
    locale,
    now,
    intentStore,
  });
  if (loaded.ok !== true) {
    return _guard({ reason: loaded.reason, payment: opened.payment });
  }
  const current = loaded.record;
  if (current.finish_transport_calls > 0 || confirmationUnknownMustNotRetry(current.state)) {
    return redactRatehawkSecrets({
      ok: true,
      invoked: false,
      finish_invoked: false,
      replayed: true,
      reason: current.state === RATEHAWK_BOOKING_STATES.CONFIRMATION_UNKNOWN
        ? "confirmation_unknown"
        : null,
      state: current.state,
      booking_attempt_id: current.booking_attempt_id,
      revision: current.revision,
      confirmation: buildSafeBookingConfirmationDto({
        intent: current,
        claims: opened.claims,
        snapshot: opened.snapshot,
        payment: opened.payment,
        locale,
        confirmedAt: current.updated_at,
      }),
      dispute_snapshot: null,
      cancel: evaluateRatehawkBookingCancelContract(),
      voucher: evaluateRatehawkBookingVoucherContract(),
      stay22_fallback_retained: true,
      mobility_independent_of_ratehawk: true,
      existing_actions: _existingActions(),
      commercial: bookingCommercialBoundary(opened.payment),
      omitted: [...RATEHAWK_BOOKING_PRIVACY_OMISSIONS],
      provider: RATEHAWK_PROVIDER,
    });
  }
  if (current.state !== RATEHAWK_BOOKING_STATES.CUSTOMER_CONFIRMATION_REQUIRED) {
    return _guard({
      reason: "form_not_ready_for_confirmation",
      state: current.state,
      booking_attempt_id: current.booking_attempt_id,
      revision: current.revision,
      payment: opened.payment,
    });
  }
  const submitted = await _advance(
    loaded.store,
    current,
    RATEHAWK_BOOKING_STATES.FINISH_SUBMITTED,
    now,
    {
      finish_submitted_at: Number(now),
      finish_transport_calls: 0,
    },
  );
  if (submitted.ok !== true) {
    return _guard({
      reason: submitted.reason,
      booking_attempt_id: current.booking_attempt_id,
      payment: opened.payment,
    });
  }
  const finish = await fetchRatehawkBookingFinish({
    finishTransport,
    bookingAttemptId: submitted.record.booking_attempt_id,
  });
  const counted = {
    ...submitted.record,
    finish_transport_calls: 1,
    updated_at: Number(now),
  };
  await loaded.store.put(counted);
  let nextState = RATEHAWK_BOOKING_STATES.CONFIRMATION_UNKNOWN;
  let extra = {
    confirmation_unknown_reason: finish.reason || "finish_ambiguous",
    finish_transport_calls: 1,
  };
  if (
    finish.ok === true &&
    finish.provider_order_id &&
    ["finish_status", "order_info"].includes(finish.provider_evidence_kind)
  ) {
    nextState = RATEHAWK_BOOKING_STATES.CONFIRMED;
    extra = {
      provider_order_id: finish.provider_order_id,
      provider_evidence_kind: finish.provider_evidence_kind,
      confirmation_unknown_reason: null,
      finish_transport_calls: 1,
    };
  } else if (finish.pending === true || (finish.ok === true && !finish.provider_order_id)) {
    nextState = RATEHAWK_BOOKING_STATES.PROVIDER_PENDING;
    extra = { finish_transport_calls: 1 };
  } else if (finish.declined === true) {
    nextState = RATEHAWK_BOOKING_STATES.PROVIDER_DECLINED;
    extra = {
      provider_evidence_kind: finish.provider_evidence_kind || "finish_status",
      finish_transport_calls: 1,
    };
  } else if (finish.ambiguous === true || finish.invoked !== true) {
    nextState = RATEHAWK_BOOKING_STATES.CONFIRMATION_UNKNOWN;
  } else if (finish.reason === "finish_timeout") {
    nextState = RATEHAWK_BOOKING_STATES.CONFIRMATION_UNKNOWN;
    extra.confirmation_unknown_reason = "finish_timeout";
  }
  const advanced = await _advance(loaded.store, counted, nextState, now, extra);
  if (advanced.ok !== true) {
    return _guard({
      reason: advanced.reason,
      state: RATEHAWK_BOOKING_STATES.CONFIRMATION_UNKNOWN,
      booking_attempt_id: counted.booking_attempt_id,
      payment: opened.payment,
    });
  }
  const snapshot = buildRatehawkBookingConfirmationSnapshot({
    intent: advanced.record,
    claims: opened.claims,
    snapshot: opened.snapshot,
    payment: opened.payment,
    locale,
    confirmedAt: Number(now),
  });
  return redactRatehawkSecrets({
    ok: true,
    invoked: false,
    finish_invoked: finish.invoked === true,
    replayed: false,
    reason:
      advanced.record.state === RATEHAWK_BOOKING_STATES.CONFIRMATION_UNKNOWN
        ? "confirmation_unknown"
        : advanced.record.state === RATEHAWK_BOOKING_STATES.PROVIDER_DECLINED
          ? "provider_declined"
          : null,
    state: advanced.record.state,
    booking_attempt_id: advanced.record.booking_attempt_id,
    revision: advanced.record.revision,
    confirmation: buildSafeBookingConfirmationDto({
      intent: advanced.record,
      claims: opened.claims,
      snapshot: opened.snapshot,
      payment: opened.payment,
      locale,
      confirmedAt: Number(now),
    }),
    dispute_snapshot: snapshot.ok === true ? snapshot : null,
    cancel: evaluateRatehawkBookingCancelContract(),
    voucher: evaluateRatehawkBookingVoucherContract(),
    stay22_fallback_retained: true,
    mobility_independent_of_ratehawk: true,
    existing_actions: _existingActions(),
    commercial: bookingCommercialBoundary(opened.payment),
    omitted: [...RATEHAWK_BOOKING_PRIVACY_OMISSIONS],
    provider: RATEHAWK_PROVIDER,
  });
}

export async function handleRatehawkBookingStatusRequest({
  env = {},
  body = {},
  now = Date.now(),
  statusTransport = null,
  intentStore = null,
  sleepImpl = null,
} = {}) {
  if (isRatehawkIsolatedTestWorker(env)) {
    return _guard({ reason: "production_path_forbidden_on_test_worker" });
  }
  const requestBody = _requestBody(body);
  const trigger =
    _text(requestBody.trigger, 40) || RATEHAWK_BOOKING_STATUS_TRIGGER;
  if (trigger !== RATEHAWK_BOOKING_STATUS_TRIGGER) {
    return _guard({ reason: "unsupported_trigger" });
  }
  if (!isRatehawkBookingStatusEnabled(env)) {
    return _guard({ reason: "booking_status_disabled" });
  }
  const opened = await _openAccepted(env, requestBody, now);
  if (opened.ok !== true) {
    return _guard({ reason: opened.reason, payment: opened.payment });
  }
  const locale = _locale(requestBody.locale);
  const loaded = await _loadOrCreateIntent({
    env,
    acceptedRef: requestBody.accepted_ref,
    claims: opened.claims,
    payment: opened.payment,
    locale,
    now,
    intentStore,
  });
  if (loaded.ok !== true) {
    return _guard({ reason: loaded.reason, payment: opened.payment });
  }
  const current = loaded.record;
  if (
    current.state !== RATEHAWK_BOOKING_STATES.PROVIDER_PENDING &&
    current.state !== RATEHAWK_BOOKING_STATES.FINISH_SUBMITTED
  ) {
    return redactRatehawkSecrets({
      ok: true,
      invoked: false,
      status_invoked: false,
      reason:
        current.state === RATEHAWK_BOOKING_STATES.CONFIRMATION_UNKNOWN
          ? "confirmation_unknown"
          : null,
      state: current.state,
      pending: current.state === RATEHAWK_BOOKING_STATES.PROVIDER_PENDING,
      booking_attempt_id: current.booking_attempt_id,
      revision: current.revision,
      confirmation: buildSafeBookingConfirmationDto({
        intent: current,
        claims: opened.claims,
        snapshot: opened.snapshot,
        payment: opened.payment,
        locale,
        confirmedAt: current.updated_at,
      }),
      cancel: evaluateRatehawkBookingCancelContract(),
      voucher: evaluateRatehawkBookingVoucherContract(),
      stay22_fallback_retained: true,
      mobility_independent_of_ratehawk: true,
      existing_actions: _existingActions(),
      commercial: bookingCommercialBoundary(opened.payment),
      omitted: [...RATEHAWK_BOOKING_PRIVACY_OMISSIONS],
      provider: RATEHAWK_PROVIDER,
    });
  }
  const polled = await pollRatehawkBookingFinishStatus({
    statusTransport,
    now,
    sleepImpl,
  });
  const pollCount = Number(current.status_poll_count || 0) + Number(polled.polls || 0);
  let nextState = current.state;
  let extra = { status_poll_count: pollCount };
  if (polled.status === "confirmed" && polled.provider_order_id) {
    nextState = RATEHAWK_BOOKING_STATES.CONFIRMED;
    extra.provider_order_id = polled.provider_order_id;
    extra.provider_evidence_kind = polled.provider_evidence_kind || "finish_status";
  } else if (polled.status === "declined") {
    nextState = RATEHAWK_BOOKING_STATES.PROVIDER_DECLINED;
    extra.provider_evidence_kind = polled.provider_evidence_kind || "finish_status";
  } else if (polled.status === "pending") {
    nextState = RATEHAWK_BOOKING_STATES.PROVIDER_PENDING;
  } else if (polled.reason === "live_booking_transport_forbidden") {
    nextState = RATEHAWK_BOOKING_STATES.CONFIRMATION_UNKNOWN;
    extra.confirmation_unknown_reason = "live_booking_transport_forbidden";
  } else {
    nextState = RATEHAWK_BOOKING_STATES.CONFIRMATION_UNKNOWN;
    extra.confirmation_unknown_reason = polled.reason || "status_poll_timeout";
  }
  const advanced = await _advance(loaded.store, current, nextState, now, extra);
  const record = advanced.ok === true ? advanced.record : current;
  return redactRatehawkSecrets({
    ok: true,
    invoked: false,
    status_invoked: polled.invoked === true,
    finish_resubmitted: false,
    polls: polled.polls || 0,
    reason:
      record.state === RATEHAWK_BOOKING_STATES.CONFIRMATION_UNKNOWN
        ? "confirmation_unknown"
        : record.state === RATEHAWK_BOOKING_STATES.PROVIDER_DECLINED
          ? "provider_declined"
          : null,
    state: record.state,
    pending: record.state === RATEHAWK_BOOKING_STATES.PROVIDER_PENDING,
    booking_attempt_id: record.booking_attempt_id,
    revision: record.revision,
    confirmation: buildSafeBookingConfirmationDto({
      intent: record,
      claims: opened.claims,
      snapshot: opened.snapshot,
      payment: opened.payment,
      locale,
      confirmedAt: Number(now),
    }),
    dispute_snapshot: buildRatehawkBookingConfirmationSnapshot({
      intent: record,
      claims: opened.claims,
      snapshot: opened.snapshot,
      payment: opened.payment,
      locale,
      confirmedAt: Number(now),
    }),
    cancel: evaluateRatehawkBookingCancelContract(),
    voucher: evaluateRatehawkBookingVoucherContract(),
    stay22_fallback_retained: true,
    mobility_independent_of_ratehawk: true,
    existing_actions: _existingActions(),
    commercial: bookingCommercialBoundary(opened.payment),
    omitted: [...RATEHAWK_BOOKING_PRIVACY_OMISSIONS],
    provider: RATEHAWK_PROVIDER,
  });
}
