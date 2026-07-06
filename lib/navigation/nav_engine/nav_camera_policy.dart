import 'dart:math' as math;

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
  final double? distanceToManeuverM;
  final bool nearManeuver;
  final bool waitingMode;
  final bool hasReliableSnap;

  const NavCameraPolicyInput({
    required this.timestamp,
    required this.liveRideActive,
    required this.cameraFollowMode,
    this.manualRecenter = false,
    this.speedKmh,
    this.accuracyM,
    this.routeConfidence,
    this.offRouteLikely = false,
    this.distanceToManeuverM,
    this.nearManeuver = false,
    this.waitingMode = false,
    this.hasReliableSnap = false,
  });
}

/// Resolved follow-camera parameters for the map view.
class NavCameraPolicyOutput {
  final bool shouldFollow;
  final double zoom;
  final double tilt;
  final double bearingModeWeight;
  final String reason;

  const NavCameraPolicyOutput({
    required this.shouldFollow,
    required this.zoom,
    required this.tilt,
    required this.bearingModeWeight,
    required this.reason,
  });
}

/// Pure-Dart camera policy for live driver follow mode.
class DriverNavCameraPolicy {
  static const double _nearManeuverDistanceM = 300.0;
  static const double _veryNearManeuverDistanceM = 80.0;

  double? _lastZoom;
  double? _lastTilt;

  void reset() {
    _lastZoom = null;
    _lastTilt = null;
  }

  NavCameraPolicyOutput update(NavCameraPolicyInput input) {
    if (!input.liveRideActive || !input.cameraFollowMode) {
      return NavCameraPolicyOutput(
        shouldFollow: false,
        zoom: _smoothZoom(16.5),
        tilt: _smoothTilt(48.0),
        bearingModeWeight: 0.15,
        reason: 'inactive',
      );
    }

    final confidence = input.routeConfidence ?? 0.0;
    if (input.offRouteLikely && confidence < 45.0 && !input.manualRecenter) {
      return NavCameraPolicyOutput(
        shouldFollow: false,
        zoom: _smoothZoom(16.2),
        tilt: _smoothTilt(48.0),
        bearingModeWeight: 0.2,
        reason: 'off_route_low_confidence',
      );
    }

    final speedKmh = math.max(0.0, input.speedKmh ?? 0.0);
    final distanceM = input.distanceToManeuverM;
    final veryNearManeuver = input.nearManeuver &&
        distanceM != null &&
        distanceM.isFinite &&
        distanceM <= _veryNearManeuverDistanceM;
    final nearManeuver = input.nearManeuver &&
        distanceM != null &&
        distanceM.isFinite &&
        distanceM <= _nearManeuverDistanceM;
    final lowConfidence =
        confidence < 55.0 || (!input.hasReliableSnap && confidence > 0);

    double zoom;
    double tilt;
    String reason;

    if (veryNearManeuver) {
      if (speedKmh < 4.0) {
        zoom = 17.8;
        tilt = 56.0;
      } else if (speedKmh < 15.0) {
        zoom = 18.0;
        tilt = 62.0;
      } else {
        zoom = 18.3;
        tilt = 64.0;
      }
      reason = 'very_near_maneuver';
    } else if (nearManeuver) {
      if (speedKmh < 4.0) {
        zoom = 17.2;
        tilt = 54.0;
      } else if (speedKmh < 15.0) {
        zoom = 17.6;
        tilt = 58.0;
      } else {
        zoom = 18.0;
        tilt = 62.0;
      }
      reason = 'near_maneuver';
    } else if (input.waitingMode || speedKmh < 3.0) {
      final t = (speedKmh / 3.0).clamp(0.0, 1.0);
      zoom = 16.2 + t * 0.6;
      tilt = 46.0 + t * 4.0;
      reason = input.waitingMode ? 'waiting' : 'low_speed';
    } else if (speedKmh > 70.0) {
      final t = math.min(1.0, (speedKmh - 70.0) / 40.0);
      zoom = 15.4 + t * 0.8;
      tilt = 58.0 + t * 4.0;
      reason = 'high_speed';
    } else {
      if (speedKmh < 15.0) {
        final t = speedKmh / 15.0;
        zoom = 16.4 + t * 0.5;
        tilt = 52.0 + t * 4.0;
      } else {
        final t = math.min(1.0, (speedKmh - 15.0) / 55.0);
        zoom = 16.9 + t * 0.3;
        tilt = 56.0 + t * 4.0;
      }
      reason = 'normal_follow';
    }

    if (lowConfidence) {
      zoom = (zoom - 0.45).clamp(15.0, 18.0);
      tilt = (tilt - 2.0).clamp(44.0, 64.0);
      reason = '${reason}_low_confidence';
    }

    if (input.manualRecenter) {
      reason = 'manual_recenter';
    }

    final bearingModeWeight = _bearingModeWeightFor(input, speedKmh: speedKmh);

    return NavCameraPolicyOutput(
      shouldFollow: true,
      zoom: _smoothZoom(zoom),
      tilt: _smoothTilt(tilt),
      bearingModeWeight: bearingModeWeight,
      reason: reason,
    );
  }

  double _bearingModeWeightFor(
    NavCameraPolicyInput input, {
    required double speedKmh,
  }) {
    final confidence = input.routeConfidence ?? 0.0;
    if (speedKmh < 3.0) return 0.15;
    if (input.offRouteLikely || confidence < 45.0) return 0.25;
    if (confidence < 55.0 || !input.hasReliableSnap) return 0.45;
    if (input.hasReliableSnap && confidence >= 55.0) return 1.0;
    return 0.6;
  }

  double _smoothZoom(double target) {
    final prev = _lastZoom;
    _lastZoom = target;
    if (prev == null || !prev.isFinite) return target;
    final delta = (target - prev).clamp(-0.35, 0.35);
    return (prev + delta).clamp(14.5, 18.5);
  }

  double _smoothTilt(double target) {
    final prev = _lastTilt;
    _lastTilt = target;
    if (prev == null || !prev.isFinite) return target;
    final delta = (target - prev).clamp(-3.0, 3.0);
    return (prev + delta).clamp(44.0, 66.0);
  }
}
