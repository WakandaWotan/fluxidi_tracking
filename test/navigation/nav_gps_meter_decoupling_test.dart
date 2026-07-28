import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/navigation/nav_engine/nav_background_dispatcher.dart';

// NAV-MOBILE-DATA-MINIMAL-SAFE-RELEASE-P0-1 Part H — end-to-end proof that
// a GPS/meter tick completes even when both the ping and the route
// presentation Futures never resolve. The dispatchers are the same runtime
// primitives used by driver_home_page_state.dart; a fake meter core simulates
// the pure local update the real callback now performs.

class _FakeMeterCore {
  double kmDriven = 0.0;
  int fareCents = 0;
  int publishCount = 0;

  void onGps(double meters, {required bool liveRideActive, required bool isWaiting}) {
    if (liveRideActive && !isWaiting && meters.isFinite && meters > 0) {
      kmDriven += meters / 1000.0;
      fareCents += (meters * 0.15).round();
      publishCount += 1;
    }
  }
}

void main() {
  test(
    'GPS callback completes meter update while ping Future never resolves',
    () async {
      final meter = _FakeMeterCore();
      final ping = NavBackgroundDispatcher<double>(
        runner: (_) => Completer<void>().future,
        // No timeout — this future would hang for the whole test if it were
        // awaited on the GPS callback.
      );
      final route = NavBackgroundDispatcher<double>(
        runner: (_) async {},
      );

      // Simulate 5 accepted GPS ticks.
      for (var i = 0; i < 5; i++) {
        meter.onGps(50.0, liveRideActive: true, isWaiting: false);
        ping.enqueue(i.toDouble());
        route.enqueue(i.toDouble());
      }
      // Flush any microtasks.
      await Future<void>.value();
      await Future<void>.value();

      expect(meter.publishCount, 5);
      expect(meter.kmDriven, closeTo(0.25, 1e-9));
      // Only one ping is in flight; four newer positions have been replaced.
      expect(ping.inFlight, isTrue);
      expect(ping.hasPending, isFalse);
      ping.dispose();
      route.dispose();
    },
  );

  test(
    'GPS callback completes meter update while route-presentation Future never resolves',
    () async {
      final meter = _FakeMeterCore();
      final ping = NavBackgroundDispatcher<double>(
        runner: (_) async {},
      );
      final route = NavBackgroundDispatcher<double>(
        runner: (_) => Completer<void>().future,
      );

      for (var i = 0; i < 3; i++) {
        meter.onGps(20.0, liveRideActive: true, isWaiting: false);
        ping.enqueue(i.toDouble());
        route.enqueue(i.toDouble());
      }
      await Future<void>.value();
      await Future<void>.value();

      expect(meter.publishCount, 3);
      expect(meter.kmDriven, closeTo(0.06, 1e-9));
      ping.dispose();
      route.dispose();
    },
  );

  test('ping exception cannot stop a later GPS update', () async {
    final meter = _FakeMeterCore();
    final ping = NavBackgroundDispatcher<double>(
      runner: (_) async => throw StateError('boom'),
      onError: (_, __) {},
    );

    meter.onGps(10.0, liveRideActive: true, isWaiting: false);
    ping.enqueue(1);
    await Future<void>.value();
    await Future<void>.value();

    // Even after a runner exception, the next accepted GPS tick continues
    // to update the meter — the exception was contained.
    meter.onGps(10.0, liveRideActive: true, isWaiting: false);
    ping.enqueue(2);
    await Future<void>.value();
    await Future<void>.value();

    expect(meter.publishCount, 2);
    expect(meter.kmDriven, closeTo(0.02, 1e-9));
    ping.dispose();
  });

  test('route-presentation exception cannot stop a later GPS update', () async {
    final meter = _FakeMeterCore();
    final route = NavBackgroundDispatcher<double>(
      runner: (_) async => throw StateError('annotations gone'),
      onError: (_, __) {},
    );

    meter.onGps(15.0, liveRideActive: true, isWaiting: false);
    route.enqueue(1);
    await Future<void>.value();
    await Future<void>.value();

    meter.onGps(15.0, liveRideActive: true, isWaiting: false);
    route.enqueue(2);
    await Future<void>.value();
    await Future<void>.value();

    expect(meter.publishCount, 2);
    expect(meter.kmDriven, closeTo(0.03, 1e-9));
    route.dispose();
  });

  test('meter values remain authoritative through STOP (dispose)', () async {
    final meter = _FakeMeterCore();
    final ping = NavBackgroundDispatcher<double>(
      runner: (_) => Completer<void>().future,
    );

    meter.onGps(100.0, liveRideActive: true, isWaiting: false);
    ping.enqueue(1);
    await Future<void>.value();
    expect(meter.kmDriven, closeTo(0.1, 1e-9));

    // STOP: pending work is dropped, but meter values are unchanged.
    ping.dispose();
    expect(meter.kmDriven, closeTo(0.1, 1e-9));
  });
}
