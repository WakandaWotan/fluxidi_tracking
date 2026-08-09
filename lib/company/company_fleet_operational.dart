/// FIRST-COMPANY-UX-P0 — operational fleet helpers for first-run bootstrap
/// and Drivers/Vehicles empty-state counting.
///
/// Seeded demo rows (`drv_1`, `vh_1` / Tesla Model 3) must never count as a
/// real company's first driver/vehicle.
library;

import 'package:fluxidi_tracking/app_config.dart';
import 'package:fluxidi_tracking/company_session_store.dart';

/// True for the in-memory demo vehicle seeded at app start (`vh_1` /
/// Hoofdwagen / Tesla Model 3 / 1-ABC-123).
///
/// Important: a real fleet vehicle may collide on id `vh_1`. Id alone is
/// never enough to hide a row — classify by demo seed *content* (demo plate /
/// Tesla Model 3 + generic main-vehicle name). A `vh_1` record with a
/// non-demo plate (or company-scoped real identity) is operational.
bool isSeededOrPlaceholderVehicle(VehicleProfile vehicle) {
  final plate = vehicle.licensePlate.trim().toUpperCase();
  final brand = vehicle.brandModel.trim().toLowerCase();
  final name = vehicle.vehicleName.trim().toLowerCase();
  final isDemoPlate = plate == '1-ABC-123';
  final isDemoBrand =
      brand == 'tesla model 3' || brand == 'tesla' || brand.contains('model 3');
  final isDemoName =
      name == 'hoofdwagen' ||
      name == 'main vehicle' ||
      name == 'véhicule principal' ||
      name == 'vehicule principal' ||
      name == 'vehículo principal' ||
      name == 'vehiculo principal';
  if (isDemoPlate && (isDemoBrand || isDemoName)) return true;
  if (isDemoBrand && isDemoName && plate.isEmpty) return true;

  // Unhydrated local seed row: well-known demo id, no real plate, and either
  // empty brand or still matching the demo Tesla/main-vehicle shape.
  final id = vehicle.id.trim().toLowerCase();
  if (id == 'vh_1') {
    final hasRealPlate = plate.isNotEmpty && !isDemoPlate;
    if (hasRealPlate) return false;
    final companyId = (vehicle.companyId ?? '').trim();
    if (companyId.isNotEmpty && !isDemoBrand && !isDemoPlate) return false;
    if (plate.isEmpty && (brand.isEmpty || isDemoBrand || isDemoName)) {
      return true;
    }
  }
  return false;
}

String? _activeCompanyId() {
  final fromProfile = companyProfileNotifier.value?.companyId.trim() ?? '';
  if (fromProfile.isNotEmpty) return fromProfile;
  final fromSession =
      activeCompanySessionNotifier.value?.companyId.trim() ?? '';
  if (fromSession.isNotEmpty) return fromSession;
  return resolveActiveCompanyIdForFleetUi();
}

bool _driverBelongsToActiveCompany(DriverProfile driver) {
  if (isSeededOrPlaceholderDriver(driver)) return false;
  final active = (_activeCompanyId() ?? '').trim();
  if (active.isEmpty) {
    return fleetRecordBelongsToActiveCompanyOrLegacy(driver.companyId);
  }
  return (driver.companyId?.trim() ?? '') == active;
}

bool _vehicleBelongsToActiveCompany(VehicleProfile vehicle) {
  if (isSeededOrPlaceholderVehicle(vehicle)) return false;
  final active = (_activeCompanyId() ?? '').trim();
  if (active.isEmpty) {
    return fleetRecordBelongsToActiveCompanyOrLegacy(vehicle.companyId);
  }
  return (vehicle.companyId?.trim() ?? '') == active;
}

/// Non-seed drivers that belong to the active company.
List<DriverProfile> companyOperationalDrivers({
  List<DriverProfile>? source,
}) {
  final list = source ?? driversNotifier.value;
  return list.where(_driverBelongsToActiveCompany).toList(growable: false);
}

/// Non-seed vehicles that belong to the active company.
List<VehicleProfile> companyOperationalVehicles({
  List<VehicleProfile>? source,
}) {
  final list = source ?? vehiclesNotifier.value;
  return list.where(_vehicleBelongsToActiveCompany).toList(growable: false);
}

bool companyHasOperationalDriver({List<DriverProfile>? source}) =>
    companyOperationalDrivers(source: source).isNotEmpty;

bool companyHasOperationalVehicle({List<VehicleProfile>? source}) =>
    companyOperationalVehicles(source: source).isNotEmpty;

/// Pure step machine for the post-wizard fleet bootstrap.
enum FirstRunFleetBootstrapStep {
  firstDriver,
  firstVehicle,
  readyToStart,
}

FirstRunFleetBootstrapStep resolveFirstRunFleetBootstrapStep({
  required bool hasDriver,
  required bool hasVehicle,
}) {
  if (!hasDriver) return FirstRunFleetBootstrapStep.firstDriver;
  if (!hasVehicle) return FirstRunFleetBootstrapStep.firstVehicle;
  return FirstRunFleetBootstrapStep.readyToStart;
}
