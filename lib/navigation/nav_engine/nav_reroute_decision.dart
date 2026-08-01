import 'dart:math' as math;

import 'nav_route_progress.dart';

/// NAV-R17A / NAV-REROUTE-P0: bounded off-route / reroute decision helpers.
/// Shared by the driver UI and replay harness. No coordinates or PII.
class NavRerouteDecisionConfig {
  /// Anti-thrash after a successful reroute (not used for first deviation).
  static const Duration successfulRerouteCooldown = Duration(seconds: 12);

  /// Opposite-direction / backtrack anti-thrash.
  static const Duration rerouteCooldownRouteDeviation = Duration(seconds: 8);

  /// Failed-request retry backoff.
  static const Duration rerouteFailedRetryBackoff = Duration(seconds: 3);

  /// Brief grace after an initial route accept (not a reroute).
  static const Duration startupGrace = Duration(seconds: 2);

  /// Legacy alias retained for existing call sites / tests.
  static const Duration rerouteCooldown = successfulRerouteCooldown;

  static const Duration debounceStrongOpposite = Duration(milliseconds: 500);
  static const Duration debounceRouteDeviation = Duration(milliseconds: 700);
  static const Duration debounceWrongStreetConfirmed = Duration.zero;
  static const Duration debounceWrongStreetConfirm = Duration(milliseconds: 250);
  static const Duration debounceStrongUrban = Duration(milliseconds: 500);
  static const Duration debounceSnapLowConfidence = Duration(
    milliseconds: 1200,
  );
  static const Duration debounceSnapMedium = Duration(milliseconds: 1800);
  static const Duration debounceDefault = Duration(milliseconds: 2500);

  static const double minMovementSpeedKmh = 5.0;
  static const double minDeviationSpeedKmh = 8.0;
  static const double parkingSpeedKmh = 3.0;

  /// RELEASE-P0: crawl floor for confirmed strong opposite only.
  /// Does not lower the global deviation / wrong-street speed floors.
  static const double minStrongOppositeCrawlSpeedKmh = 1.5;
  static const int strongOppositeCrawlMinSamples = 2;
  static const double strongOppositeHeadingDeg = 135.0;

  /// Primary fast path: confirmed wrong outgoing street after a junction.
  /// Detection is heading + unmatched geometry — not an 80–120 m snap wait.
  static const double wrongStreetMinSpeedKmh = 12.0;
  static const double wrongStreetMaxSpeedKmh = 70.0;
  static const double wrongStreetMinSnapM = 10.0;
  static const double wrongStreetClearSnapM = 15.0;
  static const double wrongStreetParallelLaneMaxSnapM = 8.0;
  static const double wrongStreetHeadingMinDeg = 55.0;
  static const double wrongStreetHeadingStrongDeg = 70.0;
  static const double wrongStreetNearManeuverM = 40.0;
  static const int wrongStreetConfirmSamples = 2;

  /// Secondary fallback only: large unmatched snap while moving (no heading).
  static const double strongEvidenceMinSpeedKmh = 20.0;
  static const double strongEvidenceMaxSpeedKmh = 55.0;
  static const double strongEvidenceMinSnapM = 80.0;
  static const double severeEvidenceMinSnapM = 110.0;
  static const double goodAccuracyMaxM = 15.0;
  static const Duration strongEvidenceMinDuration = Duration(milliseconds: 1500);
  static const int strongEvidenceMinSamples = 2;
  static const int severeEvidenceMinSamples = 2;
}

/// Why a reroute attempt is currently blocked (if at all).
enum NavRerouteCooldownKind {
  none,
  requestInFlight,
  startupGrace,
  successfulReroute,
  failedRetry,
}

/// Input for one reroute decision tick.
class NavRerouteDecisionTickInput {
  final NavRouteProgressOutput progress;
  final double snapDistanceM;
  final double speedKmh;
  final double offRouteThresholdM;
  final bool useProgressOffRouteHits;
  final DateTime now;

  /// When the latest reroute *request* started (in-flight or completed).
  final DateTime? lastRerouteAt;

  /// When the latest reroute was accepted (route version advanced).
  final DateTime? lastRerouteSuccessAt;

  /// When the latest reroute attempt failed.
  final DateTime? lastRerouteFailureAt;

  /// When the current accepted route package was activated.
  final DateTime? routeAcceptedAt;

  /// Horizontal GPS accuracy meters when known.
  final double? accuracyM;

  /// Distance to the active maneuver when known (junction proximity).
  final double? distanceToManeuverM;

