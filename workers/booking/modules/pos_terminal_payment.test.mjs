// TAP-TO-PAY-SERVER-CONTRACT-1 — tests for driver POS terminal helpers.
//
// Run: node --test workers/booking/modules/pos_terminal_payment.test.mjs

import { test } from "node:test";
import assert from "node:assert/strict";

import {
  resolveDriverPosTerminalAmount,
  normalizeDriverPosTerminalAmountFromRecord,
  classifyMolliePosStatus,
  molliePosStatusIsPaid,
  posTerminalIdempotencyDecision,
  posTerminalDiagnosticsLine,
  selectServerSidePosTerminal,
  posTerminalSnapshotModeMatches,
  maskPosTerminalId,
  validatePosDefaultTerminalCandidate,
  resolveEffectiveDefaultTerminalId,
  buildScopedDriverPosPaymentIntentKey,
  isBookingAlreadyPaid,
  isStreetDirectBookingRecord,
  shouldMarkBookingPaidFromPosStatus,
  shouldTriggerBillitSyncOnPosPaid,
  buildDriverPosCreateRequestContract,
  sanitizeMollieCreateRejection,
  buildDriverPosStartFailureDiagnostic,
  buildScopedDriverPosStartFailLatestKey,
  driverPosStartFailDiagContainsSecrets,
} from "./pos_terminal_payment.mjs";

const T = (id, extra = {}) => ({ id, status: "active", profile_id: "pfl_1", ...extra });

const plannedRec = (extra = {}) => ({
  currency: "EUR",
  leg_price_incl_vat: 22.5,
  price_incl_vat: 45.0,
  price_incl_vat_main: 25.0,
  price_incl_vat_return: 40.0,
  ...extra,
});

const streetRec = (extra = {}) => ({
  source: "street_ride",
  booking_id: "street_abc123",
  street_ride_fare_finalized: true,
  price_incl_vat: 18.6,
  currency: "EUR",
  ...extra,
});

// 1. planned uses fixed server price
test("planned uses fixed server price (leg_price_incl_vat)", () => {
  const out = resolveDriverPosTerminalAmount(plannedRec());
  assert.equal(out.ok, true);
  assert.equal(out.cents, 2250);
  assert.equal(out.value, "22.50");
  assert.equal(out.source, "leg_price_incl_vat");
  assert.equal(out.ignored_client, false);
});

// 2. street uses finalized fare
test("street uses finalized fare", () => {
  const out = resolveDriverPosTerminalAmount(streetRec());
  assert.equal(out.ok, true);
  assert.equal(out.cents, 1860);
  assert.equal(out.value, "18.60");
  assert.equal(out.source, "street_finalized");
});

// 3. client amount ignored (server amount always wins)
test("client amount ignored (client never wins)", () => {
  const out = resolveDriverPosTerminalAmount(plannedRec(), { clientAmountRaw: 99.99 });
  assert.equal(out.ok, true);
  assert.equal(out.cents, 2250);
  assert.equal(out.value, "22.50");
  assert.equal(out.ignored_client, true);
});

test("matching client amount is still ignored_client true", () => {
  const out = resolveDriverPosTerminalAmount(plannedRec(), { clientAmountRaw: 22.5 });
  assert.equal(out.ok, true);
  assert.equal(out.cents, 2250);
  assert.equal(out.ignored_client, true);
});

// 4. already-paid helper
test("isBookingAlreadyPaid detects canonical paid status", () => {
  assert.equal(isBookingAlreadyPaid({ payment_status: "paid" }), true);
  assert.equal(isBookingAlreadyPaid({ paymentStatus: "PAID" }), true);
  assert.equal(isBookingAlreadyPaid({ booking: { payment_status: "paid" } }), true);
  assert.equal(isBookingAlreadyPaid({ payment_status: "unpaid" }), false);
  assert.equal(isBookingAlreadyPaid({}), false);
});

