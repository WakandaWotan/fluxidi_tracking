// FIELD-RELEASE-BLOCKER-DEVICE-ACTIVATION-AUTH-P0-2
//
// Source-contract tests for the two client-side halves of the field release
// blocker.
//
//  * `_showNewDeviceActivationCodeDialog` (in
//    `lib/main_parts/business_home_page_state.dart`) — the company-owner
//    "generate activation code for a new company device" affordance. Before
//    this patch the request went out with `_adminHeaders()` (an empty map),
//    which caused every real call to be rejected by the booking worker.
//    The migrated method must:
//      - obtain the company-owner session bearer via
//        `resolveCompanyOwnerAuthHeaders()`;
//      - never call `_adminHeaders()` and never construct an
//        `x-admin-token` header;
//      - no longer be gated by `kReleaseMode`;
//      - preserve `hasCompanyOwnerAuthContext()` as the enablement gate;
//      - inspect `Content-Type` before `jsonDecode` to avoid throwing on
//        HTML error pages (e.g. Cloudflare Error 1101);
//      - emit redacted diagnostics on failure — never `catch (_) {}` alone.
//
//  * `_openTemporaryDriverLinkQr` (in
//    `lib/main_parts/company_driver_management_page_body.dart`) — the
//    company-owner "generate driver-link QR" affordance. The QR rendering
//    must remain downstream of a successful `createDriverLinkCode(...)`
//    response and must not gain a new `kReleaseMode` gate as part of this
//    fix. The QR route is repaired server-side only.
//
// Run:
//   flutter test test/main_parts/device_activation_auth_test.dart

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// -------------------------------------------------------------------------
// Source-contract helpers (mirror the pattern used by
// business_preview_operator_mint_hydration_test.dart)
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

String _extractMethodBody(String source, RegExp signaturePattern) {
  final match = signaturePattern.firstMatch(source);
  if (match == null) {
    fail('Method not found. Pattern: ${signaturePattern.pattern}');
  }
  var i = match.end;
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
        if (parenDepth == 0) break;
      }
    }
    i++;
  }
  if (parenDepth != 0) fail('Unbalanced parens in signature');
  i++;
  while (i < source.length && source[i] != '{') {
    i++;
  }
  final startIdx = i;
  var depth = 0;
  while (i < source.length) {
    final c = source[i];
    if (c == '{') depth++;
    if (c == '}') {
      depth--;
      if (depth == 0) {
        return _stripDartCommentsInBody(
          source.substring(startIdx, i + 1),
        );
      }
    }
    i++;
  }
  fail('Method body unterminated');
}

// -------------------------------------------------------------------------
// Tests
// -------------------------------------------------------------------------

