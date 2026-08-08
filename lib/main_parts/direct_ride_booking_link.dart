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

/// Whether `/trip/stop` has durably landed for this session.
///
/// Distinct from [kDirectTripFinalizePending]: stop may succeed while booking
/// finalize is still pending. Offline STOP leaves this `pending` with frozen
/// meter totals so reconnect can replay `/trip/stop` (reconcile alone cannot
/// stop a still-active server trip).
const String kDirectTripTrackingStopPending = 'pending';
const String kDirectTripTrackingStopCompleted = 'completed';

/// Durable record of the active/last direct-trip session, persisted so a
/// crash/restart/offline-STOP can resume or finalize without losing the ride.
///
/// Identity fields are PII-free ids/timestamps. After STOP, frozen meter
/// totals are also stored so reconnect can replay `/trip/stop` with the
/// exact driver-visible distance/time/fare (authoritative client freeze).
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
    this.stoppedAtIso,
    this.frozenKmTotal,
    this.frozenWaitSecondsTotal,
    this.frozenTotalEur,
    this.trackingStopState,
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

  /// Client freeze timestamp from the driver's STOP tap (UTC ISO).
  final String? stoppedAtIso;

  /// Frozen meter distance (km) at STOP — authoritative for offline replay.
  final double? frozenKmTotal;

  /// Frozen wait seconds at STOP.
  final int? frozenWaitSecondsTotal;

  /// Frozen client fare (€) at STOP (already €0.10-rounded when persisted).
  final double? frozenTotalEur;

  /// `pending` until `/trip/stop` is acknowledged; then `completed`.
  final String? trackingStopState;

  bool get hasTripId => tripId.trim().isNotEmpty;
  bool get hasBookingId => bookingId.trim().isNotEmpty;
  bool get isCompleted =>
      bookingFinalizeState.trim().toLowerCase() == kDirectTripFinalizeCompleted;
  bool get isStopped =>
      localLifecycle.trim().toLowerCase() == kDirectTripLocalLifecycleStopped;

  bool get hasFrozenStopTotals {
    final km = frozenKmTotal;
    final wait = frozenWaitSecondsTotal;
    final total = frozenTotalEur;
    final stopped = (stoppedAtIso ?? '').trim();
    return km != null &&
        km.isFinite &&
        km >= 0 &&
        wait != null &&
        wait >= 0 &&
        total != null &&
        total.isFinite &&
        total >= 0 &&
        stopped.isNotEmpty;
  }

  bool get trackingStopCompleted =>
      (trackingStopState ?? '').trim().toLowerCase() ==
      kDirectTripTrackingStopCompleted;

  bool get needsTrackingStopReplay =>
      isStopped &&
      hasTripId &&
      hasFrozenStopTotals &&
      !trackingStopCompleted &&
      !isCompleted;

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
    String? stoppedAtIso,
    double? frozenKmTotal,
    int? frozenWaitSecondsTotal,
    double? frozenTotalEur,
    String? trackingStopState,
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
      stoppedAtIso: stoppedAtIso ?? this.stoppedAtIso,
      frozenKmTotal: frozenKmTotal ?? this.frozenKmTotal,
      frozenWaitSecondsTotal:
          frozenWaitSecondsTotal ?? this.frozenWaitSecondsTotal,
      frozenTotalEur: frozenTotalEur ?? this.frozenTotalEur,
      trackingStopState: trackingStopState ?? this.trackingStopState,
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
        if ((stoppedAtIso ?? '').trim().isNotEmpty)
          'stopped_at': stoppedAtIso!.trim(),
        if (frozenKmTotal != null && frozenKmTotal!.isFinite)
          'frozen_km_total': frozenKmTotal,
        if (frozenWaitSecondsTotal != null)
          'frozen_wait_seconds_total': frozenWaitSecondsTotal,
        if (frozenTotalEur != null && frozenTotalEur!.isFinite)
          'frozen_total_eur': frozenTotalEur,
        if ((trackingStopState ?? '').trim().isNotEmpty)
          'tracking_stop_state': trackingStopState!.trim(),
      };

  static DirectTripSession? fromJson(Object? decoded) {
    if (decoded is! Map) return null;
    String s(Object? v) => (v ?? '').toString().trim();
    double? d(Object? v) {
      if (v is num) return v.toDouble();
      if (v == null) return null;
      return double.tryParse(v.toString().replaceAll(',', '.'));
    }

    int? i(Object? v) {
      if (v is int) return v;
      if (v is num) return v.round();
      if (v == null) return null;
      return int.tryParse(v.toString().trim());
    }

    final directRideKey = s(decoded['direct_ride_key'] ?? decoded['directRideKey']);
    final tripId = s(decoded['trip_id'] ?? decoded['tripId']);
    // A session with neither a direct_ride_key nor a trip_id is meaningless.
    if (directRideKey.isEmpty && tripId.isEmpty) return null;
    final lifecycleRaw =
        s(decoded['local_lifecycle'] ?? decoded['localLifecycle']).toLowerCase();
    final finalizeRaw = s(
      decoded['booking_finalize_state'] ?? decoded['bookingFinalizeState'],
    ).toLowerCase();
    final trackingStopRaw = s(
      decoded['tracking_stop_state'] ?? decoded['trackingStopState'],
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
      stoppedAtIso: s(decoded['stopped_at'] ?? decoded['stoppedAt']).isEmpty
          ? null
          : s(decoded['stopped_at'] ?? decoded['stoppedAt']),
      frozenKmTotal: d(decoded['frozen_km_total'] ?? decoded['frozenKmTotal']),
      frozenWaitSecondsTotal: i(
        decoded['frozen_wait_seconds_total'] ??
            decoded['frozenWaitSecondsTotal'],
      ),
      frozenTotalEur:
          d(decoded['frozen_total_eur'] ?? decoded['frozenTotalEur']),
      trackingStopState: trackingStopRaw.isEmpty ? null : trackingStopRaw,
    );
  }
}

