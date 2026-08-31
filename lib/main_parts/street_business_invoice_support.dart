/// Pure, UI-agnostic support for the company-side "request a business invoice
/// for a completed street ride" feature (Phase STREET-BUSINESS-INVOICE-UI-1).
///
/// This library intentionally contains ONLY testable, side-effect-free logic:
///   - eligibility gating,
///   - buyer billing-identity payload building + validation,
///   - parsing of the request response and the documents-list envelope,
///   - backend error classification,
///   - a small per-booking lifecycle controller whose network I/O is INJECTED.
///
/// It never talks to the Booking/Tracking workers directly, never touches
/// Peppol, never mutates payment state, and never renders UI. The concrete
/// networking (POST request-business-invoice + GET documents) is supplied by
/// the UI layer via callbacks, which keeps this file unit-testable and keeps a
/// single networking stack (the app's existing `http` + scope/auth helpers).
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:fluxidi_tracking/company/booking_documents_leg_filter.dart';
import 'package:fluxidi_tracking/payment/consumer_sale_presentation.dart';

/// Per-booking lifecycle state for the invoice action UI.
enum StreetBusinessInvoiceUiState {
  /// Not a completed street ride (action must not be shown).
  unavailable,

  /// Eligible completed street ride with no invoice yet.
  eligibleNoInvoice,

  /// A request is in flight.
  submitting,

  /// POST succeeded; trusted locally, documents index not yet confirmed.
  issuedFromResponse,

  /// Invoice confirmed visible in the documents index.
  issuedIndexed,

  /// POST succeeded but the documents index did not expose it within the
  /// bounded polling window. The successful result is retained.
  visibilityDelayed,

  /// A request failed (see [StreetBusinessInvoiceErrorKind]).
  error,
}

/// Backend/network error kinds, mapped to localized text by the UI layer.
enum StreetBusinessInvoiceErrorKind {
  /// 409 billing_identity_conflict.
  identityConflict,

  /// 403 not_in_scope / forbidden.
  accessDenied,

  /// 403 driver_not_assigned / driver_session_required: the authenticated
  /// driver is not the assigned driver for this ride.
  driverNotAuthorized,

  /// 422 not_a_street_booking / booking_not_completed / non-invoiceable state:
  /// the action is only available for a completed street ride.
  notCompletedStreet,

  /// 422 billing_customer_not_ready / incomplete readiness.
  readiness,

  /// An invoice already exists for this booking; UI switches to "view".
  alreadyExists,

  /// Timeout / connectivity / non-JSON / unknown transport failure.
  network,

  /// Anything else.
  unknown,
}

const String kStreetBusinessInvoiceIdPrefix = 'street_';
const String _kStreetSourceToken = 'street_ride';

/// ride_type value that is used ONLY as a secondary consistency signal. It is
/// never, on its own, sufficient to make a booking a street ride.
const String kStreetRideTypeDirect = 'direct';

String _norm(Object? v) => (v ?? '').toString().trim();
String _lower(Object? v) => _norm(v).toLowerCase();
String _statusToken(Object? v) =>
    _norm(v).toUpperCase().replaceAll(RegExp(r'[-\s]+'), '_');

/// True when [bookingId]/[source]/[bookingSource] establish a *canonical*
/// street-ride identity. `ride_type == direct` is intentionally NOT accepted
/// here: it may only corroborate an already-canonical street ride, never make a
/// planned/customer booking eligible on its own.
bool hasCanonicalStreetIdentity({
  required String bookingId,
  String? source,
  String? bookingSource,
}) {
  return _lower(bookingId).startsWith(kStreetBusinessInvoiceIdPrefix) ||
      _lower(source) == _kStreetSourceToken ||
      _lower(bookingSource) == _kStreetSourceToken;
}

/// True when the booking is a canonical, completed street ride and is therefore
/// eligible for the company business-invoice action. Both paid and unpaid
/// completed street rides are eligible.
///
/// Strictness (UI-1B): a canonical street identity is REQUIRED
/// (booking_id starts with `street_`, or source/booking_source == `street_ride`).
/// `ride_type == direct` alone is never sufficient. Cancelled, refunded and
/// credited rides are excluded even when the raw status string reads COMPLETED.
bool isStreetRideBusinessInvoiceEligible({
  required String bookingId,
  String? source,
  String? bookingSource,
  String? rideType,
  required String status,
  bool isCancelled = false,
  bool isRefunded = false,
  bool isCredited = false,
}) {
  if (!hasCanonicalStreetIdentity(
    bookingId: bookingId,
    source: source,
    bookingSource: bookingSource,
  )) {
    return false;
  }
  if (isCancelled || isRefunded || isCredited) return false;
  final st = _statusToken(status);
  if (st == 'CANCELLED' || st == 'REFUNDED' || st == 'CREDITED') return false;
  return st == 'COMPLETED' || st == 'STOPPED';
}

/// True when a receipt/trip status token means the ride is finished enough for
/// a post-ride business invoice (Tracking uses `stopped`, Booking uses
/// `COMPLETED`).
bool isStreetBusinessInvoiceCompletedStatus(String status) {
  final st = _statusToken(status);
  return st == 'COMPLETED' ||
      st == 'STOPPED' ||
      st == 'DONE' ||
      st == 'FINISHED';
}

/// Extracts street-ride identity signals from a Booking Worker record / envelope.
({String bookingId, String source, String bookingSource, String rideType, String status})
extractStreetSignalsFromBookingRecord(Object? decoded) {
  if (decoded is! Map) {
    return (
      bookingId: '',
      source: '',
      bookingSource: '',
      rideType: '',
      status: '',
    );
  }
  final root = Map<String, dynamic>.from(decoded);
  final booking = root['booking'] is Map
      ? Map<String, dynamic>.from(root['booking'] as Map)
      : const <String, dynamic>{};
  final record = root['record'] is Map
      ? Map<String, dynamic>.from(root['record'] as Map)
      : const <String, dynamic>{};
  final recordBooking = record['booking'] is Map
      ? Map<String, dynamic>.from(record['booking'] as Map)
      : const <String, dynamic>{};
  final payload = root['payload'] is Map
      ? Map<String, dynamic>.from(root['payload'] as Map)
      : (record['payload'] is Map
            ? Map<String, dynamic>.from(record['payload'] as Map)
            : const <String, dynamic>{});

  String first(List<Object?> values) {
    for (final v in values) {
      final t = _norm(v);
      if (t.isNotEmpty && t.toLowerCase() != 'null') return t;
    }
    return '';
  }

  return (
    bookingId: first([
      root['booking_id'],
      root['bookingId'],
      booking['booking_id'],
      booking['bookingId'],
      record['booking_id'],
      record['bookingId'],
      recordBooking['booking_id'],
      payload['booking_id'],
    ]),
    source: first([
      root['source'],
      booking['source'],
      record['source'],
      recordBooking['source'],
      payload['source'],
    ]),
    bookingSource: first([
      root['booking_source'],
      root['bookingSource'],
      booking['booking_source'],
      booking['bookingSource'],
      record['booking_source'],
      record['bookingSource'],
      recordBooking['booking_source'],
      payload['booking_source'],
    ]),
    rideType: first([
      root['ride_type'],
      root['rideType'],
      booking['ride_type'],
      record['ride_type'],
      payload['ride_type'],
    ]),
    status: first([
      root['status'],
      root['stage'],
      booking['status'],
      booking['stage'],
      record['status'],
      record['stage'],
      recordBooking['status'],
    ]),
  );
}

/// The authenticated actor context that is allowed to request / view a business
/// invoice for a completed street ride from the driver receipt.
///
/// STREET-BUSINESS-INVOICE-RECEIPT-UX-1B: the receipt runs in two legitimate
/// auth contexts. A standalone chauffeur has a driver session bearer; a company
/// admin / business-preview session has an admin OR company session bearer plus
/// an effective (preview) driver. Both are valid actors — company admin mode
/// must NOT require a standalone driver session.
enum StreetBusinessInvoiceAuthMode { none, driver, companyAdmin }

/// Central, side-effect-free auth-context resolution for the street business
/// invoice receipt action. It selects the active actor + the tenant/company
/// scope + the effective driver, and never fabricates a driver session.
@immutable
class StreetBusinessInvoiceAuthContext {
  final bool authorized;
  final StreetBusinessInvoiceAuthMode mode;
  final String tenantId;
  final String companyId;
  final String effectiveDriverId;
  final String reason;

  const StreetBusinessInvoiceAuthContext({
    required this.authorized,
    required this.mode,
    required this.tenantId,
    required this.companyId,
    required this.effectiveDriverId,
    required this.reason,
  });

  bool get isDriver => mode == StreetBusinessInvoiceAuthMode.driver;
  bool get isCompanyAdmin => mode == StreetBusinessInvoiceAuthMode.companyAdmin;

  static const StreetBusinessInvoiceAuthContext none =
      StreetBusinessInvoiceAuthContext(
        authorized: false,
        mode: StreetBusinessInvoiceAuthMode.none,
        tenantId: '',
        companyId: '',
        effectiveDriverId: '',
        reason: 'no_authorized_actor',
      );
}

/// Resolves the active auth context for the receipt business-invoice action.
///
/// DRIVER MODE wins when a standalone driver session bearer is present with a
/// complete tenant/company scope. COMPANY ADMIN MODE applies when there is no
/// standalone driver session but a valid admin/company bearer is available with
/// a complete tenant/company scope AND an effective/preview driver. In both
/// modes the booking tenant/company scope (when known) must match, and confirmed
/// ownership is required. Cross-company access is never authorized here — the
/// Booking Worker additionally enforces booking tenant/company + ownership.
StreetBusinessInvoiceAuthContext resolveStreetBusinessInvoiceAuthContext({
  required bool hasDriverSession,
  String driverBearer = '',
  String driverTenantId = '',
  String driverCompanyId = '',
  String driverId = '',
  required bool hasCompanyAdminBearer,
  String companyTenantId = '',
  String companyCompanyId = '',
  String effectiveDriverId = '',
  String bookingTenantId = '',
  String bookingCompanyId = '',
  bool hasOwnership = true,
}) {
  bool scopeMatches(String tenantId, String companyId) {
    final bt = _norm(bookingTenantId);
    final bc = _norm(bookingCompanyId);
    // When the history projection did not carry a booking scope we cannot fail
    // the client gate on it — the backend still enforces it hard on create.
    if (bt.isEmpty && bc.isEmpty) return true;
    final okTenant = bt.isEmpty || bt == _norm(tenantId);
    final okCompany = bc.isEmpty || bc == _norm(companyId);
    return okTenant && okCompany;
  }

  // DRIVER MODE — a real standalone driver session takes precedence.
  final driverReady =
      hasDriverSession &&
      _norm(driverBearer).isNotEmpty &&
      _norm(driverTenantId).isNotEmpty &&
      _norm(driverCompanyId).isNotEmpty;
  if (driverReady) {
    if (!scopeMatches(driverTenantId, driverCompanyId)) {
      return StreetBusinessInvoiceAuthContext(
        authorized: false,
        mode: StreetBusinessInvoiceAuthMode.driver,
        tenantId: _norm(driverTenantId),
        companyId: _norm(driverCompanyId),
        effectiveDriverId: _norm(driverId),
        reason: 'company_scope_mismatch',
      );
    }
    if (!hasOwnership) {
      return StreetBusinessInvoiceAuthContext(
        authorized: false,
        mode: StreetBusinessInvoiceAuthMode.driver,
        tenantId: _norm(driverTenantId),
        companyId: _norm(driverCompanyId),
        effectiveDriverId: _norm(driverId),
        reason: 'ownership_failed',
      );
    }
    return StreetBusinessInvoiceAuthContext(
      authorized: true,
      mode: StreetBusinessInvoiceAuthMode.driver,
      tenantId: _norm(driverTenantId),
      companyId: _norm(driverCompanyId),
      effectiveDriverId: _norm(driverId),
      reason: 'driver_session_valid',
    );
  }

  // COMPANY ADMIN / BUSINESS-PREVIEW MODE — no standalone driver session, but a
  // valid company/admin bearer with a complete scope and an effective driver.
  final companyReady =
      hasCompanyAdminBearer &&
      _norm(companyTenantId).isNotEmpty &&
      _norm(companyCompanyId).isNotEmpty &&
      _norm(effectiveDriverId).isNotEmpty;
  if (companyReady) {
    if (!scopeMatches(companyTenantId, companyCompanyId)) {
      return StreetBusinessInvoiceAuthContext(
        authorized: false,
        mode: StreetBusinessInvoiceAuthMode.companyAdmin,
        tenantId: _norm(companyTenantId),
        companyId: _norm(companyCompanyId),
        effectiveDriverId: _norm(effectiveDriverId),
        reason: 'company_scope_mismatch',
      );
    }
    if (!hasOwnership) {
      return StreetBusinessInvoiceAuthContext(
        authorized: false,
        mode: StreetBusinessInvoiceAuthMode.companyAdmin,
        tenantId: _norm(companyTenantId),
        companyId: _norm(companyCompanyId),
        effectiveDriverId: _norm(effectiveDriverId),
        reason: 'ownership_failed',
      );
    }
    return StreetBusinessInvoiceAuthContext(
      authorized: true,
      mode: StreetBusinessInvoiceAuthMode.companyAdmin,
      tenantId: _norm(companyTenantId),
      companyId: _norm(companyCompanyId),
      effectiveDriverId: _norm(effectiveDriverId),
      reason: 'company_admin_context_valid',
    );
  }

  return StreetBusinessInvoiceAuthContext.none;
}

