/// Temporary customer-facing Billit connect gate while production approval
/// is pending. Ordinary customers must never be sent to the Billit sandbox
/// OAuth host. Sandbox connect remains available only when explicitly allowed
/// (internal/admin/test builds via dart-define).
library;

enum BillitCustomerConnectMode {
  /// Already connected — keep status/disconnect; no new OAuth start.
  connected,

  /// Production OAuth is active and connect is allowed.
  productionReady,

  /// Production approval still pending (or worker is sandbox-locked).
  productionApprovalPending,

  /// Sandbox OAuth allowed for explicit internal/test builds only.
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

/// Resolves customer Billit connect UX from status + local allow flags.
///
/// [environment] comes from the worker status (`sandbox` | `production`).
/// [allowSandboxConnect] must be true only for explicit internal/test builds
/// (`--dart-define=FLUXIDI_BILLIT_ALLOW_SANDBOX_CONNECT=true`).
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
  // OR while the worker remains sandbox-locked.
  return const BillitCustomerConnectPresentation(
    mode: BillitCustomerConnectMode.productionApprovalPending,
    connectButtonEnabled: false,
    showApprovalPendingBanner: true,
    showSandboxInternalHint: false,
  );
}

/// Compile-time flag for internal/admin/test builds that may use sandbox OAuth.
const bool kFluxidiBillitAllowSandboxConnect = bool.fromEnvironment(
  'FLUXIDI_BILLIT_ALLOW_SANDBOX_CONNECT',
  defaultValue: false,
);
