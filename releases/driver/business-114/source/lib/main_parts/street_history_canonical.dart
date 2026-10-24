// STREET-RIDE-HISTORY-DUPLICATE-ZERO-BOOKING-1
// STREET-RIDE-HISTORY-DUPLICATE-ZERO-BOOKING-1A-RUNTIME-PROOF
//
// Canonical de-duplication of driver ride history.
//
// One physical street ride can surface as TWO backend trip records:
//
//  1. a `direct` tracking trip — the ride source: it carries the real finalized
//     fare (e.g. € 3,20), distance, wait time and start/stop timestamps;
//  2. a `planned` operational-leg shadow — created from the linked direct
//     booking's synthesized OUTBOUND leg. Its trip id is `planned_<bookingId>`
//     (optionally `_<legSuffix>`), it has km 0.0, € 0,00 and `leg_type`
//     outbound, and it is only a projection of the SAME physical ride.
//
// CANONICAL CONTRACT (1A)
// -----------------------
// Every physical ride is identified by a `canonical_physical_ride_key`:
//   * for a `direct` tracking trip           → its own booking_id;
//   * for a `planned` operational leg        → parent_booking_id, falling back
//                                              to booking_id.
// This is robust to the live shape where the flattened operational-leg row
// carries the PARENT street booking id in `booking_id` AND `parent_booking_id`,
// and also to a future shape where `booking_id` would hold a leg-scoped id while
// `parent_booking_id` still points at the street booking.
//
// A `planned` record is an `is_operational_shadow` (countContribution=0) when:
//   * a `direct` trip exists for the SAME canonical_physical_ride_key, AND
//   * it is an operational leg (leg_id / leg_type present) OR its trip id has
//     the deterministic `planned_<key>` relation.
//
// The worker (/trips/history) computes and EXPOSES `is_operational_shadow`,
// `canonical_physical_ride_key` and `canonical_trip_kind`. When that hint is
// present the client honours it directly; when it is absent (stale worker) the
// client re-derives the same decision from relational fields. It NEVER inspects
// time or amount, so real planned outbound/return legs (no direct trip for that
// key) and real free € 0,00 street rides (the surviving row is the direct trip)
// are preserved.

/// Client-side canonical contract version. Mirrored by the worker header
/// `X-Fluxidi-History-Canonical` and the `canonical_version` response field.
const String kStreetHistoryClientCanonicalVersion = '1B';

/// De-dup phase, mirrored in the `[STREET_HISTORY_CANONICAL]` diagnostic line.
enum StreetHistoryCanonicalPhase { project, dedupe, keepSeparate }

/// Bounded, PII-free diagnostic describing one canonical decision.
///
/// Never carries raw ids, customer data, addresses or tokens.
class StreetHistoryCanonicalLog {
  const StreetHistoryCanonicalLog({
    required this.phase,
    required this.source,
    required this.hasLinkedTrip,
    required this.hasLinkedBooking,
    required this.countContribution,
    required this.reason,
  });

  final StreetHistoryCanonicalPhase phase;

  /// `tracking` | `booking` | `merged`.
  final String source;
  final bool hasLinkedTrip;
  final bool hasLinkedBooking;

  /// 0 (dropped shadow) or 1 (kept canonical row).
  final int countContribution;
  final String reason;

  String toLogLine() =>
      '[STREET_HISTORY_CANONICAL] '
      'phase=${phase.name} source=$source '
      'hasLinkedTrip=$hasLinkedTrip hasLinkedBooking=$hasLinkedBooking '
      'countContribution=$countContribution reason=$reason';
}

String _canonicalKind(String kind) => kind.trim().toLowerCase();
String _canonicalId(String id) => id.trim();

/// True when a trip record is the canonical `direct` tracking street ride.
bool streetHistoryTripIsDirect(String kind) => _canonicalKind(kind) == 'direct';

/// The `canonical_physical_ride_key` for a history record.
///
/// `direct` → own booking id; `planned` → parent booking id (falling back to
/// booking id). Empty when no relational id is available (never merged).
String streetHistoryCanonicalRideKey({
  required String kind,
  required String bookingId,
  String parentBookingId = '',
}) {
  final booking = _canonicalId(bookingId);
  if (_canonicalKind(kind) == 'planned') {
    final parent = _canonicalId(parentBookingId);
    return parent.isNotEmpty ? parent : booking;
  }
  return booking;
}

/// Collects the set of keys owned by `direct` trips: each direct trip's own
/// tracking trip id AND its booking id, so a `planned` shadow can match either
/// the 1B tracking-trip relation or the legacy booking relation.
Set<String> streetHistoryDirectRideKeys<T>(
  Iterable<T> items, {
  required String Function(T) kind,
  required String Function(T) bookingId,
  String Function(T)? tripId,
  String Function(T)? parentBookingId,
}) {
  final ids = <String>{};
  for (final item in items) {
    if (!streetHistoryTripIsDirect(kind(item))) continue;
    final booking = _canonicalId(bookingId(item));
    if (booking.isNotEmpty) ids.add(booking);
    final trip = _canonicalId(tripId?.call(item) ?? '');
    if (trip.isNotEmpty) ids.add(trip);
  }
  return ids;
}

