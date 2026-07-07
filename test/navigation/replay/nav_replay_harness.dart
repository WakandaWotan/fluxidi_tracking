// NAV-R12-F: test-only replay harness for the driver navigation engine.
//
// Feeds recorded/synthetic GPS samples sequentially through the pure-Dart
// production modules (route progress, confidence, bearing policy, motion
// prediction, instruction policy) without a map, geolocator stream, or any
// network call, and mirrors the small state-level off-route/reroute gate
// from driver_home_page_state.dart.
import 'dart:math' as math;

import 'package:fluxidi_tracking/navigation/nav_engine/nav_bearing_policy.dart';
import 'package:fluxidi_tracking/navigation/nav_engine/nav_bearing_smoother.dart';
import 'package:fluxidi_tracking/navigation/nav_engine/nav_confidence_engine.dart';
import 'package:fluxidi_tracking/navigation/nav_engine/nav_instruction_policy.dart';
import 'package:fluxidi_tracking/navigation/nav_engine/nav_motion_prediction.dart';
import 'package:fluxidi_tracking/navigation/nav_engine/nav_route_progress.dart';

import 'nav_replay_sample.dart';

/// Structured per-sample replay output.
class NavReplaySampleResult {
  final int index;
  final DateTime timestamp;
  final double speedKmh;
  final double snapDistanceM;
  final bool offRouteLikely;
  final String offRouteReason;
  final bool routeDeviationLikely;
  final bool oppositeDirectionLikely;
  final String routeDeviationReason;
  final bool backwardProgressLikely;
  final double? headingDeltaDeg;
  final String bearingSource;
  final String bearingReason;
  final double displayBearing;
  final bool routeBearingAllowed;
  final bool trustSnap;
  final bool trustBearing;
  final String instructionReason;
  final String instructionText;
  final bool showOriginalInstruction;
  final bool predictionActive;
  final String predictionReason;
  final bool rerouteEligible;
  final bool rerouteWouldTrigger;
  final String progressReason;

  const NavReplaySampleResult({
    required this.index,
    required this.timestamp,
    required this.speedKmh,
    required this.snapDistanceM,
    required this.offRouteLikely,
    required this.offRouteReason,
    required this.routeDeviationLikely,
    required this.oppositeDirectionLikely,
    required this.routeDeviationReason,
    required this.backwardProgressLikely,
    required this.headingDeltaDeg,
    required this.bearingSource,
    required this.bearingReason,
    required this.displayBearing,
    required this.routeBearingAllowed,
    required this.trustSnap,
    required this.trustBearing,
    required this.instructionReason,
    required this.instructionText,
    required this.showOriginalInstruction,
    required this.predictionActive,
    required this.predictionReason,
    required this.rerouteEligible,
    required this.rerouteWouldTrigger,
    required this.progressReason,
  });
}

/// Aggregated replay run output with a compact printable report.
class NavReplayReport {
  final String fixtureName;
  final List<NavReplaySampleResult> results;

  const NavReplayReport({required this.fixtureName, required this.results});

  int get samplesProcessed => results.length;

  int? get firstRouteDeviationIndex =>
      _firstIndex((r) => r.routeDeviationLikely);

  int? get firstOppositeDirectionIndex =>
      _firstIndex((r) => r.oppositeDirectionLikely);

  int? get firstOffRouteIndex => _firstIndex((r) => r.offRouteLikely);

  int? get firstRerouteEligibleIndex => _firstIndex((r) => r.rerouteEligible);

  int? get firstRerouteWouldTriggerIndex =>
      _firstIndex((r) => r.rerouteWouldTrigger);

  /// NAV-R12-C: first sample index (>= [fromIndex]) where the display
  /// bearing is within [toleranceDeg] of [targetDeg].
  int? firstBearingWithin({
    required double targetDeg,
    double toleranceDeg = 20.0,
    int fromIndex = 0,
  }) {
    for (final r in results) {
      if (r.index < fromIndex) continue;
      final delta = NavBearingSmoother.bearingDelta(
        r.displayBearing,
        targetDeg,
      ).abs();
      if (delta <= toleranceDeg) return r.index;
    }
    return null;
  }

