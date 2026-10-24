// PAYMENT-AUTH-P0-1 - Repair in-car payment auth and truthful status.
//
// Covers:
//   1. `resolveInCarPaymentAuthHeaders` (pure/testable logic in
//      `lib/app_config.dart`) - driver-session bearer is attached and no
//      ADMIN_TOKEN / x-admin-token header is ever produced.
//   2. Source-contract on `resolveInCarPaymentAuthHeaders` proving the
//      documented fallback order (driver session -> company-owner session
//      -> none) and the absence of any client ADMIN_TOKEN plumbing.
//   3. Source-contract on
//      `lib/main_parts/ride_receipt_body_state.dart::_showPaymentQr` -
//      opening (or copying) the local EPC QR never marks the receipt
//      sent/paid.
//   4. Source-contract on `_persistInCarPayment` - auth headers are resolved
//      and a missing-auth mode refuses the request before any HTTP call;
//      HTTP 401 on every booking-worker branch is classified into the
//      truthful "sign in again" message; the canonical `paid` status is only
//      applied inside the success path (after backend confirmation), never
//      inside a catch/failure branch, so a failed attempt retains the
//      previous status and a retry cannot duplicate local state.
//
// Pumping the full ride-receipt widget in a widget test is impractical here
// (the state class is ~5k lines and depends on Mapbox/geolocation/PDF/print
// plugins with no test doubles in this repo). Consistent with the existing
// convention in this codebase (see `driver_ride_start_auth_guard_wiring_test.dart`,
// `business_preview_operator_mint_test.dart`, `no_client_admin_token_test.dart`),
// the HTTP-plumbing invariants that are impractical to widget-test are proven
// as source contracts instead.
//
// Run:
//   flutter test test/main_parts/payment_auth_p0_1_test.dart

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_config.dart';
import 'package:fluxidi_tracking/driver_session_store.dart';

ActiveDriverSession _driverSession({String? token}) {
  return ActiveDriverSession(
    driverId: 'driver_alice',
    employeeNumber: '01',
    fullName: 'Alice',
    phone: '',
    loggedInAt: '2027-01-01T00:00:00Z',
    updatedAt: '2027-01-01T00:00:00Z',
    driverSessionToken: token,
  );
}

String _readSourceOrFail(String relativePath) {
  final file = File(relativePath);
  if (!file.existsSync()) fail('Source file not found: $relativePath');
  return file.readAsStringSync();
}

