import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/navigation/driver_navigation_models.dart';
import 'package:fluxidi_tracking/navigation/driver_navigation_route_parser.dart';
import 'package:fluxidi_tracking/navigation/nav_backend/driver_route_apply.dart';

DriverNavStep _step({
  double lat = 50.85,
  double lon = 4.35,
  String instruction = 'Turn right',
}) {
  return DriverNavStep(
    lat: lat,
    lon: lon,
    instruction: instruction,
    street: 'Teststraat',
    type: 'turn',
    modifier: 'right',
    distanceAlongRouteM: 10,
    banner: const DriverNavBannerInstruction(primaryText: 'Turn right'),
    lanes: const <DriverNavLaneGuidance>[
      DriverNavLaneGuidance(indications: <String>['straight'], valid: true),
    ],
  );
}

DriverPreparedRoutePackage _package({
  List<DriverLonLat>? coords,
  List<DriverNavStep>? steps,
  DriverRouteResponseSource source = DriverRouteResponseSource.worker,
}) {
  final c =
      coords ??
      const <DriverLonLat>[
        DriverLonLat(4.35, 50.85),
        DriverLonLat(4.36, 50.86),
      ];
  final s = steps ?? <DriverNavStep>[_step()];
  return DriverPreparedRoutePackage(
    coords: List<DriverLonLat>.unmodifiable(c),
    navSteps: List<DriverNavStep>.unmodifiable(s),
    distanceMeters: 1200,
    durationSeconds: 180,
    source: source,
    geometryFingerprint: driverRouteGeometryFingerprint(c),
    stepsWithBannerCount: s.where((e) => e.banner?.hasContent == true).length,
    stepsWithLaneGuidanceCount: s.where((e) => e.lanes.isNotEmpty).length,
  );
}

DriverRouteRequestContext _ctx({
  required int generation,
  int epoch = 1,
  DriverRouteApplyPurpose purpose = DriverRouteApplyPurpose.destination,
  String? bookingId = 'B1',
  bool requireDirectRide = false,
  String? tripId,
  bool expectDirectRideActive = false,
}) {
  return DriverRouteRequestContext(
    requestGeneration: generation,
    cleanupEpoch: epoch,
    purpose: purpose,
    expectedBookingId: bookingId,
    requireDirectRide: requireDirectRide,
    expectedTripId: tripId,
    expectDirectRideActive: expectDirectRideActive,
  );
}

DriverRouteAcceptanceSnapshot _snap({
  bool mounted = true,
  int latest = 1,
  int epoch = 1,
  String? bookingId = 'B1',
  String? tripId = 'T1',
  bool directRideActive = false,
  bool liveRideActive = true,
}) {
  return DriverRouteAcceptanceSnapshot(
    mounted: mounted,
    latestRequestGeneration: latest,
    cleanupEpoch: epoch,
    activeBookingId: bookingId,
    activeTripId: tripId,
    directRideActive: directRideActive,
    liveRideActive: liveRideActive,
  );
}

