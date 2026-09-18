// COMPANY-AGENDA-P0 — Nu uses backend server time; Later keeps a local concept.

import 'package:fluxidi_tracking/company/company_agenda_models.dart';
import 'package:fluxidi_tracking/company/company_timezone.dart';

typedef CompanyPlanClock = DateTime Function();

CompanyPlanClock companyPlanClock = DateTime.now;

void debugCompanyPlanClock(CompanyPlanClock clock) {
  companyPlanClock = clock;
}

void debugResetCompanyPlanClock() {
  companyPlanClock = DateTime.now;
}

bool companyPlanPickupIsEpoch(DateTime? value) {
  if (value == null) return false;
  return !value.toUtc().isAfter(DateTime.utc(1970, 1, 2));
}

DateTime companyPlanNowLocal([CompanyPlanClock? clock]) {
  return (clock ?? companyPlanClock)().toLocal();
}

bool companyAgendaWhenIsNow(Object? raw) {
  if (raw == true) return true;
  final text = raw?.toString().trim().toLowerCase() ?? '';
  return text == 'now' ||
      text == 'when_now' ||
      text == 'true' ||
      text == '1' ||
      text == 'yes';
}

DateTime companyPlanLaterFirstDate([DateTime? now]) {
  final clock = (now ?? companyPlanNowLocal()).toLocal();
  return DateTime(clock.year, clock.month, clock.day);
}

DateTime companyPlanWallClock(DateTime value) {
  return DateTime(
    value.year,
    value.month,
    value.day,
    value.hour,
    value.minute,
    value.second,
  );
}

DateTime companyPlanCompanyNow([CompanyPlanClock? clock]) {
  return companyTimezoneUtcToLocal(
    (clock ?? companyPlanClock)().toUtc(),
    kCompanyDefaultTimezone,
  );
}

DateTime companyPlanPickupUtc(DateTime laterPickup) {
  return companyTimezoneLocalToUtc(
    companyPlanWallClock(laterPickup),
    kCompanyDefaultTimezone,
  );
}

String companyPlanPickupIso(DateTime laterPickup) {
  return companyPlanPickupUtc(laterPickup).toIso8601String();
}

bool companyPlanLaterPickupIsValid(DateTime pickup, {DateTime? now}) {
  final clock = companyPlanWallClock(
    now != null
        ? companyTimezoneUtcToLocal(now.toUtc(), kCompanyDefaultTimezone)
        : companyPlanCompanyNow(),
  );
  return !companyPlanWallClock(pickup).isBefore(clock);
}

String companyPlanQuoteFingerprintWhen({
  required bool whenNow,
  DateTime? laterPickup,
}) {
  if (whenNow) return 'now';
  if (laterPickup == null || companyPlanPickupIsEpoch(laterPickup)) return '';
  final local = laterPickup.toLocal();
  return '${local.year}-${local.month}-${local.day}T${local.hour}:${local.minute}';
}

Map<String, dynamic> companyPlanWhenWireFields({
  required bool whenNow,
  DateTime? laterPickup,
  CompanyPlanClock? clock,
}) {
  if (whenNow) {
    return const <String, dynamic>{
      'when': 'now',
      'when_now': true,
    };
  }
  if (laterPickup == null || companyPlanPickupIsEpoch(laterPickup)) {
    return const <String, dynamic>{};
  }
  return <String, dynamic>{
    'pickup_iso': companyPlanPickupIso(laterPickup),
  };
}

void companyPlanStripClientScheduleFields(Map<String, dynamic> body) {
  body.remove('pickup_iso');
  body.remove('pickupIso');
  body.remove('scheduled_at');
  body.remove('scheduledAt');
  body.remove('scheduled_pickup_iso');
  body.remove('date');
  body.remove('time');
}

Map<String, dynamic> companyPlanWhenCreateFields(
  CompanyRidePlanDraft draft, {
  CompanyPlanClock? clock,
}) {
  if (draft.whenNow) {
    return companyPlanWhenWireFields(whenNow: true, clock: clock);
  }
  return companyPlanWhenWireFields(
    whenNow: false,
    laterPickup: draft.pickupLocal,
    clock: clock,
  );
}

void companyPlanApplyCreateWhenFields(
  Map<String, dynamic> body,
  CompanyRidePlanDraft draft, {
  CompanyPlanClock? clock,
}) {
  if (draft.whenNow) {
    body.addAll(companyPlanWhenWireFields(whenNow: true, clock: clock));
    companyPlanStripClientScheduleFields(body);
    return;
  }
  if (companyPlanPickupIsEpoch(draft.pickupLocal)) {
    body.remove('pickup_iso');
    body.remove('pickupIso');
    return;
  }
  body['pickup_iso'] = companyPlanPickupIso(draft.pickupLocal);
}