// 5. no active terminal error from selectServerSidePosTerminal
test("no active terminal -> terminal_not_configured", () => {
  assert.equal(
    selectServerSidePosTerminal([], { profileId: "pfl_1" }).error,
    "terminal_not_configured",
  );
  assert.equal(
    selectServerSidePosTerminal([T("t1", { status: "inactive" })], { profileId: "pfl_1" }).error,
    "terminal_not_configured",
  );
});

// 6. idempotency reuse open
test("idempotency: open intent with payment_id -> reuse", () => {
  const d = posTerminalIdempotencyDecision({ payment_id: "tr_x", status: "open" });
  assert.equal(d.action, "reuse");
  assert.equal(d.paymentId, "tr_x");
});

test("idempotency: paid/failed/absent intent -> create", () => {
  assert.equal(
    posTerminalIdempotencyDecision({ payment_id: "tr_x", status: "paid" }).action,
    "create",
  );
  assert.equal(posTerminalIdempotencyDecision({}).action, "create");
});

// 7. only paid marks paid
test("shouldMarkBookingPaidFromPosStatus only for paid", () => {
  assert.equal(shouldMarkBookingPaidFromPosStatus("paid"), true);
  for (const s of ["settled", "authorized", "open", "pending", ""]) {
    assert.equal(shouldMarkBookingPaidFromPosStatus(s), false, s);
  }
});

test("molliePosStatusIsPaid only for the official `paid` status", () => {
  assert.equal(molliePosStatusIsPaid("paid"), true);
  for (const s of ["settled", "approved", "success", "authorized", "open"]) {
    assert.equal(molliePosStatusIsPaid(s), false, s);
  }
});

// 8. failed/canceled/expired not paid
test("failed/canceled/expired do not mark paid", () => {
  for (const s of ["failed", "canceled", "cancelled", "expired"]) {
    assert.equal(shouldMarkBookingPaidFromPosStatus(s), false, s);
    assert.equal(classifyMolliePosStatus(s), "failed");
    assert.equal(molliePosStatusIsPaid(s), false, s);
  }
});

test("classifyMolliePosStatus maps settled to pending (PAID-ONLY)", () => {
  assert.equal(classifyMolliePosStatus("paid"), "paid");
  assert.equal(classifyMolliePosStatus("settled"), "pending");
});

// 9. billit sync once helper
test("shouldTriggerBillitSyncOnPosPaid only on first paid transition", () => {
  assert.equal(shouldTriggerBillitSyncOnPosPaid({ wasAlreadyPaid: false, newlyPaid: true }), true);
  assert.equal(shouldTriggerBillitSyncOnPosPaid({ wasAlreadyPaid: true, newlyPaid: true }), false);
  assert.equal(shouldTriggerBillitSyncOnPosPaid({ wasAlreadyPaid: false, newlyPaid: false }), false);
});

// 10. return leg price
test("return leg uses price_incl_vat_return when leg_price absent", () => {
  const out = resolveDriverPosTerminalAmount(
    {
      currency: "EUR",
      price_incl_vat: 45.0,
      price_incl_vat_main: 25.0,
      price_incl_vat_return: 40.0,
    },
    { legType: "return" },
  );
  assert.equal(out.ok, true);
  assert.equal(out.cents, 4000);
  assert.equal(out.source, "price_incl_vat_return");
});

// 11. street not finalized rejected
test("street not finalized rejected", () => {
  const out = resolveDriverPosTerminalAmount(
    streetRec({ street_ride_fare_finalized: false, price_incl_vat: 18.6 }),
  );
  assert.equal(out.ok, false);
  assert.equal(out.error, "street_fare_not_finalized");
});

test("isStreetDirectBookingRecord detects street/direct ids", () => {
  assert.equal(isStreetDirectBookingRecord(streetRec()), true);
  assert.equal(isStreetDirectBookingRecord({ ride_type: "direct" }), true);
  assert.equal(isStreetDirectBookingRecord({ booking_id: "street_x" }), true);
  assert.equal(isStreetDirectBookingRecord(plannedRec()), false);
});

// 12. terminal selection single/default/required
test("exactly one suitable terminal is auto-selected", () => {
  const out = selectServerSidePosTerminal([T("term_only")], { profileId: "pfl_1" });
  assert.equal(out.ok, true);
  assert.equal(out.selection, "single");
  assert.equal(out.terminal.id, "term_only");
});

