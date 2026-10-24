// DRIVER-HISTORY-PENDING-FLICKER-MONOTONICITY-P1
//
// Pure-helper regression coverage for driver Historiek paint/merge:
// never flash "Lokaal opgeslagen — niet bevestigd" for a trip_id that was
// already backend-authoritative, while keeping genuine pending offline rides
// immediately visible and cleaning only superseded pending projections.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/history/trip_history_monotonic_merge.dart';

class _Row {
  const _Row({
    required this.tripId,
    required this.localUnconfirmed,
    this.label = '',
  });

  final String tripId;
  final bool localUnconfirmed;
  final String label;
}

void main() {
  group('planTripHistoryLocalPaintPhase', () {
    test(
      'authoritative + matching local pending => no unconfirmed flash',
      () {
        final prior = [
          const _Row(tripId: 't1', localUnconfirmed: false, label: 'auth'),
        ];
        final local = [
          const _Row(tripId: 't1', localUnconfirmed: true, label: 'pending'),
        ];
        final plan = planTripHistoryLocalPaintPhase<_Row>(
          priorAuthoritativeItems: prior,
          hasAuthoritativeSnapshot: true,
          localItems: local,
          tripIdOf: (r) => r.tripId,
          isLocalUnconfirmed: (r) => r.localUnconfirmed,
        );
        expect(plan.items, hasLength(1));
        expect(plan.items.single.label, 'auth');
        expect(plan.items.single.localUnconfirmed, isFalse);
        expect(plan.retainAuthoritativeSummary, isTrue);
        expect(plan.summaryNeutral, isFalse);
      },
    );

    test('genuine pending remains visible when trip_id absent from auth', () {
      final prior = [
        const _Row(tripId: 't1', localUnconfirmed: false, label: 'auth'),
      ];
      final local = [
        const _Row(tripId: 't1', localUnconfirmed: true, label: 'stale'),
        const _Row(tripId: 't2', localUnconfirmed: true, label: 'genuine'),
      ];
      final plan = planTripHistoryLocalPaintPhase<_Row>(
        priorAuthoritativeItems: prior,
        hasAuthoritativeSnapshot: true,
        localItems: local,
        tripIdOf: (r) => r.tripId,
        isLocalUnconfirmed: (r) => r.localUnconfirmed,
      );
      final byId = {for (final r in plan.items) r.tripId: r};
      expect(byId.keys, containsAll(['t1', 't2']));
      expect(byId['t1']!.label, 'auth');
      expect(byId['t1']!.localUnconfirmed, isFalse);
      expect(byId['t2']!.label, 'genuine');
      expect(byId['t2']!.localUnconfirmed, isTrue);
      expect(plan.retainAuthoritativeSummary, isTrue);
      expect(plan.summaryNeutral, isFalse);
    });

    test('cold start paints only genuine pending with neutral KPIs', () {
      final local = [
        const _Row(tripId: 't9', localUnconfirmed: true, label: 'pending'),
        const _Row(tripId: 't8', localUnconfirmed: false, label: 'confirmed_local'),
      ];
      final plan = planTripHistoryLocalPaintPhase<_Row>(
        priorAuthoritativeItems: const [],
        hasAuthoritativeSnapshot: false,
        localItems: local,
        tripIdOf: (r) => r.tripId,
        isLocalUnconfirmed: (r) => r.localUnconfirmed,
      );
      expect(plan.items, hasLength(1));
      expect(plan.items.single.tripId, 't9');
      expect(plan.retainAuthoritativeSummary, isFalse);
      expect(plan.summaryNeutral, isTrue);
    });

    test('KPI monotonicity: retain flag set when authoritative snapshot exists',
        () {
      final prior = [
        const _Row(tripId: 'a', localUnconfirmed: false),
        const _Row(tripId: 'b', localUnconfirmed: false),
      ];
      final plan = planTripHistoryLocalPaintPhase<_Row>(
        priorAuthoritativeItems: prior,
        hasAuthoritativeSnapshot: true,
        localItems: const [],
        tripIdOf: (r) => r.tripId,
        isLocalUnconfirmed: (r) => r.localUnconfirmed,
      );
      expect(plan.retainAuthoritativeSummary, isTrue);
      expect(plan.summaryNeutral, isFalse);
      expect(plan.items.map((e) => e.tripId), containsAll(['a', 'b']));
    });
  });

  group('superseded offline_stop_pending_finalize cleanup', () {
    test('backend merge clears/promotes pending marker for matching trip_id',
        () {
      final local = [
        {
          'trip_id': 't1',
          'history_source': 'offline_stop_pending_finalize',
          'finalize_pending': true,
        },
        {
          'trip_id': 't2',
          'history_source': 'offline_stop_pending_finalize',
          'finalize_pending': true,
        },
        {
          'trip_id': 't3',
          'history_source': 'local_only_direct_fallback',
        },
      ];
      final superseded = supersededOfflineStopPendingTripIds(
        localRecords: local,
        backendTripIds: const ['t1'],
      );
      expect(superseded, {'t1'});
      final kept = filterSupersededOfflineStopPendingRows(
        rows: local,
        supersededTripIds: superseded,
      );
      expect(kept.map((e) => e['trip_id']), ['t2', 't3']);
      expect(
        kept.any(
          (e) =>
              e['trip_id'] == 't2' &&
              isOfflineStopPendingFinalizeRecord(e),
        ),
        isTrue,
        reason: 'Genuine still-pending offline ride must remain.',
      );
      expect(
        kept.any((e) => e['trip_id'] == 't3'),
        isTrue,
        reason: 'Unrelated local fallback rows must not be removed.',
      );
    });

    test('nested booking_details history_source is recognized', () {
      final row = {
        'trip_id': 'nested1',
        'booking_details': {
          'history_source': 'offline_stop_pending_finalize',
        },
      };
      expect(isOfflineStopPendingFinalizeRecord(row), isTrue);
      final superseded = supersededOfflineStopPendingTripIds(
        localRecords: [row],
        backendTripIds: const ['nested1'],
      );
      expect(superseded, {'nested1'});
    });
  });

  group('offline STOP durability still preserved', () {
    test(
      '_persistPendingFinalizeDirectHistory wiring remains in driver STOP',
      () {
        final src =
            File('lib/main_parts/driver_home_page_state.dart').readAsStringSync();
        expect(src.contains('_persistPendingFinalizeDirectHistory('), isTrue);
        expect(src.contains('offline_stop_pending_finalize'), isTrue);
      },
    );

    test(
      'history page cleanup is presentation-only and does not remove persist',
      () {
        final page =
            File('lib/main_parts/trip_history_page.dart').readAsStringSync();
        expect(
          page.contains('removeSupersededOfflineStopPending'),
          isTrue,
        );
        expect(
          page.contains('planTripHistoryLocalPaintPhase'),
          isTrue,
        );
        // Persist call site must remain on DriverHomePage (not rewritten here).
        final driver =
            File('lib/main_parts/driver_home_page_state.dart').readAsStringSync();
        expect(
          driver.contains('await _persistPendingFinalizeDirectHistory('),
          isTrue,
        );
        final store = File('lib/main_parts/compliance_local_stores.dart')
            .readAsStringSync();
        expect(
          store.contains('isOfflineStopPendingFinalizeRecord'),
          isTrue,
        );
        expect(
          store.contains('Never touches genuine still-pending'),
          isTrue,
        );
      },
    );
  });
}
