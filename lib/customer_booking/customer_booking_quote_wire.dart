// Public /quote and /book require from, to, date, time.
// Company-plan bodies only send pickup_iso or when_now; flight time is separate.

import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/company/company_plan_when.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_labels.dart';
import 'package:fluxidi_tracking/limousine/limousine_address_lookup.dart';

const String kCustomerBookingIssueNeedRoute = 'need_route';
const String kCustomerBookingIssueNeedWhen = 'need_pickup_time';
const String kCustomerBookingIssueLaterInvalid = 'later_invalid';
const String kCustomerBookingIssueFailed = 'route_failed';
const String kCustomerBookingIssuePriceFailed = 'price_failed';
const String kCustomerBookingIssueQuoteFailed = 'quote_failed';
const String kCustomerBookingIssueNeedCompany = 'need_company';
const String kCustomerBookingIssueNeedAirport = 'need_airport';

String customerBookingFormatDateYmd(DateTime value) {
  final local = value.toLocal();
  final month = local.month.toString().padLeft(2, '0');
  final day = local.day.toString().padLeft(2, '0');
  return '${local.year}-$month-$day';
}

String customerBookingFormatTimeHm(DateTime value) {
  final local = value.toLocal();
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}

DateTime? customerBookingParsePickupIso(Object? raw) {
  final text = raw?.toString().trim() ?? '';
  if (text.isEmpty) return null;
  return DateTime.tryParse(text);
}

bool customerBookingBodyHasWhenNow(Map<String, dynamic> body) {
  return companyAgendaWhenIsNow(body['when_now']) ||
      companyAgendaWhenIsNow(body['when']);
}

bool customerBookingHasDateTime(Map<String, dynamic> body) {
  final date = body['date']?.toString().trim() ?? '';
  final time = body['time']?.toString().trim() ?? '';
  return date.isNotEmpty && time.isNotEmpty;
}

void _applyLocalDateTime(
  Map<String, dynamic> body,
  DateTime value, {
  required String dateKey,
  required String timeKey,
}) {
  body[dateKey] = customerBookingFormatDateYmd(value);
  body[timeKey] = customerBookingFormatTimeHm(value);
}

/// Copies the existing pickup schedule onto the public quote wire.
///
/// Uses `pickup_iso` or the explicit `when_now` choice. Never invents a
/// default date, never uses flight/landing time, and never fills missing
/// coordinates.
void customerBookingEnsurePublicScheduleFields(
  Map<String, dynamic> body, {
  DateTime Function()? clock,
}) {
  if (!customerBookingHasDateTime(body)) {
    final pickup = customerBookingParsePickupIso(
      body['pickup_iso'] ?? body['pickupIso'],
    );
    if (pickup != null && !companyPlanPickupIsEpoch(pickup)) {
      _applyLocalDateTime(body, pickup, dateKey: 'date', timeKey: 'time');
    } else if (customerBookingBodyHasWhenNow(body)) {
      final now = (clock ?? DateTime.now)().toLocal();
      _applyLocalDateTime(body, now, dateKey: 'date', timeKey: 'time');
      if ((body['pickup_iso'] ?? '').toString().trim().isEmpty) {
        body['pickup_iso'] = now.toUtc().toIso8601String();
      }
    }
  }

  final returnDate = body['return_date']?.toString().trim() ?? '';
  final returnTime = body['return_time']?.toString().trim() ?? '';
  if (returnDate.isNotEmpty && returnTime.isNotEmpty) return;
  final returnPickup = customerBookingParsePickupIso(
    body['return_pickup_iso'] ?? body['returnPickupIso'],
  );
  if (returnPickup == null || companyPlanPickupIsEpoch(returnPickup)) return;
  _applyLocalDateTime(
    body,
    returnPickup,
    dateKey: 'return_date',
    timeKey: 'return_time',
  );
}

String customerBookingQuoteIssueFromRaw(String? raw) {
  final text = raw?.trim() ?? '';
  if (text.isEmpty) return '';
  final lower = text.toLowerCase().replaceFirst('stateerror: ', '');
  if (lower == kCustomerBookingIssueNeedRoute ||
      lower == 'route_required' ||
      (lower.contains('missing fields: from, to') &&
          !lower.contains('date') &&
          !lower.contains('time'))) {
    return kCustomerBookingIssueNeedRoute;
  }
  if (lower == kCustomerBookingIssueNeedWhen ||
      lower.contains('pickup_iso') ||
      (lower.contains('missing fields') &&
          (lower.contains('date') || lower.contains('time')))) {
    return kCustomerBookingIssueNeedWhen;
  }
  if (lower.contains('price') ||
      lower.contains('tariff') ||
      lower.contains('calculator') ||
      lower.contains('prijs') ||
      lower == kCustomerBookingIssuePriceFailed) {
    return kCustomerBookingIssuePriceFailed;
  }
  if (lower == kCustomerBookingIssueFailed ||
      lower.contains('mapbox') ||
      lower.contains('route_failed') ||
      lower.contains('geometry')) {
    return kCustomerBookingIssueFailed;
  }
  if (lower == kCustomerBookingIssueNeedCompany ||
      lower.contains('need_company') ||
      lower.contains('public_partner') ||
      lower.contains('partner_required')) {
    return kCustomerBookingIssueNeedCompany;
  }
  if (lower == kCustomerBookingIssueNeedAirport ||
      lower.contains('need_airport') ||
      lower.contains('selecteer de luchthaven') ||
      lower.contains('select the airport')) {
    return kCustomerBookingIssueNeedAirport;
  }
  if (lower.contains('quote_failed') ||
      lower.contains('quote_http') ||
      lower == kCustomerBookingIssueQuoteFailed) {
    return kCustomerBookingIssueQuoteFailed;
  }
  if (lower.contains('missing fields')) {
    return kCustomerBookingIssueNeedWhen;
  }
  return kCustomerBookingIssueQuoteFailed;
}

String customerBookingQuoteErrorText(String? raw, AppLanguage language) {
  switch (customerBookingQuoteIssueFromRaw(raw)) {
    case kCustomerBookingIssueNeedRoute:
      return kCustomerBookingNeedRoute.of(language);
    case kCustomerBookingIssueNeedWhen:
      return kCustomerBookingNeedWhen.of(language);
    case kCustomerBookingIssueFailed:
      return kCustomerBookingRouteFailed.of(language);
    case kCustomerBookingIssuePriceFailed:
      return kCustomerBookingPriceFailed.of(language);
    case kCustomerBookingIssueQuoteFailed:
      return kCustomerBookingQuoteFailed.of(language);
    case kCustomerBookingIssueNeedCompany:
      return kCustomerBookingNeedCompany.of(language);
    case kCustomerBookingIssueNeedAirport:
      return kCustomerBookingNeedAirport.of(language);
    default:
      return '';
  }
}

String? customerBookingIncompleteQuoteIssue({
  required LimousineAddressValue from,
  required LimousineAddressValue to,
  required bool whenNow,
  required DateTime? pickupLocal,
}) {
  final fromReady = from.routeText.trim().isNotEmpty;
  final toReady = to.routeText.trim().isNotEmpty;
  if (!fromReady || !toReady) return null;
  if (!whenNow && pickupLocal == null) return kCustomerBookingIssueNeedWhen;
  return null;
}
