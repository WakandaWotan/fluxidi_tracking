// RELEASE-P0-MOLLIE-STREET-CHECKOUT-1
//
// Pure, dependency-free decision model + response/error parsing for the
// online (Mollie-hosted) checkout of a finalized street/direct ride from the
// driver receipt Payment section. Kept separate from the widget so
// eligibility, response parsing, error classification and poll-status
// classification are unit-testable without Flutter.
//
// This module never talks to the network itself — the concrete HTTP calls
// (`POST /bookings/:id/street-checkout`, `GET /pay/status`) are made by the
// receipt widget, which feeds the raw decoded JSON / HTTP status back into
// the pure functions below.
library;

String _norm(Object? v) => (v ?? '').toString().trim();
String _lower(Object? v) => _norm(v).toLowerCase();

bool _asBool(Object? v) {
  if (v is bool) return v;
  final t = _lower(v);
  return t == '1' || t == 'true' || t == 'yes' || t == 'on';
}

double? _asDouble(Object? v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString().trim());
}

Map<String, dynamic>? _asMap(Object? v) {
  if (v is Map<String, dynamic>) return v;
  if (v is Map) return Map<String, dynamic>.from(v);
  return null;
}

String? _firstNonEmpty(Map<String, dynamic> map, List<String> keys) {
  for (final key in keys) {
    final raw = map[key];
    if (raw == null) continue;
    final text = raw.toString().trim();
    if (text.isNotEmpty && text.toLowerCase() != 'null') return text;
  }
  return null;
}

/// True when [bookingId]/[source]/[bookingSource]/[rideType] mark this ride
/// as a street/direct ride eligible for the driver-initiated online checkout.
/// Unlike the (stricter) business-invoice canonical-identity check, a bare
/// `ride_type == direct` is accepted here as a sufficient marker on its own,
/// since a direct/street ride finalized from the driver app always carries at
/// least one of these signals.
bool hasStreetOrDirectRideMarker({
  required String bookingId,
  String? source,
  String? bookingSource,
  String? rideType,
}) {
  if (_lower(bookingId).startsWith('street_')) return true;
  if (_lower(source) == 'street_ride') return true;
  if (_lower(bookingSource) == 'street_ride') return true;
  if (_lower(rideType) == 'direct') return true;
  return false;
}

/// Whether the primary "Online betalen" action may be offered on the receipt
/// Payment section for this ride.
///
/// Requires ALL of:
///   * a non-empty booking id (needed to call `/bookings/:id/street-checkout`),
///   * a street/direct ride marker ([hasStreetOrDirectRideMarker]),
///   * not already paid,
///   * not cancelled,
///   * a positive payable amount.
bool resolveMollieStreetCheckoutEligible({
  required String bookingId,
  required bool isPaid,
  required bool isCancelled,
  double? amount,
  String? source,
  String? bookingSource,
  String? rideType,
}) {
  final id = bookingId.trim();
  if (id.isEmpty) return false;
  if (isPaid || isCancelled) return false;
  if (amount == null || amount <= 0) return false;
  return hasStreetOrDirectRideMarker(
    bookingId: id,
    source: source,
    bookingSource: bookingSource,
    rideType: rideType,
  );
}

/// Parsed result of `POST /bookings/:id/street-checkout`.
class MollieStreetCheckoutStartResult {
  const MollieStreetCheckoutStartResult({
    required this.ok,
    this.checkoutUrl,
    this.qrSrc,
    this.paymentBookingId,
    this.amount,
    this.reused = false,
  });

  final bool ok;
  final String? checkoutUrl;
  final String? qrSrc;
  final String? paymentBookingId;
  final double? amount;

  /// True when the backend returned an existing open checkout instead of
  /// creating a new one (the driver re-tapped "Online betalen" while a
  /// Mollie payment was already open for this ride).
  final bool reused;

  bool get hasCheckout =>
      (checkoutUrl != null && checkoutUrl!.trim().isNotEmpty) ||
      (qrSrc != null && qrSrc!.trim().isNotEmpty);

  @override
  String toString() =>
      'MollieStreetCheckoutStartResult(ok: $ok, hasCheckout: $hasCheckout, '
      'reused: $reused, hasPaymentBookingId: '
      '${(paymentBookingId ?? '').isNotEmpty})';
}

