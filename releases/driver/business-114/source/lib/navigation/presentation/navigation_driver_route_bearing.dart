import '../driver_navigation_geometry.dart';
import '../driver_navigation_models.dart';
import '../nav_engine/nav_bearing_policy.dart';
import '../nav_engine/nav_bearing_smoother.dart';
import 'nav_stationary_bearing_hold.dart';

/// Input for NAV-PRES-3E route-locked cockpit camera bearing.
class DriverRouteBearingInput {
  final List<DriverLonLat> routeCoords;
  final int? segmentIndex;
  final double? snappedLat;
  final double? snappedLon;
  final bool hasReliableSnap;
  final double? gpsHeadingDeg;
  final double? previousBearingDeg;
  final double? routeConfidence;
  final bool offRouteLikely;
  final bool forwardProgress;
  final double speedKmh;

  /// Short forward tangent distance (8–20 m). Defaults to 12 m so bearing
  /// follows the local route segment instead of over-anticipating curves.
  final double tangentLookaheadM;
  final double maxStepDeg;

  /// NAV-PRESTART-PREVIEW-AND-STABLE-BEARING-P0: metres travelled since the
  /// previous bearing, and the reported horizontal accuracy. Both feed the
  /// movement-confidence gate that guards the raw GPS heading fallback.
  final double? displacementM;
  final double? accuracyM;

  const DriverRouteBearingInput({
    this.routeCoords = const <DriverLonLat>[],
    this.segmentIndex,
    this.snappedLat,
    this.snappedLon,
    this.hasReliableSnap = false,
    this.gpsHeadingDeg,
    this.previousBearingDeg,
    this.routeConfidence,
    this.offRouteLikely = false,
    this.forwardProgress = true,
    this.speedKmh = 0.0,
    this.tangentLookaheadM = kDriverRouteBearingTangentLookaheadM,
    this.maxStepDeg = 0.0,
    this.displacementM,
    this.accuracyM,
  });
}

/// Resolved route-locked bearing for cockpit driver view.
class DriverRouteBearingOutput {
  final double bearing;
  final String source;
  final double confidence;
  final String reason;
  final double? gpsBearing;
  final double? deltaDeg;
  final double? routeTangentBearing;

  const DriverRouteBearingOutput({
    required this.bearing,
    required this.source,
    required this.confidence,
    required this.reason,
    this.gpsBearing,
    this.deltaDeg,
    this.routeTangentBearing,
  });
}

/// NAV-PRES-3E: short forward tangent for route-locked bearing.
const double kDriverRouteBearingTangentLookaheadM = 12.0;

/// NAV-PRES-3E: reject tangent candidates ~180° off reference bearing.
const double kDriverRouteBearingFlipGuardDeg = 150.0;

const double kDriverRouteBearingDefaultMaxStepDeg = 22.0;
const double kDriverRouteBearingLowSpeedMaxStepDeg = 14.0;
const double kDriverRouteBearingLowSpeedKmh = 4.0;

/// NAV-PRES-3E: bounded bearing step for cockpit camera (responsive in turns).
double driverRouteBearingMaxStep({required double speedKmh}) {
  if (speedKmh < kDriverRouteBearingLowSpeedKmh) {
    return kDriverRouteBearingLowSpeedMaxStepDeg;
  }
  return (kDriverRouteBearingDefaultMaxStepDeg + speedKmh * 0.15)
      .clamp(kDriverRouteBearingDefaultMaxStepDeg, 28.0);
}

double? resolveDriverRouteTangentBearing(DriverRouteBearingInput input) {
  if (!input.hasReliableSnap ||
      input.routeCoords.length < 2 ||
      input.segmentIndex == null ||
      input.snappedLat == null ||
      input.snappedLon == null ||
      input.offRouteLikely ||
      !input.forwardProgress) {
    return null;
  }
  final i = input.segmentIndex!.clamp(0, input.routeCoords.length - 2);
  return driverForwardRouteBearing(
    input.routeCoords,
    segmentIndex: i,
    snappedLat: input.snappedLat!,
    snappedLon: input.snappedLon!,
    lookaheadM: input.tangentLookaheadM.clamp(8.0, 20.0),
  );
}

