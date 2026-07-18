import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/navigation/nav_engine/nav_fresh_start_gate.dart';

void main() {
  group('NAV-LATENCY fresh-start gate (Part B)', () {
    test('fresh fix animates follow', () {
      expect(
        NavFreshStartGate.resolve(ageMs: 0),
        NavFreshStartAction.animateFollow,
      );
      expect(
        NavFreshStartGate.resolve(ageMs: 5000),
        NavFreshStartAction.animateFollow,
      );
      expect(
        NavFreshStartGate.resolve(ageMs: NavFreshStartGate.freshFollowMaxAgeMs),
        NavFreshStartAction.animateFollow,
      );
    });

    test('field-log stale target (284916 ms) never animates follow', () {
      expect(
        NavFreshStartGate.resolve(ageMs: 284916),
        NavFreshStartAction.waitForFix,
      );
      expect(NavFreshStartGate.mayAnimateFollow(ageMs: 284916), isFalse);
    });

    test('bounded stale window is static placeholder only', () {
      expect(
        NavFreshStartGate.resolve(ageMs: 30000),
        NavFreshStartAction.staticPlaceholder,
      );
      expect(NavFreshStartGate.mayAnimateFollow(ageMs: 30000), isFalse);
      expect(
        NavFreshStartGate.resolve(
          ageMs: NavFreshStartGate.stalePlaceholderMaxAgeMs,
        ),
        NavFreshStartAction.staticPlaceholder,
      );
    });

    test('beyond placeholder window waits for a fix', () {
      expect(
        NavFreshStartGate.resolve(
          ageMs: NavFreshStartGate.stalePlaceholderMaxAgeMs + 1,
        ),
        NavFreshStartAction.waitForFix,
      );
    });

    test('null / negative age waits for a fix', () {
      expect(
        NavFreshStartGate.resolve(ageMs: null),
        NavFreshStartAction.waitForFix,
      );
      expect(
        NavFreshStartGate.resolve(ageMs: -1),
        NavFreshStartAction.waitForFix,
      );
    });

    test('just over the fresh threshold stops animating', () {
      expect(
        NavFreshStartGate.mayAnimateFollow(
          ageMs: NavFreshStartGate.freshFollowMaxAgeMs + 1,
        ),
        isFalse,
      );
    });
  });
}