/// Parses the `POST /bookings/:id/street-checkout` success body. Accepts
/// several reasonable field-name shapes (snake_case / camelCase, top-level or
/// nested under `booking`/`payment`) so the client tolerates minor backend
/// contract variance without a Flutter release.
MollieStreetCheckoutStartResult parseMollieStreetCheckoutStartResponse(
  Map<String, dynamic> decoded,
) {
  final bookingMap = _asMap(decoded['booking']) ?? const <String, dynamic>{};
  final paymentMap = _asMap(decoded['payment']) ?? const <String, dynamic>{};

  final checkoutUrl =
      _firstNonEmpty(decoded, const [
        'checkout_url',
        'checkoutUrl',
        'payment_url',
        'paymentUrl',
      ]) ??
      _firstNonEmpty(paymentMap, const ['checkout_url', 'checkoutUrl']) ??
      _firstNonEmpty(bookingMap, const ['checkout_url', 'checkoutUrl']);

  final qrCandidates = <Map<String, dynamic>?>[
    _asMap(decoded['qr_code']),
    _asMap(decoded['qrCode']),
    _asMap(paymentMap['qr_code']),
    _asMap(paymentMap['qrCode']),
    _asMap(bookingMap['qr_code']),
    _asMap(bookingMap['qrCode']),
  ];
  String? qrSrc;
  for (final qr in qrCandidates) {
    final src = (qr?['src'] ?? '').toString().trim();
    if (src.isNotEmpty) {
      qrSrc = src;
      break;
    }
  }

  final paymentBookingId =
      _firstNonEmpty(decoded, const ['payment_booking_id', 'paymentBookingId']) ??
      _firstNonEmpty(paymentMap, const [
        'payment_booking_id',
        'paymentBookingId',
        'id',
      ]) ??
      _firstNonEmpty(bookingMap, const [
        'payment_booking_id',
        'paymentBookingId',
      ]);

  final amount =
      _asDouble(decoded['amount']) ??
      _asDouble(paymentMap['amount']) ??
      _asDouble(bookingMap['amount']);

  final reused =
      _asBool(decoded['reused']) ||
      _asBool(decoded['is_reused']) ||
      _asBool(decoded['existing_open']) ||
      _lower(decoded['status']) == 'existing_open';

  final checkoutUrlNonEmpty = (checkoutUrl ?? '').isNotEmpty;
  final qrSrcNonEmpty = (qrSrc ?? '').isNotEmpty;
  final ok = decoded['ok'] == true || checkoutUrlNonEmpty || qrSrcNonEmpty;

  return MollieStreetCheckoutStartResult(
    ok: ok,
    checkoutUrl: checkoutUrl,
    qrSrc: qrSrc,
    paymentBookingId: paymentBookingId,
    amount: amount,
    reused: reused,
  );
}

/// Backend error kinds for a failed `POST /bookings/:id/street-checkout`.
enum MollieStreetCheckoutErrorKind {
  /// 401 — no usable driver/company bearer.
  authRequired,

  /// The ride is already paid (server-authoritative, races the client's own
  /// stale "unpaid" view).
  rideAlreadyPaid,

  /// The company has no Mollie account connected.
  mollieNotConnected,

  /// Mollie is connected but has no active online payment method.
  noOnlineMethods,

  /// The booking is not (or no longer) eligible for a street checkout
  /// (not a street/direct ride, or not in a checkout-eligible state).
  notEligible,

  /// An open Tap to Pay (POS) payment still blocks minting a new hosted
  /// checkout for this ride.
  openPosPaymentExists,

  /// Transport-level failure (timeout / no connectivity / non-JSON body).
  network,

  /// Anything else / unrecognised.
  unknown,
}

/// Classifies a failed street-checkout start response.
MollieStreetCheckoutErrorKind classifyMollieStreetCheckoutStartError({
  required int httpCode,
  Map<String, dynamic>? decoded,
}) {
  if (httpCode == 401) return MollieStreetCheckoutErrorKind.authRequired;
  if (httpCode == 0) return MollieStreetCheckoutErrorKind.network;

  final err = _lower(
    decoded?['error'] ?? decoded?['error_code'] ?? decoded?['code'],
  );
  if (err.contains('already_paid') ||
      err.contains('ride_paid') ||
      err.contains('booking_paid')) {
    return MollieStreetCheckoutErrorKind.rideAlreadyPaid;
  }
  if (err.contains('not_connected') ||
      err.contains('mollie_not_connected') ||
      err.contains('no_mollie_account')) {
    return MollieStreetCheckoutErrorKind.mollieNotConnected;
  }
  if (err.contains('no_online_method') ||
      err.contains('no_active_method') ||
      err.contains('online_payments_unavailable') ||
      err.contains('no_payment_method')) {
    return MollieStreetCheckoutErrorKind.noOnlineMethods;
  }
  if (err.contains('not_a_street') ||
      err.contains('not_street_ride') ||
      err.contains('not_eligible') ||
      err.contains('booking_not_completed')) {
    return MollieStreetCheckoutErrorKind.notEligible;
  }
  if (err == 'open_pos_payment_exists' || err.contains('open_pos_payment')) {
    return MollieStreetCheckoutErrorKind.openPosPaymentExists;
  }
  return MollieStreetCheckoutErrorKind.unknown;
}

/// True when a response carries authoritative evidence that an online Mollie
/// checkout for THIS ride may still settle and therefore blocks QR / cash /
/// Tap to Pay / new checkout until recovered.
///
/// PHANTOM-MOLLIE-OPEN-PAYMENT-FALSE-POSITIVE-P0: never infer an open owner
/// from generic Mollie errors (create failed, credentials, empty error) or
/// from the substring "mollie". Only explicit canonical conflict signals.
bool manualPaymentBlockedByOpenMollieCheckout({
  required int httpCode,
  Map<String, dynamic>? decoded,
}) {
  if (httpCode != 409) return false;
  if (decoded == null) return false;
  return _hasAuthoritativeOpenMollieCheckoutEvidence(decoded);
}

