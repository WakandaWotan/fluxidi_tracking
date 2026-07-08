import 'dart:math' as math;

import 'nav_route_progress.dart';

/// NAV-R17A: bounded off-route / reroute decision helpers shared by the
/// driver UI and replay harness. No coordinates or PII.
class NavRerouteDecisionConfig {
  static const Duration rerouteCooldown = Duration(seconds: 25);
  static const Duration rerouteCooldownRouteDeviation = Duration(seconds: 8);
  static const Duration rerouteFailedRetryBackoff = Duration(seconds: 3);

  static const Duration debounceStrongOpposite = Duration(milliseconds: 500);
  static const Duration debounceRouteDeviation = Duration(milliseconds: 700);
  static const Duration debounceSnapLowConfidence = Duration(milliseconds: 1200);
  static const Duration debounceSnapMedium = Duration(milliseconds: 1800);
  static const Duration debounceDefault = Duration(milliseconds: 2500);

  static const double minMovementSpeedKmh = 5.0;
  static const double minDeviationSpeedKmh = 8.0;
  static const double parkingSpeedKmh = 3.0;
}

/// Input for one reroute decision tick.
class NavRerouteDecisionTickInput {
  final NavRouteProgressOutput progress;
  final double snapDistanceM;
  final double speedKmh;
  final double offRouteThresholdM;
  final bool useProgressOffRouteHits;
  final DateTime now;
  final DateTime? lastRerouteAt;
  final bool lastRerouteFailed;
  final bool allowReroutePhase;
  final bool liveRideActive;
  final bool isWaiting;
  final bool isRerouting;
  final bool hasRoute;

  const NavRerouteDecisionTickInput({
    required this.progress,
    required this.snapDistanceM,
    required this.speedKmh,
    required this.offRouteThresholdM,
    this.useProgressOffRouteHits = true,
    required this.now,
    this.lastRerouteAt,
    this.lastRerouteFailed = false,
    this.allowReroutePhase = true,
    this.liveRideActive = true,
    this.isWaiting = false,
    this.isRerouting = false,
    this.hasRoute = true,
  });
}

/// Output for one reroute decision tick.
class NavRerouteDecisionTickOutput {
  final bool offRouteLikely;
  final String offRouteReason;
  final int offRouteHitCount;
  final int hitsRequired;
  final int samplesOffRoute;
  final bool eligible;
  final bool cooldownActive;
  final bool movementOk;
  final bool shouldTrigger;
  final Duration debounceRequired;
  final bool debounceStarted;

  const NavRerouteDecisionTickOutput({
    required this.offRouteLikely,
    required this.offRouteReason,
    required this.offRouteHitCount,
    required this.hitsRequired,
    required this.samplesOffRoute,
    required this.eligible,
    required this.cooldownActive,
    required this.movementOk,
    required this.shouldTrigger,
    required this.debounceRequired,
    required this.debounceStarted,
  });
}

/// Stateful off-route hit / reroute gate tracker.
class NavRerouteDecisionTracker {
  int offRouteHitCount = 0;
  bool offRouteLikely = false;
  String offRouteReason = 'none';
  int samplesOffRoute = 0;
  int snapDistanceIncreaseStreak = 0;
  double? lastSnapDistanceM;
  DateTime? debounceStartedAt;

  void reset() {
    offRouteHitCount = 0;
    offRouteLikely = false;
    offRouteReason = 'none';
    samplesOffRoute = 0;
    snapDistanceIncreaseStreak = 0;
    lastSnapDistanceM = null;
    debounceStartedAt = null;
  }

