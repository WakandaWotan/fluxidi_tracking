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
  fail,
  insufficientData,
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
      case NavValidationSummaryLabel.fail:
        return 'fail';
      case NavValidationSummaryLabel.insufficientData:
        return 'insufficient_data';
    }
  }
}

/// NAV-R10: reroute observation verdict, kept separate from the overall label
/// so a healthy session without any reroute is never falsely reported as a
/// reroute pass.
enum NavRerouteObservation { notObserved, pass, fail }

extension NavRerouteObservationX on NavRerouteObservation {
  String get logLabel {
    switch (this) {
      case NavRerouteObservation.notObserved:
        return 'reroute_not_observed';
      case NavRerouteObservation.pass:
        return 'reroute_pass';
      case NavRerouteObservation.fail:
        return 'reroute_fail';
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

  /// NAV-R10 cadence / lag inputs (Part G). These are the metrics the old
  /// score-only scoring ignored, which allowed a 2-sample / 22 s-lag session to
  /// be labelled "excellent".
  final int medianCallbackIntervalMs;
  final int p95CallbackIntervalMs;
  final int maxSourceAgeMs;
  final int maxMarkerLagMs;
  final int predictionGapExceededCount;
  final int predictionGapExceededMs;
  final int cameraStaleTargetDrops;
  final int rerouteObservedCount;

  final double overallDriverOsScore;
  final NavValidationSummaryLabel summaryLabel;
  final NavRerouteObservation rerouteObservation;

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
    this.medianCallbackIntervalMs = 0,
    this.p95CallbackIntervalMs = 0,
    this.maxSourceAgeMs = 0,
    this.maxMarkerLagMs = 0,
    this.predictionGapExceededCount = 0,
    this.predictionGapExceededMs = 0,
    this.cameraStaleTargetDrops = 0,
    this.rerouteObservedCount = 0,
    required this.overallDriverOsScore,
    required this.summaryLabel,
    this.rerouteObservation = NavRerouteObservation.notObserved,
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
    summaryLabel: NavValidationSummaryLabel.insufficientData,
    rerouteObservation: NavRerouteObservation.notObserved,
  );
}

/// Aggregates bounded navigation quality samples into a deterministic report.
class DriverNavValidationEngine {
  static const double _lowConfidenceThreshold = 45.0;

  /// A confident quality label requires enough evidence. Fewer accepted
  /// samples or a too-short window can never be "excellent" — they are
  /// [NavValidationSummaryLabel.insufficientData].
  static const int _minSamplesForConfidentLabel = 5;
  static const int _minDurationSecForConfidentLabel = 8;

  /// Severe cadence / lag thresholds. A 20 s+ marker lag or source age, or a
  /// 20 s+ p95 GPS callback interval, is a hard navigation failure.
  static const int _severeLagMs = 20000;
  static const int _severeCallbackIntervalMs = 20000;

  /// Degraded (but not catastrophic) cadence caps the label at "poor".
  static const int _degradedCallbackIntervalMs = 6000;
  static const int _degradedLagMs = 6000;

  final List<NavValidationSample> _samples = <NavValidationSample>[];

  final List<int> _callbackIntervalsMs = <int>[];
  int _maxSourceAgeMs = 0;
  int _maxMarkerLagMs = 0;
  int _predictionGapExceededCount = 0;
  int _predictionGapExceededMs = 0;
  int _cameraStaleTargetDrops = 0;
  int _rerouteObservedCount = 0;
  int _rerouteFailCount = 0;

  void addSample(NavValidationSample sample) {
    _samples.add(sample);
  }

  /// GPS callback inter-arrival at the handler (bounded, non-PII).
  void noteCallbackIntervalMs(int dtMs) {
    if (dtMs <= 0) return;
    _callbackIntervalsMs.add(dtMs.clamp(0, 600000));
  }

  /// Age of the position fix that drove an accepted engine/camera update.
  void noteSourceAgeMs(int ageMs) {
    if (ageMs <= 0) return;
    final v = ageMs.clamp(0, 600000);
    if (v > _maxSourceAgeMs) _maxSourceAgeMs = v;
  }

  /// Wall-clock gap between successive marker applies.
  void noteMarkerLagMs(int lagMs) {
    if (lagMs <= 0) return;
    final v = lagMs.clamp(0, 600000);
    if (v > _maxMarkerLagMs) _maxMarkerLagMs = v;
  }

  /// Prediction disabled because the gap exceeded the defensible window.
  void notePredictionGapExceeded(int durationMs) {
    _predictionGapExceededCount += 1;
    final v = durationMs.clamp(0, 600000);
    if (v > _predictionGapExceededMs) _predictionGapExceededMs = v;
  }

