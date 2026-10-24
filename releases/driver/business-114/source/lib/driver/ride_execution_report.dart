/// Legacy history remains compatible; stamped rides must belong to the
/// original scoped driver and vehicle, regardless of today's fleet assignment.
bool historyExecutionBelongsToDriver(
  Map<dynamic, dynamic> row, {
  required String tenantId,
  required String companyId,
  required String driverId,
}) {
  final identity = row['execution_identity'];
  if (identity == null) return true;
  if (identity is! Map) return false;
  final duty = identity['duty_id'];
  return identity['tenant_id'] == tenantId &&
      identity['company_id'] == companyId &&
      identity['driver_id'] == driverId &&
      identity['driver_id'] == row['driver_id'] &&
      identity['vehicle_id'] is String &&
      (identity['vehicle_id'] as String).isNotEmpty &&
      identity['vehicle_id'] == row['vehicle_id'] &&
      duty is String &&
      duty.isNotEmpty;
}
