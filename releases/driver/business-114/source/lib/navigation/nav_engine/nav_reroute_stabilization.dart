/// FLUXIDI NAV-STREETLEVEL-FLUID-MOTION-2 (Phase 1, Part F): post-reroute
/// stabilisation gate.
///
/// After a successful route replacement, at least [freshSamplesRequired] fresh
/// GPS samples against the *new* route generation must be observed OR the
/// [cooldown] must elapse before another opposite-direction / backward-
/// progress reroute is permitted. Severe genuine deviation (large snap
/// distance OR strong opposite direction while moving fast) bypasses the gate
/// immediately.
///
/// The class is a pure, side-effect-free state machine. The widget wires:
///  * [noteRerouteApplied] into the reroute-apply hook,
///  * [observeSample] into the per-GPS-callback state update, and
///  * [allowOppositeDirectionReroute] into the reroute decision gate.
class NavRerouteStabilization {
  /// Number of fresh in-generation samples needed to satisfy the gate.
  static const int freshSamplesRequired = 2;

  /// Wall-clock timeout after which the gate opens even without fresh samples.
  static const Duration cooldown = Duration(seconds: 8);

  /// Snap distance (m) above which the gate is bypassed immediately.
  static const double severeSnapDistanceM = 100.0;

  /// Speed (km/h) above which a strong-opposite-direction bypasses the gate.
  static const double severeOppositeSpeedKmh = 25.0;

  int _postRerouteRouteGeneration = -1;
  int _freshSamplesCollected = 0;
  DateTime? _rerouteAppliedAt;

  int get postRerouteRouteGeneration => _postRerouteRouteGeneration;
  int get freshSamplesCollected => _freshSamplesCollected;
  DateTime? get rerouteAppliedAt => _rerouteAppliedAt;
  bool get stabilizationActive =>
      _postRerouteRouteGeneration >= 0 && _rerouteAppliedAt != null;

  /// Latch the gate: subsequent opposite-direction reroutes are blocked until
  /// the gate opens on fresh samples, cooldown, or a severe override.
  void noteRerouteApplied({
    required int newRouteGeneration,
    required DateTime now,
  }) {
    _postRerouteRouteGeneration = newRouteGeneration;
    _freshSamplesCollected = 0;
    _rerouteAppliedAt = now;
  }

  /// Records one GPS-derived route-progress sample. Only in-generation samples
  /// with a reliable snap contribute; old-route heading evidence can never
  /// satisfy the gate.
  void observeSample({
    required int routeGeneration,
    required double snapDistanceM,
    required bool hasReliableSnap,
  }) {
    if (!stabilizationActive) return;
    if (routeGeneration != _postRerouteRouteGeneration) return;
    if (!hasReliableSnap) return;
    _freshSamplesCollected += 1;
  }

  /// Returns true when the next opposite-direction / backward-progress
  /// reroute may fire.
  ///
  /// The gate opens when any of the following is true:
  ///   * the stabilisation window is not active (no recent reroute apply);
  ///   * the current route generation is not the one under stabilisation
  ///     (a newer reroute has already run through us);
  ///   * [freshSamplesCollected] >= [freshSamplesRequired];
  ///   * [cooldown] has elapsed since the reroute-apply timestamp;
  ///   * severe override: snap distance > [severeSnapDistanceM], OR
  ///     [oppositeStrong] && [speedKmh] > [severeOppositeSpeedKmh].
  bool allowOppositeDirectionReroute({
    required DateTime now,
    required double snapDistanceM,
    required bool oppositeStrong,
    required double speedKmh,
    required int currentRouteGeneration,
  }) {
    if (!stabilizationActive) return true;
    if (currentRouteGeneration != _postRerouteRouteGeneration) return true;
    if (snapDistanceM.isFinite && snapDistanceM > severeSnapDistanceM) {
      return true;
    }
    if (oppositeStrong && speedKmh > severeOppositeSpeedKmh) return true;
    if (_freshSamplesCollected >= freshSamplesRequired) return true;
    final appliedAt = _rerouteAppliedAt;
    if (appliedAt != null && now.difference(appliedAt) >= cooldown) return true;
    return false;
  }

  void reset() {
    _postRerouteRouteGeneration = -1;
    _freshSamplesCollected = 0;
    _rerouteAppliedAt = null;
  }
}
