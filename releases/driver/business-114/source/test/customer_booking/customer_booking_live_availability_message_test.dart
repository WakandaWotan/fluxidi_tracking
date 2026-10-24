import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_labels.dart';
void main() {
 test('live availability copy distinguishes presence from capacity or ownership errors', () {
  for(final reason in ['assignment_driver_not_live','live_location_unavailable']) {
   final message=customerBookingLiveAvailabilityMessage([reason,'active_ride_end_unknown']);
   expect(message,isNotNull);
   for(final language in AppLanguage.values) expect(message!.of(language),isNotEmpty);
  }
  for(final reason in ['assignment_capacity','assignment_driver_not_scheduled','active_ride_end_unknown','']) {
   expect(customerBookingLiveAvailabilityMessage([reason]),isNull);
  }
 });
}