bool driverRouteBearingIsFlipCandidate(double? reference, double candidate) {
  if (reference == null) return false;
  return NavBearingSmoother.bearingDelta(reference, candidate).abs() >
      kDriverRouteBearingFlipGuardDeg;
}

/// NAV-PRES-3E: route-locked bearing for cockpit driver view.
///
/// Prefers a short forward route tangent when snap is reliable; GPS heading
/// is fallback only. Applies shortest-angle smoothing with bounded steps.
DriverRouteBearingOutput resolveDriverRouteBearing(
  DriverRouteBearingInput input,
) {
  final gps = input.gpsHeadingDeg != null &&
          input.gpsHeadingDeg!.isFinite &&
          input.gpsHeadingDeg! >= 0
      ? NavBearingSmoother.normalizeBearing(input.gpsHeadingDeg!)
      : null;
  final previous = input.previousBearingDeg != null &&
          input.previousBearingDeg!.isFinite
      ? NavBearingSmoother.normalizeBearing(input.previousBearingDeg!)
      : null;
  // NAV-PRESTART-PREVIEW-AND-STABLE-BEARING-P0: raw course-over-ground is noise
  // at a standstill (geolocator reports an arbitrary value, or -1). It may only
  // act as a bearing source once movement is trustworthy; otherwise the last
  // resolved bearing is held.
  final double? eligibleGps = gps != null &&
          navBearingMovementTrustworthy(
            speedKmh: input.speedKmh,
            displacementM: input.displacementM,
            accuracyM: input.accuracyM,
          )
      ? gps
      : null;

  final tangent = resolveDriverRouteTangentBearing(input);
  var usableTangent = tangent;
  var rejectReason = '';
  if (usableTangent != null &&
      driverRouteBearingIsFlipCandidate(
        previous ?? eligibleGps,
        usableTangent,
      )) {
    usableTangent = null;
    rejectReason = 'flip_guard_previous';
  }
  // Only a trustworthy GPS course may veto a route tangent; stationary noise
  // must not reject the correct road orientation.
  if (usableTangent != null &&
      eligibleGps != null &&
      driverRouteBearingIsFlipCandidate(eligibleGps, usableTangent)) {
    usableTangent = null;
    rejectReason = 'flip_guard_gps';
  }

  late final String source;
  late final String reason;
  late final double target;
  late final double confidence;

  if (usableTangent != null) {
    target = usableTangent;
    source = 'route_tangent';
    reason = 'route_snap_tangent';
    confidence = (input.routeConfidence ?? 85.0).clamp(0.0, 100.0);
  } else if (eligibleGps != null) {
    target = eligibleGps;
    source = 'gps_heading';
    reason = tangent != null
        ? (rejectReason.isEmpty ? 'tangent_rejected' : rejectReason)
        : 'no_route_tangent';
    confidence = 55.0;
  } else if (previous != null) {
    target = previous;
    source = 'fallback';
    reason = 'hold_previous';
    confidence = 35.0;
  } else {
    target = tangent ?? 0.0;
    source = tangent != null ? 'route_tangent' : 'fallback';
    reason = tangent != null ? 'unreliable_snap_tangent' : 'cold_start';
    confidence = tangent != null ? 45.0 : 0.0;
  }

  final normalizedTarget = NavBearingSmoother.normalizeBearing(target);
  final maxStep = input.maxStepDeg > 0
      ? input.maxStepDeg
      : driverRouteBearingMaxStep(speedKmh: input.speedKmh);
  final smoothed = NavBearingPolicy.stepToward(
    previous: previous,
    target: normalizedTarget,
    maxStepDeg: maxStep,
  );
  final delta = previous == null
      ? NavBearingSmoother.bearingDelta(normalizedTarget, smoothed)
      : NavBearingSmoother.bearingDelta(previous, smoothed);

  return DriverRouteBearingOutput(
    bearing: smoothed,
    source: source,
    confidence: confidence,
    reason: reason,
    gpsBearing: gps,
    deltaDeg: delta,
    routeTangentBearing: tangent,
  );
}
