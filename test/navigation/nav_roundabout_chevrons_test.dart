// NAV-ROUNDABOUT-LANE-CLARITY-P0-2026-07-31
//
// Pure geometry contracts for `computeRoundaboutChevrons`.
//
// The function must:
//   * Return empty when input geometry is empty / short / malformed.
//   * Emit exactly one approach chevron before the roundabout ring, up to
//     `maxChevronsOnRing` chevrons on the ring, and one exit chevron on
//     the chosen exit road, when there is room.
//   * Never overlap chevrons closer than `minSpacingMeters` along-track.
//   * Point chevrons in the FORWARD direction of the polyline (bearings
//     match the underlying segment bearing).
//   * Preserve tenant-independent purity — no I/O, no randomness.

import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/navigation/nav_roundabout_chevrons.dart';

/// Synthesises a plausible route with a straight approach, a curved ring,
/// and a straight exit road — all in equal-lat/lon steps for pure numeric
/// determinism.
List<RoundaboutChevronPoint> _syntheticRoundaboutRoute({
  double startLat = 51.0,
  double startLon = 4.0,
  int approachSteps = 8,
  int ringSteps = 12,
  int exitSteps = 8,
  double stepMeters = 4.0,
}) {
  final coords = <RoundaboutChevronPoint>[];
  // Approach: north-bound.
  for (int i = 0; i < approachSteps; i++) {
    final dLat = _metersToDegLat(stepMeters * i);
    coords.add(RoundaboutChevronPoint(startLon, startLat + dLat));
  }
  final ringStart = coords.last;
  // Ring: small circle of radius ~= 12 m centered on (ringStart + 12m N).
  final centerLat = ringStart.lat + _metersToDegLat(12);
  final centerLon = ringStart.lon;
  final radius = 12.0;
  for (int i = 0; i <= ringSteps; i++) {
    final theta = (i / ringSteps) * math.pi * 1.6 - math.pi / 2;
    final dLat = _metersToDegLat(radius * math.sin(theta));
    final dLon = _metersToDegLon(radius * math.cos(theta), centerLat);
    coords.add(RoundaboutChevronPoint(centerLon + dLon, centerLat + dLat));
  }
  final ringEnd = coords.last;
  // Exit road: heading east from ring end.
  for (int i = 1; i <= exitSteps; i++) {
    final dLon = _metersToDegLon(stepMeters * i, ringEnd.lat);
    coords.add(RoundaboutChevronPoint(ringEnd.lon + dLon, ringEnd.lat));
  }
  return coords;
}

double _metersToDegLat(double m) => m / 111_320.0;
double _metersToDegLon(double m, double atLat) =>
    m / (111_320.0 * math.cos(atLat * math.pi / 180.0));