/// True when a `planned` trip is an operational-leg shadow of a street-ride
/// direct trip. 1B: an explicit/resolved `linked_tracking_trip_id` owned by a
/// direct trip is authoritative; otherwise falls back to the legacy booking-key
/// relation. The worker `is_operational_shadow` hint overrides everything.
bool isCanonicalStreetPlannedShadow({
  required String tripId,
  required String kind,
  required String bookingId,
  required Set<String> directRideKeys,
  String parentBookingId = '',
  String linkedTrackingTripId = '',
  bool isOperationalLeg = false,
  bool? workerShadowHint,
}) {
  if (_canonicalKind(kind) != 'planned') return false;
  // Authoritative worker hint wins when present.
  if (workerShadowHint == true) return true;
  if (workerShadowHint == false) return false;
  // 1B: explicit/resolved tracking-trip relation.
  final linked = _canonicalId(linkedTrackingTripId);
  if (linked.isNotEmpty && directRideKeys.contains(linked)) return true;
  // Legacy relational fallback via booking key.
  final booking = _canonicalId(bookingId);
  final parent = _canonicalId(parentBookingId);
  final ownedKey = [parent, booking].firstWhere(
    (k) => k.isNotEmpty && directRideKeys.contains(k),
    orElse: () => '',
  );
  if (ownedKey.isEmpty) return false;
  if (isOperationalLeg) return true;
  final trip = tripId.trim();
  return trip == 'planned_$ownedKey' ||
      trip.startsWith('planned_${ownedKey}_') ||
      trip == 'planned_$booking' ||
      trip.startsWith('planned_${booking}_');
}

/// Returns [items] with planned street-ride leg shadows removed so exactly one
/// canonical row survives per physical street ride.
///
/// Order is preserved. [onLog] receives one bounded diagnostic per dropped
/// shadow (and, when [logKept] is true, per surviving row).
///
/// [parentBookingId] / [isOperationalLeg] / [workerShadowHint] are optional
/// robustness inputs; when omitted the dedupe falls back to booking-id-only
/// relational matching (backward compatible).
List<T> canonicalizeStreetHistory<T>(
  List<T> items, {
  required String Function(T) tripId,
  required String Function(T) kind,
  required String Function(T) bookingId,
  String Function(T)? parentBookingId,
  String Function(T)? linkedTrackingTripId,
  bool Function(T)? isOperationalLeg,
  bool? Function(T)? workerShadowHint,
  void Function(StreetHistoryCanonicalLog log)? onLog,
  bool logKept = false,
}) {
  final directRideKeys = streetHistoryDirectRideKeys<T>(
    items,
    kind: kind,
    bookingId: bookingId,
    tripId: tripId,
    parentBookingId: parentBookingId,
  );
  final kept = <T>[];
  for (final item in items) {
    final k = kind(item);
    final bId = bookingId(item);
    final parent = parentBookingId?.call(item) ?? '';
    if (isCanonicalStreetPlannedShadow(
      tripId: tripId(item),
      kind: k,
      bookingId: bId,
      directRideKeys: directRideKeys,
      parentBookingId: parent,
      linkedTrackingTripId: linkedTrackingTripId?.call(item) ?? '',
      isOperationalLeg: isOperationalLeg?.call(item) ?? false,
      workerShadowHint: workerShadowHint?.call(item),
    )) {
      onLog?.call(
        const StreetHistoryCanonicalLog(
          phase: StreetHistoryCanonicalPhase.dedupe,
          source: 'tracking',
          hasLinkedTrip: true,
          hasLinkedBooking: true,
          countContribution: 0,
          reason: 'street_planned_leg_shadow_of_direct_trip',
        ),
      );
      continue;
    }
    if (logKept && onLog != null) {
      final isPlanned = _canonicalKind(k) == 'planned';
      onLog(
        StreetHistoryCanonicalLog(
          phase: isPlanned
              ? StreetHistoryCanonicalPhase.keepSeparate
              : StreetHistoryCanonicalPhase.project,
          source: 'tracking',
          hasLinkedTrip: streetHistoryTripIsDirect(k),
          hasLinkedBooking: streetHistoryCanonicalRideKey(
            kind: k,
            bookingId: bId,
            parentBookingId: parent,
          ).isNotEmpty,
          countContribution: 1,
          reason: isPlanned
              ? 'planned_leg_without_direct_trip_kept'
              : 'canonical_ride_kept',
        ),
      );
    }
    kept.add(item);
  }
  return kept;
}
