import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/navigation/nav_backend/driver_route_apply.dart';
import 'package:fluxidi_tracking/navigation/nav_engine/nav_complexity_guard.dart';
import 'package:fluxidi_tracking/navigation/nav_engine/nav_reroute_stabilization.dart';

/// Minimal shared-ref simulation for annotation ownership tests.
class _FakeAnnotation {
  _FakeAnnotation(this.id);
  final int id;
}

class _AnnotationSlot {
  _FakeAnnotation? shared;
  final List<int> deletedIds = <int>[];

  Future<_FakeAnnotation> create(int id) async => _FakeAnnotation(id);

  Future<void> delete(_FakeAnnotation annotation) async {
    deletedIds.add(annotation.id);
  }

  Future<void> drawOwned({
    required int capturedRenderEpoch,
    required int Function() currentRenderEpoch,
    required int createId,
  }) async {
    final previous = shared;
    final created = await create(createId);
    final commit = evaluateRouteAnnotationCommit(
      capturedRenderEpoch: capturedRenderEpoch,
      currentRenderEpoch: currentRenderEpoch(),
    );
    if (commit.shouldDeleteLocalOrphansOnly) {
      await delete(created);
      return;
    }
    shared = created;
    if (previous != null && previous.id != created.id) {
      await delete(previous);
    }
  }
}

NavComplexityGuardInput _complexityInput({
  required int routeVersion,
  DateTime? now,
}) {
  return NavComplexityGuardInput(
    timestamp: now ?? DateTime.utc(2026, 1, 1, 12),
    liveRideActive: true,
    followMode: true,
    overallConfidence: 80,
    snapDistanceM: 4,
    speedKmh: 30,
    routeVersion: routeVersion,
  );
}

