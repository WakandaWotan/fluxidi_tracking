// NAV-CAMERA-ZERO-OLD-ROUTE-HOLD-P0
//
// Pure, deterministic camera-bearing ownership and stale-command rejection.
// Old-route tangent must lose authority the moment deviation is suspected —
// before confirmed reroute — and must never commit after a newer routeVersion
// is active. Owns no Mapbox handles or timers.

import 'nav_stationary_bearing_hold.dart';

/// Explicit camera-bearing owner modes.
enum NavCameraBearingOwner {
  /// Active route tangent owns bearing while match is reliable.
  reliableRoute,

  /// Old route tangent loses authority immediately; travel/GPS owns.
  deviationSuspected,

  /// Actual travel direction owns bearing; old routeVersion has zero authority.
  reroutePending,

  /// Transfer to the new routeVersion tangent; blend from travel, no snap-back.
  newRouteAccepted,
}

String navCameraBearingOwnerLabel(NavCameraBearingOwner owner) {
  switch (owner) {
    case NavCameraBearingOwner.reliableRoute:
      return 'reliable_route';
    case NavCameraBearingOwner.deviationSuspected:
      return 'deviation_suspected';
    case NavCameraBearingOwner.reroutePending:
      return 'reroute_pending';
    case NavCameraBearingOwner.newRouteAccepted:
      return 'new_route_accepted';
  }
}

NavCameraBearingOwner? navCameraBearingOwnerFromLabel(String? label) {
  switch ((label ?? '').trim().toLowerCase()) {
    case 'reliable_route':
      return NavCameraBearingOwner.reliableRoute;
    case 'deviation_suspected':
      return NavCameraBearingOwner.deviationSuspected;
    case 'reroute_pending':
      return NavCameraBearingOwner.reroutePending;
    case 'new_route_accepted':
      return NavCameraBearingOwner.newRouteAccepted;
    default:
      return null;
  }
}

/// Angular delta (deg) at/above which travel ownership begins rotating even
/// when movement confidence is still building (U-turn / sharp reversal).
const double kNavCameraTravelImmediateDeltaDeg = 12.0;

/// Noise deadband: smaller deltas stay stable under travel ownership.
const double kNavCameraTravelNoiseDeadbandDeg = 2.0;

/// Max rotation rate (deg/s) while travel owns the camera bearing — large
/// enough that a meaningful change is visible within ~100 ms and a 180°
/// reversal begins immediately, without overshooting the target.
const double kNavCameraTravelMaxRotationRateDegPerSec = 220.0;

/// Brief blend window after a new route is accepted before settling back to
/// reliable-route ownership.
const int kNavCameraNewRouteBlendMs = 900;

/// Resolve the current camera-bearing owner from navigation signals.
NavCameraBearingOwner resolveNavCameraBearingOwner({
  required bool deviationSuspected,
  required bool reroutePending,
  required bool newRouteBlendActive,
  required bool routeMatchReliable,
}) {
  if (reroutePending) return NavCameraBearingOwner.reroutePending;
  if (deviationSuspected) return NavCameraBearingOwner.deviationSuspected;
  if (newRouteBlendActive) return NavCameraBearingOwner.newRouteAccepted;
  if (routeMatchReliable) return NavCameraBearingOwner.reliableRoute;
  // Unreliable match without an explicit deviation flag still demotes tangent.
  return NavCameraBearingOwner.deviationSuspected;
}

/// Whether the (current) route tangent may drive the camera bearing.
bool navCameraRouteTangentAllowed(NavCameraBearingOwner owner) {
  switch (owner) {
    case NavCameraBearingOwner.reliableRoute:
    case NavCameraBearingOwner.newRouteAccepted:
      return true;
    case NavCameraBearingOwner.deviationSuspected:
    case NavCameraBearingOwner.reroutePending:
      return false;
  }
}

/// Whether the retarget controller should use travel-authority catch-up
/// (fast response, still shortest-path, no overshoot).
bool navCameraTravelAuthority(NavCameraBearingOwner owner) {
  switch (owner) {
    case NavCameraBearingOwner.deviationSuspected:
    case NavCameraBearingOwner.reroutePending:
    case NavCameraBearingOwner.newRouteAccepted:
      return true;
    case NavCameraBearingOwner.reliableRoute:
      return false;
  }
}

/// Stamped camera target / command for latest-wins + stale rejection.
class NavCameraCommandToken {
  const NavCameraCommandToken({
    required this.routeVersion,
    required this.ownerMode,
    required this.poseGeneration,
    required this.renderEpoch,
    required this.targetTimestampMs,
    required this.targetBearingDeg,
    required this.bearingSource,
  });

  final int routeVersion;
  final NavCameraBearingOwner ownerMode;
  final int poseGeneration;
  final int renderEpoch;
  final int targetTimestampMs;
  final double targetBearingDeg;
  final String bearingSource;
}

/// Outcome of a commit attempt against the active camera ownership state.
class NavCameraCommandCommitDecision {
  const NavCameraCommandCommitDecision({
    required this.accept,
    required this.reason,
    required this.staleCommandCancelled,
  });

  final bool accept;
  final String reason;
  final bool staleCommandCancelled;
}

