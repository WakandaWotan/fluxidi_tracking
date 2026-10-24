import 'dart:convert';
import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:fluxidi_tracking/driver/vehicle_duty_client.dart';

void main() {
  test('retired dashboard owner cannot read or change a vehicle duty', () async {
    var calls = 0;
    final client = VehicleDutyClient(baseUrl: 'https://fixture.invalid', token: 'fixture-driver',
      driverId: 'd', vehicleId: 'v', isCurrent: () => false,
      client: MockClient((_) async { calls++; return http.Response('{"ok":true}', 200); }));
    await expectLater(client.state(), throwsA(isA<VehicleDutyException>()
      .having((e) => e.code, 'code', 'driver_session_changed')));
    await expectLater(client.command({'action':'pause'}), throwsA(isA<VehicleDutyException>()));
    expect(calls, 0);
    client.close();
  });

  test('duty reply cannot populate another dashboard actor', () async {
    var current = true;
    final reply = Completer<http.Response>();
    final client = VehicleDutyClient(baseUrl: 'https://fixture.invalid', token: 'fixture-driver',
      driverId: 'd', vehicleId: 'v', isCurrent: () => current,
      client: MockClient((_) => reply.future));
    final state = client.state();
    final check = expectLater(state, throwsA(isA<VehicleDutyException>()
      .having((e) => e.code, 'code', 'driver_session_changed')));
    current = false;
    reply.complete(http.Response('{"ok":true,"version":1,"duties":[]}', 200));
    await check;
    client.close();
  });

  test('personal command retries retain command identity and use only driver bearer', () async {
    final requests = <http.Request>[];
    final client = VehicleDutyClient(baseUrl: 'https://fixture.invalid', token: 'fixture-driver', driverId: 'd', vehicleId: 'v',
      client: MockClient((request) async { requests.add(request); return http.Response('{"ok":true,"version":1}', 200); }));
    final command = {'action':'start','duty_id':'duty','command_id':'same-command','expected_version':0};
    await client.command(command); await client.command(command);
    expect(requests[0].headers['authorization'], 'Bearer fixture-driver');
    expect(requests[0].body, requests[1].body);
    expect(jsonDecode(requests[0].body)['vehicle_id'], 'v');
    client.close();
  });
  test('history cannot be attributed to another chauffeur', () async {
    final client = VehicleDutyClient(baseUrl: 'https://fixture.invalid', token: 'fixture-driver', driverId: 'd', vehicleId: 'v',
      client: MockClient((_) async => http.Response('{"ok":true,"items":[{"driver_id":"other","summary":{},"started_at_ms":0}]}',200)));
    await expectLater(client.history(), throwsA(isA<VehicleDutyException>()));client.close();
  });
  test('disabled provider is an error and no empty token causes a request', () async {
    var calls=0;
    final transport=MockClient((_) async {calls++;return http.Response('{"ok":false,"error":"vehicle_operations_disabled"}',503);});
    final client=VehicleDutyClient(baseUrl:'https://fixture.invalid',token:'',driverId:'d',vehicleId:'v',client:transport);
    await expectLater(client.state(),throwsA(isA<VehicleDutyException>()));expect(calls,0);client.close();
  });
}
