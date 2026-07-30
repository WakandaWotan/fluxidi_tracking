part of '../main.dart';

class _BusinessHomePageState extends State<BusinessHomePage>
    with WidgetsBindingObserver, RouteAware {
  String _t({
    required String nl,
    required String en,
    required String fr,
    required String es,
  }) => _tr(nl: nl, en: en, fr: fr, es: es);

  // Time-aware greeting for the Business Home header. Uses the local
  // device time only; no backend involved. Hour ranges:
  //   05:00–11:59 → morning
  //   12:00–17:59 → afternoon
  //   18:00–04:59 → evening
  // Keeps the existing waving-hand emoji and translation style.
  String _timeAwareGreeting() {
    final hour = DateTime.now().hour;
    if (hour >= 5 && hour < 12) {
      return _t(
        nl: 'Goedemorgen! 👋',
        en: 'Good morning! 👋',
        fr: 'Bonjour ! 👋',
        es: '¡Buenos días! 👋',
      );
    }
    if (hour >= 12 && hour < 18) {
      return _t(
        nl: 'Goedemiddag! 👋',
        en: 'Good afternoon! 👋',
        fr: 'Bon après-midi ! 👋',
        es: '¡Buenas tardes! 👋',
      );
    }
    return _t(
      nl: 'Goedenavond! 👋',
      en: 'Good evening! 👋',
      fr: 'Bonsoir ! 👋',
      es: '¡Buenas noches! 👋',
    );
  }

  // BUSINESS-DASHBOARD-KPI-LOADING-UX-1: display comes from the last successful
  // scoped snapshot only. Null fields mean loading/unavailable — never flash
  // authoritative zeros while a refresh is still in flight.
  int? _openBookingsCount;
  int? _completedRidesCount;
  int? _unpaidCompletedRidesCount;
  int? _monthlyIncomeCents;
  String _kpiCurrency = 'EUR';
  bool _kpiRefreshInFlight = false;
  bool _kpiLastRequestFailed = false;
  String? _dashboardKpiTenantId;
  String? _dashboardKpiCompanyId;
  String? _kpiRequestTenantId;
  String? _kpiRequestCompanyId;
  int _dashboardKpiRefreshGeneration = 0;
  int _kpiSnapshotGeneration = 0;
  // BUSINESS-KPI-FIRST-LOAD-P0-REPAIR-1: single-flight coordinator state.
  //
  // * `_kpiCycleGeneration` is monotonic per cycle for `[BUSINESS_KPI_LOAD]`
  //   diagnostics; it does not gate any control flow. Scope-generation
  //   rejection uses `_dashboardKpiRefreshGeneration` as before.
  // * `_kpiAutoRetryTimer` is the pending 500 ms automatic-retry timer. At
  //   most one automatic retry per failed cycle.
  // * `_kpiPendingRerun*` implements latest-wins coalescing: while a cycle
  //   is in flight, additional triggers set the queued reason instead of
  //   spawning a second concurrent cycle.
  int _kpiCycleGeneration = 0;
  Timer? _kpiAutoRetryTimer;
  bool _kpiPendingRerunQueued = false;
  String? _kpiPendingRerunReason;
  bool _routeObserverSubscribed = false;
  bool _businessAccessGuardTriggered = false;

  BusinessDashboardKpiView get _kpiView {
    final scope = _activeDashboardKpiScope();
    BusinessDashboardKpiSnapshot? scoped;
    if (scope != null &&
        _openBookingsCount != null &&
        _completedRidesCount != null &&
        _unpaidCompletedRidesCount != null &&
        _monthlyIncomeCents != null &&
        _dashboardKpiTenantId == scope.tenantId &&
        _dashboardKpiCompanyId == scope.companyId) {
      scoped = BusinessDashboardKpiSnapshot(
        tenantId: scope.tenantId,
        companyId: scope.companyId,
        openBookingsCount: _openBookingsCount!,
        completedRidesCount: _completedRidesCount!,
        unpaidCompletedRidesCount: _unpaidCompletedRidesCount!,
        monthlyIncomeCents: _monthlyIncomeCents!,
        currency: _kpiCurrency,
        responseGeneration: _kpiSnapshotGeneration,
      );
    }
    return resolveBusinessDashboardKpiView(
      lastSuccessfulForActiveScope: scoped,
      requestInFlight: _kpiRefreshInFlight,
      lastRequestFailed: _kpiLastRequestFailed,
    );
  }

  void _logBusinessKpiLoad({
    required String event,
    required int scopeGeneration,
    int? durationMs,
    String? detail,
  }) {
    final bucket = durationMs == null
        ? null
        : businessKpiDurationBucket(durationMs);
    debugPrint(
      '[BUSINESS_KPI_LOAD] event=$event '
      'scope_generation=$scopeGeneration'
      '${bucket == null ? '' : ' duration_bucket=$bucket'}'
      '${detail == null || detail.isEmpty ? '' : ' $detail'}',
    );
  }

  BusinessThemePalette get _businessThemePalette =>
      paletteForBusinessTheme(businessThemeNotifier.value);

  String _businessImageAsset({
    required String executiveGoldAsset,
    String? corporateBlueAsset,
    String? cleanProfessionalAsset,
    String? emeraldIvoryAsset,
    String? fluxidiNeonRushAsset,
  }) {
    switch (businessThemeNotifier.value) {
      case BusinessThemeVariant.executiveGold:
        return executiveGoldAsset;
      case BusinessThemeVariant.corporateBlue:
        return corporateBlueAsset ?? executiveGoldAsset;
      case BusinessThemeVariant.cleanProfessional:
        return cleanProfessionalAsset ?? executiveGoldAsset;
      case BusinessThemeVariant.emeraldIvory:
        return emeraldIvoryAsset ?? executiveGoldAsset;
      case BusinessThemeVariant.fluxidiNeonRush:
        return fluxidiNeonRushAsset ?? executiveGoldAsset;
    }
  }

  void _guardBusinessAccessOrRedirect({required String reason}) {
    if (_businessAccessGuardTriggered || !mounted) return;
    if (CompanySessionStore.instance.hasValidCompanyContext) return;
    _businessAccessGuardTriggered = true;
    debugPrint('[COMPANY_PAIRING][BUSINESS_GUARD_REDIRECT] reason=$reason');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _t(
            nl: 'Bedrijfstoegang vereist eerst activatie of herstel.',
            en: 'Business access requires activation or recovery first.',
            fr: "L'accès entreprise nécessite d'abord une activation ou récupération.",
            es: 'El acceso de empresa requiere primero activación o recuperación.',
          ),
        ),
      ),
    );
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => const RoleEntryPage()),
      (route) => false,
    );
  }

  /// Frame-safe setter for [businessShellFrameActiveNotifier]. The flag is
  /// read by a [ValueListenableBuilder] higher in the tree, so mutating it
  /// during build (e.g. from [initState]) throws "setState()/markNeedsBuild()
  /// called during build". Deferring to the next frame preserves the original
  /// timing while staying build-safe; the equality guard avoids a redundant
  /// notification.
  void _setBusinessShellFrameActiveAfterFirstFrame(bool value) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (businessShellFrameActiveNotifier.value == value) return;
      businessShellFrameActiveNotifier.value = value;
    });
  }

  /// Dispose-time companion of [_setBusinessShellFrameActiveAfterFirstFrame].
  /// Called from [dispose] to flip the shell flag back to `false` AFTER the
  /// widget-tree-locked teardown frame finishes — assigning synchronously
  /// inside [dispose] notifies the [ValueListenableBuilder] higher in the
  /// tree and throws "setState()/markNeedsBuild() called when widget tree
  /// was locked". Crucially this helper does NOT guard on [mounted]: by the
  /// time the post-frame callback runs the state is already disposed, but
  /// the closure only touches the top-level notifier, never `this`, so the
  /// deferred update is still safe. The equality check avoids a redundant
  /// notification when the flag is already `false`.
  void _setBusinessShellFrameInactiveAfterUnmount() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (businessShellFrameActiveNotifier.value == false) return;
      businessShellFrameActiveNotifier.value = false;
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Opt this shell into the business frame accent. While BusinessHomePage
    // is mounted on the route stack, FluxidiFrame is allowed to consume the
    // active BusinessThemeVariant accent. Cleared on dispose so non-business
    // shells (PIN/unlock, login, customer, standalone driver) keep the brand
    // default accent.
    //
    // Deferred to after the first frame: this notifier is observed by a
    // ValueListenableBuilder higher in the tree (the app-lock gate), so a
    // synchronous mutation here would mark that listener dirty during build
    // and throw "setState() or markNeedsBuild() called during build".
    _setBusinessShellFrameActiveAfterFirstFrame(true);
    // Rebuild when the user toggles between Compact and Visual mobile layout
    // from the theme page. Only affects phone-portrait rendering; tablet and
    // phone-landscape gates remain unchanged.
    businessHomeMobileLayoutNotifier.addListener(
      _onBusinessHomeMobileLayoutChanged,
    );
    activeCompanySessionNotifier.addListener(_onDashboardKpiScopeMaybeChanged);
    companyProfileNotifier.addListener(_onDashboardKpiScopeMaybeChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _guardBusinessAccessOrRedirect(reason: 'business_home_init');
    });
    // BUSINESS-DASHBOARD-KPI-LOADING-UX-1: show scoped cached snapshot
    // immediately (if any), then refresh in the background.
    _hydrateDashboardKpisFromScopedCache(reason: 'init');
    // BUSINESS-KPI-FIRST-LOAD-P0-REPAIR-1: the first cycle only starts once
    // company profile + session are hydrated. If scope is not ready yet the
    // scope listener (`_onDashboardKpiScopeMaybeChanged`) fires the initial
    // load as soon as ready. This prevents pairing a valid company-session
    // bearer with the default `fluxidi` tenant/company fallback.
    unawaited(
      _refreshDashboardKpis(reason: BusinessKpiCycleReason.init),
    );
  }

  void _hydrateDashboardKpisFromScopedCache({required String reason}) {
    final scope = _activeDashboardKpiScope();
    if (scope == null) return;
    final cached = businessDashboardKpiCache.get(
      tenantId: scope.tenantId,
      companyId: scope.companyId,
    );
    if (cached == null) return;
    _dashboardKpiTenantId = scope.tenantId;
    _dashboardKpiCompanyId = scope.companyId;
    _openBookingsCount = cached.openBookingsCount;
    _completedRidesCount = cached.completedRidesCount;
    _unpaidCompletedRidesCount = cached.unpaidCompletedRidesCount;
    _monthlyIncomeCents = cached.monthlyIncomeCents;
    _kpiCurrency = cached.currency;
    _kpiSnapshotGeneration = cached.responseGeneration;
    _kpiLastRequestFailed = false;
    _logBusinessKpiLoad(
      event: BusinessKpiLoadEvent.cacheHit,
      scopeGeneration: _dashboardKpiRefreshGeneration,
      detail: 'trigger=$reason',
    );
  }

  void _clearDisplayedDashboardKpis() {
    _openBookingsCount = null;
    _completedRidesCount = null;
    _unpaidCompletedRidesCount = null;
    _monthlyIncomeCents = null;
    _kpiCurrency = 'EUR';
    _kpiSnapshotGeneration = 0;
  }

  void _applyDashboardKpiSnapshot(BusinessDashboardKpiSnapshot snapshot) {
    _dashboardKpiTenantId = snapshot.tenantId;
    _dashboardKpiCompanyId = snapshot.companyId;
    _openBookingsCount = snapshot.openBookingsCount;
    _completedRidesCount = snapshot.completedRidesCount;
    _unpaidCompletedRidesCount = snapshot.unpaidCompletedRidesCount;
    _monthlyIncomeCents = snapshot.monthlyIncomeCents;
    _kpiCurrency = snapshot.currency;
    _kpiSnapshotGeneration = snapshot.responseGeneration;
    _kpiLastRequestFailed = false;
    businessDashboardKpiCache.put(snapshot);
  }

  void _onBusinessHomeMobileLayoutChanged() {
    if (!mounted) return;
    setState(() {});
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_routeObserverSubscribed) return;
    final route = ModalRoute.of(context);
    if (route is PageRoute<dynamic>) {
      kAppRouteObserver.subscribe(this, route);
      _routeObserverSubscribed = true;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (_routeObserverSubscribed) {
      kAppRouteObserver.unsubscribe(this);
      _routeObserverSubscribed = false;
    }
    // BUSINESS-KPI-FIRST-LOAD-P0-REPAIR-1: cancel any pending automatic
    // retry timer so it can never fire on an unmounted state.
    _kpiAutoRetryTimer?.cancel();
    _kpiAutoRetryTimer = null;
    _kpiPendingRerunQueued = false;
    _kpiPendingRerunReason = null;
    businessHomeMobileLayoutNotifier.removeListener(
      _onBusinessHomeMobileLayoutChanged,
    );
    activeCompanySessionNotifier.removeListener(
      _onDashboardKpiScopeMaybeChanged,
    );
    companyProfileNotifier.removeListener(_onDashboardKpiScopeMaybeChanged);
    // Releasing the business shell flag here means the next non-business
    // screen (role entry, login, customer, driver standalone) renders with
    // the brand default frame accent instead of inheriting Neon Rush /
    // Emerald Ivory / Corporate Blue / Clean Professional.
    //
    // Deferred past the current teardown frame: assigning synchronously
    // here would notify the ValueListenableBuilder higher in the tree while
    // the framework is unmounting and throws "setState()/markNeedsBuild()
    // called when widget tree was locked".
    _setBusinessShellFrameInactiveAfterUnmount();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _guardBusinessAccessOrRedirect(reason: 'business_home_resume');
      unawaited(
        _refreshDashboardKpis(reason: BusinessKpiCycleReason.resume),
      );
    }
  }

  @override
  void didPopNext() {
    _guardBusinessAccessOrRedirect(reason: 'business_home_route_return');
    unawaited(
      _refreshDashboardKpis(reason: BusinessKpiCycleReason.routeReturn),
    );
  }

  int? _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.round();
    final text = value?.toString().trim() ?? '';
    if (text.isEmpty) return null;
    return int.tryParse(text);
  }

  double? _asDouble(dynamic value) {
    if (value is double) return value;
    if (value is num) return value.toDouble();
    final text = value?.toString().trim() ?? '';
    if (text.isEmpty) return null;
    return double.tryParse(text.replaceAll(',', '.'));
  }

  Future<Map<String, String>> _companyOwnerHeaders() async {
    final auth = await resolveCompanyOwnerAuthHeaders();
    return auth.headers;
  }

  String _activeMonthToken() {
    final now = DateTime.now();
    final mm = now.month.toString().padLeft(2, '0');
    return '${now.year}-$mm';
  }

  String _metricCountText(int? value) {
    return value == null ? '—' : value.toString();
  }

  String _metricIncomeText() {
    if (_monthlyIncomeCents == null) return '—';
    final amount = _monthlyIncomeCents! / 100.0;
    final useComma = appConfig.currentLanguage != AppLanguage.en;
    final text = amount.toStringAsFixed(2);
    final normalized = useComma ? text.replaceAll('.', ',') : text;
    if (_kpiCurrency.trim().toUpperCase() == 'EUR') {
      return '€$normalized';
    }
    return '${_kpiCurrency.toUpperCase()} $normalized';
  }

  ({String tenantId, String companyId})? _activeDashboardKpiScope() {
    final query = _activeBookingScopeQuery();
    final tenantId = (query['tenant_id'] ?? query['tenantId'] ?? '')
        .toString()
        .trim();
    final companyId = (query['company_id'] ?? query['companyId'] ?? '')
        .toString()
        .trim();
    if (tenantId.isEmpty || companyId.isEmpty) return null;
    return (tenantId: tenantId, companyId: companyId);
  }

  bool _dashboardKpiScopeMatches({
    required String tenantId,
    required String companyId,
  }) {
    final active = _activeDashboardKpiScope();
    if (active == null) return false;
    return active.tenantId == tenantId && active.companyId == companyId;
  }

  void _onDashboardKpiScopeMaybeChanged() {
    if (!mounted) return;
    final scope = _activeDashboardKpiScope();
    final nextTenant = scope?.tenantId;
    final nextCompany = scope?.companyId;
    final scopeChanged =
        nextTenant != _dashboardKpiTenantId ||
        nextCompany != _dashboardKpiCompanyId;
    if (scopeChanged) {
      _clearDashboardKpisForScopeChange(reason: 'session_or_profile');
      return;
    }
    // BUSINESS-KPI-FIRST-LOAD-P0-REPAIR-1: even when the resolved scope
    // tokens are unchanged (i.e. still equal to the pre-hydration fallback
    // or to the last-seen value), the underlying company profile/session
    // notifiers may have transitioned from "not ready" to "ready". In that
    // case the initial cycle from `initState` was skipped and we must now
    // start the first real cycle automatically. If a snapshot is already
    // on screen, `_refreshDashboardKpis` becomes an ordinary refresh and
    // preserves the visible values.
    if (_openBookingsCount == null &&
        _completedRidesCount == null &&
        _unpaidCompletedRidesCount == null &&
        _monthlyIncomeCents == null &&
        !_kpiRefreshInFlight &&
        _kpiScopeIsReadyForRequest()) {
      unawaited(
        _refreshDashboardKpis(reason: BusinessKpiCycleReason.scopeReady),
      );
    }
  }

  void _clearDashboardKpisForScopeChange({required String reason}) {
    final scope = _activeDashboardKpiScope();
    _dashboardKpiRefreshGeneration += 1;
    debugPrint(
      '[BUSINESS_DASHBOARD][KPI][SCOPE_CHANGE_CLEAR] reason=$reason '
      'tenant=${_maskLocalScopeId(scope?.tenantId ?? '')} '
      'company=${_maskLocalScopeId(scope?.companyId ?? '')} '
      'generation=$_dashboardKpiRefreshGeneration',
    );
    if (!mounted) return;
    setState(() {
      // Never keep another company's numbers on screen. Prefer the new scope's
      // cached snapshot; otherwise show unavailable/loading (not zeros).
      _clearDisplayedDashboardKpis();
      _kpiLastRequestFailed = false;
      _dashboardKpiTenantId = scope?.tenantId;
      _dashboardKpiCompanyId = scope?.companyId;
      if (scope != null) {
        final cached = businessDashboardKpiCache.get(
          tenantId: scope.tenantId,
          companyId: scope.companyId,
        );
        if (cached != null) {
          _applyDashboardKpiSnapshot(cached);
          _logBusinessKpiLoad(
            event: BusinessKpiLoadEvent.cacheHit,
            scopeGeneration: _dashboardKpiRefreshGeneration,
            detail: 'trigger=scope_change:$reason',
          );
        }
      }
    });
    if (scope != null) {
      unawaited(
        _refreshDashboardKpis(
          reason: BusinessKpiCycleReason.scopeChangedRerun,
        ),
      );
    }
  }

  Future<int?> _loadOpenBookingsFallbackCount({
    required Map<String, String> headers,
    required String reason,
  }) async {
    // Keep fallback lightweight: company list index-backed endpoint only.
    final listUri = _withActiveBookingScope(
      kBookingBaseUrl,
      kListBookingsPath,
      extraQuery: <String, String>{
        'limit': '200',
        'include_history': '1',
        't': '${DateTime.now().millisecondsSinceEpoch}',
      },
    );
    try {
      final res = await http
          .get(listUri, headers: headers)
          .timeout(const Duration(seconds: 12));
      if (res.statusCode != 200) {
        debugPrint(
          '[BUSINESS_DASHBOARD][KPI][FALLBACK][WARN] source=company_list status=${res.statusCode} trigger=$reason',
        );
        return null;
      }
      final decoded = jsonDecode(utf8.decode(res.bodyBytes));
      if (decoded is! Map<String, dynamic>) {
        debugPrint(
          '[BUSINESS_DASHBOARD][KPI][FALLBACK][WARN] source=company_list reason=invalid_payload trigger=$reason',
        );
        return null;
      }
      final rawItems = (decoded['items'] is List)
          ? (decoded['items'] as List)
          : ((decoded['bookings'] is List)
                ? (decoded['bookings'] as List)
                : null);
      if (rawItems == null) {
        debugPrint(
          '[BUSINESS_DASHBOARD][KPI][FALLBACK][WARN] source=company_list reason=missing_items trigger=$reason',
        );
        return null;
      }
      var openCount = 0;
      for (final raw in rawItems) {
        if (raw is! Map) continue;
        final item = _CompanyBookingOverviewItem.fromMap(
          raw.map((k, v) => MapEntry(k.toString(), v)),
        );
        if (item.bucket == _CompanyBookingsFilter.open) {
          openCount += 1;
        }
      }
      return openCount;
    } catch (e) {
      debugPrint(
        '[BUSINESS_DASHBOARD][KPI][FALLBACK][WARN] source=company_list reason=fetch_failed trigger=$reason error=$e',
      );
      return null;
    }
  }

  // BUSINESS-KPI-FIRST-LOAD-P0-REPAIR-1: scope-ready gate. The initial
  // request never fires while the resolved scope is null OR while a valid
  // company-session bearer would be paired with the `fluxidi` fallback
  // tenant/company (see `businessDashboardKpiScopeIsReady`).
  bool _kpiScopeIsReadyForRequest() {
    final scope = _activeDashboardKpiScope();
    return businessDashboardKpiScopeIsReady(
      profileCompanyId: companyProfileNotifier.value?.companyId,
      sessionCompanyId: activeCompanySessionNotifier.value?.companyId,
      scopeTenantId: scope?.tenantId,
      scopeCompanyId: scope?.companyId,
      hasAdminAuthShortcut: false,
    );
  }

  String _kpiAuthModeLabel(CompanyOwnerAuthHeaders headers) {
    return businessKpiAuthModeLabel(
      hasAdminToken: headers.mode == CompanyOwnerAuthMode.admin,
      hasCompanySession:
          headers.mode == CompanyOwnerAuthMode.companySession,
    );
  }

  // BUSINESS-KPI-FIRST-LOAD-P0-REPAIR-1: single-flight KPI load coordinator.
  //
  // Behaviour contract:
  //   * At most one cycle is in flight at any time. Concurrent triggers
  //     coalesce into one latest-wins queued rerun instead of spawning a
  //     second parallel cycle.
  //   * The initial request never fires while scope is not ready
  //     (`_kpiScopeIsReadyForRequest`). The scope listener re-invokes this
  //     helper as soon as profile/session hydrate.
  //   * On combined-cycle failure the coordinator classifies each leg's
  //     outcome and schedules exactly one bounded automatic retry (500 ms)
  //     when the failures are transient (timeout/network/429/5xx). Auth /
  //     scope / malformed-payload failures never auto-retry.
  //   * Stale-response rejections do not flip the failure flag; they
  //     schedule a fresh cycle for the current scope so the dashboard
  //     never gets stuck in unavailable+no-retry.
  //   * Presentation rules from `BUSINESS-DASHBOARD-KPI-LOADING-UX-1` are
  //     preserved: last-successful snapshot stays visible during refresh,
  //     no invented zeros, atomic apply, scope-safe cache.
  Future<void> _refreshDashboardKpis({
    required String reason,
    int attempt = 1,
  }) async {
    // Non-manual triggers must wait for ready scope. Manual retry likewise:
    // the button is only visible after a completed cycle, so scope is
    // already known ready at that point; asserting it here keeps the
    // guarantee that we never send a request with the `fluxidi` fallback
    // paired with a foreign company-session bearer.
    if (!_kpiScopeIsReadyForRequest()) {
      debugPrint(
        formatBusinessKpiLoadDiagnostic(
          cycleGeneration: _kpiCycleGeneration,
          reason: reason,
          leg: BusinessKpiLegLabel.combined,
          attempt: attempt,
          status: BusinessKpiCombinedStatus.skippedScopeNotReady,
          elapsedMs: 0,
          scopeReady: false,
          authMode: 'none',
        ),
      );
      return;
    }

    final requestScope = _activeDashboardKpiScope();
    if (requestScope == null) {
      // Defensive: scope-ready implies non-null scope, but keep the
      // legacy log for other unexpected paths.
      debugPrint(
        '[BUSINESS_DASHBOARD][KPI][WARN] reason=missing_scope trigger=$reason',
      );
      return;
    }
    final requestGeneration = _dashboardKpiRefreshGeneration;
    final capturedTenantId = requestScope.tenantId;
    final capturedCompanyId = requestScope.companyId;

    // Latest-wins single-flight coalescing. If a cycle is already active
    // (any scope), queue exactly one rerun with the incoming reason so the
    // coordinator picks it up in `finally`. Auto-retry cycles ignore this
    // path — they are scheduled internally and always run to completion.
    if (_kpiRefreshInFlight && reason != BusinessKpiCycleReason.autoRetry) {
      _kpiPendingRerunQueued = true;
      _kpiPendingRerunReason = reason;
      debugPrint(
        formatBusinessKpiLoadDiagnostic(
          cycleGeneration: _kpiCycleGeneration,
          reason: reason,
          leg: BusinessKpiLegLabel.combined,
          attempt: attempt,
          status: BusinessKpiCombinedStatus.coalesced,
          elapsedMs: 0,
          scopeReady: true,
          authMode: 'none',
        ),
      );
      return;
    }

    // Cancel any pending auto-retry so that a fresh manual/scope trigger
    // does not race against a stale scheduled retry.
    _kpiAutoRetryTimer?.cancel();
    _kpiAutoRetryTimer = null;

    _kpiRefreshInFlight = true;
    _kpiRequestTenantId = capturedTenantId;
    _kpiRequestCompanyId = capturedCompanyId;
    if (attempt == 1) {
      _kpiCycleGeneration += 1;
    }
    final cycleGeneration = _kpiCycleGeneration;
    if (mounted) setState(() {});
    final startedAt = DateTime.now();
    _logBusinessKpiLoad(
      event: BusinessKpiLoadEvent.requestStarted,
      scopeGeneration: requestGeneration,
      detail: 'trigger=$reason attempt=$attempt cycle=$cycleGeneration',
    );

    var authModeLabel = 'none';
    var bookingsOutcome = BusinessKpiLegOutcome.network;
    var tripOutcome = BusinessKpiLegOutcome.network;
    var fallbackAttempted = false;
    var fallbackOutcome = BusinessKpiLegOutcome.network;
    try {
      final month = _activeMonthToken();
      final auth = await resolveCompanyOwnerAuthHeaders();
      final headers = auth.headers;
      authModeLabel = _kpiAuthModeLabel(auth);
      if (!businessDashboardKpiMayApplyResponse(
        requestGeneration: requestGeneration,
        currentGeneration: _dashboardKpiRefreshGeneration,
        requestTenantId: capturedTenantId,
        requestCompanyId: capturedCompanyId,
        activeTenantId: _activeDashboardKpiScope()?.tenantId,
        activeCompanyId: _activeDashboardKpiScope()?.companyId,
      )) {
        // Stale-scope rejection is not a user-facing failure. Fresh
        // cycle for the current scope is scheduled below via the queued
        // rerun mechanism so the dashboard cannot get stuck in
        // unavailable+no-retry.
        _kpiPendingRerunQueued = true;
        _kpiPendingRerunReason ??= BusinessKpiCycleReason.scopeChangedRerun;
        final durationMs =
            DateTime.now().difference(startedAt).inMilliseconds;
        debugPrint(
          formatBusinessKpiLoadDiagnostic(
            cycleGeneration: cycleGeneration,
            reason: reason,
            leg: BusinessKpiLegLabel.combined,
            attempt: attempt,
            status: BusinessKpiCombinedStatus.stale,
            elapsedMs: durationMs,
            scopeReady: true,
            authMode: authModeLabel,
          ),
        );
        return;
      }
      final bookingsUri = _withActiveBookingScope(
        kBookingBaseUrl,
        '/admin/dashboard/bookings-kpis',
      );
      final tripKpisUri = _withActiveBookingScope(
        kWorkerBaseUrl,
        '/admin/dashboard/trip-kpis',
        extraQuery: <String, String>{'month': month},
      );

      int? nextOpenBookings;
      int? nextCompletedRides;
      int? nextUnpaidCompleted;
      int? nextMonthlyIncomeCents;
      var nextCurrency = 'EUR';
      var bookingsKpisOk = false;
      var tripKpisOk = false;

      final bookingsStartedAt = DateTime.now();
      try {
        final bookingsRes = await http
            .get(bookingsUri, headers: headers)
            .timeout(const Duration(seconds: 12));
        final bookingsBodyIsOkMap = () {
          if (bookingsRes.statusCode != 200) return false;
          try {
            final decoded = jsonDecode(bookingsRes.body);
            return decoded is Map && decoded['ok'] == true;
          } catch (_) {
            return false;
          }
        }();
        bookingsOutcome = classifyBusinessKpiLegHttpOutcome(
          statusCode: bookingsRes.statusCode,
          decodedOk: bookingsBodyIsOkMap,
        );
        if (bookingsRes.statusCode == 200) {
          final decoded = jsonDecode(bookingsRes.body);
          if (decoded is Map && decoded['ok'] == true) {
            bookingsKpisOk = true;
            nextOpenBookings = _asInt(decoded['open_bookings_count']) ?? 0;
          } else {
            debugPrint(
              '[BUSINESS_DASHBOARD][KPI][WARN] source=bookings reason=invalid_payload trigger=$reason',
            );
          }
        } else {
          debugPrint(
            '[BUSINESS_DASHBOARD][KPI][WARN] source=bookings status=${bookingsRes.statusCode} trigger=$reason',
          );
        }
      } catch (e) {
        bookingsOutcome = classifyBusinessKpiLegExceptionOutcome(
          errorRuntimeType: e.runtimeType.toString(),
        );
        debugPrint(
          '[BUSINESS_DASHBOARD][KPI][WARN] source=bookings reason=fetch_failed trigger=$reason error=$e',
        );
      }
      final bookingsElapsedMs = DateTime.now()
          .difference(bookingsStartedAt)
          .inMilliseconds;
      debugPrint(
        formatBusinessKpiLoadDiagnostic(
          cycleGeneration: cycleGeneration,
          reason: reason,
          leg: BusinessKpiLegLabel.bookings,
          attempt: attempt,
          status: businessKpiLegOutcomeStatusLabel(bookingsOutcome),
          elapsedMs: bookingsElapsedMs,
          scopeReady: true,
          authMode: authModeLabel,
        ),
      );
      if (!bookingsKpisOk) {
        fallbackAttempted = true;
        final fallbackStartedAt = DateTime.now();
        try {
          final fallback = await _loadOpenBookingsFallbackCount(
            headers: headers,
            reason: reason,
          );
          if (fallback != null) {
            bookingsKpisOk = true;
            nextOpenBookings = fallback;
            fallbackOutcome = BusinessKpiLegOutcome.success;
          } else {
            fallbackOutcome = BusinessKpiLegOutcome.invalidPayload;
          }
        } catch (e) {
          fallbackOutcome = classifyBusinessKpiLegExceptionOutcome(
            errorRuntimeType: e.runtimeType.toString(),
          );
        }
        final fallbackElapsedMs = DateTime.now()
            .difference(fallbackStartedAt)
            .inMilliseconds;
        debugPrint(
          formatBusinessKpiLoadDiagnostic(
            cycleGeneration: cycleGeneration,
            reason: reason,
            leg: BusinessKpiLegLabel.bookingsFallback,
            attempt: attempt,
            status: businessKpiLegOutcomeStatusLabel(fallbackOutcome),
            elapsedMs: fallbackElapsedMs,
            scopeReady: true,
            authMode: authModeLabel,
          ),
        );
      }

      final tripStartedAt = DateTime.now();
      try {
        final tripRes = await http
            .get(tripKpisUri, headers: headers)
            .timeout(const Duration(seconds: 12));
        final tripBodyIsOkMap = () {
          if (tripRes.statusCode != 200) return false;
          try {
            final decoded = jsonDecode(tripRes.body);
            return decoded is Map && decoded['ok'] == true;
          } catch (_) {
            return false;
          }
        }();
        tripOutcome = classifyBusinessKpiLegHttpOutcome(
          statusCode: tripRes.statusCode,
          decodedOk: tripBodyIsOkMap,
        );
        if (tripRes.statusCode == 200) {
          final decoded = jsonDecode(tripRes.body);
          if (decoded is Map && decoded['ok'] == true) {
            tripKpisOk = true;
            nextCompletedRides = _asInt(decoded['completed_rides_count']) ?? 0;
            nextUnpaidCompleted =
                _asInt(decoded['unpaid_completed_rides_count']) ?? 0;
            nextCurrency =
                (decoded['currency']?.toString().trim().isNotEmpty ?? false)
                ? decoded['currency'].toString().trim().toUpperCase()
                : 'EUR';
            final netCents = _asInt(decoded['net_monthly_income_cents']);
            final cents = netCents ?? _asInt(decoded['monthly_income_cents']);
            if (cents != null) {
              nextMonthlyIncomeCents = cents;
            } else {
              final netEur = _asDouble(decoded['net_monthly_income_eur']);
              if (netEur != null) {
                nextMonthlyIncomeCents = (netEur * 100).round();
              } else {
                final eur = _asDouble(decoded['monthly_income_eur']);
                nextMonthlyIncomeCents = eur == null ? 0 : (eur * 100).round();
              }
            }
          } else {
            debugPrint(
              '[BUSINESS_DASHBOARD][KPI][WARN] source=trip_kpis reason=invalid_payload trigger=$reason',
            );
          }
        } else {
          debugPrint(
            '[BUSINESS_DASHBOARD][KPI][WARN] source=trip_kpis status=${tripRes.statusCode} trigger=$reason',
          );
        }
      } catch (e) {
        tripOutcome = classifyBusinessKpiLegExceptionOutcome(
          errorRuntimeType: e.runtimeType.toString(),
        );
        debugPrint(
          '[BUSINESS_DASHBOARD][KPI][WARN] source=trip_kpis reason=fetch_failed trigger=$reason error=$e',
        );
      }
      final tripElapsedMs = DateTime.now()
          .difference(tripStartedAt)
          .inMilliseconds;
      debugPrint(
        formatBusinessKpiLoadDiagnostic(
          cycleGeneration: cycleGeneration,
          reason: reason,
          leg: BusinessKpiLegLabel.trip,
          attempt: attempt,
          status: businessKpiLegOutcomeStatusLabel(tripOutcome),
          elapsedMs: tripElapsedMs,
          scopeReady: true,
          authMode: authModeLabel,
        ),
      );

      final durationMs =
          DateTime.now().difference(startedAt).inMilliseconds;
      if (!mounted) return;
      if (!businessDashboardKpiMayApplyResponse(
        requestGeneration: requestGeneration,
        currentGeneration: _dashboardKpiRefreshGeneration,
        requestTenantId: capturedTenantId,
        requestCompanyId: capturedCompanyId,
        activeTenantId: _activeDashboardKpiScope()?.tenantId,
        activeCompanyId: _activeDashboardKpiScope()?.companyId,
      )) {
        // Stale at apply time: same non-terminal recovery as pre-fetch.
        _kpiPendingRerunQueued = true;
        _kpiPendingRerunReason ??= BusinessKpiCycleReason.scopeChangedRerun;
        debugPrint(
          formatBusinessKpiLoadDiagnostic(
            cycleGeneration: cycleGeneration,
            reason: reason,
            leg: BusinessKpiLegLabel.combined,
            attempt: attempt,
            status: BusinessKpiCombinedStatus.stale,
            elapsedMs: durationMs,
            scopeReady: true,
            authMode: authModeLabel,
          ),
        );
        return;
      }

      // BUSINESS-DASHBOARD-KPI-LOADING-UX-1: apply only a complete response.
      // Partial/failed legs must NOT invent zeros or wipe a prior snapshot.
      // BUSINESS-KPI-FIRST-LOAD-P0-REPAIR-1: on partial failure, decide
      // whether the coordinator may schedule exactly one bounded auto-retry.
      final complete = businessDashboardKpiResponseIsComplete(
        bookingsOk: bookingsKpisOk,
        tripKpisOk: tripKpisOk,
      );
      if (!complete ||
          nextOpenBookings == null ||
          nextCompletedRides == null ||
          nextUnpaidCompleted == null ||
          nextMonthlyIncomeCents == null) {
        // If bookings primary failed transient AND fallback also failed
        // transient, treat the combined bookings leg as transient. If the
        // primary succeeded (rare here because we are on the failure
        // path) fold accordingly.
        var effectiveBookingsOutcome = bookingsOutcome;
        if (fallbackAttempted && !bookingsKpisOk) {
          effectiveBookingsOutcome =
              businessKpiLegOutcomeIsTransient(bookingsOutcome) &&
                  businessKpiLegOutcomeIsTransient(fallbackOutcome)
              ? BusinessKpiLegOutcome.timeout
              : fallbackOutcome;
        }
        final retryDecision = resolveBusinessKpiRetryDecision(
          bookingsOutcome: effectiveBookingsOutcome,
          tripOutcome: tripOutcome,
          attempt: attempt,
        );
        if (retryDecision ==
            BusinessKpiRetryDecision.autoRetryTransient) {
          debugPrint(
            formatBusinessKpiLoadDiagnostic(
              cycleGeneration: cycleGeneration,
              reason: reason,
              leg: BusinessKpiLegLabel.combined,
              attempt: attempt,
              status: BusinessKpiCombinedStatus.transientWillRetry,
              elapsedMs: durationMs,
              scopeReady: true,
              authMode: authModeLabel,
            ),
          );
          _scheduleKpiAutoRetry();
          return;
        }
        _logBusinessKpiLoad(
          event: BusinessKpiLoadEvent.requestFailed,
          scopeGeneration: requestGeneration,
          durationMs: durationMs,
          detail:
              'trigger=$reason bookings_ok=$bookingsKpisOk trip_ok=$tripKpisOk',
        );
        debugPrint(
          formatBusinessKpiLoadDiagnostic(
            cycleGeneration: cycleGeneration,
            reason: reason,
            leg: BusinessKpiLegLabel.combined,
            attempt: attempt,
            status: BusinessKpiCombinedStatus.terminal,
            elapsedMs: durationMs,
            scopeReady: true,
            authMode: authModeLabel,
          ),
        );
        setState(() {
          _kpiLastRequestFailed = true;
        });
        return;
      }

      final nextGeneration = _kpiSnapshotGeneration + 1;
      final snapshot = BusinessDashboardKpiSnapshot(
        tenantId: capturedTenantId,
        companyId: capturedCompanyId,
        openBookingsCount: nextOpenBookings,
        completedRidesCount: nextCompletedRides,
        unpaidCompletedRidesCount: nextUnpaidCompleted,
        monthlyIncomeCents: nextMonthlyIncomeCents,
        currency: nextCurrency,
        responseGeneration: nextGeneration,
      );
      _logBusinessKpiLoad(
        event: BusinessKpiLoadEvent.requestCompleted,
        scopeGeneration: requestGeneration,
        durationMs: durationMs,
        detail: 'trigger=$reason',
      );
      setState(() {
        _applyDashboardKpiSnapshot(snapshot);
      });
      _logBusinessKpiLoad(
        event: BusinessKpiLoadEvent.snapshotApplied,
        scopeGeneration: requestGeneration,
        durationMs: durationMs,
        detail: 'trigger=$reason response_generation=$nextGeneration',
      );
      debugPrint(
        formatBusinessKpiLoadDiagnostic(
          cycleGeneration: cycleGeneration,
          reason: reason,
          leg: BusinessKpiLegLabel.combined,
          attempt: attempt,
          status: BusinessKpiCombinedStatus.success,
          elapsedMs: durationMs,
          scopeReady: true,
          authMode: authModeLabel,
        ),
      );
    } catch (e) {
      final durationMs =
          DateTime.now().difference(startedAt).inMilliseconds;
      final unexpectedOutcome = classifyBusinessKpiLegExceptionOutcome(
        errorRuntimeType: e.runtimeType.toString(),
      );
      _logBusinessKpiLoad(
        event: BusinessKpiLoadEvent.requestFailed,
        scopeGeneration: requestGeneration,
        durationMs: durationMs,
        detail: 'trigger=$reason',
      );
      debugPrint(
        '[BUSINESS_DASHBOARD][KPI][WARN] reason=fetch_failed trigger=$reason error=$e',
      );
      // Unexpected error in the outer scope (e.g. header resolution
      // failure). Treat it like a full combined-cycle transient failure so
      // the coordinator can schedule at most one bounded auto-retry.
      final retryDecision = resolveBusinessKpiRetryDecision(
        bookingsOutcome: unexpectedOutcome,
        tripOutcome: unexpectedOutcome,
        attempt: attempt,
      );
      if (retryDecision == BusinessKpiRetryDecision.autoRetryTransient) {
        debugPrint(
          formatBusinessKpiLoadDiagnostic(
            cycleGeneration: cycleGeneration,
            reason: reason,
            leg: BusinessKpiLegLabel.combined,
            attempt: attempt,
            status: BusinessKpiCombinedStatus.transientWillRetry,
            elapsedMs: durationMs,
            scopeReady: true,
            authMode: authModeLabel,
          ),
        );
        _scheduleKpiAutoRetry();
        return;
      }
      debugPrint(
        formatBusinessKpiLoadDiagnostic(
          cycleGeneration: cycleGeneration,
          reason: reason,
          leg: BusinessKpiLegLabel.combined,
          attempt: attempt,
          status: BusinessKpiCombinedStatus.terminal,
          elapsedMs: durationMs,
          scopeReady: true,
          authMode: authModeLabel,
        ),
      );
      if (mounted) {
        setState(() {
          _kpiLastRequestFailed = true;
        });
      }
    } finally {
      if (_kpiRequestTenantId == capturedTenantId &&
          _kpiRequestCompanyId == capturedCompanyId) {
        _kpiRefreshInFlight = false;
        _kpiRequestTenantId = null;
        _kpiRequestCompanyId = null;
      }
      if (mounted) setState(() {});
      // Dequeue at most one latest-wins rerun. This runs OUTSIDE the
      // in-flight window so it cannot loop while another cycle is still
      // executing. If the queued reason is `autoRetry` the timer already
      // handles scheduling; anything else fires a fresh cycle synchronously.
      _dequeueKpiPendingRerunIfAny();
    }
  }

  // BUSINESS-KPI-FIRST-LOAD-P0-REPAIR-1: schedule the single bounded
  // automatic retry. Cancels any previously-scheduled retry so at most one
  // pending timer exists at any time. Attempt 2 is not user-visible.
  void _scheduleKpiAutoRetry() {
    _kpiAutoRetryTimer?.cancel();
    _kpiAutoRetryTimer = Timer(
      const Duration(milliseconds: kBusinessKpiAutoRetryDelayMs),
      () {
        _kpiAutoRetryTimer = null;
        if (!mounted) return;
        unawaited(
          _refreshDashboardKpis(
            reason: BusinessKpiCycleReason.autoRetry,
            attempt: 2,
          ),
        );
      },
    );
  }

  void _dequeueKpiPendingRerunIfAny() {
    if (!_kpiPendingRerunQueued) return;
    final queuedReason =
        _kpiPendingRerunReason ?? BusinessKpiCycleReason.scopeChangedRerun;
    _kpiPendingRerunQueued = false;
    _kpiPendingRerunReason = null;
    if (!mounted) return;
    // Only run a rerun when scope is (still) ready — otherwise the scope
    // listener owns the trigger.
    if (!_kpiScopeIsReadyForRequest()) return;
    unawaited(_refreshDashboardKpis(reason: queuedReason));
  }

  String _normalizeBridgeText(String raw) {
    return raw.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  }

  String _normalizeBridgePhone(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return '';
    final hasPlus = trimmed.startsWith('+');
    final digits = trimmed.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return '';
    return hasPlus ? '+$digits' : digits;
  }

  String _maskBridgeDriverId(String raw) {
    return _maskBridgeDriverIdGlobal(raw);
  }

  bool _isSeededOrPlaceholderDriver(DriverProfile driver) {
    return _isSeededOrPlaceholderBridgeDriver(driver);
  }

  ({DriverProfile? driver, String reason}) _resolveOwnerDriverBridgeMatch() {
    final profile = companyProfileNotifier.value;
    if (profile == null) {
      return (driver: null, reason: 'no_safe_match');
    }

    final activeCompanyId = profile.companyId.trim();
    if (activeCompanyId.isEmpty) {
      return (driver: null, reason: 'no_safe_match');
    }

    final strictCandidates = driversNotifier.value
        .where(_isBusinessAdminPreviewEligibleDriver)
        .where((driver) {
          final scopedCompanyId = (driver.companyId ?? '').trim();
          return scopedCompanyId.isNotEmpty &&
              scopedCompanyId == activeCompanyId;
        })
        .toList(growable: false);

    final ownerName = _normalizeBridgeText(profile.ownerName);
    final ownerPhone = _normalizeBridgePhone(profile.phone);
    final ownerEmailToken = _normalizeBridgeText(
      profile.email.trim().isNotEmpty ? profile.email : profile.companyEmail,
    );
    final ownerEmails = <String>{
      if (ownerEmailToken.isNotEmpty) ownerEmailToken,
    };

    final matches = strictCandidates
        .where((driver) {
          final driverName = _normalizeBridgeText(driver.fullName);
          final driverPhone = _normalizeBridgePhone(driver.phone);
          final phoneMatch =
              ownerPhone.isNotEmpty &&
              driverPhone.isNotEmpty &&
              ownerPhone == driverPhone;
          // DriverProfile currently has no persisted email field.
          const driverEmail = '';
          final emailMatch =
              ownerEmails.isNotEmpty &&
              driverEmail.isNotEmpty &&
              ownerEmails.contains(driverEmail);
          final nameMatch =
              ownerName.isNotEmpty &&
              driverName.isNotEmpty &&
              ownerName == driverName;
          return phoneMatch || emailMatch || nameMatch;
        })
        .toList(growable: false);

    if (matches.length > 1) {
      return (driver: null, reason: 'multiple_matches');
    }
    if (matches.length == 1) {
      return (driver: matches.first, reason: 'owner_match');
    }
    return (driver: null, reason: 'no_safe_match');
  }

  List<DriverProfile> _resolveBusinessAdminDriverBridgeCandidates() {
    return _resolveBusinessAdminDriverBridgeCandidatesGlobal(
      logCandidates: true,
    );
  }

  Future<DriverProfile?> _showDriverOwnerBridgePicker(
    BuildContext context, {
    required List<DriverProfile> selectableDrivers,
  }) {
    return _showDriverOwnerBridgePickerSheet(
      context,
      selectableDrivers: selectableDrivers,
      tr: _tr,
    );
  }

  ({String tenantId, String companyId})? _businessDriverCockpitScope() {
    if (!CompanySessionStore.instance.hasValidCompanyContext) return null;
    final profileCompanyId =
        companyProfileNotifier.value?.companyId.trim() ?? '';
    final sessionCompanyId =
        (activeCompanySessionNotifier.value?.companyId ?? '').trim();
    if (profileCompanyId.isNotEmpty &&
        sessionCompanyId.isNotEmpty &&
        profileCompanyId != sessionCompanyId) {
      return null;
    }
    final resolvedCompanyId = profileCompanyId.isNotEmpty
        ? profileCompanyId
        : sessionCompanyId;
    if (resolvedCompanyId.isEmpty) return null;
    return (tenantId: resolvedCompanyId, companyId: resolvedCompanyId);
  }

  Future<void> _openBusinessDriverCockpitHome(BuildContext context) async {
    if (!context.mounted) return;
    setAppRole(AppRole.driver);
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const DriverHomePage(openedFromBusinessHome: true),
      ),
    );
  }

  void _showNoBusinessDriverAvailable(BuildContext context) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _tr(
            nl: 'Geen operationele chauffeur met voertuigtoewijzing gevonden.',
            en: 'No operational driver with a vehicle assignment found.',
            fr: 'Aucun chauffeur opérationnel avec véhicule assigné.',
            es: 'No se encontró ningún conductor operativo con vehículo asignado.',
          ),
        ),
      ),
    );
  }

  Future<void> _persistAndOpenBusinessDriverPreview(
    BuildContext context, {
    required ({String tenantId, String companyId}) scope,
    required DriverProfile driver,
    required String reason,
  }) async {
    await _saveBusinessDriverPreviewFromProfileGlobal(
      driver,
      tenantId: scope.tenantId,
      companyId: scope.companyId,
    );
    debugPrint(
      '[DRIVER_OWNER_BRIDGE][SELECT] driver=${_maskBridgeDriverId(driver.id)} reason=$reason',
    );
    if (!context.mounted) return;
    // SECURITY-REMOVE-CLIENT-ADMIN-TOKEN-P0-1 (Field Failure Fix, Commit 3):
    // fail-closed on operator-mint. The driver-selection record on disk is a
    // *display* pointer only; the operational driver surface must not open
    // without a real, scoped driver-session bearer. If the mint call fails,
    // remain on the company screen and surface a localised error. No meter,
    // tracking, navigation, or ride can start from this path.
    final minted = await _mintOperatorDriverSessionForPreview(
      context,
      scope: scope,
      driver: driver,
    );
    if (minted == null) return;
    if (!context.mounted) return;
    await _openBusinessDriverCockpitHome(context);
  }

  /// SECURITY-REMOVE-CLIENT-ADMIN-TOKEN-P0-1 (Field Failure Fix, Commit 3)
  ///
  /// Company-session-authenticated call to `POST /driver/session/mint-for-
  /// operator`. Returns `null` on any failure — the caller MUST refuse to
  /// enter the operational driver surface in that case. Success hydrates
  /// [activeDriverSessionNotifier] in memory only (no disk persistence) via
  /// [DriverSessionStore.setOperatorMintedDriverSessionInMemory].
  Future<OperatorMintedDriverSession?> _mintOperatorDriverSessionForPreview(
    BuildContext context, {
    required ({String tenantId, String companyId}) scope,
    required DriverProfile driver,
  }) async {
    final companySession = activeCompanySessionNotifier.value;
    final companyToken = (companySession?.companySessionToken ?? '').trim();
    if (companyToken.isEmpty) {
      debugPrint(
        '[OPERATOR_MINT][SKIP] reason=no_company_session driver=${_maskBridgeDriverId(driver.id)}',
      );
      _showOperatorMintFailureSnackbar(context, reason: 'unauthorized');
      return null;
    }
    OperatorMintedDriverSession minted;
    try {
      minted = await mintOperatorDriverSession(
        bookingBaseUrl: kBookingBaseUrl,
        companySessionToken: companyToken,
        targetDriverId: driver.id,
        tenantId: scope.tenantId,
        companyId: scope.companyId,
      );
    } on OperatorMintException catch (e) {
      debugPrint(
        '[OPERATOR_MINT][BUSINESS_PREVIEW_ABORT] reason=${e.reason} http=${e.httpStatus ?? -1} driver=${_maskBridgeDriverId(driver.id)}',
      );
      if (context.mounted) {
        _showOperatorMintFailureSnackbar(context, reason: e.reason);
      }
      return null;
    } catch (e) {
      debugPrint(
        '[OPERATOR_MINT][BUSINESS_PREVIEW_ABORT] reason=unexpected err=${e.runtimeType} driver=${_maskBridgeDriverId(driver.id)}',
      );
      if (context.mounted) {
        _showOperatorMintFailureSnackbar(context, reason: 'network');
      }
      return null;
    }
    final nowIso = DateTime.now().toUtc().toIso8601String();
    final session = ActiveDriverSession(
      driverId: minted.driverId,
      employeeNumber: driver.employeeNumber,
      fullName: minted.driverName ?? driver.fullName,
      phone: driver.phone,
      loggedInAt: minted.issuedAtUtc ?? nowIso,
      updatedAt: nowIso,
      tenantId: minted.tenantId.isNotEmpty ? minted.tenantId : scope.tenantId,
      companyId:
          minted.companyId.isNotEmpty ? minted.companyId : scope.companyId,
      companyCode: companySession?.companyCode,
      assignedVehicleId: _resolveMintedAssignedVehicleId(minted),
      driverPhotoUrl: driver.publicPortraitUrl,
      driverSessionToken: minted.driverSessionToken,
      driverSessionExpiresAtUtc: minted.driverSessionExpiresAtUtc,
      linkMethod: kOperatorMintDriverLinkMethod,
      expiresAt: minted.driverSessionExpiresAtUtc,
    );
    DriverSessionStore.instance.setOperatorMintedDriverSessionInMemory(session);
    return minted;
  }

  /// SECURITY-REMOVE-CLIENT-ADMIN-TOKEN-P0-1 (Field Failure Fix, Commit 3):
  /// The mint response carries the server-authoritative `assigned_vehicle_id`
  /// (or null). We do not fall back to a locally-derived value because
  /// vehicle assignment for driver-lifecycle mutations must be the server's
  /// decision, not the client's.
  String? _resolveMintedAssignedVehicleId(OperatorMintedDriverSession minted) {
    final serverValue = (minted.assignedVehicleId ?? '').trim();
    return serverValue.isEmpty ? null : serverValue;
  }

  /// SECURITY-REMOVE-CLIENT-ADMIN-TOKEN-P0-1 (Field Failure Fix, Commit 3):
  /// Localised snackbar for operator-mint failure. Distinguishes the most
  /// actionable classes (session expired, driver not found / inactive,
  /// forbidden scope, network); everything else falls back to a generic
  /// "could not open driver view" message. Bearer values are never referenced
  /// in these strings.
  void _showOperatorMintFailureSnackbar(
    BuildContext context, {
    required String reason,
  }) {
    if (!context.mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger.hideCurrentSnackBar();
    String message;
    switch (reason) {
      case 'unauthorized':
        message = _tr(
          nl:
              'Bedrijfssessie is verlopen. Meld opnieuw aan om de chauffeursweergave te openen.',
          en:
              'Company session expired. Sign in again to open the driver view.',
          fr:
              'Session entreprise expirée. Reconnectez-vous pour ouvrir la vue chauffeur.',
          es:
              'Sesión de empresa caducada. Inicia sesión de nuevo para abrir la vista del chofer.',
        );
        break;
      case 'forbidden':
        message = _tr(
          nl:
              'Toegang tot deze chauffeur geweigerd door de server. Controleer of de chauffeur bij dit bedrijf hoort.',
          en:
              'Server refused access to this driver. Check the driver belongs to this company.',
          fr:
              'Le serveur a refusé l’accès à ce chauffeur. Vérifiez que le chauffeur appartient à cette entreprise.',
          es:
              'El servidor denegó el acceso a este chofer. Verifica que el chofer pertenece a esta empresa.',
        );
        break;
      case 'driver_not_found':
        message = _tr(
          nl:
              'Chauffeur niet gevonden. Vernieuw de chauffeurslijst en probeer opnieuw.',
          en: 'Driver not found. Refresh the driver list and try again.',
          fr:
              'Chauffeur introuvable. Actualisez la liste des chauffeurs et réessayez.',
          es:
              'Chofer no encontrado. Actualiza la lista de chóferes e inténtalo de nuevo.',
        );
        break;
      case 'driver_inactive':
        message = _tr(
          nl:
              'Deze chauffeur is niet actief. Activeer de chauffeur voordat u de chauffeursweergave opent.',
          en:
              'This driver is not active. Activate the driver before opening the driver view.',
          fr:
              'Ce chauffeur n’est pas actif. Activez le chauffeur avant d’ouvrir la vue chauffeur.',
          es:
              'Este chofer no está activo. Actívalo antes de abrir la vista del chofer.',
        );
        break;
      case 'timeout':
      case 'network':
        message = _tr(
          nl:
              'Geen verbinding met de server. Controleer uw internet en probeer opnieuw.',
          en: 'No connection to the server. Check your internet and retry.',
          fr:
              'Aucune connexion au serveur. Vérifiez votre connexion et réessayez.',
          es: 'Sin conexión con el servidor. Verifica tu conexión y reintenta.',
        );
        break;
      default:
        message = _tr(
          nl:
              'Kan chauffeursweergave niet openen. Probeer het later opnieuw.',
          en: 'Could not open the driver view. Please try again later.',
          fr: 'Impossible d’ouvrir la vue chauffeur. Réessayez plus tard.',
          es:
              'No se pudo abrir la vista del chofer. Vuelve a intentarlo más tarde.',
        );
    }
    messenger.showSnackBar(
      SnackBar(duration: const Duration(seconds: 6), content: Text(message)),
    );
  }

  Future<void> _openDriverCockpitView(BuildContext context) async {
    await DriverDocumentsStore.instance.load();
    if (!context.mounted) return;
    DriverSessionStore.instance.prepareBusinessDriverCockpitEntry();
    if (!CompanySessionStore.instance.hasValidCompanyContext) {
      debugPrint('[DRIVER_OWNER_BRIDGE][SKIP] reason=no_company_context');
      _showNoBusinessDriverAvailable(context);
      return;
    }
    final scope = _businessDriverCockpitScope();
    if (scope == null) {
      debugPrint('[DRIVER_OWNER_BRIDGE][SKIP] reason=scope_mismatch');
      _showNoBusinessDriverAvailable(context);
      return;
    }
    final savedPreview = await DriverSessionStore.instance
        .loadBusinessDriverPreview(
          tenantId: scope.tenantId,
          companyId: scope.companyId,
        );
    final resolvedPreview = _resolveBusinessDriverForPreviewGlobal(
      tenantId: scope.tenantId,
      companyId: scope.companyId,
      savedPreview: savedPreview,
    );
    final resolvedDriver = resolvedPreview.driver;
    if (resolvedDriver != null) {
      if (!context.mounted) return;
      await _persistAndOpenBusinessDriverPreview(
        context,
        scope: scope,
        driver: resolvedDriver,
        reason: resolvedPreview.reason,
      );
      return;
    }
    if (savedPreview != null) {
      await DriverSessionStore.instance.clearBusinessPreviewDriverSelection(
        tenantId: scope.tenantId,
        companyId: scope.companyId,
      );
      debugPrint(
        '[DRIVER_OWNER_BRIDGE][SKIP] reason=preview_driver_inactive driver=${_maskBridgeDriverId(savedPreview.driverId)}',
      );
    }
    final ownerBridge = _resolveOwnerDriverBridgeMatch();
    final matchedDriver = ownerBridge.driver;
    if (matchedDriver != null) {
      if (!context.mounted) return;
      await _persistAndOpenBusinessDriverPreview(
        context,
        scope: scope,
        driver: matchedDriver,
        reason: 'owner_match',
      );
      return;
    }
    final selectableDrivers =
        _resolveOperationalCockpitDriverBridgeCandidatesGlobal(
          companyId: scope.companyId,
          logCandidates: true,
        );
    if (selectableDrivers.isEmpty) {
      debugPrint(
        '[DRIVER_OWNER_BRIDGE][SKIP] reason=no_operational_assigned_driver',
      );
      if (!context.mounted) return;
      _showNoBusinessDriverAvailable(context);
      return;
    }
    DriverProfile selectedDriver;
    if (selectableDrivers.length == 1) {
      selectedDriver = selectableDrivers.first;
    } else {
      debugPrint(
        '[DRIVER_OWNER_BRIDGE][PICKER_OPEN] count=${selectableDrivers.length}',
      );
      if (!context.mounted) return;
      final picked = await _showDriverOwnerBridgePicker(
        context,
        selectableDrivers: selectableDrivers,
      );
      if (!context.mounted) return;
      if (picked == null) return;
      selectedDriver = picked;
    }
    if (!context.mounted) return;
    await _persistAndOpenBusinessDriverPreview(
      context,
      scope: scope,
      driver: selectedDriver,
      reason: 'picker_selected',
    );
  }

  Future<void> _openBusinessBookingsOverview(BuildContext context) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const CompanyBookingsOverviewPage(),
      ),
    );
    if (!mounted) return;
    unawaited(
      _refreshDashboardKpis(reason: BusinessKpiCycleReason.routeReturn),
    );
  }

  ({Color bg, Color border, Color text}) _statusColors(CompanyProfile profile) {
    return (
      bg: profile.isSuspended
          ? const Color(0xFF3A1010)
          : profile.isVerified
          ? const Color(0xFF12331F)
          : const Color(0xFF2A2410),
      border: profile.isSuspended
          ? Colors.red.withOpacity(0.45)
          : profile.isVerified
          ? const Color(0xFF4ADE80).withOpacity(0.45)
          : kFluxidiYellow.withOpacity(0.55),
      text: profile.isSuspended
          ? const Color(0xFFFFB4B4)
          : profile.isVerified
          ? const Color(0xFFB8F5C8)
          : const Color(0xFFE5D4A1),
    );
  }

  Widget _statusPill(CompanyProfile profile, {bool compact = false}) {
    final colors = _statusColors(profile);
    final fontSize = compact ? 10.5 : 12.0;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 10,
        vertical: compact ? 3.5 : 5,
      ),
      decoration: BoxDecoration(
        color: colors.bg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.border),
      ),
      child: Text(
        profile.verificationBadgeLabel(appConfig.currentLanguage),
        style: TextStyle(
          color: colors.text,
          fontWeight: FontWeight.w700,
          fontSize: fontSize,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  String _companyInitials(CompanyProfile? profile) {
    final name = profile?.companyName.trim() ?? '';
    if (name.isEmpty) return 'FB';
    final parts = name
        .split(RegExp(r'\s+'))
        .where((part) => part.trim().isNotEmpty)
        .toList(growable: false);
    if (parts.isEmpty) return 'FB';
    final first = parts.first.substring(0, 1).toUpperCase();
    final second = parts.length > 1
        ? parts[1].substring(0, 1).toUpperCase()
        : (parts.first.length > 1
              ? parts.first.substring(1, 2).toUpperCase()
              : 'B');
    return '$first$second';
  }

  Future<void> _openCompanyDetails(BuildContext context) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const CompanyProfileEditPage()),
    );
  }

  Future<void> _openBusinessHelpManual(BuildContext context) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const BusinessHelpManualPage()),
    );
  }

  String _normalizePublicBookingCompanyCode(String raw) {
    return raw.trim().toUpperCase().replaceAll(RegExp(r'\s+'), '');
  }

  bool _isValidPublicBookingCompanyCode(String value) {
    final code = _normalizePublicBookingCompanyCode(value);
    if (code.isEmpty) return false;
    return RegExp(r'^FLX(?:-?[0-9]{4,12})$').hasMatch(code);
  }

  bool _isGeneratedSequentialPublicCompanyCode(String value) {
    final code = _normalizePublicBookingCompanyCode(value);
    return RegExp(r'^FLX-[0-9]{5,12}$').hasMatch(code);
  }

  String? _resolvePublicBookingCompanyCodeForDashboard() {
    String? readFirstValidFromMap(Map<String, dynamic>? map) {
      if (map == null) return null;
      for (final key in const <String>[
        'public_company_code',
        'publicCompanyCode',
        'company_code',
        'companyCode',
      ]) {
        final normalized = _normalizePublicBookingCompanyCode(
          (map[key] ?? '').toString(),
        );
        if (_isValidPublicBookingCompanyCode(normalized)) return normalized;
      }
      return null;
    }

    final backendMap = localBackendBusinessProfileNotifier.value?.toJson();
    final profileMap = companyProfileNotifier.value?.toJson();
    final sessionCode = _normalizePublicBookingCompanyCode(
      activeCompanySessionNotifier.value?.companyCode ?? '',
    );

    final candidates = <String>[];
    if (backendMap is Map<String, dynamic>) {
      final backendCode = readFirstValidFromMap(backendMap);
      if (backendCode != null) candidates.add(backendCode);
    }
    if (profileMap is Map<String, dynamic>) {
      final profileCode = readFirstValidFromMap(profileMap);
      if (profileCode != null) candidates.add(profileCode);
    }
    if (_isValidPublicBookingCompanyCode(sessionCode)) {
      candidates.add(sessionCode);
    }

    for (final code in candidates) {
      if (_isGeneratedSequentialPublicCompanyCode(code)) return code;
    }
    return candidates.isNotEmpty ? candidates.first : null;
  }

  String _preparedPublicBookingUrlForDashboard(String companyCode) {
    final safeCompanyCode = _normalizePublicBookingCompanyCode(companyCode);
    final base = kPublicBookingBaseUrl.trim().isEmpty
        ? 'https://fluxidi.com'
        : kPublicBookingBaseUrl.trim();
    final encodedCompanyCode = Uri.encodeQueryComponent(safeCompanyCode);
    try {
      final uri = Uri.parse(base);
      final normalizedPath = uri.path.trim().isEmpty || uri.path == '/'
          ? '/book'
          : (uri.path.endsWith('/book') ? uri.path : '${uri.path}/book');
      final nextQuery = Map<String, String>.from(uri.queryParameters);
      nextQuery['company_code'] = safeCompanyCode;
      return uri
          .replace(path: normalizedPath, queryParameters: nextQuery)
          .toString();
    } catch (_) {
      return '$base/book?company_code=$encodedCompanyCode';
    }
  }

  Future<void> _sharePublicBookingQrCardImage({
    required BuildContext context,
    required GlobalKey repaintBoundaryKey,
    required String publicCompanyCode,
    required String publicBookingUrl,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    final devicePixelRatio = MediaQuery.of(context).devicePixelRatio;
    final shareMessage = _t(
      nl: 'Boek je rit eenvoudig via deze QR-code of link.',
      en: 'Book your ride easily using this QR code or link.',
      fr: 'Réservez facilement votre trajet via ce code QR ou ce lien.',
      es: 'Reserva tu viaje fácilmente con este código QR o enlace.',
    );
    final errorMessage = _t(
      nl: 'QR-afbeelding delen mislukt. Probeer opnieuw.',
      en: 'Failed to share QR image. Please try again.',
      fr: 'Le partage de l’image QR a échoué. Réessayez.',
      es: 'No se pudo compartir la imagen QR. Inténtalo de nuevo.',
    );

    try {
      await Future<void>.delayed(const Duration(milliseconds: 30));
      final renderObject = repaintBoundaryKey.currentContext
          ?.findRenderObject();
      if (renderObject is! RenderRepaintBoundary) {
        messenger.showSnackBar(SnackBar(content: Text(errorMessage)));
        return;
      }
      final image = await renderObject.toImage(
        pixelRatio: math.max(2.0, math.min(devicePixelRatio * 2, 3.0)),
      );
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) {
        messenger.showSnackBar(SnackBar(content: Text(errorMessage)));
        return;
      }
      final bytes = Uint8List.fromList(byteData.buffer.asUint8List());
      final tempDir = await getTemporaryDirectory();
      final fileCode = publicCompanyCode
          .replaceAll(RegExp(r'[^A-Z0-9-]'), '')
          .replaceAll('-', '');
      final filePath =
          '${tempDir.path}${Platform.pathSeparator}fluxidi_booking_qr_$fileCode.png';
      final file = File(filePath);
      await file.writeAsBytes(bytes, flush: true);
      await Share.shareXFiles(
        <XFile>[XFile(file.path, mimeType: 'image/png')],
        text: shareMessage,
        subject: 'Fluxidi QR',
      );
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(errorMessage)));
    }
  }

  Future<void> _showPublicBookingShareQuickAccess(BuildContext context) async {
    final publicCompanyCode = _resolvePublicBookingCompanyCodeForDashboard();
    if (publicCompanyCode == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _t(
              nl: 'Publieke bedrijfscode ontbreekt. Verifieer je bedrijf eerst via Bedrijfsinstellingen.',
              en: 'Public company code is missing. Verify your company first via Business Settings.',
              fr: 'Le code entreprise public est manquant. Vérifiez d’abord votre entreprise via les Paramètres entreprise.',
              es: 'Falta el código público de empresa. Verifica primero tu empresa en Ajustes de empresa.',
            ),
          ),
        ),
      );
      return;
    }

    final publicBookingUrl = _preparedPublicBookingUrlForDashboard(
      publicCompanyCode,
    );
    final qrCardBoundaryKey = GlobalKey();
    final profileName = (companyProfileNotifier.value?.companyName ?? '')
        .trim();
    final qrCardTitle = profileName.isNotEmpty ? profileName : 'Fluxidi';

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final themeVariant = businessThemeNotifier.value;
        final palette = _businessThemePalette;
        final isExecutiveGold =
            themeVariant == BusinessThemeVariant.executiveGold;
        final isCorporateBlue =
            themeVariant == BusinessThemeVariant.corporateBlue;
        final isCleanProfessional =
            themeVariant == BusinessThemeVariant.cleanProfessional;
        final isEmeraldIvory =
            themeVariant == BusinessThemeVariant.emeraldIvory;
        final sheetBg = palette.surface;
        final panelBg = palette.surfaceAlt;
        final borderColor = palette.border.withOpacity(
          isCleanProfessional ? 0.9 : 0.62,
        );
        final outerBorderColor = Color.lerp(
          palette.border,
          palette.accent,
          isEmeraldIvory ? 0.28 : 0.16,
        )!;
        final titleColor = palette.textPrimary;
        final bodyColor = palette.textMuted.withOpacity(
          isCleanProfessional ? 0.96 : 0.88,
        );
        final codeColor = isExecutiveGold
            ? palette.accent.withOpacity(0.98)
            : palette.accent;
        final urlColor = palette.textPrimary;
        final qrCardBg = isCleanProfessional
            ? palette.surface
            : (isEmeraldIvory
                  ? const Color(0xFFF6EEDB)
                  : (isExecutiveGold
                        ? const Color(0xFFF8F2E3)
                        : (isCorporateBlue
                              ? const Color(0xFFF7FAFF)
                              : Colors.white)));
        final qrCardBorderColor = palette.accent.withOpacity(
          isCleanProfessional ? 0.42 : (isEmeraldIvory ? 0.72 : 0.55),
        );
        final qrCardTextColor = isCleanProfessional
            ? palette.textPrimary
            : const Color(0xFF101010);
        final qrCardSubtleTextColor = isCleanProfessional
            ? palette.textMuted
            : const Color(0xFF262626);
        final outlinedButtonStyle = OutlinedButton.styleFrom(
          foregroundColor: palette.textPrimary,
          side: BorderSide(color: palette.accent.withOpacity(0.58)),
          backgroundColor: isCleanProfessional
              ? palette.surfaceAlt.withOpacity(0.72)
              : Colors.transparent,
        );
        final filledButtonStyle = FilledButton.styleFrom(
          foregroundColor: palette.textOnAccent,
          backgroundColor: palette.accent,
        );
        final maxQrSize = math.min(
          180.0,
          MediaQuery.of(sheetContext).size.width - 96,
        );
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Container(
              decoration: BoxDecoration(
                color: sheetBg,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: outerBorderColor),
                boxShadow: [
                  BoxShadow(
                    color: palette.shadow.withOpacity(
                      isCleanProfessional ? 0.12 : 0.34,
                    ),
                    blurRadius: 22,
                    spreadRadius: 0.5,
                  ),
                ],
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _t(
                        nl: 'Publieke boekingslink',
                        en: 'Public booking link',
                        fr: 'Lien de réservation public',
                        es: 'Enlace público de reserva',
                      ),
                      style: TextStyle(
                        color: titleColor,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _t(
                        nl: 'Deel deze link of QR-code met klanten zodat zij rechtstreeks kunnen boeken.',
                        en: 'Share this link or QR code with customers so they can book directly.',
                        fr: 'Partagez ce lien ou ce code QR avec les clients afin qu’ils puissent réserver directement.',
                        es: 'Comparte este enlace o código QR con los clientes para que puedan reservar directamente.',
                      ),
                      style: TextStyle(
                        color: bodyColor,
                        fontSize: 12.5,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: panelBg,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: borderColor),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _t(
                              nl: 'Publieke bedrijfscode',
                              en: 'Public company code',
                              fr: 'Code entreprise public',
                              es: 'Código público de empresa',
                            ),
                            style: TextStyle(
                              color: bodyColor,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 6),
                          SelectableText(
                            publicCompanyCode,
                            style: TextStyle(
                              color: codeColor,
                              fontFamily: 'monospace',
                              fontSize: 13.2,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: panelBg,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: borderColor),
                      ),
                      child: SelectableText(
                        publicBookingUrl,
                        style: TextStyle(
                          color: urlColor,
                          fontFamily: 'monospace',
                          fontSize: 12.2,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Center(
                      child: RepaintBoundary(
                        key: qrCardBoundaryKey,
                        child: Container(
                          width: math.min(
                            320.0,
                            MediaQuery.of(sheetContext).size.width - 56,
                          ),
                          padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
                          decoration: BoxDecoration(
                            color: qrCardBg,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: qrCardBorderColor),
                            boxShadow: [
                              BoxShadow(
                                color: palette.shadow.withOpacity(
                                  isCleanProfessional ? 0.09 : 0.18,
                                ),
                                blurRadius: 14,
                                spreadRadius: 0.2,
                              ),
                            ],
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                qrCardTitle,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: qrCardTextColor,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _t(
                                  nl: 'Scan om een rit te boeken',
                                  en: 'Scan to book a ride',
                                  fr: 'Scannez pour réserver une course',
                                  es: 'Escanea para reservar un viaje',
                                ),
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: qrCardSubtleTextColor,
                                  fontSize: 11.2,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 8),
                              QrImageView(
                                data: publicBookingUrl,
                                version: QrVersions.auto,
                                size: maxQrSize,
                                backgroundColor: Colors.white,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                publicCompanyCode,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: qrCardTextColor,
                                  fontFamily: 'monospace',
                                  fontSize: 12.4,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _t(
                                  nl: 'Aangedreven door Fluxidi',
                                  en: 'Powered by Fluxidi',
                                  fr: 'Propulsé par Fluxidi',
                                  es: 'Con tecnología de Fluxidi',
                                ),
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: qrCardSubtleTextColor.withOpacity(
                                    0.82,
                                  ),
                                  fontSize: 10.0,
                                  fontWeight: FontWeight.w600,
                                  height: 1.22,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton.icon(
                          style: outlinedButtonStyle,
                          onPressed: () async {
                            await Clipboard.setData(
                              ClipboardData(text: publicCompanyCode),
                            );
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  _t(
                                    nl: 'Publieke bedrijfscode gekopieerd',
                                    en: 'Public company code copied',
                                    fr: 'Code entreprise public copié',
                                    es: 'Código público de empresa copiado',
                                  ),
                                ),
                              ),
                            );
                          },
                          icon: const Icon(Icons.copy_outlined, size: 16),
                          label: Text(
                            _t(
                              nl: 'Kopieer code',
                              en: 'Copy code',
                              fr: 'Copier le code',
                              es: 'Copiar código',
                            ),
                          ),
                        ),
                        OutlinedButton.icon(
                          style: outlinedButtonStyle,
                          onPressed: () async {
                            await Clipboard.setData(
                              ClipboardData(text: publicBookingUrl),
                            );
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  _t(
                                    nl: 'Publieke boekingslink gekopieerd',
                                    en: 'Public booking link copied',
                                    fr: 'Lien de réservation public copié',
                                    es: 'Enlace público de reserva copiado',
                                  ),
                                ),
                              ),
                            );
                          },
                          icon: const Icon(Icons.copy_outlined, size: 16),
                          label: Text(
                            _t(
                              nl: 'Kopieer link',
                              en: 'Copy link',
                              fr: 'Copier le lien',
                              es: 'Copiar enlace',
                            ),
                          ),
                        ),
                        FilledButton.icon(
                          style: filledButtonStyle,
                          onPressed: () => _sharePublicBookingQrCardImage(
                            context: context,
                            repaintBoundaryKey: qrCardBoundaryKey,
                            publicCompanyCode: publicCompanyCode,
                            publicBookingUrl: publicBookingUrl,
                          ),
                          icon: const Icon(Icons.qr_code_2_rounded, size: 16),
                          label: Text(
                            _t(
                              nl: 'Deel QR',
                              en: 'Share QR',
                              fr: 'Partager QR',
                              es: 'Compartir QR',
                            ),
                          ),
                        ),
                        OutlinedButton.icon(
                          style: outlinedButtonStyle,
                          onPressed: () async {
                            await Share.share(publicBookingUrl);
                          },
                          icon: const Icon(Icons.share_outlined, size: 16),
                          label: Text(
                            _t(
                              nl: 'Delen',
                              en: 'Share',
                              fr: 'Partager',
                              es: 'Compartir',
                            ),
                          ),
                        ),
                        FilledButton.icon(
                          style: filledButtonStyle,
                          onPressed: () async {
                            try {
                              final uri = Uri.parse(publicBookingUrl);
                              final launched = await launchUrl(
                                uri,
                                mode: LaunchMode.externalApplication,
                              );
                              if (!launched && context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      _t(
                                        nl: 'Publieke boekingslink kon niet geopend worden.',
                                        en: 'Could not open public booking link.',
                                        fr: 'Impossible d’ouvrir le lien de réservation public.',
                                        es: 'No se pudo abrir el enlace público de reserva.',
                                      ),
                                    ),
                                  ),
                                );
                              }
                            } catch (_) {
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    _t(
                                      nl: 'Publieke boekingslink kon niet geopend worden.',
                                      en: 'Could not open public booking link.',
                                      fr: 'Impossible d’ouvrir le lien de réservation public.',
                                      es: 'No se pudo abrir el enlace público de reserva.',
                                    ),
                                  ),
                                ),
                              );
                            }
                          },
                          icon: const Icon(
                            Icons.open_in_new_outlined,
                            size: 16,
                          ),
                          label: Text(
                            _t(
                              nl: 'Open link',
                              en: 'Open link',
                              fr: 'Ouvrir le lien',
                              es: 'Abrir enlace',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _switchCompany(BuildContext context) async {
    // SECURITY-REMOVE-CLIENT-ADMIN-TOKEN-P0-1 (Field Failure Fix, Blocker Fix):
    // Refuse to switch company while a live ride, STOP teardown or
    // direct-trip finalize/reconcile still requires the operator-minted
    // driver bearer. `operatorMintedBearerInFlightNotifier` is authoritative
    // for as long as the reconcile is pending; it is published false only
    // after the reconcile completes.
    if (operatorMintedBearerInFlightNotifier.value) {
      debugPrint(
        '[COMPANY_END][BLOCKED] path=switch_company cause=operator_bearer_in_flight',
      );
      _showCompanyEndBlockedForRideInFlight(context);
      return;
    }
    // Clear the operator-minted driver session (memory-only) before the
    // company session so no orphaned bearer remains after the switch.
    // Standalone / pairing sessions are untouched.
    DriverSessionStore.instance.clearOperatorMintedSessionOnCompanyEnd(
      reason: 'business_home_switch_company',
    );
    await CompanySessionStore.instance.clearLocalCompanyState();
    if (!context.mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => const RoleEntryPage()),
      (route) => false,
    );
  }

  /// SECURITY-REMOVE-CLIENT-ADMIN-TOKEN-P0-1 (Field Failure Fix, Blocker Fix):
  /// Localised snackbar shown when a company-end action (logout / switch)
  /// is refused because the operator-minted driver bearer is still needed
  /// by a live ride, STOP teardown or direct-trip finalize/reconcile.
  void _showCompanyEndBlockedForRideInFlight(BuildContext context) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 4),
        content: Text(
          _tr(
            nl:
                'Rond de rit eerst af voordat u van bedrijf wisselt.',
            en: 'Finish the ride before switching companies.',
            fr: 'Terminez la course avant de changer d\'entreprise.',
            es: 'Finalice el viaje antes de cambiar de empresa.',
          ),
        ),
      ),
    );
  }

  String _normalizeActivationCompanyCode(String raw) {
    var text = raw.trim().toUpperCase();
    if (text.isEmpty) return '';
    text = text.replaceAll(RegExp(r'\s+'), '-');
    text = text.replaceAll(RegExp(r'[^A-Z0-9-]'), '');
    text = text.replaceAll(RegExp(r'-+'), '-');
    text = text.replaceAll(RegExp(r'^-+|-+$'), '');
    return text;
  }

  bool _isValidActivationCompanyCode(String value) {
    final code = _normalizeActivationCompanyCode(value);
    if (code.length < 4 || code.length > 24) return false;
    if (!RegExp(r'^[A-Z0-9-]+$').hasMatch(code)) return false;
    if (!RegExp(r'[A-Z0-9]').hasMatch(code)) return false;
    final parts = code.split('-').where((p) => p.trim().isNotEmpty).toList();
    if (parts.length != 2) return false;
    if (!RegExp(r'^[A-Z0-9]{2,10}$').hasMatch(parts[0])) return false;
    if (!RegExp(r'^[A-Z0-9]{2,12}$').hasMatch(parts[1])) return false;
    return true;
  }

  ({String tenantId, String companyId})?
  _activeCompanyScopeForPairingCodeCreate() {
    final sessionCompany =
        activeCompanySessionNotifier.value?.companyId.trim() ?? '';
    if (sessionCompany.isNotEmpty) {
      return (tenantId: sessionCompany, companyId: sessionCompany);
    }
    final profileCompany = companyProfileNotifier.value?.companyId.trim() ?? '';
    if (profileCompany.isNotEmpty) {
      return (tenantId: profileCompany, companyId: profileCompany);
    }
    return null;
  }

  String? _activeCompanyCodeForPairingCodeCreate() {
    final canonicalCode = _resolvePublicBookingCompanyCodeForDashboard();
    final normalized = _normalizeActivationCompanyCode(canonicalCode ?? '');
    if (_isValidActivationCompanyCode(normalized)) return normalized;
    return null;
  }

  String? _publicCompanyCodeFromBootstrapPayload(Map<String, dynamic> payload) {
    String readTopLevel() {
      return _normalizeActivationCompanyCode(
        (payload['public_company_code'] ??
                payload['publicCompanyCode'] ??
                payload['company_code'] ??
                payload['companyCode'] ??
                '')
            .toString(),
      );
    }

    String readCompanyNode() {
      final companyNode = payload['company'];
      if (companyNode is! Map) return '';
      final map = Map<String, dynamic>.from(companyNode);
      return _normalizeActivationCompanyCode(
        (map['public_company_code'] ??
                map['publicCompanyCode'] ??
                map['company_code'] ??
                map['companyCode'] ??
                map['code'] ??
                '')
            .toString(),
      );
    }

    String readBusinessProfileNode() {
      final node = payload['business_profile'];
      if (node is! Map) return '';
      final map = Map<String, dynamic>.from(node);
      return _normalizeActivationCompanyCode(
        (map['public_company_code'] ??
                map['publicCompanyCode'] ??
                map['company_code'] ??
                map['companyCode'] ??
                '')
            .toString(),
      );
    }

    final fromBusinessProfile = readBusinessProfileNode();
    if (_isValidActivationCompanyCode(fromBusinessProfile)) {
      return fromBusinessProfile;
    }
    final fromCompany = readCompanyNode();
    if (_isValidActivationCompanyCode(fromCompany)) return fromCompany;
    final top = readTopLevel();
    if (_isValidActivationCompanyCode(top)) return top;
    return null;
  }

  Future<({String? companyCode, String source})>
  _resolvePublicCompanyCodeForPairingCodeCreate() async {
    final fromSession = _activeCompanyCodeForPairingCodeCreate();
    if (fromSession != null) {
      return (companyCode: fromSession, source: 'canonical');
    }

    final session = activeCompanySessionNotifier.value;
    final token = (session?.companySessionToken ?? '').trim();
    if (token.isEmpty) {
      return (companyCode: null, source: 'none');
    }

    try {
      final bootstrap = await fetchCompanyBootstrapWithToken(
        companySessionToken: token,
      );
      if (bootstrap is Map<String, dynamic>) {
        final fromBootstrap = _publicCompanyCodeFromBootstrapPayload(bootstrap);
        if (fromBootstrap != null) {
          if (session != null) {
            activeCompanySessionNotifier.value = session.copyWith(
              companyCode: fromBootstrap,
            );
          }
          return (companyCode: fromBootstrap, source: 'bootstrap');
        }
      }
    } catch (_) {}
    return (companyCode: null, source: 'none');
  }

  Future<void> _showNewDeviceActivationCodeDialog(BuildContext context) async {
    // FIELD-RELEASE-BLOCKER-DEVICE-ACTIVATION-AUTH-P0-2: this affordance was
    // previously blocked in release builds because it still called
    // _adminHeaders() (an empty map after SECURITY-REMOVE-CLIENT-ADMIN-TOKEN-P0-1)
    // and would therefore fail every request with an unauthenticated call
    // that the booking worker rethrew as Cloudflare Error 1101. The flow now
    // sends the company-owner session bearer via resolveCompanyOwnerAuthHeaders()
    // and the release-mode gate is removed. The company-owner-auth-context
    // requirement remains so a stale/logged-out company cannot even initiate
    // the request.
    if (!hasCompanyOwnerAuthContext()) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _t(
              nl: 'Toestelkoppeling is nu niet beschikbaar.',
              en: 'Device pairing is currently unavailable.',
              fr: 'Le jumelage d’appareil est actuellement indisponible.',
              es: 'La vinculación de dispositivo no está disponible actualmente.',
            ),
          ),
        ),
      );
      return;
    }

    final backendContext = await _resolveBackendUsableCompanyContextForAdmin(
      reason: 'business_home_pairing_code_create',
      logDegraded: true,
    );
    if (!context.mounted) return;
    if (!backendContext.usable) {
      debugPrint(
        '[PAIR_CODE_CREATE][BLOCKED] code=${backendContext.reasonCode} source=${backendContext.tokenSource}',
      );
      await _showDegradedCompanySessionRecoveryDialog(
        context,
        reason: 'business_home_pairing_code_create',
      );
      return;
    }

    final scope = _activeCompanyScopeForPairingCodeCreate();
    final codeResolution =
        await _resolvePublicCompanyCodeForPairingCodeCreate();
    final companyCode = codeResolution.companyCode;
    debugPrint(
      '[PAIR_CODE_CREATE][SCOPE] has_scope=${scope != null} has_public_code=${companyCode != null} source=${codeResolution.source}',
    );
    if (scope == null || companyCode == null) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _t(
              nl: 'Verifieer dit bedrijf eerst voordat u nieuwe toestellen kunt koppelen.',
              en: 'Verify this company first before pairing new devices.',
              fr: 'Vérifiez d’abord cette entreprise avant d’associer de nouveaux appareils.',
              es: 'Verifica primero esta empresa antes de vincular nuevos dispositivos.',
            ),
          ),
        ),
      );
      return;
    }
    if (!context.mounted) return;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF111111),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: kFluxidiYellow.withOpacity(0.45)),
        ),
        content: Row(
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2.3,
                color: kFluxidiYellow.withOpacity(0.95),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _t(
                  nl: 'Activatiecode aanmaken...',
                  en: 'Generating activation code...',
                  fr: 'Génération du code d’activation...',
                  es: 'Generando código de activación...',
                ),
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );

    Map<String, dynamic> payload = const <String, dynamic>{};
    int statusCode = -1;
    try {
      final endpoint =
          Uri.parse('$kBookingBaseUrl/admin/company/link-code/create').replace(
            queryParameters: <String, String>{
              'tenant_id': scope.tenantId,
              'company_id': scope.companyId,
            },
          );
      debugPrint(
        '[PAIR_CODE_CREATE][REQ] tenant=${_maskScopeForLog(scope.tenantId)} company=${_maskScopeForLog(scope.companyId)} code=$companyCode',
      );
      // FIELD-RELEASE-BLOCKER-DEVICE-ACTIVATION-AUTH-P0-2: use the company-
      // owner session bearer via resolveCompanyOwnerAuthHeaders(). That helper
      // already sets `Authorization: Bearer <company-session>`, `Accept:
      // application/json` and `Content-Type: application/json`; we re-assert
      // Accept and Content-Type explicitly as a defense-in-depth guarantee.
      // No ADMIN_TOKEN / x-admin-token header is ever attached from the client.
      final companyAuth = await resolveCompanyOwnerAuthHeaders();
      if (companyAuth.mode == CompanyOwnerAuthMode.none) {
        debugPrint('[PAIR_CODE_CREATE][NO_AUTH] mode=none');
      } else {
        final headers = <String, String>{
          ...companyAuth.headers,
          'Accept': 'application/json',
          'Content-Type': 'application/json',
        };
        final response = await http
            .post(
              endpoint,
              headers: headers,
              body: jsonEncode(<String, dynamic>{
                'tenant_id': scope.tenantId,
                'company_id': scope.companyId,
                'company_code': companyCode,
              }),
            )
            .timeout(const Duration(seconds: 12));
        statusCode = response.statusCode;
        final contentType =
            (response.headers['content-type'] ?? '').toLowerCase();
        if (contentType.contains('application/json')) {
          try {
            final decoded = jsonDecode(utf8.decode(response.bodyBytes));
            if (decoded is Map) {
              payload = Map<String, dynamic>.from(decoded);
            }
          } on FormatException {
            debugPrint(
              '[PAIR_CODE_CREATE][DECODE_FAIL] status=$statusCode ct=$contentType',
            );
          }
        } else {
          // Cloudflare Error 1101 or an intermediary HTML page: never try to
          // parse it as JSON. Log only the sanitized status/content-type; do
          // not echo body bytes because a leaked worker error page could
          // expose internal identifiers.
          debugPrint(
            '[PAIR_CODE_CREATE][NON_JSON_RESPONSE] status=$statusCode ct=${contentType.isEmpty ? "-" : contentType}',
          );
        }
        debugPrint(
          '[PAIR_CODE_CREATE][RES] status=$statusCode ok=${payload['ok'] == true}',
        );
      }
    } on TimeoutException {
      debugPrint('[PAIR_CODE_CREATE][TIMEOUT]');
    } catch (error) {
      // Redacted diagnostics equivalent to the driver-link flow: never print
      // the raw error message (could contain URL fragments); type is enough
      // to distinguish transport, DNS and TLS failures during triage.
      debugPrint('[PAIR_CODE_CREATE][HTTP_FAIL] type=${error.runtimeType}');
    }

    if (!context.mounted) return;
    Navigator.of(context, rootNavigator: true).pop();

    final ok = statusCode >= 200 && statusCode < 300 && payload['ok'] == true;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _t(
              nl: 'Activatiecode kon niet worden aangemaakt. Probeer opnieuw.',
              en: 'Could not generate activation code. Please try again.',
              fr: 'Impossible de générer le code d’activation. Réessayez.',
              es: 'No se pudo generar el código de activación. Inténtalo de nuevo.',
            ),
          ),
        ),
      );
      return;
    }

    final returnedCompanyCode = _normalizeActivationCompanyCode(
      (payload['company_code'] ?? companyCode).toString(),
    );
    final pairingCode = (payload['pairing_code'] ?? '').toString().trim();
    if (!_isValidActivationCompanyCode(returnedCompanyCode) ||
        !RegExp(r'^\d{6}$').hasMatch(pairingCode)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _t(
              nl: 'Activatiecode kon niet worden aangemaakt. Probeer opnieuw.',
              en: 'Could not generate activation code. Please try again.',
              fr: 'Impossible de générer le code d’activation. Réessayez.',
              es: 'No se pudo generar el código de activación. Inténtalo de nuevo.',
            ),
          ),
        ),
      );
      return;
    }

    final activationCode = '$returnedCompanyCode-$pairingCode';
    final expiresAt = (payload['expires_at'] ?? '').toString().trim();
    final expiresInSeconds = int.tryParse(
      (payload['expires_in_seconds'] ?? '').toString().trim(),
    );

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF111111),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: kFluxidiYellow.withOpacity(0.45)),
        ),
        title: Text(
          _t(
            nl: 'Nieuw toestel koppelen',
            en: 'Pair new device',
            fr: 'Associer un nouvel appareil',
            es: 'Vincular nuevo dispositivo',
          ),
          style: const TextStyle(color: Colors.white),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _t(
                nl: 'Open Fluxidi op het nieuwe toestel en voer deze activatiecode in.',
                en: 'Open Fluxidi on the new device and enter this activation code.',
                fr: 'Ouvrez Fluxidi sur le nouvel appareil et saisissez ce code d’activation.',
                es: 'Abre Fluxidi en el nuevo dispositivo e introduce este código de activación.',
              ),
              style: TextStyle(
                color: Colors.white.withOpacity(0.82),
                fontSize: 12.5,
              ),
            ),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A1A),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: kFluxidiYellow.withOpacity(0.36)),
              ),
              child: SelectableText(
                activationCode,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                  letterSpacing: 0.5,
                  fontFamily: 'monospace',
                ),
              ),
            ),
            if (expiresAt.isNotEmpty || expiresInSeconds != null) ...[
              const SizedBox(height: 8),
              Text(
                expiresAt.isNotEmpty
                    ? _t(
                        nl: 'Vervalt op: $expiresAt',
                        en: 'Expires at: $expiresAt',
                        fr: 'Expire le : $expiresAt',
                        es: 'Caduca el: $expiresAt',
                      )
                    : _t(
                        nl: 'Geldig voor ongeveer ${expiresInSeconds ?? 0} seconden.',
                        en: 'Valid for about ${expiresInSeconds ?? 0} seconds.',
                        fr: 'Valable pendant environ ${expiresInSeconds ?? 0} secondes.',
                        es: 'Válido durante aproximadamente ${expiresInSeconds ?? 0} segundos.',
                      ),
                style: TextStyle(
                  color: Colors.white.withOpacity(0.7),
                  fontSize: 11.8,
                ),
              ),
            ],
          ],
        ),
        actions: [
          OutlinedButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: activationCode));
              if (!dialogContext.mounted) return;
              ScaffoldMessenger.of(dialogContext).showSnackBar(
                SnackBar(
                  content: Text(
                    _t(
                      nl: 'Activatiecode gekopieerd.',
                      en: 'Activation code copied.',
                      fr: 'Code d’activation copié.',
                      es: 'Código de activación copiado.',
                    ),
                  ),
                ),
              );
            },
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: BorderSide(color: kFluxidiYellow.withOpacity(0.5)),
            ),
            icon: const Icon(Icons.copy_rounded, size: 16),
            label: Text(
              _t(nl: 'Kopiëren', en: 'Copy', fr: 'Copier', es: 'Copiar'),
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(
              _t(nl: 'Sluiten', en: 'Close', fr: 'Fermer', es: 'Cerrar'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _verifyCompanyFromBusinessHome(BuildContext context) async {
    const roleEntry = RoleEntryPage();
    final activationCode = await roleEntry._promptCompanyActivationCode(
      context,
    );
    if (!context.mounted || activationCode == null) return;
    if (activationCode == RoleEntryPage._companyPairingOnboardingIntent) return;
    final parsed = roleEntry._parseCompanyActivationCode(activationCode);
    if (parsed == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _t(
              nl: 'Ongeldige activatiecode. Gebruik bijvoorbeeld FLX-4821-123456.',
              en: 'Invalid activation code. Use for example FLX-4821-123456.',
              fr: 'Code d’activation invalide. Utilisez par exemple FLX-4821-123456.',
              es: 'Código de activación no válido. Usa por ejemplo FLX-4821-123456.',
            ),
          ),
        ),
      );
      return;
    }

    final verified = await roleEntry._verifyCompanyPairingCode(
      companyCode: parsed.companyCode,
      pairingCode: parsed.pairingCode,
    );
    if (!context.mounted) return;
    if (verified['ok'] != true) {
      final errorCode = roleEntry
          ._safePairingText(verified['error'])
          .toLowerCase();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(roleEntry._companyPairingErrorText(errorCode))),
      );
      return;
    }

    final payload = verified['payload'] is Map
        ? Map<String, dynamic>.from(verified['payload'] as Map)
        : <String, dynamic>{};
    await roleEntry._showCompanyPairingSuccessDialog(context);
    if (!context.mounted) return;
    final opened = await roleEntry._openVerifiedCompanySession(
      context,
      payload,
    );
    if (!context.mounted) return;
    if (!opened) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            roleEntry._companyPairingErrorText('verification_failed'),
          ),
        ),
      );
    }
  }

  Widget _panel({required Widget child, EdgeInsetsGeometry? padding}) {
    final palette = _businessThemePalette;
    final themeVariant = businessThemeNotifier.value;
    final isExecutiveGold = themeVariant == BusinessThemeVariant.executiveGold;
    // Executive Gold keeps its bespoke near-black gradient (theme intent).
    // Every other variant falls through to palette-aware surfaces so that
    // the Clean Professional light palette renders a light card instead of a
    // black block, and the other dark palettes (Corporate Blue, Emerald
    // Ivory, Fluxidi Neon Rush) use their own dark surface tones.
    final gradientColors = isExecutiveGold
        ? const <Color>[Color(0xFF101010), Color(0xFF07080C), Color(0xFF07080C)]
        : <Color>[palette.surface, palette.surfaceAlt, palette.background];
    final outerGlow = isExecutiveGold
        ? kFluxidiYellow.withOpacity(0.07)
        : palette.accent.withOpacity(0.10);
    final dropShadowColor = palette.shadow.withOpacity(
      palette.isDark ? 0.36 : 0.18,
    );
    return Container(
      padding: padding ?? const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: gradientColors,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isExecutiveGold
              ? kFluxidiYellow.withOpacity(0.17)
              : palette.accent.withOpacity(palette.isDark ? 0.22 : 0.34),
        ),
        boxShadow: [
          BoxShadow(color: outerGlow, blurRadius: 12, spreadRadius: 0.2),
          BoxShadow(
            color: dropShadowColor,
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }

  bool _isBusinessHomeAssetRef(String value) =>
      value.trim().toLowerCase().startsWith('assets/');

  bool _isBusinessHomeHttpImageRef(String value) {
    final lower = value.trim().toLowerCase();
    return lower.startsWith('https://') || lower.startsWith('http://');
  }

  String _normalizeBusinessHomeLogoRefForCompare(String raw) =>
      raw.trim().replaceAll('\\', '/').toLowerCase();

  /// True for empty paths and any known packaged/default Fluxidi logo reference.
  bool _isDefaultFluxidiLogoRefForBusinessHome(String raw) {
    final norm = _normalizeBusinessHomeLogoRefForCompare(raw);
    if (norm.isEmpty) return true;
    final config = _normalizeBusinessHomeLogoRefForCompare(kFluxidiLogoAsset);
    if (norm == config) return true;
    if (norm == 'assets/fluxidi/fluxidi_logo.png') return true;
    if (norm == 'fluxidi_logo.png') return true;
    if (norm.endsWith('/fluxidi_logo.png')) return true;
    if (norm.contains('assets/fluxidi/fluxidi_logo.png')) return true;
    return false;
  }

  String? _normalizeBusinessHomeLogoRef(String? raw) {
    final text = (raw ?? '').trim();
    if (text.isEmpty || _isDefaultFluxidiLogoRefForBusinessHome(text)) {
      return null;
    }
    if (_isBusinessHomeAssetRef(text)) return text;
    final resolved = resolvePublicHttpsMediaUrl(text);
    if (resolved.isNotEmpty) return resolved;
    final lower = text.toLowerCase();
    if (lower.startsWith('https://') || lower.startsWith('http://')) {
      return text;
    }
    if (lower.startsWith('/public/media/') ||
        lower.startsWith('public-media/')) {
      return null;
    }
    if (kIsWeb) return null;
    try {
      if (File(text).existsSync()) return text;
    } catch (_) {}
    return null;
  }

  ({String ref, String source}) _resolveBusinessHomeLogoRef({
    required BusinessSettingsState businessSettings,
    required BackendBusinessProfile? backendProfile,
  }) {
    final rawLocal = businessSettings.logoAssetPath;
    final rawPublic = backendProfile?.publicLogoUrl ?? '';
    final hasCompanyLogo =
        rawLocal.trim().isNotEmpty &&
        !_isDefaultFluxidiLogoRefForBusinessHome(rawLocal);
    final hasPublicLogo =
        rawPublic.trim().isNotEmpty &&
        !_isDefaultFluxidiLogoRefForBusinessHome(rawPublic);

    final localLogo = hasCompanyLogo
        ? _normalizeBusinessHomeLogoRef(rawLocal)
        : null;
    if (localLogo != null) {
      if (kDebugMode) {
        debugPrint(
          '[COMPANY_LOGO] surface=business_home source=business_local '
          'hasCompanyLogo=true hasPublicLogo=$hasPublicLogo',
        );
      }
      return (ref: localLogo, source: 'business_local');
    }

    final publicLogo = hasPublicLogo
        ? _normalizeBusinessHomeLogoRef(rawPublic)
        : null;
    if (publicLogo != null) {
      if (kDebugMode) {
        debugPrint(
          '[COMPANY_LOGO] surface=business_home source=public_backend '
          'hasCompanyLogo=false hasPublicLogo=true',
        );
      }
      return (ref: publicLogo, source: 'public_backend');
    }

    if (kDebugMode) {
      debugPrint(
        '[COMPANY_LOGO] surface=business_home source=fallback '
        'hasCompanyLogo=false hasPublicLogo=false',
      );
    }
    return (ref: kFluxidiLogoAsset, source: 'fallback');
  }

  Widget _businessHomeFluxidiLogoFallback({required double width}) {
    return Image.asset(
      kFluxidiLogoAsset,
      width: width,
      fit: BoxFit.contain,
      alignment: Alignment.topLeft,
      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
    );
  }

  Widget _businessHomeLogo({required double width}) {
    return ValueListenableBuilder<BusinessSettingsState>(
      valueListenable: businessSettingsNotifier,
      builder: (context, businessSettings, _) {
        return ValueListenableBuilder<BackendBusinessProfile?>(
          valueListenable: localBackendBusinessProfileNotifier,
          builder: (context, backendProfile, __) {
            final resolution = _resolveBusinessHomeLogoRef(
              businessSettings: businessSettings,
              backendProfile: backendProfile,
            );
            final ref = resolution.ref;
            final fallback = _businessHomeFluxidiLogoFallback(width: width);

            if (resolution.source == 'fallback' ||
                ref.trim() == kFluxidiLogoAsset) {
              return fallback;
            }
            if (_isBusinessHomeAssetRef(ref)) {
              return Image.asset(
                ref,
                width: width,
                fit: BoxFit.contain,
                alignment: Alignment.topLeft,
                errorBuilder: (_, ___, ____) => fallback,
              );
            }
            if (_isBusinessHomeHttpImageRef(ref)) {
              return Image.network(
                ref,
                width: width,
                fit: BoxFit.contain,
                alignment: Alignment.topLeft,
                errorBuilder: (_, ___, ____) => fallback,
              );
            }
            if (kIsWeb) return fallback;
            return Image.file(
              File(ref),
              width: width,
              fit: BoxFit.contain,
              alignment: Alignment.topLeft,
              errorBuilder: (_, ___, ____) => fallback,
            );
          },
        );
      },
    );
  }

  Widget _topBar(BuildContext context, CompanyProfile? profile) {
    final palette = _businessThemePalette;
    final themeVariant = businessThemeNotifier.value;
    final isExecutiveGold = themeVariant == BusinessThemeVariant.executiveGold;
    final isCorporateBlue = themeVariant == BusinessThemeVariant.corporateBlue;
    final isCleanProfessional =
        themeVariant == BusinessThemeVariant.cleanProfessional;
    final currentLanguage = appLanguageNotifier.value;
    final publicCompanyCode = _resolvePublicBookingCompanyCodeForDashboard();
    final hasPublicCompanyCode = publicCompanyCode != null;
    String firstNonEmpty(List<String?> values) {
      for (final value in values) {
        final text = (value ?? '').trim();
        if (text.isNotEmpty) return text;
      }
      return '';
    }

    final profileJson = profile?.toJson();
    final profilePublicDisplayName = profileJson is Map<String, dynamic>
        ? firstNonEmpty(<String?>[
            profileJson['publicDisplayName']?.toString(),
            profileJson['public_display_name']?.toString(),
          ])
        : '';
    final profileLegalName = profileJson is Map<String, dynamic>
        ? firstNonEmpty(<String?>[
            profileJson['legalName']?.toString(),
            profileJson['legal_name']?.toString(),
          ])
        : '';
    final companyIdentityName = firstNonEmpty(<String?>[
      profile?.companyName,
      profilePublicDisplayName,
      profileLegalName,
      publicCompanyCode,
      profile?.companyId,
      _t(nl: 'Bedrijf', en: 'Business', fr: 'Entreprise', es: 'Empresa'),
    ]);
    final companyName = companyIdentityName;
    final screenW = MediaQuery.of(context).size.width;
    const customerReferenceLogoWidth = 178.0;
    final businessLogoWidth = math.max(
      120.0,
      math.min(customerReferenceLogoWidth, screenW - 250),
    );
    PopupMenuItem<String> languageMenuItem({
      required String value,
      required AppLanguage language,
      required String code,
    }) {
      final selected = currentLanguage == language;
      return PopupMenuItem<String>(
        value: value,
        child: Row(
          children: [
            Expanded(
              child: Text(
                code,
                style: TextStyle(
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                  color: selected
                      ? palette.accent
                      : (isCleanProfessional ? palette.textPrimary : null),
                ),
              ),
            ),
            if (selected)
              Icon(Icons.check_rounded, size: 16, color: palette.accent),
          ],
        ),
      );
    }

    return Row(
      children: [
        _businessHomeLogo(width: businessLogoWidth),
        const Spacer(),
        PopupMenuButton<String>(
          color: isCleanProfessional
              ? palette.surface
              : (isCorporateBlue ? palette.surface : const Color(0xFF111111)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(
              color: isExecutiveGold
                  ? kFluxidiYellow.withOpacity(0.36)
                  : palette.accent.withOpacity(0.42),
            ),
          ),
          onSelected: (value) {
            if (value == 'details') {
              _openCompanyDetails(context);
              return;
            }
            if (value == 'privacy_account') {
              // GOOGLE-PLAY-PRIVACY-READINESS-P0: authority resolved from the
              // real active company session + AppRole (fail-closed) instead of
              // a hardcoded true.
              final companySession = activeCompanySessionNotifier.value;
              final isOwnerOrAdmin = resolveIsCompanyOwnerOrAdmin(
                hasCompanySession:
                    CompanySessionStore.instance.hasValidCompanyContext &&
                    companySession != null,
                companySessionToken: companySession?.companySessionToken,
                companyId: companySession?.companyId,
                sessionRole: companySession?.role,
                appRoleIsCompanyAdmin:
                    appRoleNotifier.value == AppRole.companyAdmin,
              );
              openFluxidiPrivacyAccountPage(
                context,
                audience: FluxidiPrivacyAudience.business,
                isCompanyOwnerOrAdmin: isOwnerOrAdmin,
              );
              return;
            }
            if (value == 'help_manual') {
              _openBusinessHelpManual(context);
              return;
            }
            if (value == 'verify_company') {
              unawaited(_verifyCompanyFromBusinessHome(context));
              return;
            }
            if (value == 'pair_new_device') {
              unawaited(_showNewDeviceActivationCodeDialog(context));
              return;
            }
            if (value == 'switch') {
              _switchCompany(context);
              return;
            }
            if (value == 'lang_nl') {
              setAppLanguage(AppLanguage.nl);
              return;
            }
            if (value == 'lang_en') {
              setAppLanguage(AppLanguage.en);
              return;
            }
            if (value == 'lang_fr') {
              setAppLanguage(AppLanguage.fr);
              return;
            }
            if (value == 'lang_es') {
              setAppLanguage(AppLanguage.es);
            }
          },
          itemBuilder: (_) => [
            if (profile != null)
              PopupMenuItem<String>(
                enabled: false,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (hasPublicCompanyCode)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3.5,
                        ),
                        decoration: BoxDecoration(
                          color: isCleanProfessional
                              ? palette.surfaceAlt
                              : const Color(0xFF12331F),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: isCleanProfessional
                                ? palette.accent.withOpacity(0.34)
                                : const Color(0xFF4ADE80).withOpacity(0.45),
                          ),
                        ),
                        child: Text(
                          _t(
                            nl: 'Geverifieerd',
                            en: 'Verified',
                            fr: 'Vérifiée',
                            es: 'Verificada',
                          ),
                          style: TextStyle(
                            color: isCleanProfessional
                                ? palette.textSecondary
                                : const Color(0xFFB8F5C8),
                            fontWeight: FontWeight.w700,
                            fontSize: 10.5,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      )
                    else
                      _statusPill(profile, compact: true),
                    const SizedBox(height: 8),
                    Text(
                      companyIdentityName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: isCleanProfessional
                            ? palette.textPrimary
                            : Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    if (publicCompanyCode != null) ...[
                      Text(
                        '${_t(nl: 'Fluxidi-code', en: 'Fluxidi code', fr: 'Code Fluxidi', es: 'Código Fluxidi')}: $publicCompanyCode',
                        style: TextStyle(
                          color: isCleanProfessional
                              ? palette.textSecondary
                              : Colors.white70,
                          fontSize: 11.5,
                          fontFamily: 'monospace',
                        ),
                      ),
                      const SizedBox(height: 4),
                    ],
                    Text(
                      '${_t(nl: 'Interne referentie', en: 'Internal reference', fr: 'Référence interne', es: 'Referencia interna')}: ${profile.companyId}',
                      style: TextStyle(
                        color: isCleanProfessional
                            ? palette.textMuted
                            : Colors.white54,
                        fontSize: 10.5,
                        fontFamily: 'monospace',
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      profile.email.trim(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: isCleanProfessional
                            ? palette.textSecondary
                            : Colors.white70,
                        fontSize: 11.5,
                      ),
                    ),
                    if (!hasPublicCompanyCode &&
                        profile.showsPendingVerificationNotice) ...[
                      const SizedBox(height: 6),
                      Text(
                        profile.verificationPendingNotice(
                          appConfig.currentLanguage,
                        ),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: isCleanProfessional
                              ? palette.textMuted
                              : Colors.white54,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            PopupMenuItem<String>(
              value: 'details',
              child: Text(
                _t(
                  nl: 'Bedrijfsgegevens',
                  en: 'Company details',
                  fr: 'Données de l’entreprise',
                  es: 'Datos de empresa',
                ),
                style: isCleanProfessional
                    ? TextStyle(color: palette.textPrimary)
                    : null,
              ),
            ),
            PopupMenuItem<String>(
              value: 'privacy_account',
              child: Text(
                _t(
                  nl: 'Privacy & account',
                  en: 'Privacy & account',
                  fr: 'Confidentialité & compte',
                  es: 'Privacidad y cuenta',
                ),
                style: isCleanProfessional
                    ? TextStyle(color: palette.textPrimary)
                    : null,
              ),
            ),
            PopupMenuItem<String>(
              value: 'help_manual',
              child: Text(
                _t(
                  nl: 'Help & handleiding',
                  en: 'Help & guide',
                  fr: 'Aide & guide',
                  es: 'Ayuda y guía',
                ),
                style: isCleanProfessional
                    ? TextStyle(color: palette.textPrimary)
                    : null,
              ),
            ),
            if (!hasPublicCompanyCode)
              PopupMenuItem<String>(
                value: 'verify_company',
                child: Text(
                  _t(
                    nl: 'Bedrijf verifiëren',
                    en: 'Verify company',
                    fr: 'Vérifier l’entreprise',
                    es: 'Verificar empresa',
                  ),
                  style: isCleanProfessional
                      ? TextStyle(color: palette.textPrimary)
                      : null,
                ),
              ),
            if (hasPublicCompanyCode)
              PopupMenuItem<String>(
                value: 'pair_new_device',
                child: Text(
                  _t(
                    nl: 'Nieuw toestel koppelen',
                    en: 'Pair new device',
                    fr: 'Associer un nouvel appareil',
                    es: 'Vincular nuevo dispositivo',
                  ),
                  style: isCleanProfessional
                      ? TextStyle(color: palette.textPrimary)
                      : null,
                ),
              ),
            PopupMenuItem<String>(
              value: 'switch',
              child: Text(
                _t(
                  nl: 'Ander bedrijf',
                  en: 'Other company',
                  fr: 'Autre entreprise',
                  es: 'Otra empresa',
                ),
                style: TextStyle(color: Colors.redAccent.shade100),
              ),
            ),
            const PopupMenuDivider(),
            PopupMenuItem<String>(
              enabled: false,
              child: Text(
                _t(nl: 'Taal', en: 'Language', fr: 'Langue', es: 'Idioma'),
                style: TextStyle(
                  color: palette.textSecondary,
                  fontWeight: FontWeight.w700,
                  fontSize: 12.5,
                ),
              ),
            ),
            languageMenuItem(
              value: 'lang_nl',
              language: AppLanguage.nl,
              code: 'NL',
            ),
            languageMenuItem(
              value: 'lang_en',
              language: AppLanguage.en,
              code: 'EN',
            ),
            languageMenuItem(
              value: 'lang_fr',
              language: AppLanguage.fr,
              code: 'FR',
            ),
            languageMenuItem(
              value: 'lang_es',
              language: AppLanguage.es,
              code: 'ES',
            ),
          ],
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: isCleanProfessional
                  ? palette.surface
                  : const Color(0xFF101010),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isExecutiveGold
                    ? kFluxidiYellow.withOpacity(0.32)
                    : palette.accent.withOpacity(0.38),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isCleanProfessional || isCorporateBlue
                        ? palette.surfaceAlt
                        : const Color(0xFF15120A),
                    border: Border.all(
                      color: isExecutiveGold
                          ? kFluxidiYellow.withOpacity(0.5)
                          : palette.accent.withOpacity(0.56),
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    _companyInitials(profile),
                    style: TextStyle(
                      color: isExecutiveGold
                          ? const Color(0xFFE5B641)
                          : palette.accent,
                      fontWeight: FontWeight.w800,
                      fontSize: 11,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 110),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        companyName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: isCleanProfessional
                              ? palette.textPrimary
                              : Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 12.5,
                        ),
                      ),
                      Text(
                        _t(
                          nl: 'Bedrijf',
                          en: 'Business',
                          fr: 'Entreprise',
                          es: 'Empresa',
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: isCleanProfessional
                              ? palette.textSecondary
                              : Colors.white.withOpacity(0.68),
                          fontSize: 10.5,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  Icons.keyboard_arrow_down_rounded,
                  color: isExecutiveGold
                      ? kFluxidiYellow.withOpacity(0.95)
                      : palette.accent.withOpacity(0.96),
                  size: 18,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _metricCard({
    required IconData icon,
    required String title,
    required String value,
    required String subtitle,
    required Color accentColor,
    bool compact = false,
  }) {
    final palette = _businessThemePalette;
    final cardBorder = palette.border.withOpacity(palette.isDark ? 0.54 : 0.92);
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 9 : 12,
        vertical: compact ? 7 : 11,
      ),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cardBorder),
        boxShadow: [
          BoxShadow(
            color: palette.shadow.withOpacity(palette.isDark ? 0.34 : 0.12),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: compact ? 28 : 34,
            height: compact ? 28 : 34,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: accentColor.withOpacity(0.16),
              border: Border.all(color: accentColor.withOpacity(0.45)),
            ),
            child: Icon(icon, color: accentColor, size: compact ? 16 : 19),
          ),
          SizedBox(width: compact ? 7 : 10),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontSize: compact ? 11.4 : 13.2,
                    fontWeight: FontWeight.w700,
                    height: 1.1,
                  ),
                ),
                SizedBox(height: compact ? 0 : 2),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: palette.textSecondary.withOpacity(
                      palette.isDark ? 0.84 : 1,
                    ),
                    fontSize: compact ? 9.8 : 11.2,
                    fontWeight: FontWeight.w500,
                    height: 1.1,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(width: compact ? 5 : 8),
          Text(
            value,
            style: TextStyle(
              color: palette.textPrimary,
              fontWeight: FontWeight.w900,
              fontSize: compact ? 18 : 24,
              height: 1.0,
            ),
          ),
        ],
      ),
    );
  }

  Widget _quickActionCard({
    required IconData icon,
    required String title,
    required String subtitle,
    VoidCallback? onTap,
    bool isFuture = false,
    String? futureBadge,
    String? statusBadge,
    String? backgroundAsset,
    bool useImageBackground = false,
    bool compact = false,
  }) {
    final palette = _businessThemePalette;
    final themeVariant = businessThemeNotifier.value;
    final isExecutiveGold = themeVariant == BusinessThemeVariant.executiveGold;
    final isCleanProfessional =
        themeVariant == BusinessThemeVariant.cleanProfessional;
    final active = onTap != null && !isFuture;
    final hasImageBackground =
        useImageBackground && (backgroundAsset ?? '').trim().isNotEmpty;
    final cardBorderColor = palette.border.withOpacity(
      active ? (palette.isDark ? 0.72 : 1.0) : (palette.isDark ? 0.46 : 0.88),
    );
    final warningSemantic = isExecutiveGold
        ? const Color(0xFFE5B641)
        : palette.accent;
    final warningBadgeBg = isExecutiveGold
        ? warningSemantic.withOpacity(palette.isDark ? 0.22 : 0.24)
        : palette.surfaceAlt.withOpacity(0.96);
    final iconSurfaceBase = active ? palette.accent : palette.textMuted;
    final iconTint = active
        ? palette.textOnAccent
        : palette.textMuted.withOpacity(0.78);
    final titleColor = isCleanProfessional && hasImageBackground
        ? Colors.white.withOpacity(active ? 0.98 : 0.92)
        : palette.textPrimary.withOpacity(active ? 1.0 : 0.88);
    final subtitleColor = isCleanProfessional && hasImageBackground
        ? Colors.white.withOpacity(active ? 0.86 : 0.78)
        : palette.textMuted.withOpacity(active ? 0.94 : 0.76);
    EdgeInsets cardPaddingFor(bool isTightHeight, bool isVeryTight) =>
        EdgeInsets.fromLTRB(
          compact ? 8 : 12,
          (compact ? 8 : 12) - (isVeryTight ? 3 : (isTightHeight ? 2 : 0)),
          compact ? 8 : 12,
          (compact ? 6 : 10) - (isVeryTight ? 3 : (isTightHeight ? 2 : 0)),
        );
    Widget cardContent(BoxConstraints constraints) {
      final maxHeight = constraints.maxHeight;
      final isBounded = maxHeight.isFinite && maxHeight > 0;
      final isVeryTight = isBounded && maxHeight < 108;
      final isTightHeight = isBounded && maxHeight < 126;
      final useCompactLayout = compact || isTightHeight;
      final iconCircleSize = useCompactLayout
          ? (isVeryTight ? 32.0 : 34.0)
          : (isTightHeight ? 40.0 : 44.0);
      final iconGlyphSize = useCompactLayout
          ? (isVeryTight ? 18.0 : 20.0)
          : (isTightHeight ? 26.0 : 29.0);
      final titleGap = useCompactLayout
          ? (isVeryTight ? 3.0 : 4.0)
          : (isTightHeight ? 6.0 : 8.0);
      final titleFontSize = (useCompactLayout ? 12.2 : 14.0) -
          (isVeryTight ? 1.0 : (isTightHeight ? 0.6 : 0.0));
      final subtitleFontSize = (useCompactLayout ? 9.8 : 11.2) -
          (isVeryTight ? 0.8 : (isTightHeight ? 0.5 : 0.0));
      final subtitleGap = isVeryTight ? 2.0 : (isTightHeight ? 3.0 : 4.0);
      final chevronSize = useCompactLayout
          ? (isVeryTight ? 12.0 : 13.0)
          : (isTightHeight ? 16.0 : 17.0);
      final lockSize = useCompactLayout
          ? (isVeryTight ? 11.0 : 12.0)
          : (isTightHeight ? 14.5 : 15.5);
      final textBlock = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: titleColor,
              fontWeight: FontWeight.w800,
              fontSize: titleFontSize,
              height: 1.1,
              shadows: hasImageBackground
                  ? [
                      Shadow(
                        color: Colors.black.withOpacity(
                          isCleanProfessional ? 0.76 : 0.62,
                        ),
                        blurRadius: 6,
                        offset: const Offset(0, 1.2),
                      ),
                    ]
                  : null,
            ),
          ),
          SizedBox(height: subtitleGap),
          Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: subtitleColor,
              fontSize: subtitleFontSize,
              height: 1.1,
              shadows: hasImageBackground
                  ? [
                      Shadow(
                        color: Colors.black.withOpacity(
                          isCleanProfessional ? 0.68 : 0.54,
                        ),
                        blurRadius: 5,
                        offset: const Offset(0, 1.1),
                      ),
                    ]
                  : null,
            ),
          ),
        ],
      );
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.max,
        children: [
          Row(
            children: [
              Container(
                width: iconCircleSize,
                height: iconCircleSize,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      iconSurfaceBase.withOpacity(active ? 0.28 : 0.18),
                      palette.surfaceAlt,
                    ],
                  ),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: (active ? palette.accent : palette.border)
                        .withOpacity(active ? 0.50 : 0.26),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: (active ? palette.accent : palette.shadow)
                          .withOpacity(active ? 0.10 : 0.16),
                      blurRadius: 10,
                      spreadRadius: 0.2,
                    ),
                  ],
                ),
                child: Icon(icon, color: iconTint, size: iconGlyphSize),
              ),
              const Spacer(),
              if ((futureBadge ?? '').trim().isNotEmpty)
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: useCompactLayout ? 7 : 8,
                    vertical: useCompactLayout ? 2 : 3,
                  ),
                  decoration: BoxDecoration(
                    color: palette.surfaceAlt,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: palette.accent.withOpacity(0.42)),
                  ),
                  child: Text(
                    futureBadge!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: palette.textSecondary,
                      fontSize: useCompactLayout ? 9.2 : 10.3,
                      fontWeight: FontWeight.w700,
                      height: 1.0,
                    ),
                  ),
                ),
              if ((futureBadge ?? '').trim().isEmpty &&
                  (statusBadge ?? '').trim().isNotEmpty)
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: useCompactLayout ? 7 : 8,
                    vertical: useCompactLayout ? 2 : 3,
                  ),
                  decoration: BoxDecoration(
                    color: warningBadgeBg,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: warningSemantic.withOpacity(0.72),
                    ),
                  ),
                  child: Text(
                    statusBadge!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: isExecutiveGold
                          ? palette.textOnWarning
                          : (isCleanProfessional
                                ? palette.textPrimary
                                : palette.textSecondary),
                      fontSize: useCompactLayout ? 9.2 : 10.3,
                      fontWeight: FontWeight.w700,
                      height: 1.0,
                    ),
                  ),
                ),
            ],
          ),
          SizedBox(height: titleGap),
          if (isBounded)
            Expanded(child: textBlock)
          else
            textBlock,
          SizedBox(height: isVeryTight ? 0 : 2),
          Align(
            alignment: Alignment.bottomRight,
            child: active
                ? Icon(
                    Icons.chevron_right_rounded,
                    size: chevronSize,
                    color: palette.accent.withOpacity(0.9),
                  )
                : Icon(
                    Icons.lock_clock_outlined,
                    size: lockSize,
                    color: palette.textMuted.withOpacity(0.72),
                  ),
          ),
        ],
      );
    }

    if (!hasImageBackground) {
      return InkWell(
        borderRadius: BorderRadius.circular(15),
        onTap: active ? onTap : null,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isTightHeight =
                constraints.maxHeight.isFinite && constraints.maxHeight < 126;
            final isVeryTight =
                constraints.maxHeight.isFinite && constraints.maxHeight < 108;
            return Container(
              height:
                  constraints.maxHeight.isFinite ? constraints.maxHeight : null,
              padding: cardPaddingFor(isTightHeight, isVeryTight),
              decoration: BoxDecoration(
                color: palette.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: cardBorderColor),
                boxShadow: [
                  BoxShadow(
                    color: palette.shadow.withOpacity(
                      palette.isDark ? 0.34 : 0.14,
                    ),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: cardContent(constraints),
            );
          },
        ),
      );
    }
    return InkWell(
      borderRadius: BorderRadius.circular(15),
      onTap: active ? onTap : null,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isTightHeight =
              constraints.maxHeight.isFinite && constraints.maxHeight < 126;
          final isVeryTight =
              constraints.maxHeight.isFinite && constraints.maxHeight < 108;
          return Container(
            height:
                constraints.maxHeight.isFinite ? constraints.maxHeight : null,
            decoration: BoxDecoration(
              color: palette.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: cardBorderColor),
              boxShadow: [
                BoxShadow(
                  color: palette.shadow.withOpacity(
                    palette.isDark ? 0.34 : 0.14,
                  ),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.asset(
                    backgroundAsset!,
                    fit: BoxFit.cover,
                    alignment: Alignment.centerRight,
                    errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                  ),
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                          colors: [
                            Colors.black.withOpacity(
                              isCleanProfessional ? 0.74 : 0.62,
                            ),
                            Colors.black.withOpacity(
                              isCleanProfessional ? 0.52 : 0.40,
                            ),
                            Colors.black.withOpacity(
                              isCleanProfessional ? 0.30 : 0.24,
                            ),
                            Colors.black.withOpacity(
                              isCleanProfessional ? 0.14 : 0.10,
                            ),
                          ],
                          stops: const [0.0, 0.42, 0.72, 1.0],
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: cardPaddingFor(isTightHeight, isVeryTight),
                    child: cardContent(constraints),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  bool _isBusinessAdminSessionRecoveryRequired() {
    if (!CompanySessionStore.instance.hasValidCompanyContext) return false;
    final profileCompanyId =
        companyProfileNotifier.value?.companyId.trim() ?? '';
    final session = activeCompanySessionNotifier.value;
    final sessionCompanyId = (session?.companyId ?? '').trim();
    if (profileCompanyId.isNotEmpty &&
        sessionCompanyId.isNotEmpty &&
        profileCompanyId != sessionCompanyId) {
      return true;
    }
    final token = (session?.companySessionToken ?? '').trim();
    if (token.isEmpty) return true;
    final expiresAt = session?.sessionExpiresAtUtc;
    if (expiresAt != null && !DateTime.now().toUtc().isBefore(expiresAt)) {
      return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final themeVariant = businessThemeNotifier.value;
    final isExecutiveGold = themeVariant == BusinessThemeVariant.executiveGold;
    final isCleanProfessional =
        themeVariant == BusinessThemeVariant.cleanProfessional;
    final isCorporateBlue = themeVariant == BusinessThemeVariant.corporateBlue;
    return ValueListenableBuilder<AppLanguage>(
      valueListenable: appLanguageNotifier,
      builder: (context, _, __) => Scaffold(
        backgroundColor: isCorporateBlue
            ? const Color(0xFF0A1324)
            : !isExecutiveGold
            ? _businessThemePalette.background
            : const Color(0xFF07080C),
        body: SafeArea(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: isCorporateBlue
                    ? const [
                        Color(0xFF13213A),
                        Color(0xFF0A1324),
                        Color(0xFF0A1324),
                      ]
                    : !isExecutiveGold
                    ? <Color>[
                        _businessThemePalette.background,
                        _businessThemePalette.background,
                        _businessThemePalette.surfaceAlt,
                      ]
                    : const [
                        Color(0xFF101010),
                        Color(0xFF07080C),
                        Color(0xFF07080C),
                      ],
              ),
              border: Border.all(
                color: !isExecutiveGold
                    ? _businessThemePalette.accent.withOpacity(0.34)
                    : Colors.transparent,
                width: !isExecutiveGold ? 1.2 : 0,
              ),
              boxShadow: !isExecutiveGold
                  ? [
                      BoxShadow(
                        color: _businessThemePalette.accent.withOpacity(0.16),
                        blurRadius: 16,
                        spreadRadius: 0.2,
                      ),
                    ]
                  : null,
            ),
            child: ValueListenableBuilder<CompanyProfile?>(
              valueListenable: companyProfileNotifier,
              builder: (context, profile, _) {
                double clampDouble(double v, double min, double max) =>
                    v < min ? min : (v > max ? max : v);
                final size = MediaQuery.sizeOf(context);
                final W = size.width;
                final H = size.height;
                final screenClass = FluxidiBreakpoints.classifyWidth(W);
                final mediaPaddingBottom = MediaQuery.paddingOf(context).bottom;
                final isTabletPortrait =
                    (screenClass == FluxidiScreenClass.tablet ||
                        screenClass == FluxidiScreenClass.desktop) &&
                    W < H &&
                    H >= 900;
                final isTabletLandscape =
                    (screenClass == FluxidiScreenClass.tablet ||
                        screenClass == FluxidiScreenClass.desktop) &&
                    W > H &&
                    W >= 900;
                // Phone landscape: any landscape orientation that did not
                // qualify as tablet/desktop landscape. Used ONLY by the
                // Quick actions section to render a 5x2 cockpit grid; the
                // top KPI/summary section continues to use the existing
                // sizing and remains byte-identical for phones.
                final isPhoneLandscape =
                    !isTabletLandscape && !isTabletPortrait && W > H;
                // Shared compact-card flag for quick-action cards that
                // applies to both tablet landscape (existing) and phone
                // landscape (new). The 8 KPI/metric cards above keep
                // their own `compact: isTabletLandscape` flag unchanged.
                final compactQuickAction =
                    isTabletLandscape || isPhoneLandscape;
                final useTabletVisualMode =
                    isTabletPortrait || isTabletLandscape;
                final usesTabletHeader = useTabletVisualMode;
                // Phone-portrait Visual layout is opt-in via the business
                // theme settings page. It must NOT activate on tablet (any
                // orientation) or on phone landscape, so existing layouts
                // remain byte-for-byte unchanged for those cases.
                final useVisualMobileMode =
                    !isTabletPortrait &&
                    !isTabletLandscape &&
                    W < H &&
                    businessHomeMobileLayoutNotifier.value ==
                        BusinessHomeMobileLayout.visual;
                // Flexible target for visual cards across small + large
                // Android phones. Clamped to a comfortable 100–116 px range
                // regardless of width so labels stay legible without
                // overflowing on narrow phones.
                final visualMobileCardHeight = clampDouble(
                  W * 0.28,
                  100.0,
                  116.0,
                );
                final visualMobileCardSpacing = 10.0;
                final businessHeaderHeight = isTabletLandscape
                    // Slightly taller hero banner so tablet landscape no
                    // longer leaves a wide empty band at the bottom of the
                    // page. Phone portrait/landscape and tablet portrait
                    // branches are unchanged.
                    ? clampDouble(H * 0.22, 140.0, 200.0)
                    : isTabletPortrait
                    ? clampDouble(H * 0.23, 300.0, 360.0)
                    : null;
                final businessHeaderAsset = _businessImageAsset(
                  executiveGoldAsset:
                      'assets/fluxidi/zakelijke_tablet_header_foto.png',
                  corporateBlueAsset:
                      'assets/Corporate BLEU Compagny/company_header_fleet_corporate_blue.png',
                  cleanProfessionalAsset:
                      'assets/Clean & Professional Compagny/company_header_fleet_clean_professional.png',
                  emeraldIvoryAsset:
                      'assets/Emerald_Ivory_Company/company_header_emerald_ivory.png',
                  fluxidiNeonRushAsset:
                      'assets/🥇 Fluxidi Neon Rush/company_header_fleet_neon_rush.png',
                );
                final businessQuickActionCardHeight = isTabletLandscape
                    // Proportionally taller quick action cards in tablet
                    // landscape so the 5-column row takes a larger share of
                    // the available vertical space and pushes Back to start
                    // page closer to the safe-area bottom. Phone landscape
                    // (5x2 cockpit) keeps its existing 96–116 px clamp
                    // below.
                    ? clampDouble(H * 0.27, 175.0, 230.0)
                    : isTabletPortrait
                    ? clampDouble(H * 0.105, 132.0, 148.0)
                    : isPhoneLandscape
                    // Phone landscape: 2 rows × 5 columns. Card height is
                    // clamped to 96–116 px so two rows + spacing + the back
                    // button fit comfortably without overflow on narrow
                    // landscape phones, while leaving room for the icon
                    // bubble, ellipsised title and subtitle, and chevron.
                    ? clampDouble(H * 0.27, 96.0, 116.0)
                    : useVisualMobileMode
                    ? visualMobileCardHeight
                    : 132.0;
                final businessQuickActionSpacing = isTabletLandscape
                    ? 8.0
                    : isTabletPortrait
                    ? 14.0
                    : isPhoneLandscape
                    ? 8.0
                    : useVisualMobileMode
                    ? visualMobileCardSpacing
                    : 12.0;
                final businessBackButtonGap = isTabletLandscape
                    // Slightly larger gap above Back to start page so the
                    // button sits cleanly under the taller quick-action row
                    // instead of being glued to it.
                    ? clampDouble(H * 0.04, 14.0, 36.0)
                    : isTabletPortrait
                    ? 10.0
                    : 14.0;
                final businessListBottomPadding = isTabletLandscape
                    ? math.max(mediaPaddingBottom + 12.0, 22.0)
                    : isTabletPortrait
                    ? 12.0
                    : 20.0;
                // Section / sub-section vertical gaps. Tablet landscape now
                // scales these with H so the page breathes proportionally
                // on 600 / 768 / 800 / 900+ tablet heights. Phone branches
                // (incl. phone landscape 5x2 cockpit) keep their fixed
                // values so that layout stays byte-identical.
                final businessSectionGap = isTabletLandscape
                    ? clampDouble(H * 0.018, 8.0, 16.0)
                    : 10.0;
                final businessQuickActionsTitleGap = isTabletLandscape
                    ? clampDouble(H * 0.022, 10.0, 20.0)
                    : isPhoneLandscape
                    ? 8.0
                    : 14.0;
                final businessQuickActionsGridTopGap = isTabletLandscape
                    ? clampDouble(H * 0.018, 8.0, 16.0)
                    : isPhoneLandscape
                    ? 8.0
                    : 10.0;
                final headerTitleFontSize = isTabletLandscape ? 15.0 : 19.0;
                final headerSubtitleFontSize = isTabletLandscape ? 11.0 : 12.5;
                final headerTextBottomGap = isTabletLandscape ? 2.0 : 3.0;
                final headerContentPadding = isTabletLandscape
                    ? const EdgeInsets.fromLTRB(10, 8, 10, 10)
                    : const EdgeInsets.fromLTRB(12, 12, 12, 14);

                return ValueListenableBuilder<BusinessThemeVariant>(
                  valueListenable: businessThemeNotifier,
                  builder: (context, _, __) {
                    return ListView(
                      padding: EdgeInsets.fromLTRB(
                        16,
                        12,
                        16,
                        businessListBottomPadding,
                      ),
                      children: [
                        if (usesTabletHeader)
                          Container(
                            height: businessHeaderHeight,
                            clipBehavior: Clip.antiAlias,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(
                                color: isExecutiveGold
                                    ? kFluxidiYellow.withOpacity(0.22)
                                    : _businessThemePalette.accent.withOpacity(
                                        0.30,
                                      ),
                              ),
                            ),
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                Image.asset(
                                  businessHeaderAsset,
                                  fit: BoxFit.cover,
                                  alignment: isTabletLandscape
                                      ? const Alignment(0.25, 0.35)
                                      : Alignment.center,
                                  errorBuilder: (_, __, ___) =>
                                      const DecoratedBox(
                                        decoration: BoxDecoration(
                                          gradient: LinearGradient(
                                            begin: Alignment.topCenter,
                                            end: Alignment.bottomCenter,
                                            colors: [
                                              Color(0xFF101010),
                                              Color(0xFF07080C),
                                            ],
                                          ),
                                        ),
                                      ),
                                ),
                                Positioned.fill(
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        begin: Alignment.topCenter,
                                        end: Alignment.bottomCenter,
                                        colors: [
                                          Colors.black.withOpacity(0.12),
                                          Colors.black.withOpacity(0.22),
                                          Colors.black.withOpacity(0.58),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                                Positioned.fill(
                                  child: Padding(
                                    padding: headerContentPadding,
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        ValueListenableBuilder<
                                          ActiveCompanySession?
                                        >(
                                          valueListenable:
                                              activeCompanySessionNotifier,
                                          builder: (context, _, __) =>
                                              _topBar(context, profile),
                                        ),
                                        const Spacer(),
                                        Text(
                                          _timeAwareGreeting(),
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w800,
                                            fontSize: headerTitleFontSize,
                                          ),
                                        ),
                                        SizedBox(height: headerTextBottomGap),
                                        Text(
                                          _t(
                                            nl: 'Bedrijfsoverzicht',
                                            en: 'Business overview',
                                            fr: 'Aperçu de l’entreprise',
                                            es: 'Resumen de empresa',
                                          ),
                                          style: TextStyle(
                                            color: Colors.white.withOpacity(
                                              0.78,
                                            ),
                                            fontSize: headerSubtitleFontSize,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          )
                        else ...[
                          ValueListenableBuilder<ActiveCompanySession?>(
                            valueListenable: activeCompanySessionNotifier,
                            builder: (context, _, __) =>
                                _topBar(context, profile),
                          ),
                          const SizedBox(height: 12),
                          _panel(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _timeAwareGreeting(),
                                  style: TextStyle(
                                    color: _businessThemePalette.textPrimary,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 19,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  _t(
                                    nl: 'Bedrijfsoverzicht',
                                    en: 'Business overview',
                                    fr: 'Aperçu de l’entreprise',
                                    es: 'Resumen de empresa',
                                  ),
                                  style: TextStyle(
                                    color: _businessThemePalette.textMuted,
                                    fontSize: 12.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        SizedBox(height: businessSectionGap),
                        // BUSINESS-DASHBOARD-KPI-LOADING-UX-1: subtle indicator
                        // while initial load / background refresh runs. Cards
                        // keep last successful values (or "—") — never flash 0.
                        if (_kpiView.showRefreshIndicator) ...[
                          ClipRRect(
                            borderRadius: BorderRadius.circular(999),
                            child: LinearProgressIndicator(
                              minHeight: 2,
                              backgroundColor: _businessThemePalette.border
                                  .withOpacity(0.25),
                              color: _businessThemePalette.accent
                                  .withOpacity(0.85),
                            ),
                          ),
                          const SizedBox(height: 8),
                        ],
                        if (_kpiView.phase ==
                                BusinessDashboardKpiPhase.unavailable &&
                            _kpiView.showRetry) ...[
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    _t(
                                      nl: 'KPIs tijdelijk niet beschikbaar.',
                                      en: 'KPIs temporarily unavailable.',
                                      fr: 'KPI temporairement indisponibles.',
                                      es: 'KPI temporalmente no disponibles.',
                                    ),
                                    style: TextStyle(
                                      color:
                                          _businessThemePalette.textSecondary,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                TextButton(
                                  onPressed: () => unawaited(
                                    _refreshDashboardKpis(
                                      reason:
                                          BusinessKpiCycleReason.manualRetry,
                                    ),
                                  ),
                                  child: Text(
                                    _t(
                                      nl: 'Opnieuw',
                                      en: 'Retry',
                                      fr: 'Réessayer',
                                      es: 'Reintentar',
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final stacked =
                                !isTabletLandscape &&
                                constraints.maxWidth < 430;
                            if (stacked) {
                              return Column(
                                children: [
                                  _metricCard(
                                    icon: Icons.calendar_month_outlined,
                                    title: _t(
                                      nl: 'Open boekingen',
                                      en: 'Open bookings',
                                      fr: 'Réservations ouvertes',
                                      es: 'Reservas abiertas',
                                    ),
                                    subtitle: _t(
                                      nl: 'Gepland',
                                      en: 'Planned',
                                      fr: 'Planifiées',
                                      es: 'Planificadas',
                                    ),
                                    value: _metricCountText(_openBookingsCount),
                                    accentColor: const Color(0xFF60A5FA),
                                    compact: isTabletLandscape,
                                  ),
                                  SizedBox(height: isTabletLandscape ? 6 : 8),
                                  _metricCard(
                                    icon: Icons.directions_car_outlined,
                                    title: _t(
                                      nl: 'Voltooide ritten',
                                      en: 'Completed rides',
                                      fr: 'Courses terminées',
                                      es: 'Viajes completados',
                                    ),
                                    subtitle: _t(
                                      nl: 'Afgerond',
                                      en: 'Completed',
                                      fr: 'Terminées',
                                      es: 'Completados',
                                    ),
                                    value: _metricCountText(
                                      _completedRidesCount,
                                    ),
                                    accentColor: const Color(0xFF4ADE80),
                                    compact: isTabletLandscape,
                                  ),
                                  SizedBox(height: isTabletLandscape ? 6 : 8),
                                  _metricCard(
                                    icon: Icons.payments_outlined,
                                    title: _t(
                                      nl: 'Nog te betalen',
                                      en: 'To be paid',
                                      fr: 'À payer',
                                      es: 'Por pagar',
                                    ),
                                    subtitle: _t(
                                      nl: 'Afgerond maar onbetaald',
                                      en: 'Completed but unpaid',
                                      fr: 'Terminées mais impayées',
                                      es: 'Completados sin pagar',
                                    ),
                                    value: _metricCountText(
                                      _unpaidCompletedRidesCount,
                                    ),
                                    accentColor: const Color(0xFFF97373),
                                    compact: isTabletLandscape,
                                  ),
                                  SizedBox(height: isTabletLandscape ? 6 : 8),
                                  _metricCard(
                                    icon: Icons.euro_rounded,
                                    title: _t(
                                      nl: 'Maandomzet',
                                      en: 'Monthly income',
                                      fr: 'Revenus mensuels',
                                      es: 'Ingresos mensuales',
                                    ),
                                    subtitle: _t(
                                      nl: 'Betaald',
                                      en: 'Paid',
                                      fr: 'Payées',
                                      es: 'Pagado',
                                    ),
                                    value: _metricIncomeText(),
                                    accentColor: const Color(0xFFE5B641),
                                    compact: isTabletLandscape,
                                  ),
                                ],
                              );
                            }
                            final columns = isTabletLandscape
                                ? 4
                                : constraints.maxWidth < 760
                                ? 2
                                : 4;
                            final spacing = isTabletLandscape ? 6.0 : 8.0;
                            final cardWidth =
                                (constraints.maxWidth -
                                    ((columns - 1) * spacing)) /
                                columns;
                            return Wrap(
                              spacing: spacing,
                              runSpacing: spacing,
                              children: [
                                SizedBox(
                                  width: cardWidth,
                                  child: _metricCard(
                                    icon: Icons.calendar_month_outlined,
                                    title: _t(
                                      nl: 'Open boekingen',
                                      en: 'Open bookings',
                                      fr: 'Réservations ouvertes',
                                      es: 'Reservas abiertas',
                                    ),
                                    subtitle: _t(
                                      nl: 'Gepland',
                                      en: 'Planned',
                                      fr: 'Planifiées',
                                      es: 'Planificadas',
                                    ),
                                    value: _metricCountText(_openBookingsCount),
                                    accentColor: const Color(0xFF60A5FA),
                                    compact: isTabletLandscape,
                                  ),
                                ),
                                SizedBox(
                                  width: cardWidth,
                                  child: _metricCard(
                                    icon: Icons.directions_car_outlined,
                                    title: _t(
                                      nl: 'Voltooide ritten',
                                      en: 'Completed rides',
                                      fr: 'Courses terminées',
                                      es: 'Viajes completados',
                                    ),
                                    subtitle: _t(
                                      nl: 'Afgerond',
                                      en: 'Completed',
                                      fr: 'Terminées',
                                      es: 'Completados',
                                    ),
                                    value: _metricCountText(
                                      _completedRidesCount,
                                    ),
                                    accentColor: const Color(0xFF4ADE80),
                                    compact: isTabletLandscape,
                                  ),
                                ),
                                SizedBox(
                                  width: cardWidth,
                                  child: _metricCard(
                                    icon: Icons.payments_outlined,
                                    title: _t(
                                      nl: 'Nog te betalen',
                                      en: 'To be paid',
                                      fr: 'À payer',
                                      es: 'Por pagar',
                                    ),
                                    subtitle: _t(
                                      nl: 'Afgerond maar onbetaald',
                                      en: 'Completed but unpaid',
                                      fr: 'Terminées mais impayées',
                                      es: 'Completados sin pagar',
                                    ),
                                    value: _metricCountText(
                                      _unpaidCompletedRidesCount,
                                    ),
                                    accentColor: const Color(0xFFF97373),
                                    compact: isTabletLandscape,
                                  ),
                                ),
                                SizedBox(
                                  width: cardWidth,
                                  child: _metricCard(
                                    icon: Icons.euro_rounded,
                                    title: _t(
                                      nl: 'Maandomzet',
                                      en: 'Monthly income',
                                      fr: 'Revenus mensuels',
                                      es: 'Ingresos mensuales',
                                    ),
                                    subtitle: _t(
                                      nl: 'Betaald',
                                      en: 'Paid',
                                      fr: 'Payées',
                                      es: 'Pagado',
                                    ),
                                    value: _metricIncomeText(),
                                    accentColor: isExecutiveGold
                                        ? const Color(0xFFE5B641)
                                        : _businessThemePalette.accent,
                                    compact: isTabletLandscape,
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                        SizedBox(height: businessQuickActionsTitleGap),
                        Text(
                          _t(
                            nl: 'Snelle acties',
                            en: 'Quick actions',
                            fr: 'Actions rapides',
                            es: 'Acciones rápidas',
                          ),
                          style: TextStyle(
                            color: isExecutiveGold
                                ? kFluxidiYellow.withOpacity(0.95)
                                : _businessThemePalette.accent.withOpacity(
                                    0.95,
                                  ),
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (_isBusinessAdminSessionRecoveryRequired()) ...[
                          const SizedBox(height: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: isExecutiveGold
                                  ? const Color(0xFF2A1B0F)
                                  : _businessThemePalette.surfaceAlt,
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(
                                color: isExecutiveGold
                                    ? const Color(0xFFE5B641).withOpacity(0.5)
                                    : _businessThemePalette.accent.withOpacity(
                                        0.62,
                                      ),
                              ),
                            ),
                            child: Text(
                              _t(
                                nl: 'Bedrijfssessie herstellen vereist',
                                en: 'Company admin session recovery required',
                                fr: "Récupération de session entreprise requise",
                                es: 'Se requiere recuperar la sesión de empresa',
                              ),
                              style: TextStyle(
                                color: isExecutiveGold
                                    ? const Color(0xFFE5B641).withOpacity(0.98)
                                    : (isCleanProfessional
                                          ? _businessThemePalette.textPrimary
                                          : _businessThemePalette
                                                .textSecondary),
                                fontSize: 10.7,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                        SizedBox(height: businessQuickActionsGridTopGap),
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final quickActionColumns = isTabletLandscape
                                ? 5
                                : isPhoneLandscape
                                // Phone landscape: 2 rows × 5 cards.
                                // Row 1: Settings, Plan, Vehicles, Chiron,
                                // Drivers. Row 2: Driver view, Demand,
                                // Share booking link, Bookings, AI
                                // Dispatch. Wrap order matches because the
                                // tablet-landscape-only Bookings card is
                                // skipped while the !isTabletLandscape
                                // Bookings card is included.
                                ? 5
                                : useVisualMobileMode
                                ? 1
                                : 2;
                            final totalHorizontalSpacing =
                                quickActionColumns > 1
                                ? businessQuickActionSpacing *
                                      (quickActionColumns - 1)
                                : 0.0;
                            final cardWidth =
                                (constraints.maxWidth -
                                    totalHorizontalSpacing) /
                                quickActionColumns;
                            return Wrap(
                              spacing: businessQuickActionSpacing,
                              runSpacing: businessQuickActionSpacing,
                              children: [
                                SizedBox(
                                  width: cardWidth,
                                  height: businessQuickActionCardHeight,
                                  child: _quickActionCard(
                                    icon: Icons.business_center_outlined,
                                    title: _t(
                                      nl: 'Instellingen',
                                      en: 'Settings',
                                      fr: 'Réglages',
                                      es: 'Ajustes',
                                    ),
                                    subtitle: _t(
                                      nl: 'Profiel & branding',
                                      en: 'Profile & branding',
                                      fr: 'Profil & branding',
                                      es: 'Perfil y marca',
                                    ),
                                    onTap: () {
                                      Navigator.of(context).push(
                                        MaterialPageRoute(
                                          builder: (_) =>
                                              const BusinessSettingsPage(),
                                        ),
                                      );
                                    },
                                    backgroundAsset: _businessImageAsset(
                                      executiveGoldAsset:
                                          'assets/fluxidi/settings_background_company.png',
                                      corporateBlueAsset:
                                          'assets/Corporate BLEU Compagny/company_settings_corporate_blue.png',
                                      cleanProfessionalAsset:
                                          'assets/Clean & Professional Compagny/company_settings_clean_professional.png',
                                      emeraldIvoryAsset:
                                          'assets/Emerald_Ivory_Company/company_settings_alt_emerald_ivory.png',
                                      fluxidiNeonRushAsset:
                                          'assets/🥇 Fluxidi Neon Rush/company_settings_neon_rush.png',
                                    ),
                                    useImageBackground:
                                        useTabletVisualMode ||
                                        useVisualMobileMode,
                                    compact: compactQuickAction,
                                  ),
                                ),
                                if (isTabletLandscape)
                                  SizedBox(
                                    width: cardWidth,
                                    height: businessQuickActionCardHeight,
                                    child: _quickActionCard(
                                      icon: Icons.calendar_month_outlined,
                                      title: _t(
                                        nl: 'Boekingen',
                                        en: 'Bookings',
                                        fr: 'Réservations',
                                        es: 'Reservas',
                                      ),
                                      subtitle: _t(
                                        nl: 'Alle boekingen',
                                        en: 'All bookings',
                                        fr: 'Toutes les réservations',
                                        es: 'Todas las reservas',
                                      ),
                                      onTap: () =>
                                          _openBusinessBookingsOverview(
                                            context,
                                          ),
                                      backgroundAsset: _businessImageAsset(
                                        executiveGoldAsset:
                                            'assets/fluxidi/bookings_background_company.png',
                                        corporateBlueAsset:
                                            'assets/Corporate BLEU Compagny/company_bookings_corporate_blue.png',
                                        cleanProfessionalAsset:
                                            'assets/Clean & Professional Compagny/company_bookings_clean_professional.png',
                                        emeraldIvoryAsset:
                                            'assets/Emerald_Ivory_Company/company_bookings_emerald_ivory.png',
                                        fluxidiNeonRushAsset:
                                            'assets/🥇 Fluxidi Neon Rush/company_bookings_neon_rush.png',
                                      ),
                                      useImageBackground:
                                          useTabletVisualMode ||
                                          useVisualMobileMode,
                                      compact: compactQuickAction,
                                    ),
                                  ),
                                SizedBox(
                                  width: cardWidth,
                                  height: businessQuickActionCardHeight,
                                  child: _quickActionCard(
                                    icon: Icons.credit_card_outlined,
                                    title: _t(
                                      nl: 'Abonnement',
                                      en: 'Plan',
                                      fr: 'Abonnement',
                                      es: 'Plan',
                                    ),
                                    subtitle: _t(
                                      nl: 'Facturatie',
                                      en: 'Billing',
                                      fr: 'Facturation',
                                      es: 'Facturación',
                                    ),
                                    onTap: () {
                                      Navigator.of(context).push(
                                        MaterialPageRoute(
                                          builder: (_) =>
                                              const CompanySubscriptionBillingPage(),
                                        ),
                                      );
                                    },
                                    backgroundAsset: _businessImageAsset(
                                      executiveGoldAsset:
                                          'assets/fluxidi/plan_background_company.png',
                                      corporateBlueAsset:
                                          'assets/Corporate BLEU Compagny/company_subscriptions_corporate_blue.png',
                                      cleanProfessionalAsset:
                                          'assets/Clean & Professional Compagny/company_subscriptions_clean_professional.png',
                                      emeraldIvoryAsset:
                                          'assets/Emerald_Ivory_Company/company_plan_emerald_ivory.png',
                                      fluxidiNeonRushAsset:
                                          'assets/🥇 Fluxidi Neon Rush/company_subscriptions_neon_rush.png',
                                    ),
                                    useImageBackground:
                                        useTabletVisualMode ||
                                        useVisualMobileMode,
                                    compact: compactQuickAction,
                                  ),
                                ),
                                SizedBox(
                                  width: cardWidth,
                                  height: businessQuickActionCardHeight,
                                  child: _quickActionCard(
                                    icon: Icons.directions_car_filled_outlined,
                                    title: _t(
                                      nl: 'Voertuigen',
                                      en: 'Vehicles',
                                      fr: 'Véhicules',
                                      es: 'Vehículos',
                                    ),
                                    subtitle: _t(
                                      nl: 'Wagenpark',
                                      en: 'Fleet',
                                      fr: 'Flotte',
                                      es: 'Flota',
                                    ),
                                    onTap: () {
                                      Navigator.of(context).push(
                                        MaterialPageRoute(
                                          builder: (_) =>
                                              const VehicleManagementPage(),
                                        ),
                                      );
                                    },
                                    backgroundAsset: _businessImageAsset(
                                      executiveGoldAsset:
                                          'assets/fluxidi/vehicles_background_company.png',
                                      corporateBlueAsset:
                                          'assets/Corporate BLEU Compagny/company_vehicles_corporate_blue.png',
                                      cleanProfessionalAsset:
                                          'assets/Clean & Professional Compagny/company_vehicles_clean_professional.png',
                                      emeraldIvoryAsset:
                                          'assets/Emerald_Ivory_Company/company_vehicle_emerald_ivory.png',
                                      fluxidiNeonRushAsset:
                                          'assets/🥇 Fluxidi Neon Rush/company_vehicles_neon_rush.png',
                                    ),
                                    useImageBackground:
                                        useTabletVisualMode ||
                                        useVisualMobileMode,
                                    compact: compactQuickAction,
                                  ),
                                ),
                                SizedBox(
                                  width: cardWidth,
                                  height: businessQuickActionCardHeight,
                                  child: _quickActionCard(
                                    icon: Icons.fact_check_outlined,
                                    title: _t(
                                      nl: 'Chiron',
                                      en: 'Chiron',
                                      fr: 'Chiron',
                                      es: 'Chiron',
                                    ),
                                    subtitle: 'Compliance',
                                    onTap: () {
                                      Navigator.of(context).push(
                                        MaterialPageRoute<void>(
                                          builder: (_) =>
                                              const ChironComplianceDashboardPage(),
                                        ),
                                      );
                                    },
                                    backgroundAsset: _businessImageAsset(
                                      executiveGoldAsset:
                                          'assets/fluxidi/chiron_background_company.png',
                                      corporateBlueAsset:
                                          'assets/Corporate BLEU Compagny/company_branding_corporate_blue.png',
                                      cleanProfessionalAsset:
                                          'assets/Clean & Professional Compagny/company_chiron_clean_professional.png',
                                      emeraldIvoryAsset:
                                          'assets/Emerald_Ivory_Company/company_chiron_emerald_ivory.png',
                                      fluxidiNeonRushAsset:
                                          'assets/🥇 Fluxidi Neon Rush/company_chiron_neon_rush.png',
                                    ),
                                    useImageBackground:
                                        useTabletVisualMode ||
                                        useVisualMobileMode,
                                    compact: compactQuickAction,
                                  ),
                                ),
                                SizedBox(
                                  width: cardWidth,
                                  height: businessQuickActionCardHeight,
                                  child: _quickActionCard(
                                    icon: Icons.local_taxi_outlined,
                                    title: _t(
                                      nl: 'Chauffeurs',
                                      en: 'Drivers',
                                      fr: 'Chauffeurs',
                                      es: 'Conductores',
                                    ),
                                    subtitle: _t(
                                      nl: 'Team',
                                      en: 'Team',
                                      fr: 'Équipe',
                                      es: 'Equipo',
                                    ),
                                    statusBadge:
                                        _isBusinessAdminSessionRecoveryRequired()
                                        ? _t(
                                            nl: 'Herstel vereist',
                                            en: 'Recovery required',
                                            fr: 'Récupération requise',
                                            es: 'Recuperación requerida',
                                          )
                                        : null,
                                    onTap: () async {
                                      final backendContext =
                                          await _resolveBackendUsableCompanyContextForAdmin(
                                            reason:
                                                'business_home_manage_drivers',
                                            logDegraded: true,
                                          );
                                      if (!context.mounted) return;
                                      if (!backendContext.usable) {
                                        debugPrint(
                                          '[COMPANY_SESSION][ADMIN_ENTRY_BLOCKED] flow=business_home_manage_drivers code=${backendContext.reasonCode} source=${backendContext.tokenSource}',
                                        );
                                        await _showDegradedCompanySessionRecoveryDialog(
                                          context,
                                          reason:
                                              'business_home_manage_drivers',
                                        );
                                        return;
                                      }
                                      Navigator.of(context).push(
                                        MaterialPageRoute<void>(
                                          builder: (_) =>
                                              const CompanyDriverManagementPage(),
                                        ),
                                      );
                                    },
                                    backgroundAsset: _businessImageAsset(
                                      executiveGoldAsset:
                                          'assets/fluxidi/drivers_background_company.png',
                                      corporateBlueAsset:
                                          'assets/Corporate BLEU Compagny/company_drivers_corporate_blue.png',
                                      cleanProfessionalAsset:
                                          'assets/Clean & Professional Compagny/company_drivers_clean_professional.png',
                                      emeraldIvoryAsset:
                                          'assets/Emerald_Ivory_Company/company_drivers_emerald_ivory.png',
                                      fluxidiNeonRushAsset:
                                          'assets/🥇 Fluxidi Neon Rush/company_drivers_neon_rush.png',
                                    ),
                                    useImageBackground:
                                        useTabletVisualMode ||
                                        useVisualMobileMode,
                                    compact: compactQuickAction,
                                  ),
                                ),
                                SizedBox(
                                  width: cardWidth,
                                  height: businessQuickActionCardHeight,
                                  child: _quickActionCard(
                                    icon: Icons.speed_rounded,
                                    title: _t(
                                      nl: 'Chauffeur weergave',
                                      en: 'Driver view',
                                      fr: 'Vue chauffeur',
                                      es: 'Vista de conductor',
                                    ),
                                    subtitle: _t(
                                      nl: 'Ga naar de bestaande chauffeurcockpit zonder uit te loggen.',
                                      en: 'Open the existing driver cockpit without signing out.',
                                      fr: 'Ouvrir le cockpit chauffeur existant sans se déconnecter.',
                                      es: 'Abre la cabina de conductor existente sin cerrar sesión.',
                                    ),
                                    onTap: () =>
                                        _openDriverCockpitView(context),
                                    backgroundAsset: _businessImageAsset(
                                      executiveGoldAsset:
                                          'assets/fluxidi/driver_view_background_company.png',
                                      corporateBlueAsset:
                                          'assets/Corporate BLEU Compagny/company_driver_view_corporate_blue.png',
                                      cleanProfessionalAsset:
                                          'assets/Clean & Professional Compagny/company_driver_view_clean_professional.png',
                                      emeraldIvoryAsset:
                                          'assets/Emerald_Ivory_Company/company_driver_view_emerald_ivory.png',
                                      fluxidiNeonRushAsset:
                                          'assets/🥇 Fluxidi Neon Rush/company_driver_view_neon_rush.png',
                                    ),
                                    useImageBackground:
                                        useTabletVisualMode ||
                                        useVisualMobileMode,
                                    compact: compactQuickAction,
                                  ),
                                ),
                                SizedBox(
                                  width: cardWidth,
                                  height: businessQuickActionCardHeight,
                                  child: _quickActionCard(
                                    icon: Icons.radar_rounded,
                                    title: _t(
                                      nl: 'Vraagradar',
                                      en: 'Demand radar',
                                      fr: 'Radar demande',
                                      es: 'Radar demanda',
                                    ),
                                    subtitle: _t(
                                      nl: 'Klantvraag',
                                      en: 'Customer demand',
                                      fr: 'Demande clients',
                                      es: 'Demanda clientes',
                                    ),
                                    onTap: () {
                                      Navigator.of(context).push(
                                        MaterialPageRoute<void>(
                                          builder: (_) =>
                                              const BusinessRegionalDemandPage(),
                                        ),
                                      );
                                    },
                                    backgroundAsset: _businessImageAsset(
                                      executiveGoldAsset:
                                          'assets/fluxidi/demand_radar_background_company.png',
                                      corporateBlueAsset:
                                          'assets/Corporate BLEU Compagny/company_network_corporate_blue.png',
                                      cleanProfessionalAsset:
                                          'assets/Clean & Professional Compagny/company_demand_radar_clean_professional.png',
                                      emeraldIvoryAsset:
                                          'assets/Emerald_Ivory_Company/company_demand_radar_emerald_ivory.png',
                                      fluxidiNeonRushAsset:
                                          'assets/🥇 Fluxidi Neon Rush/company_demand_radar_neon_rush.png',
                                    ),
                                    useImageBackground:
                                        useTabletVisualMode ||
                                        useVisualMobileMode,
                                    compact: compactQuickAction,
                                  ),
                                ),
                                SizedBox(
                                  width: cardWidth,
                                  height: businessQuickActionCardHeight,
                                  child: _quickActionCard(
                                    icon: Icons.qr_code_2_outlined,
                                    title: _t(
                                      nl: 'Deel boekingslink',
                                      en: 'Share booking link',
                                      fr: 'Partager le lien de réservation',
                                      es: 'Compartir enlace de reserva',
                                    ),
                                    subtitle: _t(
                                      nl: 'Link + QR',
                                      en: 'Link + QR',
                                      fr: 'Lien + QR',
                                      es: 'Enlace + QR',
                                    ),
                                    onTap: () =>
                                        _showPublicBookingShareQuickAccess(
                                          context,
                                        ),
                                    backgroundAsset: _businessImageAsset(
                                      executiveGoldAsset:
                                          'assets/fluxidi/share_booking_link_background_company.png',
                                      corporateBlueAsset:
                                          'assets/Corporate BLEU Compagny/company_mobile_app_corporate_blue.png',
                                      cleanProfessionalAsset:
                                          'assets/Clean & Professional Compagny/company_share_booking_link_clean_professional.png',
                                      emeraldIvoryAsset:
                                          'assets/Emerald_Ivory_Company/company_share_booking_emerald_ivory.png',
                                      fluxidiNeonRushAsset:
                                          'assets/🥇 Fluxidi Neon Rush/company_share_booking_link_neon_rush.png',
                                    ),
                                    useImageBackground:
                                        useTabletVisualMode ||
                                        useVisualMobileMode,
                                    compact: compactQuickAction,
                                  ),
                                ),
                                if (!isTabletLandscape)
                                  SizedBox(
                                    width: cardWidth,
                                    height: businessQuickActionCardHeight,
                                    child: _quickActionCard(
                                      icon: Icons.calendar_month_outlined,
                                      title: _t(
                                        nl: 'Boekingen',
                                        en: 'Bookings',
                                        fr: 'Réservations',
                                        es: 'Reservas',
                                      ),
                                      subtitle: _t(
                                        nl: 'Planning & opvolging',
                                        en: 'Planning & follow-up',
                                        fr: 'Planification & suivi',
                                        es: 'Planificación y seguimiento',
                                      ),
                                      onTap: () =>
                                          _openBusinessBookingsOverview(
                                            context,
                                          ),
                                      backgroundAsset: _businessImageAsset(
                                        executiveGoldAsset:
                                            'assets/fluxidi/bookings_background_company.png',
                                        corporateBlueAsset:
                                            'assets/Corporate BLEU Compagny/company_bookings_corporate_blue.png',
                                        cleanProfessionalAsset:
                                            'assets/Clean & Professional Compagny/company_bookings_clean_professional.png',
                                        emeraldIvoryAsset:
                                            'assets/Emerald_Ivory_Company/company_bookings_emerald_ivory.png',
                                        fluxidiNeonRushAsset:
                                            'assets/🥇 Fluxidi Neon Rush/company_bookings_neon_rush.png',
                                      ),
                                      useImageBackground:
                                          useTabletVisualMode ||
                                          useVisualMobileMode,
                                      compact: compactQuickAction,
                                    ),
                                  ),
                                SizedBox(
                                  width: cardWidth,
                                  height: businessQuickActionCardHeight,
                                  child: _quickActionCard(
                                    icon: Icons.auto_awesome_outlined,
                                    title: _t(
                                      nl: 'AI Dispatch',
                                      en: 'AI Dispatch',
                                      fr: 'Dispatch IA',
                                      es: 'Despacho IA',
                                    ),
                                    subtitle: _t(
                                      nl: 'Binnenkort',
                                      en: 'Coming soon',
                                      fr: 'Bientôt',
                                      es: 'Próximamente',
                                    ),
                                    isFuture: true,
                                    futureBadge: _t(
                                      nl: 'Binnenkort',
                                      en: 'Soon',
                                      fr: 'Bientôt',
                                      es: 'Pronto',
                                    ),
                                    backgroundAsset: _businessImageAsset(
                                      executiveGoldAsset:
                                          'assets/fluxidi/ai_dispatch_background_company.png',
                                      corporateBlueAsset:
                                          'assets/Corporate BLEU Compagny/company_ai_dispatch_corporate_blue.png',
                                      cleanProfessionalAsset:
                                          'assets/Clean & Professional Compagny/company_ai_dispatch_clean_professional.png',
                                      emeraldIvoryAsset:
                                          'assets/Emerald_Ivory_Company/company_ai_dispatch_emerald_ivory.png',
                                      fluxidiNeonRushAsset:
                                          'assets/🥇 Fluxidi Neon Rush/company_ai_dispatch_neon_rush.png',
                                    ),
                                    useImageBackground:
                                        useTabletVisualMode ||
                                        useVisualMobileMode,
                                    compact: compactQuickAction,
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                        SizedBox(height: businessBackButtonGap),
                        businessThemeNotifier.value !=
                                BusinessThemeVariant.executiveGold
                            ? _businessBackToStartButton()
                            : const FluxidiBackToStartButton(),
                      ],
                    );
                  },
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _businessBackToStartButton() {
    final palette = _businessThemePalette;
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: () {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const RoleEntryPage()),
            (route) => false,
          );
        },
        icon: const Icon(Icons.home_outlined),
        label: Text(
          _t(
            nl: 'Terug naar startpagina',
            en: 'Back to start page',
            fr: 'Retour à l’accueil',
            es: 'Volver a la pantalla inicial',
          ),
          style: TextStyle(color: palette.accent, fontWeight: FontWeight.w700),
        ),
        style: OutlinedButton.styleFrom(
          backgroundColor: palette.background,
          side: BorderSide(color: palette.accent.withOpacity(0.72), width: 1.1),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 14),
        ),
      ),
    );
  }
}