/// What startup / reconnect recovery should do with a persisted session.
enum DirectTripRecoveryAction {
  /// No persisted session, or it is already resolved (completed).
  none,

  /// A ride is still marked active locally and recent — resume it in memory.
  resumeActive,

  /// Local STOP froze totals but `/trip/stop` has not been acknowledged —
  /// replay stop with the frozen totals (reconcile alone is insufficient).
  retryStop,

  /// Tracking stop landed; booking finalize still pending — reconcile only.
  reconcilePending,

  /// The session is unrecoverable (too old, or stopped/local-only with no
  /// durable booking to reconcile) — clear it under a safe rule.
  abandon,
}

/// Pure decision for startup / reconnect recovery. No IO, fully unit-testable.
///
/// Rules:
///   * null / completed session → none;
///   * stopped + frozen totals + tracking stop not completed + trip_id
///     → retryStop (offline STOP durability);
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
    if (session.needsTrackingStopReplay) {
      return DirectTripRecoveryAction.retryStop;
    }
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
    this.complianceEmitState,
  });

  final bool ok;
  final double? totalEur;
  final String? bookingId;
  final String bookingFinalizeState;
  final bool bookingFinalized;

  /// Tracking-worker Chiron ride_stop outbox state (`applied` / `pending`).
  final String? complianceEmitState;

  bool get complianceEmitApplied =>
      (complianceEmitState ?? '').trim().toLowerCase() == 'applied';
}

// ===========================================================================
// DIRECT-RIDE-FINALIZE-ACK-GATE-1 — structured stop outcome + ack gate.
//
// HTTP 200 / `ok:true` on `/trip/stop` only proves the tracking trip stopped.
// Local COMPLETED UI for a street/direct booking requires an explicit booking
// finalize acknowledgement (`booking_finalized` + completed state + matching
// booking id + totals). These pure helpers keep that distinction unit-
// testable without the driver-home widget.
// ===========================================================================

/// Canonical booking-finalize state for a direct/street stop outcome.
enum DirectRideFinalizeState {
  /// Booking worker confirmed `finalize-direct` completed.
  completed,

  /// Tracking trip stopped but booking finalization is still pending.
  pending,

  /// Transport failure or unparseable finalize state — not acknowledged.
  unknown,
}

/// Immutable structured outcome of `POST /trip/stop` for street/direct rides.
class DirectRideStopOutcome {
  const DirectRideStopOutcome({
    required this.transportSucceeded,
    required this.trackingTripStopped,
    required this.bookingId,
    required this.bookingFinalized,
    required this.bookingFinalizeState,
    required this.totalEur,
    required this.totalsPresent,
    this.complianceEmitApplied = false,
  });

  /// HTTP layer succeeded and body parsed as an `ok` response.
  final bool transportSucceeded;

  /// Tracking worker acknowledged the trip is stopped (independent of booking).
  final bool trackingTripStopped;

  final String? bookingId;
  final bool bookingFinalized;
  final DirectRideFinalizeState bookingFinalizeState;
  final double? totalEur;
  final bool totalsPresent;

  /// True when STOP response reports Chiron ride_stop outbox `applied`.
  final bool complianceEmitApplied;

  /// Transport / parse failure — never treat as booking completion.
  static const DirectRideStopOutcome unknown = DirectRideStopOutcome(
    transportSucceeded: false,
    trackingTripStopped: false,
    bookingId: null,
    bookingFinalized: false,
    bookingFinalizeState: DirectRideFinalizeState.unknown,
    totalEur: null,
    totalsPresent: false,
    complianceEmitApplied: false,
  );
}

DirectRideFinalizeState _finalizeStateFromToken(String raw) {
  final t = raw.trim().toLowerCase();
  if (t == kDirectTripFinalizeCompleted) {
    return DirectRideFinalizeState.completed;
  }
  if (t == kDirectTripFinalizePending) {
    return DirectRideFinalizeState.pending;
  }
  return DirectRideFinalizeState.unknown;
}

/// Map a parsed `/trip/stop` body (or transport failure) into a structured
/// [DirectRideStopOutcome]. Pure; unit-tested.
DirectRideStopOutcome mapDirectRideStopOutcome({
  required DirectRideStopResult? parsed,
  required bool transportSucceeded,
}) {
  if (!transportSucceeded || parsed == null || !parsed.ok) {
    return DirectRideStopOutcome.unknown;
  }
  final state = _finalizeStateFromToken(parsed.bookingFinalizeState);
  final finalized = parsed.bookingFinalized &&
      state == DirectRideFinalizeState.completed;
  return DirectRideStopOutcome(
    transportSucceeded: true,
    // Worker contract: `ok:true` on `/trip/stop` means the trip is stopped.
    trackingTripStopped: true,
    bookingId: parsed.bookingId,
    bookingFinalized: finalized,
    bookingFinalizeState: finalized
        ? DirectRideFinalizeState.completed
        : (state == DirectRideFinalizeState.pending
            ? DirectRideFinalizeState.pending
            : DirectRideFinalizeState.unknown),
    totalEur: parsed.totalEur,
    totalsPresent: parsed.totalEur != null,
    complianceEmitApplied: parsed.complianceEmitApplied,
  );
}

