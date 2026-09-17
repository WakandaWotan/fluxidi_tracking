import test from "node:test";
import assert from "node:assert/strict";
import {
  projectBookableVehicleOffers,
  filterVehiclesByRosterOffers,
  fleetPassengerSeats,
} from "./fleet_roster_availability.mjs";

function nightRoster() {
  return {
    timezone: "Europe/Brussels",
    explicitly_set: true,
    days: {
      mon: [{ start: "18:00", end: "02:00" }],
      tue: [{ start: "18:00", end: "02:00" }],
      wed: [{ start: "18:00", end: "02:00" }],
      thu: [{ start: "18:00", end: "02:00" }],
      fri: [{ start: "18:00", end: "02:00" }],
      sat: [{ start: "18:00", end: "02:00" }],
      sun: [{ start: "18:00", end: "02:00" }],
    },
  };
}

function dayRoster() {
  return {
    timezone: "Europe/Brussels",
    explicitly_set: true,
    days: {
      mon: [{ start: "09:00", end: "17:00" }],
      tue: [{ start: "09:00", end: "17:00" }],
      wed: [{ start: "09:00", end: "17:00" }],
      thu: [{ start: "09:00", end: "17:00" }],
      fri: [{ start: "09:00", end: "17:00" }],
      sat: [],
      sun: [],
    },
  };
}

function tesla() {
  return {
    vehicle_id: "vh_tesla",
    is_active: true,
    passenger_capacity: 4,
    assigned_driver_id: "drv_christophe",
    assigned_driver: { driver_id: "drv_christophe", first_name: "Christophe" },
  };
}

function cadillac() {
  return {
    vehicle_id: "vh_cadillac",
    is_active: true,
    passenger_capacity: 3,
    assigned_driver_id: "drv_wotan",
    assigned_driver: { driver_id: "drv_wotan", first_name: "Wotan" },
  };
}

function christophe() {
  return {
    driver_id: "drv_christophe",
    first_name: "Christophe",
    is_active: true,
    assigned_vehicle_id: "vh_tesla",
    weekly_roster: dayRoster(),
  };
}

function wotan() {
  return {
    driver_id: "drv_wotan",
    first_name: "Wotan",
    is_active: true,
    assigned_vehicle_id: "vh_cadillac",
    weekly_roster: nightRoster(),
  };
}

test("passenger seats prefer passenger_capacity and do not invent a default", () => {
  assert.equal(fleetPassengerSeats({ passenger_capacity: 3, seats: 5 }), 3);
  assert.equal(fleetPassengerSeats({}), null);
});

test("daytime offers hide Cadillac when only Wotan's night roster is linked", () => {
  const pickupMs = Date.parse("2026-09-17T12:00:00.000Z"); // 14:00 Brussels
  const offers = projectBookableVehicleOffers({
    vehicles: [tesla(), cadillac()],
    drivers: [christophe(), wotan()],
    pickupMs,
    durationMin: 40,
    pax: 2,
    nowMs: Date.parse("2026-09-17T10:00:00.000Z"),
  });
  const cadillacOffer = offers.find((row) => row.vehicle_id === "vh_cadillac");
  assert.equal(cadillacOffer.available, false);
});

test("22:00 night shift offers Cadillac+Wotan and hides Tesla+Christophe", () => {
  const pickupMs = Date.parse("2026-09-18T20:00:00.000Z"); // 22:00 Brussels
  const offers = projectBookableVehicleOffers({
    vehicles: [tesla(), cadillac()],
    drivers: [christophe(), wotan()],
    pickupMs,
    durationMin: 40,
    pax: 2,
    nowMs: Date.parse("2026-09-18T12:00:00.000Z"),
  });
  const teslaOffer = offers.find((row) => row.vehicle_id === "vh_tesla");
  const cadillacOffer = offers.find((row) => row.vehicle_id === "vh_cadillac");
  assert.equal(teslaOffer.available, false);
  assert.equal(cadillacOffer.available, true);
  assert.equal(cadillacOffer.driver_id, "drv_wotan");
  const free = filterVehiclesByRosterOffers([tesla(), cadillac()], offers);
  assert.deepEqual(free.map((row) => row.vehicle_id), ["vh_cadillac"]);
});

test("three sequential drivers on one car stay one vehicle card", () => {
  const car = {
    vehicle_id: "vh_shared",
    is_active: true,
    passenger_capacity: 3,
  };
  const morning = {
    driver_id: "drv_a",
    is_active: true,
    assigned_vehicle_id: "vh_shared",
    vehicle_ids: ["vh_shared"],
    weekly_roster: {
      timezone: "Europe/Brussels",
      explicitly_set: true,
      days: { fri: [{ start: "06:00", end: "14:00" }] },
    },
  };
  const evening = {
    driver_id: "drv_b",
    is_active: true,
    assigned_vehicle_id: "vh_shared",
    vehicle_ids: ["vh_shared"],
    weekly_roster: {
      timezone: "Europe/Brussels",
      explicitly_set: true,
      days: { fri: [{ start: "14:00", end: "22:00" }] },
    },
  };
  const night = {
    driver_id: "drv_c",
    is_active: true,
    assigned_vehicle_id: "vh_shared",
    vehicle_ids: ["vh_shared"],
    weekly_roster: {
      timezone: "Europe/Brussels",
      explicitly_set: true,
      days: { fri: [{ start: "22:00", end: "06:00" }] },
    },
  };
  const drivers = [morning, evening, night];
  const eveningPickup = Date.parse("2026-09-18T16:00:00.000Z"); // 18:00 Brussels Friday
  const nightPickup = Date.parse("2026-09-18T21:00:00.000Z"); // 23:00 Brussels
  const eveningOffers = projectBookableVehicleOffers({
    vehicles: [car, car],
    drivers,
    pickupMs: eveningPickup,
    nowMs: Date.parse("2026-09-18T10:00:00.000Z"),
  });
  assert.equal(eveningOffers.length, 1);
  assert.equal(eveningOffers[0].available, true);
  assert.equal(eveningOffers[0].driver_id, "drv_b");
  const nightOffers = projectBookableVehicleOffers({
    vehicles: [car],
    drivers,
    pickupMs: nightPickup,
    nowMs: Date.parse("2026-09-18T10:00:00.000Z"),
  });
  assert.equal(nightOffers.length, 1);
  assert.equal(nightOffers[0].available, true);
  assert.equal(nightOffers[0].driver_id, "drv_c");
});

test("a never-set roster does not hide the linked vehicle", () => {
  const offers = projectBookableVehicleOffers({
    vehicles: [tesla()],
    drivers: [{
      driver_id: "drv_christophe",
      is_active: true,
      assigned_vehicle_id: "vh_tesla",
    }],
    pickupMs: Date.parse("2026-09-18T20:00:00.000Z"),
    nowMs: Date.parse("2026-09-18T12:00:00.000Z"),
  });
  assert.equal(offers[0].available, true);
});

test("a saved empty roster hides the linked vehicle", () => {
  const offers = projectBookableVehicleOffers({
    vehicles: [tesla()],
    drivers: [{
      driver_id: "drv_christophe",
      is_active: true,
      assigned_vehicle_id: "vh_tesla",
      weekly_roster: {
        timezone: "Europe/Brussels",
        explicitly_set: true,
        days: {},
      },
    }],
    pickupMs: Date.parse("2026-09-18T20:00:00.000Z"),
    nowMs: Date.parse("2026-09-18T12:00:00.000Z"),
  });
  assert.equal(offers[0].available, false);
  assert.equal(offers[0].reason, "assignment_driver_not_scheduled");
});
