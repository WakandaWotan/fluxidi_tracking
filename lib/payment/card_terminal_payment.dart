// TAP-TO-PAY-DRIVER-UI-1 / CARD-TERMINAL-PAYMENT-CONFIRMATION-1
//
// Pure, dependency-free decision model for card-terminal (Mollie Point of Sale)
// / Tap to Pay payments made from the driver ride receipt.
//
// SAFETY CONTRACT
// ---------------
// A card-terminal payment may ONLY be recorded as paid after the provider
// (Mollie) explicitly reports SUCCESS (Mollie `paid`). Every other outcome —
// declined, cancelled, failed, timeout, pending/open, missing callback, or ANY
// HTTP / provider error — keeps the ride unpaid/pending.
//
// This module never inspects time, amount, or address to decide paid-ness.

import 'package:fluxidi_tracking/payment/mollie_capability_status.dart';

/// Classified outcome of a card-terminal payment attempt.
enum CardTerminalOutcome {
  /// Provider explicitly confirmed the payment (Mollie `paid`).
  success,

  /// The shopper's card/PIN was declined by the terminal/issuer.
  declined,

  /// The shopper or driver cancelled the terminal transaction.
  cancelled,

  /// The provider reported an explicit failure/expiry.
  failed,

  /// The terminal did not respond in time (no final status yet).
  timeout,

  /// Any HTTP / provider error (incl. 422) or an unrecognised status.
  error,

  /// A non-final status (open / pending / authorized) — keep waiting.
  pending,
}

/// Phase labels for the `[CARD_TERMINAL_PAYMENT]` diagnostic line.
class CardTerminalPhase {
  static const String launch = 'launch';
  static const String callback = 'callback';
  static const String confirm = 'confirm';
  static const String decline = 'decline';
  static const String cancel = 'cancel';
  static const String error = 'error';
}

String _norm(Object? value) => (value ?? '').toString().trim().toLowerCase();

/// Classifies a provider result into a [CardTerminalOutcome].
///
/// Only an official server-verified Mollie payment status may map to success.
/// Bare client/provider text such as `approved` or `success` is NEVER treated
/// as proof of payment. `settled` is payout/settlement, not shopper paid.
CardTerminalOutcome classifyCardTerminalProviderStatus({
  String? providerStatus,
  int? httpCode,
  String? providerCode,
}) {
  if (httpCode != null && httpCode >= 400) {
    return CardTerminalOutcome.error;
  }
  switch (_norm(providerStatus)) {
    case 'paid':
      return CardTerminalOutcome.success;
    case 'failed':
    case 'expired':
      return CardTerminalOutcome.failed;
    case 'canceled':
    case 'cancelled':
      return CardTerminalOutcome.cancelled;
    case 'declined':
    case 'denied':
    case 'refused':
      return CardTerminalOutcome.declined;
    case 'timeout':
    case 'timed_out':
      return CardTerminalOutcome.timeout;
    case 'open':
    case 'pending':
    case 'authorized':
    case 'created':
    case 'settled':
    case 'approved':
    case 'success':
      return CardTerminalOutcome.pending;
    default:
      return CardTerminalOutcome.error;
  }
}

/// The ONLY predicate that authorises treating a card-terminal payment as paid.
bool cardTerminalShouldWritePaid(CardTerminalOutcome outcome) {
  return outcome == CardTerminalOutcome.success;
}

/// Whether the backend start response is a valid open POS intent.
bool cardTerminalStartIsValidIntent({
  required int httpCode,
  required bool ok,
  String? paymentId,
  String? status,
  String? mollieStatus,
}) {
  final is2xx = httpCode >= 200 && httpCode < 300;
  final hasIntent = (paymentId ?? '').trim().isNotEmpty;
  final s = _norm(status);
  final serverStarted = s == 'created' || s == 'existing_open';
  final outcome = classifyCardTerminalProviderStatus(
    providerStatus: mollieStatus,
    httpCode: is2xx ? null : httpCode,
  );
  return is2xx &&
      ok &&
      hasIntent &&
      serverStarted &&
      outcome == CardTerminalOutcome.pending;
}

