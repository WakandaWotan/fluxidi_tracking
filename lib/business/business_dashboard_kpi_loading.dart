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
