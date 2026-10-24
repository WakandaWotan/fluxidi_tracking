/// Exact server-issued actor selected for this physical device. Display names,
/// employee numbers and company-admin preview tokens are never identity proof.
class DriverDutyIdentity {
  const DriverDutyIdentity({
    required this.tenantId,
    required this.companyId,
    required this.driverId,
    required this.vehicleId,
  });

  final String tenantId;
  final String companyId;
  final String driverId;
  final String vehicleId;

  bool get complete => [tenantId, companyId, driverId, vehicleId]
      .every((value) => value.trim().isNotEmpty);

  bool matches({
    required String tenantId,
    required String companyId,
    required String driverId,
    required String vehicleId,
  }) => complete && this.tenantId == tenantId.trim() &&
      this.companyId == companyId.trim() && this.driverId == driverId.trim() &&
      this.vehicleId == vehicleId.trim();

  Map<String, String> toJson() => {
    'tenant_id': tenantId, 'company_id': companyId,
    'driver_id': driverId, 'vehicle_id': vehicleId,
  };

  factory DriverDutyIdentity.fromJson(Map<String, dynamic> json) =>
      DriverDutyIdentity(
        tenantId: (json['tenant_id'] ?? '').toString().trim(),
        companyId: (json['company_id'] ?? '').toString().trim(),
        driverId: (json['driver_id'] ?? '').toString().trim(),
        vehicleId: (json['vehicle_id'] ?? '').toString().trim(),
      );
}
