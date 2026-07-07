import 'nav_bearing_policy.dart';

/// Smooths heading/bearing with correct 0..360 wrap-around.
class NavBearingSmoother {
  double? _lastBearing;
  String _lastSource = 'unknown';
  String _lastReason = 'unknown';
  bool _lastRouteBearingAllowed = false;

  void reset() {
    _lastBearing = null;
    _lastSource = 'unknown';
    _lastReason = 'unknown';
    _lastRouteBearingAllowed = false;
  }

  /// Source of the most recent [smooth] target before easing.
  String get lastSource => _lastSource;

  /// Bounded reason token from the last [smooth] call.
  String get lastReason => _lastReason;

  /// NAV-R12-C: whether route bearing was eligible on the last [smooth] call.
  bool get lastRouteBearingAllowed => _lastRouteBearingAllowed;

  /// Normalizes degrees to \[0, 360).
  static double normalizeBearing(double degrees) {
    var bearing = degrees % 360.0;
    if (bearing < 0) bearing += 360.0;
    return bearing;
  }

  /// Shortest signed delta from [from] to [to] in degrees.
  static double bearingDelta(double from, double to) {
    var delta = normalizeBearing(to) - normalizeBearing(from);
    if (delta > 180) delta -= 360;
    if (delta < -180) delta += 360;
    return delta;
  }

  /// Picks target bearing via [NavBearingPolicy], then eases toward it.
  double smooth({
    required double? rawHeading,
    required double? routeBearing,
    required double? speedKmh,
    bool hasReliableSnap = false,
    double? movementBearing,
    double? accuracyM,
    double? routeConfidence,
    bool offRouteLikely = false,
    bool trustBearing = true,
    bool trustRouteSnap = false,
    bool routeDeviationLikely = false,
    bool oppositeDirectionLikely = false,
    bool backwardProgressLikely = false,
    double? headingDeltaDeg,
    bool forwardProgress = true,
  }) {
    final policy = NavBearingPolicy.resolve(
      NavBearingPolicyInput(
        rawHeading: rawHeading,
        routeBearing: routeBearing,
        movementBearing: movementBearing,
        lastBearing: _lastBearing,
        speedKmh: speedKmh ?? 0.0,
        accuracyM: accuracyM,
        routeConfidence: routeConfidence,
        hasReliableSnap: hasReliableSnap,
        offRouteLikely: offRouteLikely,
        trustBearing: trustBearing,
        trustRouteSnap: trustRouteSnap,
        routeDeviationLikely: routeDeviationLikely,
        oppositeDirectionLikely: oppositeDirectionLikely,
        backwardProgressLikely: backwardProgressLikely,
        headingDeltaDeg: headingDeltaDeg,
        forwardProgress: forwardProgress,
      ),
    );

    _lastSource = _legacySourceLabel(policy.source);
    _lastReason = policy.reason;
    _lastRouteBearingAllowed = policy.routeBearingAllowed;

    final resolved = NavBearingPolicy.stepToward(
      previous: _lastBearing,
      target: policy.targetBearing,
      maxStepDeg: policy.maxStepDeg,
    );
    _lastBearing = resolved;
    return resolved;
  }

  static String _legacySourceLabel(String source) {
    switch (source) {
      case 'route':
        return 'route_segment';
      case 'gps':
        return 'gps_heading';
      case 'last':
        return 'last_stable';
      default:
        return 'fallback';
    }
  }
}
