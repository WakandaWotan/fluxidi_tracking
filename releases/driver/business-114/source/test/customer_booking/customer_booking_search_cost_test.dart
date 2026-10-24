import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_quote_wire.dart';

void main() {
  test('search limits and unverified areas are not shown as missing taxis', () {
    expect(customerBookingQuoteIssueFromRaw('rate_limited'), 'search_rate_limited');
    for (final code in ['booking_area_unverified', 'booking_area_unconfigured',
      'search_admission_unavailable', 'official_address_index_unavailable']) {
      expect(customerBookingQuoteIssueFromRaw(code), 'search_area_unverified');
      expect(customerBookingQuoteErrorText(code, AppLanguage.nl), contains('niet controleren'));
    }
    expect(customerBookingQuoteIssueFromRaw('booking_area_not_served'), 'search_company_unavailable');
    expect(customerBookingQuoteIssueFromRaw('StateError: official_address_position_changed'), kCustomerBookingIssueNeedRoute);
    for (final language in AppLanguage.values) {
      expect(customerBookingQuoteErrorText('rate_limited', language), isNotEmpty);
      expect(customerBookingQuoteErrorText('booking_area_unverified', language), isNotEmpty);
      expect(customerBookingQuoteErrorText('booking_area_not_served', language), isNotEmpty);
    }
  });
}
