// BUSINESS-DASHBOARD-KPI-LOADING-UX-1
//
// Pure presentation/cache ownership for Business dashboard KPI cards.
// Does not change server KPI definitions or fare/street-ride lifecycle.

/// One successful, complete KPI response for a single tenant/company scope.
class BusinessDashboardKpiSnapshot {
  const BusinessDashboardKpiSnapshot({
    required this.tenantId,
    required this.companyId,
    required this.openBookingsCount,
    required this.completedRidesCount,
    required this.unpaidCompletedRidesCount,
    required this.monthlyIncomeCents,
    required this.currency,
    required this.responseGeneration,
  });

  final String tenantId;
  final String companyId;
  final int openBookingsCount;
  final int completedRidesCount;
  final int unpaidCompletedRidesCount;
  final int monthlyIncomeCents;
  final String currency;

  /// Monotonic generation stamped when the response was accepted. All four
  /// card values always belong to the same generation.
  final int responseGeneration;

  bool matchesScope({
    required String tenantId,
    required String companyId,
  }) {
    return this.tenantId == tenantId && this.companyId == companyId;
  }
}

/// UI phase for the four KPI cards.
enum BusinessDashboardKpiPhase {
  /// No successful snapshot yet; request in flight or about to start.
  initialLoading,

  /// Authoritative snapshot is on screen; no request in flight.
  ready,

  /// Authoritative snapshot stays on screen while a refresh runs.
  refreshing,

  /// No snapshot and the latest request failed (or scope has no data yet).
  unavailable,
}

/// Resolved view for the KPI strip.
class BusinessDashboardKpiView {
  const BusinessDashboardKpiView({
    required this.phase,
    required this.snapshot,
    required this.showRefreshIndicator,
    required this.showRetry,
  });

  final BusinessDashboardKpiPhase phase;

  /// Authoritative values to render. Null ⇒ unavailable/loading (never show
  /// numeric zero as authoritative).
  final BusinessDashboardKpiSnapshot? snapshot;

  final bool showRefreshIndicator;
  final bool showRetry;

  bool get hasAuthoritativeValues => snapshot != null;
}

/// Scoped in-memory cache of last successful KPI snapshots.
///
/// Keyed by `tenantId|companyId`. Never returns a snapshot for another scope.
class BusinessDashboardKpiCache {
  final Map<String, BusinessDashboardKpiSnapshot> _byScope =
      <String, BusinessDashboardKpiSnapshot>{};

  static String scopeKey(String tenantId, String companyId) =>
      '${tenantId.trim()}|${companyId.trim()}';

  BusinessDashboardKpiSnapshot? get({
    required String tenantId,
    required String companyId,
  }) {
    final t = tenantId.trim();
    final c = companyId.trim();
    if (t.isEmpty || c.isEmpty) return null;
    final snap = _byScope[scopeKey(t, c)];
    if (snap == null) return null;
    if (!snap.matchesScope(tenantId: t, companyId: c)) return null;
    return snap;
  }

  void put(BusinessDashboardKpiSnapshot snapshot) {
    final t = snapshot.tenantId.trim();
    final c = snapshot.companyId.trim();
    if (t.isEmpty || c.isEmpty) return;
    _byScope[scopeKey(t, c)] = snapshot;
  }

  void clearScope({
    required String tenantId,
    required String companyId,
  }) {
    _byScope.remove(scopeKey(tenantId.trim(), companyId.trim()));
  }

  void clearAll() => _byScope.clear();

  int get length => _byScope.length;
}

/// Process-wide cache so re-entering the dashboard can show the last scoped
/// snapshot immediately while a background refresh runs.
final BusinessDashboardKpiCache businessDashboardKpiCache =
    BusinessDashboardKpiCache();

