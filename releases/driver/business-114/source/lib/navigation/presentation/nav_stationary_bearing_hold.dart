// NAV-PRESTART-PREVIEW-AND-STABLE-BEARING-P0 — Problem 2
//
// Pure, side-effect-free bearing stabilisation for the Street Level driving
// camera. This module exists because the previous pipeline adopted a *new*
// bearing target on every GPS fix even while the vehicle was completely
// stationary:
//
//   * `applyDriverCockpitStreetlevelBearingLock` used the route tangent as the
//     primary target whenever a tangent existed, so its low-speed hold branch
//     was unreachable with a route loaded;
//   * `resolveDriverRouteBearing` fell back to raw `Position.heading`, which
//     geolocator reports as noise at speed 0;
//   * the nearest route-segment index oscillates around the origin, so the
//     tangent itself flipped back and forth between fixes.
//
// The downstream `NavStreetlevelBearingController` is a *bounded smoother*, not
// a gate: it is required to keep rotating for a genuine low-speed route-tangent
// turn. Stabilisation therefore has to happen here, at target resolution, by
// refusing to move the target at all until movement is trustworthy.
//
// Owns no widget state, no Mapbox handle and no timers.

import 'dart:math' as math;

import '../driver_navigation_geometry.dart';
import '../driver_navigation_models.dart';

/// Speed at/above which a *moving* bearing source (GPS course, movement delta,
/// re-targeted route tangent) becomes eligible at all.
const double kNavBearingMovingEligibleSpeedKmh = 4.0;

/// Shortest route segment (metres) considered "meaningful" for the initial
/// bearing at START. Encoded polylines frequently begin with sub-metre stubs
/// whose azimuth is arbitrary; skipping them is what keeps the opening camera
/// orientation stable.
const double kNavBearingMeaningfulSegmentMinMeters = 5.0;

/// Speed below which the vehicle is treated as stationary or creeping. Between
/// this and [kNavBearingMovingEligibleSpeedKmh] the last reliable bearing is
/// held: enough to cover traffic lights and stop-and-go without spinning.
const double kNavBearingStationarySpeedKmh = 2.0;

/// Displacement (metres) since the last accepted bearing anchor required before
/// movement is trusted, independent of the reported speed. GPS noise while
/// parked is typically well under this.
const double kNavBearingMovingEligibleDisplacementM = 5.0;

/// Worst horizontal accuracy (metres) at which a moving bearing may be
/// accepted. A 60 m fix cannot authorise a camera rotation.
const double kNavBearingMaxAccuracyM = 25.0;

/// Consecutive eligible fixes required before a moving bearing is trusted, so a
/// single noisy fix cannot unlock rotation.
const int kNavBearingMovingConfidenceFixes = 2;

/// Maximum camera rotation rate (degrees per second) applied on top of the
/// per-tick smoothing caps. Bounds how fast a legitimate re-target may sweep.
const double kNavBearingMaxRotationRateDegPerSec = 45.0;

/// Reference tick (ms) the rotation-rate clamp is expressed against.
const double kNavBearingRotationRateReferenceTickMs = 1000.0;

/// Where a resolved bearing came from. PII-free — safe for diagnostics.
enum NavBearingSource {
  /// Stable initial bearing taken from the first meaningful route segment at
  /// START, before any movement exists.
  initialRouteSegment,

  /// Route tangent re-targeted while moving.
  routeTangent,

  /// Raw GPS course, accepted only once movement is trustworthy.
  gpsCourse,

  /// Bearing derived from displacement between fixes.
  movementDelta,

  /// The previously accepted bearing, deliberately unchanged.
  held,
}

/// PII-free label for [NavBearingSource].
String navBearingSourceLabel(NavBearingSource source) {
  switch (source) {
    case NavBearingSource.initialRouteSegment:
      return 'initial_route_segment';
    case NavBearingSource.routeTangent:
      return 'route_tangent';
    case NavBearingSource.gpsCourse:
      return 'gps_course';
    case NavBearingSource.movementDelta:
      return 'movement_delta';
    case NavBearingSource.held:
      return 'held';
  }
}

double navBearingNormalize(double bearing) {
  if (!bearing.isFinite) return 0.0;
  var b = bearing % 360.0;
  if (b < 0) b += 360.0;
  return b;
}

