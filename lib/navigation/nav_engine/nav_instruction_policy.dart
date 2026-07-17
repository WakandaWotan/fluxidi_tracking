/// Signals for deterministic maneuver instruction display policy.
class NavInstructionPolicyInput {
  final DateTime timestamp;
  final bool liveRideActive;
  final String? rawInstructionText;
  final String? maneuverType;
  final String? maneuverModifier;
  final double? distanceToManeuverM;
  final double? routeConfidence;
  final double? instructionConfidenceScore;
  final bool trustInstruction;
  final bool trustRouteSnap;
  final bool offRouteLikely;
  // NAV-R12-E2: route adaptation signals (NAV-R12-B) plus reroute-pending —
  // any of these suppresses route-specific maneuvers.
  final bool routeDeviationLikely;
  final bool oppositeDirectionLikely;
  final bool backwardProgressLikely;
  final bool reroutePending;
  final bool forwardProgress;
  final bool predictionActive;
  final double? speedKmh;

  const NavInstructionPolicyInput({
    required this.timestamp,
    required this.liveRideActive,
    this.rawInstructionText,
    this.maneuverType,
    this.maneuverModifier,
    this.distanceToManeuverM,
    this.routeConfidence,
    this.instructionConfidenceScore,
    this.trustInstruction = false,
    this.trustRouteSnap = false,
    this.offRouteLikely = false,
    this.routeDeviationLikely = false,
    this.oppositeDirectionLikely = false,
    this.backwardProgressLikely = false,
    this.reroutePending = false,
    this.forwardProgress = true,
    this.predictionActive = false,
    this.speedKmh,
  });

  /// NAV-R12-E2: true while the route is adapting — old-route maneuvers may
  /// not be shown confidently.
  bool get routeAdaptationActive =>
      offRouteLikely ||
      routeDeviationLikely ||
      oppositeDirectionLikely ||
      backwardProgressLikely ||
      reroutePending;
}

/// Resolved instruction text and display flags for the nav banner.
class NavInstructionPolicyOutput {
  final String displayInstructionText;
  final bool showOriginalInstruction;
  final bool showLaneGuidance;
  final bool isNeutralFallback;
  final String reason;

  const NavInstructionPolicyOutput({
    required this.displayInstructionText,
    required this.showOriginalInstruction,
    required this.showLaneGuidance,
    required this.isNeutralFallback,
    required this.reason,
  });
}

/// Deterministic instruction policy — no AI, no PII in logs.
class DriverNavInstructionPolicy {
  static const double _uturnMaxDistanceM = 300.0;
  static const double _lowRouteConfidence = 45.0;
  static const double _uturnRouteConfidence = 55.0;
  static const double _uturnInstructionConfidence = 65.0;
  static const double _predictionHighRouteConfidence = 55.0;
  static const double _maxReasonableManeuverDistanceM = 10000.0;

  void reset() {}