/// True only when the server has authoritatively acknowledged booking
/// completion for the exact active direct booking. HTTP stop success alone is
/// never sufficient.
bool isDirectRideFinalizeAcknowledged({
  required DirectRideStopOutcome outcome,
  required String? expectedBookingId,
}) {
  final expected = (expectedBookingId ?? '').trim();
  final got = (outcome.bookingId ?? '').trim();
  if (!outcome.transportSucceeded) return false;
  if (!outcome.trackingTripStopped) return false;
  if (!outcome.bookingFinalized) return false;
  if (outcome.bookingFinalizeState != DirectRideFinalizeState.completed) {
    return false;
  }
  if (expected.isEmpty || got.isEmpty || expected != got) return false;
  if (!outcome.totalsPresent) return false;
  return true;
}

// ===========================================================================
// DIRECT-RIDE-STOP-RECOVERY-RACE-1 / Commit 1 — reconcile acknowledgement.
//
// `/trip/reconcile-direct-booking` does not return fare totals. Local COMPLETED
// after reconcile therefore requires identity match + booking_finalized +
// completed state — never HTTP 200 alone, never a bare boolean.
// ===========================================================================

/// Reason token used by the tracking worker for an active (non-terminal) trip.
const String kDirectReconcileReasonNonTerminal = 'skipped_non_terminal';

/// Immutable structured outcome of `POST /trip/reconcile-direct-booking`.
class DirectRideReconcileOutcome {
  const DirectRideReconcileOutcome({
    required this.transportSucceeded,
    required this.httpStatus,
    required this.requestedTripId,
    required this.responseTripId,
    required this.expectedBookingId,
    required this.responseBookingId,
    required this.bookingFinalized,
    required this.bookingFinalizeState,
    required this.reconciled,
    required this.reason,
    required this.isNonTerminal,
    required this.isAcknowledged,
  });

  final bool transportSucceeded;
  final int? httpStatus;
  final String requestedTripId;
  final String? responseTripId;
  final String expectedBookingId;
  final String? responseBookingId;
  final bool bookingFinalized;
  final DirectRideFinalizeState bookingFinalizeState;
  final bool reconciled;
  final String? reason;
  final bool isNonTerminal;

  /// True only when identity + completed finalize state are proven.
  final bool isAcknowledged;

  /// Transport / decode failure — never treat as booking completion.
  static DirectRideReconcileOutcome unknown({
    required String requestedTripId,
    required String expectedBookingId,
    int? httpStatus,
  }) {
    return DirectRideReconcileOutcome(
      transportSucceeded: false,
      httpStatus: httpStatus,
      requestedTripId: requestedTripId.trim(),
      responseTripId: null,
      expectedBookingId: expectedBookingId.trim(),
      responseBookingId: null,
      bookingFinalized: false,
      bookingFinalizeState: DirectRideFinalizeState.unknown,
      reconciled: false,
      reason: null,
      isNonTerminal: false,
      isAcknowledged: false,
    );
  }
}

/// Pure mapper for `/trip/reconcile-direct-booking` responses.
///
/// Acknowledgement requires HTTP 200, matching trip + booking ids,
/// `booking_finalized == true`, and finalize state `completed`.
/// Totals are intentionally not required (absent from the endpoint).
DirectRideReconcileOutcome mapDirectRideReconcileOutcome({
  required Object? decoded,
  required int? httpStatus,
  required String requestedTripId,
  required String expectedBookingId,
  bool transportSucceeded = true,
}) {
  final reqTrip = requestedTripId.trim();
  final expBooking = expectedBookingId.trim();
  if (!transportSucceeded) {
    return DirectRideReconcileOutcome.unknown(
      requestedTripId: reqTrip,
      expectedBookingId: expBooking,
      httpStatus: httpStatus,
    );
  }
  if (decoded is! Map) {
    return DirectRideReconcileOutcome.unknown(
      requestedTripId: reqTrip,
      expectedBookingId: expBooking,
      httpStatus: httpStatus,
    );
  }

  String? s(Object? v) {
    final t = (v ?? '').toString().trim();
    return t.isEmpty ? null : t;
  }

  final responseTripId = s(decoded['trip_id'] ?? decoded['tripId']);
  final responseBookingId = s(decoded['booking_id'] ?? decoded['bookingId']);
  final reason = s(decoded['reason']);
  final state = _finalizeStateFromToken(
    (decoded['booking_finalize_state'] ?? decoded['bookingFinalizeState'] ?? '')
        .toString(),
  );
  final bookingFinalizedFlag = decoded['booking_finalized'] == true ||
      decoded['bookingFinalized'] == true;
  // Preserve the worker's `reconciled` flag as-is (`already_completed` returns
  // reconciled:false while still booking_finalized:true).
  final reconciledFlag = decoded['reconciled'] == true;
  final status = httpStatus;
  final isNonTerminal = status == 409 &&
      (reason ?? '').toLowerCase() == kDirectReconcileReasonNonTerminal;

  // Identity + completed-state acknowledgement (no totals; endpoint omits them).
  final identityMatch = reqTrip.isNotEmpty &&
      expBooking.isNotEmpty &&
      responseTripId != null &&
      responseBookingId != null &&
      responseTripId == reqTrip &&
      responseBookingId == expBooking;
  final completedState = state == DirectRideFinalizeState.completed &&
      bookingFinalizedFlag;
  final isAcknowledged = status == 200 &&
      identityMatch &&
      completedState &&
      !isNonTerminal;

  return DirectRideReconcileOutcome(
    transportSucceeded: true,
    httpStatus: status,
    requestedTripId: reqTrip,
    responseTripId: responseTripId,
    expectedBookingId: expBooking,
    responseBookingId: responseBookingId,
    bookingFinalized: bookingFinalizedFlag &&
        state == DirectRideFinalizeState.completed,
    bookingFinalizeState: state == DirectRideFinalizeState.completed &&
            bookingFinalizedFlag
        ? DirectRideFinalizeState.completed
        : (state == DirectRideFinalizeState.pending
            ? DirectRideFinalizeState.pending
            : DirectRideFinalizeState.unknown),
    reconciled: reconciledFlag,
    reason: reason,
    isNonTerminal: isNonTerminal,
    isAcknowledged: isAcknowledged,
  );
}