/// Latest-wins / stale rejection for camera targets.
///
/// Proves routeVersion N cannot commit after routeVersion N+1 is active, and
/// that an older renderEpoch / poseGeneration cannot overwrite a newer one.
NavCameraCommandCommitDecision decideNavCameraCommandCommit({
  required NavCameraCommandToken candidate,
  required int activeRouteVersion,
  required int activeRenderEpoch,
  required int lastCommittedPoseGeneration,
  NavCameraBearingOwner? activeOwner,
}) {
  if (candidate.routeVersion < activeRouteVersion) {
    return const NavCameraCommandCommitDecision(
      accept: false,
      reason: 'stale_route_version',
      staleCommandCancelled: true,
    );
  }
  if (candidate.renderEpoch < activeRenderEpoch) {
    return const NavCameraCommandCommitDecision(
      accept: false,
      reason: 'stale_render_epoch',
      staleCommandCancelled: true,
    );
  }
  if (candidate.poseGeneration < lastCommittedPoseGeneration) {
    return const NavCameraCommandCommitDecision(
      accept: false,
      reason: 'stale_pose_generation',
      staleCommandCancelled: true,
    );
  }
  // Old-route ownership modes must not commit once a newer route is active
  // even if the numeric version stamp was incorrectly reused.
  if (activeOwner == NavCameraBearingOwner.newRouteAccepted ||
      activeOwner == NavCameraBearingOwner.reliableRoute) {
    if (candidate.ownerMode == NavCameraBearingOwner.reroutePending ||
        candidate.ownerMode == NavCameraBearingOwner.deviationSuspected) {
      if (candidate.routeVersion < activeRouteVersion) {
        return const NavCameraCommandCommitDecision(
          accept: false,
          reason: 'stale_owner_after_new_route',
          staleCommandCancelled: true,
        );
      }
    }
  }
  return const NavCameraCommandCommitDecision(
    accept: true,
    reason: 'accepted',
    staleCommandCancelled: false,
  );
}

/// One retargetable bearing step under travel authority.
///
/// Replaces pending targets in place (no animation queue). Filters noise,
/// follows the shortest arc, never overshoots, and responds immediately to
/// sustained / large heading changes.
double navCameraTravelBearingStep({
  required double? previousDeg,
  required double targetDeg,
  required double dtMs,
  double noiseDeadbandDeg = kNavCameraTravelNoiseDeadbandDeg,
  double maxRotationRateDegPerSec = kNavCameraTravelMaxRotationRateDegPerSec,
}) {
  final target = navBearingNormalize(targetDeg);
  if (previousDeg == null || !previousDeg.isFinite) return target;
  final previous = navBearingNormalize(previousDeg);
  final delta = navBearingShortestDelta(previous, target);
  final ad = delta.abs();
  if (ad < noiseDeadbandDeg) return previous;
  if (!dtMs.isFinite || dtMs <= 0) {
    // Still begin the motion on a zero-dt tick so a 180° reversal is not held.
    final kick = ad.clamp(0.0, 18.0);
    return navBearingNormalize(previous + kick * delta.sign);
  }
  final maxStep = maxRotationRateDegPerSec * (dtMs / 1000.0);
  if (!maxStep.isFinite || maxStep <= 0) return previous;
  if (ad <= maxStep) return target;
  return navBearingNormalize(previous + maxStep * delta.sign);
}

/// Whether a travel bearing change should unlock rotation immediately even
/// before the stationary gate's multi-fix confidence streak is met.
bool navCameraTravelImmediateUnlock({
  required double? previousDeg,
  required double? travelBearingDeg,
  double thresholdDeg = kNavCameraTravelImmediateDeltaDeg,
}) {
  if (previousDeg == null ||
      travelBearingDeg == null ||
      !previousDeg.isFinite ||
      !travelBearingDeg.isFinite) {
    return false;
  }
  return navBearingShortestDelta(previousDeg, travelBearingDeg).abs() >=
      thresholdDeg;
}

/// Owner-transition reason labels (PII-free).
String navCameraOwnerTransitionReason({
  required NavCameraBearingOwner from,
  required NavCameraBearingOwner to,
  required bool deviationSuspected,
  required bool reroutePending,
  required bool newRouteAccepted,
}) {
  if (to == NavCameraBearingOwner.reroutePending || reroutePending) {
    return 'reroute_pending';
  }
  if (to == NavCameraBearingOwner.deviationSuspected || deviationSuspected) {
    return 'deviation_suspected';
  }
  if (to == NavCameraBearingOwner.newRouteAccepted || newRouteAccepted) {
    return 'new_route_accepted';
  }
  if (from != NavCameraBearingOwner.reliableRoute &&
      to == NavCameraBearingOwner.reliableRoute) {
    return 'route_match_reliable';
  }
  return 'owner_resolve';
}

/// Bounded PII-free diagnostics line for camera bearing ownership.
String formatNavCameraOwnerDiag({
  required NavCameraBearingOwner fromOwner,
  required NavCameraBearingOwner toOwner,
  required String reason,
  required int routeVersion,
  required String bearingSource,
  required double targetBearing,
  required double appliedBearing,
  required double angularDelta,
  required int targetAgeMs,
  required bool staleCommandCancelled,
}) {
  return '[NAV_CAMERA_OWNER] '
      'fromOwner=${navCameraBearingOwnerLabel(fromOwner)} '
      'toOwner=${navCameraBearingOwnerLabel(toOwner)} '
      'reason=$reason '
      'routeVersion=$routeVersion '
      'bearingSource=$bearingSource '
      'targetBearing=${targetBearing.toStringAsFixed(1)} '
      'appliedBearing=${appliedBearing.toStringAsFixed(1)} '
      'angularDelta=${angularDelta.toStringAsFixed(1)} '
      'targetAgeMs=$targetAgeMs '
      'staleCommandCancelled=$staleCommandCancelled';
}
