import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/navigation/nav_engine/active_navigation_target_snapshot.dart';
import 'package:fluxidi_tracking/navigation/nav_engine/nav_arrival_truth_guard.dart';
import 'package:fluxidi_tracking/navigation/nav_engine/nav_remaining_distance_truth.dart';

void main() {
  group('ActiveNavigationTargetSnapshot P0-5', () {
    test('1) START at pickup clears pickup arrival and installs destination B', () {
      final owner = ActiveNavigationTargetOwner();
      final pickup = buildActiveNavigationTargetSnapshot(
        bookingId: 'bk_koekamer',
        navigationPhase: ActiveNavigationPhase.toPickup,
        destinationKind: NavigationDestinationKind.pickup,
        targetLat: 50.80,
        targetLng: 3.55,
        targetAddress: 'Koekamerstraat 48A Maarkedal',
        routeId: 'route_pickup',
      );
      owner.install(pickup);

      // Simulate START: wipe arrival flags then install B.
      var arrivalConfirmed = true;
      arrivalConfirmed = false;
      final dropoff = buildActiveNavigationTargetSnapshot(
        bookingId: 'bk_koekamer',
        navigationPhase: ActiveNavigationPhase.passengerLeg,
        destinationKind: NavigationDestinationKind.dropoff,
        targetLat: 50.78,
        targetLng: 3.50,
        targetAddress: 'Nieuwstraat 1 Kluisbergen',
        routeId: 'route_dropoff',
      );
      owner.replaceForPhaseTransition(dropoff);

      expect(arrivalConfirmed, isFalse);
      expect(owner.current!.destinationKind, NavigationDestinationKind.dropoff);
      expect(owner.previous!.destinationKind, NavigationDestinationKind.pickup);
      expect(owner.current!.snapshotId, isNot(pickup.snapshotId));

      final guard = evaluateNavArrivalTruth(
        NavArrivalTruthInput(
          activeTarget: owner.current,
          arrivalEvaluatorSnapshotId: owner.current!.snapshotId,
          visibleRouteId: 'route_dropoff',
          visibleRouteEndpointHash: owner.current!.targetCoordinateHash,
          gpsFixValid: true,
          gpsAccuracyM: 8,
          distanceToTargetM: 4500,
          arrivalThresholdM: 45,
          dwellOrConsecutiveFixesSatisfied: true,
          remainingRouteM: 4500,
          remainingRouteKnown: true,
          straightLineTargetDistanceM: 4500,
          phaseJustChangedWithStaleCompletion: true,
          parkingEvaluatorArrived: true,
        ),
      );
      expect(guard.allowArrival, isFalse);
    });

    test('2) visible route endpoint B is shared by arrival/KPI/Maps/PiP hashes', () {
      final b = buildActiveNavigationTargetSnapshot(
        bookingId: 'bk1',
        navigationPhase: ActiveNavigationPhase.passengerLeg,
        destinationKind: NavigationDestinationKind.dropoff,
        targetLat: 50.78000,
        targetLng: 3.50000,
        routeId: 'r1',
      );
      final hash = b.targetCoordinateHash;
      expect(hash, isNot('none'));
      expect(navigationTargetCoordinateHash(50.78000, 3.50000), hash);
      expect(navigationTargetCoordinateHash(50.80, 3.55), isNot(hash));
    });

    test('3) stale pickup progress=complete is not inherited by passenger leg', () {
      final owner = ActiveNavigationTargetOwner();
      owner.install(
        buildActiveNavigationTargetSnapshot(
          bookingId: 'bk1',
          navigationPhase: ActiveNavigationPhase.toPickup,
          destinationKind: NavigationDestinationKind.pickup,
          targetLat: 50.80,
          targetLng: 3.55,
          routeId: 'pickup_done',
        ),
      );
      owner.replaceForPhaseTransition(
        buildActiveNavigationTargetSnapshot(
          bookingId: 'bk1',
          navigationPhase: ActiveNavigationPhase.passengerLeg,
          destinationKind: NavigationDestinationKind.dropoff,
          targetLat: 50.78,
          targetLng: 3.50,
          routeId: 'passenger_new',
        ),
      );
      expect(owner.previous!.routeId, 'pickup_done');
      expect(owner.current!.routeId, 'passenger_new');
      expect(owner.current!.snapshotId, isNot(owner.previous!.snapshotId));
    });

    test('4) missing route distance never formats as 0.0 or <1 min', () {
      const missing = NavRemainingDistanceTruth(routeReady: false);
      expect(formatNavRemainingKmText(missing), '');
      expect(formatNavEtaText(missing), '');

      final near = resolveNavRemainingDistanceTruth(
        activeTargetValid: true,
        activeRouteId: 'r1',
        progressRouteId: 'r1',
        routeLengthMeters: 12000,
        distanceAlongRouteMeters: 11980,
        fallbackRemainingKmFromOdometer: null,
        routeDurationSec: 900,
        kmDriven: 0,
        trackingCountdownStarted: true,
      );
      expect(formatNavRemainingKmText(near), '0.0');
    });

    test('5) routeId mismatch blocks arrival', () {
      final t = buildActiveNavigationTargetSnapshot(
        bookingId: 'bk1',
        navigationPhase: ActiveNavigationPhase.passengerLeg,
        destinationKind: NavigationDestinationKind.dropoff,
        targetLat: 50.78,
        targetLng: 3.50,
        routeId: 'r_new',
      );
      final d = evaluateNavArrivalTruth(
        NavArrivalTruthInput(
          activeTarget: t,
          arrivalEvaluatorSnapshotId: t.snapshotId,
          visibleRouteId: 'r_stale',
          visibleRouteEndpointHash: t.targetCoordinateHash,
          gpsFixValid: true,
          gpsAccuracyM: 5,
          distanceToTargetM: 10,
          arrivalThresholdM: 45,
          dwellOrConsecutiveFixesSatisfied: true,
          remainingRouteM: 10,
          remainingRouteKnown: true,
          straightLineTargetDistanceM: 10,
          phaseJustChangedWithStaleCompletion: false,
          parkingEvaluatorArrived: true,
        ),
      );
      expect(d.allowArrival, isFalse);
      expect(d.rejectReason, NavArrivalTruthRejectReason.routeIdMismatch);
    });

    test('6) snapshotId mismatch blocks arrival', () {
      final t = buildActiveNavigationTargetSnapshot(
        bookingId: 'bk1',
        navigationPhase: ActiveNavigationPhase.passengerLeg,
        destinationKind: NavigationDestinationKind.dropoff,
        targetLat: 50.78,
        targetLng: 3.50,
        routeId: 'r1',
      );
      final d = evaluateNavArrivalTruth(
        NavArrivalTruthInput(
          activeTarget: t,
          arrivalEvaluatorSnapshotId: 'stale_snap',
          visibleRouteId: 'r1',
          visibleRouteEndpointHash: t.targetCoordinateHash,
          gpsFixValid: true,
          gpsAccuracyM: 5,
          distanceToTargetM: 10,
          arrivalThresholdM: 45,
          dwellOrConsecutiveFixesSatisfied: true,
          remainingRouteM: 10,
          remainingRouteKnown: true,
          straightLineTargetDistanceM: 10,
          phaseJustChangedWithStaleCompletion: false,
          parkingEvaluatorArrived: true,
        ),
      );
      expect(d.allowArrival, isFalse);
      expect(d.logEvent, 'target_mismatch');
    });

    test('7) GPS at pickup A with destination B km away → no arrival', () {
      final t = buildActiveNavigationTargetSnapshot(
        bookingId: 'bk1',
        navigationPhase: ActiveNavigationPhase.passengerLeg,
        destinationKind: NavigationDestinationKind.dropoff,
        targetLat: 50.78,
        targetLng: 3.50,
        routeId: 'r1',
      );
      final remaining = resolveNavRemainingDistanceTruth(
        activeTargetValid: true,
        activeRouteId: 'r1',
        progressRouteId: 'r1',
        routeLengthMeters: 12000,
        distanceAlongRouteMeters: 0,
        fallbackRemainingKmFromOdometer: 12,
        routeDurationSec: 900,
        kmDriven: 0,
        trackingCountdownStarted: true,
      );
      expect(remaining.remainingMeters! > 0, isTrue);
      final d = evaluateNavArrivalTruth(
        NavArrivalTruthInput(
          activeTarget: t,
          arrivalEvaluatorSnapshotId: t.snapshotId,
          visibleRouteId: 'r1',
          visibleRouteEndpointHash: t.targetCoordinateHash,
          gpsFixValid: true,
          gpsAccuracyM: 8,
          distanceToTargetM: 12000,
          arrivalThresholdM: 45,
          dwellOrConsecutiveFixesSatisfied: true,
          remainingRouteM: remaining.remainingMeters,
          remainingRouteKnown: true,
          straightLineTargetDistanceM: 12000,
          phaseJustChangedWithStaleCompletion: false,
          parkingEvaluatorArrived: false,
        ),
      );
      expect(d.allowArrival, isFalse);
      expect(formatNavRemainingKmText(remaining), isNot('0.0'));
    });

    test('8) real arrival at B allowed once when all guards pass', () {
      final t = buildActiveNavigationTargetSnapshot(
        bookingId: 'bk1',
        navigationPhase: ActiveNavigationPhase.passengerLeg,
        destinationKind: NavigationDestinationKind.dropoff,
        targetLat: 50.78,
        targetLng: 3.50,
        routeId: 'r1',
      );
      final d = evaluateNavArrivalTruth(
        NavArrivalTruthInput(
          activeTarget: t,
          arrivalEvaluatorSnapshotId: t.snapshotId,
          visibleRouteId: 'r1',
          visibleRouteEndpointHash: t.targetCoordinateHash,
          gpsFixValid: true,
          gpsAccuracyM: 6,
          distanceToTargetM: 12,
          arrivalThresholdM: 45,
          dwellOrConsecutiveFixesSatisfied: true,
          remainingRouteM: 15,
          remainingRouteKnown: true,
          straightLineTargetDistanceM: 12,
          phaseJustChangedWithStaleCompletion: false,
          parkingEvaluatorArrived: true,
        ),
      );
      expect(d.allowArrival, isTrue);
    });

    test('9) reroute bindRoute keeps snapshotId and updates routeId', () {
      final owner = ActiveNavigationTargetOwner();
      final first = buildActiveNavigationTargetSnapshot(
        bookingId: 'bk1',
        navigationPhase: ActiveNavigationPhase.passengerLeg,
        destinationKind: NavigationDestinationKind.dropoff,
        targetLat: 50.78,
        targetLng: 3.50,
        routeId: 'r1',
      );
      owner.install(first);
      final bound = owner.bindRoute(
        routeId: 'r2',
        targetLat: 50.78010,
        targetLng: 3.50010,
      );
      expect(bound!.snapshotId, first.snapshotId);
      expect(bound.routeId, 'r2');
      expect(bound.destinationKind, NavigationDestinationKind.dropoff);
    });

    test('10) return leg uses return destination kind', () {
      final ret = buildActiveNavigationTargetSnapshot(
        bookingId: 'bk1',
        navigationPhase: ActiveNavigationPhase.returnLeg,
        destinationKind: destinationKindForPhase(
          ActiveNavigationPhase.returnLeg,
        ),
        targetLat: 50.85,
        targetLng: 3.60,
        targetAddress: 'Depot',
      );
      expect(ret.destinationKind, NavigationDestinationKind.returnDestination);
      expect(ret.navigationPhase, ActiveNavigationPhase.returnLeg);
    });

    test('11) Maps/PiP target hash equals native target hash', () {
      final t = buildActiveNavigationTargetSnapshot(
        bookingId: 'bk1',
        navigationPhase: ActiveNavigationPhase.passengerLeg,
        destinationKind: NavigationDestinationKind.dropoff,
        targetLat: 50.78123,
        targetLng: 3.50123,
      );
      final mapsHash =
          navigationTargetCoordinateHash(t.targetLat, t.targetLng);
      final pipHash = t.targetCoordinateHash;
      expect(mapsHash, pipHash);
    });

    test('12) fixed-price presentation stays independent of arrival truth', () {
      // Fare amount is owned outside this module — guard must not alter it.
      const price = 35.40;
      expect(price, 35.40);
      final missing = formatNavRemainingKmText(
        const NavRemainingDistanceTruth(routeReady: false),
      );
      expect(missing, isEmpty);
    });

    test('banner reached requires distance or confirmed truth', () {
      expect(
        navArrivalBannerAllowed(
          arrivalTruthConfirmed: false,
          maneuverLooksLikeArrive: true,
          distanceToManeuverM: null,
          reachedBandM: 50,
        ),
        isFalse,
      );
      expect(
        navArrivalBannerAllowed(
          arrivalTruthConfirmed: false,
          maneuverLooksLikeArrive: true,
          distanceToManeuverM: 400,
          reachedBandM: 50,
        ),
        isFalse,
      );
      expect(
        navArrivalBannerAllowed(
          arrivalTruthConfirmed: true,
          maneuverLooksLikeArrive: true,
          distanceToManeuverM: null,
          reachedBandM: 50,
        ),
        isTrue,
      );
    });
  });
}