  final bool lastRerouteFailed;
  final bool allowReroutePhase;
  final bool liveRideActive;
  final bool isWaiting;
  final bool isRerouting;
  final bool hasRoute;
  final int routeVersion;

  const NavRerouteDecisionTickInput({
    required this.progress,
    required this.snapDistanceM,
    required this.speedKmh,
    required this.offRouteThresholdM,
    this.useProgressOffRouteHits = true,
    required this.now,
    this.lastRerouteAt,
    this.lastRerouteSuccessAt,
    this.lastRerouteFailureAt,
    this.routeAcceptedAt,
    this.accuracyM,
    this.distanceToManeuverM,
    this.lastRerouteFailed = false,
    this.allowReroutePhase = true,
    this.liveRideActive = true,
    this.isWaiting = false,
    this.isRerouting = false,
    this.hasRoute = true,
    this.routeVersion = 0,
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
  final NavRerouteCooldownKind cooldownKind;
  final int cooldownRemainingMs;
  final bool fastPathEligible;
  final String blockedReason;
  final int strongSampleCount;
  final int wrongStreetSampleCount;
  final bool wrongStreetFastPath;
  final int? firstStrongEvidenceAgeMs;
  final int? strongEvidenceDurationMs;
  final bool requestInFlight;
  final int routeVersion;

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
    this.cooldownKind = NavRerouteCooldownKind.none,
    this.cooldownRemainingMs = 0,
    this.fastPathEligible = false,
    this.blockedReason = 'none',
    this.strongSampleCount = 0,
    this.wrongStreetSampleCount = 0,
    this.wrongStreetFastPath = false,
    this.firstStrongEvidenceAgeMs,
    this.strongEvidenceDurationMs,
    this.requestInFlight = false,
    this.routeVersion = 0,
  });
}

class NavRerouteCooldownEval {
  final NavRerouteCooldownKind kind;
  final bool active;
  final int remainingMs;
  final bool fastPathEligible;
  final String blockedReason;

