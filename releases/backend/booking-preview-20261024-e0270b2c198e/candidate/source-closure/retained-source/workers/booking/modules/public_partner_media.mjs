import { resolvePublicBookingPhotoUrl } from "./public_booking_vehicles.mjs";

const id = value => String(value ?? "").trim();
const scoped = (row, tenantId, companyId) => row && typeof row === "object" &&
  (!row.tenant_id && !row.tenantId || id(row.tenant_id ?? row.tenantId) === tenantId) &&
  (!row.company_id && !row.companyId || id(row.company_id ?? row.companyId) === companyId);

function publicPhoto(ref, origin) {
  const resolved = resolvePublicBookingPhotoUrl(ref, origin);
  try {
    const url = new URL(resolved);
    if (url.protocol !== "https:" || url.username || url.password || url.href.length > 2048) return "";
    const raw = id(ref).toLowerCase();
    if (!raw.startsWith("https://") &&
        (url.origin !== new URL(origin).origin || !url.pathname.startsWith("/public/media/"))) return "";
    return url.href;
  } catch { return ""; }
}

// Only current records from this partner's scoped indexes can establish a
// public identity, photo consent or vehicle link. Stored profile previews are
// used for presentation details only after an exact ID match.
export function projectPublicPartnerMedia({ vehicles = [], fleet = [], driverIndex = null,
  storedDrivers = [], tenantId = "", companyId = "", origin = "" } = {}) {
  const eligible = new Map();
  const stored = new Map((Array.isArray(storedDrivers) ? storedDrivers : [])
    .filter(row => row && typeof row === "object" && id(row.driver_id ?? row.driverId ?? row.id))
    .map(row => [id(row.driver_id ?? row.driverId ?? row.id), row]));
  for (const [key, row] of Object.entries(driverIndex?.drivers || {})) {
    const driverId = id(row?.driver_id ?? row?.driverId ?? key);
    if (!driverId || driverId !== key || !scoped(row, tenantId, companyId) ||
        row.is_active === false || row.isActive === false || row.blocked === true ||
        row.public_profile_enabled !== true) continue;
    const preview = stored.get(driverId);
    const name = id(row.public_display_name ?? row.publicDisplayName ?? preview?.display_name ?? row.display_name);
    const photo = row.public_photo_enabled === true
      ? publicPhoto(row.public_portrait_url ?? row.publicPortraitUrl, origin) : "";
    eligible.set(driverId, {
      driver_id: driverId,
      display_name: name,
      bio: id(row.public_bio ?? row.publicBio).slice(0, 2000),
      public_photo_enabled: Boolean(photo),
      ...(photo ? { public_portrait_url: photo } : {}),
      ...(Array.isArray(preview?.languages) ? { languages: preview.languages } : {}),
      ...(Array.isArray(preview?.badges) ? { badges: preview.badges } : {}),
    });
  }
  const fleetById = new Map((Array.isArray(fleet) ? fleet : [])
    .filter(row => scoped(row, tenantId, companyId) && row.is_active !== false)
    .map(row => [id(row.vehicle_id ?? row.vehicleId ?? row.id), row])
    .filter(([vehicleId]) => vehicleId));
  const candidates = new Map();
  const add = (vehicleId, driverId) => {
    if (!fleetById.has(vehicleId) || !eligible.has(driverId)) return;
    if (!candidates.has(vehicleId)) candidates.set(vehicleId, new Set());
    candidates.get(vehicleId).add(driverId);
  };
  for (const [vehicleId, row] of fleetById) {
    add(vehicleId, id(row.assigned_driver_id ?? row.assignedDriverId ??
      row.assigned_driver?.driver_id ?? row.assignedDriver?.driver_id));
  }
  for (const [driverId, row] of Object.entries(driverIndex?.drivers || {})) {
    if (eligible.has(driverId) && scoped(row, tenantId, companyId))
      add(id(row.assigned_vehicle_id ?? row.assignedVehicleId), driverId);
  }
  return {
    drivers: [...eligible.values()],
    vehicles: (Array.isArray(vehicles) ? vehicles : [])
      .filter(vehicle => fleetById.has(id(vehicle?.vehicle_id ?? vehicle?.vehicleId)))
      .map(vehicle => {
      const vehicleId = id(vehicle?.vehicle_id ?? vehicle?.vehicleId);
      const links = candidates.get(vehicleId);
      return links?.size === 1
        ? { ...vehicle, assigned_driver_id: [...links][0] }
        : vehicle;
      }),
  };
}
