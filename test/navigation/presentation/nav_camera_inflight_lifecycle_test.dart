// NAV-CAMERA-INFLIGHT-SELF-HEAL-1
// Pure lifecycle tests: every camera-run outcome must leave the flag cleared,
// a stale run can never clear a newer one, pending coalesces latest-wins,
// timeout self-heals, and style/dispose invalidation makes old completions
// harmless.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/navigation/presentation/nav_camera_inflight_lifecycle.dart';

typedef PhaseLog = List<_PhaseEvent>;

class _PhaseEvent {
  _PhaseEvent(this.phase, this.reason);
  final NavCameraInFlightPhase phase;
  final String? reason;
  @override
  String toString() => '${phase.label}(${reason ?? ""})';
}

void main() {
  group('NavCameraInFlightLifecycle state machine', () {
    test('1. valid completion clears matching generation', () {
      final l = NavCameraInFlightLifecycle();
      expect(l.inFlight, isFalse);
      final gen = l.begin(kind: NavCameraCommandKind.passiveFollow)!;
      expect(l.inFlight, isTrue);
      expect(gen, 1);
      expect(l.complete(gen), isTrue);
      expect(l.inFlight, isFalse);
    });

    test('2. stale completion cannot clear newer generation', () {
      final l = NavCameraInFlightLifecycle();
      final gen1 = l.begin()!;
      final gen2 = l.begin()!;
      expect(gen2, gen1 + 1);
      expect(l.tryClear(gen1), isFalse, reason: 'stale must not clear');
      expect(l.inFlight, isTrue, reason: 'newer run still owns');
      expect(l.tryClear(gen2), isTrue);
      expect(l.inFlight, isFalse);
    });

    test('3. timeout releases stuck owner', () {
      final l = NavCameraInFlightLifecycle();
      final gen = l.begin(
        kind: NavCameraCommandKind.passiveFollow,
        expectedDuration: const Duration(milliseconds: 220),
      )!;
      expect(l.markTimedOut(gen), isTrue);
      expect(l.inFlight, isFalse);
    });

    test('4. timeout replays newest pending command', () {
      final l = NavCameraInFlightLifecycle();
      final events = <NavCameraInFlightEvent>[];
      l.onEvent = (e, {String? reason}) => events.add(e);
      final gen = l.begin()!;
      l.setPending(NavCameraCommandKind.pendingReplay, 'target-a');
      l.setPending(NavCameraCommandKind.pendingReplay, 'target-b');
      expect(l.markTimedOut(gen), isTrue);
      final pending = l.takePending(reportReplay: true);
      expect(pending?.target, 'target-b');
      expect(events, contains(NavCameraInFlightEvent.commandTimedOut));
      expect(events, contains(NavCameraInFlightEvent.pendingReplaced));
      expect(events, contains(NavCameraInFlightEvent.pendingReplayed));
    });

    test('5. multiple pending commands coalesce to one latest target', () {
      final l = NavCameraInFlightLifecycle();
      l.setPending(NavCameraCommandKind.passiveFollow, 1);
      l.setPending(NavCameraCommandKind.passiveFollow, 2);
      l.setPending(NavCameraCommandKind.userViewZoom, 3);
      expect(l.hasPending, isTrue);
      expect(l.pendingTarget, 3);
      expect(l.pendingKind, NavCameraCommandKind.userViewZoom);
      final taken = l.takePending();
      expect(taken?.target, 3);
      expect(l.hasPending, isFalse);
      expect(l.takePending(), isNull);
    });

    test('6. exception releases matching owner', () {
      final l = NavCameraInFlightLifecycle();
      final gen = l.begin()!;
      expect(l.fail(gen, reason: 'async_throw'), isTrue);
      expect(l.inFlight, isFalse);
    });

    test('7. old exception cannot release newer owner', () {
      final l = NavCameraInFlightLifecycle();
      final oldGen = l.begin()!;
      final newGen = l.begin(kind: NavCameraCommandKind.userViewZoom)!;
      expect(l.fail(oldGen), isFalse);
      expect(l.inFlight, isTrue);
      expect(l.activeKind, NavCameraCommandKind.userViewZoom);
      expect(l.complete(newGen), isTrue);
      expect(l.inFlight, isFalse);
    });

    test('8. style invalidation makes old completion harmless', () {
      final l = NavCameraInFlightLifecycle();
      final gen = l.begin()!;
      l.invalidate(reason: 'style_change');
      expect(l.inFlight, isFalse);
      expect(l.tryClear(gen), isFalse);
      expect(l.inFlight, isFalse);
    });

    test('9. route/session invalidation clears obsolete pending target', () {
      final l = NavCameraInFlightLifecycle();
      l.begin();
      l.setPending(NavCameraCommandKind.passiveFollow, 'stale');
      l.invalidate(reason: 'navigation_stop');
      expect(l.hasPending, isFalse);
      expect(l.inFlight, isFalse);
    });

    test('10. disposal cancels timeout', () async {
      final l = NavCameraInFlightLifecycle();
      var timedOut = false;
      final gen = l.begin()!;
      l.armTimeout(
        generation: gen,
        timeout: const Duration(milliseconds: 80),
        onTimeout: (_) => timedOut = true,
      );
      l.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(timedOut, isFalse);
      expect(l.isDisposed, isTrue);
      expect(l.inFlight, isFalse);
    });

    test('11. command after disposal is rejected safely', () {
      final l = NavCameraInFlightLifecycle();
      l.dispose();
      expect(l.begin(), isNull);
      expect(l.inFlight, isFalse);
    });

    test('12. user command supersedes passive follow', () {
      final l = NavCameraInFlightLifecycle();
      final passive = l.begin(kind: NavCameraCommandKind.passiveFollow)!;
      final user = l.begin(kind: NavCameraCommandKind.userViewZoom)!;
      expect(l.activeKind, NavCameraCommandKind.userViewZoom);
      expect(l.tryClear(passive), isFalse);
      expect(l.inFlight, isTrue);
      expect(l.complete(user), isTrue);
      expect(l.inFlight, isFalse);
    });

    test('13. repeated rapid View +/- keeps only final desired zoom target',
        () {
      final l = NavCameraInFlightLifecycle();
      l.begin(kind: NavCameraCommandKind.userViewZoom);
      l.setPending(NavCameraCommandKind.userViewZoom, 8);
      l.setPending(NavCameraCommandKind.userViewZoom, 9);
      l.setPending(NavCameraCommandKind.userViewZoom, 11);
      expect(l.pendingTarget, 11);
    });

    test('14. completion after timeout is ignored', () {
      final l = NavCameraInFlightLifecycle();
      final gen = l.begin()!;
      expect(l.markTimedOut(gen), isTrue);
      expect(l.complete(gen), isFalse);
      expect(l.inFlight, isFalse);
    });

    test('15. two successive timeouts do not deadlock', () {
      final l = NavCameraInFlightLifecycle();
      final g1 = l.begin()!;
      expect(l.markTimedOut(g1), isTrue);
      final g2 = l.begin()!;
      expect(l.markTimedOut(g2), isTrue);
      expect(l.inFlight, isFalse);
      expect(l.begin(), isNotNull);
      expect(l.inFlight, isTrue);
    });

    test('16. no permanent in-flight state after any terminal path', () async {
      final l = NavCameraInFlightLifecycle();
      // success
      final g1 = l.begin()!;
      l.complete(g1);
      expect(l.inFlight, isFalse);
      // fail
      final g2 = l.begin()!;
      l.fail(g2);
      expect(l.inFlight, isFalse);
      // timeout
      final g3 = l.begin()!;
      l.markTimedOut(g3);
      expect(l.inFlight, isFalse);
      // invalidate
      l.begin();
      l.invalidate();
      expect(l.inFlight, isFalse);
      // dispose
      l.begin();
      l.dispose();
      expect(l.inFlight, isFalse);
    });

    test('reset clears AND bumps generation so stale tryClear is a no-op', () {
      final l = NavCameraInFlightLifecycle();
      final gen = l.begin()!;
      l.reset();
      expect(l.inFlight, isFalse);
      expect(l.tryClear(gen), isFalse,
          reason: 'reset must invalidate old generation');
    });

    test('armed timeout self-heals matching generation only', () async {
      final l = NavCameraInFlightLifecycle();
      final timedOutGens = <int>[];
      final gen = l.begin()!;
      l.armTimeout(
        generation: gen,
        timeout: const Duration(milliseconds: 40),
        onTimeout: timedOutGens.add,
      );
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(timedOutGens, <int>[gen]);
      expect(l.inFlight, isFalse);
    });

    test('armed timeout ignored after supersede', () async {
      final l = NavCameraInFlightLifecycle();
      final timedOutGens = <int>[];
      final oldGen = l.begin()!;
      l.armTimeout(
        generation: oldGen,
        timeout: const Duration(milliseconds: 40),
        onTimeout: timedOutGens.add,
      );
      final newGen = l.begin(kind: NavCameraCommandKind.userRecenter)!;
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(timedOutGens, isEmpty);
      expect(l.inFlight, isTrue);
      expect(l.currentGeneration, newGen);
      l.complete(newGen);
    });
  });

  group('computeNavCameraInFlightTimeout', () {
    test('animMs=220 -> max(440, 620) = 620 ms', () {
      expect(computeNavCameraInFlightTimeout(220),
          const Duration(milliseconds: 620));
    });

    test('animMs=1000 -> max(2000, 1400) = 2000 ms', () {
      expect(computeNavCameraInFlightTimeout(1000),
          const Duration(milliseconds: 2000));
    });

    test('non-positive falls back to 220 ms baseline', () {
      expect(computeNavCameraInFlightTimeout(0),
          const Duration(milliseconds: 620));
      expect(computeNavCameraInFlightTimeout(-100),
          const Duration(milliseconds: 620));
    });

    test('hard ceiling prevents multi-second hangs', () {
      expect(computeNavCameraInFlightTimeout(10000).inMilliseconds, 2500);
    });
  });

  group('navCameraCommandKindFromReason', () {
    test('maps user and passive reasons', () {
      expect(
        navCameraCommandKindFromReason('cockpit_adjust'),
        NavCameraCommandKind.userViewZoom,
      );
      expect(
        navCameraCommandKindFromReason('manual_recenter'),
        NavCameraCommandKind.userRecenter,
      );
      expect(
        navCameraCommandKindFromReason('normal_follow'),
        NavCameraCommandKind.passiveFollow,
      );
      expect(
        navCameraCommandKindFromReason('style_switch'),
        NavCameraCommandKind.styleRestore,
      );
    });
  });

  group('formatNavCameraInFlightDiagnostic (PII-free)', () {
    test('emits every required field in stable order', () {
      final line = formatNavCameraInFlightDiagnostic(
        phase: NavCameraInFlightPhase.timeout,
        generation: 7,
        animMs: 220,
        ageMs: 1200,
        hasPending: true,
        reason: 'flyTo_no_completion_1200ms',
        commandKind: 'passive_follow',
        event: 'command_timed_out',
      );
      expect(line, startsWith('[NAV_CAMERA_INFLIGHT] '));
      expect(line, contains('phase=timeout'));
      expect(line, contains('generation=7'));
      expect(line, contains('animMs=220'));
      expect(line, contains('ageMs=1200'));
      expect(line, contains('hasPending=true'));
      expect(line, contains('commandKind=passive_follow'));
      expect(line, contains('event=command_timed_out'));
      expect(line, contains('reason=flyTo_no_completion_1200ms'));
    });

    test('empty reason renders as "none"', () {
      final line = formatNavCameraInFlightDiagnostic(
        phase: NavCameraInFlightPhase.cleared,
        generation: 1,
      );
      expect(line, contains('reason=none'));
      expect(line, contains('hasPending=false'));
      expect(line, contains('commandKind=none'));
      expect(line, contains('event=none'));
    });
  });

  group('runNavCameraInFlightFlyTo — every outcome clears', () {
    late NavCameraInFlightLifecycle lifecycle;
    late PhaseLog log;

    setUp(() {
      lifecycle = NavCameraInFlightLifecycle();
      log = <_PhaseEvent>[];
    });

    void onPhase(NavCameraInFlightPhase p, {String? reason}) =>
        log.add(_PhaseEvent(p, reason));

    test('normal flyTo completion clears in-flight and reports complete',
        () async {
      final gen = lifecycle.begin()!;
      final outcome = await runNavCameraInFlightFlyTo(
        lifecycle: lifecycle,
        generation: gen,
        animMs: 220,
        flyToFactory: () async {},
        onPhase: onPhase,
      );
      expect(outcome, NavCameraInFlightOutcome.success);
      expect(lifecycle.inFlight, isFalse);
      expect(log.map((e) => e.phase).toList(), <NavCameraInFlightPhase>[
        NavCameraInFlightPhase.start,
        NavCameraInFlightPhase.complete,
        NavCameraInFlightPhase.cleared,
      ]);
    });

    test('synchronous throw inside flyToFactory clears in-flight', () async {
      final gen = lifecycle.begin()!;
      final outcome = await runNavCameraInFlightFlyTo(
        lifecycle: lifecycle,
        generation: gen,
        animMs: 220,
        flyToFactory: () => throw StateError('boom'),
        onPhase: onPhase,
      );
      expect(outcome, NavCameraInFlightOutcome.error);
      expect(lifecycle.inFlight, isFalse);
      final phases = log.map((e) => e.phase).toList();
      expect(phases, contains(NavCameraInFlightPhase.error));
      expect(phases.last, NavCameraInFlightPhase.cleared);
    });

    test('async flyTo exception clears in-flight', () async {
      final gen = lifecycle.begin()!;
      final outcome = await runNavCameraInFlightFlyTo(
        lifecycle: lifecycle,
        generation: gen,
        animMs: 220,
        flyToFactory: () async {
          await Future<void>.delayed(const Duration(milliseconds: 1));
          throw StateError('async boom');
        },
        onPhase: onPhase,
      );
      expect(outcome, NavCameraInFlightOutcome.error);
      expect(lifecycle.inFlight, isFalse);
      expect(
        log.map((e) => e.phase).toList(),
        containsAllInOrder(<NavCameraInFlightPhase>[
          NavCameraInFlightPhase.start,
          NavCameraInFlightPhase.error,
          NavCameraInFlightPhase.cleared,
        ]),
      );
    });

    test('never-completing flyTo times out and clears in-flight', () async {
      final gen = lifecycle.begin()!;
      final outcome = await runNavCameraInFlightFlyTo(
        lifecycle: lifecycle,
        generation: gen,
        animMs: 10,
        flyToFactory: () => Completer<void>().future,
        onPhase: onPhase,
      );
      expect(outcome, NavCameraInFlightOutcome.timeout);
      expect(lifecycle.inFlight, isFalse, reason: 'timeout must self-heal');
      final phases = log.map((e) => e.phase).toList();
      expect(phases, contains(NavCameraInFlightPhase.timeout));
      expect(phases.last, NavCameraInFlightPhase.cleared);
    }, timeout: const Timeout(Duration(seconds: 5)));

    test('stale-generation completion does NOT clear a newer run', () async {
      final oldGen = lifecycle.begin()!;
      final oldCompleter = Completer<void>();
      final oldFuture = runNavCameraInFlightFlyTo(
        lifecycle: lifecycle,
        generation: oldGen,
        animMs: 220,
        flyToFactory: () => oldCompleter.future,
        onPhase: onPhase,
      );
      final newGen = lifecycle.begin()!;
      await runNavCameraInFlightFlyTo(
        lifecycle: lifecycle,
        generation: newGen,
        animMs: 220,
        flyToFactory: () async {},
        onPhase: onPhase,
      );
      expect(lifecycle.inFlight, isFalse);
      expect(lifecycle.currentGeneration, newGen);
      oldCompleter.complete();
      final oldOutcome = await oldFuture;
      expect(oldOutcome, NavCameraInFlightOutcome.stale);
      expect(lifecycle.inFlight, isFalse,
          reason: 'newer run still owned = false, stale must not flip');
      expect(log.map((e) => e.phase).toList(),
          contains(NavCameraInFlightPhase.stale));
    });

    test('three rapid begins with slow first flyTo: only latest clears',
        () async {
      final blockers = <Completer<void>>[
        Completer(),
        Completer(),
        Completer(),
      ];
      final futures = <Future<NavCameraInFlightOutcome>>[];
      for (var i = 0; i < 3; i++) {
        final gen = lifecycle.begin()!;
        futures.add(runNavCameraInFlightFlyTo(
          lifecycle: lifecycle,
          generation: gen,
          animMs: 220,
          flyToFactory: () => blockers[i].future,
          onPhase: (_, {String? reason}) {},
        ));
      }
      blockers[2].complete();
      final r2 = await futures[2];
      expect(r2, NavCameraInFlightOutcome.success);
      expect(lifecycle.inFlight, isFalse);
      blockers[0].complete();
      blockers[1].complete();
      final r0 = await futures[0];
      final r1 = await futures[1];
      expect(r0, NavCameraInFlightOutcome.stale);
      expect(r1, NavCameraInFlightOutcome.stale);
      expect(lifecycle.inFlight, isFalse);
    });

    test('reset() before completion turns the outcome into stale', () async {
      final gen = lifecycle.begin()!;
      final completer = Completer<void>();
      final future = runNavCameraInFlightFlyTo(
        lifecycle: lifecycle,
        generation: gen,
        animMs: 220,
        flyToFactory: () => completer.future,
        onPhase: onPhase,
      );
      lifecycle.reset();
      expect(lifecycle.inFlight, isFalse);
      completer.complete();
      final outcome = await future;
      expect(outcome, NavCameraInFlightOutcome.stale);
      expect(lifecycle.inFlight, isFalse);
    });

    test('disposed lifecycle rejects runner safely', () async {
      lifecycle.dispose();
      final outcome = await runNavCameraInFlightFlyTo(
        lifecycle: lifecycle,
        generation: 1,
        animMs: 220,
        flyToFactory: () async {},
        onPhase: onPhase,
      );
      expect(outcome, NavCameraInFlightOutcome.disposed);
    });
  });
}