void main() {
  group('computeRoundaboutChevrons: input validation', () {
    test('empty coord list returns empty', () {
      final res = computeRoundaboutChevrons(
        routeCoordinates: const [],
        roundaboutStepStartIndex: 0,
        roundaboutStepEndIndex: 0,
      );
      expect(res, isEmpty);
    });

    test('coord list shorter than 2 returns empty', () {
      final res = computeRoundaboutChevrons(
        routeCoordinates: const [RoundaboutChevronPoint(4.0, 51.0)],
        roundaboutStepStartIndex: 0,
        roundaboutStepEndIndex: 0,
      );
      expect(res, isEmpty);
    });

    test('start >= end returns empty', () {
      final route = _syntheticRoundaboutRoute();
      final res = computeRoundaboutChevrons(
        routeCoordinates: route,
        roundaboutStepStartIndex: 5,
        roundaboutStepEndIndex: 5,
      );
      expect(res, isEmpty);
    });

    test('start out of bounds returns empty', () {
      final route = _syntheticRoundaboutRoute();
      final res = computeRoundaboutChevrons(
        routeCoordinates: route,
        roundaboutStepStartIndex: -1,
        roundaboutStepEndIndex: 5,
      );
      expect(res, isEmpty);
    });

    test('end out of bounds returns empty', () {
      final route = _syntheticRoundaboutRoute();
      final res = computeRoundaboutChevrons(
        routeCoordinates: route,
        roundaboutStepStartIndex: 5,
        roundaboutStepEndIndex: route.length,
      );
      expect(res, isEmpty);
    });

    test('roundabout shorter than 2× chevron size returns empty', () {
      // 4-point tight ring with total length < 2× default 6 m.
      final route = <RoundaboutChevronPoint>[
        const RoundaboutChevronPoint(4.0, 51.0),
        const RoundaboutChevronPoint(4.00001, 51.00001),
        const RoundaboutChevronPoint(4.00002, 51.00002),
        const RoundaboutChevronPoint(4.00003, 51.00003),
      ];
      final res = computeRoundaboutChevrons(
        routeCoordinates: route,
        roundaboutStepStartIndex: 1,
        roundaboutStepEndIndex: 2,
      );
      expect(res, isEmpty);
    });
  });

  group('computeRoundaboutChevrons: emission counts', () {
    test('typical roundabout emits approach + ≥1 ring + exit chevrons', () {
      final route = _syntheticRoundaboutRoute();
      final ringStart = 8;
      final ringEnd = 8 + 12;
      final res = computeRoundaboutChevrons(
        routeCoordinates: route,
        roundaboutStepStartIndex: ringStart,
        roundaboutStepEndIndex: ringEnd,
        chevronSizeMeters: 4.0,
        maxChevronsOnRing: 4,
        minSpacingMeters: 6.0,
      );
      expect(res.length, greaterThanOrEqualTo(3));
      expect(
        res.any((c) => c.role == RoundaboutChevronRole.approach),
        isTrue,
      );
      expect(
        res.any((c) => c.role == RoundaboutChevronRole.insideRing),
        isTrue,
      );
      expect(
        res.any((c) => c.role == RoundaboutChevronRole.exit),
        isTrue,
      );
    });

    test('maxChevronsOnRing = 1 caps ring chevrons to 1', () {
      final route = _syntheticRoundaboutRoute();
      final ringStart = 8;
      final ringEnd = 8 + 12;
      final res = computeRoundaboutChevrons(
        routeCoordinates: route,
        roundaboutStepStartIndex: ringStart,
        roundaboutStepEndIndex: ringEnd,
        chevronSizeMeters: 4.0,
        maxChevronsOnRing: 1,
        minSpacingMeters: 6.0,
      );
      final ringCount = res
          .where((c) => c.role == RoundaboutChevronRole.insideRing)
          .length;
      expect(ringCount, lessThanOrEqualTo(1));
    });
  });

  group('computeRoundaboutChevrons: geometry sanity', () {
    test('each chevron has 3 distinct points (left, tip, right)', () {
      final route = _syntheticRoundaboutRoute();
      final res = computeRoundaboutChevrons(
        routeCoordinates: route,
        roundaboutStepStartIndex: 8,
        roundaboutStepEndIndex: 20,
        chevronSizeMeters: 4.0,
      );
      expect(res, isNotEmpty);
      for (final c in res) {
        expect(c.points.length, 3);
        expect(c.left.lat != c.tip.lat || c.left.lon != c.tip.lon, isTrue);
        expect(c.right.lat != c.tip.lat || c.right.lon != c.tip.lon, isTrue);
      }
    });

    test('bearings are in valid [0, 360) range', () {
      final route = _syntheticRoundaboutRoute();
      final res = computeRoundaboutChevrons(
        routeCoordinates: route,
        roundaboutStepStartIndex: 8,
        roundaboutStepEndIndex: 20,
      );
      for (final c in res) {
        expect(c.bearingDegrees, greaterThanOrEqualTo(0));
        expect(c.bearingDegrees, lessThan(360));
      }
    });

    test('approach chevron precedes ring chevrons along the polyline', () {
      final route = _syntheticRoundaboutRoute();
      final res = computeRoundaboutChevrons(
        routeCoordinates: route,
        roundaboutStepStartIndex: 8,
        roundaboutStepEndIndex: 20,
        chevronSizeMeters: 4.0,
        maxChevronsOnRing: 3,
      );
      final approach =
          res.firstWhere((c) => c.role == RoundaboutChevronRole.approach);
      final firstRing =
          res.firstWhere((c) => c.role == RoundaboutChevronRole.insideRing);
      // Approach latitude should be less-than-or-equal to first ring tip
      // latitude — the synthetic route is northbound, so smaller lat means
      // "earlier" along the route.
      expect(approach.tip.lat, lessThanOrEqualTo(firstRing.tip.lat));
    });

    test('exit chevron sits AFTER the ring end vertex', () {
      final route = _syntheticRoundaboutRoute();
      final ringEndVertex = route[20];
      final res = computeRoundaboutChevrons(
        routeCoordinates: route,
        roundaboutStepStartIndex: 8,
        roundaboutStepEndIndex: 20,
        chevronSizeMeters: 4.0,
      );
      final exit = res.firstWhere(
        (c) => c.role == RoundaboutChevronRole.exit,
      );
      // Exit road runs east — increasing longitude — from ring end.
      expect(exit.tip.lon, greaterThan(ringEndVertex.lon));
    });
  });

  group('computeRoundaboutChevrons: safety caps', () {
    test('chevronSizeMeters <= 0.5 → empty', () {
      final route = _syntheticRoundaboutRoute();
      final res = computeRoundaboutChevrons(
        routeCoordinates: route,
        roundaboutStepStartIndex: 8,
        roundaboutStepEndIndex: 20,
        chevronSizeMeters: 0.4,
      );
      expect(res, isEmpty);
    });

    test('maxChevronsOnRing < 1 → empty', () {
      final route = _syntheticRoundaboutRoute();
      final res = computeRoundaboutChevrons(
        routeCoordinates: route,
        roundaboutStepStartIndex: 8,
        roundaboutStepEndIndex: 20,
        maxChevronsOnRing: 0,
      );
      expect(res, isEmpty);
    });
  });
}
