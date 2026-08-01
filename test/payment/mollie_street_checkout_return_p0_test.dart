// RELEASE-P0-MOLLIE-STREET-CHECKOUT-RETURN-1
//
// Pure + wiring tests for redirect URL, deep-link contract, generic Mollie
// copy, and resume/poll dialog behaviour.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/payment/mollie_street_checkout.dart';
import 'package:fluxidi_tracking/payment/mollie_street_checkout_dialog.dart';
import 'package:fluxidi_tracking/payment/payment_qr_panel.dart';
import 'package:fluxidi_tracking/payment_return.dart';

import 'dart:io';

String _read(String path) {
  final f = File(path);
  if (!f.existsSync()) fail('missing $path');
  return f.readAsStringSync();
}

MollieStreetCheckoutCopy _copy() => const MollieStreetCheckoutCopy(
      title: 'Online betalen',
      instruction:
          'Open de beveiligde betaalpagina of scan de QR-code. Kies daarna een van de beschikbare betaalmethodes.',
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

void main() {
  group('redirect / deep-link contracts', () {
    test('1. worker builds HTTPS /pay/return redirectUrl (not fluxidi:// to Mollie)', () {
      final mod = _read('workers/booking/modules/street_mollie_checkout.js');
      expect(mod, contains('function buildStreetMollieRedirectUrl'));
      expect(mod, contains('/pay/return?id='));
      expect(mod, contains('return_to='));

      final worker = _read('workers/booking/fluxidi_booking_worker.js');
      expect(worker, contains('buildStreetMollieRedirectUrl'));
      expect(
        worker,
        contains('async function createStreetRideCheckoutAuthoritative'),
      );
    });

    test('2. Android deep link matches fluxidi pay return', () {
      final manifest = _read('android/app/src/main/AndroidManifest.xml');
      expect(manifest, contains('android:scheme="fluxidi"'));
      expect(manifest, contains('android:host="pay"'));
      expect(manifest, contains('android:launchMode="singleTop"'));
      expect(
        _read('lib/payment_return.dart'),
        contains("const String kFluxidiPaymentReturnUrl = 'fluxidi://pay/return'"),
      );
    });

    test('return page opens app immediately (does not wait on auth /pay/status)', () {
      final worker = _read('workers/booking/fluxidi_booking_worker.js');
      expect(worker, contains('immediateAppReturn'));
      expect(worker, contains("params.set('status', 'pending')"));
      expect(worker, isNot(contains("params.set('status', 'confirmed')")));
    });

    test('deep link alone never marks paid in PaymentReturnCoordinator', () {
      final src = _read('lib/payment_return.dart');
      expect(
        src,
        contains('Deep-link query status is advisory only'),
      );
      expect(src, contains("unawaited(_reconcilePendingPayment(source: 'DEEP_LINK'))"));
      // Must not assign FluxidiPaymentStatus.confirmed from statusRaw alone.
      expect(
        src,
        isNot(contains("statusRaw == 'confirmed'")),
      );
    });
  });

  group('generic Mollie copy', () {
    test('12. street instruction has no Bancontact-only wording', () {
      final helpers = _read('lib/main_parts/receipt_text_helpers.dart');
      final idx = helpers.indexOf("case 'onlinePayInstruction':");
      expect(idx, greaterThan(-1));
      final block = helpers.substring(idx, idx + 700);
      expect(block.toLowerCase(), isNot(contains('bancontact')));
      expect(block.toLowerCase(), isNot(contains('payconiq')));
      expect(block, contains('beschikbare betaalmethodes'));
    });

    test('13. EPC / Bancontact PaymentQrPanel default copy unchanged', () {
      expect(
        PaymentQrPanel.subtitleFor(AppLanguage.nl),
        contains('Bancontact Pay'),
      );
      expect(
        PaymentQrPanel.subtitleFor(AppLanguage.nl),
        contains('Payconiq'),
      );
    });

    test('PaymentQrPanel override shows generic street instruction', () {
      expect(
        _copy().instruction.toLowerCase(),
        isNot(contains('bancontact')),
      );
    });
  });

  group('dialog resume / poll', () {
    testWidgets('5+6. app resume triggers immediate /pay/status; webhook-paid updates modal',
        (tester) async {
      var polls = 0;
      final outcomes = <MollieStreetCheckoutPollResult>[
        MollieStreetCheckoutPollResult.pending,
        MollieStreetCheckoutPollResult.paid,
      ];
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
                        checkoutUrl: 'https://www.mollie.com/checkout/test',
                        amountText: 'EUR 5.30',
                        paymentBookingId: 'pay_shadow_1',
                        textMutedColor: Colors.grey,
                        copy: _copy(),
                        interval: const Duration(days: 1),
                        maxAttempts: 10,
                        pollOnce: () async {
                          final i = polls;
                          polls++;
                          return outcomes[i.clamp(0, outcomes.length - 1)];
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
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));
      expect(find.text('Wachten op betaling…'), findsOneWidget);
      expect(polls, greaterThanOrEqualTo(1));

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));
      await tester.pump(const Duration(milliseconds: 500));

      expect(polls, greaterThanOrEqualTo(2));
      expect(popped, MollieStreetCheckoutPollOutcome.paid);
    });

    testWidgets('7. polling stops on paid', (tester) async {
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
      expect(find.text('Betaling geslaagd'), findsOneWidget);
      final afterPaid = polls;
      await tester.pump(const Duration(milliseconds: 100));
      expect(polls, afterPaid);
    });

    testWidgets('8. polling remains bounded on perpetual pending', (tester) async {
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

    testWidgets('9. failed stays unpaid terminal', (tester) async {
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
                        paymentBookingId: 'pay_fail',
                        textMutedColor: Colors.grey,
                        copy: _copy(),
                        interval: const Duration(days: 1),
                        pollOnce: () async => const MollieStreetCheckoutPollResult(
                          outcome: MollieStreetCheckoutPollOutcome.failed,
                          httpCode: 200,
                        ),
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
      await tester.pump(const Duration(milliseconds: 20));
      await tester.pump(const Duration(milliseconds: 500));
      expect(popped, MollieStreetCheckoutPollOutcome.failed);
    });

    testWidgets('10. modal shows paid without close/reopen (success text)', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MollieStreetCheckoutDialogContent(
              language: AppLanguage.nl,
              qrSrc: '',
              checkoutUrl: 'https://example.com/c',
              amountText: 'EUR 5.30',
              paymentBookingId: 'pay_ok',
              textMutedColor: Colors.grey,
              copy: _copy(),
              interval: const Duration(days: 1),
              pollOnce: () async => MollieStreetCheckoutPollResult.paid,
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 30));
      expect(find.text('Betaling geslaagd'), findsOneWidget);
      expect(find.text('Wachten op betaling…'), findsNothing);
    });

    testWidgets('I have paid refresh triggers another poll', (tester) async {
      var polls = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MollieStreetCheckoutDialogContent(
              language: AppLanguage.nl,
              qrSrc: '',
              checkoutUrl: 'https://example.com/c',
              amountText: 'EUR 1.00',
              paymentBookingId: 'pay_refresh',
              textMutedColor: Colors.grey,
              copy: _copy(),
              interval: const Duration(days: 1),
              maxAttempts: 20,
              pollOnce: () async {
                polls++;
                return MollieStreetCheckoutPollResult.pending;
              },
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));
      final afterOpen = polls;
      await tester.tap(find.text('Ik heb betaald'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));
      expect(polls, greaterThan(afterOpen));
    });

    test('11. paid ride cannot create second checkout (eligibility)', () {
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

    test('pending notifier triggers poll without trusting deep-link paid', () async {
      expect(
        classifyMollieStreetCheckoutPollStatus(
          httpCode: 200,
          data: {'payment_status': 'pending'},
        ),
        MollieStreetCheckoutPollOutcome.pending,
      );
      expect(
        classifyMollieStreetCheckoutPollStatus(
          httpCode: 200,
          data: {'payment_status': 'paid'},
        ),
        MollieStreetCheckoutPollOutcome.paid,
      );
      expect(kFluxidiPaymentReturnUrl, 'fluxidi://pay/return');
    });
  });
}
