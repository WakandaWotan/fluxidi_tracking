import 'dart:math' as math;

/// Severity for the local Fluxidi OS caution banner.
enum NavCautionSeverity { info, warning }

/// Snapshot of the caution UI / diagnostics state.
class NavCautionState {
  final bool shouldShowCaution;
  final NavCautionSeverity severity;
  final String reasonCode;
  final int cooldownMs;
  final int signalCount;
  final bool complexCandidate;

  const NavCautionState({
    required this.shouldShowCaution,
    required this.severity,
    required this.reasonCode,
    required this.cooldownMs,
    this.signalCount = 0,
    this.complexCandidate = false,
  });

  static const inactive = NavCautionState(
    shouldShowCaution: false,
    severity: NavCautionSeverity.info,
    reasonCode: 'none',
    cooldownMs: 0,
  );
}

/// Inputs for local complexity detection — all derived from existing engine
/// signals; no cloud, no coordinates.
class NavComplexityMonitorInput {
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

  const NavComplexityMonitorInput({
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

/// NAV-R14: pure local monitor for complex / low-confidence navigation zones.
///
/// Uses signal counting plus hysteresis so the driver sees a calm warning only
/// after sustained complexity, and not repeatedly (cooldown).
class NavComplexityMonitor {
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

  NavCautionState update(NavComplexityMonitorInput input) {
    if (!input.liveRideActive || !input.followMode) {
      reset();
      return NavCautionState.inactive;
    }

    _trackManeuverChanges(input);
    _trackPredictionBridge(input);

    final assessment = _assessSignals(
      input,
      stepChangesInWindow: _stepChangesInWindow,
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

    return NavCautionState(
      shouldShowCaution: _showing,
      severity: assessment.severity,
      reasonCode: _showing ? _activeReason : 'none',
      cooldownMs: cooldownMs,
      signalCount: assessment.signalCount,
      complexCandidate: assessment.complexCandidate,
    );
  }

  void _trackManeuverChanges(NavComplexityMonitorInput input) {
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

  void _trackPredictionBridge(NavComplexityMonitorInput input) {
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
    NavComplexityMonitorInput input, {
    required int stepChangesInWindow,
  }) {
    final signals = <String>[];

    final overall = input.overallConfidence;
    if (overall != null && overall < lowConfidenceThreshold) {
      signals.add('low_confidence');
    }

    if (!input.trustInstruction || !input.trustBearing) {
      signals.add('low_trust');
    }

    final snap = input.snapDistanceM;
    if (snap != null && snap.isFinite && snap > highSnapThresholdM) {
      signals.add('high_snap_distance');
    }

    if (input.offRouteLikely) {
      signals.add('offroute_uncertain');
    }

    if (_maneuverAmbiguous(input) || stepChangesInWindow >= 1) {
      signals.add('ambiguous_maneuver');
    }

    final headingDelta = input.headingDeltaDeg;
    final speed = math.max(0.0, input.speedKmh ?? 0.0);
    if (headingDelta != null &&
        headingDelta.isFinite &&
        headingDelta >= strongHeadingConflictDeg &&
        speed >= 5.0) {
      signals.add('heading_conflict');
    }

    if (_repeatedPrediction(input)) {
      signals.add('repeated_prediction');
    }

    if (_denseManeuverArea(input)) {
      signals.add('dense_junction');
    }

    final complexCandidate = signals.length >= minSignalCount;
    final reasonCode = complexCandidate ? _primaryReason(signals) : 'none';
    final severity =
        signals.contains('offroute_uncertain') ||
            signals.contains('heading_conflict') ||
            (overall != null && overall < 40.0)
        ? NavCautionSeverity.warning
        : NavCautionSeverity.info;

    return _SignalAssessment(
      complexCandidate: complexCandidate,
      signalCount: signals.length,
      reasonCode: reasonCode,
      severity: severity,
    );
  }

  static bool _maneuverAmbiguous(NavComplexityMonitorInput input) {
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

  bool _repeatedPrediction(NavComplexityMonitorInput input) {
    if (!input.predictionActive) return false;
    if (_predictionBridgeCount >= 3) return true;
    if (_predictionActiveSince == null) return false;
    return input.timestamp.difference(_predictionActiveSince!).inMilliseconds >=
        repeatedPredictionMs;
  }

  static bool _denseManeuverArea(NavComplexityMonitorInput input) {
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
      'heading_conflict',
      'repeated_prediction',
      'ambiguous_maneuver',
      'dense_junction',
      'low_confidence',
      'high_snap_distance',
      'low_trust',
    ];
    for (final reason in priority) {
      if (signals.contains(reason)) return reason;
    }
    return signals.first;
  }

  /// Bounded snap-distance bucket for diagnostics (no raw meters when huge).
  static String snapDistanceBucket(double? snapDistanceM) {
    final snap = snapDistanceM;
    if (snap == null || !snap.isFinite) return 'unknown';
    if (snap <= 15.0) return '0_15';
    if (snap <= 25.0) return '15_25';
    if (snap <= 40.0) return '25_40';
    return '40_plus';
  }
}

class _SignalAssessment {
  final bool complexCandidate;
  final int signalCount;
  final String reasonCode;
  final NavCautionSeverity severity;

  const _SignalAssessment({
    required this.complexCandidate,
    required this.signalCount,
    required this.reasonCode,
    required this.severity,
  });
}

/// Localized caution copy for the driver banner.
String navComplexityCautionLocalizedText({
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
        en: 'Complex traffic situation',
        fr: 'Situation de circulation complexe',
        es: 'Situación de tráfico compleja',
      );
    case 'body':
      return tr(
        nl: 'Fluxidi OS is minder zeker. Volg verkeersborden en wegmarkeringen.',
        en: 'Fluxidi OS is less certain. Follow traffic signs and road markings.',
        fr: 'Fluxidi OS est moins certain. Suivez les panneaux et marquages routiers.',
        es: 'Fluxidi OS es menos seguro. Siga señales y marcas viales.',
      );
    default:
      return '';
  }
}
