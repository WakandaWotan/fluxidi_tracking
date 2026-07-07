import 'dart:math' as math;

import 'nav_bearing_smoother.dart';

/// Input signals for taxi/marker bearing target selection and step limits.
class NavBearingPolicyInput {
  final double? rawHeading;
  final double? routeBearing;
  final double? movementBearing;
  final double? lastBearing;
  final double speedKmh;
  final double? accuracyM;
  final double? routeConfidence;
  final bool hasReliableSnap;
  final bool offRouteLikely;
  final bool trustBearing;
  final bool trustRouteSnap;

  const NavBearingPolicyInput({
    this.rawHeading,
    this.routeBearing,
    this.movementBearing,
    this.lastBearing,
    this.speedKmh = 0.0,
    this.accuracyM,
    this.routeConfidence,
    this.hasReliableSnap = false,
    this.offRouteLikely = false,
    this.trustBearing = true,
    this.trustRouteSnap = false,
  });
}

/// Resolved bearing target before easing.
class NavBearingPolicyResult {
  final double targetBearing;
  final String source;
  final double maxStepDeg;
  final String reason;
  final double? targetDeltaDeg;

  const NavBearingPolicyResult({
    required this.targetBearing,
    required this.source,
    required this.maxStepDeg,
    required this.reason,
    this.targetDeltaDeg,
  });
}

/// NAV-R11-A: pure bearing policy — target selection + cautious step limits.
class NavBearingPolicy {
  static const double _lowSpeedHoldKmh = 3.5;
  static const double _gpsMinSpeedKmh = 4.0;
  static const double _movementMinSpeedKmh = 8.0;
  static const double _flipGuardDeg = 150.0;

  /// Picks the next bearing target and a safe max rotation step.
  static NavBearingPolicyResult resolve(NavBearingPolicyInput input) {
    final speed = math.max(0.0, input.speedKmh);
    final last = _validBearing(input.lastBearing);
    final route = _validBearing(input.routeBearing);
    final gps = _validBearing(input.rawHeading);
    final movement = _validBearing(input.movementBearing);
    final reliableRoute = input.hasReliableSnap && input.trustRouteSnap;

    String source;
    String reason;
    double target;

    if (speed < _lowSpeedHoldKmh) {
      if (last != null) {
        target = last;
        source = 'last';
        reason = 'low_speed_hold';
      } else if (reliableRoute && route != null) {
        target = route;
        source = 'route';
        reason = 'low_speed_route';
      } else {
        target = route ?? movement ?? 0.0;
        source = target == route
            ? 'route'
            : (target == movement ? 'gps' : 'fallback');
        reason = 'low_speed_fallback';
      }
    } else if (reliableRoute && route != null) {
      target = route;
      source = 'route';
      reason = 'route_snap';
    } else if (input.offRouteLikely ||
        (input.routeConfidence != null && input.routeConfidence! < 45.0)) {
      if (last != null) {
        target = last;
        source = 'last';
        reason = 'off_route_hold';
      } else if (movement != null && speed >= _movementMinSpeedKmh) {
        target = movement;
        source = 'gps';
        reason = 'off_route_movement';
      } else if (gps != null &&
          input.trustBearing &&
          speed >= _gpsMinSpeedKmh &&
          !_isFlipFrom(last, gps)) {
        target = gps;
        source = 'gps';
        reason = 'off_route_gps';
      } else {
        target = route ?? movement ?? gps ?? last ?? 0.0;
        source = _sourceForTarget(
          target: target,
          route: route,
          gps: gps,
          movement: movement,
          last: last,
        );
        reason = 'off_route_fallback';
      }
    } else if (gps != null &&
        input.trustBearing &&
        speed >= _gpsMinSpeedKmh &&
        !_isFlipFrom(last, gps)) {
      target = gps;
      source = 'gps';
      reason = 'gps_heading';
    } else if (movement != null &&
        (speed >= _movementMinSpeedKmh ||
            (gps == null && speed >= 5.0))) {
      target = movement;
      source = 'gps';
      reason = 'movement';
    } else if (last != null) {
      target = last;
      source = 'last';
      reason = 'last_stable';
    } else {
      target = route ?? movement ?? gps ?? 0.0;
      source = _sourceForTarget(
        target: target,
        route: route,
        gps: gps,
        movement: movement,
        last: last,
      );
      reason = 'fallback';
    }

    target = NavBearingSmoother.normalizeBearing(target);
    final delta = last == null
        ? null
        : NavBearingSmoother.bearingDelta(last, target);
    final maxStep = maxStepDeg(
      speedKmh: speed,
      accuracyM: input.accuracyM,
      routeConfidence: input.routeConfidence,
      offRouteLikely: input.offRouteLikely,
      trustBearing: input.trustBearing,
      deltaAbs: delta?.abs(),
      source: source,
    );

    return NavBearingPolicyResult(
      targetBearing: target,
      source: source,
      maxStepDeg: maxStep,
      reason: reason,
      targetDeltaDeg: delta,
    );
  }

