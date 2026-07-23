import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/main_parts/direct_ride_booking_link.dart';

/// STREET-RIDE-DURABLE-COMPLETION-2 — client-side durable session contract.
///
/// Pure tests for the persisted direct-trip session record, the startup
/// recovery decision, the bounded reconcile backoff, and the STOP response
/// parser. These pin the client half of the durable-completion contract
/// without pumping the driver home widget.
void main() {
  DirectTripSession active({
    String key = 'direct_1752863820000_driver-1',
    String tripId = 'trip_abc',
    String bookingId = 'street_1752863820000_ab12cd34',
    String started = '2026-07-23T10:00:00.000Z',
    String lifecycle = kDirectTripLocalLifecycleActive,
    String finalize = kDirectTripFinalizePending,
    String? updated,
  }) {
    return DirectTripSession(
      directRideKey: key,
      tripId: tripId,
      bookingId: bookingId,
      startedAtIso: started,
      localLifecycle: lifecycle,
      bookingFinalizeState: finalize,
      tenantId: 'T1',
      companyId: 'C1',
      driverId: 'driver-1',
      updatedAtIso: updated,
    );
  }

  group('DirectTripSession serialization', () {
    test('round-trips through json preserving identity fields', () {
      final s = active(updated: '2026-07-23T10:05:00.000Z');
      final decoded = DirectTripSession.fromJson(s.toJson());
      expect(decoded, isNotNull);
      expect(decoded!.directRideKey, s.directRideKey);
      expect(decoded.tripId, s.tripId);
      expect(decoded.bookingId, s.bookingId);
      expect(decoded.startedAtIso, s.startedAtIso);
      expect(decoded.localLifecycle, kDirectTripLocalLifecycleActive);
      expect(decoded.bookingFinalizeState, kDirectTripFinalizePending);
      expect(decoded.tenantId, 'T1');
      expect(decoded.companyId, 'C1');
      expect(decoded.driverId, 'driver-1');
    });

    test('fromJson returns null for meaningless records', () {
      expect(DirectTripSession.fromJson(null), isNull);
      expect(DirectTripSession.fromJson('nope'), isNull);
      expect(
        DirectTripSession.fromJson(<String, dynamic>{'booking_id': 'x'}),
        isNull,
        reason: 'no direct_ride_key and no trip_id',
      );
    });

    test('copyWith updates only the given fields', () {
      final s = active();
      final next = s.copyWith(
        localLifecycle: kDirectTripLocalLifecycleStopped,
        bookingFinalizeState: kDirectTripFinalizeCompleted,
      );
      expect(next.localLifecycle, kDirectTripLocalLifecycleStopped);
      expect(next.bookingFinalizeState, kDirectTripFinalizeCompleted);
      expect(next.tripId, s.tripId);
      expect(next.directRideKey, s.directRideKey);
      expect(next.isCompleted, isTrue);
      expect(next.isStopped, isTrue);
    });
  });

  group('directTripRecoveryAction', () {
    final now = DateTime.parse('2026-07-23T10:10:00.000Z');

    test('null or completed session needs no recovery', () {
      expect(directTripRecoveryAction(null, now: now),
          DirectTripRecoveryAction.none);
      expect(
        directTripRecoveryAction(
          active(finalize: kDirectTripFinalizeCompleted),
          now: now,
        ),
        DirectTripRecoveryAction.none,
      );
    });

    test('stopped + pending + durable ids reconciles', () {
      expect(
        directTripRecoveryAction(
          active(lifecycle: kDirectTripLocalLifecycleStopped),
          now: now,
        ),
        DirectTripRecoveryAction.reconcilePending,
      );
    });

    test('stopped + pending but local-only (no booking/trip) is abandoned', () {
      expect(
        directTripRecoveryAction(
          active(
            lifecycle: kDirectTripLocalLifecycleStopped,
            tripId: '',
            bookingId: '',
          ),
          now: now,
        ),
        DirectTripRecoveryAction.abandon,
      );
    });

    test('recent active session resumes', () {
      expect(
        directTripRecoveryAction(
          active(started: '2026-07-23T10:00:00.000Z'),
          now: now,
        ),
        DirectTripRecoveryAction.resumeActive,
      );
    });

    test('stale active session (older than staleAfter) is abandoned', () {
      expect(
        directTripRecoveryAction(
          active(started: '2026-07-22T10:00:00.000Z'),
          now: now,
          staleAfter: const Duration(hours: 12),
        ),
        DirectTripRecoveryAction.abandon,
      );
    });
  });

  group('directReconcileBackoff', () {
    test('is bounded between 2s and 5min and monotonic-ish', () {
      expect(directReconcileBackoff(0), const Duration(seconds: 2));
      expect(directReconcileBackoff(1), const Duration(seconds: 4));
      expect(directReconcileBackoff(3), const Duration(seconds: 16));
      expect(directReconcileBackoff(100).inSeconds, 300);
      expect(directReconcileBackoff(-5), const Duration(seconds: 2));
    });
  });

  group('company bucket for the ACTIVE projection', () {
    test('ACTIVE street ride buckets to open (stays in Available)', () {
      expect(streetRideCompanyBucket('ACTIVE'), StreetRideCompanyBucket.open);
      expect(streetRideCompanyBucket('IN_PROGRESS'), StreetRideCompanyBucket.open);
    });

    test('COMPLETED street ride buckets to completed (History only)', () {
      expect(
        streetRideCompanyBucket('COMPLETED'),
        StreetRideCompanyBucket.completed,
      );
    });

    test('CANCELLED street ride buckets to cancelled', () {
      expect(
        streetRideCompanyBucket('CANCELLED'),
        StreetRideCompanyBucket.cancelled,
      );
    });
  });

  group('parseDirectRideStopResponse', () {
    test('reads totals and completed finalize state', () {
      final r = parseDirectRideStopResponse(<String, dynamic>{
        'ok': true,
        'booking_id': 'street_1_ab',
        'booking_finalize_state': 'completed',
        'booking_finalized': true,
        'totals': <String, dynamic>{'total_eur': 3.2},
      });
      expect(r.ok, isTrue);
      expect(r.totalEur, 3.2);
      expect(r.bookingId, 'street_1_ab');
      expect(r.bookingFinalizeState, kDirectTripFinalizeCompleted);
      expect(r.bookingFinalized, isTrue);
    });

    test('pending finalize is not falsely reported as completed', () {
      final r = parseDirectRideStopResponse(<String, dynamic>{
        'ok': true,
        'booking_id': 'street_1_ab',
        'booking_finalize_state': 'pending',
        'booking_finalized': false,
        'totals': <String, dynamic>{'total_eur': 3.3},
      });
      expect(r.totalEur, 3.3);
      expect(r.bookingFinalized, isFalse);
      expect(r.bookingFinalizeState, kDirectTripFinalizePending);
    });

    test('malformed response defaults to pending / not finalized', () {
      final r = parseDirectRideStopResponse('nope');
      expect(r.ok, isFalse);
      expect(r.totalEur, isNull);
      expect(r.bookingFinalized, isFalse);
      expect(r.bookingFinalizeState, kDirectTripFinalizePending);
    });
  });
}