  double get maxHeadingDeltaDeg {
    var max = 0.0;
    for (final r in results) {
      final d = r.headingDeltaDeg;
      if (d != null && d.isFinite && d > max) max = d;
    }
    return max;
  }

  /// Bearing source transitions as "index:from->to" tokens.
  List<String> get bearingSourceTransitions {
    final transitions = <String>[];
    String? previous;
    for (final r in results) {
      if (previous != null && r.bearingSource != previous) {
        transitions.add('${r.index}:$previous->${r.bearingSource}');
      }
      previous = r.bearingSource;
    }
    return transitions;
  }

  int? _firstIndex(bool Function(NavReplaySampleResult) test) {
    for (final r in results) {
      if (test(r)) return r.index;
    }
    return null;
  }

  String _indexAndTime(int? index) {
    if (index == null) return 'never';
    final r = results[index];
    final t0 = results.first.timestamp;
    final relMs = r.timestamp.difference(t0).inMilliseconds;
    return 'sample=$index t=+${(relMs / 1000.0).toStringAsFixed(1)}s';
  }

  String compactReport() {
    final buffer = StringBuffer()
      ..writeln('--- NAV_R12_REPLAY fixture=$fixtureName ---')
      ..writeln('samplesProcessed=$samplesProcessed')
      ..writeln(
        'firstRouteDeviation=${_indexAndTime(firstRouteDeviationIndex)}',
      )
      ..writeln('firstOffRouteLikely=${_indexAndTime(firstOffRouteIndex)}')
      ..writeln(
        'firstRerouteEligible=${_indexAndTime(firstRerouteEligibleIndex)}',
      )
      ..writeln(
        'firstRerouteWouldTrigger='
        '${_indexAndTime(firstRerouteWouldTriggerIndex)}',
      )
      ..writeln('maxHeadingDeltaDeg=${maxHeadingDeltaDeg.toStringAsFixed(0)}')
      ..writeln(
        'bearingSourceTransitions='
        '${bearingSourceTransitions.isEmpty ? 'none' : bearingSourceTransitions.join(' ')}',
      );
    return buffer.toString();
  }
}

/// Synthetic maneuver context for the instruction policy during replay.
class NavReplayInstructionContext {
  final String rawInstructionText;
  final String maneuverType;
  final String maneuverModifier;
  final double distanceToManeuverM;

  const NavReplayInstructionContext({
    this.rawInstructionText = 'Turn left onto Elm Street',
    this.maneuverType = 'turn',
    this.maneuverModifier = 'left',
    this.distanceToManeuverM = 400.0,
  });
}

/// Runs samples through the production nav modules and the mirrored
/// state-level off-route/reroute gate.
class NavReplayHarness {
  // ---------------------------------------------------------------------
  // Mirror of driver_home_page_state.dart NAV-R12-B gating.
  //
  // SEAM (NAV-R12-C follow-up): these thresholds live inside the widget
  // state in production and are duplicated here. Extracting them into a
  // pure `NavOffRouteDecision` module would let this harness exercise the
  // exact production object instead of a mirror.
  // ---------------------------------------------------------------------
  static const Duration rerouteCooldown = Duration(seconds: 25);
  static const Duration rerouteCooldownRouteDeviation = Duration(seconds: 8);
  static const Duration debounceStrong = Duration(milliseconds: 500);
  static const Duration debounceRouteDeviation = Duration(milliseconds: 800);
  static const Duration debounceDefault = Duration(milliseconds: 2500);

  final List<NavRoutePoint> routePoints;
  final NavReplayInstructionContext instructionContext;

