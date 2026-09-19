// Pre-deploy safety check — choosing cash is not paying, but an authorized
// confirmation must still make a cash ride paid, refundable and creditable.
//
// Run:
//   node --test workers/booking/modules/cash_payment_authorization.test.mjs

import { test } from "node:test";
import assert from "node:assert/strict";

import {
  CANONICAL_PAID,
  CANONICAL_PENDING,
  CANONICAL_UNPAID,
  canonicalPaymentStatusFromProvider,
} from "./canonical_payment_truth.mjs";
import {
  _bookingRecordIsPaidForCredit,
  _resolveBookingRecordPaymentStatusForProjection,
} from "./booking_payment_classify.js";

/** A booking where the customer picked a method but nothing was collected. */
function methodChosenOnly(method) {
  return {
    booking_id: "bk_cash_safety",
    status: "COMPLETED",
    payment_method: method,
    payment_status: "unpaid",
  };
}

/**
 * Exactly what the driver receipt posts when the driver confirms the cash was
 * received (`_persistInCarPayment(method: 'cash')`), after an authenticated
 * driver or company-owner session.
 */
function cashConfirmedByDriver() {
  return {
    booking_id: "bk_cash_safety",
    status: "COMPLETED",
    payment_status: "paid",
    payment_method: "cash",
    payment_source: "in_car",
    payment_provider: "manual",
    paid_by_driver_id: "drv_1786881253086",
    paid_at: "2026-09-19T09:42:11.000Z",
    currency: "EUR",
  };
}

test("cash chosen but not received is unpaid", () => {
  const rec = methodChosenOnly("cash");
  assert.equal(_bookingRecordIsPaidForCredit(rec), false);
  assert.notEqual(_resolveBookingRecordPaymentStatusForProjection(rec), "paid");
  assert.equal(canonicalPaymentStatusFromProvider(rec.payment_status), CANONICAL_UNPAID);
});

test("cash explicitly received and auditably confirmed is paid", () => {
  const rec = cashConfirmedByDriver();
  assert.equal(canonicalPaymentStatusFromProvider(rec.payment_status), CANONICAL_PAID);
  assert.equal(_bookingRecordIsPaidForCredit(rec), true);
  assert.equal(_resolveBookingRecordPaymentStatusForProjection(rec), "paid");
  // The audit trail that makes it authorized rather than assumed.
  assert.ok(rec.paid_by_driver_id, "the confirming driver is recorded");
  assert.ok(rec.paid_at, "the moment of collection is recorded");
  assert.equal(rec.payment_source, "in_car");
  assert.equal(rec.payment_provider, "manual");
});

test("bancontact, card and QR chosen without provider confirmation are unpaid", () => {
  for (const method of ["bancontact", "card", "qr", "qr_code"]) {
    const rec = methodChosenOnly(method);
    assert.equal(
      _bookingRecordIsPaidForCredit(rec),
      false,
      `${method} must not be paid on choice alone`,
    );
  }
  const openCheckout = {
    booking_id: "bk_cash_safety",
    status: "COMPLETED",
    payment_method: "bancontact",
    payment_status: "open",
    mollie: { status: "open", payment_id: "tr_open" },
  };
  assert.equal(_bookingRecordIsPaidForCredit(openCheckout), false);
  assert.equal(canonicalPaymentStatusFromProvider("open"), CANONICAL_PENDING);
});

test("a verified provider payment is paid", () => {
  const rec = {
    booking_id: "bk_cash_safety",
    payment_status: "paid",
    payment_method: "bancontact",
    payment_provider: "mollie",
    payment_source: "online",
    mollie: { status: "paid", payment_id: "tr_verified" },
  };
  assert.equal(_bookingRecordIsPaidForCredit(rec), true);
  assert.equal(_resolveBookingRecordPaymentStatusForProjection(rec), "paid");
});

test("a manually confirmed QR or terminal payment is also paid", () => {
  for (const method of ["qr_code", "bancontact"]) {
    const rec = {
      ...cashConfirmedByDriver(),
      payment_method: method,
    };
    assert.equal(
      _bookingRecordIsPaidForCredit(rec),
      true,
      `${method} confirmed in car must stay paid`,
    );
  }
});

test("only a truly paid ride can be refunded or counted as paid credit", () => {
  // The refund and credit gates in the worker all read this one predicate.
  assert.equal(_bookingRecordIsPaidForCredit(methodChosenOnly("cash")), false);
  assert.equal(_bookingRecordIsPaidForCredit(cashConfirmedByDriver()), true);
  assert.equal(
    _bookingRecordIsPaidForCredit({ payment_status: "completed" }),
    false,
    "a completed ride is not a paid ride",
  );
  assert.equal(
    _bookingRecordIsPaidForCredit({ payment_status: "refunded" }),
    false,
    "a refunded ride is no longer paid",
  );
});

test("a confirmed cash ride does not become permanently unpaid", () => {
  const cancelledAfterCash = {
    ...cashConfirmedByDriver(),
    status: "CANCELLED",
    cancelled_at: "2026-09-19T10:05:00.000Z",
  };
  assert.equal(
    _bookingRecordIsPaidForCredit(cancelledAfterCash),
    true,
    "a cancelled but paid cash ride stays eligible for credit or refund",
  );
  const reloaded = JSON.parse(JSON.stringify(cashConfirmedByDriver()));
  assert.equal(
    _resolveBookingRecordPaymentStatusForProjection(reloaded),
    "paid",
    "reloading the record keeps the confirmed cash payment",
  );
});

test("an offline cash confirmation that later syncs is still paid", () => {
  const syncedLater = {
    ...cashConfirmedByDriver(),
    offline_cash_queued_at: "2026-09-19T09:41:00.000Z",
    synced_at: "2026-09-19T09:55:00.000Z",
  };
  assert.equal(_bookingRecordIsPaidForCredit(syncedLater), true);
});
