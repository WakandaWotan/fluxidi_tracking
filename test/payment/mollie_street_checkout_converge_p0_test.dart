// RELEASE-P0-MOLLIE-STREET-CHECKOUT-CONVERGE-1
//
// Auth alignment, non-silent "Ik heb betaald", notifier→modal, dismiss
// refresh, paid monotonic, and diagnostics contracts.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/payment/mollie_street_checkout.dart';
import 'package:fluxidi_tracking/payment/mollie_street_checkout_dialog.dart';
import 'package:fluxidi_tracking/payment/mollie_street_status_auth.dart';
import 'package:fluxidi_tracking/payment_return.dart';

String _read(String path) {
  final f = File(path);
  if (!f.existsSync()) fail('missing $path');
  return f.readAsStringSync();
}

MollieStreetCheckoutCopy _copy() => const MollieStreetCheckoutCopy(
      title: 'Online betalen',
      instruction: 'Open de beveiligde betaalpagina.',
      waitingText: 'Wachten op betaling…',
      processingText: 'Betaling wordt nog verwerkt…',
      succeededText: 'Betaling geslaagd',
      failedText: 'Betaling mislukt',
      cancelledText: 'Betaling geannuleerd',
      expiredText: 'Betaling verlopen',
      iHavePaidLabel: 'Ik heb betaald',
      closeLabel: 'Sluiten',
      statusAuthErrorText: 'Kon de betaalstatus niet ophalen (sessie).',
      statusNotFoundErrorText: 'Betaling niet gevonden.',
      statusServerErrorText: 'Tijdelijke serverfout.',
      statusGenericErrorText: 'Kon de betaalstatus niet controleren.',
    );

