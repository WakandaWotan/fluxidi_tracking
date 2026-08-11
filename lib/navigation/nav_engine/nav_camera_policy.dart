import 'dart:math' as math;

import 'nav_camera_view_mode.dart';

/// Signals that drive follow-camera zoom, tilt, and bearing policy.
class NavCameraPolicyInput {
  final DateTime timestamp;
  final bool liveRideActive;
  final bool cameraFollowMode;
  final bool manualRecenter;
  final double? speedKmh;
  final double? accuracyM;
  final double? routeConfidence;
  final bool offRouteLikely;
  // NAV-R12-H: route adaptation signals (NAV-R12-B) plus reroute-pending —
  // while adapting, the camera prefers a wider context over a tight zoom.
  final bool routeDeviationLikely;
  final bool oppositeDirectionLikely;
  final bool backwardProgressLikely;
  final bool reroutePending;
  final double? distanceToManeuverM;
  final bool nearManeuver;
  final bool waitingMode;
  final bool hasReliableSnap;
  /// NAV-R15A: overview preserves legacy behavior; street view strengthens
  /// bearing follow and viewport anchor (camera-only).
  final NavCameraViewMode viewMode;

  const NavCameraPolicyInput({
    required this.timestamp,
    required this.liveRideActive,
    required this.cameraFollowMode,
    this.manualRecenter = false,
    this.speedKmh,
    this.accuracyM,
    this.routeConfidence,
    this.offRouteLikely = false,
    this.routeDeviationLikely = false,
    this.oppositeDirectionLikely = false,
    this.backwardProgressLikely = false,
    this.reroutePending = false,
    this.distanceToManeuverM,
    this.nearManeuver = false,
    this.waitingMode = false,
    this.hasReliableSnap = false,
    this.viewMode = NavCameraViewMode.overview,
  });

  /// NAV-R12-H: true while the route is adapting and the driver benefits
  /// from seeing surrounding roads.
  bool get routeAdaptationActive =>
      offRouteLikely ||
      routeDeviationLikely ||
      oppositeDirectionLikely ||
      backwardProgressLikely ||
      reroutePending;
}

/// Resolved follow-camera parameters for the map view.
class NavCameraPolicyOutput {
  final bool shouldFollow;
  final double zoom;
  final double tilt;
  final double bearingModeWeight;
  final String reason;

  /// NAV-R12-H: pre-smoothing zoom the policy is steering toward.
  final double targetZoom;

  /// NAV-R12-H: bounded label — speed|maneuver|adaptation|manual_hold|fallback.
  final String zoomReason;

  const NavCameraPolicyOutput({
    required this.shouldFollow,
    required this.zoom,
    required this.tilt,
    required this.bearingModeWeight,
    required this.reason,
    required this.targetZoom,
    required this.zoomReason,
  });
}

/// Pure-Dart camera policy for live driver follow mode.
///
/// NAV-R12-H: dynamic auto-zoom. Zoom is chosen from speed bands, boosted
/// near maneuvers, capped wider during route adaptation, and always ramped
/// through a max-step smoother so the camera never jumps.
class DriverNavCameraPolicy {
  // NAV-R13: only genuinely close maneuvers may override the speed-based
  // overview zoom.
  static const double _nearManeuverDistanceM = 120.0;
  static const double _veryNearManeuverDistanceM = 80.0;

  // NAV-R12-H zoom constants.
  static const double stoppedZoom = 16.7;
  static const double adaptationMaxZoom = 15.8;
  static const double maxZoomStepPerUpdate = 0.35;
  static const double maxTiltStepPerUpdate = 3.0;
  static const double minZoom = 13.0;
  static const double maxZoom = 18.5;

  /// Conservative extra zoom-out for overview / north-up only.
  ///
  /// Street View / 3D cockpit steady-state targets come from the Pro2
  /// cockpit profile and must not be shifted by this bias. Keeping the
  /// bias off [NavCameraViewMode.streetView] also preserves the streetlevel
  /// cold-start policy seed used before the first cockpit apply.
  static const double nonStreetViewOverviewZoomBias = -0.45;

