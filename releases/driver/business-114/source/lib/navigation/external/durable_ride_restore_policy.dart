/// A disk snapshot is recovery evidence, never assignment authority.
/// Keep it for retry/review when the exact server binding cannot be proved.
String? durableRideRestoreBlockReason({
  required bool serverRecordFound,
  required bool actorAllowed,
  required String serverStatus,
  required bool isStreet,
  required String trackingTripId,
  required bool finalizePending,
  required String expectedLegId,
  required String actualLegId,
}) {
  if (!serverRecordFound) return 'server_binding_missing';
  if (!actorAllowed) return 'assignment_mismatch';
  if (expectedLegId.trim().isNotEmpty &&
      expectedLegId.trim() != actualLegId.trim())
    return 'leg_mismatch';
  if (finalizePending) return 'finalization_pending';
  final status = serverStatus.trim().toUpperCase();
  if (!const {'IN_PROGRESS', 'STARTED', 'ACTIVE', 'ON_TRIP'}.contains(status)) {
    return 'server_not_active';
  }
  if (isStreet && trackingTripId.trim().isEmpty)
    return 'tracking_identity_missing';
  return null;
}

/// Offline/manual recovery confers no server booking or assignment rights.
/// Legacy snapshots without explicit actor and pricing proof remain pending.
bool canRestoreLocalStreetRide({
  required bool isStreet,
  required bool? backendConfirmed,
  required String ownerDriverId,
  required String activeDriverId,
  required String ownerVehicleId,
  required String activeVehicleId,
  required String tripId,
  required bool finalizePending,
  required String lifecyclePhase,
  required Map<String, dynamic>? meterPricing,
}) {
  if (!isStreet ||
      backendConfirmed != false ||
      tripId.trim().isNotEmpty ||
      finalizePending ||
      lifecyclePhase != 'active' ||
      ownerDriverId.trim().isEmpty ||
      ownerDriverId.trim() != activeDriverId.trim())
    return false;
  if (ownerVehicleId.trim().isNotEmpty &&
      ownerVehicleId.trim() != activeVehicleId.trim())
    return false;
  return isValidDurableMeterPricing(meterPricing);
}

bool isValidDurableMeterPricing(Map<String, dynamic>? meterPricing) {
  if (meterPricing == null) return false;
  for (final key in ['start_fee', 'per_km', 'wait_per_min', 'vat_rate']) {
    final value = meterPricing[key];
    if (value is! num || !value.isFinite || value < 0) return false;
  }
  if ((meterPricing['vat_rate'] as num) > 1) return false;
  return const {'incl', 'excl'}.contains(meterPricing['vat_mode']) &&
      (meterPricing['currency'] is String &&
          (meterPricing['currency'] as String).trim().isNotEmpty);
}
