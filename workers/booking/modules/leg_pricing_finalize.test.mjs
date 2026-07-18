// FARE-ROUNDING-PLANNED-QUOTE-0_10-1 — tests for planned-quote leg finalization.
//
// Run: node --test workers/booking/modules/leg_pricing_finalize.test.mjs

import { test } from "node:test";
import assert from "node:assert/strict";

import { finalizeLegPricingInclVat } from "./leg_pricing_finalize.mjs";
import {
  roundFareCentsToNearestTenCents,
  roundFareEuroToNearestTenCents,
} from "../../shared/fluxidi_fare_rounding.mjs";

const incl = (euro, rate = 0) =>
  finalizeLegPricingInclVat({ rawInclVat: euro, vatRate: rate }).price_incl_vat;

test("single planned leg rounds to nearest €0.10 (half-up)", () => {
  assert.equal(incl(3.14), 3.1);
  assert.equal(incl(3.15), 3.2);
  assert.equal(incl(3.19), 3.2);
  assert.equal(incl(3.21), 3.2);
  assert.equal(incl(3.25), 3.3);
  assert.equal(incl(3.37), 3.4);
});

test("stored leg_price_incl_vat is always a €0.10 multiple", () => {
  for (const euro of [3.14, 3.19, 3.25, 12.24, 13.37, 99.99]) {
    const out = finalizeLegPricingInclVat({ rawInclVat: euro, vatRate: 0.06 });
    assert.equal(Math.round(out.price_incl_vat * 100) % 10, 0);
  }
});

test("net + VAT reconstruct the rounded incl-VAT exactly", () => {
  const out = finalizeLegPricingInclVat({ rawInclVat: 13.37, vatRate: 0.06 });
  assert.equal(out.price_incl_vat, 13.4);
  assert.equal(
    Math.round((out.price_ex_vat + out.price_vat) * 100) / 100,
    out.price_incl_vat,
  );
});

test("preview and create produce identical prices (deterministic)", () => {
  const preview = finalizeLegPricingInclVat({ rawInclVat: 3.37, vatRate: 0.06 });
  const create = finalizeLegPricingInclVat({ rawInclVat: 3.37, vatRate: 0.06 });
  assert.deepEqual(preview, create);
});

test("round trip: each leg rounded individually, total = sum of rounded legs", () => {
  const outbound = finalizeLegPricingInclVat({ rawInclVat: 13.37, vatRate: 0.06 });
  const ret = finalizeLegPricingInclVat({ rawInclVat: 12.24, vatRate: 0.06 });
  assert.equal(outbound.price_incl_vat, 13.4);
  assert.equal(ret.price_incl_vat, 12.2);
  // booking_total_eur = sum of the already-rounded legs (cent sum, NOT a second
  // €0.10 round on the parent total).
  const bookingTotalCents =
    Math.round(outbound.price_incl_vat * 100) + Math.round(ret.price_incl_vat * 100);
  assert.equal(bookingTotalCents, 2560);
  assert.equal(bookingTotalCents / 100, 25.6);
  // The parent total must not be re-dime-rounded (it already is a €0.10 sum).
  assert.equal(roundFareCentsToNearestTenCents(bookingTotalCents), 2560);
});

test("recurring: each occurrence leg is rounded individually (no cumulative round)", () => {
  const raws = [3.19, 3.21, 3.37, 3.14, 3.25];
  const rounded = raws.map((r) => finalizeLegPricingInclVat({ rawInclVat: r }).price_incl_vat);
  assert.deepEqual(rounded, [3.2, 3.2, 3.4, 3.1, 3.3]);
});

test("explicit requote of raw €3.19 becomes €3.20", () => {
  assert.equal(incl(3.19), 3.2);
});

test("finalizing an already-rounded amount is a no-op (idempotent retry)", () => {
  assert.equal(incl(3.2), 3.2);
  assert.equal(incl(13.4), 13.4);
  const first = finalizeLegPricingInclVat({ rawInclVat: 3.37, vatRate: 0.06 });
  const retry = finalizeLegPricingInclVat({ rawInclVat: first.price_incl_vat, vatRate: 0.06 });
  assert.equal(retry.price_incl_vat, first.price_incl_vat);
});

test("defensive: invalid / non-positive input yields zeros, never NaN", () => {
  for (const bad of [null, undefined, NaN, Infinity, -3.2, 0]) {
    const out = finalizeLegPricingInclVat({ rawInclVat: bad, vatRate: 0.06 });
    assert.equal(out.price_incl_vat, 0);
    assert.equal(out.price_ex_vat, 0);
    assert.equal(out.price_vat, 0);
  }
});

test("no floating-point drift: ten €3.20 legs sum to exactly €32.00", () => {
  let totalCents = 0;
  for (let i = 0; i < 10; i += 1) {
    totalCents += Math.round(incl(3.19) * 100); // raw 3.19 -> 3.20
  }
  assert.equal(totalCents, 3200);
  assert.equal(totalCents / 100, 32);
});

test("parity: leg finalize incl matches the shared canonical helper", () => {
  for (const euro of [3.14, 3.15, 3.19, 3.21, 3.25, 3.37, 12.24, 13.37, 99.95]) {
    const legIncl = finalizeLegPricingInclVat({ rawInclVat: euro, vatRate: 0.06 }).price_incl_vat;
    assert.equal(legIncl, roundFareEuroToNearestTenCents(euro));
    const cents = Math.round(euro * 100);
    assert.equal(Math.round(legIncl * 100), roundFareCentsToNearestTenCents(cents));
  }
});
