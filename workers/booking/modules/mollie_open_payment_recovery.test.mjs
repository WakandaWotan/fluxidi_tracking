// MOLLIE-OPEN-PAYMENT-RECOVERY-P0 — pure decision tests
// Run: node --test workers/booking/modules/mollie_open_payment_recovery.test.mjs

import { test } from "node:test";
import assert from "node:assert/strict";

import {
  buildOpenMollieCheckoutRecoveryPayload,
  isMollieProviderStatusPaid,
  isMollieProviderStatusReleased,
  normalizeMollieRecoveryAction,
  resolveMollieCancelReconcileOutcome,
  resolveMollieOpenPaymentCancelDecision,
  resolveMollieOpenPaymentPresentation,
} from "./mollie_open_payment_recovery.mjs";
import {
  manualMarkPaidConflict,
  readOpenStreetMollieCheckout,
} from "./street_mollie_checkout.js";

const openCheckout = {
  checkout_url: "https://www.mollie.com/checkout/test",
  payment_booking_id: "pay-shadow-1",
  mollie_payment_id: "tr_test1",
  mollie_status: "open",
};

test("1. open checkout + QR/manual attempt → recovery payload blocks fallback", () => {
  const payload = buildOpenMollieCheckoutRecoveryPayload(openCheckout);
  assert.equal(payload.error, "open_mollie_checkout_exists");
  assert.equal(payload.status, 409);
  assert.equal(payload.recovery.fallback_allowed, false);
  assert.ok(payload.recovery.actions.includes("refresh_status"));
  assert.ok(payload.recovery.actions.includes("resume_checkout"));
  assert.ok(payload.recovery.actions.includes("cancel_open_checkout"));
});

test("2. open checkout blocks POS-equivalent owner via same payload", () => {
  const payload = buildOpenMollieCheckoutRecoveryPayload(openCheckout);
  assert.equal(payload.requires_confirm_cancel_open_mollie, true);
  assert.equal(payload.recovery.cancel_allowed, true);
  assert.equal(payload.recovery.resumable, true);
});

test("3. refresh presentation while pending", () => {
  const pending = resolveMollieOpenPaymentPresentation({
    providerStatus: "open",
    hasCheckoutUrl: true,
  });
  assert.equal(pending.state, "pending");
  const refreshing = resolveMollieOpenPaymentPresentation({
    providerStatus: "open",
    hasCheckoutUrl: true,
    busy: "refreshing",
  });
  assert.equal(refreshing.state, "refreshing");
});

test("4. pending → paid presentation", () => {
  assert.equal(isMollieProviderStatusPaid("paid"), true);
  const paid = resolveMollieOpenPaymentPresentation({
    providerStatus: "paid",
    hasCheckoutUrl: true,
  });
  assert.equal(paid.state, "paid");
  assert.equal(paid.fallback_allowed, false);
  assert.equal(paid.cancel_allowed, false);
});

test("5+6. app resume / browser return keep pending until paid", () => {
  const pending = resolveMollieOpenPaymentPresentation({
    providerStatus: "pending",
    hasCheckoutUrl: true,
  });
  assert.equal(pending.state, "pending");
  assert.equal(pending.resumable, true);
  assert.equal(pending.fallback_allowed, false);
});

test("7. resume allowed only when checkout URL present", () => {
  assert.equal(
    resolveMollieOpenPaymentPresentation({
      providerStatus: "open",
      hasCheckoutUrl: false,
    }).resumable,
    false,
  );
  assert.equal(
    resolveMollieOpenPaymentPresentation({
      providerStatus: "open",
      hasCheckoutUrl: true,
    }).resumable,
    true,
  );
});

test("8. cancel pending succeeds gate", () => {
  const gate = resolveMollieOpenPaymentCancelDecision({
    providerStatus: "open",
  });
  assert.equal(gate.may_cancel, true);
  assert.equal(gate.action, "cancel");
});

