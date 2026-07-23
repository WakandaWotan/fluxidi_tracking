// NAV-STYLE-MANAGER-CRASH-TELLERS-MARKER-1 / Commit 1

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/navigation/nav_engine/nav_annotation_manager_lifecycle.dart';

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