/// Extracts the body of a class-member method starting at [signaturePrefix],
/// using a naive brace counter that ignores braces inside string literals.
/// Mirrors the helper used by
/// `driver_ride_start_auth_guard_wiring_test.dart` /
/// `business_preview_operator_mint_test.dart`.
String _extractMethodBody(
  String source,
  String signaturePrefix, {
  String? relativePath,
}) {
  final startIdx = source.indexOf(signaturePrefix);
  if (startIdx < 0) {
    fail(
      'Could not locate signature "$signaturePrefix" in '
      '${relativePath ?? "source"} - the PAYMENT-AUTH-P0-1 wiring may have '
      'been renamed or removed.',
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
    // Skip `//` line comments outside of strings: a single unmatched
    // apostrophe in a doc/inline comment (e.g. "worker's") would otherwise
    // desync the naive quote tracker for the remainder of the method.
    if (ch == '/' && k + 1 < source.length && source[k + 1] == '/') {
      final newlineIdx = source.indexOf('\n', k);
      k = (newlineIdx < 0 ? source.length : newlineIdx) - 1;
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

String _stripLineComments(String source) {
  return source
      .split('\n')
      .map((line) {
        final commentIdx = line.indexOf('//');
        if (commentIdx < 0) return line;
        return line.substring(0, commentIdx);
      })
      .join('\n');
}

void main() {
  tearDown(() {
    activeDriverSessionNotifier.value = null;
  });

  group('resolveInCarPaymentAuthHeaders - driver-session branch (real logic)', () {
    test('attaches Authorization: Bearer <driver token>; mode=driverSession', () async {
      activeDriverSessionNotifier.value = _driverSession(token: 'dst_alice_123');

      final result = await resolveInCarPaymentAuthHeaders();

      expect(result.mode, InCarPaymentAuthMode.driverSession);
      expect(result.headers['Authorization'], 'Bearer dst_alice_123');
      expect(result.headers['Content-Type'], 'application/json');
    });

    test('never sends x-admin-token / ADMIN_TOKEN when a driver session is active', () async {
      activeDriverSessionNotifier.value = _driverSession(token: 'dst_alice_123');

      final result = await resolveInCarPaymentAuthHeaders();

      final lowerKeys = result.headers.keys.map((k) => k.toLowerCase());
      for (final forbidden in const [
        'x-admin-token',
        'x-fluxidi-admin',
        'admin-token',
      ]) {
        expect(
          lowerKeys.contains(forbidden),
          isFalse,
          reason:
              'resolveInCarPaymentAuthHeaders must never send "$forbidden".',
        );
      }
    });

    test('blank/whitespace-only driver token is treated as absent (falls through)', () async {
      activeDriverSessionNotifier.value = _driverSession(token: '   ');

      final result = await resolveInCarPaymentAuthHeaders();

      // No driver session token usable; falls through to the company-owner
      // resolution path (which returns `none` with no persisted company
      // session in this bare test environment) rather than sending a blank
      // bearer.
      expect(result.mode, isNot(InCarPaymentAuthMode.driverSession));
      expect(result.headers.containsKey('Authorization'), isFalse);
    });

    test('json:false omits Content-Type but still attaches the bearer', () async {
      activeDriverSessionNotifier.value = _driverSession(token: 'dst_alice_123');

      final result = await resolveInCarPaymentAuthHeaders(json: false);

      expect(result.mode, InCarPaymentAuthMode.driverSession);
      expect(result.headers['Authorization'], 'Bearer dst_alice_123');
      expect(result.headers.containsKey('Content-Type'), isFalse);
    });
  });

  group('InCarPaymentAuthMode enum contract', () {
    test('has exactly the documented three values', () {
      expect(InCarPaymentAuthMode.values, hasLength(3));
      expect(
        InCarPaymentAuthMode.values,
        containsAll(const <InCarPaymentAuthMode>[
          InCarPaymentAuthMode.driverSession,
          InCarPaymentAuthMode.companySession,
          InCarPaymentAuthMode.none,
        ]),
      );
    });
  });

  group('resolveInCarPaymentAuthHeaders - source contract (app_config.dart)', () {
    const relativePath = 'lib/app_config.dart';
    late String src;

    setUpAll(() {
      src = _readSourceOrFail(relativePath);
    });

    test('prefers driver session, then company-owner session, then none - no ADMIN_TOKEN', () {
      final body = _extractMethodBody(
        src,
        'Future<InCarPaymentAuthHeaders> resolveInCarPaymentAuthHeaders(',
        relativePath: relativePath,
      );
      final driverIdx = body.indexOf('activeDriverSessionNotifier.value');
      final companyIdx = body.indexOf('resolveCompanyOwnerAuthHeaders(');
      final companyModeCheckIdx = body.indexOf(
        'companyAuth.mode == CompanyOwnerAuthMode.companySession',
      );
      final noneIdx = body.indexOf('InCarPaymentAuthMode.none');
      expect(driverIdx, greaterThanOrEqualTo(0),
          reason: 'Must check the active driver session first.');
      expect(companyIdx, greaterThan(driverIdx),
          reason:
              'Company-owner auth must only be attempted after the driver '
              'session check fails, never in parallel/first.');
      expect(companyModeCheckIdx, greaterThan(companyIdx));
      expect(noneIdx, greaterThan(companyModeCheckIdx),
          reason:
              'The `none` fallback must be the last resort, after both '
              'driver and company session resolution failed.');
      // Never silently fall back to an unauthenticated request by omission -
      // the explicit `none` mode must always be returned, and no admin token
      // plumbing may reappear in this function.
      for (final forbidden in const [
        'kAdminToken',
        "'x-admin-token'",
        '"x-admin-token"',
        'ADMIN_TOKEN',
      ]) {
        expect(body.contains(forbidden), isFalse,
            reason:
                'resolveInCarPaymentAuthHeaders must not reference "$forbidden".');
      }
    });
  });

  group('ride_receipt_body_state.dart - truthful QR dialog (source contract)', () {
    const relativePath = 'lib/main_parts/ride_receipt_body_state.dart';
    late String src;

    setUpAll(() {
      src = _readSourceOrFail(relativePath);
    });

    test('_showPaymentQr never calls _markPaymentRequestSent (opening/copying QR is not a payment confirmation)', () {
      final body = _extractMethodBody(
        src,
        '  void _showPaymentQr(BuildContext context) {',
        relativePath: relativePath,
      );
      expect(
        body.contains('_markPaymentRequestSent('),
        isFalse,
        reason:
            'Opening or copying the local EPC QR must never optimistically '
            'mark the receipt "sent"/paid. Payment state may only change '
            'after an authoritative backend mark-paid confirmation.',
      );
      expect(
        body,
        contains("_receiptText('qrReadyToScan')"),
        reason:
            'The QR dialog must show a truthful "ready to scan / confirm '
            'below" message instead of implying payment already happened.',
      );
      // Manual confirmation must remain manual: no automatic bank-transfer
      // verification claim anywhere in this dialog.
      expect(
        body.toLowerCase().contains('automatically verified'),
        isFalse,
      );
    });
  });

  group('_persistInCarPayment - auth resolution + truthful status (source contract)', () {
    const relativePath = 'lib/main_parts/ride_receipt_body_state.dart';
    late String src;
    late String body;

    setUpAll(() {
      src = _readSourceOrFail(relativePath);
      body = _extractMethodBody(
        src,
        '  Future<void> _persistInCarPayment({',
        relativePath: relativePath,
      );
    });

    test('resolves auth headers once and refuses silently-unauthenticated requests', () {
      final resolveIdx = body.indexOf('resolveInCarPaymentAuthHeaders()');
      final noneCheckIdx = body.indexOf('InCarPaymentAuthMode.none');
      final snackbarIdx = body.indexOf("_receiptText('paymentAuthRequired')");
      final legBranchIdx = body.indexOf('if (useLegBookingPaymentPath) {');
      expect(resolveIdx, greaterThanOrEqualTo(0),
          reason:
              '_persistInCarPayment must call resolveInCarPaymentAuthHeaders() '
              'to obtain the driver/company-owner bearer.');
      expect(noneCheckIdx, greaterThan(resolveIdx));
      expect(snackbarIdx, greaterThan(noneCheckIdx));
      expect(
        snackbarIdx,
        lessThan(legBranchIdx),
        reason:
            'The missing-auth early return must happen BEFORE any '
            'booking/leg/trip payment branch runs, so no HTTP request is '
            'ever sent without a resolved bearer.',
      );
    });

    test('every booking-worker HTTP branch classifies HTTP 401 into _InCarPaymentAuthRequiredException', () {
      final occurrences = RegExp(
        'res.statusCode == 401\\)\\s*\\{\\s*\\n\\s*throw const _InCarPaymentAuthRequiredException\\(\\);',
      ).allMatches(body).length;
      expect(
        occurrences,
        greaterThanOrEqualTo(2),
        reason:
            'Both the leg-payment and booking-payment branches (booking-'
            'worker routes) must classify HTTP 401 into '
            '_InCarPaymentAuthRequiredException so the UI can show a '
            'truthful "sign in again" message instead of a generic failure.',
      );
    });

    test('auth failures surface the truthful paymentAuthRequired message, not a generic failure message', () {
      final authRequiredOccurrences = RegExp(
        r"_receiptText\('paymentAuthRequired'\)",
      ).allMatches(body).length;
      // Once for the pre-flight missing-auth refusal, and once per
      // booking-worker branch's isAuthFailure catch handling (leg + booking).
      expect(authRequiredOccurrences, greaterThanOrEqualTo(3));
      expect(body, contains('isAuthFailure'));
    });

    test('canonical paid status is set ONLY inside success paths, never inside a catch/failure branch', () {
      // Split on the catch-block openers used throughout this method and
      // verify none of the resulting failure-branch chunks assign the
      // canonical paid status. This proves a failed attempt (401, network,
      // or any other HTTP/backend error) always retains/restores the
      // previous canonical status rather than fabricating a paid transition,
      // and that a retry after failure cannot duplicate local state (the
      // paid flag is set at most once, from the success path only).
      final chunks = body.split('} catch (err) {');
      expect(
        chunks.length,
        greaterThanOrEqualTo(3),
        reason:
            'Expected at least 3 catch blocks (leg / trip / booking payment '
            'branches).',
      );
      for (var i = 1; i < chunks.length; i++) {
        final failureChunk = chunks[i];
        // Stop at the next branch's `try {` (start of the following
        // success path) so we only inspect the failure branch itself.
        final nextTryIdx = failureChunk.indexOf('    try {');
        final scoped = nextTryIdx > 0
            ? failureChunk.substring(0, nextTryIdx)
            : failureChunk;
        expect(
          scoped.contains('_paymentStatus = _ReceiptPaymentStatus.paid'),
          isFalse,
          reason:
              'A catch/failure branch must never set _paymentStatus to paid. '
              'Failure chunk #$i: ${scoped.substring(0, scoped.length.clamp(0, 200))}',
        );
      }
    });

    test('the paid status assignment always follows the HTTP response validation in each branch', () {
      // For each of the three booking-worker/tracking-worker branches, the
      // setState(paid) call must occur AFTER the branch's own HTTP status
      // check, i.e. only once the backend has authoritatively confirmed the
      // payment - never optimistically before the request completes.
      final legStart = body.indexOf('if (useLegBookingPaymentPath) {');
      final tripStart = body.indexOf('if (useTripPaymentPath) {');
      final bookingStart = body.indexOf(
        '// Booking-level payment (single-leg planned / direct receipts)',
      );
      expect(legStart, greaterThanOrEqualTo(0));
      expect(tripStart, greaterThan(legStart));
      expect(bookingStart, greaterThan(tripStart));

      final legSlice = body.substring(legStart, tripStart);
      final tripSlice = body.substring(tripStart, bookingStart);
      final bookingSlice = body.substring(bookingStart);

      for (final entry in <String, String>{
        'leg': legSlice,
        'trip': tripSlice,
        'booking': bookingSlice,
      }.entries) {
        final slice = entry.value;
        final httpCallIdx = slice.indexOf('await http');
        final paidIdx = slice.indexOf(
          '_paymentStatus = _ReceiptPaymentStatus.paid',
        );
        expect(httpCallIdx, greaterThanOrEqualTo(0),
            reason: '${entry.key} branch must issue an HTTP request.');
        expect(
          paidIdx,
          greaterThan(httpCallIdx),
          reason:
              '${entry.key} branch must only set the paid status AFTER the '
              'HTTP call, i.e. after authoritative backend confirmation.',
        );
      }
    });

    test('booking and leg branches use the resolved auth headers, not a client ADMIN_TOKEN', () {
      final legStart = body.indexOf('if (useLegBookingPaymentPath) {');
      final tripStart = body.indexOf('if (useTripPaymentPath) {');
      final bookingStart = body.indexOf(
        '// Booking-level payment (single-leg planned / direct receipts)',
      );
      final legSlice = body.substring(legStart, tripStart);
      final bookingSlice = body.substring(bookingStart);
      for (final entry in <String, String>{
        'leg': legSlice,
        'booking': bookingSlice,
      }.entries) {
        expect(
          entry.value.contains('headers: headers,'),
          isTrue,
          reason:
              '${entry.key} branch must post with the resolved '
              '`headers` (driver/company bearer), not a locally-declared '
              'admin-token header map.',
        );
        expect(
          entry.value.contains('kAdminToken'),
          isFalse,
          reason:
              '${entry.key} branch (booking-worker route) must not reference '
              'kAdminToken - that plumbing was removed by PAYMENT-AUTH-P0-1.',
        );
      }
    });
  });

  group('no stray ADMIN_TOKEN reintroduced in the payment-auth surfaces', () {
    test('lib/app_config.dart resolveInCarPaymentAuthHeaders + resolveCompanyOwnerAuthHeaders stay ADMIN_TOKEN-free', () {
      final src = _readSourceOrFail('lib/app_config.dart');
      final resolveInCar = _extractMethodBody(
        src,
        'Future<InCarPaymentAuthHeaders> resolveInCarPaymentAuthHeaders(',
      );
      final resolveCompany = _extractMethodBody(
        src,
        'Future<CompanyOwnerAuthHeaders> resolveCompanyOwnerAuthHeaders(',
      );
      for (final fn in <String, String>{
        'resolveInCarPaymentAuthHeaders': resolveInCar,
        'resolveCompanyOwnerAuthHeaders': resolveCompany,
      }.entries) {
        final stripped = _stripLineComments(fn.value);
        for (final forbidden in const [
          'kAdminToken',
          "'x-admin-token'",
          '"x-admin-token"',
        ]) {
          expect(
            stripped.contains(forbidden),
            isFalse,
            reason: '${fn.key} must not contain "$forbidden".',
          );
        }
      }
    });
  });
}
