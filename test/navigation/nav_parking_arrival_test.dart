import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/navigation/nav_engine/nav_parking_arrival.dart';

NavParkingArrivalInput _input({
  int t = 0,
  double toOriginal = 20.0,
  double toEndpoint = 25.0,
  double remaining = 30.0,
  double accuracy = 8.0,
  double speed = 0.0,
  bool progressing = false,
}) {
  return NavParkingArrivalInput(
    timestampMs: t,
    distanceToOriginalDestinationM: toOriginal,
    distanceToRouteEndpointM: toEndpoint,
    remainingRouteM: remaining,
    gpsAccuracyM: accuracy,
    speedKmh: speed,
    progressingTowardDestination: progressing,
  );
}

void main() {
  group('NavParkingArrivalEvaluator', () {
    test('8. Hubo-like parking arrival confirms through bounded proximity', () {
      final e = NavParkingArrivalEvaluator();
      // Near destination, low speed, accurate — accrue dwell then confirm.
      e.evaluate(_input(t: 0, speed: 1.0));
      e.evaluate(_input(t: 2000, speed: 0.5));
      final r = e.evaluate(_input(t: 5000, speed: 0.0));
      expect(r.arrived, isTrue);
      expect(r.decision, NavArrivalDecision.confirmedProximity);
      expect(r.event, NavArrivalEvent.confirmedDestinationProximity);
    });

    test('9. passing at speed does not arrive', () {
      final e = NavParkingArrivalEvaluator();
      // Near destination but fast — never accrues dwell, never arrives.
      for (var t = 0; t <= 10000; t += 1000) {
        final r = e.evaluate(_input(t: t, speed: 45.0));
        expect(r.arrived, isFalse);
      }
      expect(e.confirmed, isFalse);
    });

    test('10. poor GPS accuracy cannot cause arrival', () {
      final e = NavParkingArrivalEvaluator();
      for (var t = 0; t <= 10000; t += 1000) {
        final r = e.evaluate(_input(t: t, speed: 0.0, accuracy: 120.0));
        expect(r.arrived, isFalse);
      }
      expect(e.confirmed, isFalse);
    });

    test('far from destination never arrives even when stationary', () {
      final e = NavParkingArrivalEvaluator();
      for (var t = 0; t <= 10000; t += 1000) {
        final r = e.evaluate(
          _input(t: t, speed: 0.0, toOriginal: 500, toEndpoint: 480, remaining: 600),
        );
        expect(r.arrived, isFalse);
      }
    });

    test('11. close-destination reroute suppression fires within band', () {
      final e = NavParkingArrivalEvaluator();
      final r = e.evaluate(_input(t: 0, speed: 20.0, toOriginal: 70, remaining: 85));
      expect(r.suppressCloseDestinationReroute, isTrue);
    });

    test('one radius alone is not enough (endpoint far)', () {
      final e = NavParkingArrivalEvaluator();
      // Near original but route endpoint far and route not exhausted.
      final r = e.evaluate(
        _input(t: 0, speed: 0.0, toOriginal: 20, toEndpoint: 300, remaining: 400),
      );
      expect(r.arrived, isFalse);
      expect(r.decision, isNot(NavArrivalDecision.confirmedProximity));
    });

    test('12. repeated arrival is idempotent', () {
      final e = NavParkingArrivalEvaluator();
      e.evaluate(_input(t: 0, speed: 1.0));
      e.evaluate(_input(t: 2000, speed: 0.5));
      final first = e.evaluate(_input(t: 5000, speed: 0.0));
      expect(first.arrived, isTrue);
      final second = e.evaluate(_input(t: 6000, speed: 0.0));
      // Stays confirmed but does not re-fire arrival.
      expect(second.arrived, isFalse);
      expect(second.decision, NavArrivalDecision.confirmedProximity);
      expect(second.suppressCloseDestinationReroute, isTrue);
    });

    test('dwell must be continuous — leaving band resets dwell', () {
      final e = NavParkingArrivalEvaluator();
      e.evaluate(_input(t: 0, speed: 0.5));
      e.evaluate(_input(t: 2000, speed: 0.5));
      // Drive away before dwell completes.
      e.evaluate(_input(t: 3000, speed: 30, toOriginal: 500, toEndpoint: 480, remaining: 600));
      // Come back near, dwell must restart.
      e.evaluate(_input(t: 4000, speed: 0.5));
      final r = e.evaluate(_input(t: 6000, speed: 0.5));
      expect(r.arrived, isFalse);
    });

    test('diagnostic line is PII-free', () {
      final line = formatNavArrivalDiagnostic(
        event: NavArrivalEvent.confirmedDestinationProximity,
        dwellMs: 4200,
      );
      expect(line, contains('[NAV_ARRIVAL]'));
      expect(line, contains('event=confirmed_destination_proximity'));
    });
  });
}
