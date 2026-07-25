// SECURITY-REMOVE-CLIENT-ADMIN-TOKEN-P0-1 (Field Failure Fix, Commit 4)
//
// Tests for the deterministic STOP / navigation teardown.
//
// Live-navigation is not a separate route — it is `DriverHomePage` rendered
// in `_liveRideActive` mode. Exiting therefore means state reset, never
// Navigator.pop / Navigator.popUntil / Navigator.maybePop. The teardown is
// idempotent and cancels every live-ride timer/callback explicitly so a
// duplicate STOP (or a teardown call on already-cleared state) still
// converges.
//
// This file has three parts:
//
//   Part A. Pure-plan tests on `planDriverStopTeardown` — exhaustive over
//           `StopTeardownOutcome` and drawer/hub visibility.
//   Part B. `computeLiveRideActiveForRendering` unit tests — proves the
//           state reset causes the widget to rebuild into normal
//           (non-live) rendering.
//   Part C. Source-contract tests on
//           `lib/main_parts/driver_home_page_state.dart` — pins the wiring
//           into `_stopTrip`, its early-return guards, and
//           `_abortDirectRideAfterAuthFailure`; asserts the "no Navigator"
//           invariant, the unconditional timer-cancel invariant, and the
//           no-`ADMIN_TOKEN` invariant.
//
// Pumping the full `DriverHomePage` widget is impractical (the state class
// has >30k lines and depends on Mapbox / geolocation / http), so the wiring
// invariants are proved by inspecting the source file. This is the same
// pattern used by Commit 2's `driver_ride_start_auth_guard_wiring_test.dart`
// and Commit 3's `business_preview_operator_mint_test.dart`.
//
// Run:
//   flutter test test/main_parts/direct_trip_stop_teardown_always_exits_nav_test.dart

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/main_parts/driver_stop_teardown_plan.dart';

const _driverHomeStatePath = 'lib/main_parts/driver_home_page_state.dart';

/// Returns the index of the first line-comment `//` outside a string literal
/// on the given line, or -1 if no comment is present.
int _findLineCommentStart(String line) {
  var inString = false;
  var stringQuote = '';
  for (var i = 0; i < line.length - 1; i++) {
    final ch = line[i];
    final prev = i > 0 ? line[i - 1] : '';
    if (inString) {
      if (ch == stringQuote && prev != r'\\') inString = false;
      continue;
    }
    if (ch == "'" || ch == '"') {
      inString = true;
      stringQuote = ch;
      continue;
    }
    if (ch == '/' && line[i + 1] == '/') return i;
  }
  return -1;
}

String readSourceOrFail() {
  final file = File(_driverHomeStatePath);
  if (!file.existsSync()) {
    fail('Source file not found: $_driverHomeStatePath');
  }
  return file.readAsStringSync();
}

