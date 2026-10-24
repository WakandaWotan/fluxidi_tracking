// NAV-ANNOTATION-LIFECYCLE-REPAIR-1

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/navigation/nav_engine/nav_polyline_annotation_delete.dart';
import 'package:fluxidi_tracking/navigation/nav_engine/nav_ui_input_timing_diagnostics.dart';

PlatformException _alreadyDeletedEx([String id = 'ann-1']) {
  return PlatformException(
    code: 'Throwable',
    message:
        'java.lang.Throwable: Annotation has not been added on the map: '
        'PolylineAnnotation(id=$id, geometry=LineString([]))',
  );
}

PlatformException _managerLostEx() {
  return PlatformException(
    code: 'Throwable',
    message: 'No manager found with id: 4',
  );
}

PlatformException _unexpectedEx() {
  return PlatformException(
    code: 'other',
    message: 'native boom unrelated',
  );
}

void main() {
  group('classifyPolylineAnnotationDeleteError', () {
    test('already-deleted annotation is non-fatal lifecycle', () {
      expect(
        classifyPolylineAnnotationDeleteError(_alreadyDeletedEx()),
        NavPolylineDeleteErrorClass.alreadyDeleted,
      );
      expect(isStalePolylineAnnotationDeleteError(_alreadyDeletedEx()), isTrue);
    });

    test('manager lost is non-fatal lifecycle', () {
      expect(
        classifyPolylineAnnotationDeleteError(_managerLostEx()),
        NavPolylineDeleteErrorClass.managerLost,
      );
    });

    test('unexpected PlatformException stays unexpected', () {
      expect(
        classifyPolylineAnnotationDeleteError(_unexpectedEx()),
        NavPolylineDeleteErrorClass.unexpected,
      );
      expect(isStalePolylineAnnotationDeleteError(_unexpectedEx()), isFalse);
    });
  });

  group('NavPolylineDeleteCoordinator', () {
    late NavPolylineDeleteCoordinator coord;
    late int managerGen;
    late int renderEpoch;
    late int sessionGen;
    late int styleGen;

    setUp(() {
      coord = NavPolylineDeleteCoordinator();
      managerGen = 1;
      renderEpoch = 10;
      sessionGen = 1;
      styleGen = 1;
      coord.onManagerActivated(managerGen);
    });

    NavPolylineDeleteOwnership ownership({
      int? manager,
      int? render,
      int? session,
      int? style,
    }) {
      return NavPolylineDeleteOwnership(
        managerGeneration: manager ?? managerGen,
        renderEpoch: render ?? renderEpoch,
        sessionGeneration: session ?? sessionGen,
        styleGeneration: style ?? styleGen,
      );
    }

    Future<NavPolylineDeleteResult> del(
      String id, {
      NavPolylineDeleteOwnership? own,
      Future<void> Function()? native,
    }) {
      return coord.delete(
        annotationId: id,
        ownership: own ?? ownership(),
        currentManagerGeneration: () => managerGen,
        currentRenderEpoch: () => renderEpoch,
        currentSessionGeneration: () => sessionGen,
        currentStyleGeneration: () => styleGen,
        nativeDelete: native ?? () async {},
      );
    }

    test('repeated clear/delete is idempotent', () async {
      var nativeCalls = 0;
      final first = await del('a1', native: () async {
        nativeCalls += 1;
      });
      final second = await del('a1', native: () async {
        nativeCalls += 1;
      });
      expect(first.outcome, NavPolylineDeleteOutcome.deleted);
      expect(second.outcome, NavPolylineDeleteOutcome.alreadyGone);
      expect(nativeCalls, 1);
      expect(coord.wasDeleted('a1'), isTrue);
    });

    test('route A delete completing after route B installed does not mutate B',
        () async {
      final gate = Completer<void>();
      final aOwn = ownership(render: 10);
      // Route A delete starts (slow native).
      final aFuture = del(
        'routeA',
        own: aOwn,
        native: () async {
          await gate.future;
        },
      );
      // Route B installs while A is in-flight (queued behind serial chain).
      renderEpoch = 11;
      final bFuture = del('routeB', own: ownership(render: 11));
      gate.complete();
      final a = await aFuture;
      final b = await bFuture;
      expect(a.outcome, NavPolylineDeleteOutcome.deleted);
      expect(b.outcome, NavPolylineDeleteOutcome.deleted);
      // Completion must report ownership no longer current → caller must not
      // clear current route handles.
      expect(a.ownershipStillCurrent, isFalse);
      expect(
        coord.mayMutateCurrentRoute(
          aOwn,
          currentManagerGeneration: managerGen,
          currentRenderEpoch: renderEpoch,
          currentSessionGeneration: sessionGen,
          currentStyleGeneration: styleGen,
        ),
        isFalse,
      );
      expect(coord.wasDeleted('routeB'), isTrue);
      expect(coord.wasDeleted('routeA'), isTrue);
    });

    test('reroute replacement: overlapping delete of same id is safe', () async {
      final slow = Completer<void>();
      var nativeCalls = 0;
      final first = del(
        'line',
        native: () async {
          nativeCalls += 1;
          await slow.future;
        },
      );
      final second = del(
        'line',
        native: () async {
          nativeCalls += 1;
        },
      );
      slow.complete();
      final r1 = await first;
      final r2 = await second;
      expect(r1.outcome, NavPolylineDeleteOutcome.deleted);
      expect(r2.outcome, NavPolylineDeleteOutcome.alreadyGone);
      expect(nativeCalls, 1);
    });

    test('STOP teardown: already-deleted annotation is non-fatal', () async {
      final r = await del(
        'stop-line',
        native: () async {
          throw _alreadyDeletedEx('stop-line');
        },
      );
      expect(r.outcome, NavPolylineDeleteOutcome.alreadyGone);
      expect(r.errorClass, NavPolylineDeleteErrorClass.alreadyDeleted);
      // Second STOP clear is idempotent.
      final r2 = await del(
        'stop-line',
        native: () async {
          fail('must not call native again');
        },
      );
      expect(r2.outcome, NavPolylineDeleteOutcome.alreadyGone);
    });

    test('style reload / manager recreation skips stale generation deletes',
        () async {
      final oldOwn = ownership(manager: 1);
      managerGen = 2;
      coord.onManagerActivated(2);
      var nativeCalls = 0;
      final r = await del(
        'old',
        own: oldOwn,
        native: () async {
          nativeCalls += 1;
        },
      );
      expect(r.outcome, NavPolylineDeleteOutcome.staleSkipped);
      expect(r.ownershipStillCurrent, isFalse);
      expect(nativeCalls, 0);
    });

    test('already-deleted PlatformException does not escape', () async {
      Object? escaped;
      await runZonedGuarded(() async {
        await del(
          'gone',
          native: () async {
            throw _alreadyDeletedEx('gone');
          },
        );
      }, (e, st) {
        escaped = e;
      });
      expect(escaped, isNull);
    });

    test('unexpected PlatformException is reported but not rethrown', () async {
      Object? escaped;
      late NavPolylineDeleteResult result;
      final diag = <String>[];
      String? currentRouteId = 'routeB';
      final aOwn = ownership(render: 10);
      // Newer route already installed before the unexpected delete completes.
      renderEpoch = 11;

      await runZonedGuarded(() async {
        result = await del(
          'boom',
          own: aOwn,
          native: () async {
            throw _unexpectedEx();
          },
        );
        // Production delete path emits sanitized timing for unexpected failures.
        logNavUiInputTiming(
          action: NavUiInputTimingAction.routeAnnotationDelete,
          phase: NavUiInputTimingPhase.deleteFailed,
          managerGeneration: managerGen,
          renderEpoch: renderEpoch,
          reason: result.errorToken,
          emit: diag.add,
        );
      }, (e, st) {
        escaped = e;
      });

      expect(escaped, isNull);
      expect(result.outcome, NavPolylineDeleteOutcome.unexpectedFailure);
      expect(result.errorClass, NavPolylineDeleteErrorClass.unexpected);
      expect(result.errorClass, isNot(NavPolylineDeleteErrorClass.alreadyDeleted));
      expect(result.errorToken, 'platform:other');
      expect(diag, isNotEmpty);
      expect(diag.single, contains('action=route_annotation_delete'));
      expect(diag.single, contains('phase=delete_failed'));
      expect(diag.single, contains('reason=platform:other'));

      // Unexpected failure must leave the id retryable (not marked deleted).
      expect(coord.wasDeleted('boom'), isFalse);

      // Later successful retry completes normally.
      final retry = await del('boom', own: ownership(render: 11));
      expect(retry.outcome, NavPolylineDeleteOutcome.deleted);
      expect(coord.wasDeleted('boom'), isTrue);

      // Stale unexpected completion must never clear the newer route.
      if (result.ownershipStillCurrent &&
          coord.mayMutateCurrentRoute(
            aOwn,
            currentManagerGeneration: managerGen,
            currentRenderEpoch: renderEpoch,
            currentSessionGeneration: sessionGen,
            currentStyleGeneration: styleGen,
          )) {
        currentRouteId = null;
      }
      expect(result.ownershipStillCurrent, isFalse);
      expect(currentRouteId, 'routeB');
    });

    test('no unhandled async error on fire-and-forget overlapping deletes',
        () async {
      Object? escaped;
      final errors = <Object>[];
      await runZonedGuarded(() async {
        final slow = Completer<void>();
        unawaited(
          del(
            'x',
            native: () async {
              await slow.future;
              throw _alreadyDeletedEx('x');
            },
          ),
        );
        unawaited(
          del(
            'x',
            native: () async {
              throw _alreadyDeletedEx('x');
            },
          ),
        );
        slow.complete();
        // Flush microtasks / serial chain.
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);
      }, (e, st) {
        escaped = e;
        errors.add(e);
      });
      expect(escaped, isNull);
      expect(errors, isEmpty);
    });

    test('current route remains intact after stale delete completion', () async {
      // Simulate shared route handle ownership outside the coordinator.
      String? currentRouteId = 'routeA';
      final gate = Completer<void>();
      final aOwn = ownership(render: 10);

      final aFuture = del(
        'routeA',
        own: aOwn,
        native: () async {
          await gate.future;
        },
      );

      // Install route B (as _drawRouteLine would).
      renderEpoch = 11;
      currentRouteId = 'routeB';

      gate.complete();
      final a = await aFuture;

      // Mimic production rule: never clear current from delete completion.
      if (a.ownershipStillCurrent &&
          coord.mayMutateCurrentRoute(
            aOwn,
            currentManagerGeneration: managerGen,
            currentRenderEpoch: renderEpoch,
            currentSessionGeneration: sessionGen,
            currentStyleGeneration: styleGen,
          )) {
        currentRouteId = null;
      }

      expect(currentRouteId, 'routeB');
      expect(a.ownershipStillCurrent, isFalse);
    });
  });

  group('nav_ui_input_timing_diagnostics', () {
    test('emits sanitized Ter plaatse / View zoom / delete lines', () {
      final lines = <String>[];
      logNavUiInputTiming(
        action: NavUiInputTimingAction.terPlaatse,
        phase: NavUiInputTimingPhase.inputReceived,
        managerGeneration: 2,
        renderEpoch: 5,
        reason: 'start_trip',
        emit: lines.add,
      );
      logNavUiInputTiming(
        action: NavUiInputTimingAction.viewZoom,
        phase: NavUiInputTimingPhase.completed,
        durationMs: 120,
        reason: 'minus',
        emit: lines.add,
      );
      logNavUiInputTiming(
        action: NavUiInputTimingAction.routeAnnotationDelete,
        phase: NavUiInputTimingPhase.deleteFailed,
        reason: 'already_deleted',
        emit: lines.add,
      );
      expect(lines[0], contains('action=ter_plaatse'));
      expect(lines[0], contains('phase=input_received'));
      expect(lines[0], contains('managerGeneration=2'));
      expect(lines[1], contains('action=view_zoom'));
      expect(lines[1], contains('phase=completed'));
      expect(lines[2], contains('action=route_annotation_delete'));
      expect(lines.join(), isNot(contains('Bearer')));
      expect(lines.join(), isNot(contains('pk.')));
    });
  });
}
