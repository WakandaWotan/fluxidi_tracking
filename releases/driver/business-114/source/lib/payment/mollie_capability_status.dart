// MOLLIE-ONBOARDING-STATUS-P1 (builds on MOLLIE-CAPABILITY-STATUS-SEPARATION-1)
//
// Three INDEPENDENT status models for the Business Settings "Receive payments"
// area. Previously one badge conflated account connection, online payment
// methods, and in-person/Tap terminals — so a connected LIVE account showed a
// misleading "Activation pending".
//
// These are pure, dependency-free resolvers so the separation is unit-testable.
//
//   1. Mollie account connection  — is the company's Mollie account linked?
//   2. Online payment methods     — are online methods (Bancontact/iDEAL/…) live?
//   3. In-person / terminals      — derived ONLY from the terminal snapshot.
//
// RULES enforced here:
//   * A connected LIVE account is NEVER "activation_pending" (that belongs only
//     to online payment methods).
//   * Online-method status is resolved primarily from Mollie's own authoritative
//     "can this organization receive payments" signal (`canReceivePayments`),
//     never from a client-side guess. A `null` value means the signal has never
//     been captured/refreshed and falls back to legacy signals.
//   * "Genuinely pending verification" (onboarding still in-review — Mollie is
//     reviewing) is a DIFFERENT state from "needs-data" (merchant must supply
//     missing data → Action required) and from "connected LIVE but no active
//     methods yet" (onboarding complete, still no receivable methods). These
//     must never be conflated into a single "activation pending" bucket.
//   * A failed status lookup (e.g. transient Mollie/API error) surfaces as its
//     own `lookupFailed` state and must never silently downgrade an already
//     confirmed active/complete account — callers are expected to preserve the
//     last authoritative snapshot and only use `lookupFailed` when there is no
//     prior authoritative data at all.
//   * Terminal status is derived exclusively from the terminal snapshot and is
//     never inferred from online-method activation.
//   * A stale snapshot surfaces as "snapshot_stale" (refresh required), never a
//     silent "complete".

/// 1. Mollie account connection.
enum MollieAccountConnection {
  disconnected,
  connectedLive,
  connectedTest,
  reconnectRequired,
}

/// 2. Online payment methods (Bancontact, iDEAL, cards, wallets, …).
enum OnlinePaymentMethodsStatus {
  /// Not connected (no online payment methods can be active).
  noneActive,

  /// Connected, but Mollie onboarding/verification is genuinely still in
  /// progress (`in-review` — waiting on Mollie). Distinct from `needs-data`,
  /// which maps to [actionRequired] because the merchant must act.
  activationPending,

  /// Connected LIVE, but merchant action is required: either onboarding
  /// `needs-data`, or onboarding is done and there is currently no
  /// active/receivable payment method.
  actionRequired,

  /// Some but not all known methods are active.
  partiallyActive,

  /// Connected LIVE (or TEST) with at least one active/receivable method.
  active,

  /// The most recent status lookup failed (network/API error) and there is
  /// no prior authoritative snapshot to fall back on.
  lookupFailed,

  /// MOLLIE-ONBOARDING-READ-SCOPE-P0-1: Mollie is connected but the OAuth
  /// token lacks `onboarding.read`, so live status cannot be verified.
  /// Must never be shown as activation-pending, and must not claim that
  /// online payments are disabled.
  statusCheckPermissionMissing,
}

/// 3. In-person / Tap terminals.
enum InPersonTerminalStatus {
  noTerminal,
  snapshotStale,
  connectedNoActiveTerminal,
  activeTerminal,
  multipleTerminalsNeedDefault,
  error,
}

String _norm(Object? v) => (v ?? '').toString().trim().toLowerCase();

/// Onboarding status tokens that mean "Mollie is still actively reviewing"
/// — i.e. genuinely pending on Mollie's side. Distinct from `needs-data`,
/// which is merchant action (maps to [OnlinePaymentMethodsStatus.actionRequired]).
bool _isGenuinelyPendingOnboardingStatus(String normalized) {
  const pendingTokens = {
    'in-review',
    'in_review',
    'inreview',
    'pending',
    'review',
    'waiting_for_documents',
    'waiting-for-documents',
  };
  return pendingTokens.contains(normalized);
}

/// Onboarding status tokens that mean the merchant still owes Mollie data.
bool _isNeedsDataOnboardingStatus(String normalized) {
  const tokens = {
    'needs-data',
    'needs_data',
    'needsdata',
  };
  return tokens.contains(normalized);
}

/// Resolves the account-connection status. `statusCode` is the raw connect
/// status (`connected`/`disconnected`/`failed`/`auth_required`/…); `mollieMode`
/// is `live`/`test`.
MollieAccountConnection resolveMollieAccountConnection({
  required bool connected,
  String? statusCode,
  String? mollieMode,
}) {
  final s = _norm(statusCode);
  if (s == 'failed' ||
      s == 'auth_required' ||
      s == 'reconnect_required' ||
      s == 'terminals_scope_missing') {
    return MollieAccountConnection.reconnectRequired;
  }
  if (!connected) return MollieAccountConnection.disconnected;
  return _norm(mollieMode) == 'test'
      ? MollieAccountConnection.connectedTest
      : MollieAccountConnection.connectedLive;
}

/// True when the account is connected in either live or test mode.
bool mollieAccountIsConnected(MollieAccountConnection c) =>
    c == MollieAccountConnection.connectedLive ||
    c == MollieAccountConnection.connectedTest;

