// COMPANY-CUSTOMER-OPS-P0 — local web demo repository (no dart:io).

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:fluxidi_tracking/company/company_customer_import_session_core.dart';
import 'package:fluxidi_tracking/company/company_customer_models.dart';
import 'package:fluxidi_tracking/company/company_customers_repository.dart';

const String kCompanyCustomerOpsLocalDemoBaseUrl = String.fromEnvironment(
  'BOOKING_BASE_URL',
  defaultValue: 'http://127.0.0.1:8788',
);
const String kCompanyCustomerOpsLocalDemoToken = String.fromEnvironment(
  'COMPANY_SESSION_TOKEN',
  defaultValue: 'cst_local_demo_synthetic',
);
const String kCompanyCustomerOpsLocalDemoCompanyId = String.fromEnvironment(
  'FLUXIDI_DEV_COMPANY_ID',
  defaultValue: 'demo_company_p0',
);

String _demoBase() {
  final raw = kCompanyCustomerOpsLocalDemoBaseUrl.trim();
  return raw.endsWith('/') ? raw.substring(0, raw.length - 1) : raw;
}

Future<Map<String, String>> _demoHeaders() async {
  return <String, String>{
    'Accept': 'application/json',
    'Content-Type': 'application/json',
    'Authorization': 'Bearer $kCompanyCustomerOpsLocalDemoToken',
  };
}

Map<String, String> _demoScope() {
  final id = kCompanyCustomerOpsLocalDemoCompanyId.trim();
  return <String, String>{
    'tenant_id': id,
    'company_id': id,
    'tenantId': id,
    'companyId': id,
  };
}

Map<String, dynamic> _decode(List<int> bytes) {
  final decoded = jsonDecode(utf8.decode(bytes));
  if (decoded is! Map) {
    throw const CompanyCustomerException('invalid_payload');
  }
  return Map<String, dynamic>.from(decoded);
}

CompanyCustomersRepository createCompanyCustomersRepository() {
  return CompanyCustomersRepository(
    headers: _demoHeaders,
    scopeQuery: _demoScope(),
    listTransport: ({
      required path,
      required query,
      required headers,
    }) async {
      final uri = Uri.parse('${_demoBase()}$path').replace(queryParameters: query);
      final res = await http.get(uri, headers: await headers());
      final decoded = _decode(res.bodyBytes);
      if (res.statusCode != 200) {
        throw CompanyCustomerException(
          decoded['error']?.toString() ?? 'http_${res.statusCode}',
        );
      }
      return decoded;
    },
    sendTransport: ({
      required method,
      required path,
      required query,
      required body,
      required headers,
      idempotencyKey,
    }) async {
      final uri = Uri.parse('${_demoBase()}$path').replace(queryParameters: query);
      final resolved = Map<String, String>.from(await headers());
      if ((idempotencyKey ?? '').trim().isNotEmpty) {
        resolved['Idempotency-Key'] = idempotencyKey!.trim();
      }
      final encoded = jsonEncode(body);
      final res = method == 'PATCH'
          ? await http.patch(uri, headers: resolved, body: encoded)
          : await http.post(uri, headers: resolved, body: encoded);
      final decoded = _decode(res.bodyBytes);
      if (res.statusCode != 200 && res.statusCode != 201) {
        throw CompanyCustomerException(
          decoded['error']?.toString() ?? 'http_${res.statusCode}',
        );
      }
      return decoded;
    },
  );
}

CompanyCustomerImportSessionStore createCompanyCustomerImportSessionStore() {
  return MemoryCompanyCustomerImportSessionStore();
}

Future<List<Map<String, dynamic>>> fetchCompanyLocalBookings() async {
  final uri = Uri.parse('${_demoBase()}/bookings').replace(
    queryParameters: <String, String>{
      ..._demoScope(),
      'limit': '50',
    },
  );
  final res = await http.get(uri, headers: await _demoHeaders());
  final decoded = _decode(res.bodyBytes);
  if (res.statusCode != 200 || decoded['ok'] != true) {
    throw CompanyCustomerException(
      decoded['error']?.toString() ?? 'bookings_list_failed',
    );
  }
  final items = decoded['items'];
  if (items is! List) return const <Map<String, dynamic>>[];
  return [
    for (final item in items)
      if (item is Map) Map<String, dynamic>.from(item),
  ];
}

Future<Map<String, dynamic>> fetchCompanyLocalBooking(String bookingId) async {
  final id = bookingId.trim();
  if (id.isEmpty) {
    throw const CompanyCustomerException('booking_id_required');
  }
  final uri = Uri.parse(
    '${_demoBase()}/bookings/${Uri.encodeComponent(id)}',
  ).replace(queryParameters: _demoScope());
  final res = await http.get(uri, headers: await _demoHeaders());
  final decoded = _decode(res.bodyBytes);
  if (res.statusCode != 200 || decoded['ok'] != true) {
    throw CompanyCustomerException(
      decoded['error']?.toString() ?? 'booking_not_found',
    );
  }
  return decoded;
}
