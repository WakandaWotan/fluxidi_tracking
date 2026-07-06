import 'dart:math' as math;

/// A point on the active navigation route polyline.
class NavRoutePoint {
  final double latitude;
  final double longitude;

  const NavRoutePoint({
    required this.latitude,
    required this.longitude,
  });
}

/// Raw GPS + route geometry for route-progress evaluation.
class NavRouteProgressInput {
  final DateTime timestamp;
  final double rawLatitude;
  final double rawLongitude;
  final double? rawHeading;
  final double? speedKmh;
  final double? accuracyM;
  final List<NavRoutePoint> routePoints;

  const NavRouteProgressInput({
    required this.timestamp,
    required this.rawLatitude,
    required this.rawLongitude,
    this.rawHeading,
    this.speedKmh,
    this.accuracyM,
    required this.routePoints,
  });
}

/// Confidence-aware route snap and progress along the polyline.
class NavRouteProgressOutput {
  final bool hasReliableSnap;
  final double? snappedLatitude;
  final double? snappedLongitude;
  final int? segmentIndex;
  final double snapDistanceM;
  final double confidence;
  final double? distanceAlongRouteM;
  final bool forwardProgress;
  final bool offRouteLikely;
  final String reason;

  const NavRouteProgressOutput({
    required this.hasReliableSnap,
    this.snappedLatitude,
    this.snappedLongitude,
    this.segmentIndex,
    required this.snapDistanceM,
    required this.confidence,
    this.distanceAlongRouteM,
    required this.forwardProgress,
    required this.offRouteLikely,
    required this.reason,
  });
}

class _ProjectionCandidate {
  final double latitude;
  final double longitude;
  final int segmentIndex;
  final double segmentT;
  final double snapDistanceM;
  final double distanceAlongRouteM;
  final double? segmentBearing;

  const _ProjectionCandidate({
    required this.latitude,
    required this.longitude,
    required this.segmentIndex,
    required this.segmentT,
    required this.snapDistanceM,
    required this.distanceAlongRouteM,
    required this.segmentBearing,
  });
}

/// Stateful route progress tracker with segment-window projection and confidence.
class DriverNavRouteProgress {
  static const int _segmentWindow = 25;
  static const int _lowConfidenceOffRouteThreshold = 2;

  int? _previousSegmentIndex;
  int? _lastReliableSegmentIndex;
  double? _lastDistanceAlongRouteM;
  int _lowConfidenceStreak = 0;
  bool _routeWasReset = true;

  void reset() {
    _previousSegmentIndex = null;
    _lastReliableSegmentIndex = null;
    _lastDistanceAlongRouteM = null;
    _lowConfidenceStreak = 0;
    _routeWasReset = true;
  }