  // NAV-R13: cap tilt to reduce marker perspective distortion; 64° made the
  // viewport-anchored taxi sprite look flattened during angled follow.
  static const double maxTiltDeg = 58.0;

  double? _lastZoom;
  double? _lastTilt;

  void reset() {
    _lastZoom = null;
    _lastTilt = null;
  }

  /// NAV-R12-H: speed-band zoom, interpolated inside each band so the
  /// target changes continuously with speed.
  /// NAV-R13: medium/fast bands widened for a more top-down overview —
  /// ~30 km/h lands near 15.7, ~50 km/h near 15.0.
  static double speedZoomFor(double speedKmh) {
    if (speedKmh <= 3.0) return stoppedZoom;
    if (speedKmh <= 25.0) {
      final t = (speedKmh - 3.0) / 22.0;
      return 17.0 - t * 0.5; // city: 17.0 -> 16.5
    }
    if (speedKmh <= 60.0) {
      final t = (speedKmh - 25.0) / 35.0;
      return 15.9 - t * 1.2; // medium: 15.9 -> 14.7
    }
    if (speedKmh <= 95.0) {
      final t = (speedKmh - 60.0) / 35.0;
      return 14.6 - t * 0.6; // fast: 14.6 -> 14.0
    }
    final t = math.min(1.0, (speedKmh - 95.0) / 35.0);
    return 14.0 - t * 0.5; // highway: 14.0 -> 13.5
  }

  /// NAV-R12-H: temporary zoom-in near a maneuver; high speed keeps a wider
  /// view so the zoom-in never hides the road ahead.
  /// NAV-R13: boost softened and limited to genuinely close maneuvers
  /// (<=80 m strong, <=120 m moderate) so the speed overview stays dominant.
  static double? maneuverZoomFor({
    required double speedKmh,
    required double? distanceToManeuverM,
    required bool nearManeuver,
  }) {
    final distance = distanceToManeuverM;
    if (!nearManeuver || distance == null || !distance.isFinite) return null;
    if (distance <= _veryNearManeuverDistanceM) {
      return speedKmh >= 60.0 ? 15.8 : 16.6;
    }
    if (distance <= _nearManeuverDistanceM) {
      return speedKmh >= 60.0 ? 15.2 : 16.0;
    }
    return null;
  }