/// Result of the driver-receipt street-business-invoice eligibility resolver.
@immutable
class StreetBusinessInvoiceReceiptEligibility {
  final bool eligible;
  final bool needsBookingLookup;
  final String canonicalBookingId;
  final String reason;
  final bool isStreetRide;
  final bool isCompleted;
  final bool hasDriverSession;
  final bool hasOwnership;
  final bool hasBookingId;
  final StreetBusinessInvoiceAuthMode authMode;

  const StreetBusinessInvoiceReceiptEligibility({
    required this.eligible,
    required this.needsBookingLookup,
    required this.canonicalBookingId,
    required this.reason,
    required this.isStreetRide,
    required this.isCompleted,
    required this.hasDriverSession,
    required this.hasOwnership,
    required this.hasBookingId,
    this.authMode = StreetBusinessInvoiceAuthMode.none,
  });

  bool get visible => eligible;

  /// True when the active actor is an authorized company admin / business
  /// preview session (no standalone driver session required).
  bool get hasAuthorizedCompanyAdminContext =>
      authMode == StreetBusinessInvoiceAuthMode.companyAdmin;
}

/// Central receipt-side gate for mounting the Business invoice Payment action.
///
/// Tracking `/trips/history` intentionally summarizes trips WITHOUT `source`,
/// so a real linked street ride often arrives as `kind=direct` +
/// `booking_id=street_…` + `status=stopped` with an empty source. This
/// resolver accepts that shape, and when the street identity is only available
/// on the Booking Worker record it signals [needsBookingLookup].
StreetBusinessInvoiceReceiptEligibility
resolveStreetBusinessInvoiceReceiptEligibility({
  required String bookingId,
  String tripId = '',
  String kind = '',
  String status = '',
  String? source,
  String? bookingSource,
  String? rideType,
  String? directRideKey,
  String? bookingLinkState,
  bool isLocalOnlyFallback = false,
  bool hasDriverSession = true,
  bool hasCompanyAdminContext = false,
  bool hasOwnership = true,
  bool isCancelled = false,
  bool isRefunded = false,
  bool isCredited = false,
  StreetBusinessInvoiceAuthContext? authContext,
  Object? lookedUpBooking,
}) {
  final id = _norm(bookingId);
  final kindToken = _lower(kind);
  final rideToken = _lower(rideType);
  final linkState = _lower(bookingLinkState);
  final directKey = _norm(directRideKey);
  final completed = isStreetBusinessInvoiceCompletedStatus(status);

  // Resolve the active actor. A supplied [authContext] wins (it carries the
  // precise actor reason such as company_scope_mismatch / ownership_failed);
  // otherwise fall back to the driver / company-admin booleans.
  final StreetBusinessInvoiceAuthMode authMode;
  final bool authorized;
  final String actorReason;
  if (authContext != null) {
    authMode = authContext.mode;
    authorized = authContext.authorized;
    actorReason = authContext.reason;
  } else {
    authMode = hasDriverSession
        ? StreetBusinessInvoiceAuthMode.driver
        : (hasCompanyAdminContext
              ? StreetBusinessInvoiceAuthMode.companyAdmin
              : StreetBusinessInvoiceAuthMode.none);
    authorized = authMode != StreetBusinessInvoiceAuthMode.none;
    actorReason = authorized ? '' : 'no_authorized_actor';
  }
  final hasSession = authMode == StreetBusinessInvoiceAuthMode.driver;
  final owns = hasOwnership;
  final eligibleReason = authMode == StreetBusinessInvoiceAuthMode.companyAdmin
      ? 'eligible_company_admin'
      : 'eligible_driver';

  var resolvedSource = _norm(source);
  var resolvedBookingSource = _norm(bookingSource);
  var resolvedId = id;
  var resolvedStatus = status;
  var lookedUpIsStreet = false;

  if (lookedUpBooking != null) {
    final signals = extractStreetSignalsFromBookingRecord(lookedUpBooking);
    if (signals.bookingId.isNotEmpty) resolvedId = signals.bookingId;
    if (signals.source.isNotEmpty) resolvedSource = signals.source;
    if (signals.bookingSource.isNotEmpty) {
      resolvedBookingSource = signals.bookingSource;
    }
    if (signals.status.isNotEmpty) resolvedStatus = signals.status;
    lookedUpIsStreet = hasCanonicalStreetIdentity(
      bookingId: signals.bookingId.isNotEmpty ? signals.bookingId : resolvedId,
      source: signals.source,
      bookingSource: signals.bookingSource,
    );
    // Backend isStreetRideBooking also accepts ride_type=direct on the record.
    if (!lookedUpIsStreet &&
        (_lower(signals.rideType) == kStreetRideTypeDirect ||
            _lower(signals.rideType) == 'direct_trip' ||
            _lower(signals.rideType) == 'street_hail')) {
      lookedUpIsStreet = true;
    }
  }

  final hasBooking = resolvedId.isNotEmpty;
  final localCanonical = hasCanonicalStreetIdentity(
    bookingId: resolvedId,
    source: resolvedSource,
    bookingSource: resolvedBookingSource,
  );
  // Tracking history keeps kind=direct for street rides even when `source` was
  // stripped by summarizeTrip. A non-empty linked booking id (or direct_ride
  // linkage) is required so planned/customer bookings never qualify on kind.
  final trackingDirectCandidate =
      !isLocalOnlyFallback &&
      (kindToken == kStreetRideTypeDirect ||
          rideToken == kStreetRideTypeDirect) &&
      (hasBooking ||
          directKey.isNotEmpty ||
          linkState == 'linked' ||
          linkState == 'pending');

  final isStreet =
      localCanonical || lookedUpIsStreet || trackingDirectCandidate;
  final statusCompleted =
      completed || isStreetBusinessInvoiceCompletedStatus(resolvedStatus);

  StreetBusinessInvoiceReceiptEligibility result({
    required bool eligible,
    required bool needsLookup,
    required String reason,
  }) {
    return StreetBusinessInvoiceReceiptEligibility(
      eligible: eligible,
      needsBookingLookup: needsLookup,
      canonicalBookingId: resolvedId,
      reason: reason,
      isStreetRide: isStreet,
      isCompleted: statusCompleted,
      hasDriverSession: hasSession,
      hasOwnership: owns,
      hasBookingId: hasBooking,
      authMode: authMode,
    );
  }

  if (!authorized) {
    return result(
      eligible: false,
      needsLookup: false,
      reason: actorReason.isNotEmpty ? actorReason : 'no_authorized_actor',
    );
  }
  if (!owns) {
    return result(eligible: false, needsLookup: false, reason: 'no_ownership');
  }
  if (isCancelled || _statusToken(resolvedStatus).contains('CANCEL')) {
    return result(eligible: false, needsLookup: false, reason: 'cancelled');
  }
  if (isRefunded || isCredited) {
    return result(eligible: false, needsLookup: false, reason: 'reversed');
  }
  if (!statusCompleted) {
    return result(eligible: false, needsLookup: false, reason: 'not_completed');
  }
  if (kindToken == 'planned' && !localCanonical && !lookedUpIsStreet) {
    return result(
      eligible: false,
      needsLookup: false,
      reason: 'planned_not_street',
    );
  }
  if (!isStreet) {
    return result(
      eligible: false,
      needsLookup: false,
      reason: 'not_street_ride',
    );
  }
  if (!hasBooking) {
    // Linked street ride without a booking id yet: cannot create; allow a
    // lookup retry path only when a trip id could still resolve a booking.
    final canRetry = _norm(tripId).isNotEmpty;
    return result(
      eligible: false,
      needsLookup: canRetry,
      reason: 'missing_booking_id',
    );
  }
  if (localCanonical || lookedUpIsStreet) {
    return result(eligible: true, needsLookup: false, reason: eligibleReason);
  }
  // Tracking-direct candidate without local source/street_ prefix: confirm via
  // Booking Worker before mounting the create action.
  if (lookedUpBooking == null) {
    return result(
      eligible: false,
      needsLookup: true,
      reason: 'needs_booking_lookup',
    );
  }
  return result(
    eligible: false,
    needsLookup: false,
    reason: 'lookup_not_street',
  );
}

/// Explicit render state for the receipt Business-invoice Payment slot. There
/// is never an implicit empty state (STREET-BUSINESS-INVOICE-RECEIPT-UX-1C):
///   - [resolving]      → compact loading placeholder in the Payment card;
///   - [available]      → mount the action (its controller then shows
///                        available / submitting / existingInvoice / error);
///   - [retryableError] → a retry affordance;
///   - [unavailable]    → provably ineligible ride; the fourth action does not
///                        exist (a non-street / planned ride).
enum StreetInvoiceSlotKind { resolving, available, retryableError, unavailable }

/// Immutable decision describing how the receipt Payment slot must render.
@immutable
class StreetInvoiceSlotDecision {
  final StreetInvoiceSlotKind kind;
  final StreetBusinessInvoiceAuthMode authMode;
  final String canonicalBookingId;
  final String reason;

  const StreetInvoiceSlotDecision({
    required this.kind,
    required this.authMode,
    required this.canonicalBookingId,
    required this.reason,
  });

  bool get visible => kind == StreetInvoiceSlotKind.available;
}