  const NavRerouteCooldownEval({
    required this.kind,
    required this.active,
    required this.remainingMs,
    required this.fastPathEligible,
    required this.blockedReason,
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

  DateTime? firstStrongEvidenceAt;
  DateTime? lastStrongEvidenceAt;
  int strongSampleCount = 0;
  int wrongStreetSampleCount = 0;

  void reset() {
    offRouteHitCount = 0;
    offRouteLikely = false;
    offRouteReason = 'none';
    samplesOffRoute = 0;
    snapDistanceIncreaseStreak = 0;
    lastSnapDistanceM = null;
    debounceStartedAt = null;
    firstStrongEvidenceAt = null;
    lastStrongEvidenceAt = null;
    strongSampleCount = 0;
    wrongStreetSampleCount = 0;
  }

  NavRerouteDecisionTickOutput update(NavRerouteDecisionTickInput input) {
    final progress = input.progress;
    final snapDistance = input.snapDistanceM;
    final prevSnap = lastSnapDistanceM;

    final preliminaryGrowing =
        prevSnap != null &&
        snapDistance.isFinite &&
        snapDistance > prevSnap + 2.0;

    final wrongStreetEval = navRerouteEvaluateWrongStreet(
      progress: progress,
      snapDistanceM: snapDistance,
      speedKmh: input.speedKmh,
      accuracyM: input.accuracyM,
      distanceToManeuverM: input.distanceToManeuverM,
      snapGrowing: preliminaryGrowing || snapDistanceIncreaseStreak >= 1,
      wrongStreetSampleCount: wrongStreetSampleCount,
    );

    var hitThisTick = false;
    if (input.useProgressOffRouteHits) {
      if (progress.offRouteLikely || wrongStreetEval.observation) {
        offRouteHitCount += 1;
        hitThisTick = true;
      } else if (progress.hasReliableSnap) {
        offRouteHitCount = 0;
      } else if (snapDistance > input.offRouteThresholdM) {
        offRouteHitCount += 1;
        hitThisTick = true;
      } else {
        offRouteHitCount = 0;
      }
    } else if (snapDistance > input.offRouteThresholdM ||
        progress.offRouteLikely ||
        wrongStreetEval.observation) {
      offRouteHitCount += 1;
      hitThisTick = true;
    } else {
      offRouteHitCount = 0;
    }

    if (progress.offRouteLikely || wrongStreetEval.observation) {
      samplesOffRoute += 1;
    } else if (progress.hasReliableSnap) {
      samplesOffRoute = 0;
    }

    if (prevSnap != null &&
        snapDistance.isFinite &&
        snapDistance > prevSnap + 2.0 &&
        (progress.offRouteLikely ||
            wrongStreetEval.observation ||
            snapDistance > NavRerouteDecisionConfig.wrongStreetMinSnapM)) {
      snapDistanceIncreaseStreak += 1;
    } else if (progress.hasReliableSnap &&
        !progress.offRouteLikely &&
        !wrongStreetEval.observation) {
      snapDistanceIncreaseStreak = 0;
    }
    lastSnapDistanceM = snapDistance.isFinite ? snapDistance : prevSnap;

    final growing =
        snapDistanceIncreaseStreak >= 1 ||
        (prevSnap != null &&
            snapDistance.isFinite &&
            snapDistance >= prevSnap);

    if (wrongStreetEval.observation) {
      wrongStreetSampleCount += 1;
      firstStrongEvidenceAt ??= input.now;
      lastStrongEvidenceAt = input.now;
    } else if (progress.hasReliableSnap &&
        !progress.offRouteLikely &&
        !hitThisTick) {
      wrongStreetSampleCount = 0;
    }

    final oppositeDirection = progress.oppositeDirectionLikely;
    final strongOppositeDirection =
        progress.routeDeviationReason == 'opposite_heading_strong';
    final backwardProgress = progress.backwardProgressLikely;
    final routeDeviation = progress.routeDeviationLikely;

    final wrongStreetConfirmed = navRerouteWrongStreetConfirmed(
      eval: wrongStreetEval,
      wrongStreetSampleCount: wrongStreetSampleCount,
      snapDistanceM: snapDistance,
      snapGrowing: growing,
    );

    final hitsRequired = navRerouteHitsRequired(
      strongOppositeDirection: strongOppositeDirection,
      routeDeviation: routeDeviation,
      backwardProgress: backwardProgress,
      oppositeDirection: oppositeDirection,
      progressOffRouteLikely: progress.offRouteLikely,
      snapDistanceM: snapDistance,
      snapDistanceIncreaseStreak: snapDistanceIncreaseStreak,
      wrongStreetConfirmed: wrongStreetConfirmed,
      wrongStreetObservation: wrongStreetEval.observation,
    );

    final offRoute = offRouteHitCount >= hitsRequired;
    final reason = offRoute
        ? navRerouteOffRouteReason(
            oppositeDirection: oppositeDirection,
            strongOppositeDirection: strongOppositeDirection,
            backwardProgress: backwardProgress,
            wrongStreet: wrongStreetEval.observation || wrongStreetConfirmed,
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

    // Secondary fallback: large snap without usable heading.
    final observationStrong = navRerouteIsStrongEvidenceObservation(
      progress: progress,
      snapDistanceM: snapDistance,
      speedKmh: input.speedKmh,
      accuracyM: input.accuracyM,
    );
    final observationSevere = navRerouteIsSevereEvidenceObservation(
      progress: progress,
      snapDistanceM: snapDistance,
      speedKmh: input.speedKmh,
      accuracyM: input.accuracyM,
    );

    if (observationStrong) {
      firstStrongEvidenceAt ??= input.now;
      lastStrongEvidenceAt = input.now;
      strongSampleCount += 1;
    } else if (progress.hasReliableSnap &&
        !progress.offRouteLikely &&
        !wrongStreetEval.observation) {
      if (strongSampleCount > 0 && wrongStreetSampleCount == 0) {
        firstStrongEvidenceAt = null;
        lastStrongEvidenceAt = null;
        strongSampleCount = 0;
      }
    }

    final strongDuration = firstStrongEvidenceAt == null
        ? Duration.zero
        : input.now.difference(firstStrongEvidenceAt!);

    final wrongStreetFastPath = wrongStreetConfirmed ||
        (wrongStreetSampleCount >=
                NavRerouteDecisionConfig.wrongStreetConfirmSamples &&
            wrongStreetEval.observation);
    final largeSnapFastPath = navRerouteStrongFastPathReady(
      strongSampleCount: strongSampleCount,
      strongEvidenceDuration: strongDuration,
      severe: observationSevere ||
          (observationStrong &&
              snapDistance >= NavRerouteDecisionConfig.severeEvidenceMinSnapM),
      growing: growing,
    );
    final fastPathReady = wrongStreetFastPath || largeSnapFastPath;

    final cooldownEval = navRerouteEvaluateCooldown(
      now: input.now,
      isRerouting: input.isRerouting,
      lastRerouteFailed: input.lastRerouteFailed,
      lastRerouteAt: input.lastRerouteAt,
      lastRerouteSuccessAt: input.lastRerouteSuccessAt,
      lastRerouteFailureAt: input.lastRerouteFailureAt,
      routeAcceptedAt: input.routeAcceptedAt,
      offRouteReason: offRouteReason,
      fastPathReady: fastPathReady,
      severeEvidence: wrongStreetFastPath ||
          observationSevere ||
          snapDistance >= NavRerouteDecisionConfig.severeEvidenceMinSnapM,
    );

    final movementOk = navRerouteMovementOk(
      speedKmh: input.speedKmh,
      offRouteReason: offRouteReason,
      routeDeviationLikely: routeDeviation || wrongStreetEval.observation,
      samplesOffRoute: samplesOffRoute,
      offRouteLikely: offRouteLikely,
    );
    final movementBlockReason = navRerouteMovementBlockedReason(
      speedKmh: input.speedKmh,
      offRouteReason: offRouteReason,
      routeDeviationLikely: routeDeviation || wrongStreetEval.observation,
      samplesOffRoute: samplesOffRoute,
      offRouteLikely: offRouteLikely,
      accuracyM: input.accuracyM,
      headingDeltaDeg: progress.headingDeltaDeg,
    );

    String blockedReason = 'none';
    if (!input.hasRoute) {
      blockedReason = 'no_route';
    } else if (!input.liveRideActive) {
      blockedReason = 'not_live';
    } else if (input.isWaiting) {
      blockedReason = 'waiting';
    } else if (!input.allowReroutePhase) {
      blockedReason = 'phase_not_allowed';
    } else if (input.isRerouting) {
      blockedReason = 'request_in_flight';
    } else if (wrongStreetEval.ambiguous &&
        !wrongStreetConfirmed &&
        !strongOppositeDirection &&
        !oppositeDirection) {
      blockedReason = 'junction_ambiguous';
    } else if (!offRouteLikely) {
      blockedReason = 'not_off_route';
    } else if (!movementOk) {
      blockedReason = movementBlockReason;
    } else if (cooldownEval.active) {
      blockedReason = cooldownEval.blockedReason == 'successful_reroute_cooldown' ||
              cooldownEval.blockedReason == 'failed_retry_backoff' ||
              cooldownEval.blockedReason == 'startup_grace'
          ? 'cooldown'
          : cooldownEval.blockedReason;
    }

    final eligible =
        offRouteLikely &&
        movementOk &&
        !cooldownEval.active &&
        input.allowReroutePhase &&
        input.liveRideActive &&
        !input.isWaiting &&
        !input.isRerouting &&
        input.hasRoute &&
        !(wrongStreetEval.ambiguous &&
            !wrongStreetConfirmed &&
            !strongOppositeDirection &&
            !oppositeDirection);

    final debounceRequired = navRerouteDebounceFor(
      offRouteReason: offRouteReason,
      progress: progress,
      fastPathReady: fastPathReady,
      strongEvidence: observationStrong,
      wrongStreetConfirmed: wrongStreetConfirmed,
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
      } else {
        blockedReason = 'debounce';
      }
    } else if (!offRouteLikely) {
      debounceStartedAt = null;
    }

    final firstAgeMs = firstStrongEvidenceAt == null
        ? null
        : input.now.difference(firstStrongEvidenceAt!).inMilliseconds;
    final strongDurMs = firstStrongEvidenceAt == null
        ? null
        : strongDuration.inMilliseconds;

    return NavRerouteDecisionTickOutput(
      offRouteLikely: offRouteLikely,
      offRouteReason: offRouteReason,
      offRouteHitCount: offRouteHitCount,
      hitsRequired: hitsRequired,
      samplesOffRoute: samplesOffRoute,
      eligible: eligible,
      cooldownActive: cooldownEval.active,
      movementOk: movementOk,
      shouldTrigger: shouldTrigger,
      debounceRequired: debounceRequired,
      debounceStarted: debounceStarted,
      cooldownKind: cooldownEval.kind,
      cooldownRemainingMs: cooldownEval.remainingMs,
      fastPathEligible: cooldownEval.fastPathEligible || fastPathReady,
      blockedReason: blockedReason,
      strongSampleCount: strongSampleCount,
      wrongStreetSampleCount: wrongStreetSampleCount,
      wrongStreetFastPath: wrongStreetFastPath,
      firstStrongEvidenceAgeMs: firstAgeMs,
      strongEvidenceDurationMs: strongDurMs,
      requestInFlight: input.isRerouting,
      routeVersion: input.routeVersion,
    );
  }

  void noteRerouteApplied(DateTime now) {
    debounceStartedAt = null;
    offRouteHitCount = 0;
    offRouteLikely = false;
    offRouteReason = 'none';
    samplesOffRoute = 0;
    snapDistanceIncreaseStreak = 0;
    lastSnapDistanceM = null;
    firstStrongEvidenceAt = null;
    lastStrongEvidenceAt = null;
    strongSampleCount = 0;
    wrongStreetSampleCount = 0;
  }
}

/// Per-tick wrong-street / junction-exit assessment (pure).
class NavRerouteWrongStreetEval {
  final bool observation;
  final bool ambiguous;
  final bool strongHeading;
  final bool nearOrPastManeuver;

  const NavRerouteWrongStreetEval({
    required this.observation,
    required this.ambiguous,
    required this.strongHeading,
    required this.nearOrPastManeuver,
  });

  static const none = NavRerouteWrongStreetEval(
    observation: false,
    ambiguous: false,
    strongHeading: false,
    nearOrPastManeuver: false,
  );
}

NavRerouteWrongStreetEval navRerouteEvaluateWrongStreet({
  required NavRouteProgressOutput progress,
  required double snapDistanceM,
  required double speedKmh,
  double? accuracyM,
  double? distanceToManeuverM,
  required bool snapGrowing,
  required int wrongStreetSampleCount,
}) {
  if (!snapDistanceM.isFinite) return NavRerouteWrongStreetEval.none;
  if (speedKmh < NavRerouteDecisionConfig.wrongStreetMinSpeedKmh ||
      speedKmh > NavRerouteDecisionConfig.wrongStreetMaxSpeedKmh) {
    return NavRerouteWrongStreetEval.none;
  }
  if (accuracyM != null &&
      accuracyM.isFinite &&
      accuracyM > NavRerouteDecisionConfig.goodAccuracyMaxM) {
    return NavRerouteWrongStreetEval.none;
  }

  final heading = progress.headingDeltaDeg;
  final headingDisagree = heading != null &&
      heading.isFinite &&
      heading >= NavRerouteDecisionConfig.wrongStreetHeadingMinDeg;
  final strongHeading = heading != null &&
      heading.isFinite &&
      heading >= NavRerouteDecisionConfig.wrongStreetHeadingStrongDeg;
  final routeSaysWrong = progress.routeDeviationLikely ||
      progress.oppositeDirectionLikely ||
      progress.backwardProgressLikely;
  final nearOrPastManeuver = distanceToManeuverM != null &&
      distanceToManeuverM.isFinite &&
      distanceToManeuverM <= NavRerouteDecisionConfig.wrongStreetNearManeuverM;

  // Inside a wide / ambiguous junction: wait until the outgoing street clears.
  // RELEASE-P0: sustained very-strong reverse heading (>=135) must not be
  // treated as junction ambiguity solely because snap is still <10 m.
  final veryStrongReverse = heading != null &&
      heading.isFinite &&
      heading >= NavRerouteDecisionConfig.strongOppositeHeadingDeg;
  final ambiguous = snapDistanceM <
          NavRerouteDecisionConfig.wrongStreetMinSnapM &&
      !strongHeading &&
      !veryStrongReverse &&
      !routeSaysWrong;

  if (ambiguous) {
    return NavRerouteWrongStreetEval(
      observation: false,
      ambiguous: true,
      strongHeading: false,
      nearOrPastManeuver: nearOrPastManeuver,
    );
  }

  // Parallel-lane ambiguity: small lateral offset with route-aligned heading.
  if (snapDistanceM <=
          NavRerouteDecisionConfig.wrongStreetParallelLaneMaxSnapM &&
      !headingDisagree &&
      !routeSaysWrong &&
      !veryStrongReverse) {
    return NavRerouteWrongStreetEval.none;
  }

  if (!headingDisagree && !routeSaysWrong) {
    return NavRerouteWrongStreetEval.none;
  }

  final unmatched = progress.offRouteLikely ||
      !progress.hasReliableSnap ||
      progress.confidence < 55.0 ||
      snapDistanceM >= NavRerouteDecisionConfig.wrongStreetMinSnapM ||
      veryStrongReverse ||
      routeSaysWrong;
  if (!unmatched) return NavRerouteWrongStreetEval.none;

  final beyondJunction = snapDistanceM >=
          NavRerouteDecisionConfig.wrongStreetMinSnapM &&
      (headingDisagree || routeSaysWrong);
  // RELEASE-P0: small-snap reverse travel along/beside the corridor.
  final smallSnapReverse = veryStrongReverse &&
      routeSaysWrong &&
      snapDistanceM < NavRerouteDecisionConfig.wrongStreetMinSnapM;
  final exitClear = (beyondJunction &&
          (snapGrowing ||
              snapDistanceM >= NavRerouteDecisionConfig.wrongStreetClearSnapM ||
              nearOrPastManeuver ||
              wrongStreetSampleCount >= 1 ||
              strongHeading ||
              routeSaysWrong)) ||
      smallSnapReverse;

  if (!exitClear && !beyondJunction && !smallSnapReverse) {
    return NavRerouteWrongStreetEval(
      observation: false,
      ambiguous: nearOrPastManeuver && !veryStrongReverse,
      strongHeading: strongHeading || veryStrongReverse,
      nearOrPastManeuver: nearOrPastManeuver,
    );
  }

  if (!beyondJunction && !smallSnapReverse) {
    return NavRerouteWrongStreetEval.none;
  }

  return NavRerouteWrongStreetEval(
    observation: true,
    ambiguous: false,
    strongHeading: strongHeading || veryStrongReverse,
    nearOrPastManeuver: nearOrPastManeuver,
  );
}

bool navRerouteWrongStreetConfirmed({
  required NavRerouteWrongStreetEval eval,
  required int wrongStreetSampleCount,
  required double snapDistanceM,
  required bool snapGrowing,
}) {
  if (!eval.observation) return false;
  if (eval.strongHeading &&
      snapDistanceM >= NavRerouteDecisionConfig.wrongStreetClearSnapM &&
      (snapGrowing ||
          snapDistanceM >= 20.0 ||
          eval.nearOrPastManeuver ||
          wrongStreetSampleCount >= 1)) {
    return true;
  }
  if (wrongStreetSampleCount >=
          NavRerouteDecisionConfig.wrongStreetConfirmSamples &&
      snapDistanceM >= NavRerouteDecisionConfig.wrongStreetMinSnapM) {
    return true;
  }
  return false;
}

bool navRerouteIsStrongEvidenceObservation({
  required NavRouteProgressOutput progress,
  required double snapDistanceM,
  required double speedKmh,
  double? accuracyM,
}) {
  if (!progress.offRouteLikely) return false;
  if (!snapDistanceM.isFinite) return false;
  if (snapDistanceM < NavRerouteDecisionConfig.strongEvidenceMinSnapM) {
    return false;
  }
  if (speedKmh < NavRerouteDecisionConfig.strongEvidenceMinSpeedKmh ||
      speedKmh > NavRerouteDecisionConfig.strongEvidenceMaxSpeedKmh) {
    return false;
  }
  if (accuracyM != null &&
      accuracyM.isFinite &&
      accuracyM > NavRerouteDecisionConfig.goodAccuracyMaxM) {
    return false;
  }
  return true;
}

bool navRerouteIsSevereEvidenceObservation({
  required NavRouteProgressOutput progress,
  required double snapDistanceM,
  required double speedKmh,
  double? accuracyM,
}) {
  if (!navRerouteIsStrongEvidenceObservation(
    progress: progress,
    snapDistanceM: snapDistanceM,
    speedKmh: speedKmh,
    accuracyM: accuracyM,
  )) {
    return false;
  }
  return snapDistanceM >= NavRerouteDecisionConfig.severeEvidenceMinSnapM;
}

bool navRerouteStrongFastPathReady({
  required int strongSampleCount,
  required Duration strongEvidenceDuration,
  required bool severe,
  required bool growing,
}) {
  if (severe &&
      strongSampleCount >= NavRerouteDecisionConfig.severeEvidenceMinSamples) {
    return true;
  }
  if (strongSampleCount >= 3) return true;
  if (strongSampleCount >= NavRerouteDecisionConfig.strongEvidenceMinSamples &&
      (growing ||
          strongEvidenceDuration >=
              NavRerouteDecisionConfig.strongEvidenceMinDuration)) {
    return true;
  }
  return false;
}

NavRerouteCooldownEval navRerouteEvaluateCooldown({
  required DateTime now,
  required bool isRerouting,
  required bool lastRerouteFailed,
  required DateTime? lastRerouteAt,
  required DateTime? lastRerouteSuccessAt,
  required DateTime? lastRerouteFailureAt,
  required DateTime? routeAcceptedAt,
  required String offRouteReason,
  required bool fastPathReady,
  required bool severeEvidence,
}) {
  if (isRerouting) {
    return const NavRerouteCooldownEval(
      kind: NavRerouteCooldownKind.requestInFlight,
      active: true,
      remainingMs: 0,
      fastPathEligible: false,
      blockedReason: 'request_in_flight',
    );
  }

  if (lastRerouteFailed) {
    final failureAt = lastRerouteFailureAt ?? lastRerouteAt;
    if (failureAt != null) {
      final elapsed = now.difference(failureAt);
      final limit = NavRerouteDecisionConfig.rerouteFailedRetryBackoff;
      if (elapsed < limit) {
        return NavRerouteCooldownEval(
          kind: NavRerouteCooldownKind.failedRetry,
          active: true,
          remainingMs: (limit - elapsed).inMilliseconds,
          fastPathEligible: false,
          blockedReason: 'failed_retry_backoff',
        );
      }
    }
  }

  // Startup grace only for a freshly accepted non-reroute route.
  final successAt = lastRerouteSuccessAt;
  final acceptedAt = routeAcceptedAt;
  if (acceptedAt != null &&
      (successAt == null || !successAt.isAfter(acceptedAt)) &&
      now.difference(acceptedAt) < NavRerouteDecisionConfig.startupGrace) {
    if (!fastPathReady) {
      return NavRerouteCooldownEval(
        kind: NavRerouteCooldownKind.startupGrace,
        active: true,
        remainingMs: (NavRerouteDecisionConfig.startupGrace -
                now.difference(acceptedAt))
            .inMilliseconds,
        fastPathEligible: false,
        blockedReason: 'startup_grace',
      );
    }
  }

  // Successful-reroute anti-thrash — strong/severe fast path may bypass.
  // Failed attempts must NOT inherit this window; they use the shorter
  // failed-retry backoff above so persistent opposite-direction deviations
  // can recover after ~3s.
  if (!lastRerouteFailed) {
    final antiThrashAnchor = successAt ?? lastRerouteAt;
    if (antiThrashAnchor != null) {
      final elapsed = now.difference(antiThrashAnchor);
      final isDeviation = navRerouteIsRouteDeviationReason(offRouteReason);
      final limit = isDeviation
          ? NavRerouteDecisionConfig.rerouteCooldownRouteDeviation
          : NavRerouteDecisionConfig.successfulRerouteCooldown;
      if (elapsed < limit) {
        final allowBypass = fastPathReady && (severeEvidence || !isDeviation);
        if (!allowBypass) {
          return NavRerouteCooldownEval(
            kind: NavRerouteCooldownKind.successfulReroute,
            active: true,
            remainingMs: (limit - elapsed).inMilliseconds,
            fastPathEligible: fastPathReady,
            blockedReason: 'successful_reroute_cooldown',
          );
        }
        return const NavRerouteCooldownEval(
          kind: NavRerouteCooldownKind.none,
          active: false,
          remainingMs: 0,
          fastPathEligible: true,
          blockedReason: 'none',
        );
      }
    }
  }

  return const NavRerouteCooldownEval(
    kind: NavRerouteCooldownKind.none,
    active: false,
    remainingMs: 0,
    fastPathEligible: false,
    blockedReason: 'none',
  );
}

int navRerouteHitsRequired({
  required bool strongOppositeDirection,
  required bool routeDeviation,
  required bool backwardProgress,
  required bool oppositeDirection,
  required bool progressOffRouteLikely,
  required double snapDistanceM,
  required int snapDistanceIncreaseStreak,
  bool wrongStreetConfirmed = false,
  bool wrongStreetObservation = false,
}) {
  if (wrongStreetConfirmed || strongOppositeDirection) return 1;
  if (wrongStreetObservation) return 2;
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
  bool wrongStreet = false,
}) {
  if (wrongStreet && !oppositeDirection && !backwardProgress) {
    return 'wrong_street';
  }
  if (oppositeDirection) {
    return strongOppositeDirection
        ? 'opposite_direction_strong'
        : 'opposite_direction';
  }
  if (backwardProgress) return 'backward_progress';
  if (wrongStreet) return 'wrong_street';
  return 'snap_distance';
}

bool navRerouteIsRouteDeviationReason(String reason) {
  return reason == 'opposite_direction' ||
      reason == 'opposite_direction_strong' ||
      reason == 'backward_progress' ||
      reason == 'wrong_street';
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
  return NavRerouteDecisionConfig.successfulRerouteCooldown;
}

Duration navRerouteDebounceFor({
  required String offRouteReason,
  required NavRouteProgressOutput progress,
  bool fastPathReady = false,
  bool strongEvidence = false,
  bool wrongStreetConfirmed = false,
}) {
  if (offRouteReason == 'wrong_street' && wrongStreetConfirmed) {
    return NavRerouteDecisionConfig.debounceWrongStreetConfirmed;
  }
  if (offRouteReason == 'wrong_street') {
    return NavRerouteDecisionConfig.debounceWrongStreetConfirm;
  }
  if (offRouteReason == 'opposite_direction_strong') {
    return NavRerouteDecisionConfig.debounceStrongOpposite;
  }
  if (navRerouteIsRouteDeviationReason(offRouteReason)) {
    return NavRerouteDecisionConfig.debounceRouteDeviation;
  }
  if (fastPathReady || strongEvidence) {
    return NavRerouteDecisionConfig.debounceStrongUrban;
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
  // RELEASE-P0: strong opposite crawl (fuel-station / reverse exit) may
  // proceed below the normal 8 km/h floor once progress already confirmed
  // the deviation with displacement evidence.
  if (offRouteReason == 'opposite_direction_strong' &&
      speedKmh >= NavRerouteDecisionConfig.minStrongOppositeCrawlSpeedKmh &&
      samplesOffRoute >=
          NavRerouteDecisionConfig.strongOppositeCrawlMinSamples) {
    return true;
  }
  if (routeDeviationLikely &&
      speedKmh >= NavRerouteDecisionConfig.minDeviationSpeedKmh) {
    return true;
  }
  if ((offRouteReason == 'opposite_direction_strong' ||
          offRouteReason == 'wrong_street') &&
      speedKmh >= NavRerouteDecisionConfig.minMovementSpeedKmh) {
    return true;
  }
  if (navRerouteIsRouteDeviationReason(offRouteReason) &&
      speedKmh >= NavRerouteDecisionConfig.minMovementSpeedKmh &&
      samplesOffRoute >= 1) {
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

/// PII-safe blocked reason when [navRerouteMovementOk] is false.
String navRerouteMovementBlockedReason({
  required double speedKmh,
  required String offRouteReason,
  required bool routeDeviationLikely,
  required int samplesOffRoute,
  required bool offRouteLikely,
  double? accuracyM,
  double? headingDeltaDeg,
}) {
  if (!offRouteLikely) return 'not_off_route';
  if (speedKmh < NavRerouteDecisionConfig.minStrongOppositeCrawlSpeedKmh) {
    return 'stationary';
  }
  if (accuracyM != null &&
      accuracyM.isFinite &&
      accuracyM > NavRerouteDecisionConfig.goodAccuracyMaxM &&
      navRerouteIsRouteDeviationReason(offRouteReason)) {
    return 'accuracy_low';
  }
  if (offRouteReason == 'opposite_direction_strong' ||
      offRouteReason == 'opposite_direction') {
    if (headingDeltaDeg != null &&
        headingDeltaDeg.isFinite &&
        headingDeltaDeg < NavRerouteDecisionConfig.strongOppositeHeadingDeg &&
        speedKmh < NavRerouteDecisionConfig.minDeviationSpeedKmh) {
      return 'heading_not_strong';
    }
    if (samplesOffRoute <
        NavRerouteDecisionConfig.strongOppositeCrawlMinSamples) {
      return 'insufficient_samples';
    }
  }
  if (samplesOffRoute < 2) return 'insufficient_samples';
  return 'movement_blocked';
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

String navRerouteDisplacementBucket(double displacementM) {
  if (!displacementM.isFinite || displacementM < 0) return 'na';
  if (displacementM < 1.0) return '0-1';
  if (displacementM < 3.0) return '1-3';
  if (displacementM < 8.0) return '3-8';
  if (displacementM < 20.0) return '8-20';
  return '20+';
}

String navRerouteAccuracyBucket(double? accuracyM) {
  if (accuracyM == null || !accuracyM.isFinite) return 'na';
  if (accuracyM <= 5.0) return '0-5';
  if (accuracyM <= 15.0) return '5-15';
  if (accuracyM <= 30.0) return '15-30';
  return '30+';
}

String navRerouteCooldownKindToken(NavRerouteCooldownKind kind) {
  switch (kind) {
    case NavRerouteCooldownKind.none:
      return 'none';
    case NavRerouteCooldownKind.requestInFlight:
      return 'request_in_flight';
    case NavRerouteCooldownKind.startupGrace:
      return 'startup_grace';
    case NavRerouteCooldownKind.successfulReroute:
      return 'successful_reroute';
    case NavRerouteCooldownKind.failedRetry:
      return 'failed_retry';
  }
}