void main() {
  group('_showNewDeviceActivationCodeDialog (company-device create)', () {
    late String source;
    late String body;
    setUpAll(() {
      source = _readSourceOrFail(
        'lib/main_parts/business_home_page_state.dart',
      );
      body = _extractMethodBody(
        source,
        RegExp(
          r'Future<void>\s+_showNewDeviceActivationCodeDialog\s*\(',
        ),
      );
    });

    test(
      'uses resolveCompanyOwnerAuthHeaders (company-session bearer) '
      'and does not call _adminHeaders()',
      () {
        expect(
          RegExp(r'\bresolveCompanyOwnerAuthHeaders\s*\(').hasMatch(body),
          isTrue,
          reason:
              'Company-device create must obtain the company-owner session '
              'bearer via resolveCompanyOwnerAuthHeaders(); the empty '
              '_adminHeaders() call was the direct cause of the field '
              'failure.',
        );
        expect(
          RegExp(r'\b_adminHeaders\s*\(').hasMatch(body),
          isFalse,
          reason:
              'Company-device create must NOT call _adminHeaders() '
              '(returns an empty map post SECURITY-REMOVE-CLIENT-ADMIN-TOKEN-P0-1).',
        );
      },
    );

    test('never constructs an x-admin-token header on this route', () {
      expect(
        RegExp(r'''['"]x-admin-token['"]''', caseSensitive: false)
            .hasMatch(body),
        isFalse,
        reason:
            'Company-device create must never send x-admin-token. '
            'Backend admin-token compatibility is a server-only concern.',
      );
      expect(
        RegExp(r'\bkAdminToken\b').hasMatch(body),
        isFalse,
        reason:
            'kAdminToken is inert in shipped builds, but must not be '
            'referenced from this route either.',
      );
    });

    test(
      'no longer gates the entire method on kReleaseMode; retains '
      'hasCompanyOwnerAuthContext() gate',
      () {
        // The whole-method release-mode block was the reason the field
        // build could never even ATTEMPT the request. The migrated route
        // must be usable in release builds — only a missing company-owner
        // auth context blocks it now.
        expect(
          RegExp(r'\bkReleaseMode\b').hasMatch(body),
          isFalse,
          reason:
              'Company-device create must not be gated by kReleaseMode. '
              'Server-side auth (company-session bearer + exact scope) is '
              'the enforcement point.',
        );
        expect(
          RegExp(r'!\s*hasCompanyOwnerAuthContext\s*\(').hasMatch(body),
          isTrue,
          reason:
              'hasCompanyOwnerAuthContext() must still gate the flow so '
              'a logged-out company cannot even initiate a request.',
        );
      },
    );

    test('inspects Content-Type before jsonDecode (Cloudflare 1101 safety)',
        () {
      // The original code called `jsonDecode(utf8.decode(response.bodyBytes))`
      // unconditionally, which throws when Cloudflare returns an HTML error
      // page (e.g. worker exception 1101). The migrated route MUST branch
      // on Content-Type first.
      expect(
        RegExp(r"response\.headers\[\s*['\x22]content-type['\x22]\s*\]")
            .hasMatch(body),
        isTrue,
        reason:
            'Response must inspect Content-Type before parsing JSON to '
            'avoid throwing on HTML error pages.',
      );
      expect(
        RegExp(r"contains\s*\(\s*['\x22]application/json['\x22]\s*\)")
            .hasMatch(body),
        isTrue,
        reason:
            'Response handling must branch on '
            'content-type.contains("application/json").',
      );
      expect(
        RegExp(r'NON_JSON_RESPONSE').hasMatch(body),
        isTrue,
        reason:
            'Non-JSON responses must emit a controlled diagnostic tag '
            'so field triage can distinguish worker exceptions from '
            'structured API errors.',
      );
    });

    test(
      'emits redacted failure diagnostics — no empty catch (_) {} that '
      'silently swallows errors',
      () {
        // The old code ended with `} catch (_) {}` which is exactly what
        // hid the Cloudflare 1101 failure from field logs. The new code
        // must emit at least ONE redacted diagnostic on the failure path
        // (HTTP_FAIL or TIMEOUT).
        expect(
          RegExp(r'catch\s*\(\s*_\s*\)\s*\{\s*\}').hasMatch(body),
          isFalse,
          reason:
              'Empty `catch (_) {}` blocks are forbidden on this route — '
              'they hide the very failure this blocker fixes.',
        );
        expect(
          RegExp(r'\[PAIR_CODE_CREATE\]\[HTTP_FAIL\]').hasMatch(body) ||
              RegExp(r'\[PAIR_CODE_CREATE\]\[TIMEOUT\]').hasMatch(body),
          isTrue,
          reason:
              'Failure branches must emit redacted diagnostics tagged '
              '[PAIR_CODE_CREATE][HTTP_FAIL] or [PAIR_CODE_CREATE][TIMEOUT].',
        );
        // Redaction rule: the diagnostic must not print the raw error
        // message or the bearer.
        expect(
          RegExp(r'error\.toString\s*\(\s*\)').hasMatch(body),
          isFalse,
          reason:
              'Do not print `error.toString()` — it may contain URL '
              'fragments or transport identifiers.',
        );
        expect(
          RegExp(r'response\.body\b').hasMatch(body),
          isFalse,
          reason:
              'Do not echo response body bytes in diagnostics — they may '
              'be a leaked worker HTML page containing internal ids.',
        );
      },
    );

    test('sends explicit Accept and Content-Type application/json headers',
        () {
      expect(
        RegExp(r"['\x22]Accept['\x22]\s*:\s*['\x22]application/json['\x22]")
            .hasMatch(body),
        isTrue,
        reason:
            'Accept: application/json must be set explicitly (defense in '
            'depth against transparent proxies).',
      );
      expect(
        RegExp(
          r"['\x22]Content-Type['\x22]\s*:\s*['\x22]application/json['\x22]",
        ).hasMatch(body),
        isTrue,
        reason:
            'Content-Type: application/json must be set explicitly on the '
            'outbound POST.',
      );
    });

    test('preserves exact tenant/company query and body scope', () {
      // Server-side auth pins the scope, but the client must still send
      // the explicit scope both in the query and in the JSON body; the
      // helper `_requireAdminOrCompanySessionForExplicitScope` requires it.
      expect(
        RegExp(r'queryParameters\s*:\s*<String,\s*String>\s*\{')
            .hasMatch(body),
        isTrue,
        reason: 'tenant_id/company_id query parameters must remain present.',
      );
      expect(
        RegExp(r"['\x22]tenant_id['\x22]\s*:\s*scope\.tenantId")
            .hasMatch(body),
        isTrue,
      );
      expect(
        RegExp(r"['\x22]company_id['\x22]\s*:\s*scope\.companyId")
            .hasMatch(body),
        isTrue,
      );
    });
  });

  group('_openTemporaryDriverLinkQr (driver-link QR affordance)', () {
    late String source;
    late String body;
    setUpAll(() {
      source = _readSourceOrFail(
        'lib/main_parts/company_driver_management_page_body.dart',
      );
      body = _extractMethodBody(
        source,
        RegExp(r'Future<void>\s+_openTemporaryDriverLinkQr\s*\('),
      );
    });

    test(
      'does not add a new kReleaseMode gate as part of this blocker fix',
      () {
        expect(
          RegExp(r'\bkReleaseMode\b').hasMatch(body),
          isFalse,
          reason:
              'The driver-link QR flow already sends the correct '
              'company-session bearer via createDriverLinkCode; only the '
              'worker route needs repair. No new release-mode gate.',
        );
      },
    );

    test(
      'QR rendering is downstream of a successful createDriverLinkCode(...) '
      'response',
      () {
        // The QR dialog must never be shown when createDriverLinkCode
        // returned null / a non-ok body. Enforce that the call is present
        // and that its response is inspected before UI is opened.
        expect(
          RegExp(r'\bcreateDriverLinkCode\s*\(').hasMatch(body),
          isTrue,
          reason:
              'QR flow must call createDriverLinkCode (which uses '
              'resolveCompanyOwnerAuthHeaders internally, not _adminHeaders).',
        );
        // The dialog-show call site must come AFTER the create call.
        final createIdx = body.indexOf('createDriverLinkCode');
        final showDialogIdx = body.indexOf('SHOW_DIALOG');
        expect(
          showDialogIdx > createIdx && createIdx >= 0,
          isTrue,
          reason:
              'The [DRIVER_LINK_QR][SHOW_DIALOG] diagnostic (which precedes '
              'QR rendering) must fire strictly AFTER createDriverLinkCode '
              'returns.',
        );
      },
    );

    test('does not construct an x-admin-token header on this route', () {
      expect(
        RegExp(r'''['"]x-admin-token['"]''', caseSensitive: false)
            .hasMatch(body),
        isFalse,
      );
      expect(
        RegExp(r'\b_adminHeaders\s*\(').hasMatch(body),
        isFalse,
        reason:
            'The driver-link QR flow must never call _adminHeaders() '
            '(which returns an empty map post ADMIN_TOKEN removal).',
      );
    });
  });

  group('createDriverLinkCode (app_config helper used by QR flow)', () {
    late String source;
    late String body;
    setUpAll(() {
      source = _readSourceOrFail('lib/app_config.dart');
      body = _extractMethodBody(
        source,
        RegExp(
          r'Future<Map<String,\s*dynamic>\?>\s+createDriverLinkCode\s*\(',
        ),
      );
    });

    test('sends company-session bearer via resolveCompanyOwnerAuthHeaders',
        () {
      expect(
        RegExp(r'\bresolveCompanyOwnerAuthHeaders\s*\(').hasMatch(body),
        isTrue,
      );
      expect(
        RegExp(r'\b_adminHeaders\s*\(').hasMatch(body),
        isFalse,
      );
      expect(
        RegExp(r'''['"]x-admin-token['"]''', caseSensitive: false)
            .hasMatch(body),
        isFalse,
      );
    });

    test('emits redacted [CREATE_HTTP_FAIL] diagnostics with masked fields',
        () {
      expect(
        RegExp(r'\[DRIVER_LINK_QR\]\[CREATE_HTTP_FAIL\]').hasMatch(body),
        isTrue,
      );
      // Sensitive fields must be masked out of the body preview.
      expect(
        RegExp(r'"pairing_code"\s*:\s*"\*\*\*"').hasMatch(body),
        isTrue,
        reason: 'pairing_code must be masked out of failure diagnostics.',
      );
      expect(
        RegExp(r'"challenge_id"\s*:\s*"\*\*\*"').hasMatch(body),
        isTrue,
        reason: 'challenge_id must be masked out of failure diagnostics.',
      );
    });
  });
}