  /// Eases [previous] toward [target] with correct wrap-around.
  static double stepToward({
    required double? previous,
    required double target,
    required double maxStepDeg,
  }) {
    final normalizedTarget = NavBearingSmoother.normalizeBearing(target);
    if (previous == null || !previous.isFinite) {
      return normalizedTarget;
    }
    final delta = NavBearingSmoother.bearingDelta(previous, normalizedTarget);
    final step = maxStepDeg.clamp(0.5, 36.0);
    if (delta.abs() <= step) {
      return normalizedTarget;
    }
    return NavBearingSmoother.normalizeBearing(previous + delta.sign * step);
  }

  static double maxStepDeg({
    required double speedKmh,
    double? accuracyM,
    double? routeConfidence,
    bool offRouteLikely = false,
    bool trustBearing = true,
    double? deltaAbs,
    String source = 'fallback',
  }) {
    final speed = math.max(0.0, speedKmh);
    double base;
    if (speed < 3.5) {
      base = 3.5;
    } else if (speed < 8.0) {
      base = 10.0;
    } else if (speed < 25.0) {
      base = 18.0;
    } else {
      base = 28.0;
    }

    if (source == 'route' && speed >= 8.0) {
      base = math.min(32.0, base + 4.0);
    }

    var factor = 1.0;
    if (offRouteLikely) {
      factor *= 0.30;
    } else if (routeConfidence != null && routeConfidence < 45.0) {
      factor *= 0.45;
    } else if (routeConfidence != null && routeConfidence < 55.0) {
      factor *= 0.65;
    }

    if (accuracyM != null && accuracyM.isFinite) {
      if (accuracyM > 60.0) {
        factor *= 0.40;
      } else if (accuracyM > 40.0) {
        factor *= 0.55;
      } else if (accuracyM > 20.0) {
        factor *= 0.75;
      }
    }

    if (!trustBearing) factor *= 0.55;

    final absDelta = deltaAbs ?? 0.0;
    if (absDelta > 100.0) {
      factor *= 0.35;
    } else if (absDelta > 70.0) {
      factor *= 0.50;
    } else if (absDelta > 45.0) {
      factor *= 0.70;
    }

    return (base * factor).clamp(2.0, 32.0);
  }

  static double? _validBearing(double? value) {
    if (value == null || !value.isFinite || value < 0) return null;
    return NavBearingSmoother.normalizeBearing(value);
  }

  static bool _isFlipFrom(double? last, double candidate) {
    if (last == null) return false;
    return NavBearingSmoother.bearingDelta(last, candidate).abs() > _flipGuardDeg;
  }

  static String _sourceForTarget({
    required double target,
    double? route,
    double? gps,
    double? movement,
    double? last,
  }) {
    if (route != null && target == route) return 'route';
    if (gps != null && target == gps) return 'gps';
    if (movement != null && target == movement) return 'gps';
    if (last != null && target == last) return 'last';
    return 'fallback';
  }
}
