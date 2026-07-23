// STREET-RIDE-DURABLE-COMPLETION-2 — status projection for street/direct rides.
//
// Run: node --test workers/booking/modules/direct_ride_projection.test.mjs

import { test } from "node:test";
import assert from "node:assert/strict";

import {
  _isStreetDirectRecord,
  _projectionLifecycleStatusFromRecord,
  _flattenBookingForRidesList,
} from "./booking_read_model.js";

const streetRec = (over = {}) => ({
  booking_id: "street_1752863820000_ab12cd34",
  source: "street_ride",
  ride_type: "direct",
  status: over.status ?? "IN_PROGRESS",
  currency: "EUR",
  booking: {
    from: "A",
    to: "B",
    customer_name: "Straatrit",
    status: over.status ?? "IN_PROGRESS",
    ...(over.booking || {}),
  },
  quote: { from: "A", to: "B", pricing: {} },
  ...over,
});

const plannedRec = (over = {}) => ({
  booking_id: "BK-2026-000123",
  source: "planning",
  ride_type: "planned",
  status: over.status ?? "PENDING",
  booking: { from: "A", to: "B", status: over.status ?? "PENDING" },
  quote: { from: "A", to: "B", pricing: {} },
  ...over,
});

test("_isStreetDirectRecord matches street_ride / direct / street_ id, not planned", () => {
  assert.equal(_isStreetDirectRecord(streetRec()), true);
  assert.equal(_isStreetDirectRecord({ ride_type: "direct" }), true);
  assert.equal(_isStreetDirectRecord({ booking_id: "street_x" }), true);
  assert.equal(_isStreetDirectRecord(plannedRec()), false);
  assert.equal(_isStreetDirectRecord(null), false);
});

test("live street ride projects as ACTIVE (not generic PENDING)", () => {
  assert.equal(_projectionLifecycleStatusFromRecord(streetRec()), "ACTIVE");
});

test("completed street ride projects as COMPLETED", () => {
  assert.equal(
    _projectionLifecycleStatusFromRecord(streetRec({ status: "COMPLETED" })),
    "COMPLETED",
  );
});

test("cancelled street ride projects as CANCELLED", () => {
  assert.equal(
    _projectionLifecycleStatusFromRecord(streetRec({ status: "CANCELLED" })),
    "CANCELLED",
  );
});

test("planned customer booking lifecycle is unchanged (stays PENDING)", () => {
  assert.equal(_projectionLifecycleStatusFromRecord(plannedRec()), "PENDING");
  assert.equal(
    _projectionLifecycleStatusFromRecord(plannedRec({ status: "COMPLETED" })),
    "COMPLETED",
  );
});

test("ACTIVE / PENDING are non-terminal (stay in Available); COMPLETED/CANCELLED are terminal", () => {
  const terminal = (s) => s === "COMPLETED" || s === "CANCELLED";
  assert.equal(terminal(_projectionLifecycleStatusFromRecord(streetRec())), false);
  assert.equal(terminal(_projectionLifecycleStatusFromRecord(plannedRec())), false);
  assert.equal(
    terminal(_projectionLifecycleStatusFromRecord(streetRec({ status: "COMPLETED" }))),
    true,
  );
});

test("flatten row for a live street ride is ACTIVE", () => {
  const row = _flattenBookingForRidesList("street_1_ab", streetRec());
  assert.equal(row.status, "ACTIVE");
});

test("flatten row for a completed street ride is COMPLETED and surfaces the finalized fare", () => {
  const rec = streetRec({
    status: "COMPLETED",
    price_incl_vat: 3.2,
    booking: {
      from: "A",
      to: "B",
      status: "COMPLETED",
      price_incl_vat: 3.2,
      price: 3.2,
    },
  });
  const row = _flattenBookingForRidesList("street_1_ab", rec);
  assert.equal(row.status, "COMPLETED");
  assert.equal(row.price, 3.2);
});