  NavCameraPolicyOutput update(NavCameraPolicyInput input) {
    if (!input.liveRideActive || !input.cameraFollowMode) {
      // Manual/not-follow mode: hold the current zoom so auto-zoom never
      // fights a user who panned or zoomed away (shouldFollow=false means
      // the value is not applied anyway).
      final held = _lastZoom ?? 16.5;
      return NavCameraPolicyOutput(
        shouldFollow: false,
        zoom: _smoothZoom(held),
        tilt: _smoothTilt(_lastTilt ?? 48.0),
        bearingModeWeight: 0.15,
        reason: 'inactive',
        targetZoom: held,
        zoomReason: 'manual_hold',
      );
    }

    final confidence = input.routeConfidence ?? 0.0;
    if (input.offRouteLikely && confidence < 45.0 && !input.manualRecenter) {
      // Not following, but keep steering toward the wider adaptation
      // context so a recenter lands on a useful zoom.
      final held = math.min(_lastZoom ?? adaptationMaxZoom, adaptationMaxZoom);
      return NavCameraPolicyOutput(
        shouldFollow: false,
        zoom: _smoothZoom(held),
        tilt: _smoothTilt(48.0),
        bearingModeWeight: 0.2,
        reason: 'off_route_low_confidence',
        targetZoom: held,
        zoomReason: 'adaptation',
      );
    }

    final speedKmh = math.max(0.0, input.speedKmh ?? 0.0);
    final distanceM = input.distanceToManeuverM;
    final veryNearManeuver =
        input.nearManeuver &&
        distanceM != null &&
        distanceM.isFinite &&
        distanceM <= _veryNearManeuverDistanceM;
    final nearManeuver =
        input.nearManeuver &&
        distanceM != null &&
        distanceM.isFinite &&
        distanceM <= _nearManeuverDistanceM;
    final lowConfidence =
        confidence < 55.0 || (!input.hasReliableSnap && confidence > 0);

    // NAV-R13: tilt capped at [maxTiltDeg] (58°) everywhere — 62-64° pitch
    // visibly flattened the taxi sprite and hid context.
    double tilt;
    String reason;
    if (veryNearManeuver) {
      if (speedKmh < 4.0) {
        tilt = 54.0;
      } else if (speedKmh < 15.0) {
        tilt = 57.0;
      } else {
        tilt = 58.0;
      }
      reason = 'very_near_maneuver';
    } else if (nearManeuver) {
      if (speedKmh < 4.0) {
        tilt = 52.0;
      } else if (speedKmh < 15.0) {
        tilt = 56.0;
      } else {
        tilt = 58.0;
      }
      reason = 'near_maneuver';
    } else if (input.waitingMode || speedKmh < 3.0) {
      final t = (speedKmh / 3.0).clamp(0.0, 1.0);
      tilt = 46.0 + t * 4.0;
      reason = input.waitingMode ? 'waiting' : 'low_speed';
    } else if (speedKmh > 70.0) {
      final t = math.min(1.0, (speedKmh - 70.0) / 40.0);
      tilt = 56.0 + t * 2.0;
      reason = 'high_speed';
    } else {
      if (speedKmh < 15.0) {
        final t = speedKmh / 15.0;
        tilt = 50.0 + t * 4.0;
      } else {
        final t = math.min(1.0, (speedKmh - 15.0) / 55.0);
        tilt = 54.0 + t * 4.0;
      }
      reason = 'normal_follow';
    }
    tilt = math.min(tilt, maxTiltDeg);

    // --- NAV-R12-H dynamic zoom -------------------------------------------
    double targetZoom;
    String zoomReason;
    // Overview / north-up bias applies to freshly resolved targets only.
    // Holding `_lastZoom` must not re-apply the bias (that value is already
    // the previously applied overview zoom).
    var applyNonStreetViewBias =
        input.viewMode != NavCameraViewMode.streetView;
    if (input.speedKmh == null || !input.speedKmh!.isFinite) {
      if (_lastZoom != null) {
        targetZoom = _lastZoom!;
        applyNonStreetViewBias = false;
      } else {
        targetZoom = 16.5;
      }
      zoomReason = 'fallback';
    } else if (speedKmh < 3.0) {
      // Stopped/crawling: hold the current zoom instead of chasing a new
      // band on GPS jitter; first fix ever gets the stable close zoom.
      if (_lastZoom != null) {
        targetZoom = _lastZoom!;
        applyNonStreetViewBias = false;
      } else {
        targetZoom = stoppedZoom;
      }
      zoomReason = 'speed';
    } else {
      targetZoom = speedZoomFor(speedKmh);
      zoomReason = 'speed';
    }

    final maneuverZoom = maneuverZoomFor(
      speedKmh: speedKmh,
      distanceToManeuverM: distanceM,
      nearManeuver: input.nearManeuver,
    );
    if (maneuverZoom != null && maneuverZoom > targetZoom) {
      targetZoom = maneuverZoom;
      zoomReason = 'maneuver';
      // Maneuver targets are raw band values; re-enable bias when overview.
      applyNonStreetViewBias =
          input.viewMode != NavCameraViewMode.streetView;
    }

    if (lowConfidence) {
      targetZoom = (targetZoom - 0.3).clamp(minZoom, maxZoom);
      tilt = (tilt - 2.0).clamp(44.0, 66.0);
      reason = '${reason}_low_confidence';
    }

    // Route adaptation: widen the view so the driver sees surrounding
    // roads, unless standing still with an excellent fix.
    if (input.routeAdaptationActive) {
      final excellentLowSpeedFix =
          speedKmh < 3.0 && (input.accuracyM ?? 99.0) <= 10.0;
      if (!excellentLowSpeedFix && targetZoom > adaptationMaxZoom) {
        targetZoom = adaptationMaxZoom;
        zoomReason = 'adaptation';
        tilt = math.min(tilt, 52.0);
        reason = '${reason}_adaptation';
        applyNonStreetViewBias =
            input.viewMode != NavCameraViewMode.streetView;
      }
    }

    // Non-3D overview / north-up: raise the camera slightly (more road /
    // context). Never applied to streetView so 3D cockpit framing stays put.
    if (applyNonStreetViewBias) {
      targetZoom = (targetZoom + nonStreetViewOverviewZoomBias)
          .clamp(minZoom, maxZoom);
    }

    if (input.manualRecenter) {
      reason = 'manual_recenter';
    }

    final bearingModeWeight = _bearingModeWeightFor(input, speedKmh: speedKmh);

    var appliedZoom = _smoothZoom(targetZoom);
    var appliedTilt = _smoothTilt(tilt);
    if (input.viewMode == NavCameraViewMode.streetView && input.cameraFollowMode) {
      final tuned = streetViewCameraTuning(
        zoom: appliedZoom,
        tilt: appliedTilt,
        routeAdaptationActive: input.routeAdaptationActive,
      );
      appliedZoom = _smoothZoom(tuned.zoom);
      appliedTilt = _smoothTilt(tuned.tilt);
      if (!input.routeAdaptationActive) {
        reason = '${reason}_street_view';
      }
    }

    return NavCameraPolicyOutput(
      shouldFollow: true,
      zoom: appliedZoom,
      tilt: appliedTilt,
      bearingModeWeight: bearingModeWeight,
      reason: reason,
      targetZoom: targetZoom,
      zoomReason: zoomReason,
    );
  }

