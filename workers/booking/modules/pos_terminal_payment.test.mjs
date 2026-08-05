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