/// Convenience: true when [outcome] is a strict reconcile acknowledgement.
bool isDirectRideReconcileAcknowledged(DirectRideReconcileOutcome outcome) =>
    outcome.isAcknowledged;

// ===========================================================================
// DIRECT-RIDE-STOP-RECOVERY-RACE-1 / Commit 2 — server-truth recovery probe.
//
// A persisted `active` session must never be blindly resumed or abandoned after
// process restart. Classify the reconcile probe into an explicit recovery
// action without ever reissuing `/trip/stop`.
// ===========================================================================

/// Recovery action after probing `/trip/reconcile-direct-booking` for a
/// persisted active (or stale-active) DirectTripSession.
enum DirectTripRecoveryProbeAction {
  /// Booking finalize acknowledged — clear session; no meter restore.
  clearAcknowledged,

  /// Server reports the trip is still active (HTTP 409 non-terminal).
  retainServerActive,

  /// Trip appears stopped/pending — rewrite lifecycle and reconcile.
  rewriteStoppedPending,

  /// Transport/decode failure — retain evidence for a later retry.
  retainTransportUnknown,

  /// Response identity does not match the persisted session.
  retainIdentityMismatch,
}

/// Pure classifier for an active-session recovery probe. Unit-tested.
DirectTripRecoveryProbeAction classifyDirectTripRecoveryProbe({
  required DirectTripSession session,
  required DirectRideReconcileOutcome outcome,
}) {
  if (outcome.isAcknowledged) {
    return DirectTripRecoveryProbeAction.clearAcknowledged;
  }
  if (!outcome.transportSucceeded) {
    return DirectTripRecoveryProbeAction.retainTransportUnknown;
  }
  if (outcome.isNonTerminal) {
    return DirectTripRecoveryProbeAction.retainServerActive;
  }

  final reqTrip = session.tripId.trim();
  final expBooking = session.bookingId.trim();
  final respTrip = (outcome.responseTripId ?? '').trim();
  final respBooking = (outcome.responseBookingId ?? '').trim();
  if (respTrip.isNotEmpty && respTrip != reqTrip) {
    return DirectTripRecoveryProbeAction.retainIdentityMismatch;
  }
  if (respBooking.isNotEmpty && respBooking != expBooking) {
    return DirectTripRecoveryProbeAction.retainIdentityMismatch;
  }

  // Matching (or empty response) identities with non-acknowledged finalize →
  // treat as stopped/pending and drive the existing reconcile backoff.
  return DirectTripRecoveryProbeAction.rewriteStoppedPending;
}

/// True when a persisted session has the durable ids required for a server
/// truth probe (never invent ids).
bool directTripSessionHasProbeIdentity(DirectTripSession? session) {
  if (session == null) return false;
  return session.hasTripId && session.hasBookingId;
}

// ===========================================================================
// DIRECT-RIDE-EXISTING-BOOKING-OWNERSHIP-1 — reopen safety helpers.
//
// A booking that originated from a street/direct ride must never be routed
// through the planned booking lifecycle when it is reopened from the Bookings
// screen. The following pure helpers let the driver home page (and future
// callers) make that routing decision from record fields alone, so a listing
// row can be classified without any network IO.
//
// Detection uses one shared rule and is deliberately conservative:
//   * `booking_id` starts with `street_`,           OR
//   * `source` / `booking_source` == `street_ride`, OR
//   * `ride_type` / `rideType` == `direct`.
//
// Nested `booking` and `record` maps (as returned by the booking worker's
// `/tracking/booking` hydration and by the read-model list rows) are also
// inspected so the helper works uniformly across every client surface.
// ===========================================================================

bool _looksLikeStreetIdRaw(String id) {
  final trimmed = id.trim().toLowerCase();
  return trimmed.startsWith('street_');
}

bool _isStreetRideSource(String v) => v.trim().toLowerCase() == 'street_ride';
bool _isDirectRideType(String v) => v.trim().toLowerCase() == 'direct';

/// Returns `true` when [record] represents a street/direct ride under the
/// shared classification rule. Accepts flattened list rows, hydrated
/// `/tracking/booking` responses (nested `booking`) and full `record` maps.
///
/// Pure; no IO; safe on `null`/empty input.
bool isStreetDirectBooking(Map<String, dynamic>? record) {
  if (record == null || record.isEmpty) return false;

  String s(Object? v) => v == null ? '' : v.toString();

  final bookingId = s(record['booking_id'] ?? record['bookingId']);
  if (bookingId.isNotEmpty && _looksLikeStreetIdRaw(bookingId)) return true;

  final source = s(
    record['source'] ?? record['booking_source'] ?? record['bookingSource'],
  );
  if (source.trim().isNotEmpty && _isStreetRideSource(source)) return true;

  final rideType = s(record['ride_type'] ?? record['rideType']);
  if (rideType.trim().isNotEmpty && _isDirectRideType(rideType)) return true;

  for (final nestedKey in const ['booking', 'record']) {
    final nested = record[nestedKey];
    if (nested is Map) {
      if (isStreetDirectBooking(Map<String, dynamic>.from(nested))) return true;
    }
  }
  return false;
}

