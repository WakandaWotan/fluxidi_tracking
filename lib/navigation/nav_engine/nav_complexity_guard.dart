import 'dart:math' as math;

import 'package:flutter/foundation.dart';

/// Severity for the local Fluxidi OS complexity caution banner.
enum NavComplexitySeverity { info, warning }

/// NAV-R14A: local guard output — offline decision only, no cloud dependency.
class NavComplexityGuardState {
  final bool active;
  final NavComplexitySeverity severity;
  final String reasonCode;
  final int cooldownMs;
  final String messageKey;
  final int signalCount;
  final bool complexCandidate;
  final bool predictionRepeated;
  final NavComplexityDecisionSnapshot decision;

  const NavComplexityGuardState({
    required this.active,
    required this.severity,
    required this.reasonCode,
    required this.cooldownMs,
    this.messageKey = 'nav_complexity_caution',
    this.signalCount = 0,
    this.complexCandidate = false,
    this.predictionRepeated = false,
    this.decision = NavComplexityDecisionSnapshot.inactive,
  });

  static const inactive = NavComplexityGuardState(
    active: false,
    severity: NavComplexitySeverity.info,
    reasonCode: 'none',
    cooldownMs: 0,
  );

  /// Back-compat alias used by existing UI wiring.
  bool get shouldShowCaution => active;
}

/// NAV-R14-COMPLEXITY-GATE-2: final advisory decision snapshot.
class NavComplexityDecisionSnapshot {
  const NavComplexityDecisionSnapshot({
    required this.show,
    required this.score,
    required this.threshold,
    required this.triggerRules,
    required this.qualityRules,
    required this.maneuverCount,
    required this.branchCount,
    required this.bearingAmbiguity,
    required this.routeConfidence,
    required this.mapMatchConfidence,
    required this.offRoute,
    required this.rerouteState,
    required this.reason,
    this.rawScore = 0,
    this.effectiveScore = 0,
    this.candidateReason = 'none',
    this.visible = false,
    this.positiveStreak = 0,
    this.negativeStreak = 0,
    this.transition = 'none',
    this.suppressionReason = 'none',
    this.predictionSupportingOnly = false,
    this.structuralComplexityPresent = false,
    this.complexityRouteVersion = 0,
    this.currentRouteVersion = 0,
    this.stateOwnerMatches = true,
    this.hysteresisHold = false,
    this.staleStateClearedReason = 'none',
  });

  final bool show;
  final int score;
  final int threshold;
  final List<String> triggerRules;
  final List<String> qualityRules;
  final int maneuverCount;
  final int branchCount;
  final double? bearingAmbiguity;
  final double? routeConfidence;
  final double? mapMatchConfidence;
  final bool offRoute;
  final bool rerouteState;
  final String reason;
  final int rawScore;
  final int effectiveScore;
  final String candidateReason;
  final bool visible;
  final int positiveStreak;
  final int negativeStreak;
  final String transition;
  final String suppressionReason;
  final bool predictionSupportingOnly;
  final bool structuralComplexityPresent;
  final int complexityRouteVersion;
  final int currentRouteVersion;
  final bool stateOwnerMatches;
  final bool hysteresisHold;
  final String staleStateClearedReason;

  static const inactive = NavComplexityDecisionSnapshot(
    show: false,
    score: 0,
    threshold: 1,
    triggerRules: [],
    qualityRules: [],
    maneuverCount: 0,
    branchCount: 0,
    bearingAmbiguity: null,
    routeConfidence: null,
    mapMatchConfidence: null,
    offRoute: false,
    rerouteState: false,
    reason: 'none',
  );

  String get diagnosticSignature =>
      '$show|$rawScore|$effectiveScore|$threshold|'
      '${triggerRules.join('+')}|${qualityRules.join('+')}|$reason|'
      '$transition|$suppressionReason|$positiveStreak|$negativeStreak|'
      '$predictionSupportingOnly|$structuralComplexityPresent|'
      '$complexityRouteVersion|$currentRouteVersion|$stateOwnerMatches|'
      '$hysteresisHold|$staleStateClearedReason';
}

/// Inputs derived from existing engine/confidence/progress signals only.
class NavComplexityGuardInput {
  final DateTime timestamp;
  final bool liveRideActive;
  final bool followMode;
  final double? overallConfidence;
  final bool trustInstruction;
  final bool trustBearing;
  final double? snapDistanceM;
  final bool offRouteLikely;
  final bool reroutePending;
  final double? headingDeltaDeg;
  final bool predictionActive;
  final int gapBridgeMs;
  final String? maneuverModifier;
  final int? instructionStepIndex;
  final double? speedKmh;
  final double? distanceToManeuverM;
  final String? maneuverType;
  final int routeVersion;