/// Signed shortest angular delta from [from] to [to] in (-180, 180]. This is
/// the circular-smoothing primitive: 359 -> 1 yields +2, never -358.
double navBearingShortestDelta(double from, double to) {
  var delta = (navBearingNormalize(to) - navBearingNormalize(from)) % 360.0;
  if (delta > 180.0) delta -= 360.0;
  if (delta < -180.0) delta += 360.0;
  return delta;
}

/// Advances [previousDeg] toward [targetDeg] along the short arc, bounded by
/// [maxRotationRateDegPerSec] over [dtMs]. Pure.
double navBearingRateClampedStep({
  required double? previousDeg,
  required double targetDeg,
  double maxRotationRateDegPerSec = kNavBearingMaxRotationRateDegPerSec,
  double dtMs = kNavBearingRotationRateReferenceTickMs,
}) {
  final target = navBearingNormalize(targetDeg);
  if (previousDeg == null || !previousDeg.isFinite) return target;
  final previous = navBearingNormalize(previousDeg);
  if (!dtMs.isFinite || dtMs <= 0) return previous;
  final maxStep =
      maxRotationRateDegPerSec * (dtMs / kNavBearingRotationRateReferenceTickMs);
  if (!maxStep.isFinite || maxStep <= 0) return previous;
  final delta = navBearingShortestDelta(previous, target);
  if (delta.abs() <= maxStep) return target;
  return navBearingNormalize(previous + maxStep * delta.sign);
}

/// Whether the route tangent may be re-targeted for [candidateSegmentIndex].
///
/// While slow, the nearest-segment index oscillates around the origin (…0, 1,
/// 0, 1…) purely from GPS noise, and each flip produces a materially different
/// tangent. Below [kNavBearingMovingEligibleSpeedKmh] a re-target therefore
/// requires the index to have genuinely *advanced* past the accepted one;
/// going backwards or standing still keeps the accepted tangent.
bool navRouteSegmentTangentRetargetAllowed({
  required int? acceptedSegmentIndex,
  required int? candidateSegmentIndex,
  required double speedKmh,
}) {
  if (candidateSegmentIndex == null) return false;
  if (acceptedSegmentIndex == null) return true;
  if (speedKmh.isFinite && speedKmh >= kNavBearingMovingEligibleSpeedKmh) {
    return true;
  }
  return candidateSegmentIndex > acceptedSegmentIndex;
}

/// Whether a moving bearing source may be trusted for this fix.
bool navBearingMovementTrustworthy({
  required double speedKmh,
  double? displacementM,
  double? accuracyM,
}) {
  if (accuracyM != null &&
      accuracyM.isFinite &&
      accuracyM > kNavBearingMaxAccuracyM) {
    return false;
  }
  if (speedKmh.isFinite && speedKmh >= kNavBearingMovingEligibleSpeedKmh) {
    return true;
  }
  if (displacementM != null &&
      displacementM.isFinite &&
      displacementM >= kNavBearingMovingEligibleDisplacementM) {
    return true;
  }
  return false;
}

/// Whether a raw GPS course value is structurally usable. Geolocator reports
/// -1 (and on some devices 0 with no fix) when course is unknown.
bool navBearingGpsCourseUsable(double? gpsHeadingDeg) {
  return gpsHeadingDeg != null && gpsHeadingDeg.isFinite && gpsHeadingDeg >= 0;
}

/// Bearing of the first route segment long enough to carry a trustworthy
/// azimuth, walking forward from [startIndex]. Used to resolve the stable
/// initial camera orientation at START, before any movement exists.
///
/// Returns null when the geometry has no segment reaching
/// [minSegmentMeters]; the caller then falls back to the overall
/// first-to-last direction rather than a sub-metre stub.
double? navFirstMeaningfulRouteSegmentBearing(
  List<DriverLonLat> routeCoords, {
  int startIndex = 0,
  double minSegmentMeters = kNavBearingMeaningfulSegmentMinMeters,
}) {
  if (routeCoords.length < 2) return null;
  final from = startIndex.clamp(0, routeCoords.length - 2);
  final origin = routeCoords[from];
  for (var i = from + 1; i < routeCoords.length; i++) {
    final candidate = routeCoords[i];
    if (driverMetersBetween(origin, candidate) >= minSegmentMeters) {
      return driverBearingFromPoints(
        origin.lat,
        origin.lon,
        candidate.lat,
        candidate.lon,
      );
    }
  }
  final last = routeCoords.last;
  return driverBearingFromPoints(origin.lat, origin.lon, last.lat, last.lon);
}

