import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/navigation/traffic/navigation_route_warning_controller.dart';
import 'package:fluxidi_tracking/navigation/traffic/navigation_route_warnings.dart';
import 'package:fluxidi_tracking/navigation/traffic/navigation_route_warning_host.dart';
import 'package:fluxidi_tracking/navigation/traffic/navigation_route_warning_banner.dart';
import 'package:fluxidi_tracking/navigation/traffic/navigation_traffic_controller.dart';
import 'package:fluxidi_tracking/navigation/traffic/navigation_traffic_model.dart';
import 'package:fluxidi_tracking/navigation/traffic/navigation_traffic_route_adapter.dart';
import 'package:fluxidi_tracking/navigation/driver_navigation_models.dart';
import 'package:fluxidi_tracking/navigation/driver_navigation_route_parser.dart';
import 'package:fluxidi_tracking/navigation/nav_backend/driver_route_apply.dart';

void main() {
  final cases =
      (jsonDecode(
                File(
                  'test/navigation/traffic/device_handoff/device-fixtures.json',
                ).readAsStringSync(),
              )['results']
              as List)
          .where((r) => r['action'] == 'warnings');
  for (final record in cases) {
    final dto = Map<String, dynamic>.from(record['warnings']);
    final geometry = <List<num>>[
      for (final p in record['rawRoute']['geometry'])
        [p['longitude'] as num, p['latitude'] as num],
    ];
    final now = DateTime.fromMillisecondsSinceEpoch(
      dto['generatedAt'],
      isUtc: true,
    );
    final expiry = DateTime.fromMillisecondsSinceEpoch(
      dto['validUntil'],
      isUtc: true,
    );
    final name = '${dto['warnings'][0]['kind']}:${dto['routeEvidenceId']}';
    NavigationRouteWarningBinding binding({
      DateTime? routeUntil,
      DateTime? grantUntil,
      dynamic attachment,
    }) => NavigationRouteWarningBinding(
      tenantId: dto['tenant_id'],
      companyId: dto['company_id'],
      driverId: 'fixture-driver',
      graphVersion: dto['graphVersion'],
      manifestSha256: dto['manifestSha256'],
      evidenceRevision: dto['evidenceRevision'],
      routeEvidenceId: dto['routeEvidenceId'],
      routeValidUntil: routeUntil ?? expiry,
      attachment:
          attachment ??
          {
            'grant': {
              'schema': 'fluxidi-navigation-traffic-test-grant-v1',
              'enabled': true,
              'tenant_id': dto['tenant_id'],
              'company_id': dto['company_id'],
              'validUntil': (grantUntil ?? expiry).millisecondsSinceEpoch,
            },
            'warnings': dto,
          },
    );
    void install(
      NavigationRouteWarningController c, {
      NavigationRouteWarningBinding? evidence,
      String? company,
      String? tenant,
      String? driver,
      List<List<num>>? points,
    }) => c.install(
      binding: evidence,
      tenantId: tenant ?? dto['tenant_id'],
      companyId: company ?? dto['company_id'],
      driverId: driver ?? 'fixture-driver',
      displayedGeometry: points ?? geometry,
      now: now,
    );
    test(
      '$name passed warning cannot return on backward jitter or a GPS gap',
      () {
        final c = NavigationRouteWarningController(testBuildEnabled: true);
        addTearDown(c.dispose);
        install(c, evidence: binding());
        final warning = c.current(now).items.first;
        // Each route occurrence is separate, even when event IDs repeat.
        final passed = warning.end + 1;
        c.updateProgress(passed, trusted: true, now: now);
        c.updateProgress(warning.start, trusted: true, now: now);
        expect(c.progressMeters, passed);
        expect(
          c
              .current(now)
              .ahead(progressMeters: c.progressMeters, trusted: true, now: now),
          isNot(same(warning)),
        );
        c.updateProgress(0, trusted: false, now: now);
        c.updateProgress(warning.start, trusted: true, now: now);
        expect(c.progressMeters, passed);
        install(c, evidence: binding());
        expect(c.progressMeters, 0);
        c.updateProgress(warning.start, trusted: true, now: now);
        expect(
          c
              .current(now)
              .ahead(progressMeters: c.progressMeters, trusted: true, now: now)?.id,
          warning.id,
        );
        c.clear();
        expect(c.progressMeters, 0);
        expect(c.progressTrusted, isFalse);
      },
    );
    testWidgets('$name existing/new traffic channels share one banner slot', (
      tester,
    ) async {
      final c = NavigationRouteWarningController(testBuildEnabled: true);
      final old = ValueNotifier<NavigationTrafficAlert?>(null);
      install(c, evidence: binding());
      c.updateProgress(
        c.current(now).items.first.start,
        trusted: true,
        now: now,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NavigationRouteWarningHost(
              controller: c,
              existingAlertListenable: old,
              clock: () => now,
              child: ValueListenableBuilder<NavigationTrafficAlert?>(
                valueListenable: old,
                builder: (_, alert, _) => Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Guidance'),
                    if (alert != null) const Text('Existing traffic'),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      expect(find.byType(NavigationRouteWarningBanner), findsOneWidget);
      old.value = const NavigationTrafficAlert(
        event: NavigationTrafficEvent.incident,
        traffic: NavigationTrafficClass.normal,
        distanceMeters: 0,
      );
      await tester.pump();
      expect(find.byType(NavigationRouteWarningBanner), findsNothing);
      expect(find.text('Existing traffic'), findsOneWidget);
      expect(find.text('Guidance'), findsOneWidget);
      old.value = null;
      await tester.pump();
      expect(find.byType(NavigationRouteWarningBanner), findsOneWidget);
      c.clear();
      await tester.pump();
      expect(find.byType(NavigationRouteWarningBanner), findsNothing);
      old.value = const NavigationTrafficAlert(
        event: NavigationTrafficEvent.incident,
        traffic: NavigationTrafficClass.normal,
        distanceMeters: 0,
      );
      await tester.pump();
      expect(find.text('Existing traffic'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      c.dispose();
      old.dispose();
    });
    test('$name default-off and ordinary route have no warning', () {
      final c = NavigationRouteWarningController();
      addTearDown(c.dispose);
      install(c, evidence: binding());
      expect(c.current(now).items, isEmpty);
      expect(c.nextExpiry(now), isNull);
    });
    test(
      '$name route, actor, grant and exact displayed geometry bind together',
      () {
        final c = NavigationRouteWarningController(testBuildEnabled: true);
        addTearDown(c.dispose);
        install(c, evidence: binding());
        expect(c.current(now).state, RouteWarningState.available);
        for (final wrong in [
          'company',
          'tenant',
          'driver',
          'reversed',
          'trimmed',
        ]) {
          install(
            c,
            evidence: binding(),
            company: wrong == 'company' ? 'foreign' : null,
            tenant: wrong == 'tenant' ? 'foreign' : null,
            driver: wrong == 'driver' ? 'other' : null,
            points: wrong == 'reversed'
                ? geometry.reversed.toList()
                : wrong == 'trimmed'
                ? geometry.sublist(1)
                : null,
          );
          expect(c.current(now).items, isEmpty, reason: wrong);
        }
      },
    );
    test(
      '$name stationary expiry, progress trust, resume and logout stay closed',
      () {
        final c = NavigationRouteWarningController(testBuildEnabled: true);
        addTearDown(c.dispose);
        install(
          c,
          evidence: binding(grantUntil: now.add(const Duration(seconds: 1))),
        );
        expect(c.nextExpiry(now), now.add(const Duration(seconds: 1)));
        c.updateProgress(0, trusted: false, now: now);
        expect(c.progressTrusted, isFalse);
        c.updateProgress(0, trusted: true, now: now);
        expect(c.progressTrusted, isTrue);
        final later = now.add(const Duration(seconds: 1));
        c.refresh(later);
        expect(c.current(later).items, isEmpty);
        install(c, evidence: binding(routeUntil: later));
        expect(c.nextExpiry(now), later);
        expect(c.current(later).items, isEmpty);
        c.clear();
        c.refresh(now);
        expect(c.current(now).items, isEmpty);
      },
    );
    test(
      '$name replacement without proof clears previous route; package does not alter route',
      () {
        final c = NavigationRouteWarningController(testBuildEnabled: true);
        addTearDown(c.dispose);
        install(c, evidence: binding());
        expect(c.current(now).items, isNotEmpty);
        install(c);
        expect(c.current(now).items, isEmpty);
        final parsed = DriverRouteParseResult(
          coords: [
            for (final p in geometry)
              DriverLonLat(p[0].toDouble(), p[1].toDouble()),
          ],
          distanceMeters: 1234,
          durationSeconds: 321,
          navSteps: const [],
          stepsWithBannerCount: 0,
          stepsWithLaneGuidanceCount: 0,
        );
        final bound = bindNavigationTrafficParseResult(
          parsed: parsed,
          response: {},
          warningBinding: binding(),
        );
        final worker =
            prepareNavigationTrafficRoutePackage(
                  parsed: bound,
                  source: DriverRouteResponseSource.worker,
                )
                as NavigationTrafficPreparedRoute;
        expect(worker.coords, parsed.coords);
        expect(worker.distanceMeters, 1234);
        expect(worker.durationSeconds, 321);
        expect(worker.navSteps, parsed.navSteps);
        expect(worker.warningBinding, isNotNull);
        final legacy =
            prepareNavigationTrafficRoutePackage(
                  parsed: bound,
                  source: DriverRouteResponseSource.mapboxDirect,
                )
                as NavigationTrafficPreparedRoute;
        expect(legacy.warningBinding, isNull);
      },
    );
  }
}