Future<void> _openDialog(
  WidgetTester tester, {
  required Future<MollieStreetCheckoutPollResult> Function() pollOnce,
  ValueNotifier<FluxidiPendingPayment?>? pending,
  String paymentBookingId = 'pay_shadow_same',
  Duration interval = const Duration(days: 1),
  int maxAttempts = 20,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: ElevatedButton(
            onPressed: () {
              showDialog<MollieStreetCheckoutPollOutcome>(
                context: context,
                builder: (_) => AlertDialog(
                  content: MollieStreetCheckoutDialogContent(
                    language: AppLanguage.nl,
                    qrSrc: '',
                    checkoutUrl: 'https://example.com/c',
                    amountText: 'EUR 5.30',
                    paymentBookingId: paymentBookingId,
                    canonicalBookingId: 'street_test_1',
                    textMutedColor: Colors.grey,
                    copy: _copy(),
                    interval: interval,
                    maxAttempts: maxAttempts,
                    pendingPaymentListenable: pending,
                    pollOnce: pollOnce,
                  ),
                ),
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pump();
  await tester.pump();
}

void main() {
  group('1–2 auth selection + shared helper', () {
    test('1. company preferred when stale driver also present', () {
      expect(
        selectMollieStreetStatusAuthMode(
          hasCompanySession: true,
          hasDriverSession: true,
          hasCustomerSession: false,
        ),
        MollieStreetStatusAuthMode.companySession,
      );
    });

    test('2. coordinator and street dialog share auth helper source', () {
      final auth = _read('lib/payment/mollie_street_status_auth.dart');
      expect(auth, contains('resolveMollieStreetStatusAuthHeaders'));
      expect(auth, contains('selectMollieStreetStatusAuthMode'));

      final payReturn = _read('lib/payment_return.dart');
      expect(payReturn, contains('resolveMollieStreetStatusAuthHeaders'));
      expect(payReturn, isNot(contains('resolveInCarPaymentAuthHeaders')));
      expect(payReturn, contains('resolveMollieStreetStatusScopeQuery'));

      final receipt = _read('lib/main_parts/ride_receipt_body_state.dart');
      expect(receipt, contains('resolveMollieStreetStatusAuthHeaders'));
      expect(
        receipt,
        isNot(contains('resolveInCarPaymentAuthHeaders(json: false)')),
      );
    });

    test('4. driver-first 404 regression cannot occur when company exists', () {
      // Pure order proof: company wins over driver.
      expect(
        selectMollieStreetStatusAuthMode(
          hasCompanySession: true,
          hasDriverSession: true,
          hasCustomerSession: true,
        ),
        isNot(MollieStreetStatusAuthMode.driverSession),
      );
      final inCar = _read('lib/app_config.dart');
      // In-car cash/QR remains driver-first — street status must not reuse it.
      expect(inCar, contains('Prefers the active driver-session bearer'));
      final street = _read('lib/payment/mollie_street_status_auth.dart');
      expect(street, contains('Company-first auth headers'));
    });

    test('driver fallback only when company absent', () {
      expect(
        selectMollieStreetStatusAuthMode(
          hasCompanySession: false,
          hasDriverSession: true,
          hasCustomerSession: false,
        ),
        MollieStreetStatusAuthMode.driverSession,
      );
    });

    test('never unauthenticated when any session exists', () {
      expect(
        selectMollieStreetStatusAuthMode(
          hasCompanySession: false,
          hasDriverSession: false,
          hasCustomerSession: true,
        ),
        MollieStreetStatusAuthMode.customerSession,
      );
      expect(
        selectMollieStreetStatusAuthMode(
          hasCompanySession: false,
          hasDriverSession: false,
          hasCustomerSession: false,
        ),
        MollieStreetStatusAuthMode.none,
      );
    });
  });

  group('3–8 Ik heb betaald feedback', () {
    testWidgets('5. Ik heb betaald on paid → success', (tester) async {
      var polls = 0;
      await _openDialog(
        tester,
        pollOnce: () async {
          polls++;
          if (polls == 1) return MollieStreetCheckoutPollResult.pending;
          return MollieStreetCheckoutPollResult.paid;
        },
      );
      await tester.pump(const Duration(milliseconds: 20));
      await tester.tap(find.text('Ik heb betaald'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));
      expect(find.text('Betaling geslaagd'), findsOneWidget);
    });

    testWidgets('6. Ik heb betaald on pending → visible pending feedback',
        (tester) async {
      await _openDialog(
        tester,
        pollOnce: () async => MollieStreetCheckoutPollResult.pending,
      );
      await tester.pump(const Duration(milliseconds: 20));
      await tester.tap(find.text('Ik heb betaald'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));
      expect(find.text('Betaling wordt nog verwerkt…'), findsOneWidget);
    });

    testWidgets('7. Ik heb betaald on 404 → visible sanitized error',
        (tester) async {
      await _openDialog(
        tester,
        pollOnce: () async => const MollieStreetCheckoutPollResult(
          outcome: MollieStreetCheckoutPollOutcome.error,
          httpCode: 404,
          sanitizedErrorCode: 'not_found',
        ),
      );
      await tester.pump(const Duration(milliseconds: 20));
      await tester.tap(find.text('Ik heb betaald'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));
      expect(find.text('Betaling niet gevonden.'), findsOneWidget);
    });

    testWidgets('8. button re-enables after failure', (tester) async {
      await _openDialog(
        tester,
        pollOnce: () async => const MollieStreetCheckoutPollResult(
          outcome: MollieStreetCheckoutPollOutcome.error,
          httpCode: 401,
          sanitizedErrorCode: 'unauthorized',
        ),
      );
      await tester.pump(const Duration(milliseconds: 20));
      await tester.tap(find.text('Ik heb betaald'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));
      final button = tester.widget<TextButton>(
        find.widgetWithText(TextButton, 'Ik heb betaald'),
      );
      expect(button.onPressed, isNotNull);
    });
  });

  group('9–10 notifier updates modal', () {
    testWidgets('9. notifier paid for same booking updates open modal',
        (tester) async {
      final pending = ValueNotifier<FluxidiPendingPayment?>(
        const FluxidiPendingPayment(
          paymentBookingId: 'pay_shadow_same',
          publicBookingId: 'street_test_1',
        ),
      );
      await _openDialog(
        tester,
        pending: pending,
        pollOnce: () async => MollieStreetCheckoutPollResult.pending,
      );
      await tester.pump(const Duration(milliseconds: 20));
      expect(find.text('Wachten op betaling…'), findsOneWidget);

      pending.value = pending.value!.copyWith(
        status: FluxidiPaymentStatus.confirmed,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));
      expect(find.text('Betaling geslaagd'), findsOneWidget);
    });

    testWidgets('10. notifier paid for another booking is ignored',
        (tester) async {
      final pending = ValueNotifier<FluxidiPendingPayment?>(
        const FluxidiPendingPayment(paymentBookingId: 'other_pay'),
      );
      await _openDialog(
        tester,
        pending: pending,
        pollOnce: () async => MollieStreetCheckoutPollResult.pending,
      );
      await tester.pump(const Duration(milliseconds: 20));
      pending.value = pending.value!.copyWith(
        status: FluxidiPaymentStatus.confirmed,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));
      expect(find.text('Betaling geslaagd'), findsNothing);
      expect(find.text('Wachten op betaling…'), findsOneWidget);
    });

    test('payment id match helper', () {
      expect(mollieStreetPaymentIdsMatch('a', 'a'), isTrue);
      expect(mollieStreetPaymentIdsMatch(' a ', 'a'), isTrue);
      expect(mollieStreetPaymentIdsMatch('a', 'b'), isFalse);
      expect(mollieStreetPaymentIdsMatch('', 'a'), isFalse);
    });
  });

  group('11–13 dismiss refresh + monotonic paid', () {
    test('11. modal dismiss always triggers canonical refresh (source)', () {
      final receipt = _read('lib/main_parts/ride_receipt_body_state.dart');
      expect(
        receipt,
        contains('_refreshCanonicalReceiptAfterStreetMollieModal'),
      );
      expect(
        receipt,
        contains('Always refresh canonical booking after modal close'),
      );
    });

    test('12. canonical paid overrides local unpaid helper', () {
      expect(
        shouldKeepReceiptPaidMonotonic(
          currentlyPaid: false,
          authoritativeSaysPaid: true,
          authoritativeReadSucceeded: true,
        ),
        isFalse, // caller must apply auth paid separately when local unpaid
      );
      // When applying: if auth paid, set paid. Monotonic guard is for keep.
      expect(
        classifyMollieStreetCheckoutPollStatus(
          httpCode: 200,
          data: {'payment_status': 'paid'},
        ),
        MollieStreetCheckoutPollOutcome.paid,
      );
    });

    test('13. paid cannot revert to unpaid', () {
      expect(
        shouldKeepReceiptPaidMonotonic(
          currentlyPaid: true,
          authoritativeSaysPaid: false,
          authoritativeReadSucceeded: true,
        ),
        isTrue,
      );
      expect(
        shouldKeepReceiptPaidMonotonic(
          currentlyPaid: true,
          authoritativeSaysPaid: false,
          authoritativeReadSucceeded: false,
        ),
        isTrue,
      );
    });
  });

  group('14–17 polling behavior', () {
    testWidgets('14. app resume polls immediately', (tester) async {
      var polls = 0;
      await _openDialog(
        tester,
        pollOnce: () async {
          polls++;
          return MollieStreetCheckoutPollResult.pending;
        },
      );
      await tester.pump(const Duration(milliseconds: 20));
      final afterOpen = polls;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));
      expect(polls, greaterThan(afterOpen));
    });

    testWidgets('15. no concurrent duplicate polls (queued)', (tester) async {
      var inFlight = 0;
      var maxInFlight = 0;
      var polls = 0;
      await _openDialog(
        tester,
        interval: const Duration(days: 1),
        pollOnce: () async {
          inFlight++;
          if (inFlight > maxInFlight) maxInFlight = inFlight;
          polls++;
          await Future<void>.delayed(const Duration(milliseconds: 40));
          inFlight--;
          return MollieStreetCheckoutPollResult.pending;
        },
      );
      await tester.pump();
      // Spam resume + button while first poll in flight.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.tap(find.text('Ik heb betaald'));
      await tester.pump(const Duration(milliseconds: 10));
      expect(maxInFlight, lessThanOrEqualTo(1));
      await tester.pump(const Duration(milliseconds: 80));
      expect(polls, greaterThanOrEqualTo(1));
    });

    testWidgets('16. polling stops on paid', (tester) async {
      var polls = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MollieStreetCheckoutDialogContent(
              language: AppLanguage.nl,
              qrSrc: '',
              checkoutUrl: 'https://example.com/c',
              amountText: 'EUR 1.00',
              paymentBookingId: 'pay_1',
              textMutedColor: Colors.grey,
              copy: _copy(),
              interval: const Duration(milliseconds: 10),
              maxAttempts: 20,
              pollOnce: () async {
                polls++;
                return MollieStreetCheckoutPollResult.paid;
              },
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));
      await tester.pump(const Duration(milliseconds: 500));
      final afterPaid = polls;
      await tester.pump(const Duration(milliseconds: 100));
      expect(polls, afterPaid);
    });

    testWidgets('17. no infinite loading (bounded attempts)', (tester) async {
      var polls = 0;
      MollieStreetCheckoutPollOutcome? popped;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () async {
                  popped = await showDialog<MollieStreetCheckoutPollOutcome>(
                    context: context,
                    builder: (_) => AlertDialog(
                      content: MollieStreetCheckoutDialogContent(
                        language: AppLanguage.nl,
                        qrSrc: '',
                        checkoutUrl: 'https://example.com/c',
                        amountText: 'EUR 1.00',
                        paymentBookingId: 'pay_bound',
                        textMutedColor: Colors.grey,
                        copy: _copy(),
                        interval: Duration.zero,
                        maxAttempts: 3,
                        pollOnce: () async {
                          polls++;
                          return MollieStreetCheckoutPollResult.pending;
                        },
                      ),
                    ),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pump();
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 5));
      }
      expect(polls, lessThanOrEqualTo(3));
      expect(popped, MollieStreetCheckoutPollOutcome.pending);
    });
  });

  group('18–20 receipt/history + checkout block + diagnostics', () {
    test('18. receipt refresh path present after modal', () {
      final receipt = _read('lib/main_parts/ride_receipt_body_state.dart');
      expect(receipt, contains('_fetchAuthoritativePaymentFields'));
      expect(receipt, contains('shouldKeepReceiptPaidMonotonic'));
      expect(receipt, contains('paymentSucceeded'));
    });

    test('19. second checkout remains blocked when paid', () {
      expect(
        resolveMollieStreetCheckoutEligible(
          bookingId: 'street_1',
          isPaid: true,
          isCancelled: false,
          amount: 5.3,
        ),
        isFalse,
      );
    });

    test('20. diagnostics never log tokens/PII patterns', () {
      final auth = _read('lib/payment/mollie_street_status_auth.dart');
      expect(auth, contains('mollieStreetIdHash'));
      expect(auth, contains('logMollieStreetStatusDiag'));
      // Headers may set Authorization, but diagnostics must not print it.
      expect(auth, isNot(contains('debugPrint(headers')));
      expect(auth, isNot(contains('debugPrint(auth')));
      // Diagnostic helper body must not reference Authorization.
      final diagIdx = auth.indexOf('void logMollieStreetStatusDiag');
      final diagEnd = auth.indexOf('/// True when [pendingPaymentId]', diagIdx);
      expect(diagIdx, greaterThan(-1));
      expect(diagEnd, greaterThan(diagIdx));
      final diagBody = auth.substring(diagIdx, diagEnd);
      expect(diagBody.toLowerCase(), isNot(contains('authorization')));
      expect(diagBody.toLowerCase(), isNot(contains('bearer')));
      expect(diagBody.toLowerCase(), isNot(contains('token')));

      expect(
        mollieStreetIdHash('23d9ee58-651d-44a5-a051-49d7122ef15d'),
        '23d9ee58…',
      );
      expect(mollieStreetIdHash('short'), '5c');
      expect(mollieStreetIdHash(''), '-');

      final payReturn = _read('lib/payment_return.dart');
      expect(payReturn, contains('mollieStreetIdHash'));
      expect(
        payReturn,
        isNot(contains("source=\$source id=\$paymentBookingId")),
      );
    });

    test('3. classify valid company /pay/status paid', () {
      final result = buildMollieStreetCheckoutPollResult(
        httpCode: 200,
        root: {'ok': true},
        data: {
          'payment_status': 'paid',
          'confirmed_at': '2026-08-01T18:51:32.000Z',
        },
      );
      expect(result.outcome, MollieStreetCheckoutPollOutcome.paid);
    });

    test('sanitize error codes', () {
      expect(
        sanitizeMollieStreetStatusErrorCode(httpCode: 404),
        'not_found',
      );
      expect(
        sanitizeMollieStreetStatusErrorCode(httpCode: 401),
        'unauthorized',
      );
      expect(
        sanitizeMollieStreetStatusErrorCode(httpCode: 503),
        'server_error',
      );
    });
  });
}
