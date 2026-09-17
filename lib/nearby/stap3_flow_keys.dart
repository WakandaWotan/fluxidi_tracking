import 'package:flutter/foundation.dart';

const Key kRoleEntryCustomerKey = Key('role_entry_customer');
const Key kRoleEntryBusinessKey = Key('role_entry_business');
const Key kRoleEntryDriverKey = Key('role_entry_driver');
const Key kRoleEntryCarouselBackgroundKey = Key(
  'role_entry_carousel_background',
);

Key roleEntryCarouselIndexKey(int index) =>
    Key('role_entry_carousel_index_$index');
const Key kCustomerEntryNewKey = Key('customer_entry_new');
const Key kCustomerOnboardingLaterKey = Key('customer_onboarding_later');
const Key kCustomerHomeTaxisNavKey = Key('customer_home_taxis_nav');
const Key kNearbyPostalCodeFieldKey = Key('nearby_postal_code_field');
const Key kNearbySearchPartnersKey = Key('nearby_search_partners');
const Key kCalculatorFromFieldKey = Key('calculator_from_field');
const Key kCalculatorTierFieldKey = Key('calculator_tier_field');
const Key kCalculatorPickupTimeKey = Key('calculator_pickup_time');
const Key kCalculatorQuoteKey = Key('calculator_quote');
const Key kCalculatorBookKey = Key('calculator_book');
const Key kBookingConfirmNameKey = Key('booking_confirm_name');
const Key kBookingConfirmPhoneKey = Key('booking_confirm_phone');
const Key kBookingConfirmEmailKey = Key('booking_confirm_email');
const Key kBookingConfirmButtonKey = Key('booking_confirm_button');
const Key kFluxidiBackToStartKey = Key('fluxidi_back_to_start');
const Key kCompanyBookingDetailRouteKey = Key('company_booking_detail_route');
const Key kCompanyBookingDetailAmountKey = Key('company_booking_detail_amount');
const Key kPartnerPublicProfileScrollKey = Key('partner_public_profile_scroll');

const String kStap3DesktopItCustomerName = 'Stap3DesktopIt';
const String kStap3DesktopItPhone = '+32470111222';
const String kStap3DesktopItEmail = 'stap3.desktop.it@demolocal.example';
const String kStap3DesktopItPickupQuery = 'Koekamerstraat 48A, 9688 Schorisse';
const String kStap3MaarkedalRonseRuleId = 'fx_1789315937284';
const String kStap3LocalPartnerId = 'company:demo_company_p0:demo_company_p0';

Key nearbyPartnerProfileKey(String partnerId) =>
    Key('nearby_partner_profile_${partnerId.trim()}');

Key calculatorPlaceSuggestionKey(String label) =>
    Key('calculator_place_suggestion_${label.trim()}');

Key companyBookingRowKey(String bookingId) =>
    Key('company_booking_row_${bookingId.trim()}');