/// Sticky memo of POSITIVE receipt eligibility verdicts, keyed by canonical
/// booking id. The volatile effective/preview-driver override is cleared while
/// a form modal is pushed or after leaving the driver UI, which transiently
/// collapses the auth context in company-admin mode and made the action vanish
/// on form-open/cancel and on receipt re-entry. This memo remembers only
/// successful (visible) verdicts so a confirmed completed street ride keeps its
/// Payment slot across those transitions. It NEVER caches negative/failed
/// verdicts, and is only honoured while a real actor context still exists.
class StreetInvoiceEligibilityMemo {
  final Map<String, StreetBusinessInvoiceAuthMode> _byBooking =
      <String, StreetBusinessInvoiceAuthMode>{};

  void remember(String bookingId, StreetBusinessInvoiceAuthMode mode) {
    final id = _norm(bookingId);
    if (id.isEmpty || mode == StreetBusinessInvoiceAuthMode.none) return;
    _byBooking[id] = mode;
  }

  StreetBusinessInvoiceAuthMode? recall(String bookingId) {
    final id = _norm(bookingId);
    if (id.isEmpty) return null;
    return _byBooking[id];
  }

  void reset() => _byBooking.clear();
}

/// Transient auth-context reasons for which the sticky memo may recover a
/// previously-eligible booking. Hard-negative verdicts (cancelled / reversed /
/// not_completed / not_street_ride / planned) are NEVER recovered.
const Set<String> kStreetInvoiceTransientAuthReasons = <String>{
  'no_authorized_actor',
  'ownership_failed',
  'company_scope_mismatch',
};

/// Pure resolver for the Payment slot render state. Combines the live
/// eligibility verdict with the sticky memo and the current actor-context /
/// lookup flags. Records positive verdicts into [memo] as a side effect.
StreetInvoiceSlotDecision resolveStreetInvoiceSlotDecision({
  required StreetBusinessInvoiceReceiptEligibility eligibility,
  required String canonicalBookingId,
  required StreetInvoiceEligibilityMemo memo,
  required bool hasActorContext,
  required bool lookupInFlight,
  required bool lookupFailed,
  String kindToken = '',
}) {
  final canonicalId = _norm(canonicalBookingId);
  final e = eligibility;

  if (e.visible) {
    memo.remember(canonicalId, e.authMode);
    return StreetInvoiceSlotDecision(
      kind: StreetInvoiceSlotKind.available,
      authMode: e.authMode,
      canonicalBookingId: canonicalId,
      reason: e.reason,
    );
  }

  final remembered = memo.recall(canonicalId);
  if (remembered != null &&
      hasActorContext &&
      canonicalId.isNotEmpty &&
      kStreetInvoiceTransientAuthReasons.contains(e.reason)) {
    return StreetInvoiceSlotDecision(
      kind: StreetInvoiceSlotKind.available,
      authMode: remembered,
      canonicalBookingId: canonicalId,
      reason: 'eligible_sticky',
    );
  }

  // An in-flight lookup shows the loading placeholder. A FAILED lookup takes
  // precedence over "needs lookup" so the user gets a retry affordance instead
  // of an endless spinner (the eligibility still reports needsBookingLookup).
  if (lookupInFlight) {
    return StreetInvoiceSlotDecision(
      kind: StreetInvoiceSlotKind.resolving,
      authMode: e.authMode,
      canonicalBookingId: canonicalId,
      reason: e.reason,
    );
  }

  final retryable =
      lookupFailed ||
      (e.reason == 'missing_booking_id' && _lower(kindToken) == 'direct');
  if (retryable) {
    return StreetInvoiceSlotDecision(
      kind: StreetInvoiceSlotKind.retryableError,
      authMode: e.authMode,
      canonicalBookingId: canonicalId,
      reason: e.reason,
    );
  }

  if (e.needsBookingLookup) {
    return StreetInvoiceSlotDecision(
      kind: StreetInvoiceSlotKind.resolving,
      authMode: e.authMode,
      canonicalBookingId: canonicalId,
      reason: e.reason,
    );
  }

  return StreetInvoiceSlotDecision(
    kind: StreetInvoiceSlotKind.unavailable,
    authMode: e.authMode,
    canonicalBookingId: canonicalId,
    reason: e.reason,
  );
}

/// PDF readiness for View/Share invoice PDF actions
/// (STREET-BUSINESS-INVOICE-PDF-PAYMENT-SYNC-1).
///
/// A PDF is NEVER treated as available from invoice reference / Billit order id
/// / "created" alone — only a confirmed artifact (documents envelope flag or a
/// successful PDF endpoint probe) is sufficient.
enum StreetInvoicePdfAvailabilityState {
  unavailable,
  preparing,
  available,
  retryableError,
}

@immutable
class StreetInvoicePdfAvailability {
  final StreetInvoicePdfAvailabilityState state;
  final String reason;
  final String? documentReference;

  const StreetInvoicePdfAvailability({
    required this.state,
    required this.reason,
    this.documentReference,
  });

  bool get canViewOrShare => state == StreetInvoicePdfAvailabilityState.available;
  bool get isPreparing => state == StreetInvoicePdfAvailabilityState.preparing;
  bool get isRetryable =>
      state == StreetInvoicePdfAvailabilityState.retryableError;
}

/// Bounded status-refresh delays after invoice create / receipt reopen.
/// Schedule: immediate, 2s, 5s, 10s — then stop. Never an endless timer.
const List<Duration> kStreetInvoiceStatusRefreshDelays = <Duration>[
  Duration.zero,
  Duration(seconds: 2),
  Duration(seconds: 5),
  Duration(seconds: 10),
];

/// Resolves whether View/Share invoice PDF may be active.
///
/// Evidence precedence:
/// 1. [pdfArtifactReady] from the documents envelope (booking-level artifact);
/// 2. [pdfProbeStatusCode] from GET `/bookings/:id/invoice/pdf`
///    (200 + bytes → available; 404 → preparing; 401/403 → unavailable;
///    null status with [pdfProbeFailed] → retryableError);
/// 3. invoice exists but no evidence yet → preparing (Billit/backend may still
///    be writing the artifact).
StreetInvoicePdfAvailability resolveStreetInvoicePdfAvailability({
  required bool hasIssuedInvoice,
  bool? pdfArtifactReady,
  int? pdfProbeStatusCode,
  bool pdfProbeFailed = false,
  String documentReference = '',
}) {
  final ref = _norm(documentReference);
  if (!hasIssuedInvoice) {
    return StreetInvoicePdfAvailability(
      state: StreetInvoicePdfAvailabilityState.unavailable,
      reason: 'no_invoice',
      documentReference: ref.isEmpty ? null : ref,
    );
  }
  if (pdfArtifactReady == true) {
    return StreetInvoicePdfAvailability(
      state: StreetInvoicePdfAvailabilityState.available,
      reason: 'artifact_ready',
      documentReference: ref.isEmpty ? null : ref,
    );
  }
  if (pdfProbeStatusCode == 200) {
    return StreetInvoicePdfAvailability(
      state: StreetInvoicePdfAvailabilityState.available,
      reason: 'pdf_endpoint_ok',
      documentReference: ref.isEmpty ? null : ref,
    );
  }
  if (pdfProbeStatusCode == 202) {
    return StreetInvoicePdfAvailability(
      state: StreetInvoicePdfAvailabilityState.preparing,
      reason: 'pdf_pending',
      documentReference: ref.isEmpty ? null : ref,
    );
  }
  if (pdfProbeStatusCode == 401 || pdfProbeStatusCode == 403) {
    return StreetInvoicePdfAvailability(
      state: StreetInvoicePdfAvailabilityState.unavailable,
      reason: 'pdf_auth_denied',
      documentReference: ref.isEmpty ? null : ref,
    );
  }
  if (pdfProbeFailed ||
      (pdfProbeStatusCode != null &&
          pdfProbeStatusCode >= 500 &&
          pdfProbeStatusCode < 600)) {
    return StreetInvoicePdfAvailability(
      state: StreetInvoicePdfAvailabilityState.retryableError,
      reason: 'pdf_probe_failed',
      documentReference: ref.isEmpty ? null : ref,
    );
  }
  // 404 / not probed yet / artifact not ready → preparing, never a dead button.
  return StreetInvoicePdfAvailability(
    state: StreetInvoicePdfAvailabilityState.preparing,
    reason: pdfProbeStatusCode == 404
        ? 'pdf_not_persisted_yet'
        : (pdfArtifactReady == false
              ? 'artifact_pending'
              : 'awaiting_pdf_evidence'),
    documentReference: ref.isEmpty ? null : ref,
  );
}

/// Ride-level payment (cash / card / QR / unpaid). Distinct from invoice paid.
enum StreetInvoiceRidePaymentStatus { unpaid, paid }

/// Invoice-level payment presentation (language-independent semantic status).
///
/// Translate only AFTER this enum is chosen — never pick outstanding from a
/// localized string or from `billitPaid == false` alone while the ride is paid.
enum StreetInvoiceInvoicePaymentStatus {
  /// Definitive Billit/invoice paid (confirmed).
  paid,

  /// Ride is paid; Billit paid sync is still pending / updating.
  /// Only valid when a Billit order link already exists.
  syncInProgress,

  /// Terminal Billit payment-sync failure (retryable — never "outstanding").
  syncFailed,

  /// Invoice issued and ride paid, but not linked to a Billit order yet.
  /// Distinct from [syncInProgress] — missing export/order_id is NOT syncing.
  notLinkedToBillit,

  /// Ride/invoice truly unpaid / outstanding.
  outstanding,
}

/// Invoice processing / lifecycle presentation (not payment).
enum StreetInvoiceProcessingStatus {
  requested,
  created,
  billitUpdating,
  sent,
  peppolSent,
  pdfReady,
}

@immutable
class StreetInvoicePaymentPresentation {
  final StreetInvoiceRidePaymentStatus ridePaymentStatus;
  final StreetInvoiceInvoicePaymentStatus invoicePaymentStatus;
  final StreetInvoiceProcessingStatus invoiceProcessingStatus;
  final bool isConsistent;
  final String reason;

  const StreetInvoicePaymentPresentation({
    required this.ridePaymentStatus,
    required this.invoicePaymentStatus,
    required this.invoiceProcessingStatus,
    required this.isConsistent,
    required this.reason,
  });
}

/// Stable, language-independent diagnostic key for a semantic invoice payment
/// status (STREET-BUSINESS-INVOICE-PDF-PAYMENT-SYNC-1C).
///
/// Used for bounded runtime logging AND tests so the enum can be asserted
/// without any localized text. Translation happens ONLY via
/// `streetInvoicePaymentStatusLabel(lang, status)` — never from this key.
String streetInvoicePaymentStatusKey(StreetInvoiceInvoicePaymentStatus status) {
  switch (status) {
    case StreetInvoiceInvoicePaymentStatus.paid:
      return 'paid';
    case StreetInvoiceInvoicePaymentStatus.syncInProgress:
      return 'syncInProgress';
    case StreetInvoiceInvoicePaymentStatus.syncFailed:
      return 'syncFailed';
    case StreetInvoiceInvoicePaymentStatus.notLinkedToBillit:
      return 'notLinkedToBillit';
    case StreetInvoiceInvoicePaymentStatus.outstanding:
      return 'outstanding';
  }
}