test("9. cancel races with webhook paid → paid wins", () => {
  const before = resolveMollieOpenPaymentCancelDecision({
    providerStatus: "paid",
  });
  assert.equal(before.action, "reject_paid");
  assert.equal(before.may_cancel, false);
  const after = resolveMollieCancelReconcileOutcome({
    providerStatusAfter: "paid",
    cancelHttpOk: true,
  });
  assert.equal(after.action, "project_paid");
  assert.equal(after.may_manual_pay, false);
});

test("10. already-paid payment cannot be canceled", () => {
  assert.equal(
    resolveMollieOpenPaymentCancelDecision({
      localPaymentStatus: "paid",
    }).may_cancel,
    false,
  );
});

test("11. expired payment releases owner", () => {
  const gate = resolveMollieOpenPaymentCancelDecision({
    providerStatus: "expired",
  });
  assert.equal(gate.release_owner, true);
  assert.equal(gate.fallback_allowed, true);
  assert.equal(
    resolveMollieOpenPaymentPresentation({ providerStatus: "expired" }).state,
    "expired",
  );
});

test("12. failed payment releases owner", () => {
  assert.equal(isMollieProviderStatusReleased("failed"), true);
  assert.equal(
    resolveMollieOpenPaymentPresentation({ providerStatus: "failed" })
      .fallback_allowed,
    true,
  );
});

test("13. canceled payment releases owner", () => {
  const reconcile = resolveMollieCancelReconcileOutcome({
    providerStatusAfter: "canceled",
    cancelHttpOk: true,
  });
  assert.equal(reconcile.release_owner, true);
  assert.equal(reconcile.may_manual_pay, true);
});

test("14. repeated refresh action normalizes idempotently", () => {
  assert.equal(normalizeMollieRecoveryAction("refresh"), "refresh");
  assert.equal(normalizeMollieRecoveryAction("refresh_status"), "refresh");
  assert.equal(normalizeMollieRecoveryAction("status"), "refresh");
});

test("15. repeated cancel action normalizes idempotently", () => {
  assert.equal(normalizeMollieRecoveryAction("cancel"), "cancel");
  assert.equal(normalizeMollieRecoveryAction("cancel_open_checkout"), "cancel");
});

test("16. weak network / recovery error keeps owner (no fallback)", () => {
  const err = resolveMollieOpenPaymentPresentation({
    providerStatus: "open",
    hasCheckoutUrl: true,
    recoveryError: true,
  });
  assert.equal(err.state, "recoveryError");
  assert.equal(err.fallback_allowed, false);
  assert.deepEqual(err.actions, ["refresh_status"]);
});

test("17. manualMarkPaidConflict surfaces recovery (no duplicate create)", () => {
  const rec = {
    payment_status: "pending",
    payment_provider: "mollie",
    payment_mode: "mollie",
    checkout_url: openCheckout.checkout_url,
    payment_booking_id: openCheckout.payment_booking_id,
    mollie: { id: "tr_test1", payment_id: "tr_test1", status: "open" },
  };
  assert.ok(readOpenStreetMollieCheckout(rec));
  const conflict = manualMarkPaidConflict(rec, { confirmCancelOpenMollie: false });
  assert.equal(conflict.error, "open_mollie_checkout_exists");
  assert.equal(conflict.recovery.fallback_allowed, false);
  assert.ok(conflict.recovery.actions.includes("cancel_open_checkout"));
});

test("18. paid presentation forbids cancel and fallback", () => {
  const paid = resolveMollieOpenPaymentPresentation({ providerStatus: "paid" });
  assert.equal(paid.cancel_allowed, false);
  assert.equal(paid.fallback_allowed, false);
});

test("19+20. amount/ownership invariants stay outside this module (guards only)", () => {
  // Recovery decisions never invent amounts or second payments.
  assert.equal(normalizeMollieRecoveryAction("create"), "");
  assert.equal(
    resolveMollieCancelReconcileOutcome({
      providerStatusAfter: "open",
      cancelHttpOk: true,
    }).may_manual_pay,
    false,
  );
});
