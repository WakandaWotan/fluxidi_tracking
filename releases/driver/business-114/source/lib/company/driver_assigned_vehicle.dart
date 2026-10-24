import '../app_config.dart';

/// Resolve the vehicle of this driver within the active company.
/// The reverse vehicle.driverId field can represent only one of several
/// drivers who use the same car on different shifts.
VehicleProfile? assignedVehicleForDriver(
  DriverProfile driver,
  Iterable<VehicleProfile> vehicles, {
  required bool Function(VehicleProfile) inCompany,
}) {
  final assignedId = (driver.assignedVehicleId ?? '').trim();
  if (assignedId.isNotEmpty) {
    for (final vehicle in vehicles) {
      if (vehicle.id.trim() == assignedId && inCompany(vehicle)) {
        return vehicle;
      }
    }
    return null;
  }
  for (final vehicle in vehicles) {
    if (inCompany(vehicle) &&
        (vehicle.driverId ?? '').trim() == driver.id.trim()) {
      return vehicle;
    }
  }
  return null;
}

/// Every company driver assigned to this vehicle. The legacy reverse
/// [VehicleProfile.driverId] can name only one driver, so it is used only when
/// that driver's authoritative assignment is absent.
List<DriverProfile> driversAssignedToVehicle(
  VehicleProfile vehicle,
  Iterable<DriverProfile> drivers, {
  required bool Function(DriverProfile) inCompany,
}) {
  final vehicleId = vehicle.id.trim();
  if (vehicleId.isEmpty) return const <DriverProfile>[];
  final linked = <DriverProfile>[];
  for (final driver in drivers) {
    if (!inCompany(driver)) continue;
    final assignedId = (driver.assignedVehicleId ?? '').trim();
    if (assignedId == vehicleId ||
        (assignedId.isEmpty && (vehicle.driverId ?? '').trim() == driver.id.trim())) {
      linked.add(driver);
    }
  }
  return linked;
}
