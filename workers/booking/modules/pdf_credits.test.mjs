import { test } from "node:test";
import assert from "node:assert/strict";

import {
  grantPurchasedPdfCredits,
  consumePdfCreation,
  resetIncludedPdfUsageForNewPeriod,
  projectLegacyPdfMonthlyAllowance,
  withLegacyPdfAllowanceProjection,
  sumPurchasedCreditsFromHistoryEntries,
  pdfPackCreditsForCode,
  clearPdfCancellationSchedules,
  includedPdfCap,
} from "./pdf_credits.mjs";
import { cascadeAddonCancellations } from "./subscription_cancellation.mjs";

test("verified pack grants exact credits; legacy projection mirrors SoT", () => {
  let p = { max_vehicles: 2, pdf_monthly_used: 0 };
  const g = grantPurchasedPdfCredits(p, {
    credits: 5000,
    grantedAt: "2026-06-28T07:45:03.923Z",
  });
  assert.equal(g.ok, true);
  assert.equal(g.profile.pdf_purchased_credits_remaining, 5000);
  assert.equal(g.profile.pdf_purchased_credits_granted_total, 5000);
  assert.equal(projectLegacyPdfMonthlyAllowance(g.profile), 5000);
  assert.equal(g.profile.pdf_monthly_allowance, 5000);
});

test("history rebuild for ddmh9g four packs = 7500 once", () => {
  const entries = [
    { addon_code: "pdf_1000", quantity: 1, activation_id: "a1", applied_at: "2026-06-28T06:30:34.305Z" },
    { addon_code: "pdf_500", quantity: 1, activation_id: "a2", applied_at: "2026-06-28T07:09:03.336Z" },
    { addon_code: "pdf_1000", quantity: 1, activation_id: "a3", applied_at: "2026-06-28T07:09:48.515Z" },
    { addon_code: "pdf_5000", quantity: 1, activation_id: "a4", applied_at: "2026-06-28T07:45:03.923Z" },
    // duplicate activation must not double-count
    { addon_code: "pdf_5000", quantity: 1, activation_id: "a4", applied_at: "2026-06-28T07:45:03.923Z" },
  ];
  const s = sumPurchasedCreditsFromHistoryEntries(entries);
  assert.equal(s.granted_total, 7500);
  assert.equal(s.remaining, 7500);
  assert.equal(pdfPackCreditsForCode("pdf_500"), 500);
});

test("included consumed first then purchased; insufficient fails without mutation", () => {
  let p = withLegacyPdfAllowanceProjection({
    max_vehicles: 2, // included cap 400
    pdf_monthly_used: 398,
    pdf_purchased_credits_remaining: 10,
  });
  const c1 = consumePdfCreation(p, { count: 3 });
  assert.equal(c1.ok, true);
  assert.equal(c1.consumed_included, 2);
  assert.equal(c1.consumed_purchased, 1);
  assert.equal(c1.profile.pdf_monthly_used, 400);
  assert.equal(c1.profile.pdf_purchased_credits_remaining, 9);
  assert.equal(c1.profile.pdf_monthly_allowance, 9);

  const fail = consumePdfCreation({
    max_vehicles: 2,
    pdf_monthly_used: 400,
    pdf_purchased_credits_remaining: 0,
  }, { count: 1 });
  assert.equal(fail.ok, false);
  assert.equal(fail.error, "insufficient_pdf_credits");
  assert.equal(fail.profile.pdf_purchased_credits_remaining, 0);
});

test("monthly reset preserves purchased credits", () => {
  const p = withLegacyPdfAllowanceProjection({
    max_vehicles: 2,
    pdf_monthly_used: 32,
    pdf_purchased_credits_remaining: 7500,
  });
  const r = resetIncludedPdfUsageForNewPeriod(p);
  assert.equal(r.pdf_monthly_used, 0);
  assert.equal(r.pdf_purchased_credits_remaining, 7500);
  assert.equal(r.pdf_monthly_allowance, 7500);
});

test("base cancel cascade excludes PDF packs and preserves purchased", () => {
  const p = {
    extra_vehicle_active_quantity: 1,
    extra_driver_active_quantity: 0,
    pdf500_active_quantity: 1,
    pdf1000_active_quantity: 2,
    pdf5000_active_quantity: 1,
    pdf_purchased_credits_remaining: 7500,
    pdf_monthly_allowance: 7500,
    current_period_end: "2026-09-11T16:44:36.124Z",
  };
  const c = cascadeAddonCancellations(p, {
    effectiveAt: "2026-09-11T16:44:36.124Z",
    requestedAt: "2026-08-13T10:00:00.000Z",
  });
  assert.equal(c.summary.pdf500, 0);
  assert.equal(c.summary.pdf1000, 0);
  assert.equal(c.summary.pdf5000, 0);
  assert.equal(c.profile.pdf500_cancel_at_period_end_quantity, 0);
  assert.equal(c.profile.pdf_purchased_credits_remaining, 7500);
  const cleared = clearPdfCancellationSchedules(c.profile);
  assert.equal(cleared.pdf5000_cancel_at_period_end_quantity, 0);
});

test("included cap and old-client projection never double-count", () => {
  assert.equal(includedPdfCap({ max_vehicles: 2 }), 400);
  const p = withLegacyPdfAllowanceProjection({
    pdf_purchased_credits_remaining: 7500,
    pdf_monthly_allowance: 99999, // stale legacy — overwritten by projection
  });
  assert.equal(p.pdf_monthly_allowance, 7500);
  assert.equal(p.pdf_purchased_credits_remaining, 7500);
});
