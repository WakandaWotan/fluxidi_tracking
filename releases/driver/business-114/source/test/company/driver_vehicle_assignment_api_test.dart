import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/company/driver_vehicle_assignment_api.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  const base = 'https://booking.example.test';
  const tenant = 'taxi-mario';
  const company = 'taxi-mario';

  test('vehicle change sends only scoped assignment fields and confirms readback', () async {
    final requests = <http.Request>[];
    final client = MockClient((request) async {
      requests.add(request);
      if (request.method == 'POST') {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body, {
          'tenant_id': tenant,
          'company_id': company,
          'driver_id': 'driver-9',
          'expected_vehicle_id': 'vito',
          'vehicle_id': 'corolla',
        });
        expect(request.headers['authorization'], 'Bearer session');
        return http.Response('{"ok":true}', 200);
      }
      return http.Response(
        '{"drivers":[{"driver_id":"driver-9","assigned_vehicle_id":"corolla"}]}',
        200,
      );
    });
    final result = await saveDriverVehicleAssignment(
      bookingBaseUrl: base,
      tenantId: tenant,
      companyId: company,
      companySessionToken: 'session',
      driverId: 'driver-9',
      expectedVehicleId: 'vito',
      newVehicleId: 'corolla',
      client: client,
    );
    expect(result.confirmed, isTrue);
    expect(requests.map((request) => request.method), ['POST', 'GET']);
    for (final request in requests) {
      expect(request.url.queryParameters, {
        'tenant_id': tenant,
        'company_id': company,
      });
    }
  });

  test('missing endpoint fails closed without a local assignment', () async {
    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      return http.Response('{"error":"not_found"}', 404);
    });
    final result = await saveDriverVehicleAssignment(
      bookingBaseUrl: base,
      tenantId: tenant,
      companyId: company,
      companySessionToken: 'session',
      driverId: 'driver-9',
      expectedVehicleId: 'vito',
      newVehicleId: 'corolla',
      client: client,
    );
    expect(result.confirmed, isFalse);
    expect(result.statusCode, 404);
    expect(calls, 1);
  });

  test('wrong readback cannot claim success', () async {
    final client = MockClient((request) async => request.method == 'POST'
        ? http.Response('{"ok":true}', 200)
        : http.Response(
            '{"drivers":[{"driver_id":"driver-9","assigned_vehicle_id":"vito"}]}',
            200,
          ));
    final result = await saveDriverVehicleAssignment(
      bookingBaseUrl: base,
      tenantId: tenant,
      companyId: company,
      companySessionToken: 'session',
      driverId: 'driver-9',
      expectedVehicleId: 'vito',
      newVehicleId: 'corolla',
      client: client,
    );
    expect(result.confirmed, isFalse);
    expect(result.error, 'readback_mismatch');
  });

  test('rosters use one company-scoped request for all drivers', () async {
    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      expect(request.url.queryParameters['company_id'], company);
      expect(request.headers['authorization'], 'Bearer session');
      return http.Response(
        '{"drivers":[{"driver_id":"one","weekly_roster":{"days":{}},"driver_code_hash":"secret"},'
        '{"driver_id":"two","weekly_roster":{"days":{}}}]}',
        200,
      );
    });
    final rows = await loadCompanyDriverRosterRecords(
      bookingBaseUrl: base,
      tenantId: tenant,
      companyId: company,
      companySessionToken: 'session',
      client: client,
    );
    expect(calls, 1);
    expect(rows.keys, ['one', 'two']);
    expect(rows['one']!.containsKey('driver_code_hash'), isFalse);
  });

  test('invalid scope or insecure host makes no request', () async {
    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      return http.Response('', 200);
    });
    final result = await saveDriverVehicleAssignment(
      bookingBaseUrl: 'http://booking.example.test',
      tenantId: tenant,
      companyId: company,
      companySessionToken: 'session',
      driverId: 'driver-9',
      expectedVehicleId: '',
      newVehicleId: 'corolla',
      client: client,
    );
    expect(result.confirmed, isFalse);
    expect(calls, 0);
  });
}
