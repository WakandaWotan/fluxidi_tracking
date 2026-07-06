/// Smooths heading/bearing with correct 0..360 wrap-around.
class NavBearingSmoother {
  double? _lastBearing;

  void reset() {
    _lastBearing = null;
  }

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

  /// Picks target bearing, then eases toward it without 359°→1° backward spins.
  double smooth({
    required double? rawHeading,
    required double? routeBearing,
    required double? speedKmh,
  }) {
    final speed = speedKmh ?? 0.0;
    double? target;

    // Prefer route segment bearing when moving fast enough.
    if (speed >= 5.0 &&
        routeBearing != null &&
        routeBearing.isFinite &&
        routeBearing >= 0) {
      target = normalizeBearing(routeBearing);
    } else if (rawHeading != null &&
        rawHeading.isFinite &&
        rawHeading >= 0) {
      target = normalizeBearing(rawHeading);
    } else if (_lastBearing != null && _lastBearing!.isFinite) {
      target = _lastBearing!;
    } else {
      target = 0.0;
    }

    final previous = _lastBearing;
    if (previous == null || !previous.isFinite) {
      _lastBearing = target;
      return target;
    }

    // Larger steps when moving faster; tiny steps when creeping.
    final maxStep = speed >= 25
        ? 28.0
        : (speed >= 8 ? 18.0 : (speed >= 3.5 ? 10.0 : 6.0));
    final delta = bearingDelta(previous, target);
    final stepped = previous + delta.clamp(-maxStep, maxStep);
    final resolved = normalizeBearing(stepped);
    _lastBearing = resolved;
    return resolved;
  }
}
