import 'package:flutter/widgets.dart';

const Key kCustomerBookingFlowKey = Key('customer_booking_flow');
const Key kCustomerBookingTitleKey = Key('customer_booking_title');
const Key kCustomerBookingAirplaneVisualKey = Key(
  'customer_booking_airplane_visual',
);
const Key kCustomerBookingStreetModeKey = Key('customer_booking_mode_street');
const Key kCustomerBookingAirportModeKey = Key('customer_booking_mode_airport');
const Key kCustomerBookingToAirportKey = Key('customer_booking_to_airport');
const Key kCustomerBookingFromAirportKey = Key('customer_booking_from_airport');
const Key kCustomerBookingBrowseAllAirportsKey = Key(
  'customer_booking_browse_all_airports',
);
const Key kCustomerBookingChooseCountryKey = Key(
  'customer_booking_choose_country',
);
const Key kCustomerBookingChooseAirportKey = Key(
  'customer_booking_choose_airport',
);
const Key kCustomerBookingAirportSearchKey = Key(
  'customer_booking_airport_search',
);
const Key kCustomerBookingAirportSummaryKey = Key(
  'customer_booking_airport_summary',
);
const Key kCustomerBookingPickupKey = Key('customer_booking_pickup');
const Key kCustomerBookingDropoffKey = Key('customer_booking_dropoff');
const Key kCustomerBookingAddStopKey = Key('customer_booking_add_stop');
const Key kCustomerBookingNowKey = Key('customer_booking_when_now');
const Key kCustomerBookingLaterKey = Key('customer_booking_when_later');
const Key kCustomerBookingDateKey = Key('customer_booking_date');
const Key kCustomerBookingTimeKey = Key('customer_booking_time');
const Key kCustomerBookingLaterInvalidKey = Key(
  'customer_booking_later_invalid',
);
const Key kCustomerBookingOneWayKey = Key('customer_booking_one_way');
const Key kCustomerBookingReturnNoWaitKey = Key(
  'customer_booking_return_no_wait',
);
const Key kCustomerBookingReturnWaitKey = Key('customer_booking_return_wait');
const Key kCustomerBookingConfirmKey = Key('customer_booking_confirm');
const Key kCustomerBookingGpsFallbackKey = Key('customer_booking_gps_fallback');
const Key kCustomerBookingAddressConfirmKey = Key(
  'customer_booking_address_confirm',
);
const Key kCustomerBookingAddressConfirmMapKey = Key(
  'customer_booking_address_confirm_map',
);
const Key kCustomerBookingVehiclesNeedRideKey = Key(
  'customer_booking_vehicles_need_ride',
);
const Key kCustomerBookingQuoteStatusKey = Key('customer_booking_quote_status');
const Key kCustomerBookingQuoteRetryKey = Key('customer_booking_quote_retry');
const Key kCustomerBookingPriceKey = Key('customer_booking_price');
const Key kCustomerBookingMapKey = Key('customer_booking_map');
const Key kCustomerBookingFormKey = Key('customer_booking_form');
const Key kCustomerBookingWideSplitKey = Key('customer_booking_wide_split');
const Key kCustomerBookingNarrowStackKey = Key('customer_booking_narrow_stack');
const Key kCustomerBookingFitRouteKey = Key('customer_booking_fit_route');
const Key kCustomerBookingRouteCanvasKey = Key('customer_booking_route_canvas');
const Key kCustomerBookingTripSummaryKey = Key('customer_booking_trip_summary');
const Key kCustomerBookingFlightNumberKey = Key(
  'customer_booking_flight_number',
);
const Key kCustomerBookingFlightWhenKey = Key('customer_booking_flight_when');
const Key kCustomerBookingLandingHintKey = Key(
  'customer_booking_landing_hint',
);
const Key kCustomerBookingCompanyLockKey = Key('customer_booking_company_lock');
const Key kCustomerBookingCompanyBannerKey = Key(
  'customer_booking_company_banner',
);
const Key kCustomerBookingExampleBadgeKey = Key(
  'customer_booking_example_badge',
);
const Key kCustomerBookingExampleNoticeKey = Key(
  'customer_booking_example_notice',
);
const Key kCustomerBookingCompanyChangeKey = Key(
  'customer_booking_company_change',
);
const Key kCustomerBookingCompanyChooseKey = Key(
  'customer_booking_company_choose',
);
const Key kCustomerBookingSuccessKey = Key('customer_booking_success');
const Key kCustomerBookingContextErrorKey = Key(
  'customer_booking_context_error',
);

Key customerBookingAirportCardKey(String iata) {
  return Key('customer_booking_airport_card_${iata.trim().toLowerCase()}');
}

Key customerBookingAirportListKey(String iata) {
  return Key('customer_booking_airport_list_${iata.trim().toLowerCase()}');
}

Key customerBookingCountryKey(String countryCode) {
  return Key('customer_booking_country_${countryCode.trim().toLowerCase()}');
}

Key customerBookingStopKey(int index) {
  return Key('customer_booking_stop_$index');
}

Key customerBookingVehicleKey(String type) {
  return Key('customer_booking_vehicle_${type.trim().toLowerCase()}');
}

Key customerBookingWaitChipKey(int minutes) {
  return Key('customer_booking_wait_$minutes');
}

const Key kCustomerBookingPaxIncKey = Key('customer_booking_pax_inc');
const Key kCustomerBookingBagsIncKey = Key('customer_booking_bags_inc');
const Key kCustomerBookingSubmitErrorKey = Key('customer_booking_submit_error');
const Key kCustomerBookingMyAddressKey = Key('customer_booking_my_address');
const Key kCustomerBookingUseLocationKey = Key('customer_booking_use_location');
const Key kCustomerBookingVehicleHintKey = Key('customer_booking_vehicle_hint');
const Key kCustomerBookingNameKey = Key('customer_booking_name');
const Key kCustomerBookingPhoneKey = Key('customer_booking_phone');
const Key kCustomerBookingSubmittingKey = Key('customer_booking_submitting');
const Key kCustomerBookingAirportChromeKey = Key(
  'customer_booking_airport_chrome',
);
const Key kCustomerBookingPrivateRideKey = Key('customer_booking_ride_private');
const Key kCustomerBookingBusinessRideKey = Key(
  'customer_booking_ride_business',
);
const Key kCustomerBookingPaymentPageKey = Key('customer_booking_payment_page');
const Key kCustomerBookingPaymentConfirmKey = Key(
  'customer_booking_payment_confirm',
);
const Key kCustomerBookingPaymentUnavailableKey = Key(
  'customer_booking_payment_unavailable',
);
const Key kCustomerBookingVehiclesLoadingKey = Key(
  'customer_booking_vehicles_loading',
);
const Key kCustomerBookingVehiclesFailedKey = Key(
  'customer_booking_vehicles_failed',
);

Key customerBookingPaymentMethodKey(String methodId) {
  return Key('customer_booking_payment_${methodId.trim().toLowerCase()}');
}
