/// PLANNED-STOP-HISTORY-DURABILITY-P0-8
///
/// Durable STOP intent for PLANNED rides.
///
/// ## Why this exists
///
/// For a planned ride, `POST /trip/record-planned-stop` is the ONLY code path
/// that materializes the durable chain: tracking trip KV, `trips_index`, the
/// driver-history projection and the Chiron `ride_stop` outbox row. Booking
/// `COMPLETED` is written by a different worker over a different call and has no
/// dependency on that chain, and neither `/trip/reconcile-planned-stop` nor
/// `/trip/recover-planned-pending` can create a missing trip row — they only
/// reconcile rows that already exist.
///
/// Field incident (PLN-2026-000387 / booking 2026-08-168): on poor network the
/// tracking call never landed, yet the OUTBOUND leg still became COMPLETED. The
/// driven ride therefore existed nowhere durable — no trip, no history, no
/// Chiron, no consumer_sale.
///
/// Street rides survived the same test because `/trip/start-direct` writes the
/// trip record and both index entries at START, and because the client keeps a
/// durable on-disk `DirectTripSession` that a later startup drains.
///
/// ## The contract this file encodes
///
/// A planned ride may only reach a terminal COMPLETED projection when either
/// the durable chain is confirmed, or a durable idempotent STOP intent has been
/// persisted that guarantees the chain completes later. See
/// [plannedTerminalProjectionDecision].
///
/// ## Idempotency
///
/// Replay is safe because the server is already idempotent for a given
/// (booking, leg): the tracking worker derives `trip_id` deterministically (see
/// [plannedStopTripId]), `prependIndex` de-duplicates index entries, the Chiron
/// `event_id` is deterministic and APPLIED never regresses, and consumer_sale
/// is guarded by its own idempotency key. So a replayed intent cannot produce a
/// duplicate trip, history row, Chiron event or Billit record.
///
/// ## Never invent ride truth
///
/// An intent stores the EXACT request body measured at STOP time and replays it
/// verbatim. Recovery never synthesizes distance, waiting time or stop
/// timestamps. If a value was not measured it stays absent.
///
/// These helpers are pure and dependency-free so the durability contract can be
/// unit-tested without pumping the driver home widget (which needs Mapbox /
/// geolocation / http). Disk persistence lives in `compliance_local_stores.dart`.
library;

/// Max intents retained on disk per tenant/company.
///
/// A driver accumulates at most one intent per (booking, leg); the cap only
/// exists so a pathological offline streak cannot grow the file without bound.
const int kPlannedStopIntentMaxRecords = 50;

/// Mirror of the tracking worker's `sanitizeTripIdentityToken` (tracking worker
/// `fluxidi_tracking_api_worker_V2_1_with_route_index.js`).
///
/// MUST stay byte-identical in behaviour, otherwise a replayed intent would
/// address a different `trip_id` than the original call and duplicate history.
String? sanitizePlannedTripIdentityToken(String? value, {int maxLen = 96}) {
  final raw = (value ?? '').trim();
  if (raw.isEmpty) return null;
  final sanitized = raw
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9_-]+'), '_')
      .replaceAll(RegExp(r'_+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');
  if (sanitized.isEmpty) return null;
  return sanitized.length > maxLen ? sanitized.substring(0, maxLen) : sanitized;
}

/// Deterministic planned `trip_id` for a (booking, leg), mirroring the tracking
/// worker's derivation in `handleRecordPlannedStop`.
///
/// `planned_{bookingId}_{legId|rowKey}` when a leg identity exists, else
/// `planned_{bookingId}`. Being deterministic is what makes replay idempotent.
String plannedStopTripId({
  required String bookingId,
  String? legId,
  String? rowKey,
}) {
  final suffix =
      sanitizePlannedTripIdentityToken(legId) ??
      sanitizePlannedTripIdentityToken(rowKey);
  final booking = bookingId.trim();
  return suffix == null ? 'planned_$booking' : 'planned_${booking}_$suffix';
}

/// Outcome of the terminal-projection durability gate.
enum PlannedTerminalProjectionDecision {
  /// The durable STOP/history chain is confirmed materialized (invariant A).
  allowedChainConfirmed,