  NavRouteProgressOutput update(NavRouteProgressInput input) {
    final points = input.routePoints;
    if (points.length < 2) {
      return const NavRouteProgressOutput(
        hasReliableSnap: false,
        snapDistanceM: double.infinity,
        confidence: 0,
        forwardProgress: true,
        offRouteLikely: false,
        reason: 'route_too_short',
      );
    }

    final centerSegment = _previousSegmentIndex ?? _lastReliableSegmentIndex;
    var candidate = _projectOntoRoute(
      routePoints: points,
      rawLat: input.rawLatitude,
      rawLon: input.rawLongitude,
      centerSegmentIndex: centerSegment,
    );

    if (candidate == null) {
      return const NavRouteProgressOutput(
        hasReliableSnap: false,
        snapDistanceM: double.infinity,
        confidence: 0,
        forwardProgress: true,
        offRouteLikely: false,
        reason: 'projection_failed',
      );
    }

    final speedKmh = math.max(0.0, input.speedKmh ?? 0.0);
    final accuracyM = input.accuracyM;

    var confidence = _computeConfidence(
      snapDistanceM: candidate.snapDistanceM,
      accuracyM: accuracyM,
      rawHeading: input.rawHeading,
      segmentBearing: candidate.segmentBearing,
      speedKmh: speedKmh,
    );

    final forwardEval = _evaluateForwardProgress(
      candidate: candidate,
      speedKmh: speedKmh,
    );
    var forwardProgress = forwardEval.forwardProgress;
    confidence = (confidence + forwardEval.confidenceAdjust).clamp(0.0, 100.0);

    final largeBackwardTeleport = forwardEval.largeBackwardTeleport;
    final allowBackwardException = _allowBackwardException(
      confidence: confidence,
      snapDistanceM: candidate.snapDistanceM,
      rawHeading: input.rawHeading,
      segmentBearing: candidate.segmentBearing,
      speedKmh: speedKmh,
    );

    if (largeBackwardTeleport && !allowBackwardException) {
      forwardProgress = false;
      confidence = (confidence - 20.0).clamp(0.0, 100.0);
    }

    final maxSnapDist = _maxReliableSnapDistanceM(accuracyM);
    var hasReliableSnap = confidence >= 55.0 &&
        candidate.snapDistanceM <= maxSnapDist &&
        forwardProgress &&
        (!largeBackwardTeleport || allowBackwardException);

    if (_routeWasReset && candidate.snapDistanceM <= maxSnapDist + 10.0) {
      hasReliableSnap = confidence >= 50.0 && candidate.snapDistanceM <= maxSnapDist;
    }

    if (hasReliableSnap) {
      _lastReliableSegmentIndex = candidate.segmentIndex;
      _lastDistanceAlongRouteM = candidate.distanceAlongRouteM;
      _routeWasReset = false;
    }

    _previousSegmentIndex = candidate.segmentIndex;

    if (candidate.snapDistanceM > 58.0 || confidence < 40.0) {
      _lowConfidenceStreak += 1;
    } else {
      _lowConfidenceStreak = 0;
    }
    final offRouteLikely =
        candidate.snapDistanceM > 58.0 ||
        _lowConfidenceStreak >= _lowConfidenceOffRouteThreshold;

    final reason = _reasonFor(
      hasReliableSnap: hasReliableSnap,
      snapDistanceM: candidate.snapDistanceM,
      confidence: confidence,
      forwardProgress: forwardProgress,
      offRouteLikely: offRouteLikely,
      largeBackwardTeleport: largeBackwardTeleport,
    );

    return NavRouteProgressOutput(
      hasReliableSnap: hasReliableSnap,
      snappedLatitude: candidate.latitude,
      snappedLongitude: candidate.longitude,
      segmentIndex: candidate.segmentIndex,
      snapDistanceM: candidate.snapDistanceM,
      confidence: confidence,
      distanceAlongRouteM: candidate.distanceAlongRouteM,
      forwardProgress: forwardProgress,
      offRouteLikely: offRouteLikely,
      reason: reason,
    );
  }

  static double _maxReliableSnapDistanceM(double? accuracyM) {
    if (accuracyM != null && accuracyM.isFinite && accuracyM > 0) {
      return math.max(45.0, accuracyM + 20.0);
    }
    return 45.0;
  }

  _ProjectionCandidate? _projectOntoRoute({
    required List<NavRoutePoint> routePoints,
    required double rawLat,
    required double rawLon,
    int? centerSegmentIndex,
  }) {
    final lastSeg = routePoints.length - 2;
    if (lastSeg < 0) return null;

    _ProjectionCandidate? best;
    if (centerSegmentIndex != null) {
      final start = math.max(0, centerSegmentIndex - _segmentWindow);
      final end = math.min(lastSeg, centerSegmentIndex + _segmentWindow);
      best = _scanSegments(
        routePoints: routePoints,
        rawLat: rawLat,
        rawLon: rawLon,
        startSegment: start,
        endSegment: end,
      );
      if (best != null && best.snapDistanceM > 55.0) {
        final full = _scanSegments(
          routePoints: routePoints,
          rawLat: rawLat,
          rawLon: rawLon,
          startSegment: 0,
          endSegment: lastSeg,
        );
        if (full != null && full.snapDistanceM + 5.0 < best.snapDistanceM) {
          best = full;
        }
      }
    } else {
      best = _scanSegments(
        routePoints: routePoints,
        rawLat: rawLat,
        rawLon: rawLon,
        startSegment: 0,
        endSegment: lastSeg,
      );
    }
    return best;
  }

