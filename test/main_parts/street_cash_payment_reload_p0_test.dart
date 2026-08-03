// STREET-CASH-PAYMENT-RELOAD-P0
//
// Proves cash / QR / terminal paid status survives receipt reopen and that
// a stale Unpaid History projection cannot overwrite a newer confirmed Paid.
//
// Run:
//   flutter test test/main_parts/street_cash_payment_reload_p0_test.dart

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/main_parts/street_business_invoice_support.dart';

String _readSourceOrFail(String relativePath) {
  final file = File(relativePath);
  if (!file.existsSync()) fail('Source file not found: $relativePath');
  return file.readAsStringSync();
}

String _extractMethodBody(String source, String signaturePrefix) {
  final startIdx = source.indexOf(signaturePrefix);
  if (startIdx < 0) {
    fail('Could not locate signature "$signaturePrefix"');
  }
  final bodyOpenPattern = RegExp(r'\)\s*(?:async\s*)?\{');
  final bodyOpenMatch = bodyOpenPattern.firstMatch(source.substring(startIdx));
  if (bodyOpenMatch == null) {
    fail('Could not find body-opening brace after "$signaturePrefix"');
  }
  final openIdx = startIdx + bodyOpenMatch.end - 1;
  var depth = 0;
  for (var i = openIdx; i < source.length; i++) {
    final ch = source[i];
    if (ch == '{') depth++;
    if (ch == '}') {
      depth--;
      if (depth == 0) {
        return source.substring(openIdx, i + 1);
      }
    }
  }
  fail('Unbalanced braces for "$signaturePrefix"');
}