  /// The chain is not confirmed, but a durable idempotent STOP intent is
  /// persisted and will complete it later (invariant B).
  allowedDurableIntent,

  /// Neither holds. Projecting COMPLETED here would lose the driven ride.
  blockedNoDurability,
}

/// The PLANNED-STOP-HISTORY-DURABILITY-P0-8 product invariant, as a pure
/// decision.
///
/// A planned ride must not become definitively COMPLETED unless the durable
/// STOP/history chain is confirmed, or a durable idempotent STOP/finalize
/// intent exists that guarantees the chain will complete later.
///
/// Street/direct rides are out of scope: they materialize their trip at START
/// and are gated separately by the finalize-ack gate.
PlannedTerminalProjectionDecision plannedTerminalProjectionDecision({
  required bool trackingStopMaterialized,
  required bool durableIntentPersisted,
}) {
  if (trackingStopMaterialized) {
    return PlannedTerminalProjectionDecision.allowedChainConfirmed;
  }
  if (durableIntentPersisted) {
    return PlannedTerminalProjectionDecision.allowedDurableIntent;
  }
  return PlannedTerminalProjectionDecision.blockedNoDurability;
}

/// Whether a terminal COMPLETED projection may proceed.
bool plannedTerminalProjectionAllowed({
  required bool trackingStopMaterialized,
  required bool durableIntentPersisted,
}) {
  return plannedTerminalProjectionDecision(
        trackingStopMaterialized: trackingStopMaterialized,
        durableIntentPersisted: durableIntentPersisted,
      ) !=
      PlannedTerminalProjectionDecision.blockedNoDurability;
}

/// A durable, replayable planned-ride STOP intent.
///
/// [payload] is the verbatim `/trip/record-planned-stop` request body captured
/// at STOP time. Recovery replays it unchanged so no ride metric is ever
/// synthesized.
class PlannedStopIntent {
  const PlannedStopIntent({
    required this.intentId,
    required this.bookingId,
    required this.tenantId,
    required this.companyId,
    required this.driverId,
    required this.payload,
    required this.createdAtIso,
    required this.updatedAtIso,
    this.legId = '',
    this.rowKey = '',
    this.legType = '',
    this.attemptCount = 0,
    this.lastError = '',
  });

  /// Deterministic identity, equal to the server-side planned `trip_id`.
  final String intentId;
  final String bookingId;
  final String legId;
  final String rowKey;
  final String legType;
  final String tenantId;
  final String companyId;
  final String driverId;

  /// Verbatim `/trip/record-planned-stop` body measured at STOP time.
  final Map<String, dynamic> payload;

  final String createdAtIso;
  final String updatedAtIso;
  final int attemptCount;
  final String lastError;

  /// Builds an intent from the measured STOP payload.
  ///
  /// [payload] is stored as-is; nothing is derived, defaulted or invented.
  factory PlannedStopIntent.fromStopPayload({
    required String bookingId,
    required String tenantId,
    required String companyId,
    required String driverId,
    required Map<String, dynamic> payload,
    required DateTime nowUtc,
    String? legId,
    String? rowKey,
    String? legType,
  }) {
    final iso = nowUtc.toUtc().toIso8601String();
    return PlannedStopIntent(
      intentId: plannedStopTripId(
        bookingId: bookingId,
        legId: legId,
        rowKey: rowKey,
      ),
      bookingId: bookingId.trim(),
      legId: (legId ?? '').trim(),
      rowKey: (rowKey ?? '').trim(),
      legType: (legType ?? '').trim(),
      tenantId: tenantId.trim(),
      companyId: companyId.trim(),
      driverId: driverId.trim(),
      payload: Map<String, dynamic>.from(payload),
      createdAtIso: iso,
      updatedAtIso: iso,
    );
  }

