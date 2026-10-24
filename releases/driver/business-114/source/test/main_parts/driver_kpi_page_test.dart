import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_config.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/main_parts/driver_kpi_model.dart';
import 'package:fluxidi_tracking/main_parts/driver_kpi_page.dart';

DriverKpiRideRecord _ride(String id, {double amount = 10.0}) {
  return DriverKpiRideRecord(
    rideId: id,
    startedAt: DateTime(2026, 7, 18, 9),
    stoppedAt: DateTime(2026, 7, 18, 9, 20),
    amountEur: amount,
    kmTotal: 4,
    isCompleted: true,
    isCancelled: false,
    paymentState: DriverKpiPaymentState.paid,
  );
}

/// Fetcher that hands out a fresh [Completer] per call so tests can control the
/// exact ordering of async responses (for the generation guard).
class _ManualFetcher {
  final List<DriverKpiPeriod> calls = <DriverKpiPeriod>[];
  final List<Completer<List<DriverKpiRideRecord>>> completers =
      <Completer<List<DriverKpiRideRecord>>>[];

  Future<List<DriverKpiRideRecord>> call(DriverKpiPeriod period) {
    calls.add(period);
    final completer = Completer<List<DriverKpiRideRecord>>();
    completers.add(completer);
    return completer.future;
  }
}

