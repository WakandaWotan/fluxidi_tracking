import 'package:flutter/material.dart';
import 'package:fluxidi_tracking/app_config.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_entry.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_flow.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_labels.dart';

Future<T?> openCustomerBookingFlow<T>(
  BuildContext context, {
  required CustomerBookingEntryContext entry,
  String? bookingBaseUrl,
  AppLanguage? language,
  WidgetBuilder? onGoToStartPage,
}) {
  return Navigator.of(context).push<T>(
    MaterialPageRoute<T>(
      builder: (_) => CustomerBookingFlow(
        entry: entry,
        bookingBaseUrl: bookingBaseUrl ?? kBookingBaseUrl,
        language: language ?? appConfig.currentLanguage,
        onGoToStartPage: onGoToStartPage,
      ),
    ),
  );
}

LocalizedText customerBookingTitleFor(CustomerBookingEntryContext entry) {
  switch (entry.kind) {
    case CustomerBookingKind.airport:
      return kCustomerBookingAirportTitle;
    case CustomerBookingKind.event:
      return kCustomerBookingEventTitle;
    case CustomerBookingKind.stay:
      return kCustomerBookingStayTitle;
    case CustomerBookingKind.business:
      return kCustomerBookingBusinessTitle;
    case CustomerBookingKind.companyPage:
    case CustomerBookingKind.bookingLink:
    case CustomerBookingKind.qr:
      return kCustomerBookingCompanyTitle;
    case CustomerBookingKind.taxi:
      return kCustomerBookingTaxiTitle;
  }
}
