import '../app_config.dart';
import '../driver_session_store.dart';

/// GPS publication uses the authenticated actor, even on a company tablet.
/// A foreign local fleet and arbitrary first vehicle are never actor identity.
String authenticatedDriverVehicleId({
  required ActiveDriverSession session,
  required String activeDriverId,
  required Iterable<VehicleProfile> vehicles,
}) {
  if (session.driverId.trim() != activeDriverId.trim() ||
      activeDriverId.trim().isEmpty || (session.companyId ?? '').trim().isEmpty) return '';
  final assigned = (session.assignedVehicleId ?? '').trim();
  if (assigned.isNotEmpty) return assigned;
  for (final vehicle in vehicles) {
    if (vehicle.isActive && vehicle.companyId?.trim() == (session.companyId ?? '').trim() &&
        vehicle.driverId?.trim() == session.driverId.trim()) return vehicle.id.trim();
  }
  return '';
}
