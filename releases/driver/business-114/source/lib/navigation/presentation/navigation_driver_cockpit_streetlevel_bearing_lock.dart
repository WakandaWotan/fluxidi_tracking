import '../nav_engine/nav_bearing_policy.dart';
import '../nav_engine/nav_bearing_smoother.dart';
import 'nav_stationary_bearing_hold.dart';
import 'navigation_driver_cockpit_camera.dart';
import 'navigation_driver_route_bearing.dart';

/// NAV-PRES-3L-A: presentation-only streetlevel bearing lock input.
class DriverCockpitStreetlevelBearingLockInput {
  const DriverCockpitStreetlevelBearingLockInput({
    required this.routeBearing,
    required this.viewLevel,
    required this.speedKmh,
    this.gpsHeadingDeg,
    this.gpsAccuracyM,
    this.previousAppliedBearingDeg,
    this.instantApply = false,
    this.displacementM,
  });

  final DriverRouteBearingOutput routeBearing;
  final int viewLevel;
  final double speedKmh;
  final double? gpsHeadingDeg;
  final double? gpsAccuracyM;
  final double? previousAppliedBearingDeg;
  final bool instantApply;

  /// NAV-PRESTART-PREVIEW-AND-STABLE-BEARING-P0: metres travelled since the
  /// previously applied bearing. Lets a slow-but-genuinely-moving vehicle
  /// re-target even when the reported speed is unreliable.
  final double? displacementM;
}

/// NAV-PRES-3L-A: presentation-only streetlevel bearing lock output.
class DriverCockpitStreetlevelBearingLockOutput {
  const DriverCockpitStreetlevelBearingLockOutput({
    required this.appliedBearing,
    required this.targetBearing,
    required this.deltaDeg,
    required this.mode,
    required this.result,
    this.reason,
  });

  final double appliedBearing;
  final double targetBearing;
  final double deltaDeg;
  final String mode;
  final String result;
  final String? reason;
}

const int kDriverCockpitStreetlevelBearingLockMinLevel = 7;
const double kDriverCockpitStreetlevelGpsBlendMaxWeight = 0.14;
const double kDriverCockpitStreetlevelGpsReliableMinSpeedKmh = 8.0;
const double kDriverCockpitStreetlevelGpsReliableMaxAccuracyM = 25.0;

bool driverCockpitStreetlevelBearingLockActive(int viewLevel) {
  return clampDriverCockpitViewLevel(viewLevel) >=
      kDriverCockpitStreetlevelBearingLockMinLevel;
}

bool driverCockpitGpsHeadingReliableForBearingLock({
  required double speedKmh,
  required double? gpsAccuracyM,
}) {
  return speedKmh >= kDriverCockpitStreetlevelGpsReliableMinSpeedKmh &&
      gpsAccuracyM != null &&
      gpsAccuracyM.isFinite &&
      gpsAccuracyM > 0 &&
      gpsAccuracyM <= kDriverCockpitStreetlevelGpsReliableMaxAccuracyM;
}

double driverCockpitStreetlevelBearingMaxStepDeg({
  required double speedKmh,
  required int viewLevel,
  required bool instantApply,
}) {
  if (instantApply) return 0.0;
  if (!driverCockpitStreetlevelBearingLockActive(viewLevel)) {
    return 180.0;
  }
  if (speedKmh < 2.0) return 2.5;
  if (speedKmh < 5.0) return 5.0;
  if (speedKmh < 12.0) return 10.0;
  if (speedKmh < 30.0) return 22.0;
  return 36.0;
}

double driverCockpitBlendBearings({
  required double primaryDeg,
  required double secondaryDeg,
  required double secondaryWeight,
}) {
  final w = secondaryWeight.clamp(0.0, 0.35);
  if (w <= 0) return NavBearingSmoother.normalizeBearing(primaryDeg);
  final delta = NavBearingSmoother.bearingDelta(primaryDeg, secondaryDeg);
  return NavBearingSmoother.normalizeBearing(primaryDeg + delta * w);
}

