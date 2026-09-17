import test from "node:test";
import assert from "node:assert/strict";
import {
  mergePublicBookingVehicles,
  projectPublicBookingVehicle,
} from "./public_booking_vehicles.mjs";

test("taxi vehicles keep vehicle_id, own seats and a resolvable photo", () => {
  const tesla = projectPublicBookingVehicle(
    {
      vehicle_id: "vh_tesla",
      name: "Tesla",
      passenger_capacity: 3,
      public_photo_url: "public-media/t1/c1/vehicles/vh_tesla/gallery/a.jpg",
    },
    "https://booking.example",
  );
  const limo = projectPublicBookingVehicle({
    vehicle_id: "vh_party",
    vehicle_name: "Party Limo",
    passenger_capacity: 16,
    service_category: "taxi",
  });
  assert.equal(tesla.vehicle_id, "vh_tesla");
  assert.equal(tesla.passenger_capacity, 3);
  assert.equal(
    tesla.photo_url,
    "https://booking.example/public/media/t1/c1/vehicles/vh_tesla/gallery/a.jpg",
  );
  assert.equal(limo.passenger_capacity, 16);
  assert.notEqual(tesla.passenger_capacity, limo.passenger_capacity);
});

test("a vehicle without a photo stays in the public offer", () => {
  const row = projectPublicBookingVehicle({
    vehicle_id: "vh_bare",
    name: "Cadillac",
    passenger_capacity: 4,
  });
  assert.equal(row.vehicle_id, "vh_bare");
  assert.equal(row.photo_url, undefined);
});

test("fleet overlay restores ids that the stored public list stripped", () => {
  const merged = mergePublicBookingVehicles({
    stored: [{ name: "Tesla", pax: 3, photo_url: "https://cdn.example/t.jpg" }],
    fleet: [
      { vehicle_id: "vh_tesla", name: "Tesla", passenger_capacity: 3 },
      { vehicle_id: "vh_cadillac", name: "Cadillac", passenger_capacity: 4 },
    ],
    origin: "https://booking.example",
  });
  assert.deepEqual(
    merged.map((row) => row.vehicle_id),
    ["vh_tesla", "vh_cadillac"],
  );
  assert.equal(merged[0].passenger_capacity, 3);
  assert.equal(merged[1].passenger_capacity, 4);
});

test("Fluxidi live taxi rows regain fleet ids without changing stored names", () => {
  const merged = mergePublicBookingVehicles({
    stored: [
      { name: "Hoofdwagen", pax: 3, photo_url: "https://cdn.example/h.jpg" },
      { name: "Cadillac", pax: 4, photo_url: "https://cdn.example/c.jpg" },
      {
        name: "Party Limo",
        vehicle_id: "vh_1787058237109",
        pax: 16,
        service_category: "limousine",
      },
      {
        name: "Hummer white",
        vehicle_id: "vh_1787076028764",
        pax: 8,
        service_category: "limousine",
      },
    ],
    fleet: [
      { vehicle_id: "vh_1", name: "Hoofdwagen", passenger_capacity: 3 },
      {
        vehicle_id: "vh_1786881139131",
        name: "Cadillac",
        passenger_capacity: 4,
      },
      {
        vehicle_id: "vh_1787058237109",
        name: "Party Limo",
        passenger_capacity: 16,
        service_category: "limousine",
      },
      {
        vehicle_id: "vh_1787076028764",
        name: "Hummer white",
        passenger_capacity: 8,
        service_category: "limousine",
      },
    ],
  });
  assert.deepEqual(
    merged.map((row) => [row.vehicle_id, row.name, row.passenger_capacity]),
    [
      ["vh_1", "Hoofdwagen", 3],
      ["vh_1786881139131", "Cadillac", 4],
      ["vh_1787058237109", "Party Limo", 16],
      ["vh_1787076028764", "Hummer white", 8],
    ],
  );
});
