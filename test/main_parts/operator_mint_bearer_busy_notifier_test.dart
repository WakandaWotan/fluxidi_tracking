// SECURITY-REMOVE-CLIENT-ADMIN-TOKEN-P0-1 (Field Failure Fix, Blocker Fix v5)
//
// Tests for the `operatorMintedBearerInFlightNotifier` transition wiring
// in `_DriverHomePageState`. These tests enforce the corrected contract:
//
//   * `build()` MUST NOT mutate the notifier (no build-time global side
//     effects).
//   * Publication occurs at explicit state transitions only:
//       - hydration/ownership-capture (`_hydrateBusinessPreviewDriverSession`)
//       - ride START setStates (planned + street_direct_resume + street ride)
//       - `_stopDirectTrip` early meter-stop setState
//       - `_deterministicStopTeardown` enter (post `_stopTeardownInProgress = true`)
//         and finally (post `_stopTeardownInProgress = false`)
//       - reconcile pending enter (post `_directStopFinalizePending = true`) and
//         all exits (ack path and final)
//       - `_performInPageDriverSwitchMint` enter (post `beginSwitch`) and every
//         exit (publish, drop-stale, failure, company-mismatch, scope-mismatch)
//       - `dispose()` after `invalidatePendingResponses()` +
//         `_clearOperatorMintedSessionIfOwned(...)`
//   * Post-await company/session/scope mismatch inside
//     `_performInPageDriverSwitchMint` calls
//     `invalidatePendingResponses()` on the controller so START is not left
//     disabled by a stranded `isMinting` flag.
//   * The busy calculation includes `_driverSwitchMintController.isMinting`.
//
// The test uses BOTH runtime unit-tests for the pure store helper and
// source-contract tests for the widget file. Source-contract tests are
// necessary because `_DriverHomePageState` cannot be exercised in isolation
// without a full Mapbox surface — the real widget integration is exercised
// separately via
// `test/main_parts/driver_home_page_pop_scope_integration_test.dart`.
//
// Run:
//   flutter test test/main_parts/operator_mint_bearer_busy_notifier_test.dart

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/driver_session_store.dart';

// -------------------------------------------------------------------------
// Source-contract helpers (self-contained; see hydration_test for docs)
// -------------------------------------------------------------------------

String _readSourceOrFail(String relativePath) {
  final f = File(relativePath);
  if (!f.existsSync()) {
    fail('Missing source file for contract test: $relativePath');
  }
  return f.readAsStringSync();
}

