/// Street-ride (direct ride) <-> company booking linking helpers.
///
/// A "street ride" is implemented as a direct ride (`ride_type: direct`).
/// Historically it lived only in the Tracking Worker + local compliance
/// ledger and never produced a Booking Worker record, so completed street
/// rides could not appear in the company Bookings screen.
///
/// These pure, dependency-free helpers build the START/STOP payloads, parse
/// the start response, and decide the compliance-ledger `booking_id`, so the
/// linking contract can be unit-tested without pumping the driver home widget
/// (which needs Mapbox / geolocation / http).
library;

/// Canonical source tag written on street-ride bookings.
const String kStreetRideBookingSource = 'street_ride';

/// Canonical `ride_type` for direct/street rides.
const String kStreetRideRideType = 'direct';

/// Lifecycle status token for an active street ride.
///
/// MUST be a token the company bookings bucketer (`_bucketFromStatus` in
/// `company_bookings_helpers.dart`) maps to the "Open / gepland" bucket:
/// `IN_PROGRESS` is neither cancelled nor completed, so it falls into the
/// default `open` bucket.
const String kStreetRideStatusInProgress = 'IN_PROGRESS';

/// Lifecycle status token for a finalized street ride.
///
/// MUST be a token the company bookings bucketer maps to the
/// "Afgerond / voltooid" bucket: it contains `COMPLETE`.
const String kStreetRideStatusCompleted = 'COMPLETED';

/// Company-bookings tab bucket, mirrored 1:1 from `_bucketFromStatus`
/// (`company_bookings_helpers.dart`). Kept here so tests can assert the
/// street-ride status tokens land in the intended tabs without importing the
/// private `part of main.dart` bucketer.
enum StreetRideCompanyBucket { open, completed, cancelled }

/// Mirror of `_normStatus` + `_bucketFromStatus` from the company bookings
/// screen. If that logic changes, this must be updated in lockstep (there is a
/// guard test asserting the mapping for the street-ride tokens).
StreetRideCompanyBucket streetRideCompanyBucket(String statusRaw) {
  final normalized =
      statusRaw.trim().toUpperCase().replaceAll('-', '_').replaceAll(' ', '_');
  if (normalized.contains('CANCEL')) return StreetRideCompanyBucket.cancelled;
  if (normalized == 'DELETED') return StreetRideCompanyBucket.cancelled;
  if (normalized.contains('COMPLETE') ||
      normalized == 'DONE' ||
      normalized == 'FINISHED') {
    return StreetRideCompanyBucket.completed;
  }
  return StreetRideCompanyBucket.open;
}

/// Stable idempotency key so a retried START call never creates a duplicate
/// booking. Derived from the driver id + start timestamp; it is stable for the
/// lifetime of a single ride and unique across rides.
String makeDirectRideKey({
  required String driverId,
  required int startedAtMs,
}) {
  final safeDriver = driverId.trim().isEmpty ? 'driver' : driverId.trim();
  return 'direct_${startedAtMs}_$safeDriver';
}

/// Extend an existing direct-trip START payload with the fields the backend
/// needs to create + link a street-ride booking. Returns a new map; the input
/// is not mutated.
Map<String, dynamic> withDirectRideBookingStartFields(
  Map<String, dynamic> base, {
  required String directRideKey,
}) {
  return <String, dynamic>{
    ...base,
    'source': kStreetRideBookingSource,
    'ride_type': kStreetRideRideType,
    'direct_ride_key': directRideKey,
    'booking_status': kStreetRideStatusInProgress,
  };
}

/// Parsed result of `POST /trip/start-direct`.
class DirectRideStartResult {
  const DirectRideStartResult({
    required this.ok,
    required this.tripId,
    required this.bookingId,
    required this.bookingLinkState,
  });

  final bool ok;
  final String tripId;

  /// Non-null only when the backend created + returned a linked booking.
  final String? bookingId;

  /// `linked` when a booking_id is present, `pending` when the ride started
  /// but no booking was linked yet (reconcilable), `unknown` on malformed or
  /// not-ok responses.
  final String bookingLinkState;

  bool get hasLinkedBooking => (bookingId ?? '').trim().isNotEmpty;
}

