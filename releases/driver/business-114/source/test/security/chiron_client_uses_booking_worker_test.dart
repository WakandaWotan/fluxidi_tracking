// CHIRON-P0-2A source-contract tests.
//
// Prove that after the client-required session migration:
//   * the three previously-direct compliance calls (readiness,
//     score-summary, recent events) now go through the booking worker
//     using `resolveCompanyOwnerAuthHeaders()` and `bookingBaseUrl`;
//   * `lib/` contains no `_complianceAdminToken` constant;
//   * `lib/` contains no `Authorization: Bearer $_complianceAdminToken`
//     or `x-admin-token` header construction on Chiron surfaces;
//   * destructive reset / testflow-reset controls are hidden or disabled
//     in release mode;
//   * the five previously-migrated Chiron config/connection routes remain
//     wired via `_chironBookingScopedEndpoint`.
//
// These are static, source-contract assertions: they read the shipping
// Dart files as text and check for the required syntactic patterns. Data
// isolation is proved end-to-end by the worker `.test.mjs` suites at
// `workers/booking/chiron_readonly_proxy_isolation.test.mjs` and
// `workers/compliance/chiron_readonly_internal_proxy_auth.test.mjs`.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String path) {
  final file = File(path);
  expect(
    file.existsSync(),
    isTrue,
    reason: 'Required source file $path must exist.',
  );
  return file.readAsStringSync();
}

/// Extract the body of a method whose signature matches [signaturePattern].
/// The pattern must anchor at the opening `(` (e.g. `Future<void> _foo(`).
/// The extractor then advances to the first `{` and returns everything up
/// to the matching `}` using a brace counter.
String _extractMethodBody(String source, RegExp signaturePattern) {
  final match = signaturePattern.firstMatch(source);
  expect(
    match,
    isNotNull,
    reason: 'Could not find method matching ${signaturePattern.pattern}',
  );
  final startParen = match!.end - 1; // final `(`
  // Advance through parameter list balancing parens.
  var depth = 0;
  var i = startParen;
  for (; i < source.length; i++) {
    final ch = source[i];
    if (ch == '(') depth += 1;
    if (ch == ')') {
      depth -= 1;
      if (depth == 0) {
        i += 1;
        break;
      }
    }
  }
  // Skip `async ` and other keywords up to `{`.
  final braceIdx = source.indexOf('{', i);
  expect(braceIdx, greaterThan(-1));
  var bd = 0;
  for (var j = braceIdx; j < source.length; j++) {
    final ch = source[j];
    if (ch == '{') bd += 1;
    if (ch == '}') {
      bd -= 1;
      if (bd == 0) return source.substring(braceIdx, j + 1);
    }
  }
  fail('Unbalanced braces after ${signaturePattern.pattern}');
}