/// Authoritative open-checkout / recovery evidence (HTTP-agnostic payload).
bool _hasAuthoritativeOpenMollieCheckoutEvidence(Map<String, dynamic> decoded) {
  if (_asBool(decoded['requires_confirm_cancel_mollie']) ||
      _asBool(decoded['confirm_cancel_required']) ||
      _asBool(decoded['confirm_cancel_open_mollie_required']) ||
      _asBool(decoded['requires_confirm_cancel_open_mollie'])) {
    return true;
  }
  if (_asMap(decoded['open_checkout'] ?? decoded['openCheckout']) != null) {
    return true;
  }
  if (_asMap(decoded['recovery']) != null) {
    return true;
  }
  final err = _lower(
    decoded['error'] ?? decoded['error_code'] ?? decoded['code'],
  );
  return err == 'open_mollie_checkout_exists';
}

/// Whether receipt-local open-Mollie recovery state must be dropped when the
/// receipt widget is rebound to a different booking identity.
///
/// Same booking id => keep local recovery (rebuild/update must not discard a
/// still-valid owner). Different booking => clear so ride A never blocks B.
bool shouldResetOpenMollieRecoveryForBookingChange({
  required String? previousBookingId,
  required String? nextBookingId,
}) {
  final oldId = _norm(previousBookingId);
  final newId = _norm(nextBookingId);
  if (oldId.isEmpty || newId.isEmpty) return false;
  return oldId != newId;
}

/// Driver-facing recovery action chosen from the open-checkout dialog.
enum MollieOpenPaymentRecoveryChoice {
  refresh,
  resume,
  cancel,
  dismiss,
}

/// Parsed `recovery` block from `open_mollie_checkout_exists` / recovery API.
class MollieOpenPaymentRecoveryInfo {
  const MollieOpenPaymentRecoveryInfo({
    required this.presentationState,
    required this.resumable,
    required this.cancelAllowed,
    required this.fallbackAllowed,
    required this.actions,
    this.checkoutUrl,
    this.paymentBookingId,
    this.molliePaymentId,
  });

  final String presentationState;
  final bool resumable;
  final bool cancelAllowed;
  final bool fallbackAllowed;
  final List<String> actions;
  final String? checkoutUrl;
  final String? paymentBookingId;
  final String? molliePaymentId;

  bool get isPendingOwner {
    if (fallbackAllowed) return false;
    // presentationState is normalized lowercase by parseMollieOpenPaymentRecovery.
    switch (presentationState) {
      case 'pending':
      case 'checking':
      case 'refreshing':
      case 'canceling':
      case 'cancelling':
      case 'recoveryerror':
      case 'recovery_error':
        return true;
      default:
        return false;
    }
  }
}

/// Parses open-checkout recovery UI state from a server response.
///
/// [httpCode] must be the actual HTTP status. Recovery activates only when
/// the payload (or a 409 conflict) carries authoritative open-checkout
/// evidence — never from generic Mollie failures.
MollieOpenPaymentRecoveryInfo? parseMollieOpenPaymentRecovery(
  Map<String, dynamic>? decoded, {
  int? httpCode,
}) {
  if (decoded == null) return null;
  final recovery = _asMap(decoded['recovery']);
  final open = _asMap(decoded['open_checkout'] ?? decoded['openCheckout']);
  final hasPayload = recovery != null || open != null;
  final conflictBlocked = httpCode != null &&
      manualPaymentBlockedByOpenMollieCheckout(
        httpCode: httpCode,
        decoded: decoded,
      );
  // Payload-only path: Tap-to-Pay / street-checkout may return non-409 HTTP
  // with a full open_checkout+recovery body (canonical evidence).
  if (!hasPayload && !conflictBlocked) {
    return null;
  }
  final actionsRaw = recovery?['actions'];
  final actions = <String>[];
  if (actionsRaw is List) {
    for (final a in actionsRaw) {
      final t = _norm(a);
      if (t.isNotEmpty) actions.add(t);
    }
  }
  final checkoutUrl = _firstNonEmpty(open ?? const {}, [
        'checkout_url',
        'checkoutUrl',
        'payment_url',
        'paymentUrl',
      ]) ??
      _firstNonEmpty(decoded, ['checkout_url', 'checkoutUrl']);
  final resumable = recovery != null
      ? _asBool(recovery['resumable'])
      : (checkoutUrl != null && checkoutUrl.isNotEmpty);
  final cancelAllowed = recovery != null
      ? _asBool(recovery['cancel_allowed'] ?? recovery['cancelAllowed'])
      : true;
  final fallbackAllowed = recovery != null
      ? _asBool(recovery['fallback_allowed'] ?? recovery['fallbackAllowed'])
      : false;
  return MollieOpenPaymentRecoveryInfo(
    presentationState: _lower(
      recovery?['presentation_state'] ??
          recovery?['presentationState'] ??
          decoded['presentation_state'] ??
          'pending',
    ),
    resumable: resumable,
    cancelAllowed: cancelAllowed,
    fallbackAllowed: fallbackAllowed,
    actions: actions.isEmpty
        ? <String>[
            'refresh_status',
            if (resumable) 'resume_checkout',
            if (cancelAllowed) 'cancel_open_checkout',
          ]
        : actions,
    checkoutUrl: checkoutUrl,
    paymentBookingId: _firstNonEmpty(open ?? const {}, [
      'payment_booking_id',
      'paymentBookingId',
    ]),
    molliePaymentId: _firstNonEmpty(open ?? const {}, [
      'mollie_payment_id',
      'molliePaymentId',
    ]),
  );
}

