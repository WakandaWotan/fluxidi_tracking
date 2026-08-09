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
  resolveMollieRecoveryWhenProviderFetchFailed,
  resolveMollieUserCancelOwnershipOutcome,
  resolveOpenPosBlocksNewStreetCheckout,
  resolvePendingLockClearAfterCancel,
} from "./mollie_open_payment_recovery.mjs";
import {
  isStreetCheckoutOwnershipAbandoned,
  manualMarkPaidConflict,
  readOpenStreetMollieCheckout,
  webhookAfterManualPaidConflict,
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

test("16b. provider GET failure never invents cancel_not_confirmed from local open", () => {
  const out = resolveMollieRecoveryWhenProviderFetchFailed({
    action: "cancel",
    hasCheckoutUrl: true,
    openCheckout,
  });
  assert.equal(out.ok, false);
  assert.equal(out.error, "provider_status_unavailable");
  assert.notEqual(out.error, "cancel_not_confirmed");
  assert.equal(out.release_owner, false);
  assert.equal(out.fallback_allowed, false);
  assert.equal(out.presentation_state, "recoveryError");
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

test("21. open POS blocks minting a new street checkout", () => {
  const blocked = resolveOpenPosBlocksNewStreetCheckout({
    posProviderStatus: "open",
    cancelReleased: false,
  });
  assert.equal(blocked.blocks, true);
  assert.equal(blocked.error, "open_pos_payment_exists");
  assert.equal(blocked.creates_new_mollie_payment, false);
});

test("22. released POS allows new street checkout (Tap after cancel)", () => {
  const allowed = resolveOpenPosBlocksNewStreetCheckout({
    posProviderStatus: "canceled",
    cancelReleased: true,
  });
  assert.equal(allowed.blocks, false);
  assert.equal(allowed.creates_new_mollie_payment, true);
});

test("23. pending lock clears only after authoritative cancel/abandon", () => {
  const stillOpen = resolvePendingLockClearAfterCancel({
    providerStatusAfter: "open",
    cancelHttpOk: true,
  });
  assert.equal(stillOpen.clear_local_lock, false);
  assert.equal(stillOpen.payment_status, "pending");

  const canceled = resolvePendingLockClearAfterCancel({
    providerStatusAfter: "canceled",
    cancelHttpOk: true,
  });
  assert.equal(canceled.clear_local_lock, true);
  assert.equal(canceled.payment_status, "unpaid");

  const abandoned = resolvePendingLockClearAfterCancel({
    providerStatusAfter: "abandoned",
    cancelHttpOk: false,
  });
  assert.equal(abandoned.clear_local_lock, true);
});

test("24. paid payment can never be cancelled locally into unpaid", () => {
  const paid = resolvePendingLockClearAfterCancel({
    providerStatusAfter: "paid",
    cancelHttpOk: true,
    localWasPaid: false,
  });
  assert.equal(paid.clear_local_lock, false);
  assert.equal(paid.payment_status, "paid");
  assert.equal(paid.error, "payment_already_paid");

  const localPaid = resolvePendingLockClearAfterCancel({
    providerStatusAfter: "open",
    cancelHttpOk: true,
    localWasPaid: true,
  });
  assert.equal(localPaid.clear_local_lock, false);
  assert.equal(localPaid.payment_status, "paid");
});

test("25. repeated cancel/recheck is idempotent once released", () => {
  const first = resolveMollieOpenPaymentCancelDecision({
    providerStatus: "canceled",
  });
  const second = resolveMollieOpenPaymentCancelDecision({
    providerStatus: "canceled",
  });
  assert.equal(first.action, "already_released");
  assert.equal(second.action, "already_released");
  assert.equal(first.release_owner, true);
  assert.equal(second.release_owner, true);
});

test("26. late webhook from abandoned/other Mollie cannot create double-paid", () => {
  const alreadyPaid = {
    payment_status: "paid",
    payment_provider: "mollie",
    payment_mode: "mollie",
    payment_id: "tr_street_paid",
    mollie: { id: "tr_street_paid", payment_id: "tr_street_paid", status: "paid" },
  };
  const conflict = webhookAfterManualPaidConflict(alreadyPaid, "tr_abandoned_pos");
  assert.equal(conflict.error, "payment_reconciliation_conflict");
  assert.equal(conflict.reason, "canonical_already_paid_different_mollie");

  const cashPaid = {
    payment_status: "paid",
    payment_provider: "manual",
    payment_mode: "manual",
  };
  const cashConflict = webhookAfterManualPaidConflict(cashPaid, "tr_abandoned_pos");
  assert.equal(cashConflict.error, "payment_reconciliation_conflict");
  assert.equal(cashConflict.reason, "canonical_already_paid_manual");
});

test("27. resume keeps single owner (no second create signal)", () => {
  const pending = resolveMollieOpenPaymentPresentation({
    providerStatus: "open",
    hasCheckoutUrl: true,
  });
  assert.equal(pending.resumable, true);
  assert.ok(pending.actions.includes("resume_checkout"));
  assert.equal(normalizeMollieRecoveryAction("resume"), "resume");
});

test("28. user cancel while Mollie open → abandon ownership; DELETE not required", () => {
  const out = resolveMollieUserCancelOwnershipOutcome({ providerStatus: "open" });
  assert.equal(out.action, "abandon_checkout");
  assert.equal(out.release_owner, true);
  assert.equal(out.fallback_allowed, true);
  assert.equal(out.ownership_status, "abandoned");
  assert.equal(out.provider_status, "open");
  assert.equal(out.forge_provider_status, false);
  assert.equal(out.user_abandoned, true);
});

test("29. user cancel paid race → paid wins; no fallback", () => {
  const out = resolveMollieUserCancelOwnershipOutcome({ providerStatus: "paid" });
  assert.equal(out.action, "project_paid");
  assert.equal(out.release_owner, false);
  assert.equal(out.fallback_allowed, false);
  assert.equal(out.presentation_state, "paid");
});

test("30. user cancel already canceled/expired/failed → fallback enabled", () => {
  for (const status of ["canceled", "expired", "failed"]) {
    const out = resolveMollieUserCancelOwnershipOutcome({
      providerStatus: status,
    });
    assert.equal(out.release_owner, true);
    assert.equal(out.fallback_allowed, true);
    assert.equal(out.ownership_status, "abandoned");
  }
});

test("31. abandoned ownership ignores stale checkout_url/open", () => {
  const abandoned = {
    payment_status: "unpaid",
    payment_provider: "mollie",
    payment_mode: "mollie",
    payment_attempt_status: "abandoned",
    mollie_checkout_abandoned: true,
    checkout_url: "https://www.mollie.com/checkout/stale",
    mollie: { id: "tr_stale", status: "open" },
  };
  assert.equal(isStreetCheckoutOwnershipAbandoned(abandoned), true);
  assert.equal(readOpenStreetMollieCheckout(abandoned), null);
});

test("32. repeated user-cancel abandon decision is idempotent", () => {
  const first = resolveMollieUserCancelOwnershipOutcome({
    providerStatus: "open",
  });
  const second = resolveMollieUserCancelOwnershipOutcome({
    providerStatus: "open",
  });
  assert.deepEqual(first, second);
  assert.equal(first.release_owner, true);
});
