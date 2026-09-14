import { test } from "node:test";
import assert from "node:assert/strict";

import {
  applyCompanyRoundtripFields,
  decorateAgendaItem,
  occupancyWindowsForRecord,
  occupancyWindowsFromTimes,
  parseCompanyRoundtripWrite,
  resolveBookingDurationMin,
  resolveBookingPriceInclVat,
  resolveRoundtripDispatchMode,
  shouldSplitOperationalReturnLeg,
} from "./modules/company_roundtrip.mjs";

test("existing decision table keeps airport wait out of split/continuous", () => {
  const split = {
    return_enabled: true,
    return_pickup_iso: "2026-09-18T12:00:00.000Z",
    wait_min: 0,
    ride_options: { wait_min: 45 },
  };
  assert.equal(resolveRoundtripDispatchMode(split), "split_no_wait");
  assert.equal(
    shouldSplitOperationalReturnLeg({
      returnEnabled: true,
      hasReturnSchedule: true,
      occupancyWaitMin: 0,
    }),
    true,
  );
  const continuous = {
    return_enabled: true,
    return_pickup_iso: "2026-09-18T12:00:00.000Z",
    occupancy_wait_min: 90,
    wait_min: 90,
    ride_options: { wait_min: 20 },
  };
  assert.equal(resolveRoundtripDispatchMode(continuous), "continuous_wait");
});

test("continuous occupancy is one window and does not add airport wait", () => {
  const windows = occupancyWindowsFromTimes({
    mode: "continuous_wait",
    pickupIso: "2026-09-19T08:00:00.000Z",
    durationMin: 45,
    returnPickupIso: "2026-09-19T11:00:00.000Z",
    returnDurationMin: 40,
  });
  assert.equal(windows.unknown, false);
  assert.equal(windows.windows.length, 1);
  assert.equal(windows.windows[0].start, Date.parse("2026-09-19T08:00:00.000Z"));
  assert.equal(windows.windows[0].end, Date.parse("2026-09-19T11:40:00.000Z"));
});

test("missing return duration keeps continuous occupancy unknown", () => {
  const windows = occupancyWindowsFromTimes({
    mode: "continuous_wait",
    pickupIso: "2026-09-19T08:00:00.000Z",
    durationMin: 45,
    returnPickupIso: "2026-09-19T11:00:00.000Z",
  });
  assert.equal(windows.unknown, true);
  assert.equal(windows.windows.length, 0);
});

test("split expands into outbound and return agenda items", () => {
  const parsed = parseCompanyRoundtripWrite({
    roundtrip_dispatch_mode: "split_no_wait",
    pickup_iso: "2026-09-18T06:00:00.000Z",
    duration_min: 40,
    from: "Gent",
    to: "Antwerpen",
    return_pickup_iso: "2026-09-18T12:00:00.000Z",
    return_duration_min: 40,
    assigned_driver_id: "drv_a",
    return_assigned_driver_id: "drv_b",
  });
  const record = applyCompanyRoundtripFields(
    {
      booking_id: "agb_demo",
      pickup_iso: parsed.pickupIso,
      duration_min: 40,
      booking: { from: "Gent", to: "Antwerpen" },
      ride_options: { wait_min: 15 },
    },
    parsed,
    { bookingId: "agb_demo", now: "2026-09-13T00:00:00.000Z" },
  );
  assert.equal(record.wait_min, 0);
  assert.equal(record.ride_options.wait_min, 15);
  assert.equal(record.operational_legs.length, 2);
  const items = decorateAgendaItem(
    {
      booking_id: "agb_demo",
      from: "Gent",
      to: "Antwerpen",
      pickup_iso: parsed.pickupIso,
      duration_min: 40,
      assigned_driver_id: "drv_a",
      ride_options: { wait_min: 15 },
    },
    record,
    "agb_demo",
  );
  assert.equal(items.length, 2);
  assert.equal(items[0].leg_type, "outbound");
  assert.equal(items[1].leg_type, "return");
  assert.equal(items[1].pickup_iso, "2026-09-18T12:00:00.000Z");
  assert.equal(items[1].assigned_driver_id, "drv_b");
  assert.equal(items[0].wait_min, 15);
});

test("cancelled split return stays off the agenda and frees that occupancy", () => {
  const parsed = parseCompanyRoundtripWrite({
    roundtrip_dispatch_mode: "split_no_wait",
    pickup_iso: "2026-09-17T08:00:00.000Z",
    duration_min: 40,
    from: "Gent",
    to: "Antwerpen",
    return_pickup_iso: "2026-09-17T14:00:00.000Z",
    return_duration_min: 40,
    assigned_driver_id: "drv_a",
  });
  const record = applyCompanyRoundtripFields(
    {
      booking_id: "agb_cancel_leg",
      pickup_iso: parsed.pickupIso,
      duration_min: 40,
      status: "PENDING",
      progress_state: "partially_cancelled",
      booking: { from: "Gent", to: "Antwerpen", status: "PENDING" },
    },
    parsed,
    { bookingId: "agb_cancel_leg", now: "2026-09-13T00:00:00.000Z" },
  );
  record.operational_legs = record.operational_legs.map((leg) =>
    String(leg.leg_type) === "return" ? { ...leg, status: "CANCELLED", lifecycle: "cancelled" } : leg,
  );
  const items = decorateAgendaItem(
    {
      booking_id: "agb_cancel_leg",
      from: "Gent",
      to: "Antwerpen",
      pickup_iso: parsed.pickupIso,
      duration_min: 40,
      assigned_driver_id: "drv_a",
      status: "PENDING",
    },
    record,
    "agb_cancel_leg",
  );
  assert.equal(items.length, 1);
  assert.equal(items[0].leg_type, "outbound");
  const occupancy = occupancyWindowsForRecord(record);
  assert.equal(occupancy.unknown, false);
  assert.equal(occupancy.windows.length, 1);
  assert.equal(occupancy.windows[0].start, Date.parse("2026-09-17T08:00:00.000Z"));
  assert.equal(occupancy.windows[0].end, Date.parse("2026-09-17T08:40:00.000Z"));
});

test("customer-app aliases keep duration and price for occupancy", () => {
  const record = {
    pickup_iso: "2026-09-15T08:00:00.000Z",
    booking: {
      pickup_iso: "2026-09-15T08:00:00.000Z",
      duration_route_min: 29,
      currency: "EUR",
    },
    quote: {
      duration_min: 29,
      pricing: { price_incl_vat: "46.70", currency: "EUR", pricing_source: "route_calc" },
    },
    operational_legs: [{ duration_min: 29, price_incl_vat: 46.7 }],
  };
  assert.equal(resolveBookingDurationMin(record), 29);
  assert.equal(resolveBookingPriceInclVat(record), 46.7);
  const occupancy = occupancyWindowsForRecord(record);
  assert.equal(occupancy.unknown, false);
  assert.equal(occupancy.windows[0].end, Date.parse("2026-09-15T08:29:00.000Z"));
});

test("legacy booking without duration stays unknown and does not crash", () => {
  const record = {
    pickup_iso: "2026-09-15T08:00:00.000Z",
    booking: { pickup_iso: "2026-09-15T08:00:00.000Z" },
  };
  assert.equal(resolveBookingDurationMin(record), null);
  assert.equal(resolveBookingPriceInclVat(record), null);
  const occupancy = occupancyWindowsForRecord(record);
  assert.equal(occupancy.unknown, true);
  assert.equal(occupancy.windows.length, 0);
});
