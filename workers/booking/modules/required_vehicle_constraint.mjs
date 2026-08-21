/* Generic server-authoritative exact-vehicle dispatch constraint.
 *
 * A trusted server-side booking source may require the canonical fleet
 * allocator to reserve ONE exact vehicle instead of "any suitable vehicle".
 * Today the only such source is an accepted limousine quote: the customer
 * approved an offer for one specific car, so reserving a different car would
 * be a mis-sale. The concept itself is product-neutral, which keeps limousine
 * branching out of the allocator.
 *
 * Authority rules:
 *   - the constraint is NEVER read from a client payload;
 *   - booking creation passes it explicitly, derived from the sealed
 *     acceptance snapshot;
 *   - a later dispatch attempt (post-payment auto dispatch) recovers it from
 *     the immutable snapshot the Worker itself wrote onto the booking record.
 *
 * Absence of a constraint must leave existing selection behaviour untouched.
 */

import { safeStr } from "./parsing_utils.js";

/// Reads the constraint from a dispatch/allocator request object.
export function requiredVehicleIdFromRequest(req) {
  if (!req || typeof req !== "object") return "";
  return safeStr(req.required_vehicle_id ?? req.requiredVehicleId);
}

/// True when `vehicle` satisfies the constraint. An empty constraint accepts
/// every vehicle, so unpinned taxi/airport allocation is unaffected.
export function vehicleMatchesRequiredVehicle(vehicle, requiredVehicleId) {
  const required = safeStr(requiredVehicleId);
  if (!required) return true;
  if (!vehicle || typeof vehicle !== "object") return false;
  return safeStr(vehicle.vehicle_id ?? vehicle.vehicleId) === required;
}

/// Recovers the constraint from a persisted canonical booking record. Only the
/// server-sealed accepted-price snapshot is consulted, so a client-supplied
/// `vehicle_id` on the payload or booking fields can never pin or re-point an
/// assignment.
export function requiredVehicleIdFromBookingRecord(rec) {
  if (!rec || typeof rec !== "object") return "";
  const snapshots = [
    rec.quote?.limousine_accepted_price,
    rec.quote?.limousineAcceptedPrice,
    rec.limousine_accepted_price,
    rec.limousineAcceptedPrice,
    rec.booking?.limousine_accepted_price,
    rec.booking?.limousineAcceptedPrice,
  ];
  for (const snapshot of snapshots) {
    if (!snapshot || typeof snapshot !== "object") continue;
    const vehicleId = safeStr(snapshot.vehicle_id ?? snapshot.vehicleId);
    if (vehicleId) return vehicleId;
  }
  return "";
}
