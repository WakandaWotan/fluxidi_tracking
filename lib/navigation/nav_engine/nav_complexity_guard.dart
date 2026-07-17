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
      '$predictionSupportingOnly|$structuralComplexityPresent';
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
        ),
      );
    }

    if (_lastRouteVersion != null && input.routeVersion != _lastRouteVersion) {
      // Route / route-version replacement — drop stale evidence immediately.
      final keptRouteVersion = input.routeVersion;
      reset();
      _lastRouteVersion = keptRouteVersion;
      _sessionStartedAt = input.timestamp;
      _lastTransition = 'terminal_clear';
    } else {
      _lastRouteVersion = input.routeVersion;
      _sessionStartedAt ??= input.timestamp;
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

    final assessment = _assessSignals(
      input,
      stepChangesInWindow: _stepChangesInWindow,
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

    if (complexCandidate) {
      _positiveStreak += 1;
      _negativeStreak = 0;
      if (!_showing) {
        if (!inCooldown && _positiveStreak >= requiredPositiveStreak) {
          _showing = true;
          _activeReason = assessment.reasonCode;
          transition = 'shown';
        } else if (!inCooldown) {
          transition = transition == 'none' ? 'pending_show' : transition;
        }
      } else {
        _activeReason = assessment.reasonCode;
        transition = 'none';
      }
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
        } else if (trustedNegative) {
          transition = 'pending_clear';
        }
      } else if (transition == 'none' &&
          suppressionReason == 'startup_prediction_only') {
        transition = 'startup_prediction_suppressed';
      }
    }

    _lastTransition = transition;

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

  _SignalAssessment _assessSignals(
    NavComplexityGuardInput input, {
    required int stepChangesInWindow,
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
    if (stepChangesInWindow >= rapidInstructionChurnThreshold) {
      structuralSignals.add('rapid_instruction_churn');
    }

    final headingDelta = input.headingDeltaDeg;
    final speed = math.max(0.0, input.speedKmh ?? 0.0);
    if (headingDelta != null &&
        headingDelta.isFinite &&
        headingDelta >= strongHeadingConflictDeg &&
        speed >= 5.0) {
      structuralSignals.add('heading_route_conflict');
    }

    // Prediction is a supporting quality signal only — never a structural
    // trigger on its own.
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
    final severity =
        uniqueStructural.contains('heading_route_conflict') ||
            uniqueStructural.contains('rapid_instruction_churn') ||
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
    'qualityRules=${decision.qualityRules.join(",")}',
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