/// Resolves what the four cards should show.
BusinessDashboardKpiView resolveBusinessDashboardKpiView({
  required BusinessDashboardKpiSnapshot? lastSuccessfulForActiveScope,
  required bool requestInFlight,
  required bool lastRequestFailed,
}) {
  final snap = lastSuccessfulForActiveScope;
  if (snap != null) {
    if (requestInFlight) {
      return BusinessDashboardKpiView(
        phase: BusinessDashboardKpiPhase.refreshing,
        snapshot: snap,
        showRefreshIndicator: true,
        showRetry: false,
      );
    }
    return BusinessDashboardKpiView(
      phase: BusinessDashboardKpiPhase.ready,
      snapshot: snap,
      showRefreshIndicator: false,
      showRetry: lastRequestFailed,
    );
  }
  if (requestInFlight) {
    return const BusinessDashboardKpiView(
      phase: BusinessDashboardKpiPhase.initialLoading,
      snapshot: null,
      showRefreshIndicator: true,
      showRetry: false,
    );
  }
  return BusinessDashboardKpiView(
    phase: BusinessDashboardKpiPhase.unavailable,
    snapshot: null,
    showRefreshIndicator: false,
    showRetry: lastRequestFailed,
  );
}

/// Count display: never render a bare `0` as authoritative before a snapshot.
String businessDashboardKpiCountText({
  required BusinessDashboardKpiSnapshot? snapshot,
  required int Function(BusinessDashboardKpiSnapshot snap) select,
}) {
  if (snapshot == null) return '—';
  return select(snapshot).toString();
}

/// Income display helper (currency formatting stays at the call site).
int? businessDashboardKpiIncomeCents(
  BusinessDashboardKpiSnapshot? snapshot,
) {
  return snapshot?.monthlyIncomeCents;
}

/// Whether a fetch result may replace the displayed snapshot.
///
/// Both bookings and trip KPI legs must succeed so all four cards update from
/// one complete response generation. Partial/failed results never invent zeros.
bool businessDashboardKpiResponseIsComplete({
  required bool bookingsOk,
  required bool tripKpisOk,
}) {
  return bookingsOk && tripKpisOk;
}

/// Whether a completed response may be applied to the active scope.
bool businessDashboardKpiMayApplyResponse({
  required int requestGeneration,
  required int currentGeneration,
  required String requestTenantId,
  required String requestCompanyId,
  required String? activeTenantId,
  required String? activeCompanyId,
}) {
  if (requestGeneration != currentGeneration) return false;
  final t = (activeTenantId ?? '').trim();
  final c = (activeCompanyId ?? '').trim();
  if (t.isEmpty || c.isEmpty) return false;
  return requestTenantId.trim() == t && requestCompanyId.trim() == c;
}

/// Coarse PII-free duration bucket for `[BUSINESS_KPI_LOAD]` diagnostics.
String businessKpiDurationBucket(int durationMs) {
  final ms = durationMs < 0 ? 0 : durationMs;
  if (ms < 250) return 'lt_250';
  if (ms < 500) return '250_499';
  if (ms < 1000) return '500_999';
  if (ms < 2000) return '1000_1999';
  if (ms < 5000) return '2000_4999';
  return 'gte_5000';
}

/// Bounded diagnostic event names (values are never PII).
abstract final class BusinessKpiLoadEvent {
  static const cacheHit = 'cache_hit';
  static const requestStarted = 'request_started';
  static const requestCompleted = 'request_completed';
  static const requestFailed = 'request_failed';
  static const snapshotApplied = 'snapshot_applied';
}

// BUSINESS-KPI-FIRST-LOAD-P0-REPAIR-1
//
// Pure coordinator helpers for the Business dashboard KPI single-flight
// loader. These helpers are Flutter-free and testable in isolation. The
// state code in `_BusinessHomePageState` composes them; presentation rules
// (atomic snapshot, never invent zeros, last-successful cache) are
// unchanged.

/// Bounded outcome for a single KPI leg attempt.
///
/// Used by the coordinator to decide whether to schedule exactly one bounded
/// automatic retry, and to emit a bounded PII-free diagnostic line.
enum BusinessKpiLegOutcome {
  success,
  http400,
  http401,
  http403,
  http429,
  http5xx,
  httpOther,
  timeout,
  network,
  invalidPayload,
}

