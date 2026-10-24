// NAVIGATION-ARRIVAL-STATE-RESET-P0-5 /
// NAVIGATION-SINGLE-ACTIVE-TARGET-TRUTH-P0-5
//
// Arrival ("Bestemming bereikt") may fire only when the active target, visible
// route endpoint, GPS, remaining route and phase transition guards all agree.

import 'active_navigation_target_snapshot.dart';

enum NavArrivalTruthRejectReason {
  inactiveTarget,
  snapshotMismatch,
  targetEndpointMismatch,
  invalidGps,
  poorAccuracy,
  tooFarFromTarget,
  dwellNotSatisfied,
  routeIdMismatch,
  remainingUnknownOrStale,
  remainingZeroWithoutProximity,
  phaseTransitionStale,
  evaluatorNotArrived,
}

class NavArrivalTruthInput {
  const NavArrivalTruthInput({
    required this.activeTarget,
    required this.arrivalEvaluatorSnapshotId,
    required this.visibleRouteId,
    required this.visibleRouteEndpointHash,
    required this.gpsFixValid,
    required this.gpsAccuracyM,
    required this.distanceToTargetM,
    required this.arrivalThresholdM,
    required this.dwellOrConsecutiveFixesSatisfied,
    required this.remainingRouteM,
    required this.remainingRouteKnown,
    required this.straightLineTargetDistanceM,
    required this.phaseJustChangedWithStaleCompletion,
    required this.parkingEvaluatorArrived,
    this.maxAccuracyM = 35.0,
  });

  final ActiveNavigationTargetSnapshot? activeTarget;
  final String? arrivalEvaluatorSnapshotId;
  final String? visibleRouteId;
  final String? visibleRouteEndpointHash;
  final bool gpsFixValid;
  final double? gpsAccuracyM;
  final double? distanceToTargetM;
  final double arrivalThresholdM;
  final bool dwellOrConsecutiveFixesSatisfied;
  final double? remainingRouteM;
  final bool remainingRouteKnown;
  final double? straightLineTargetDistanceM;
  final bool phaseJustChangedWithStaleCompletion;
  final bool parkingEvaluatorArrived;
  final double maxAccuracyM;
}

class NavArrivalTruthDecision {
  const NavArrivalTruthDecision({
    required this.allowArrival,
    this.rejectReason,
    this.logEvent,
  });

  final bool allowArrival;
  final NavArrivalTruthRejectReason? rejectReason;

  /// Safe diagnostic token for logs (no PII).
  final String? logEvent;

  static const blocked = NavArrivalTruthDecision(allowArrival: false);
}