  /// Latest camera stale-target drop total from the follow pump.
  void noteCameraStaleTargetDrops(int total) {
    if (total > _cameraStaleTargetDrops) _cameraStaleTargetDrops = total;
  }

  /// A reroute was actually observed in this session.
  void noteRerouteObserved({required bool success}) {
    _rerouteObservedCount += 1;
    if (!success) _rerouteFailCount += 1;
  }

  void reset() {
    _samples.clear();
    _callbackIntervalsMs.clear();
    _maxSourceAgeMs = 0;
    _maxMarkerLagMs = 0;
    _predictionGapExceededCount = 0;
    _predictionGapExceededMs = 0;
    _cameraStaleTargetDrops = 0;
    _rerouteObservedCount = 0;
    _rerouteFailCount = 0;
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
    final avgRouteConfidence = routeCount == 0 ? 0.0 : routeTotal / routeCount;
    final avgOverallConfidence = overallCount == 0
        ? 0.0
        : overallTotal / overallCount;
    final avgSnapDistanceM = snapCount == 0 ? 0.0 : snapTotal / snapCount;
    final avgCameraScore = cameraScoreCount == 0
        ? avgOverallConfidence
        : cameraScoreTotal / cameraScoreCount;

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

    final medianCallbackIntervalMs = _percentileMs(_callbackIntervalsMs, 0.50);
    final p95CallbackIntervalMs = _percentileMs(_callbackIntervalsMs, 0.95);

    final rerouteObservation = _rerouteObservedCount == 0
        ? NavRerouteObservation.notObserved
        : (_rerouteFailCount > 0
              ? NavRerouteObservation.fail
              : NavRerouteObservation.pass);

    final summaryLabel = _classifyLabel(
      score: overallDriverOsScore,
      sampleCount: _samples.length,
      durationSec: durationSec,
      maxMarkerLagMs: _maxMarkerLagMs,
      maxSourceAgeMs: _maxSourceAgeMs,
      p95CallbackIntervalMs: p95CallbackIntervalMs,
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
      medianCallbackIntervalMs: medianCallbackIntervalMs,
      p95CallbackIntervalMs: p95CallbackIntervalMs,
      maxSourceAgeMs: _maxSourceAgeMs,
      maxMarkerLagMs: _maxMarkerLagMs,
      predictionGapExceededCount: _predictionGapExceededCount,
      predictionGapExceededMs: _predictionGapExceededMs,
      cameraStaleTargetDrops: _cameraStaleTargetDrops,
      rerouteObservedCount: _rerouteObservedCount,
      overallDriverOsScore: _round1(overallDriverOsScore),
      summaryLabel: summaryLabel,
      rerouteObservation: rerouteObservation,
    );
  }

  static int _percentileMs(List<int> values, double p) {
    if (values.isEmpty) return 0;
    final sorted = List<int>.from(values)..sort();
    final idx = ((sorted.length - 1) * p).round().clamp(0, sorted.length - 1);
    return sorted[idx];
  }

  /// NAV-R10 corrected classification (Part G). Cadence and lag gate the label
  /// BEFORE any confidence-based score, so severe stalls or thin sessions can
  /// never be reported as "excellent".
  static NavValidationSummaryLabel _classifyLabel({
    required double score,
    required int sampleCount,
    required int durationSec,
    required int maxMarkerLagMs,
    required int maxSourceAgeMs,
    required int p95CallbackIntervalMs,
  }) {
    // A single sample carries no cadence evidence at all.
    if (sampleCount < 2) {
      return NavValidationSummaryLabel.insufficientData;
    }

    // Hard failure: multi-tens-of-seconds stall in any cadence dimension.
    final severeStall =
        maxMarkerLagMs >= _severeLagMs ||
        maxSourceAgeMs >= _severeLagMs ||
        p95CallbackIntervalMs >= _severeCallbackIntervalMs;
    if (severeStall) {
      return NavValidationSummaryLabel.fail;
    }

    // Not enough evidence for a confident verdict.
    if (sampleCount < _minSamplesForConfidentLabel ||
        durationSec < _minDurationSecForConfidentLabel) {
      return NavValidationSummaryLabel.insufficientData;
    }

    // Degraded cadence caps the label at "poor" regardless of confidence.
    final degradedCadence =
        maxMarkerLagMs >= _degradedLagMs ||
        maxSourceAgeMs >= _degradedLagMs ||
        p95CallbackIntervalMs >= _degradedCallbackIntervalMs;
    if (degradedCadence) {
      return NavValidationSummaryLabel.poor;
    }

    return _labelForScore(score);
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
    var score =
        avgOverallConfidence * 0.40 +
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

  static double _round1(double value) => (value * 10).roundToDouble() / 10.0;
}