/// Flight timestamp as a Europe/Brussels wall clock, never the device zone.
DateTime? companyPlanFlightLocal(String flightAt) {
  final text = flightAt.trim();
  if (text.isEmpty) return null;
  final parsed = DateTime.tryParse(text);
  if (parsed == null) return null;
  if (parsed.isUtc ||
      text.endsWith('Z') ||
      RegExp(r'[+-]\d{2}:?\d{2}$').hasMatch(text)) {
    final local = companyTimezoneUtcToLocal(
      parsed.toUtc(),
      kCompanyDefaultTimezone,
    );
    return DateTime(
      local.year,
      local.month,
      local.day,
      local.hour,
      local.minute,
    );
  }
  return DateTime(
    parsed.year,
    parsed.month,
    parsed.day,
    parsed.hour,
    parsed.minute,
  );
}

bool companyPlanFlightDepartsBeforePickup({
  required String flightAt,
  required DateTime? pickupLocal,
  required bool whenNow,
}) {
  final flight = companyPlanFlightLocal(flightAt);
  if (flight == null) return false;
  final pickup = whenNow ? companyPlanNowLocal() : pickupLocal;
  if (pickup == null || companyPlanPickupIsEpoch(pickup)) return false;
  return !companyPlanWallClock(pickup).isBefore(flight);
}

const int kCompanyPlanDefaultAirportArrivalMarginMin = 15;

DateTime? companyPlanSuggestedToAirportPickup({
  required String flightAt,
  int? durationMin,
  int arrivalMarginMin = kCompanyPlanDefaultAirportArrivalMarginMin,
}) {
  final flight = companyPlanFlightLocal(flightAt);
  if (flight == null || durationMin == null || durationMin <= 0) return null;
  final margin = arrivalMarginMin.clamp(0, 180);
  return flight.subtract(Duration(minutes: durationMin + margin));
}

DateTime? companyPlanSuggestedFromAirportPickup({
  required String flightAt,
  int pickupAfterMin = 0,
}) {
  final flight = companyPlanFlightLocal(flightAt);
  if (flight == null) return null;
  return flight.add(Duration(minutes: pickupAfterMin.clamp(0, 240)));
}

/// Pickup the roster and assignment must use. A later airport flight is never
/// judged against the phone clock.
DateTime? companyPlanAssignmentPickupLocal({
  required bool whenNow,
  DateTime? pickupLocal,
  DateTime? airportPickup,
  bool futureAirportFlight = false,
}) {
  if (airportPickup != null) return airportPickup;
  if (futureAirportFlight) return pickupLocal;
  if (whenNow) return companyPlanNowLocal();
  return pickupLocal;
}

bool companyPlanAssignmentWhenNow({
  required bool whenNow,
  DateTime? airportPickup,
  bool futureAirportFlight = false,
}) {
  if (airportPickup != null || futureAirportFlight) return false;
  return whenNow;
}

bool companyPlanPickupWallEquals(DateTime? left, DateTime? right) {
  if (left == null || right == null) return false;
  return companyPlanWallClock(left) == companyPlanWallClock(right);
}

DateTime? companyPlanAirportSuggestedPickup({
  required String airportDirection,
  required String flightAt,
  int? durationMin,
  int arrivalMarginMin = kCompanyPlanDefaultAirportArrivalMarginMin,
  int pickupAfterMin = 0,
  bool isAirportService = false,
}) {
  final direction = airportDirection.trim();
  final toAirport =
      direction == 'to_airport' || (direction.isEmpty && isAirportService);
  if (toAirport) {
    return companyPlanSuggestedToAirportPickup(
      flightAt: flightAt,
      durationMin: durationMin,
      arrivalMarginMin: arrivalMarginMin,
    );
  }
  if (direction == 'from_airport') {
    return companyPlanSuggestedFromAirportPickup(
      flightAt: flightAt,
      pickupAfterMin: pickupAfterMin,
    );
  }
  return null;
}

bool companyPlanFlightIsInFuture(String flightAt, {DateTime? now}) {
  final flight = companyPlanFlightLocal(flightAt);
  if (flight == null) return false;
  final clock = companyPlanWallClock(
    now != null
        ? companyTimezoneUtcToLocal(now.toUtc(), kCompanyDefaultTimezone)
        : companyPlanCompanyNow(),
  );
  return flight.isAfter(clock);
}

String companyPlanFormatClock(DateTime value) {
  final local = value.toLocal();
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}

int? companyPlanCanonicalDurationMin({
  int? quoteDurationMin,
  int? durationRouteMin,
  int? geometryDurationMin,
  String durationText = '',
}) {
  if (quoteDurationMin != null && quoteDurationMin > 0) return quoteDurationMin;
  if (durationRouteMin != null && durationRouteMin > 0) return durationRouteMin;
  if (geometryDurationMin != null && geometryDurationMin > 0) {
    return geometryDurationMin;
  }
  final typed = int.tryParse(durationText.trim());
  if (typed != null && typed > 0) return typed;
  return null;
}
