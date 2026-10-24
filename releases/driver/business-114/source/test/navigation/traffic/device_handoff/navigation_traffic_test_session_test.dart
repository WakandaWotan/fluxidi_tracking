import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/navigation/traffic/navigation_traffic_test_session.dart';
import 'package:fluxidi_tracking/navigation/traffic/navigation_route_warnings.dart';
import 'package:fluxidi_tracking/navigation/traffic/navigation_route_warning_banner.dart';

void main() {
  final cloud =
      jsonDecode(File('test/navigation/traffic/device_handoff/device-fixtures.json').readAsStringSync()) as Map;
  final records = (cloud['results'] as List)
      .where((r) => r['action'] == 'warnings')
      .toList();
  for (final r in records) {
    final dto = Map<String, dynamic>.from(r['warnings']);
    final geometry = [
      for (final p in r['rawRoute']['geometry'])
        [p['longitude'] as num, p['latitude'] as num]
    ];
    final now =
        DateTime.fromMillisecondsSinceEpoch(dto['generatedAt'], isUtc: true);
    final expiry =
        DateTime.fromMillisecondsSinceEpoch(dto['validUntil'], isUtc: true);
    final kind = dto['warnings'][0]['kind'];
    Map<String, dynamic> attachment() => {
          'grant': {
            'schema': 'fluxidi-navigation-traffic-test-grant-v1',
            'enabled': true,
            'tenant_id': dto['tenant_id'],
            'company_id': dto['company_id'],
            'validUntil': dto['validUntil'],
          },
          'warnings': jsonDecode(jsonEncode(dto))
        };
    int apply(NavigationTrafficTestSession s,
            {String? company, List<List<num>>? points}) =>
        s.applyDisplayedRoute(
            tenantId: dto['tenant_id'],
            companyId: company ?? dto['company_id'],
            graphVersion: dto['graphVersion'],
            manifestSha256: dto['manifestSha256'],
            evidenceRevision: dto['evidenceRevision'],
            routeEvidenceId: dto['routeEvidenceId'],
            routeValidUntil: expiry,
            geometry: points ?? geometry);
    test('$kind: off by default, exact company and actual displayed route', () {
      final off = NavigationTrafficTestSession(), e = apply(off);
      off.receive(epoch: e, attachment: attachment(), now: now);
      expect(off.current(now).items, isEmpty);
      final on = NavigationTrafficTestSession(testBuildEnabled: true),
          e2 = apply(on);
      on.receive(epoch: e2, attachment: attachment(), now: now);
      expect(on.current(now).state, RouteWarningState.available);
      final e3 = apply(on, company: 'foreign');
      on.receive(epoch: e3, attachment: attachment(), now: now);
      expect(on.current(now).items, isEmpty);
      final e4 = apply(on, points: geometry.reversed.toList());
      on.receive(epoch: e4, attachment: attachment(), now: now);
      expect(on.current(now).items, isEmpty);
    });
    test(
        '$kind: reroute/same route reapply/logout invalidate in-flight updates',
        () {
      final s = NavigationTrafficTestSession(testBuildEnabled: true),
          old = apply(s),
          current = apply(s);
      s.receive(epoch: old, attachment: attachment(), now: now);
      expect(s.current(now).items, isEmpty);
      s.receive(epoch: current, attachment: attachment(), now: now);
      expect(s.current(now).items, isNotEmpty);
      s.receive(
          epoch: old,
          attachment: null,
          now: now); // Old failure cannot clear newer result.
      expect(s.current(now).items, isNotEmpty);
      s.clear();
      s.receive(epoch: current, attachment: attachment(), now: now);
      expect(s.current(now).items, isEmpty);
    });
    test('$kind: missed/malformed/stale/disabled update hides only warnings',
        () {
      final s = NavigationTrafficTestSession(testBuildEnabled: true),
          e = apply(s);
      for (final invalid in [
        null,
        {},
        'bad',
        {'grant': true, 'warnings': dto},
        {
          ...attachment(),
          'grant': {...attachment()['grant'], 'enabled': false}
        },
        {
          ...attachment(),
          'grant': {...attachment()['grant'], 'tenant_id': 'foreign'}
        },
        {
          ...attachment(),
          'grant': {
            ...attachment()['grant'],
            'validUntil': now.millisecondsSinceEpoch
          }
        },
      ]) {
        s.receive(epoch: e, attachment: attachment(), now: now);
        expect(s.current(now).items, isNotEmpty);
        s.receive(epoch: e, attachment: invalid, now: now);
        expect(s.current(now).items, isEmpty);
      }
      s.receive(epoch: e, attachment: attachment(), now: now);
      expect(s.current(expiry).items,
          isEmpty); // Foreground resume, without fetching.
      s.receive(epoch: e, attachment: attachment(), now: expiry);
      expect(s.current(expiry).items, isEmpty);
    });
    for (final size in [const Size(360, 800), const Size(1280, 800)]) {
      for (final dark in [false, true]) {
        for (final scale in [1.0, 2.0]) {
          testWidgets(
              '$kind: active overlay ${size.width} dark=$dark text=$scale, progress/reroute/expiry',
              (tester) async {
            tester.view.physicalSize = size;
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);
            final s = NavigationTrafficTestSession(testBuildEnabled: true),
                e = apply(s);
            final immutableRoute = jsonEncode(r['rawRoute']);
            s.receive(epoch: e, attachment: attachment(), now: now);
            Future<void> render(
                    {DateTime? clock,
                    double progress = 0,
                    bool trusted = true}) =>
                tester.pumpWidget(
                  MaterialApp(
                      theme: dark ? ThemeData.dark() : ThemeData.light(),
                      home: MediaQuery(
                        data: MediaQueryData(
                            size: size, textScaler: TextScaler.linear(scale)),
                        child: Scaffold(
                            body: Stack(children: [
                          const Center(
                              child: Text(
                                  'Bestaande navigatie · GPS actief · ETA ongewijzigd',
                                  key: Key('base-navigation'))),
                          Positioned(
                              top: 20,
                              left: 12,
                              right: 12,
                              child: NavigationRouteWarningBanner(
                                  snapshot: s.current(clock ?? now),
                                  progressMeters: progress,
                                  progressTrusted: trusted,
                                  now: clock ?? now)),
                        ])),
                      )),
                );
            await render();
            expect(find.byType(NavigationRouteWarningBanner), findsOneWidget);
            expect(find.byType(Icon), findsOneWidget);
            expect(tester.takeException(), isNull);
            expect(find.byKey(const Key('base-navigation')), findsOneWidget);
            await render(trusted: false);
            expect(find.byType(Icon), findsNothing);
            await render(progress: s.current(now).items.last.end + 1);
            expect(find.byType(Icon), findsNothing);
            await render(clock: expiry);
            expect(find.byType(Icon), findsNothing);
            expect(find.byKey(const Key('base-navigation')), findsOneWidget);
            apply(s);
            s.receive(epoch: e, attachment: attachment(), now: now);
            await render();
            expect(find.byType(Icon), findsNothing);
            expect(jsonEncode(r['rawRoute']), immutableRoute);
            expect(tester.takeException(), isNull);
          });
        }
      }
    }
  }
}
