// Dossier 02 — an unconfirmed payment may never read as Paid.
//
// Run:
//   node --test workers/booking/modules/canonical_payment_truth.test.mjs

import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

import {
  CANONICAL_FAILED,
  CANONICAL_PAID,
  CANONICAL_PENDING,
  CANONICAL_UNPAID,
  TOKENS_THAT_NEVER_IMPLY_PAID,
  canonicalPaidFromStatusTokens,
  canonicalPaymentStatusFromProvider,
  paymentMethodImpliesPaid,
  providerStatusIsVerifiedPaid,
} from "./canonical_payment_truth.mjs";
import {
  _bookingRecordIsPaidForCredit,
  _resolveBookingRecordPaymentStatusForProjection,
} from "./booking_payment_classify.js";

const WORKER_SOURCE = readFileSync(
  new URL("../fluxidi_booking_worker.js", import.meta.url),
  "utf8",
);

test("only a verified provider paid is paid", () => {
  assert.equal(providerStatusIsVerifiedPaid("paid"), true);
  assert.equal(providerStatusIsVerifiedPaid("PAID"), true);
  assert.equal(canonicalPaymentStatusFromProvider("paid"), CANONICAL_PAID);
});

test("pending, failed, canceled and expired never become paid", () => {
  assert.equal(canonicalPaymentStatusFromProvider("open"), CANONICAL_PENDING);
  assert.equal(canonicalPaymentStatusFromProvider("pending"), CANONICAL_PENDING);
  assert.equal(canonicalPaymentStatusFromProvider("authorized"), CANONICAL_PENDING);
  assert.equal(canonicalPaymentStatusFromProvider("failed"), CANONICAL_FAILED);
  assert.equal(canonicalPaymentStatusFromProvider("canceled"), CANONICAL_FAILED);
  assert.equal(canonicalPaymentStatusFromProvider("cancelled"), CANONICAL_FAILED);
  assert.equal(canonicalPaymentStatusFromProvider("expired"), CANONICAL_FAILED);
});

test("a settlement batch is not a customer payment", () => {
  assert.equal(providerStatusIsVerifiedPaid("settled"), false);
  assert.equal(canonicalPaymentStatusFromProvider("settled"), CANONICAL_PENDING);
});

test("an unknown token falls to unpaid, never to paid", () => {
  assert.equal(canonicalPaymentStatusFromProvider(""), CANONICAL_UNPAID);
  assert.equal(canonicalPaymentStatusFromProvider(null), CANONICAL_UNPAID);
  assert.equal(canonicalPaymentStatusFromProvider("online_weirdness"), CANONICAL_UNPAID);
});

test("ride lifecycle and method tokens never imply paid", () => {
  for (const token of TOKENS_THAT_NEVER_IMPLY_PAID) {
    assert.equal(
      providerStatusIsVerifiedPaid(token),
      false,
      `${token} must not be a verified settlement`,
    );
    assert.notEqual(
      canonicalPaymentStatusFromProvider(token),
      CANONICAL_PAID,
      `${token} must not map to canonical paid`,
    );
  }
  assert.equal(paymentMethodImpliesPaid(), false);
});

test("the webhook marker is the only non-status paid signal", () => {
  assert.equal(canonicalPaidFromStatusTokens(["pending"]), false);
  assert.equal(
    canonicalPaidFromStatusTokens(["pending"], { verifiedPaidFlag: true }),
    true,
  );
  assert.equal(canonicalPaidFromStatusTokens(["paid"]), true);
  assert.equal(canonicalPaidFromStatusTokens(null), false);
});

test("PLN-2026-000431 shape: completed ride with an unconfirmed payment is not paid", () => {
  const rec = {
    booking_id: "bk_pln_2026_000431",
    status: "completed",
    payment_status: "open",
    payment_method: "bancontact",
    mollie: { status: "open", payment_id: "tr_unconfirmed_431" },
    billit: { invoice_id: "BILLIT-2026-000431" },
  };
  assert.equal(_bookingRecordIsPaidForCredit(rec), false);
  assert.notEqual(_resolveBookingRecordPaymentStatusForProjection(rec), "paid");
});

test("a completed ride alone is not paid in the list projection", () => {
  const rec = { status: "completed", payment_status: "completed" };
  assert.equal(_bookingRecordIsPaidForCredit(rec), false);
  assert.notEqual(_resolveBookingRecordPaymentStatusForProjection(rec), "paid");
});

test("a confirmed booking alone is not paid", () => {
  assert.equal(_bookingRecordIsPaidForCredit({ payment_status: "confirmed" }), false);
  assert.equal(_bookingRecordIsPaidForCredit({ payment_status: "success" }), false);
  assert.equal(_bookingRecordIsPaidForCredit({ payment_status: "captured" }), false);
});

test("a verified Mollie paid still projects as paid", () => {
  const rec = {
    payment_status: "paid",
    mollie: { status: "paid", payment_id: "tr_verified" },
  };
  assert.equal(_bookingRecordIsPaidForCredit(rec), true);
  assert.equal(_resolveBookingRecordPaymentStatusForProjection(rec), "paid");
});

test("a double webhook for the same payment stays paid exactly once", () => {
  const rec = { payment_status: "paid", mollie: { status: "paid" } };
  const first = _resolveBookingRecordPaymentStatusForProjection(rec);
  const second = _resolveBookingRecordPaymentStatusForProjection({ ...rec });
  assert.equal(first, "paid");
  assert.equal(second, "paid");
});

test("a return from checkout without a webhook stays pending", () => {
  const rec = {
    payment_status: "open",
    payment_method: "bancontact",
    mollie: { status: "open" },
  };
  assert.equal(_bookingRecordIsPaidForCredit(rec), false);
  assert.equal(canonicalPaymentStatusFromProvider(rec.payment_status), CANONICAL_PENDING);
});

test("the authoritative writer no longer defaults unknown statuses to paid", () => {
  assert.ok(
    WORKER_SOURCE.includes('from "./modules/canonical_payment_truth.mjs"'),
    "worker must import the canonical payment truth",
  );
  assert.ok(
    WORKER_SOURCE.includes("canonicalPaymentStatusFromProvider("),
    "the authoritative writer must classify through the shared module",
  );
  const legacyDefault = /\? "pending"[\s\S]{0,400}?: "paid";/.test(WORKER_SOURCE);
  assert.equal(legacyDefault, false, "the fall-through to paid must be gone");
});

test("the classifier treats only paid as paid-like", () => {
  const classifier = readFileSync(
    new URL("./booking_payment_classify.js", import.meta.url),
    "utf8",
  );
  for (const token of ["completed", "confirmed", "success", "succeeded", "captured"]) {
    assert.ok(
      !new RegExp(`paidLike[\\s\\S]{0,400}"${token}"`).test(classifier),
      `${token} must not be paid-like`,
    );
  }
  assert.ok(
    classifier.includes("providerStatusIsVerifiedPaid"),
    "the classifier must use the shared verified-paid rule",
  );
});
