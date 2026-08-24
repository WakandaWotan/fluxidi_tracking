import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { applyCanonicalPaymentFieldsToTrackingTrip } from "./tracking_trip_payment_apply.mjs";

const worker = readFileSync(
  join(dirname(fileURLToPath(import.meta.url)), "..", "fluxidi_booking_worker.js"),
  "utf8",
);

test("cash in car writes trip root and booking_details paid", () => {
  const trip = applyCanonicalPaymentFieldsToTrackingTrip(
    {
      trip_id: "planned_2026-09-004_2026-09-004_outbound",
      payment_status: "unpaid",
      booking_details: {
        service_type: "limousine",
        payment_status: "unpaid",
      },
    },
    {
      payment_status: "paid",
      payment_method: "cash",
      payment_source: "in_car",
      payment_provider: "manual",
      payment_amount: 1060,
      paid_at: "2026-08-24T08:59:31.652Z",
    },
  );
  assert.equal(trip.payment_status, "paid");
  assert.equal(trip.paymentStatus, "paid");
  assert.equal(trip.payment_method, "cash");
  assert.equal(trip.payment_source, "in_car");
  assert.equal(trip.payment_amount, 1060);
  assert.equal(trip.booking_details.payment_status, "paid");
  assert.equal(trip.booking_details.paymentStatus, "paid");
  assert.equal(trip.booking_details.payment_method, "cash");
  assert.equal(trip.booking_details.payment_source, "in_car");
  assert.equal(trip.booking_details.payment_amount, 1060);
  assert.equal(trip.booking_details.service_type, "limousine");
});

test("creates booking_details when the trip row had none", () => {
  const trip = applyCanonicalPaymentFieldsToTrackingTrip(
    { trip_id: "planned_1" },
    { payment_status: "paid", payment_method: "cash" },
  );
  assert.equal(trip.booking_details.payment_status, "paid");
  assert.equal(trip.booking_details.payment_method, "cash");
});

test("booking worker syncs payment through the shared trip apply helper", () => {
  assert.match(worker, /applyCanonicalPaymentFieldsToTrackingTrip\(trip,/);
});