void main() {
  final now = DateTime(2026, 7, 18, 15);
  DateTime clock() => now;

  group('FASE12 DriverKpiController', () {
    test('open() fetches and loads a snapshot', () async {
      final fetcher = _ManualFetcher();
      final controller = DriverKpiController(
        fetchRides: fetcher.call,
        authMode: DriverKpiAuthMode.driver,
        driverKey: 'driver-a',
        hasDriver: true,
        clock: clock,
        logger: (_) {},
      );
      final future = controller.open();
      expect(controller.state, DriverKpiViewState.loading);
      fetcher.completers.first.complete([_ride('a', amount: 12.0)]);
      await future;
      expect(controller.state, DriverKpiViewState.loaded);
      expect(controller.snapshot!.revenueTotal, 12.0);
    });

    test('driver switch clears the previous driver data immediately', () async {
      final fetcher = _ManualFetcher();
      final controller = DriverKpiController(
        fetchRides: fetcher.call,
        authMode: DriverKpiAuthMode.driver,
        driverKey: 'driver-a',
        hasDriver: true,
        clock: clock,
        logger: (_) {},
      );
      final openFuture = controller.open();
      fetcher.completers[0].complete([_ride('a', amount: 40.0)]);
      await openFuture;
      expect(controller.snapshot!.revenueTotal, 40.0);

      // Switch driver: data must be wiped synchronously (no lingering numbers).
      // ignore: unawaited_futures
      controller.setDriver(driverKey: 'driver-b', hasDriver: true);
      expect(controller.state, DriverKpiViewState.loading);
      expect(controller.snapshot, isNull);
    });

    test('late response from the previous driver is ignored', () async {
      final fetcher = _ManualFetcher();
      final logs = <String>[];
      final controller = DriverKpiController(
        fetchRides: fetcher.call,
        authMode: DriverKpiAuthMode.driver,
        driverKey: 'driver-a',
        hasDriver: true,
        clock: clock,
        logger: logs.add,
      );
      // ignore: unawaited_futures
      controller.open(); // call 0 → driver-a
      // ignore: unawaited_futures
      controller.setDriver(driverKey: 'driver-b', hasDriver: true); // call 1

      // Complete driver-b first with its data.
      fetcher.completers[1].complete([_ride('b', amount: 5.0)]);
      await Future<void>.delayed(Duration.zero);
      expect(controller.snapshot!.revenueTotal, 5.0);

      // Now the stale driver-a response arrives late — must be ignored.
      fetcher.completers[0].complete([_ride('a', amount: 999.0)]);
      await Future<void>.delayed(Duration.zero);
      expect(controller.snapshot!.revenueTotal, 5.0);
      expect(logs.any((l) => l.contains('phase=stale_ignored')), isTrue);
    });

    test('cache is per driver + period and shown instantly on return',
        () async {
      final fetcher = _ManualFetcher();
      final controller = DriverKpiController(
        fetchRides: fetcher.call,
        authMode: DriverKpiAuthMode.driver,
        driverKey: 'driver-a',
        hasDriver: true,
        clock: clock,
        logger: (_) {},
      );
      final openFuture = controller.open(); // today
      fetcher.completers[0].complete([_ride('t', amount: 11.0)]);
      await openFuture;

      final weekFuture = controller.setPeriod(DriverKpiPeriod.week);
      fetcher.completers[1].complete([_ride('w', amount: 22.0)]);
      await weekFuture;
      expect(controller.snapshot!.revenueTotal, 22.0);

      // Returning to today shows the cached snapshot synchronously, then
      // refreshes (a new fetch is issued).
      final callsBefore = fetcher.calls.length;
      // ignore: unawaited_futures
      controller.setPeriod(DriverKpiPeriod.today);
      expect(controller.state, DriverKpiViewState.loaded);
      expect(controller.snapshot!.revenueTotal, 11.0);
      expect(fetcher.calls.length, callsBefore + 1);
    });

    test('open() always refreshes even when cache exists', () async {
      final fetcher = _ManualFetcher();
      final controller = DriverKpiController(
        fetchRides: fetcher.call,
        authMode: DriverKpiAuthMode.driver,
        driverKey: 'driver-a',
        hasDriver: true,
        clock: clock,
        logger: (_) {},
      );
      final f1 = controller.open();
      fetcher.completers[0].complete([_ride('a')]);
      await f1;
      final f2 = controller.open();
      fetcher.completers[1].complete([_ride('a')]);
      await f2;
      expect(fetcher.calls.length, 2);
    });

    test('empty result yields the empty state', () async {
      final fetcher = _ManualFetcher();
      final controller = DriverKpiController(
        fetchRides: fetcher.call,
        authMode: DriverKpiAuthMode.driver,
        driverKey: 'driver-a',
        hasDriver: true,
        clock: clock,
        logger: (_) {},
      );
      final future = controller.open();
      fetcher.completers[0].complete(const <DriverKpiRideRecord>[]);
      await future;
      expect(controller.state, DriverKpiViewState.empty);
    });

    test('fetch failure yields the error state', () async {
      Future<List<DriverKpiRideRecord>> failing(DriverKpiPeriod period) {
        return Future<List<DriverKpiRideRecord>>.error(Exception('net'));
      }

      final controller = DriverKpiController(
        fetchRides: failing,
        authMode: DriverKpiAuthMode.driver,
        driverKey: 'driver-a',
        hasDriver: true,
        clock: clock,
        logger: (_) {},
      );
      await controller.open();
      expect(controller.state, DriverKpiViewState.error);
    });

    test('no driver never fetches and shows a no-driver empty state', () async {
      final fetcher = _ManualFetcher();
      final controller = DriverKpiController(
        fetchRides: fetcher.call,
        authMode: DriverKpiAuthMode.companyAdmin,
        driverKey: '',
        hasDriver: false,
        clock: clock,
        logger: (_) {},
      );
      await controller.open();
      expect(controller.state, DriverKpiViewState.empty);
      expect(controller.errorReason, 'no_driver');
      expect(fetcher.calls, isEmpty);
    });

    test('emits bounded [DRIVER_KPI] diagnostics with auth mode + period',
        () async {
      final fetcher = _ManualFetcher();
      final logs = <String>[];
      final controller = DriverKpiController(
        fetchRides: fetcher.call,
        authMode: DriverKpiAuthMode.companyAdmin,
        driverKey: 'driver-a',
        hasDriver: true,
        clock: clock,
        logger: logs.add,
      );
      final future = controller.open();
      fetcher.completers[0].complete([_ride('a')]);
      await future;
      expect(
        logs.any(
          (l) =>
              l.contains('[DRIVER_KPI]') &&
              l.contains('authMode=companyAdmin') &&
              l.contains('period=today') &&
              l.contains('hasDriver=true'),
        ),
        isTrue,
      );
    });
  });

  group('FASE12 DriverKpiPage widget', () {
    Future<void> pumpPage(
      WidgetTester tester, {
      required DriverKpiAuthMode authMode,
      required List<DriverKpiRideRecord> rides,
      String driverKey = 'driver-a',
      bool hasDriver = true,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: DriverKpiPage(
            fetchRides: (_) async => rides,
            authMode: authMode,
            driverKey: driverKey,
            hasDriver: hasDriver,
            clock: clock,
            logger: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('renders in standalone driver mode with KPI values', (
      tester,
    ) async {
      appLanguageNotifier.value = AppLanguage.nl;
      await pumpPage(
        tester,
        authMode: DriverKpiAuthMode.driver,
        rides: [_ride('a', amount: 12.5)],
      );
      expect(find.text('Mijn prestaties'), findsOneWidget);
      expect(find.text('€ 12.50'), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders in business preview (company admin) mode', (
      tester,
    ) async {
      appLanguageNotifier.value = AppLanguage.nl;
      await pumpPage(
        tester,
        authMode: DriverKpiAuthMode.companyAdmin,
        rides: [_ride('a', amount: 30.0)],
      );
      expect(find.text('Mijn prestaties'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('shows the empty state when there are no rides', (
      tester,
    ) async {
      appLanguageNotifier.value = AppLanguage.nl;
      await pumpPage(
        tester,
        authMode: DriverKpiAuthMode.driver,
        rides: const <DriverKpiRideRecord>[],
      );
      expect(find.text('Nog geen ritten'), findsOneWidget);
    });

    testWidgets('shows an error + retry state on failure', (tester) async {
      appLanguageNotifier.value = AppLanguage.nl;
      await tester.pumpWidget(
        MaterialApp(
          home: DriverKpiPage(
            fetchRides: (_) async => throw Exception('net'),
            authMode: DriverKpiAuthMode.driver,
            driverKey: 'driver-a',
            hasDriver: true,
            clock: clock,
            logger: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Opnieuw'), findsOneWidget);
    });

    testWidgets('localizes the title in NL/EN/FR/ES', (tester) async {
      final expected = <AppLanguage, String>{
        AppLanguage.nl: 'Mijn prestaties',
        AppLanguage.en: 'My performance',
        AppLanguage.fr: 'Mes performances',
        AppLanguage.es: 'Mi rendimiento',
      };
      for (final entry in expected.entries) {
        appLanguageNotifier.value = entry.key;
        await pumpPage(
          tester,
          authMode: DriverKpiAuthMode.driver,
          rides: [_ride('a')],
        );
        expect(find.text(entry.value), findsOneWidget);
      }
    });

    testWidgets('lays out without overflow on phone and tablet, both orientations',
        (tester) async {
      appLanguageNotifier.value = AppLanguage.nl;
      final sizes = <Size>[
        const Size(360, 780), // phone portrait
        const Size(780, 360), // phone landscape
        const Size(834, 1112), // tablet portrait
        const Size(1112, 834), // tablet landscape
      ];
      addTearDown(tester.view.reset);
      for (final size in sizes) {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;
        await pumpPage(
          tester,
          authMode: DriverKpiAuthMode.driver,
          rides: [
            _ride('a', amount: 12.0),
            _ride('b', amount: 34.5),
          ],
        );
        expect(tester.takeException(), isNull);
      }
    });
  });
}
