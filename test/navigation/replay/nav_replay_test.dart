// NAV-R12-F: replay assertions for the driver navigation engine.
//
// Run with: flutter test test/navigation/replay/nav_replay_test.dart
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluxidi_tracking/navigation/nav_engine/nav_bearing_smoother.dart';

import 'nav_replay_fixtures.dart';
import 'nav_replay_harness.dart';
import 'nav_replay_sample.dart';

NavReplayReport _run(NavReplayFixture fixture) {
  final harness = NavReplayHarness(routePoints: fixture.routePoints);
  final report = harness.run(
    fixtureName: fixture.name,
    samples: fixture.samples,
  );
  // Compact report for every fixture run (spec NAV-R12-F output section).
  // ignore: avoid_print
  print(report.compactReport());
  return report;
}

void main() {
  group('NAV-R12-F replay: A opposite-direction start', () {
    late NavReplayReport report;

    setUpAll(() {
      report = _run(NavReplayFixtures.oppositeDirectionStart());
    });

    test('route deviation + offRouteLikely fire within max 2 reliable '
        'moving samples', () {
      expect(report.firstOffRouteIndex, isNotNull);
      expect(
        report.firstOffRouteIndex!,
        lessThanOrEqualTo(1),
        reason:
            'opposite-direction start must confirm off-route on the first '
            'or second reliable moving fix',
      );
      expect(report.firstRouteDeviationIndex, isNotNull);
      expect(report.firstRouteDeviationIndex!, lessThanOrEqualTo(1));
      expect(report.firstOppositeDirectionIndex, isNotNull);
      expect(report.firstOppositeDirectionIndex!, lessThanOrEqualTo(1));
      final first = report.results[report.firstOffRouteIndex!];
      expect(
        first.offRouteReason,
        anyOf('opposite_direction_strong', 'opposite_direction'),
      );
    });

    test('route bearing loses priority after deviation detection', () {
      final first = report.firstOffRouteIndex!;
      for (final r in report.results.skip(first + 1)) {
        expect(
          r.bearingSource,
          isNot('route'),
          reason:
              'sample ${r.index}: route segment bearing must not drive '
              'the taxi nose while route deviation is active',
        );
      }
    });

    test('NAV-R12-C: bearing source switches to GPS/course within max '
        '1 sample', () {
      final firstGps = report.results.indexWhere(
        (r) => r.bearingSource == 'gps',
      );
      expect(firstGps, isNonNegative);
      expect(
        firstGps,
        lessThanOrEqualTo(1),
        reason: 'real course must take over immediately on deviation',
      );
    });

    test('NAV-R12-C: displayBearing converges to actual course (~180°) '
        'within 2 samples', () {
      final idx = report.firstBearingWithin(
        targetDeg: 180.0,
        toleranceDeg: 15.0,
      );
      expect(idx, isNotNull);
      expect(
        idx!,
        lessThanOrEqualTo(2),
        reason:
            'taxi nose must reflect the southbound course within ~2 seconds',
      );
    });

    test('NAV-R12-C: route bearing is never allowed while deviating', () {
      final first = report.firstRouteDeviationIndex!;
      for (final r in report.results.skip(first)) {
        expect(r.routeBearingAllowed, isFalse, reason: 'sample ${r.index}');
      }
    });

    test('route snap is released (trustSnap false) while deviating', () {
      final first = report.firstOffRouteIndex!;
      for (final r in report.results.skip(first)) {
        expect(r.trustSnap, isFalse, reason: 'sample ${r.index}');
      }
    });

    test('reroute becomes eligible and would trigger within ~1s', () {
      expect(report.firstRerouteEligibleIndex, isNotNull);
      expect(report.firstRerouteEligibleIndex!, lessThanOrEqualTo(1));
      expect(report.firstRerouteWouldTriggerIndex, isNotNull);
      final eligibleAt =
          report.results[report.firstRerouteEligibleIndex!].timestamp;
      final triggerAt =
          report.results[report.firstRerouteWouldTriggerIndex!].timestamp;
      expect(
        triggerAt.difference(eligibleAt).inMilliseconds,
        lessThanOrEqualTo(1000),
        reason: 'reroute must start within about 1 second of confirmation',
      );
    });
  });

  group('NAV-R12-F replay: B normal on-route driving', () {
    late NavReplayReport report;

    setUpAll(() {
      report = _run(NavReplayFixtures.normalOnRoute());
    });

    test('never triggers false off-route or route deviation', () {
      expect(report.firstOffRouteIndex, isNull);
      expect(report.firstRouteDeviationIndex, isNull);
      for (final r in report.results) {
        expect(r.backwardProgressLikely, isFalse, reason: 'sample ${r.index}');
      }
    });

    test('keeps reliable snap and shows the real maneuver banner', () {
      // Skip warmup sample 0; from then on the snap must hold.
      for (final r in report.results.skip(1)) {
        expect(r.trustSnap, isTrue, reason: 'sample ${r.index}');
        expect(
          r.showOriginalInstruction,
          isTrue,
          reason:
              'sample ${r.index}: on-route driving must show the real '
              'instruction, not a neutral fallback',
        );
      }
    });

    test('prediction never overrides fresh real movement', () {
      for (final r in report.results) {
        expect(r.predictionActive, isFalse, reason: 'sample ${r.index}');
      }
    });

    test('NAV-R12-C: route bearing may still win on-route', () {
      // Skip warmup sample 0; from then on route bearing stays eligible
      // and the nose stays on the northbound course despite heading jitter.
      for (final r in report.results.skip(1)) {
        expect(r.routeBearingAllowed, isTrue, reason: 'sample ${r.index}');
      }
      final routeDriven = report.results
          .skip(1)
          .where((r) => r.bearingSource == 'route');
      expect(
        routeDriven,
        isNotEmpty,
        reason: 'reliable on-route driving should use route segment bearing',
      );
      for (final r in report.results.skip(1)) {
        final deltaFromNorth = NavBearingSmoother.bearingDelta(
          r.displayBearing,
          0.0,
        ).abs();
        expect(
          deltaFromNorth,
          lessThanOrEqualTo(10.0),
          reason: 'sample ${r.index}: no jitter-induced nose wobble',
        );
      }
    });
  });

  group('NAV-R12-F replay: C U-turn/backtrack', () {
    late NavReplayReport report;

    setUpAll(() {
      report = _run(NavReplayFixtures.uTurnBacktrack());
    });

    test('bearing output never disappears (finite for every sample)', () {
      for (final r in report.results) {
        expect(r.displayBearing.isFinite, isTrue, reason: 'sample ${r.index}');
        expect(r.bearingSource, isNotEmpty, reason: 'sample ${r.index}');
      }
    });

    test('backtrack after the U-turn is detected as off-route', () {
      expect(report.firstOffRouteIndex, isNotNull);
      expect(report.maxHeadingDeltaDeg, greaterThanOrEqualTo(140.0));
    });

    test('banner never keeps the stale maneuver while off-route', () {
      for (final r in report.results.where((r) => r.offRouteLikely)) {
        expect(
          r.showOriginalInstruction,
          isFalse,
          reason:
              'sample ${r.index}: off-route must show neutral/checking '
              'banner instead of a stale maneuver',
        );
      }
    });

    test('NAV-R12-C: nose converges to the new southbound course within '
        '~2 samples of deviation detection', () {
      final first = report.firstRouteDeviationIndex;
      expect(first, isNotNull);
      final idx = report.firstBearingWithin(
        targetDeg: 180.0,
        toleranceDeg: 20.0,
        fromIndex: first!,
      );
      expect(idx, isNotNull);
      expect(
        idx! - first,
        lessThanOrEqualTo(2),
        reason: 'the old 150° flip guard must not block the U-turn correction',
      );
    });
  });

  group('NAV-R12-F replay: D side-street departure', () {
    late NavReplayReport report;

    setUpAll(() {
      report = _run(NavReplayFixtures.sideStreetDeparture());
    });

    test('departure is detected via snap distance, not opposite-direction', () {
      expect(report.firstOffRouteIndex, isNotNull);
      expect(
        report.firstOffRouteIndex!,
        lessThanOrEqualTo(18),
        reason:
            'side-street departure must confirm off-route well before '
            'the end of the trace',
      );
      expect(report.firstOppositeDirectionIndex, isNull);
      final first = report.results[report.firstOffRouteIndex!];
      expect(first.offRouteReason, 'snap_distance');
    });

    test('banner falls back to neutral once the route is unreliable', () {
      for (final r in report.results.where((r) => r.offRouteLikely)) {
        expect(r.showOriginalInstruction, isFalse, reason: 'sample ${r.index}');
      }
    });

    test('NAV-R12-C: GPS/course drives the nose once route is unreliable', () {
      final first = report.firstOffRouteIndex!;
      for (final r in report.results.skip(first)) {
        expect(r.bearingSource, 'gps', reason: 'sample ${r.index}');
        expect(r.routeBearingAllowed, isFalse, reason: 'sample ${r.index}');
      }
      final idx = report.firstBearingWithin(
        targetDeg: 90.0,
        toleranceDeg: 20.0,
        fromIndex: first,
      );
      expect(idx, isNotNull);
      expect(idx! - first, lessThanOrEqualTo(2));
    });
  });

  group('NAV-R12-F replay: prediction safety across fixtures', () {
    test('fresh fixes never activate prediction in any fixture', () {
      for (final fixture in NavReplayFixtures.all()) {
        final report = NavReplayHarness(
          routePoints: fixture.routePoints,
        ).run(fixtureName: fixture.name, samples: fixture.samples);
        for (final r in report.results) {
          expect(
            r.predictionActive,
            isFalse,
            reason: '${fixture.name} sample ${r.index}',
          );
        }
      }
    });
  });

  group('NAV-R12-F replay: diagnostics export import', () {
    test('parses gps_update events and dead-reckons positions', () {
      final export = jsonEncode(<String, dynamic>{
        'exportedAt': '2026-07-07T10:00:00Z',
        'sessionCount': 1,
        'sessions': <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'session_test',
            'events': <Map<String, dynamic>>[
              <String, dynamic>{
                'ts': '2026-07-07T10:00:00Z',
                'type': 'gps_update',
                'data': <String, dynamic>{
                  'dtMs': 1000,
                  'speedKmh': 30.0,
                  'accuracyM': 8.0,
                  'heading': 0.0,
                  'distanceFromLastM': 0.0,
                },
              },
              <String, dynamic>{
                'ts': '2026-07-07T10:00:01Z',
                'type': 'gps_update',
                'data': <String, dynamic>{
                  'dtMs': 1000,
                  'speedKmh': 30.0,
                  'accuracyM': 8.0,
                  'heading': 0.0,
                  'distanceFromLastM': 8.3,
                },
              },
              <String, dynamic>{
                'ts': '2026-07-07T10:00:02Z',
                'type': 'nav_engine',
                'data': <String, dynamic>{'tag': 'NAV_R4_PROGRESS'},
              },
              <String, dynamic>{
                'ts': '2026-07-07T10:00:02Z',
                'type': 'gps_update',
                'data': <String, dynamic>{
                  'dtMs': 1000,
                  'speedKmh': 32.0,
                  'accuracyM': 8.0,
                  'heading': 90.0,
                  'distanceFromLastM': 8.9,
                },
              },
            ],
          },
        ],
      });

      final samples = NavReplayDiagnosticsImport.samplesFromExportJson(export);
      expect(samples, hasLength(3));
      expect(samples[0].speedKmh, 30.0);
      expect(samples[1].latitude, greaterThan(samples[0].latitude));
      expect(samples[2].longitude, greaterThan(samples[1].longitude));
      expect(
        samples[2].timestamp.difference(samples[0].timestamp).inSeconds,
        2,
      );
    });
  });
}
