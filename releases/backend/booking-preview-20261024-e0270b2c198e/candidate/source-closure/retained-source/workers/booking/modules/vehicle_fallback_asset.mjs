// Stable bundled illustration IDs; never accept URLs or arbitrary local paths.
export const VEHICLE_FALLBACK_ASSETS = Object.freeze([
  "assets/vehicles/fallback/v1/fluxidi_vehicle_compact_hatchback_v1.webp",
  "assets/vehicles/fallback/v1/fluxidi_vehicle_sedan_v1.webp",
  "assets/vehicles/fallback/v1/fluxidi_vehicle_station_wagon_v1.webp",
  "assets/vehicles/fallback/v1/fluxidi_vehicle_suv_crossover_v1.webp",
  "assets/vehicles/fallback/v1/fluxidi_vehicle_mpv_minivan_v1.webp",
  "assets/vehicles/fallback/v1/fluxidi_vehicle_passenger_minibus_v1.webp",
  "assets/vehicles/fallback/v1/fluxidi_vehicle_premium_limousine_v1.webp",
  "assets/vehicles/fallback/v1/fluxidi_vehicle_wheelchair_accessible_v1.webp",
  "assets/vehicles/fallback/v1/fluxidi_vehicle_stretch_limousine_v1.webp",
  "assets/vehicles/fallback/v1/fluxidi_vehicle_hummer_stretch_v1.webp"
]);
export function normalizeVehicleFallbackAsset(value) {
  const asset = String(value ?? '').trim();
  return VEHICLE_FALLBACK_ASSETS.includes(asset) ? asset : '';
}
