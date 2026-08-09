// RELEASE-P0-MOLLIE-STREET-CHECKOUT-1
//
// Source-contract checks for the receipt Payment section wiring: the
// "Online betalen" button must be gated by the pure eligibility resolver,
// rendered above the bank QR button, must never send `amount` as an
// authority in the street-checkout start request, and all its new
// translation keys must exist for NL/EN/FR/ES.
//
// `_RideReceiptBodyState` is a private class declared inside `main.dart`
// (via `part of`), so — matching the existing style in
// test/main_parts/street_cash_payment_reload_p0_test.dart — this proves the
// wiring by reading the source files rather than instantiating the widget.
//
// Run:
//   flutter test test/main_parts/mollie_street_checkout_receipt_wiring_test.dart

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _readSourceOrFail(String relativePath) {
  final file = File(relativePath);
  if (!file.existsSync()) fail('Source file not found: $relativePath');
  return file.readAsStringSync();
}

void main() {
  group('RELEASE-P0-MOLLIE-STREET-CHECKOUT-1 receipt wiring', () {
    late String receiptSource;
    late String textHelpersSource;

    setUpAll(() {
      receiptSource = _readSourceOrFail(
        'lib/main_parts/ride_receipt_body_state.dart',
      );
      textHelpersSource = _readSourceOrFail(
        'lib/main_parts/receipt_text_helpers.dart',
      );
    });

    test('eligibility is gated by the pure resolveMollieStreetCheckoutEligible', () {
      expect(
        receiptSource,
        contains('bool _mollieStreetCheckoutEligible()'),
      );
      expect(
        receiptSource,
        contains('resolveMollieStreetCheckoutEligible('),
      );
    });

    test('"Online betalen" button is rendered above the bank QR button', () {
      final onlinePayIdx = receiptSource.indexOf("_receiptText('onlinePay')");
      final payByQrIdx = receiptSource.indexOf("_receiptText('payByQr')");
      expect(onlinePayIdx, greaterThan(-1), reason: 'onlinePay button missing');
      expect(payByQrIdx, greaterThan(-1), reason: 'payByQr button missing');
      expect(
        onlinePayIdx,
        lessThan(payByQrIdx),
        reason: 'Online betalen must render above Pay by QR',
      );
    });

    test('online-pay button shows the subtitle text', () {
      expect(
        receiptSource,
        contains("_receiptText('onlinePaySubtitle')"),
      );
    });

    test('online-pay button is gated on eligibility inside _paymentSection', () {
      final sectionIdx = receiptSource.indexOf(
        'Widget _paymentSection(BuildContext context) {',
      );
      expect(sectionIdx, greaterThan(-1));
      final sectionBody = receiptSource.substring(
        sectionIdx,
        sectionIdx + 12000,
      );
      expect(sectionBody, contains('_mollieStreetCheckoutEligible()'));
      // MOLLIE-OPEN-PAYMENT-RECOVERY-P0: recovery actions while open checkout owns payment.
      expect(sectionBody, contains('_openMollieBlocksFallback'));
      expect(sectionBody, contains('checkPaymentStatus'));
      expect(receiptSource, contains('mollie-checkout-recovery'));
    });

    test('street-checkout start request never sends amount as authority', () {
      final startIdx = receiptSource.indexOf(
        'Future<void> _startMollieStreetCheckout(BuildContext context) async {',
      );
      expect(startIdx, greaterThan(-1));
      final endIdx = receiptSource.indexOf(
        '\n  Future<void> _showMollieStreetCheckoutDialog(',
      );
      expect(endIdx, greaterThan(startIdx));
      final body = receiptSource.substring(startIdx, endIdx);
      expect(body, contains('/street-checkout'));
      expect(body, contains('return_url'));
      // No `'amount':` key anywhere in the request payload construction.
      expect(body, isNot(contains("'amount':")));
    });

    test('street-checkout POST uses the trusted driver/company bearer', () {
      final startIdx = receiptSource.indexOf(
        'Future<void> _startMollieStreetCheckout(BuildContext context) async {',
      );
      final endIdx = receiptSource.indexOf(
        '\n  Future<void> _showMollieStreetCheckoutDialog(',
      );
      final body = receiptSource.substring(startIdx, endIdx);
      expect(body, contains('resolveInCarPaymentAuthHeaders()'));
      expect(body, contains('InCarPaymentAuthMode.none'));
      expect(body, contains('.timeout(const Duration(seconds: 25))'));
    });

    test('/pay/status poll uses a bounded attempt budget (no infinite spinner)', () {
      final dialog = _readSourceOrFail(
        'lib/payment/mollie_street_checkout_dialog.dart',
      );
      expect(dialog, contains('maxAttempts = 60'));
      expect(dialog, contains("source: 'LIFECYCLE_RESUME'"));
      expect(dialog, contains('WidgetsBindingObserver'));
      expect(dialog, contains('iHavePaidLabel'));
      expect(dialog, contains('onCancelOnlinePayment'));
      expect(dialog, contains('onAuthoritativeRefresh'));
      expect(dialog, contains('cancelOnlinePaymentNow'));
    });

    test('CONVERGE-P0: receipt auto-refreshes on open/resume/return', () {
      expect(
        receiptSource,
        contains('_maybeAuthoritativeMollieCheckoutRefresh'),
      );
      expect(receiptSource, contains("reason: 'receipt_open'"));
      expect(receiptSource, contains("reason: 'app_resume'"));
      expect(receiptSource, contains("reason: 'return_from_checkout'"));
      expect(receiptSource, contains('with WidgetsBindingObserver'));
      expect(
        receiptSource,
        contains('onCancelOnlinePayment: () => _cancelOpenMollieCheckoutAsPollOutcome'),
      );
    });

    test(
      'MOLLIE-HOSTED-RESUME-P0: resume does NOT call _startMollieStreetCheckout',
      () {
        expect(
          receiptSource,
          contains('Future<void> _resumeOpenMollieCheckout(BuildContext context)'),
        );
        expect(
          receiptSource,
          contains('await _resumeOpenMollieCheckout(context);'),
        );

        final runIdx = receiptSource.indexOf(
          'Future<void> _runOpenMollieRecoveryAction(',
        );
        expect(runIdx, greaterThan(-1));
        final resumeHelperIdx = receiptSource.indexOf(
          'Future<void> _resumeOpenMollieCheckout(BuildContext context)',
          runIdx,
        );
        expect(resumeHelperIdx, greaterThan(runIdx));
        final runBody = receiptSource.substring(runIdx, resumeHelperIdx);
        expect(
          runBody,
          contains('MollieOpenPaymentRecoveryChoice.resume'),
        );
        expect(runBody, contains('await _resumeOpenMollieCheckout(context);'));
        expect(runBody, isNot(contains('await _startMollieStreetCheckout')));

        final nextMethodIdx = receiptSource.indexOf(
          '\n  void _togglePaidDemo(',
          resumeHelperIdx,
        );
        expect(nextMethodIdx, greaterThan(resumeHelperIdx));
        final resumeBody = receiptSource.substring(
          resumeHelperIdx,
          nextMethodIdx,
        );
        expect(resumeBody, contains("action: 'resume'"));
        expect(resumeBody, contains('_postMollieCheckoutRecovery('));
        expect(resumeBody, contains('resolveMollieHostedResumeOutcome'));
        expect(resumeBody, contains('launchUrl('));
        expect(resumeBody, contains('LaunchMode.externalApplication'));
        expect(resumeBody, contains('_mollieRecoveryBusy'));
        expect(resumeBody, isNot(contains('/street-checkout')));
        expect(resumeBody, isNot(contains('_startMollieStreetCheckout')));
      },
    );

    test(
      'MOLLIE-HOSTED-RESUME-P0: after launch, app resume still auto-refreshes',
      () {
        expect(receiptSource, contains("reason: 'app_resume'"));
        expect(
          receiptSource,
          contains('_maybeAuthoritativeMollieCheckoutRefresh'),
        );
        expect(
          receiptSource,
          contains('void didChangeAppLifecycleState(AppLifecycleState state)'),
        );
      },
    );

    test('street dialog uses generic Mollie instruction (not Bancontact-only)', () {
      expect(
        receiptSource,
        contains("_receiptText('onlinePayInstruction')"),
      );
      expect(
        receiptSource,
        contains('MollieStreetCheckoutDialogContent('),
      );
      expect(receiptSource, isNot(contains('_MollieStreetCheckoutDialogContent(')));
    });

    test('cash/bancontact conflict path supports confirm_cancel_open_mollie', () {
      expect(
        receiptSource,
        contains('manualPaymentBlockedByOpenMollieCheckout('),
      );
      expect(
        receiptSource,
        contains("'confirm_cancel_open_mollie': true"),
      );
      expect(
        receiptSource,
        contains('confirmCancelOpenMollie'),
      );
      expect(
        receiptSource,
        contains('_showOpenMollieRecoveryDialog'),
      );
      expect(
        receiptSource,
        contains('MollieOpenPaymentRecoveryChoice'),
      );
    });

    test(
      'HIDE-MANUAL-BANCONTACT-P1: primary zone keeps online/QR/cash/invoice',
      () {
        final sectionIdx = receiptSource.indexOf(
          'Widget _paymentSection(BuildContext context) {',
        );
        expect(sectionIdx, greaterThan(-1));
        final sectionBody = receiptSource.substring(
          sectionIdx,
          sectionIdx + 14000,
        );
        expect(sectionBody, contains("_receiptText('onlinePay')"));
        expect(sectionBody, contains("_receiptText('payByQr')"));
        expect(sectionBody, contains("_receiptText('cashReceived')"));
        expect(sectionBody, contains('_shouldShowStreetInvoicePaymentSlot()'));
        expect(
          sectionBody,
          isNot(contains("_receiptText('paidByCardTerminal')")),
        );
      },
    );

    test(
      'PHANTOM-P0: booking change clears local open-Mollie recovery owner',
      () {
        final idx = receiptSource.indexOf(
          'void didUpdateWidget(covariant _RideReceiptBody oldWidget)',
        );
        expect(idx, greaterThan(-1));
        final body = receiptSource.substring(idx, idx + 1800);
        expect(
          body,
          contains('shouldResetOpenMollieRecoveryForBookingChange('),
        );
        expect(body, contains('_openMollieRecovery = null'));
        expect(body, contains('_mollieRecoveryBusy = false'));
        // Tap-to-Pay parse must pass the actual HTTP status (no hardcoded 409).
        expect(
          receiptSource,
          contains('parseMollieOpenPaymentRecovery(\n'),
        );
        expect(
          receiptSource,
          contains('httpCode: httpCode'),
        );
      },
    );

    test('paid poll outcome refreshes receipt paid state via canonical helper', () {
      expect(
        receiptSource,
        contains('Future<void> _markMollieStreetCheckoutPaid(BuildContext context) async {'),
      );
      final idx = receiptSource.indexOf(
        'Future<void> _markMollieStreetCheckoutPaid(BuildContext context) async {',
      );
      final body = receiptSource.substring(idx, idx + 2000);
      expect(body, contains('_mergePaymentFieldsIntoReceiptDetails('));
      expect(body, contains('_ReceiptPaymentStatus.paid'));
      expect(body, contains('_appendPaymentUpdateLedgerIfPaid('));
    });

    test('all new translation keys exist for NL/EN/FR/ES', () {
      const keys = <String>[
        'onlinePay',
        'onlinePaySubtitle',
        'onlinePayInstruction',
        'waitingForPayment',
        'paymentStillProcessing',
        'paymentStatusAuthError',
        'paymentStatusNotFoundError',
        'paymentStatusServerError',
        'paymentStatusGenericError',
        'paymentRefreshFailed',
        'iHavePaid',
        'paymentSucceeded',
        'paymentFailed',
        'paymentCancelled',
        'paymentExpired',
        'tryAgain',
        'noOnlineMethods',
        'mollieNotConnected',
        'openPaymentExists',
        'rideAlreadyPaid',
        'cancelOpenMollieConfirm',
        'openPaymentRecoveryBody',
        'checkPaymentStatus',
        'resumeOnlinePayment',
        'cancelOnlinePayment',
        'cancelOnlinePaymentHint',
        'cancelOnlinePaymentBusy',
        'cancelOnlinePaymentFailed',
        'paymentStillPending',
        'paymentOwnerReleased',
        'paymentRecoveryError',
      ];
      for (final key in keys) {
        final caseIdx = textHelpersSource.indexOf("case '$key':");
        expect(caseIdx, greaterThan(-1), reason: 'missing case for "$key"');
        final nextCaseIdx = textHelpersSource.indexOf(
          "\n    case '",
          caseIdx + 1,
        );
        final block = textHelpersSource.substring(
          caseIdx,
          nextCaseIdx == -1 ? textHelpersSource.length : nextCaseIdx,
        );
        expect(block, contains('nl:'), reason: '"$key" missing nl:');
        expect(block, contains('en:'), reason: '"$key" missing en:');
        expect(block, contains('fr:'), reason: '"$key" missing fr:');
        expect(block, contains('es:'), reason: '"$key" missing es:');
      }
    });
  });
}