/// Authoritative direct-ride identifiers for an already-running street/direct
/// ride.
///
/// Minimum identity is [bookingId] + [trackingTripId]. [directRideKey] is
/// optional on reopen (create-idempotency only on the server); when present on
/// a local record it is preserved, never synthesized.
///
/// The client MUST NOT invent, reconstruct or regenerate either value.
class StreetDirectResumeIdentity {
  const StreetDirectResumeIdentity({
    required this.bookingId,
    required this.trackingTripId,
    this.directRideKey = '',
  });

  final String bookingId;
  final String trackingTripId;

  /// Optional. Empty when the server keeps the key private. Never invent.
  final String directRideKey;
}

String _firstNonEmptyDeep(Map<String, dynamic>? record, List<String> keys) {
  if (record == null || record.isEmpty) return '';
  for (final k in keys) {
    final v = record[k];
    if (v != null) {
      final t = v.toString().trim();
      if (t.isNotEmpty) return t;
    }
  }
  for (final nestedKey in const ['booking', 'record']) {
    final nested = record[nestedKey];
    if (nested is Map) {
      final t = _firstNonEmptyDeep(
        Map<String, dynamic>.from(nested),
        keys,
      );
      if (t.isNotEmpty) return t;
    }
  }
  return '';
}

/// Resolves the minimum direct-ride identity from [record]. Returns `null`
/// when [record] is not street/direct or when `tracking_trip_id` is missing.
///
/// `direct_ride_key` is NOT required. A `null` result MUST be treated as
/// "cannot resume" — never fabricate identifiers and never enter the planned
/// lifecycle for a street/direct record.
StreetDirectResumeIdentity? resolveStreetDirectResumeIdentity(
  Map<String, dynamic>? record, {
  required String bookingId,
}) {
  final safeBookingId = bookingId.trim();
  if (safeBookingId.isEmpty) return null;
  if (!isStreetDirectBooking(record)) return null;

  final trip = _firstNonEmptyDeep(record, const [
    'tracking_trip_id',
    'trackingTripId',
  ]);
  if (trip.isEmpty) return null;

  final key = _firstNonEmptyDeep(record, const [
    'direct_ride_key',
    'directRideKey',
  ]);

  return StreetDirectResumeIdentity(
    bookingId: safeBookingId,
    trackingTripId: trip,
    directRideKey: key,
  );
}

// ===========================================================================
// DIRECT-RIDE-RESUME-CONTEXT-MODEL-1 — authorized resume-context contract.
//
// Proposed `POST /trip/resume-context-for-booking` response shape (client
// model only). Runtime networking / `_goToRide` wiring is intentionally NOT
// in this commit. Until that wiring lands, [openExistingRideDecision] keeps
// its conservative local-record gate (still requires a non-empty
// `direct_ride_key` on the listing/hydrate record so reopen cannot proceed
// from trip id alone without the authorized endpoint).
// ===========================================================================

/// Server-provided lifecycle mode for reopening an existing street/direct ride.
enum DirectRideResumeMode {
  /// Trip is active; client may enter live direct-ride driver state.
  activeResume,

  /// Trip is stopped; booking finalize is still pending — reconcile only.
  reconcilePending,

  /// Booking/trip already completed/finalized — refresh list UI only.
  refreshOnly,

  /// Hard deny (cancelled, mismatch, unauthorized linkage, etc.).
  rejected,

  /// Malformed / unrecognized mode — fail closed.
  unknown,
}

/// Immutable parsed resume context from the proposed authorized endpoint.
class DirectRideResumeContext {
  const DirectRideResumeContext({
    required this.ok,
    required this.bookingId,
    required this.trackingTripId,
    required this.tripStatus,
    required this.bookingStatus,
    required this.bookingFinalizeState,
    required this.bookingFinalized,
    required this.resumeMode,
    this.rejectReason = '',
  });

  final bool ok;
  final String bookingId;
  final String trackingTripId;
  final String tripStatus;
  final String bookingStatus;
  final String bookingFinalizeState;
  final bool bookingFinalized;
  final DirectRideResumeMode resumeMode;
  final String rejectReason;
}

/// Outcome of [validateDirectRideResumeContext].
class DirectRideResumeContextDecision {
  const DirectRideResumeContextDecision._({
    required this.mode,
    required this.context,
    required this.rejectReason,
  });

  const DirectRideResumeContextDecision.rejected(String reason)
      : mode = DirectRideResumeMode.rejected,
        context = null,
        rejectReason = reason;

  const DirectRideResumeContextDecision.unknown(String reason)
      : mode = DirectRideResumeMode.unknown,
        context = null,
        rejectReason = reason;

  final DirectRideResumeMode mode;
  final DirectRideResumeContext? context;
  final String rejectReason;

  /// Live `_directRideActive` / cockpit resume — active mode only.
  bool get allowsLiveDriverState =>
      mode == DirectRideResumeMode.activeResume && context != null;

  /// May call reconcile (never `/trip/stop` invent) for stopped+pending.
  bool get allowsReconcile =>
      mode == DirectRideResumeMode.reconcilePending && context != null;

  /// Refresh bookings list / UI only — never enter live direct state.
  bool get isRefreshOnly => mode == DirectRideResumeMode.refreshOnly;

  bool get isRejected =>
      mode == DirectRideResumeMode.rejected ||
      mode == DirectRideResumeMode.unknown;
}

String _normResumeToken(Object? raw) =>
    (raw ?? '').toString().trim().toLowerCase().replaceAll('-', '_');

/// Map an explicit `resume_mode` token from the proposed server response.
DirectRideResumeMode parseDirectRideResumeModeToken(Object? raw) {
  switch (_normResumeToken(raw)) {
    case 'active_resume':
    case 'activeresume':
      return DirectRideResumeMode.activeResume;
    case 'reconcile_pending':
    case 'reconcilepending':
      return DirectRideResumeMode.reconcilePending;
    case 'refresh_only':
    case 'refreshonly':
      return DirectRideResumeMode.refreshOnly;
    case 'rejected':
      return DirectRideResumeMode.rejected;
    case '':
    case 'unknown':
      return DirectRideResumeMode.unknown;
    default:
      return DirectRideResumeMode.unknown;
  }
}

