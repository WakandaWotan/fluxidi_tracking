// SECURITY-REMOVE-CLIENT-ADMIN-TOKEN-P0-1 (Field Failure Fix, Commit 3)
//
// Tests for the Flutter operator-mint integration:
//
//   1. `mintOperatorDriverSession` (pure HTTP helper) — happy path, all
//      documented failure modes, no ADMIN_TOKEN header, no client-supplied
//      scope trust.
//   2. `ActiveDriverSession.sessionOrigin` / `isOperatorMintedSession`
//      classification.
//   3. Source-contract on
//      `lib/main_parts/business_home_page_state.dart::_persistAndOpenBusinessDriverPreview`
//      — the mint call precedes the cockpit-open call, on failure the
//      cockpit is NOT opened, and no ADMIN_TOKEN plumbing is reintroduced.
//   4. Source-contract on
//      `lib/driver_session_store.dart::setOperatorMintedDriverSessionInMemory`
//      — the hydration path is memory-only (no file writes, no scoped-file
//      helpers, no `saveSession`).
//
// Run:
//   flutter test test/main_parts/business_preview_operator_mint_test.dart

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_config.dart';
import 'package:fluxidi_tracking/driver_session_store.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const String _fakeBookingBaseUrl =
    'https://fluxidi-booking-api.fluxidi.workers.dev';
const String _companyToken = 'cst_test_company_123';

Map<String, dynamic> _happyResponseBody({
  String token = 'dst_op_ABC123',
  String expiresAt = '2027-01-01T12:00:00.000Z',
  int expiresIn = 3600,
  String tenantId = 'tenant_a',
  String companyId = 'company_a',
  String driverId = 'driver_wakanda',
  String driverName = 'Wakanda',
  String? assignedVehicleId = 'veh_1',
}) {
  return <String, dynamic>{
    'ok': true,
    'driver_session_token': token,
    'issued_at': '2027-01-01T11:00:00.000Z',
    'expires_at': expiresAt,
    'expires_in': expiresIn,
    'origin': 'operator_mint',
    'link_method': 'operator_mint',
    'role': 'driver',
    'tenant_id': tenantId,
    'company_id': companyId,
    'driver': <String, dynamic>{
      'driver_id': driverId,
      'driver_name': driverName,
      if (assignedVehicleId != null) 'assigned_vehicle_id': assignedVehicleId,
    },
  };
}

