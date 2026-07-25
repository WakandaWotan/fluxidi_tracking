// SECURITY-REMOVE-CLIENT-ADMIN-TOKEN-P0-1 (Field Failure Fix, Commit 2)
//
// Source-contract test that pins the wiring of the driver-lifecycle START
// auth guard and the /trip/start-direct auth-failure abort. Pumping the full
// driver home widget in a Flutter widget test is impractical here (the state
// class has ~30k lines and depends on Mapbox / geolocation / http), so this
// test proves the same invariant by inspecting the source of
// `driver_home_page_state.dart` for the required call sites and log lines.
//
// This test is a companion to the pure-logic tests in
// `driver_ride_start_auth_guard_test.dart`. Together they prove:
//
//   1. The guard decision itself is correct (pure tests).
//   2. Every driver-lifecycle START entry point runs the guard before any
//      state mutation (this file).
//   3. The direct-trip start error is classified and 401/403 dispatches into
//      the deterministic abort path (this file).
//
// If future refactors move any of these call sites this test will fail with
// a clear pointer to the missing invariant.
//
// Run:
//   flutter test test/main_parts/driver_ride_start_auth_guard_wiring_test.dart

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _relativePath = 'lib/main_parts/driver_home_page_state.dart';

String _readSourceOrFail() {
  final file = File(_relativePath);
  if (!file.existsSync()) {
    fail('Source file not found: $_relativePath');
  }
  return file.readAsStringSync();
}

/// Extracts the body of a top-level class-member method (declared at
/// two-space class-member indentation) starting at `signaturePrefix`. Uses a
/// naive brace counter that ignores braces inside single-line string
/// literals; sufficient for the anchoring assertions in this file.
///
/// The helper handles multi-line parameter lists ending in `) async {`,
/// `) {`, or `}) async {`, etc., by locating the *opening* body brace as the
/// first `{` after the last `)` on the signature line(s), then counting to
/// the matching `}`.
String _extractMethodBody(String source, String signaturePrefix) {
  final startIdx = source.indexOf(signaturePrefix);
  if (startIdx < 0) {
    fail(
      'Could not locate signature "$signaturePrefix" in $_relativePath — '
      'the SECURITY-REMOVE-CLIENT-ADMIN-TOKEN-P0-1 wiring may have been '
      'removed or renamed. Restore the guard call site.',
    );
  }
  // Locate the *body*-opening `{`, which always comes after the final `)`
  // of the signature (possibly with `async` in between). Named-parameter
  // braces `{required int? x}` occur BEFORE that `)` and must be skipped.
  final bodyOpenPattern = RegExp(r'\)\s*(?:async\s*)?\{');
  final bodyOpenMatch = bodyOpenPattern.firstMatch(source.substring(startIdx));
  if (bodyOpenMatch == null) {
    fail('Could not find body-opening brace after "$signaturePrefix"');
  }
  final openIdx = startIdx + bodyOpenMatch.end - 1;
  var depth = 0;
  var inString = false;
  var stringQuote = '';
  for (var k = openIdx; k < source.length; k++) {
    final ch = source[k];
    final prev = k > 0 ? source[k - 1] : '';
    if (inString) {
      if (ch == stringQuote && prev != '\\') inString = false;
      continue;
    }
    if (ch == "'" || ch == '"') {
      inString = true;
      stringQuote = ch;
      continue;
    }
    if (ch == '{') depth += 1;
    if (ch == '}') {
      depth -= 1;
      if (depth == 0) return source.substring(startIdx, k + 1);
    }
  }
  fail('Could not find matching close brace for "$signaturePrefix"');
}

