import 'dart:math' as math;

/// Signals for unified navigation reliability scoring.
class NavConfidenceInput {
  final DateTime timestamp;
  final double? gpsAccuracyM;
  final double? speedKmh;
  final double? routeConfidence;
  final double? snapDistanceM;
  final bool hasReliableSnap;
  final bool offRouteLikely;
  final bool forwardProgress;
  final double? headingDeltaDeg;
  final bool liveRideActive;

  const NavConfidenceInput({
    required this.timestamp,
    this.gpsAccuracyM,
    this.speedKmh,
    this.routeConfidence,
    this.snapDistanceM,
    this.hasReliableSnap = false,
    this.offRouteLikely = false,
    this.forwardProgress = true,
    this.headingDeltaDeg,
    this.liveRideActive = false,
  });
}

/// Unified reliability scores and trust flags for marker/camera/instructions.
class NavConfidenceOutput {
  final double gpsScore;
  final double routeScore;
  final double headingScore;
  final double motionScore;
  final double cameraScore;
  final double instructionScore;
  final double overallScore;
  final bool trustRouteSnap;
  final bool trustBearing;
  final bool trustInstruction;
  final bool allowCameraAggression;
  final String reason;

  const NavConfidenceOutput({
    required this.gpsScore,
    required this.routeScore,
    required this.headingScore,
    required this.motionScore,
    required this.cameraScore,
    required this.instructionScore,
    required this.overallScore,
    required this.trustRouteSnap,
    required this.trustBearing,
    required this.trustInstruction,
    required this.allowCameraAggression,
    required this.reason,
  });
}

/// Central confidence layer for driver navigation decisions.
class DriverNavConfidenceEngine {
  NavConfidenceOutput? _previousOutput;

  void reset() {
    _previousOutput = null;
  }

  NavConfidenceOutput update(NavConfidenceInput input) {
    final gpsScore = _gpsScoreFor(input.gpsAccuracyM);
    final routeScore = _routeScoreFor(input);
    final headingScore = _headingScoreFor(input);
    final motionScore = _motionScoreFor(input);
    final cameraScore = _cameraScoreFor(
      gpsScore: gpsScore,
      routeScore: routeScore,
      headingScore: headingScore,
      motionScore: motionScore,
      input: input,
    );
    final instructionScore = _instructionScoreFor(
      gpsScore: gpsScore,
      routeScore: routeScore,
      headingScore: headingScore,
      motionScore: motionScore,
      input: input,
    );

    final overallScore = (
      gpsScore * 0.20 +
      routeScore * 0.30 +
      headingScore * 0.15 +
      motionScore * 0.20 +
      cameraScore * 0.15
    ).clamp(0.0, 100.0);

    final trustRouteSnap =
        routeScore >= 55.0 && !input.offRouteLikely && input.hasReliableSnap;
    final trustBearing = headingScore >= 50.0 || routeScore >= 65.0;
    final trustInstruction =
        instructionScore >= 65.0 && !input.offRouteLikely;
    final allowCameraAggression =
        overallScore >= 70.0 && input.hasReliableSnap && !input.offRouteLikely;

    final reason = _reasonFor(
      input: input,
      overallScore: overallScore,
      trustRouteSnap: trustRouteSnap,
      trustInstruction: trustInstruction,
      allowCameraAggression: allowCameraAggression,
    );

    final output = NavConfidenceOutput(
      gpsScore: gpsScore,
      routeScore: routeScore,
      headingScore: headingScore,
      motionScore: motionScore,
      cameraScore: cameraScore,
      instructionScore: instructionScore,
      overallScore: overallScore,
      trustRouteSnap: trustRouteSnap,
      trustBearing: trustBearing,
      trustInstruction: trustInstruction,
      allowCameraAggression: allowCameraAggression,
      reason: reason,
    );
    _previousOutput = output;
    return output;
  }

  static double _gpsScoreFor(double? accuracyM) {
    if (accuracyM == null || !accuracyM.isFinite || accuracyM <= 0) {
      return 70.0;
    }
    if (accuracyM <= 8.0) return 100.0;
    if (accuracyM <= 20.0) return 85.0;
    if (accuracyM <= 40.0) return 65.0;
    if (accuracyM <= 60.0) return 40.0;
    return 15.0;
  }