/// True when Fluxidi online-checkout ownership was durably abandoned by the user.
///
/// Stale `checkout_url` / `mollie.status=open` must NOT resurrect ONLINE mode.
bool receiptDetailsHaveAbandonedMollieCheckout(Map<String, dynamic>? details) {
  final map = details;
  if (map == null) return false;
  if (_asBool(map['mollie_checkout_abandoned']) ||
      _asBool(map['mollieCheckoutAbandoned'])) {
    return true;
  }
  final attempt = _lower(
    map['payment_attempt_status'] ?? map['paymentAttemptStatus'],
  );
  if (attempt == 'abandoned') return true;
  final booking = _asMap(map['booking']);
  if (booking == null) return false;
  if (_asBool(booking['mollie_checkout_abandoned']) ||
      _asBool(booking['mollieCheckoutAbandoned'])) {
    return true;
  }
  final nestedAttempt = _lower(
    booking['payment_attempt_status'] ?? booking['paymentAttemptStatus'],
  );
  return nestedAttempt == 'abandoned';
}

/// True when receipt booking details already show an open Mollie checkout owner.
bool receiptDetailsHaveOpenMollieCheckout(Map<String, dynamic>? details) {
  final map = details;
  if (map == null) return false;
  if (receiptDetailsHaveAbandonedMollieCheckout(map)) return false;
  final payStatus = _lower(
    map['payment_status'] ?? map['paymentStatus'] ?? 'unpaid',
  );
  if (payStatus == 'paid' ||
      payStatus == 'failed' ||
      payStatus == 'canceled' ||
      payStatus == 'cancelled' ||
      payStatus == 'expired' ||
      payStatus == 'abandoned') {
    return false;
  }
  final attempt = _lower(
    map['payment_attempt_status'] ?? map['paymentAttemptStatus'],
  );
  if (attempt == 'failed' ||
      attempt == 'canceled' ||
      attempt == 'cancelled' ||
      attempt == 'expired' ||
      attempt == 'abandoned') {
    return false;
  }
  final provider = _lower(
    map['payment_provider'] ??
        map['paymentProvider'] ??
        map['payment_mode'] ??
        map['paymentMode'],
  );
  if (provider != 'mollie') return false;
  final checkout = _firstNonEmpty(map, [
    'checkout_url',
    'checkoutUrl',
    'payment_url',
    'paymentUrl',
  ]);
  if (checkout == null || checkout.isEmpty) return false;
  final mollie = _asMap(map['mollie']);
  final mollieStatus = _lower(mollie?['status'] ?? payStatus);
  if (mollieStatus == 'paid' ||
      mollieStatus == 'failed' ||
      mollieStatus == 'canceled' ||
      mollieStatus == 'cancelled' ||
      mollieStatus == 'expired' ||
      mollieStatus == 'abandoned') {
    return false;
  }
  return true;
}

/// Outcome of a single `GET /pay/status` poll for an in-flight street
/// checkout.
enum MollieStreetCheckoutPollOutcome {
  /// Not final yet — keep polling.
  pending,

  /// The customer paid; the ride may be marked paid.
  paid,

  /// The Mollie payment explicitly failed.
  failed,

  /// The customer or the checkout session was cancelled.
  cancelled,

  /// The checkout session expired before payment.
  expired,

  /// Transport / decode error on this poll attempt; not authoritative, the
  /// caller should keep the ride unpaid and may retry.
  error,
}

/// Full result of one street `/pay/status` attempt (outcome + sanitized meta).
class MollieStreetCheckoutPollResult {
  const MollieStreetCheckoutPollResult({
    required this.outcome,
    this.httpCode = 0,
    this.sanitizedErrorCode,
  });

  final MollieStreetCheckoutPollOutcome outcome;
  final int httpCode;

  /// Bounded, non-PII error token suitable for UI/diagnostics
  /// (`unauthorized`, `not_found`, `server_error`, …).
  final String? sanitizedErrorCode;

  static const MollieStreetCheckoutPollResult pending =
      MollieStreetCheckoutPollResult(
        outcome: MollieStreetCheckoutPollOutcome.pending,
        httpCode: 200,
      );

  static const MollieStreetCheckoutPollResult paid =
      MollieStreetCheckoutPollResult(
        outcome: MollieStreetCheckoutPollOutcome.paid,
        httpCode: 200,
      );

  static const MollieStreetCheckoutPollResult error =
      MollieStreetCheckoutPollResult(
        outcome: MollieStreetCheckoutPollOutcome.error,
        httpCode: 0,
        sanitizedErrorCode: 'network',
      );
}