/// Raw inputs + resolved semantic status for a single presentation, used only
/// for bounded runtime diagnostics. Carries NO PII (no reference, no buyer, no
/// tokens) — only ride/Billit booleans + the sync token + the semantic status.
@immutable
class StreetInvoicePaymentDiagnostics {
  final bool ridePaid;
  final bool? billitPaid;
  final String billitPaymentSyncStatus;
  final bool billitUpdating;
  final StreetInvoiceInvoicePaymentStatus semanticStatus;

  const StreetInvoicePaymentDiagnostics({
    required this.ridePaid,
    required this.billitPaid,
    required this.billitPaymentSyncStatus,
    required this.billitUpdating,
    required this.semanticStatus,
  });

  String get semanticStatusKey => streetInvoicePaymentStatusKey(semanticStatus);
}

/// Canonical ride (booking) payment result shared by the receipt status, the
/// Payment/Betaalzone AND the business-invoice controller input
/// (STREET-BUSINESS-INVOICE-PDF-PAYMENT-SYNC-1D).
///
/// [normalizedStatus] is one of `paid` / `unpaid` / `unknown`. A missing
/// invoice-document payment field resolves to `unknown` — never `unpaid` — so
/// a lagging documents index can never downgrade a confirmed-paid ride.
@immutable
class CanonicalRidePayment {
  final bool isPaid;
  final String normalizedStatus;
  final String source;
  final String reason;

  const CanonicalRidePayment({
    required this.isPaid,
    required this.normalizedStatus,
    required this.source,
    required this.reason,
  });
}

/// One canonical resolver for the ride (booking) payment. Used by the general
/// receipt status, the Payment/Betaalzone and the business-invoice controller
/// so all three surfaces agree on `rideConfirmedPaid`.
///
/// Priority:
///   0. an already-canonical paid ride stays paid (monotonic — never
///      downgraded by a later missing/false signal, unless [reversal]).
///   1. explicit canonical booking/receipt payment_status == paid;
///   2. the existing effective receipt-paid resolver result;
///   3. payment lifecycle evidence (cash / card terminal / QR recorded);
///   4. the invoice-document response ONLY when it carries an explicit valid
///      paid status.
///
/// A null [documentRidePaid] means the document did not report a payment status
/// (UNKNOWN) and therefore never forces `unpaid`.
CanonicalRidePayment resolveCanonicalReceiptRidePayment({
  String? explicitPaymentStatus,
  bool effectiveReceiptPaid = false,
  bool paymentLifecyclePaid = false,
  bool? documentRidePaid,
  bool priorCanonicalPaid = false,
  bool reversal = false,
}) {
  if (reversal) {
    return const CanonicalRidePayment(
      isPaid: false,
      normalizedStatus: 'unpaid',
      source: 'reversal',
      reason: 'explicit_reversal_or_refund',
    );
  }
  if (priorCanonicalPaid) {
    return const CanonicalRidePayment(
      isPaid: true,
      normalizedStatus: 'paid',
      source: 'prior_canonical',
      reason: 'monotonic_retained',
    );
  }
  final explicit = _lower(explicitPaymentStatus ?? '');
  const paidTokens = <String>{
    'paid',
    'succeeded',
    'settled',
    'completed',
    'captured',
  };
  if (paidTokens.contains(explicit)) {
    return CanonicalRidePayment(
      isPaid: true,
      normalizedStatus: 'paid',
      source: 'explicit_status',
      reason: 'explicit_$explicit',
    );
  }
  if (effectiveReceiptPaid) {
    return const CanonicalRidePayment(
      isPaid: true,
      normalizedStatus: 'paid',
      source: 'receipt_effective_paid',
      reason: 'effective_receipt_paid',
    );
  }
  if (paymentLifecyclePaid) {
    return const CanonicalRidePayment(
      isPaid: true,
      normalizedStatus: 'paid',
      source: 'payment_lifecycle',
      reason: 'lifecycle_cash_card_qr',
    );
  }
  if (documentRidePaid == true) {
    return const CanonicalRidePayment(
      isPaid: true,
      normalizedStatus: 'paid',
      source: 'document',
      reason: 'document_explicit_paid',
    );
  }
  // No paid evidence. Explicit document false is `unpaid`; everything else
  // (missing status) is UNKNOWN so it can never downgrade a paid ride.
  final normalized = documentRidePaid == false ? 'unpaid' : 'unknown';
  return CanonicalRidePayment(
    isPaid: false,
    normalizedStatus: normalized,
    source: 'none',
    reason: 'no_paid_evidence',
  );
}

/// STREET-CASH-PAYMENT-RELOAD-P0: precedence for receipt reopen hydration.
///
/// Authoritative BOOKING_KV status always wins when present. History/trip
/// projections are fallbacks only — they must never outrank a successful
/// booking-worker read.
String? resolveReceiptReloadPaymentStatusRaw({
  String? authoritativeStatus,
  String? historyTopLevelStatus,
  String? historyNestedStatus,
}) {
  final auth = (authoritativeStatus ?? '').trim();
  if (auth.isNotEmpty) return auth;
  final top = (historyTopLevelStatus ?? '').trim();
  if (top.isNotEmpty) return top;
  final nested = (historyNestedStatus ?? '').trim();
  if (nested.isNotEmpty) return nested;
  return null;
}

bool _isConfirmedPaidStatusToken(String? raw) {
  final text = (raw ?? '').trim().toLowerCase();
  if (text.isEmpty) return false;
  return text == 'paid' ||
      text == 'settled' ||
      text == 'confirmed' ||
      text == 'completed' ||
      text == 'success' ||
      text == 'succeeded' ||
      text == 'captured';
}

/// Stale / missing projections that must not outrank a prior server-confirmed
/// Paid. Explicit terminal non-paid states (refunded / reversed / cancelled /
/// rejected / failed) are NOT included — those must be allowed to win.
bool _isStaleOrMissingUnpaidProjection(String? raw) {
  final text = (raw ?? '').trim().toLowerCase();
  if (text.isEmpty) return true;
  return text == 'unpaid' ||
      text == 'pending' ||
      text == 'open' ||
      text == 'authorized' ||
      text == 'unknown' ||
      text == 'none';
}

/// True when a prior server-confirmed Paid must be retained against a failed
/// read, missing payment fields, or a stale cached/history Unpaid projection.
///
/// Must NOT mask a newer explicit authoritative non-paid state such as
/// reversed, refunded, cancelled, rejected, or a failed payment write.
bool shouldRetainConfirmedPaidOnReload({
  required bool alreadyConfirmedPaid,
  required String? resolvedRawStatus,
}) {
  if (!alreadyConfirmedPaid) return false;
  if (_isConfirmedPaidStatusToken(resolvedRawStatus)) return false;
  if (!_isStaleOrMissingUnpaidProjection(resolvedRawStatus)) return false;
  return true;
}

/// Bounded de-dup guard so the ride-payment log fires only when the
/// (booking, canonicalPaid, source) tuple actually changes.
final Set<String> _streetInvoiceRidePaymentLogSeen = <String>{};

/// Emits the bounded `[STREET_INVOICE_RIDE_PAYMENT]` runtime proof (1D).
/// Carries no PII/tokens — only the canonical booleans, source and normalized
/// status. [bookingTag] must already be a non-identifying short tag.
void logStreetInvoiceRidePayment({
  required String surface,
  required CanonicalRidePayment canonical,
  String bookingTag = '',
}) {
  final dedupeKey =
      '$surface|$bookingTag|${canonical.isPaid}|${canonical.source}|${canonical.normalizedStatus}';
  if (!_streetInvoiceRidePaymentLogSeen.add(dedupeKey)) return;
  if (_streetInvoiceRidePaymentLogSeen.length > 64) {
    _streetInvoiceRidePaymentLogSeen.clear();
    _streetInvoiceRidePaymentLogSeen.add(dedupeKey);
  }
  debugPrint(
    '[STREET_INVOICE_RIDE_PAYMENT] '
    'surface=$surface '
    'canonicalPaid=${canonical.isPaid} '
    'source=${canonical.source} '
    'normalizedStatus=${canonical.normalizedStatus}',
  );
}

/// Canonical payment/processing presentation for a street business invoice.
///
/// Priority (RELEASE-P0 truthful Billit status):
///   1. invoicePaymentConfirmedPaid → [paid]
///   2. ridePaid + Billit linked + sync failed → [syncFailed]
///   3. ridePaid + Billit linked + sync pending → [syncInProgress]
///   4. ridePaid + no Billit link → [notLinkedToBillit]
///   5. !ridePaid → [outstanding]
///
/// Missing `billit_export` / empty sync token / `billitPaid == null` MUST NOT
/// become [syncInProgress] when there is no Billit order link.
StreetInvoicePaymentPresentation resolveStreetInvoicePaymentPresentation({
  required bool hasIssuedInvoice,
  required bool ridePaid,
  bool responsePaymentPaid = false,
  bool? billitPaid,
  String billitPaymentSyncStatus = '',
  bool billitUpdating = false,
  bool syncPending = false,
  bool hasBillitLink = false,
  bool peppolSent = false,
  bool pdfReady = false,
  String lifecycleState = '',
  bool visibilityDelayed = false,
}) {
  final rideConfirmedPaid = ridePaid || responsePaymentPaid;
  final ride = rideConfirmedPaid
      ? StreetInvoiceRidePaymentStatus.paid
      : StreetInvoiceRidePaymentStatus.unpaid;
  final syncToken = _lower(billitPaymentSyncStatus);
  final invoicePaymentConfirmedPaid =
      billitPaid == true || syncToken == 'synced';
  final billitSyncFailed = hasBillitLink && syncToken == 'failed';
  // Active payment-sync only applies after a Billit order is linked.
  // Empty/null export fields without a link are "not linked", not syncing.
  final billitPaymentSyncPending = hasBillitLink &&
      (syncPending ||
          billitUpdating ||
          syncToken == 'pending' ||
          syncToken == 'in_progress' ||
          syncToken.isEmpty ||
          billitPaid == false ||
          billitPaid == null);

  StreetInvoiceInvoicePaymentStatus invoicePay;
  String reason;

  if (!hasIssuedInvoice) {
    invoicePay = StreetInvoiceInvoicePaymentStatus.outstanding;
    reason = 'no_invoice';
  } else if (invoicePaymentConfirmedPaid) {
    invoicePay = StreetInvoiceInvoicePaymentStatus.paid;
    reason = billitPaid == true ? 'billit_paid' : 'billit_sync_synced';
  } else if (rideConfirmedPaid && billitSyncFailed) {
    invoicePay = StreetInvoiceInvoicePaymentStatus.syncFailed;
    reason = 'payment_sync_failed_retryable';
  } else if (rideConfirmedPaid && hasBillitLink && billitPaymentSyncPending) {
    invoicePay = StreetInvoiceInvoicePaymentStatus.syncInProgress;
    reason = 'payment_sync_in_progress';
  } else if (rideConfirmedPaid && !hasBillitLink) {
    invoicePay = StreetInvoiceInvoicePaymentStatus.notLinkedToBillit;
    reason = 'not_linked_to_billit';
  } else if (rideConfirmedPaid) {
    invoicePay = StreetInvoiceInvoicePaymentStatus.syncInProgress;
    reason = 'payment_sync_in_progress';
  } else {
    invoicePay = StreetInvoiceInvoicePaymentStatus.outstanding;
    reason = 'invoice_outstanding';
  }

  StreetInvoiceProcessingStatus processing;
  if (peppolSent) {
    processing = StreetInvoiceProcessingStatus.peppolSent;
  } else if (pdfReady) {
    processing = StreetInvoiceProcessingStatus.pdfReady;
  } else if (_lower(lifecycleState) == 'sent' ||
      _lower(lifecycleState) == 'ready_to_send') {
    processing = StreetInvoiceProcessingStatus.sent;
  } else if (!hasBillitLink || billitUpdating) {
    processing = StreetInvoiceProcessingStatus.billitUpdating;
  } else if (visibilityDelayed) {
    processing = StreetInvoiceProcessingStatus.requested;
  } else {
    processing = StreetInvoiceProcessingStatus.created;
  }

  return StreetInvoicePaymentPresentation(
    ridePaymentStatus: ride,
    invoicePaymentStatus: invoicePay,
    invoiceProcessingStatus: processing,
    isConsistent: true,
    reason: reason,
  );
}

