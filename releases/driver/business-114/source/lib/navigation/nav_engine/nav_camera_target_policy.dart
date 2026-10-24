/// NAV-R12-E1: pure decision for which navigation target the follow camera
/// should aim at. No Mapbox/Flutter references so the rules are
/// unit-testable; the widget layer resolves the actual coordinates.
///
/// Priority:
/// 1. Not in follow mode and not a manual recenter -> skip (never force a
///    recenter on a user who panned away).
/// 2. Any route-deviation signal active -> freshest raw/live driver
///    position; never a stale route snap or prediction while adapting.
/// 3. Prediction only when active, confident, and fresh.
/// 4. Reliable route snap -> snapped/progress visual as before.
/// 5. Otherwise raw/live position.
enum NavCameraTargetSource { routeSnap, rawLive, prediction, skipped }

class NavCameraTargetInput {
  final bool followMode;
  final bool manualRecenter;
  final bool routeDeviationLikely;
  final bool oppositeDirectionLikely;
  final bool backwardProgressLikely;
  final bool offRouteLikely;
  /// Early strong-mismatch suspicion (before full off-route confirm).
  final bool strongMismatchSuspected;
  final bool hasReliableSnap;
  final bool predictionActive;

  /// Milliseconds since the last fresh engine/GPS basis behind the
  /// prediction; null when unknown (treated as stale).
  final int? predictionAgeMs;

  /// Camera confidence score 0..100 (NavConfidenceEngine.cameraScore).
  final double cameraScore;

  const NavCameraTargetInput({
    required this.followMode,
    this.manualRecenter = false,
    this.routeDeviationLikely = false,
    this.oppositeDirectionLikely = false,
    this.backwardProgressLikely = false,
    this.offRouteLikely = false,
    this.strongMismatchSuspected = false,
    this.hasReliableSnap = false,
    this.predictionActive = false,
    this.predictionAgeMs,
    this.cameraScore = 0.0,
  });

  bool get deviationActive =>
      routeDeviationLikely ||
      oppositeDirectionLikely ||
      backwardProgressLikely ||
      offRouteLikely ||
      strongMismatchSuspected;
}

class NavCameraTargetDecision {
  final NavCameraTargetSource source;
  final String reason;

  /// True when the camera target must be forced to the raw/live driver
  /// position because a route-deviation signal is active.
  final bool forceRawTarget;

  const NavCameraTargetDecision({
    required this.source,
    required this.reason,
    this.forceRawTarget = false,
  });

  String get sourceLabel {
    switch (source) {
      case NavCameraTargetSource.routeSnap:
        return 'route_snap';
      case NavCameraTargetSource.rawLive:
        return 'raw_live';
      case NavCameraTargetSource.prediction:
        return 'prediction';
      case NavCameraTargetSource.skipped:
        return 'skipped';
    }
  }
}

class NavCameraTargetPolicy {
  /// Prediction older than this may not drive the camera (marker/offline
  /// prediction may run longer; the camera stays conservative).
  static const int maxPredictionAgeMs = 1500;

  /// Existing camera prediction confidence gate (kept from NAV-R6/R7).
  static const double minPredictionCameraScore = 45.0;

  static NavCameraTargetDecision resolve(NavCameraTargetInput input) {
    if (!input.followMode && !input.manualRecenter) {
      return const NavCameraTargetDecision(
        source: NavCameraTargetSource.skipped,
        reason: 'not_follow_mode',
      );
    }

    if (input.deviationActive) {
      return NavCameraTargetDecision(
        source: NavCameraTargetSource.rawLive,
        reason: _deviationReason(input),
        forceRawTarget: true,
      );
    }

    if (input.predictionActive) {
      final ageMs = input.predictionAgeMs;
      final stale = ageMs == null || ageMs > maxPredictionAgeMs;
      final lowConfidence = input.cameraScore < minPredictionCameraScore;
      if (!stale && !lowConfidence) {
        return const NavCameraTargetDecision(
          source: NavCameraTargetSource.prediction,
          reason: 'prediction_fresh',
        );
      }
      final rejection = stale
          ? 'prediction_stale'
          : 'prediction_low_confidence';
      if (input.hasReliableSnap) {
        return NavCameraTargetDecision(
          source: NavCameraTargetSource.routeSnap,
          reason: rejection,
        );
      }
      return NavCameraTargetDecision(
        source: NavCameraTargetSource.rawLive,
        reason: rejection,
      );
    }

    if (input.hasReliableSnap) {
      return const NavCameraTargetDecision(
        source: NavCameraTargetSource.routeSnap,
        reason: 'reliable_route',
      );
    }

    return const NavCameraTargetDecision(
      source: NavCameraTargetSource.rawLive,
      reason: 'no_reliable_snap',
    );
  }

  static String _deviationReason(NavCameraTargetInput input) {
    // Neutral product wording: the route is adapting; never blame driving.
    if (input.oppositeDirectionLikely) return 'route_adaptation_opposite';
    if (input.backwardProgressLikely) return 'route_adaptation_backward';
    if (input.routeDeviationLikely) return 'route_adaptation';
    if (input.strongMismatchSuspected) return 'route_adaptation_mismatch';
    return 'off_route';
  }
}
