import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_checkout.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_labels.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_submit.dart';
import 'package:fluxidi_tracking/payment/payment_booking_selection.dart';
import 'package:fluxidi_tracking/payment/payment_method_catalog.dart';

void main() {
  test('Bancontact after /book uses the Mollie checkout link', () {
    final selection = BookingPaymentSelection.fromMethodId(
      PaymentMethodIds.bancontact,
    );
    expect(selection.isMollieCheckout, isTrue);
    final plan = customerBookingCheckoutPlan(
      isMollieCheckout: selection.isMollieCheckout,
      response: const <String, dynamic>{
        'ok': true,
        'booking_id': 'B-76',
        'payment_booking_id': 'PB-76',
        'public_reference': 'FLX-76',
        'checkout_url': 'https://www.mollie.com/checkout/select-method/abc',
        'payment_status': 'open',
      },
    );
    expect(plan.canOpen, isTrue);
    expect(
      plan.checkoutUrl,
      'https://www.mollie.com/checkout/select-method/abc',
    );
    expect(plan.paymentBookingId, 'PB-76');
    expect(
      customerBookingStoredPaymentStatus(
        isMollieCheckout: true,
        response: const <String, dynamic>{'payment_status': 'open'},
      ),
      'open',
    );
  });

  test('a missing checkout link is a start failure, not a confirmed booking', () {
    final plan = customerBookingCheckoutPlan(
      isMollieCheckout: true,
      response: const <String, dynamic>{
        'ok': true,
        'booking_id': 'B-76',
        'payment_booking_id': 'PB-76',
      },
    );
    expect(plan.requiredCheckout, isTrue);
    expect(plan.hasSafeUrl, isFalse);
    expect(
      customerBookingBookIssueFromRaw('checkout_url_missing'),
      kCustomerBookingIssueCheckoutStart,
    );
    expect(
      customerBookingSubmitIssueText(
        kCustomerBookingIssueCheckoutStart,
        AppLanguage.en,
      ),
      kCustomerBookingCheckoutStart.en,
    );
  });

  test('in-vehicle stays unpaid until collection, without opening Mollie', () {
    final selection = BookingPaymentSelection.fromMethodId(
      PaymentMethodIds.inVehicleCard,
    );
    expect(selection.isMollieCheckout, isFalse);
    final plan = customerBookingCheckoutPlan(
      isMollieCheckout: selection.isMollieCheckout,
      response: const <String, dynamic>{'ok': true, 'booking_id': 'B-1'},
    );
    expect(plan.requiredCheckout, isFalse);
    expect(
      customerBookingStoredPaymentStatus(
        isMollieCheckout: false,
        response: const <String, dynamic>{'status': 'CONFIRMED'},
      ),
      'unpaid',
    );
  });

  test('ride completed is not stored as paid', () {
    expect(
      customerBookingStoredPaymentStatus(
        isMollieCheckout: false,
        response: const <String, dynamic>{
          'status': 'completed',
          'payment_status': 'completed',
        },
      ),
      'unpaid',
    );
  });
}
