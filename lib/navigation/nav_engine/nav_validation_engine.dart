/// NAV-R10: local Driver OS navigation quality validation for test rides.
class NavValidationSample {
  final DateTime timestamp;
  final double? gpsAccuracyM;
  final double? speedKmh;
  final double? routeConfidence;
  final double? snapDistanceM;
  final double? overallConfidence;
  final double? cameraScore;
  final double? instructionScore;
  final bool predictionActive;
  final bool offRouteLikely;
  final bool markerAnimated;
  final bool cameraFollowed;
  final String? cameraSkippedReason;

  const NavValidationSample({
    required this.timestamp,
    this.gpsAccuracyM,
    this.speedKmh,
    this.routeConfidence,
    this.snapDistanceM,
    this.overallConfidence,
    this.cameraScore,
    this.instructionScore,
    this.predictionActive = false,
    this.offRouteLikely = false,
    this.markerAnimated = false,
    this.cameraFollowed = false,
    this.cameraSkippedReason,
  });
}

enum NavValidationSummaryLabel {
  excellent,
  good,
  needsAttention,
  poor,
}

extension NavValidationSummaryLabelX on NavValidationSummaryLabel {
  String get logLabel {
    switch (this) {
      case NavValidationSummaryLabel.excellent:
        return 'excellent';
      case NavValidationSummaryLabel.good:
        return 'good';
      case NavValidationSummaryLabel.needsAttention:
        return 'needs_attention';
      case NavValidationSummaryLabel.poor:
        return 'poor';
    }
  }
}

class NavValidationReport {
  final int durationSec;
  final int sampleCount;
  final double avgGpsScore;
  final double avgRouteConfidence;
  final double avgOverallConfidence;
  final double avgSnapDistanceM;
  final int predictionEvents;
  final int offRouteEvents;
  final int cameraSkipEvents;
  final int lowConfidenceEvents;
  final double overallDriverOsScore;
  final NavValidationSummaryLabel summaryLabel;

  const NavValidationReport({
    required this.durationSec,
    required this.sampleCount,
    required this.avgGpsScore,
    required this.avgRouteConfidence,
    required this.avgOverallConfidence,
    required this.avgSnapDistanceM,
    required this.predictionEvents,
    required this.offRouteEvents,
    required this.cameraSkipEvents,
    required this.lowConfidenceEvents,
    required this.overallDriverOsScore,
    required this.summaryLabel,
  });

  static const NavValidationReport empty = NavValidationReport(
    durationSec: 0,
    sampleCount: 0,
    avgGpsScore: 0,
    avgRouteConfidence: 0,
    avgOverallConfidence: 0,
    avgSnapDistanceM: 0,
    predictionEvents: 0,
    offRouteEvents: 0,
    cameraSkipEvents: 0,
    lowConfidenceEvents: 0,
    overallDriverOsScore: 0,
    summaryLabel: NavValidationSummaryLabel.poor,
  );
}

/// Aggregates bounded navigation quality samples into a deterministic report.
class DriverNavValidationEngine {
  static const double _lowConfidenceThreshold = 45.0;

  final List<NavValidationSample> _samples = <NavValidationSample>[];

  void addSample(NavValidationSample sample) {
    _samples.add(sample);
  }

  void reset() {
    _samples.clear();
  }

