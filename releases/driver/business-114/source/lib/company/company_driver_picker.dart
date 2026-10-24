import 'dart:convert';

import 'package:http/http.dart' as http;

/// Uses a captured company session, never a remembered vehicle-device identity.
/// Membership is enforced by the server; scope tags are checked again before UI.
Future<Map<String, dynamic>> fetchCompanyDriverPicker({
  required String bookingBaseUrl,
  required String tenantId,
  required String companyId,
  required String sessionToken,
  http.Client? client,
}) async {
  if (tenantId.isEmpty || companyId.isEmpty || sessionToken.isEmpty) {
    throw StateError('company_driver_picker_session_required');
  }
  bool sameScope(Map row) =>
      row['tenant_id'] == tenantId &&
      row['company_id'] == companyId &&
      (!row.containsKey('tenantId') || row['tenantId'] == tenantId) &&
      (!row.containsKey('companyId') || row['companyId'] == companyId);
  final transport = client ?? http.Client();
  try {
    final response = await transport
        .get(
          Uri.parse(
            '${bookingBaseUrl.replaceFirst(RegExp(r'/+$'), '')}/admin/company/drivers/index',
          ).replace(
            queryParameters: {'tenant_id': tenantId, 'company_id': companyId},
          ),
          headers: {
            'Accept': 'application/json',
            'Authorization': 'Bearer $sessionToken',
          },
        )
        .timeout(const Duration(seconds: 12));
    final dynamic result = jsonDecode(utf8.decode(response.bodyBytes));
    if (response.statusCode != 200 ||
        result is! Map ||
        result['ok'] != true ||
        !sameScope(result) ||
        result['drivers'] is! List) {
      throw StateError('company_driver_picker_scope_unavailable');
    }
    final drivers = <Map<String, dynamic>>[];
    final seen = <String>{};
    for (final row in result['drivers'] as List) {
      if (row is! Map || !sameScope(row)) continue;
      if (row['is_active'] == false || row['isActive'] == false) continue;
      final id = (row['driver_id'] ?? '').toString().trim();
      final name =
          (row['display_name'] ??
                  row['displayName'] ??
                  row['driver_name'] ??
                  row['driverName'] ??
                  row['name'] ??
                  '')
              .toString()
              .trim();
      if (id.isEmpty || name.isEmpty || !seen.add(id)) continue;
      drivers.add({
        'driver_id': id,
        'name': name,
        'tenant_id': tenantId,
        'company_id': companyId,
      });
    }
    drivers.sort(
      (a, b) => (a['name'] as String).compareTo(b['name'] as String),
    );
    return {'tenant_id': tenantId, 'company_id': companyId, 'drivers': drivers};
  } finally {
    if (client == null) transport.close();
  }
}