/// NAV-PRES-3L-A: locks map bearing under the fixed HUD taxi nose in cockpit
/// streetlevel views. The route bearing resolver is unchanged; this layer only
/// shapes the final camera bearing for presentation.
DriverCockpitStreetlevelBearingLockOutput
applyDriverCockpitStreetlevelBearingLock(
  DriverCockpitStreetlevelBearingLockInput input,
) {
  final previous = input.previousAppliedBearingDeg != null &&
          input.previousAppliedBearingDeg!.isFinite
      ? NavBearingSmoother.normalizeBearing(input.previousAppliedBearingDeg!)
      : null;
  final resolverBearing =
      NavBearingSmoother.normalizeBearing(input.routeBearing.bearing);

  if (!driverCockpitStreetlevelBearingLockActive(input.viewLevel)) {
    return DriverCockpitStreetlevelBearingLockOutput(
      appliedBearing: resolverBearing,
      targetBearing: resolverBearing,
      deltaDeg: previous == null
          ? 0.0
          : NavBearingSmoother.bearingDelta(previous, resolverBearing),
      mode: 'hold',
      result: 'skipped',
      reason: 'below_streetlevel_level',
    );
  }

  final gps = input.gpsHeadingDeg != null &&
          input.gpsHeadingDeg!.isFinite &&
          input.gpsHeadingDeg! >= 0
      ? NavBearingSmoother.normalizeBearing(input.gpsHeadingDeg!)
      : null;
  final tangent = input.routeBearing.routeTangentBearing;

  late final double targetBearing;
  late final String mode;
  late final String? reason;

  // NAV-PRESTART-PREVIEW-AND-STABLE-BEARING-P0: the route tangent used to be
  // adopted unconditionally, which made the branches below unreachable with a
  // route loaded. A stationary vehicle re-snaps to a slightly different segment
  // on every fix, so the tangent itself oscillates and rotated the map
  // continuously. Movement must be trustworthy before ANY re-target; until then
  // the established bearing is held. The tangent is still the *initial*
  // orientation when nothing has been established yet, so START opens facing
  // along the route rather than adopting a random stationary course.
  final movementTrustworthy = navBearingMovementTrustworthy(
    speedKmh: input.speedKmh,
    displacementM: input.displacementM,
    accuracyM: input.gpsAccuracyM,
  );

  if (!movementTrustworthy && previous != null) {
    targetBearing = previous;
    mode = 'hold';
    reason = input.speedKmh < kNavBearingStationarySpeedKmh
        ? 'stationary_hold'
        : 'low_confidence_hold';
  } else if (tangent != null) {
    final tangentBearing = NavBearingSmoother.normalizeBearing(tangent);
    if (gps != null &&
        driverCockpitGpsHeadingReliableForBearingLock(
          speedKmh: input.speedKmh,
          gpsAccuracyM: input.gpsAccuracyM,
        )) {
      targetBearing = driverCockpitBlendBearings(
        primaryDeg: tangentBearing,
        secondaryDeg: gps,
        secondaryWeight: kDriverCockpitStreetlevelGpsBlendMaxWeight,
      );
      mode = 'speed_blend';
      reason = 'route_tangent_with_gps_stabilizer';
    } else {
      targetBearing = tangentBearing;
      mode = 'route_tangent';
      reason = 'route_tangent_primary';
    }
  } else if (input.speedKmh < 3.0 && previous != null) {
    targetBearing = previous;
    mode = 'hold';
    reason = 'low_speed_hold';
  } else if (gps != null &&
      driverCockpitGpsHeadingReliableForBearingLock(
        speedKmh: input.speedKmh,
        gpsAccuracyM: input.gpsAccuracyM,
      )) {
    targetBearing = gps;
    mode = 'speed_blend';
    reason = 'gps_without_tangent';
  } else if (previous != null) {
    targetBearing = previous;
    mode = 'hold';
    reason = 'hold_without_tangent';
  } else {
    targetBearing = resolverBearing;
    mode = 'hold';
    reason = 'resolver_fallback';
  }

  final maxStep = driverCockpitStreetlevelBearingMaxStepDeg(
    speedKmh: input.speedKmh,
    viewLevel: input.viewLevel,
    instantApply: input.instantApply,
  );
  final applied = maxStep <= 0
      ? targetBearing
      : NavBearingPolicy.stepToward(
          previous: previous,
          target: targetBearing,
          maxStepDeg: maxStep,
        );
  final deltaDeg = previous == null
      ? NavBearingSmoother.bearingDelta(targetBearing, applied)
      : NavBearingSmoother.bearingDelta(previous, applied);

  return DriverCockpitStreetlevelBearingLockOutput(
    appliedBearing: NavBearingSmoother.normalizeBearing(applied),
    targetBearing: targetBearing,
    deltaDeg: deltaDeg,
    mode: mode,
    result: 'applied',
    reason: input.instantApply ? 'instant_apply' : reason,
  );
}
