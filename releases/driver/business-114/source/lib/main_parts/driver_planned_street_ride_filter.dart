// P0-FIELD-REPAIR-1 (A) — street/direct rides are never "planned".
//
// PRODUCT CONTRACT
// ----------------
// A street/direct ride is started by the driver from the street, not booked
// ahead. It therefore has no planning identity:
//
//   * while it is running it is owned by the active street-ride lifecycle
//     (the live-navigation surface), NOT by the planned list;
//   * once it is stopped it belongs to Completed / history exactly once;
//   * it must never appear in the driver's Planned ("Gepland") count or in
//     the "Next ride" ("Volgende rit") card, in either state;
//   * an app refresh or restart must not resurrect it under Planned.
//
// The booking worker is authoritative: `listDriverBookingsAuthoritative`
// already drops these rows from the planned/open projection and stamps the
// canonical identity (`is_street_direct`, `source`, `booking_source`,
// `ride_type`) on every projected row. This module is the CLIENT SAFETY NET
// for that contract, so the ghost row cannot come back if a stale worker, a
// cached response or a future read path re-introduces it.
//
// DECISION INPUTS
// ---------------
// Canonical fields only — never a display label, never a translated string,
// never a price or a timestamp:
//
//   1. the authoritative worker hint `is_street_direct` / `isStreetDirect`;
//   2. canonical `source` / `booking_source`;
//   3. canonical `ride_type`;
//   4. a `street_`-prefixed canonical booking id.
//
// Genuine planned rides (single and round-trip, including an open return leg
// whose sibling outbound already completed) are never matched, because none of
// them carry a street/direct canonical identity.
//
// This module does NOT touch completed-history canonicalisation: that stays
// owned by `canonicalizeStreetHistory` in `street_history_canonical.dart`.

/// Canonical `source` / `booking_source` values that identify a street ride.
const Set<String> kStreetDirectCanonicalSources = <String>{
  'street_ride',
  'streetride',
  'street-ride',
  'direct',
  'direct_ride',
  'direct-ride',
};

/// Canonical `ride_type` values that identify a driver-started direct ride.
const Set<String> kStreetDirectCanonicalRideTypes = <String>{
  'direct',
  'street',
  'street_ride',
};

/// Canonical booking-id prefix used by street rides.
const String kStreetDirectBookingIdPrefix = 'street_';

String _norm(Object? value) =>
    (value ?? '').toString().trim().toLowerCase().replaceAll('-', '_');

/// Reads the authoritative worker hint, if the row carries one.
///
/// Returns null when neither key is present or the value is not a real
/// boolean, so callers fall through to the canonical-field derivation instead
/// of treating "absent" as "false".
bool? streetDirectWorkerHint(Map<String, dynamic> row) {
  for (final key in const <String>['is_street_direct', 'isStreetDirect']) {
    if (!row.containsKey(key)) continue;
    final raw = row[key];
    if (raw is bool) return raw;
    final token = _norm(raw);
    if (token == 'true' || token == '1') return true;
    if (token == 'false' || token == '0') return false;
  }
  return null;
}

/// True when [row] is a canonical street/direct ride.
///
/// The worker hint wins when present. Otherwise the decision is derived from
/// canonical source / booking_source / ride_type / booking-id prefix, checked
/// at the top level and inside a nested `booking` / `record` map so a
/// partially-flattened payload is still classified correctly.
bool driverRowIsStreetDirectRide(Map<String, dynamic> row) {
  final hint = streetDirectWorkerHint(row);
  if (hint != null) return hint;

  final nested = <Map<String, dynamic>>[row];
  for (final key in const <String>['booking', 'record', 'details']) {
    final value = row[key];
    if (value is Map) {
      nested.add(Map<String, dynamic>.from(value));
      final inner = value['booking'];
      if (inner is Map) nested.add(Map<String, dynamic>.from(inner));
    }
  }

  for (final map in nested) {
    final nestedHint = map == row ? null : streetDirectWorkerHint(map);
    if (nestedHint == true) return true;

    for (final key in const <String>[
      'source',
      'booking_source',
      'bookingSource',
    ]) {
      if (kStreetDirectCanonicalSources.contains(_norm(map[key]))) return true;
    }
    for (final key in const <String>['ride_type', 'rideType']) {
      if (kStreetDirectCanonicalRideTypes.contains(_norm(map[key]))) return true;
    }
    for (final key in const <String>[
      'booking_id',
      'bookingId',
      'parent_booking_id',
      'parentBookingId',
    ]) {
      if (_norm(map[key]).startsWith(kStreetDirectBookingIdPrefix)) return true;
    }
  }
  return false;
}

/// Bounded, PII-free diagnostic for one excluded planned row.
class DriverPlannedStreetRideExclusionLog {
  const DriverPlannedStreetRideExclusionLog({
    required this.segment,
    required this.status,
    required this.hasWorkerHint,
  });

  /// Driver-home list segment the exclusion applied to (e.g. `my_rides`).
  final String segment;

  /// Normalized lifecycle status of the excluded row (never a label).
  final String status;

  /// Whether the authoritative worker hint drove the decision.
  final bool hasWorkerHint;

  String toLogLine() =>
      '[DRIVER_PLANNED][STREET_DIRECT_EXCLUDED] '
      'segment=$segment status=$status hasWorkerHint=$hasWorkerHint '
      'reason=street_direct_never_planned';
}

/// Returns [items] without street/direct rides, for a PLANNED/OPEN projection.
///
/// Order is preserved and the input list is never mutated. [onLog] receives one
/// bounded diagnostic per excluded row. Never carries ids, addresses, customer
/// data or tokens.
///
/// Must only be used for the planned/open/next-ride projection. Completed and
/// history projections must keep the canonical street row.
List<T> filterPlannedRidesExcludingStreetDirect<T>(
  List<T> items, {
  required Map<String, dynamic> Function(T item) canonicalFieldsOf,
  String Function(T item)? statusOf,
  String segment = 'planned',
  void Function(DriverPlannedStreetRideExclusionLog log)? onLog,
}) {
  final kept = <T>[];
  for (final item in items) {
    final fields = canonicalFieldsOf(item);
    if (driverRowIsStreetDirectRide(fields)) {
      onLog?.call(
        DriverPlannedStreetRideExclusionLog(
          segment: segment,
          status: _norm(statusOf?.call(item)).toUpperCase(),
          hasWorkerHint: streetDirectWorkerHint(fields) != null,
        ),
      );
      continue;
    }
    kept.add(item);
  }
  return kept;
}
