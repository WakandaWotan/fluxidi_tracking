import 'dart:convert';
import 'package:fluxidi_tracking/company/driver_management_native_repository.dart';

class NativeDriverFixture {
  NativeDriverFixture({
    this.company = 'company-future',
    this.tenant = 'tenant-test',
  });
  final String company, tenant;
  bool current = true;
  Future<bool> Function()? sessionProbe;
  bool empty = false;
  int denied = 0;
  final requests = <Uri>[];
  bool partnerWrite = true;
  final partnerRecords = <Map<String, dynamic>>[];

  List<Map<String, dynamic>> get scopedVehicles => [
    {
      'tenant_id': tenant,
      'company_id': company,
      'vehicle_id': 'vehicle-1',
      'vehicle_name': 'Tesla testwagen',
      'license_plate': 'TEST',
      'vehicle_type': 'taxi',
    },
    {
      'tenant_id': tenant,
      'company_id': company,
      'vehicle_id': 'vehicle-2',
      'vehicle_name': 'Tweede testwagen',
      'license_plate': 'TEST',
      'vehicle_type': 'van',
    },
  ];

  Map<String, dynamic> get driver => {
    'tenant_id': tenant,
    'company_id': company,
    'driver_id': 'driver-1',
    'display_name':
        'Chauffeur met een bijzonder lange samengestelde familienaam',
    'status': 'offline',
    'is_active': true,
    'driver_type': 'FLEET_DRIVER',
    'contact': {
      'phone': '+32 400 00 00 00',
      'email': 'test@example.invalid',
      'revealed': true,
    },
    // Match the real host contract: only the readiness fleet carries scope.
    'vehicles': scopedVehicles
        .map(
          (vehicle) => {...vehicle}
            ..remove('tenant_id')
            ..remove('company_id'),
        )
        .toList(),
    'observed_at': '2026-10-12T10:00:00Z',
    'last_seen_at': null,
    'ride_count': null,
    'created_at': null,
    'current_trip': null,
    'recent_trips': <dynamic>[],
  };

  Map<String, dynamic> get ready => {
    'ok': true,
    'ready': true,
    'read_only': true,
    'contract': 'fluxidi-driver-management-read-v1',
    'operator': {'tenant_id': tenant, 'company_id': company},
    'vehicles': empty ? [] : scopedVehicles,
    'capabilities': {
      'drivers_read': true,
      'export_csv': true,
      'partner_write': false,
      'settlement_write': false,
      'import_write': false,
      'bulk_assign': false,
    },
  };

  Future<DriverManagementResponse> get(
    Uri uri,
    Map<String, String> headers,
  ) async {
    requests.add(uri);
    if (headers['Authorization'] != 'Bearer local-test')
      throw StateError('missing auth');
    if (denied != 0)
      return (status: denied, body: 'PRIVATE SERVER ERROR MUST NOT APPEAR');
    if (uri.path.endsWith('/app-readiness'))
      return (
        status: 200,
        body: jsonEncode({
          ...ready,
          'contract': 'fluxidi-driver-management-app-v2',
          'roster_read_only': true,
          'capabilities': {
            'partner_read': true,
            'partner_write': partnerWrite,
            'financial_rule_write': false,
            'settlement_read': false,
            'settlement_write': false,
            'import_write': false,
            'bulk_assign': false,
            'bulk_write': false,
          },
        }),
      );
    if (uri.path.endsWith('/partners'))
      return (
        status: 200,
        body: jsonEncode({'ok': true, 'partners': partnerRecords}),
      );
    if (uri.path.endsWith('/readiness'))
      return (status: 200, body: jsonEncode(ready));
    if (uri.path.endsWith('/export'))
      return (status: 200, body: '"Name","Company"\r\n"Test","$company"\r\n');
    if (uri.path.endsWith('/detail'))
      return (status: 200, body: jsonEncode({'ok': true, 'driver': driver}));
    final second = uri.queryParameters['cursor'] == 'next-page';
    final noResults = empty || uri.queryParameters['q'] == 'geen';
    return (
      status: 200,
      body: jsonEncode({
        'ok': true,
        'items': noResults ? [] : [driver],
        'total': noResults ? 0 : 2,
        'offset': second ? 1 : 0,
        'limit': 25,
        'next_cursor': noResults || second ? null : 'next-page',
        'observed_at': '2026-10-12T10:00:00Z',
      }),
    );
  }

  DriverManagementNativeRepository repository({
    Future<DriverManagementResponse> Function(Uri, Map<String, String>)? get,
  }) => DriverManagementNativeRepository(
    companyId: company,
    authorization: 'Bearer local-test',
    sessionUnchanged: () => sessionProbe?.call() ?? Future.value(current),
    get: get ?? this.get,
  );
}
