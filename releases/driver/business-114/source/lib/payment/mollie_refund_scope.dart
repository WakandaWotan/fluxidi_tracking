// Mollie Connect refund scopes. `refunds_write_granted` is derived from the
// stored token `scope` that Mollie actually granted, not from requested
// authorize scopes or a browser return.

const String kMollieConnectRefundsWriteScope = 'refunds.write';
const String kMollieConnectRefundsReadScope = 'refunds.read';

bool mollieConnectScopeGranted(String? oauthScopes, String needed) {
  final want = needed.trim().toLowerCase();
  if (want.isEmpty) return false;
  final tokens = (oauthScopes ?? '')
      .toLowerCase()
      .split(RegExp(r'[\s,]+'))
      .where((part) => part.isNotEmpty);
  return tokens.contains(want);
}

/// `null` means the stored grant predates scope capture — unknown, not false.
bool? mollieConnectRefundsWriteGranted({
  String? oauthScopes,
  bool? refundsWriteGranted,
}) {
  if (refundsWriteGranted != null) return refundsWriteGranted;
  if ((oauthScopes ?? '').trim().isEmpty) return null;
  return mollieConnectScopeGranted(
    oauthScopes,
    kMollieConnectRefundsWriteScope,
  );
}

bool mollieConnectNeedsRefundsWriteReconnect({
  String? oauthScopes,
  bool? refundsWriteGranted,
}) {
  return mollieConnectRefundsWriteGranted(
        oauthScopes: oauthScopes,
        refundsWriteGranted: refundsWriteGranted,
      ) ==
      false;
}
