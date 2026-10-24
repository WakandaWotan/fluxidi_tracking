import 'dart:math' as math;

/// Signals for dead-reckoning during GPS gaps.
class NavMotionPredictionInput {
  final DateTime timestamp;
  final double lastDisplayLatitude;
  final double lastDisplayLongitude;
  final double? lastReliableLatitude;
  final double? lastReliableLongitude;
  final double bearing;
  final double? speedKmh;
  final double? routeBearing;
  final bool trustRouteSnap;
  final bool trustBearing;
  final bool offRouteLikely;
  final double? gpsAccuracyM;
  final bool liveRideActive;
  final int gapSinceLastEngineMs;
  final bool weakGps;

  const NavMotionPredictionInput({
    required this.timestamp,
    required this.lastDisplayLatitude,
    required this.lastDisplayLongitude,
    this.lastReliableLatitude,
    this.lastReliableLongitude,
    required this.bearing,
    this.speedKmh,
    this.routeBearing,
    this.trustRouteSnap = false,
    this.trustBearing = false,
    this.offRouteLikely = false,
    this.gpsAccuracyM,
    this.liveRideActive = false,
    this.gapSinceLastEngineMs = 0,
    this.weakGps = false,
  });
}

/// Dead-reckoned position during controlled GPS gaps.
class NavMotionPredictionOutput {
  final double predictedLatitude;
  final double predictedLongitude;
  final double predictedBearing;
  final bool predictionActive;
  final int maxPredictionMs;
  final double confidence;
  final String reason;

  const NavMotionPredictionOutput({
    required this.predictedLatitude,
    required this.predictedLongitude,
    required this.predictedBearing,
    required this.predictionActive,
    required this.maxPredictionMs,
    required this.confidence,
    required this.reason,
  });
}

/// Deterministic local motion prediction for GPS gaps and tunnels.
class DriverNavMotionPrediction {
  static const int _normalMaxPredictionMs = 2500;
  static const int _tunnelMaxPredictionMs = 6000;
  static const int _minGapMs = 300;

  DateTime? _lastEngineTimestamp;
  bool _hadReliableSnapBeforeGap = false;
  double? _anchorLatitude;
  double? _anchorLongitude;
  double? _anchorBearing;
  DateTime? _predictionStartedAt;

  void reset() {
    _lastEngineTimestamp = null;
    _hadReliableSnapBeforeGap = false;
    _anchorLatitude = null;
    _anchorLongitude = null;
    _anchorBearing = null;
    _predictionStartedAt = null;
  }

  void noteEngineUpdate({
    required DateTime timestamp,
    required double displayLatitude,
    required double displayLongitude,
    required double bearing,
    required bool trustRouteSnap,
  }) {
    _lastEngineTimestamp = timestamp;
    _hadReliableSnapBeforeGap = trustRouteSnap;
    _anchorLatitude = displayLatitude;
    _anchorLongitude = displayLongitude;
    _anchorBearing = bearing;
    _predictionStartedAt = null;
  }

  NavMotionPredictionOutput update(NavMotionPredictionInput input) {
    final hold = NavMotionPredictionOutput(
      predictedLatitude: input.lastDisplayLatitude,
      predictedLongitude: input.lastDisplayLongitude,
      predictedBearing: input.bearing,
      predictionActive: false,
      maxPredictionMs: _normalMaxPredictionMs,
      confidence: 0,
      reason: 'inactive',
    );

    if (!input.liveRideActive) {
      reset();
      return hold;
    }
    if (input.offRouteLikely) {
      _predictionStartedAt = null;
      return hold.copyWith(reason: 'off_route');
    }
    if (!input.trustBearing && !input.trustRouteSnap) {
      _predictionStartedAt = null;
      return hold.copyWith(reason: 'low_trust');
    }

    final gapMs = math.max(0, input.gapSinceLastEngineMs);
    if (gapMs < _minGapMs) {
      _predictionStartedAt = null;
      return hold.copyWith(reason: 'fresh_engine');
    }

    final tunnelMode =
        input.weakGps && _hadReliableSnapBeforeGap && input.trustRouteSnap;
    final maxPredictionMs =
        tunnelMode ? _tunnelMaxPredictionMs : _normalMaxPredictionMs;

    if (gapMs > maxPredictionMs) {
      _predictionStartedAt = null;
      return hold.copyWith(
        maxPredictionMs: maxPredictionMs,
        reason: 'gap_exceeded',
      );
    }

    final speedKmh = math.max(0.0, input.speedKmh ?? 0.0);
    if (speedKmh < 3.0) {
      return NavMotionPredictionOutput(
        predictedLatitude: input.lastDisplayLatitude,
        predictedLongitude: input.lastDisplayLongitude,
        predictedBearing: input.bearing,
        predictionActive: true,
        maxPredictionMs: maxPredictionMs,
        confidence: _confidenceFor(
          gapMs: gapMs,
          maxPredictionMs: maxPredictionMs,
          speedKmh: speedKmh,
          trustRouteSnap: input.trustRouteSnap,
          weakGps: input.weakGps,
        ),
        reason: tunnelMode ? 'tunnel_hold' : 'low_speed_hold',
      );
    }

    _predictionStartedAt ??= input.timestamp;

    final anchorLat = _anchorLatitude ?? input.lastDisplayLatitude;
    final anchorLon = _anchorLongitude ?? input.lastDisplayLongitude;
    final travelBearing = input.trustRouteSnap &&
            input.routeBearing != null &&
            input.routeBearing!.isFinite
        ? input.routeBearing!
        : input.bearing;

    final gapSec = gapMs / 1000.0;
    final speedMps = speedKmh / 3.6;
    var distanceM = speedMps * gapSec;

    final maxStepM = _maxPlausibleDistanceM(
      speedKmh: speedKmh,
      gapMs: gapMs,
      maxPredictionMs: maxPredictionMs,
      accuracyM: input.gpsAccuracyM,
    );
    distanceM = distanceM.clamp(0.0, maxStepM);

    final predicted = _offsetMeters(
      latitude: anchorLat,
      longitude: anchorLon,
      bearingDeg: travelBearing,
      distanceM: distanceM,
    );

    var predictedLat = predicted.latitude;
    var predictedLon = predicted.longitude;

    final reliableLat = input.lastReliableLatitude;
    final reliableLon = input.lastReliableLongitude;
    if (reliableLat != null &&
        reliableLon != null &&
        reliableLat.isFinite &&
        reliableLon.isFinite) {
      final driftM = _haversineMeters(
        reliableLat,
        reliableLon,
        predictedLat,
        predictedLon,
      );
      final maxDriftM = maxStepM + 12.0;
      if (driftM > maxDriftM && driftM > 0.01) {
        final scale = maxDriftM / driftM;
        predictedLat =
            reliableLat + (predictedLat - reliableLat) * scale;
        predictedLon =
            reliableLon + (predictedLon - reliableLon) * scale;
      }
    }

    final confidence = _confidenceFor(
      gapMs: gapMs,
      maxPredictionMs: maxPredictionMs,
      speedKmh: speedKmh,
      trustRouteSnap: input.trustRouteSnap,
      weakGps: input.weakGps,
    );

    return NavMotionPredictionOutput(
      predictedLatitude: predictedLat,
      predictedLongitude: predictedLon,
      predictedBearing: travelBearing,
      predictionActive: true,
      maxPredictionMs: maxPredictionMs,
      confidence: confidence,
      reason: tunnelMode ? 'tunnel_predict' : 'gap_predict',
    );
  }

