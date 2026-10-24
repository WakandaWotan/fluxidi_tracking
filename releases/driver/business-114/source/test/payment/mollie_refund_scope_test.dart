import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/payment/mollie_refund_scope.dart';

void main() {
  test('legacy grants without stored scopes stay unknown', () {
    expect(mollieConnectRefundsWriteGranted(oauthScopes: null), isNull);
    expect(mollieConnectNeedsRefundsWriteReconnect(oauthScopes: null), isFalse);
  });

  test('current Connect grant without refunds.write needs reconnect', () {
    const scopes =
        'organizations.read profiles.read payments.read payments.write refunds.read terminals.read onboarding.read';
    expect(
      mollieConnectRefundsWriteGranted(oauthScopes: scopes),
      isFalse,
    );
    expect(
      mollieConnectNeedsRefundsWriteReconnect(oauthScopes: scopes),
      isTrue,
    );
  });

  test('grant with refunds.write does not ask for reconnect', () {
    const scopes =
        'organizations.read profiles.read payments.read payments.write refunds.read refunds.write terminals.read onboarding.read';
    expect(mollieConnectRefundsWriteGranted(oauthScopes: scopes), isTrue);
    expect(mollieConnectNeedsRefundsWriteReconnect(oauthScopes: scopes), isFalse);
  });
}
