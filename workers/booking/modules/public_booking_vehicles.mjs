/// Public taxi booking vehicles must keep the same vehicle_id as fleet
/// management. A missing photo must not drop the vehicle.

export function publicBookingVehicleId(row) {
  return String(row?.vehicle_id ?? row?.vehicleId ?? row?.id ?? "").trim();
}

export function publicBookingPassengerCapacity(row) {
  const n = Number(
    row?.passenger_capacity ??
      row?.passengerCapacity ??
      row?.max_passengers ??
      row?.maxPassengers ??
      row?.pax,
  );
  if (!Number.isFinite(n) || n <= 0) return 0;
  return Math.min(99, Math.trunc(n));
}

export function publicBookingVehicleName(row) {
  return String(
    row?.vehicle_name ??
      row?.vehicleName ??
      row?.name ??
      row?.brand_model ??
      row?.brandModel ??
      row?.label ??
      "",
  ).trim();
}

export function resolvePublicBookingPhotoUrl(raw, origin = "") {
  const text = String(raw || "").trim();
  if (!text) return "";
  const lower = text.toLowerCase();
  if (lower.startsWith("https://")) return text;
  if (lower.startsWith("http://")) return "";
  const base = String(origin || "").replace(/\/+$/, "");
  if (lower.startsWith("/public/media/")) {
    return base ? `${base}${text}` : "";
  }
  if (lower.startsWith("public-media/")) {
    const suffix = text.slice("public-media/".length).trim();
    if (!suffix) return "";
    return base ? `${base}/public/media/${suffix}` : "";
  }
  return "";
}

function firstPhotoCandidate(row) {
  const gallery = row?.gallery_photo_urls ?? row?.galleryPhotoUrls;
  const galleryFirst = Array.isArray(gallery) ? gallery[0] : "";
  return (
    row?.public_photo_url ??
    row?.publicPhotoUrl ??
    row?.primary_photo_url ??
    row?.primaryPhotoUrl ??
    row?.vehicle_photo_url ??
    row?.vehiclePhotoUrl ??
    row?.photo_url ??
    row?.photoUrl ??
    row?.primary_photo_ref ??
    row?.primaryPhotoRef ??
    galleryFirst ??
    ""
  );
}

export function projectPublicBookingVehicle(row, origin = "") {
  if (!row || typeof row !== "object") return null;
  if (row.is_active === false || row.isActive === false) return null;
  const vehicleId = publicBookingVehicleId(row);
  if (!vehicleId) return null;
  const name = publicBookingVehicleName(row);
  const seats = publicBookingPassengerCapacity(row);
  const serviceCategory = String(
    row.service_category ?? row.serviceCategory ?? "",
  )
    .trim()
    .toLowerCase();
  const vehicleType = String(
    row.vehicle_type ?? row.vehicleType ?? row.category ?? "",
  ).trim();
  const photo = resolvePublicBookingPhotoUrl(firstPhotoCandidate(row), origin);
  return {
    vehicle_id: vehicleId,
    vehicleId,
    name,
    vehicle_name: name,
    ...(vehicleType
      ? { vehicle_type: vehicleType, vehicleType, category: vehicleType }
      : {}),
    ...(serviceCategory ? { service_category: serviceCategory } : {}),
    ...(seats > 0
      ? {
          passenger_capacity: seats,
          passengerCapacity: seats,
          pax: seats,
        }
      : {}),
    ...(photo
      ? {
          photo_url: photo,
          public_photo_url: photo,
          publicPhotoUrl: photo,
        }
      : {}),
    is_active: true,
    isActive: true,
  };
}

export function mergePublicBookingVehicles({
  stored = [],
  fleet = [],
  origin = "",
} = {}) {
  const out = [];
  const seen = new Set();
  for (const row of [...(Array.isArray(fleet) ? fleet : []), ...(Array.isArray(stored) ? stored : [])]) {
    const projected = projectPublicBookingVehicle(row, origin);
    if (!projected || seen.has(projected.vehicle_id)) continue;
    seen.add(projected.vehicle_id);
    out.push(projected);
  }
  return out;
}