  NavValidationReport buildReport() {
    if (_samples.isEmpty) return NavValidationReport.empty;

    final first = _samples.first.timestamp;
    final last = _samples.last.timestamp;
    final durationSec = last.isAfter(first)
        ? last.difference(first).inSeconds
        : 0;

    var gpsTotal = 0.0;
    var gpsCount = 0;
    var routeTotal = 0.0;
    var routeCount = 0;
    var overallTotal = 0.0;
    var overallCount = 0;
    var cameraScoreTotal = 0.0;
    var cameraScoreCount = 0;
    var snapTotal = 0.0;
    var snapCount = 0;

    var predictionEvents = 0;
    var offRouteEvents = 0;
    var cameraSkipEvents = 0;
    var lowConfidenceEvents = 0;

    for (final sample in _samples) {
      final gpsScore = _gpsScoreFromAccuracy(sample.gpsAccuracyM);
      gpsTotal += gpsScore;
      gpsCount += 1;

      if (sample.routeConfidence != null) {
        routeTotal += sample.routeConfidence!.clamp(0.0, 100.0);
        routeCount += 1;
      }
      if (sample.overallConfidence != null) {
        final overall = sample.overallConfidence!.clamp(0.0, 100.0);
        overallTotal += overall;
        overallCount += 1;
        if (overall < _lowConfidenceThreshold) {
          lowConfidenceEvents += 1;
        }
      }
      if (sample.cameraScore != null) {
        cameraScoreTotal += sample.cameraScore!.clamp(0.0, 100.0);
        cameraScoreCount += 1;
      }
      if (sample.snapDistanceM != null && sample.snapDistanceM!.isFinite) {
        snapTotal += sample.snapDistanceM!.clamp(0.0, 500.0);
        snapCount += 1;
      }

      if (sample.predictionActive) predictionEvents += 1;
      if (sample.offRouteLikely) offRouteEvents += 1;
      if (!sample.cameraFollowed &&
          (sample.cameraSkippedReason ?? '').trim().isNotEmpty) {
        cameraSkipEvents += 1;
      }
    }

    final avgGpsScore = gpsCount == 0 ? 0.0 : gpsTotal / gpsCount;
    final avgRouteConfidence =
        routeCount == 0 ? 0.0 : routeTotal / routeCount;
    final avgOverallConfidence =
        overallCount == 0 ? 0.0 : overallTotal / overallCount;
    final avgSnapDistanceM = snapCount == 0 ? 0.0 : snapTotal / snapCount;
    final avgCameraScore =
        cameraScoreCount == 0 ? avgOverallConfidence : cameraScoreTotal / cameraScoreCount;

    final overallDriverOsScore = _overallScoreFor(
      avgGpsScore: avgGpsScore,
      avgRouteConfidence: avgRouteConfidence,
      avgOverallConfidence: avgOverallConfidence,
      avgCameraScore: avgCameraScore,
      avgSnapDistanceM: avgSnapDistanceM,
      predictionEvents: predictionEvents,
      offRouteEvents: offRouteEvents,
      cameraSkipEvents: cameraSkipEvents,
      lowConfidenceEvents: lowConfidenceEvents,
      sampleCount: _samples.length,
    );

    return NavValidationReport(
      durationSec: durationSec,
      sampleCount: _samples.length,
      avgGpsScore: _round1(avgGpsScore),
      avgRouteConfidence: _round1(avgRouteConfidence),
      avgOverallConfidence: _round1(avgOverallConfidence),
      avgSnapDistanceM: _round1(avgSnapDistanceM),
      predictionEvents: predictionEvents,
      offRouteEvents: offRouteEvents,
      cameraSkipEvents: cameraSkipEvents,
      lowConfidenceEvents: lowConfidenceEvents,
      overallDriverOsScore: _round1(overallDriverOsScore),
      summaryLabel: _labelForScore(overallDriverOsScore),
    );
  }

  static double _gpsScoreFromAccuracy(double? accuracyM) {
    if (accuracyM == null || !accuracyM.isFinite || accuracyM <= 0) {
      return 50.0;
    }
    if (accuracyM <= 8) return 100.0;
    if (accuracyM <= 15) return 85.0;
    if (accuracyM <= 25) return 70.0;
    if (accuracyM <= 40) return 55.0;
    if (accuracyM <= 60) return 40.0;
    return 25.0;
  }

  static double _overallScoreFor({
    required double avgGpsScore,
    required double avgRouteConfidence,
    required double avgOverallConfidence,
    required double avgCameraScore,
    required double avgSnapDistanceM,
    required int predictionEvents,
    required int offRouteEvents,
    required int cameraSkipEvents,
    required int lowConfidenceEvents,
    required int sampleCount,
  }) {
    var score = avgOverallConfidence * 0.40 +
        avgRouteConfidence * 0.25 +
        avgGpsScore * 0.20 +
        avgCameraScore * 0.15;

    if (avgSnapDistanceM > 35) {
      score -= 15;
    } else if (avgSnapDistanceM > 20) {
      score -= 8;
    } else if (avgSnapDistanceM > 12) {
      score -= 3;
    }

    if (sampleCount > 0) {
      final offRouteRate = offRouteEvents / sampleCount;
      final cameraSkipRate = cameraSkipEvents / sampleCount;
      final lowConfidenceRate = lowConfidenceEvents / sampleCount;
      score -= offRouteRate * 30;
      score -= cameraSkipRate * 18;
      score -= lowConfidenceRate * 20;
    }

    if (predictionEvents > 0 && avgOverallConfidence >= 60) {
      score += 2;
    } else if (predictionEvents > (sampleCount * 0.35)) {
      score -= 4;
    }

    if (avgOverallConfidence >= 75 &&
        avgSnapDistanceM < 15 &&
        offRouteEvents == 0) {
      score += 4;
    }

    return score.clamp(0.0, 100.0);
  }

  static NavValidationSummaryLabel _labelForScore(double score) {
    if (score >= 85) return NavValidationSummaryLabel.excellent;
    if (score >= 70) return NavValidationSummaryLabel.good;
    if (score >= 50) return NavValidationSummaryLabel.needsAttention;
    return NavValidationSummaryLabel.poor;
  }

  static double _round1(double value) =>
      (value * 10).roundToDouble() / 10.0;
}
