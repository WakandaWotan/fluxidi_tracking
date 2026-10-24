/// OFFLINE-CASH-COLLECTION-P0
///
/// Durable pending cash-collection intent for chauffeur **Contant ontvangen**.
///
/// Offline STOP already persists on disk (`DirectTripSession` /
/// `PlannedStopIntent`) and reconnect drains that outbox. Cash mark-paid did
/// not: `_persistInCarPayment` POSTed immediately and treated any network
/// error as `paymentMarkFailed`. This module is the cash counterpart of that
/// existing local-outbox pattern — not a second sync architecture.
///
/// Server `/bookings/:id/payment` is already idempotent for a second cash
/// confirmation on the same booking. Replay therefore cannot create a second
/// financial registration, document or Billit row. A different already-paid
/// method must not be overwritten.
library;

import 'package:flutter/foundation.dart';

const String kOfflineCashPaymentMethod = 'cash';
const String kOfflineCashIdempotencyPrefix = 'cash_v1';
const String kOfflineCashPendingCopyKey = 'cashReceivedPendingSync';
const String kOfflineCashConflictCopyKey = 'cashReceivedMethodConflict';
const String kOfflineCashPendingStatusText =
    'Contant ontvangen · wacht op synchronisatie';

const int kOfflineCashIntentMaxRecords = 50;

enum OfflineCashIntentStatus { pending, synced, conflict }

enum OfflineCashServerOutcome {
  /// Canonical is unpaid / unknown — POST the stored cash payload.
  postCash,

  /// Same cash payment already applied. Treat as successful convergence.
  alreadyAppliedCash,

  /// Server already paid with a different method. Do not overwrite.
  methodConflict,

  /// Transient transport failure. Keep pending and retry later.
  retryableNetwork,

  /// Driver/company session missing. Keep pending; show sign-in copy.
  authRequired,

  /// Non-retryable application failure.
  failed,
}

enum OfflineCashUiPhase { unpaid, pendingSync, paid, conflict }

/// Deterministic idempotency identity: tenant + company + booking/trip + cash.
String offlineCashIdempotencyKey({
  required String tenantId,
  required String companyId,
  required String bookingId,
  String tripId = '',
}) {
  final tenant = tenantId.trim();
  final company = companyId.trim();
  final booking = bookingId.trim();
  final trip = tripId.trim();
  final ride = booking.isNotEmpty ? booking : trip;
  return [
    kOfflineCashIdempotencyPrefix,
    tenant,
    company,
    ride,
    if (booking.isNotEmpty && trip.isNotEmpty) trip,
    kOfflineCashPaymentMethod,
  ].where((part) => part.isNotEmpty).join(':');
}

bool isOfflineCashMethod(String? method) {
  final m = (method ?? '').trim().toLowerCase();
  return m == 'cash' || m == 'contant';
}

bool isPaidPaymentStatus(String? status) {
  final s = (status ?? '').trim().toLowerCase();
  return s == 'paid' ||
      s == 'confirmed' ||
      s == 'completed' ||
      s == 'success' ||
      s == 'settled';
}

/// Classify an already-stored canonical payment before POSTing cash.
OfflineCashServerOutcome classifyExistingPaymentForOfflineCash({
  required String? paymentStatus,
  required String? paymentMethod,
}) {
  if (!isPaidPaymentStatus(paymentStatus)) {
    return OfflineCashServerOutcome.postCash;
  }
  if (isOfflineCashMethod(paymentMethod)) {
    return OfflineCashServerOutcome.alreadyAppliedCash;
  }
  return OfflineCashServerOutcome.methodConflict;
}

/// Classify a mark-paid HTTP response for the same stored cash intent.
OfflineCashServerOutcome classifyOfflineCashHttpResponse({
  required int statusCode,
  Map<String, dynamic>? body,
  String? paymentMethod,
}) {
  if (statusCode == 401) return OfflineCashServerOutcome.authRequired;
  if (statusCode >= 500) return OfflineCashServerOutcome.retryableNetwork;
  final error = (body?['error'] ?? '').toString().trim().toLowerCase();
  final status = (body?['payment_status'] ?? body?['paymentStatus'] ?? '')
      .toString();
  final method =
      (body?['payment_method'] ?? body?['paymentMethod'] ?? paymentMethod ?? '')
          .toString();
  if (statusCode >= 200 && statusCode < 300) {
    if (isPaidPaymentStatus(status) &&
        method.isNotEmpty &&
        !isOfflineCashMethod(method)) {
      return OfflineCashServerOutcome.methodConflict;
    }
    return OfflineCashServerOutcome.alreadyAppliedCash;
  }
  if (error == 'payment_already_paid' ||
      error == 'already_applied' ||
      error == 'already_paid') {
    if (method.isNotEmpty && !isOfflineCashMethod(method)) {
      return OfflineCashServerOutcome.methodConflict;
    }
    return OfflineCashServerOutcome.alreadyAppliedCash;
  }
  if (error == 'payment_already_paid_mollie' ||
      error == 'payment_already_paid_manual' ||
      error.contains('already_paid_different') ||
      error.contains('canonical_already_paid')) {
    if (isOfflineCashMethod(method)) {
      return OfflineCashServerOutcome.alreadyAppliedCash;
    }
    return OfflineCashServerOutcome.methodConflict;
  }
  if (statusCode == 409 && isPaidPaymentStatus(status)) {
    return classifyExistingPaymentForOfflineCash(
      paymentStatus: status,
      paymentMethod: method,
    );
  }
  if (statusCode >= 400 && statusCode < 500) {
    return OfflineCashServerOutcome.failed;
  }
  return OfflineCashServerOutcome.retryableNetwork;
}

