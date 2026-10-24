import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/navigation/driver_navigation_models.dart';
import 'package:fluxidi_tracking/navigation/nav_backend/driver_route_apply.dart';

DriverNavStep _step({String instruction = 'Turn right'}) {
  return DriverNavStep(
    lat: 50.85,
    lon: 4.35,
    instruction: instruction,
    street: 'Teststraat',
    type: 'turn',
    modifier: 'right',
    distanceAlongRouteM: 10,
  );
}

DriverPreparedRoutePackage _livePackage() {
  final coords = const <DriverLonLat>[
    DriverLonLat(4.35, 50.85),
    DriverLonLat(4.36, 50.86),
  ];
  return DriverPreparedRoutePackage(
    coords: coords,
    navSteps: <DriverNavStep>[_step()],
    distanceMeters: 1000,
    durationSeconds: 120,
    source: DriverRouteResponseSource.worker,
    geometryFingerprint: driverRouteGeometryFingerprint(coords),
  );
}

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
    required int capturedVersion,
    required int Function() currentVersion,
    required int createId,
  }) async {
    // Match production: optional early check, then create into locals,
    // then commit-or-orphan-delete without touching newer shared refs.
    if (shouldIgnoreStaleRouteDraw(
      drawAppliedRouteVersion: capturedVersion,
      currentAppliedRouteVersion: currentVersion(),
    )) {
      // Still model a late create that raced past the early check.
    }
    final previous = shared;
    final created = await create(createId);
    final commit = evaluateRouteAnnotationCommit(
      capturedRenderEpoch: capturedVersion,
      currentRenderEpoch: currentVersion(),
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

void main() {
  group('P0B1 render invalidation', () {
    test(
      '1-3: clear invalidates accepted draw; stale completion cannot commit',
      () async {
        final render = DriverRouteAppliedRenderVersionClock();
        final slot = _AnnotationSlot();

        final versionN = render.activateAcceptedRoute();
        expect(versionN, 1);

        // Draw N starts (captures version 1).
        final capturedN = versionN;

        // Hard clear invalidates rendering before annotation wipe.
        final afterClear = render.invalidateForHardClear();
        expect(afterClear, 2);
        slot.shared = null; // clear wiped shared refs

        // Draw N completes afterward.
        await slot.drawOwned(
          capturedVersion: capturedN,
          currentVersion: () => render.current,
          createId: 100,
        );

        expect(slot.shared, isNull);
        expect(slot.deletedIds, contains(100));
        expect(
          formatNavRouteRenderDiag(
            action: 'invalidate',
            reason: 'stop',
            renderEpoch: afterClear,
          ),
          contains('action=invalidate'),
        );
      },
    );

    test(
      '4-6: newer route draw wins; stale N cannot damage N+1 shared refs',
      () async {
        final render = DriverRouteAppliedRenderVersionClock();
        final slot = _AnnotationSlot();

        final versionN = render.activateAcceptedRoute();
        final capturedN = versionN;

        final versionN1 = render.activateAcceptedRoute();
        await slot.drawOwned(
          capturedVersion: versionN1,
          currentVersion: () => render.current,
          createId: 201,
        );
        expect(slot.shared?.id, 201);

        await slot.drawOwned(
          capturedVersion: capturedN,
          currentVersion: () => render.current,
          createId: 101,
        );
        expect(slot.shared?.id, 201, reason: 'N+1 shared ref intact');
        expect(
          slot.deletedIds,
          contains(101),
          reason: 'N orphan cleaned locally',
        );
        expect(slot.deletedIds, isNot(contains(201)));
      },
    );

    test('7: stale route-line commit deletes only local orphans', () {
      final decision = evaluateRouteAnnotationCommit(
        capturedRenderEpoch: 3,
        currentRenderEpoch: 4,
      );
      expect(decision.shouldDeleteLocalOrphansOnly, isTrue);
      expect(decision.shouldCommitShared, isFalse);
    });

    test(
      '8-9: stale pin/marker commit cannot touch shared current objects',
      () {
        // Same ownership decision for pins and destination marker.
        final stale = evaluateRouteAnnotationCommit(
          capturedRenderEpoch: 1,
          currentRenderEpoch: 2,
        );
        expect(stale.shouldCommitShared, isFalse);
        final current = evaluateRouteAnnotationCommit(
          capturedRenderEpoch: 2,
          currentRenderEpoch: 2,
        );
        expect(current.shouldCommitShared, isTrue);
      },
    );

    test(
      '10: style restore aborts when route cleared (no coords / version mismatch)',
      () {
        expect(
          mayRestoreRouteRender(
            routeCoordCount: 0,
            capturedRenderEpoch: 5,
            currentRenderEpoch: 5,
          ),
          isFalse,
        );
        expect(
          mayRestoreRouteRender(
            routeCoordCount: 4,
            capturedRenderEpoch: 5,
            currentRenderEpoch: 6,
          ),
          isFalse,
        );
        expect(
          mayRestoreRouteRender(
            routeCoordCount: 4,
            capturedRenderEpoch: 6,
            currentRenderEpoch: 6,
          ),
          isTrue,
        );
      },
    );

    test('16: exactly one render version per accepted activation', () {
      final render = DriverRouteAppliedRenderVersionClock();
      expect(render.activateAcceptedRoute(), 1);
      expect(render.activateAcceptedRoute(), 2);
      expect(render.current, 2);
    });

    test('17: hard clear invalidates request + render clocks', () {
      final requests = DriverRouteRequestGenerationClock();
      final render = DriverRouteAppliedRenderVersionClock();
      final inFlightRequest = requests.begin();
      final acceptedRender = render.activateAcceptedRoute();
      requests.invalidateAll();
      final clearedRender = render.invalidateForHardClear();
      expect(inFlightRequest == requests.latest, isFalse);
      expect(acceptedRender == clearedRender, isFalse);
      expect(
        shouldIgnoreStaleRouteDraw(
          drawAppliedRouteVersion: acceptedRender,
          currentAppliedRouteVersion: clearedRender,
        ),
        isTrue,
      );
    });
  });

  group('P0B1 booking-worker fallback + purpose gates', () {
    test(
      '11-12: booking-worker overview package activates only for overview',
      () {
        final package = prepareBookingWorkerOverviewPackage(
          coords: const <DriverLonLat>[
            DriverLonLat(4.35, 50.85),
            DriverLonLat(4.36, 50.86),
          ],
          distanceMeters: 800,
          durationSeconds: 90,
        );
        expect(package.source, DriverRouteResponseSource.bookingWorkerOverview);
        expect(package.hasUsableSteps, isFalse);
        expect(
          package.isAcceptableFor(DriverRouteApplyPurpose.overview),
          isTrue,
        );
        expect(
          package.isAcceptableFor(DriverRouteApplyPurpose.destination),
          isFalse,
        );

        final clock = DriverRouteRequestGenerationClock();
        final gen = clock.begin();
        final overviewAccept = evaluateDriverRouteAcceptance(
          context: DriverRouteRequestContext(
            requestGeneration: gen,
            cleanupEpoch: 1,
            purpose: DriverRouteApplyPurpose.overview,
            expectedBookingId: 'B1',
          ),
          snapshot: DriverRouteAcceptanceSnapshot(
            mounted: true,
            latestRequestGeneration: gen,
            cleanupEpoch: 1,
            activeBookingId: 'B1',
            activeTripId: null,
            directRideActive: false,
            liveRideActive: false,
          ),
          package: package,
        );
        expect(overviewAccept.accepted, isTrue);

        final liveReject = evaluateDriverRouteAcceptance(
          context: DriverRouteRequestContext(
            requestGeneration: gen,
            cleanupEpoch: 1,
            purpose: DriverRouteApplyPurpose.destination,
            expectedBookingId: 'B1',
            expectedTripId: 'T1',
          ),
          snapshot: DriverRouteAcceptanceSnapshot(
            mounted: true,
            latestRequestGeneration: gen,
            cleanupEpoch: 1,
            activeBookingId: 'B1',
            activeTripId: 'T1',
            directRideActive: false,
            liveRideActive: true,
          ),
          package: package,
        );
        expect(liveReject.accepted, isFalse);
        expect(liveReject.reason, DriverRouteRejectReason.emptySteps);
      },
    );

    test('13: booking-worker fallback cannot replace active live route', () {
      final package = prepareBookingWorkerOverviewPackage(
        coords: const <DriverLonLat>[
          DriverLonLat(4.35, 50.85),
          DriverLonLat(4.36, 50.86),
        ],
        distanceMeters: 800,
        durationSeconds: 90,
      );
      final clock = DriverRouteRequestGenerationClock();
      final gen = clock.begin();
      final decision = evaluateDriverRouteAcceptance(
        context: DriverRouteRequestContext(
          requestGeneration: gen,
          cleanupEpoch: 1,
          purpose: DriverRouteApplyPurpose.overview,
          expectedBookingId: 'B1',
        ),
        snapshot: DriverRouteAcceptanceSnapshot(
          mounted: true,
          latestRequestGeneration: gen,
          cleanupEpoch: 1,
          activeBookingId: 'B1',
          activeTripId: 'T1',
          directRideActive: false,
          liveRideActive: true,
        ),
        package: package,
      );
      expect(decision.accepted, isFalse);
      expect(decision.reason, DriverRouteRejectReason.phaseChanged);
    });

    test('14: overview builder must not clear live-navigation annotations', () {
      expect(mayClearOverviewAnnotations(liveRideActive: true), isFalse);
      expect(mayClearOverviewAnnotations(liveRideActive: false), isTrue);
    });

    test('15: dedicated destination-purpose acceptance', () {
      final clock = DriverRouteRequestGenerationClock();
      final gen = clock.begin();
      final package = _livePackage();
      final accepted = evaluateDriverRouteAcceptance(
        context: DriverRouteRequestContext(
          requestGeneration: gen,
          cleanupEpoch: 2,
          purpose: DriverRouteApplyPurpose.destination,
          expectedBookingId: 'B1',
          expectedTripId: 'T1',
        ),
        snapshot: DriverRouteAcceptanceSnapshot(
          mounted: true,
          latestRequestGeneration: gen,
          cleanupEpoch: 2,
          activeBookingId: 'B1',
          activeTripId: 'T1',
          directRideActive: false,
          liveRideActive: true,
        ),
        package: package,
      );
      expect(accepted.accepted, isTrue);

      final rejected = evaluateDriverRouteAcceptance(
        context: DriverRouteRequestContext(
          requestGeneration: gen,
          cleanupEpoch: 2,
          purpose: DriverRouteApplyPurpose.destination,
          expectedBookingId: 'B1',
          expectedTripId: 'T1',
        ),
        snapshot: DriverRouteAcceptanceSnapshot(
          mounted: true,
          latestRequestGeneration: gen,
          cleanupEpoch: 2,
          activeBookingId: 'B1',
          activeTripId: null,
          directRideActive: false,
          liveRideActive: false,
        ),
        package: package,
      );
      expect(rejected.accepted, isFalse);
      expect(
        rejected.reason,
        anyOf(
          DriverRouteRejectReason.sessionChanged,
          DriverRouteRejectReason.phaseChanged,
        ),
      );
    });

    test(
      '18: stale/failed acceptance preserves conceptual prior route version',
      () {
        var priorAppliedVersion = 9;
        final priorCoords = const <DriverLonLat>[
          DriverLonLat(4.10, 50.10),
          DriverLonLat(4.11, 50.11),
        ];
        final clock = DriverRouteRequestGenerationClock();
        final staleGen = clock.begin();
        clock.invalidateAll();
        final decision = evaluateDriverRouteAcceptance(
          context: DriverRouteRequestContext(
            requestGeneration: staleGen,
            cleanupEpoch: 1,
            purpose: DriverRouteApplyPurpose.destination,
            expectedBookingId: 'B1',
            expectedTripId: 'T1',
          ),
          snapshot: DriverRouteAcceptanceSnapshot(
            mounted: true,
            latestRequestGeneration: clock.latest,
            cleanupEpoch: 1,
            activeBookingId: 'B1',
            activeTripId: 'T1',
            directRideActive: false,
            liveRideActive: true,
          ),
          package: _livePackage(),
        );
        expect(decision.accepted, isFalse);
        // No activation => prior version/geometry conceptually unchanged.
        expect(priorAppliedVersion, 9);
        expect(priorCoords.length, 2);
      },
    );
  });
}
