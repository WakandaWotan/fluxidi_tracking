import '../app_config.dart' show VehicleProfile;
import '../driver_session_store.dart' show ActiveDriverSession;

/// Display metadata only. This never chooses a vehicle or changes an offer.
class DriverRideOfferVehiclePresentation {
  const DriverRideOfferVehiclePresentation({this.name, this.capacity});
  final String? name;
  final int? capacity;
}

bool driverOfferDisplayIsTechnicalId(String value) =>
    RegExp(
      r'^(?:vh_|veh_|vehicle[:_-]|drv_|company:|[a-f0-9]{32,}$)',
      caseSensitive: false,
    ).hasMatch(value.trim()) ||
    RegExp(
      r'^[a-f0-9]{8}-(?:[a-f0-9]{4}-){3}[a-f0-9]{12}$',
      caseSensitive: false,
    ).hasMatch(value.trim());

DriverRideOfferVehiclePresentation driverRideOfferVehiclePresentation({
  required String vehicleId,
  required ActiveDriverSession? session,
  required Iterable<VehicleProfile> vehicles,
}) {
  const unknown = DriverRideOfferVehiclePresentation();
  if (session == null ||
      !session.isStandaloneLoginSession ||
      (session.tenantId ?? '').trim().isEmpty ||
      (session.companyId ?? '').trim().isEmpty ||
      session.assignedVehicleId != vehicleId)
    return unknown;
  // Legacy unscoped/example rows cannot supply confirmed company metadata.
  final matches = vehicles
      .where((v) => v.id == vehicleId && v.companyId == session.companyId)
      .toList();
  if (matches.length != 1) return unknown;
  final vehicle = matches.single;
  final names = [vehicle.brandModel.trim(), vehicle.vehicleName.trim()].where(
    (s) =>
        s.isNotEmpty && s != vehicleId && !driverOfferDisplayIsTechnicalId(s),
  );
  return DriverRideOfferVehiclePresentation(
    name: names.isEmpty ? null : names.first,
    capacity: vehicle.passengerCapacity > 0 ? vehicle.passengerCapacity : null,
  );
}