/// Derived, display-only document count that keeps a locally-successful invoice
/// visible while the eventually-consistent documents index catches up.
///
/// It never mutates the backend collection: it simply adds 1 to the backend
/// visible count when a locally-issued invoice is known but not yet present in
/// the backend list, and adds nothing once the backend list includes it (so the
/// count never double-counts and never reverts to 0).
int deriveDisplayedDocumentCount({
  required int backendVisibleCount,
  required bool hasLocalIssuedInvoice,
  required bool localInvoiceInBackend,
}) {
  final base = backendVisibleCount < 0 ? 0 : backendVisibleCount;
  if (hasLocalIssuedInvoice && !localInvoiceInBackend) return base + 1;
  return base;
}

/// Snapshot of a just-issued street business invoice kept in the app until the
/// booking Documents GET catches up. Carries enough Billit fields for the
/// Documents row to show link/status without inventing a second invoice.
@immutable
class StreetInvoiceLocalIssuedSnapshot {
  final String documentId;
  final String invoiceReference;
  final String billitEnvironment;
  final String billitOrderId;
  final String billitPaymentSyncStatus;
  final bool peppolSent;
  final bool? billitPaid;
  final String saleKind;

  const StreetInvoiceLocalIssuedSnapshot({
    required this.documentId,
    this.invoiceReference = '',
    this.billitEnvironment = '',
    this.billitOrderId = '',
    this.billitPaymentSyncStatus = '',
    this.peppolSent = false,
    this.billitPaid,
    this.saleKind = 'business_invoice',
  });

  factory StreetInvoiceLocalIssuedSnapshot.fromIssueResponse(
    StreetBusinessInvoiceResponse response,
  ) {
    return StreetInvoiceLocalIssuedSnapshot(
      documentId: response.documentId,
      invoiceReference: response.invoiceReference,
      billitEnvironment: response.billitEnvironment,
      billitOrderId: response.billitOrderId,
      billitPaymentSyncStatus: response.billitPaymentSyncStatus,
      peppolSent: response.peppolSent,
      billitPaid: response.isPaid ? true : null,
      saleKind: 'business_invoice',
    );
  }

  factory StreetInvoiceLocalIssuedSnapshot.fromDocSummary(
    StreetInvoiceDocSummary summary,
  ) {
    return StreetInvoiceLocalIssuedSnapshot(
      documentId: summary.documentId,
      invoiceReference: summary.documentNumber,
      billitEnvironment: summary.billitEnvironment,
      billitOrderId: summary.billitOrderId,
      billitPaymentSyncStatus: summary.billitPaymentSyncStatus,
      peppolSent: summary.peppolSent,
      billitPaid: summary.billitPaid,
      saleKind: summary.saleKind.isEmpty
          ? 'business_invoice'
          : summary.saleKind,
    );
  }

  bool get hasBillitLink => billitOrderId.trim().isNotEmpty;
}

/// True when Documents should show the empty-state copy. A locally-issued
/// invoice that is not yet in the backend list must not show
/// "Nog geen documenten…" while the count already reads 1.
bool shouldShowBookingDocumentsEmptyState({
  required int visibleDocumentCount,
  required bool hasPendingLocalIssuedInvoice,
}) {
  if (visibleDocumentCount > 0) return false;
  if (hasPendingLocalIssuedInvoice) return false;
  return true;
}

/// Whether [localDocumentId] should be injected as a synthetic Documents row
/// (backend list lag). Never doubles when the id is already visible.
bool shouldInjectLocalIssuedInvoiceDocument({
  required String localDocumentId,
  required Iterable<String> visibleBackendDocumentIds,
}) {
  final id = localDocumentId.trim();
  if (id.isEmpty) return false;
  for (final existing in visibleBackendDocumentIds) {
    if (existing.trim() == id) return false;
  }
  return true;
}

/// Width (dp) at/below which the document actions stack vertically as
/// full-width touch targets (phone). Above it, actions may sit side-by-side
/// (tablet/wide), matching the existing company-bookings card breakpoint.
const double kStreetInvoiceActionNarrowBreakpoint = 600;

/// True when the invoice action(s) should stack full-width (narrow phone).
/// False when they may render side-by-side (wide/tablet).
bool streetInvoiceActionIsNarrowLayout(double maxWidth) =>
    maxWidth < kStreetInvoiceActionNarrowBreakpoint;

/// Buyer billing identity entered in the request form. Only buyer/legal fields;
/// never passenger/ride fields and never pricing/payment state.
@immutable
class StreetBusinessInvoiceBuyerInput {
  final String legalName;
  final String street;
  final String postalCode;
  final String city;
  final String country;
  final String vatNumber;
  final String companyRegistrationNumber;
  final String contactEmail;
  final String buyerReference;

  const StreetBusinessInvoiceBuyerInput({
    this.legalName = '',
    this.street = '',
    this.postalCode = '',
    this.city = '',
    this.country = 'BE',
    this.vatNumber = '',
    this.companyRegistrationNumber = '',
    this.contactEmail = '',
    this.buyerReference = '',
  });

  /// Builds the exact `{ "billing_customer": { ... } }` request body. Empty
  /// optional fields are omitted (never sent as empty strings). Country is
  /// upper-cased. `customer_type` is always "business" for this action.
  /// Optional [sourceLegId]/[sourceLegType] scope roundtrip conversion to one
  /// operational leg (ROUNDTRIP-CONSUMER-SALE-LATE-INVOICE-ACTION-P0-4).
  Map<String, dynamic> toRequestBody({
    String? sourceLegId,
    String? sourceLegType,
  }) {
    final address = <String, dynamic>{};
    void putAddr(String key, String value) {
      final t = value.trim();
      if (t.isNotEmpty) address[key] = t;
    }

    putAddr('street', street);
    putAddr('postal_code', postalCode);
    putAddr('city', city);
    final c = country.trim().toUpperCase();
    if (c.isNotEmpty) address['country'] = c;

    final billing = <String, dynamic>{'customer_type': 'business'};
    void putField(String key, String value) {
      final t = value.trim();
      if (t.isNotEmpty) billing[key] = t;
    }

    putField('legal_name', legalName);
    putField('contact_email', contactEmail);
    putField('vat_number', vatNumber);
    putField('company_registration_number', companyRegistrationNumber);
    putField('buyer_reference', buyerReference);
    if (address.isNotEmpty) billing['billing_address'] = address;

    final body = <String, dynamic>{'billing_customer': billing};
    final legId = (sourceLegId ?? '').trim();
    final legType = (sourceLegType ?? '').trim();
    if (legId.isNotEmpty) body['source_leg_id'] = legId;
    if (legType.isNotEmpty) body['source_leg_type'] = legType;
    return body;
  }
}

/// Validation verdict for the safe UI rule: legal name + full billing address
/// (street, postal code, city, country) are required in this phase. VAT /
/// company registration numbers are optional, but when provided they must look
/// like a plausible identifier.
@immutable
class StreetBusinessInvoiceFormValidation {
  final bool legalNameMissing;
  final bool streetMissing;
  final bool postalCodeMissing;
  final bool cityMissing;
  final bool countryMissing;
  final bool vatInvalid;
  final bool companyRegistrationInvalid;

  const StreetBusinessInvoiceFormValidation({
    required this.legalNameMissing,
    required this.streetMissing,
    required this.postalCodeMissing,
    required this.cityMissing,
    required this.countryMissing,
    this.vatInvalid = false,
    this.companyRegistrationInvalid = false,
  });

  bool get isValid =>
      !legalNameMissing &&
      !streetMissing &&
      !postalCodeMissing &&
      !cityMissing &&
      !countryMissing &&
      !vatInvalid &&
      !companyRegistrationInvalid;

  List<String> get missingFieldKeys => <String>[
    if (legalNameMissing) 'legal_name',
    if (streetMissing) 'street',
    if (postalCodeMissing) 'postal_code',
    if (cityMissing) 'city',
    if (countryMissing) 'country',
    if (vatInvalid) 'vat_number',
    if (companyRegistrationInvalid) 'company_registration_number',
  ];
}

/// True when [raw] is empty (optional) or looks like a usable VAT /
/// enterprise number (BE/EU-style or a compact alphanumeric id).
bool isPlausibleVatOrCompanyNumber(String raw) {
  final t = raw.trim().replaceAll(RegExp(r'[\s.\-]'), '').toUpperCase();
  if (t.isEmpty) return true;
  if (RegExp(r'^BE0?\d{9,10}$').hasMatch(t)) return true;
  if (RegExp(r'^\d{9,12}$').hasMatch(t)) return true;
  if (RegExp(r'^[A-Z]{2}[A-Z0-9]{2,12}$').hasMatch(t)) return true;
  if (RegExp(r'^[A-Z0-9]{6,20}$').hasMatch(t)) return true;
  return false;
}

StreetBusinessInvoiceFormValidation validateStreetBusinessInvoiceForm(
  StreetBusinessInvoiceBuyerInput input,
) {
  return StreetBusinessInvoiceFormValidation(
    legalNameMissing: input.legalName.trim().isEmpty,
    streetMissing: input.street.trim().isEmpty,
    postalCodeMissing: input.postalCode.trim().isEmpty,
    cityMissing: input.city.trim().isEmpty,
    countryMissing: input.country.trim().isEmpty,
    vatInvalid: !isPlausibleVatOrCompanyNumber(input.vatNumber),
    companyRegistrationInvalid: !isPlausibleVatOrCompanyNumber(
      input.companyRegistrationNumber,
    ),
  );
}

/// Loose parse of a single-line / multi-line billing address for form prefill.
/// Best-effort only; empty parts are left blank so the driver can complete them.
({String street, String postalCode, String city, String country})
parseLooseBillingAddress(String raw) {
  final text = raw.trim();
  if (text.isEmpty) {
    return (street: '', postalCode: '', city: '', country: '');
  }
  final lines = text
      .split(RegExp(r'[\n;]+'))
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toList();
  String street = lines.isNotEmpty ? lines.first : text;
  String postalCode = '';
  String city = '';
  String country = '';
  final postalCity = RegExp(
    r'\b(\d{4,6})\s+([A-Za-zÀ-ÿ][\wÀ-ÿ\-\s]{1,40})\b',
  ).firstMatch(text);
  if (postalCity != null) {
    postalCode = postalCity.group(1) ?? '';
    city = (postalCity.group(2) ?? '').trim();
    street = text
        .replaceFirst(postalCity.group(0)!, '')
        .replaceAll(RegExp(r'[,\s]+$'), '')
        .trim();
    if (street.isEmpty && lines.isNotEmpty) street = lines.first;
  } else if (lines.length >= 2) {
    city = lines[1];
  }
  final countryMatch = RegExp(
    r'\b(BE|NL|FR|DE|LU|ES|IT|PT|GB|UK)\b',
    caseSensitive: false,
  ).firstMatch(text);
  if (countryMatch != null) {
    country = countryMatch.group(1)!.toUpperCase();
    if (country == 'UK') country = 'GB';
  }
  return (
    street: street,
    postalCode: postalCode,
    city: city,
    country: country,
  );
}

