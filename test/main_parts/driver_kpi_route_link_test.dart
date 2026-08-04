// DRIVER-REPORTS-ROUTE-LINK
//
// Proves company Drivers → Rapporten and driver-home → Mijn prestaties
// converge on the same DriverKpiPage route, forward the selected driver_id,
// and preserve tenant/company scope. Also pins the company UI wiring so the
// placeholder snackbar cannot return silently.
//
// Run:
//   flutter test test/main_parts/driver_kpi_route_link_test.dart

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/main_parts/driver_kpi_model.dart';
import 'package:fluxidi_tracking/main_parts/driver_kpi_page.dart';

DriverKpiRideRecord _ride(String id) {
  return DriverKpiRideRecord(
    rideId: id,
    startedAt: DateTime(2026, 7, 18, 9),
    stoppedAt: DateTime(2026, 7, 18, 9, 20),
    amountEur: 12.0,
    kmTotal: 4,
    isCompleted: true,
    isCancelled: false,
    paymentState: DriverKpiPaymentState.paid,
  );
}

void main() {
  group('DRIVER-REPORTS-ROUTE-LINK route contract', () {
    test('company and driver-home args share driver_id + company scope', () {
      const driverId = 'driver_christophe_001';
      const tenantId = 'tenant_acme';
      const companyId = 'company_acme';

      final companyArgs = driverKpiRouteArgsForCompanyDriver(
        driverId: driverId,
        tenantId: tenantId,
        companyId: companyId,
      );
      final driverHomeArgs = driverKpiRouteArgsForDriverHome(
        driverId: driverId,
        companyAdminPreview: false,
        tenantId: tenantId,
        companyId: companyId,
      );
      final previewArgs = driverKpiRouteArgsForDriverHome(
        driverId: driverId,
        companyAdminPreview: true,
        tenantId: tenantId,
        companyId: companyId,
      );

      expect(companyArgs.driverKey, driverId);
      expect(driverHomeArgs.driverKey, driverId);
      expect(previewArgs.driverKey, driverId);

      expect(companyArgs.tenantId, tenantId);
      expect(companyArgs.companyId, companyId);
      expect(driverHomeArgs.tenantId, tenantId);
      expect(driverHomeArgs.companyId, companyId);
      expect(previewArgs.hasCompanyScope, isTrue);

      expect(companyArgs.authMode, DriverKpiAuthMode.companyAdmin);
      expect(driverHomeArgs.authMode, DriverKpiAuthMode.driver);
      expect(previewArgs.authMode, DriverKpiAuthMode.companyAdmin);
      expect(companyArgs.hasDriver, isTrue);
    });

    testWidgets(
      'both entry points push the same DriverKpiPage with forwarded driver_id',
      (tester) async {
        const driverId = 'driver_christophe_001';
        const tenantId = 'tenant_acme';
        const companyId = 'company_acme';
        DriverKpiRouteArgs? lastArgs;

        Future<void> openFrom(DriverKpiRouteArgs args) {
          lastArgs = args;
          return pushDriverKpiPage(
            tester.element(find.byType(Scaffold)),
            args: args,
            fetchRides: (_) async => [_ride('a')],
            logger: (_) {},
          );
        }

        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) {
                return Scaffold(
                  body: Column(
                    children: [
                      TextButton(
                        key: const Key('entry_company_drivers'),
                        onPressed: () {
                          openFrom(
                            driverKpiRouteArgsForCompanyDriver(
                              driverId: driverId,
                              tenantId: tenantId,
                              companyId: companyId,
                            ),
                          );
                        },
                        child: const Text('company_drivers'),
                      ),
                      TextButton(
                        key: const Key('entry_driver_home'),
                        onPressed: () {
                          openFrom(
                            driverKpiRouteArgsForDriverHome(
                              driverId: driverId,
                              companyAdminPreview: false,
                              tenantId: tenantId,
                              companyId: companyId,
                            ),
                          );
                        },
                        child: const Text('driver_home'),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        );

        await tester.tap(find.byKey(const Key('entry_company_drivers')));
        await tester.pumpAndSettle();
        expect(find.byType(DriverKpiPage), findsOneWidget);
        expect(lastArgs?.driverKey, driverId);
        expect(lastArgs?.tenantId, tenantId);
        expect(lastArgs?.companyId, companyId);
        expect(lastArgs?.authMode, DriverKpiAuthMode.companyAdmin);

        final companyRoute = ModalRoute.of(
          tester.element(find.byType(DriverKpiPage)),
        );
        expect(companyRoute?.settings.name, kDriverKpiRouteName);
        expect(companyRoute?.settings.arguments, same(lastArgs));

        // Back must leave the KPI page (return to chauffeur/company context).
        Navigator.of(tester.element(find.byType(DriverKpiPage))).pop();
        await tester.pumpAndSettle();
        expect(find.byType(DriverKpiPage), findsNothing);

        await tester.tap(find.byKey(const Key('entry_driver_home')));
        await tester.pumpAndSettle();
        expect(find.byType(DriverKpiPage), findsOneWidget);
        expect(lastArgs?.driverKey, driverId);
        expect(lastArgs?.tenantId, tenantId);
        expect(lastArgs?.companyId, companyId);
        expect(lastArgs?.authMode, DriverKpiAuthMode.driver);

        final driverRoute = ModalRoute.of(
          tester.element(find.byType(DriverKpiPage)),
        );
        expect(driverRoute?.settings.name, kDriverKpiRouteName);
        expect(driverRoute?.settings.arguments, isA<DriverKpiRouteArgs>());
        final routed = driverRoute!.settings.arguments! as DriverKpiRouteArgs;
        expect(routed.driverKey, driverId);
        expect(routed.companyId, companyId);
      },
    );

    testWidgets('another chauffeur opens the same page with its own driver_id', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              return Scaffold(
                body: TextButton(
                  key: const Key('open_other'),
                  onPressed: () {
                    pushDriverKpiPage(
                      context,
                      args: driverKpiRouteArgsForCompanyDriver(
                        driverId: 'driver_other_002',
                        tenantId: 'tenant_acme',
                        companyId: 'company_acme',
                      ),
                      fetchRides: (_) async => [_ride('b')],
                      logger: (_) {},
                    );
                  },
                  child: const Text('open'),
                ),
              );
            },
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('open_other')));
      await tester.pumpAndSettle();
      final page = tester.widget<DriverKpiPage>(find.byType(DriverKpiPage));
      expect(page.driverKey, 'driver_other_002');
      expect(page.authMode, DriverKpiAuthMode.companyAdmin);
      final route = ModalRoute.of(tester.element(find.byType(DriverKpiPage)));
      final args = route!.settings.arguments! as DriverKpiRouteArgs;
      expect(args.driverKey, 'driver_other_002');
      expect(args.tenantId, 'tenant_acme');
      expect(args.companyId, 'company_acme');
    });
  });

  group('DRIVER-REPORTS-ROUTE-LINK company UI wiring', () {
    test('placeholder snackbar is removed and shared KPI open is wired', () {
      final companySource = File(
        'lib/main_parts/company_driver_management_page_body.dart',
      ).readAsStringSync();
      final driverHomeSource = File(
        'lib/main_parts/driver_home_page_state.dart',
      ).readAsStringSync();
      final fetchSource = File(
        'lib/main_parts/driver_kpi_fetch.dart',
      ).readAsStringSync();

      expect(
        companySource.contains('Chauffeurprestaties komen binnenkort.'),
        isFalse,
      );
      expect(
        companySource.contains('Driver performance is coming soon.'),
        isFalse,
      );
      expect(companySource.contains('_openCompanyDriverKpiPage'), isTrue);
      expect(companySource.contains('pushDriverKpiPage'), isTrue);
      expect(
        companySource.contains('driverKpiRouteArgsForCompanyDriver'),
        isTrue,
      );
      expect(
        companySource.contains('fetchDriverKpiRidesFromTripsHistory'),
        isTrue,
      );
      expect(
        companySource.contains('_openPortraitDriverReportsPicker'),
        isTrue,
      );

      expect(driverHomeSource.contains('pushDriverKpiPage'), isTrue);
      expect(
        driverHomeSource.contains('driverKpiRouteArgsForDriverHome'),
        isTrue,
      );
      expect(
        driverHomeSource.contains('fetchDriverKpiRidesFromTripsHistory'),
        isTrue,
      );

      expect(
        fetchSource.contains('fetchDriverKpiRidesFromTripsHistory'),
        isTrue,
      );
      expect(fetchSource.contains('kTripsHistoryPath'), isTrue);
      expect(fetchSource.contains('canonicalizeStreetHistory'), isTrue);
    });
  });
}
