/**
 * Vehicle offers at a pickup time: one card per vehicle, driver from roster.
 *
 * Never-set roster ≠ saved empty. A load failure is not availability.
 * Night shifts that cross midnight stay on the existing weekly_roster maths.
 */

import {
  evaluateDriverEligibility,
  linkedVehicleIds,
  rideIsSoon,
} from "./company_dispatch.mjs";
import { sanitizeTenantString } from "./parsing_utils.js";

const LIVE_REASONS = new Set([
  "assignment_driver_offline",
  "assignment_driver_not_live",
]);

export function fleetVehicleId(vehicle) {
  return sanitizeTenantString(
    vehicle?.vehicle_id ?? vehicle?.vehicleId ?? vehicle?.id,
    128,
  );
}

export function fleetDriverId(driver) {
  if (!driver || typeof driver !== "object") return "";
  return sanitizeTenantString(
    driver.driver_id ?? driver.driverId ?? driver.id,
    96,
  );
}

export function fleetPassengerSeats(vehicle) {
  if (!vehicle || typeof vehicle !== "object") return null;
  const keys = [
    "passenger_capacity",
    "passengerCapacity",
    "max_passengers",
    "maxPassengers",
    "pax",
    "seats",
    "capacity",
  ];
  for (const key of keys) {
    if (!Object.prototype.hasOwnProperty.call(vehicle, key)) continue;
    const n = Number(vehicle[key]);
    if (Number.isFinite(n) && n >= 0) return Math.trunc(n);
  }
  return null;
}

export function driversLinkedToVehicle(vehicle, drivers) {
  const vid = fleetVehicleId(vehicle);
  const owner = fleetDriverId(vehicle?.assigned_driver ?? vehicle?.assignedDriver)
    || sanitizeTenantString(
      vehicle?.assigned_driver_id ?? vehicle?.assignedDriverId ?? vehicle?.driver_id,
      96,
    );
  const byId = new Map();
  for (const driver of Array.isArray(drivers) ? drivers : []) {
    const id = fleetDriverId(driver);
    if (id) byId.set(id, driver);
  }
  const out = [];
  const push = (driver) => {
    const id = fleetDriverId(driver);
    if (!id || out.some((row) => fleetDriverId(row) === id)) return;
    out.push(byId.get(id) || driver);
  };
  const embedded = vehicle?.assigned_driver ?? vehicle?.assignedDriver;
  if (embedded && typeof embedded === "object") push(embedded);
  if (owner) {
    const indexed = byId.get(owner);
    if (indexed) push(indexed);
  }
  for (const driver of Array.isArray(drivers) ? drivers : []) {
    if (linkedVehicleIds(driver).includes(vid)) push(driver);
  }
  return out;
}

export function rosterEligibilityReasons(evaluation, { ignoreLive = false } = {}) {
  const reasons = Array.isArray(evaluation?.reasons) ? evaluation.reasons : [];
  if (!ignoreLive) return reasons;
  return reasons.filter((reason) => !LIVE_REASONS.has(reason));
}

export function pickOnDutyDriverForVehicle({
  vehicle,
  drivers,
  pickupMs,
  durationMin = 30,
  nowMs = Date.now(),
  ignoreLive = false,
} = {}) {
  const pickupIso = Number.isFinite(Number(pickupMs))
    ? new Date(Number(pickupMs)).toISOString()
    : "";
  const soon = rideIsSoon(pickupIso, nowMs);
  const candidates = driversLinkedToVehicle(vehicle, drivers);
  if (!candidates.length) {
    return { ok: false, error: "assignment_driver_no_vehicle", driver: null };
  }
  let firstError = "";
  for (const driver of candidates) {
    const evaluation = evaluateDriverEligibility({
      driver,
      vehicles: [vehicle],
      drivers,
      atMs: nowMs,
      pickupIso,
      durationMin,
      soon,
    });
    const reasons = rosterEligibilityReasons(evaluation, {
      ignoreLive: ignoreLive || !soon,
    });
    if (reasons.length === 0) {
      return { ok: true, error: "", driver, evaluation };
    }
    firstError = firstError || reasons[0];
  }
  return {
    ok: false,
    error: firstError || "assignment_driver_not_scheduled",
    driver: null,
  };
}

export function projectBookableVehicleOffers({
  vehicles = [],
  drivers = [],
  pickupMs,
  durationMin = 30,
  pax = 1,
  nowMs = Date.now(),
  ignoreLive = false,
} = {}) {
  const seen = new Set();
  const offers = [];
  for (const vehicle of Array.isArray(vehicles) ? vehicles : []) {
    const vehicleId = fleetVehicleId(vehicle);
    if (!vehicleId || seen.has(vehicleId)) continue;
    seen.add(vehicleId);
    const seats = fleetPassengerSeats(vehicle);
    if (seats != null && seats > 0 && Number(pax) > seats) {
      offers.push({
        vehicle_id: vehicleId,
        vehicle,
        available: false,
        reason: "assignment_capacity",
        driver: null,
        driver_id: "",
        passenger_seats: seats,
      });
      continue;
    }
    const duty = pickOnDutyDriverForVehicle({
      vehicle,
      drivers,
      pickupMs,
      durationMin,
      nowMs,
      ignoreLive,
    });
    offers.push({
      vehicle_id: vehicleId,
      vehicle,
      available: duty.ok === true,
      reason: duty.ok ? "" : duty.error,
      driver: duty.driver,
      driver_id: fleetDriverId(duty.driver),
      passenger_seats: seats,
    });
  }
  return offers;
}

export function filterVehiclesByRosterOffers(vehicles, offers) {
  const available = new Set(
    (Array.isArray(offers) ? offers : [])
      .filter((row) => row?.available)
      .map((row) => row.vehicle_id),
  );
  return (Array.isArray(vehicles) ? vehicles : []).filter((vehicle) =>
    available.has(fleetVehicleId(vehicle)),
  );
}

export function publicDriverPreviewFromFleet(driver) {
  const id = fleetDriverId(driver);
  if (!id) return { driver_id: "" };
  const profileOn =
    driver?.public_profile_enabled === true || driver?.publicProfileEnabled === true;
  const photoOn =
    driver?.public_photo_enabled === true || driver?.publicPhotoEnabled === true;
  const name = profileOn
    ? sanitizeTenantString(driver?.public_display_name ?? driver?.publicDisplayName, 160)
    : "";
  const photo = photoOn
    ? sanitizeTenantString(
        driver?.public_portrait_url ?? driver?.publicPortraitUrl,
        400,
      )
    : "";
  return {
    driver_id: id,
    ...(name ? { public_display_name: name } : {}),
    ...(photo ? { public_photo_url: photo } : {}),
  };
}

export function publicBookableVehicleRows(offers) {
  return (Array.isArray(offers) ? offers : []).map((row) => {
    const preview = publicDriverPreviewFromFleet(row.driver);
    return {
      vehicle_id: row.vehicle_id,
      available: row.available === true,
      reason: row.reason || "",
      driver_id: preview.driver_id || row.driver_id || "",
      ...(preview.public_display_name
        ? { public_display_name: preview.public_display_name }
        : {}),
      ...(preview.public_photo_url ? { public_photo_url: preview.public_photo_url } : {}),
      passenger_seats: row.passenger_seats,
    };
  });
}
