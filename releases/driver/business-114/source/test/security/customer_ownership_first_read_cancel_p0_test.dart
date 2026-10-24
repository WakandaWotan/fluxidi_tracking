// CUSTOMER BOOKING AUTH P0 — Flutter source-contract tests.
//
// Proves protected customer booking read/cancel surfaces:
//   * use CustomerSessionStore / Bearer via _customerSessionBearerHeaders
//   * use _customerCanonicalBookingGetUri (no conflicting tenant/company query)
//   * prefer canonical booking id
//   * disable cancel while using local cache
//   * never mark cancelled locally before server acknowledgement
//
// These are static source-contract assertions (pages are `part of` main.dart).

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String path) {
  final file = File(path);
  if (!file.existsSync()) {
    throw StateError('Missing $path');
  }
  return file.readAsStringSync();
}

String _extractMethodBody(String source, RegExp signaturePattern) {
  final match = signaturePattern.firstMatch(source);
  if (match == null) {
    throw StateError('Method not found: ${signaturePattern.pattern}');
  }
  final openBrace = source.indexOf('{', match.end - 1);
  if (openBrace < 0) {
    throw StateError('No opening brace for ${signaturePattern.pattern}');
  }
  var depth = 0;
  for (var i = openBrace; i < source.length; i++) {
    final ch = source[i];
    if (ch == '{') depth++;
    if (ch == '}') {
      depth--;
      if (depth == 0) {
        return source.substring(openBrace + 1, i);
      }
    }
  }
  throw StateError('Unbalanced braces for ${signaturePattern.pattern}');
}

void main() {
  late final String bootstrap;
  late final String listPage;
  late final String savedPage;
  late final String lookupPage;
  late final String detailPage;

  setUpAll(() {
    bootstrap = _read('lib/main_parts/customer_session_bootstrap.dart');
    listPage = _read('lib/main_parts/customer_bookings_page.dart');
    savedPage = _read('lib/main_parts/customer_saved_bookings_page.dart');
    lookupPage = _read('lib/main_parts/customer_booking_lookup_page.dart');
    detailPage = _read('lib/main_parts/customer_booking_detail_page.dart');
  });

  test('1. list refresh includes Bearer helper', () {
    final body = _extractMethodBody(
      listPage,
      RegExp(r'Future<void>\s+_refreshAuthoritative\s*\('),
    );
    expect(body, contains('_customerSessionBearerHeaders'));
    expect(body, contains('_customerCanonicalBookingGetUri'));
    expect(body, isNot(contains('_withActiveBookingScope')));
    expect(body, isNot(contains('_customerOwnershipProof')));
  });

  test('2. detail refresh includes Bearer', () {
    final body = _extractMethodBody(
      detailPage,
      RegExp(r'Future<void>\s+_refresh\s*\('),
    );
    expect(body, contains('_customerSessionBearerHeaders'));
    expect(body, contains('_customerCanonicalBookingGetUri'));
    expect(body, isNot(contains('_activeBookingScopeQuery')));
    expect(body, isNot(contains('_customerOwnershipProof')));
  });

  test('3. customer requests omit conflicting tenant/company query scope', () {
    expect(bootstrap, contains('_customerCanonicalBookingGetUri'));
    expect(bootstrap, contains('_customerSessionBearerHeaders'));
    expect(bootstrap, contains("headers['Authorization'] = 'Bearer \$token'"));
    // Canonical GET URI has no queryParameters for tenant/company.
    final uriBody = _extractMethodBody(
      bootstrap,
      RegExp(r'Uri\s+_customerCanonicalBookingGetUri\s*\('),
    );
    expect(uriBody, isNot(contains('tenant_id')));
    expect(uriBody, isNot(contains('company_id')));
    expect(uriBody, isNot(contains('queryParameters')));
  });

  test('4. canonical id preferred; public/planning not cancel route keys', () {
    final cancelBody = _extractMethodBody(
      detailPage,
      RegExp(r'Future<void>\s+_cancelBookingServerSide\s*\('),
    );
    expect(cancelBody, contains("final cancelCandidates = <String>[bookingId]"));
    expect(cancelBody, isNot(contains('_cancelBookingIdCandidates')));
    expect(cancelBody, contains("actor_role': 'customer'"));
    // No tenant/company in cancel payload/query for Bearer ownership-first.
    expect(cancelBody, isNot(contains("'tenant_id': scope")));
    expect(cancelBody, isNot(contains('scopedQuery')));
  });

  test('5. cancel includes Bearer', () {
    final cancelBody = _extractMethodBody(
      detailPage,
      RegExp(r'Future<void>\s+_cancelBookingServerSide\s*\('),
    );
    expect(cancelBody, contains('_cancelHeaders()'));
    expect(detailPage, contains('_cancelHeaders() => _customerSessionBearerHeaders()'));
  });

  test('6. cancel disabled while using local cache', () {
    final canCancel = _extractMethodBody(
      detailPage,
      RegExp(r'bool\s+get\s+_canCancelBooking\s*\{'),
    );
    expect(canCancel, contains('_usingLocalCache'));
    expect(
      detailPage,
      contains(
        'Annuleren is tijdelijk niet beschikbaar omdat de boeking niet met de server kon worden bevestigd.',
      ),
    );
  });

  test('7. no local cancelled state before successful server response', () {
    final cancelBody = _extractMethodBody(
      detailPage,
      RegExp(r'Future<void>\s+_cancelBookingServerSide\s*\('),
    );
    // Optimistic hide must only run after successfulBookingId is set.
    final successIdx = cancelBody.indexOf('successfulBookingId == null');
    final hideIdx = cancelBody.indexOf(
      '_optimisticHideCustomerBookingForCancelOrRemove',
    );
    expect(successIdx, greaterThan(0));
    expect(hideIdx, greaterThan(successIdx));
  });

  test('8. successful refresh clears local-cache and re-enables cancel gate', () {
    final refreshBody = _extractMethodBody(
      detailPage,
      RegExp(r'Future<void>\s+_refresh\s*\('),
    );
    expect(refreshBody, contains('_usingLocalCache = false'));
    final canCancel = _extractMethodBody(
      detailPage,
      RegExp(r'bool\s+get\s+_canCancelBooking\s*\{'),
    );
    expect(canCancel, contains('_isCustomerBookingTerminalStatus'));
  });

  test('saved + lookup also use Bearer canonical GET', () {
    expect(savedPage, contains('_customerCanonicalBookingGetUri'));
    expect(savedPage, contains('_customerSessionBearerHeaders'));
    expect(lookupPage, contains('_customerCanonicalBookingGetUri'));
    expect(lookupPage, contains('_customerSessionBearerHeaders'));
    expect(lookupPage, isNot(contains('_withActiveBookingScope')));
  });

  test('canonical id fixture 2026-08-161 used in worker ownership-first suite', () {
    final workerTest = _read(
      'workers/booking/customer_ownership_first_read_cancel_p0.test.mjs',
    );
    expect(workerTest, contains('2026-08-161'));
    expect(workerTest, contains('tenantId: "global"'));
    expect(workerTest, contains('ALLOW_LEGACY_CUSTOMER_CONTACT_PROOF: "0"'));
  });
}