bool isTransientPaymentNetworkError(Object error) {
  final name = error.runtimeType.toString();
  if (name.contains('SocketException') ||
      name.contains('TimeoutException') ||
      name.contains('HandshakeException') ||
      name.contains('ClientException') ||
      name.contains('HttpException')) {
    return true;
  }
  final text = error.toString().toLowerCase();
  return text.contains('socketexception') ||
      text.contains('timed out') ||
      text.contains('timeout') ||
      text.contains('failed host lookup') ||
      text.contains('network is unreachable') ||
      text.contains('connection refused') ||
      text.contains('connection failed') ||
      text.contains('clientexception') ||
      text.contains('failed to fetch') ||
      text.contains('network error');
}

bool shouldBlockConflictingPaymentMethods({
  required OfflineCashIntentStatus? status,
}) {
  return status == OfflineCashIntentStatus.pending;
}

OfflineCashUiPhase offlineCashUiPhase({
  required bool serverPaid,
  required OfflineCashIntentStatus? localStatus,
}) {
  if (localStatus == OfflineCashIntentStatus.conflict && !serverPaid) {
    return OfflineCashUiPhase.conflict;
  }
  if (serverPaid || localStatus == OfflineCashIntentStatus.synced) {
    return OfflineCashUiPhase.paid;
  }
  if (localStatus == OfflineCashIntentStatus.pending) {
    return OfflineCashUiPhase.pendingSync;
  }
  return OfflineCashUiPhase.unpaid;
}

String offlineCashStatusCopyKey(OfflineCashUiPhase phase) {
  switch (phase) {
    case OfflineCashUiPhase.pendingSync:
      return kOfflineCashPendingCopyKey;
    case OfflineCashUiPhase.conflict:
      return kOfflineCashConflictCopyKey;
    case OfflineCashUiPhase.paid:
      return 'paid';
    case OfflineCashUiPhase.unpaid:
      return 'unpaid';
  }
}

/// In-process mutex so reconnect + resume + receipt refresh post at most once.
class OfflineCashSyncGuard {
  OfflineCashSyncGuard._();
  static final Set<String> _inFlight = <String>{};

  static bool tryAcquire(String idempotencyKey) {
    final key = idempotencyKey.trim();
    if (key.isEmpty) return false;
    return _inFlight.add(key);
  }

  static void release(String idempotencyKey) {
    _inFlight.remove(idempotencyKey.trim());
  }

  @visibleForTesting
  static void resetForTest() => _inFlight.clear();

  @visibleForTesting
  static bool isInFlightForTest(String idempotencyKey) =>
      _inFlight.contains(idempotencyKey.trim());
}

/// Durable replayable cash-collection intent. [payload] is the verbatim
/// mark-paid body captured at tap time so reconnect never invents amounts.
class OfflineCashPaymentIntent {
  const OfflineCashPaymentIntent({
    required this.idempotencyKey,
    required this.tenantId,
    required this.companyId,
    required this.driverId,
    required this.bookingId,
    required this.payload,
    required this.createdAtIso,
    required this.updatedAtIso,
    this.tripId = '',
    this.endpoint = 'booking',
    this.parentBookingId = '',
    this.legId = '',
    this.status = OfflineCashIntentStatus.pending,
    this.conflictMethod = '',
    this.attemptCount = 0,
    this.lastError = '',
  });

  final String idempotencyKey;
  final String tenantId;
  final String companyId;
  final String driverId;
  final String bookingId;
  final String tripId;
  final String endpoint;
  final String parentBookingId;
  final String legId;
  final Map<String, dynamic> payload;
  final OfflineCashIntentStatus status;
  final String conflictMethod;
  final String createdAtIso;
  final String updatedAtIso;
  final int attemptCount;
  final String lastError;

  bool get isPending => status == OfflineCashIntentStatus.pending;

