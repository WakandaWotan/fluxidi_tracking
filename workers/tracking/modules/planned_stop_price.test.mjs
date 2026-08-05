// PLANNED-RIDE-FIXED-PRICE-PRESENTATION-AND-DURABILITY-1
// Run: node --test workers/tracking/modules/planned_stop_price.test.mjs

import { test } from "node:test";
import assert from "node:assert/strict";
import {
  resolveCanonicalPlannedBookingFare,
  resolvePlannedStopTotalEur,
} from "./planned_stop_price.mjs";

test("planned STOP with missing client total_eur uses server booking price", () => {
  const out = resolvePlannedStopTotalEur({
    bookingRecord: { price_incl_vat: 42.5 },
    clientTotalEur: null,
  });
  assert.equal(out.total_eur, 42.5);
  assert.equal(out.source, "price_incl_vat");
  assert.equal(out.ignored_client_total, true);
});

test("planned STOP with client total_eur=0 uses valid server booking price", () => {
  const out = resolvePlannedStopTotalEur({
    bookingRecord: { price_incl_vat: 18 },
    clientTotalEur: 0,
  });
  assert.equal(out.total_eur, 18);
  assert.equal(out.source, "price_incl_vat");
});

test("manipulated client meter amount is ignored when booking price exists", () => {
  const out = resolvePlannedStopTotalEur({
    bookingRecord: { price_incl_vat: 30 },
    bookingDetails: { leg_price_incl_vat: 30 },
    clientTotalEur: 999.99,
  });
  assert.equal(out.total_eur, 30);
  assert.notEqual(out.total_eur, 999.99);
  assert.equal(out.ignored_client_total, true);
});

test("return leg uses price_incl_vat_return, not package total", () => {
  const out = resolveCanonicalPlannedBookingFare({
    bookingRecord: {
      price_incl_vat: 100,
      price_incl_vat_main: 60,
      price_incl_vat_return: 40,
    },
    legType: "return",
  });
  assert.equal(out.amount, 40);
  assert.equal(out.source, "price_incl_vat_return");
});

test("leg_price_incl_vat wins over package total", () => {
  const out = resolveCanonicalPlannedBookingFare({
    bookingDetails: {
      leg_price_incl_vat: 22.5,
      price_incl_vat: 100,
    },
    legId: "leg_out",
  });
  assert.equal(out.amount, 22.5);
  assert.equal(out.source, "leg_price_incl_vat");
});

test("offline reconcile preserves canonical planned price via existing trip", () => {
  const out = resolvePlannedStopTotalEur({
    bookingRecord: null,
    clientTotalEur: 0,
    existingTripTotalEur: 27.5,
  });
  assert.equal(out.total_eur, 27.5);
  assert.equal(out.source, "existing_trip");
});

test("never writes 0 when a valid booking price exists", () => {
  const out = resolvePlannedStopTotalEur({
    bookingRecord: { price_incl_vat: 12.5 },
    clientTotalEur: 0,
    existingTripTotalEur: 0,
  });
  assert.equal(out.total_eur, 12.5);
  assert.ok(out.total_eur > 0);
});

test("missing booking fare does not persist client meter as planned price", () => {
  const out = resolvePlannedStopTotalEur({
    bookingRecord: null,
    bookingDetails: null,
    clientTotalEur: 7.8,
  });
  assert.equal(out.total_eur, null);
  assert.equal(out.source, "missing");
});

test("payment/receipt/Billit projections stay outside fare resolver (pure)", () => {
  const booking = {
    price_incl_vat: 55,
    payment_status: "paid",
    receipt_reference: "R-1",
    billit_document_type: "invoice",
  };
  const before = JSON.stringify(booking);
  const out = resolvePlannedStopTotalEur({
    bookingRecord: booking,
    clientTotalEur: 1,
  });
  assert.equal(out.total_eur, 55);
  assert.equal(JSON.stringify(booking), before);
  assert.equal(booking.payment_status, "paid");
  assert.equal(booking.receipt_reference, "R-1");
  assert.equal(booking.billit_document_type, "invoice");
});