void main() {
  group('DriverRouteRequestGenerationClock', () {
    test('begin advances and invalidateAll drops in-flight generations', () {
      final clock = DriverRouteRequestGenerationClock();
      final a = clock.begin();
      final b = clock.begin();
      expect(a, 1);
      expect(b, 2);
      expect(clock.latest, 2);
      final cleared = clock.invalidateAll();
      expect(cleared, 3);
      expect(clock.latest, 3);
      // A and B are both stale versus latest.
      expect(a == clock.latest, isFalse);
      expect(b == clock.latest, isFalse);
    });
  });

  group('prepareDriverRoutePackage', () {
    test('is immutable and fingerprints geometry', () {
      final parsed = DriverRouteParseResult(
        coords: const <DriverLonLat>[
          DriverLonLat(4.35, 50.85),
          DriverLonLat(4.36, 50.86),
          DriverLonLat(4.37, 50.87),
        ],
        distanceMeters: 900,
        durationSeconds: 120,
        navSteps: <DriverNavStep>[_step()],
        stepsWithBannerCount: 1,
        stepsWithLaneGuidanceCount: 1,
      );
      final package = prepareDriverRoutePackage(
        parsed: parsed,
        source: DriverRouteResponseSource.mapboxDirect,
      );
      expect(package.hasValidGeometry, isTrue);
      expect(package.hasUsableSteps, isTrue);
      expect(package.source, DriverRouteResponseSource.mapboxDirect);
      expect(package.geometryFingerprint, isNonZero);
      expect(
        () => package.coords.add(const DriverLonLat(0, 0)),
        throwsUnsupportedError,
      );
    });
  });

  group('latest-request-wins / stale races', () {
    test('1-4: A starts, B starts, B accepts, late A rejected', () {
      final clock = DriverRouteRequestGenerationClock();
      final genA = clock.begin();
      final genB = clock.begin();
      expect(genB > genA, isTrue);

      final ctxA = _ctx(generation: genA, tripId: 'T1');
      final ctxB = _ctx(generation: genB, tripId: 'T1');
      final packageB = _package(
        steps: <DriverNavStep>[_step(instruction: 'B step')],
      );
      final packageA = _package(
        steps: <DriverNavStep>[_step(instruction: 'A step')],
        coords: const <DriverLonLat>[
          DriverLonLat(4.40, 50.90),
          DriverLonLat(4.41, 50.91),
        ],
      );

      final acceptB = evaluateDriverRouteAcceptance(
        context: ctxB,
        snapshot: _snap(latest: clock.latest),
        package: packageB,
      );
      expect(acceptB.accepted, isTrue);

      // Simulate B activation advancing applied version externally.
      var appliedVersion = 10;
      var appliedSteps = packageB.navSteps;
      var appliedCoords = packageB.coords;
      if (acceptB.accepted) {
        appliedVersion += 1;
        appliedSteps = packageB.navSteps;
        appliedCoords = packageB.coords;
      }

      final acceptA = evaluateDriverRouteAcceptance(
        context: ctxA,
        snapshot: _snap(latest: clock.latest),
        package: packageA,
      );
      expect(acceptA.accepted, isFalse);
      expect(acceptA.reason, DriverRouteRejectReason.staleGeneration);
      expect(appliedVersion, 11);
      expect(appliedSteps.first.instruction, 'B step');
      expect(appliedCoords.first.lon, 4.35);
      expect(
        formatNavRouteApplyDiag(
          requestGeneration: genA,
          latestGeneration: clock.latest,
          accepted: false,
          reason: acceptA.reason,
        ),
        contains('reason=stale_generation'),
      );
    });

    test('5-7: overview in flight rejected after start-trip live session', () {
      final clock = DriverRouteRequestGenerationClock();
      final overviewGen = clock.begin();
      // Start-trip invalidates obsolete builders.
      clock.invalidateAll();
      final destGen = clock.begin();

      final overviewCtx = _ctx(
        generation: overviewGen,
        purpose: DriverRouteApplyPurpose.overview,
        tripId: null,
      );
      final destCtx = _ctx(
        generation: destGen,
        purpose: DriverRouteApplyPurpose.destination,
        tripId: 'T1',
      );

      final destAccept = evaluateDriverRouteAcceptance(
        context: destCtx,
        snapshot: _snap(
          latest: clock.latest,
          tripId: 'T1',
          liveRideActive: true,
        ),
        package: _package(steps: <DriverNavStep>[_step(instruction: 'dest')]),
      );
      expect(destAccept.accepted, isTrue);

      final overviewAccept = evaluateDriverRouteAcceptance(
        context: overviewCtx,
        snapshot: _snap(
          latest: clock.latest,
          tripId: 'T1',
          liveRideActive: true,
        ),
        package: _package(
          steps: <DriverNavStep>[_step(instruction: 'overview')],
        ),
      );
      expect(overviewAccept.accepted, isFalse);
      expect(
        overviewAccept.reason,
        anyOf(
          DriverRouteRejectReason.staleGeneration,
          DriverRouteRejectReason.phaseChanged,
        ),
      );
    });

    test('8: response after clear/stop (cleanup epoch) rejected', () {
      final clock = DriverRouteRequestGenerationClock();
      final gen = clock.begin();
      final ctx = _ctx(generation: gen, epoch: 4, tripId: 'T1');
      // Stop clears: bump epoch + invalidate generations.
      clock.invalidateAll();
      final decision = evaluateDriverRouteAcceptance(
        context: ctx,
        snapshot: _snap(latest: clock.latest, epoch: 5, tripId: null),
        package: _package(),
      );
      expect(decision.accepted, isFalse);
      expect(
        decision.reason,
        anyOf(
          DriverRouteRejectReason.staleGeneration,
          DriverRouteRejectReason.cleanupEpoch,
          DriverRouteRejectReason.sessionChanged,
          DriverRouteRejectReason.phaseChanged,
        ),
      );
    });

    test('9: booking switch rejects foreign package', () {
      final clock = DriverRouteRequestGenerationClock();
      final gen = clock.begin();
      final decision = evaluateDriverRouteAcceptance(
        context: _ctx(generation: gen, bookingId: 'OLD', tripId: 'T1'),
        snapshot: _snap(latest: gen, bookingId: 'NEW', tripId: 'T1'),
        package: _package(),
      );
      expect(decision.accepted, isFalse);
      expect(decision.reason, DriverRouteRejectReason.bookingChanged);
    });

    test(
      '10: worker-fail then mapbox package accepts only under final guard',
      () {
        final clock = DriverRouteRequestGenerationClock();
        final gen = clock.begin();
        final mapboxPackage = _package(
          source: DriverRouteResponseSource.mapboxDirect,
        );
        final decision = evaluateDriverRouteAcceptance(
          context: _ctx(generation: gen, tripId: 'T1'),
          snapshot: _snap(latest: gen),
          package: mapboxPackage,
        );
        expect(decision.accepted, isTrue);
        expect(mapboxPackage.source, DriverRouteResponseSource.mapboxDirect);
      },
    );

    test(
      '11: malformed/missing package rejected; prior route conceptually kept',
      () {
        final clock = DriverRouteRequestGenerationClock();
        final gen = clock.begin();
        final priorVersion = 7;
        final decision = evaluateDriverRouteAcceptance(
          context: _ctx(generation: gen, tripId: 'T1'),
          snapshot: _snap(latest: gen),
          package: null,
        );
        expect(decision.accepted, isFalse);
        expect(decision.reason, DriverRouteRejectReason.invalidPackage);
        expect(priorVersion, 7);
      },
    );

    test('12: geometry and steps share one applied version allocation', () {
      // Pure activation model: one version bump for the whole package.
      var appliedVersion = 3;
      final package = _package();
      final clock = DriverRouteRequestGenerationClock();
      final gen = clock.begin();
      final decision = evaluateDriverRouteAcceptance(
        context: _ctx(generation: gen, tripId: 'T1'),
        snapshot: _snap(latest: gen),
        package: package,
      );
      expect(decision.accepted, isTrue);
      appliedVersion += 1;
      final activatedCoordsVersion = appliedVersion;
      final activatedStepsVersion = appliedVersion;
      expect(activatedCoordsVersion, activatedStepsVersion);
      expect(
        formatNavRouteApplyDiag(
          requestGeneration: gen,
          latestGeneration: gen,
          accepted: true,
          routeVersion: appliedVersion,
          renderEpoch: appliedVersion,
        ),
        allOf(contains('routeVersion=4'), contains('renderEpoch=4')),
      );
    });

    test('13: route clear invalidates in-flight request generations', () {
      final clock = DriverRouteRequestGenerationClock();
      final inFlight = clock.begin();
      clock.invalidateAll();
      final decision = evaluateDriverRouteAcceptance(
        context: _ctx(generation: inFlight, tripId: 'T1'),
        snapshot: _snap(latest: clock.latest),
        package: _package(),
      );
      expect(decision.accepted, isFalse);
      expect(decision.reason, DriverRouteRejectReason.staleGeneration);
    });

    test('14: async draw for N ignored after N+1', () {
      expect(
        shouldIgnoreStaleRouteDraw(
          drawAppliedRouteVersion: 5,
          currentAppliedRouteVersion: 6,
        ),
        isTrue,
      );
      expect(
        shouldIgnoreStaleRouteDraw(
          drawAppliedRouteVersion: 6,
          currentAppliedRouteVersion: 6,
        ),
        isFalse,
      );
    });

    test(
      '15: empty steps rejected for live purposes (no geo/instruction mismatch)',
      () {
        final clock = DriverRouteRequestGenerationClock();
        final gen = clock.begin();
        final emptySteps = _package(steps: const <DriverNavStep>[]);
        final live = evaluateDriverRouteAcceptance(
          context: _ctx(
            generation: gen,
            purpose: DriverRouteApplyPurpose.destination,
            tripId: 'T1',
          ),
          snapshot: _snap(latest: gen),
          package: emptySteps,
        );
        expect(live.accepted, isFalse);
        expect(live.reason, DriverRouteRejectReason.emptySteps);

        final overview = evaluateDriverRouteAcceptance(
          context: _ctx(
            generation: gen,
            purpose: DriverRouteApplyPurpose.overview,
            bookingId: 'B1',
            tripId: null,
          ),
          snapshot: _snap(latest: gen, tripId: null, liveRideActive: false),
          package: emptySteps,
        );
        expect(overview.accepted, isTrue);
      },
    );
  });

  group('purpose / session gates', () {
    test('direct ride requires active direct session', () {
      final clock = DriverRouteRequestGenerationClock();
      final gen = clock.begin();
      final decision = evaluateDriverRouteAcceptance(
        context: _ctx(
          generation: gen,
          purpose: DriverRouteApplyPurpose.direct,
          bookingId: null,
          requireDirectRide: true,
          expectDirectRideActive: true,
        ),
        snapshot: _snap(
          latest: gen,
          bookingId: null,
          tripId: null,
          directRideActive: false,
          liveRideActive: false,
        ),
        package: _package(),
      );
      expect(decision.accepted, isFalse);
      expect(decision.reason, DriverRouteRejectReason.sessionChanged);
    });

    test('pickup rejected once trip session exists', () {
      final clock = DriverRouteRequestGenerationClock();
      final gen = clock.begin();
      final decision = evaluateDriverRouteAcceptance(
        context: _ctx(
          generation: gen,
          purpose: DriverRouteApplyPurpose.pickup,
          tripId: null,
        ),
        snapshot: _snap(latest: gen, tripId: 'T1', liveRideActive: true),
        package: _package(),
      );
      expect(decision.accepted, isFalse);
      expect(decision.reason, DriverRouteRejectReason.phaseChanged);
    });
  });
}
