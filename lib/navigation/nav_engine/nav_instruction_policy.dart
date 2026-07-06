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
    this.forwardProgress = true,
    this.predictionActive = false,
    this.speedKmh,
  });
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

  // TODO(NAV Engine v2): Re-enable lane row only after lane confidence model exists.
  static const bool _laneGuidanceEnabled = false;

  void reset() {}

  NavInstructionPolicyOutput update(NavInstructionPolicyInput input) {
    final raw = (input.rawInstructionText ?? '').trim();
    const neutralFollowEn = 'Follow the route';
    const checkingRouteEn = 'Checking route';
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

    if (input.offRouteLikely) {
      return NavInstructionPolicyOutput(
        displayInstructionText: checkingRouteEn,
        showOriginalInstruction: false,
        showLaneGuidance: false,
        isNeutralFallback: true,
        reason: 'off_route_checking',
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

    final explicitUturn = _explicitUturnManeuver(
      input.maneuverType,
      input.maneuverModifier,
    );

    if (explicitUturn) {
      if (_uturnSafeToShow(input)) {
        return NavInstructionPolicyOutput(
          displayInstructionText: raw,
          showOriginalInstruction: true,
          showLaneGuidance: _laneGuidanceEnabled,
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
        showLaneGuidance: _laneGuidanceEnabled,
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
  }) tr,
}) {
  if (policy.showOriginalInstruction) {
    final trimmed = originalText.trim();
    return trimmed.isNotEmpty ? trimmed : policy.displayInstructionText;
  }
  switch (policy.reason) {
    case 'off_route_checking':
      return tr(
        nl: 'Route wordt gecontroleerd',
        en: 'Checking route',
        fr: 'Verification de l\'itineraire',
        es: 'Comprobando ruta',
      );
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
