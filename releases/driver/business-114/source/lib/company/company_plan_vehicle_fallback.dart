// COMPANY-AGENDA-P0 — Fluxidi vehicle fallback assets v1 from asset_manifest.json.

import 'package:fluxidi_tracking/company/company_driver_agenda_style.dart';
import 'package:fluxidi_tracking/company/company_plan_vehicle_type.dart';

const String kCompanyPlanVehicleFallbackDir = 'assets/vehicles/fallback/v1';

const String kCompanyPlanFallbackCompact =
    '$kCompanyPlanVehicleFallbackDir/fluxidi_vehicle_compact_hatchback_v1.webp';
const String kCompanyPlanFallbackSedan =
    '$kCompanyPlanVehicleFallbackDir/fluxidi_vehicle_sedan_v1.webp';
const String kCompanyPlanFallbackStation =
    '$kCompanyPlanVehicleFallbackDir/fluxidi_vehicle_station_wagon_v1.webp';
const String kCompanyPlanFallbackSuv =
    '$kCompanyPlanVehicleFallbackDir/fluxidi_vehicle_suv_crossover_v1.webp';
const String kCompanyPlanFallbackMinivan =
    '$kCompanyPlanVehicleFallbackDir/fluxidi_vehicle_mpv_minivan_v1.webp';
const String kCompanyPlanFallbackMinibus =
    '$kCompanyPlanVehicleFallbackDir/fluxidi_vehicle_passenger_minibus_v1.webp';
const String kCompanyPlanFallbackPremium =
    '$kCompanyPlanVehicleFallbackDir/fluxidi_vehicle_premium_limousine_v1.webp';
const String kCompanyPlanFallbackWheelchair =
    '$kCompanyPlanVehicleFallbackDir/fluxidi_vehicle_wheelchair_accessible_v1.webp';
const String kCompanyPlanFallbackStretchLimousine =
    '$kCompanyPlanVehicleFallbackDir/fluxidi_vehicle_stretch_limousine_v1.webp';
const String kCompanyPlanFallbackHummerStretch =
    '$kCompanyPlanVehicleFallbackDir/fluxidi_vehicle_hummer_stretch_v1.webp';
const List<String> kCompanyPlanLimousineFallbackAssets = <String>[
  kCompanyPlanFallbackStretchLimousine,
  kCompanyPlanFallbackHummerStretch,
];

/// Manifest category order. Airport ride is not a vehicle category.
const List<CompanyPlanVehicleCategory> kCompanyPlanFallbackCategories =
    CompanyPlanVehicleCategory.values;

String companyPlanVehicleFallbackAsset(CompanyPlanVehicleCategory category) {
  return switch (category) {
    CompanyPlanVehicleCategory.compact => kCompanyPlanFallbackCompact,
    CompanyPlanVehicleCategory.sedan => kCompanyPlanFallbackSedan,
    CompanyPlanVehicleCategory.breakWagon => kCompanyPlanFallbackStation,
    CompanyPlanVehicleCategory.suv => kCompanyPlanFallbackSuv,
    CompanyPlanVehicleCategory.minivan => kCompanyPlanFallbackMinivan,
    CompanyPlanVehicleCategory.minibus => kCompanyPlanFallbackMinibus,
    CompanyPlanVehicleCategory.premium => kCompanyPlanFallbackPremium,
    CompanyPlanVehicleCategory.wheelchair => kCompanyPlanFallbackWheelchair,
  };
}