  double _bearingModeWeightFor(
    NavCameraPolicyInput input, {
    required double speedKmh,
  }) {
    if (input.viewMode == NavCameraViewMode.northUp) {
      return 0.0;
    }
    if (input.viewMode == NavCameraViewMode.streetView) {
      return streetViewBearingModeWeight(input);
    }
    final confidence = input.routeConfidence ?? 0.0;
    if (speedKmh < 3.0) return 0.15;
    if (input.offRouteLikely || confidence < 45.0) return 0.25;
    if (confidence < 55.0 || !input.hasReliableSnap) return 0.45;
    if (input.hasReliableSnap && confidence >= 55.0) return 1.0;
    return 0.6;
  }

  /// NAV-R12-H: ramp toward the target from the last *applied* zoom so a
  /// band change never jumps more than [maxZoomStepPerUpdate] per update.
  double _smoothZoom(double target) {
    final prev = _lastZoom;
    if (prev == null || !prev.isFinite) {
      final applied = target.clamp(minZoom, maxZoom);
      _lastZoom = applied;
      return applied;
    }
    final delta = (target - prev).clamp(
      -maxZoomStepPerUpdate,
      maxZoomStepPerUpdate,
    );
    final applied = (prev + delta).clamp(minZoom, maxZoom);
    _lastZoom = applied;
    return applied;
  }

  double _smoothTilt(double target) {
    final prev = _lastTilt;
    if (prev == null || !prev.isFinite) {
      final applied = target.clamp(44.0, 66.0);
      _lastTilt = applied;
      return applied;
    }
    final delta = (target - prev).clamp(
      -maxTiltStepPerUpdate,
      maxTiltStepPerUpdate,
    );
    final applied = (prev + delta).clamp(44.0, 66.0);
    _lastTilt = applied;
    return applied;
  }
}