/// Input for one [NavStationaryBearingGate] resolution.
class NavStationaryBearingInput {
  const NavStationaryBearingInput({
    required this.speedKmh,
    this.routeTangentBearingDeg,
    this.routeSegmentIndex,
    this.gpsHeadingDeg,
    this.movementBearingDeg,
    this.travelBearingDeg,
    this.displacementM,
    this.accuracyM,
    this.dtMs = kNavBearingRotationRateReferenceTickMs,
    this.allowRouteTangent = true,
    this.travelAuthority = false,
    this.maxRotationRateDegPerSec = kNavBearingMaxRotationRateDegPerSec,
  });

  final double speedKmh;

  /// Forward tangent of the current route segment, when a reliable snap exists.
  final double? routeTangentBearingDeg;

  /// Nearest route-segment index for this fix (drives origin hysteresis).
  final int? routeSegmentIndex;

  /// Raw course-over-ground reported by the platform.
  final double? gpsHeadingDeg;

  /// Bearing derived from displacement between consecutive fixes.
  final double? movementBearingDeg;

  /// Predicted / interpolated travel bearing between GPS samples. Used when
  /// route tangent authority is revoked (deviation / reroute-pending).
  final double? travelBearingDeg;

  /// Metres travelled since the last accepted bearing anchor.
  final double? displacementM;

  /// Reported horizontal accuracy in metres.
  final double? accuracyM;

  /// Wall-clock interval since the previous resolution, for the rate clamp.
  final double dtMs;

  /// When false, old/current route tangent cannot drive the camera bearing.
  final bool allowRouteTangent;

  /// When true, travel/GPS may unlock the multi-fix streak early on a
  /// meaningful heading change *after* movement is already trustworthy, and
  /// uses a higher rotation-rate ceiling. Standstill GPS noise alone must
  /// never unlock via this flag.
  final bool travelAuthority;

  /// Per-resolve rotation-rate ceiling (deg/s).
  final double maxRotationRateDegPerSec;
}

/// Outcome of one resolution. [held] is true when the gate deliberately refused
/// to move the bearing.
class NavStationaryBearingDecision {
  const NavStationaryBearingDecision({
    required this.bearingDeg,
    required this.source,
    required this.held,
    required this.reason,
    required this.movingConfident,
  });

  final double bearingDeg;
  final NavBearingSource source;
  final bool held;
  final String reason;

  /// Whether the gate currently considers movement trustworthy.
  final bool movingConfident;
}

/// Stateful (but Mapbox-free) bearing gate for one navigation session.
///
/// Lifecycle:
///   * [seedInitialRouteBearing] at START fixes a stable initial bearing from
///     the first meaningful route segment;
///   * [resolve] is called per accepted GPS fix and returns the bearing the
///     camera target should use;
///   * [reset] clears the session on STOP.
class NavStationaryBearingGate {
  double? _accepted;
  double? _lastReliableMovingBearing;
  int? _acceptedSegmentIndex;
  int _eligibleStreak = 0;
  bool _seeded = false;

  /// Currently accepted bearing, or null before the first seed/resolve.
  double? get acceptedBearing => _accepted;

  /// Last bearing accepted while movement was trustworthy. Held across short
  /// stops (traffic lights) so the camera keeps facing the road ahead.
  double? get lastReliableMovingBearing => _lastReliableMovingBearing;

  int? get acceptedSegmentIndex => _acceptedSegmentIndex;

  /// Consecutive trustworthy fixes seen so far (bounded by the confidence
  /// requirement, so this never grows unbounded).
  int get eligibleStreak => _eligibleStreak;

  bool get isSeeded => _seeded;

  /// Fixes the stable initial bearing from the first meaningful route segment.
  ///
  /// Called once at START, before any movement exists, so the camera opens
  /// facing along the route instead of adopting a random stationary course.
  /// Returns the seeded bearing, or null when no usable segment bearing exists.
  double? seedInitialRouteBearing({
    required double? routeTangentBearingDeg,
    int? routeSegmentIndex,
  }) {
    if (routeTangentBearingDeg == null || !routeTangentBearingDeg.isFinite) {
      return null;
    }
    final seeded = navBearingNormalize(routeTangentBearingDeg);
    _accepted = seeded;
    _acceptedSegmentIndex = routeSegmentIndex;
    _eligibleStreak = 0;
    _seeded = true;
    return seeded;
  }