  _ProjectionCandidate? _scanSegments({
    required List<NavRoutePoint> routePoints,
    required double rawLat,
    required double rawLon,
    required int startSegment,
    required int endSegment,
  }) {
    final refLatRad = rawLat * math.pi / 180.0;
    const metersPerDegLat = 111320.0;
    final metersPerDegLon =
        math.max(1.0, metersPerDegLat * math.cos(refLatRad));

    var bestDistance = double.infinity;
    var bestAlong = 0.0;
    var bestSegment = startSegment;
    var bestT = 0.0;
    double? bestLat;
    double? bestLon;
    double? bestSegmentBearing;

    var cumulative = 0.0;
    for (var i = 0; i < routePoints.length - 1; i++) {
      final a = routePoints[i];
      final b = routePoints[i + 1];
      final segmentMeters = _haversineMeters(
        a.latitude,
        a.longitude,
        b.latitude,
        b.longitude,
      );

      if (i >= startSegment && i <= endSegment) {
        final ax = (a.longitude - rawLon) * metersPerDegLon;
        final ay = (a.latitude - rawLat) * metersPerDegLat;
        final bx = (b.longitude - rawLon) * metersPerDegLon;
        final by = (b.latitude - rawLat) * metersPerDegLat;
        final vx = bx - ax;
        final vy = by - ay;
        final len2 = vx * vx + vy * vy;
        final t = len2 <= 0 ? 0.0 : ((-ax * vx - ay * vy) / len2).clamp(0.0, 1.0);
        final px = ax + vx * t;
        final py = ay + vy * t;
        final approxDistance = math.sqrt(px * px + py * py);
        if (approxDistance < bestDistance) {
          bestDistance = approxDistance;
          bestAlong = cumulative + segmentMeters * t;
          bestSegment = i;
          bestT = t;
          bestLat = a.latitude + (b.latitude - a.latitude) * t;
          bestLon = a.longitude + (b.longitude - a.longitude) * t;
          bestSegmentBearing = _bearingFromPoints(
            a.latitude,
            a.longitude,
            b.latitude,
            b.longitude,
          );
        }
      }
      cumulative += segmentMeters;
    }

    if (bestLat == null || bestLon == null || !bestDistance.isFinite) {
      return null;
    }

    return _ProjectionCandidate(
      latitude: bestLat,
      longitude: bestLon,
      segmentIndex: bestSegment,
      segmentT: bestT,
      snapDistanceM: bestDistance,
      distanceAlongRouteM: bestAlong,
      segmentBearing: bestSegmentBearing,
    );
  }

