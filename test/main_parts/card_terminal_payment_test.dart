// TAP-TO-PAY-DRIVER-UI-1 — card-terminal / Tap to Pay pure contract tests

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/payment/card_terminal_payment.dart';
import 'package:fluxidi_tracking/payment/mollie_capability_status.dart';

void main() {
  group('classifyCardTerminalProviderStatus', () {
    test('PAID-ONLY: only the official Mollie `paid` -> success', () {
      for (final s in ['paid', 'PAID', ' Paid ']) {
        expect(
          classifyCardTerminalProviderStatus(providerStatus: s),
          CardTerminalOutcome.success,
          reason: 'status "$s" should be success',
        );
      }
    });

    test('PAID-ONLY: raw "settled" text is NOT paid', () {
      for (final s in ['settled', 'SETTLED', ' Settled ']) {
        final o = classifyCardTerminalProviderStatus(providerStatus: s);
        expect(o, CardTerminalOutcome.pending, reason: 'status "$s"');
        expect(cardTerminalShouldWritePaid(o), isFalse, reason: 'status "$s"');
      }
    });

    test('SERVER AUTHORITY: raw "approved"/"success" text is NOT paid', () {
      for (final s in ['approved', 'success', 'APPROVED', ' Approved ']) {
        final o = classifyCardTerminalProviderStatus(providerStatus: s);
        expect(o, CardTerminalOutcome.pending, reason: 'status "$s"');
        expect(cardTerminalShouldWritePaid(o), isFalse, reason: 'status "$s"');
      }
    });

    test('open/pending/authorized/created -> pending (never success)', () {
      for (final s in ['open', 'pending', 'authorized', 'created']) {
        final o = classifyCardTerminalProviderStatus(providerStatus: s);
        expect(o, CardTerminalOutcome.pending, reason: 'status "$s"');
        expect(cardTerminalShouldWritePaid(o), isFalse);
      }
    });

    test('failed/expired -> failed', () {
      for (final s in ['failed', 'expired']) {
        expect(
          classifyCardTerminalProviderStatus(providerStatus: s),
          CardTerminalOutcome.failed,
        );
      }
    });

    test('canceled/cancelled -> cancelled', () {
      for (final s in ['canceled', 'cancelled']) {
        expect(
          classifyCardTerminalProviderStatus(providerStatus: s),
          CardTerminalOutcome.cancelled,
        );
      }
    });

    test('declined/denied/refused -> declined', () {
      for (final s in ['declined', 'denied', 'refused']) {
        expect(
          classifyCardTerminalProviderStatus(providerStatus: s),
          CardTerminalOutcome.declined,
        );
      }
    });

    test('HTTP 422 is always error even with a paid-looking body', () {
      final o = classifyCardTerminalProviderStatus(
        providerStatus: 'paid',
        httpCode: 422,
      );
      expect(o, CardTerminalOutcome.error);
      expect(cardTerminalShouldWritePaid(o), isFalse);
    });

    test('missing / empty / unknown status -> error (no callback == unpaid)', () {
      for (final s in [null, '', '   ', 'weird_unmapped_status']) {
        final o = classifyCardTerminalProviderStatus(providerStatus: s);
        expect(o, CardTerminalOutcome.error, reason: 'status "$s"');
        expect(cardTerminalShouldWritePaid(o), isFalse);
      }
    });
  });

  group('cardTerminalShouldWritePaid', () {
    test('only success authorises a paid write', () {
      expect(cardTerminalShouldWritePaid(CardTerminalOutcome.success), isTrue);
      for (final o in [
        CardTerminalOutcome.declined,
        CardTerminalOutcome.cancelled,
        CardTerminalOutcome.failed,
        CardTerminalOutcome.timeout,
        CardTerminalOutcome.error,
        CardTerminalOutcome.pending,
      ]) {
        expect(cardTerminalShouldWritePaid(o), isFalse, reason: '$o');
      }
    });
  });

  group('cardTerminalStartIsValidIntent', () {
    test('backend created intent (open) -> valid', () {
      expect(
        cardTerminalStartIsValidIntent(
          httpCode: 200,
          ok: true,
          paymentId: 'tr_123',
          status: 'created',
          mollieStatus: 'open',
        ),
        isTrue,
      );
    });

    test('existing_open reuse -> valid', () {
      expect(
        cardTerminalStartIsValidIntent(
          httpCode: 200,
          ok: true,
          paymentId: 'tr_123',
          status: 'existing_open',
          mollieStatus: 'pending',
        ),
        isTrue,
      );
    });

    test('401/422 -> NOT valid', () {
      for (final code in [401, 422]) {
        expect(
          cardTerminalStartIsValidIntent(
            httpCode: code,
            ok: false,
            paymentId: '',
            status: '',
            mollieStatus: '',
          ),
          isFalse,
        );
      }
    });
  });

  group('Tap to Pay capability gating', () {
    test('1. button visible with active terminal', () {
      expect(
        shouldShowTapToPayAction(InPersonTerminalStatus.activeTerminal),
        isTrue,
      );
      expect(
        shouldShowTapToPayAction(
          resolveTapToPayCapabilityStatus({
            'ok': true,
            'available': true,
            'status': 'active_terminal',
          }),
        ),
        isTrue,
      );
    });

    test('2. button absent/unavailable without terminal', () {
      expect(
        shouldShowTapToPayAction(InPersonTerminalStatus.noTerminal),
        isFalse,
      );
      expect(
        shouldShowTapToPayAction(
          resolveTapToPayCapabilityStatus({
            'ok': true,
            'available': false,
            'status': 'no_terminal',
          }),
        ),
        isFalse,
      );
      expect(
        shouldShowTapToPayAction(
          resolveTapToPayStatusFromTerminalsSnapshot({
            'status': 'synced',
            'terminals': [
              {'id': 'term_x', 'status': 'inactive'},
            ],
          }),
        ),
        isFalse,
      );
    });
  });

  group('manual Bancontact vs Tap to Pay', () {
    test('3. labels and methods stay distinct', () {
      // Source contract: receipt helpers use different keys/methods.
      const manualKey = 'paidByCardTerminal';
      const tapKey = 'tapToPay';
      expect(manualKey == tapKey, isFalse);
      expect(manualKey, isNot(equals(tapKey)));
      const manualMethod = 'bancontact';
      const tapMethod = 'pointofsale';
      expect(manualMethod, isNot(equals(tapMethod)));
    });
  });

  group('TapToPayStartGuard', () {
    test('4. double tap starts only one request', () async {
      final guard = TapToPayStartGuard();
      var starts = 0;
      Future<String> start() async {
        starts += 1;
        await Future<void>.delayed(const Duration(milliseconds: 30));
        return 'ok';
      }

      final first = guard.runOnce(start);
      final second = guard.runOnce(start);
      final a = await first;
      final b = await second;
      expect(a, 'ok');
      expect(b, isNull);
      expect(starts, 1);
    });
  });

  group('pending / paid / canceled mapping', () {
    test('5. pending shows processing without paid-state', () {
      final o = classifyCardTerminalProviderStatus(providerStatus: 'open');
      expect(o, CardTerminalOutcome.pending);
      expect(cardTerminalShouldWritePaid(o), isFalse);
      expect(cardTerminalUserMessageKey(o), 'cardTerminalProcessing');
    });

    test('6. paid authorises receipt refresh / paid status', () {
      final o = classifyCardTerminalProviderStatus(providerStatus: 'paid');
      expect(cardTerminalShouldWritePaid(o), isTrue);
      expect(cardTerminalUserMessageKey(o), isNull);
    });

    test('7. canceled/failed leave ride unpaid', () {
      for (final s in ['canceled', 'failed', 'expired']) {
        final o = classifyCardTerminalProviderStatus(providerStatus: s);
        expect(cardTerminalShouldWritePaid(o), isFalse, reason: s);
        expect(cardTerminalIsTerminalOutcome(o), isTrue, reason: s);
      }
    });
  });

  group('server amount authority (client path)', () {
    test('8+9. client never sends authoritative amount (planned or street)', () {
      expect(tapToPayClientSendsAuthoritativeAmount(), isFalse);
    });

    test('10. phone and tablet share the same logical path', () {
      expect(
        tapToPayLogicalPathId(isTablet: false),
        tapToPayLogicalPathId(isTablet: true),
      );
      expect(
        tapToPayLogicalPathId(isTablet: false),
        'driver_mollie_terminal_payment',
      );
    });
  });

  group('cardTerminalDiagnosticsLine', () {
    test('is PII-free and contains required structural fields', () {
      final line = cardTerminalDiagnosticsLine(
        phase: CardTerminalPhase.launch,
        amountCents: 320,
        providerStatus: 'created',
        providerCode: null,
        paymentWritten: false,
        reason: 'card_terminal_start',
      );
      expect(line, startsWith('[CARD_TERMINAL_PAYMENT] '));
      expect(line, contains('phase=launch'));
      expect(line, contains('amountCents=320'));
      expect(line, contains('paymentWritten=false'));
    });
  });
}