test("multiple terminals WITH matching default -> default selected", () => {
  const out = selectServerSidePosTerminal([T("t1"), T("t2")], {
    profileId: "pfl_1",
    defaultTerminalId: "t2",
  });
  assert.equal(out.ok, true);
  assert.equal(out.selection, "default");
  assert.equal(out.terminal.id, "t2");
});

test("multiple terminals without default -> terminal_selection_required", () => {
  const out = selectServerSidePosTerminal([T("t1"), T("t2")], { profileId: "pfl_1" });
  assert.equal(out.ok, false);
  assert.equal(out.error, "terminal_selection_required");
});

// Backward-compatible normalize wrapper (recovery WIP)
test("normalizeDriverPosTerminalAmountFromRecord omits source/ignored_client", () => {
  const out = normalizeDriverPosTerminalAmountFromRecord({
    price_incl_vat_cents: 320,
    currency: "EUR",
  });
  assert.deepEqual(out, { ok: true, currency: "EUR", cents: 320, value: "3.20" });
});

test("normalize from euro float when cents field absent", () => {
  const out = normalizeDriverPosTerminalAmountFromRecord({ price_incl_vat: 3.2 });
  assert.equal(out.ok, true);
  assert.equal(out.cents, 320);
});

test("buildScopedDriverPosPaymentIntentKey scopes tenant/company/booking/leg", () => {
  const key = buildScopedDriverPosPaymentIntentKey(
    { tenantId: "t1", companyId: "c9" },
    "bk_42",
    "leg_ret",
  );
  assert.equal(key, "tenant:t1:company:c9:mollie_driver_pos_intent:bk_42:leg_ret:v1");
  assert.equal(
    buildScopedDriverPosPaymentIntentKey({ tenantId: "t1", companyId: "c9" }, "bk_42", ""),
    "tenant:t1:company:c9:mollie_driver_pos_intent:bk_42:main:v1",
  );
});

test("validate default terminal candidate", () => {
  assert.equal(
    validatePosDefaultTerminalCandidate([T("t1")], "t_ghost", { profileId: "pfl_1" }).error,
    "terminal_not_found",
  );
});

test("resolveEffectiveDefaultTerminalId auto single", () => {
  const out = resolveEffectiveDefaultTerminalId([T("t1")], null, { profileId: "pfl_1" });
  assert.equal(out.defaultTerminalId, "t1");
  assert.equal(out.autoSingle, true);
});

test("posTerminalSnapshotModeMatches live vs test", () => {
  assert.equal(posTerminalSnapshotModeMatches({ testmode: false }, { expectTestmode: false }), true);
  assert.equal(posTerminalSnapshotModeMatches({ testmode: true }, { expectTestmode: false }), false);
});

test("maskPosTerminalId never exposes the full id", () => {
  const masked = maskPosTerminalId("term_1234567890");
  assert.notEqual(masked, "term_1234567890");
  assert.match(masked, /\*/);
});

test("diagnostics line is PII-free with required fields", () => {
  const line = posTerminalDiagnosticsLine({
    phase: "launch",
    amountCents: 320,
    currency: "EUR",
    providerStatus: "created",
    referencePresent: true,
    callbackPresent: true,
    paymentWritten: false,
    reason: "mollie_pos_create_ok",
  });
  assert.match(line, /^\[CARD_TERMINAL_PAYMENT\] /);
  assert.match(line, /amountCents=320/);
  assert.match(line, /paymentWritten=false/);
});

