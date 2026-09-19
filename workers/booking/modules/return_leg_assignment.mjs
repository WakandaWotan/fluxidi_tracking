/* AIRPORT-RETURN-ASSIGNMENT-P0 — one vehicle and driver per ride leg.
 *
 * A split round trip (`split_no_wait`) is two real drives at two moments. The
 * outbound choice must never be pinned onto the return leg: either the customer
 * picked a return vehicle explicitly, or the allocator resolves the return leg
 * on its own for the return moment.
 *
 * Canonical request fields (used in new responses and documentation):
 *   return_vehicle_id
 *   preferred_return_vehicle_id
 *   return_assigned_driver_id
 *
 * Documented compatibility aliases, read only:
 *   returnVehicleId / preferredReturnVehicleId / returnAssignedDriverId
 *   return_preferred_vehicle_id / returnPreferredVehicleId
 */

import { safeStr } from "./parsing_utils.js";

export const RETURN_LEG_KEY = "RETURN";
export const OUTBOUND_LEG_KEY = "OUTBOUND";

/// Explicit return vehicle from the booking contract. Canonical names first,
/// then the documented aliases. Older clients that send nothing stay unpinned.
export function returnRequestedVehicleIdFromPayload(payload) {
  if (!payload || typeof payload !== "object") return "";
  return safeStr(
    payload.return_vehicle_id ??
      payload.returnVehicleId ??
      payload.preferred_return_vehicle_id ??
      payload.preferredReturnVehicleId ??
      // Compatibility aliases: some clients and tests use this word order.
      payload.return_preferred_vehicle_id ??
      payload.returnPreferredVehicleId,
  );
}

/// Explicit return driver from the booking contract.
export function returnRequestedDriverIdFromPayload(payload) {
  if (!payload || typeof payload !== "object") return "";
  return safeStr(
    payload.return_assigned_driver_id ??
      payload.returnAssignedDriverId ??
      payload.return_driver_id ??
      payload.returnDriverId,
  );
}

/**
 * The vehicle constraint for one leg.
 *
 * The return leg only ever uses its own pin. An empty return pin means "let the
 * allocator decide for the return moment", never "reuse the outbound car",
 * because the outbound car may be busy or off duty by then.
 */
export function legRequiredVehicleId({
  legKey,
  outboundVehicleId = "",
  returnVehicleId = "",
} = {}) {
  const key = safeStr(legKey, 24).toUpperCase();
  if (key === RETURN_LEG_KEY) return safeStr(returnVehicleId, 128);
  return safeStr(outboundVehicleId, 128);
}

function legAssignment(legResults, legKey) {
  const list = Array.isArray(legResults) ? legResults : [];
  const match = list.find(
    (entry) => safeStr(entry?.legKey, 24).toUpperCase() === legKey,
  );
  if (!match) return { vehicle_id: null, driver_id: null };
  return {
    vehicle_id: safeStr(match.assignedVehicleId, 128) || null,
    driver_id:
      safeStr(
        match.assignedDriverId ??
          match.assignedDriver?.driver_id ??
          match.assignedDriver?.driverId ??
          match.assignedDriver?.id,
        96,
      ) || null,
  };
}

/// Confirmed assignment per leg, as the booking response and the detail read
/// model should present it. Availability is not an assignment: only values that
/// came out of the allocator appear here.
export function perLegAssignmentFromLegResults(legResults) {
  return {
    outbound: legAssignment(legResults, OUTBOUND_LEG_KEY),
    return: legAssignment(legResults, RETURN_LEG_KEY),
  };
}

/// True when the two legs really run on different cars.
export function legsUseDifferentVehicles(perLeg) {
  const outbound = safeStr(perLeg?.outbound?.vehicle_id, 128);
  const inbound = safeStr(perLeg?.return?.vehicle_id, 128);
  return !!outbound && !!inbound && outbound !== inbound;
}

/// Additive top-level booking fields for the confirmed return assignment.
/// Nothing is written when the return leg has no confirmed assignment, so a
/// reader can never mistake availability for a guarantee.
export function returnAssignmentRecordFields(perLeg) {
  const vehicleId = safeStr(perLeg?.return?.vehicle_id, 128);
  const driverId = safeStr(perLeg?.return?.driver_id, 96);
  const fields = {};
  if (vehicleId) {
    fields.return_vehicle_id = vehicleId;
    fields.returnVehicleId = vehicleId;
    fields.return_assigned_vehicle_id = vehicleId;
    fields.returnAssignedVehicleId = vehicleId;
  }
  if (driverId) {
    fields.return_assigned_driver_id = driverId;
    fields.returnAssignedDriverId = driverId;
  }
  return fields;
}

/// Requested (not yet confirmed) return choice, stored next to the outbound
/// `customer_requested_vehicle_id` so a later dispatch can recover it.
export function returnRequestedRecordFields({ vehicleId, driverId } = {}) {
  const vehicle = safeStr(vehicleId, 128);
  const driver = safeStr(driverId, 96);
  const fields = {};
  if (vehicle) {
    fields.customer_requested_return_vehicle_id = vehicle;
    fields.customerRequestedReturnVehicleId = vehicle;
  }
  if (driver) {
    fields.customer_requested_return_driver_id = driver;
    fields.customerRequestedReturnDriverId = driver;
  }
  return fields;
}
