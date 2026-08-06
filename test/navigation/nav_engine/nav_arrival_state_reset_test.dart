// NAVIGATION-ARRIVAL-STATE-RESET-P0-5
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/navigation/nav_engine/active_navigation_target_snapshot.dart';
import 'package:fluxidi_tracking/navigation/nav_engine/nav_arrival_truth_guard.dart';

void main() {
  group('NAVIGATION-ARRIVAL-STATE-RESET-P0-5', () {
    test('pickup completion fields do not survive passenger snapshot install', () {
      final owner = ActiveNavigationTargetOwner();
      owner.install(
        buildActiveNavigationTargetSnapshot(
          bookingId: 'bk',
          navigationPhase: ActiveNavigationPhase.toPickup,
          destinationKind: NavigationDestinationKind.pickup,
          targetLat: 50.80,
          targetLng: 3.55,
          routeId: 'pickup',
        ),
      );
      var destinationReached = true;
      var remainingDistance = 0.0;
      var progressFraction = 1.0;
      var lastManeuver = 'arrive';

      // Atomic START transition contract.
      destinationReached = false;
      remainingDistance = double.nan; // unknown until passenger route ready
      progressFraction = 0.0;
      lastManeuver = '';
      owner.replaceForPhaseTransition(
        buildActiveNavigationTargetSnapshot(
          bookingId: 'bk',
          navigationPhase: ActiveNavigationPhase.passengerLeg,
          destinationKind: NavigationDestinationKind.dropoff,
          targetLat: 50.78,
          targetLng: 3.50,
          routeId: 'passenger',
        ),
      );

      expect(destinationReached, isFalse);
      expect(progressFraction, 0.0);
      expect(lastManeuver, isEmpty);
      expect(remainingDistance.isNaN, isTrue);
      expect(owner.current!.destinationKind, NavigationDestinationKind.dropoff);

      final blocked = evaluateNavArrivalTruth(
        NavArrivalTruthInput(
          activeTarget: owner.current,
          arrivalEvaluatorSnapshotId: owner.current!.snapshotId,
          visibleRouteId: 'passenger',
          visibleRouteEndpointHash: owner.current!.targetCoordinateHash,
          gpsFixValid: true,
          gpsAccuracyM: 8,
          distanceToTargetM: 5000,
          arrivalThresholdM: 45,
          dwellOrConsecutiveFixesSatisfied: true,
          remainingRouteM: null,
          remainingRouteKnown: false,
          straightLineTargetDistanceM: 5000,
          phaseJustChangedWithStaleCompletion: true,
          parkingEvaluatorArrived: true,
        ),
      );
      expect(blocked.allowArrival, isFalse);
    });
  });
}