/// True when the outcome is final (no more polling needed).
bool cardTerminalIsTerminalOutcome(CardTerminalOutcome outcome) {
  return outcome != CardTerminalOutcome.pending;
}

/// Receipt-status text key for a non-success terminal outcome.
String? cardTerminalUserMessageKey(CardTerminalOutcome outcome) {
  switch (outcome) {
    case CardTerminalOutcome.success:
      return null;
    case CardTerminalOutcome.pending:
      return 'cardTerminalProcessing';
    case CardTerminalOutcome.declined:
      return 'tapToPayDeclined';
    case CardTerminalOutcome.cancelled:
      return 'tapToPayCancelled';
    case CardTerminalOutcome.failed:
    case CardTerminalOutcome.timeout:
    case CardTerminalOutcome.error:
      return 'cardTerminalRetryOrOther';
  }
}

/// Stable reason token for diagnostics (no PII).
String cardTerminalOutcomeReason(CardTerminalOutcome outcome) {
  switch (outcome) {
    case CardTerminalOutcome.success:
      return 'provider_success';
    case CardTerminalOutcome.declined:
      return 'provider_declined';
    case CardTerminalOutcome.cancelled:
      return 'provider_cancelled';
    case CardTerminalOutcome.failed:
      return 'provider_failed';
    case CardTerminalOutcome.timeout:
      return 'provider_timeout';
    case CardTerminalOutcome.error:
      return 'provider_error_or_missing_status';
    case CardTerminalOutcome.pending:
      return 'provider_pending';
  }
}

/// Bounded, PII-free `[CARD_TERMINAL_PAYMENT]` diagnostic line.
String cardTerminalDiagnosticsLine({
  required String phase,
  required int amountCents,
  String? providerStatus,
  String? providerCode,
  required bool paymentWritten,
  required String reason,
}) {
  final status = (providerStatus ?? '').trim();
  final code = (providerCode ?? '').trim();
  return '[CARD_TERMINAL_PAYMENT] '
      'phase=$phase '
      'amountCents=$amountCents '
      'providerStatus=${status.isEmpty ? '-' : status} '
      'providerCode=${code.isEmpty ? '-' : code} '
      'paymentWritten=$paymentWritten '
      'reason=$reason';
}

/// Show the Tap to Pay action only when capability reports an active terminal.
bool shouldShowTapToPayAction(InPersonTerminalStatus status) =>
    inPersonTerminalPaymentAvailable(status);

/// Resolve capability status from a driver/company terminal capability payload.
InPersonTerminalStatus resolveTapToPayCapabilityStatus(Map<String, dynamic>? raw) {
  if (raw == null) return InPersonTerminalStatus.noTerminal;
  final available = raw['available'] == true;
  final statusToken = _norm(
    raw['status'] ?? raw['terminal_status'] ?? raw['capability'],
  );
  if (statusToken == 'active_terminal' || statusToken == 'activeterminal') {
    return InPersonTerminalStatus.activeTerminal;
  }
  if (statusToken == 'multiple_terminals_need_default' ||
      statusToken == 'terminal_selection_required') {
    return InPersonTerminalStatus.multipleTerminalsNeedDefault;
  }
  if (statusToken == 'connected_no_active_terminal') {
    return InPersonTerminalStatus.connectedNoActiveTerminal;
  }
  if (statusToken == 'snapshot_stale') {
    return InPersonTerminalStatus.snapshotStale;
  }
  if (statusToken == 'error' || statusToken == 'fetch_failed') {
    return InPersonTerminalStatus.error;
  }
  if (available && statusToken.isEmpty) {
    return InPersonTerminalStatus.activeTerminal;
  }
  return InPersonTerminalStatus.noTerminal;
}

