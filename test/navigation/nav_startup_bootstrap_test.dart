import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/navigation/nav_engine/nav_startup_bootstrap.dart';

NavStartupBootstrapSample _sample({
  int elapsedMs = 500,
  bool hasRoute = true,
  int fixAgeMs = 500,
  double accuracyM = 8.0,
  double speedKmh = 0.0,
  bool usableCourse = false,
  bool matched = false,
  bool routeEntry = false,
  bool coherent = true,
}) {
  return NavStartupBootstrapSample(
    elapsedSinceStartMs: elapsedMs,
    hasActiveSessionRoute: hasRoute,
    gpsFixAgeMs: fixAgeMs,
    gpsAccuracyM: accuracyM,
    speedKmh: speedKmh,
    hasUsableCourse: usableCourse,
    mapMatched: matched,
    routeEntryProgressing: routeEntry,
    coherentWithPreviousSample: coherent,
  );
}

void main() {
  group('NavStartupBootstrapGate', () {
    test('1. normal road start becomes ready immediately when evidence is good',
        () {
      final gate = NavStartupBootstrapGate();
      gate.start();
      // First coherent fresh sample counts as one, matched confirms on second.
      gate.evaluate(_sample(matched: true, coherent: false));
      final r = gate.evaluate(_sample(matched: true, coherent: true));
      expect(r.ready, isTrue);
      expect(r.phase, NavStartupBootstrapPhase.readinessConfirmed);
    });

    test('2. parking start (unmatched, stationary) is NOT ready yet', () {
      final gate = NavStartupBootstrapGate();
      gate.start();
      final r = gate.evaluate(
        _sample(matched: false, routeEntry: false, speedKmh: 0.0),
      );
      expect(r.ready, isFalse);
      expect(gate.ready, isFalse);
    });

    test('stale/inaccurate fix keeps waiting_for_fresh_location', () {
      final gate = NavStartupBootstrapGate();
      gate.start();
      final stale = gate.evaluate(_sample(fixAgeMs: 9000));
      expect(stale.phase, NavStartupBootstrapPhase.waitingForFreshLocation);
      final inaccurate = gate.evaluate(_sample(accuracyM: 120.0));
      expect(inaccurate.phase, NavStartupBootstrapPhase.waitingForFreshLocation);
      expect(gate.ready, isFalse);
    });

    test('6. moving with reliable course takes ownership (readiness)', () {
      final gate = NavStartupBootstrapGate();
      gate.start();
      gate.evaluate(_sample(coherent: false, speedKmh: 12, usableCourse: true));
      final r = gate.evaluate(
        _sample(coherent: true, speedKmh: 12, usableCourse: true, matched: false),
      );
      expect(r.ready, isTrue);
      expect(r.phase, NavStartupBootstrapPhase.readinessConfirmed);
    });

    test('single lucky fix cannot confirm (needs coherent samples)', () {
      final gate = NavStartupBootstrapGate();
      gate.start();
      final r = gate.evaluate(
        _sample(coherent: false, matched: true, hasRoute: true),
      );
      // Only one coherent sample so far -> not ready.
      expect(r.ready, isFalse);
    });

    test('safe upper bound forces timeout_fallback readiness', () {
      final gate = NavStartupBootstrapGate();
      gate.start();
      final r = gate.evaluate(_sample(elapsedMs: 20000, matched: false));
      expect(r.ready, isTrue);
      expect(r.phase, NavStartupBootstrapPhase.timeoutFallback);
    });

    test('readiness is sticky for the session', () {
      final gate = NavStartupBootstrapGate();
      gate.start();
      gate.evaluate(_sample(matched: true, coherent: false));
      gate.evaluate(_sample(matched: true, coherent: true));
      expect(gate.ready, isTrue);
      // A subsequent poor sample must not un-ready the session.
      final r = gate.evaluate(_sample(fixAgeMs: 9000, matched: false));
      expect(r.ready, isTrue);
    });

    test('reset returns to started/not-ready', () {
      final gate = NavStartupBootstrapGate();
      gate.start();
      gate.evaluate(_sample(matched: true, coherent: false));
      gate.evaluate(_sample(matched: true, coherent: true));
      gate.reset();
      expect(gate.ready, isFalse);
      expect(gate.phase, NavStartupBootstrapPhase.started);
    });

    test('diagnostic line is PII-free and bounded', () {
      final line = formatNavStartupBootstrapDiagnostic(
        phase: NavStartupBootstrapPhase.readinessConfirmed,
        ready: true,
        elapsedMs: 1234,
      );
      expect(line, contains('[NAV_STARTUP_BOOTSTRAP]'));
      expect(line, contains('phase=readiness_confirmed'));
      expect(line, contains('ready=true'));
    });
  });
}