  static double _haversineMeters(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const earthRadiusM = 6371000.0;
    final phi1 = lat1 * math.pi / 180.0;
    final phi2 = lat2 * math.pi / 180.0;
    final dPhi = (lat2 - lat1) * math.pi / 180.0;
    final dLambda = (lon2 - lon1) * math.pi / 180.0;
    final a = math.sin(dPhi / 2) * math.sin(dPhi / 2) +
        math.cos(phi1) *
            math.cos(phi2) *
            math.sin(dLambda / 2) *
            math.sin(dLambda / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadiusM * c;
  }

  static double? _bearingFromPoints(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const degToRad = math.pi / 180.0;
    const radToDeg = 180.0 / math.pi;
    final dLon = (lon2 - lon1) * degToRad;
    final y = math.sin(dLon) * math.cos(lat2 * degToRad);
    final x = math.cos(lat1 * degToRad) * math.sin(lat2 * degToRad) -
        math.sin(lat1 * degToRad) * math.cos(lat2 * degToRad) * math.cos(dLon);
    if (!x.isFinite || !y.isFinite) return null;
    final brng = math.atan2(y, x) * radToDeg;
    return (brng + 360.0) % 360.0;
  }

  static double _bearingDiff(double a, double b) {
    var delta = (a - b) % 360.0;
    if (delta > 180.0) delta -= 360.0;
    if (delta < -180.0) delta += 360.0;
    return delta;
  }

  static double _computeConfidence({
    required double snapDistanceM,
    required double? accuracyM,
    required double? rawHeading,
    required double? segmentBearing,
    required double speedKmh,
  }) {
    final snapScore = _snapDistanceScore(snapDistanceM);
    final accuracyScore = _accuracyScore(accuracyM);
    final headingScore = _headingScore(
      rawHeading: rawHeading,
      segmentBearing: segmentBearing,
      speedKmh: speedKmh,
    );

    return (snapScore * 0.45 + accuracyScore * 0.25 + headingScore * 0.30)
        .clamp(0.0, 100.0);
  }

  static double _snapDistanceScore(double distanceM) {
    if (distanceM <= 8.0) return 100.0;
    if (distanceM <= 20.0) return 85.0;
    if (distanceM <= 40.0) return 65.0;
    if (distanceM <= 60.0) return 40.0;
    return 15.0;
  }

  static double _accuracyScore(double? accuracyM) {
    if (accuracyM == null || !accuracyM.isFinite || accuracyM <= 0) {
      return 70.0;
    }
    if (accuracyM <= 12.0) return 100.0;
    if (accuracyM <= 20.0) return 85.0;
    if (accuracyM <= 35.0) return 65.0;
    if (accuracyM <= 50.0) return 45.0;
    return 25.0;
  }

  static double _headingScore({
    required double? rawHeading,
    required double? segmentBearing,
    required double speedKmh,
  }) {
    if (speedKmh < 8.0 ||
        rawHeading == null ||
        segmentBearing == null ||
        !rawHeading.isFinite ||
        !segmentBearing.isFinite) {
      return 80.0;
    }
    final diff = _bearingDiff(rawHeading, segmentBearing).abs();
    if (diff <= 25.0) return 100.0;
    if (diff <= 45.0) return 75.0;
    if (diff <= 70.0) return 50.0;
    if (diff <= 100.0) return 30.0;
    return 10.0;
  }

  ({
    bool forwardProgress,
    bool largeBackwardTeleport,
    double confidenceAdjust,
  }) _evaluateForwardProgress({
    required _ProjectionCandidate candidate,
    required double speedKmh,
  }) {
    if (_routeWasReset || _lastDistanceAlongRouteM == null) {
      return (
        forwardProgress: true,
        largeBackwardTeleport: false,
        confidenceAdjust: 0.0,
      );
    }

    final backwardM = _lastDistanceAlongRouteM! - candidate.distanceAlongRouteM;
    final lastSeg = _lastReliableSegmentIndex ?? _previousSegmentIndex ?? 0;
    final segmentBack = lastSeg - candidate.segmentIndex;
    final backwardToleranceM = speedKmh < 6.0 ? 35.0 : 22.0;

    var forwardProgress = true;
    var confidenceAdjust = 0.0;
    var largeBackwardTeleport = false;

    if (segmentBack > 5 || backwardM > 80.0) {
      largeBackwardTeleport = true;
      forwardProgress = false;
      confidenceAdjust = -25.0;
    } else if (segmentBack > 3 || backwardM > 40.0) {
      forwardProgress = false;
      confidenceAdjust = -20.0;
    } else if (segmentBack > 1 || backwardM > backwardToleranceM) {
      confidenceAdjust = -12.0;
      if (backwardM > backwardToleranceM + 10.0) {
        forwardProgress = false;
      }
    }

    return (
      forwardProgress: forwardProgress,
      largeBackwardTeleport: largeBackwardTeleport,
      confidenceAdjust: confidenceAdjust,
    );
  }

  static bool _allowBackwardException({
    required double confidence,
    required double snapDistanceM,
    required double? rawHeading,
    required double? segmentBearing,
    required double speedKmh,
  }) {
    if (confidence < 85.0 || snapDistanceM > 15.0) return false;
    if (speedKmh < 8.0 ||
        rawHeading == null ||
        segmentBearing == null ||
        !rawHeading.isFinite ||
        !segmentBearing.isFinite) {
      return confidence >= 90.0 && snapDistanceM <= 10.0;
    }
    return _bearingDiff(rawHeading, segmentBearing).abs() <= 35.0;
  }

  static String _reasonFor({
    required bool hasReliableSnap,
    required double snapDistanceM,
    required double confidence,
    required bool forwardProgress,
    required bool offRouteLikely,
    required bool largeBackwardTeleport,
  }) {
    if (hasReliableSnap) return 'reliable_snap';
    if (offRouteLikely) return 'off_route_likely';
    if (largeBackwardTeleport) return 'backward_teleport';
    if (!forwardProgress) return 'backward_progress';
    if (confidence < 55.0) return 'low_confidence';
    if (snapDistanceM > _maxReliableSnapDistanceM(null)) {
      return 'snap_too_far';
    }
    return 'unreliable';
  }
}
