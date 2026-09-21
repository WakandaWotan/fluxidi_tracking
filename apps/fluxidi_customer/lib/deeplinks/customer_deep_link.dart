import '../app/customer_app_config.dart';

/// What an incoming link is allowed to do in this app.
enum CustomerDeepLinkKind {
  /// Open a neutral payment-return screen. Never a confirmation.
  paymentReturn,

  /// Anything this app does not answer to.
  unsupported,
}

class CustomerDeepLinkResult {
  const CustomerDeepLinkResult._(this.kind, this.reason);

  const CustomerDeepLinkResult.paymentReturn()
    : this._(CustomerDeepLinkKind.paymentReturn, 'own_payment_return');

  const CustomerDeepLinkResult.unsupported(String reason)
    : this._(CustomerDeepLinkKind.unsupported, reason);

  final CustomerDeepLinkKind kind;

  /// Diagnostic reason. Never contains link query values.
  final String reason;

  bool get opensPaymentReturnScreen =>
      kind == CustomerDeepLinkKind.paymentReturn;
}

/// Resolves an incoming link against this app's own scheme only.
///
/// The query string is deliberately never inspected: a return link is a
/// navigation trigger, not a payment result. Payment and booking state stay
/// server-owned and are not wired up in this phase.
CustomerDeepLinkResult resolveCustomerDeepLink(
  Uri uri, {
  CustomerAppConfig config = kCustomerAppConfig,
}) {
  if (uri.scheme.toLowerCase() != config.deepLinkScheme.toLowerCase()) {
    return const CustomerDeepLinkResult.unsupported('foreign_scheme');
  }
  if (uri.host.toLowerCase() != config.deepLinkHost.toLowerCase()) {
    return const CustomerDeepLinkResult.unsupported('unknown_host');
  }
  if (_normalizePath(uri.path) != _normalizePath(config.deepLinkPath)) {
    return const CustomerDeepLinkResult.unsupported('unknown_path');
  }
  return const CustomerDeepLinkResult.paymentReturn();
}

String _normalizePath(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty || trimmed == '/') return '/';
  final withSlash = trimmed.startsWith('/') ? trimmed : '/$trimmed';
  return withSlash.endsWith('/')
      ? withSlash.substring(0, withSlash.length - 1)
      : withSlash;
}
