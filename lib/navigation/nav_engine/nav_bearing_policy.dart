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

  /// NAV-R12-C: route-deviation signals from `DriverNavRouteProgress`.
  final bool routeDeviationLikely;
  final bool oppositeDirectionLikely;
  final bool backwardProgressLikely;

  /// NAV-R12-C: 0..180 delta between GPS course and matched segment bearing.
  final double? headingDeltaDeg;

  /// NAV-R12-C: forward route progress trust; route bearing may only win
  /// while this holds.
  final bool forwardProgress;

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
    this.routeDeviationLikely = false,
    this.oppositeDirectionLikely = false,
    this.backwardProgressLikely = false,
    this.headingDeltaDeg,
    this.forwardProgress = true,
  });
}

/// Resolved bearing target before easing.
class NavBearingPolicyResult {
  final double targetBearing;
  final String source;
  final double maxStepDeg;
  final String reason;
  final double? targetDeltaDeg;

  /// NAV-R12-C: whether route segment bearing was eligible to drive the
  /// taxi nose this cycle (reliable snap, no deviation, course agreement).
  final bool routeBearingAllowed;

  const NavBearingPolicyResult({
    required this.targetBearing,
    required this.source,
    required this.maxStepDeg,
    required this.reason,
    this.targetDeltaDeg,
    this.routeBearingAllowed = false,
  });
}

/// NAV-R11-A: pure bearing policy — target selection + cautious step limits.
/// NAV-R12-C: route deviation demotes route bearing and unlocks fast
/// convergence toward the real GPS/course direction.
class NavBearingPolicy {
  static const double _lowSpeedHoldKmh = 3.5;
  static const double _gpsMinSpeedKmh = 4.0;
  static const double _movementMinSpeedKmh = 8.0;
  static const double _flipGuardDeg = 150.0;

  // NAV-R12-C: while the route is unreliable, the real course must win from
  // this speed on, and the nose may swing fast enough to converge on an
  // opposite course within ~1-2 seconds.
  static const double _courseMinSpeedKmh = 5.0;
  static const double _routeCourseAgreementDeg = 60.0;
  static const double _deviationFastStepDeg = 90.0;
  static const double _deviationSlowStepDeg = 60.0;

  /// Picks the next bearing target and a safe max rotation step.
  static NavBearingPolicyResult resolve(NavBearingPolicyInput input) {
    final speed = math.max(0.0, input.speedKmh);
    final last = _validBearing(input.lastBearing);
    final route = _validBearing(input.routeBearing);
    final gps = _validBearing(input.rawHeading);
    final movement = _validBearing(input.movementBearing);
    final reliableRoute = input.hasReliableSnap && input.trustRouteSnap;

    // NAV-R12-C: any route-invalidating signal demotes route bearing.
    final deviationActive =
        input.routeDeviationLikely ||
        input.oppositeDirectionLikely ||
        input.backwardProgressLikely ||
        input.offRouteLikely;

    // Course-vs-route agreement (0..180). Prefer the progress engine's
    // delta; fall back to a local computation when both bearings exist.
    final headingDelta =
        input.headingDeltaDeg ??
        ((gps != null && route != null)
            ? NavBearingSmoother.bearingDelta(gps, route).abs()
            : null);

    // Route bearing may drive the nose only with reliable snap, no
    // deviation, trusted forward progress, and course agreement <= ~60°.
    final routeBearingAllowed =
        reliableRoute &&
        route != null &&
        !deviationActive &&
        input.forwardProgress &&
        (headingDelta == null || headingDelta <= _routeCourseAgreementDeg);

    String source;
    String reason;
    double target;
    var fastConverge = false;

    if (speed < _lowSpeedHoldKmh) {
      // Stationary/creeping: hold to avoid taxi spinning.
      if (last != null) {
        target = last;
        source = 'last';
        reason = 'low_speed_hold';
      } else if (routeBearingAllowed) {
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
    } else if (deviationActive &&
        speed >= _courseMinSpeedKmh &&
        (gps != null || movement != null)) {
      // NAV-R12-C: route no longer matches actual movement — the real
      // course wins immediately, without flip guard, without holding the
      // old route-aligned bearing.
      target = gps ?? movement!;
      source = 'gps';
      reason = gps != null ? 'deviation_gps_course' : 'deviation_movement';
      fastConverge = true;
    } else if (routeBearingAllowed) {
      target = route;
      source = 'route';
      reason = 'route_snap';
    } else if (gps != null &&
        input.trustBearing &&
        speed >= _gpsMinSpeedKmh &&
        !_isFlipFrom(last, gps)) {
      target = gps;
      source = 'gps';
      reason = 'gps_heading';
    } else if (movement != null &&
        (speed >= _movementMinSpeedKmh || (gps == null && speed >= 5.0))) {
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
      fastConverge: fastConverge,
    );

    return NavBearingPolicyResult(
      targetBearing: target,
      source: source,
      maxStepDeg: maxStep,
      reason: reason,
      targetDeltaDeg: delta,
      routeBearingAllowed: routeBearingAllowed,
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
    // NAV-R12-C: allow deviation fast-convergence steps through the easing
    // clamp; normal cautious steps stay well below this ceiling.
    final step = maxStepDeg.clamp(0.5, 120.0);
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
    bool fastConverge = false,
  }) {
    final speed = math.max(0.0, speedKmh);

    // NAV-R12-C: confirmed route deviation must let the nose swing to the
    // true course within ~1-2 seconds instead of being dampened by the
    // off-route caution factors below. Only very poor GPS accuracy still
    // slows the swing down.
    if (fastConverge) {
      final fast = speed >= 8.0 ? _deviationFastStepDeg : _deviationSlowStepDeg;
      if (accuracyM != null && accuracyM.isFinite && accuracyM > 60.0) {
        return fast * 0.5;
      }
      return fast;
    }
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
    return NavBearingSmoother.bearingDelta(last, candidate).abs() >
        _flipGuardDeg;
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
