// STREET-RIDE-HISTORY-DUPLICATE-ZERO-BOOKING-1 / 1A / 1B — canonical dedupe.

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/main_parts/street_history_canonical.dart';

class _Row {
  const _Row({
    required this.tripId,
    required this.kind,
    required this.bookingId,
    this.parentBookingId = '',
    this.linkedTrackingTripId = '',
    this.isOperationalLeg = false,
    this.workerShadowHint,
    this.amountEur = 0.0,
    this.completed = true,
  });

  final String tripId;
  final String kind;
  final String bookingId;
  final String parentBookingId;
  final String linkedTrackingTripId;
  final bool isOperationalLeg;
  final bool? workerShadowHint;
  final double amountEur;
  final bool completed;
}

List<_Row> _canon(List<_Row> rows, {List<StreetHistoryCanonicalLog>? logs}) {
  return canonicalizeStreetHistory<_Row>(
    rows,
    tripId: (r) => r.tripId,
    kind: (r) => r.kind,
    bookingId: (r) => r.bookingId,
    parentBookingId: (r) => r.parentBookingId,
    linkedTrackingTripId: (r) => r.linkedTrackingTripId,
    isOperationalLeg: (r) => r.isOperationalLeg,
    workerShadowHint: (r) => r.workerShadowHint,
    onLog: logs?.add,
  );
}

// Real runtime shapes where the ids DIFFER between the two records.
_Row _direct320({
  String tripId = 'trip_DIRECT_9f3a10',
  String bookingId = 'street_OLD_1752863820000',
  double amount = 3.20,
  bool completed = true,
}) => _Row(
  tripId: tripId,
  kind: 'direct',
  bookingId: bookingId,
  amountEur: amount,
  completed: completed,
);

// €0,00 Outbound shadow whose booking id differs from the direct trip's.
_Row _legacyShadow000({
  String tripId = 'planned_street_NEW_88_OUTBOUND',
  String bookingId = 'street_NEW_88',
  String parentBookingId = 'street_NEW_88',
  String linkedTrackingTripId = '',
  bool isOperationalLeg = true,
  bool? workerShadowHint,
}) => _Row(
  tripId: tripId,
  kind: 'planned',
  bookingId: bookingId,
  parentBookingId: parentBookingId,
  linkedTrackingTripId: linkedTrackingTripId,
  isOperationalLeg: isOperationalLeg,
  workerShadowHint: workerShadowHint,
  amountEur: 0.0,
);