void main() {
  group('mintOperatorDriverSession — happy path', () {
    test('returns OperatorMintedDriverSession with all fields populated', () async {
      http.Request? captured;
      final client = MockClient((request) async {
        captured = request;
        return http.Response(jsonEncode(_happyResponseBody()), 200);
      });

      final result = await mintOperatorDriverSession(
        bookingBaseUrl: _fakeBookingBaseUrl,
        companySessionToken: _companyToken,
        targetDriverId: 'driver_wakanda',
        tenantId: 'tenant_a',
        companyId: 'company_a',
        client: client,
      );

      expect(result.driverSessionToken, 'dst_op_ABC123');
      expect(result.driverSessionExpiresAtUtc, '2027-01-01T12:00:00.000Z');
      expect(result.expiresInSeconds, 3600);
      expect(result.tenantId, 'tenant_a');
      expect(result.companyId, 'company_a');
      expect(result.driverId, 'driver_wakanda');
      expect(result.driverName, 'Wakanda');
      expect(result.assignedVehicleId, 'veh_1');
      expect(result.origin, 'operator_mint');
      expect(result.linkMethod, 'operator_mint');
      expect(result.issuedAtUtc, '2027-01-01T11:00:00.000Z');

      expect(captured, isNotNull);
      expect(captured!.method, 'POST');
      expect(
        captured!.url.toString(),
        '$_fakeBookingBaseUrl/driver/session/mint-for-operator',
      );
    });

    test('sends only Authorization: Bearer <company_session_token>', () async {
      http.Request? captured;
      final client = MockClient((request) async {
        captured = request;
        return http.Response(jsonEncode(_happyResponseBody()), 200);
      });

      await mintOperatorDriverSession(
        bookingBaseUrl: _fakeBookingBaseUrl,
        companySessionToken: _companyToken,
        targetDriverId: 'driver_wakanda',
        tenantId: 'tenant_a',
        companyId: 'company_a',
        client: client,
      );

      final headers = captured!.headers;
      expect(headers['authorization'], 'Bearer $_companyToken');
      // Content-Type is set on the request builder (via companyBearerHeaders
      // with json:true).
      expect(headers['content-type']?.toLowerCase(), contains('application/json'));
      // Regression guard: no admin plumbing.
      for (final forbidden in const [
        'x-admin-token',
        'X-Admin-Token',
        'admin-token',
        'x-fluxidi-admin',
      ]) {
        expect(headers.keys.map((k) => k.toLowerCase()).contains(forbidden.toLowerCase()),
            isFalse,
            reason:
                'mintOperatorDriverSession must not send $forbidden — company session is the sole credential.');
      }
    });

    test('body carries target_driver_id and echoes scope; no admin flags', () async {
      Map<String, dynamic>? capturedBody;
      final client = MockClient((request) async {
        capturedBody = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(jsonEncode(_happyResponseBody()), 200);
      });

      await mintOperatorDriverSession(
        bookingBaseUrl: _fakeBookingBaseUrl,
        companySessionToken: _companyToken,
        targetDriverId: 'driver_wakanda',
        tenantId: 'tenant_a',
        companyId: 'company_a',
        client: client,
      );

      expect(capturedBody, isNotNull);
      expect(capturedBody!['target_driver_id'], 'driver_wakanda');
      expect(capturedBody!['tenant_id'], 'tenant_a');
      expect(capturedBody!['company_id'], 'company_a');
      // Body must not carry any admin toggle.
      expect(capturedBody!.containsKey('admin'), isFalse);
      expect(capturedBody!.containsKey('admin_token'), isFalse);
      expect(capturedBody!.containsKey('x_admin_token'), isFalse);
    });

    test('body omits tenant/company keys when caller passes null/empty', () async {
      Map<String, dynamic>? capturedBody;
      final client = MockClient((request) async {
        capturedBody = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(jsonEncode(_happyResponseBody()), 200);
      });

      await mintOperatorDriverSession(
        bookingBaseUrl: _fakeBookingBaseUrl,
        companySessionToken: _companyToken,
        targetDriverId: 'driver_wakanda',
        tenantId: '',
        companyId: null,
        client: client,
      );

      expect(capturedBody!.containsKey('tenant_id'), isFalse);
      expect(capturedBody!.containsKey('company_id'), isFalse);
      expect(capturedBody!['target_driver_id'], 'driver_wakanda');
    });
  });

  group('mintOperatorDriverSession — failure classification', () {
    test('empty company session token → OperatorMintException(reason=unauthorized)',
        () async {
      final client = MockClient((request) async {
        fail('HTTP call must not happen when company token is empty');
      });
      await expectLater(
        () => mintOperatorDriverSession(
          bookingBaseUrl: _fakeBookingBaseUrl,
          companySessionToken: '   ',
          targetDriverId: 'driver_wakanda',
          client: client,
        ),
        throwsA(isA<OperatorMintException>()
            .having((e) => e.reason, 'reason', 'unauthorized')),
      );
    });

    test('empty target_driver_id → OperatorMintException(reason=invalid_body)',
        () async {
      final client = MockClient((request) async {
        fail('HTTP call must not happen when target_driver_id is empty');
      });
      await expectLater(
        () => mintOperatorDriverSession(
          bookingBaseUrl: _fakeBookingBaseUrl,
          companySessionToken: _companyToken,
          targetDriverId: '',
          client: client,
        ),
        throwsA(isA<OperatorMintException>()
            .having((e) => e.reason, 'reason', 'invalid_body')),
      );
    });

    test('HTTP 401 → OperatorMintException(reason=unauthorized, http=401)', () async {
      final client = MockClient((request) async {
        return http.Response('{"ok":false,"error":"unauthorized"}', 401);
      });
      try {
        await mintOperatorDriverSession(
          bookingBaseUrl: _fakeBookingBaseUrl,
          companySessionToken: _companyToken,
          targetDriverId: 'driver_wakanda',
          client: client,
        );
        fail('expected OperatorMintException');
      } on OperatorMintException catch (e) {
        expect(e.reason, 'unauthorized');
        expect(e.httpStatus, 401);
      }
    });

    test('HTTP 403 (generic) → forbidden', () async {
      final client = MockClient((request) async {
        return http.Response('{"ok":false,"error":"forbidden"}', 403);
      });
      try {
        await mintOperatorDriverSession(
          bookingBaseUrl: _fakeBookingBaseUrl,
          companySessionToken: _companyToken,
          targetDriverId: 'driver_wakanda',
          client: client,
        );
        fail('expected OperatorMintException');
      } on OperatorMintException catch (e) {
        expect(e.reason, 'forbidden');
        expect(e.httpStatus, 403);
        expect(e.errorCode, 'forbidden');
      }
    });

    test('HTTP 403 driver_inactive → OperatorMintException(reason=driver_inactive)',
        () async {
      final client = MockClient((request) async {
        return http.Response('{"ok":false,"error":"driver_inactive"}', 403);
      });
      try {
        await mintOperatorDriverSession(
          bookingBaseUrl: _fakeBookingBaseUrl,
          companySessionToken: _companyToken,
          targetDriverId: 'driver_wakanda',
          client: client,
        );
        fail('expected OperatorMintException');
      } on OperatorMintException catch (e) {
        expect(e.reason, 'driver_inactive');
        expect(e.httpStatus, 403);
        expect(e.errorCode, 'driver_inactive');
      }
    });

    test('HTTP 404 → driver_not_found', () async {
      final client = MockClient((request) async {
        return http.Response('{"ok":false,"error":"driver_not_found"}', 404);
      });
      try {
        await mintOperatorDriverSession(
          bookingBaseUrl: _fakeBookingBaseUrl,
          companySessionToken: _companyToken,
          targetDriverId: 'unknown_driver',
          client: client,
        );
        fail('expected OperatorMintException');
      } on OperatorMintException catch (e) {
        expect(e.reason, 'driver_not_found');
        expect(e.httpStatus, 404);
      }
    });

    test('HTTP 400 → invalid_body', () async {
      final client = MockClient((request) async {
        return http.Response('{"ok":false,"error":"invalid_driver_id"}', 400);
      });
      try {
        await mintOperatorDriverSession(
          bookingBaseUrl: _fakeBookingBaseUrl,
          companySessionToken: _companyToken,
          targetDriverId: 'driver_wakanda',
          client: client,
        );
        fail('expected OperatorMintException');
      } on OperatorMintException catch (e) {
        expect(e.reason, 'invalid_body');
        expect(e.httpStatus, 400);
      }
    });

    test('HTTP 500 mint_failed → mint_failed', () async {
      final client = MockClient((request) async {
        return http.Response('{"ok":false,"error":"mint_failed"}', 500);
      });
      try {
        await mintOperatorDriverSession(
          bookingBaseUrl: _fakeBookingBaseUrl,
          companySessionToken: _companyToken,
          targetDriverId: 'driver_wakanda',
          client: client,
        );
        fail('expected OperatorMintException');
      } on OperatorMintException catch (e) {
        expect(e.reason, 'mint_failed');
        expect(e.httpStatus, 500);
      }
    });

    test('HTTP 502 → server_error', () async {
      final client = MockClient((request) async {
        return http.Response('bad gateway', 502);
      });
      try {
        await mintOperatorDriverSession(
          bookingBaseUrl: _fakeBookingBaseUrl,
          companySessionToken: _companyToken,
          targetDriverId: 'driver_wakanda',
          client: client,
        );
        fail('expected OperatorMintException');
      } on OperatorMintException catch (e) {
        expect(e.reason, 'server_error');
        expect(e.httpStatus, 502);
      }
    });

    test('200 with malformed body → invalid_response', () async {
      final client = MockClient((request) async {
        return http.Response('not json at all', 200);
      });
      try {
        await mintOperatorDriverSession(
          bookingBaseUrl: _fakeBookingBaseUrl,
          companySessionToken: _companyToken,
          targetDriverId: 'driver_wakanda',
          client: client,
        );
        fail('expected OperatorMintException');
      } on OperatorMintException catch (e) {
        expect(e.reason, 'invalid_response');
      }
    });

    test('200 with ok:true but missing driver_session_token → invalid_response',
        () async {
      final client = MockClient((request) async {
        return http.Response(
          jsonEncode(<String, dynamic>{
            'ok': true,
            'expires_at': '2027-01-01T12:00:00.000Z',
            'driver': <String, dynamic>{'driver_id': 'driver_wakanda'},
          }),
          200,
        );
      });
      try {
        await mintOperatorDriverSession(
          bookingBaseUrl: _fakeBookingBaseUrl,
          companySessionToken: _companyToken,
          targetDriverId: 'driver_wakanda',
          client: client,
        );
        fail('expected OperatorMintException');
      } on OperatorMintException catch (e) {
        expect(e.reason, 'invalid_response');
      }
    });

    test('200 with ok:false → invalid_response (server contract violation)', () async {
      final client = MockClient((request) async {
        return http.Response('{"ok":false}', 200);
      });
      try {
        await mintOperatorDriverSession(
          bookingBaseUrl: _fakeBookingBaseUrl,
          companySessionToken: _companyToken,
          targetDriverId: 'driver_wakanda',
          client: client,
        );
        fail('expected OperatorMintException');
      } on OperatorMintException catch (e) {
        expect(e.reason, 'invalid_response');
      }
    });

    test('network exception → OperatorMintException(reason=network)', () async {
      final client = MockClient((request) async {
        throw const SocketException('lookup failed');
      });
      try {
        await mintOperatorDriverSession(
          bookingBaseUrl: _fakeBookingBaseUrl,
          companySessionToken: _companyToken,
          targetDriverId: 'driver_wakanda',
          client: client,
        );
        fail('expected OperatorMintException');
      } on OperatorMintException catch (e) {
        expect(e.reason, 'network');
      }
    });

    test('timeout → OperatorMintException(reason=timeout)', () async {
      final client = MockClient((request) async {
        // Never completes within the injected timeout.
        await Future<void>.delayed(const Duration(seconds: 5));
        return http.Response('{"ok":true}', 200);
      });
      try {
        await mintOperatorDriverSession(
          bookingBaseUrl: _fakeBookingBaseUrl,
          companySessionToken: _companyToken,
          targetDriverId: 'driver_wakanda',
          client: client,
          timeout: const Duration(milliseconds: 20),
        );
        fail('expected OperatorMintException');
      } on OperatorMintException catch (e) {
        expect(e.reason, 'timeout');
      }
    });
  });

  group('SessionOrigin classification', () {
    ActiveDriverSession session(String? linkMethod) {
      return ActiveDriverSession(
        driverId: 'driver_x',
        employeeNumber: '01',
        fullName: 'X',
        phone: '',
        loggedInAt: '2027-01-01T00:00:00Z',
        updatedAt: '2027-01-01T00:00:00Z',
        linkMethod: linkMethod,
      );
    }

    test("linkMethod='operator_mint' → SessionOrigin.operatorMint", () {
      final s = session('operator_mint');
      expect(s.sessionOrigin, SessionOrigin.operatorMint);
      expect(s.isOperatorMintedSession, isTrue);
      expect(s.isCompanyAdminDriverViewSession, isFalse);
      expect(s.isStandaloneLoginSession, isFalse);
      expect(s.sessionMode, 'business_driver_view_minted');
    });

    test("linkMethod='company_admin_driver_view' → companyAdminDriverView", () {
      final s = session('company_admin_driver_view');
      expect(s.sessionOrigin, SessionOrigin.companyAdminDriverView);
      expect(s.isOperatorMintedSession, isFalse);
      expect(s.isCompanyAdminDriverViewSession, isTrue);
      expect(s.sessionMode, 'business_driver_view');
    });

    test("linkMethod='standalone_driver' → standaloneLogin", () {
      final s = session('standalone_driver');
      expect(s.sessionOrigin, SessionOrigin.standaloneLogin);
      expect(s.isStandaloneLoginSession, isTrue);
      expect(s.sessionMode, 'standalone_driver');
    });

    test("linkMethod=null → unknown", () {
      final s = session(null);
      expect(s.sessionOrigin, SessionOrigin.unknown);
      expect(s.isOperatorMintedSession, isFalse);
      expect(s.isCompanyAdminDriverViewSession, isFalse);
      expect(s.isStandaloneLoginSession, isFalse);
      expect(s.sessionMode, 'standalone_driver');
    });

    test('kOperatorMintDriverLinkMethod matches worker record shape', () {
      expect(kOperatorMintDriverLinkMethod, 'operator_mint');
    });
  });

  // ---- Source-contract tests ---------------------------------------------

  String readSourceOrFail(String relativePath) {
    final file = File(relativePath);
    if (!file.existsSync()) fail('Source file not found: $relativePath');
    return file.readAsStringSync();
  }

  String extractMethodBody(String source, String signaturePrefix,
      {String? relativePath}) {
    final startIdx = source.indexOf(signaturePrefix);
    if (startIdx < 0) {
      fail(
        'Could not locate signature "$signaturePrefix" in ${relativePath ?? "source"} — '
        'the SECURITY-REMOVE-CLIENT-ADMIN-TOKEN-P0-1 (Commit 3) wiring may '
        'have been renamed or removed.',
      );
    }
    final bodyOpenPattern = RegExp(r'\)\s*(?:async\s*)?\{');
    final bodyOpenMatch =
        bodyOpenPattern.firstMatch(source.substring(startIdx));
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

  group('business preview wiring — _persistAndOpenBusinessDriverPreview', () {
    const relativePath = 'lib/main_parts/business_home_page_state.dart';
    late String src;

    setUpAll(() {
      src = readSourceOrFail(relativePath);
    });

    test('mints operator session BEFORE opening cockpit; refuses on failure',
        () {
      final body = extractMethodBody(
        src,
        '  Future<void> _persistAndOpenBusinessDriverPreview(',
        relativePath: relativePath,
      );
      final mintIdx = body.indexOf('_mintOperatorDriverSessionForPreview(');
      final cockpitIdx = body.indexOf('_openBusinessDriverCockpitHome(');
      expect(
        mintIdx,
        greaterThanOrEqualTo(0),
        reason:
            '_persistAndOpenBusinessDriverPreview must call '
            '_mintOperatorDriverSessionForPreview before opening the cockpit.',
      );
      expect(
        cockpitIdx,
        greaterThan(mintIdx),
        reason:
            'Cockpit push must happen AFTER the mint call. Otherwise the '
            'business-preview surface can enter driver-lifecycle mutations '
            'without a real bearer.',
      );
      // Must abort on null (mint failure) before opening the cockpit.
      expect(
        body,
        contains('if (minted == null) return;'),
        reason:
            'On mint failure the cockpit must NOT open. Field failure fix '
            'requires deterministic early return.',
      );
    });

    test('_mintOperatorDriverSessionForPreview uses company session bearer, '
        'hydrates in-memory only, shows snackbar on failure', () {
      final body = extractMethodBody(
        src,
        '  Future<OperatorMintedDriverSession?> _mintOperatorDriverSessionForPreview(',
        relativePath: relativePath,
      );
      for (final marker in const [
        'activeCompanySessionNotifier.value',
        'companySessionToken',
        'mintOperatorDriverSession(',
        'setOperatorMintedDriverSessionInMemory(',
        'OperatorMintException',
        '_showOperatorMintFailureSnackbar(',
        "linkMethod: kOperatorMintDriverLinkMethod",
      ]) {
        expect(body, contains(marker),
            reason:
                '_mintOperatorDriverSessionForPreview must include "$marker" '
                'to satisfy the operator-mint contract.');
      }
      // NEVER reconstruct any admin plumbing.
      for (final forbidden in const [
        'admin: true',
        'kAdminToken',
        "'x-admin-token'",
        '"x-admin-token"',
      ]) {
        expect(body.contains(forbidden), isFalse,
            reason:
                '_mintOperatorDriverSessionForPreview must NOT reintroduce '
                '"$forbidden".');
      }
    });

    test('no ADMIN_TOKEN / kAdminToken / x-admin-token in business_home_page_state.dart',
        () {
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
        expect(withoutLineComments.contains(forbidden), isFalse,
            reason:
                'business_home_page_state.dart must not restore ADMIN_TOKEN '
                'plumbing; found "$forbidden".');
      }
    });
  });

  group('DriverSessionStore.setOperatorMintedDriverSessionInMemory — no persist',
      () {
    const relativePath = 'lib/driver_session_store.dart';
    late String src;

    setUpAll(() {
      src = readSourceOrFail(relativePath);
    });

    test('sets notifier + clears cache and does NOTHING else', () {
      final body = extractMethodBody(
        src,
        '  void setOperatorMintedDriverSessionInMemory(ActiveDriverSession session)',
        relativePath: relativePath,
      );
      expect(body, contains('activeDriverSessionNotifier.value = session'));
      expect(body, contains('_cache = null'));
      expect(body, contains("_cacheScopeKey = ''"));
      // MUST NOT write anywhere to disk in this method body.
      for (final forbidden in const [
        'writeAsString(',
        '_scopedFile(',
        '_writeSessionAtScope(',
        'saveSession(',
        'saveStandaloneScopePointer(',
        'File(',
      ]) {
        expect(body.contains(forbidden), isFalse,
            reason:
                'setOperatorMintedDriverSessionInMemory MUST be memory-only; '
                'found "$forbidden". The minted bearer must never survive an '
                'app restart.');
      }
      // Diagnostic tag must carry origin=operator_mint.
      expect(body, contains('origin=operator_mint'));
    });

    test('setBusinessDriverViewSessionInMemory remains present (no regression)',
        () {
      expect(
        src,
        contains('void setBusinessDriverViewSessionInMemory('),
        reason:
            'The legacy business-preview in-memory hydration must remain — '
            'Commit 3 only ADDS the operator-mint path.',
      );
    });
  });
}