test("create request contract asserts pointofsale + terminal + EUR amount", () => {
  const contract = buildDriverPosCreateRequestContract({
    terminalId: "term_YAhfDhEbbbydgRaVLd4VJ",
    amount: { currency: "EUR", value: "43.60" },
    profileId: "pfl_53RM5gS9qZ",
    webhookUrl: "https://fluxidi-booking-api.fluxidi.workers.dev/webhook/mollie",
    redirectUrl: null,
    testmode: false,
  });
  assert.equal(contract.api, "POST /v2/payments");
  assert.equal(contract.method, "pointofsale");
  assert.equal(contract.terminalId, "term_YAhfDhEbbbydgRaVLd4VJ");
  assert.equal(contract.amount.currency, "EUR");
  assert.equal(contract.amount.value, "43.60");
  assert.equal(contract.profileId_present, true);
  assert.equal(contract.webhookUrl_present, true);
  assert.equal(contract.webhookUrl_host, "fluxidi-booking-api.fluxidi.workers.dev");
  assert.equal(contract.redirectUrl_present, false);
  assert.equal(contract.mollie_mode, "live");
  assert.equal(driverPosStartFailDiagContainsSecrets(contract), false);
});

test("sanitizeMollieCreateRejection keeps 4xx title/detail/field", () => {
  const out = sanitizeMollieCreateRejection({
    httpStatus: 422,
    body: {
      status: 422,
      title: "Unprocessable Entity",
      detail: "The terminal is not enabled for this profile",
      field: "terminalId",
    },
    requestId: "req_abc",
  });
  assert.equal(out.category, "mollie_http_4xx");
  assert.equal(out.http_status, 422);
  assert.equal(out.title, "Unprocessable Entity");
  assert.match(out.detail, /terminal is not enabled/);
  assert.equal(out.field, "terminalId");
  assert.equal(out.request_id, "req_abc");
});

test("sanitizeMollieCreateRejection keeps 5xx without inventing detail", () => {
  const out = sanitizeMollieCreateRejection({
    httpStatus: 503,
    body: { title: "Service Unavailable" },
  });
  assert.equal(out.category, "mollie_http_5xx");
  assert.equal(out.http_status, 503);
  assert.equal(out.title, "Service Unavailable");
  assert.equal(out.detail, null);
});

test("sanitizeMollieCreateRejection timeout/network does not invent provider body", () => {
  const out = sanitizeMollieCreateRejection({
    networkError: true,
    body: { title: "should_not_use", detail: "ignored" },
  });
  assert.equal(out.category, "mollie_network_error");
  assert.equal(out.http_status, null);
  assert.equal(out.title, null);
  assert.equal(out.detail, null);
  assert.equal(out.code, null);
});

test("start-fail diagnostic record is secret-free and latest-key scoped", () => {
  const rejection = sanitizeMollieCreateRejection({
    httpStatus: 422,
    body: {
      title: "Unprocessable Entity",
      detail: "The payment could not be created",
      code: "invalid_request",
    },
  });
  const contract = buildDriverPosCreateRequestContract({
    terminalId: "term_1",
    amount: { currency: "EUR", value: "43.60" },
    profileId: "pfl_1",
    webhookUrl: "https://example.test/webhook/mollie",
    testmode: false,
  });
  const diag = buildDriverPosStartFailureDiagnostic({
    scope: { tenant_id: "T1", company_id: "C1" },
    bookingId: "street_1786120995678_uupw9mnz",
    terminalId: "term_1",
    profileId: "pfl_1",
    amount: { currency: "EUR", value: "43.60" },
    testmode: false,
    requestContract: contract,
    rejection,
    attemptId: "att_test1",
    nowIso: "2026-08-08T05:00:00.000Z",
  });
  assert.equal(
    diag.keys.latest,
    buildScopedDriverPosStartFailLatestKey(
      { tenant_id: "T1", company_id: "C1" },
      "street_1786120995678_uupw9mnz",
    ),
  );
  assert.match(diag.keys.attempt, /att_test1/);
  assert.equal(diag.record.mollie_http_status, 422);
  assert.equal(diag.record.mollie_title, "Unprocessable Entity");
  assert.equal(diag.record.request_method, "pointofsale");
  assert.equal(diag.record.fluxidi_error, "mollie_terminal_payment_create_failed");
  assert.equal(driverPosStartFailDiagContainsSecrets(diag.record), false);
  assert.equal(
    driverPosStartFailDiagContainsSecrets({
      Authorization: "Bearer live_secret_token_value",
    }),
    true,
  );
});