DirectRideStartResult parseDirectRideStartResponse(Object? decoded) {
  if (decoded is! Map) {
    return const DirectRideStartResult(
      ok: false,
      tripId: '',
      bookingId: null,
      bookingLinkState: 'unknown',
    );
  }
  final ok = decoded['ok'] == true;
  final tripId = (decoded['trip_id'] ?? decoded['tripId'] ?? '').toString().trim();
  final bookingIdRaw =
      (decoded['booking_id'] ?? decoded['bookingId'] ?? '').toString().trim();
  final bookingId = bookingIdRaw.isEmpty ? null : bookingIdRaw;
  final linkStateRaw =
      (decoded['booking_link_state'] ?? decoded['bookingLinkState'] ?? '')
          .toString()
          .trim();
  final linkState = linkStateRaw.isNotEmpty
      ? linkStateRaw
      : (bookingId != null ? 'linked' : 'pending');
  return DirectRideStartResult(
    ok: ok,
    tripId: tripId,
    bookingId: bookingId,
    bookingLinkState: ok ? linkState : 'unknown',
  );
}

/// Add booking linkage to a direct-trip STOP payload so the backend finalizes
/// the same booking record. Returns a new map; the input is not mutated. When
/// no booking is linked (local-only ride), the base payload is returned
/// unchanged so no empty `booking_id` is sent.
Map<String, dynamic> withDirectRideBookingStopFields(
  Map<String, dynamic> base, {
  required String? bookingId,
}) {
  final id = (bookingId ?? '').trim();
  if (id.isEmpty) return <String, dynamic>{...base};
  return <String, dynamic>{
    ...base,
    'booking_id': id,
    'source': kStreetRideBookingSource,
  };
}

/// The `booking_id` value to write into the compliance ledger for a direct
/// ride: the trimmed booking id when the ride is linked to a booking, else
/// null for a local-only ride. This replaces the previous unconditional
/// `booking_id: null` so a successfully linked direct ride is auditable.
String? complianceLedgerBookingId(String? bookingId) {
  final id = (bookingId ?? '').trim();
  return id.isEmpty ? null : id;
}

// ===========================================================================
// STREET-RIDE-DURABLE-COMPLETION-2 — durable client-side direct-trip session.
// ===========================================================================

/// Tracking-worker endpoint that idempotently retries street/direct booking
/// finalization from the persisted trip. Defined here (a clean, non-WIP file)
/// because the other trip path constants live in the WIP-mixed `main.dart`.
const String kReconcileDirectBookingPath = '/trip/reconcile-direct-booking';

/// Local lifecycle of a client-side direct-trip session.
const String kDirectTripLocalLifecycleActive = 'active';
const String kDirectTripLocalLifecycleStopped = 'stopped';

/// Booking finalize states mirrored 1:1 from the tracking worker.
const String kDirectTripFinalizePending = 'pending';
const String kDirectTripFinalizeCompleted = 'completed';

/// Minimal durable record of the active/last direct-trip session, persisted so
/// a crash/restart can resume an active ride or reconcile a stopped-but-not-
/// finalized booking. Deliberately small and PII-free (ids + timestamps only).
class DirectTripSession {
  const DirectTripSession({
    required this.directRideKey,
    required this.tripId,
    required this.bookingId,
    required this.startedAtIso,
    required this.localLifecycle,
    required this.bookingFinalizeState,
    this.tenantId,
    this.companyId,
    this.driverId,
    this.updatedAtIso,
  });

  final String directRideKey;
  final String tripId;
  final String bookingId;
  final String startedAtIso;

  /// `active` while the ride is running, `stopped` once the driver stopped it.
  final String localLifecycle;

  /// `pending` until the booking is durably `completed` server-side.
  final String bookingFinalizeState;

  final String? tenantId;
  final String? companyId;
  final String? driverId;
  final String? updatedAtIso;

  bool get hasTripId => tripId.trim().isNotEmpty;
  bool get hasBookingId => bookingId.trim().isNotEmpty;
  bool get isCompleted =>
      bookingFinalizeState.trim().toLowerCase() == kDirectTripFinalizeCompleted;
  bool get isStopped =>
      localLifecycle.trim().toLowerCase() == kDirectTripLocalLifecycleStopped;