/// Builds a form prefill from already-known receipt/booking business fields.
StreetBusinessInvoiceBuyerInput streetBusinessInvoicePrefillFromFields({
  String companyName = '',
  String vatNumber = '',
  String invoiceEmail = '',
  String invoiceAddress = '',
  String countryFallback = 'BE',
}) {
  final parsed = parseLooseBillingAddress(invoiceAddress);
  final country = parsed.country.isNotEmpty
      ? parsed.country
      : countryFallback.trim().toUpperCase();
  return StreetBusinessInvoiceBuyerInput(
    legalName: companyName.trim(),
    street: parsed.street,
    postalCode: parsed.postalCode,
    city: parsed.city,
    country: country.isEmpty ? 'BE' : country,
    vatNumber: vatNumber.trim(),
    contactEmail: invoiceEmail.trim(),
  );
}

/// Receipt Payment-status key when a street business invoice is known.
/// Returns null when the regular unpaid/paid/sent labels should be used.
///
/// A paid ride always wins as 'paid' (never forced back to invoicePending).
/// Sync-in-progress is still ride-paid for the receipt row.
String? streetBusinessInvoicePaymentStatusKey({
  required bool hasInvoice,
  required bool invoicePaid,
  required bool receiptPaid,
  bool paymentSyncInProgress = false,
  bool paymentSyncFailed = false,
  bool notLinkedToBillit = false,
}) {
  if (!hasInvoice) return null;
  if (receiptPaid ||
      invoicePaid ||
      paymentSyncInProgress ||
      paymentSyncFailed ||
      notLinkedToBillit) {
    return 'paid';
  }
  return 'invoicePending';
}

/// Parsed success envelope of `POST .../request-business-invoice`.
@immutable
class StreetBusinessInvoiceResponse {
  final bool ok;
  final String bookingId;
  final String documentId;
  final String invoiceReference;
  final bool reused;
  final String paymentStatus; // "paid" | "unpaid"
  final String billitEnvironment; // "sandbox"
  final String billitOrderId;
  final bool billitOrderReused;
  final String billitPaymentSyncStatus;
  final bool peppolSent;
  final List<String> warnings;
  final String paymentReconciliation;

  const StreetBusinessInvoiceResponse({
    required this.ok,
    required this.bookingId,
    required this.documentId,
    required this.invoiceReference,
    required this.reused,
    required this.paymentStatus,
    required this.billitEnvironment,
    required this.billitOrderId,
    required this.billitOrderReused,
    required this.billitPaymentSyncStatus,
    required this.peppolSent,
    required this.warnings,
    required this.paymentReconciliation,
  });

  bool get isPaid => paymentStatus.toLowerCase() == 'paid';
}

StreetBusinessInvoiceResponse? parseStreetBusinessInvoiceResponse(
  Object? decoded,
) {
  if (decoded is! Map) return null;
  final warningsRaw = decoded['warnings'];
  final warnings = <String>[];
  if (warningsRaw is List) {
    for (final w in warningsRaw) {
      final t = _norm(w);
      if (t.isNotEmpty) warnings.add(t);
    }
  }
  return StreetBusinessInvoiceResponse(
    ok: decoded['ok'] == true,
    bookingId: _norm(decoded['booking_id']),
    documentId: _norm(decoded['document_id']),
    invoiceReference: _norm(decoded['invoice_reference']),
    reused: decoded['reused'] == true,
    paymentStatus: _lower(decoded['payment_status']),
    billitEnvironment: _lower(decoded['billit_environment']),
    billitOrderId: _norm(decoded['billit_order_id']),
    billitOrderReused: decoded['billit_order_reused'] == true,
    billitPaymentSyncStatus: _norm(decoded['billit_payment_sync_status']),
    peppolSent: decoded['peppol_sent'] == true,
    warnings: warnings,
    paymentReconciliation: _norm(decoded['payment_reconciliation']),
  );
}

/// Maps an HTTP status / backend error token to a UI error kind.
/// A `null` [statusCode] means a transport/network failure.
StreetBusinessInvoiceErrorKind classifyStreetBusinessInvoiceError({
  int? statusCode,
  String? errorToken,
}) {
  final token = _lower(errorToken);
  // Token-specific classification comes first so driver-auth reasons (which
  // share HTTP status codes with other cases) map to the correct message.
  if (token == 'billing_identity_conflict') {
    return StreetBusinessInvoiceErrorKind.identityConflict;
  }
  if (token == 'driver_not_assigned' || token == 'driver_session_required') {
    return StreetBusinessInvoiceErrorKind.driverNotAuthorized;
  }
  if (token == 'not_a_street_booking' ||
      token == 'booking_not_completed' ||
      token == 'booking_not_invoiceable_state' ||
      token == 'source_booking_not_found') {
    return StreetBusinessInvoiceErrorKind.notCompletedStreet;
  }
  if (token == 'billing_customer_not_ready') {
    return StreetBusinessInvoiceErrorKind.readiness;
  }
  if (token == 'not_in_scope' || token == 'forbidden') {
    return StreetBusinessInvoiceErrorKind.accessDenied;
  }
  if (token == 'invoice_already_exists' || token == 'already_exists') {
    return StreetBusinessInvoiceErrorKind.alreadyExists;
  }
  // Fall back to HTTP status codes when no specific token matched.
  if (statusCode == 409) {
    return StreetBusinessInvoiceErrorKind.identityConflict;
  }
  if (statusCode == 403) {
    return StreetBusinessInvoiceErrorKind.accessDenied;
  }
  if (statusCode == 422) {
    return StreetBusinessInvoiceErrorKind.readiness;
  }
  if (statusCode == null) return StreetBusinessInvoiceErrorKind.network;
  return StreetBusinessInvoiceErrorKind.unknown;
}

/// Safe display projection of an invoice document from the documents-list
/// envelope. Buyer/PII fields are never carried.
@immutable
class StreetInvoiceDocSummary {
  final String documentId;
  final String documentNumber;
  final String lifecycleState;
  final String billitEnvironment;
  final String billitOrderId;
  final bool peppolSent;
  final bool? billitPaid;
  final String billitPaymentSyncStatus;
  final String saleKind;

  const StreetInvoiceDocSummary({
    required this.documentId,
    required this.documentNumber,
    required this.lifecycleState,
    required this.billitEnvironment,
    required this.billitOrderId,
    required this.peppolSent,
    required this.billitPaid,
    this.billitPaymentSyncStatus = '',
    this.saleKind = 'business_invoice',
  });
}

/// Counts normal invoice documents in a documents-list envelope. Returns 0 for
/// any invalid/failed envelope (never treats a failed GET as a definitive 0
/// for lifecycle decisions — callers gate on [documentsEnvelopeOk] first).
int countInvoiceDocuments(Object? decoded) {
  if (decoded is! Map) return 0;
  final docs = decoded['documents'];
  if (docs is! List) return 0;
  var count = 0;
  for (final d in docs) {
    if (d is Map && _lower(d['document_type']) == 'invoice') count++;
  }
  return count;
}

/// True when a documents-list envelope is a valid, successful response.
bool documentsEnvelopeOk(Object? decoded) =>
    decoded is Map && decoded['ok'] == true;

/// True when a documents-list row is a convertible / presentation consumer
/// sale (never a business invoice or credit note).
bool documentRecordIsConsumerSale(Map doc) {
  final saleKind = _lower(
    doc['fluxidi_sale_kind'] ??
        doc['fluxidiSaleKind'] ??
        doc['sale_kind'] ??
        doc['saleKind'],
  );
  if (saleKind == 'consumer_sale' ||
      saleKind == 'private_sale' ||
      saleKind == 'particuliere_verkoop' ||
      saleKind == 'ritbon') {
    return true;
  }
  if (saleKind == 'business_invoice' ||
      saleKind == 'credit_note' ||
      saleKind == 'creditnote' ||
      saleKind == 'consumer_conversion_credit') {
    return false;
  }
  final role = _lower(doc['created_by_role'] ?? doc['createdByRole']);
  if (role == 'system_consumer_sale' || role.contains('consumer_sale')) {
    return true;
  }
  return false;
}

bool documentRecordIsBusinessInvoice(Map doc) {
  if (documentRecordIsConsumerSale(doc)) return false;
  final saleKind = _lower(
    doc['fluxidi_sale_kind'] ??
        doc['fluxidiSaleKind'] ??
        doc['sale_kind'] ??
        doc['saleKind'],
  );
  if (saleKind == 'credit_note' ||
      saleKind == 'creditnote' ||
      saleKind == 'consumer_conversion_credit') {
    return false;
  }
  final type = _lower(doc['document_type'] ?? doc['documentType']);
  if (type == 'credit_note' || type == 'creditnote') return false;
  if (doc['superseded'] == true) return false;
  if (saleKind == 'business_invoice' || saleKind == 'zakelijke_factuur') {
    return true;
  }
  final intent = _lower(doc['invoice_intent'] ?? doc['invoiceIntent']);
  if (intent == 'business_invoice') return true;
  if (doc['explicit_business_invoice'] == true) return true;
  if (doc['peppol_applicable'] == true || doc['peppolApplicable'] == true) {
    return true;
  }
  // Bare document_type=invoice is not business evidence.
  return false;
}

/// CONSUMER-SALE-LATE-INVOICE-ACTION-PLACEMENT-P1 /
/// ROUNDTRIP-CONSUMER-SALE-LATE-INVOICE-ACTION-P0-4
///
/// True when a documents GET envelope contains a convertible consumer sale and
/// no linked business invoice for the optional leg scope — used to mount the
/// single large action above Documenten (never guessed when docs are empty).
/// Roundtrip leg cards MUST pass [sourceLegId]/[sourceLegType] so a sibling
/// leg's consumer sale cannot unlock the button on this card.
bool documentsEnvelopeHasConvertibleConsumerSale(
  Object? decoded, {
  String? sourceLegId,
  String? sourceLegType,
}) {
  if (!documentsEnvelopeOk(decoded)) return false;
  final docs = (decoded as Map)['documents'];
  if (docs is! List || docs.isEmpty) return false;

  final scoped = <Map>[];
  for (final d in docs) {
    if (d is! Map) continue;
    final asMap = d.map((k, v) => MapEntry(k.toString(), v));
    final legFields = readBookingDocumentLegFieldsFromJson(asMap);
    if (!bookingDocumentMatchesLegFilter(
      legFields,
      sourceLegId: sourceLegId,
      sourceLegType: sourceLegType,
    )) {
      continue;
    }
    scoped.add(d);
  }
  if (scoped.isEmpty) return false;

  var businessInvoicePresent = false;
  for (final d in scoped) {
    if (documentRecordIsBusinessInvoice(d)) {
      businessInvoicePresent = true;
      break;
    }
  }
  if (businessInvoicePresent) return false;

  for (final d in scoped) {
    final saleKind =
        d['fluxidi_sale_kind'] ??
        d['fluxidiSaleKind'] ??
        d['sale_kind'] ??
        d['saleKind'];
    final documentType = d['document_type'] ?? d['documentType'];
    final createdByRole = d['created_by_role'] ?? d['createdByRole'];
    bool? peppolApplicable;
    if (d['peppol_applicable'] == true || d['peppolApplicable'] == true) {
      peppolApplicable = true;
    } else if (d['peppol_applicable'] == false ||
        d['peppolApplicable'] == false) {
      peppolApplicable = false;
    }
    final lifecycle =
        d['lifecycle_state'] ??
        d['lifecycleState'] ??
        d['document_status'] ??
        d['documentStatus'];
    if (shouldShowLateBusinessInvoiceAction(
      saleKind: saleKind,
      documentType: documentType,
      createdByRole: createdByRole,
      peppolApplicable: peppolApplicable,
      superseded: d['superseded'] == true,
      lifecycleState: lifecycle,
      businessInvoicePresent: false,
      conversionInProgress: false,
      conversionAllowed: true,
    )) {
      return true;
    }
  }
  return false;
}