bool _resumeBookingFinalizationCompleted({
  required bool bookingFinalized,
  required String bookingFinalizeState,
}) {
  if (bookingFinalized) return true;
  final state = _normResumeToken(bookingFinalizeState);
  return state == kDirectTripFinalizeCompleted || state == 'complete';
}

bool _resumeBookingIsCancelled(String bookingStatus) =>
    streetRideCompanyBucket(bookingStatus) == StreetRideCompanyBucket.cancelled;

bool _resumeBookingIsCompleted(String bookingStatus) =>
    streetRideCompanyBucket(bookingStatus) == StreetRideCompanyBucket.completed;

/// Derive [DirectRideResumeMode] from lifecycle fields when the server omits
/// an explicit `resume_mode` (or for pure unit mapping proofs).
DirectRideResumeMode mapDirectRideResumeModeFromLifecycle({
  required String tripStatus,
  required String bookingStatus,
  required String bookingFinalizeState,
  required bool bookingFinalized,
}) {
  if (_resumeBookingIsCancelled(bookingStatus)) {
    return DirectRideResumeMode.rejected;
  }
  final finalized = _resumeBookingFinalizationCompleted(
    bookingFinalized: bookingFinalized,
    bookingFinalizeState: bookingFinalizeState,
  );
  if (finalized || _resumeBookingIsCompleted(bookingStatus)) {
    return DirectRideResumeMode.refreshOnly;
  }
  final trip = _normResumeToken(tripStatus);
  if (trip == 'stopped' && !finalized) {
    return DirectRideResumeMode.reconcilePending;
  }
  if (trip == 'active' && !finalized) {
    return DirectRideResumeMode.activeResume;
  }
  return DirectRideResumeMode.unknown;
}

/// Pure parser for the proposed resume-context JSON body.
///
/// Never reads a client-invented trip id from outside [decoded]. Malformed
/// input yields `ok: false` + [DirectRideResumeMode.unknown].
DirectRideResumeContext parseDirectRideResumeContext(Object? decoded) {
  if (decoded is! Map) {
    return const DirectRideResumeContext(
      ok: false,
      bookingId: '',
      trackingTripId: '',
      tripStatus: '',
      bookingStatus: '',
      bookingFinalizeState: '',
      bookingFinalized: false,
      resumeMode: DirectRideResumeMode.unknown,
      rejectReason: 'malformed_response',
    );
  }
  final map = Map<String, dynamic>.from(decoded);
  final ok = map['ok'] == true;
  final bookingId =
      (map['booking_id'] ?? map['bookingId'] ?? '').toString().trim();
  final trackingTripId = (map['tracking_trip_id'] ??
          map['trackingTripId'] ??
          map['trip_id'] ??
          map['tripId'] ??
          '')
      .toString()
      .trim();
  final tripStatus =
      (map['trip_status'] ?? map['tripStatus'] ?? '').toString().trim();
  final bookingStatus =
      (map['booking_status'] ?? map['bookingStatus'] ?? '').toString().trim();
  final finalizeState = (map['booking_finalize_state'] ??
          map['bookingFinalizeState'] ??
          '')
      .toString()
      .trim()
      .toLowerCase();
  final bookingFinalized = map['booking_finalized'] == true ||
      map['bookingFinalized'] == true ||
      finalizeState == kDirectTripFinalizeCompleted;
  final rejectReason =
      (map['reject_reason'] ?? map['rejectReason'] ?? '').toString().trim();

  final hasExplicitMode = map.containsKey('resume_mode') ||
      map.containsKey('resumeMode');
  final DirectRideResumeMode mode;
  if (hasExplicitMode) {
    mode = parseDirectRideResumeModeToken(
      map['resume_mode'] ?? map['resumeMode'],
    );
  } else {
    mode = mapDirectRideResumeModeFromLifecycle(
      tripStatus: tripStatus,
      bookingStatus: bookingStatus,
      bookingFinalizeState: finalizeState,
      bookingFinalized: bookingFinalized,
    );
  }

  return DirectRideResumeContext(
    ok: ok,
    bookingId: bookingId,
    trackingTripId: trackingTripId,
    tripStatus: tripStatus,
    bookingStatus: bookingStatus,
    bookingFinalizeState: finalizeState,
    bookingFinalized: bookingFinalized,
    resumeMode: mode,
    rejectReason: rejectReason,
  );
}