  final DriverNavRouteProgress _routeProgress = DriverNavRouteProgress();
  final DriverNavConfidenceEngine _confidenceEngine =
      DriverNavConfidenceEngine();
  final DriverNavInstructionPolicy _instructionPolicy =
      DriverNavInstructionPolicy();
  final DriverNavMotionPrediction _motionPrediction =
      DriverNavMotionPrediction();

  NavReplayHarness({
    required this.routePoints,
    this.instructionContext = const NavReplayInstructionContext(),
  });

  NavReplayReport run({
    required String fixtureName,
    required List<NavReplaySample> samples,
  }) {
    _routeProgress.reset();
    _confidenceEngine.reset();
    _instructionPolicy.reset();
    _motionPrediction.reset();

    final results = <NavReplaySampleResult>[];

    double? lastBearing;
    NavReplaySample? previousSample;
    double? movementBearing;

    // Mirrored state-level off-route gate.
    var offRouteHitCount = 0;
    var offRouteLikelyState = false;
    var offRouteReason = 'none';
    DateTime? debounceStartedAt;
    DateTime? lastRerouteAt;

    for (var i = 0; i < samples.length; i++) {
      final sample = samples[i];

      // Movement bearing parity with production (>= 1.8 m between fixes).
      if (previousSample != null) {
        final movedM = _haversineMeters(
          previousSample.latitude,
          previousSample.longitude,
          sample.latitude,
          sample.longitude,
        );
        if (movedM >= 1.8) {
          movementBearing = _bearingFromPoints(
            previousSample.latitude,
            previousSample.longitude,
            sample.latitude,
            sample.longitude,
          );
        }
      }

      final progress = _routeProgress.update(
        NavRouteProgressInput(
          timestamp: sample.timestamp,
          rawLatitude: sample.latitude,
          rawLongitude: sample.longitude,
          rawHeading: sample.headingDeg,
          speedKmh: sample.speedKmh,
          accuracyM: sample.accuracyM,
          routePoints: routePoints,
        ),
      );

      final confidence = _confidenceEngine.update(
        NavConfidenceInput(
          timestamp: sample.timestamp,
          gpsAccuracyM: sample.accuracyM,
          speedKmh: sample.speedKmh,
          routeConfidence: progress.confidence,
          snapDistanceM: progress.snapDistanceM,
          hasReliableSnap: progress.hasReliableSnap,
          offRouteLikely: progress.offRouteLikely,
          forwardProgress: progress.forwardProgress,
          headingDeltaDeg: progress.headingDeltaDeg,
          liveRideActive: true,
        ),
      );

      // Mirrored off-route hit/debounce decision (NAV-R12-B behavior).
      final snapDistance = progress.snapDistanceM;
      final offRouteThreshold = math.max(
        70.0,
        _snapThresholdFor(sample.accuracyM) + 25.0,
      );
      if (progress.offRouteLikely) {
        offRouteHitCount += 1;
      } else if (progress.hasReliableSnap) {
        offRouteHitCount = 0;
      } else if (snapDistance > offRouteThreshold) {
        offRouteHitCount += 1;
      } else {
        offRouteHitCount = 0;
      }
      final oppositeDirection = progress.oppositeDirectionLikely;
      final strongOppositeDirection =
          progress.routeDeviationReason == 'opposite_heading_strong';
      final backwardProgress = progress.backwardProgressLikely;
      final routeDeviation = progress.routeDeviationLikely;
      final int hitsRequired;
      if (strongOppositeDirection) {
        hitsRequired = 1;
      } else if (routeDeviation) {
        hitsRequired = 2;
      } else if (progress.offRouteLikely || snapDistance > 55.0) {
        hitsRequired = 2;
      } else {
        hitsRequired = 3;
      }
      final offRoute = offRouteHitCount >= hitsRequired;
      if (offRoute) {
        offRouteReason = oppositeDirection
            ? (strongOppositeDirection
                  ? 'opposite_direction_strong'
                  : 'opposite_direction')
            : (backwardProgress ? 'backward_progress' : 'snap_distance');
      } else {
        offRouteReason = 'none';
      }
      if (offRoute != offRouteLikelyState) {
        offRouteLikelyState = offRoute;
        if (!offRoute) debounceStartedAt = null;
      }

      // Reroute eligibility mirror (cooldown; no follow-mode gate anymore).
      final cooldown = offRouteReason == 'snap_distance' || !offRoute
          ? rerouteCooldown
          : rerouteCooldownRouteDeviation;
      final cooldownOk =
          lastRerouteAt == null ||
          sample.timestamp.difference(lastRerouteAt) >= cooldown;
      final rerouteEligible = offRoute && cooldownOk;

      var rerouteWouldTrigger = false;
      if (rerouteEligible) {
        final debounceStart = debounceStartedAt ?? sample.timestamp;
        debounceStartedAt = debounceStart;
        final debounce = offRouteReason == 'opposite_direction_strong'
            ? debounceStrong
            : (offRouteReason == 'opposite_direction' ||
                      offRouteReason == 'backward_progress'
                  ? debounceRouteDeviation
                  : debounceDefault);
        if (sample.timestamp.difference(debounceStart) >= debounce) {
          rerouteWouldTrigger = true;
          lastRerouteAt = sample.timestamp;
          debounceStartedAt = null;
        }
      } else if (!offRoute) {
        debounceStartedAt = null;
      }

      // Bearing policy on production module.
      final routeBearing = _segmentBearingFor(progress.segmentIndex);
      final policy = NavBearingPolicy.resolve(
        NavBearingPolicyInput(
          rawHeading: sample.headingDeg,
          routeBearing: routeBearing,
          movementBearing: movementBearing,
          lastBearing: lastBearing,
          speedKmh: sample.speedKmh,
          accuracyM: sample.accuracyM,
          routeConfidence: progress.confidence,
          hasReliableSnap: progress.hasReliableSnap,
          offRouteLikely: offRoute || progress.offRouteLikely,
          trustBearing: confidence.trustBearing,
          trustRouteSnap: confidence.trustRouteSnap,
          routeDeviationLikely: progress.routeDeviationLikely,
          oppositeDirectionLikely: progress.oppositeDirectionLikely,
          backwardProgressLikely: progress.backwardProgressLikely,
          headingDeltaDeg: progress.headingDeltaDeg,
          forwardProgress: progress.forwardProgress,
        ),
      );
      final displayBearing = NavBearingPolicy.stepToward(
        previous: lastBearing,
        target: policy.targetBearing,
        maxStepDeg: policy.maxStepDeg,
      );
      lastBearing = displayBearing;

      // Prediction on a fresh fix: gap 0 → must stay inactive.
      final prediction = _motionPrediction.update(
        NavMotionPredictionInput(
          timestamp: sample.timestamp,
          lastDisplayLatitude: sample.latitude,
          lastDisplayLongitude: sample.longitude,
          bearing: displayBearing,
          speedKmh: sample.speedKmh,
          routeBearing: routeBearing,
          trustRouteSnap: confidence.trustRouteSnap,
          trustBearing: confidence.trustBearing,
          offRouteLikely: offRoute || progress.offRouteLikely,
          gpsAccuracyM: sample.accuracyM,
          liveRideActive: true,
          gapSinceLastEngineMs: 0,
          weakGps: false,
        ),
      );
      _motionPrediction.noteEngineUpdate(
        timestamp: sample.timestamp,
        displayLatitude: sample.latitude,
        displayLongitude: sample.longitude,
        bearing: displayBearing,
        trustRouteSnap: confidence.trustRouteSnap,
      );

      // Instruction/banner policy on production module.
      final instruction = _instructionPolicy.update(
        NavInstructionPolicyInput(
          timestamp: sample.timestamp,
          liveRideActive: true,
          rawInstructionText: instructionContext.rawInstructionText,
          maneuverType: instructionContext.maneuverType,
          maneuverModifier: instructionContext.maneuverModifier,
          distanceToManeuverM: instructionContext.distanceToManeuverM,
          routeConfidence: progress.confidence,
          instructionConfidenceScore: confidence.instructionScore,
          trustInstruction: confidence.trustInstruction,
          trustRouteSnap: confidence.trustRouteSnap,
          offRouteLikely: offRoute || progress.offRouteLikely,
          forwardProgress: progress.forwardProgress,
          predictionActive: prediction.predictionActive,
          speedKmh: sample.speedKmh,
        ),
      );

      results.add(
        NavReplaySampleResult(
          index: i,
          timestamp: sample.timestamp,
          speedKmh: sample.speedKmh,
          snapDistanceM: progress.snapDistanceM,
          offRouteLikely: offRoute,
          offRouteReason: offRouteReason,
          routeDeviationLikely: progress.routeDeviationLikely,
          oppositeDirectionLikely: progress.oppositeDirectionLikely,
          routeDeviationReason: progress.routeDeviationReason,
          backwardProgressLikely: progress.backwardProgressLikely,
          headingDeltaDeg: progress.headingDeltaDeg,
          bearingSource: policy.source,
          bearingReason: policy.reason,
          displayBearing: displayBearing,
          routeBearingAllowed: policy.routeBearingAllowed,
          trustSnap: confidence.trustRouteSnap,
          trustBearing: confidence.trustBearing,
          instructionReason: instruction.reason,
          instructionText: instruction.displayInstructionText,
          showOriginalInstruction: instruction.showOriginalInstruction,
          predictionActive: prediction.predictionActive,
          predictionReason: prediction.reason,
          rerouteEligible: rerouteEligible,
          rerouteWouldTrigger: rerouteWouldTrigger,
          progressReason: progress.reason,
        ),
      );

      previousSample = sample;
    }

    return NavReplayReport(fixtureName: fixtureName, results: results);
  }