  NavRerouteDecisionTickOutput update(NavRerouteDecisionTickInput input) {
    final progress = input.progress;
    final snapDistance = input.snapDistanceM;

    if (input.useProgressOffRouteHits) {
      if (progress.offRouteLikely) {
        offRouteHitCount += 1;
      } else if (progress.hasReliableSnap) {
        offRouteHitCount = 0;
      } else if (snapDistance > input.offRouteThresholdM) {
        offRouteHitCount += 1;
      } else {
        offRouteHitCount = 0;
      }
    } else if (snapDistance > input.offRouteThresholdM || progress.offRouteLikely) {
      offRouteHitCount += 1;
    } else {
      offRouteHitCount = 0;
    }

    if (progress.offRouteLikely) {
      samplesOffRoute += 1;
    } else if (progress.hasReliableSnap) {
      samplesOffRoute = 0;
    }

    final prevSnap = lastSnapDistanceM;
    if (prevSnap != null &&
        snapDistance.isFinite &&
        snapDistance > prevSnap + 4.0 &&
        (progress.offRouteLikely || snapDistance > 55.0)) {
      snapDistanceIncreaseStreak += 1;
    } else if (progress.hasReliableSnap && !progress.offRouteLikely) {
      snapDistanceIncreaseStreak = 0;
    }
    lastSnapDistanceM = snapDistance.isFinite ? snapDistance : prevSnap;

    final oppositeDirection = progress.oppositeDirectionLikely;
    final strongOppositeDirection =
        progress.routeDeviationReason == 'opposite_heading_strong';
    final backwardProgress = progress.backwardProgressLikely;
    final routeDeviation = progress.routeDeviationLikely;

    final hitsRequired = navRerouteHitsRequired(
      strongOppositeDirection: strongOppositeDirection,
      routeDeviation: routeDeviation,
      backwardProgress: backwardProgress,
      oppositeDirection: oppositeDirection,
      progressOffRouteLikely: progress.offRouteLikely,
      snapDistanceM: snapDistance,
      snapDistanceIncreaseStreak: snapDistanceIncreaseStreak,
    );

    final offRoute = offRouteHitCount >= hitsRequired;
    final reason = offRoute
        ? navRerouteOffRouteReason(
            oppositeDirection: oppositeDirection,
            strongOppositeDirection: strongOppositeDirection,
            backwardProgress: backwardProgress,
          )
        : 'none';

    if (offRoute != offRouteLikely) {
      offRouteLikely = offRoute;
      offRouteReason = reason;
      if (!offRoute) {
        debounceStartedAt = null;
      }
    } else if (offRoute) {
      offRouteReason = reason;
    } else {
      offRouteReason = 'none';
    }

    final cooldown = navRerouteCooldownFor(
      offRouteReason: offRouteReason,
      lastRerouteFailed: input.lastRerouteFailed,
    );
    final cooldownActive =
        input.lastRerouteAt != null &&
        input.now.difference(input.lastRerouteAt!) < cooldown;

    final movementOk = navRerouteMovementOk(
      speedKmh: input.speedKmh,
      offRouteReason: offRouteReason,
      routeDeviationLikely: routeDeviation,
      samplesOffRoute: samplesOffRoute,
      offRouteLikely: offRouteLikely,
    );

    final eligible =
        offRouteLikely &&
        movementOk &&
        !cooldownActive &&
        input.allowReroutePhase &&
        input.liveRideActive &&
        !input.isWaiting &&
        !input.isRerouting &&
        input.hasRoute;

    final debounceRequired = navRerouteDebounceFor(
      offRouteReason: offRouteReason,
      progress: progress,
    );

    var debounceStarted = false;
    var shouldTrigger = false;
    if (eligible) {
      final start = debounceStartedAt ?? input.now;
      debounceStartedAt = start;
      debounceStarted = debounceStartedAt == input.now;
      if (input.now.difference(start) >= debounceRequired) {
        shouldTrigger = true;
        debounceStartedAt = null;
      }
    } else if (!offRouteLikely) {
      debounceStartedAt = null;
    }

    return NavRerouteDecisionTickOutput(
      offRouteLikely: offRouteLikely,
      offRouteReason: offRouteReason,
      offRouteHitCount: offRouteHitCount,
      hitsRequired: hitsRequired,
      samplesOffRoute: samplesOffRoute,
      eligible: eligible,
      cooldownActive: cooldownActive,
      movementOk: movementOk,
      shouldTrigger: shouldTrigger,
      debounceRequired: debounceRequired,
      debounceStarted: debounceStarted,
    );
  }

  void noteRerouteApplied(DateTime now) {
    debounceStartedAt = null;
    offRouteHitCount = 0;
    offRouteLikely = false;
    offRouteReason = 'none';
    samplesOffRoute = 0;
    snapDistanceIncreaseStreak = 0;
  }
}

int navRerouteHitsRequired({
  required bool strongOppositeDirection,
  required bool routeDeviation,
  required bool backwardProgress,
  required bool oppositeDirection,
  required bool progressOffRouteLikely,
  required double snapDistanceM,
  required int snapDistanceIncreaseStreak,
}) {
  if (strongOppositeDirection) return 1;
  if (routeDeviation && backwardProgress && oppositeDirection) return 1;
  if (routeDeviation && backwardProgress) return 1;
  if (routeDeviation) return 2;
  if (progressOffRouteLikely && snapDistanceIncreaseStreak >= 2) return 2;
  if (progressOffRouteLikely || snapDistanceM > 55.0) return 2;
  return 3;
}