void main() {
  group('STREET-RIDE-HISTORY-DUPLICATE-ZERO-BOOKING-1B canonical dedupe', () {
    test('client canonical version is 1B', () {
      expect(kStreetHistoryClientCanonicalVersion, '1B');
    });

    test('worker is_operational_shadow hint collapses despite differing ids', () {
      final logs = <StreetHistoryCanonicalLog>[];
      final out = _canon([
        _direct320(),
        _legacyShadow000(workerShadowHint: true),
      ], logs: logs);
      expect(out.length, 1);
      expect(out.single.kind, 'direct');
      expect(out.single.amountEur, 3.20);
      expect(logs.single.reason, 'street_planned_leg_shadow_of_direct_trip');
    });

    test('explicit linked_tracking_trip_id collapses despite differing ids', () {
      final out = _canon([
        _direct320(),
        _legacyShadow000(linkedTrackingTripId: 'trip_DIRECT_9f3a10'),
      ]);
      expect(out.length, 1);
      expect(out.single.kind, 'direct');
    });

    test('linked shadow collapses even when it appears before its direct', () {
      final out = _canon([
        _legacyShadow000(linkedTrackingTripId: 'trip_DIRECT_9f3a10'),
        _direct320(),
      ]);
      expect(out.length, 1);
      expect(out.single.kind, 'direct');
    });

    test('why 1A failed: differing ids + no link/hint -> stays (no guessing)', () {
      final out = _canon([_direct320(), _legacyShadow000()]);
      expect(out.length, 2);
    });

    test('worker hint=false is respected even if heuristics would collapse', () {
      final out = _canon([
        _direct320(bookingId: 'street_SAME'),
        _legacyShadow000(
          tripId: 'planned_street_SAME_OUTBOUND',
          bookingId: 'street_SAME',
          parentBookingId: 'street_SAME',
          workerShadowHint: false,
        ),
      ]);
      expect(out.length, 2);
    });

    test('legacy 1A shape (shared booking id) still collapses', () {
      final out = _canon([
        _direct320(bookingId: 'street_SAME'),
        _legacyShadow000(
          tripId: 'planned_street_SAME_OUTBOUND',
          bookingId: 'street_SAME',
          parentBookingId: 'street_SAME',
        ),
      ]);
      expect(out.length, 1);
      expect(out.single.kind, 'direct');
    });

    test('counts/revenue increase by one, not two', () {
      final out = _canon([
        _direct320(amount: 3.20),
        _legacyShadow000(linkedTrackingTripId: 'trip_DIRECT_9f3a10'),
      ]);
      final completed = out.where((r) => r.completed).length;
      final revenue = out
          .where((r) => r.completed)
          .fold<double>(0, (s, r) => s + r.amountEur);
      expect(out.length, 1);
      expect(completed, 1);
      expect(revenue, 3.20);
    });

    test('real planned outbound + return (no direct, no link) stay separate', () {
      final out = _canon([
        const _Row(
          tripId: 'planned_P9',
          kind: 'planned',
          bookingId: 'P9',
          parentBookingId: 'P9',
          isOperationalLeg: true,
          amountEur: 20,
        ),
        const _Row(
          tripId: 'planned_P9_RETURN',
          kind: 'planned',
          bookingId: 'P9',
          parentBookingId: 'P9',
          isOperationalLeg: true,
          amountEur: 20,
        ),
      ]);
      expect(out.length, 2);
    });

    test('real free €0 direct ride stays visible', () {
      final out = _canon([
        _direct320(tripId: 'trip_free', bookingId: 'street_free', amount: 0.0),
      ]);
      expect(out.length, 1);
      expect(out.single.amountEur, 0.0);
    });

    test('unresolved legacy record stays safely visible', () {
      final out = _canon([_legacyShadow000()]);
      expect(out.length, 1);
    });

    test('dedupe uses relational ids, not time/amount', () {
      final out = _canon([
        _direct320(tripId: 't1', bookingId: 'b1', amount: 3.20),
        _direct320(tripId: 't2', bookingId: 'b2', amount: 3.20),
      ]);
      expect(out.length, 2);
    });

    test('idempotent — no extra rows on re-run', () {
      final once = _canon([
        _direct320(),
        _legacyShadow000(linkedTrackingTripId: 'trip_DIRECT_9f3a10'),
      ]);
      final twice = _canon(once);
      expect(twice.length, 1);
    });

    test('empty booking id is never merged', () {
      final out = _canon([
        _direct320(bookingId: ''),
        const _Row(tripId: 'planned_', kind: 'planned', bookingId: ''),
      ]);
      expect(out.length, 2);
    });

    test('order of kept rows is preserved', () {
      final out = _canon([
        _direct320(tripId: 't1', bookingId: 'b1'),
        _legacyShadow000(
          tripId: 'planned_b1',
          bookingId: 'b1',
          parentBookingId: 'b1',
          linkedTrackingTripId: 't1',
        ),
        _direct320(tripId: 't2', bookingId: 'b2'),
      ]);
      expect(out.map((r) => r.tripId).toList(), ['t1', 't2']);
    });

    test('helpers expose direct ride keys (trip id AND booking id)', () {
      final ids = streetHistoryDirectRideKeys<_Row>(
        [_direct320()],
        kind: (r) => r.kind,
        bookingId: (r) => r.bookingId,
        tripId: (r) => r.tripId,
      );
      expect(ids.contains('trip_DIRECT_9f3a10'), isTrue);
      expect(ids.contains('street_OLD_1752863820000'), isTrue);
      expect(
        isCanonicalStreetPlannedShadow(
          tripId: 'planned_street_NEW_88_OUTBOUND',
          kind: 'planned',
          bookingId: 'street_NEW_88',
          parentBookingId: 'street_NEW_88',
          linkedTrackingTripId: 'trip_DIRECT_9f3a10',
          isOperationalLeg: true,
          directRideKeys: ids,
        ),
        isTrue,
      );
      expect(
        isCanonicalStreetPlannedShadow(
          tripId: 'planned_street_NEW_88_OUTBOUND',
          kind: 'planned',
          bookingId: 'street_NEW_88',
          parentBookingId: 'street_NEW_88',
          isOperationalLeg: true,
          directRideKeys: ids,
        ),
        isFalse,
      );
    });
  });
}
