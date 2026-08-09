// GOOGLE-PLAY-SAAS-CONSUMPTION-ONLY-P0
//
// Proves the Play-distributed build cannot start company SaaS Mollie checkout,
// while ride Mollie / QR / cash / Tap paths remain ungated, and subscription
// entitlement reads are still wired.
//
// Run:
//   flutter test test/company/play_saas_consumption_only_p0_test.dart

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/company/fluxidi_play_distribution.dart';
import 'package:fluxidi_tracking/payment/payment_method_catalog.dart';

String _read(String relativePath) {
  final file = File(relativePath);
  if (!file.existsSync()) fail('Missing $relativePath');
  return file.readAsStringSync();
}

void main() {
  group('GOOGLE-PLAY-SAAS-CONSUMPTION-ONLY-P0 helpers', () {
    test('Play distribution disables company SaaS Mollie checkout', () {
      expect(
        mayStartCompanySaasMollieCheckout(playDistribution: true),
        isFalse,
      );
      expect(
        mayStartCompanySaasMollieCheckout(playDistribution: false),
        isTrue,
      );
    });

    test('default compile-time flag is off (field builds keep checkout)', () {
      // This test binary is not built with FLUXIDI_PLAY_DISTRIBUTION=true.
      expect(kFluxidiPlayDistribution, isFalse);
      expect(kFluxidiCompanySaasCheckoutEnabled, isTrue);
    });

    test('Play notice copy has no checkout URL or Mollie link', () {
      for (final lang in const ['nl', 'en', 'fr', 'es']) {
        final msg = fluxidiPlaySaasManagedOutsideMessage(languageCode: lang);
        expect(msg.toLowerCase(), contains('google play'));
        expect(msg.contains('http'), isFalse);
        expect(msg.toLowerCase(), isNot(contains('mollie')));
        expect(msg.contains('checkout'), isFalse);
      }
    });
  });

  group('GOOGLE-PLAY-SAAS-CONSUMPTION-ONLY-P0 source contracts', () {
    test('API checkout starters hard-gate on Play SaaS flag', () {
      final config = _read('lib/app_config.dart');
      expect(config.contains('kFluxidiCompanySaasCheckoutEnabled'), isTrue);
      expect(
        config.contains('kFluxidiCompanySaasCheckoutDisabledError'),
        isTrue,
      );
      expect(
        _read('lib/company/fluxidi_play_distribution.dart'),
        contains(kFluxidiCompanySaasCheckoutDisabledError),
      );
      // Both SaaS starters must return before HTTP when disabled.
      expect(
        config.contains('[SUBSCRIPTION_CHECKOUT_START][BLOCKED]'),
        isTrue,
      );
      expect(
        config.contains('[SUBSCRIPTION_ADDON_CHECKOUT_START][BLOCKED]'),
        isTrue,
      );
    });

    test('subscription billing UI hides purchase CTAs on Play', () {
      final ui = _read('lib/main_parts/company_subscription_billing_state.dart');
      expect(ui.contains('kFluxidiCompanySaasCheckoutEnabled'), isTrue);
      expect(ui.contains('_playSaasManagedOutsideNotice'), isTrue);
      expect(ui.contains('fluxidiPlaySaasManagedOutsideMessage'), isTrue);
      // Entitlement/status fetch must remain.
      expect(ui.contains('fetchCompanySubscriptionProfile'), isTrue);
    });

    test('ride Mollie checkout is not gated by Play SaaS flag', () {
      final street = _read('lib/payment/mollie_street_checkout.dart');
      expect(street.contains('kFluxidiPlayDistribution'), isFalse);
      expect(street.contains('kFluxidiCompanySaasCheckoutEnabled'), isFalse);
      expect(street.contains('play_saas_checkout_disabled'), isFalse);
    });

    test('QR / cash / Tap catalog ids remain available', () {
      expect(PaymentMethodCatalog.knownIds, contains(PaymentMethodIds.cash));
      expect(PaymentMethodCatalog.knownIds, contains(PaymentMethodIds.qrCode));
      expect(
        PaymentMethodCatalog.knownIds,
        contains(PaymentMethodIds.onlinePayment),
      );
      final receipt = _read('lib/main_parts/ride_receipt_body_state.dart');
      expect(receipt.contains('_startTapToPay'), isTrue);
      expect(receipt.contains('kFluxidiPlayDistribution'), isFalse);
      expect(receipt.contains('kFluxidiCompanySaasCheckoutEnabled'), isFalse);
    });

    test('Play release scripts/docs use FLUXIDI_PLAY_DISTRIBUTION define', () {
      final example = File('android/key.properties.example');
      expect(example.existsSync(), isTrue);
      // The release build entry used for Play must pass the define. Prefer a
      // checked-in script when present; otherwise the source gate + this suite
      // remain the contract and the build command is verified at build time.
      final buildScript = File('scripts/build_fluxidi_play_aab.ps1');
      expect(buildScript.existsSync(), isTrue);
      final text = buildScript.readAsStringSync();
      expect(text.contains('FLUXIDI_PLAY_DISTRIBUTION=true'), isTrue);
      expect(text.contains('flutter build appbundle'), isTrue);
      // Must not inject Play Billing.
      expect(text.toLowerCase(), isNot(contains('in_app_purchase')));
    });
  });
}
