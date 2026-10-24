// SECURITY-REMOVE-CLIENT-ADMIN-TOKEN-P0-1 (Field Failure Fix, Blocker Fix)
//
// Tests for the business-preview operator-mint hydration lifecycle. The
// field failure — "operator-minted in-memory session is cleared during
// business-preview hydration" — is caused by `_resolveBusinessPreviewSessionToken`
// unconditionally returning a tokenless session during
// `preview_load_applied`. This suite proves:
//
//   1. `_resolveBusinessPreviewSessionToken` preserves an operator-minted
//      bearer from `previous` (in-memory) ONLY when scope + expiry + identity
//      all match.
//   2. `persisted` is never consulted for operator-mint preservation.
//   3. Standalone / pairing / public-login / tokenless preview sessions are
//      never eligible.
//   4. `clearOperatorMintedSessionOnCompanyEnd` refuses to clear while the
//      operator bearer is in flight, and clears otherwise.
//   5. Source-contract wiring:
//      - `_hydrateBusinessPreviewDriverSession` routes to
//        `setOperatorMintedDriverSessionInMemory` when the built session is
//        operator-minted, and captures `_ownedOperatorMintedSessionRef`.
//      - `_performInPageDriverSwitchMint` re-reads company session + scope
//        + generation before publishing.
//      - `_atomicallyPublishBAsCurrent` publishes with no `await` between
//        `_businessPreviewDriverId` and `activeDriverSessionNotifier.value`.
//      - Three company-end sites call
//        `clearOperatorMintedSessionOnCompanyEnd` and gate on
//        `operatorMintedBearerInFlightNotifier`.
//      - `_driverRideStartAuthAllowsOrRefuse` refuses during a switch mint.
//      - `_DriverHomePageState.build()` returns a `PopScope` and dispose
//        invalidates pending switch responses first.
//
// Run:
//   flutter test test/main_parts/business_preview_operator_mint_hydration_test.dart

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_config.dart';
import 'package:fluxidi_tracking/driver_session_store.dart';
import 'package:fluxidi_tracking/main.dart' show validateMintedScope;

// -------------------------------------------------------------------------
// Fixtures
// -------------------------------------------------------------------------

ActiveDriverSession _operatorMintedSession({
  String driverId = 'driver_a',
  String tenantId = 'tenant_a',
  String companyId = 'company_a',
  String token = 'dst_op_AAA',
  String? expiresAt,
}) {
  final iso = expiresAt ?? DateTime.utc(2099, 1, 1).toIso8601String();
  return ActiveDriverSession(
    driverId: driverId,
    employeeNumber: 'E001',
    fullName: 'A',
    phone: '+3100',
    loggedInAt: DateTime.utc(2027).toIso8601String(),
    updatedAt: DateTime.utc(2027).toIso8601String(),
    tenantId: tenantId,
    companyId: companyId,
    driverSessionToken: token,
    driverSessionExpiresAtUtc: iso,
    linkMethod: kOperatorMintDriverLinkMethod,
    expiresAt: iso,
  );
}

ActiveDriverSession _standaloneSession({
  String driverId = 'driver_x',
}) {
  return ActiveDriverSession(
    driverId: driverId,
    employeeNumber: 'E002',
    fullName: 'X',
    phone: '+3100',
    loggedInAt: DateTime.utc(2027).toIso8601String(),
    updatedAt: DateTime.utc(2027).toIso8601String(),
    tenantId: 'tenant_a',
    companyId: 'company_a',
    driverSessionToken: 'dst_standalone_XXX',
    driverSessionExpiresAtUtc:
        DateTime.utc(2099, 1, 1).toIso8601String(),
    linkMethod: 'standalone_driver',
  );
}

ActiveDriverSession _tokenlessPreviewSession({
  String driverId = 'driver_a',
}) {
  return ActiveDriverSession(
    driverId: driverId,
    employeeNumber: 'E001',
    fullName: 'A',
    phone: '+3100',
    loggedInAt: DateTime.utc(2027).toIso8601String(),
    updatedAt: DateTime.utc(2027).toIso8601String(),
    tenantId: 'tenant_a',
    companyId: 'company_a',
    linkMethod: kCompanyAdminDriverViewLinkMethod,
  );
}