CompanyPlanVehicleCategory? companyPlanVehicleCategoryFromAlias(String? raw) {
  switch (raw?.trim().toLowerCase().replaceAll('-', '_').replaceAll(' ', '_') ??
      '') {
    case 'compact':
    case 'hatchback':
    case 'compact_hatchback':
    case 'city':
    case 'economy':
    case 'small_car':
      return CompanyPlanVehicleCategory.compact;
    case 'sedan':
    case 'saloon':
    case 'berline':
    case 'standard':
      return CompanyPlanVehicleCategory.sedan;
    case 'station_wagon':
    case 'stationwagon':
    case 'estate':
    case 'break':
    case 'combi':
      return CompanyPlanVehicleCategory.breakWagon;
    case 'suv':
    case 'crossover':
    case 'suv_crossover':
      return CompanyPlanVehicleCategory.suv;
    case 'mpv':
    case 'minivan':
    case 'people_carrier':
    case 'van_5_7':
    case 'van':
      return CompanyPlanVehicleCategory.minivan;
    case 'minibus':
    case 'passenger_minibus':
    case 'van_8_plus':
      return CompanyPlanVehicleCategory.minibus;
    case 'premium':
    case 'executive':
    case 'luxury':
    case 'limousine':
    case 'vip':
      return CompanyPlanVehicleCategory.premium;
    case 'wheelchair':
    case 'wheelchair_accessible':
    case 'accessible':
    case 'prm':
    case 'wav':
    case 'rolstoel':
      return CompanyPlanVehicleCategory.wheelchair;
    case 'airport':
    case 'airport_ride':
      return null;
    default:
      return null;
  }
}

CompanyPlanVehicleCategory companyPlanVehicleFallbackCategory(
  Map<String, dynamic> vehicle,
) {
  final explicit = companyPlanVehicleCategoryFromAlias(
    (vehicle['vehicle_type'] ??
            vehicle['vehicleType'] ??
            vehicle['type'] ??
            vehicle['class'] ??
            vehicle['vehicle_class'] ??
            vehicle['vehicleClass'])
        ?.toString(),
  );
  if (explicit != null) return explicit;
  final classified = classifyCompanyPlanVehicleCategory(vehicle);
  final capacity = companyAgendaVehicleCapacity(vehicle);
  if (capacity >= 8 &&
      classified != CompanyPlanVehicleCategory.wheelchair &&
      classified != CompanyPlanVehicleCategory.premium &&
      classified != CompanyPlanVehicleCategory.suv) {
    return CompanyPlanVehicleCategory.minibus;
  }
  if (classified != null) return classified;
  if (capacity > kCompanyPlanSedanMaxPassengers) {
    return CompanyPlanVehicleCategory.minivan;
  }
  return CompanyPlanVehicleCategory.sedan;
}

String normalizeVehicleFallbackAsset(Object? raw) {
  final value = (raw ?? '').toString().trim();
  return kCompanyPlanLimousineFallbackAssets.contains(value) ||
          kCompanyPlanFallbackCategories.any(
            (c) => companyPlanVehicleFallbackAsset(c) == value,
          )
      ? value
      : '';
}

/// The fleet and limousine screens use the same allowlisted illustration as
/// customer vehicle cards when a vehicle has no configured illustration.
/// A real photo is selected by the caller before this fallback is rendered.
String companyPlanVehicleDisplayFallbackAsset(Map<String, dynamic> vehicle) {
  final configured = normalizeVehicleFallbackAsset(
    vehicle['fallbackAsset'] ?? vehicle['fallback_asset'],
  );
  if (configured.isNotEmpty) return configured;
  final name = [
    vehicle['vehicleName'],
    vehicle['vehicle_name'],
    vehicle['public_name'],
    vehicle['brandModel'],
    vehicle['brand_model'],
    vehicle['name'],
  ].whereType<Object>().join(' ').toLowerCase();
  final serviceClass =
      (vehicle['service_class_id'] ??
              vehicle['serviceClassId'] ??
              vehicle['limousine_service_class_id'] ??
              '')
          .toString()
          .toLowerCase();
  final isStretch =
      serviceClass == 'stretch_limousine' ||
      name.contains('stretch') ||
      name.contains('limousine') ||
      name.contains('limo');
  if (isStretch) {
    return name.contains('hummer')
        ? kCompanyPlanFallbackHummerStretch
        : kCompanyPlanFallbackStretchLimousine;
  }
  return companyPlanVehicleFallbackAsset(
    companyPlanVehicleFallbackCategory(vehicle),
  );
}
