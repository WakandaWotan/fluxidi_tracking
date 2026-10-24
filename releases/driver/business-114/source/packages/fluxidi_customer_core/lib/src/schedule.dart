/// Pickup schedule and timezone handling.
///
/// Ported from golden commit 9df7e7b92ecc86a11184ee995e255da7b8f6fb68:
/// - `lib/company/company_timezone.dart` — `kCompanyDefaultTimezone`,
///   `companyTimezoneOffsetAt`, `companyTimezoneUtcToLocal`,
///   `companyTimezoneLocalToUtc`
/// - `lib/company/company_plan_when.dart` — `companyPlanPickupIsEpoch`,
///   `companyPlanWallClock`, `companyPlanPickupIso`, `companyPlanWhenWireFields`,
///   `companyPlanStripClientScheduleFields`, `companyAgendaWhenIsNow`
///
/// A pickup time is always a Europe/Brussels wall clock converted to UTC, never
/// the device timezone.
library;

const String kFluxidiDefaultTimezone = 'Europe/Brussels';

const Map<String, int> _standardOffsetHours = <String, int>{
  'Europe/Brussels': 1,
  'Europe/Amsterdam': 1,
  'Europe/Paris': 1,
  'Europe/Luxembourg': 1,
  'Europe/Berlin': 1,
  'Europe/Madrid': 1,
  'Europe/Rome': 1,
  'Europe/Vienna': 1,
  'Europe/Zurich': 1,
  'Europe/Prague': 1,
  'Europe/Warsaw': 1,
  'Europe/Copenhagen': 1,
  'Europe/Stockholm': 1,
  'Europe/Oslo': 1,
  'Europe/London': 0,
  'Europe/Dublin': 0,
  'Europe/Lisbon': 0,
  'UTC': 0,
};

bool fluxidiZoneIsResolvable(String timezone) =>
    _standardOffsetHours.containsKey(timezone.trim());

Duration fluxidiZoneOffsetAt(DateTime utc, String timezone) {
  final zone = timezone.trim();
  final standardHours = _standardOffsetHours[zone];
  if (standardHours == null) return utc.toLocal().timeZoneOffset;
  final standard = Duration(hours: standardHours);
  if (zone == 'UTC') return standard;
  return _europeanSummerTimeApplies(utc.toUtc())
      ? standard + const Duration(hours: 1)
      : standard;
}

DateTime fluxidiZoneUtcToLocal(DateTime utc, String timezone) =>
    utc.toUtc().add(fluxidiZoneOffsetAt(utc.toUtc(), timezone));

DateTime fluxidiZoneLocalToUtc(DateTime local, String timezone) {
  final naive = DateTime.utc(
    local.year,
    local.month,
    local.day,
    local.hour,
    local.minute,
    local.second,
  );
  var offset = fluxidiZoneOffsetAt(naive, timezone);
  var candidate = naive.subtract(offset);
  final settled = fluxidiZoneOffsetAt(candidate, timezone);
  if (settled != offset) {
    offset = settled;
    candidate = naive.subtract(offset);
  }
  return candidate;
}

/// EU summer time: last Sunday of March 01:00 UTC until last Sunday of October
/// 01:00 UTC. One rule covers every supported zone.
bool _europeanSummerTimeApplies(DateTime utc) {
  final start = _lastSundayAt01Utc(utc.year, DateTime.march);
  final end = _lastSundayAt01Utc(utc.year, DateTime.october);
  return !utc.isBefore(start) && utc.isBefore(end);
}

DateTime _lastSundayAt01Utc(int year, int month) {
  var day = DateTime.utc(year, month + 1, 0).day;
  while (DateTime.utc(year, month, day).weekday != DateTime.sunday) {
    day -= 1;
  }
  return DateTime.utc(year, month, day, 1);
}

bool fluxidiPickupIsEpoch(DateTime? value) {
  if (value == null) return false;
  return !value.toUtc().isAfter(DateTime.utc(1970, 1, 2));
}

DateTime fluxidiWallClock(DateTime value) => DateTime(
  value.year,
  value.month,
  value.day,
  value.hour,
  value.minute,
  value.second,
);

DateTime fluxidiPickupUtc(DateTime laterPickup) =>
    fluxidiZoneLocalToUtc(fluxidiWallClock(laterPickup), kFluxidiDefaultTimezone);

String fluxidiPickupIso(DateTime laterPickup) =>
    fluxidiPickupUtc(laterPickup).toIso8601String();

bool fluxidiWhenIsNow(Object? raw) {
  if (raw == true) return true;
  final text = raw?.toString().trim().toLowerCase() ?? '';
  return text == 'now' ||
      text == 'when_now' ||
      text == 'true' ||
      text == '1' ||
      text == 'yes';
}

/// Wire fields for the chosen pickup moment.
Map<String, dynamic> fluxidiWhenWireFields({
  required bool whenNow,
  DateTime? laterPickup,
}) {
  if (whenNow) {
    return const <String, dynamic>{'when': 'now', 'when_now': true};
  }
  if (laterPickup == null || fluxidiPickupIsEpoch(laterPickup)) {
    return const <String, dynamic>{};
  }
  return <String, dynamic>{'pickup_iso': fluxidiPickupIso(laterPickup)};
}

/// Removes client-side schedule fields, so "now" never carries a stale time.
void fluxidiStripClientScheduleFields(Map<String, dynamic> body) {
  body.remove('pickup_iso');
  body.remove('pickupIso');
  body.remove('scheduled_at');
  body.remove('scheduledAt');
  body.remove('scheduled_pickup_iso');
  body.remove('date');
  body.remove('time');
}