  const NavComplexityGuardInput({
    required this.timestamp,
    this.liveRideActive = false,
    this.followMode = false,
    this.overallConfidence,
    this.trustInstruction = true,
    this.trustBearing = true,
    this.snapDistanceM,
    this.offRouteLikely = false,
    this.reroutePending = false,
    this.headingDeltaDeg,
    this.predictionActive = false,
    this.gapBridgeMs = 0,
    this.maneuverModifier,
    this.instructionStepIndex,
    this.speedKmh,
    this.distanceToManeuverM,
    this.maneuverType,
    this.routeVersion = 0,
  });
}

/// NAV-R14A / NAV-R14-COMPLEXITY-GATE-2: local complexity guard.
class NavComplexityGuard {
  /// Ordinary non-critical complexity needs this many consecutive positives.
  static const int requiredPositiveStreak = 2;

  /// Trusted negatives needed before an ordinary clear.
  static const int requiredNegativeStreak = 2;
  static const int cooldownMs = 45000;

  /// Complexity-only (structural) signals required; quality/prediction alone
  /// must not warn.
  static const int minComplexitySignalCount = 1;
  static const double lowConfidenceThreshold = 55.0;
  static const double highSnapThresholdM = 25.0;
  static const double strongHeadingConflictDeg = 70.0;
  static const int repeatedPredictionMs = 4000;
  static const int maneuverChangeWindowMs = 10000;

  /// Normal junction step advance is one change; churn needs repeated churn.
  static const int rapidInstructionChurnThreshold = 2;

  /// Prediction-only activity is ignored as a sole trigger during warm-up.
  static const int startupWarmupMs = 8000;

  /// NAV-COMPLEXITY-HEADING-CONFLICT-GATE-P0-1: consecutive raw
  /// heading-vs-matched-segment-bearing conflict samples required before the
  /// heading conflict may contribute as a structural complexity signal.
  /// A single-tick GPS course spike on a curvy local road must never activate
  /// the caution.
  static const int sustainedHeadingConflictMinConsecutive = 3;

  /// NAV-COMPLEXITY-HEADING-CONFLICT-GATE-P0-1: minimum speed at which a raw
  /// heading conflict sample is considered meaningful. Below this speed the
  /// GPS course is dominated by noise and cannot corroborate real complexity.
  static const double sustainedHeadingConflictMinSpeedKmh = 8.0;

  bool _showing = false;
  DateTime? _lastDismissedAt;
  String _activeReason = 'none';
  int _positiveStreak = 0;
  int _negativeStreak = 0;
  String _lastTransition = 'none';

  int? _lastStepIndex;
  DateTime? _lastStepChangeAt;
  int _stepChangesInWindow = 0;

  DateTime? _predictionActiveSince;
  int _predictionBridgeCount = 0;
  bool _predictionWasActive = false;

  DateTime? _sessionStartedAt;
  int? _lastRouteVersion;
  String _staleStateClearedReason = 'none';

  /// NAV-COMPLEXITY-HEADING-CONFLICT-GATE-P0-1: bounded consecutive-sample
  /// counter for raw heading conflict. Reset by [reset],
  /// [_clearVisibleImmediate] (arrival/destination), and whenever the
  /// per-tick conflict predicate becomes false.
  int _headingConflictConsecutive = 0;

  void reset() {
    _showing = false;
    _lastDismissedAt = null;
    _activeReason = 'none';
    _positiveStreak = 0;
    _negativeStreak = 0;
    _lastTransition = 'none';
    _lastStepIndex = null;
    _lastStepChangeAt = null;
    _stepChangesInWindow = 0;
    _predictionActiveSince = null;
    _predictionBridgeCount = 0;
    _predictionWasActive = false;
    _sessionStartedAt = null;
    _lastRouteVersion = null;
    _staleStateClearedReason = 'none';
    _headingConflictConsecutive = 0;
  }