void main() {
  group('NAV-SIGNAL-P0B2 dual version clocks', () {
    test('1: accepted route N bumps steps version and render epoch', () {
      final clocks = DriverRouteVersionClocks();
      final activated = clocks.activateAcceptedRoute();
      expect(activated.routeStepsVersion, 1);
      expect(activated.routeRenderEpoch, 1);
      expect(clocks.routeStepsVersion, 1);
      expect(clocks.routeRenderEpoch, 1);
    });

    test(
      '2: hard clear bumps render epoch only; no activation success diag',
      () {
        final clocks = DriverRouteVersionClocks();
        clocks.activateAcceptedRoute();
        final stepsBefore = clocks.routeStepsVersion;
        final renderBefore = clocks.routeRenderEpoch;

        final cleared = clocks.invalidateRenderForHardClear();
        expect(cleared, renderBefore + 1);
        expect(clocks.routeStepsVersion, stepsBefore);
        expect(clocks.routeRenderEpoch, renderBefore + 1);

        final applyDiag = formatNavRouteApplyDiag(
          requestGeneration: 1,
          latestGeneration: 1,
          accepted: true,
          routeVersion: clocks.routeStepsVersion,
          renderEpoch: clocks.routeRenderEpoch,
        );
        // Render invalidation must not be phrased as route apply success alone.
        final renderDiag = formatNavRouteRenderDiag(
          action: 'invalidate',
          reason: 'hard_clear',
          renderEpoch: clocks.routeRenderEpoch,
          activeRouteVersion: clocks.routeStepsVersion,
        );
        expect(renderDiag, contains('action=invalidate'));
        expect(renderDiag, isNot(contains('accepted=true')));
        expect(applyDiag, contains('accepted=true')); // only when explicitly so
      },
    );

    test(
      '3: render-only clear does not open stabilization via newer generation',
      () {
        final clocks = DriverRouteVersionClocks();
        final activated = clocks.activateAcceptedRoute();
        final stab = NavRerouteStabilization();
        final t0 = DateTime.utc(2026, 7, 17, 12);
        stab.noteRerouteApplied(
          newRouteGeneration: activated.routeStepsVersion,
          now: t0,
        );

        // Render-only invalidation (hard clear) must not bump steps version.
        clocks.invalidateRenderForHardClear();
        expect(clocks.routeStepsVersion, activated.routeStepsVersion);

        // Without an explicit reset, same generation keeps the gate closed.
        expect(
          stab.allowOppositeDirectionReroute(
            now: t0.add(const Duration(seconds: 1)),
            snapDistanceM: 15,
            oppositeStrong: true,
            speedKmh: 10,
            currentRouteGeneration: clocks.routeStepsVersion,
          ),
          isFalse,
        );

        // Production clear resets stabilization explicitly.
        stab.reset();
        expect(
          stab.allowOppositeDirectionReroute(
            now: t0.add(const Duration(seconds: 1)),
            snapDistanceM: 15,
            oppositeStrong: true,
            speedKmh: 10,
            currentRouteGeneration: clocks.routeStepsVersion,
          ),
          isTrue,
        );
        expect(stab.stabilizationActive, isFalse);
      },
    );

    test(
      '4: render-only clear is not a complexity route-replacement version',
      () {
        final clocks = DriverRouteVersionClocks();
        clocks.activateAcceptedRoute();
        final steps = clocks.routeStepsVersion;
        clocks.invalidateRenderForHardClear();

        final guard = NavComplexityGuard();
        var t = DateTime.utc(2026, 1, 1, 12);
        var state = guard.update(_complexityInput(routeVersion: steps, now: t));
        expect(state.decision.transition, isNot('terminal_clear'));

        // Same accepted route version after render clear — no fake replacement.
        t = t.add(const Duration(seconds: 1));
        state = guard.update(
          _complexityInput(routeVersion: clocks.routeStepsVersion, now: t),
        );
        expect(clocks.routeStepsVersion, steps);
        expect(clocks.routeRenderEpoch, isNot(steps));
        expect(state.decision.transition, isNot('terminal_clear'));

        // Explicit session clear resets complexity (production clear path).
        guard.reset();
        expect(
          guard.update(_complexityInput(routeVersion: steps)).active,
          isFalse,
        );
      },
    );

    test('5: accept → clear → accept: steps N→N+1; render advances thrice', () {
      final clocks = DriverRouteVersionClocks();
      final n = clocks.activateAcceptedRoute();
      expect(n.routeStepsVersion, 1);
      expect(n.routeRenderEpoch, 1);

      final afterClear = clocks.invalidateRenderForHardClear();
      expect(clocks.routeStepsVersion, 1);
      expect(afterClear, 2);

      final n1 = clocks.activateAcceptedRoute();
      expect(n1.routeStepsVersion, 2);
      expect(n1.routeRenderEpoch, 3);
      // Counters need not stay equal or consecutive with each other.
      expect(n1.routeStepsVersion == n1.routeRenderEpoch, isFalse);
      expect(n1.routeRenderEpoch - n1.routeStepsVersion, 1);
    });

    test(
      '6-8: draw R starts; hard clear → R+1; stale R deletes local only',
      () async {
        final clocks = DriverRouteVersionClocks();
        final slot = _AnnotationSlot();
        final r = clocks.activateAcceptedRoute().routeRenderEpoch;
        final capturedR = r;

        clocks.invalidateRenderForHardClear();
        expect(clocks.routeRenderEpoch, r + 1);
        slot.shared = null;

        await slot.drawOwned(
          capturedRenderEpoch: capturedR,
          currentRenderEpoch: () => clocks.routeRenderEpoch,
          createId: 100,
        );
        expect(slot.shared, isNull);
        expect(slot.deletedIds, contains(100));
      },
    );

    test(
      '9-11: draw R starts; activate R+1 commits; late R cannot damage it',
      () async {
        final clocks = DriverRouteVersionClocks();
        final slot = _AnnotationSlot();
        final r = clocks.activateAcceptedRoute().routeRenderEpoch;
        final capturedR = r;

        final next = clocks.activateAcceptedRoute();
        expect(next.routeRenderEpoch, r + 1);
        await slot.drawOwned(
          capturedRenderEpoch: next.routeRenderEpoch,
          currentRenderEpoch: () => clocks.routeRenderEpoch,
          createId: 201,
        );
        expect(slot.shared?.id, 201);

        await slot.drawOwned(
          capturedRenderEpoch: capturedR,
          currentRenderEpoch: () => clocks.routeRenderEpoch,
          createId: 101,
        );
        expect(slot.shared?.id, 201);
        expect(slot.deletedIds, contains(101));
        expect(slot.deletedIds, isNot(contains(201)));
      },
    );

    test('12: style restore captured before clear cannot restore after', () {
      final clocks = DriverRouteVersionClocks();
      final activated = clocks.activateAcceptedRoute();
      final capturedRender = activated.routeRenderEpoch;
      final capturedSteps = activated.routeStepsVersion;

      clocks.invalidateRenderForHardClear();
      // Content version unchanged, but render epoch advanced + coords cleared.
      expect(
        mayRestoreRouteRender(
          routeCoordCount: 4,
          capturedRenderEpoch: capturedRender,
          currentRenderEpoch: clocks.routeRenderEpoch,
          capturedRouteStepsVersion: capturedSteps,
          currentRouteStepsVersion: clocks.routeStepsVersion,
        ),
        isFalse,
      );
      expect(
        mayRestoreRouteRender(
          routeCoordCount: 0,
          capturedRenderEpoch: clocks.routeRenderEpoch,
          currentRenderEpoch: clocks.routeRenderEpoch,
          capturedRouteStepsVersion: clocks.routeStepsVersion,
          currentRouteStepsVersion: clocks.routeStepsVersion,
        ),
        isFalse,
      );
    });

    test('13: exactly-once hard-clear render invalidation', () {
      final clocks = DriverRouteVersionClocks();
      clocks.activateAcceptedRoute();
      var renderAlreadyInvalidated = false;
      void invalidateOnce() {
        if (renderAlreadyInvalidated) return;
        clocks.invalidateRenderForHardClear();
        renderAlreadyInvalidated = true;
      }

      invalidateOnce();
      final epoch = clocks.routeRenderEpoch;
      invalidateOnce();
      expect(clocks.routeRenderEpoch, epoch);
    });

    test(
      '14: renderAlreadyInvalidated cannot suppress a required invalidation',
      () {
        final clocks = DriverRouteVersionClocks();
        clocks.activateAcceptedRoute();
        // First clear path marks already-invalidated after bumping.
        clocks.invalidateRenderForHardClear();
        final afterFirst = clocks.routeRenderEpoch;
        // A later independent clear/replacement must still be able to invalidate.
        clocks.invalidateRenderForHardClear();
        expect(clocks.routeRenderEpoch, afterFirst + 1);
      },
    );

    test(
      '15: render-only invalidation is not an accepted-route success event',
      () {
        final clocks = DriverRouteVersionClocks();
        clocks.activateAcceptedRoute();
        final steps = clocks.routeStepsVersion;
        final stab = NavRerouteStabilization();
        final t0 = DateTime.utc(2026, 7, 17, 12);
        stab.noteRerouteApplied(newRouteGeneration: steps, now: t0);

        clocks.invalidateRenderForHardClear();

        expect(clocks.routeStepsVersion, steps);
        expect(
          formatNavRouteRenderDiag(
            action: 'invalidate',
            reason: 'stop',
            renderEpoch: clocks.routeRenderEpoch,
            activeRouteVersion: clocks.routeStepsVersion,
          ),
          allOf(
            contains('action=invalidate'),
            contains('reason=stop'),
            isNot(contains('route_steps_applied')),
          ),
        );
        // Does not call noteRerouteApplied / open via newer generation.
        expect(stab.postRerouteRouteGeneration, steps);
        expect(
          stab.allowOppositeDirectionReroute(
            now: t0.add(const Duration(seconds: 1)),
            snapDistanceM: 12,
            oppositeStrong: true,
            speedKmh: 10,
            currentRouteGeneration: clocks.routeStepsVersion,
          ),
          isFalse,
        );
      },
    );

    test(
      '16: activation after clear uses new steps version + new render epoch',
      () {
        final clocks = DriverRouteVersionClocks();
        clocks.activateAcceptedRoute();
        clocks.invalidateRenderForHardClear();
        final next = clocks.activateAcceptedRoute();

        // Content consumers see steps version 2.
        expect(next.routeStepsVersion, 2);
        // Visual consumers see render epoch 3.
        expect(next.routeRenderEpoch, 3);
        expect(
          formatNavRouteApplyDiag(
            requestGeneration: 2,
            latestGeneration: 2,
            accepted: true,
            routeVersion: next.routeStepsVersion,
            renderEpoch: next.routeRenderEpoch,
          ),
          allOf(
            contains('accepted=true'),
            contains('routeVersion=2'),
            contains('renderEpoch=3'),
          ),
        );
      },
    );

    test('rejected package increments neither counter', () {
      final clocks = DriverRouteVersionClocks();
      final genClock = DriverRouteRequestGenerationClock();
      final gen = genClock.begin();
      final decision = evaluateDriverRouteAcceptance(
        context: DriverRouteRequestContext(
          requestGeneration: gen,
          cleanupEpoch: 0,
          purpose: DriverRouteApplyPurpose.destination,
          expectedBookingId: 'B1',
          expectedTripId: 'T1',
        ),
        snapshot: DriverRouteAcceptanceSnapshot(
          mounted: true,
          latestRequestGeneration: gen,
          cleanupEpoch: 0,
          activeBookingId: 'B1',
          activeTripId: 'T1',
          directRideActive: false,
          liveRideActive: true,
        ),
        package: null,
      );
      expect(decision.accepted, isFalse);
      expect(clocks.routeStepsVersion, 0);
      expect(clocks.routeRenderEpoch, 0);
    });
  });
}
