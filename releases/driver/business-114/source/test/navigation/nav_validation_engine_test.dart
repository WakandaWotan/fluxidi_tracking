import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/navigation/nav_engine/nav_validation_engine.dart';

NavValidationSample _sample({
  required DateTime timestamp,
  double gpsAccuracyM = 6.0,
  double routeConfidence = 92.0,
  double snapDistanceM = 6.0,
  double overallConfidence = 90.0,
  double cameraScore = 90.0,
  bool predictionActive = false,
  bool offRouteLikely = false,
  bool cameraFollowed = true,
  String? cameraSkippedReason,
}) {
  return NavValidationSample(
    timestamp: timestamp,
    gpsAccuracyM: gpsAccuracyM,
    routeConfidence: routeConfidence,
    snapDistanceM: snapDistanceM,
    overallConfidence: overallConfidence,
    cameraScore: cameraScore,
    predictionActive: predictionActive,
    offRouteLikely: offRouteLikely,
    cameraFollowed: cameraFollowed,
    cameraSkippedReason: cameraSkippedReason,
  );
}

/// Adds [count] healthy samples at 1 s cadence starting at [start].
void _addHealthySession(
  DriverNavValidationEngine engine, {
  required DateTime start,
  required int count,
}) {
  for (var i = 0; i < count; i++) {
    engine.addSample(_sample(timestamp: start.add(Duration(seconds: i))));
    if (i > 0) engine.noteCallbackIntervalMs(1000);
  }
}

void main() {
  final t0 = DateTime.utc(2026, 1, 1, 12, 0, 0);

  group('NAV-R10 corrected scoring (Part G)', () {
    test(
      'field regression: 2 samples + 22 s marker lag is never excellent',
      () {
        final engine = DriverNavValidationEngine();
        engine.addSample(_sample(timestamp: t0));
        engine.addSample(
          _sample(timestamp: t0.add(const Duration(seconds: 22))),
        );
        engine.noteCallbackIntervalMs(22251);
        engine.noteMarkerLagMs(22251);
        engine.noteSourceAgeMs(22251);

        final report = engine.buildReport();

        expect(report.summaryLabel, isNot(NavValidationSummaryLabel.excellent));
        expect(report.summaryLabel, NavValidationSummaryLabel.fail);
        expect(report.maxMarkerLagMs, 22251);
        expect(report.summaryLabel.logLabel, 'fail');
      },
    );

    test('20 s+ source age alone forces fail', () {
      final engine = DriverNavValidationEngine();
      _addHealthySession(engine, start: t0, count: 8);
      engine.noteSourceAgeMs(21000);

      expect(engine.buildReport().summaryLabel, NavValidationSummaryLabel.fail);
    });

    test('20 s+ p95 callback interval forces fail', () {
      final engine = DriverNavValidationEngine();
      _addHealthySession(engine, start: t0, count: 8);
      engine.noteCallbackIntervalMs(25000);

      expect(engine.buildReport().summaryLabel, NavValidationSummaryLabel.fail);
    });

    test('too few samples => insufficient_data, never excellent', () {
      final engine = DriverNavValidationEngine();
      engine.addSample(_sample(timestamp: t0));
      engine.addSample(_sample(timestamp: t0.add(const Duration(seconds: 1))));
      engine.noteCallbackIntervalMs(1000);

      final report = engine.buildReport();
      expect(report.summaryLabel, NavValidationSummaryLabel.insufficientData);
      expect(report.summaryLabel.logLabel, 'insufficient_data');
    });

    test('single sample => insufficient_data', () {
      final engine = DriverNavValidationEngine();
      engine.addSample(_sample(timestamp: t0));
      expect(
        engine.buildReport().summaryLabel,
        NavValidationSummaryLabel.insufficientData,
      );
    });

    test('empty session => insufficient_data', () {
      final engine = DriverNavValidationEngine();
      expect(
        engine.buildReport().summaryLabel,
        NavValidationSummaryLabel.insufficientData,
      );
    });

    test('healthy sustained session can reach excellent', () {
      final engine = DriverNavValidationEngine();
      _addHealthySession(engine, start: t0, count: 15);

      final report = engine.buildReport();
      expect(report.summaryLabel, NavValidationSummaryLabel.excellent);
      expect(report.maxMarkerLagMs, 0);
    });

    test('degraded (6-20 s) cadence caps the label at poor', () {
      final engine = DriverNavValidationEngine();
      _addHealthySession(engine, start: t0, count: 15);
      engine.noteMarkerLagMs(9000);

      final report = engine.buildReport();
      expect(report.summaryLabel, NavValidationSummaryLabel.poor);
    });
  });

  group('NAV-R10 reroute observation (Part G)', () {
    test('no reroute in session => reroute_not_observed (not a pass)', () {
      final engine = DriverNavValidationEngine();
      _addHealthySession(engine, start: t0, count: 10);

      final report = engine.buildReport();
      expect(report.rerouteObservation, NavRerouteObservation.notObserved);
      expect(report.rerouteObservation.logLabel, 'reroute_not_observed');
      expect(report.rerouteObservedCount, 0);
    });

    test('observed successful reroute => reroute_pass', () {
      final engine = DriverNavValidationEngine();
      _addHealthySession(engine, start: t0, count: 10);
      engine.noteRerouteObserved(success: true);

      final report = engine.buildReport();
      expect(report.rerouteObservation, NavRerouteObservation.pass);
      expect(report.rerouteObservedCount, 1);
    });

    test('observed failed reroute => reroute_fail', () {
      final engine = DriverNavValidationEngine();
      _addHealthySession(engine, start: t0, count: 10);
      engine.noteRerouteObserved(success: true);
      engine.noteRerouteObserved(success: false);

      expect(
        engine.buildReport().rerouteObservation,
        NavRerouteObservation.fail,
      );
    });
  });

  group('NAV-R10 cadence percentiles + reset', () {
    test('median/p95 callback intervals are surfaced', () {
      final engine = DriverNavValidationEngine();
      _addHealthySession(engine, start: t0, count: 6);
      for (final dt in <int>[900, 1000, 1100, 1200, 4000]) {
        engine.noteCallbackIntervalMs(dt);
      }

      final report = engine.buildReport();
      expect(
        report.p95CallbackIntervalMs,
        greaterThanOrEqualTo(report.medianCallbackIntervalMs),
      );
      expect(report.p95CallbackIntervalMs, lessThan(20000));
    });

    test('reset clears cadence/lag accumulators', () {
      final engine = DriverNavValidationEngine();
      engine.addSample(_sample(timestamp: t0));
      engine.noteMarkerLagMs(22000);
      engine.notePredictionGapExceeded(3261);
      engine.noteCameraStaleTargetDrops(31);
      engine.reset();

      _addHealthySession(engine, start: t0, count: 12);
      final report = engine.buildReport();
      expect(report.maxMarkerLagMs, 0);
      expect(report.predictionGapExceededCount, 0);
      expect(report.cameraStaleTargetDrops, 0);
      expect(report.summaryLabel, NavValidationSummaryLabel.excellent);
    });
  });
}