  OfflineCashPaymentIntent copyWith({
    OfflineCashIntentStatus? status,
    String? conflictMethod,
    String? updatedAtIso,
    int? attemptCount,
    String? lastError,
  }) {
    return OfflineCashPaymentIntent(
      idempotencyKey: idempotencyKey,
      tenantId: tenantId,
      companyId: companyId,
      driverId: driverId,
      bookingId: bookingId,
      tripId: tripId,
      endpoint: endpoint,
      parentBookingId: parentBookingId,
      legId: legId,
      payload: Map<String, dynamic>.from(payload),
      status: status ?? this.status,
      conflictMethod: conflictMethod ?? this.conflictMethod,
      createdAtIso: createdAtIso,
      updatedAtIso: updatedAtIso ?? this.updatedAtIso,
      attemptCount: attemptCount ?? this.attemptCount,
      lastError: lastError ?? this.lastError,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'idempotency_key': idempotencyKey,
      'tenant_id': tenantId,
      'company_id': companyId,
      'driver_id': driverId,
      'booking_id': bookingId,
      'trip_id': tripId,
      'endpoint': endpoint,
      'parent_booking_id': parentBookingId,
      'leg_id': legId,
      'payload': payload,
      'status': status.name,
      'conflict_method': conflictMethod,
      'created_at': createdAtIso,
      'updated_at': updatedAtIso,
      'attempt_count': attemptCount,
      'last_error': lastError,
    };
  }

  static OfflineCashPaymentIntent? fromJson(Object? decoded) {
    if (decoded is! Map) return null;
    final map = Map<String, dynamic>.from(decoded);
    final key = (map['idempotency_key'] ?? map['idempotencyKey'] ?? '')
        .toString()
        .trim();
    final tenant = (map['tenant_id'] ?? map['tenantId'] ?? '')
        .toString()
        .trim();
    final company = (map['company_id'] ?? map['companyId'] ?? '')
        .toString()
        .trim();
    final booking = (map['booking_id'] ?? map['bookingId'] ?? '')
        .toString()
        .trim();
    if (key.isEmpty || tenant.isEmpty || company.isEmpty) return null;
    final rawPayload = map['payload'];
    final payload = rawPayload is Map
        ? Map<String, dynamic>.from(rawPayload)
        : <String, dynamic>{};
    final statusName = (map['status'] ?? OfflineCashIntentStatus.pending.name)
        .toString();
    final status = OfflineCashIntentStatus.values.firstWhere(
      (value) => value.name == statusName,
      orElse: () => OfflineCashIntentStatus.pending,
    );
    return OfflineCashPaymentIntent(
      idempotencyKey: key,
      tenantId: tenant,
      companyId: company,
      driverId: (map['driver_id'] ?? map['driverId'] ?? '').toString().trim(),
      bookingId: booking,
      tripId: (map['trip_id'] ?? map['tripId'] ?? '').toString().trim(),
      endpoint: (map['endpoint'] ?? 'booking').toString().trim().isEmpty
          ? 'booking'
          : (map['endpoint'] ?? 'booking').toString().trim(),
      parentBookingId:
          (map['parent_booking_id'] ?? map['parentBookingId'] ?? '')
              .toString()
              .trim(),
      legId: (map['leg_id'] ?? map['legId'] ?? '').toString().trim(),
      payload: payload,
      status: status,
      conflictMethod: (map['conflict_method'] ?? map['conflictMethod'] ?? '')
          .toString(),
      createdAtIso: (map['created_at'] ?? map['createdAtIso'] ?? '').toString(),
      updatedAtIso: (map['updated_at'] ?? map['updatedAtIso'] ?? '').toString(),
      attemptCount: _asInt(map['attempt_count'] ?? map['attemptCount']),
      lastError: (map['last_error'] ?? map['lastError'] ?? '').toString(),
    );
  }

  static int _asInt(Object? value) {
    if (value is int) return value;
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}

List<OfflineCashPaymentIntent> upsertOfflineCashIntent(
  List<OfflineCashPaymentIntent> existing,
  OfflineCashPaymentIntent intent,
) {
  final next = <OfflineCashPaymentIntent>[
    for (final row in existing)
      if (row.idempotencyKey != intent.idempotencyKey) row,
    intent,
  ];
  if (next.length <= kOfflineCashIntentMaxRecords) return next;
  next.sort((a, b) => a.updatedAtIso.compareTo(b.updatedAtIso));
  return next.sublist(next.length - kOfflineCashIntentMaxRecords);
}

List<OfflineCashPaymentIntent> pendingOfflineCashIntents(
  List<OfflineCashPaymentIntent> existing, {
  required String tenantId,
  required String companyId,
  String driverId = '',
}) {
  final tenant = tenantId.trim();
  final company = companyId.trim();
  final driver = driverId.trim();
  return existing.where((row) {
    if (!row.isPending) return false;
    if (row.tenantId != tenant || row.companyId != company) return false;
    if (driver.isNotEmpty &&
        row.driverId.isNotEmpty &&
        row.driverId != driver) {
      return false;
    }
    return true;
  }).toList();
}

OfflineCashPaymentIntent? offlineCashIntentForRide(
  List<OfflineCashPaymentIntent> existing, {
  required String tenantId,
  required String companyId,
  required String bookingId,
  String tripId = '',
}) {
  final key = offlineCashIdempotencyKey(
    tenantId: tenantId,
    companyId: companyId,
    bookingId: bookingId,
    tripId: tripId,
  );
  for (final row in existing) {
    if (row.idempotencyKey == key) return row;
  }
  return null;
}

final ValueNotifier<int> offlineCashPaymentRevisionNotifier =
    ValueNotifier<int>(0);

void bumpOfflineCashPaymentRevision() {
  offlineCashPaymentRevisionNotifier.value++;
}
