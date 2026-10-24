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
const String kCustomerBookingIssueRequestQuoteRequired =
    'request_quote_required';

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
  if (lower == 'rate_limited') return 'search_rate_limited';
  if (const ['booking_area_unconfigured', 'booking_area_unverified',
      'company_scope_unverified', 'search_admission_unavailable',
      'official_address_index_unavailable'].contains(lower)) {
    return 'search_area_unverified';
  }
  if (const ['booking_area_not_served', 'company_unavailable',
      'company_service_unavailable'].contains(lower)) {
    return 'search_company_unavailable';
  }
  if (lower == 'official_address_required' ||
      lower == 'official_address_position_changed' ||
      lower == 'official_address_index_changed' ||
      lower == 'official_address_source_changed') {
    return kCustomerBookingIssueNeedRoute;
  }
  final advance = RegExp(
    r'airport_minimum_advance_booking(?::([0-9.]+))?',
  ).firstMatch(lower);
  if (advance != null) return advance.group(0)!;
  if (lower == kCustomerBookingIssueRequestQuoteRequired ||
      lower.contains('request_quote_required') ||
      lower.contains('company_mission_quote_required')) {
    return kCustomerBookingIssueRequestQuoteRequired;
  }
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
  final issue = customerBookingQuoteIssueFromRaw(raw);
  if (issue.startsWith('airport_minimum_advance_booking')) {
    final hours = num.tryParse(issue.split(':').last);
    final term = hours == null
        ? ''
        : ' ${hours % 1 == 0 ? hours.toInt() : hours}';
    return LocalizedText(
      nl: 'Boek minimaal$term uur vooraf.',
      en: 'Book at least$term hours ahead.',
      fr: 'Réservez au moins$term heures à l’avance.',
      es: 'Reserve al menos$term horas antes.',
      de: 'Mindestens$term Stunden im Voraus buchen.',
    ).of(language);
  }
  switch (customerBookingQuoteIssueFromRaw(raw)) {
    case 'search_rate_limited':
      return const LocalizedText(
        nl: 'Je hebt veel zoekopdrachten gedaan. Wacht even en probeer opnieuw.',
        en: 'You have made many searches. Please wait a moment and try again.',
        fr: 'Vous avez effectué beaucoup de recherches. Patientez puis réessayez.',
        es: 'Has realizado muchas búsquedas. Espera un momento e inténtalo de nuevo.',
        de: 'Du hast viele Suchanfragen gestellt. Warte kurz und versuche es erneut.',
      ).of(language);
    case 'search_area_unverified':
      return const LocalizedText(
        nl: 'We kunnen het ophaalgebied nu niet controleren. Probeer opnieuw.',
        en: 'We cannot check the pickup area right now. Please try again.',
        fr: 'Nous ne pouvons pas vérifier la zone de prise en charge. Réessayez.',
        es: 'No podemos comprobar la zona de recogida ahora. Inténtalo de nuevo.',
        de: 'Wir können den Abholbereich gerade nicht prüfen. Versuche es erneut.',
      ).of(language);
    case 'search_company_unavailable':
      return const LocalizedText(
        nl: 'Dit bedrijf kan deze aanvraag nu niet behandelen. Kies een ander bedrijf.',
        en: 'This company cannot handle this request right now. Choose another company.',
        fr: 'Cette entreprise ne peut pas traiter cette demande. Choisissez-en une autre.',
        es: 'Esta empresa no puede atender esta solicitud ahora. Elige otra empresa.',
        de: 'Dieses Unternehmen kann diese Anfrage gerade nicht bearbeiten. Wähle ein anderes.',
      ).of(language);
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
    case kCustomerBookingIssueRequestQuoteRequired:
      return '';
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
