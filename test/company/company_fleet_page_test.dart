import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/company/company_fleet_page.dart';

void main() {
  testWidgets('fleet lists the seeded vehicle and keeps the app vehicle limit', (
    tester,
  ) async {
    var saved = <Map<String, dynamic>>[];
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: CompanyFleetPage(
          language: AppLanguage.nl,
          vehiclesLoader: () async => <Map<String, dynamic>>[
            <String, dynamic>{
              'vehicle_id': 'vh_demo_company_p0_1',
              'vehicle_name': 'S-Klasse',
              'brand_model': 'Mercedes S500',
              'license_plate': '1-FLX-001',
            },
          ],
          subscriptionLoader: () async => <String, dynamic>{
            'max_vehicles': 1,
          },
          vehiclesSaver: (vehicles) async {
            saved = vehicles;
            return vehicles;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(kCompanyFleetPageKey), findsOneWidget);
    expect(find.text('S-Klasse'), findsOneWidget);
    expect(find.textContaining('1-FLX-001'), findsOneWidget);
    expect(find.text('Limiet bereikt'), findsOneWidget);
    await tester.tap(find.byKey(kCompanyFleetAddKey));
    await tester.pumpAndSettle();
    expect(saved, isEmpty);
  });

  testWidgets('fleet can add the included vehicle when the slot is free', (
    tester,
  ) async {
    var stored = <Map<String, dynamic>>[];
    await tester.pumpWidget(
      MaterialApp(
        home: CompanyFleetPage(
          language: AppLanguage.nl,
          vehiclesLoader: () async => stored,
          subscriptionLoader: () async => <String, dynamic>{
            'max_vehicles': 1,
          },
          vehiclesSaver: (vehicles) async {
            stored = vehicles;
            return vehicles;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(kCompanyFleetNameKey), 'S-Klasse');
    await tester.enterText(find.byKey(kCompanyFleetPlateKey), '1-FLX-001');
    await tester.tap(find.byKey(kCompanyFleetAddKey));
    await tester.pumpAndSettle();
    expect(stored.single['license_plate'], '1-FLX-001');
    expect(find.text('S-Klasse'), findsWidgets);
  });
}