  DirectTripSession copyWith({
    String? directRideKey,
    String? tripId,
    String? bookingId,
    String? startedAtIso,
    String? localLifecycle,
    String? bookingFinalizeState,
    String? tenantId,
    String? companyId,
    String? driverId,
    String? updatedAtIso,
  }) {
    return DirectTripSession(
      directRideKey: directRideKey ?? this.directRideKey,
      tripId: tripId ?? this.tripId,
      bookingId: bookingId ?? this.bookingId,
      startedAtIso: startedAtIso ?? this.startedAtIso,
      localLifecycle: localLifecycle ?? this.localLifecycle,
      bookingFinalizeState: bookingFinalizeState ?? this.bookingFinalizeState,
      tenantId: tenantId ?? this.tenantId,
      companyId: companyId ?? this.companyId,
      driverId: driverId ?? this.driverId,
      updatedAtIso: updatedAtIso ?? this.updatedAtIso,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'direct_ride_key': directRideKey,
        'trip_id': tripId,
        'booking_id': bookingId,
        'started_at': startedAtIso,
        'local_lifecycle': localLifecycle,
        'booking_finalize_state': bookingFinalizeState,
        if ((tenantId ?? '').trim().isNotEmpty) 'tenant_id': tenantId!.trim(),
        if ((companyId ?? '').trim().isNotEmpty) 'company_id': companyId!.trim(),
        if ((driverId ?? '').trim().isNotEmpty) 'driver_id': driverId!.trim(),
        if ((updatedAtIso ?? '').trim().isNotEmpty)
          'updated_at': updatedAtIso!.trim(),
      };

  static DirectTripSession? fromJson(Object? decoded) {
    if (decoded is! Map) return null;
    String s(Object? v) => (v ?? '').toString().trim();
    final directRideKey = s(decoded['direct_ride_key'] ?? decoded['directRideKey']);
    final tripId = s(decoded['trip_id'] ?? decoded['tripId']);
    // A session with neither a direct_ride_key nor a trip_id is meaningless.
    if (directRideKey.isEmpty && tripId.isEmpty) return null;
    final lifecycleRaw =
        s(decoded['local_lifecycle'] ?? decoded['localLifecycle']).toLowerCase();
    final finalizeRaw = s(
      decoded['booking_finalize_state'] ?? decoded['bookingFinalizeState'],
    ).toLowerCase();
    return DirectTripSession(
      directRideKey: directRideKey,
      tripId: tripId,
      bookingId: s(decoded['booking_id'] ?? decoded['bookingId']),
      startedAtIso: s(decoded['started_at'] ?? decoded['startedAt']),
      localLifecycle: lifecycleRaw.isEmpty
          ? kDirectTripLocalLifecycleActive
          : lifecycleRaw,
      bookingFinalizeState:
          finalizeRaw.isEmpty ? kDirectTripFinalizePending : finalizeRaw,
      tenantId: s(decoded['tenant_id'] ?? decoded['tenantId']).isEmpty
          ? null
          : s(decoded['tenant_id'] ?? decoded['tenantId']),
      companyId: s(decoded['company_id'] ?? decoded['companyId']).isEmpty
          ? null
          : s(decoded['company_id'] ?? decoded['companyId']),
      driverId: s(decoded['driver_id'] ?? decoded['driverId']).isEmpty
          ? null
          : s(decoded['driver_id'] ?? decoded['driverId']),
      updatedAtIso: s(decoded['updated_at'] ?? decoded['updatedAt']).isEmpty
          ? null
          : s(decoded['updated_at'] ?? decoded['updatedAt']),
    );
  }
}

/// What startup recovery should do with a persisted session.
enum DirectTripRecoveryAction {
  /// No persisted session, or it is already resolved (completed).
  none,

  /// A ride is still marked active locally and recent — resume it in memory.
  resumeActive,

  /// A stopped ride whose booking is still pending and has a durable booking id
  /// and trip id — call the reconcile endpoint.
  reconcilePending,

