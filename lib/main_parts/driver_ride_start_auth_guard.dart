/// SECURITY-REMOVE-CLIENT-ADMIN-TOKEN-P0-1 (Field Failure Fix, Commit 2)
///
/// Pure predicates for the driver-lifecycle START auth guard and the
/// direct-trip start-error classifier. Kept dependency-free so the fail-closed
/// contract can be unit-tested without pumping the driver home widget
/// (which needs Mapbox / geolocation / http).
///
/// Product contract enforced here:
///   - START of any driver-lifecycle action (planned trip start, direct/
///     street ride start) requires a non-empty `driverSessionToken`.
///   - If the token is absent or the session is expired, the UI must refuse
///     the action client-side and never send an unauthenticated request that
///     would (deterministically) 401 on the tracking worker and silently
///     leave a local-only ghost ride in history.
///   - An HTTP 401 or 403 returned from `/trip/start-direct` after the guard
///     has passed (e.g. because the token expired mid-flight or was revoked)
///     is treated as an authorisation failure that must tear down the ride —
///     never as a transient transport error that keeps the meter running.
library;

import 'package:fluxidi_tracking/company/subscription_entitlement_ux.dart';

/// Outcome of the pre-flight START auth guard.
class DriverRideStartAuthDecision {
  const DriverRideStartAuthDecision({
    required this.allow,
    required this.reason,
  });

  /// Whether the driver-lifecycle action may proceed.
  final bool allow;

  /// Machine-readable reason token. Stable and safe to log.
  /// Values: `ok`, `missing_session`, `missing_token`, `expired_token`.
  final String reason;

  bool get isAllowed => allow;

  bool get isBlocked => !allow;
}

/// Pure predicate. `now` is injectable so tests can pin the reference clock.
///
/// Returns `allow: true, reason: 'ok'` when both:
///   - `driverSessionToken` is present after trimming,
///   - `driverSessionExpiresAtUtc` is either absent (no expiry known) or
///     parses to an instant strictly after `now`.
///
/// Otherwise returns a blocking decision with a stable `reason` token.
DriverRideStartAuthDecision evaluateDriverRideStartAuth({
  required String? driverSessionToken,
  required String? driverSessionExpiresAtUtc,
  DateTime? now,
}) {
  final token = (driverSessionToken ?? '').trim();
  if (token.isEmpty) {
    return const DriverRideStartAuthDecision(
      allow: false,
      reason: 'missing_token',
    );
  }
  final expiryRaw = (driverSessionExpiresAtUtc ?? '').trim();
  if (expiryRaw.isNotEmpty) {
    final parsed = DateTime.tryParse(expiryRaw);
    if (parsed != null) {
      final effectiveNow = (now ?? DateTime.now()).toUtc();
      if (parsed.toUtc().isBefore(effectiveNow) ||
          parsed.toUtc().isAtSameMomentAs(effectiveNow)) {
        return const DriverRideStartAuthDecision(
          allow: false,
          reason: 'expired_token',
        );
      }
    }
  }
  return const DriverRideStartAuthDecision(allow: true, reason: 'ok');
}

/// Classification of an error thrown by `_startDirectTripSessionOnWorker`.
///
/// The tracking worker returns `401 unauthorized` when no bearer is present
/// or the driver session is invalid, and `403 forbidden` when the caller-
/// supplied scope conflicts with the session-derived scope. Both cases mean
/// the ride must be torn down client-side.
///
/// COMMERCIAL-ENTITLEMENT-FLUTTER-P0: HTTP 402 / entitlement deny tokens are
/// a hard operational abort — never local-only ghost rides.
///
/// Any other status (or a raw transport error such as timeout/connection-
/// refused/DNS) is a transient failure — the client may keep a local-only
/// ride and later render it as `backend_confirmed=false`.
class DirectTripStartErrorClassification {
  const DirectTripStartErrorClassification({
    required this.isAuthFailure,
    this.isEntitlementFailure = false,
    this.httpStatus,
  });

  /// `true` when the error indicates HTTP 401 or 403.
  final bool isAuthFailure;

  /// `true` when the error is an authoritative subscription entitlement deny.
  final bool isEntitlementFailure;

  /// Parsed HTTP status when the error string exposed one; `null` otherwise
  /// (e.g. transport-only errors, parse errors on the response body).
  final int? httpStatus;

  bool get isHardAbort => isAuthFailure || isEntitlementFailure;

  bool get isTransportOrOther => !isHardAbort;
}

/// Parses an error thrown from the direct-trip start path into an auth /
/// entitlement / transport classification. The parser is tolerant of the two
/// shapes used by the current caller (see `_startDirectTripSessionOnWorker`):
///
///   1. `Exception('HTTP 401: {...}')` — the `res.statusCode != 200` throw.
///   2. Any other thrown object (transport, timeout, JSON parse, etc.).
///
/// The regex explicitly requires `HTTP ` followed by the status so we never
/// mis-classify a body that happens to contain "401" or "403" as an auth
/// failure. The status is captured for auditability but never logged with
/// the bearer or response body.
DirectTripStartErrorClassification classifyDirectTripStartError(Object error) {
  final text = error.toString();
  final match = RegExp(r'HTTP\s+(\d{3})').firstMatch(text);
  final status =
      match == null ? null : int.tryParse(match.group(1) ?? '');
  final entitlement = classifySubscriptionEntitlementDeny(
    httpStatus: status,
    errorBody: text,
  );
  if (entitlement.isCompanyOperationalDeny) {
    return DirectTripStartErrorClassification(
      isAuthFailure: false,
      isEntitlementFailure: true,
      httpStatus: status ?? entitlement.httpStatus,
    );
  }
  if (status == null) {
    return const DirectTripStartErrorClassification(isAuthFailure: false);
  }
  final isAuth = status == 401 || status == 403;
  return DirectTripStartErrorClassification(
    isAuthFailure: isAuth,
    httpStatus: status,
  );
}

/// Result of awaiting `/trip/start-direct` before local street activation.
enum DirectTripWorkerStartOutcome {
  /// Worker accepted the start (or returned a linked/reused booking).
  ok,

  /// Authoritative entitlement deny — must not create local ride state.
  entitlementDenied,

  /// Auth failure (401/403).
  authDenied,

  /// Transport / other — caller may choose local-only only when already live.
  transportOrOther,
}

/// Structured preflight result so callers can activate local state after OK.
class DirectTripWorkerStartResult {
  const DirectTripWorkerStartResult({
    required this.outcome,
    this.tripId = '',
    this.bookingId,
  });

  final DirectTripWorkerStartOutcome outcome;
  final String tripId;
  final String? bookingId;

  bool get isOk => outcome == DirectTripWorkerStartOutcome.ok;
  bool get isEntitlementDenied =>
      outcome == DirectTripWorkerStartOutcome.entitlementDenied;
  bool get isAuthDenied => outcome == DirectTripWorkerStartOutcome.authDenied;
}

DirectTripWorkerStartOutcome directTripWorkerStartOutcomeFromError(
  Object error,
) {
  final c = classifyDirectTripStartError(error);
  if (c.isEntitlementFailure) {
    return DirectTripWorkerStartOutcome.entitlementDenied;
  }
  if (c.isAuthFailure) return DirectTripWorkerStartOutcome.authDenied;
  return DirectTripWorkerStartOutcome.transportOrOther;
}
