import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/customer_booking/customer_bootstrap_record.dart';
import 'package:fluxidi_tracking/customer_booking/customer_payment_display.dart';

void main() {
  test('bootstrap list items carry ride status, payment and public reference', () {
    final stored = storedCustomerBookingFromBootstrapItem(
      item: <String, dynamic>{
        'booking_id': 'bk_internal_51',
        'public_booking_reference': '2026-09-000051',
        'status': 'PENDING',
        'payment_status': 'unpaid',
        'payment_method': 'qr_code',
        'from': 'Koekamerstraat 48',
        'to': 'Brussels Airport',
        'pickup_iso': '2026-09-30T16:27:00.000Z',
        'price': 143.90,
        'currency': 'EUR',
      },
    );

    expect(stored, isNotNull);
    expect(stored!.bookingId, 'bk_internal_51');
    expect(stored.publicReference, '2026-09-000051');
    expect(stored.publicBookingId, '2026-09-000051');
    expect(stored.status, 'PENDING');
    expect(stored.paymentStatus, 'unpaid');
    expect(stored.paymentMethod, 'qr_code');
    expect(
      resolveCustomerPaymentDisplayToken(
        paymentStatus: stored.paymentStatus,
        paymentMethod: stored.paymentMethod,
        paymentMode: stored.paymentMode,
      ),
      CustomerPaymentDisplayTokens.payInCar,
    );
  });

  test('bootstrap does not invent paid or confirmed from missing fields', () {
    final stored = storedCustomerBookingFromBootstrapItem(
      item: <String, dynamic>{
        'booking_id': 'bk_internal_50',
        'public_booking_reference': '2026-09-000050',
        'status': 'PENDING',
        'payment_status': 'unpaid',
      },
    );

    expect(stored, isNotNull);
    expect(stored!.status, 'PENDING');
    expect(stored.paymentStatus, 'unpaid');
    expect(
      resolveCustomerPaymentDisplayToken(
        paymentStatus: stored.paymentStatus,
        paymentMethod: stored.paymentMethod,
        paymentMode: stored.paymentMode,
      ),
      isNot(CustomerPaymentDisplayTokens.paid),
    );
  });
}
