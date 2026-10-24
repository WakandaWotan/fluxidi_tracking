import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/navigation/nav_engine/nav_marker_lifecycle.dart';

void main() {
  final t0 = DateTime(2026, 1, 1, 12, 0, 0);

  group('NAV-R12-D NavMarkerLifecycle self-heal decisions', () {
    test('starts healthy: no self-heal, no in-flight update', () {
      final lc = NavMarkerLifecycle();
      expect(lc.degraded, isFalse);
      expect(lc.shouldAttemptSelfHeal(t0), isFalse);
      expect(lc.updateInFlight, isFalse);
      expect(lc.pendingUpdate, isFalse);
    });

    test('failure marks degraded and applies first backoff', () {
      final lc = NavMarkerLifecycle();
      lc.noteFailure('no_manager_found', t0);
      expect(lc.degraded, isTrue);
      expect(lc.lastFailureReason, 'no_manager_found');
      expect(lc.shouldAttemptSelfHeal(t0), isFalse);
      expect(lc.selfHealDelay(t0), const Duration(milliseconds: 250));
      final afterBackoff = t0.add(const Duration(milliseconds: 250));
      expect(lc.shouldAttemptSelfHeal(afterBackoff), isTrue);
      expect(lc.selfHealDelay(afterBackoff), Duration.zero);
    });

    test('repeated failures grow backoff and cap at the last entry', () {
      final lc = NavMarkerLifecycle();
      var now = t0;
      final observed = <Duration>[];
      for (var i = 0; i < 8; i++) {
        lc.noteSelfHealAttemptStarted(now);
        lc.noteSelfHealFailed('mapbox_unavailable', now);
        observed.add(lc.selfHealDelay(now));
        now = now.add(lc.selfHealDelay(now));
      }
      expect(observed.first, const Duration(milliseconds: 500));
      expect(observed.last, NavMarkerLifecycle.backoffSchedule.last);
      // Monotonically non-decreasing: no hot retry loop.
      for (var i = 1; i < observed.length; i++) {
        expect(observed[i] >= observed[i - 1], isTrue);
      }
      expect(lc.selfHealAttempts, 8);
    });

    test('self-heal success clears degraded state and attempt count', () {
      final lc = NavMarkerLifecycle();
      lc.noteFailure('update_marker', t0);
      lc.noteSelfHealAttemptStarted(t0);
      lc.noteSelfHealSucceeded(t0.add(const Duration(seconds: 1)));
      expect(lc.degraded, isFalse);
      expect(lc.selfHealAttempts, 0);
      expect(lc.nextSelfHealAt, isNull);
      expect(lc.lastFailureReason, 'none');
      // A new episode starts back at the shortest backoff.
      final t1 = t0.add(const Duration(seconds: 5));
      lc.noteFailure('update_marker', t1);
      expect(lc.selfHealDelay(t1), NavMarkerLifecycle.backoffSchedule.first);
    });

    test('successful marker apply also heals a degraded pipeline', () {
      final lc = NavMarkerLifecycle();
      lc.noteFailure('update_marker', t0);
      expect(lc.beginUpdate(t0), isTrue);
      lc.finishUpdate(
        applied: true,
        now: t0.add(const Duration(milliseconds: 50)),
      );
      expect(lc.degraded, isFalse);
      expect(lc.selfHealAttempts, 0);
      expect(lc.lastAppliedAt, t0.add(const Duration(milliseconds: 50)));
    });

    test('reset returns to a clean state when navigation stops', () {
      final lc = NavMarkerLifecycle();
      lc.noteFailure('create_marker', t0);
      lc.beginUpdate(t0);
      lc.beginUpdate(t0); // queues a pending update
      lc.reset();
      expect(lc.degraded, isFalse);
      expect(lc.updateInFlight, isFalse);
      expect(lc.pendingUpdate, isFalse);
      expect(lc.selfHealAttempts, 0);
      expect(lc.nextSelfHealAt, isNull);
      expect(lc.lastAppliedAt, isNull);
    });
  });

  group('NAV-R12-D NavMarkerLifecycle update coalescing (last-wins)', () {
    test('second fix during an in-flight update becomes pending', () {
      final lc = NavMarkerLifecycle();
      expect(lc.beginUpdate(t0), isTrue);
      expect(lc.updateInFlight, isTrue);
      expect(
        lc.beginUpdate(t0.add(const Duration(milliseconds: 100))),
        isFalse,
      );
      expect(lc.pendingUpdate, isTrue);
      // Finish signals one rerun for the newest fix, then goes idle.
      expect(
        lc.finishUpdate(
          applied: true,
          now: t0.add(const Duration(milliseconds: 200)),
        ),
        isTrue,
      );
      expect(lc.updateInFlight, isFalse);
      expect(lc.pendingUpdate, isFalse);
    });

    test('finish without pending fix requires no rerun', () {
      final lc = NavMarkerLifecycle();
      lc.beginUpdate(t0);
      expect(
        lc.finishUpdate(
          applied: true,
          now: t0.add(const Duration(milliseconds: 80)),
        ),
        isFalse,
      );
      expect(lc.updateInFlight, isFalse);
    });

    test('many fixes while in flight collapse into a single rerun', () {
      final lc = NavMarkerLifecycle();
      lc.beginUpdate(t0);
      for (var i = 0; i < 5; i++) {
        expect(lc.beginUpdate(t0), isFalse);
      }
      expect(lc.finishUpdate(applied: true, now: t0), isTrue);
      // Rerun consumed all queued fixes at once.
      lc.beginUpdate(t0);
      expect(lc.finishUpdate(applied: true, now: t0), isFalse);
    });

    test('failed update does not mark applied timestamp nor heal', () {
      final lc = NavMarkerLifecycle();
      lc.noteFailure('update_marker', t0);
      lc.beginUpdate(t0);
      lc.finishUpdate(
        applied: false,
        now: t0.add(const Duration(milliseconds: 40)),
      );
      expect(lc.degraded, isTrue);
      expect(lc.lastAppliedAt, isNull);
    });
  });
}