  /// Latches a camera bearing already established by preview / force-flyTo
  /// before the gate has a normal accepted seed.
  ///
  /// Closes the pre-seed gap: while [acceptedBearing] is still null the
  /// streetlevel pump must not chase wandering pose headings. Does not
  /// overwrite an existing accepted bearing (route seed wins). Returns the
  /// held bearing, or null when [bearingDeg] is unusable.
  double? latchHeldCameraBearing(double? bearingDeg) {
    if (_accepted != null) return _accepted;
    if (bearingDeg == null || !bearingDeg.isFinite) return null;
    final latched = navBearingNormalize(bearingDeg);
    _accepted = latched;
    _eligibleStreak = 0;
    // Not a route seed — route apply may still call [seedInitialRouteBearing].
    return latched;
  }

  NavStationaryBearingDecision resolve(NavStationaryBearingInput input) {
    final trustworthy = navBearingMovementTrustworthy(
      speedKmh: input.speedKmh,
      displacementM: input.displacementM,
      accuracyM: input.accuracyM,
    );
    if (trustworthy) {
      // Bounded: never grows past the confidence requirement.
      _eligibleStreak = math.min(
        _eligibleStreak + 1,
        kNavBearingMovingConfidenceFixes,
      );
    } else {
      _eligibleStreak = 0;
    }
    var movingConfident =
        trustworthy && _eligibleStreak >= kNavBearingMovingConfidenceFixes;

    // NAV-CAMERA-ZERO-OLD-ROUTE-HOLD-P0: under travel authority, a meaningful
    // heading change may skip the multi-fix streak — but only after movement
    // itself is already trustworthy. A >=12° GPS/pose delta at standstill must
    // not unlock the hold.
    if (input.travelAuthority &&
        trustworthy &&
        _accepted != null &&
        _travelImmediateUnlock(
          previous: _accepted!,
          travel: input.travelBearingDeg,
          gps: input.gpsHeadingDeg,
          movement: input.movementBearingDeg,
        )) {
      movingConfident = true;
    }

    // No bearing established yet: take the route segment as the initial
    // orientation rather than a stationary GPS course.
    if (_accepted == null) {
      final tangent = input.routeTangentBearingDeg;
      if (input.allowRouteTangent && tangent != null && tangent.isFinite) {
        _accepted = navBearingNormalize(tangent);
        _acceptedSegmentIndex = input.routeSegmentIndex;
        _seeded = true;
        return NavStationaryBearingDecision(
          bearingDeg: _accepted!,
          source: NavBearingSource.initialRouteSegment,
          held: false,
          reason: 'initial_route_segment',
          movingConfident: movingConfident,
        );
      }
      final coldTravel = _firstUsableTravel(
        travel: input.travelBearingDeg,
        gps: input.gpsHeadingDeg,
        movement: input.movementBearingDeg,
      );
      // Cold travel may seed only once movement is confident (or travel
      // authority with trustworthy movement). Standstill travelAuthority alone
      // must not adopt noisy GPS/pose headings.
      if (coldTravel != null &&
          (movingConfident || (input.travelAuthority && trustworthy))) {
        _accepted = navBearingNormalize(coldTravel);
        _lastReliableMovingBearing = _accepted;
        return NavStationaryBearingDecision(
          bearingDeg: _accepted!,
          source: navBearingGpsCourseUsable(input.gpsHeadingDeg) &&
                  coldTravel == input.gpsHeadingDeg
              ? NavBearingSource.gpsCourse
              : NavBearingSource.movementDelta,
          held: false,
          reason: 'cold_start_travel',
          movingConfident: movingConfident,
        );
      }
      // Nothing trustworthy at all yet — report 0 without accepting it, so a
      // later route segment or genuine movement still seeds cleanly.
      return NavStationaryBearingDecision(
        bearingDeg: 0.0,
        source: NavBearingSource.held,
        held: true,
        reason: 'no_reliable_bearing_yet',
        movingConfident: movingConfident,
      );
    }

    final previous = _accepted!;

    // Stationary / creeping / low-confidence: hold. This is the branch that
    // fixes the field bug — with a route loaded and the vehicle parked, the
    // tangent is NOT allowed to re-target. Travel authority may still unlock
    // above via [movingConfident].
    if (!movingConfident) {
      final held = _lastReliableMovingBearing ?? previous;
      _accepted = held;
      return NavStationaryBearingDecision(
        bearingDeg: held,
        source: NavBearingSource.held,
        held: true,
        reason: input.speedKmh < kNavBearingStationarySpeedKmh
            ? 'stationary_hold'
            : 'low_confidence_hold',
        movingConfident: movingConfident,
      );
    }

    // Movement is trustworthy. Prefer the route tangent only while ownership
    // still allows it, and only when the segment index has not merely oscillated.
    final tangent = input.routeTangentBearingDeg;
    if (input.allowRouteTangent &&
        tangent != null &&
        tangent.isFinite &&
        navRouteSegmentTangentRetargetAllowed(
          acceptedSegmentIndex: _acceptedSegmentIndex,
          candidateSegmentIndex: input.routeSegmentIndex,
          speedKmh: input.speedKmh,
        )) {
      final stepped = navBearingRateClampedStep(
        previousDeg: previous,
        targetDeg: tangent,
        maxRotationRateDegPerSec: input.maxRotationRateDegPerSec,
        dtMs: input.dtMs,
      );
      _accepted = stepped;
      _lastReliableMovingBearing = stepped;
      _acceptedSegmentIndex = input.routeSegmentIndex ?? _acceptedSegmentIndex;
      return NavStationaryBearingDecision(
        bearingDeg: stepped,
        source: NavBearingSource.routeTangent,
        held: false,
        reason: 'moving_route_tangent',
        movingConfident: movingConfident,
      );
    }

    // When route tangent is revoked (or travel authority is active), the
    // predicted/interpolated travel pose owns bearing between GPS samples.
    // Otherwise keep the legacy GPS → displacement fallback order.
    final preferTravel =
        !input.allowRouteTangent || input.travelAuthority;
    if (preferTravel) {
      final travel = input.travelBearingDeg;
      if (travel != null && travel.isFinite) {
        final stepped = navBearingRateClampedStep(
          previousDeg: previous,
          targetDeg: travel,
          maxRotationRateDegPerSec: input.maxRotationRateDegPerSec,
          dtMs: input.dtMs,
        );
        _accepted = stepped;
        _lastReliableMovingBearing = stepped;
        return NavStationaryBearingDecision(
          bearingDeg: stepped,
          source: NavBearingSource.movementDelta,
          held: false,
          reason: 'travel_owns_bearing',
          movingConfident: movingConfident,
        );
      }
    }

    if (navBearingGpsCourseUsable(input.gpsHeadingDeg)) {
      final stepped = navBearingRateClampedStep(
        previousDeg: previous,
        targetDeg: input.gpsHeadingDeg!,
        maxRotationRateDegPerSec: input.maxRotationRateDegPerSec,
        dtMs: input.dtMs,
      );
      _accepted = stepped;
      _lastReliableMovingBearing = stepped;
      return NavStationaryBearingDecision(
        bearingDeg: stepped,
        source: NavBearingSource.gpsCourse,
        held: false,
        reason: preferTravel ? 'travel_owns_gps' : 'moving_gps_course',
        movingConfident: movingConfident,
      );
    }

    final movement = input.movementBearingDeg;
    if (movement != null && movement.isFinite) {
      final stepped = navBearingRateClampedStep(
        previousDeg: previous,
        targetDeg: movement,
        maxRotationRateDegPerSec: input.maxRotationRateDegPerSec,
        dtMs: input.dtMs,
      );
      _accepted = stepped;
      _lastReliableMovingBearing = stepped;
      return NavStationaryBearingDecision(
        bearingDeg: stepped,
        source: NavBearingSource.movementDelta,
        held: false,
        reason:
            preferTravel ? 'travel_owns_displacement' : 'moving_displacement',
        movingConfident: movingConfident,
      );
    }

    return NavStationaryBearingDecision(
      bearingDeg: previous,
      source: NavBearingSource.held,
      held: true,
      reason: 'moving_without_source',
      movingConfident: movingConfident,
    );
  }