void main() {
  const dashboardPath = 'lib/chiron_compliance_dashboard_page.dart';
  const readerPath = 'lib/compliance_ledger_reader.dart';

  String stripDartComments(String source) {
    // Remove block comments then line comments. This is deliberately
    // conservative — it doesn't parse strings, so a literal "//" inside
    // a Dart string would be dropped. That's fine for this check: we're
    // only stripping to allow doc-comments to reference the removed
    // identifier without triggering a false positive.
    return source
        .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
        .replaceAll(RegExp(r'//[^\n]*'), '');
  }

  test('CHIRON-P0-2A: _complianceAdminToken is not present in shipped lib/ (excluding comments)', () {
    final offenders = <String>[];
    final dir = Directory('lib');
    for (final entity in dir.listSync(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      if (!entity.path.toLowerCase().endsWith('.dart')) continue;
      final text = entity.readAsStringSync();
      final stripped = stripDartComments(text);
      if (stripped.contains('_complianceAdminToken')) {
        offenders.add(entity.path);
      }
    }
    expect(
      offenders,
      isEmpty,
      reason:
          '_complianceAdminToken must be removed from shipped Flutter code '
          '(only documentation comments may reference it). '
          'Offenders: $offenders',
    );
  });

  test("CHIRON-P0-2A: no String.fromEnvironment('ADMIN_TOKEN') in Chiron surfaces", () {
    final dashboardSrc = _read(dashboardPath);
    final readerSrc = _read(readerPath);
    final pattern = RegExp(
      r"String\.fromEnvironment\s*\(\s*['\x22]ADMIN_TOKEN['\x22]",
    );
    expect(
      pattern.hasMatch(dashboardSrc),
      isFalse,
      reason:
          "$dashboardPath must not embed String.fromEnvironment('ADMIN_TOKEN').",
    );
    expect(
      pattern.hasMatch(readerSrc),
      isFalse,
      reason:
          "$readerPath must not embed String.fromEnvironment('ADMIN_TOKEN').",
    );
  });

  test('CHIRON-P0-2A: no x-admin-token header on Chiron surfaces', () {
    final dashboardSrc = _read(dashboardPath);
    final readerSrc = _read(readerPath);
    expect(dashboardSrc.contains("'x-admin-token'"), isFalse);
    expect(dashboardSrc.contains('"x-admin-token"'), isFalse);
    expect(readerSrc.contains("'x-admin-token'"), isFalse);
    expect(readerSrc.contains('"x-admin-token"'), isFalse);
  });

  test(
    'CHIRON-P0-2A: readiness / score-summary / events-recent use '
    'resolveCompanyOwnerAuthHeaders + bookingBaseUrl',
    () {
      final dashboardSrc = _read(dashboardPath);

      // Top-level `_fetchChironReadinessResponse` (technical report opener).
      final topReadiness = _extractMethodBody(
        dashboardSrc,
        RegExp(r'Future<_ChironReadinessResponse>\s+_fetchChironReadinessResponse\s*\('),
      );
      expect(
        topReadiness.contains('resolveCompanyOwnerAuthHeaders'),
        isTrue,
        reason: 'Technical-report readiness must resolve company-owner headers.',
      );
      expect(
        topReadiness.contains('_chironBookingReadonlyEndpoint'),
        isTrue,
        reason: 'Technical-report readiness must build the booking-worker URL.',
      );
      expect(topReadiness.contains("Authorization': 'Bearer"), isFalse);
      expect(topReadiness.contains('x-admin-token'), isFalse);
      expect(topReadiness.contains('_complianceApiBaseUrl'), isFalse);

      // `_loadScoreSummary`.
      final scoreSummary = _extractMethodBody(
        dashboardSrc,
        RegExp(r'Future<_ChironScoreSummaryResponse>\s+_loadScoreSummary\s*\('),
      );
      expect(scoreSummary.contains('resolveCompanyOwnerAuthHeaders'), isTrue);
      expect(scoreSummary.contains('_chironBookingReadonlyEndpoint'), isTrue);
      expect(scoreSummary.contains('x-admin-token'), isFalse);
      expect(scoreSummary.contains("Authorization': 'Bearer"), isFalse);

      // In-panel `_loadReadiness`.
      final panelReadiness = _extractMethodBody(
        dashboardSrc,
        RegExp(r'Future<_ChironReadinessResponse>\s+_loadReadiness\s*\('),
      );
      expect(panelReadiness.contains('resolveCompanyOwnerAuthHeaders'), isTrue);
      expect(panelReadiness.contains('_chironBookingReadonlyEndpoint'), isTrue);
      expect(panelReadiness.contains('x-admin-token'), isFalse);

      // Remote compliance events fetch (RemoteComplianceEventsFetcher-equivalent).
      // CHIRON-P0-2A follow-up A: the state class now also contains a
      // sibling `_dispatchLoad()` wrapper (which handles the hydration
      // generation guard); this regex anchors on the actual network
      // fetcher `_loadRemoteEvents` to keep the invariant precise.
      final events = _extractMethodBody(
        dashboardSrc,
        RegExp(
          r'Future<RemoteComplianceEventsResponse>\s+_loadRemoteEvents\s*\(',
        ),
      );
      expect(
        events.contains('resolveCompanyOwnerAuthHeaders'),
        isTrue,
        reason: 'Remote compliance events fetch must resolve company-owner headers.',
      );
      expect(
        events.contains('_chironBookingReadonlyEndpoint'),
        isTrue,
        reason: 'Remote compliance events fetch must use the booking-worker URL.',
      );
      expect(events.contains('x-admin-token'), isFalse);
    },
  );

  test(
    'CHIRON-P0-2A: compliance_ledger_reader.fetchBackendEntries goes through booking worker',
    () {
      final readerSrc = _read(readerPath);
      final body = _extractMethodBody(
        readerSrc,
        RegExp(
          r'fetchBackendEntries\s*\(',
        ),
      );
      expect(
        body.contains('appConfig.bookingBaseUrl'),
        isTrue,
        reason: 'fetchBackendEntries must call appConfig.bookingBaseUrl.',
      );
      expect(
        body.contains('resolveCompanyOwnerAuthHeaders'),
        isTrue,
        reason: 'fetchBackendEntries must resolve company-owner headers.',
      );
      expect(body.contains('x-admin-token'), isFalse);
      expect(body.contains("Authorization': 'Bearer"), isFalse);
    },
  );

  test(
    'CHIRON-P0-2A: loadRegisterGrouped no longer accepts apiBaseUrl or adminToken',
    () {
      final readerSrc = _read(readerPath);
      final match = RegExp(
        r'ComplianceLedgerReadResult>\s+loadRegisterGrouped\s*\(\s*\{([^}]*)\}',
      ).firstMatch(readerSrc);
      expect(match, isNotNull);
      final params = match!.group(1)!;
      expect(
        params.contains('apiBaseUrl'),
        isFalse,
        reason:
            'loadRegisterGrouped must not accept apiBaseUrl any more; it now '
            'uses appConfig.bookingBaseUrl internally.',
      );
      expect(
        params.contains('adminToken'),
        isFalse,
        reason:
            'loadRegisterGrouped must not accept adminToken any more; it now '
            'uses resolveCompanyOwnerAuthHeaders internally.',
      );
    },
  );

  test(
    'CHIRON-P0-2A: five pre-existing Chiron config/connection routes remain '
    'wired to _chironBookingScopedEndpoint',
    () {
      final src = _read(dashboardPath);
      const requiredPaths = <String>[
        '/admin/chiron/config/test-credentials',
        '/admin/chiron/config/test-credentials/clear',
        '/admin/chiron/connection/test',
        '/admin/chiron/config/status',
        '/admin/chiron/testflow/reset',
      ];
      for (final path in requiredPaths) {
        expect(
          src.contains(path),
          isTrue,
          reason: 'Chiron config route $path must remain wired.',
        );
      }
      expect(src.contains('_chironBookingScopedEndpoint'), isTrue);
    },
  );

  test(
    'CHIRON-P0-2A: destructive controls are gated behind !kReleaseMode',
    () {
      final src = _read(dashboardPath);

      // The IconButton for "Clear backend test events" must be wrapped in
      // a `!kReleaseMode` conditional.
      final iconMatch = RegExp(
        r'if\s*\(\s*!\s*kReleaseMode\s*\)\s*IconButton\s*\(',
      ).firstMatch(src);
      expect(
        iconMatch,
        isNotNull,
        reason:
            'The "Clear backend test events" IconButton must be inside an '
            '`if (!kReleaseMode)` guard.',
      );

      // The "Reset testflow" OutlinedButton must be wrapped in
      // `!kReleaseMode`.
      final outlinedMatch = RegExp(
        r'if\s*\(\s*!\s*kReleaseMode\s*\)\s*Align\s*\(',
      ).firstMatch(src);
      expect(
        outlinedMatch,
        isNotNull,
        reason:
            'The "Reset testflow" Align/OutlinedButton must be inside an '
            '`if (!kReleaseMode)` guard.',
      );

      // The reset-remote-events method body itself must no longer perform
      // any network call.
      final resetBody = _extractMethodBody(
        src,
        RegExp(r'Future<void>\s+_resetRemoteComplianceEvents\s*\('),
      );
      expect(resetBody.contains('http.get'), isFalse);
      expect(resetBody.contains('http.post'), isFalse);
      expect(resetBody.contains('x-admin-token'), isFalse);
    },
  );

  test(
    'CHIRON-P0-2A: _chironBookingReadonlyEndpoint always uses bookingBaseUrl '
    'and never a compliance-worker URL',
    () {
      final src = _read(dashboardPath);
      final body = _extractMethodBody(
        src,
        RegExp(r'Uri\s+_chironBookingReadonlyEndpoint\s*\('),
      );
      expect(body.contains('appConfig.bookingBaseUrl'), isTrue);
      expect(
        body.contains('fluxidi-compliance-api'),
        isFalse,
        reason:
            'The helper must NOT hard-code the compliance worker hostname.',
      );
    },
  );
}
