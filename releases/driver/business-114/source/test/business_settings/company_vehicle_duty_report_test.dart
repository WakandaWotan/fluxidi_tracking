import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:fluxidi_tracking/company/company_vehicle_duty_report_page.dart';

Map<String, dynamic> row(String id, String vehicle) => {
  'company_id': 'c', 'driver_id': 'd', 'vehicle_id': vehicle, 'duty_id': id,
  'started_at_ms': 1000, 'ended_at_ms': 3601000,
  'summary': {'ok': true, 'driver_id': 'd', 'vehicle_id': vehicle, 'duty_id': id,
    'elapsed_ms': 3600000, 'pause_ms': 600000, 'duty_ms': 3000000},
};
CompanyVehicleDutyReportClient client(http.Client transport) => CompanyVehicleDutyReportClient(
  baseUrl: 'https://fixture.invalid', token: 'company-fixture', companyId: 'c', driverId: 'd', client: transport);

void main() {
  test('company report binds selected chauffeur and authenticates with company bearer', () async {
    final api = client(MockClient((request) async {
      expect(request.url.path, '/admin/company/vehicle-duty-history');
      expect(request.headers['authorization'], 'Bearer company-fixture');
      expect(jsonDecode(request.body), {'company_id': 'c', 'driver_id': 'd'});
      return http.Response(jsonEncode({'ok': true, 'items': [row('a', 'v')], 'cursor': null}), 200);
    }));
    expect((await api.history())['items'], hasLength(1)); api.close();
  });
  test('foreign company archive is never rendered', () async {
    final api = client(MockClient((_) async => http.Response(jsonEncode({'ok': true,
      'items': [{...row('a', 'v'), 'company_id': 'foreign'}]}), 200)));
    await expectLater(api.history(), throwsFormatException); api.close();
  });
  testWidgets('partial duty totals stay labelled until next page is loaded', (tester) async {
    var calls = 0;
    final api = client(MockClient((request) async {
      calls++;
      if (calls == 2) expect(jsonDecode(request.body)['cursor'], 'next');
      return http.Response(jsonEncode({'ok': true,
        'items': [row(calls == 1 ? 'a' : 'b', calls == 1 ? 'v1' : 'v2')],
        'cursor': calls == 1 ? 'next' : null}), 200);
    }));
    await tester.pumpWidget(MaterialApp(home: CompanyVehicleDutyReportPage(client: api, driverName: 'Bart')));
    await tester.pumpAndSettle();
    expect(find.text('Totaal geladen diensten (onvolledig)'), findsOneWidget);
    expect(find.text('Aanwezig: 1 u 0 min'), findsOneWidget);
    await tester.ensureVisible(find.text('Meer diensten'));
    await tester.tap(find.text('Meer diensten')); await tester.pumpAndSettle();
    expect(find.text('Totaal afgeronde diensten'), findsOneWidget);
    expect(find.text('Aanwezig: 2 u 0 min'), findsOneWidget);
    expect(find.text('Dienst zonder pauzes: 1 u 40 min'), findsOneWidget);
    expect(find.text('Meer diensten'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
