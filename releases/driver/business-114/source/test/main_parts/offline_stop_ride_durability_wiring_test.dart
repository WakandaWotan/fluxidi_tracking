import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Source-wiring guard for OFFLINE-STOP-RIDE-DURABILITY-P0.
///
/// Ensures DriverHomePage keeps the reconnect / frozen-STOP outbox hooks that
/// pure unit tests cannot exercise through the giant State class.
void main() {
  late String stopBody;
  late String connectivityBody;

  setUpAll(() {
    final file = File('lib/main_parts/driver_home_page_state.dart');
    final src = file.readAsStringSync();
    final stopIdx = src.indexOf('Future<void> _stopTrip() async');
    expect(stopIdx, greaterThan(0));
    stopBody = src.substring(stopIdx, stopIdx + 18000);
    final connIdx = src.indexOf('void _setNavInternetConnectivity({');
    expect(connIdx, greaterThan(0));
    connectivityBody = src.substring(connIdx, connIdx + 1200);
  });

  test('STOP freezes durable session before leaving active presentation', () {
    expect(stopBody.contains('kDirectTripTrackingStopPending'), isTrue);
    expect(stopBody.contains('frozenKmTotal: kmAtStop'), isTrue);
    expect(stopBody.contains('frozenTotalEur: frozenDirectFare'), isTrue);
    final persistIdx = stopBody.indexOf('_persistDirectTripSession(');
    final clearIdx = stopBody.indexOf("_directRideActive = false");
    expect(persistIdx, greaterThan(0));
    expect(clearIdx, greaterThan(persistIdx),
        reason: 'Durable freeze must precede clearing live ride UI');
  });

  test('offline pending history is written for known trip ids', () {
    expect(stopBody.contains('_persistPendingFinalizeDirectHistory('), isTrue);
  });

  test('second STOP while pending triggers recovery drain', () {
    final guardIdx = stopBody.indexOf('if (_directStopFinalizePending)');
    final recoverIdx = stopBody.indexOf(
      'unawaited(_recoverPendingDirectTripSession())',
      guardIdx,
    );
    expect(guardIdx, greaterThan(0));
    expect(recoverIdx, greaterThan(guardIdx));
  });

  test('connectivity restore drains pending direct-trip session', () {
    expect(
      connectivityBody.contains(
        'unawaited(_recoverPendingDirectTripSession())',
      ),
      isTrue,
    );
    expect(connectivityBody.contains('!wasUsable && usable'), isTrue);
  });

  test('recovery implements stop replay with frozen totals', () {
    final src = File('lib/main_parts/driver_home_page_state.dart')
        .readAsStringSync();
    expect(src.contains('_attemptDirectStopReplayWithBackoff'), isTrue);
    expect(src.contains('DirectTripRecoveryAction.retryStop'), isTrue);
  });

  test('STOP success drains Chiron when compliance emit not applied', () {
    final src = File('lib/main_parts/driver_home_page_state.dart')
        .readAsStringSync();
    expect(src.contains('!outcome.complianceEmitApplied'), isTrue);
    expect(
      src.contains('OFFLINE-STOP-CHIRON-ARRIVAL-DURABILITY-P0'),
      isTrue,
    );
  });
}
