import 'dart:math' as math;

import 'nav_engine_input.dart';
import 'nav_engine_output.dart';
import 'nav_position_sample.dart';

/// Resolves display position and jump/animate flags from GPS/snap samples.
class NavMotionSmoother {
  NavPositionSample? _previousTarget;

  void reset() {
    _previousTarget = null;
  }

  static double _haversineMeters({
    required double lat1,
    required double lon1,
    required double lat2,
    required double lon2,
  }) {
    const earthRadiusM = 6371000.0;
    final phi1 = lat1 * math.pi / 180.0;
    final phi2 = lat2 * math.pi / 180.0;
    final dPhi = (lat2 - lat1) * math.pi / 180.0;
    final dLambda = (lon2 - lon1) * math.pi / 180.0;
    final a = math.sin(dPhi / 2) * math.sin(dPhi / 2) +
        math.cos(phi1) *
            math.cos(phi2) *
            math.sin(dLambda / 2) *
            math.sin(dLambda / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadiusM * c;
  }

  static double _maxPlausibleJumpM({
    required double dtSec,
    required double? speedKmh,
    required double? accuracyM,
  }) {
    final speed = math.max(0.0, speedKmh ?? 0.0);
    final speedMps = speed / 3.6;
    final accuracy = math.max(12.0, accuracyM ?? 20.0);
    final timeBudget = dtSec.isFinite && dtSec > 0 ? dtSec : 1.0;
    // Allow some GPS noise plus movement since last sample.
    return math.max(accuracy * 2.8, speedMps * timeBudget + accuracy * 1.6);
  }

  ({
    double latitude,
    double longitude,
    String markerSource,
    bool shouldAnimateMarker,
  })
  resolve({
    required NavEngineInput input,
    required NavEngineOutput? previousOutput,
  }) {
    double latitude;
    double longitude;
    String markerSource;

    if (input.hasReliableSnap &&
        input.snappedLatitude != null &&
        input.snappedLongitude != null) {
      latitude = input.snappedLatitude!;
      longitude = input.snappedLongitude!;
      markerSource = 'route_snap';
    } else if (input.rawLatitude.isFinite && input.rawLongitude.isFinite) {
      latitude = input.rawLatitude;
      longitude = input.rawLongitude;
      markerSource = 'raw';
    } else if (previousOutput != null) {
      latitude = previousOutput.displayLatitude;
      longitude = previousOutput.displayLongitude;
      markerSource = 'fallback';
    } else {
      latitude = input.rawLatitude;
      longitude = input.rawLongitude;
      markerSource = 'fallback';
    }

    final previous = previousOutput == null
        ? _previousTarget
        : NavPositionSample(
            latitude: previousOutput.displayLatitude,
            longitude: previousOutput.displayLongitude,
            timestamp: previousOutput.timestamp,
          );

    if (previous == null) {
      _previousTarget = NavPositionSample(
        latitude: latitude,
        longitude: longitude,
        timestamp: input.timestamp,
      );
      return (
        latitude: latitude,
        longitude: longitude,
        markerSource: markerSource,
        shouldAnimateMarker: true,
      );
    }

    final dtSec =
        input.timestamp.difference(previous.timestamp).inMilliseconds / 1000.0;
    final jumpM = _haversineMeters(
      lat1: previous.latitude,
      lon1: previous.longitude,
      lat2: latitude,
      lon2: longitude,
    );
    final maxJumpM = _maxPlausibleJumpM(
      dtSec: dtSec,
      speedKmh: input.speedKmh,
      accuracyM: input.accuracyM,
    );

    _previousTarget = NavPositionSample(
      latitude: latitude,
      longitude: longitude,
      timestamp: input.timestamp,
    );

    if (jumpM > maxJumpM) {
      // Bad GPS spike: snap visually without implying smooth motion.
      return (
        latitude: latitude,
        longitude: longitude,
        markerSource: markerSource,
        shouldAnimateMarker: false,
      );
    }

    return (
      latitude: latitude,
      longitude: longitude,
      markerSource: markerSource,
      shouldAnimateMarker: true,
    );
  }
}