  NavComplexityGuardState update(NavComplexityGuardInput input) {
    if (!input.liveRideActive || !input.followMode) {
      final wasShowing = _showing;
      reset();
      _lastTransition = wasShowing ? 'terminal_clear' : 'none';
      return NavComplexityGuardState.inactive.copyWithDecision(
        NavComplexityDecisionSnapshot.inactive.copyWith(
          transition: _lastTransition,
          suppressionReason: 'no_active_session',
          currentRouteVersion: input.routeVersion,
          complexityRouteVersion: input.routeVersion,
          stateOwnerMatches: true,
          staleStateClearedReason: wasShowing
              ? 'session_inactive'
              : 'none',
        ),
      );
    }

    if (_lastRouteVersion != null && input.routeVersion != _lastRouteVersion) {
      // Route / route-version replacement — drop stale evidence immediately.
      // Old-route hysteresis / instruction churn must not transfer to N+1.
      final keptRouteVersion = input.routeVersion;
      final hadStaleWarning = _showing || _positiveStreak > 0;
      reset();
      _lastRouteVersion = keptRouteVersion;
      _sessionStartedAt = input.timestamp;
      _lastTransition = 'terminal_clear';
      _staleStateClearedReason = hadStaleWarning
          ? 'route_version_replaced'
          : 'route_version_replaced_clean';
    } else {
      _lastRouteVersion = input.routeVersion;
      _sessionStartedAt ??= input.timestamp;
      if (_staleStateClearedReason.startsWith('route_version_replaced')) {
        // One-shot diagnostic token for the first post-replace tick.
      } else {
        _staleStateClearedReason = 'none';
      }
    }

    if (_isTerminalGuidance(input.maneuverType)) {
      _clearVisibleImmediate(reason: 'none');
      _lastTransition = 'terminal_clear';
      final decision = NavComplexityDecisionSnapshot(
        show: false,
        score: 0,
        threshold: minComplexitySignalCount,
        triggerRules: const [],
        qualityRules: const [],
        maneuverCount: _stepChangesInWindow,
        branchCount: inferBranchCount(input),
        bearingAmbiguity: input.headingDeltaDeg,
        routeConfidence: input.overallConfidence,
        mapMatchConfidence: resolveMapMatchConfidence(input),
        offRoute: input.offRouteLikely,
        rerouteState: input.reroutePending,
        reason: 'none',
        rawScore: 0,
        effectiveScore: 0,
        candidateReason: 'none',
        visible: false,
        positiveStreak: _positiveStreak,
        negativeStreak: _negativeStreak,
        transition: 'terminal_clear',
        suppressionReason: _terminalSuppressionReason(input.maneuverType),
        predictionSupportingOnly: false,
        structuralComplexityPresent: false,
      );
      return NavComplexityGuardState(
        active: false,
        severity: NavComplexitySeverity.info,
        reasonCode: 'none',
        cooldownMs: cooldownMs,
        decision: decision,
      );
    }

    _trackManeuverChanges(input);
    _trackPredictionBridge(input);
    _trackHeadingConflict(input);

    final assessment = _assessSignals(
      input,
      stepChangesInWindow: _stepChangesInWindow,
      headingConflictConsecutive: _headingConflictConsecutive,
      predictionRepeated: _repeatedPrediction(input),
    );
    final now = input.timestamp;
    final inStartupWarmup =
        _sessionStartedAt != null &&
        now.difference(_sessionStartedAt!).inMilliseconds < startupWarmupMs;

    var complexCandidate =
        assessment.structuralComplexityPresent &&
        assessment.effectiveScore >= minComplexitySignalCount;
    var suppressionReason = 'none';
    var transition = 'none';
    var hysteresisHold = false;
    final ownerVersion = _lastRouteVersion ?? input.routeVersion;
    final stateOwnerMatches = ownerVersion == input.routeVersion;

    // Prediction may support structural complexity, but never activate alone —
    // including during startup warm-up.
    if (!assessment.structuralComplexityPresent &&
        assessment.predictionRepeated) {
      complexCandidate = false;
      suppressionReason = inStartupWarmup
          ? 'startup_prediction_only'
          : 'prediction_supporting_only';
      if (inStartupWarmup) {
        transition = 'startup_prediction_suppressed';
      }
    }

    final inCooldown =
        _lastDismissedAt != null &&
        now.difference(_lastDismissedAt!).inMilliseconds < cooldownMs;

    // Strong reliable recovery (high confidence, tight snap, on-route) must
    // clear immediately — never keep show=true from stale churn / rerouteState.
    final strongReliableRecovery = _isStrongReliableRecovery(input, assessment);

    if (complexCandidate) {
      _positiveStreak += 1;
      _negativeStreak = 0;
      if (!_showing) {
        if (!inCooldown && _positiveStreak >= requiredPositiveStreak) {
          _showing = true;
          _activeReason = assessment.reasonCode;
          transition = 'shown';
          _staleStateClearedReason = 'none';
        } else if (!inCooldown) {
          transition = transition == 'none' ? 'pending_show' : transition;
        }
      } else {
        _activeReason = assessment.reasonCode;
        transition = 'none';
      }
    } else if (strongReliableRecovery && _showing) {
      // Clear immediately, but keep dismiss cooldown so the same route
      // cannot re-spam the banner a tick later.
      _showing = false;
      _activeReason = 'none';
      _positiveStreak = 0;
      _negativeStreak = 0;
      _lastDismissedAt = now;
      transition = 'reliable_recovery_clear';
      _staleStateClearedReason = 'reliable_recovery';
    } else {
      final trustedNegative = _isTrustedNegative(input, assessment);
      if (trustedNegative) {
        _negativeStreak += 1;
        _positiveStreak = 0;
      } else {
        // Untrusted / noisy negative — do not advance clear streak, but also
        // do not keep building a stale positive streak.
        _positiveStreak = 0;
      }

      if (_showing) {
        if (trustedNegative && _negativeStreak >= requiredNegativeStreak) {
          _showing = false;
          _lastDismissedAt = now;
          _activeReason = 'none';
          transition = 'cleared';
          _staleStateClearedReason = 'negative_hysteresis';
        } else if (trustedNegative) {
          transition = 'pending_clear';
          hysteresisHold = true;
        } else {
          hysteresisHold = true;
        }
      } else if (transition == 'none' &&
          suppressionReason == 'startup_prediction_only') {
        transition = 'startup_prediction_suppressed';
      }
    }

    // Consume one-shot route-version clear reason after packaging this tick.
    final staleCleared = _staleStateClearedReason;
    if (_staleStateClearedReason.startsWith('route_version_replaced')) {
      _staleStateClearedReason = 'none';
    }

    _lastTransition = transition;

    // NAV-COMPLEXITY-HEADING-CONFLICT-GATE-P0-1: one bounded PII-free log per
    // `shown` transition. Bounded by hysteresis (>=2 positive ticks) and
    // cooldown (45s), so cannot spam.
    if (transition == 'shown') {
      logNavComplexityTrigger(
        triggerRules: assessment.structuralSignals,
        qualityRules: assessment.qualitySignals,
        headingDeltaDeg: input.headingDeltaDeg,
        speedKmh: input.speedKmh,
        headingConflictStreak: _headingConflictConsecutive,
        stepChanges: _stepChangesInWindow,
      );
    }

    final decision = assessment.decision.copyWith(
      show: _showing,
      visible: _showing,
      score: assessment.effectiveScore,
      effectiveScore: assessment.effectiveScore,
      rawScore: assessment.rawScore,
      // Current-tick reason (may be none while visible is still clearing).
      reason: assessment.reasonCode,
      candidateReason: assessment.reasonCode,
      positiveStreak: _positiveStreak,
      negativeStreak: _negativeStreak,
      transition: transition,
      suppressionReason: suppressionReason,
      predictionSupportingOnly: assessment.predictionSupportingOnly,
      structuralComplexityPresent: assessment.structuralComplexityPresent,
      complexityRouteVersion: ownerVersion,
      currentRouteVersion: input.routeVersion,
      stateOwnerMatches: stateOwnerMatches,
      hysteresisHold: hysteresisHold,
      staleStateClearedReason: staleCleared,
    );

    return NavComplexityGuardState(
      active: _showing,
      severity: assessment.severity,
      reasonCode: _showing ? _activeReason : 'none',
      cooldownMs: cooldownMs,
      signalCount: assessment.structuralSignals.length,
      complexCandidate: complexCandidate,
      predictionRepeated: assessment.predictionRepeated,
      decision: decision,
    );
  }

