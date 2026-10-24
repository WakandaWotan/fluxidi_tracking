/// An explicit driver assignment takes precedence over a shared vehicle.
/// Vehicle-only legacy records may use the actor's existing scoped vehicle.
bool driverBookingBelongsToActor({
  required String activeDriverId,
  required String assignedDriverId,
  required String assignedVehicleId,
  required String activeVehicleId,
  required Set<String> linkedVehicleIds,
}) {
  if (activeDriverId.trim().isEmpty) return false;
  if (assignedDriverId.trim().isNotEmpty)
    return assignedDriverId.trim() == activeDriverId.trim();
  final vehicle = assignedVehicleId.trim();
  return vehicle.isNotEmpty &&
      (vehicle == activeVehicleId.trim() || linkedVehicleIds.contains(vehicle));
}
