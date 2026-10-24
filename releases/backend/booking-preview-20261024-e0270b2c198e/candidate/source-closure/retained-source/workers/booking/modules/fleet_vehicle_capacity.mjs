/**
 * Authoritative vehicle-capacity gate for fleet writes.
 *
 * Trial includes one vehicle. Extra capacity comes only from a stored paid
 * extra-vehicle quantity (or a legacy active profile that already baked extras
 * into max_vehicles). A client field or requested add-on does not grant a slot.
 * Missing rights fail closed to one vehicle, never to unlimited.
 *
 * Existing over-capacity fleets are left untouched: an update that adds no new
 * active id is allowed so Christophe's Tesla and other real vehicles stay.
 */

export const VEHICLE_LIMIT_REACHED = "vehicle_limit_reached";
export const DEMO_SEED_PLATE = "1-ABC-123";

function truncNonNeg(value, fallback) {
  const n = Number(value);
  if (!Number.isFinite(n)) return fallback;
  return Math.max(0, Math.trunc(n));
}

function text(value) {
  return value == null ? "" : String(value).trim();
}

function vehicleIdOf(vehicle) {
  return text(vehicle?.vehicle_id ?? vehicle?.vehicleId ?? vehicle?.id);
}

export function isDemoSeedFingerprint(vehicle) {
  const id = vehicleIdOf(vehicle);
  const plate = text(vehicle?.license_plate ?? vehicle?.licensePlate).toUpperCase();
  const brand = text(vehicle?.brand_model ?? vehicle?.brandModel).toLowerCase();
  const name = text(
    vehicle?.vehicle_name ?? vehicle?.vehicleName ?? vehicle?.display_label,
  ).toLowerCase();
  const demoPlate = plate === DEMO_SEED_PLATE;
  const emptyPlate = plate === "";
  const demoBrand = brand === "tesla model 3" || brand.includes("model 3");
  const demoName =
    name === "hoofdwagen" ||
    name === "main vehicle" ||
    name === "véhicule principal" ||
    name === "vehicule principal";
  if (demoPlate && (demoBrand || demoName)) return true;
  return id === "vh_1" && demoName && (emptyPlate || demoPlate);
}

/**
 * Drop only a demo seed that this company has never stored. A matching Tesla
 * that is already on the company's fleet stays (Christophe / JM).
 */
export function isUnpersistedDemoVehicle(vehicle, existingIds = []) {
  if (!isDemoSeedFingerprint(vehicle)) return false;
  const id = vehicleIdOf(vehicle);
  if (!id) return true;
  return !existingIds.map((row) => text(row)).filter(Boolean).includes(id);
}

export function dropUnpersistedDemoVehicles(vehicles = [], existingIds = []) {
  return (Array.isArray(vehicles) ? vehicles : []).filter(
    (vehicle) => !isUnpersistedDemoVehicle(vehicle, existingIds),
  );
}

/**
 * Paid + included capacity from the subscription record. Trial and unknown
 * statuses ignore a client-inflated max_vehicles.
 */
export function resolveAuthoritativeVehicleCapacity(profile = {}) {
  const includedRaw = profile?.included_vehicles ?? profile?.includedVehicles;
  const included = includedRaw == null || includedRaw === ""
    ? 1
    : truncNonNeg(includedRaw, 1);
  const extra = truncNonNeg(
    profile?.extra_vehicle_active_quantity ?? profile?.extraVehicleActiveQuantity,
    0,
  );
  const status = text(profile?.status ?? profile?.subscription_status).toLowerCase();
  if (extra > 0) return included + extra;
  if (status === "active" || status === "past_due") {
    const maxV = truncNonNeg(profile?.max_vehicles ?? profile?.maxVehicles, 0);
    if (maxV > included) return maxV;
  }
  return included > 0 ? included : 1;
}

export function evaluateFleetCapacityWrite({
  existingActiveIds = [],
  incomingActiveIds = [],
  allowed,
} = {}) {
  const cap = allowed == null || allowed === ""
    ? 1
    : Math.max(0, truncNonNeg(allowed, 1) || 1);
  const existing = [...new Set((existingActiveIds || []).map((id) => text(id)).filter(Boolean))];
  const incoming = [...new Set((incomingActiveIds || []).map((id) => text(id)).filter(Boolean))];
  const existingSet = new Set(existing);
  const added = incoming.filter((id) => !existingSet.has(id));
  const base = {
    allowed: cap,
    existing: existing.length,
    incoming: incoming.length,
    added: added.length,
  };
  if (incoming.length <= cap) {
    const disjointReplace = existing.length >= cap
      && added.length > 0
      && incoming.every((id) => !existingSet.has(id));
    if (disjointReplace) {
      return { ok: false, error: VEHICLE_LIMIT_REACHED, ...base };
    }
    return { ok: true, ...base };
  }
  if (added.length === 0) {
    return { ok: true, preserved_overrun: true, ...base };
  }
  return { ok: false, error: VEHICLE_LIMIT_REACHED, ...base };
}

export function vehicleLimitMessage() {
  return "Tijdens de proefperiode is één voertuig inbegrepen. Extra capaciteit vereist een betaalde uitbreiding.";
}