/// Extracts a single **business** invoice summary from a documents-list
/// envelope. Consumer sales and credit notes are ignored so a private Billit
/// sale never blocks “Zakelijke factuur aanvragen”.
StreetInvoiceDocSummary? extractInvoiceFromDocuments(
  Object? decoded, {
  String? expectedDocumentId,
}) {
  if (!documentsEnvelopeOk(decoded)) return null;
  final docs = (decoded as Map)['documents'];
  if (docs is! List) return null;
  final invoices = <Map>[];
  for (final d in docs) {
    if (d is Map && documentRecordIsBusinessInvoice(d)) invoices.add(d);
  }
  if (invoices.isEmpty) return null;

  Map chosen = invoices.first;
  final wanted = (expectedDocumentId ?? '').trim();
  if (wanted.isNotEmpty) {
    for (final d in invoices) {
      if (_norm(d['document_id']) == wanted) {
        chosen = d;
        break;
      }
    }
  }

  final billit = chosen['billit_export'];
  final billitMap = billit is Map ? billit : const <dynamic, dynamic>{};
  bool? billitPaid;
  final rawPaid = billitMap['billit_paid'];
  if (rawPaid is bool) billitPaid = rawPaid;

  return StreetInvoiceDocSummary(
    documentId: _norm(chosen['document_id']),
    documentNumber: _norm(chosen['document_number']),
    lifecycleState: _lower(chosen['lifecycle_state']),
    billitEnvironment: _lower(billitMap['environment']),
    billitOrderId: _norm(billitMap['order_id']),
    peppolSent: billitMap['peppol_sent'] == true,
    billitPaid: billitPaid,
    billitPaymentSyncStatus: _norm(
      billitMap['billit_payment_sync_status'] ??
          billitMap['billitPaymentSyncStatus'],
    ),
    saleKind: _lower(
      chosen['fluxidi_sale_kind'] ??
          chosen['fluxidiSaleKind'] ??
          chosen['sale_kind'] ??
          'business_invoice',
    ),
  );
}

/// Reads booking-level invoice PDF artifact readiness from a documents-list
/// envelope (`invoice_pdf.ready` / `invoice_pdf.exists`). Returns null when the
/// envelope does not carry the field (caller must then probe the PDF endpoint).
bool? extractInvoicePdfReadyFromDocuments(Object? decoded) {
  if (!documentsEnvelopeOk(decoded)) return null;
  final pdf = (decoded as Map)['invoice_pdf'];
  if (pdf is! Map) return null;
  if (pdf['ready'] is bool) return pdf['ready'] as bool;
  if (pdf['exists'] is bool) return pdf['exists'] as bool;
  return null;
}

/// Result of the injected POST callback.
@immutable
class StreetInvoicePostResult {
  /// HTTP status code, or null for a transport/network failure.
  final int? statusCode;
  final StreetBusinessInvoiceResponse? response;
  final String? errorToken;

  const StreetInvoicePostResult({
    this.statusCode,
    this.response,
    this.errorToken,
  });
}

/// Result of the injected documents GET callback.
@immutable
class StreetInvoiceDocsResult {
  final int? statusCode;
  final bool okEnvelope;
  final StreetInvoiceDocSummary? invoice;

  /// Booking-level PDF artifact readiness from the documents envelope, when
  /// the backend includes `invoice_pdf`. Null means "unknown — probe required".
  final bool? invoicePdfReady;

  const StreetInvoiceDocsResult({
    this.statusCode,
    this.okEnvelope = false,
    this.invoice,
    this.invoicePdfReady,
  });
}

/// Result of an injected PDF endpoint probe (GET invoice/pdf).
@immutable
class StreetInvoicePdfProbeResult {
  final int? statusCode;
  final bool failed;

  const StreetInvoicePdfProbeResult({this.statusCode, this.failed = false});
}

/// Small, disposable, per-booking controller for the invoice action.
///
/// Networking is injected ([postInvoice], [fetchDocuments]) so the whole
/// lifecycle (submit, idempotent guard, bounded polling, eventual-consistency
/// handling) is unit-testable without Flutter's HTTP stack or real timers.
///
/// Guarantees:
///   - exactly one in-flight POST per booking (double-tap safe),
///   - visibility polling issues ONLY GET requests (never POST),
///   - no overlapping polls (sequential await loop),
///   - a successful POST result is always retained even if the index lags.
class StreetBusinessInvoiceController extends ChangeNotifier {
  StreetBusinessInvoiceController({
    required this.bookingId,
    required this.isPaidBooking,
    required Future<StreetInvoicePostResult> Function(Map<String, dynamic> body)
    postInvoice,
    required Future<StreetInvoiceDocsResult> Function() fetchDocuments,
    Future<StreetInvoicePdfProbeResult> Function()? probePdf,
    Duration pollInterval = const Duration(seconds: 2),
    Duration pollTimeout = const Duration(seconds: 30),
    List<Duration> statusRefreshDelays = kStreetInvoiceStatusRefreshDelays,
    Future<void> Function(Duration)? delay,
  }) : _postInvoice = postInvoice,
       _fetchDocuments = fetchDocuments,
       _probePdf = probePdf,
       _pollInterval = pollInterval,
       _pollTimeout = pollTimeout,
       _statusRefreshDelays = List<Duration>.unmodifiable(statusRefreshDelays),
       _delay = delay ?? Future<void>.delayed;

  final String bookingId;

  /// The ride-paid value at construction time. Retained for reference; the live
  /// canonical value is [_canonicalRidePaid] which is updated monotonically via
  /// [updateCanonicalRidePaymentStatus] (1D).
  final bool isPaidBooking;

  /// Canonical ride (booking) payment, seeded from [isPaidBooking]. A missing or
  /// false invoice-document field NEVER downgrades this — only an explicit
  /// reversal can (see [updateCanonicalRidePaymentStatus]).
  late bool _canonicalRidePaid = isPaidBooking;

  final Future<StreetInvoicePostResult> Function(Map<String, dynamic> body)
  _postInvoice;
  final Future<StreetInvoiceDocsResult> Function() _fetchDocuments;
  final Future<StreetInvoicePdfProbeResult> Function()? _probePdf;
  final Duration _pollInterval;
  final Duration _pollTimeout;
  final List<Duration> _statusRefreshDelays;
  final Future<void> Function(Duration) _delay;

  StreetBusinessInvoiceUiState _state =
      StreetBusinessInvoiceUiState.eligibleNoInvoice;
  StreetBusinessInvoiceResponse? _issuedResponse;
  StreetInvoiceDocSummary? _indexedInvoice;
  StreetBusinessInvoiceErrorKind? _errorKind;

  bool? _invoicePdfReady;
  int? _pdfProbeStatusCode;
  bool _pdfProbeFailed = false;
  bool _submitting = false;
  bool _polling = false;
  bool _statusRefreshing = false;
  bool _disposed = false;
  Future<void>? _pollingFuture;
  Future<void>? _statusRefreshFuture;

  /// The in-flight bounded-polling loop, exposed so tests can deterministically
  /// await completion. Null until the first successful submit.
  @visibleForTesting
  Future<void>? get pollingFuture => _pollingFuture;

  @visibleForTesting
  Future<void>? get statusRefreshFuture => _statusRefreshFuture;

  StreetBusinessInvoiceUiState get state => _state;
  StreetBusinessInvoiceResponse? get issuedResponse => _issuedResponse;
  StreetInvoiceDocSummary? get indexedInvoice => _indexedInvoice;
  StreetBusinessInvoiceErrorKind? get errorKind => _errorKind;

  /// True once a successful POST result is held (any indexed/delayed state).
  bool get hasIssuedInvoice =>
      _issuedResponse != null || _indexedInvoice != null;

  /// Canonical ride-paid used by the payment presentation (1D). True when the
  /// ride is confirmed paid at the receipt OR the issued POST response reports
  /// paid. This — not the raw constructor value — feeds the resolver, so a late
  /// receipt-paid transition is honored without recreating the controller.
  bool get rideConfirmedPaid =>
      _canonicalRidePaid || (_issuedResponse?.isPaid == true);

  /// Monotonic canonical ride-paid update (1D). Once the ride is canonically
  /// paid it stays paid unless [reversal] is set for an explicit backend
  /// refund/void. A false or unknown signal (e.g. a documents envelope without
  /// payment_status, or a stale poll) is ignored, so a lagging index can never
  /// flip a confirmed-paid ride back to outstanding.
  void updateCanonicalRidePaymentStatus(bool isPaid, {bool reversal = false}) {
    if (reversal) {
      if (_canonicalRidePaid) {
        _canonicalRidePaid = false;
        notifyListeners();
      }
      return;
    }
    if (isPaid && !_canonicalRidePaid) {
      _canonicalRidePaid = true;
      notifyListeners();
    }
  }

  /// The invoice reference to display, preferring the indexed doc when present.
  String get displayInvoiceReference =>
      _indexedInvoice?.documentNumber.isNotEmpty == true
      ? _indexedInvoice!.documentNumber
      : (_issuedResponse?.invoiceReference ?? '');

  /// The document id to open, preferring the indexed doc when present.
  String get displayDocumentId => _indexedInvoice?.documentId.isNotEmpty == true
      ? _indexedInvoice!.documentId
      : (_issuedResponse?.documentId ?? '');

  StreetInvoicePdfAvailability get pdfAvailability =>
      resolveStreetInvoicePdfAvailability(
        hasIssuedInvoice: hasIssuedInvoice,
        pdfArtifactReady: _invoicePdfReady,
        pdfProbeStatusCode: _pdfProbeStatusCode,
        pdfProbeFailed: _pdfProbeFailed,
        documentReference: displayInvoiceReference,
      );

