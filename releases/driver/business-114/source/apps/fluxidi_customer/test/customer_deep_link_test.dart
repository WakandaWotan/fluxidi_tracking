import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_customer/app/customer_app_config.dart';
import 'package:fluxidi_customer/deeplinks/customer_deep_link.dart';

void main() {
  group('resolveCustomerDeepLink', () {
    test('accepts this app\'s own payment-return link', () {
      final result = resolveCustomerDeepLink(
        Uri.parse('${kCustomerAppConfig.deepLinkScheme}://pay/return'),
      );

      expect(result.kind, CustomerDeepLinkKind.paymentReturn);
      expect(result.opensPaymentReturnScreen, isTrue);
    });

    test('rejects the existing app\'s fluxidi://pay/return link', () {
      final result = resolveCustomerDeepLink(
        Uri.parse('fluxidi://pay/return?payment_booking_id=abc'),
      );

      expect(result.kind, CustomerDeepLinkKind.unsupported);
      expect(result.reason, 'foreign_scheme');
      expect(result.opensPaymentReturnScreen, isFalse);
    });

    test('rejects an unknown host and an unknown path on the own scheme', () {
      expect(
        resolveCustomerDeepLink(
          Uri.parse('${kCustomerAppConfig.deepLinkScheme}://booking/return'),
        ).reason,
        'unknown_host',
      );
      expect(
        resolveCustomerDeepLink(
          Uri.parse('${kCustomerAppConfig.deepLinkScheme}://pay/confirm'),
        ).reason,
        'unknown_path',
      );
    });

    test('a status query parameter changes nothing about the outcome', () {
      final plain = resolveCustomerDeepLink(
        Uri.parse('${kCustomerAppConfig.deepLinkScheme}://pay/return'),
      );
      final claimingPaid = resolveCustomerDeepLink(
        Uri.parse('${kCustomerAppConfig.deepLinkScheme}://pay/return?status=paid&paid=true'),
      );

      expect(claimingPaid.kind, plain.kind);
      expect(claimingPaid.reason, plain.reason);
    });

    test('scheme and host match case-insensitively', () {
      final result = resolveCustomerDeepLink(
        Uri.parse('${kCustomerAppConfig.deepLinkScheme.toUpperCase()}://PAY/return'),
      );

      expect(result.opensPaymentReturnScreen, isTrue);
    });

    test('config exposes the compiled identity used by the manifest', () {
      expect(kCustomerAppConfig.androidApplicationId, kCustomerStagingRuntime ? 'com.fluxidi.customer.staging' : 'com.fluxidi.customer');
      expect(
        kCustomerAppConfig.paymentReturnUrl,
        '${kCustomerAppConfig.deepLinkScheme}://pay/return',
      );
      expect(kCustomerAppConfig.variant, CustomerAppVariant.fluxidiMarketplace);
    });
  });
}