  static bool _travelImmediateUnlock({
    required double previous,
    required double? travel,
    required double? gps,
    required double? movement,
  }) {
    const threshold = 12.0;
    for (final candidate in <double?>[travel, gps, movement]) {
      if (candidate == null || !candidate.isFinite) continue;
      if (navBearingShortestDelta(previous, candidate).abs() >= threshold) {
        return true;
      }
    }
    return false;
  }

  static double? _firstUsableTravel({
    required double? travel,
    required double? gps,
    required double? movement,
  }) {
    if (travel != null && travel.isFinite) return travel;
    if (navBearingGpsCourseUsable(gps)) return gps;
    if (movement != null && movement.isFinite) return movement;
    return null;
  }

  void reset() {
    _accepted = null;
    _lastReliableMovingBearing = null;
    _acceptedSegmentIndex = null;
    _eligibleStreak = 0;
    _seeded = false;
  }
}

/// PII-free diagnostics line. Caller rate-limits; no coordinates are included.
String formatNavStationaryBearingDiag({
  required NavStationaryBearingDecision decision,
  required double speedKmh,
  required int? segmentIndex,
}) {
  return '[NAV_BEARING_HOLD] '
      'source=${navBearingSourceLabel(decision.source)} '
      'held=${decision.held} '
      'movingConfident=${decision.movingConfident} '
      'bearing=${decision.bearingDeg.toStringAsFixed(1)} '
      'speedKmh=${speedKmh.toStringAsFixed(1)} '
      'segmentIndex=${segmentIndex ?? -1} '
      'reason=${decision.reason}';
}