  void _clearVisibleImmediate({required String reason}) {
    _showing = false;
    _activeReason = reason;
    _positiveStreak = 0;
    _negativeStreak = 0;
    _lastDismissedAt = null;
    // NAV-COMPLEXITY-HEADING-CONFLICT-GATE-P0-1: arrival/destination clears
    // the sustained-conflict counter so a fresh session cannot inherit it.
    _headingConflictConsecutive = 0;
  }

  static bool _isTrustedNegative(
    NavComplexityGuardInput input,
    _SignalAssessment assessment,
  ) {
    if (assessment.structuralComplexityPresent) return false;
    if (assessment.effectiveScore > 0) return false;
    // Ordinary clear path: no structural complexity and reason/score are none.
    // Trust flags reinforce that the negative evaluation is reliable.
    if (!input.trustBearing || !input.trustInstruction) {
      // Still allow clear when confidence is clearly healthy.
      final overall = input.overallConfidence;
      if (overall == null || overall < 70.0) return false;
    }
    return true;
  }

  /// High-confidence on-route recovery must not keep a stale warning visible.
  static bool _isStrongReliableRecovery(
    NavComplexityGuardInput input,
    _SignalAssessment assessment,
  ) {
    if (assessment.structuralComplexityPresent) return false;
    if (assessment.effectiveScore > 0) return false;
    if (input.offRouteLikely) return false;
    if (input.reroutePending) return false;
    if (!input.trustInstruction) return false;
    final snap = input.snapDistanceM;
    if (snap == null || !snap.isFinite || snap > 10.0) return false;
    final overall = input.overallConfidence;
    if (overall == null || !overall.isFinite || overall < 80.0) return false;
    return true;
  }

  static bool _isTerminalGuidance(String? maneuverType) {
    final type = (maneuverType ?? '').trim().toLowerCase();
    if (type.isEmpty) return false;
    return type.contains('arrive') || type.contains('destination');
  }

  static String _terminalSuppressionReason(String? maneuverType) {
    final type = (maneuverType ?? '').trim().toLowerCase();
    if (type.contains('destination')) return 'destination_reached';
    if (type.contains('arrive')) return 'arrive';
    return 'terminal_guidance';
  }