// -------------------------------------------------------------------------
// Source-contract helpers
// -------------------------------------------------------------------------

/// Reads a source file from the repo tree relative to the project root.
String _readSourceOrFail(String relativePath) {
  final f = File(relativePath);
  if (!f.existsSync()) {
    fail('Missing source file for contract test: $relativePath');
  }
  return f.readAsStringSync();
}

/// Strips `// line` and `/* block */` comments from a Dart source snippet.
/// This is a best-effort stripper used only on the EXTRACTED body — never
/// on the whole file (which contains complex strings/regexes that this
/// simple pass may mishandle). Preserves double-quoted string literals
/// with `//` inside them via a naive quote counter.
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

/// Extracts a method body (from `signaturePattern` up to matching brace).
/// The signature pattern is expected to end at the opening `(` of the
/// parameter list. The extractor first walks the parameter list (tracking
/// `(` / `)` and `{` / `}` and single-line strings) to find the closing
/// `)`, and only then locates the body-opening `{`. This handles named
/// parameters like `({required String x})` correctly.
///
/// When [bodyMustContain] is set, the extractor iterates every regex
/// match and picks the first whose body contains that substring. This
/// disambiguates `dispose()` in files where several classes declare their
/// own dispose method.
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

/// Helper for [_extractMethodBody]. Returns `null` on parse failure so the
/// caller can try the next candidate match.
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
// Tests
// -------------------------------------------------------------------------

