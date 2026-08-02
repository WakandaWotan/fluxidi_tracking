import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/company/billit_customer_connect_gate.dart';

void main() {
  group('resolveBillitCustomerConnectPresentation', () {
    test('ordinary customer on sandbox sees approval pending; connect disabled', () {
      final p = resolveBillitCustomerConnectPresentation(
        configured: true,
        connected: false,
        environment: 'sandbox',
        allowSandboxConnect: false,
      );
      expect(p.mode, BillitCustomerConnectMode.productionApprovalPending);
      expect(p.connectButtonEnabled, isFalse);
      expect(p.showApprovalPendingBanner, isTrue);
    });

    test('internal sandbox allow enables connect without customer pending banner', () {
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

    test('already connected keeps disconnect path; no pending banner', () {
      final p = resolveBillitCustomerConnectPresentation(
        configured: true,
        connected: true,
        environment: 'sandbox',
        allowSandboxConnect: false,
      );
      expect(p.mode, BillitCustomerConnectMode.connected);
      expect(p.connectButtonEnabled, isFalse);
      expect(p.showApprovalPendingBanner, isFalse);
    });

    test('unconfigured ordinary customer still shows pending, not sandbox connect', () {
      final p = resolveBillitCustomerConnectPresentation(
        configured: false,
        connected: false,
        environment: 'sandbox',
      );
      expect(p.connectButtonEnabled, isFalse);
      expect(p.showApprovalPendingBanner, isTrue);
    });
  });
}
