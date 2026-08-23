// P3O — frozen accepted ride facts (pax/bags + cancellation terms).

import { test } from "node:test";
import assert from "node:assert/strict";
import {
  evaluateFrozenLimousineCancellation,
  freezeLimousineAcceptedRideFacts,
  limousineFrozenCancellationFieldsFromDecision,
  readFrozenLimousineCancellationTerms,
} from "./limousine_accepted_ride_facts.mjs";

test("pax 8 bags 2 stay 8/2 from the quotation snapshot", () => {
  const facts = freezeLimousineAcceptedRideFacts({
    requestSnapshot: { pax: 8, bags: 2 },
    offerTerms: {
      cancellation_deadline_hours: 24,
      cancellation_penalty_percent: 25,
      no_show_penalty_percent: 100,
      terms_revision: 4,
    },
    totals: { total_incl_vat_cents: 106000 },
  });
  assert.equal(facts.pax, 8);
  assert.equal(facts.bags, 2);
  assert.equal(facts.cancellation_deadline_hours, 24);
  assert.equal(facts.cancellation_penalty_percent, 25);
  assert.equal(facts.no_show_penalty_percent, 100);
  assert.equal(facts.cancellation_canonical_gross_cents, 106000);
  assert.equal(facts.cancellation_terms_source, "frozen_quotation");
});

test("pax 1 and pax 16 stay inside the limousine contract", () => {
  assert.equal(freezeLimousineAcceptedRideFacts({ requestSnapshot: { pax: 1 } }).pax, 1);
  assert.equal(freezeLimousineAcceptedRideFacts({ requestSnapshot: { pax: 16 } }).pax, 16);
  assert.equal(freezeLimousineAcceptedRideFacts({ requestSnapshot: { pax: 99 } }).pax, 16);
});

test("before deadline 0%, after 25% of 106000 = 26500, no-show 100%", () => {
  const terms = {
    cancellation_deadline_hours: 24,
    cancellation_penalty_percent: 25,
    no_show_penalty_percent: 100,
    cancellation_canonical_gross_cents: 106000,
    terms_revision: 4,
  };
  const before = evaluateFrozenLimousineCancellation({
    terms,
    pickupIso: "2026-09-02T10:00:00.000Z",
    now: new Date("2026-09-01T08:00:00.000Z"),
    paymentClass: "unpaid",
  });
  assert.equal(before.applicable_penalty_percent, 0);
  assert.equal(before.cancellation_penalty_cents, 0);
  assert.equal(before.allowed, true);

  const after = evaluateFrozenLimousineCancellation({
    terms,
    pickupIso: "2026-09-01T10:00:00.000Z",
    now: new Date("2026-09-01T09:00:00.000Z"),
    paymentClass: "unpaid",
  });
  assert.equal(after.applicable_penalty_percent, 25);
  assert.equal(after.cancellation_penalty_cents, 26500);
  assert.equal(after.outstanding_cancellation_cents, 26500);
  assert.equal(after.refund_required, false);

  const paid = evaluateFrozenLimousineCancellation({
    terms,
    pickupIso: "2026-09-01T10:00:00.000Z",
    now: new Date("2026-09-01T09:00:00.000Z"),
    paymentClass: "paid",
    paidAmountCents: 106000,
  });
  assert.equal(paid.refund_required, true);
  assert.equal(paid.refund_amount_cents, 79500);

  const noShow = evaluateFrozenLimousineCancellation({
    terms,
    pickupIso: "2026-08-01T10:00:00.000Z",
    now: new Date("2026-08-23T12:00:00.000Z"),
    paymentClass: "unpaid",
  });
  assert.equal(noShow.is_no_show, true);
  assert.equal(noShow.applicable_penalty_percent, 100);
  assert.equal(noShow.cancellation_penalty_cents, 106000);
});

test("later company policy is ignored when frozen terms exist on the booking", () => {
  const rec = {
    service_type: "limousine",
    cancellation_deadline_hours: 24,
    cancellation_penalty_percent: 25,
    no_show_penalty_percent: 100,
    cancellation_canonical_gross_cents: 106000,
    cancellation_terms_source: "frozen_quotation",
    quote: {
      limousine_accepted_price: {
        service_category: "limousine",
        cancellation_deadline_hours: 24,
        cancellation_penalty_percent: 25,
        no_show_penalty_percent: 100,
        cancellation_canonical_gross_cents: 106000,
        cancellation_terms_source: "frozen_quotation",
        terms_revision: 4,
      },
    },
  };
  const frozen = readFrozenLimousineCancellationTerms(rec);
  assert.equal(frozen.cancellation_deadline_hours, 24);
  assert.equal(frozen.cancellation_penalty_percent, 25);
  const decision = evaluateFrozenLimousineCancellation({
    terms: frozen,
    pickupIso: "2026-09-01T10:00:00.000Z",
    now: new Date("2026-09-01T09:00:00.000Z"),
    paymentClass: "unpaid",
  });
  assert.equal(decision.cutoff_minutes, 24 * 60);
  assert.equal(decision.applicable_penalty_percent, 25);
  const persist = limousineFrozenCancellationFieldsFromDecision(decision);
  assert.equal(persist.refund_required, false);
  assert.equal(persist.outstanding_cancellation_cents, 26500);
});

test("legacy taxi record without frozen terms is not treated as limousine", () => {
  assert.equal(
    readFrozenLimousineCancellationTerms({
      service_type: "taxi",
      payment_status: "unpaid",
    }),
    null,
  );
});