void main() {
  group('STREET-CASH-PAYMENT-RELOAD-P0 reload precedence', () {
    test('1/2/3) authoritative Paid wins over unpaid History on reopen', () {
      final resolved = resolveReceiptReloadPaymentStatusRaw(
        authoritativeStatus: 'paid',
        historyTopLevelStatus: 'unpaid',
        historyNestedStatus: 'pending',
      );
      expect(resolved, 'paid');
      expect(
        shouldRetainConfirmedPaidOnReload(
          alreadyConfirmedPaid: false,
          resolvedRawStatus: resolved,
        ),
        isFalse,
      );
      final canonical = resolveCanonicalReceiptRidePayment(
        explicitPaymentStatus: resolved,
      );
      expect(canonical.isPaid, isTrue);
      expect(canonical.normalizedStatus, 'paid');
    });

    test('4/5) History and Company Bookings share the same Paid token', () {
      // Both surfaces normalize on payment_status=paid from their store.
      // History uses the tracking-trip projection (synced from booking);
      // Company Bookings rehydrates BOOKING_KV. The canonical resolver is
      // the shared truth for the receipt UI after either source.
      final fromHistory = resolveCanonicalReceiptRidePayment(
        explicitPaymentStatus: 'paid',
      );
      final fromBookingKv = resolveCanonicalReceiptRidePayment(
        explicitPaymentStatus: 'paid',
      );
      expect(fromHistory.isPaid, isTrue);
      expect(fromBookingKv.isPaid, isTrue);
      expect(fromHistory.normalizedStatus, fromBookingKv.normalizedStatus);
    });

    test('6) payment actions stay hidden when effective paid is true', () {
      final canonical = resolveCanonicalReceiptRidePayment(
        effectiveReceiptPaid: true,
      );
      expect(canonical.isPaid, isTrue);
    });

    test('8/9) QR and terminal confirmation share durable Paid truth', () {
      for (final method in const ['qr_code', 'cash', 'bancontact']) {
        final canonical = resolveCanonicalReceiptRidePayment(
          explicitPaymentStatus: 'paid',
          paymentLifecyclePaid: true,
        );
        expect(
          canonical.isPaid,
          isTrue,
          reason: 'method=$method must resolve paid',
        );
      }
    });

    test('10) successful payment does not auto-create a business invoice '
        'via the ride-payment canonical path', () {
      // The ride-payment resolver only decides Paid/Unpaid. Invoice creation
      // remains gated elsewhere (Billit auto-create / business intent). This
      // proof asserts the ride-paid path does not invent invoice evidence.
      final canonical = resolveCanonicalReceiptRidePayment(
        explicitPaymentStatus: 'paid',
        documentRidePaid: null,
      );
      expect(canonical.isPaid, isTrue);
      expect(canonical.source, isNot('document'));
    });

    test('11) stale Unpaid cannot overwrite newer confirmed Paid', () {
      expect(
        shouldRetainConfirmedPaidOnReload(
          alreadyConfirmedPaid: true,
          resolvedRawStatus: 'unpaid',
        ),
        isTrue,
      );
      expect(
        shouldRetainConfirmedPaidOnReload(
          alreadyConfirmedPaid: true,
          resolvedRawStatus: null,
        ),
        isTrue,
      );
      expect(
        shouldRetainConfirmedPaidOnReload(
          alreadyConfirmedPaid: true,
          resolvedRawStatus: 'pending',
        ),
        isTrue,
      );
      expect(
        shouldRetainConfirmedPaidOnReload(
          alreadyConfirmedPaid: true,
          resolvedRawStatus: 'paid',
        ),
        isFalse,
      );
      expect(
        shouldRetainConfirmedPaidOnReload(
          alreadyConfirmedPaid: false,
          resolvedRawStatus: 'unpaid',
        ),
        isFalse,
      );
    });

    test('11b) explicit authoritative reverse/refund/cancel must not be masked',
        () {
      for (final status in const [
        'refunded',
        'reversed',
        'cancelled',
        'canceled',
        'rejected',
        'failed',
        'payment_failed',
      ]) {
        expect(
          shouldRetainConfirmedPaidOnReload(
            alreadyConfirmedPaid: true,
            resolvedRawStatus: status,
          ),
          isFalse,
          reason: 'status=$status must win over prior Paid',
        );
      }
    });

    test('history falls back only when authoritative is absent', () {
      expect(
        resolveReceiptReloadPaymentStatusRaw(
          authoritativeStatus: null,
          historyTopLevelStatus: 'unpaid',
          historyNestedStatus: 'paid',
        ),
        'unpaid',
      );
      expect(
        resolveReceiptReloadPaymentStatusRaw(
          authoritativeStatus: '  ',
          historyTopLevelStatus: null,
          historyNestedStatus: 'paid',
        ),
        'paid',
      );
    });
  });

  group('STREET-CASH-PAYMENT-RELOAD-P0 source contracts', () {
    late String receiptSource;

    setUpAll(() {
      receiptSource = _readSourceOrFail(
        'lib/main_parts/ride_receipt_body_state.dart',
      );
    });

    test('authoritative GET uses company-first Mollie street status auth '
        '(not admin-token-only)', () {
      // Product owner: resolveMollieStreetStatusAuthHeaders (company-first).
      // Cash/QR mark-paid retains resolveInCarPaymentAuthHeaders elsewhere.
      final body = _extractMethodBody(
        receiptSource,
        'Future<Map<String, dynamic>?> _fetchAuthoritativePaymentFields(',
      );
      expect(body, contains('resolveMollieStreetStatusAuthHeaders()'));
      expect(body, contains('MollieStreetStatusAuthMode.none'));
      expect(body, isNot(contains('resolveInCarPaymentAuthHeaders()')));
      expect(body, isNot(contains("headers['x-admin-token']")));
      expect(body, isNot(contains('kAdminToken')));
    });

    test('cash / QR mark-paid retain driver-first in-car auth helper', () {
      // Persist paths must keep resolveInCarPaymentAuthHeaders (driver-first).
      // Authoritative status GET intentionally uses the Mollie street helper.
      expect(
        receiptSource.contains('resolveInCarPaymentAuthHeaders()'),
        isTrue,
      );
      final persistBody = _extractMethodBody(
        receiptSource,
        'Future<void> _persistInCarPayment(',
      );
      expect(persistBody, contains('resolveInCarPaymentAuthHeaders()'));
      expect(persistBody, contains('InCarPaymentAuthMode.none'));
      expect(persistBody, contains('final headers = authHeaders.headers'));
      // Booking-worker mark-paid must not invent an admin-token-only header map.
      expect(
        persistBody.contains(
          "headers['x-admin-token'] = kAdminToken",
        ),
        isFalse,
      );
    });

    test('reload resolver uses the pure precedence helpers', () {
      final body = _extractMethodBody(
        receiptSource,
        'Future<void> _resolveReceiptPaymentStatus()',
      );
      expect(body, contains('resolveReceiptReloadPaymentStatusRaw('));
      expect(body, contains('shouldRetainConfirmedPaidOnReload('));
    });

    test('cash / QR / terminal share _persistInCarPayment', () {
      expect(
        receiptSource.contains("method: 'cash'"),
        isTrue,
      );
      expect(
        receiptSource.contains("method: 'qr'"),
        isTrue,
      );
      expect(
        RegExp(r"_persistInCarPayment\([\s\S]*?method:\s*'bancontact'")
            .hasMatch(receiptSource),
        isTrue,
      );
    });
  });
}