  static double _confidenceFor({
    required int gapMs,
    required int maxPredictionMs,
    required double speedKmh,
    required bool trustRouteSnap,
    required bool weakGps,
  }) {
    final gapT = (gapMs / maxPredictionMs).clamp(0.0, 1.0);
    var score = (100.0 * (1.0 - gapT * 0.55)).clamp(35.0, 95.0);
    if (trustRouteSnap) score = math.min(100.0, score + 8.0);
    if (weakGps && trustRouteSnap) score = math.min(100.0, score + 5.0);
    if (speedKmh < 8.0) score -= 8.0;
    return score.clamp(0.0, 100.0);
  }

  static double _maxPlausibleDistanceM({
    required double speedKmh,
    required int gapMs,
    required int maxPredictionMs,
    required double? accuracyM,
  }) {
    final speedMps = math.max(0.0, speedKmh) / 3.6;
    final gapSec = gapMs / 1000.0;
    final accuracy = math.max(12.0, accuracyM ?? 20.0);
    final timeBudget = math.min(gapSec, maxPredictionMs / 1000.0);
    return math.min(
      speedMps * timeBudget * 1.15 + accuracy * 0.5,
      speedMps * (maxPredictionMs / 1000.0) * 1.2 + 25.0,
    );
  }

  static ({double latitude, double longitude}) _offsetMeters({
    required double latitude,
    required double longitude,
    required double bearingDeg,
    required double distanceM,
  }) {
    if (distanceM <= 0.01) {
      return (latitude: latitude, longitude: longitude);
    }
    const earthRadiusM = 6371000.0;
    final brng = bearingDeg * math.pi / 180.0;
    final lat1 = latitude * math.pi / 180.0;
    final lon1 = longitude * math.pi / 180.0;
    final lat2 = math.asin(
      math.sin(lat1) * math.cos(distanceM / earthRadiusM) +
          math.cos(lat1) *
              math.sin(distanceM / earthRadiusM) *
              math.cos(brng),
    );
    final lon2 = lon1 +
        math.atan2(
          math.sin(brng) *
              math.sin(distanceM / earthRadiusM) *
              math.cos(lat1),
          math.cos(distanceM / earthRadiusM) -
              math.sin(lat1) * math.sin(lat2),
        );
    return (
      latitude: lat2 * 180.0 / math.pi,
      longitude: lon2 * 180.0 / math.pi,
    );
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
    final a = math.sin(dPhi / 2) * math.sin(dPhi / 2) +
        math.cos(phi1) *
            math.cos(phi2) *
            math.sin(dLambda / 2) *
            math.sin(dLambda / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadiusM * c;
  }
}

extension _NavMotionPredictionOutputCopy on NavMotionPredictionOutput {
  NavMotionPredictionOutput copyWith({
    String? reason,
    int? maxPredictionMs,
  }) {
    return NavMotionPredictionOutput(
      predictedLatitude: predictedLatitude,
      predictedLongitude: predictedLongitude,
      predictedBearing: predictedBearing,
      predictionActive: predictionActive,
      maxPredictionMs: maxPredictionMs ?? this.maxPredictionMs,
      confidence: confidence,
      reason: reason ?? this.reason,
    );
  }
}