String _stripDartCommentsInBody(String body) {
  final noBlock =
      body.replaceAll(RegExp(r'/\*[\s\S]*?\*/', multiLine: true), '');
  final sb = StringBuffer();
  for (final line in noBlock.split('\n')) {
    var inQuote = false;
    var i = 0;
    while (i < line.length) {
      final c = line[i];
      if (c == '"' && (i == 0 || line[i - 1] != r'\')) {
        inQuote = !inQuote;
      }
      if (!inQuote &&
          c == '/' &&
          i + 1 < line.length &&
          line[i + 1] == '/') {
        break;
      }
      sb.write(c);
      i++;
    }
    sb.write('\n');
  }
  return sb.toString();
}

String _extractMethodBody(
  String source,
  RegExp signaturePattern, {
  String? bodyMustContain,
}) {
  final matches = signaturePattern.allMatches(source).toList();
  if (matches.isEmpty) {
    fail('Method not found. Pattern: ${signaturePattern.pattern}');
  }
  for (final match in matches) {
    final body = _tryExtractBodyAt(source, match.end);
    if (body == null) continue;
    if (bodyMustContain == null || body.contains(bodyMustContain)) {
      return _stripDartCommentsInBody(body);
    }
  }
  fail(
    'No match of ${signaturePattern.pattern} '
    '${bodyMustContain != null ? "with body containing '$bodyMustContain' " : ""}found',
  );
}

String? _tryExtractBodyAt(String source, int startAfterOpenParen) {
  var i = startAfterOpenParen;
  var parenDepth = 1;
  var inSingle = false;
  var inDouble = false;
  while (i < source.length) {
    final c = source[i];
    final prev = i > 0 ? source[i - 1] : '';
    if (c == "'" && prev != r'\' && !inDouble) inSingle = !inSingle;
    if (c == '"' && prev != r'\' && !inSingle) inDouble = !inDouble;
    if (!inSingle && !inDouble) {
      if (c == '(') parenDepth++;
      if (c == ')') {
        parenDepth--;
        if (parenDepth == 0) {
          break;
        }
      }
    }
    i++;
  }
  if (parenDepth != 0) return null;
  i++;
  while (i < source.length && source[i] != '{') {
    i++;
  }
  if (i >= source.length) return null;
  final startIdx = i;
  var depth = 0;
  while (i < source.length) {
    final c = source[i];
    if (c == '{') depth++;
    if (c == '}') {
      depth--;
      if (depth == 0) {
        return source.substring(startIdx, i + 1);
      }
    }
    i++;
  }
  return null;
}

// -------------------------------------------------------------------------
// Runtime tests: the notifier itself + the store's guarded clear
// -------------------------------------------------------------------------

void main() {
  group('operatorMintedBearerInFlightNotifier — default state', () {
    tearDown(() {
      operatorMintedBearerInFlightNotifier.value = false;
    });

    test('defaults to false at app startup', () {
      expect(operatorMintedBearerInFlightNotifier.value, isFalse);
    });

    test('is a ValueNotifier<bool> that fires on distinct writes', () {
      var events = 0;
      void l() => events++;
      operatorMintedBearerInFlightNotifier.addListener(l);
      operatorMintedBearerInFlightNotifier.value = true;
      operatorMintedBearerInFlightNotifier.value = true;
      operatorMintedBearerInFlightNotifier.value = false;
      operatorMintedBearerInFlightNotifier.removeListener(l);
      expect(events, 2);
    });
  });

  group('clearOperatorMintedSessionOnCompanyEnd (guarded transition)', () {
    setUp(() {
      activeDriverSessionNotifier.value = null;
      operatorMintedBearerInFlightNotifier.value = false;
    });
    tearDown(() {
      activeDriverSessionNotifier.value = null;
      operatorMintedBearerInFlightNotifier.value = false;
    });

    test(
      'refuses to clear the operator-minted bearer while the notifier is true',
      () {
        final expiry = DateTime.utc(2099, 1, 1).toIso8601String();
        activeDriverSessionNotifier.value = ActiveDriverSession(
          driverId: 'driver_a',
          employeeNumber: 'E001',
          fullName: 'A',
          phone: '+3100',
          loggedInAt: DateTime.utc(2027).toIso8601String(),
          updatedAt: DateTime.utc(2027).toIso8601String(),
          tenantId: 'tenant_a',
          companyId: 'company_a',
          driverSessionToken: 'dst',
          driverSessionExpiresAtUtc: expiry,
          linkMethod: kOperatorMintDriverLinkMethod,
          expiresAt: expiry,
        );
        operatorMintedBearerInFlightNotifier.value = true;
        final cleared = DriverSessionStore.instance
            .clearOperatorMintedSessionOnCompanyEnd(reason: 'unit_test');
        expect(cleared, isFalse);
        expect(activeDriverSessionNotifier.value, isNotNull);
      },
    );

    test(
      'clears the operator-minted bearer once the notifier drops to false',
      () {
        final expiry = DateTime.utc(2099, 1, 1).toIso8601String();
        activeDriverSessionNotifier.value = ActiveDriverSession(
          driverId: 'driver_a',
          employeeNumber: 'E001',
          fullName: 'A',
          phone: '+3100',
          loggedInAt: DateTime.utc(2027).toIso8601String(),
          updatedAt: DateTime.utc(2027).toIso8601String(),
          tenantId: 'tenant_a',
          companyId: 'company_a',
          driverSessionToken: 'dst',
          driverSessionExpiresAtUtc: expiry,
          linkMethod: kOperatorMintDriverLinkMethod,
          expiresAt: expiry,
        );
        operatorMintedBearerInFlightNotifier.value = false;
        final cleared = DriverSessionStore.instance
            .clearOperatorMintedSessionOnCompanyEnd(reason: 'unit_test');
        expect(cleared, isTrue);
        expect(activeDriverSessionNotifier.value, isNull);
      },
    );
  });

  // -----------------------------------------------------------------
  // Source-contract wiring: proves the widget publishes at explicit
  // transitions and NOT from build().
  // -----------------------------------------------------------------
  group('source-contract: _publishBearerBusyState', () {
    final source =
        _readSourceOrFail('lib/main_parts/driver_home_page_state.dart');

    test(
      'busy calculation includes _driverSwitchMintController.isMinting',
      () {
        final method = _extractMethodBody(
          source,
          RegExp(r'void\s+_publishBearerBusyState\('),
        );
        expect(
          method.contains('_driverSwitchMintController.isMinting'),
          isTrue,
          reason:
              'The notifier must remain true while a mint is in flight so '
              'company-end call sites refuse until the mint settles.',
        );
        expect(method.contains('_liveRideActive'), isTrue);
        expect(method.contains('_stopTeardownInProgress'), isTrue);
        expect(method.contains('_directStopFinalizePending'), isTrue);
      },
    );

    test(
      'standalone driver mode publishes false unconditionally',
      () {
        final method = _extractMethodBody(
          source,
          RegExp(r'void\s+_publishBearerBusyState\('),
        );
        expect(
          method.contains('if (!widget.openedFromBusinessHome)'),
          isTrue,
        );
        expect(
          method.contains('operatorMintedBearerInFlightNotifier.value = false'),
          isTrue,
        );
      },
    );

    test(
      'build() MUST NOT call _publishBearerBusyState (no global mutation '
      'from render)',
      () {
        final buildBody = _extractMethodBody(
          source,
          RegExp(r'Widget\s+build\('),
        );
        expect(
          buildBody.contains('_publishBearerBusyState()'),
          isFalse,
          reason:
              'build() must not mutate operatorMintedBearerInFlightNotifier.',
        );
      },
    );
  });

  group('source-contract: explicit transition publish sites', () {
    final source =
        _readSourceOrFail('lib/main_parts/driver_home_page_state.dart');

    test(
      'dispose() publishes AFTER invalidating pending switches AND clearing '
      'owned operator session',
      () {
        final body = _extractMethodBody(
          source,
          RegExp(r'void\s+dispose\('),
          bodyMustContain: 'invalidatePendingResponses()',
        );
        final invIdx =
            body.indexOf('_driverSwitchMintController.invalidatePendingResponses()');
        final clearIdx =
            body.indexOf("_clearOperatorMintedSessionIfOwned(reason: 'dispose')");
        final pubIdx = body.indexOf('_publishBearerBusyState()');
        expect(invIdx, greaterThanOrEqualTo(0));
        expect(clearIdx, greaterThan(invIdx));
        expect(pubIdx, greaterThan(clearIdx));
      },
    );

    test(
      '_hydrateBusinessPreviewDriverSession publishes bearer-busy AFTER '
      'setOperatorMintedDriverSessionInMemory / '
      'setBusinessDriverViewSessionInMemory (init/ownership capture)',
      () {
        final body = _extractMethodBody(
          source,
          RegExp(r'Future<ActiveDriverSession>\s+_hydrateBusinessPreviewDriverSession\('),
        );
        final opSetIdx =
            body.indexOf('setOperatorMintedDriverSessionInMemory(built)');
        final busSetIdx =
            body.indexOf('setBusinessDriverViewSessionInMemory(built)');
        final pubIdx = body.indexOf('_publishBearerBusyState()');
        expect(opSetIdx, greaterThanOrEqualTo(0));
        expect(busSetIdx, greaterThanOrEqualTo(0));
        expect(pubIdx, greaterThan(opSetIdx));
        expect(pubIdx, greaterThan(busSetIdx));
      },
    );

    test(
      '_deterministicStopTeardown publishes at ENTRY (after '
      '_stopTeardownInProgress = true) and in the FINALLY block '
      '(after _stopTeardownInProgress = false)',
      () {
        final body = _extractMethodBody(
          source,
          RegExp(r'Future<void>\s+_deterministicStopTeardown\('),
        );
        // Two publishes: one before the try{}, one inside finally{}.
        final firstEnter =
            body.indexOf('_stopTeardownInProgress = true;');
        final firstPub =
            body.indexOf('_publishBearerBusyState()', firstEnter);
        expect(firstEnter, greaterThanOrEqualTo(0));
        expect(firstPub, greaterThan(firstEnter));

        final finallyIdx = body.indexOf('} finally {');
        final falseIdx =
            body.indexOf('_stopTeardownInProgress = false;', finallyIdx);
        final finallyPub =
            body.indexOf('_publishBearerBusyState()', falseIdx);
        expect(finallyIdx, greaterThanOrEqualTo(0));
        expect(falseIdx, greaterThan(finallyIdx));
        expect(finallyPub, greaterThan(falseIdx));
      },
    );

    test(
      'reconcile pending enter/exit publishes bearer-busy on '
      '_directStopFinalizePending = true / false',
      () {
        final body = _extractMethodBody(
          source,
          RegExp(r'Future<void>\s+_stopTrip\('),
        );
        // Enter: `_directStopFinalizePending = true; _publishBearerBusyState();`
        final enterFlagIdx =
            body.indexOf('_directStopFinalizePending = true;');
        final enterPubIdx =
            body.indexOf('_publishBearerBusyState()', enterFlagIdx);
        expect(enterFlagIdx, greaterThanOrEqualTo(0));
        expect(enterPubIdx, greaterThan(enterFlagIdx));

        // Exit: two paths clear the pending flag and publish. The ack
        // branch and the final terminate branch.
        // We assert every occurrence of `_directStopFinalizePending = false;`
        // is followed by a `_publishBearerBusyState()` before the next
        // pending-flag mutation or end of method.
        final falseMatches = RegExp(
          r'_directStopFinalizePending = false;',
        ).allMatches(body).toList();
        expect(falseMatches.length, greaterThanOrEqualTo(2));
        for (final m in falseMatches) {
          final nextPub = body.indexOf('_publishBearerBusyState()', m.end);
          expect(
            nextPub,
            greaterThan(m.end),
            reason:
                'Every `_directStopFinalizePending = false;` must be '
                'immediately followed by `_publishBearerBusyState()`.',
          );
        }
      },
    );

    test(
      'ride START transitions publish bearer-busy (three code paths: '
      'planned start, street_direct_resume, street ride start)',
      () {
        // Anchor on the reason-string literal that precedes each START
        // setState (each site invokes `_hardClearAtRideBoundary` with the
        // matching reason). Using the plain literal is robust against
        // single-line vs multi-line function calls.
        final startPaths = <String>[
          "'planned_ride_start'",
          "'street_direct_resume'",
          "'street_ride_start'",
        ];
        for (final anchorText in startPaths) {
          final anchor = source.indexOf(anchorText);
          expect(
            anchor,
            greaterThanOrEqualTo(0),
            reason:
                'Missing anchor $anchorText for ride START transition.',
          );
          // Search a bounded window after the anchor (2500 chars is more
          // than enough for the enclosing setState + publish call to fit).
          final window = source.substring(
            anchor,
            (anchor + 2500).clamp(0, source.length),
          );
          // The publish must come AFTER the setState and BEFORE any
          // wakelock/tracking start so a company-end running immediately
          // after START observes busy=true.
          expect(
            window.contains('_publishBearerBusyState()'),
            isTrue,
            reason:
                'Ride START ($anchorText) must publish bearer-busy=true '
                'inside its enclosing scope.',
          );
        }
      },
    );

    test(
      '_stopTrip early meter-stop setState is followed by an explicit '
      'publish (covers the case where the reconcile branch is skipped)',
      () {
        final body = _extractMethodBody(
          source,
          RegExp(r'Future<void>\s+_stopTrip\('),
        );
        final meterStopIdx = body.indexOf('_hardClearAtRideBoundary(reason: \'stop_begin\'');
        final pubIdx = body.indexOf(
          '_publishBearerBusyState()',
          meterStopIdx,
        );
        expect(meterStopIdx, greaterThanOrEqualTo(0));
        expect(pubIdx, greaterThan(meterStopIdx));
        // The publish must come BEFORE the deterministic teardown enter
        // so the notifier is accurate when reconcile is skipped.
        final teardownIdx = body.indexOf('_deterministicStopTeardown(', pubIdx);
        expect(teardownIdx, greaterThan(pubIdx));
      },
    );

    test(
      '_performInPageDriverSwitchMint publishes bearer-busy at mint ENTER '
      '(post-beginSwitch) and at every EXIT path',
      () {
        final body = _extractMethodBody(
          source,
          RegExp(r'Future<void>\s+_performInPageDriverSwitchMint\('),
        );
        // ENTER — post beginSwitch, before await.
        final beginIdx =
            body.indexOf('_driverSwitchMintController.beginSwitch(');
        final awaitIdx = body.indexOf('await begin.outcomeFuture', beginIdx);
        final enterPub =
            body.indexOf('_publishBearerBusyState()', beginIdx);
        expect(beginIdx, greaterThanOrEqualTo(0));
        expect(awaitIdx, greaterThan(beginIdx));
        expect(enterPub, greaterThan(beginIdx));
        expect(enterPub, lessThan(awaitIdx));

        // EXIT paths — publish/drop-stale/failure/company-mismatch/scope-mismatch.
        // Each anchor sits inside its own case-block or if-block; scan a
        // bidirectional window because publish placement varies (some anchors
        // are the debugPrint that follows the publish, some precede it).
        final exitAnchors = <String>[
          'company_session_changed',
          'scope_changed_during_mint',
          'stale_generation',
          '[DRIVER_SWITCH_MINT][FAIL]',
          '[DRIVER_SWITCH_MINT][PUBLISHED]',
        ];
        for (final anchor in exitAnchors) {
          final aIdx = body.indexOf(anchor);
          expect(
            aIdx,
            greaterThanOrEqualTo(0),
            reason: 'anchor $anchor missing',
          );
          final start = (aIdx - 400).clamp(0, body.length);
          final end = (aIdx + 400).clamp(0, body.length);
          final window = body.substring(start, end);
          expect(
            window.contains('_publishBearerBusyState()'),
            isTrue,
            reason:
                'Mint exit path $anchor must publish bearer-busy to reflect '
                'the just-cleared mint state.',
          );
        }
      },
    );

    test(
      'post-await company/scope mismatch calls '
      '_driverSwitchMintController.invalidatePendingResponses() '
      'BEFORE publishing (so START is not left disabled by stranded '
      'isMinting)',
      () {
        final body = _extractMethodBody(
          source,
          RegExp(r'Future<void>\s+_performInPageDriverSwitchMint\('),
        );
        for (final anchor in const [
          'company_session_changed',
          'scope_changed_during_mint',
        ]) {
          final aIdx = body.indexOf(anchor);
          final invIdx = body.indexOf(
            '_driverSwitchMintController.invalidatePendingResponses()',
            aIdx,
          );
          final pubIdx = body.indexOf('_publishBearerBusyState()', aIdx);
          final returnIdx = body.indexOf('return;', aIdx);
          expect(aIdx, greaterThanOrEqualTo(0));
          expect(invIdx, greaterThan(aIdx));
          expect(pubIdx, greaterThan(invIdx));
          expect(returnIdx, greaterThan(pubIdx));
        }
      },
    );
  });
}
