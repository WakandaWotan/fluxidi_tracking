import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/navigation/nav_engine/nav_adaptive_cadence.dart';

void main() {
  group('NavAdaptiveCadenceController', () {
    test('starts at maxHz, currentTickMs matches Hz', () {
      final c = NavAdaptiveCadenceController();
      expect(c.currentHz, 10);
      expect(c.currentTickMs(), 100);
    });

    test('healthy ticks eventually step up, capped at maxHz', () {
      final c = NavAdaptiveCadenceController(
        startHz: 6,
        minHz: 6,
        maxHz: 10,
        stepUpHealthyTicks: 4,
      );
      expect(c.currentHz, 6);
      for (var i = 0; i < 4; i++) {
        c.observe(applyLatencyMs: 20, frameP95Ms: 20, freezesOver100: 0);
      }
      expect(c.currentHz, 7);
      for (var i = 0; i < 4; i++) {
        c.observe(applyLatencyMs: 20, frameP95Ms: 20, freezesOver100: 0);
      }
      expect(c.currentHz, 8);
      for (var i = 0; i < 200; i++) {
        c.observe(applyLatencyMs: 20, frameP95Ms: 20, freezesOver100: 0);
      }
      expect(c.currentHz, 10);
    });

    test(
      'high apply-latency p95 steps down one Hz and resets healthy streak',
      () {
        final c = NavAdaptiveCadenceController(startHz: 10);
        // Warm up a healthy streak.
        for (var i = 0; i < 3; i++) {
          c.observe(applyLatencyMs: 20, frameP95Ms: 20, freezesOver100: 0);
        }
        expect(c.healthyStreak, 3);
        // Field-observed pathological apply latency.
        c.observe(applyLatencyMs: 200, frameP95Ms: 20, freezesOver100: 0);
        expect(c.currentHz, 9);
        expect(c.healthyStreak, 0);
      },
    );

    test('high frame p95 steps down', () {
      final c = NavAdaptiveCadenceController(startHz: 10);
      c.observe(applyLatencyMs: 20, frameP95Ms: 120, freezesOver100: 0);
      expect(c.currentHz, 9);
    });

    test('>=2 freezes over 100 ms step down', () {
      final c = NavAdaptiveCadenceController(startHz: 10);
      c.observe(applyLatencyMs: 20, frameP95Ms: 20, freezesOver100: 2);
      expect(c.currentHz, 9);
    });

    test('bounded at minHz on repeated unhealthy ticks', () {
      final c = NavAdaptiveCadenceController(startHz: 10);
      for (var i = 0; i < 20; i++) {
        c.observe(applyLatencyMs: 500, frameP95Ms: 500, freezesOver100: 5);
      }
      expect(c.currentHz, 6);
      expect(c.currentTickMs(), closeTo(166.66, 1));
    });

    test('reset returns to maxHz and clears window', () {
      final c = NavAdaptiveCadenceController(startHz: 10);
      for (var i = 0; i < 5; i++) {
        c.observe(applyLatencyMs: 500, frameP95Ms: 500, freezesOver100: 5);
      }
      expect(c.currentHz, 6);
      c.reset();
      expect(c.currentHz, 10);
      expect(c.healthyStreak, 0);
      expect(c.applyLatencyP95Ms(), 0.0);
    });

    test('non-finite / negative apply latency is ignored', () {
      final c = NavAdaptiveCadenceController(startHz: 10);
      c.observe(applyLatencyMs: double.nan, frameP95Ms: 20, freezesOver100: 0);
      c.observe(applyLatencyMs: -1, frameP95Ms: 20, freezesOver100: 0);
      expect(c.applyLatencyP95Ms(), 0.0);
      // Two healthy ticks landed regardless.
      expect(c.healthyStreak, 2);
    });
  });
}