/// Classifies an HTTP response outcome for a single KPI leg.
///
/// * `statusCode == 200` with `decodedOk == true` → [BusinessKpiLegOutcome.success].
/// * `statusCode == 200` with `decodedOk == false` → [BusinessKpiLegOutcome.invalidPayload].
/// * `statusCode == 400` → [BusinessKpiLegOutcome.http400].
/// * `statusCode == 401` → [BusinessKpiLegOutcome.http401].
/// * `statusCode == 403` → [BusinessKpiLegOutcome.http403].
/// * `statusCode == 429` → [BusinessKpiLegOutcome.http429].
/// * `500 <= statusCode <= 599` → [BusinessKpiLegOutcome.http5xx].
/// * Any other status → [BusinessKpiLegOutcome.httpOther].
BusinessKpiLegOutcome classifyBusinessKpiLegHttpOutcome({
  required int statusCode,
  required bool decodedOk,
}) {
  if (statusCode == 200) {
    return decodedOk
        ? BusinessKpiLegOutcome.success
        : BusinessKpiLegOutcome.invalidPayload;
  }
  if (statusCode == 400) return BusinessKpiLegOutcome.http400;
  if (statusCode == 401) return BusinessKpiLegOutcome.http401;
  if (statusCode == 403) return BusinessKpiLegOutcome.http403;
  if (statusCode == 429) return BusinessKpiLegOutcome.http429;
  if (statusCode >= 500 && statusCode <= 599) {
    return BusinessKpiLegOutcome.http5xx;
  }
  return BusinessKpiLegOutcome.httpOther;
}

/// Classifies a thrown error into a bounded leg outcome.
///
/// The coordinator passes the runtime type name (e.g. `"TimeoutException"`)
/// so the classifier remains pure and dependency-free.
BusinessKpiLegOutcome classifyBusinessKpiLegExceptionOutcome({
  required String errorRuntimeType,
}) {
  final t = errorRuntimeType.trim().toLowerCase();
  if (t.contains('timeout')) return BusinessKpiLegOutcome.timeout;
  return BusinessKpiLegOutcome.network;
}

/// True if a leg outcome is transient and warrants exactly one bounded
/// automatic retry.
bool businessKpiLegOutcomeIsTransient(BusinessKpiLegOutcome o) {
  switch (o) {
    case BusinessKpiLegOutcome.timeout:
    case BusinessKpiLegOutcome.network:
    case BusinessKpiLegOutcome.http429:
    case BusinessKpiLegOutcome.http5xx:
      return true;
    case BusinessKpiLegOutcome.success:
    case BusinessKpiLegOutcome.http400:
    case BusinessKpiLegOutcome.http401:
    case BusinessKpiLegOutcome.http403:
    case BusinessKpiLegOutcome.httpOther:
    case BusinessKpiLegOutcome.invalidPayload:
      return false;
  }
}

/// True if a leg outcome is a permanent user-facing failure that must NOT
/// be automatically retried (auth, scope, or malformed payload).
bool businessKpiLegOutcomeIsPermanentFailure(BusinessKpiLegOutcome o) {
  switch (o) {
    case BusinessKpiLegOutcome.http400:
    case BusinessKpiLegOutcome.http401:
    case BusinessKpiLegOutcome.http403:
    case BusinessKpiLegOutcome.httpOther:
    case BusinessKpiLegOutcome.invalidPayload:
      return true;
    case BusinessKpiLegOutcome.success:
    case BusinessKpiLegOutcome.timeout:
    case BusinessKpiLegOutcome.network:
    case BusinessKpiLegOutcome.http429:
    case BusinessKpiLegOutcome.http5xx:
      return false;
  }
}

/// Bounded PII-free label for [BusinessKpiLegOutcome] used in
/// `[BUSINESS_KPI_LOAD]` diagnostics.
String businessKpiLegOutcomeStatusLabel(BusinessKpiLegOutcome o) {
  switch (o) {
    case BusinessKpiLegOutcome.success:
      return 'success';
    case BusinessKpiLegOutcome.http400:
      return '400';
    case BusinessKpiLegOutcome.http401:
      return '401';
    case BusinessKpiLegOutcome.http403:
      return '403';
    case BusinessKpiLegOutcome.http429:
      return '429';
    case BusinessKpiLegOutcome.http5xx:
      return '5xx';
    case BusinessKpiLegOutcome.httpOther:
      return 'http_other';
    case BusinessKpiLegOutcome.timeout:
      return 'timeout';
    case BusinessKpiLegOutcome.network:
      return 'network';
    case BusinessKpiLegOutcome.invalidPayload:
      return 'invalid_payload';
  }
}

