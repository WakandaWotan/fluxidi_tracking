import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/company/company_plan_quote.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_book_payload.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_entry.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_submit.dart';
import 'package:fluxidi_tracking/payment/payment_booking_selection.dart';
import 'package:fluxidi_tracking/payment/payment_method_catalog.dart';
import 'package:fluxidi_tracking/payment_return.dart';

void main() {
  test('Bancontact taxi and airport send the same Mollie return contract', () {
    final selection = BookingPaymentSelection.fromMethodId(
      PaymentMethodIds.bancontact,
    );
    const quote = CompanyPlanQuoteResult(
      fingerprint: 'q-10',
      distanceKm: 3.2,
      durationMin: 8,
      priceAvailable: true,
      priceInclVat: 10.10,
      currency: 'EUR',
    );
    final taxi = customerBookingBookContractFields(
      selection: selection,
      kind: CustomerBookingKind.taxi,
      quote: quote,
    );
    final airport = customerBookingBookContractFields(
      selection: selection,
      kind: CustomerBookingKind.airport,
      quote: quote,
    );
    for (final body in <Map<String, dynamic>>[taxi, airport]) {
      expect(body['payment_mode'], 'mollie');
      expect(body['payment_method'], PaymentMethodIds.bancontact);
      expect(body['mollie_method'], 'bancontact');
      expect(body['return_url'], kFluxidiPaymentReturnUrl);
      expect(body['returnUrl'], kFluxidiPaymentReturnUrl);
      expect(body['booking_source'], kCustomerBookingBookSource);
      expect(body['entry_channel'], kCustomerBookingBookChannel);
      expect((body['quote'] as Map)['price_incl_vat'], 10.10);
    }
    expect(taxi['entry_kind'], 'taxi');
    expect(airport['entry_kind'], 'airport');
  });

  test('cash never asks Mollie and still carries the return url field', () {
    final body = customerBookingBookContractFields(
      selection: BookingPaymentSelection.fromMethodId(
        PaymentMethodIds.inVehicleCard,
      ),
      kind: CustomerBookingKind.taxi,
    );
    expect(body['payment_mode'], 'manual');
    expect(body.containsKey('mollie_method'), isFalse);
    expect(body['return_url'], kFluxidiPaymentReturnUrl);
    expect(body.containsKey('quote'), isFalse);
  });

  test('a missing checkout is a start failure, not a paid booking', () {
    expect(
      customerBookingBookIssueFromRaw('payment_checkout_unavailable'),
      kCustomerBookingIssueCheckoutStart,
    );
    expect(
      customerBookingBookIssueFromRaw('Mollie payment failed'),
      kCustomerBookingIssuePayment,
    );
  });
}
