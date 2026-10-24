// Company timezone conversion for driver schedules.
//
// The app has no IANA tz database bundled. Rather than silently guessing, this
// resolves the European zones the fleet actually uses (EU DST rule: forward on
// the last Sunday of March at 01:00 UTC, back on the last Sunday of October at
// 01:00 UTC) and reports anything else as unresolved so the caller can say so
// instead of showing a wrong clock.

const String kCompanyDefaultTimezone = 'Europe/Brussels';

/// Standard (winter) UTC offset per supported zone.
const Map<String, int> _kEuropeanStandardOffsetHours = <String, int>{
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

/// Whether [timezone] can be converted exactly. Unknown zones fall back to the
/// device zone, which callers must surface rather than present as company time.
bool companyTimezoneIsResolvable(String timezone) =>
    _kEuropeanStandardOffsetHours.containsKey(timezone.trim());

/// UTC offset in effect at [utc] for [timezone].
Duration companyTimezoneOffsetAt(DateTime utc, String timezone) {
  final zone = timezone.trim();
  final standardHours = _kEuropeanStandardOffsetHours[zone];
  if (standardHours == null) {
    return utc.toLocal().timeZoneOffset;
  }
  final standard = Duration(hours: standardHours);
  if (zone == 'UTC') return standard;
  return _europeanSummerTimeApplies(utc.toUtc())
      ? standard + const Duration(hours: 1)
      : standard;
}

/// Wall-clock time in [timezone] for an instant.
DateTime companyTimezoneUtcToLocal(DateTime utc, String timezone) {
  return utc.toUtc().add(companyTimezoneOffsetAt(utc.toUtc(), timezone));
}

/// Instant for a wall-clock time in [timezone].
///
/// The offset depends on the instant we are solving for, so this resolves once
/// with a first guess and re-checks. During the autumn overlap hour the first
/// (summer-time) reading wins, matching how a roster entered before the change
/// keeps its earlier clock.
DateTime companyTimezoneLocalToUtc(DateTime local, String timezone) {
  final naive = DateTime.utc(
    local.year,
    local.month,
    local.day,
    local.hour,
    local.minute,
    local.second,
  );
  var offset = companyTimezoneOffsetAt(naive, timezone);
  var candidate = naive.subtract(offset);
  final settled = companyTimezoneOffsetAt(candidate, timezone);
  if (settled != offset) {
    offset = settled;
    candidate = naive.subtract(offset);
  }
  return candidate;
}

/// EU summer time: last Sunday of March 01:00 UTC until last Sunday of
/// October 01:00 UTC. Identical in every EU zone, so one rule covers them all.
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