/// Bounded retry decision for one KPI cycle.
enum BusinessKpiRetryDecision {
  /// All required legs succeeded — no retry.
  noRetryAllOk,

  /// At least one leg outcome is a permanent user-facing failure (auth,
  /// scope, malformed payload). Show the manual Retry control instead.
  noRetryTerminalFailure,

  /// Cycle failed only due to transient outcomes and the coordinator may
  /// schedule exactly one bounded automatic retry.
  autoRetryTransient,

  /// Cycle failed with transient outcomes but the automatic attempt was
  /// already used. Show the manual Retry control.
  noRetryAttemptsExhausted,
}

/// The single bounded automatic retry uses a short delay of ~500 ms.
/// This range (400–800 ms) is chosen so a transient worker/KV warm-up
/// completes without producing a visible failure state.
const int kBusinessKpiAutoRetryDelayMs = 500;

/// The initial attempt plus at most one automatic retry.
const int kBusinessKpiMaxAutomaticAttempts = 2;

/// Decides whether the coordinator may schedule exactly one bounded
/// automatic retry after the current cycle finished. Pure.
///
/// Rules:
/// * If any required leg is a permanent failure ([businessKpiLegOutcomeIsPermanentFailure])
///   → [BusinessKpiRetryDecision.noRetryTerminalFailure]. Manual Retry is the
///   only recovery.
/// * Otherwise, if all required legs succeeded → [BusinessKpiRetryDecision.noRetryAllOk].
/// * Otherwise, at least one leg is transient. If `attempt` is still below
///   [kBusinessKpiMaxAutomaticAttempts] → [BusinessKpiRetryDecision.autoRetryTransient].
///   Otherwise → [BusinessKpiRetryDecision.noRetryAttemptsExhausted].
///
/// [bookingsOutcome] and [tripOutcome] are the two required legs; the
/// bookings fallback outcome is folded into [bookingsOutcome] by the caller
/// before invoking this helper.
BusinessKpiRetryDecision resolveBusinessKpiRetryDecision({
  required BusinessKpiLegOutcome bookingsOutcome,
  required BusinessKpiLegOutcome tripOutcome,
  required int attempt,
  int maxAutomaticAttempts = kBusinessKpiMaxAutomaticAttempts,
}) {
  final bookingsPermanent = businessKpiLegOutcomeIsPermanentFailure(
    bookingsOutcome,
  );
  final tripPermanent = businessKpiLegOutcomeIsPermanentFailure(tripOutcome);
  if (bookingsPermanent || tripPermanent) {
    return BusinessKpiRetryDecision.noRetryTerminalFailure;
  }
  final bookingsOk = bookingsOutcome == BusinessKpiLegOutcome.success;
  final tripOk = tripOutcome == BusinessKpiLegOutcome.success;
  if (bookingsOk && tripOk) {
    return BusinessKpiRetryDecision.noRetryAllOk;
  }
  if (attempt < maxAutomaticAttempts) {
    return BusinessKpiRetryDecision.autoRetryTransient;
  }
  return BusinessKpiRetryDecision.noRetryAttemptsExhausted;
}

/// Bounded canonical reason token for a KPI cycle. Never contains PII.
///
/// The coordinator maps its internal reason strings onto this bounded set
/// before emitting diagnostics.
abstract final class BusinessKpiCycleReason {
  /// Initial load triggered by BusinessHomePage `initState`.
  static const init = 'init';

  /// Scope became ready after `initState` (session/profile hydrated) so the
  /// coordinator triggered the first load.
  static const scopeReady = 'scope_ready';

  /// Coordinator scheduled the single bounded automatic retry.
  static const autoRetry = 'auto_retry';

  /// User pressed the Retry button.
  static const manualRetry = 'manual_retry';

