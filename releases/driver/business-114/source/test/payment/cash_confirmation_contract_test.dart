// Pre-deploy safety check on the client side — the driver receipt keeps an
// authorized "cash received" action, and no screen turns a chosen method into
// Paid by itself.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/payment/canonical_ride_paid.dart';

String read(String relativePath) =>
    File(relativePath).readAsStringSync().replaceAll('\r\n', '\n');

void main() {
  late String receiptSource;
  late String bookingViewSource;

  setUpAll(() {
    receiptSource = read('lib/main_parts/ride_receipt_body_state.dart');
    bookingViewSource = read('lib/main_parts/customer_booking_view.dart');
  });

  group('the authorized cash action still exists', () {
    test('the receipt offers a cash-received action that posts to the backend', () {
      expect(receiptSource, contains("_receiptText('cashReceived')"));
      expect(
        receiptSource,
        contains("_persistInCarPayment(context: context, method: 'cash')"),
      );
    });

    test('the confirmation is authenticated and carries an audit trail', () {
      expect(receiptSource, contains('resolveInCarPaymentAuthHeaders'));
      expect(receiptSource, contains('InCarPaymentAuthMode.none'));
      expect(receiptSource, contains("'payment_status': 'paid'"));
      expect(receiptSource, contains("'paid_by_driver_id': kDriverId"));
      expect(receiptSource, contains("'paid_at': paidAtIso"));
      expect(receiptSource, contains("'payment_source': 'in_car'"));
    });
  });

  group('choosing a method never implies payment', () {
    test('the customer view no longer derives paid from the method', () {
      expect(bookingViewSource, isNot(contains('_methodImpliesPaid')));
      expect(
        bookingViewSource,
        contains("bool get isPaid => rawPaymentStatus == 'paid';"),
      );
    });

    test('an in-car method without a settlement reads as unpaid', () {
      for (final method in <String>['cash', 'bancontact', 'qr', 'card']) {
        expect(
          resolveCanonicalRideIsPaid(
            bookingRecord: <String, dynamic>{
              'status': 'COMPLETED',
              'payment_method': method,
              'payment_status': 'unpaid',
            },
          ),
          isFalse,
          reason: '$method chosen but not collected must stay unpaid',
        );
      }
    });

    test('a driver-confirmed cash ride reads as paid', () {
      expect(
        resolveCanonicalRideIsPaid(
          bookingRecord: <String, dynamic>{
            'status': 'COMPLETED',
            'payment_method': 'cash',
            'payment_status': 'paid',
            'payment_source': 'in_car',
            'payment_provider': 'manual',
            'paid_by_driver_id': 'drv_1786881253086',
            'paid_at': '2026-09-19T09:42:11.000Z',
          },
        ),
        isTrue,
      );
    });

    test('a verified online payment reads as paid', () {
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
  });
}
