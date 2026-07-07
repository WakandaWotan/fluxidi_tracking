import 'nav_bearing_smoother.dart';
import 'nav_engine_input.dart';
import 'nav_engine_output.dart';
import 'nav_motion_smoother.dart';

/// Local navigation engine: smooths marker bearing/position for live driver UI.
///
/// Pure Dart — no Mapbox dependency. GPS updates should flow:
/// NavEngineInput → [DriverNavEngine.update] → NavEngineOutput.
class DriverNavEngine {
  NavEngineOutput? _previousOutput;
  final NavBearingSmoother _bearingSmoother = NavBearingSmoother();
  final NavMotionSmoother _motionSmoother = NavMotionSmoother();

  NavEngineOutput? get previousOutput => _previousOutput;

  String get lastBearingSource => _bearingSmoother.lastSource;

  String get lastBearingReason => _bearingSmoother.lastReason;

  bool get lastRouteBearingAllowed => _bearingSmoother.lastRouteBearingAllowed;

  void reset() {
    _previousOutput = null;
    _bearingSmoother.reset();
    _motionSmoother.reset();
  }

  NavEngineOutput update(NavEngineInput input) {
    final motion = _motionSmoother.resolve(
      input: input,
      previousOutput: _previousOutput,
    );

    final bearing = _bearingSmoother.smooth(
      rawHeading: input.rawHeading,
      routeBearing: input.routeBearing,
      speedKmh: input.speedKmh,
      hasReliableSnap: input.hasReliableSnap,
      movementBearing: input.movementBearing,
      accuracyM: input.accuracyM,
      routeConfidence: input.routeConfidence,
      offRouteLikely: input.offRouteLikely,
      trustBearing: input.trustBearing,
      trustRouteSnap: input.hasReliableSnap,
      routeDeviationLikely: input.routeDeviationLikely,
      oppositeDirectionLikely: input.oppositeDirectionLikely,
      backwardProgressLikely: input.backwardProgressLikely,
      headingDeltaDeg: input.headingDeltaDeg,
      forwardProgress: input.forwardProgress,
    );

    final cameraReason = _cameraReasonFor(input, motion.markerSource);

    final output = NavEngineOutput(
      timestamp: input.timestamp,
      displayLatitude: motion.latitude,
      displayLongitude: motion.longitude,
      bearing: bearing,
      markerSource: motion.markerSource,
      shouldAnimateMarker: motion.shouldAnimateMarker,
      cameraFollowMode: input.cameraFollowMode,
      cameraReason: cameraReason,
      speedKmh: input.speedKmh,
      accuracyM: input.accuracyM,
    );
    _previousOutput = output;
    return output;
  }

  String _cameraReasonFor(NavEngineInput input, String markerSource) {
    if (!input.liveRideActive) return 'inactive';
    if (!input.cameraFollowMode) return 'not_follow';
    if (markerSource == 'fallback') return 'fallback';
    return 'engine_follow';
  }
}