  /// App resumed from background.
  static const resume = 'resume';

  /// User returned to BusinessHomePage from another route.
  static const routeReturn = 'route_return';

  /// Coordinator rescheduled a fresh cycle after a stale/scope-changed
  /// response was rejected.
  static const scopeChangedRerun = 'scope_changed_rerun';
}

/// Bounded canonical leg label used in `[BUSINESS_KPI_LOAD]` diagnostics.
abstract final class BusinessKpiLegLabel {
  static const bookings = 'bookings';
  static const bookingsFallback = 'bookings_fallback';
  static const trip = 'trip';
  static const combined = 'combined';
}

/// Bounded canonical status token for combined-cycle log lines.
abstract final class BusinessKpiCombinedStatus {
  static const success = 'success';
  static const transientWillRetry = 'transient_will_retry';
  static const terminal = 'terminal';
  static const stale = 'stale';
  static const skippedScopeNotReady = 'skipped_scope_not_ready';
  static const coalesced = 'coalesced';
}

/// Bounded PII-free auth-mode label. Mirrors `CompanyOwnerAuthMode` values
/// but is safe to use in the pure module (which cannot import Flutter).
String businessKpiAuthModeLabel({
  required bool hasAdminToken,
  required bool hasCompanySession,
}) {
  if (hasAdminToken) return 'admin';
  if (hasCompanySession) return 'company_session';
  return 'none';
}

/// Renders one bounded `[BUSINESS_KPI_LOAD]` diagnostic line.
///
/// Never contains company IDs, tenant IDs, tokens, URLs with query
/// parameters, booking IDs or customer data. Callers are responsible for
/// clamping raw runtime values (elapsed ms, HTTP status) before passing
/// them in.
String formatBusinessKpiLoadDiagnostic({
  required int cycleGeneration,
  required String reason,
  required String leg,
  required int attempt,
  required String status,
  required int elapsedMs,
  required bool scopeReady,
  required String authMode,
}) {
  final safeCycle = cycleGeneration < 0 ? 0 : cycleGeneration;
  final safeAttempt = attempt < 1 ? 1 : attempt;
  final safeElapsed = elapsedMs < 0 ? 0 : elapsedMs;
  return '[BUSINESS_KPI_LOAD] '
      'cycle=$safeCycle '
      'reason=$reason '
      'leg=$leg '
      'attempt=$safeAttempt '
      'status=$status '
      'elapsed_ms=$safeElapsed '
      'scope_ready=$scopeReady '
      'auth_mode=$authMode';
}

/// Pure scope-ready gate.
///
/// Returns true only when every required current context is available and
/// mutually consistent:
///
/// * a company profile is present with a non-empty `companyId`;
/// * an active company session is present with a non-empty `companyId`;
/// * the session's `companyId` matches the profile's `companyId`;
/// * the resolved scope's `tenantId` and `companyId` match the authoritative
///   company id (i.e. no silent fallback to `fluxidi` while an authenticated
///   session belongs to another company).
///
/// The `hasAdminAuthShortcut` parameter allows dev/ops builds with a
/// compile-time admin token to bypass session/profile requirements while
/// still requiring a non-empty scope.
bool businessDashboardKpiScopeIsReady({
  required String? profileCompanyId,
  required String? sessionCompanyId,
  required String? scopeTenantId,
  required String? scopeCompanyId,
  required bool hasAdminAuthShortcut,
}) {
  final scopeTenant = (scopeTenantId ?? '').trim();
  final scopeCompany = (scopeCompanyId ?? '').trim();
  if (scopeTenant.isEmpty || scopeCompany.isEmpty) return false;
  if (hasAdminAuthShortcut) return true;
  final profile = (profileCompanyId ?? '').trim();
  final session = (sessionCompanyId ?? '').trim();
  if (profile.isEmpty || session.isEmpty) return false;
  if (profile != session) return false;
  // Fail-closed against a silent tenant/company `fluxidi` fallback while a
  // company-session bearer belongs to another company.
  if (scopeTenant != profile) return false;
  if (scopeCompany != profile) return false;
  return true;
}
