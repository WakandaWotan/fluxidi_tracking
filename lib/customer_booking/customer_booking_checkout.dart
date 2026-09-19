// Checkout after POST /book. Same worker fields as airport and limousine.

import 'package:fluxidi_tracking/payment/booking_checkout_response.dart';

class CustomerBookingCheckoutPlan {
  const CustomerBookingCheckoutPlan({
    required this.requiredCheckout,
    required this.hasSafeUrl,
    required this.checkoutUrl,
    required this.paymentBookingId,
    required this.publicReference,
  });

  const CustomerBookingCheckoutPlan.manual()
    : requiredCheckout = false,
      hasSafeUrl = false,
      checkoutUrl = '',
      paymentBookingId = '',
      publicReference = '';

  final bool requiredCheckout;
  final bool hasSafeUrl;
  final String checkoutUrl;
  final String paymentBookingId;
  final String publicReference;

  bool get canOpen => requiredCheckout && hasSafeUrl;
}

CustomerBookingCheckoutPlan customerBookingCheckoutPlan({
  required bool isMollieCheckout,
  required Map<String, dynamic> response,
}) {
  if (!isMollieCheckout) {
    return const CustomerBookingCheckoutPlan.manual();
  }
  final checkoutUrl = bookingCheckoutUrl(response);
  return CustomerBookingCheckoutPlan(
    requiredCheckout: true,
    hasSafeUrl: checkoutUrl.isNotEmpty,
    checkoutUrl: checkoutUrl,
    paymentBookingId: bookingPaymentBookingId(response),
    publicReference: bookingPublicReference(response),
  );
}

String customerBookingStoredPaymentStatus({
  required bool isMollieCheckout,
  required Map<String, dynamic> response,
}) {
  final booking = response['booking'] is Map
      ? Map<String, dynamic>.from(response['booking'] as Map)
      : const <String, dynamic>{};
  for (final value in <dynamic>[
    response['payment_status'],
    response['paymentStatus'],
    booking['payment_status'],
    booking['paymentStatus'],
  ]) {
    final text = (value ?? '').toString().trim().toLowerCase();
    if (text.isEmpty || text == 'null') continue;
    // Ride lifecycle tokens are not a Mollie settlement.
    if (text == 'completed' || text == 'confirmed') continue;
    return text;
  }
  return isMollieCheckout ? 'pending' : 'unpaid';
}
