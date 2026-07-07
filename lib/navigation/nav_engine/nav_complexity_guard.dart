import 'dart:math' as math;

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

  const NavComplexityGuardState({
    required this.active,
    required this.severity,
    required this.reasonCode,
    required this.cooldownMs,
    this.messageKey = 'nav_complexity_caution',
    this.signalCount = 0,
    this.complexCandidate = false,
    this.predictionRepeated = false,
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
  });
}

/// NAV-R14A: pure local complexity guard with hysteresis + cooldown.
class NavComplexityGuard {
  static const int showPersistMs = 2500;
  static const int hideStableMs = 5000;
  static const int cooldownMs = 45000;
  static const int minSignalCount = 2;
  static const double lowConfidenceThreshold = 55.0;
  static const double highSnapThresholdM = 25.0;
  static const double strongHeadingConflictDeg = 70.0;
  static const int repeatedPredictionMs = 4000;
  static const int maneuverChangeWindowMs = 10000;

  bool _showing = false;
  DateTime? _complexSince;
  DateTime? _stableSince;
  DateTime? _lastDismissedAt;
  String _activeReason = 'none';

  int? _lastStepIndex;
  DateTime? _lastStepChangeAt;
  int _stepChangesInWindow = 0;

  DateTime? _predictionActiveSince;
  int _predictionBridgeCount = 0;
  bool _predictionWasActive = false;

  void reset() {
    _showing = false;
    _complexSince = null;
    _stableSince = null;
    _lastDismissedAt = null;
    _activeReason = 'none';
    _lastStepIndex = null;
    _lastStepChangeAt = null;
    _stepChangesInWindow = 0;
    _predictionActiveSince = null;
    _predictionBridgeCount = 0;
    _predictionWasActive = false;
  }

  NavComplexityGuardState update(NavComplexityGuardInput input) {
    if (!input.liveRideActive || !input.followMode) {
      reset();
      return NavComplexityGuardState.inactive;
    }

    _trackManeuverChanges(input);
    _trackPredictionBridge(input);

    final assessment = _assessSignals(
      input,
      stepChangesInWindow: _stepChangesInWindow,
      predictionRepeated: _repeatedPrediction(input),
    );
    final now = input.timestamp;

    if (assessment.complexCandidate) {
      _complexSince ??= now;
      _stableSince = null;
    } else {
      _complexSince = null;
      _stableSince ??= now;
    }

    final inCooldown =
        _lastDismissedAt != null &&
        now.difference(_lastDismissedAt!).inMilliseconds < cooldownMs;

    if (!_showing) {
      final persistedMs = _complexSince == null
          ? 0
          : now.difference(_complexSince!).inMilliseconds;
      if (!inCooldown &&
          assessment.complexCandidate &&
          persistedMs >= showPersistMs) {
        _showing = true;
        _activeReason = assessment.reasonCode;
        _stableSince = null;
      }
    } else {
      final stableMs = _stableSince == null
          ? 0
          : now.difference(_stableSince!).inMilliseconds;
      if (!assessment.complexCandidate && stableMs >= hideStableMs) {
        _showing = false;
        _lastDismissedAt = now;
        _activeReason = 'none';
        _complexSince = null;
      } else if (assessment.complexCandidate) {
        _activeReason = assessment.reasonCode;
        _stableSince = null;
      }
    }

    return NavComplexityGuardState(
      active: _showing,
      severity: assessment.severity,
      reasonCode: _showing ? _activeReason : 'none',
      cooldownMs: cooldownMs,
      signalCount: assessment.signalCount,
      complexCandidate: assessment.complexCandidate,
      predictionRepeated: assessment.predictionRepeated,
    );
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
    final signals = <String>[];

    final overall = input.overallConfidence;
    if (overall != null && overall < lowConfidenceThreshold) {
      signals.add('low_confidence');
    }
    if (!input.trustInstruction || !input.trustBearing) {
      signals.add('low_confidence');
    }

    final snap = input.snapDistanceM;
    if (snap != null && snap.isFinite && snap > highSnapThresholdM) {
      signals.add('high_snap_distance');
    }

    if (input.offRouteLikely || input.reroutePending) {
      signals.add('offroute_uncertain');
    }

    if (_instructionAmbiguous(input) || stepChangesInWindow >= 1) {
      signals.add('ambiguous_instruction');
    }

    final headingDelta = input.headingDeltaDeg;
    final speed = math.max(0.0, input.speedKmh ?? 0.0);
    if (headingDelta != null &&
        headingDelta.isFinite &&
        headingDelta >= strongHeadingConflictDeg &&
        speed >= 5.0) {
      signals.add('heading_route_conflict');
    }

    if (predictionRepeated) {
      signals.add('repeated_prediction');
    }

    if (_denseManeuverArea(input)) {
      signals.add('dense_maneuver_area');
    }

    final uniqueSignals = signals.toSet().toList();
    final complexCandidate = uniqueSignals.length >= minSignalCount;
    final reasonCode = complexCandidate
        ? _primaryReason(uniqueSignals)
        : 'none';
    final severity =
        uniqueSignals.contains('offroute_uncertain') ||
            uniqueSignals.contains('heading_route_conflict') ||
            (overall != null && overall < 40.0)
        ? NavComplexitySeverity.warning
        : NavComplexitySeverity.info;

    return _SignalAssessment(
      complexCandidate: complexCandidate,
      signalCount: uniqueSignals.length,
      reasonCode: reasonCode,
      severity: severity,
      predictionRepeated: predictionRepeated,
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
      'offroute_uncertain',
      'heading_route_conflict',
      'repeated_prediction',
      'ambiguous_instruction',
      'dense_maneuver_area',
      'low_confidence',
      'high_snap_distance',
    ];
    for (final reason in priority) {
      if (signals.contains(reason)) return reason;
    }
    return signals.first;
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
  final bool complexCandidate;
  final int signalCount;
  final String reasonCode;
  final NavComplexitySeverity severity;
  final bool predictionRepeated;

  const _SignalAssessment({
    required this.complexCandidate,
    required this.signalCount,
    required this.reasonCode,
    required this.severity,
    required this.predictionRepeated,
  });
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
