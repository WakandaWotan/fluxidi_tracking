import 'dart:convert';

import 'package:http/http.dart' as http;

import '../app_config.dart';

class DriverVehicleAssignmentResult {
  const DriverVehicleAssignmentResult({
    required this.confirmed,
    required this.error,
    this.statusCode,
  });

  final bool confirmed;
  final String error;
  final int? statusCode;
}

/// One scoped index read for the whole vehicle screen; never one request per
/// vehicle or driver. Only display-safe fields are retained.
Future<Map<String, Map<String, dynamic>>> loadCompanyDriverRosterRecords({
  required String bookingBaseUrl,
  required String tenantId,
  required String companyId,
  required String companySessionToken,
  http.Client? client,
}) async {
  final token = companySessionToken.trim();
  final tenant = tenantId.trim();
  final company = companyId.trim();
  if (token.isEmpty || tenant.isEmpty || company.isEmpty) return const {};
  final transport = client ?? http.Client();
  try {
    final base = Uri.parse(bookingBaseUrl);
    if (base.scheme != 'https') return const {};
    final uri = base.replace(
      path: '${base.path.replaceAll(RegExp(r'/$'), '')}/admin/company/drivers/index',
      queryParameters: <String, String>{'tenant_id': tenant, 'company_id': company},
    );
    final response = await transport.get(
      uri,
      headers: companyBearerHeaders(token),
    ).timeout(const Duration(seconds: 12));
    if (response.statusCode < 200 || response.statusCode >= 300) return const {};
    final decoded = jsonDecode(response.body);
    if (decoded is! Map || decoded['drivers'] is! List) return const {};
    final records = <String, Map<String, dynamic>>{};
    for (final raw in decoded['drivers'] as List) {
      if (raw is! Map) continue;
      final id = (raw['driver_id'] ?? raw['driverId'] ?? '').toString().trim();
      if (id.isEmpty) continue;
      records[id] = <String, dynamic>{
        'driver_id': id,
        'weekly_roster': raw['weekly_roster'],
        'roster_exceptions': raw['roster_exceptions'],
      };
    }
    return records;
  } catch (_) {
    return const {};
  } finally {
    if (client == null) transport.close();
  }
}

/// Mutates only the selected driver's vehicle. The general driver-index
/// upsert rewrites profile and login fields, so it must never be used here.
/// The dedicated endpoint fails closed until its Bookingworker version is
/// deployed. Success is reported only after a scoped server readback.
Future<DriverVehicleAssignmentResult> saveDriverVehicleAssignment({
  required String bookingBaseUrl,
  required String tenantId,
  required String companyId,
  required String companySessionToken,
  required String driverId,
  required String expectedVehicleId,
  required String newVehicleId,
  http.Client? client,
}) async {
  final tenant = tenantId.trim();
  final company = companyId.trim();
  final driver = driverId.trim();
  final next = newVehicleId.trim();
  final token = companySessionToken.trim();
  if (tenant.isEmpty || company.isEmpty || driver.isEmpty || next.isEmpty || token.isEmpty) {
    return const DriverVehicleAssignmentResult(
      confirmed: false,
      error: 'missing_scope_or_selection',
    );
  }
  final transport = client ?? http.Client();
  try {
    final base = Uri.parse(bookingBaseUrl);
    if (base.scheme != 'https') {
      return const DriverVehicleAssignmentResult(confirmed: false, error: 'insecure_endpoint');
    }
    final scope = <String, String>{'tenant_id': tenant, 'company_id': company};
    final saveUri = base.replace(
      path: '${base.path.replaceAll(RegExp(r'/$'), '')}/admin/company/drivers/index/assign-vehicle',
      queryParameters: scope,
    );
    final response = await transport.post(
      saveUri,
      headers: companyBearerHeaders(token, json: true),
      body: jsonEncode(<String, String>{
        ...scope,
        'driver_id': driver,
        'expected_vehicle_id': expectedVehicleId.trim(),
        'vehicle_id': next,
      }),
    ).timeout(const Duration(seconds: 12));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      return DriverVehicleAssignmentResult(
        confirmed: false,
        error: 'save_rejected',
        statusCode: response.statusCode,
      );
    }
    final readUri = base.replace(
      path: '${base.path.replaceAll(RegExp(r'/$'), '')}/admin/company/drivers/index',
      queryParameters: scope,
    );
    final readback = await transport.get(
      readUri,
      headers: companyBearerHeaders(token),
    ).timeout(const Duration(seconds: 12));
    if (readback.statusCode < 200 || readback.statusCode >= 300) {
      return DriverVehicleAssignmentResult(
        confirmed: false,
        error: 'readback_failed',
        statusCode: readback.statusCode,
      );
    }
    final decoded = jsonDecode(readback.body);
    if (decoded is! Map || decoded['drivers'] is! List) {
      return const DriverVehicleAssignmentResult(confirmed: false, error: 'invalid_readback');
    }
    final rows = (decoded['drivers'] as List).whereType<Map>();
    final matches = rows.where((row) =>
        (row['driver_id'] ?? row['driverId'] ?? '').toString().trim() == driver);
    if (matches.length != 1 ||
        (matches.single['assigned_vehicle_id'] ??
                matches.single['assignedVehicleId'] ?? '')
            .toString()
            .trim() != next) {
      return const DriverVehicleAssignmentResult(confirmed: false, error: 'readback_mismatch');
    }
    return DriverVehicleAssignmentResult(
      confirmed: true,
      error: '',
      statusCode: response.statusCode,
    );
  } catch (_) {
    return const DriverVehicleAssignmentResult(confirmed: false, error: 'request_failed');
  } finally {
    if (client == null) transport.close();
  }
}