  void _trackManeuverChanges(NavComplexityGuardInput input) {
    final step = input.instructionStepIndex;
    if (step == null) return;
    if (_lastStepIndex != null && step != _lastStepIndex) {
      final now = input.timestamp;
      if (_lastStepChangeAt != null &&
          now.difference(_lastStepChangeAt!).inMilliseconds <=
              maneuverChangeWindowMs) {
        _stepChangesInWindow += 1;
      } else {
        _stepChangesInWindow = 1;
      }
      _lastStepChangeAt = now;
    }
    _lastStepIndex = step;
  }

  void _trackPredictionBridge(NavComplexityGuardInput input) {
    if (input.predictionActive) {
      _predictionActiveSince ??= input.timestamp;
      if (!_predictionWasActive && input.gapBridgeMs >= 300) {
        _predictionBridgeCount += 1;
      }
      _predictionWasActive = true;
    } else {
      _predictionActiveSince = null;
      _predictionWasActive = false;
    }
  }

  /// NAV-COMPLEXITY-HEADING-CONFLICT-GATE-P0-1: maintains the consecutive raw
  /// conflict-sample counter. A sample requires
  /// [strongHeadingConflictDeg] (>=70°) at
  /// [sustainedHeadingConflictMinSpeedKmh] (>=8 km/h). Any break in either
  /// condition resets the counter immediately so alternating curvature
  /// noise (75°/60°/75°/…) cannot accumulate.
  void _trackHeadingConflict(NavComplexityGuardInput input) {
    final headingDelta = input.headingDeltaDeg;
    final speed = math.max(0.0, input.speedKmh ?? 0.0);
    final sampleIsConflict =
        headingDelta != null &&
        headingDelta.isFinite &&
        headingDelta >= strongHeadingConflictDeg &&
        speed >= sustainedHeadingConflictMinSpeedKmh;
    if (sampleIsConflict) {
      // Bound the counter so a very long conflict cannot grow unbounded and
      // the diagnostic bucket stays small.
      if (_headingConflictConsecutive < 60) {
        _headingConflictConsecutive += 1;
      }
    } else {
      _headingConflictConsecutive = 0;
    }
  }

  _SignalAssessment _assessSignals(
    NavComplexityGuardInput input, {
    required int stepChangesInWindow,
    required int headingConflictConsecutive,
    required bool predictionRepeated,
  }) {
    final structuralSignals = <String>[];
    final qualitySignals = <String>[];

    final overall = input.overallConfidence;
    if (overall != null && overall < lowConfidenceThreshold) {
      qualitySignals.add('low_confidence');
    }
    if (!input.trustInstruction || !input.trustBearing) {
      qualitySignals.add('low_confidence');
    }

    final snap = input.snapDistanceM;
    if (snap != null && snap.isFinite && snap > highSnapThresholdM) {
      qualitySignals.add('high_snap_distance');
    }

    if (input.offRouteLikely || input.reroutePending) {
      qualitySignals.add('offroute_uncertain');
    }

    if (_instructionAmbiguous(input)) {
      structuralSignals.add('ambiguous_instruction');
    }
    // NAV-COMPLEXITY-CHURN-GATE-P0-FIELD-2026-07-29:
    // `rapid_instruction_churn` on its own is NOT structural complexity. Field
    // evidence (routeConfidence=96.5, mapMatchConfidence=100.0, branchCount=0,
    // maneuverCount=2, offRoute=false, rerouteState=false) proved that stepping
    // an instruction index twice inside the 10 s window is a normal event on
    // ordinary routes. Churn is retained as a QUALITY signal so it can only
    // ELEVATE / support an already-structural warning, never activate one by
    // itself. The producer/presentation contract requires at least one genuine
    // structural signal (real branches, dense conflicting geometry, materially
    // ambiguous bearings/junction, complex interchange) before WARN may show.
    if (stepChangesInWindow >= rapidInstructionChurnThreshold) {
      qualitySignals.add('rapid_instruction_churn');
    }

    // NAV-COMPLEXITY-HEADING-CONFLICT-GATE-P0-1: a raw single-sample bearing
    // spike on a curvy local road must never activate the caution. Require:
    //   1. consecutive conflict samples >= sustainedHeadingConflictMinConsecutive
    //   2. AND at least one independent quality signal on this same tick
    //      (low_confidence, high_snap_distance, or offroute_uncertain).
    // Repeated prediction is explicitly excluded as corroboration below.
    final headingDelta = input.headingDeltaDeg;
    final headingConflictSustained =
        headingConflictConsecutive >= sustainedHeadingConflictMinConsecutive;
    final supportingQualityPresent =
        qualitySignals.contains('low_confidence') ||
        qualitySignals.contains('high_snap_distance') ||
        qualitySignals.contains('offroute_uncertain');
    if (headingConflictSustained && supportingQualityPresent) {
      structuralSignals.add('heading_route_conflict');
    }

    // Prediction is a supporting quality signal only — never a structural
    // trigger on its own and never corroboration for a heading conflict.
    if (predictionRepeated) {
      qualitySignals.add('repeated_prediction');
    }

    if (_denseManeuverArea(input)) {
      structuralSignals.add('dense_maneuver_area');
    }

    final uniqueStructural = structuralSignals.toSet().toList();
    final uniqueQuality = qualitySignals.toSet().toList();
    final structuralPresent = uniqueStructural.isNotEmpty;
    final rawScore = uniqueStructural.length;
    // Prediction may reinforce when structural complexity is already present,
    // but never creates effective score by itself.
    final effectiveScore = structuralPresent ? rawScore : 0;
    final reasonCode = structuralPresent
        ? _primaryReason(uniqueStructural)
        : 'none';
    // NAV-COMPLEXITY-CHURN-GATE-P0-FIELD-2026-07-29: churn is a quality
    // signal now, so severity elevation must not rely on it. `warning`
    // severity is reserved for genuine structural risk: a sustained
    // route/heading conflict, or any structural signal on a route where
    // confidence has collapsed below 40 %.
    final severity =
        uniqueStructural.contains('heading_route_conflict') ||
            (overall != null && overall < 40.0 && structuralPresent)
        ? NavComplexitySeverity.warning
        : NavComplexitySeverity.info;

    final decision = NavComplexityDecisionSnapshot(
      show: false,
      score: effectiveScore,
      threshold: minComplexitySignalCount,
      triggerRules: uniqueStructural,
      qualityRules: uniqueQuality,
      maneuverCount: stepChangesInWindow,
      branchCount: inferBranchCount(input),
      bearingAmbiguity: headingDelta,
      routeConfidence: overall,
      mapMatchConfidence: resolveMapMatchConfidence(input),
      offRoute: input.offRouteLikely,
      rerouteState: input.reroutePending,
      reason: reasonCode,
      rawScore: rawScore,
      effectiveScore: effectiveScore,
      candidateReason: reasonCode,
      visible: false,
      predictionSupportingOnly: predictionRepeated && !structuralPresent,
      structuralComplexityPresent: structuralPresent,
    );

    return _SignalAssessment(
      structuralComplexityPresent: structuralPresent,
      structuralSignals: uniqueStructural,
      qualitySignals: uniqueQuality,
      reasonCode: reasonCode,
      severity: severity,
      predictionRepeated: predictionRepeated,
      predictionSupportingOnly: predictionRepeated && !structuralPresent,
      rawScore: rawScore,
      effectiveScore: effectiveScore,
      decision: decision,
    );
  }