  StreetInvoicePaymentPresentation get paymentPresentation =>
      resolveStreetInvoicePaymentPresentation(
        hasIssuedInvoice: hasIssuedInvoice,
        ridePaid: rideConfirmedPaid,
        responsePaymentPaid: _issuedResponse?.isPaid == true,
        billitPaid: _indexedInvoice?.billitPaid,
        billitPaymentSyncStatus:
            (_indexedInvoice?.billitPaymentSyncStatus.isNotEmpty == true
                ? _indexedInvoice!.billitPaymentSyncStatus
                : (_issuedResponse?.billitPaymentSyncStatus ?? '')),
        // Billit still updating when no order link yet (or PDF still preparing
        // alongside an unconfirmed paid sync — presentation stays syncPending).
        billitUpdating: !hasBillitLink,
        syncPending:
            _indexedInvoice?.billitPaid == false ||
            (_issuedResponse?.isPaid == true &&
                (_indexedInvoice?.billitPaid != true)),
        hasBillitLink: hasBillitLink,
        peppolSent: displayPeppolSent,
        pdfReady: pdfAvailability.canViewOrShare,
        lifecycleState: _indexedInvoice?.lifecycleState ?? '',
        visibilityDelayed:
            _state == StreetBusinessInvoiceUiState.visibilityDelayed,
      );

  /// Language-independent invoice payment status for card + detail modal.
  StreetInvoiceInvoicePaymentStatus get displayInvoicePaymentStatus =>
      paymentPresentation.invoicePaymentStatus;

  /// True when the invoice payment is definitively paid (Billit paid / synced).
  /// Sync-in-progress is NOT treated as unpaid — see [paymentPresentation].
  bool get displayIsPaid =>
      displayInvoicePaymentStatus == StreetInvoiceInvoicePaymentStatus.paid;

  bool get displayPaymentSyncInProgress =>
      displayInvoicePaymentStatus ==
      StreetInvoiceInvoicePaymentStatus.syncInProgress;

  bool get displayPaymentSyncFailed =>
      displayInvoicePaymentStatus ==
      StreetInvoiceInvoicePaymentStatus.syncFailed;

  bool get displayNotLinkedToBillit =>
      displayInvoicePaymentStatus ==
      StreetInvoiceInvoicePaymentStatus.notLinkedToBillit;

  /// Language-independent raw inputs + resolved semantic status, so the card
  /// and the detail modal can emit identical bounded diagnostics and prove the
  /// same enum reaches both surfaces regardless of locale (1C).
  StreetInvoicePaymentDiagnostics get paymentDiagnostics =>
      StreetInvoicePaymentDiagnostics(
        ridePaid: rideConfirmedPaid,
        billitPaid: _indexedInvoice?.billitPaid,
        billitPaymentSyncStatus:
            (_indexedInvoice?.billitPaymentSyncStatus.isNotEmpty == true
                ? _indexedInvoice!.billitPaymentSyncStatus
                : (_issuedResponse?.billitPaymentSyncStatus ?? '')),
        billitUpdating: !hasBillitLink,
        semanticStatus: displayInvoicePaymentStatus,
      );

  /// Peppol is only ever true when the backend explicitly reports it.
  bool get displayPeppolSent =>
      _indexedInvoice?.peppolSent == true ||
      _issuedResponse?.peppolSent == true;

  /// The Billit order id to display, preferring the indexed document.
  String get displayBillitOrderId {
    final indexed = (_indexedInvoice?.billitOrderId ?? '').trim();
    if (indexed.isNotEmpty) return indexed;
    return (_issuedResponse?.billitOrderId ?? '').trim();
  }

  /// True only when a real Billit link exists (a non-empty Billit order id from
  /// the POST response or the indexed document). Never inferred from
  /// billit_environment alone, so the UI can be honest about "created in Billit"
  /// versus "Billit still updating".
  bool get hasBillitLink => displayBillitOrderId.isNotEmpty;

  int _maxPollAttempts() {
    final ms = _pollInterval.inMilliseconds;
    if (ms <= 0) return 1;
    final n = (_pollTimeout.inMilliseconds / ms).ceil();
    return n < 1 ? 1 : n;
  }

  void _set(StreetBusinessInvoiceUiState next) {
    if (_disposed) return;
    _state = next;
    notifyListeners();
  }

  void _notify() {
    if (_disposed) return;
    notifyListeners();
  }

  bool _matchesExpected(StreetInvoiceDocSummary inv) {
    final expected = (_issuedResponse?.documentId ?? '').trim();
    if (expected.isEmpty) return true;
    return inv.documentId == expected;
  }

  void _applyDocsResult(StreetInvoiceDocsResult r) {
    if (r.invoicePdfReady != null) _invoicePdfReady = r.invoicePdfReady;
    if (r.okEnvelope && r.invoice != null && _matchesExpected(r.invoice!)) {
      _indexedInvoice = r.invoice;
      if (_state == StreetBusinessInvoiceUiState.eligibleNoInvoice ||
          _state == StreetBusinessInvoiceUiState.issuedFromResponse ||
          _state == StreetBusinessInvoiceUiState.visibilityDelayed) {
        _state = StreetBusinessInvoiceUiState.issuedIndexed;
      }
    }
  }

  Future<void> _probePdfOnce() async {
    final probe = _probePdf;
    if (probe == null) return;
    try {
      final r = await probe();
      if (_disposed) return;
      _pdfProbeStatusCode = r.statusCode;
      _pdfProbeFailed = r.failed;
    } catch (_) {
      if (_disposed) return;
      _pdfProbeFailed = true;
    }
  }

  /// Bounded status refresh: documents + PDF probe on the schedule
  /// [kStreetInvoiceStatusRefreshDelays]. Stops early when PDF is available and
  /// payment is no longer syncing (or on dispose).
  Future<void> _runStatusRefreshLoop() async {
    if (_statusRefreshing) return;
    _statusRefreshing = true;
    try {
      var previousDelay = Duration.zero;
      for (final delay in _statusRefreshDelays) {
        if (_disposed) return;
        final wait = delay - previousDelay;
        previousDelay = delay;
        if (wait > Duration.zero) await _delay(wait);
        if (_disposed) return;

        try {
          final r = await _fetchDocuments();
          if (_disposed) return;
          _applyDocsResult(r);
        } catch (_) {
          // Non-fatal: keep last known docs state.
        }
        if (_disposed) return;
        if (!pdfAvailability.canViewOrShare) {
          await _probePdfOnce();
        }
        if (_disposed) return;
        _notify();

        final pdfDone = pdfAvailability.canViewOrShare;
        // Stop only when Billit has confirmed paid — sync-in-progress and
        // sync-failed both keep the bounded refresh alive for catch-up.
        final payDone = displayIsPaid;
        if (pdfDone && payDone) return;
        // Stop early on terminal PDF auth denial.
        if (pdfAvailability.state ==
            StreetInvoicePdfAvailabilityState.unavailable) {
          return;
        }
      }
    } finally {
      _statusRefreshing = false;
    }
  }

  void _kickStatusRefresh() {
    if (_disposed || !hasIssuedInvoice) return;
    _statusRefreshFuture = _runStatusRefreshLoop();
  }

  /// Manual retry of documents + PDF readiness (UI "Opnieuw controleren").
  Future<void> refreshStatus() async {
    if (_disposed || !hasIssuedInvoice) return;
    try {
      final r = await _fetchDocuments();
      if (_disposed) return;
      _applyDocsResult(r);
    } catch (_) {
      // leave last state
    }
    if (_disposed) return;
    await _probePdfOnce();
    if (_disposed) return;
    _notify();
  }

  /// Read-only existence check on (re)open: detects an already-issued invoice
  /// and renders "view". A failed GET is non-alarming: it leaves the action in
  /// [StreetBusinessInvoiceUiState.eligibleNoInvoice] rather than showing an
  /// error, and never fabricates a zero-document verdict. When an invoice is
  /// found, starts bounded PDF/payment status refresh from the backend.
  Future<void> loadExisting() async {
    StreetInvoiceDocsResult r;
    try {
      r = await _fetchDocuments();
    } catch (_) {
      return;
    }
    if (_disposed) return;
    if (r.okEnvelope && r.invoice != null) {
      _applyDocsResult(r);
      _set(StreetBusinessInvoiceUiState.issuedIndexed);
      _kickStatusRefresh();
    }
  }

  /// Submit exactly one invoice request. Re-entrancy is guarded so repeated
  /// taps produce a single POST. After a prior failure (especially a network
  /// ambiguity) the documents index is re-checked before create so a second
  /// invoice cannot be spawned by retry.
  Future<void> submit(StreetBusinessInvoiceBuyerInput input) async {
    if (_submitting || _state == StreetBusinessInvoiceUiState.submitting)
      return;
    if (hasIssuedInvoice) return; // already issued: nothing to POST

    final retrying =
        _state == StreetBusinessInvoiceUiState.error || _errorKind != null;
    if (retrying) {
      await loadExisting();
      if (_disposed || hasIssuedInvoice) return;
    }

    _submitting = true;
    _errorKind = null;
    _set(StreetBusinessInvoiceUiState.submitting);

    StreetInvoicePostResult result;
    try {
      result = await _postInvoice(input.toRequestBody());
    } catch (_) {
      result = const StreetInvoicePostResult(statusCode: null);
    }
    _submitting = false;
    if (_disposed) return;

    final resp = result.response;
    if (result.statusCode == 200 && resp != null && resp.ok) {
      _issuedResponse = resp;
      _set(StreetBusinessInvoiceUiState.issuedFromResponse);
      // Bounded document-index polling + status refresh (PDF / paid sync).
      _pollingFuture = _runPollingLoop();
      _kickStatusRefresh();
      return;
    }

    final kind = classifyStreetBusinessInvoiceError(
      statusCode: result.statusCode,
      errorToken: result.errorToken,
    );
    if (kind == StreetBusinessInvoiceErrorKind.alreadyExists ||
        kind == StreetBusinessInvoiceErrorKind.network) {
      // Ambiguous outcome: confirm server state before offering another create.
      await loadExisting();
      if (_disposed) return;
      if (hasIssuedInvoice) return;
    }
    _errorKind = kind;
    _set(StreetBusinessInvoiceUiState.error);
  }

  /// Bounded GET-only polling of the documents index after a successful POST.
  Future<void> _runPollingLoop() async {
    if (_polling) return;
    _polling = true;
    final maxAttempts = _maxPollAttempts();
    try {
      for (var attempt = 0; attempt < maxAttempts; attempt++) {
        if (_disposed) return;
        await _delay(_pollInterval);
        if (_disposed) return;
        StreetInvoiceDocsResult? r;
        try {
          r = await _fetchDocuments();
        } catch (_) {
          r = null;
        }
        if (_disposed) return;
        final inv = r?.invoice;
        if (r != null && r.okEnvelope && inv != null && _matchesExpected(inv)) {
          _applyDocsResult(r);
          _set(StreetBusinessInvoiceUiState.issuedIndexed);
          return;
        }
      }
      // Window exhausted: retain success, surface a non-alarming delayed state.
      if (!_disposed &&
          _state == StreetBusinessInvoiceUiState.issuedFromResponse) {
        _set(StreetBusinessInvoiceUiState.visibilityDelayed);
      }
    } finally {
      _polling = false;
    }
  }

  /// Deterministic single poll step for tests.
  @visibleForTesting
  Future<bool> debugPollOnce() async {
    StreetInvoiceDocsResult? r;
    try {
      r = await _fetchDocuments();
    } catch (_) {
      r = null;
    }
    if (_disposed) return false;
    final inv = r?.invoice;
    if (r != null && r.okEnvelope && inv != null && _matchesExpected(inv)) {
      _applyDocsResult(r);
      _set(StreetBusinessInvoiceUiState.issuedIndexed);
      return true;
    }
    return false;
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
