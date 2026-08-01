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
  return MollieStreetCheckoutErrorKind.unknown;
}

/// True when a manual in-car payment (cash / Bancontact terminal / QR
/// confirm) was rejected because an online Mollie checkout is already open
/// for this ride, and the backend requires an explicit confirmation before
/// it will cancel the open checkout and accept the manual payment.
bool manualPaymentBlockedByOpenMollieCheckout({
  required int httpCode,
  Map<String, dynamic>? decoded,
}) {
  if (httpCode != 409) return false;
  if (decoded == null) return true;
  if (_asBool(decoded['requires_confirm_cancel_mollie']) ||
      _asBool(decoded['confirm_cancel_required']) ||
      _asBool(decoded['confirm_cancel_open_mollie_required'])) {
    return true;
  }
  final err = _lower(
    decoded['error'] ?? decoded['error_code'] ?? decoded['code'],
  );
  return err.contains('mollie') ||
      err.contains('open_payment') ||
      err.contains('open_checkout') ||
      err.isEmpty;
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