String navRerouteOffRouteReason({
  required bool oppositeDirection,
  required bool strongOppositeDirection,
  required bool backwardProgress,
}) {
  if (oppositeDirection) {
    return strongOppositeDirection
        ? 'opposite_direction_strong'
        : 'opposite_direction';
  }
  if (backwardProgress) return 'backward_progress';
  return 'snap_distance';
}

bool navRerouteIsRouteDeviationReason(String reason) {
  return reason == 'opposite_direction' ||
      reason == 'opposite_direction_strong' ||
      reason == 'backward_progress';
}

Duration navRerouteCooldownFor({
  required String offRouteReason,
  required bool lastRerouteFailed,
}) {
  if (lastRerouteFailed) {
    return NavRerouteDecisionConfig.rerouteFailedRetryBackoff;
  }
  if (navRerouteIsRouteDeviationReason(offRouteReason)) {
    return NavRerouteDecisionConfig.rerouteCooldownRouteDeviation;
  }
  return NavRerouteDecisionConfig.rerouteCooldown;
}

Duration navRerouteDebounceFor({
  required String offRouteReason,
  required NavRouteProgressOutput progress,
}) {
  if (offRouteReason == 'opposite_direction_strong') {
    return NavRerouteDecisionConfig.debounceStrongOpposite;
  }
  if (navRerouteIsRouteDeviationReason(offRouteReason)) {
    return NavRerouteDecisionConfig.debounceRouteDeviation;
  }
  if (progress.offRouteLikely) {
    final snapDist = progress.snapDistanceM;
    final conf = progress.confidence;
    if (snapDist > 55.0 && conf < 45.0) {
      return NavRerouteDecisionConfig.debounceSnapLowConfidence;
    }
    if (snapDist > 45.0 || conf < 55.0) {
      return NavRerouteDecisionConfig.debounceSnapMedium;
    }
  }
  return NavRerouteDecisionConfig.debounceDefault;
}

bool navRerouteMovementOk({
  required double speedKmh,
  required String offRouteReason,
  required bool routeDeviationLikely,
  required int samplesOffRoute,
  required bool offRouteLikely,
}) {
  if (!offRouteLikely) return false;
  if (routeDeviationLikely &&
      speedKmh >= NavRerouteDecisionConfig.minDeviationSpeedKmh) {
    return true;
  }
  if (offRouteReason == 'opposite_direction_strong' &&
      speedKmh >= NavRerouteDecisionConfig.minMovementSpeedKmh) {
    return true;
  }
  if (navRerouteIsRouteDeviationReason(offRouteReason) &&
      speedKmh >= NavRerouteDecisionConfig.minMovementSpeedKmh &&
      samplesOffRoute >= 2) {
    return true;
  }
  if (speedKmh >= NavRerouteDecisionConfig.minMovementSpeedKmh) return true;
  if (speedKmh < NavRerouteDecisionConfig.parkingSpeedKmh &&
      offRouteReason == 'snap_distance') {
    return false;
  }
  if (speedKmh < NavRerouteDecisionConfig.parkingSpeedKmh) {
    return routeDeviationLikely && samplesOffRoute >= 3;
  }
  return samplesOffRoute >= 2;
}

String navRerouteHeadingDeltaBucket(double? headingDeltaDeg) {
  if (headingDeltaDeg == null || !headingDeltaDeg.isFinite) return 'na';
  final abs = headingDeltaDeg.abs();
  if (abs < 45.0) return '0-45';
  if (abs < 90.0) return '45-90';
  if (abs < 135.0) return '90-135';
  return '135-180';
}

String navRerouteDistanceBucket(double snapDistanceM) {
  if (!snapDistanceM.isFinite) return 'inf';
  if (snapDistanceM < 15.0) return '0-15';
  if (snapDistanceM < 30.0) return '15-30';
  if (snapDistanceM < 60.0) return '30-60';
  if (snapDistanceM < 100.0) return '60-100';
  return '100+';
}

String navRerouteMovementBucket(double speedKmh) {
  final speed = math.max(0.0, speedKmh);
  if (speed < 3.0) return 'stopped';
  if (speed < 8.0) return 'slow';
  if (speed < 30.0) return 'city';
  if (speed < 60.0) return 'urban';
  return 'highway';
}