  static bool _instructionAmbiguous(NavComplexityGuardInput input) {
    final modifier = (input.maneuverModifier ?? '').trim().toLowerCase();
    if (modifier.isEmpty || modifier == 'unknown') {
      final type = (input.maneuverType ?? '').trim().toLowerCase();
      if (type.contains('roundabout') ||
          type.contains('rotary') ||
          type.contains('merge') ||
          type.contains('fork')) {
        return true;
      }
    }
    return false;
  }

  bool _repeatedPrediction(NavComplexityGuardInput input) {
    if (!input.predictionActive) return false;
    if (_predictionBridgeCount >= 3) return true;
    if (_predictionActiveSince == null) return false;
    return input.timestamp.difference(_predictionActiveSince!).inMilliseconds >=
        repeatedPredictionMs;
  }

  static bool _denseManeuverArea(NavComplexityGuardInput input) {
    final speed = input.speedKmh ?? 99.0;
    final distance = input.distanceToManeuverM;
    if (speed >= 15.0 || distance == null || !distance.isFinite) {
      return false;
    }
    if (distance > 150.0) return false;
    final type = (input.maneuverType ?? '').trim().toLowerCase();
    return type.contains('roundabout') ||
        type.contains('rotary') ||
        type.contains('merge') ||
        type.contains('fork') ||
        type.contains('ramp');
  }

  static String _primaryReason(List<String> signals) {
    const priority = <String>[
      'heading_route_conflict',
      'rapid_instruction_churn',
      'ambiguous_instruction',
      'dense_maneuver_area',
    ];
    for (final reason in priority) {
      if (signals.contains(reason)) return reason;
    }
    return signals.first;
  }

  /// Estimated branch count from maneuver geometry (not GPS quality).
  static int inferBranchCount(NavComplexityGuardInput input) {
    final type = (input.maneuverType ?? '').trim().toLowerCase();
    if (type.contains('fork')) return 2;
    if (type.contains('merge')) return 2;
    if (type.contains('roundabout') || type.contains('rotary')) return 3;
    return 0;
  }

  /// Map-match quality proxy for diagnostics (higher = better match).
  static double? resolveMapMatchConfidence(NavComplexityGuardInput input) {
    final snap = input.snapDistanceM;
    if (snap == null || !snap.isFinite) return null;
    final snapScore =
        (1.0 - (snap / highSnapThresholdM).clamp(0.0, 1.0)) * 100.0;
    var score = snapScore;
    if (input.trustInstruction) score += 10.0;
    if (input.trustBearing) score += 10.0;
    return score.clamp(0.0, 100.0);
  }