  NavInstructionPolicyOutput update(NavInstructionPolicyInput input) {
    final raw = (input.rawInstructionText ?? '').trim();
    const neutralFollowEn = 'Follow the route';
    // NAV-R12-B product wording: neutral route adaptation, never blame the
    // driver for a deviation.
    const checkingRouteEn = 'Adapting route…';
    const tunnelFollowEn = 'Keep following the route';

    if (!input.liveRideActive || raw.isEmpty) {
      return NavInstructionPolicyOutput(
        displayInstructionText: raw,
        showOriginalInstruction: raw.isNotEmpty,
        showLaneGuidance: false,
        isNeutralFallback: false,
        reason: 'inactive',
      );
    }

    // NAV-R12-E2: while the route is adapting (deviation signals from
    // NAV-R12-B or a reroute in flight) any old-route maneuver is stale —
    // show neutral adaptation wording instead. Never blames the driver.
    if (input.routeAdaptationActive) {
      return NavInstructionPolicyOutput(
        displayInstructionText: checkingRouteEn,
        showOriginalInstruction: false,
        showLaneGuidance: false,
        isNeutralFallback: true,
        reason: 'route_adaptation_${_adaptationTrigger(input)}',
      );
    }

    if (input.predictionActive && !_predictionConfidenceHigh(input)) {
      return NavInstructionPolicyOutput(
        displayInstructionText: tunnelFollowEn,
        showOriginalInstruction: false,
        showLaneGuidance: false,
        isNeutralFallback: true,
        reason: 'tunnel_low_confidence',
      );
    }

    if (!input.trustInstruction ||
        (input.routeConfidence ?? 0.0) < _lowRouteConfidence) {
      return NavInstructionPolicyOutput(
        displayInstructionText: neutralFollowEn,
        showOriginalInstruction: false,
        showLaneGuidance: false,
        isNeutralFallback: true,
        reason: 'low_instruction_trust',
      );
    }

    // NAV-R12-E2: treat instructions whose text reads like a 180°/U-turn the
    // same as explicit U-turn maneuvers — they only show when the route is
    // reliable, close, confident, and progressing forward.
    final explicitUturn =
        _explicitUturnManeuver(input.maneuverType, input.maneuverModifier) ||
        _textLooksLikeUturn(raw);

    if (explicitUturn) {
      if (_uturnSafeToShow(input)) {
        return NavInstructionPolicyOutput(
          displayInstructionText: raw,
          showOriginalInstruction: true,
          // Policy permits lanes for this instruction; master flag gates display.
          showLaneGuidance: true,
          isNeutralFallback: false,
          reason: 'uturn_allowed',
        );
      }
      return NavInstructionPolicyOutput(
        displayInstructionText: neutralFollowEn,
        showOriginalInstruction: false,
        showLaneGuidance: false,
        isNeutralFallback: true,
        reason: _uturnBlockedReason(input),
      );
    }

    if (_normalManeuverSafeToShow(input)) {
      return NavInstructionPolicyOutput(
        displayInstructionText: raw,
        showOriginalInstruction: true,
        // Policy permits lanes for this instruction; master flag gates display.
        showLaneGuidance: true,
        isNeutralFallback: false,
        reason: 'maneuver_allowed',
      );
    }

    return NavInstructionPolicyOutput(
      displayInstructionText: neutralFollowEn,
      showOriginalInstruction: false,
      showLaneGuidance: false,
      isNeutralFallback: true,
      reason: 'neutral_fallback',
    );
  }

  static bool _predictionConfidenceHigh(NavInstructionPolicyInput input) {
    final route = input.routeConfidence ?? 0.0;
    if (route < _predictionHighRouteConfidence) return false;
    final instruction = input.instructionConfidenceScore;
    if (instruction != null && instruction < _uturnInstructionConfidence) {
      return false;
    }
    return true;
  }

  /// NAV-R12-E2: bounded, deterministic trigger label for diagnostics.
  static String _adaptationTrigger(NavInstructionPolicyInput input) {
    if (input.reroutePending) return 'reroute_pending';
    if (input.oppositeDirectionLikely) return 'opposite_direction';
    if (input.backwardProgressLikely) return 'backward_progress';
    if (input.routeDeviationLikely) return 'route_deviation';
    return 'off_route';
  }

  /// Text-only 180°/U-turn detection (mirrors the display-side helper; the
  /// policy cannot import it without a dependency cycle).
  static bool _textLooksLikeUturn(String text) {
    final lower = text.trim().toLowerCase();
    if (lower.isEmpty) return false;
    const markers = <String>[
      'u-turn',
      'uturn',
      'u turn',
      'turn around',
      'turn-around',
      'keer om',
      'keer terug',
      'omkeren',
      'demi-tour',
      'demi tour',
      'giro en u',
      'media vuelta',
    ];
    for (final marker in markers) {
      if (lower.contains(marker)) return true;
    }
    return false;
  }