void main() {
  group('driver-lifecycle START auth-guard wiring', () {
    late String src;

    setUpAll(() {
      src = _readSourceOrFail();
    });

    test('_startDirectRide calls _driverRideStartAuthAllowsOrRefuse before state mutation', () {
      final body = _extractMethodBody(src, '  Future<void> _startDirectRide() async {');
      // The guard call must appear.
      expect(
        body,
        contains("_driverRideStartAuthAllowsOrRefuse(action: 'start_direct_ride')"),
        reason:
            '_startDirectRide must gate on the driver-session guard before '
            'touching meter/tracking/nav state.',
      );
      // And it must appear BEFORE the first setState / _hardClearAtRideBoundary /
      // wakelock activation. Otherwise state can be mutated on the blocked
      // path (which caused the field failure).
      final guardIdx = body.indexOf('_driverRideStartAuthAllowsOrRefuse');
      final firstSetStateIdx = body.indexOf('setState(');
      final firstHardClearIdx = body.indexOf('_hardClearAtRideBoundary');
      final firstWakelockIdx = body.indexOf('_setNavigationWakelock(true)');
      final firstMutation = [
        firstSetStateIdx,
        firstHardClearIdx,
        firstWakelockIdx,
      ].where((i) => i >= 0).fold<int>(1 << 30, (a, b) => a < b ? a : b);
      expect(
        guardIdx,
        lessThan(firstMutation),
        reason:
            '_startDirectRide must run the auth guard before any state mutation '
            '(setState / _hardClearAtRideBoundary / _setNavigationWakelock).',
      );
    });

    test('_startTrip calls _driverRideStartAuthAllowsOrRefuse before ownership guard and setState', () {
      final body = _extractMethodBody(src, '  Future<void> _startTrip(BookingItem b) async {');
      expect(
        body,
        contains("_driverRideStartAuthAllowsOrRefuse(action: 'start_trip')"),
        reason:
            '_startTrip must gate on the driver-session guard before /trip/start.',
      );
      final guardIdx = body.indexOf('_driverRideStartAuthAllowsOrRefuse');
      final ownershipGuardIdx = body.indexOf('_canOperateBookingWithGuard');
      final firstSetStateIdx = body.indexOf('setState(');
      expect(guardIdx, greaterThanOrEqualTo(0));
      expect(ownershipGuardIdx, greaterThan(guardIdx));
      expect(firstSetStateIdx, greaterThan(guardIdx));
    });

    test('_handleCockpitStart calls _driverRideStartAuthAllowsOrRefuse before dispatch', () {
      final body = _extractMethodBody(src, '  void _handleCockpitStart() {');
      expect(
        body,
        contains("_driverRideStartAuthAllowsOrRefuse(action: 'cockpit_start')"),
        reason:
            'The cockpit START button must run the auth guard before '
            'dispatching to _startTrip or _startDirectRide.',
      );
      final guardIdx = body.indexOf('_driverRideStartAuthAllowsOrRefuse');
      final startTripIdx = body.indexOf('_startTrip(');
      final startDirectIdx = body.indexOf('_startDirectRide(');
      expect(guardIdx, greaterThanOrEqualTo(0));
      expect(startTripIdx, greaterThan(guardIdx));
      expect(startDirectIdx, greaterThan(guardIdx));
    });
  });

  group('/trip/start-direct auth-failure abort wiring', () {
    late String src;

    setUpAll(() {
      src = _readSourceOrFail();
    });

    test('_startDirectTripSessionOnWorker catch dispatches through classifyDirectTripStartError', () {
      final body = _extractMethodBody(
        src,
        '  Future<void> _startDirectTripSessionOnWorker({',
      );
      expect(
        body,
        contains('classifyDirectTripStartError'),
        reason:
            'The direct-trip start catch must classify errors so HTTP 401/403 '
            'branches into deterministic teardown instead of the "local-only" '
            'silent-success path.',
      );
      expect(
        body,
        contains('_abortDirectRideAfterAuthFailure'),
        reason: 'Auth-failure branch must call the abort helper.',
      );
      expect(
        body,
        contains('[DIRECT_TRIP][START][ABORT]'),
        reason:
            'The abort branch must emit a stable diagnostic so field logs can '
            'distinguish auth-abort from transport-fallback outcomes.',
      );
    });

    test('_abortDirectRideAfterAuthFailure exists and tears down critical state', () {
      final body = _extractMethodBody(
        src,
        '  void _abortDirectRideAfterAuthFailure({required int? httpStatus}) {',
      );
      // Meter, tracking, wakelock, deterministic route/nav teardown, snackbar.
      //
      // NOTE (SECURITY-REMOVE-CLIENT-ADMIN-TOKEN-P0-1 Commit 4): the earlier
      // Commit 2 contract required the specific helper name
      // `_clearActiveRouteAndNavigationState(clearActiveSelection: true)`.
      // Commit 4 replaces that helper — which suffered from an early-return
      // when route geometry was already empty — with the stronger
      // `_deterministicStopTeardown(outcome: authFailure)` funnel. The
      // invariant is preserved and strengthened: state is torn down
      // unconditionally, every live-ride timer is explicitly cancelled, and
      // route/pin cleanup runs independent of prior geometry. The invariants
      // enforced here still hold. Additional Commit 4 invariants are
      // enforced by `direct_trip_stop_teardown_always_exits_nav_test.dart`.
      for (final marker in const [
        '_stopMeterTicker(',
        '_stopTrackingInternal(',
        '_setNavigationWakelock(false',
        '_deterministicStopTeardown(',
        'StopTeardownOutcome.authFailure',
        '_showDriverSessionRequiredSnackbar(',
      ]) {
        expect(
          body,
          contains(marker),
          reason:
              '_abortDirectRideAfterAuthFailure must include $marker to '
              'guarantee deterministic teardown after HTTP 401/403.',
        );
      }
      // MUST NOT write compliance-ledger rows or persist local-only history
      // in this path — no ride actually happened.
      expect(
        body,
        isNot(contains('_writeComplianceLedgerRecord(')),
        reason:
            'Auth-failure abort must NOT write compliance-ledger rows — no '
            'ride occurred, so there is nothing to record.',
      );
      expect(
        body,
        isNot(contains('_persistLocalOnlyDirectHistoryFallback(')),
        reason:
            'Auth-failure abort must NOT persist a local-only history record.',
      );
    });
  });

  group('no ADMIN_TOKEN restored', () {
    late String src;

    setUpAll(() {
      src = _readSourceOrFail();
    });

    test('no admin: true / kAdminToken / x-admin-token restored in this file', () {
      // Defensive: ensures the fix does not accidentally re-introduce the
      // P0-1 shortcut. Comments and diagnostic labels are stripped so a
      // reference to the security ticket in a doc-comment does not trip
      // the guard.
      final withoutLineComments = src
          .split('\n')
          .map((line) {
            final commentIdx = line.indexOf('//');
            if (commentIdx < 0) return line;
            return line.substring(0, commentIdx);
          })
          .join('\n');
      for (final forbidden in const [
        'admin: true',
        'kAdminToken',
        "'x-admin-token'",
        '"x-admin-token"',
        "'X-Admin-Token'",
        '"X-Admin-Token"',
      ]) {
        expect(
          withoutLineComments.contains(forbidden),
          isFalse,
          reason:
              'driver_home_page_state.dart must not restore ADMIN_TOKEN '
              'plumbing; found "$forbidden".',
        );
      }
    });
  });
}
