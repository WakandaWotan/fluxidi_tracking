// Dossier 02 — the device never upgrades a booking to Paid on its own.
//
// Three surfaces used to paint Paid before the authoritative record agreed:
// the saved-bookings list, the booking detail page and the ride receipt. Only
// a verified provider settlement or an audited in-car cash confirmation may
// read as Paid, and both arrive as payment_status paid from the server.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/payment/canonical_ride_paid.dart';

String read(String relativePath) =>
    File(relativePath).readAsStringSync().replaceAll('\r\n', '\n');

void main() {
  late String savedListSource;
  late String activeListSource;
  late String detailSource;
  late String receiptSource;

  setUpAll(() {
    savedListSource = read('lib/main_parts/customer_saved_bookings_page.dart');
    activeListSource = read('lib/main_parts/customer_bookings_page.dart');
    detailSource = read('lib/main_parts/customer_booking_detail_page.dart');
    receiptSource = read('lib/main_parts/ride_receipt_body_state.dart');
  });

  group('no surface keeps a local paid override', () {
    test('the saved-bookings list has no optimistic paid set', () {
      expect(savedListSource, isNot(contains('_optimisticallyPaidBookingIds')));
      expect(savedListSource, isNot(contains('STALE_PAYMENT_LABEL_GUARD')));
      expect(savedListSource, isNot(contains('PAYMENT_STATUS_PATCHED')));
    });

    test('the active bookings list has no optimistic paid set', () {
      expect(activeListSource, isNot(contains('_optimisticallyPaidBookingIds')));
      expect(activeListSource, isNot(contains('STALE_PAYMENT_LABEL_GUARD')));
      expect(activeListSource, isNot(contains('PAYMENT_STATUS_PATCHED')));
      expect(activeListSource, isNot(contains("copyWith(paymentStatus: 'paid')")));
    });

    test('the detail page has no optimistic paid flag', () {
      expect(detailSource, isNot(contains('_optimisticPaidApplied')));
      expect(detailSource, isNot(contains('PAYMENT_STATUS_PATCHED')));
      expect(detailSource, isNot(contains("paymentToken = 'paid'")));
    });

    test('the receipt never derives paid from the chosen method', () {
      expect(receiptSource, isNot(contains('_methodImpliesPaid')));
      expect(receiptSource, isNot(contains('markAsPaidFromMethod')));
    });
  });

  group('a return from checkout only triggers a refresh', () {
    test('every payment-return surface logs local_patch=none', () {
      for (final source in <String>[
        savedListSource,
        activeListSource,
        detailSource,
      ]) {
        expect(source, contains('local_patch=none'));
      }
    });
  });

  group('the canonical rule still holds for both settlement routes', () {
    test('a cancelled or failed Mollie return stays unpaid', () {
      for (final status in <String>[
        'open',
        'pending',
        'authorized',
        'failed',
        'canceled',
        'expired',
      ]) {
        expect(
          resolveCanonicalRideIsPaid(
            bookingRecord: <String, dynamic>{
              'status': 'COMPLETED',
              'payment_method': 'bancontact',
              'payment_provider': 'mollie',
              'payment_status': status,
            },
          ),
          isFalse,
          reason: 'Mollie $status must never read as paid',
        );
      }
    });

    test('an app restart does not turn an unpaid ride into paid', () {
      final restored = <String, dynamic>{
        'status': 'COMPLETED',
        'payment_method': 'qr',
        'payment_provider': 'mollie',
        'payment_status': 'pending',
      };
      expect(mapLooksCanonicallyPaid(restored), isFalse);
      expect(
        resolveCanonicalRidePaidDisplay(bookingRecord: restored),
        CanonicalRidePaidDisplay.unpaid,
      );
    });

    test('a verified provider settlement reads as paid', () {
      expect(
        resolveCanonicalRideIsPaid(
          bookingRecord: <String, dynamic>{
            'payment_status': 'paid',
            'payment_provider': 'mollie',
            'mollie': <String, dynamic>{'status': 'paid'},
          },
        ),
        isTrue,
      );
    });

    test('an audited in-car cash confirmation reads as paid', () {
      expect(
        resolveCanonicalRideIsPaid(
          bookingRecord: <String, dynamic>{
            'payment_status': 'paid',
            'payment_method': 'cash',
            'payment_source': 'in_car',
            'paid_by_driver_id': 'drv_1786881253086',
            'paid_at': '2026-09-19T09:42:11.000Z',
          },
        ),
        isTrue,
      );
    });

    test('a double webhook is idempotent on the display side', () {
      final once = <String, dynamic>{
        'payment_status': 'paid',
        'paid_at': '2026-09-19T09:42:11.000Z',
      };
      final twice = Map<String, dynamic>.from(once);
      expect(
        resolveCanonicalRidePaidDisplay(bookingRecord: once),
        resolveCanonicalRidePaidDisplay(bookingRecord: twice),
      );
    });
  });
}