/// Strict validation of a parsed resume context against the booking the
/// driver tapped.
///
/// [clientSuppliedTripId] is accepted only to prove it cannot override the
/// response identity — it is never used as [DirectRideResumeContext.trackingTripId].
///
/// [bookingClassificationRecord] should be the local list/hydrate row used for
/// [isStreetDirectBooking] (must already be street/direct).
DirectRideResumeContextDecision validateDirectRideResumeContext({
  required String requestedBookingId,
  required DirectRideResumeContext? context,
  Map<String, dynamic>? bookingClassificationRecord,
  String? clientSuppliedTripId,
}) {
  // Security: any caller-supplied trip id is discarded. Response identity
  // alone is authoritative (never merged / never overrides).
  final ignoredClientTripId = (clientSuppliedTripId ?? '').trim();
  assert(ignoredClientTripId.isEmpty || ignoredClientTripId.isNotEmpty);

  if (context == null) {
    return const DirectRideResumeContextDecision.rejected('missing_context');
  }
  if (!context.ok) {
    return DirectRideResumeContextDecision.rejected(
      context.rejectReason.isEmpty ? 'not_ok' : context.rejectReason,
    );
  }

  final requested = requestedBookingId.trim();
  if (requested.isEmpty) {
    return const DirectRideResumeContextDecision.rejected(
      'missing_requested_booking_id',
    );
  }
  if (context.bookingId.trim() != requested) {
    return const DirectRideResumeContextDecision.rejected(
      'booking_id_mismatch',
    );
  }

  final classifyRecord = <String, dynamic>{
    ...?bookingClassificationRecord,
    'booking_id': requested,
  };
  if (!isStreetDirectBooking(classifyRecord)) {
    return const DirectRideResumeContextDecision.rejected(
      'not_street_direct',
    );
  }

  if (_resumeBookingIsCancelled(context.bookingStatus)) {
    return const DirectRideResumeContextDecision.rejected(
      'booking_cancelled',
    );
  }

  final tripId = context.trackingTripId.trim();
  final tripStatus = _normResumeToken(context.tripStatus);
  final finalized = _resumeBookingFinalizationCompleted(
    bookingFinalized: context.bookingFinalized,
    bookingFinalizeState: context.bookingFinalizeState,
  );

  switch (context.resumeMode) {
    case DirectRideResumeMode.activeResume:
      if (tripId.isEmpty) {
        return const DirectRideResumeContextDecision.rejected(
          'missing_tracking_trip_id',
        );
      }
      if (tripStatus != 'active') {
        return const DirectRideResumeContextDecision.rejected(
          'active_requires_active_trip',
        );
      }
      if (_resumeBookingIsCompleted(context.bookingStatus) || finalized) {
        return const DirectRideResumeContextDecision.rejected(
          'active_forbidden_when_completed_or_finalized',
        );
      }
      return DirectRideResumeContextDecision._(
        mode: DirectRideResumeMode.activeResume,
        context: context,
        rejectReason: '',
      );

    case DirectRideResumeMode.reconcilePending:
      if (tripId.isEmpty) {
        return const DirectRideResumeContextDecision.rejected(
          'missing_tracking_trip_id',
        );
      }
      if (tripStatus != 'stopped') {
        return const DirectRideResumeContextDecision.rejected(
          'reconcile_requires_stopped_trip',
        );
      }
      if (finalized || _resumeBookingIsCompleted(context.bookingStatus)) {
        return const DirectRideResumeContextDecision.rejected(
          'reconcile_forbidden_when_finalized',
        );
      }
      return DirectRideResumeContextDecision._(
        mode: DirectRideResumeMode.reconcilePending,
        context: context,
        rejectReason: '',
      );

    case DirectRideResumeMode.refreshOnly:
      // Accepted as a non-live decision only — never allowsLiveDriverState.
      return DirectRideResumeContextDecision._(
        mode: DirectRideResumeMode.refreshOnly,
        context: context,
        rejectReason: '',
      );

    case DirectRideResumeMode.rejected:
      return DirectRideResumeContextDecision.rejected(
        context.rejectReason.isEmpty ? 'rejected' : context.rejectReason,
      );

    case DirectRideResumeMode.unknown:
      return DirectRideResumeContextDecision.unknown(
        context.rejectReason.isEmpty ? 'unknown_mode' : context.rejectReason,
      );
  }
}

/// Routing decision produced by [openExistingRideDecision]. The driver home
/// page acts on this decision instead of duplicating the classification logic
/// across multiple callers.
enum OpenExistingRideDecisionKind {
  /// Ordinary planned booking — retain the existing lifecycle unchanged.
  planned,

  /// Street/direct booking with authoritative resume identity — enter the
  /// existing direct-ride lifecycle without generating a new key or trip id.
  streetResume,

  /// Street/direct booking without authoritative resume identity — the caller
  /// MUST fail safely and never enter the planned lifecycle.
  streetUnavailable,
}

class OpenExistingRideDecision {
  const OpenExistingRideDecision._(this.kind, this.identity);

  const OpenExistingRideDecision.planned()
      : kind = OpenExistingRideDecisionKind.planned,
        identity = null;

  const OpenExistingRideDecision.streetResume(this.identity)
      : kind = OpenExistingRideDecisionKind.streetResume;

  const OpenExistingRideDecision.streetUnavailable()
      : kind = OpenExistingRideDecisionKind.streetUnavailable,
        identity = null;

  final OpenExistingRideDecisionKind kind;
  final StreetDirectResumeIdentity? identity;

  bool get isPlanned => kind == OpenExistingRideDecisionKind.planned;
  bool get isStreetResume => kind == OpenExistingRideDecisionKind.streetResume;
  bool get isStreetUnavailable =>
      kind == OpenExistingRideDecisionKind.streetUnavailable;
}

// ===========================================================================
// DIRECT-RIDE-PLANNED-STOP-GUARD-1 — stop lifecycle routing.
//
// Once a booking is classified as street/direct, its stop MUST take the
// direct-ride finalization path. The client must never fall back to
// `/track/session/stop` planned semantics, `/trip/record-planned-stop` or a
// generic `/bookings/{id}/status` COMPLETED write for such a booking, even
// when `_directRideActive == false` (recovered/stale/future state).
//
// Selection rule:
//   * NOT street/direct     -> planned (existing lifecycle unchanged).
//   * street/direct + tracking trip id present -> directFinalize.
//   * street/direct + no tracking trip id      -> directUnavailable (safe fail).
//
// Complete authoritative direct identity for STOP purposes means the client
// holds a non-empty `_activeDirectTripId`; that is what
// `_stopDirectTripSessionOnWorker` needs to call `/trip/stop` and let the
// booking worker apply `finalize-direct`.
// ===========================================================================

