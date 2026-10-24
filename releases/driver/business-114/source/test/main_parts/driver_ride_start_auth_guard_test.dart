// SECURITY-REMOVE-CLIENT-ADMIN-TOKEN-P0-1 (Field Failure Fix, Commit 2)
//
// Pure tests for the driver-lifecycle START auth guard and the direct-trip
// start-error classifier. These are the two primitives that prevent the
// business-preview field failure re-appearing: START refuses to proceed
// without a valid driver session token, and an HTTP 401/403 during
// /trip/start-direct is classified as an authorisation failure that must
// tear down the ride rather than as a transient transport error that keeps
// a local-only ghost ride running.
//
// Run:
//   flutter test test/main_parts/driver_ride_start_auth_guard_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/main_parts/driver_ride_start_auth_guard.dart';

void main() {
  group('evaluateDriverRideStartAuth', () {
    final now = DateTime.parse('2026-07-25T12:00:00.000Z');

    test('null token blocks with missing_token', () {
      final d = evaluateDriverRideStartAuth(
        driverSessionToken: null,
        driverSessionExpiresAtUtc: null,
        now: now,
      );
      expect(d.allow, isFalse);
      expect(d.isBlocked, isTrue);
      expect(d.reason, 'missing_token');
    });

    test('empty-string token blocks with missing_token', () {
      final d = evaluateDriverRideStartAuth(
        driverSessionToken: '',
        driverSessionExpiresAtUtc: null,
        now: now,
      );
      expect(d.allow, isFalse);
      expect(d.reason, 'missing_token');
    });

    test('whitespace-only token blocks with missing_token', () {
      final d = evaluateDriverRideStartAuth(
        driverSessionToken: '   \t\n',
        driverSessionExpiresAtUtc: null,
        now: now,
      );
      expect(d.allow, isFalse);
      expect(d.reason, 'missing_token');
    });

    test('token present + no expiry known → allow', () {
      final d = evaluateDriverRideStartAuth(
        driverSessionToken: 'dst_abc',
        driverSessionExpiresAtUtc: null,
        now: now,
      );
      expect(d.allow, isTrue);
      expect(d.isAllowed, isTrue);
      expect(d.reason, 'ok');
    });

    test('token present + empty expiry string → allow (unknown expiry)', () {
      final d = evaluateDriverRideStartAuth(
        driverSessionToken: 'dst_abc',
        driverSessionExpiresAtUtc: '  ',
        now: now,
      );
      expect(d.allow, isTrue);
      expect(d.reason, 'ok');
    });

    test('token present + malformed expiry → allow (parse failure is not a block)', () {
      final d = evaluateDriverRideStartAuth(
        driverSessionToken: 'dst_abc',
        driverSessionExpiresAtUtc: 'not-a-real-date',
        now: now,
      );
      expect(d.allow, isTrue);
      expect(d.reason, 'ok');
    });

    test('token present + expiry in the future → allow', () {
      final d = evaluateDriverRideStartAuth(
        driverSessionToken: 'dst_op_abc',
        driverSessionExpiresAtUtc: '2026-07-25T13:00:00.000Z',
        now: now,
      );
      expect(d.allow, isTrue);
      expect(d.reason, 'ok');
    });

    test('token present + expiry in the past → expired_token', () {
      final d = evaluateDriverRideStartAuth(
        driverSessionToken: 'dst_op_abc',
        driverSessionExpiresAtUtc: '2026-07-25T11:59:59.000Z',
        now: now,
      );
      expect(d.allow, isFalse);
      expect(d.reason, 'expired_token');
    });

    test('token present + expiry equal to now → expired_token (boundary is closed)', () {
      final d = evaluateDriverRideStartAuth(
        driverSessionToken: 'dst_op_abc',
        driverSessionExpiresAtUtc: '2026-07-25T12:00:00.000Z',
        now: now,
      );
      expect(d.allow, isFalse);
      expect(d.reason, 'expired_token');
    });

    test('token present + expiry with local offset (Z-less) parses and compares in UTC', () {
      // `DateTime.tryParse('2026-07-25T13:00:00')` treats as local; the guard
      // converts to UTC before comparing so results are stable regardless of
      // the runner's local timezone.
      final d = evaluateDriverRideStartAuth(
        driverSessionToken: 'dst_op_abc',
        driverSessionExpiresAtUtc: '2027-01-01T00:00:00',
        now: now,
      );
      expect(d.allow, isTrue);
      expect(d.reason, 'ok');
    });

    test('now defaults to system time when omitted (smoke test)', () {
      // Just verify the function does not throw when `now` is absent; content
      // of the decision cannot be pinned without injecting the clock.
      final d = evaluateDriverRideStartAuth(
        driverSessionToken: 'dst_op_abc',
        driverSessionExpiresAtUtc: null,
      );
      expect(d.allow, isTrue);
    });
  });

  group('classifyDirectTripStartError', () {
    test('Exception("HTTP 401: ...") is auth failure', () {
      final c = classifyDirectTripStartError(
        Exception('HTTP 401: {"ok":false,"error":"unauthorized"}'),
      );
      expect(c.isAuthFailure, isTrue);
      expect(c.httpStatus, 401);
      expect(c.isTransportOrOther, isFalse);
    });

    test('Exception("HTTP 403: ...") is auth failure', () {
      final c = classifyDirectTripStartError(
        Exception('HTTP 403: {"ok":false,"error":"forbidden"}'),
      );
      expect(c.isAuthFailure, isTrue);
      expect(c.httpStatus, 403);
    });

    test('Exception("HTTP 402: entitlement") is hard abort, not transport', () {
      final c = classifyDirectTripStartError(
        Exception(
          'HTTP 402: {"ok":false,"error":"subscription_entitlement_denied"}',
        ),
      );
      expect(c.isEntitlementFailure, isTrue);
      expect(c.isHardAbort, isTrue);
      expect(c.isTransportOrOther, isFalse);
      expect(c.isAuthFailure, isFalse);
      expect(c.httpStatus, 402);
      expect(
        directTripWorkerStartOutcomeFromError(
          Exception('HTTP 402: {"error":"subscription_entitlement_denied"}'),
        ),
        DirectTripWorkerStartOutcome.entitlementDenied,
      );
    });

    test('Exception("HTTP 500: ...") is NOT auth failure but exposes status', () {
      final c = classifyDirectTripStartError(
        Exception('HTTP 500: worker exploded'),
      );
      expect(c.isAuthFailure, isFalse);
      expect(c.httpStatus, 500);
      expect(c.isTransportOrOther, isTrue);
    });

    test('Exception("HTTP 502: ...") is NOT auth failure', () {
      final c = classifyDirectTripStartError(Exception('HTTP 502: bad gateway'));
      expect(c.isAuthFailure, isFalse);
      expect(c.httpStatus, 502);
    });

    test('Exception("HTTP 429: ...") is NOT auth failure (rate-limited, not unauthenticated)', () {
      final c = classifyDirectTripStartError(Exception('HTTP 429: too many'));
      expect(c.isAuthFailure, isFalse);
      expect(c.httpStatus, 429);
    });

    test('TimeoutException (transport only) is NOT auth failure', () {
      final c = classifyDirectTripStartError(
        Exception('TimeoutException: Future not completed'),
      );
      expect(c.isAuthFailure, isFalse);
      expect(c.httpStatus, isNull);
      expect(c.isTransportOrOther, isTrue);
    });

    test('SocketException-style transport error is NOT auth failure', () {
      final c = classifyDirectTripStartError(
        Exception('SocketException: Failed host lookup: booking.internal'),
      );
      expect(c.isAuthFailure, isFalse);
      expect(c.httpStatus, isNull);
    });

    test('body containing "401" without HTTP prefix is NOT auth failure', () {
      // Prevents mis-classifying a well-formed JSON body like
      // `{"ok":true,"trip_id":"trip_4013"}` (contains "401" as a substring).
      final c = classifyDirectTripStartError(
        Exception('Invalid direct trip start response: {"trip_id":"trip_4013"}'),
      );
      expect(c.isAuthFailure, isFalse);
      expect(c.httpStatus, isNull);
    });

    test('malformed status digits after HTTP → NOT auth failure', () {
      final c = classifyDirectTripStartError(
        Exception('HTTP 40x: unrecognised'),
      );
      expect(c.isAuthFailure, isFalse);
      expect(c.httpStatus, isNull);
    });

    test('non-Exception object is tolerated (isTransportOrOther)', () {
      final c = classifyDirectTripStartError('random string thrown');
      expect(c.isAuthFailure, isFalse);
      expect(c.httpStatus, isNull);
    });
  });
}
