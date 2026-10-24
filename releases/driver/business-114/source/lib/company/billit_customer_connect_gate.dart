/// Temporary customer-facing Billit connect gate while production approval
/// is pending. Ordinary customers must never be sent to the Billit sandbox
/// OAuth host. Sandbox connect is available only when the booking worker
/// returns a trusted `company_sandbox_oauth_allowed` entitlement.
library;

enum BillitCustomerConnectMode {
  /// Already connected — keep status/disconnect; no new OAuth start.
  connected,

  /// Production OAuth is active and connect is allowed.
  productionReady,

  /// Production approval still pending (or worker is sandbox-locked).
  productionApprovalPending,

  /// Sandbox OAuth allowed for server-entitled internal/test companies only.
  sandboxInternalAllowed,
}

/// Language-independent presentation inputs for the Billit settings card.
class BillitCustomerConnectPresentation {
  final BillitCustomerConnectMode mode;
  final bool connectButtonEnabled;
  final bool showApprovalPendingBanner;
  final bool showSandboxInternalHint;

  const BillitCustomerConnectPresentation({
    required this.mode,
    required this.connectButtonEnabled,
    required this.showApprovalPendingBanner,
    required this.showSandboxInternalHint,
  });
}

/// Resolves customer Billit connect UX from status + server entitlement.
///
/// [environment] comes from the worker status (`sandbox` | `production`).
/// [allowSandboxConnect] must reflect ONLY the server field
/// `company_sandbox_oauth_allowed` (master flag + company allowlist).
/// Never enable sandbox from a client-only switch.
/// [productionConnectEnabled] is reserved for when production OAuth is
/// intentionally opened to ordinary customers (worker env = production).
BillitCustomerConnectPresentation resolveBillitCustomerConnectPresentation({
  required bool configured,
  required bool connected,
  required String environment,
  bool allowSandboxConnect = false,
  bool productionConnectEnabled = false,
}) {
  if (connected) {
    return const BillitCustomerConnectPresentation(
      mode: BillitCustomerConnectMode.connected,
      connectButtonEnabled: false,
      showApprovalPendingBanner: false,
      showSandboxInternalHint: false,
    );
  }

  final env = environment.trim().toLowerCase();
  final isProduction = env == 'production';

  if (isProduction && productionConnectEnabled && configured) {
    return const BillitCustomerConnectPresentation(
      mode: BillitCustomerConnectMode.productionReady,
      connectButtonEnabled: true,
      showApprovalPendingBanner: false,
      showSandboxInternalHint: false,
    );
  }

  if (!isProduction && allowSandboxConnect && configured) {
    return const BillitCustomerConnectPresentation(
      mode: BillitCustomerConnectMode.sandboxInternalAllowed,
      connectButtonEnabled: true,
      showApprovalPendingBanner: false,
      showSandboxInternalHint: true,
    );
  }

  // Default for ordinary customers while Billit production approval is pending
  // OR while the worker remains sandbox-locked without internal entitlement.
  return const BillitCustomerConnectPresentation(
    mode: BillitCustomerConnectMode.productionApprovalPending,
    connectButtonEnabled: false,
    showApprovalPendingBanner: true,
    showSandboxInternalHint: false,
  );
}

/// Deprecated compile-time flag — must NOT unlock sandbox alone.
/// Kept for source compatibility; Bedrijfsinstellingen trusts only the
/// server `company_sandbox_oauth_allowed` entitlement.
@Deprecated('Use server company_sandbox_oauth_allowed entitlement only')
const bool kFluxidiBillitAllowSandboxConnect = bool.fromEnvironment(
  'FLUXIDI_BILLIT_ALLOW_SANDBOX_CONNECT',
  defaultValue: false,
);