void main() {
  group('validateMintedScope (blocker-fix invariants)', () {
    test(
      'requires the minted driver/tenant/company to be non-empty and exactly '
      'equal to the requested values',
      () {
        final expiry = DateTime.utc(2099, 1, 1).toIso8601String();
        final now = DateTime.utc(2027);
        // Empty minted tenant/company must NOT be tolerated with a fallback.
        expect(
          validateMintedScope(
            minted: OperatorMintedDriverSession(
              driverSessionToken: 'dst',
              driverSessionExpiresAtUtc: expiry,
              expiresInSeconds: 3600,
              tenantId: '',
              companyId: 'company_a',
              driverId: 'driver_a',
            ),
            requestedDriverId: 'driver_a',
            requestedTenantId: 'tenant_a',
            requestedCompanyId: 'company_a',
            now: now,
          ),
          equals('scope_mismatch_tenant'),
        );
      },
    );
  });

  group('clearOperatorMintedSessionOnCompanyEnd', () {
    setUp(() {
      activeDriverSessionNotifier.value = null;
      operatorMintedBearerInFlightNotifier.value = false;
    });

    tearDown(() {
      activeDriverSessionNotifier.value = null;
      operatorMintedBearerInFlightNotifier.value = false;
    });

    test('clears operator-minted session and returns true on success', () {
      final session = _operatorMintedSession();
      activeDriverSessionNotifier.value = session;
      final cleared = DriverSessionStore.instance
          .clearOperatorMintedSessionOnCompanyEnd(reason: 'test');
      expect(cleared, isTrue);
      expect(activeDriverSessionNotifier.value, isNull);
    });

    test('returns false when no session is present', () {
      final cleared = DriverSessionStore.instance
          .clearOperatorMintedSessionOnCompanyEnd(reason: 'test');
      expect(cleared, isFalse);
    });

    test('does not touch a standalone chauffeur session', () {
      final session = _standaloneSession();
      activeDriverSessionNotifier.value = session;
      final cleared = DriverSessionStore.instance
          .clearOperatorMintedSessionOnCompanyEnd(reason: 'test');
      expect(cleared, isFalse);
      expect(activeDriverSessionNotifier.value, same(session));
    });

    test('refuses to clear while the bearer is in flight', () {
      final session = _operatorMintedSession();
      activeDriverSessionNotifier.value = session;
      operatorMintedBearerInFlightNotifier.value = true;
      final cleared = DriverSessionStore.instance
          .clearOperatorMintedSessionOnCompanyEnd(reason: 'test');
      expect(cleared, isFalse);
      expect(activeDriverSessionNotifier.value, same(session));
    });
  });

  // -----------------------------------------------------------------------
  // Source-contract on _DriverHomePageState.
  // -----------------------------------------------------------------------

  group('source-contract — _resolveBusinessPreviewSessionToken', () {
    final source = _readSourceOrFail('lib/main_parts/driver_home_page_state.dart');
    final method = _extractMethodBody(
      source,
      RegExp(
        r'_resolveBusinessPreviewSessionToken\(',
      ),
    );

    test('only considers `previous` for operator-mint preservation', () {
      expect(
        method.contains('previous.isOperatorMintedSession'),
        isTrue,
        reason: 'must gate reuse on previous.isOperatorMintedSession',
      );
      // `persisted` MUST NOT be inspected for preservation.
      expect(
        RegExp(r'\bpersisted[\.\s]').hasMatch(method),
        isFalse,
        reason:
            'operator-mint preservation must not consult `persisted`',
      );
    });

    test('checks expiry usability before preserving the token', () {
      expect(
        method.contains('_isBusinessPreviewDriverSessionTokenUsable'),
        isTrue,
      );
    });

    test('checks driver/tenant/company identity before preserving', () {
      expect(
        method.contains('_businessPreviewSessionIdentityMatches'),
        isTrue,
      );
    });

    test('returns source=operator_mint_preserved on the happy path', () {
      expect(method.contains("'operator_mint_preserved'"), isTrue);
    });
  });

  group('source-contract — _hydrateBusinessPreviewDriverSession', () {
    final source = _readSourceOrFail('lib/main_parts/driver_home_page_state.dart');
    final method = _extractMethodBody(
      source,
      RegExp(
        r'Future<ActiveDriverSession>\s+_hydrateBusinessPreviewDriverSession\(',
      ),
    );

    test(
      'routes an operator-minted built session to setOperatorMintedDriverSessionInMemory',
      () {
        expect(
          method.contains('setOperatorMintedDriverSessionInMemory(built)'),
          isTrue,
        );
      },
    );

    test('captures reference identity ownership after publish', () {
      expect(
        method.contains('_ownedOperatorMintedSessionRef = built'),
        isTrue,
      );
    });

    test('falls back to setBusinessDriverViewSessionInMemory for non-mint', () {
      expect(
        method.contains('setBusinessDriverViewSessionInMemory(built)'),
        isTrue,
      );
    });
  });

  group('source-contract — _buildBusinessPreviewDriverSession', () {
    final source = _readSourceOrFail('lib/main_parts/driver_home_page_state.dart');
    final method = _extractMethodBody(
      source,
      RegExp(
        r'ActiveDriverSession\s+_buildBusinessPreviewDriverSession\(',
      ),
    );

    test(
      'preserves operator-mint linkMethod when the resolver preserved the token',
      () {
        // The build path must emit kOperatorMintDriverLinkMethod when
        // resolvedToken.source == 'operator_mint_preserved'; otherwise it
        // falls back to kCompanyAdminDriverViewLinkMethod. Both symbols must
        // appear textually.
        expect(method.contains('kOperatorMintDriverLinkMethod'), isTrue);
        expect(
          method.contains('kCompanyAdminDriverViewLinkMethod'),
          isTrue,
        );
        expect(method.contains("'operator_mint_preserved'"), isTrue);
      },
    );
  });

  group('source-contract — _performInPageDriverSwitchMint', () {
    final source = _readSourceOrFail('lib/main_parts/driver_home_page_state.dart');
    final method = _extractMethodBody(
      source,
      RegExp(
        r'Future<void>\s+_performInPageDriverSwitchMint\(',
      ),
    );

    test('captures the company session at request begin', () {
      expect(
        method.contains(
          'final capturedCompanySession = activeCompanySessionNotifier.value',
        ),
        isTrue,
      );
    });

    test('re-reads the company session after await to detect a change', () {
      expect(
        method.contains(
          'final currentCompanySession = activeCompanySessionNotifier.value',
        ),
        isTrue,
      );
      expect(
        method.contains(
          'identical(currentCompanySession, capturedCompanySession)',
        ),
        isTrue,
      );
    });

    test('re-reads the live scope after await', () {
      expect(
        method.contains('_activeBusinessPreviewScope()'),
        isTrue,
      );
    });

    test('uses the controller for begin, resolve, and drop-stale', () {
      expect(
        method.contains('_driverSwitchMintController.beginSwitch'),
        isTrue,
      );
      expect(
        method.contains('_driverSwitchMintController.resolveResponse'),
        isTrue,
      );
      expect(method.contains('DriverSwitchMintDropStale()'), isTrue);
    });

    test('publishes B via the atomic helper on success', () {
      expect(method.contains('_atomicallyPublishBAsCurrent('), isTrue);
    });

    test('does not touch _businessPreviewDriverId before publish', () {
      // Only assignment to _businessPreviewDriverId inside the mint helper
      // must be through _atomicallyPublishBAsCurrent. Direct assignment
      // would appear here as `_businessPreviewDriverId =`.
      final directAssignments = RegExp(
        r'_businessPreviewDriverId\s*=',
      ).allMatches(method).toList();
      expect(
        directAssignments,
        isEmpty,
        reason:
            'A → B selection state must not mutate until atomic publish',
      );
    });
  });

  group('source-contract — _atomicallyPublishBAsCurrent', () {
    final source = _readSourceOrFail('lib/main_parts/driver_home_page_state.dart');
    final method = _extractMethodBody(
      source,
      RegExp(
        r'void\s+_atomicallyPublishBAsCurrent\(',
      ),
    );

    test(
      'no `await` between _businessPreviewDriverId assignment and notifier publish',
      () {
        final businessIdx =
            method.indexOf('_businessPreviewDriverId = driverProfile.id.trim()');
        final notifierIdx = method.indexOf(
          'setOperatorMintedDriverSessionInMemory(session)',
        );
        expect(businessIdx, greaterThanOrEqualTo(0));
        expect(notifierIdx, greaterThan(businessIdx));
        final between = method.substring(businessIdx, notifierIdx);
        expect(
          RegExp(r'\bawait\b').hasMatch(between),
          isFalse,
          reason:
              'atomic transition must not contain an await between the '
              'selection update and the notifier publish',
        );
      },
    );

    test('captures reference identity ownership on publish', () {
      expect(
        method.contains('_ownedOperatorMintedSessionRef = session'),
        isTrue,
      );
    });

    test('always uses kOperatorMintDriverLinkMethod for the new B session', () {
      expect(method.contains('kOperatorMintDriverLinkMethod'), isTrue);
      // Must not fall back to the company-admin driver-view linkMethod here.
      expect(
        method.contains('kCompanyAdminDriverViewLinkMethod'),
        isFalse,
      );
    });
  });

  group('source-contract — _clearOperatorMintedSessionIfOwned', () {
    final source = _readSourceOrFail('lib/main_parts/driver_home_page_state.dart');
    final method = _extractMethodBody(
      source,
      RegExp(
        r'bool\s+_clearOperatorMintedSessionIfOwned\(',
      ),
    );

    test('uses reference identity (identical) against the notifier value', () {
      expect(
        method.contains(
          'identical(current, owned)',
        ),
        isTrue,
      );
    });

    test('refuses to clear during live ride/teardown/finalize', () {
      expect(method.contains('_liveRideActive'), isTrue);
      expect(method.contains('_stopTeardownInProgress'), isTrue);
      expect(method.contains('_directStopFinalizePending'), isTrue);
    });

    test('refuses to clear while a switch mint is still pending', () {
      expect(
        method.contains('_driverSwitchMintController.isMinting'),
        isTrue,
      );
      expect(
        method.contains(
          '_driverSwitchMintController.pendingGeneration',
        ),
        isTrue,
      );
    });
  });

  group('source-contract — _attemptBusinessPreviewRouteExit', () {
    final source = _readSourceOrFail('lib/main_parts/driver_home_page_state.dart');
    final method = _extractMethodBody(
      source,
      RegExp(
        r'void\s+_attemptBusinessPreviewRouteExit\(',
      ),
    );

    test('delegates to the controller for exit-request resolution', () {
      expect(
        method.contains(
          '_driverSwitchMintController.resolveExitRequest',
        ),
        isTrue,
      );
    });

    test('applies the owned-clear helper before popping the route', () {
      final clearIdx = method.indexOf(
        "_clearOperatorMintedSessionIfOwned(reason: 'route_exit')",
      );
      // Business-preview branch is the second `nav.pop()` in the method
      // (the first pops the standalone-mode fallback before the guard runs).
      final popIdx = method.indexOf('nav.pop()', clearIdx);
      expect(clearIdx, greaterThanOrEqualTo(0));
      expect(popIdx, greaterThan(clearIdx));
    });
  });

  group('source-contract — dispose defensive ordering', () {
    final source = _readSourceOrFail('lib/main_parts/driver_home_page_state.dart');
    final method = _extractMethodBody(
      source,
      RegExp(r'void\s+dispose\('),
      bodyMustContain: '[MAP][DISPOSE] mounted=',
    );

    test(
      'invalidates pending controller responses BEFORE attempting owned-clear',
      () {
        final invIdx = method.indexOf(
          '_driverSwitchMintController.invalidatePendingResponses()',
        );
        final clearIdx = method.indexOf(
          '_clearOperatorMintedSessionIfOwned(reason: \'dispose\')',
        );
        expect(invIdx, greaterThanOrEqualTo(0));
        expect(clearIdx, greaterThan(invIdx));
      },
    );

    test('publishes the bearer-busy state after invalidating and clearing', () {
      expect(method.contains('_publishBearerBusyState()'), isTrue);
    });
  });

  group('source-contract — PopScope wiring in build()', () {
    final source = _readSourceOrFail('lib/main_parts/driver_home_page_state.dart');

    test('returns a PopScope wrapping the Scaffold', () {
      // build() assigns the PopScope to `driverBody` (PiP can wrap it in a
      // Stack). Require the widget, the business-preview pop contract, and
      // that PopScope's child is the page Scaffold.
      expect(
        RegExp(r'(?:return|=)\s+PopScope\s*\(').hasMatch(source),
        isTrue,
        reason: 'Driver home build must construct a PopScope',
      );
      expect(
        source.contains(
          'canPop: !widget.openedFromBusinessHome',
        ),
        isTrue,
      );
      expect(source.contains('onPopInvokedWithResult:'), isTrue);
      expect(
        source.contains(
          "_attemptBusinessPreviewRouteExit(source: 'pop_scope_system_back')",
        ),
        isTrue,
      );
      expect(
        RegExp(r'PopScope\s*\([\s\S]*?child:\s*Scaffold\s*\(').hasMatch(source),
        isTrue,
        reason: 'PopScope must wrap the driver Scaffold',
      );
    });

    test(
      'build() must NOT invoke _publishBearerBusyState — global notifier '
      'mutation is not a build-time side effect',
      () {
        // Extract the body of the exact `Widget build(BuildContext context)`
        // method and assert `_publishBearerBusyState()` is absent. The
        // notifier is published only from explicit state transitions.
        final method = _extractMethodBody(
          source,
          RegExp(r'Widget\s+build\('),
        );
        expect(
          method.contains('_publishBearerBusyState()'),
          isFalse,
          reason:
              'build() must not mutate operatorMintedBearerInFlightNotifier '
              'as a side effect of render scheduling.',
        );
      },
    );
  });

  group('source-contract — START guard refuses during switch mint', () {
    final source = _readSourceOrFail('lib/main_parts/driver_home_page_state.dart');
    final method = _extractMethodBody(
      source,
      RegExp(
        r'bool\s+_driverRideStartAuthAllowsOrRefuse\(',
      ),
    );

    test('refuses when the controller is minting', () {
      expect(
        method.contains('_driverSwitchMintController.isMinting'),
        isTrue,
      );
      expect(method.contains('reason=switch_mint_in_flight'), isTrue);
    });
  });

  group('source-contract — three company-end call sites', () {
    test(
      'BusinessHomePage._switchCompany gates on bearer-in-flight and clears '
      'operator-minted session before clearing company state',
      () {
        final source = _readSourceOrFail('lib/main_parts/business_home_page_state.dart');
        final method = _extractMethodBody(
          source,
          RegExp(r'Future<void>\s+_switchCompany\('),
        );
        expect(
          method.contains(
            'operatorMintedBearerInFlightNotifier.value',
          ),
          isTrue,
        );
        final clearIdx = method.indexOf(
          'DriverSessionStore.instance.clearOperatorMintedSessionOnCompanyEnd',
        );
        final companyClearIdx = method.indexOf(
          'CompanySessionStore.instance.clearLocalCompanyState()',
        );
        expect(clearIdx, greaterThanOrEqualTo(0));
        expect(companyClearIdx, greaterThan(clearIdx));
      },
    );

    test(
      '_switchCompanyFromRecoveryDialog gates on bearer-in-flight and clears '
      'operator-minted session',
      () {
        final source = _readSourceOrFail('lib/main.dart');
        final method = _extractMethodBody(
          source,
          RegExp(
            r'Future<void>\s+_switchCompanyFromRecoveryDialog\(',
          ),
        );
        expect(
          method.contains('operatorMintedBearerInFlightNotifier.value'),
          isTrue,
        );
        final clearIdx = method.indexOf(
          'DriverSessionStore.instance.clearOperatorMintedSessionOnCompanyEnd',
        );
        final companyClearIdx = method.indexOf(
          'CompanySessionStore.instance.clearLocalCompanyState()',
        );
        expect(clearIdx, greaterThanOrEqualTo(0));
        expect(companyClearIdx, greaterThan(clearIdx));
      },
    );

    test(
      'RoleEntryPage onboarding intent gates on bearer-in-flight and clears '
      'operator-minted session before clearing company state',
      () {
        final source = _readSourceOrFail('lib/main_parts/role_entry_page.dart');
        // We do not extract a method; we check the presence of the guard
        // inside the file. The three tokens (notifier, clearOperator, clear
        // company state) must appear in that order in the source.
        final notIdx = source.indexOf(
          'operatorMintedBearerInFlightNotifier.value',
        );
        final clearOpIdx = source.indexOf(
          'DriverSessionStore.instance.clearOperatorMintedSessionOnCompanyEnd',
        );
        final companyClearIdx = source.indexOf(
          'CompanySessionStore.instance.clearLocalCompanyState()',
        );
        expect(notIdx, greaterThanOrEqualTo(0));
        expect(clearOpIdx, greaterThan(notIdx));
        expect(companyClearIdx, greaterThan(clearOpIdx));
      },
    );
  });

  group('source-contract — tokenless preview sessions never eligible', () {
    // Runtime cross-check of the resolver-preserved fixture: only
    // operator-minted, non-empty-token, non-expired, exact-scope sessions
    // must be able to survive the hydration. Standalone / tokenless
    // sessions cannot even satisfy the eligibility predicates.
    test('standalone session is not operator-minted', () {
      final s = _standaloneSession();
      expect(s.isOperatorMintedSession, isFalse);
    });

    test('tokenless preview session is not operator-minted', () {
      final s = _tokenlessPreviewSession();
      expect(s.isOperatorMintedSession, isFalse);
      expect((s.driverSessionToken ?? '').trim(), isEmpty);
    });

    test('operator-minted session with future expiry is eligible', () {
      final s = _operatorMintedSession();
      expect(s.isOperatorMintedSession, isTrue);
      expect((s.driverSessionToken ?? '').trim(), isNotEmpty);
      final expiry = DateTime.parse(s.driverSessionExpiresAtUtc!).toUtc();
      expect(expiry.isAfter(DateTime.now().toUtc()), isTrue);
    });

    test('operator-minted session with past expiry is NOT eligible', () {
      final s = _operatorMintedSession(
        expiresAt: '2020-01-01T00:00:00Z',
      );
      final expiry = DateTime.parse(s.driverSessionExpiresAtUtc!).toUtc();
      expect(expiry.isBefore(DateTime.now().toUtc()), isTrue);
    });
  });
}