/// NAV-PRESTART-HEADING-HOLD-P0: skip passive GPS `_followCameraTesla` writes
/// while a prepared route draft is visible and START has not been pressed.
///
/// Post-START (`liveRideActive`) is never skipped. Forced one-shots
/// (`style_switch`, preview apply, recenter, cockpit adjust) keep working.
bool shouldSkipPassivePrestartFollowCamera({
  required bool liveRideActive,
  required bool preparedRouteDraft,
  required bool force,
  required String cameraReason,
}) {
  if (liveRideActive) return false;
  if (!preparedRouteDraft) return false;
  if (force) return false;
  if (cameraReason != 'normal_follow') return false;
  return true;
}

/// NAV-PRESTART-ROUTE-REPLACE-HEADING-HOLD-P0: keep an already-latched
/// pre-START camera bearing across a later prepared-route accept while the
/// vehicle is still stationary / movement-untrusted.
///
/// First prepared route (no held bearing yet) returns false so seed + preview
/// may establish the initial route-up orientation. Post-START always false.
/// Trustworthy movement before START also returns false so architecture may
/// adopt a new route-up target again.
bool shouldPreservePrestartHeldBearingAcrossRouteReplace({
  required bool liveRideActive,
  required bool preparedRouteDraft,
  required bool hasHeldBearing,
  required double speedKmh,
  double? displacementM,
  double? accuracyM,
}) {
  if (liveRideActive) return false;
  if (!preparedRouteDraft) return false;
  if (!hasHeldBearing) return false;
  if (navBearingMovementTrustworthy(
        speedKmh: speedKmh,
        displacementM: displacementM,
        accuracyM: accuracyM,
      )) {
    return false;
  }
  return true;
}

/// Route-tangent input for pre-START [resolveNavFixedRouteUpBearing].
///
/// When [preserveHeldBearing] is true the tangent is omitted so the already
/// seeded/held bearing wins without changing global live route-up precedence.
double? prestartPreviewRouteTangentForResolve({
  required bool preserveHeldBearing,
  required double? routeFirstSegmentBearingDeg,
}) {
  if (preserveHeldBearing) return null;
  return routeFirstSegmentBearingDeg;
}

/// Pure pre-START hold: once a trusted preview/route bearing is latched, GPS
/// pose jitter and route-progress noise must not change the camera bearing
/// until START (live ride) takes over.
double resolvePrestartHeldCameraBearing({
  required NavStationaryBearingGate gate,
  required double? lastSmoothedCameraBearing,
  required double? previewRouteUpBearing,
}) {
  final held = gate.acceptedBearing;
  if (held != null && held.isFinite) return held;
  if (lastSmoothedCameraBearing != null && lastSmoothedCameraBearing.isFinite) {
    return lastSmoothedCameraBearing;
  }
  if (previewRouteUpBearing != null && previewRouteUpBearing.isFinite) {
    return previewRouteUpBearing;
  }
  return 0.0;
}
