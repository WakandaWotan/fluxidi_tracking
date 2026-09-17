import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/company/company_agenda_labels.dart';
import 'package:fluxidi_tracking/company/company_driver_agenda_color_chips.dart';
import 'package:fluxidi_tracking/company/company_driver_schedule_page.dart';
import 'package:fluxidi_tracking/company/company_drivers_admin_page.dart';

void main() {
  testWidgets(
    'drivers admin lists, adds and deletes without opening the cockpit',
    (tester) async {
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
            subscriptionLoader: () async => <String, dynamic>{'max_drivers': 3},
            driverUpsert: (driver) async {
              expect(driver['agenda_color'], isNotEmpty);
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
      await tester.enterText(
        find.byKey(kCompanyDriversPhoneKey),
        '+32470000022',
      );
      await tester.tap(find.byKey(kCompanyDriversAddKey));
      await tester.pumpAndSettle();
      expect(find.text('Lina Moreau'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.delete_outline).first);
      await tester.pumpAndSettle();
      expect(find.text('Karel Peeters'), findsNothing);
    },
  );

  testWidgets('existing driver color can be changed under Agendakleur', (
    tester,
  ) async {
    var drivers = <Map<String, dynamic>>[
      <String, dynamic>{
        'driver_id': 'drv_demo_company_p0_1',
        'display_name': 'Karel Peeters',
        'phone': '+32470000011',
        'agenda_color': '#C9A227',
      },
    ];
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: CompanyDriversAdminPage(
          language: AppLanguage.nl,
          driversLoader: () async => drivers,
          subscriptionLoader: () async => <String, dynamic>{'max_drivers': 3},
          driverUpsert: (driver) async {
            expect(driver['agenda_color'], '#2F6B4F');
            drivers = <Map<String, dynamic>>[
              <String, dynamic>{...drivers.first, ...driver},
            ];
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text(kCompanyAgendaColorLabel.of(AppLanguage.nl)),
      findsWidgets,
    );
    await tester.tap(
      find.byKey(companyDriverAgendaColorActionKey('drv_demo_company_p0_1')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byKey(kCompanyDriverAgendaColorPickerKey),
        matching: find.byKey(companyDriverAgendaColorChipKey('#2F6B4F')),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(kCompanyDriverAgendaColorSaveKey));
    await tester.pumpAndSettle();
    expect(drivers.first['agenda_color'], '#2F6B4F');
  });

  testWidgets('Uurrooster from Chauffeurs opens the roster of that driver', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: CompanyDriversAdminPage(
          language: AppLanguage.nl,
          driversLoader: () async => <Map<String, dynamic>>[
            <String, dynamic>{
              'driver_id': 'drv_karel',
              'display_name': 'Karel Peeters',
              'phone': '+32470000011',
            },
          ],
          subscriptionLoader: () async => <String, dynamic>{'max_drivers': 3},
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(companyDriverScheduleActionKey('drv_karel')));
    await tester.pumpAndSettle();
    expect(find.byKey(kCompanyDriverSchedulePageKey), findsOneWidget);
    expect(find.textContaining('Karel Peeters'), findsWidgets);
    expect(find.byKey(kCompanyDriverScheduleSaveUnavailableKey), findsOneWidget);
  });
}