  /// NAV-R14A diagnostics bucket — no raw meters.
  static String snapDistanceBucket(double? snapDistanceM) {
    final snap = snapDistanceM;
    if (snap == null || !snap.isFinite) return 'unknown';
    if (snap <= 5.0) return '0-5';
    if (snap <= 15.0) return '5-15';
    if (snap <= 30.0) return '15-30';
    return '30+';
  }

  /// NAV-R14A / NAV-AI-1 confidence bucket.
  static String confidenceBucket(double? overallConfidence) {
    final score = overallConfidence;
    if (score == null || !score.isFinite) return 'unknown';
    if (score < 20.0) return '0-20';
    if (score < 40.0) return '20-40';
    if (score < 60.0) return '40-60';
    if (score < 80.0) return '60-80';
    return '80-100';
  }
}

class _SignalAssessment {
  final bool structuralComplexityPresent;
  final List<String> structuralSignals;
  final List<String> qualitySignals;
  final String reasonCode;
  final NavComplexitySeverity severity;
  final bool predictionRepeated;
  final bool predictionSupportingOnly;
  final int rawScore;
  final int effectiveScore;
  final NavComplexityDecisionSnapshot decision;

  const _SignalAssessment({
    required this.structuralComplexityPresent,
    required this.structuralSignals,
    required this.qualitySignals,
    required this.reasonCode,
    required this.severity,
    required this.predictionRepeated,
    required this.predictionSupportingOnly,
    required this.rawScore,
    required this.effectiveScore,
    required this.decision,
  });
}

extension on NavComplexityGuardState {
  NavComplexityGuardState copyWithDecision(
    NavComplexityDecisionSnapshot decision,
  ) {
    return NavComplexityGuardState(
      active: active,
      severity: severity,
      reasonCode: reasonCode,
      cooldownMs: cooldownMs,
      messageKey: messageKey,
      signalCount: signalCount,
      complexCandidate: complexCandidate,
      predictionRepeated: predictionRepeated,
      decision: decision,
    );
  }
}

extension on NavComplexityDecisionSnapshot {
  NavComplexityDecisionSnapshot copyWith({
    bool? show,
    int? score,
    int? threshold,
    List<String>? triggerRules,
    List<String>? qualityRules,
    int? maneuverCount,
    int? branchCount,
    double? bearingAmbiguity,
    double? routeConfidence,
    double? mapMatchConfidence,
    bool? offRoute,
    bool? rerouteState,
    String? reason,
    int? rawScore,
    int? effectiveScore,
    String? candidateReason,
    bool? visible,
    int? positiveStreak,
    int? negativeStreak,
    String? transition,
    String? suppressionReason,
    bool? predictionSupportingOnly,
    bool? structuralComplexityPresent,
    int? complexityRouteVersion,
    int? currentRouteVersion,
    bool? stateOwnerMatches,
    bool? hysteresisHold,
    String? staleStateClearedReason,
  }) {
    return NavComplexityDecisionSnapshot(
      show: show ?? this.show,
      score: score ?? this.score,
      threshold: threshold ?? this.threshold,
      triggerRules: triggerRules ?? this.triggerRules,
      qualityRules: qualityRules ?? this.qualityRules,
      maneuverCount: maneuverCount ?? this.maneuverCount,
      branchCount: branchCount ?? this.branchCount,
      bearingAmbiguity: bearingAmbiguity ?? this.bearingAmbiguity,
      routeConfidence: routeConfidence ?? this.routeConfidence,
      mapMatchConfidence: mapMatchConfidence ?? this.mapMatchConfidence,
      offRoute: offRoute ?? this.offRoute,
      rerouteState: rerouteState ?? this.rerouteState,
      reason: reason ?? this.reason,
      rawScore: rawScore ?? this.rawScore,
      effectiveScore: effectiveScore ?? this.effectiveScore,
      candidateReason: candidateReason ?? this.candidateReason,
      visible: visible ?? this.visible,
      positiveStreak: positiveStreak ?? this.positiveStreak,
      negativeStreak: negativeStreak ?? this.negativeStreak,
      transition: transition ?? this.transition,
      suppressionReason: suppressionReason ?? this.suppressionReason,
      predictionSupportingOnly:
          predictionSupportingOnly ?? this.predictionSupportingOnly,
      structuralComplexityPresent:
          structuralComplexityPresent ?? this.structuralComplexityPresent,
      complexityRouteVersion:
          complexityRouteVersion ?? this.complexityRouteVersion,
      currentRouteVersion: currentRouteVersion ?? this.currentRouteVersion,
      stateOwnerMatches: stateOwnerMatches ?? this.stateOwnerMatches,
      hysteresisHold: hysteresisHold ?? this.hysteresisHold,
      staleStateClearedReason:
          staleStateClearedReason ?? this.staleStateClearedReason,
    );
  }
}

String? _lastNavComplexityDecisionLogSignature;