  static double _routeScoreFor(NavConfidenceInput input) {
    if (!input.liveRideActive) return 0.0;

    var score = input.routeConfidence ?? 0.0;
    if (!input.hasReliableSnap) {
      score = math.min(score, 45.0);
    }
    if (input.offRouteLikely) {
      score = math.min(score, 30.0);
    }
    if (!input.forwardProgress) {
      score = math.min(score, 40.0);
    }

    final snapDist = input.snapDistanceM;
    if (snapDist != null && snapDist.isFinite) {
      if (snapDist <= 8.0) {
        score = math.max(score, 90.0);
      } else if (snapDist <= 20.0) {
        score = math.max(score, 75.0);
      } else if (snapDist <= 40.0) {
        score = math.min(score, 70.0);
      } else if (snapDist > 60.0) {
        score = math.min(score, 35.0);
      }
    }

    return score.clamp(0.0, 100.0);
  }

  static double _headingScoreFor(NavConfidenceInput input) {
    final delta = input.headingDeltaDeg;
    if (delta == null || !delta.isFinite) return 75.0;

    final speed = math.max(0.0, input.speedKmh ?? 0.0);
    final absDelta = delta.abs();

    if (speed < 3.0) return 80.0;

    if (speed >= 8.0) {
      if (absDelta <= 25.0) return 100.0;
      if (absDelta <= 45.0) return 75.0;
      if (absDelta <= 70.0) return 50.0;
      if (absDelta <= 100.0) return 30.0;
      return 10.0;
    }

    if (absDelta <= 35.0) return 90.0;
    if (absDelta <= 60.0) return 70.0;
    if (absDelta <= 90.0) return 50.0;
    return 30.0;
  }

  static double _motionScoreFor(NavConfidenceInput input) {
    if (!input.liveRideActive) return 0.0;
    if (input.offRouteLikely) return 20.0;
    if (!input.forwardProgress) return 35.0;
    final speed = input.speedKmh ?? 0.0;
    if (speed.isFinite && speed < 3.0) return 75.0;
    return 85.0;
  }

  static double _cameraScoreFor({
    required double gpsScore,
    required double routeScore,
    required double headingScore,
    required double motionScore,
    required NavConfidenceInput input,
  }) {
    if (!input.liveRideActive) return 0.0;
    if (input.offRouteLikely) return 20.0;

    final blended = (
      gpsScore * 0.25 +
      routeScore * 0.35 +
      headingScore * 0.20 +
      motionScore * 0.20
    ).clamp(0.0, 100.0);

    if (!input.hasReliableSnap) {
      return math.min(blended, 50.0);
    }
    if (routeScore < 45.0) {
      return math.min(blended, 40.0);
    }
    return blended;
  }

  static double _instructionScoreFor({
    required double gpsScore,
    required double routeScore,
    required double headingScore,
    required double motionScore,
    required NavConfidenceInput input,
  }) {
    if (!input.liveRideActive) return 0.0;
    if (input.offRouteLikely) return 15.0;

    var score = (
      routeScore * 0.40 +
      headingScore * 0.25 +
      gpsScore * 0.15 +
      motionScore * 0.20
    ).clamp(0.0, 100.0);

    if (!input.hasReliableSnap) {
      score = math.min(score, 45.0);
    }
    if (routeScore < 55.0) {
      score = math.min(score, 50.0);
    }
    if (headingScore < 45.0 && (input.speedKmh ?? 0.0) >= 8.0) {
      score = math.min(score, 40.0);
    }
    if (!input.forwardProgress) {
      score = math.min(score, 45.0);
    }
    return score;
  }

  static String _reasonFor({
    required NavConfidenceInput input,
    required double overallScore,
    required bool trustRouteSnap,
    required bool trustInstruction,
    required bool allowCameraAggression,
  }) {
    if (!input.liveRideActive) return 'inactive';
    if (input.offRouteLikely) return 'off_route';
    if (!trustRouteSnap) return 'low_route_trust';
    if (!trustInstruction) return 'low_instruction_trust';
    if (!allowCameraAggression) return 'cautious_camera';
    if (overallScore >= 80.0) return 'high_confidence';
    if (overallScore >= 60.0) return 'moderate_confidence';
    return 'low_confidence';
  }
}
