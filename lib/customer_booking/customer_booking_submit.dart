// Customer booking submit checks. Does not invent missing fields or fares.

import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/company/company_plan_quote.dart';
import 'package:fluxidi_tracking/company/company_plan_when.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_labels.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_quote_wire.dart';
import 'package:fluxidi_tracking/limousine/limousine_address_lookup.dart';

const String kCustomerBookingIssueNeedPickup = 'need_pickup';
const String kCustomerBookingIssueNeedDropoff = 'need_dropoff';
const String kCustomerBookingIssueNeedName = 'need_name';
const String kCustomerBookingIssueNeedPhone = 'need_phone';
const String kCustomerBookingIssueNeedQuote = 'need_quote';
const String kCustomerBookingIssueAlreadyBooked = 'already_booked';
const String kCustomerBookingIssueBookFailed = 'book_failed';
const String kCustomerBookingIssueUnavailable = 'vehicle_unavailable';
const String kCustomerBookingIssuePayment = 'payment_failed';
const String kCustomerBookingIssueCheckoutStart = 'checkout_start_failed';
const String kCustomerBookingIssueNetwork = 'network_failed';

class CustomerBookingSubmitIssue {
  const CustomerBookingSubmitIssue({
    required this.code,
    required this.focusKey,
  });

  final String code;
  final String focusKey;
}

bool customerBookingAddressReady(LimousineAddressValue value) {
  return value.isRouteReady && value.routeText.trim().isNotEmpty;
}

List<CustomerBookingSubmitIssue> customerBookingSubmitIssues({
  required bool hasCompany,
  required LimousineAddressValue pickup,
  required LimousineAddressValue dropoff,
  required bool whenNow,
  required DateTime? pickupLocal,
  required String name,
  required String phone,
  required bool quoteLoading,
  required CompanyPlanQuoteResult? quote,
  required String? quoteError,
  required String? successId,
}) {
  if ((successId ?? '').trim().isNotEmpty) {
    return const [
      CustomerBookingSubmitIssue(
        code: kCustomerBookingIssueAlreadyBooked,
        focusKey: 'success',
      ),
    ];
  }
  final issues = <CustomerBookingSubmitIssue>[];
  if (!hasCompany) {
    issues.add(
      const CustomerBookingSubmitIssue(
        code: kCustomerBookingIssueNeedCompany,
        focusKey: 'company',
      ),
    );
  }
  if (!customerBookingAddressReady(pickup)) {
    issues.add(
      const CustomerBookingSubmitIssue(
        code: kCustomerBookingIssueNeedPickup,
        focusKey: 'pickup',
      ),
    );
  }
  if (!customerBookingAddressReady(dropoff)) {
    issues.add(
      const CustomerBookingSubmitIssue(
        code: kCustomerBookingIssueNeedDropoff,
        focusKey: 'dropoff',
      ),
    );
  }
  if (!whenNow && pickupLocal == null) {
    issues.add(
      const CustomerBookingSubmitIssue(
        code: kCustomerBookingIssueNeedWhen,
        focusKey: 'when',
      ),
    );
  } else if (!whenNow &&
      pickupLocal != null &&
      !companyPlanLaterPickupIsValid(pickupLocal)) {
    issues.add(
      const CustomerBookingSubmitIssue(
        code: kCustomerBookingIssueLaterInvalid,
        focusKey: 'when',
      ),
    );
  }
  if (name.trim().isEmpty) {
    issues.add(
      const CustomerBookingSubmitIssue(
        code: kCustomerBookingIssueNeedName,
        focusKey: 'name',
      ),
    );
  }
  if (phone.trim().isEmpty) {
    issues.add(
      const CustomerBookingSubmitIssue(
        code: kCustomerBookingIssueNeedPhone,
        focusKey: 'phone',
      ),
    );
  }
  if (quoteLoading) {
    issues.add(
      const CustomerBookingSubmitIssue(
        code: kCustomerBookingIssueNeedQuote,
        focusKey: 'quote',
      ),
    );
  } else if ((quoteError ?? '').trim().isNotEmpty) {
    issues.add(
      CustomerBookingSubmitIssue(
        code: quoteError!.trim(),
        focusKey: 'quote',
      ),
    );
  } else if (quote == null || !quote.hasRoute) {
    if (customerBookingAddressReady(pickup) &&
        customerBookingAddressReady(dropoff) &&
        (whenNow || pickupLocal != null)) {
      issues.add(
        const CustomerBookingSubmitIssue(
          code: kCustomerBookingIssueNeedQuote,
          focusKey: 'quote',
        ),
      );
    }
  } else if (customerBookingQuotePriceFailed(quote)) {
    issues.add(
      const CustomerBookingSubmitIssue(
        code: kCustomerBookingIssuePriceFailed,
        focusKey: 'quote',
      ),
    );
  }
  return issues;
}