/// True when [outcome] is a final state (no more polling needed).
bool molliePollOutcomeIsTerminal(MollieStreetCheckoutPollOutcome outcome) {
  return outcome != MollieStreetCheckoutPollOutcome.pending &&
      outcome != MollieStreetCheckoutPollOutcome.error;
}

/// Sanitized error code for non-success `/pay/status` responses.
String sanitizeMollieStreetStatusErrorCode({
  required int httpCode,
  Map<String, dynamic>? root,
}) {
  if (httpCode == 0) return 'network';
  if (httpCode == 401) return 'unauthorized';
  if (httpCode == 403) return 'forbidden';
  if (httpCode == 404) return 'not_found';
  if (httpCode == 409) return 'conflict';
  if (httpCode >= 500) return 'server_error';
  if (httpCode < 200 || httpCode >= 300) return 'http_error';

  final err = _lower(
    root?['error'] ?? root?['error_code'] ?? root?['code'],
  );
  if (err.isEmpty) return 'unknown';
  // Whitelist known backend tokens only — never echo raw bodies.
  const allowed = <String>{
    'unauthorized',
    'forbidden',
    'booking_not_found',
    'missing_tenant_scope',
    'tenant_scope_conflict',
    'missing_id',
  };
  if (allowed.contains(err)) return err;
  if (err.contains('not_found')) return 'not_found';
  if (err.contains('forbidden')) return 'forbidden';
  if (err.contains('unauthorized')) return 'unauthorized';
  return 'unknown';
}

/// Classifies a single `GET /pay/status` response into a poll outcome.
///
/// SERVER-AUTHORITY: only an explicit `paid` (or a non-empty `confirmed_at`)
/// counts as paid. Every other status — including a non-2xx HTTP code, a
/// missing/undecodable body, or any open/pending/authorized status — keeps
/// the ride unpaid and, unless terminal, resumes polling.
MollieStreetCheckoutPollOutcome classifyMollieStreetCheckoutPollStatus({
  required int httpCode,
  Map<String, dynamic>? data,
}) {
  if (httpCode < 200 || httpCode >= 300) {
    return MollieStreetCheckoutPollOutcome.error;
  }
  if (data == null) return MollieStreetCheckoutPollOutcome.error;

  final mollieMap = _asMap(data['mollie']);
  final mollieStatus = _lower(mollieMap?['status']);
  final paymentStatus = _lower(data['payment_status'] ?? data['paymentStatus']);
  final confirmedAt = _norm(data['confirmed_at'] ?? data['confirmedAt']);

  if (confirmedAt.isNotEmpty ||
      mollieStatus == 'paid' ||
      paymentStatus == 'paid') {
    return MollieStreetCheckoutPollOutcome.paid;
  }
  if (mollieStatus == 'failed' || paymentStatus == 'failed') {
    return MollieStreetCheckoutPollOutcome.failed;
  }
  if (mollieStatus == 'expired' || paymentStatus == 'expired') {
    return MollieStreetCheckoutPollOutcome.expired;
  }
  if (mollieStatus == 'canceled' ||
      mollieStatus == 'cancelled' ||
      paymentStatus == 'canceled' ||
      paymentStatus == 'cancelled') {
    return MollieStreetCheckoutPollOutcome.cancelled;
  }
  return MollieStreetCheckoutPollOutcome.pending;
}

/// Builds a [MollieStreetCheckoutPollResult] from an HTTP status + body maps.
MollieStreetCheckoutPollResult buildMollieStreetCheckoutPollResult({
  required int httpCode,
  Map<String, dynamic>? root,
  Map<String, dynamic>? data,
}) {
  final outcome = classifyMollieStreetCheckoutPollStatus(
    httpCode: httpCode,
    data: data ?? root,
  );
  if (outcome == MollieStreetCheckoutPollOutcome.error ||
      httpCode < 200 ||
      httpCode >= 300) {
    return MollieStreetCheckoutPollResult(
      outcome: MollieStreetCheckoutPollOutcome.error,
      httpCode: httpCode,
      sanitizedErrorCode: sanitizeMollieStreetStatusErrorCode(
        httpCode: httpCode,
        root: root,
      ),
    );
  }
  return MollieStreetCheckoutPollResult(
    outcome: outcome,
    httpCode: httpCode,
  );
}

/// True when a local receipt that is already paid must stay paid against a
/// stale unpaid/pending projection from history or a failed refresh.
///
/// Paid is monotonic for the street Mollie receipt surface: a refresh may
/// never revert paid → unpaid.
bool shouldKeepReceiptPaidMonotonic({
  required bool currentlyPaid,
  required bool authoritativeSaysPaid,
  required bool authoritativeReadSucceeded,
}) {
  if (!currentlyPaid) return false;
  if (authoritativeSaysPaid) return true;
  if (!authoritativeReadSucceeded) return true;
  // Authoritative unpaid while local is paid: keep paid (no revert).
  return true;
}

