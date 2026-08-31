import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/driver/trip_history_booking_detail_repository.dart';
import 'package:fluxidi_tracking/payment/canonical_ride_paid.dart';

void main() {
  group('canonical ride paid resolver', () {
    test('paid booking makes receipt and history paid', () {
      final history = <String, dynamic>{'payment_status': 'pending'};
      final booking = <String, dynamic>{
        'payment_status': 'paid',
        'paid_at': '2026-08-22T12:00:00Z',
      };
      expect(
        resolveCanonicalRideIsPaid(historyRaw: history, bookingRecord: booking),
        isTrue,
      );
      expect(
        resolveCanonicalRidePaidDisplay(
          historyRaw: history,
          bookingRecord: booking,
        ),
        CanonicalRidePaidDisplay.paid,
      );
    });

    test('unpaid booking keeps receipt and history unpaid', () {
      final history = <String, dynamic>{'payment_status': 'pending'};
      final booking = <String, dynamic>{'payment_status': 'unpaid'};
      expect(
        resolveCanonicalRideIsPaid(historyRaw: history, bookingRecord: booking),
        isFalse,
      );
      expect(
        resolveCanonicalRidePaidDisplay(
          historyRaw: history,
          bookingRecord: booking,
        ),
        CanonicalRidePaidDisplay.unpaid,
      );
    });

    test('refresh does not regress booking paid to history pending', () {
      final staleHistory = <String, dynamic>{'payment_status': 'pending'};
      final booking = <String, dynamic>{'payment_status': 'paid'};
      final first = resolveCanonicalRidePaidDisplay(
        historyRaw: staleHistory,
        bookingRecord: booking,
      );
      final refreshedHistory = overlayCanonicalPaymentFields(
        staleHistory,
        extractCanonicalPaymentFields(booking),
      );
      final second = resolveCanonicalRidePaidDisplay(
        historyRaw: refreshedHistory,
        bookingRecord: booking,
      );
      expect(first, CanonicalRidePaidDisplay.paid);
      expect(second, CanonicalRidePaidDisplay.paid);
      expect(refreshedHistory['payment_status'], 'paid');
    });

    test('local unpaid cache cannot override booking paid', () {
      final local = <String, dynamic>{
        'payment_status': 'unpaid',
        'paid': false,
      };
      final booking = <String, dynamic>{
        'record': <String, dynamic>{'payment_status': 'paid'},
      };
      expect(
        resolveCanonicalRideIsPaid(historyRaw: local, bookingRecord: booking),
        isTrue,
      );
    });

    test('stale unpaid overlay cannot downgrade a paid trip', () {
      expect(
        resolveCanonicalRideIsPaid(
          historyRaw: <String, dynamic>{'payment_status': 'paid'},
        ),
        isTrue,
      );
      expect(
        resolveCanonicalRideIsPaid(
          historyRaw: <String, dynamic>{'payment_status': 'paid'},
          historyDetails: <String, dynamic>{'payment_status': 'unpaid'},
          bookingRecord: <String, dynamic>{'payment_status': 'unpaid'},
        ),
        isTrue,
      );
      final retained = overlayCanonicalPaymentFields(
        <String, dynamic>{'payment_status': 'paid', 'payment_method': 'cash'},
        <String, dynamic>{'payment_status': 'unpaid'},
      );
      expect(retained['payment_status'], 'paid');
      expect(
        resolveCanonicalRidePaidDisplay(
          historyRaw: retained,
          bookingRecord: <String, dynamic>{'payment_status': 'unpaid'},
        ),
        CanonicalRidePaidDisplay.paid,
      );
    });

    test('cash in car paid trip remains Historiek Betaald', () {
      final historyRaw = <String, dynamic>{
        'payment_status': 'paid',
        'payment_method': 'cash',
        'payment_source': 'in_car',
        'booking_details': <String, dynamic>{'payment_status': 'unpaid'},
      };
      expect(
        resolveCanonicalRideIsPaid(
          historyRaw: historyRaw,
          historyDetails: <String, dynamic>{'payment_status': 'unpaid'},
          bookingRecord: <String, dynamic>{'payment_status': 'paid'},
        ),
        isTrue,
      );
    });

    test('paid_at is a paid signal when status is missing', () {
      expect(
        resolveCanonicalRideIsPaid(
          bookingRecord: <String, dynamic>{'paid_at': '2026-08-22T12:00:00Z'},
        ),
        isTrue,
      );
    });
  });

  test('Historiek and receipt share the same paid helper', () {
    final history = File(
      'lib/main_parts/trip_history_page.dart',
    ).readAsStringSync();
    final receipt = File(
      'lib/main_parts/ride_receipt_body_state.dart',
    ).readAsStringSync();
    expect(history.contains('resolveCanonicalRidePaidDisplay('), isTrue);
    expect(history.contains('_refreshCanonicalPaymentForItems'), isFalse);
    expect(tripHistoryAllowsAutomaticDetailHydration(), isFalse);
    expect(receipt.contains('isCanonicalPaidStatusValue(value)'), isTrue);
    expect(receipt.contains('resolveCanonicalRideIsPaid('), isTrue);
    expect(
      File('lib/main.dart').readAsStringSync().contains(
        "import 'package:fluxidi_tracking/payment/canonical_ride_paid.dart';",
      ),
      isTrue,
    );
  });
}