/// NAV-R14-COMPLEXITY-GATE-2: bounded final advisory diagnostics.
void logNavComplexityDecision(NavComplexityDecisionSnapshot decision) {
  if (decision.diagnosticSignature == _lastNavComplexityDecisionLogSignature) {
    return;
  }
  _lastNavComplexityDecisionLogSignature = decision.diagnosticSignature;
  debugPrint(
    '[NAV_COMPLEXITY_DECISION] '
    'rawScore=${decision.rawScore} '
    'effectiveScore=${decision.effectiveScore} '
    'threshold=${decision.threshold} '
    'candidateReason=${decision.candidateReason} '
    'visible=${decision.visible} '
    'positiveStreak=${decision.positiveStreak} '
    'negativeStreak=${decision.negativeStreak} '
    'transition=${decision.transition} '
    'suppressionReason=${decision.suppressionReason} '
    'predictionSupportingOnly=${decision.predictionSupportingOnly} '
    'structuralComplexityPresent=${decision.structuralComplexityPresent} '
    'show=${decision.show} '
    'score=${decision.score} '
    'triggerRules=${decision.triggerRules.join(",")} '
    'maneuverCount=${decision.maneuverCount} '
    'branchCount=${decision.branchCount} '
    'bearingAmbiguity=${decision.bearingAmbiguity?.toStringAsFixed(1) ?? "null"} '
    'routeConfidence=${decision.routeConfidence?.toStringAsFixed(1) ?? "null"} '
    'mapMatchConfidence=${decision.mapMatchConfidence?.toStringAsFixed(1) ?? "null"} '
    'offRoute=${decision.offRoute} '
    'rerouteState=${decision.rerouteState} '
    'reason=${decision.reason} '
    'qualityRules=${decision.qualityRules.join(",")} '
    'complexityRouteVersion=${decision.complexityRouteVersion} '
    'currentRouteVersion=${decision.currentRouteVersion} '
    'stateOwnerMatches=${decision.stateOwnerMatches} '
    'hysteresisHold=${decision.hysteresisHold} '
    'staleStateClearedReason=${decision.staleStateClearedReason}',
  );
}

/// NAV-COMPLEXITY-HEADING-CONFLICT-GATE-P0-1: bounded PII-free diagnostic
/// emitted exactly once per `shown` transition. Buckets guarantee no raw
/// coordinates, IDs, tokens, addresses or route data are logged.
void logNavComplexityTrigger({
  required List<String> triggerRules,
  required List<String> qualityRules,
  required double? headingDeltaDeg,
  required double? speedKmh,
  required int headingConflictStreak,
  required int stepChanges,
}) {
  String headingBucket() {
    final delta = headingDeltaDeg;
    if (delta == null || !delta.isFinite || delta < 70.0) return 'lt70';
    if (delta < 100.0) return '70_99';
    return '100_plus';
  }

  String speedBucket() {
    final speed = speedKmh;
    if (speed == null || !speed.isFinite || speed < 8.0) return 'lt8';
    if (speed < 30.0) return '8_29';
    return '30_plus';
  }

  int clampBounded(int value) {
    if (value < 0) return 0;
    if (value > 20) return 20;
    return value;
  }

  debugPrint(
    '[NAV_COMPLEXITY_TRIGGER] '
    'rules=${triggerRules.join(",")} '
    'quality=${qualityRules.join(",")} '
    'heading_bucket=${headingBucket()} '
    'speed_bucket=${speedBucket()} '
    'heading_streak=${clampBounded(headingConflictStreak)} '
    'step_changes=${clampBounded(stepChanges)}',
  );
}

/// Localized caution copy for the driver banner (offline, no cloud).
String navComplexityGuardLocalizedText({
  required String field,
  required String Function({
    required String nl,
    required String en,
    required String fr,
    required String es,
  })
  tr,
}) {
  switch (field) {
    case 'title':
      return tr(
        nl: 'Complexe verkeerssituatie',
        en: 'Complex road situation',
        fr: 'Situation routière complexe',
        es: 'Situación vial compleja',
      );
    case 'body':
      return tr(
        nl: 'Fluxidi OS is minder zeker. Volg verkeersborden en wegmarkeringen.',
        en: 'Fluxidi OS is less certain. Follow road signs and lane markings.',
        fr: 'Fluxidi OS est moins certain. Suivez les panneaux et le marquage au sol.',
        es: 'Fluxidi OS tiene menos certeza. Sigue las señales y las marcas viales.',
      );
    default:
      return '';
  }
}

/// Back-compat alias for existing UI imports during NAV-R14A migration.
typedef NavCautionState = NavComplexityGuardState;
typedef NavCautionSeverity = NavComplexitySeverity;
String navComplexityCautionLocalizedText({
  required String field,
  required String Function({
    required String nl,
    required String en,
    required String fr,
    required String es,
  })
  tr,
}) => navComplexityGuardLocalizedText(field: field, tr: tr);