/// Pure arrival gate. Never throws.
NavArrivalTruthDecision evaluateNavArrivalTruth(NavArrivalTruthInput input) {
  final target = input.activeTarget;
  if (target == null || !target.isValid) {
    return const NavArrivalTruthDecision(
      allowArrival: false,
      rejectReason: NavArrivalTruthRejectReason.inactiveTarget,
      logEvent: 'target_inactive',
    );
  }

  if (input.phaseJustChangedWithStaleCompletion) {
    return const NavArrivalTruthDecision(
      allowArrival: false,
      rejectReason: NavArrivalTruthRejectReason.phaseTransitionStale,
      logEvent: 'phase_transition_stale_completion',
    );
  }

  final evalSnap = (input.arrivalEvaluatorSnapshotId ?? '').trim();
  if (evalSnap.isEmpty || evalSnap != target.snapshotId) {
    return const NavArrivalTruthDecision(
      allowArrival: false,
      rejectReason: NavArrivalTruthRejectReason.snapshotMismatch,
      logEvent: 'target_mismatch',
    );
  }

  final routeId = (target.routeId ?? '').trim();
  final visibleRouteId = (input.visibleRouteId ?? '').trim();
  if (routeId.isNotEmpty &&
      visibleRouteId.isNotEmpty &&
      routeId != visibleRouteId) {
    return const NavArrivalTruthDecision(
      allowArrival: false,
      rejectReason: NavArrivalTruthRejectReason.routeIdMismatch,
      logEvent: 'route_id_mismatch',
    );
  }

  final targetHash = target.targetCoordinateHash;
  final endpointHash = (input.visibleRouteEndpointHash ?? '').trim();
  if (targetHash == 'none' ||
      endpointHash.isEmpty ||
      endpointHash == 'none' ||
      targetHash != endpointHash) {
    return const NavArrivalTruthDecision(
      allowArrival: false,
      rejectReason: NavArrivalTruthRejectReason.targetEndpointMismatch,
      logEvent: 'target_mismatch',
    );
  }

  if (!input.gpsFixValid) {
    return const NavArrivalTruthDecision(
      allowArrival: false,
      rejectReason: NavArrivalTruthRejectReason.invalidGps,
      logEvent: 'gps_invalid',
    );
  }

  final accuracy = input.gpsAccuracyM;
  if (accuracy == null ||
      !accuracy.isFinite ||
      accuracy < 0 ||
      accuracy > input.maxAccuracyM) {
    return const NavArrivalTruthDecision(
      allowArrival: false,
      rejectReason: NavArrivalTruthRejectReason.poorAccuracy,
      logEvent: 'gps_accuracy',
    );
  }

  if (!input.remainingRouteKnown ||
      input.remainingRouteM == null ||
      !input.remainingRouteM!.isFinite) {
    // Missing/stale remaining must never be treated as 0 → arrival.
    return const NavArrivalTruthDecision(
      allowArrival: false,
      rejectReason: NavArrivalTruthRejectReason.remainingUnknownOrStale,
      logEvent: 'remaining_unknown',
    );
  }

  final distance = input.distanceToTargetM;
  if (distance == null || !distance.isFinite) {
    return const NavArrivalTruthDecision(
      allowArrival: false,
      rejectReason: NavArrivalTruthRejectReason.tooFarFromTarget,
      logEvent: 'distance_unknown',
    );
  }

  if (distance > input.arrivalThresholdM) {
    return const NavArrivalTruthDecision(
      allowArrival: false,
      rejectReason: NavArrivalTruthRejectReason.tooFarFromTarget,
      logEvent: 'too_far',
    );
  }

  // remainingDistance=0 alone (stale/missing route) is never enough — require
  // real proximity to the active target.
  if (input.remainingRouteM! <= 0.01 &&
      distance > input.arrivalThresholdM) {
    return const NavArrivalTruthDecision(
      allowArrival: false,
      rejectReason: NavArrivalTruthRejectReason.remainingZeroWithoutProximity,
      logEvent: 'remaining_zero_stale',
    );
  }

  final straight = input.straightLineTargetDistanceM;
  if (straight != null &&
      straight.isFinite &&
      straight > input.arrivalThresholdM * 4) {
    // GPS still far from B while remaining collapsed — classic pickup/A stale.
    return const NavArrivalTruthDecision(
      allowArrival: false,
      rejectReason: NavArrivalTruthRejectReason.tooFarFromTarget,
      logEvent: 'straight_line_far',
    );
  }

  if (!input.dwellOrConsecutiveFixesSatisfied) {
    return const NavArrivalTruthDecision(
      allowArrival: false,
      rejectReason: NavArrivalTruthRejectReason.dwellNotSatisfied,
      logEvent: 'dwell_pending',
    );
  }

  if (!input.parkingEvaluatorArrived) {
    return const NavArrivalTruthDecision(
      allowArrival: false,
      rejectReason: NavArrivalTruthRejectReason.evaluatorNotArrived,
      logEvent: 'evaluator_not_arrived',
    );
  }

  return const NavArrivalTruthDecision(
    allowArrival: true,
    logEvent: 'arrival_allowed',
  );
}

/// Banner / sign "reached" may only follow confirmed arrival truth.
bool navArrivalBannerAllowed({
  required bool arrivalTruthConfirmed,
  required bool maneuverLooksLikeArrive,
  required double? distanceToManeuverM,
  required double reachedBandM,
}) {
  if (arrivalTruthConfirmed) return true;
  if (!maneuverLooksLikeArrive) return false;
  if (distanceToManeuverM == null || !distanceToManeuverM.isFinite) {
    // Missing distance must never become "Bestemming bereikt".
    return false;
  }
  return distanceToManeuverM <= reachedBandM;
}
