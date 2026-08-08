import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/main_parts/direct_ride_booking_link.dart';

/// OFFLINE-STOP-RIDE-DURABILITY-P0 — contract tests for frozen STOP totals,
/// outbox recovery actions, and idempotent reconnect semantics.
void main() {
  DirectTripSession stoppedPending({
    String tripId = 'trip_field_1',
    String bookingId = 'street_field_1',
    String trackingStop = kDirectTripTrackingStopPending,
    double km = 1.25,
    int wait = 15,
    double fare = 7.5,
  }) {
    return DirectTripSession(
      directRideKey: 'direct_1_drv',
      tripId: tripId,
      bookingId: bookingId,
      startedAtIso: '2026-08-08T09:00:00.000Z',
      localLifecycle: kDirectTripLocalLifecycleStopped,
      bookingFinalizeState: kDirectTripFinalizePending,
      stoppedAtIso: '2026-08-08T09:12:00.000Z',
      frozenKmTotal: km,
      frozenWaitSecondsTotal: wait,
      frozenTotalEur: fare,
      trackingStopState: trackingStop,
      tenantId: 'T1',
      companyId: 'C1',
      driverId: 'drv_1',
    );
  }

  group('1. STOP online (tracking completed → reconcile path)', () {
    test('tracking stop completed keeps reconcilePending action', () {
      final s = stoppedPending(trackingStop: kDirectTripTrackingStopCompleted);
      expect(s.needsTrackingStopReplay, isFalse);
      expect(directTripRecoveryAction(s), DirectTripRecoveryAction.reconcilePending);
    });
  });

  group('2. STOP while offline', () {
    test('frozen totals + pending tracking stop survive serialization', () {
      final s = stoppedPending();
      final roundTrip = DirectTripSession.fromJson(s.toJson())!;
      expect(roundTrip.hasFrozenStopTotals, isTrue);
      expect(roundTrip.frozenKmTotal, 1.25);
      expect(roundTrip.frozenWaitSecondsTotal, 15);
      expect(roundTrip.frozenTotalEur, 7.5);
      expect(roundTrip.needsTrackingStopReplay, isTrue);
      expect(
        directTripRecoveryAction(roundTrip),
        DirectTripRecoveryAction.retryStop,
      );
    });

    test('active ride is not abandoned when stopped pending outbox exists', () {
      final s = stoppedPending();
      expect(directTripRecoveryAction(s), isNot(DirectTripRecoveryAction.abandon));
      expect(directTripRecoveryAction(s), isNot(DirectTripRecoveryAction.none));
    });
  });

  group('3. Reconnect after offline STOP', () {
    test('retryStop precedes reconcile until tracking stop lands', () {
      final pending = stoppedPending();
      expect(directTripRecoveryAction(pending), DirectTripRecoveryAction.retryStop);

      final landed = pending.copyWith(
        trackingStopState: kDirectTripTrackingStopCompleted,
      );
      expect(directTripRecoveryAction(landed), DirectTripRecoveryAction.reconcilePending);
      expect(landed.frozenKmTotal, pending.frozenKmTotal);
      expect(landed.frozenTotalEur, pending.frozenTotalEur);
    });
  });

  group('4. App restart while offline-finalize pending', () {
    test('disk JSON recovers identical ride identity and frozen totals', () {
      final s = stoppedPending();
      final recovered = DirectTripSession.fromJson(s.toJson())!;
      expect(recovered.tripId, s.tripId);
      expect(recovered.bookingId, s.bookingId);
      expect(recovered.directRideKey, s.directRideKey);
      expect(recovered.frozenTotalEur, s.frozenTotalEur);
      expect(
        directTripRecoveryAction(recovered),
        DirectTripRecoveryAction.retryStop,
      );
    });
  });

  group('5. Multiple reconnect/retry events stay idempotent', () {
    test('repeated recovery decisions stay retryStop with same frozen fare', () {
      final s = stoppedPending();
      for (var i = 0; i < 5; i++) {
        expect(directTripRecoveryAction(s), DirectTripRecoveryAction.retryStop);
        expect(s.frozenTotalEur, 7.5);
        expect(s.frozenKmTotal, 1.25);
      }
    });
  });

  group('6. Backend succeeds but response lost', () {
    test('already-completed tracking stop flips to reconcile without new totals', () {
      // Client still has trackingStop=pending after lost response; once a
      // replay observes trackingTripStopped, session advances to completed
      // tracking stop and reconcile — frozen totals unchanged.
      final lostResponse = stoppedPending();
      final afterReplayAck = lostResponse.copyWith(
        trackingStopState: kDirectTripTrackingStopCompleted,
      );
      expect(afterReplayAck.frozenKmTotal, lostResponse.frozenKmTotal);
      expect(afterReplayAck.frozenTotalEur, lostResponse.frozenTotalEur);
      expect(
        directTripRecoveryAction(afterReplayAck),
        DirectTripRecoveryAction.reconcilePending,
      );
    });
  });

  group('7. Payment safety after recovery', () {
    test('completed finalize clears recovery; pending never invents payment', () {
      final pending = stoppedPending();
      expect(pending.isCompleted, isFalse);
      expect(directTripRecoveryAction(pending), DirectTripRecoveryAction.retryStop);

      final done = pending.copyWith(
        bookingFinalizeState: kDirectTripFinalizeCompleted,
        trackingStopState: kDirectTripTrackingStopCompleted,
      );
      expect(done.isCompleted, isTrue);
      expect(directTripRecoveryAction(done), DirectTripRecoveryAction.none);
    });
  });
}