/// Extracts the body of a top-level class-member method (declared at
/// two-space class-member indentation) starting at [signaturePrefix]. Uses a
/// brace counter that ignores braces inside single-line string literals;
/// sufficient for the anchoring assertions in this file.
///
/// The helper handles multi-line parameter lists ending in `) async {`,
/// `) {`, or `}) async {`, etc., by locating the body-opening brace as the
/// first `{` after the final `)` on the signature line(s), then counting
/// to the matching `}`.
String extractMethodBody(String source, String signaturePrefix) {
  final startIdx = source.indexOf(signaturePrefix);
  if (startIdx < 0) {
    fail(
      'Could not locate signature "$signaturePrefix" in $_driverHomeStatePath '
      '— the Commit 4 wiring may have been removed or renamed. Restore the '
      'STOP teardown call site.',
    );
  }
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
  // =========================================================================
  // Part A. Pure-plan tests on `planDriverStopTeardown`.
  // =========================================================================

  group('planDriverStopTeardown — always-on cleanup invariants', () {
    for (final outcome in StopTeardownOutcome.values) {
      test('all always-on fields are true for outcome=${outcome.name}', () {
        final plan = planDriverStopTeardown(DriverStopTeardownContext(
          outcome: outcome,
          isMounted: true,
          bookingsHubVisible: false,
          drawerOpen: false,
          preservePendingDirectIdentity: false,
        ));
        expect(plan.outcome, outcome);
        expect(plan.stopMeterTicker, isTrue);
        expect(plan.stopTracking, isTrue);
        expect(plan.releaseWakelock, isTrue);
        expect(plan.disableNativeFollow, isTrue);
        expect(plan.cancelMarkerSelfHealTimer, isTrue);
        expect(plan.cancelNavRouteRetryTimer, isTrue);
        expect(plan.cancelDriver3dActivationConfirmRetryTimer, isTrue);
        expect(plan.cancelDirectRideEstimateDebounce, isTrue);
        expect(plan.cancelDirectRideEstimateLocationRetryTimer, isTrue);
        expect(plan.resetPendingFollowCamera, isTrue);
        expect(plan.stopStreetlevelFollowPump, isTrue);
        expect(plan.resetNavR3MotionState, isTrue);
        expect(plan.flushNavValidationReport, isTrue);
        expect(plan.clearOperationalRideState, isTrue);
        expect(plan.resetCameraAndFollow, isTrue);
        expect(plan.clearRouteAndPinAnnotations, isTrue);
        expect(plan.restartBookingPolling, isTrue);
      });
    }
  });

  group('planDriverStopTeardown — pending identity passthrough', () {
    test('preserve=false is passed through', () {
      final plan = planDriverStopTeardown(const DriverStopTeardownContext(
        outcome: StopTeardownOutcome.backendConfirmed,
        isMounted: true,
        bookingsHubVisible: false,
        drawerOpen: false,
        preservePendingDirectIdentity: false,
      ));
      expect(plan.preservePendingDirectIdentity, isFalse);
    });

    test('preserve=true is passed through — used only for finalize-pending', () {
      final plan = planDriverStopTeardown(const DriverStopTeardownContext(
        outcome: StopTeardownOutcome.finalizePending,
        isMounted: true,
        bookingsHubVisible: false,
        drawerOpen: false,
        preservePendingDirectIdentity: true,
      ));
      expect(plan.preservePendingDirectIdentity, isTrue);
      // Passthrough must not change any always-on field.
      expect(plan.clearOperationalRideState, isTrue);
      expect(plan.restartBookingPolling, isTrue);
      expect(plan.clearRouteAndPinAnnotations, isTrue);
    });
  });

  group('planDriverStopTeardown — drawer & hub closes require explicit state', () {
    test('drawerOpen=false → closeScaffoldDrawer=false (ownership not proven)', () {
      final plan = planDriverStopTeardown(const DriverStopTeardownContext(
        outcome: StopTeardownOutcome.backendConfirmed,
        isMounted: true,
        bookingsHubVisible: false,
        drawerOpen: false,
        preservePendingDirectIdentity: false,
      ));
      expect(plan.closeScaffoldDrawer, isFalse);
    });

    test('drawerOpen=true → closeScaffoldDrawer=true', () {
      final plan = planDriverStopTeardown(const DriverStopTeardownContext(
        outcome: StopTeardownOutcome.backendConfirmed,
        isMounted: true,
        bookingsHubVisible: false,
        drawerOpen: true,
        preservePendingDirectIdentity: false,
      ));
      expect(plan.closeScaffoldDrawer, isTrue);
    });

    test('bookingsHubVisible=false → hideBookingsHubPanel=false', () {
      final plan = planDriverStopTeardown(const DriverStopTeardownContext(
        outcome: StopTeardownOutcome.backendConfirmed,
        isMounted: true,
        bookingsHubVisible: false,
        drawerOpen: false,
        preservePendingDirectIdentity: false,
      ));
      expect(plan.hideBookingsHubPanel, isFalse);
    });

    test('bookingsHubVisible=true → hideBookingsHubPanel=true', () {
      final plan = planDriverStopTeardown(const DriverStopTeardownContext(
        outcome: StopTeardownOutcome.backendConfirmed,
        isMounted: true,
        bookingsHubVisible: true,
        drawerOpen: false,
        preservePendingDirectIdentity: false,
      ));
      expect(plan.hideBookingsHubPanel, isTrue);
    });

    test('both drawer+hub visible → both closes true', () {
      final plan = planDriverStopTeardown(const DriverStopTeardownContext(
        outcome: StopTeardownOutcome.backendConfirmed,
        isMounted: true,
        bookingsHubVisible: true,
        drawerOpen: true,
        preservePendingDirectIdentity: false,
      ));
      expect(plan.closeScaffoldDrawer, isTrue);
      expect(plan.hideBookingsHubPanel, isTrue);
    });
  });

  // =========================================================================
  // Part B. `_liveRideActive` rendering consequence.
  // =========================================================================

  group('computeLiveRideActiveForRendering — state-driven live-nav exit', () {
    test('activeTripId=null && directRideActive=false → false '
        '(post-teardown state — DriverHomePage rebuilds into normal mode)', () {
      expect(
        computeLiveRideActiveForRendering(
          activeTripId: null,
          directRideActive: false,
        ),
        isFalse,
        reason:
            'The core of the Commit 4 fix: after teardown clears both '
            'operational flags, the getter mirror resolves false and the '
            'widget rebuilds without live-navigation. No Navigator popping '
            'is required.',
      );
    });

    test('activeTripId="" is treated as absent', () {
      expect(
        computeLiveRideActiveForRendering(
          activeTripId: '',
          directRideActive: false,
        ),
        isFalse,
      );
    });

    test('activeTripId="s123" is treated as live', () {
      expect(
        computeLiveRideActiveForRendering(
          activeTripId: 's123',
          directRideActive: false,
        ),
        isTrue,
      );
    });

    test('directRideActive=true is treated as live', () {
      expect(
        computeLiveRideActiveForRendering(
          activeTripId: null,
          directRideActive: true,
        ),
        isTrue,
      );
    });
  });

  // =========================================================================
  // Part C. Source-contract tests on `driver_home_page_state.dart`.
  // =========================================================================

  group('_stopTrip wiring', () {
    late String src;
    late String stopTripBody;

    setUpAll(() {
      src = readSourceOrFail();
      stopTripBody = extractMethodBody(src, '  Future<void> _stopTrip() async {');
    });

    test('acknowledged / local-only / finalize-pending branch dispatches to _deterministicStopTeardown', () {
      expect(
        stopTripBody,
        contains('await _deterministicStopTeardown('),
        reason:
            'The terminal `_clearActiveRouteAndNavigationState` call in '
            '_stopTrip must be replaced by `_deterministicStopTeardown` so '
            'route/pin cleanup, wakelock release, camera/follow reset, '
            'native-follow disable, and booking-polling restart all run '
            'unconditionally — even when route geometry was already '
            'invalidated earlier in the same method.',
      );
      expect(
        stopTripBody,
        contains('StopTeardownOutcome.backendConfirmed'),
        reason:
            'Acknowledged branch must call teardown with '
            'outcome=backendConfirmed.',
      );
      expect(
        stopTripBody,
        contains('StopTeardownOutcome.finalizePending'),
        reason:
            'Reconcile-pending branch must call teardown with '
            'outcome=finalizePending so the reconcile identity survives.',
      );
      expect(
        stopTripBody,
        contains('StopTeardownOutcome.localOnly'),
        reason:
            'The non-direct-ride branch (planned-trip local-only fallback) '
            'must call teardown with outcome=localOnly.',
      );
      expect(
        stopTripBody,
        contains(
          'preservePendingDirectIdentity: wasDirectRide && !directFinalizeAcknowledged',
        ),
        reason:
            'Pending identity preservation must be strictly derived from '
            'wasDirectRide && !directFinalizeAcknowledged — nothing else.',
      );
    });

    test('_directStopFinalizePending guard runs teardown before returning', () {
      // Locate the specific guard block.
      final guardIdx =
          stopTripBody.indexOf('if (_directStopFinalizePending)');
      expect(guardIdx, greaterThanOrEqualTo(0));
      // The teardown call must appear AFTER the guard opens and BEFORE the
      // early `return;`.
      final tailIdx = stopTripBody.indexOf('_showStreetDirectFinalizePendingSnackbar()');
      expect(tailIdx, greaterThan(guardIdx));
      final firstDeterministicIdx = stopTripBody.indexOf(
        'await _deterministicStopTeardown(',
        guardIdx,
      );
      expect(firstDeterministicIdx, greaterThan(tailIdx));
      // Preserve the pending reconcile identity on this guard branch.
      final firstReturnIdx = stopTripBody.indexOf('return;', firstDeterministicIdx);
      expect(firstReturnIdx, greaterThan(firstDeterministicIdx));
      final guardTeardownBlock =
          stopTripBody.substring(firstDeterministicIdx, firstReturnIdx);
      expect(
        guardTeardownBlock,
        contains('StopTeardownOutcome.alreadyCleared'),
        reason:
            'Duplicate STOP tap while finalize pending must call teardown '
            'with outcome=alreadyCleared.',
      );
      expect(
        guardTeardownBlock,
        contains('preservePendingDirectIdentity: true'),
        reason: 'Pending reconcile identity must survive the guard branch.',
      );
    });

    test('trip==null && !_directRideActive early-return also runs teardown', () {
      final idx = stopTripBody.indexOf('trip == null && !_directRideActive');
      expect(
        idx,
        greaterThanOrEqualTo(0),
        reason: 'Early-return guard must still exist.',
      );
      final firstDeterministicIdx =
          stopTripBody.indexOf('await _deterministicStopTeardown(', idx);
      final firstReturnIdx = stopTripBody.indexOf('return;', idx);
      expect(firstDeterministicIdx, greaterThan(idx));
      expect(firstReturnIdx, greaterThan(firstDeterministicIdx));
      final block =
          stopTripBody.substring(firstDeterministicIdx, firstReturnIdx);
      expect(
        block,
        contains('StopTeardownOutcome.alreadyCleared'),
        reason:
            'The "nothing to stop" early-return must still force the '
            'DriverHomePage back into normal rendering by calling teardown '
            'with outcome=alreadyCleared.',
      );
      expect(
        block,
        contains('preservePendingDirectIdentity: false'),
        reason:
            'On the "no active session" guard there is no reconcile identity '
            'to preserve.',
      );
    });
  });

  group('_abortDirectRideAfterAuthFailure wiring', () {
    late String src;
    late String abortBody;

    setUpAll(() {
      src = readSourceOrFail();
      abortBody = extractMethodBody(
        src,
        '  void _abortDirectRideAfterAuthFailure({required int? httpStatus}) {',
      );
    });

    test('dispatches to _deterministicStopTeardown with outcome=authFailure', () {
      expect(
        abortBody,
        contains('_deterministicStopTeardown('),
        reason:
            'HTTP 401/403 abort must run the same deterministic teardown '
            'so the live-navigation surface is exited by state reset '
            '(not Navigator popping).',
      );
      expect(abortBody, contains('StopTeardownOutcome.authFailure'));
      expect(
        abortBody,
        contains('preservePendingDirectIdentity: false'),
        reason:
            'No ride existed on the server after 401/403 — no reconcile '
            'identity to preserve.',
      );
      expect(
        abortBody,
        contains('_showDriverSessionRequiredSnackbar'),
        reason:
            'Commit 2 snackbar must remain — Commit 4 only replaces the '
            'clear-route call.',
      );
      // The old direct call to _clearActiveRouteAndNavigationState must be
      // gone from this method — teardown is the single funnel now.
      expect(
        abortBody,
        isNot(contains('_clearActiveRouteAndNavigationState(')),
        reason:
            'The abort helper must delegate to `_deterministicStopTeardown` '
            'instead of the older narrow clear-route helper (which '
            'early-returned when route geometry was empty).',
      );
    });
  });

  group('_deterministicStopTeardown body — invariants', () {
    late String src;
    late String body;

    setUpAll(() {
      src = readSourceOrFail();
      body = extractMethodBody(
        src,
        '  Future<void> _deterministicStopTeardown({',
      );
    });

    test('never uses Navigator.pop / popUntil / maybePop — state-driven exit only', () {
      final forbiddenPatterns = <RegExp>[
        RegExp(r'Navigator\.of\([^)]*\)\.pop\('),
        RegExp(r'Navigator\.of\([^)]*\)\.popUntil\('),
        RegExp(r'Navigator\.of\([^)]*\)\.maybePop\('),
        RegExp(r'Navigator\.pop\('),
        RegExp(r'Navigator\.popUntil\('),
        RegExp(r'Navigator\.maybePop\('),
      ];
      for (final pattern in forbiddenPatterns) {
        expect(
          pattern.hasMatch(body),
          isFalse,
          reason:
              'The teardown helper must exit live-navigation by state '
              'reset (`_directRideActive=false`, `_activeTripId=null`, '
              'route/pin cleanup, `_bookingsHubVisible=false`), NEVER by '
              'popping the Navigator stack. Forbidden pattern matched: '
              '${pattern.pattern}',
        );
      }
    });

    test('never uses settings.name inspection or bounded route-pop loops', () {
      expect(
        body.contains('.settings.name'),
        isFalse,
        reason:
            'Route names may be null and popping based on `settings.name` '
            'could pop the wrong app screen. The teardown helper must not '
            'inspect route names.',
      );
      // The helper body must contain no `while (Navigator.of(...).canPop())`
      // or `for (...) { Navigator.of(...).pop(); }` loops.
      final bodyLower = body.toLowerCase();
      expect(bodyLower.contains('canpop()'), isFalse,
          reason: 'No bounded pop loop over `canPop()`.');
      expect(RegExp(r'for\s*\([^)]*canpop', caseSensitive: false).hasMatch(body),
          isFalse);
      expect(
          RegExp(r'while\s*\([^)]*canpop', caseSensitive: false).hasMatch(body),
          isFalse);
    });

    test('drawer close uses Scaffold-owned closeDrawer() — never Navigator.pop', () {
      expect(
        body,
        contains('_scaffoldKey.currentState?.closeDrawer()'),
        reason:
            'Drawer close must use Scaffold-owned `closeDrawer()` which '
            'closes only the Scaffold-registered drawer route. Never `Navigator.pop`.',
      );
    });

    test('bookings-hub close flips _bookingsHubVisible=false inside setState', () {
      expect(
        body,
        contains('_bookingsHubVisible = false'),
        reason:
            'Bookings-hub is a boolean-owned overlay; the teardown must '
            'flip `_bookingsHubVisible = false`.',
      );
      // The flip is wrapped in `setState` when mounted.
      final flipRegex = RegExp(
        r'setState\(\s*\(\)\s*\{\s*_bookingsHubVisible\s*=\s*false;\s*\}\s*\);',
      );
      expect(
        flipRegex.hasMatch(body),
        isTrue,
        reason:
            'The hub flip must occur inside `setState(() { ... })` to '
            'trigger a rebuild — never as a bare assignment.',
      );
    });

    test('unconditionally cancels every live-ride timer — never gated on _posSub', () {
      // Every explicit timer cancel below must appear literally in the body.
      const requiredCancelCalls = <String>[
        '_stopMeterTicker();',
        '_markerSelfHealTimer?.cancel();',
        '_markerSelfHealTimer = null;',
        '_navRouteRetryTimer?.cancel();',
        '_navRouteRetryTimer = null;',
        '_driver3dActivationConfirmRetryTimer?.cancel();',
        '_driver3dActivationConfirmRetryTimer = null;',
        '_directRideEstimateDebounce?.cancel();',
        '_directRideEstimateDebounce = null;',
        '_directRideEstimateLocationRetryTimer?.cancel();',
        '_directRideEstimateLocationRetryTimer = null;',
        '_resetPendingFollowCamera();',
        '_stopStreetlevelFollowPump();',
        '_resetNavR3MotionState();',
        '_resetNavValidationState(flushReport: true);',
        '_posSub?.cancel();',
        '_posSub = null;',
        '_stopBookingPolling(reason:',
        '_setNavigationWakelock(false);',
        '_nativeFollow!.disable()',
      ];
      for (final call in requiredCancelCalls) {
        expect(
          body,
          contains(call),
          reason:
              'The teardown helper must explicitly issue `$call` so live-'
              'ride timers/callbacks are cancelled even when `_posSub` is '
              'already null (e.g. duplicate STOP tap, dispose race).',
        );
      }

      // Crucial: NONE of these cancels are guarded by `if (_posSub != null)`
      // / `if (_posSub == null) return;` inside the helper body. Prove by
      // ensuring the body contains no such guard at all.
      final posSubGuardRegexes = <RegExp>[
        RegExp(r'if\s*\(\s*_posSub\s*==\s*null\s*\)'),
        RegExp(r'if\s*\(\s*_posSub\s*!=\s*null\s*\)'),
      ];
      for (final r in posSubGuardRegexes) {
        expect(
          r.hasMatch(body),
          isFalse,
          reason:
              'The teardown body must NOT gate timer cancels on `_posSub` '
              'state. Every cancel runs unconditionally so an already-'
              'stopped tracking session still tears the timer wall down '
              'fully. Matched forbidden guard: ${r.pattern}',
        );
      }
    });

    test('clears operational ride state unconditionally — including _activeBooking', () {
      // These four writes are UNCONDITIONAL — they must appear outside any
      // `if (!plan.preservePendingDirectIdentity)` block.
      const alwaysCleared = <String>[
        '_directRideActive = false;',
        '_activeTripId = null;',
        '_activeBooking = null;',
        '_cameraMode = _CameraMode.overview;',
        '_hasSwitchedToFollow = false;',
        '_followCar = false;',
        '_allowOverviewCamera = false;',
      ];
      for (final line in alwaysCleared) {
        expect(
          body,
          contains(line),
          reason:
              'Operational ride state `$line` must always be cleared. '
              '`_activeBooking = null;` in particular must run even on the '
              'finalize-pending branch — no BookingItem preservation.',
        );
      }

      // The preservation block must exist and must be gated by
      // `!plan.preservePendingDirectIdentity`.
      expect(
        body,
        contains('if (!plan.preservePendingDirectIdentity)'),
        reason:
            'Only the minimum reconcile identity is preserved when '
            'preservePendingDirectIdentity is true. Everything else is '
            'unconditional.',
      );

      // Reconcile identifiers must live INSIDE that guard.
      final guardOpen =
          body.indexOf('if (!plan.preservePendingDirectIdentity)');
      expect(guardOpen, greaterThanOrEqualTo(0));
      final guardClose = body.indexOf('}', guardOpen);
      final guardBlock = body.substring(guardOpen, guardClose);
      const reconcileFields = <String>[
        '_activeDirectTripId = null;',
        '_activeDirectBookingId = null;',
        '_directRideKey = null;',
        '_directStopFinalizePending = false;',
      ];
      for (final field in reconcileFields) {
        expect(
          guardBlock,
          contains(field),
          reason:
              'Reconcile identity `$field` must live inside the '
              '`!preservePendingDirectIdentity` guard so it survives when '
              'finalize is still pending.',
        );
      }
    });

    test('route/pin cleanup runs independent of route geometry', () {
      expect(
        body,
        contains('_hardClearAtRideBoundary('),
        reason:
            'Session/render generations must be bumped even when route '
            'geometry is already empty — this closes the race where a late '
            'style/route callback repaints stale geometry.',
      );
      expect(
        body,
        contains('await _clearRouteAndPinAnnotationsOnly()'),
        reason:
            'Mapbox annotation deletes must run unconditionally — the '
            'earlier `_clearActiveRouteAndNavigationState` early-return '
            'was the root cause of the field failure.',
      );
    });

    test('booking polling restarts unconditionally after teardown', () {
      expect(
        body,
        contains('_stopBookingPolling(reason:'),
        reason:
            'Polling must be cancelled first so we can restart from a '
            'known state.',
      );
      expect(
        body,
        contains('_startBookingPolling(reason:'),
        reason:
            'Polling MUST restart even when route geometry was already '
            'empty. The `if (!_liveRideActive)` guard around this call is '
            'satisfied because operational state was cleared above.',
      );
      // Prove the restart is guarded by `!_liveRideActive` (which is now
      // trivially true because we just cleared both source flags).
      final restartIdx = body.indexOf('_startBookingPolling(reason:');
      expect(restartIdx, greaterThanOrEqualTo(0));
      // Find the preceding `if (!_liveRideActive)` within the last 200
      // characters — the restart lives inside such a guard.
      final windowStart = restartIdx > 200 ? restartIdx - 200 : 0;
      final window = body.substring(windowStart, restartIdx);
      expect(
        window.contains('if (!_liveRideActive)'),
        isTrue,
        reason:
            'The polling restart must be gated on `!_liveRideActive` (which '
            'resolves true immediately after the state clear above).',
      );
    });

    test('re-entrancy guard protects against callback loops', () {
      expect(
        body,
        contains('if (_stopTeardownInProgress)'),
        reason: 'Re-entrancy guard must exist at the very top of the helper.',
      );
      expect(
        body,
        contains('[STOP_TEARDOWN][REENTRY]'),
        reason:
            'A re-entrancy hit must emit a diagnostic so field logs can '
            'distinguish it from a normal teardown.',
      );
      expect(
        body,
        contains('_stopTeardownInProgress = true;'),
      );
      expect(
        body,
        contains('} finally {'),
        reason:
            'The re-entrancy flag must be cleared in a `finally` block so '
            'an exception mid-teardown does not permanently lock out '
            'future STOPs.',
      );
      expect(
        body,
        contains('_stopTeardownInProgress = false;'),
      );
    });

    test('emits stable [STOP_TEARDOWN][EXIT] diagnostic at the end', () {
      expect(body, contains('[STOP_TEARDOWN][EXIT]'));
    });

    test('drawer/hub closes are gated on plan flags (owned-state only)', () {
      expect(
        body,
        contains('if (plan.closeScaffoldDrawer)'),
        reason:
            'Drawer close must only fire when the plan proved the drawer '
            'is open — never speculatively.',
      );
      expect(
        body,
        contains('if (plan.hideBookingsHubPanel)'),
        reason:
            'Bookings-hub hide must only fire when the plan proved the hub '
            'is visible — never speculatively.',
      );
    });

    test('does NOT touch receipt / history / compliance ledger state', () {
      const forbiddenWrites = <String>[
        '_bookingStatusOverrides[',
        '_deletedBookingIds.add',
        '_deletedBookingIds.remove',
        '_writeComplianceLedgerRecord',
        '_persistLocalOnlyDirectHistoryFallback',
      ];
      for (final w in forbiddenWrites) {
        expect(
          body.contains(w),
          isFalse,
          reason:
              'The teardown helper must NEVER write `$w`. Receipt / '
              'history / compliance ledger state must remain available '
              'for the next screen.',
        );
      }
    });
  });

  // =========================================================================
  // Part D. Duplicate-STOP safety, ADMIN_TOKEN non-regression, Commit 2/3
  //         invariants preserved.
  // =========================================================================

  group('duplicate STOP safety', () {
    test('helper starts with re-entrancy guard and never mutates state before it', () {
      final src = readSourceOrFail();
      final body = extractMethodBody(
        src,
        '  Future<void> _deterministicStopTeardown({',
      );
      final guardIdx = body.indexOf('if (_stopTeardownInProgress)');
      final flagSetIdx = body.indexOf('_stopTeardownInProgress = true;');
      final firstMutationCandidates = <int>[
        body.indexOf('_stopMeterTicker();'),
        body.indexOf('_posSub?.cancel();'),
        body.indexOf('_markerSelfHealTimer?.cancel();'),
        body.indexOf('setState('),
      ].where((i) => i >= 0).toList();
      expect(guardIdx, greaterThanOrEqualTo(0));
      expect(flagSetIdx, greaterThan(guardIdx));
      for (final m in firstMutationCandidates) {
        expect(
          m,
          greaterThan(flagSetIdx),
          reason:
              'Every state mutation must come AFTER the re-entrancy flag '
              'is set — otherwise a re-entrant call could observe a partly '
              'mutated state.',
        );
      }
    });
  });

  group('ADMIN_TOKEN non-regression (Commit 4)', () {
    test('no ADMIN_TOKEN / x-admin-token reintroduced in modified file (code, not comments)', () {
      final src = readSourceOrFail();
      // Strip line comments (`//...`) — the existing comments in this file
      // deliberately mention ADMIN_TOKEN to document that the code does NOT
      // use it. Those references are audit trail, not regressions.
      final codeOnly = src
          .split('\n')
          .map((line) {
            final trimmed = line.trimLeft();
            if (trimmed.startsWith('//')) return '';
            final commentIdx = _findLineCommentStart(line);
            return commentIdx < 0 ? line : line.substring(0, commentIdx);
          })
          .join('\n');
      final forbidden = <RegExp>[
        RegExp(r'\bADMIN_TOKEN\b'),
        RegExp(r"'x-admin-token'", caseSensitive: false),
        RegExp(r'"X-Admin-Token"', caseSensitive: false),
        RegExp(r"'x-admin-token'\s*:", caseSensitive: false),
      ];
      for (final r in forbidden) {
        expect(
          r.hasMatch(codeOnly),
          isFalse,
          reason:
              'Commit 4 must not reintroduce ADMIN_TOKEN in any executable '
              'line. Matched: ${r.pattern}',
        );
      }
    });
  });

  group('Commit 2 & 3 invariants remain green', () {
    late String src;

    setUpAll(() {
      src = readSourceOrFail();
    });

    test('_startDirectRide still runs the fail-closed auth guard', () {
      final body = extractMethodBody(
        src,
        '  Future<void> _startDirectRide() async {',
      );
      expect(
        body,
        contains(
          "_driverRideStartAuthAllowsOrRefuse(action: 'start_direct_ride')",
        ),
      );
    });

    test('_startTrip still runs the fail-closed auth guard', () {
      final body = extractMethodBody(
        src,
        '  Future<void> _startTrip(BookingItem b) async {',
      );
      expect(
        body,
        contains(
          "_driverRideStartAuthAllowsOrRefuse(action: 'start_trip')",
        ),
      );
    });

    test('_handleCockpitStart still runs the fail-closed auth guard', () {
      final body = extractMethodBody(
        src,
        '  void _handleCockpitStart() {',
      );
      expect(
        body,
        contains(
          "_driverRideStartAuthAllowsOrRefuse(action: 'cockpit_start')",
        ),
      );
    });

    test('_abortDirectRideAfterAuthFailure still tears down critical state (Commit 2)', () {
      final body = extractMethodBody(
        src,
        '  void _abortDirectRideAfterAuthFailure({required int? httpStatus}) {',
      );
      expect(body, contains('_stopMeterTicker();'));
      expect(body, contains('_stopTrackingInternal();'));
      expect(body, contains('_setNavigationWakelock(false);'));
      expect(body, contains('_directRideActive = false;'));
    });
  });
}