  static bool _explicitUturnManeuver(String? type, String? modifier) {
    final t = (type ?? '').trim().toLowerCase();
    final m = (modifier ?? '').trim().toLowerCase();
    if (m.contains('uturn') || m.contains('u-turn')) return true;
    if (t.contains('uturn') || t.contains('u-turn')) return true;
    if (t == 'end of road' &&
        (m.contains('uturn') ||
            m.contains('u-turn') ||
            m.contains('left') ||
            m.contains('right') ||
            m.isEmpty)) {
      return true;
    }
    return false;
  }

  static bool _uturnSafeToShow(NavInstructionPolicyInput input) {
    final distance = input.distanceToManeuverM;
    if (distance == null ||
        !distance.isFinite ||
        distance > _uturnMaxDistanceM) {
      return false;
    }
    if (!input.trustInstruction || !input.trustRouteSnap) return false;
    if ((input.routeConfidence ?? 0.0) < _uturnRouteConfidence) return false;
    final instructionScore = input.instructionConfidenceScore;
    if (instructionScore != null &&
        instructionScore < _uturnInstructionConfidence) {
      return false;
    }
    if (input.offRouteLikely || !input.forwardProgress) return false;
    return true;
  }

  static String _uturnBlockedReason(NavInstructionPolicyInput input) {
    final distance = input.distanceToManeuverM;
    if (distance == null ||
        !distance.isFinite ||
        distance > _uturnMaxDistanceM) {
      return 'uturn_distance';
    }
    if (!input.trustRouteSnap) return 'uturn_not_snapped';
    if (!input.trustInstruction) return 'uturn_low_trust';
    if ((input.routeConfidence ?? 0.0) < _uturnRouteConfidence) {
      return 'uturn_low_route_confidence';
    }
    final instructionScore = input.instructionConfidenceScore;
    if (instructionScore != null &&
        instructionScore < _uturnInstructionConfidence) {
      return 'uturn_low_instruction_score';
    }
    if (!input.forwardProgress) return 'uturn_no_forward_progress';
    return 'uturn_blocked';
  }

  static bool _normalManeuverSafeToShow(NavInstructionPolicyInput input) {
    if (!input.trustInstruction || input.offRouteLikely) return false;
    if (!input.forwardProgress) return false;
    final distance = input.distanceToManeuverM;
    if (distance != null &&
        distance.isFinite &&
        (distance < 0 || distance > _maxReasonableManeuverDistanceM)) {
      return false;
    }
    return true;
  }
}

/// Localized display strings for [NavInstructionPolicyOutput] reasons.
String navInstructionPolicyLocalizedText({
  required NavInstructionPolicyOutput policy,
  required String originalText,
  required String Function({
    required String nl,
    required String en,
    required String fr,
    required String es,
  })
  tr,
}) {
  if (policy.showOriginalInstruction) {
    final trimmed = originalText.trim();
    return trimmed.isNotEmpty ? trimmed : policy.displayInstructionText;
  }
  // NAV-R12-E2: all route-adaptation reasons share the same neutral wording.
  if (policy.reason == 'off_route_checking' ||
      policy.reason.startsWith('route_adaptation')) {
    return tr(
      nl: 'Route wordt aangepast…',
      en: 'Adapting route…',
      fr: 'Adaptation de l\'itinéraire…',
      es: 'Ajustando la ruta…',
    );
  }
  switch (policy.reason) {
    case 'tunnel_low_confidence':
      return tr(
        nl: 'Blijf de route volgen',
        en: 'Keep following the route',
        fr: 'Continuez a suivre l\'itineraire',
        es: 'Sigue la ruta',
      );
    default:
      return tr(
        nl: 'Volg de route',
        en: 'Follow the route',
        fr: 'Suivez l\'itinéraire',
        es: 'Sigue la ruta',
      );
  }
}

String navInstructionPolicyLogSnippet(String text) {
  final trimmed = text.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (trimmed.length <= 48) return trimmed;
  return '${trimmed.substring(0, 45)}...';
}