  /// The session is unrecoverable (too old, or stopped/local-only with no
  /// durable booking to reconcile) — clear it under a safe rule.
  abandon,
}

/// Pure decision for startup recovery. No IO, fully unit-testable.
///
/// Rules:
///   * null / completed session → none;
///   * stopped + pending + has trip_id + has booking_id → reconcilePending;
///   * stopped + pending but no durable booking/trip → abandon (local-only);
///   * active + within [staleAfter] → resumeActive;
///   * active + older than [staleAfter] → abandon (crash left it dangling and
///     it is now too old to safely resume).
DirectTripRecoveryAction directTripRecoveryAction(
  DirectTripSession? session, {
  DateTime? now,
  Duration staleAfter = const Duration(hours: 12),
}) {
  if (session == null) return DirectTripRecoveryAction.none;
  if (session.isCompleted) return DirectTripRecoveryAction.none;
  final resolvedNow = (now ?? DateTime.now()).toUtc();

  if (session.isStopped) {
    if (session.hasTripId && session.hasBookingId) {
      return DirectTripRecoveryAction.reconcilePending;
    }
    return DirectTripRecoveryAction.abandon;
  }

  // Active (or unknown) lifecycle: resume when recent, else abandon.
  final startedAt = DateTime.tryParse(session.startedAtIso)?.toUtc();
  final reference = DateTime.tryParse(session.updatedAtIso ?? '')?.toUtc() ??
      startedAt;
  if (reference == null) return DirectTripRecoveryAction.resumeActive;
  final age = resolvedNow.difference(reference);
  if (age > staleAfter) return DirectTripRecoveryAction.abandon;
  return DirectTripRecoveryAction.resumeActive;
}

/// Bounded exponential backoff for reconcile retries. Never below 2s, never
/// above 5 minutes, so a persistently failing reconcile cannot busy-loop.
Duration directReconcileBackoff(int attempt) {
  final safeAttempt = attempt < 0 ? 0 : (attempt > 10 ? 10 : attempt);
  final seconds = 2 * (1 << safeAttempt); // 2,4,8,16,... seconds
  const maxSeconds = 5 * 60;
  return Duration(seconds: seconds > maxSeconds ? maxSeconds : seconds);
}

/// Parsed result of `POST /trip/stop` (and reconcile) for the client, capturing
/// the durable booking finalize state so the client never falsely represents a
/// booking sync as successful.
class DirectRideStopResult {
  const DirectRideStopResult({
    required this.ok,
    required this.totalEur,
    required this.bookingId,
    required this.bookingFinalizeState,
    required this.bookingFinalized,
  });

  final bool ok;
  final double? totalEur;
  final String? bookingId;
  final String bookingFinalizeState;
  final bool bookingFinalized;
}

DirectRideStopResult parseDirectRideStopResponse(Object? decoded) {
  if (decoded is! Map) {
    return const DirectRideStopResult(
      ok: false,
      totalEur: null,
      bookingId: null,
      bookingFinalizeState: kDirectTripFinalizePending,
      bookingFinalized: false,
    );
  }
  final ok = decoded['ok'] == true;
  final totals = decoded['totals'];
  Object? totalRaw;
  if (totals is Map) {
    totalRaw = totals['total_eur'] ?? totals['price_incl_vat'];
  }
  totalRaw ??= decoded['total_eur'];
  double? total;
  if (totalRaw is num) {
    total = totalRaw.toDouble();
  } else if (totalRaw != null) {
    total = double.tryParse(totalRaw.toString().replaceAll(',', '.'));
  }
  final bookingIdRaw =
      (decoded['booking_id'] ?? decoded['bookingId'] ?? '').toString().trim();
  final stateRaw = (decoded['booking_finalize_state'] ??
          decoded['bookingFinalizeState'] ??
          '')
      .toString()
      .trim()
      .toLowerCase();
  final finalized = decoded['booking_finalized'] == true ||
      stateRaw == kDirectTripFinalizeCompleted;
  return DirectRideStopResult(
    ok: ok,
    totalEur: total,
    bookingId: bookingIdRaw.isEmpty ? null : bookingIdRaw,
    bookingFinalizeState:
        stateRaw.isEmpty ? kDirectTripFinalizePending : stateRaw,
    bookingFinalized: finalized,
  );
}
