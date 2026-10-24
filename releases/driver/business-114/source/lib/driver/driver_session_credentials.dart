import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// The bearer is keyed by the exact tenant, company and driver. The JSON
/// session file contains only non-secret metadata.
class DriverSessionCredentials {
  DriverSessionCredentials({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  String keyFor(String tenantId, String companyId, String driverId) {
    final scope = '$tenantId\u0000$companyId\u0000$driverId';
    return 'driver_bearer_v1_${base64Url.encode(utf8.encode(scope))}';
  }

  Future<String?> read(String tenantId, String companyId, String driverId) =>
      _storage.read(key: keyFor(tenantId, companyId, driverId));

  Future<void> write(
    String tenantId,
    String companyId,
    String driverId,
    String token,
  ) => _storage.write(
    key: keyFor(tenantId, companyId, driverId),
    value: token,
  );

  Future<void> delete(String tenantId, String companyId, String driverId) =>
      _storage.delete(key: keyFor(tenantId, companyId, driverId));
}
