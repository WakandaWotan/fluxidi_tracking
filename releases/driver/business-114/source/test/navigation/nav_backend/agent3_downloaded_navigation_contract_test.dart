import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:fluxidi_tracking/navigation/driver_navigation_models.dart';
import 'package:fluxidi_tracking/navigation/nav_backend/driver_navigation_worker_client.dart';

void main() {
  test('B111 guard rejects exact live-worker response contract, replayed entirely locally', () async {
    final body = File('test/navigation/fixtures/agent3_legacy_navigation_response.json').readAsStringSync();
    final json=jsonDecode(body) as Map;
    expect(json['ok'],true);expect(json['distance_m'],1000);expect(json['duration_s'],120);
    var calls=0;
    final client=DriverNavigationWorkerClient(baseUrl:'https://fixture.invalid',loadHeaders:()=>{'Authorization':'Bearer LOCAL_ONLY'},
      httpClient:MockClient((request) async {calls++;return http.Response(body,200);}));
    expect(await client.route(origin:const DriverLonLat(4,51),destination:const DriverLonLat(4.1,51.1),country:'BE'),isNull);
    expect(calls,1);
  });
}