/// MOLLIE-CUSTOMER-CANCEL-RETURN-CONVERGENCE-P0: whether a recovery refresh
/// response means hosted ownership must be released (customer cancel /
/// expired / failed / abandoned). Paid is never treated as released.
bool isAuthoritativeMollieOwnershipReleased(Map<String, dynamic>? decoded) {
  if (decoded == null) return false;
  final payStatus = _lower(
    decoded['payment_status'] ?? decoded['paymentStatus'],
  );
  final presentation = _lower(
    decoded['presentation_state'] ?? decoded['presentationState'],
  );
  if (payStatus == 'paid' || presentation == 'paid') return false;

  if (_asBool(decoded['mollie_checkout_abandoned']) ||
      _asBool(decoded['mollieCheckoutAbandoned']) ||
      _asBool(decoded['user_abandoned']) ||
      _asBool(decoded['userAbandoned'])) {
    return true;
  }
  final ownership = _lower(
    decoded['ownership_status'] ?? decoded['ownershipStatus'],
  );
  if (ownership == 'abandoned') return true;
  final attempt = _lower(
    decoded['payment_attempt_status'] ?? decoded['paymentAttemptStatus'],
  );
  if (attempt == 'abandoned') return true;

  final recovery = _asMap(decoded['recovery']);
  if (_asBool(decoded['fallback_allowed'] ?? decoded['fallbackAllowed'])) {
    return true;
  }
  if (recovery != null &&
      _asBool(recovery['fallback_allowed'] ?? recovery['fallbackAllowed'])) {
    return true;
  }
  const releasedStates = <String>{
    'canceled',
    'cancelled',
    'expired',
    'failed',
    'abandoned',
  };
  final recoveryPresentation = _lower(
    recovery?['presentation_state'] ?? recovery?['presentationState'],
  );
  if (releasedStates.contains(presentation)) return true;
  if (releasedStates.contains(recoveryPresentation)) return true;
  if (releasedStates.contains(payStatus)) return true;
  return false;
}

/// True when recovery/cancel response means Fluxidi ONLINE mode was abandoned
/// (payment-method switch), not necessarily Mollie provider canceled.
bool isMollieCheckoutUserAbandoned(Map<String, dynamic>? decoded) {
  if (decoded == null) return false;
  if (_asBool(decoded['mollie_checkout_abandoned']) ||
      _asBool(decoded['mollieCheckoutAbandoned']) ||
      _asBool(decoded['user_abandoned']) ||
      _asBool(decoded['userAbandoned'])) {
    return true;
  }
  final ownership = _lower(
    decoded['ownership_status'] ?? decoded['ownershipStatus'],
  );
  if (ownership == 'abandoned') return true;
  final attempt = _lower(
    decoded['payment_attempt_status'] ?? decoded['paymentAttemptStatus'],
  );
  return attempt == 'abandoned';
}

/// Provider terminal token to persist locally after ownership release.
String resolveMollieReleasePresentationStatus(Map<String, dynamic>? decoded) {
  if (decoded == null) return 'canceled';
  final recovery = _asMap(decoded['recovery']);
  final raw = _firstNonEmpty(decoded, [
        'presentation_state',
        'presentationState',
      ]) ??
      _firstNonEmpty(recovery ?? const {}, [
        'presentation_state',
        'presentationState',
      ]) ??
      _firstNonEmpty(decoded, ['payment_status', 'paymentStatus']);
  return normalizeMollieReleasedProviderStatus(raw);
}

/// Normalizes Mollie provider terminal status for local receipt markers.
String normalizeMollieReleasedProviderStatus(String? raw) {
  final t = _lower(raw);
  if (t == 'expired') return 'expired';
  if (t == 'failed') return 'failed';
  if (t == 'abandoned') return 'abandoned';
  if (t == 'canceled' || t == 'cancelled') return 'canceled';
  return 'canceled';
}

/// Clears stale local open-checkout ownership after authoritative provider
/// terminal release or user leave of ONLINE payment mode.
///
/// When [userAbandoned] is true, keep authentic Mollie [providerStatus]
/// (may remain `open`) and mark Fluxidi ownership as `abandoned`.
Map<String, dynamic> applyAuthoritativeMollieOwnershipReleaseToDetails(
  Map<String, dynamic>? details, {
  required String providerStatus,
  bool userAbandoned = false,
  String? ownershipStatus,
}) {
  final next = <String, dynamic>{
    if (details != null) ...details,
  };
  final providerToken = _lower(providerStatus);
  final attemptStatus = () {
    final explicit = _lower(ownershipStatus);
    if (explicit.isNotEmpty) {
      return explicit == 'canceled' ? 'cancelled' : explicit;
    }
    if (userAbandoned) return 'abandoned';
    final terminal = normalizeMollieReleasedProviderStatus(providerStatus);
    return terminal == 'canceled' ? 'cancelled' : terminal;
  }();
  final persistedMollieStatus = userAbandoned
      ? (providerToken.isEmpty ? 'open' : providerToken)
      : normalizeMollieReleasedProviderStatus(providerStatus);

  void clearOn(Map<String, dynamic> map) {
    map['checkout_url'] = null;
    map['checkoutUrl'] = null;
    map['payment_url'] = null;
    map['paymentUrl'] = null;
    map['payment_attempt_status'] = attemptStatus;
    map['paymentAttemptStatus'] = attemptStatus;
    map['payment_status'] = 'unpaid';
    map['paymentStatus'] = 'unpaid';
    map['payment_provider'] = null;
    map['paymentProvider'] = null;
    map['payment_mode'] = null;
    map['paymentMode'] = null;
    if (userAbandoned || attemptStatus == 'abandoned') {
      map['mollie_checkout_abandoned'] = true;
      map['mollieCheckoutAbandoned'] = true;
    }
    final mollie = _asMap(map['mollie']);
    if (mollie != null) {
      map['mollie'] = <String, dynamic>{
        ...mollie,
        'status': persistedMollieStatus,
      };
    } else {
      map['mollie'] = <String, dynamic>{'status': persistedMollieStatus};
    }
  }

  clearOn(next);
  final nested = _asMap(next['booking']);
  if (nested != null) {
    final booking = Map<String, dynamic>.from(nested);
    clearOn(booking);
    next['booking'] = booking;
  }
  return next;
}

