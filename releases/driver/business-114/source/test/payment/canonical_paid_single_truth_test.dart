// Dossier 02 — one canonical payment truth on the client.
//
// Only a verified provider settlement may read as Paid. A completed ride, a
// chosen method, a return from checkout, an app restart or a double webhook
// must never produce Paid on their own.

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/payment/canonical_ride_paid.dart';

Map<String, dynamic> booking({
  required String paymentStatus,
  String? method,
  String? mollieStatus,
  String? paidAt,
  String rideStatus = 'COMPLETED',
}) {
  return <String, dynamic>{
    'booking_id': 'bk_pln_2026_000431',
    'status': rideStatus,
    'payment_status': paymentStatus,
    if (method != null) 'payment_method': method,
    if (mollieStatus != null) 'mollie': <String, dynamic>{'status': mollieStatus},
    if (paidAt != null) 'paid_at': paidAt,
  };
}

void main() {
  group('only a verified provider paid is paid', () {
    test('a verified Mollie paid is paid', () {
      expect(isCanonicalPaidStatusValue('paid'), isTrue);
      expect(
        resolveCanonicalRideIsPaid(
          bookingRecord: booking(paymentStatus: 'paid', mollieStatus: 'paid'),
        ),
        isTrue,
      );
    });

    test('completed, confirmed, success, succeeded, captured and settled are not paid', () {
      for (final token in <String>[
        'completed',
        'confirmed',
        'success',
        'succeeded',
        'captured',
        'settled',
      ]) {
        expect(
          isCanonicalPaidStatusValue(token),
          isFalse,
          reason: '$token must not read as paid',
        );
      }
    });
  });

  group('the observed PLN-2026-000431 chain', () {
    test('a completed ride with an unconfirmed Mollie payment is not paid', () {
      final record = booking(
        paymentStatus: 'open',
        method: 'bancontact',
        mollieStatus: 'open',
      );
      expect(
        resolveCanonicalRidePaidDisplay(bookingRecord: record),
        CanonicalRidePaidDisplay.unpaid,
      );
      expect(mapLooksCanonicallyPaid(record), isFalse);
    });

    test('a Billit document on the record does not make it paid', () {
      final record = booking(
        paymentStatus: 'open',
        method: 'bancontact',
        mollieStatus: 'open',
      )..['billit'] = <String, dynamic>{'invoice_id': 'BILLIT-2026-000431'};
      expect(mapLooksCanonicallyPaid(record), isFalse);
    });
  });

  group('every unpaid provider state stays visibly unpaid', () {
    for (final entry in <String, String>{
      'pending': 'pending',
      'open': 'open',
      'authorized': 'authorized',
      'processing': 'processing',
    }.entries) {
      test('${entry.key} is unpaid', () {
        expect(isCanonicalPaidStatusValue(entry.value), isFalse);
        expect(isCanonicalUnpaidStatusValue(entry.value), isTrue);
        expect(
          resolveCanonicalRidePaidDisplay(
            bookingRecord: booking(paymentStatus: entry.value),
          ),
          CanonicalRidePaidDisplay.unpaid,
        );
      });
    }

    for (final token in <String>['failed', 'canceled', 'cancelled', 'declined']) {
      test('$token is terminal and not paid', () {
        expect(isCanonicalPaidStatusValue(token), isFalse);
        expect(isCanonicalTerminalNonPaidStatusValue(token), isTrue);
        expect(
          resolveCanonicalRidePaidDisplay(
            bookingRecord: booking(paymentStatus: token),
          ),
          CanonicalRidePaidDisplay.unpaid,
        );
      });
    }
  });

  test('an in-car method without settlement is not paid', () {
    for (final method in <String>['cash', 'bancontact', 'qr', 'card']) {
      expect(
        resolveCanonicalRideIsPaid(
          bookingRecord: booking(paymentStatus: 'open', method: method),
        ),
        isFalse,
        reason: '$method is a choice, not a payment',
      );
    }
  });

  test('a return from checkout without a webhook stays unpaid', () {
    final afterReturn = booking(
      paymentStatus: 'open',
      method: 'bancontact',
      mollieStatus: 'open',
    );
    expect(resolveCanonicalRideIsPaid(bookingRecord: afterReturn), isFalse);
  });

  test('an app restart re-reads the same unpaid record', () {
    final stored = booking(paymentStatus: 'open', mollieStatus: 'open');
    final afterRestart = Map<String, dynamic>.from(stored);
    expect(resolveCanonicalRideIsPaid(bookingRecord: afterRestart), isFalse);
  });

  test('a double webhook for one payment keeps exactly one paid outcome', () {
    final first = booking(paymentStatus: 'paid', mollieStatus: 'paid');
    final second = Map<String, dynamic>.from(first);
    expect(resolveCanonicalRideIsPaid(bookingRecord: first), isTrue);
    expect(resolveCanonicalRideIsPaid(bookingRecord: second), isTrue);
  });

  test('a paid overlay never regresses to unpaid, and an unpaid one never invents paid', () {
    final paidTarget = <String, dynamic>{'payment_status': 'paid'};
    final stalePending = <String, dynamic>{'payment_status': 'open'};
    final keptPaid = overlayCanonicalPaymentFields(paidTarget, stalePending);
    expect(keptPaid['payment_status'], 'paid');

    final pendingTarget = <String, dynamic>{'payment_status': 'open'};
    final completedOverlay = <String, dynamic>{'payment_status': 'completed'};
    final stillNotPaid = overlayCanonicalPaymentFields(
      pendingTarget,
      completedOverlay,
    );
    expect(mapLooksCanonicallyPaid(stillNotPaid), isFalse);
  });

  test('a refund after payment wins over the paid history row', () {
    expect(
      resolveCanonicalRidePaidDisplay(
        bookingRecord: booking(paymentStatus: 'refunded'),
        historyDetails: <String, dynamic>{'payment_status': 'paid'},
      ),
      CanonicalRidePaidDisplay.unpaid,
    );
  });
}