enum StopTripLifecycleKind {
  /// Ordinary planned booking — keep the existing planned stop lifecycle.
  planned,

  /// Street/direct booking that can be finalized authoritatively.
  directFinalize,

  /// Street/direct booking whose direct identity is incomplete — the caller
  /// MUST fail safely: no planned endpoint, no generic COMPLETED, no clearing
  /// of reconciliation evidence, no new key.
  directUnavailable,
}

class StopTripLifecycleDecision {
  const StopTripLifecycleDecision._({required this.kind, required this.tripId});

  const StopTripLifecycleDecision.planned()
      : kind = StopTripLifecycleKind.planned,
        tripId = null;

  const StopTripLifecycleDecision.directFinalize(this.tripId)
      : kind = StopTripLifecycleKind.directFinalize;

  const StopTripLifecycleDecision.directUnavailable()
      : kind = StopTripLifecycleKind.directUnavailable,
        tripId = null;

  final StopTripLifecycleKind kind;

  /// The authoritative tracking trip id, only non-null for [directFinalize].
  final String? tripId;

  bool get isPlanned => kind == StopTripLifecycleKind.planned;
  bool get isDirectFinalize => kind == StopTripLifecycleKind.directFinalize;
  bool get isDirectUnavailable =>
      kind == StopTripLifecycleKind.directUnavailable;

  /// Convenience: any street/direct classification (finalize OR unavailable).
  bool get isStreetDirect => !isPlanned;
}

/// Decide how `_stopTrip` (or any equivalent caller) should route the stop of
/// a booking. Pure; unit-tested; the single source of truth for street/direct
/// stop routing on the client.
///
/// - [bookingDetails] MUST be the raw record view (either
///   `BookingItem.details` or a `_bookingScopeViewFor` map). It is inspected
///   for `source`, `booking_source`, `ride_type`, and nested `booking`/`record`.
/// - [bookingId] is used for the `street_` prefix classification.
/// - [activeDirectTripId] is the in-memory tracking trip id from prior direct
///   ride start. When empty and the booking is street/direct, we cannot
///   finalize authoritatively — safe fail.
/// - [directRideActive] is accepted so callers can pass their observation
///   verbatim; it MUST NOT override a street/direct classification into
///   planned. It is only used to promote a still-active direct session into
///   `directFinalize` if a trip id is also present.
StopTripLifecycleDecision stopTripLifecycleDecision({
  required Map<String, dynamic> bookingDetails,
  required String bookingId,
  required String? activeDirectTripId,
  required bool directRideActive,
}) {
  final safeBookingId = bookingId.trim();
  final record = <String, dynamic>{
    ...bookingDetails,
    if (safeBookingId.isNotEmpty) 'booking_id': safeBookingId,
  };
  if (!isStreetDirectBooking(record)) {
    return const StopTripLifecycleDecision.planned();
  }
  final trip = (activeDirectTripId ?? '').trim();
  if (trip.isEmpty) {
    return const StopTripLifecycleDecision.directUnavailable();
  }
  // [directRideActive] is intentionally observed but never used to *override*
  // the classification. Even when it is `false` (recovered state, stale UI
  // path), the classification-first rule keeps the stop on the direct
  // finalization path so a stale flag can never divert a street/direct
  // booking into planned completion.
  //
  // Reference the parameter defensively so a future refactor cannot silently
  // drop it from the signature without breaking these unit tests.
  assert(directRideActive || !directRideActive);
  return StopTripLifecycleDecision.directFinalize(trip);
}

/// Decide how `_goToRide` (or any equivalent caller) should route an opened
/// booking. Pure; unit-tested; the single source of truth for street/direct
/// detection on the client.
///
/// Runtime gate (until resume-context endpoint wiring): street/direct rows
/// still require a non-empty local `direct_ride_key` in addition to
/// `tracking_trip_id` before [streetResume]. List/hydrate paths today expose
/// neither, so reopen remains safe-fail. Live resume without a key must go
/// through [validateDirectRideResumeContext] once the authorized endpoint is
/// wired — not through this helper inventing identifiers.
OpenExistingRideDecision openExistingRideDecision({
  required String bookingId,
  required Map<String, dynamic> details,
}) {
  final safeBookingId = bookingId.trim();
  final record = <String, dynamic>{
    ...details,
    if (safeBookingId.isNotEmpty) 'booking_id': safeBookingId,
  };
  if (!isStreetDirectBooking(record)) {
    return const OpenExistingRideDecision.planned();
  }
  final identity = resolveStreetDirectResumeIdentity(
    record,
    bookingId: safeBookingId,
  );
  if (identity == null) {
    return const OpenExistingRideDecision.streetUnavailable();
  }
  // Conservative local-record gate: do not enter live resume from a listing
  // row that only carries a trip id. The authorized resume-context path is
  // the sole future way to resume without a client-held direct_ride_key.
  if (identity.directRideKey.trim().isEmpty) {
    return const OpenExistingRideDecision.streetUnavailable();
  }
  return OpenExistingRideDecision.streetResume(identity);
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
  final complianceRaw = (decoded['compliance_emit_state'] ??
          decoded['complianceEmitState'] ??
          '')
      .toString()
      .trim()
      .toLowerCase();
  return DirectRideStopResult(
    ok: ok,
    totalEur: total,
    bookingId: bookingIdRaw.isEmpty ? null : bookingIdRaw,
    bookingFinalizeState:
        stateRaw.isEmpty ? kDirectTripFinalizePending : stateRaw,
    bookingFinalized: finalized,
    complianceEmitState: complianceRaw.isEmpty ? null : complianceRaw,
  );
}
