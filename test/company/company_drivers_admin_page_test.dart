import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/company/company_drivers_admin_page.dart';

void main() {
  testWidgets('drivers admin lists, adds and deletes without opening the cockpit', (
    tester,
  ) async {
    var drivers = <Map<String, dynamic>>[
      <String, dynamic>{
        'driver_id': 'drv_demo_company_p0_1',
        'display_name': 'Karel Peeters',
        'phone': '+32470000011',
      },
    ];
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: CompanyDriversAdminPage(
          language: AppLanguage.nl,
          driversLoader: () async => drivers,
          subscriptionLoader: () async => <String, dynamic>{
            'max_drivers': 3,
          },
          driverUpsert: (driver) async {
            drivers = <Map<String, dynamic>>[...drivers, driver];
          },
          driverDelete: (driverId) async {
            drivers = drivers
                .where((item) => item['driver_id'] != driverId)
                .toList();
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(kCompanyDriversAdminPageKey), findsOneWidget);
    expect(find.text('Karel Peeters'), findsOneWidget);
    expect(
      find.textContaining('administratief chauffeursbeheer'),
      findsOneWidget,
    );
    await tester.enterText(find.byKey(kCompanyDriversNameKey), 'Lina Moreau');
    await tester.enterText(find.byKey(kCompanyDriversPhoneKey), '+32470000022');
    await tester.tap(find.byKey(kCompanyDriversAddKey));
    await tester.pumpAndSettle();
    expect(find.text('Lina Moreau'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.delete_outline).first);
    await tester.pumpAndSettle();
    expect(find.text('Karel Peeters'), findsNothing);
  });
}