/// Merge protection: abandoned ONLINE mode must not be resurrected by a stale
/// booking GET that still carries checkout_url / mollie.status=open.
///
/// Paid always wins and is merged normally.
Map<String, dynamic> mergeReceiptPaymentFieldsPreservingAbandonedCheckout({
  required Map<String, dynamic> localDetails,
  required Map<String, dynamic> incomingFields,
}) {
  final merged = <String, dynamic>{...localDetails};
  final incomingPaid = _lower(
        incomingFields['payment_status'] ?? incomingFields['paymentStatus'],
      ) ==
      'paid';
  final localAbandoned = receiptDetailsHaveAbandonedMollieCheckout(localDetails);

  for (final entry in incomingFields.entries) {
    final value = entry.value?.toString().trim();
    if (value == null || value.isEmpty || value.toLowerCase() == 'null') {
      continue;
    }
    if (localAbandoned && !incomingPaid) {
      final key = _lower(entry.key);
      if (key == 'checkout_url' ||
          key == 'checkouturl' ||
          key == 'payment_url' ||
          key == 'paymenturl') {
        continue;
      }
      if (key == 'payment_attempt_status' || key == 'paymentattemptstatus') {
        final attempt = _lower(entry.value);
        if (attempt == 'mollie_open' ||
            attempt == 'open' ||
            attempt == 'pending') {
          continue;
        }
      }
      if (key == 'payment_provider' ||
          key == 'paymentprovider' ||
          key == 'payment_mode' ||
          key == 'paymentmode') {
        if (_lower(entry.value) == 'mollie') continue;
      }
      if (key == 'mollie_checkout_abandoned' ||
          key == 'molliecheckoutabandoned') {
        // Keep local abandoned=true.
        continue;
      }
    }
    merged[entry.key] = entry.value;
  }

  if (localAbandoned && !incomingPaid) {
    merged['mollie_checkout_abandoned'] = true;
    merged['mollieCheckoutAbandoned'] = true;
    merged['payment_attempt_status'] = 'abandoned';
    merged['paymentAttemptStatus'] = 'abandoned';
    merged['checkout_url'] = null;
    merged['checkoutUrl'] = null;
    merged['payment_url'] = null;
    merged['paymentUrl'] = null;
  }
  return merged;
}

/// Whether an app-lifecycle / return-from-checkout refresh must bypass the
/// short debounce (customer may cancel in Mollie and return within seconds).
bool shouldForceImmediateMollieOwnershipRefresh(String reason) {
  final r = _lower(reason);
  return r == 'app_resume' ||
      r == 'return_from_checkout' ||
      r == 'checkout_dialog';
}

/// Decision for `POST .../mollie-checkout-recovery` with `action=resume`.
///
/// MOLLIE-HOSTED-RESUME-EXISTING-CHECKOUT-P0: resume never mints; it either
/// launches the existing checkout URL or adopts paid / released / fail-closed
/// provider truth from the recovery response.
enum MollieHostedResumeDecision {
  /// Resumable + non-empty checkout URL — caller may launch externally.
  launchCheckout,

  /// Provider says paid — no launch; paid wins.
  paid,

  /// Provider terminal (expired/failed/canceled) or ownership released.
  released,

  /// Authoritative Mollie GET unavailable — keep ownership fail-closed.
  providerUnavailable,

  /// No safe launchable URL; keep ownership / show retryable error.
  notResumable,
}

/// Parsed outcome of a hosted-checkout resume recovery call.
class MollieHostedResumeOutcome {
  const MollieHostedResumeOutcome({
    required this.decision,
    this.checkoutUrl,
    this.recovery,
    this.paymentBookingId,
    this.molliePaymentId,
  });

  final MollieHostedResumeDecision decision;
  final String? checkoutUrl;
  final MollieOpenPaymentRecoveryInfo? recovery;
  final String? paymentBookingId;
  final String? molliePaymentId;
}