  PlannedStopIntent copyWith({
    String? updatedAtIso,
    int? attemptCount,
    String? lastError,
    String? driverId,
  }) {
    return PlannedStopIntent(
      intentId: intentId,
      bookingId: bookingId,
      legId: legId,
      rowKey: rowKey,
      legType: legType,
      tenantId: tenantId,
      companyId: companyId,
      driverId: driverId ?? this.driverId,
      payload: payload,
      createdAtIso: createdAtIso,
      updatedAtIso: updatedAtIso ?? this.updatedAtIso,
      attemptCount: attemptCount ?? this.attemptCount,
      lastError: lastError ?? this.lastError,
    );
  }

  /// Records a failed replay attempt without touching the captured payload.
  PlannedStopIntent markAttemptFailed({
    required DateTime nowUtc,
    required String error,
  }) {
    return copyWith(
      updatedAtIso: nowUtc.toUtc().toIso8601String(),
      attemptCount: attemptCount + 1,
      lastError: error.trim(),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'intent_id': intentId,
    'booking_id': bookingId,
    'leg_id': legId,
    'row_key': rowKey,
    'leg_type': legType,
    'tenant_id': tenantId,
    'company_id': companyId,
    'driver_id': driverId,
    'payload': payload,
    'created_at': createdAtIso,
    'updated_at': updatedAtIso,
    'attempt_count': attemptCount,
    'last_error': lastError,
  };

  /// Parses a stored intent. Returns null for anything unusable, so a corrupt
  /// row can never crash startup recovery.
  static PlannedStopIntent? fromJson(Object? raw) {
    if (raw is! Map) return null;
    String str(String key) => (raw[key] ?? '').toString().trim();
    final intentId = str('intent_id');
    final bookingId = str('booking_id');
    final payloadRaw = raw['payload'];
    if (intentId.isEmpty || bookingId.isEmpty) return null;
    if (payloadRaw is! Map) return null;
    final attemptRaw = raw['attempt_count'];
    return PlannedStopIntent(
      intentId: intentId,
      bookingId: bookingId,
      legId: str('leg_id'),
      rowKey: str('row_key'),
      legType: str('leg_type'),
      tenantId: str('tenant_id'),
      companyId: str('company_id'),
      driverId: str('driver_id'),
      payload: Map<String, dynamic>.from(payloadRaw),
      createdAtIso: str('created_at'),
      updatedAtIso: str('updated_at'),
      attemptCount: attemptRaw is int
          ? attemptRaw
          : int.tryParse('$attemptRaw') ?? 0,
      lastError: str('last_error'),
    );
  }
}

/// Inserts or replaces [intent] in [existing], keyed by [PlannedStopIntent
/// .intentId].
///
/// The updated intent moves to the front and the list is capped at
/// [kPlannedStopIntentMaxRecords]. Keying by the deterministic intent id is
/// what stops a retried STOP from queuing the same ride twice.
List<PlannedStopIntent> upsertPlannedStopIntent(
  List<PlannedStopIntent> existing,
  PlannedStopIntent intent, {
  int maxRecords = kPlannedStopIntentMaxRecords,
}) {
  final next = <PlannedStopIntent>[
    intent,
    ...existing.where((e) => e.intentId != intent.intentId),
  ];
  return next.length > maxRecords ? next.sublist(0, maxRecords) : next;
}

/// Removes the intent with [intentId], used once the chain is confirmed.
List<PlannedStopIntent> removePlannedStopIntent(
  List<PlannedStopIntent> existing,
  String intentId,
) {
  final target = intentId.trim();
  return existing.where((e) => e.intentId != target).toList();
}

/// Intents belonging to exactly this tenant/company/driver.
///
/// A shared device must never replay another driver's or another company's
/// stop, so isolation is enforced on read as well as on write.
List<PlannedStopIntent> plannedStopIntentsForScope(
  List<PlannedStopIntent> existing, {
  required String tenantId,
  required String companyId,
  required String driverId,
}) {
  final tenant = tenantId.trim();
  final company = companyId.trim();
  final driver = driverId.trim();
  if (tenant.isEmpty || company.isEmpty) return const <PlannedStopIntent>[];
  return existing.where((e) {
    if (e.tenantId != tenant || e.companyId != company) return false;
    // Legacy rows without a driver stay recoverable by the scoped driver.
    return e.driverId.isEmpty || driver.isEmpty || e.driverId == driver;
  }).toList();
}
