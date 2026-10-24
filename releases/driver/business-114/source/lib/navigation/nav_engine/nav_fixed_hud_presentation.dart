/// NAV-FIXED-HUD-PRESENTATION-1: pure decisions for the single screen-fixed
/// HUD vehicle presentation.
///
/// Field-proven defect (tablet, commit 49c110d): the whole driver marker and
/// camera pipeline gated on `followLiveActive = cameraFollowMode &&
/// liveRideActive`. A prepared booking, a prepared street draft and NAV-to-
/// pickup A are all *not* live rides, so that predicate was false and:
///
///   * the screen-fixed Flutter HUD never mounted;
///   * the geographic Mapbox annotation stayed at opacity 1.0 and became the
///     visible owner (`[NAV_MARKER_OWNER] owner=mapbox`);
///   * that annotation kept `IconRotationAlignment.MAP` with the pose bearing
///     in `iconRotate`, so the Car/Arrow rendered diagonally and moved with
///     the geography instead of staying above the KPI counters;
///   * the camera policy resolved `follow=false reason=inactive` and the
///     view mode collapsed to overview / north-up, so the forward route did
///     not point to the top of the screen.
///
/// The activation predicate is therefore widened from "live ride" to "a route
/// is prepared or being driven", which is the phase set that must share one
/// identical deterministic presentation.
library;

import 'dart:math' as math;

/// The route phases of the driver surface, in precedence order.
enum NavFixedHudPhase {
  /// No prepared route and no guidance: the idle map keeps platform defaults.
  idle,

  /// A booking or street draft is prepared but neither NAV nor START ran.
  preparedRoute,

  /// Unmetered NAV guidance from the driver position to pickup point A.
  toPickup,

  /// A metered customer trip A -> B is running.
  liveRide,
}

/// Bounded, PII-free label for diagnostics.
String navFixedHudPhaseLabel(NavFixedHudPhase phase) {
  switch (phase) {
    case NavFixedHudPhase.idle:
      return 'idle';
    case NavFixedHudPhase.preparedRoute:
      return 'prepared_route';
    case NavFixedHudPhase.toPickup:
      return 'to_pickup';
    case NavFixedHudPhase.liveRide:
      return 'live_ride';
  }
}

/// Resolves the current route phase. A live ride always wins over guidance,
/// and guidance always wins over a prepared draft.
NavFixedHudPhase resolveNavFixedHudPhase({
  required bool liveRideActive,
  required bool navigationGuidanceActive,
  required bool preparedRouteDraft,
}) {
  if (liveRideActive) return NavFixedHudPhase.liveRide;
  if (navigationGuidanceActive) return NavFixedHudPhase.toPickup;
  if (preparedRouteDraft) return NavFixedHudPhase.preparedRoute;
  return NavFixedHudPhase.idle;
}

/// True when the screen-fixed HUD must be the sole visible vehicle
/// presentation owner and the fixed Street Level camera profile applies.
///
/// This replaces the former `cameraFollowMode && liveRideActive` gate at every
/// marker-ownership, HUD-mount, Mapbox-opacity, rotation-policy and camera
/// -policy call site, so prepared route, NAV-to-pickup and the live ride are
/// indistinguishable to the presentation pipeline.
bool navFixedHudPresentationActive({
  required NavFixedHudPhase phase,
  required bool cameraFollowMode,
}) {
  return cameraFollowMode && phase != NavFixedHudPhase.idle;
}

/// Where the fixed Street Level camera bearing came from.
enum NavFixedRouteUpBearingSource {
  /// Tangent of the first meaningful forward segment of the accepted route.
  routeTangent,

  /// Bearing already accepted by the stationary-bearing gate, itself seeded
  /// from the route on route activation.
  seededRoute,

  /// Raw GPS course. Only trusted when no route geometry exists at all.
  gpsHeading,

  /// Nothing reliable; caller keeps north-up rather than snapping to noise.
  none,
}

/// Bounded, PII-free label for diagnostics.
String navFixedRouteUpBearingSourceLabel(NavFixedRouteUpBearingSource source) {
  switch (source) {
    case NavFixedRouteUpBearingSource.routeTangent:
      return 'route_tangent';
    case NavFixedRouteUpBearingSource.seededRoute:
      return 'seeded_route';
    case NavFixedRouteUpBearingSource.gpsHeading:
      return 'gps_heading';
    case NavFixedRouteUpBearingSource.none:
      return 'none';
  }
}

/// Resolved camera bearing for the fixed Street Level presentation.
class NavFixedRouteUpBearing {
  const NavFixedRouteUpBearing({
    required this.bearingDeg,
    required this.source,
  });

  /// Normalised to `[0, 360)`.
  final double bearingDeg;

  final NavFixedRouteUpBearingSource source;

  /// True when the bearing came from route geometry rather than GPS noise.
  bool get isRouteUp =>
      source == NavFixedRouteUpBearingSource.routeTangent ||
      source == NavFixedRouteUpBearingSource.seededRoute;
}

double _normaliseDeg(double deg) {
  final wrapped = deg % 360.0;
  return wrapped < 0 ? wrapped + 360.0 : wrapped;
}

bool _usable(double? deg) => deg != null && deg.isFinite;

/// Resolves the camera bearing that makes the forward route extend toward the
/// top of the screen.
///
/// Precedence is route geometry first, GPS last. At standstill the route
/// tangent is the only trustworthy source: GPS course is noise when speed is
/// zero, and falling back to it produced the field-observed "route does not
/// point up" and "stale map angle" behaviour.
NavFixedRouteUpBearing resolveNavFixedRouteUpBearing({
  double? routeTangentBearingDeg,
  double? seededRouteBearingDeg,
  double? gpsHeadingDeg,
}) {
  if (_usable(routeTangentBearingDeg)) {
    return NavFixedRouteUpBearing(
      bearingDeg: _normaliseDeg(routeTangentBearingDeg!),
      source: NavFixedRouteUpBearingSource.routeTangent,
    );
  }
  if (_usable(seededRouteBearingDeg)) {
    return NavFixedRouteUpBearing(
      bearingDeg: _normaliseDeg(seededRouteBearingDeg!),
      source: NavFixedRouteUpBearingSource.seededRoute,
    );
  }
  if (_usable(gpsHeadingDeg) && gpsHeadingDeg! >= 0) {
    return NavFixedRouteUpBearing(
      bearingDeg: _normaliseDeg(gpsHeadingDeg),
      source: NavFixedRouteUpBearingSource.gpsHeading,
    );
  }
  return const NavFixedRouteUpBearing(
    bearingDeg: 0.0,
    source: NavFixedRouteUpBearingSource.none,
  );
}

/// Screen rotation of the vehicle glyph, in degrees, for a marker whose icon
/// rotation is [iconRotateDeg] under a camera aimed at [cameraBearingDeg].
///
/// A screen-up HUD must return 0 for every camera bearing. Used by the tests
/// to prove the invariant rather than by production code.
double navFixedHudMarkerScreenRotationDeg({
  required double iconRotateDeg,
  required double cameraBearingDeg,
  required bool viewportAligned,
}) {
  if (viewportAligned) return _normaliseDeg(iconRotateDeg);
  final delta = _normaliseDeg(iconRotateDeg - cameraBearingDeg);
  return delta;
}

/// Absolute angular distance between two bearings, in `[0, 180]`.
double navFixedBearingDeltaDeg(double a, double b) {
  final delta = (_normaliseDeg(a) - _normaliseDeg(b)).abs();
  return math.min(delta, 360.0 - delta);
}
