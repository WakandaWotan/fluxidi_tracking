// NAV-STYLE-MANAGER-CRASH-TELLERS-MARKER-1 / Commit 1
// NAV-ANNOTATION-MANAGER-TRANSACTIONAL-LIFECYCLE-2 / Commit

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/navigation/nav_engine/nav_annotation_manager_lifecycle.dart';

/// Phase 7 test adapter: records every native op so the race is deterministic.
class _FakeNativeManager {
  bool removed = false;
  int createCalls = 0;
  int deleteCalls = 0;
  final List<String> log = <String>[];

  /// A create controlled by an external Completer so tests can interleave a
  /// style-swap disposal precisely mid-flight.
  Future<void> create(Completer<void> gate) async {
    // If this ever runs after removal, that is the field crash.
    if (removed) {
      throw StateError('No manager found with id: 4');
    }
    createCalls += 1;
    log.add('create_start');
    await gate.future;
    if (removed) {
      throw StateError('No manager found with id: 4');
    }
    log.add('create_done');
  }

  Future<void> delete() async {
    if (removed) throw StateError('No manager found with id: 4');
    deleteCalls += 1;
    log.add('delete');
  }

  void remove() {
    removed = true;
    log.add('removed');
  }
}

void main() {
  group('NavAnnotationManagerGate', () {
    NavAnnotationManagerGate gate() =>
        NavAnnotationManagerGate(NavAnnotationManagerRole.route);

    test('queued delete after invalidation never reaches native', () {
      final g = gate();
      final token = g.activate(
        styleGeneration: 1,
        sessionGeneration: 1,
        renderEpoch: 1,
      );
      // Capture a deferred delete, then drain/dispose the manager.
      final deferred = g.capture();
      g.beginDrain();
      expect(g.markDisposed(), isTrue);

      final check = g.allow(deferred, NavAnnotationOperationKind.delete);
      expect(check.allowed, isFalse);
      expect(
        check.reason,
        anyOf(
          NavAnnotationRejectReason.disposed,
          NavAnnotationRejectReason.generationMismatch,
        ),
      );
      // Original activate token is also dead.
      expect(
        g.allow(token, NavAnnotationOperationKind.delete).allowed,
        isFalse,
      );
    });

    test('update after manager disposal never reaches native', () {
      final g = gate();
      final token = g.activate(
        styleGeneration: 2,
        sessionGeneration: 1,
        renderEpoch: 3,
      );
      g.beginDrain();
      g.markDisposed();
      expect(
        g.allow(token, NavAnnotationOperationKind.update).allowed,
        isFalse,
      );
      expect(
        g.allow(token, NavAnnotationOperationKind.create).allowed,
        isFalse,
      );
      expect(
        g.allow(token, NavAnnotationOperationKind.deleteAll).allowed,
        isFalse,
      );
    });

    test('repeated disposal is idempotent', () {
      final g = gate();
      g.activate(styleGeneration: 1, sessionGeneration: 1, renderEpoch: 1);
      g.beginDrain();
      expect(g.markDisposed(), isTrue);
      expect(g.markDisposed(), isFalse);
      expect(g.state, NavAnnotationManagerState.disposed);
      // Dispose op itself is rejected once disposed.
      expect(
        g.allow(g.currentOwnership(), NavAnnotationOperationKind.dispose)
            .allowed,
        isFalse,
      );
      expect(
        g.allow(g.currentOwnership(), NavAnnotationOperationKind.dispose)
            .reason,
        NavAnnotationRejectReason.disposed,
      );
    });

    test('style swap drains old manager before disposal', () {
      final g = gate();
      final old = g.activate(
        styleGeneration: 10,
        sessionGeneration: 1,
        renderEpoch: 5,
      );
      expect(g.beginOperation(old), isTrue);
      g.beginDrain();
      // New ops for the draining generation are rejected.
      expect(
        g.allow(old, NavAnnotationOperationKind.delete).allowed,
        isFalse,
      );
      expect(
        g.allow(old, NavAnnotationOperationKind.delete).reason,
        NavAnnotationRejectReason.draining,
      );
      // Dispose is still allowed while draining.
      expect(
        g.allow(old, NavAnnotationOperationKind.dispose).allowed,
        isTrue,
      );
      g.endOperation();
      expect(g.isQueueDrained(old), isTrue);
      expect(g.markDisposed(), isTrue);
    });

    test('stale style callback cannot use old manager', () {
      final g = gate();
      final styleN = g.activate(
        styleGeneration: 4,
        sessionGeneration: 1,
        renderEpoch: 1,
      );
      g.beginDrain();
      g.markDisposed();
      // Style N+1 activates a new generation.
      final styleN1 = g.activate(
        styleGeneration: 5,
        sessionGeneration: 1,
        renderEpoch: 1,
      );
      expect(
        g.allow(styleN, NavAnnotationOperationKind.restore).allowed,
        isFalse,
      );
      expect(
        g.allow(styleN, NavAnnotationOperationKind.restore).reason,
        NavAnnotationRejectReason.generationMismatch,
      );
      expect(
        g.allow(styleN1, NavAnnotationOperationKind.restore).allowed,
        isTrue,
      );
    });

    test('reroute during style swap cannot call the old manager', () {
      final g = gate();
      final old = g.activate(
        styleGeneration: 7,
        sessionGeneration: 2,
        renderEpoch: 9,
      );
      g.beginDrain();
      // A reroute captured against the old generation is rejected.
      expect(
        g.allow(old, NavAnnotationOperationKind.create).allowed,
        isFalse,
      );
      expect(
        g.allow(old, NavAnnotationOperationKind.update).allowed,
        isFalse,
      );
    });

    test('stop during style swap cannot call the old manager', () {
      final g = gate();
      final old = g.activate(
        styleGeneration: 8,
        sessionGeneration: 3,
        renderEpoch: 2,
      );
      g.beginDrain();
      // Stop-path deletes against the old manager are rejected before native.
      expect(
        g.allow(old, NavAnnotationOperationKind.delete).allowed,
        isFalse,
      );
      expect(
        g.allow(old, NavAnnotationOperationKind.deleteAll).allowed,
        isFalse,
      );
    });

    test('start-stop-start has only current manager generations', () {
      final g = gate();
      final a = g.activate(
        styleGeneration: 1,
        sessionGeneration: 1,
        renderEpoch: 1,
      );
      g.beginDrain();
      g.markDisposed();
      final b = g.activate(
        styleGeneration: 1,
        sessionGeneration: 2,
        renderEpoch: 1,
      );
      g.beginDrain();
      g.markDisposed();
      final c = g.activate(
        styleGeneration: 1,
        sessionGeneration: 3,
        renderEpoch: 1,
      );
      expect(a.managerGeneration, 1);
      expect(b.managerGeneration, 2);
      expect(c.managerGeneration, 3);
      expect(g.allow(a, NavAnnotationOperationKind.update).allowed, isFalse);
      expect(g.allow(b, NavAnnotationOperationKind.update).allowed, isFalse);
      expect(g.allow(c, NavAnnotationOperationKind.update).allowed, isTrue);
    });

    test('destination-marker operations use current manager only', () {
      final g = NavAnnotationManagerGate(NavAnnotationManagerRole.destination);
      final old = g.activate(
        styleGeneration: 1,
        sessionGeneration: 1,
        renderEpoch: 1,
      );
      g.beginDrain();
      g.markDisposed();
      final cur = g.activate(
        styleGeneration: 2,
        sessionGeneration: 1,
        renderEpoch: 2,
      );
      expect(g.allow(old, NavAnnotationOperationKind.create).allowed, isFalse);
      expect(g.allow(cur, NavAnnotationOperationKind.create).allowed, isTrue);
      expect(g.allow(cur, NavAnnotationOperationKind.delete).allowed, isTrue);
    });

    test('rapid repeated style swaps are latest-wins', () {
      final g = gate();
      final tokens = <NavAnnotationOwnership>[];
      for (var i = 1; i <= 5; i++) {
        if (g.state != NavAnnotationManagerState.disposed) {
          g.beginDrain();
          g.markDisposed();
        }
        tokens.add(
          g.activate(
            styleGeneration: i,
            sessionGeneration: 1,
            renderEpoch: i,
          ),
        );
      }
      for (var i = 0; i < tokens.length - 1; i++) {
        expect(
          g.allow(tokens[i], NavAnnotationOperationKind.restore).allowed,
          isFalse,
          reason: 'style $i must be stale',
        );
      }
      expect(
        g.allow(tokens.last, NavAnnotationOperationKind.restore).allowed,
        isTrue,
      );
    });

    test('ownership mismatches (style/session/epoch) reject before native', () {
      final g = gate();
      g.activate(styleGeneration: 3, sessionGeneration: 4, renderEpoch: 5);
      final badStyle = NavAnnotationOwnership(
        managerGeneration: g.managerGeneration,
        styleGeneration: 99,
        sessionGeneration: 4,
        renderEpoch: 5,
      );
      final badSession = NavAnnotationOwnership(
        managerGeneration: g.managerGeneration,
        styleGeneration: 3,
        sessionGeneration: 99,
        renderEpoch: 5,
      );
      final badEpoch = NavAnnotationOwnership(
        managerGeneration: g.managerGeneration,
        styleGeneration: 3,
        sessionGeneration: 4,
        renderEpoch: 99,
      );
      expect(
        g.allow(badStyle, NavAnnotationOperationKind.update).reason,
        NavAnnotationRejectReason.styleMismatch,
      );
      expect(
        g.allow(badSession, NavAnnotationOperationKind.update).reason,
        NavAnnotationRejectReason.sessionMismatch,
      );
      expect(
        g.allow(badEpoch, NavAnnotationOperationKind.update).reason,
        NavAnnotationRejectReason.epochMismatch,
      );
    });

    test('diag line is PII-free and includes role/generation/event', () {
      final g = gate();
      g.activate(styleGeneration: 2, sessionGeneration: 3, renderEpoch: 4);
      final line = g.formatDiag(
        event: 'stale_operation_rejected',
        operation: NavAnnotationOperationKind.delete,
        reason: NavAnnotationRejectReason.draining,
        routeVersion: 7,
      );
      expect(line, contains('role=route'));
      expect(line, contains('managerGeneration=1'));
      expect(line, contains('styleGeneration=2'));
      expect(line, contains('sessionGeneration=3'));
      expect(line, contains('renderEpoch=4'));
      expect(line, contains('event=stale_operation_rejected'));
      expect(line, contains('operation=delete'));
      expect(line, contains('reason=draining'));
      expect(line, contains('routeVersion=7'));
      expect(line.toLowerCase(), isNot(contains('lat')));
      expect(line.toLowerCase(), isNot(contains('lon')));
      expect(line.toLowerCase(), isNot(contains('address')));
    });
  });

  group('NavAnnotationManagerGate — transactional lease (Phase 2/3/8)', () {
    NavAnnotationManagerGate gate() =>
        NavAnnotationManagerGate(NavAnnotationManagerRole.route);

    test('exact crash ordering: create finishes before manager removal under '
        'lease', () async {
      final g = gate();
      final own = g.activate(
        styleGeneration: 1,
        sessionGeneration: 1,
        renderEpoch: 1,
      );
      final native = _FakeNativeManager();
      final createGate = Completer<void>();

      // Route create is queued/started while manager id 4 is active.
      final createFuture = g.runGuarded<void>(
        ownership: own,
        kind: NavAnnotationOperationKind.create,
        nativeOp: () => native.create(createGate),
      );
      await Future<void>.value(); // let create_start run
      expect(g.activeLeases, 1);
      expect(native.log, ['create_start']);

      // Cockpit style change → drain begins; disposal AWAITS the lease.
      g.beginDrain();
      var removed = false;
      final disposeFuture = () async {
        await g.awaitDrained();
        native.remove();
        removed = true;
        g.markDisposed();
      }();

      // Disposal must NOT have removed the manager yet (create still in flight).
      await Future<void>.value();
      expect(removed, isFalse);
      expect(native.removed, isFalse);

      // Complete the create; only then may removal proceed.
      createGate.complete();
      await createFuture;
      await disposeFuture;

      expect(native.log, ['create_start', 'create_done', 'removed']);
      expect(g.state, NavAnnotationManagerState.disposed);
    });

    test('queued create after draining never reaches native', () async {
      final g = gate();
      final own = g.activate(
        styleGeneration: 1,
        sessionGeneration: 1,
        renderEpoch: 1,
      );
      g.beginDrain();
      final native = _FakeNativeManager();
      final res = await g.runGuarded<void>(
        ownership: own,
        kind: NavAnnotationOperationKind.create,
        nativeOp: () => native.create(Completer<void>()..complete()),
      );
      expect(res.ran, isFalse);
      expect(res.rejectReason, NavAnnotationRejectReason.draining);
      expect(native.createCalls, 0);
    });

    test('create with stale style / manager / epoch generation never reaches '
        'native', () async {
      final g = gate();
      g.activate(styleGeneration: 5, sessionGeneration: 6, renderEpoch: 7);
      final native = _FakeNativeManager();
      final staleStyle = NavAnnotationOwnership(
        managerGeneration: g.managerGeneration,
        styleGeneration: 4,
        sessionGeneration: 6,
        renderEpoch: 7,
      );
      final staleGen = NavAnnotationOwnership(
        managerGeneration: g.managerGeneration - 1,
        styleGeneration: 5,
        sessionGeneration: 6,
        renderEpoch: 7,
      );
      final staleEpoch = NavAnnotationOwnership(
        managerGeneration: g.managerGeneration,
        styleGeneration: 5,
        sessionGeneration: 6,
        renderEpoch: 6,
      );
      for (final own in [staleStyle, staleGen, staleEpoch]) {
        final res = await g.runGuarded<void>(
          ownership: own,
          kind: NavAnnotationOperationKind.create,
          nativeOp: () => native.create(Completer<void>()..complete()),
        );
        expect(res.ran, isFalse);
      }
      expect(native.createCalls, 0);
      expect(g.activeLeases, 0);
    });

    test('dispose waits for in-flight create lease then removes exactly once',
        () async {
      final g = gate();
      final own = g.activate(
        styleGeneration: 1,
        sessionGeneration: 1,
        renderEpoch: 1,
      );
      final native = _FakeNativeManager();
      final createGate = Completer<void>();
      final createFuture = g.runGuarded<void>(
        ownership: own,
        kind: NavAnnotationOperationKind.create,
        nativeOp: () => native.create(createGate),
      );
      await Future<void>.value();
      g.beginDrain();

      var drainResolved = false;
      final drainFuture = g.awaitDrained().then((_) => drainResolved = true);
      await Future<void>.value();
      expect(drainResolved, isFalse);

      createGate.complete();
      await createFuture;
      await drainFuture;
      expect(drainResolved, isTrue);
      expect(g.activeLeases, 0);

      // Idempotent dispose.
      expect(g.markDisposed(), isTrue);
      expect(g.markDisposed(), isFalse);
    });

    test('rapid style taps coalesce → latest style wins (product gate)', () {
      // NAV-MOBILE-DATA-MINIMAL-SAFE-RELEASE-P0-1 Part D: the emergency
      // Kill-switch can still be forced off; Phase-6 lease/coalesce behaviour
      // is exercised with the flag explicitly enabled.
      expect(
        navStyleTapDecision(
          liveRideActive: true,
          styleTransactionRunning: false,
          activeRideStyleSwitchEnabled: true,
        ),
        NavStyleTapDecision.begin,
      );
      expect(
        navStyleTapDecision(
          liveRideActive: true,
          styleTransactionRunning: true,
          activeRideStyleSwitchEnabled: true,
        ),
        NavStyleTapDecision.coalesce,
      );
      expect(
        navStyleTapDecision(
          liveRideActive: true,
          styleTransactionRunning: false,
          activeRideStyleSwitchEnabled: false,
        ),
        NavStyleTapDecision.blocked,
      );
      // Non-live ride is never blocked.
      expect(
        navStyleTapDecision(
          liveRideActive: false,
          styleTransactionRunning: false,
          activeRideStyleSwitchEnabled: false,
        ),
        NavStyleTapDecision.begin,
      );
      // NAV-RELEASE-FINAL-FLOW-1: default kill switch locks style during a
      // live ride; Light/Dark/3D/Satellite remain available only in preview.
      expect(
        navStyleTapDecision(
          liveRideActive: true,
          styleTransactionRunning: false,
        ),
        NavStyleTapDecision.blocked,
      );
    });

    test('lease releases on native throw (finally) — never leaks a lease',
        () async {
      final g = gate();
      final own = g.activate(
        styleGeneration: 1,
        sessionGeneration: 1,
        renderEpoch: 1,
      );
      await expectLater(
        g.runGuarded<void>(
          ownership: own,
          kind: NavAnnotationOperationKind.create,
          nativeOp: () async => throw StateError('boom'),
        ),
        throwsA(isA<StateError>()),
      );
      expect(g.activeLeases, 0);
    });

    test('awaitDrained completes immediately when no lease is held', () async {
      final g = gate();
      g.activate(styleGeneration: 1, sessionGeneration: 1, renderEpoch: 1);
      var done = false;
      await g.awaitDrained().then((_) => done = true);
      expect(done, isTrue);
    });

    test('TX event labels and count buckets are PII-free and bounded', () {
      expect(navAnnotationTxEventLabel(NavAnnotationTxEvent.leaseAcquired),
          'lease_acquired');
      expect(navAnnotationTxEventLabel(NavAnnotationTxEvent.managerRemoved),
          'manager_removed');
      expect(navAnnotationCountBucket(0), '0');
      expect(navAnnotationCountBucket(1), '1');
      expect(navAnnotationCountBucket(3), '2-3');
      expect(navAnnotationCountBucket(7), '4-7');
      expect(navAnnotationCountBucket(50), '8+');
    });
  });

  group('Tellers / style invariants', () {
    test('Tellers open/close must not request a map-style change', () {
      expect(tellersPresentationMustNotChangeMapStyle(), isTrue);
    });

    test('style-swap steps are ordered drain → dispose → activate → restore', () {
      final steps = navAnnotationStyleSwapSteps();
      expect(steps.first, NavAnnotationStyleSwapStep.beginDrain);
      expect(
        steps.indexOf(NavAnnotationStyleSwapStep.disposeOnce),
        lessThan(
          steps.indexOf(NavAnnotationStyleSwapStep.activateNewGeneration),
        ),
      );
      expect(
        steps.indexOf(NavAnnotationStyleSwapStep.activateNewGeneration),
        lessThan(steps.indexOf(NavAnnotationStyleSwapStep.restoreCurrentOwner)),
      );
      // Never delete-then-dispose: dispose is the annotation-clearing step.
      expect(steps, isNot(contains('deleteThenDispose')));
    });
  });
}
