import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:fluxidi_tracking/customer_booking/customer_booking_book_result.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_quote_wire.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_submit.dart';

void main() {
  test('company mission exceptions use existing quote request outcome with reason intact', () {
    for (final reason in ['exception_day', 'ambiguous_distance_band', 'vehicle_tariff_missing']) {
      final error = customerBookingBookExceptionFromResponse(
        res: http.Response('', 409),
        decoded: {'error': 'company_mission_quote_required',
          'request_quote_required': true, 'reason': reason},
      );
      expect(error.statusCode, 409);
      expect(error.quoteReason, reason);
      expect(error.uncertain, false);
      expect(customerBookingBookIssueFromException(error),
        kCustomerBookingIssueRequestQuoteRequired);
      expect(customerBookingQuoteIssueFromRaw(error.raw),
        kCustomerBookingIssueRequestQuoteRequired);
    }
  });
  test('legacy quote request and ordinary failures stay distinct', () {
    final legacy = customerBookingBookExceptionFromResponse(
      res: http.Response('', 409),
      decoded: {'error': 'request_quote_required', 'reason': 'airport_outside_work_area'},
    );
    expect(legacy.quoteReason, 'airport_outside_work_area');
    expect(customerBookingBookIssueFromException(legacy), kCustomerBookingIssueRequestQuoteRequired);
    expect(customerBookingBookIssueFromRaw('payment_checkout_unavailable'),
      isNot(kCustomerBookingIssueRequestQuoteRequired));
    expect(customerBookingQuoteIssueFromRaw('route_failed'),
      isNot(kCustomerBookingIssueRequestQuoteRequired));
  });
}
