/// Reads the payment part of a `POST /book` response.
///
/// The worker answers every booking surface with the same fields, so the keys
/// to look at, and which checkout links are safe to send a customer to, belong
/// in one place rather than in each surface that books a ride.
///
/// Pure Dart — no Flutter imports.
library;

/// Whether a checkout link may be handed to a customer.
///
/// Only https, and never an internal host: a booking response is the wrong
/// place to learn about the deployment behind it.
bool isCustomerSafeCheckoutUrl(String value) {
  final url = value.trim();
  if (url.isEmpty) return false;
  final uri = Uri.tryParse(url);
  if (uri == null || !uri.hasScheme || !uri.hasAuthority) return false;
  final scheme = uri.scheme.toLowerCase();
  if (scheme != 'https') return false;
  final host = uri.host.toLowerCase();
  if (host.contains('workers.dev') ||
      host.contains('localhost') ||
      host.contains('127.0.0.1')) {
    return false;
  }
  return true;
}

Map<String, dynamic> _bookingObject(Map<String, dynamic> body) {
  final booking = body['booking'];
  return booking is Map
      ? booking.map((key, value) => MapEntry(key.toString(), value))
      : const <String, dynamic>{};
}

String _firstNonEmpty(Map<String, dynamic> body, List<String> keys) {
  final booking = _bookingObject(body);
  for (final key in keys) {
    for (final source in <Map<String, dynamic>>[body, booking]) {
      final text = (source[key] ?? '').toString().trim();
      if (text.isNotEmpty) return text;
    }
  }
  return '';
}

/// Hosted checkout link the worker created for this booking, or `''`.
///
/// Returns only links that pass [isCustomerSafeCheckoutUrl].
String bookingCheckoutUrl(Map<String, dynamic> body) {
  final url = _firstNonEmpty(body, const <String>[
    'checkoutUrl',
    'checkout_url',
    'paymentUrl',
    'payment_url',
  ]);
  return isCustomerSafeCheckoutUrl(url) ? url : '';
}

/// Id the payment lifecycle is tracked under, or `''` for an unpaid booking.
String bookingPaymentBookingId(Map<String, dynamic> body) {
  return _firstNonEmpty(body, const <String>[
    'paymentBookingId',
    'payment_booking_id',
  ]);
}

/// Public booking reference the customer sees, or `''`.
String bookingPublicReference(Map<String, dynamic> body) {
  return _firstNonEmpty(body, const <String>[
    'public_reference',
    'publicReference',
    'public_booking_id',
    'publicBookingId',
  ]);
}