/// True when a snapshot terminal is Fluxidi-forgotten (removed from UI).
bool isMollieTerminalForgottenInSnapshot(Map terminal) {
  return terminal['forgotten'] == true ||
      terminal['forgotten'] == 'true' ||
      terminal['removed_from_fluxidi'] == true;
}

/// True when a snapshot terminal is Fluxidi-excluded / unlinked / forgotten.
bool isMollieTerminalExcludedInSnapshot(Map terminal) {
  if (isMollieTerminalForgottenInSnapshot(terminal)) return true;
  if (terminal['excluded'] == true || terminal['excluded'] == 'true') {
    return true;
  }
  if (terminal['linked'] == false || terminal['linked'] == 'false') {
    return true;
  }
  return false;
}

/// Terminals eligible for Tap to Pay from a company snapshot.
List<Map<String, dynamic>> selectableMollieTerminalsFromSnapshot(
  Map<String, dynamic>? snapshot,
) {
  if (snapshot == null) return const <Map<String, dynamic>>[];
  final terminalsRaw = snapshot['terminals'];
  if (terminalsRaw is! List) return const <Map<String, dynamic>>[];
  final out = <Map<String, dynamic>>[];
  for (final t in terminalsRaw) {
    if (t is! Map) continue;
    final map = Map<String, dynamic>.from(t);
    if (isMollieTerminalExcludedInSnapshot(map)) continue;
    if (_norm(map['status']) != 'active') continue;
    final id = (map['id'] ?? '').toString().trim();
    if (id.isEmpty) continue;
    out.add(map);
  }
  return out;
}

/// Resolve from a Mollie terminals snapshot map (admin/company fetch).
InPersonTerminalStatus resolveTapToPayStatusFromTerminalsSnapshot(
  Map<String, dynamic>? snapshot,
) {
  if (snapshot == null) return InPersonTerminalStatus.noTerminal;
  final terminalsRaw = snapshot['terminals'];
  final terminals = terminalsRaw is List ? terminalsRaw : const <dynamic>[];
  final selectable = selectableMollieTerminalsFromSnapshot(snapshot);
  final active = selectable.length;
  final hasDefault =
      (snapshot['default_terminal_id'] ?? snapshot['defaultTerminalId'] ?? '')
          .toString()
          .trim()
          .isNotEmpty;
  DateTime? syncedAt;
  final syncedRaw =
      (snapshot['synced_at'] ?? snapshot['syncedAt'] ?? '').toString().trim();
  if (syncedRaw.isNotEmpty) {
    syncedAt = DateTime.tryParse(syncedRaw);
  }
  final statusCode = (snapshot['status'] ?? '').toString().trim().isEmpty
      ? (terminals.isEmpty ? 'not_synced' : 'synced')
      : snapshot['status'].toString();
  return resolveInPersonTerminalStatus(
    snapshotStatus: statusCode,
    terminalCount: terminals.length,
    // Only linked, non-excluded, provider-active terminals count for Tap to Pay.
    activeTerminalCount: active,
    hasDefault: hasDefault,
    syncedAt: syncedAt,
  );
}

/// Phone and tablet must share one Tap-to-Pay business path (no form-factor fork).
String tapToPayLogicalPathId({required bool isTablet}) {
  // Form factor is accepted so call sites stay explicit, but it must never
  // change the logical payment path id.
  final _ = isTablet;
  return 'driver_mollie_terminal_payment';
}

/// Client must never dictate the payable amount for Tap to Pay.
bool tapToPayClientSendsAuthoritativeAmount() => false;

/// Double-tap / re-entrancy guard for Tap-to-Pay start.
class TapToPayStartGuard {
  bool _inFlight = false;

  bool get inFlight => _inFlight;

  /// Runs [action] once; concurrent/overlapping calls return `null`.
  Future<T?> runOnce<T>(Future<T> Function() action) async {
    if (_inFlight) return null;
    _inFlight = true;
    try {
      return await action();
    } finally {
      _inFlight = false;
    }
  }
}