/// Resolves online-method status.
///
/// Precedence (highest to lowest authority):
///  1. [lookupFailed] — the most recent live status check itself errored and
///     there is no prior authoritative snapshot at all. Callers that DO have
///     a prior good snapshot must keep showing it instead of passing this.
///  2. [canReceivePayments] — Mollie's own authoritative signal for "this
///     organization can currently receive payments" (from the Mollie
///     onboarding resource). `true` -> active. `false` -> either
///     `activationPending` (still genuinely under Mollie review) or
///     `actionRequired` (`needs-data`, or review done with no receivable
///     method), distinguished by [onboardingStatus].
///  3. Explicit method counts ([activeMethodCount]/[totalMethodCount]) — used
///     only when [canReceivePayments] is unknown (`null`), e.g. legacy cached
///     records captured before this signal existed.
///  4. [onboardingStatus] text alone — last-resort legacy fallback.
///
/// A disconnected account has no active online methods.
OnlinePaymentMethodsStatus resolveOnlinePaymentMethods({
  required bool connected,
  String? onboardingStatus,
  bool? canReceivePayments,
  int? activeMethodCount,
  int? totalMethodCount,
  bool lookupFailed = false,
  bool statusCheckPermissionMissing = false,
}) {
  if (lookupFailed) return OnlinePaymentMethodsStatus.lookupFailed;
  if (!connected) return OnlinePaymentMethodsStatus.noneActive;

  final o = _norm(onboardingStatus);
  final genuinelyPending = _isGenuinelyPendingOnboardingStatus(o);
  final needsData = _isNeedsDataOnboardingStatus(o);

  // MOLLIE-ONBOARDING-READ-SCOPE-P0-1: a 403 / missing onboarding.read must
  // never be presented as "Activation pending". Preserve a known-good
  // can_receive_payments=true; otherwise surface the permission-missing state.
  if (statusCheckPermissionMissing) {
    if (canReceivePayments == true) {
      return OnlinePaymentMethodsStatus.active;
    }
    return OnlinePaymentMethodsStatus.statusCheckPermissionMissing;
  }

  if (canReceivePayments == true) {
    return OnlinePaymentMethodsStatus.active;
  }
  if (canReceivePayments == false) {
    return genuinelyPending
        ? OnlinePaymentMethodsStatus.activationPending
        : OnlinePaymentMethodsStatus.actionRequired;
  }

  // canReceivePayments is unknown (never captured/refreshed) -> legacy
  // fallbacks below.
  if (activeMethodCount != null &&
      totalMethodCount != null &&
      totalMethodCount > 0) {
    if (activeMethodCount <= 0) {
      return genuinelyPending
          ? OnlinePaymentMethodsStatus.activationPending
          : OnlinePaymentMethodsStatus.actionRequired;
    }
    if (activeMethodCount >= totalMethodCount) {
      return OnlinePaymentMethodsStatus.active;
    }
    return OnlinePaymentMethodsStatus.partiallyActive;
  }

  if (o == 'completed' || o == 'complete' || o == 'active' || o == 'live') {
    return OnlinePaymentMethodsStatus.active;
  }
  // Merchant still owes Mollie data — Action required, not Activation pending.
  if (needsData) return OnlinePaymentMethodsStatus.actionRequired;
  // Connected but onboarding not finished / unknown -> activation pending.
  return OnlinePaymentMethodsStatus.activationPending;
}

/// Resolves the in-person/terminal status EXCLUSIVELY from the terminal
/// snapshot. It never looks at online-method activation.
///
/// [snapshotStatus] is the snapshot `status` (`synced`/`not_synced`/
/// `fetch_failed`/`terminals_scope_missing`). [terminalCount] /
/// [activeTerminalCount] come from the snapshot's terminals list. A snapshot
/// older than [staleAfter] surfaces as [InPersonTerminalStatus.snapshotStale].
InPersonTerminalStatus resolveInPersonTerminalStatus({
  required String snapshotStatus,
  required int terminalCount,
  required int activeTerminalCount,
  bool hasDefault = false,
  DateTime? syncedAt,
  DateTime? now,
  Duration staleAfter = const Duration(hours: 24),
  bool errorFlag = false,
}) {
  final s = _norm(snapshotStatus);
  if (errorFlag || s == 'fetch_failed' || s == 'terminals_scope_missing') {
    return InPersonTerminalStatus.error;
  }
  if (s != 'synced') return InPersonTerminalStatus.noTerminal;
  if (syncedAt != null) {
    final ref = now ?? DateTime.now();
    if (ref.difference(syncedAt) > staleAfter) {
      return InPersonTerminalStatus.snapshotStale;
    }
  }
  if (terminalCount <= 0) return InPersonTerminalStatus.noTerminal;
  if (activeTerminalCount <= 0) {
    return InPersonTerminalStatus.connectedNoActiveTerminal;
  }
  if (activeTerminalCount == 1) return InPersonTerminalStatus.activeTerminal;
  return hasDefault
      ? InPersonTerminalStatus.activeTerminal
      : InPersonTerminalStatus.multipleTerminalsNeedDefault;
}

/// Whether terminal (in-person) card payments can be offered. Point of Sale
/// with an active terminal must NOT be blocked by online-method status.
bool inPersonTerminalPaymentAvailable(InPersonTerminalStatus s) =>
    s == InPersonTerminalStatus.activeTerminal;