/// True when [url] is a http(s) URI safe to pass to `launchUrl`.
bool isSafeMollieCheckoutLaunchUrl(String? url) {
  final text = (url ?? '').trim();
  if (text.isEmpty) return false;
  final uri = Uri.tryParse(text);
  if (uri == null || !uri.hasScheme) return false;
  return uri.scheme == 'https' || uri.scheme == 'http';
}

/// Pure decision for recovery `action=resume` (never invents a new payment).
MollieHostedResumeOutcome resolveMollieHostedResumeOutcome(
  Map<String, dynamic>? decoded, {
  int? httpCode,
}) {
  if (decoded == null) {
    return const MollieHostedResumeOutcome(
      decision: MollieHostedResumeDecision.providerUnavailable,
    );
  }

  final payStatus = _lower(
    decoded['payment_status'] ?? decoded['paymentStatus'],
  );
  final presentation = _lower(
    decoded['presentation_state'] ?? decoded['presentationState'],
  );
  final err = _lower(decoded['error'] ?? decoded['error_code'] ?? decoded['code']);

  final recovery = parseMollieOpenPaymentRecovery(
    decoded,
    httpCode: httpCode,
  );

  if (payStatus == 'paid' || presentation == 'paid') {
    return MollieHostedResumeOutcome(
      decision: MollieHostedResumeDecision.paid,
      recovery: recovery,
      paymentBookingId: _firstNonEmpty(decoded, [
        'payment_booking_id',
        'paymentBookingId',
      ]),
      molliePaymentId: _firstNonEmpty(decoded, [
        'mollie_payment_id',
        'molliePaymentId',
      ]),
    );
  }

  final released =
      recovery?.fallbackAllowed == true ||
      _asBool(decoded['fallback_allowed'] ?? decoded['fallbackAllowed']) ||
      presentation == 'canceled' ||
      presentation == 'cancelled' ||
      presentation == 'expired' ||
      presentation == 'failed' ||
      payStatus == 'canceled' ||
      payStatus == 'cancelled' ||
      payStatus == 'expired' ||
      payStatus == 'failed';
  if (released) {
    return MollieHostedResumeOutcome(
      decision: MollieHostedResumeDecision.released,
      recovery: recovery,
      paymentBookingId: recovery?.paymentBookingId ??
          _firstNonEmpty(decoded, ['payment_booking_id', 'paymentBookingId']),
      molliePaymentId: recovery?.molliePaymentId ??
          _firstNonEmpty(decoded, ['mollie_payment_id', 'molliePaymentId']),
    );
  }

  if (err == 'provider_status_unavailable' ||
      err == 'recovery_refresh_failed' ||
      presentation == 'recoveryerror') {
    return MollieHostedResumeOutcome(
      decision: MollieHostedResumeDecision.providerUnavailable,
      recovery: recovery,
      checkoutUrl: recovery?.checkoutUrl ??
          _firstNonEmpty(decoded, ['checkout_url', 'checkoutUrl']),
      paymentBookingId: recovery?.paymentBookingId ??
          _firstNonEmpty(decoded, ['payment_booking_id', 'paymentBookingId']),
      molliePaymentId: recovery?.molliePaymentId ??
          _firstNonEmpty(decoded, ['mollie_payment_id', 'molliePaymentId']),
    );
  }

  final checkoutUrl = recovery?.checkoutUrl ??
      _firstNonEmpty(decoded, [
        'checkout_url',
        'checkoutUrl',
        'payment_url',
        'paymentUrl',
      ]);
  final resumable = recovery != null
      ? recovery.resumable
      : (_asBool(decoded['resumable']) ||
          (checkoutUrl != null && checkoutUrl.isNotEmpty));
  final paymentBookingId = recovery?.paymentBookingId ??
      _firstNonEmpty(decoded, ['payment_booking_id', 'paymentBookingId']);
  final molliePaymentId = recovery?.molliePaymentId ??
      _firstNonEmpty(decoded, ['mollie_payment_id', 'molliePaymentId']);

  if (resumable && isSafeMollieCheckoutLaunchUrl(checkoutUrl)) {
    // Prefer a pending-owner recovery snapshot so the receipt keeps blocking
    // fallbacks after a successful resume launch.
    final pendingRecovery = recovery ??
        MollieOpenPaymentRecoveryInfo(
          presentationState: presentation.isEmpty ? 'pending' : presentation,
          resumable: true,
          cancelAllowed: true,
          fallbackAllowed: false,
          actions: const ['refresh_status', 'resume_checkout', 'cancel_open_checkout'],
          checkoutUrl: checkoutUrl,
          paymentBookingId: paymentBookingId,
          molliePaymentId: molliePaymentId,
        );
    return MollieHostedResumeOutcome(
      decision: MollieHostedResumeDecision.launchCheckout,
      checkoutUrl: checkoutUrl!.trim(),
      recovery: pendingRecovery,
      paymentBookingId: paymentBookingId,
      molliePaymentId: molliePaymentId,
    );
  }

  return MollieHostedResumeOutcome(
    decision: MollieHostedResumeDecision.notResumable,
    recovery: recovery,
    checkoutUrl: checkoutUrl,
    paymentBookingId: paymentBookingId,
    molliePaymentId: molliePaymentId,
  );
}