bool customerBookingQuoteIsOnRequest(CompanyPlanQuoteResult quote) {
  return quote.calculatorOff || quote.requestQuoteRequired;
}

bool customerBookingQuotePriceFailed(CompanyPlanQuoteResult quote) {
  if (customerBookingQuoteIsOnRequest(quote) || quote.priceAvailable) {
    return false;
  }
  final amount = quote.displayTotalPrice ?? quote.outboundPriceInclVat;
  if (amount != null && amount > 0) return false;
  return quote.hasRoute;
}

String customerBookingSubmitIssueText(String code, AppLanguage language) {
  switch (code) {
    case kCustomerBookingIssueNeedCompany:
      return kCustomerBookingNeedCompany.of(language);
    case kCustomerBookingIssueNeedPickup:
      return kCustomerBookingNeedPickupField.of(language);
    case kCustomerBookingIssueNeedDropoff:
      return kCustomerBookingNeedDropoffField.of(language);
    case kCustomerBookingIssueNeedWhen:
      return kCustomerBookingNeedWhen.of(language);
    case kCustomerBookingIssueLaterInvalid:
      return kCustomerBookingLaterInvalid.of(language);
    case kCustomerBookingIssueNeedName:
      return kCustomerBookingNeedNameField.of(language);
    case kCustomerBookingIssueNeedPhone:
      return kCustomerBookingNeedPhoneField.of(language);
    case kCustomerBookingIssueNeedQuote:
      return kCustomerBookingNeedQuote.of(language);
    case kCustomerBookingIssuePriceFailed:
      return kCustomerBookingPriceFailed.of(language);
    case kCustomerBookingIssueAlreadyBooked:
      return kCustomerBookingAlreadyBooked.of(language);
    case kCustomerBookingIssueNeedRoute:
      return kCustomerBookingNeedRoute.of(language);
    case kCustomerBookingIssueFailed:
      return kCustomerBookingRouteFailed.of(language);
    case kCustomerBookingIssueUnavailable:
      return kCustomerBookingBookUnavailable.of(language);
    case kCustomerBookingIssuePayment:
      return kCustomerBookingBookPayment.of(language);
    case kCustomerBookingIssueCheckoutStart:
      return kCustomerBookingCheckoutStart.of(language);
    case kCustomerBookingIssueNetwork:
      return kCustomerBookingBookNetwork.of(language);
    default:
      return kCustomerBookingBookFailed.of(language);
  }
}

String customerBookingBookIssueFromRaw(String? raw) {
  final text = raw?.trim() ?? '';
  if (text.isEmpty) return kCustomerBookingIssueBookFailed;
  final lower = text.toLowerCase().replaceFirst('stateerror: ', '');
  if (lower.contains('timeout') ||
      lower.contains('socket') ||
      lower.contains('network') ||
      lower.contains('failed host lookup') ||
      lower.contains('connection refused')) {
    return kCustomerBookingIssueNetwork;
  }
  if (lower.contains('geocode') ||
      lower.contains('route_failed') ||
      lower.contains('route_config') ||
      lower.contains('mapbox')) {
    return kCustomerBookingIssueFailed;
  }
  if (lower.contains('duplicate') || lower.contains('idempotency')) {
    return kCustomerBookingIssueAlreadyBooked;
  }
  if (lower.contains('missing') &&
      (lower.contains('from') || lower.contains('to'))) {
    return kCustomerBookingIssueNeedRoute;
  }
  if (lower.contains('missing') &&
      (lower.contains('date') || lower.contains('time'))) {
    return kCustomerBookingIssueNeedWhen;
  }
  if (lower.contains('checkout_url') ||
      lower.contains('checkout_start') ||
      lower.contains('could not be started') ||
      lower.contains('kon niet worden gestart')) {
    return kCustomerBookingIssueCheckoutStart;
  }
  if (lower.contains('payment') ||
      lower.contains('mollie') ||
      lower.contains('betaal')) {
    return kCustomerBookingIssuePayment;
  }
  if (lower.contains('vehicle') ||
      lower.contains('voertuig') ||
      lower.contains('unavailable') ||
      lower.contains('niet beschikbaar') ||
      lower.contains('allocator') ||
      lower.contains('required_vehicle') ||
      lower.contains('assignment_')) {
    return kCustomerBookingIssueUnavailable;
  }
  if (lower.contains('partner_required') ||
      lower.contains('need_company') ||
      lower.contains('missing tenant') ||
      lower.contains('public_partner')) {
    return kCustomerBookingIssueNeedCompany;
  }
  return kCustomerBookingIssueBookFailed;
}
