// COMPANY-AGENDA-P0 — Nu uses backend server time; Later keeps a local concept.

import 'package:fluxidi_tracking/company/company_agenda_models.dart';

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

bool companyPlanLaterPickupIsValid(DateTime pickup, {DateTime? now}) {
  final clock = (now ?? companyPlanNowLocal()).toLocal();
  return !pickup.toLocal().isBefore(clock);
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
    'pickup_iso': laterPickup.toUtc().toIso8601String(),
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
  body['pickup_iso'] = draft.pickupLocal.toUtc().toIso8601String();
}

bool companyPlanFlightDepartsBeforePickup({
  required String flightAt,
  required DateTime? pickupLocal,
  required bool whenNow,
}) {
  final flight = DateTime.tryParse(flightAt.trim());
  if (flight == null) return false;
  final pickup = whenNow ? companyPlanNowLocal() : pickupLocal;
  if (pickup == null || companyPlanPickupIsEpoch(pickup)) return false;
  return !pickup.toUtc().isBefore(flight.toUtc());
}

DateTime? companyPlanSuggestedToAirportPickup({
  required String flightAt,
  int? durationMin,
}) {
  final flight = DateTime.tryParse(flightAt.trim());
  if (flight == null || durationMin == null || durationMin <= 0) return null;
  return flight.toLocal().subtract(Duration(minutes: durationMin));
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
  String durationText = '',
}) {
  if (quoteDurationMin != null && quoteDurationMin > 0) return quoteDurationMin;
  if (durationRouteMin != null && durationRouteMin > 0) return durationRouteMin;
  final typed = int.tryParse(durationText.trim());
  if (typed != null && typed > 0) return typed;
  return null;
}
