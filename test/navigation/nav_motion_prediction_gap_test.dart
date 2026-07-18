import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/navigation/nav_engine/nav_motion_prediction.dart';

final DateTime _t0 = DateTime.utc(2026, 1, 1, 12, 0, 0);

DriverNavMotionPrediction _engine() {
  final e = DriverNavMotionPrediction();
  e.noteEngineUpdate(
    timestamp: _t0,
    displayLatitude: 51.0,
    displayLongitude: 4.0,
    bearing: 90.0, // due east -> longitude increases when moving
    trustRouteSnap: true,
  );
  return e;
}

NavMotionPredictionInput _input({
  required int gapMs,
  double speedKmh = 40.0,
  bool weakGps = false,
  bool trustRouteSnap = true,
  bool trustBearing = true,
  bool offRoute = false,
}) {
  return NavMotionPredictionInput(
    timestamp: _t0.add(Duration(milliseconds: gapMs)),
    lastDisplayLatitude: 51.0,
    lastDisplayLongitude: 4.0,
    lastReliableLatitude: 51.0,
    lastReliableLongitude: 4.0,
    bearing: 90.0,
    speedKmh: speedKmh,
    routeBearing: 90.0,
    trustRouteSnap: trustRouteSnap,
    trustBearing: trustBearing,
    offRouteLikely: offRoute,
    gpsAccuracyM: 8.0,
    liveRideActive: true,
    gapSinceLastEngineMs: gapMs,
    weakGps: weakGps,
  );
}

void main() {
  group('NAV prediction gap policy (Part D)', () {
    test('1 s cadence: prediction active and advances forward', () {
      final out = _engine().update(_input(gapMs: 1000));
      expect(out.predictionActive, isTrue);
      expect(out.reason, 'gap_predict');
      expect(out.predictedLongitude, greaterThan(4.0));
    });

    test(
      '2 s cadence: prediction still active within the defensible window',
      () {
        final out = _engine().update(_input(gapMs: 2000));
        expect(out.predictionActive, isTrue);
        expect(out.reason, 'gap_predict');
      },
    );

    test(
      '5 s gap (normal): prediction stops with gap_exceeded, not stepping',
      () {
        final out = _engine().update(_input(gapMs: 5000));
        expect(out.predictionActive, isFalse);
        expect(out.reason, 'gap_exceeded');
        // Graceful freeze at the last display position (no abrupt jump).
        expect(out.predictedLongitude, 4.0);
      },
    );

    test('5 s gap (tunnel): extended window keeps predicting', () {
      final out = _engine().update(
        _input(gapMs: 5000, weakGps: true, trustRouteSnap: true),
      );
      expect(out.predictionActive, isTrue);
      expect(out.reason, 'tunnel_predict');
    });

    test('10 s gap: prediction stops (gap_exceeded)', () {
      final out = _engine().update(_input(gapMs: 10000));
      expect(out.reason, 'gap_exceeded');
      expect(out.predictionActive, isFalse);
    });

    test('20 s+ gap: prediction stops even in tunnel mode', () {
      final out = _engine().update(
        _input(gapMs: 22000, weakGps: true, trustRouteSnap: true),
      );
      expect(out.reason, 'gap_exceeded');
      expect(out.predictionActive, isFalse);
    });

    test('low-speed stationary: holds position, no fake movement', () {
      final out = _engine().update(_input(gapMs: 1500, speedKmh: 1.0));
      expect(out.predictionActive, isTrue);
      expect(out.reason, 'low_speed_hold');
      expect(out.predictedLatitude, 51.0);
      expect(out.predictedLongitude, 4.0);
    });

    test('normal urban movement: advances a bounded plausible distance', () {
      final out = _engine().update(_input(gapMs: 1000, speedKmh: 36.0));
      // 36 km/h ~ 10 m/s over 1 s ~ 10 m east; must be forward and bounded.
      expect(out.predictedLongitude, greaterThan(4.0));
      expect(out.predictedLatitude, closeTo(51.0, 1e-4));
    });

    test(
      'GPS recovery after gap: fresh engine update resets to fresh_engine',
      () {
        final e = _engine();
        final duringGap = e.update(_input(gapMs: 1500));
        expect(duringGap.predictionActive, isTrue);

        // Fresh GPS arrives -> engine anchor resets.
        e.noteEngineUpdate(
          timestamp: _t0.add(const Duration(milliseconds: 1500)),
          displayLatitude: 51.0002,
          displayLongitude: 4.0003,
          bearing: 90.0,
          trustRouteSnap: true,
        );
        final afterRecovery = e.update(
          NavMotionPredictionInput(
            timestamp: _t0.add(const Duration(milliseconds: 1600)),
            lastDisplayLatitude: 51.0002,
            lastDisplayLongitude: 4.0003,
            bearing: 90.0,
            speedKmh: 40.0,
            routeBearing: 90.0,
            trustRouteSnap: true,
            trustBearing: true,
            liveRideActive: true,
            gapSinceLastEngineMs: 100, // < min gap -> fresh
            gpsAccuracyM: 8.0,
          ),
        );
        expect(afterRecovery.reason, 'fresh_engine');
        expect(afterRecovery.predictionActive, isFalse);
      },
    );

    test('sub-minimum gap does not start prediction', () {
      final out = _engine().update(_input(gapMs: 200));
      expect(out.reason, 'fresh_engine');
      expect(out.predictionActive, isFalse);
    });

    test('off-route disables prediction', () {
      final out = _engine().update(_input(gapMs: 1000, offRoute: true));
      expect(out.reason, 'off_route');
      expect(out.predictionActive, isFalse);
    });

    test('no trust disables prediction', () {
      final out = _engine().update(
        _input(gapMs: 1000, trustRouteSnap: false, trustBearing: false),
      );
      expect(out.reason, 'low_trust');
      expect(out.predictionActive, isFalse);
    });
  });
}
