import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/company/billit_customer_connect_gate.dart';

void main() {
  group('resolveBillitCustomerConnectPresentation', () {
    test('1) ordinary company cannot connect to sandbox', () {
      final p = resolveBillitCustomerConnectPresentation(
        configured: true,
        connected: false,
        environment: 'sandbox',
        allowSandboxConnect: false,
      );
      expect(p.mode, BillitCustomerConnectMode.productionApprovalPending);
      expect(p.connectButtonEnabled, isFalse);
      expect(p.showApprovalPendingBanner, isTrue);
      expect(p.showSandboxInternalHint, isFalse);
    });

    test('2) ordinary company receives no sandbox-connect affordance', () {
      final p = resolveBillitCustomerConnectPresentation(
        configured: true,
        connected: false,
        environment: 'sandbox',
        allowSandboxConnect: false,
      );
      // UI must not present internal sandbox mode without server entitlement.
      expect(p.mode, isNot(BillitCustomerConnectMode.sandboxInternalAllowed));
      expect(p.connectButtonEnabled, isFalse);
      expect(p.showSandboxInternalHint, isFalse);
    });

    test('3) internal entitled session can connect', () {
      final p = resolveBillitCustomerConnectPresentation(
        configured: true,
        connected: false,
        environment: 'sandbox',
        allowSandboxConnect: true,
      );
      expect(p.mode, BillitCustomerConnectMode.sandboxInternalAllowed);
      expect(p.connectButtonEnabled, isTrue);
      expect(p.showApprovalPendingBanner, isFalse);
      expect(p.showSandboxInternalHint, isTrue);
    });

    test('4) internal entitled session can disconnect and reconnect', () {
      final connected = resolveBillitCustomerConnectPresentation(
        configured: true,
        connected: true,
        environment: 'sandbox',
        allowSandboxConnect: true,
      );
      expect(connected.mode, BillitCustomerConnectMode.connected);
      expect(connected.connectButtonEnabled, isFalse);

      final afterDisconnect = resolveBillitCustomerConnectPresentation(
        configured: true,
        connected: false,
        environment: 'sandbox',
        allowSandboxConnect: true,
      );
      expect(
        afterDisconnect.mode,
        BillitCustomerConnectMode.sandboxInternalAllowed,
      );
      expect(afterDisconnect.connectButtonEnabled, isTrue);
    });

    test('5) removing entitlement restores production gate', () {
      final entitled = resolveBillitCustomerConnectPresentation(
        configured: true,
        connected: false,
        environment: 'sandbox',
        allowSandboxConnect: true,
      );
      expect(entitled.connectButtonEnabled, isTrue);

      final revoked = resolveBillitCustomerConnectPresentation(
        configured: true,
        connected: false,
        environment: 'sandbox',
        allowSandboxConnect: false,
      );
      expect(revoked.mode, BillitCustomerConnectMode.productionApprovalPending);
      expect(revoked.connectButtonEnabled, isFalse);
      expect(revoked.showApprovalPendingBanner, isTrue);
    });

    test('6) client cannot self-assert internal access without server flag', () {
      // Even if configured+sandbox, without allowSandboxConnect (server
      // company_sandbox_oauth_allowed) the gate stays closed.
      final p = resolveBillitCustomerConnectPresentation(
        configured: true,
        connected: false,
        environment: 'sandbox',
      );
      expect(p.connectButtonEnabled, isFalse);
      expect(p.mode, BillitCustomerConnectMode.productionApprovalPending);
    });

    test('production ready enables connect for ordinary customers', () {
      final p = resolveBillitCustomerConnectPresentation(
        configured: true,
        connected: false,
        environment: 'production',
        productionConnectEnabled: true,
      );
      expect(p.mode, BillitCustomerConnectMode.productionReady);
      expect(p.connectButtonEnabled, isTrue);
      expect(p.showApprovalPendingBanner, isFalse);
    });

    test('production env without enable flag stays approval pending', () {
      final p = resolveBillitCustomerConnectPresentation(
        configured: true,
        connected: false,
        environment: 'production',
        productionConnectEnabled: false,
      );
      expect(p.mode, BillitCustomerConnectMode.productionApprovalPending);
      expect(p.connectButtonEnabled, isFalse);
    });

    test('unconfigured ordinary customer still shows pending, not sandbox connect', () {
      final p = resolveBillitCustomerConnectPresentation(
        configured: false,
        connected: false,
        environment: 'sandbox',
        allowSandboxConnect: true,
      );
      expect(p.connectButtonEnabled, isFalse);
      expect(p.showApprovalPendingBanner, isTrue);
    });
  });
}