  double? _segmentBearingFor(int? segmentIndex) {
    if (segmentIndex == null ||
        segmentIndex < 0 ||
        segmentIndex >= routePoints.length - 1) {
      return null;
    }
    final a = routePoints[segmentIndex];
    final b = routePoints[segmentIndex + 1];
    return _bearingFromPoints(a.latitude, a.longitude, b.latitude, b.longitude);
  }

  static double _snapThresholdFor(double? accuracyM) {
    final accuracy = accuracyM != null && accuracyM.isFinite && accuracyM > 0
        ? accuracyM
        : 20.0;
    return math.max(35.0, math.min(90.0, accuracy * 1.8));
  }

  static double _haversineMeters(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const earthRadiusM = 6371000.0;
    final phi1 = lat1 * math.pi / 180.0;
    final phi2 = lat2 * math.pi / 180.0;
    final dPhi = (lat2 - lat1) * math.pi / 180.0;
    final dLambda = (lon2 - lon1) * math.pi / 180.0;
    final a =
        math.sin(dPhi / 2) * math.sin(dPhi / 2) +
        math.cos(phi1) *
            math.cos(phi2) *
            math.sin(dLambda / 2) *
            math.sin(dLambda / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadiusM * c;
  }

  static double _bearingFromPoints(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const degToRad = math.pi / 180.0;
    const radToDeg = 180.0 / math.pi;
    final dLon = (lon2 - lon1) * degToRad;
    final y = math.sin(dLon) * math.cos(lat2 * degToRad);
    final x =
        math.cos(lat1 * degToRad) * math.sin(lat2 * degToRad) -
        math.sin(lat1 * degToRad) * math.cos(lat2 * degToRad) * math.cos(dLon);
    final brng = math.atan2(y, x) * radToDeg;
    return (brng + 360.0) % 360.0;
  }
}
