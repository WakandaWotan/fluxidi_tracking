part of '../main.dart';

class _CompanyDriverManagementPageState
    extends State<CompanyDriverManagementPage>
    with WidgetsBindingObserver {
  bool _refreshInFlight = false;
  bool _adminDocsRefreshInFlight = false;
  bool _hasSuccessfulRefresh = false;
  bool _lastRefreshOk = false;
  bool _recoveryHintShown = false;
  DateTime? _lastRefreshAtUtc;
  final Set<String> _docRefreshFailedDriverIds = <String>{};
  final Map<String, ({bool active, DateTime atUtc})>
  _recentConfirmedDriverActiveById =
      <String, ({bool active, DateTime atUtc})>{};

  Future<void> _ensureCompanySessionTokenForAdminView({
    required String reason,
  }) async {
    final hasToken = await _hasUsableCompanyBootstrapToken(
      reason: reason,
      logDegraded: true,
    );
    if (!mounted || hasToken || _recoveryHintShown) return;
    _recoveryHintShown = true;
    await _showDegradedCompanySessionRecoveryDialog(context, reason: reason);
  }

  ({String tenantId, String companyId})? _adminScopeForDriver(
    DriverProfile driver,
  ) {
    final scoped = driver.companyId?.trim() ?? '';
    if (scoped.isNotEmpty) {
      return (tenantId: scoped, companyId: scoped);
    }
    final fromProfile = companyProfileNotifier.value?.companyId.trim() ?? '';
    if (fromProfile.isNotEmpty) {
      return (tenantId: fromProfile, companyId: fromProfile);
    }
    final fromSession =
        activeCompanySessionNotifier.value?.companyId.trim() ?? '';
    if (fromSession.isNotEmpty) {
      return (tenantId: fromSession, companyId: fromSession);
    }
    return null;
  }

  List<DriverProfile> _adminVisibleDrivers() {
    return driversNotifier.value
        .where(
          (d) =>
              !isSeededOrPlaceholderDriver(d) &&
              fleetRecordBelongsToActiveCompanyOrLegacy(d.companyId),
        )
        .toList(growable: false);
  }

  bool _isExpiryWithinDaysForDiag(String raw, {required int days}) {
    final text = raw.trim();
    if (text.isEmpty) return false;
    final dt = DateTime.tryParse(text);
    if (dt == null) return false;
    final now = DateTime.now().toUtc();
    final target = dt.toUtc();
    if (target.isBefore(now)) return false;
    return target.difference(now).inDays <= days;
  }

  Future<void> _refreshAdminDocumentsForVisibleDrivers({
    required String reason,
    bool force = false,
    String? onlyDriverId,
  }) async {
    if (_adminDocsRefreshInFlight) return;
    var refreshFailureStateChanged = false;
    final allVisible = _adminVisibleDrivers();
    final targetDriverId = (onlyDriverId ?? '').trim();
    final targets = targetDriverId.isEmpty
        ? allVisible
        : allVisible
              .where((d) => d.id.trim() == targetDriverId)
              .toList(growable: false);
    if (targets.isEmpty) return;
    final token =
        (activeCompanySessionNotifier.value?.companySessionToken ?? '').trim();
    if (token.isEmpty) {
      for (final driver in targets) {
        final safeDriverRef = _shortDriverIdForDiag(driver.id);
        final scope = _adminScopeForDriver(driver);
        if (_docRefreshFailedDriverIds.add(driver.id.trim())) {
          refreshFailureStateChanged = true;
        }
        debugPrint('[DRIVER_DOCS_SYNC][AUDIT_START] driver=$safeDriverRef');
        if (scope == null) {
          debugPrint('[DRIVER_DOCS_SYNC][SKIP] reason=missing_strict_scope');
        } else {
          debugPrint(
            '[DRIVER_DOCS_SYNC][SCOPE] driver=$safeDriverRef tenant=${_maskScopeForLog(scope.tenantId)} company=${_maskScopeForLog(scope.companyId)}',
          );
        }
        debugPrint('[DRIVER_DOCS_SYNC][BACKEND] driver=$safeDriverRef count=0');
        debugPrint(
          '[DRIVER_DOCS_SYNC][MISMATCH] driver=$safeDriverRef reason=no_company_session_token',
        );
        debugPrint(
          '[DRIVER_DOCS][REFRESH_FAILED] driver=${_shortDriverIdForDiag(driver.id)} error=no_company_session_token',
        );
      }
      if (mounted && refreshFailureStateChanged) {
        setState(() {});
      }
      return;
    }
    _adminDocsRefreshInFlight = true;
    for (final driver in targets) {
      if (_docRefreshFailedDriverIds.add(driver.id.trim())) {
        refreshFailureStateChanged = true;
      }
    }
    debugPrint(
      '[DRIVER_DOCS_ADMIN][REFRESH_START] drivers=${targets.length} reason=$reason force=$force',
    );
    try {
      for (final driver in targets) {
        final safeDriverRef = _shortDriverIdForDiag(driver.id);
        debugPrint('[DRIVER_DOCS_SYNC][AUDIT_START] driver=$safeDriverRef');
        debugPrint('[DRIVER_DOCS][REFRESH_START] driver=$safeDriverRef');
        final scope = _adminScopeForDriver(driver);
        if (scope == null) {
          debugPrint('[DRIVER_DOCS_SYNC][SKIP] reason=missing_strict_scope');
          continue;
        }
        debugPrint(
          '[DRIVER_DOCS_SYNC][SCOPE] driver=$safeDriverRef tenant=${_maskScopeForLog(scope.tenantId)} company=${_maskScopeForLog(scope.companyId)}',
        );
        final localBefore = DriverDocumentsStore.instance
            .documentsVisibleForCompanyAdminDriver(
              driver.id,
              tenantId: scope.tenantId,
              companyId: scope.companyId,
            )
            .length;
        debugPrint(
          '[DRIVER_DOCS_SYNC][LOCAL] driver=$safeDriverRef count=$localBefore',
        );
        await DriverDocumentsStore.instance
            .backfillLocalDriverDocumentsToBackendForDriver(
              bookingBaseUrl: kBookingBaseUrl,
              companySessionToken: token,
              tenantId: scope.tenantId,
              companyId: scope.companyId,
              driverId: driver.id,
            );
        final refreshResult = await DriverDocumentsStore.instance
            .refreshDriverDocumentsFromBackendDetailed(
              bookingBaseUrl: kBookingBaseUrl,
              companySessionToken: token,
              tenantId: scope.tenantId,
              companyId: scope.companyId,
              driverId: driver.id,
            );
        debugPrint(
          '[DRIVER_DOCS_BACKFILL][AUDIT] driver=$safeDriverRef local=$localBefore backend=${refreshResult.backendCount}',
        );
        final ok = refreshResult.ok;
        final visibleCount = DriverDocumentsStore.instance
            .documentsVisibleForCompanyAdminDriver(
              driver.id,
              tenantId: scope.tenantId,
              companyId: scope.companyId,
            )
            .length;
        debugPrint(
          '[DRIVER_DOCS_SYNC][BACKEND] driver=$safeDriverRef count=${refreshResult.backendCount}',
        );
        final compliance = DriverDocumentsStore.instance
            .complianceSummaryForCompanyAdminDriver(
              driver.id,
              tenantId: scope.tenantId,
              companyId: scope.companyId,
            );
        final visibleDocs = DriverDocumentsStore.instance
            .documentsVisibleForCompanyAdminDriver(
              driver.id,
              tenantId: scope.tenantId,
              companyId: scope.companyId,
            );
        final expiringSoonForDriver = visibleDocs
            .where(
              (doc) => _isExpiryWithinDaysForDiag(doc.expiryDate, days: 30),
            )
            .length;
        var localOnlyCount = 0;
        for (final doc in visibleDocs) {
          final hasMetadata =
              doc.documentType.trim().isNotEmpty ||
              doc.title.trim().isNotEmpty ||
              doc.status.trim().isNotEmpty;
          final artifactSource = driverDocumentArtifactSource(doc);
          final hasArtifact = artifactSource != 'missing';
          debugPrint(
            '[DRIVER_DOCS][ARTIFACT_CHECK] driver=$safeDriverRef doc=${_shortDriverIdForDiag(doc.documentId)} hasMetadata=$hasMetadata hasArtifact=$hasArtifact source=$artifactSource',
          );
          if (!hasArtifact) {
            final normalizedType = normalizeDriverDocumentTypeForCompliance(
              rawType: doc.documentType,
              title: doc.title,
            );
            debugPrint(
              '[DRIVER_DOCS][ARTIFACT_MISSING] driver=$safeDriverRef doc=${_shortDriverIdForDiag(doc.documentId)} type=$normalizedType',
            );
          }
          final likelyLocalOnly =
              doc.backendFileName.trim().isEmpty &&
              doc.backendContentType.trim().isEmpty &&
              doc.backendSizeBytes <= 0 &&
              doc.storageState.trim().isEmpty;
          if (likelyLocalOnly) {
            localOnlyCount++;
          }
        }
        if (localOnlyCount > 0) {
          debugPrint(
            '[DRIVER_DOCS_SYNC][UPLOAD_REQUIRED] driver=$safeDriverRef localOnly=$localOnlyCount',
          );
        }
        if (ok && refreshResult.backendCount == 0) {
          debugPrint(
            '[DRIVER_DOCS_SYNC][MISMATCH] driver=$safeDriverRef reason=backend_empty_for_scope',
          );
          if (localBefore == 0) {
            debugPrint(
              '[DRIVER_DOCS_BACKFILL][SOURCE_DEVICE_REQUIRED] driver=$safeDriverRef count=0',
            );
          }
        }
        if (ok) {
          if (_docRefreshFailedDriverIds.remove(driver.id.trim())) {
            refreshFailureStateChanged = true;
          }
          debugPrint(
            '[DRIVER_DOCS][REFRESH_DONE] driver=$safeDriverRef count=$visibleCount',
          );
        } else {
          if (_docRefreshFailedDriverIds.add(driver.id.trim())) {
            refreshFailureStateChanged = true;
          }
          debugPrint(
            '[DRIVER_DOCS_SYNC][MISMATCH] driver=$safeDriverRef reason=${refreshResult.errorCode}',
          );
          debugPrint(
            '[DRIVER_DOCS][REFRESH_FAILED] driver=$safeDriverRef error=backend_refresh_failed',
          );
        }
        debugPrint(
          '[DRIVER_DOCS][COMPLIANCE] driver=$safeDriverRef valid=${compliance.validRequiredCount}/7 uploaded=${compliance.uploadedRequiredCount}/7 missing=${compliance.missingRequiredTypeIds.length} expired=${compliance.expiredRequiredTypeIds.length} pending=${compliance.pendingRequiredTypeIds.length} rejected=${compliance.rejectedRequiredTypeIds.length} attachmentMissing=${compliance.missingAttachmentRequiredTypeIds.length}',
        );
        debugPrint(
          '[DRIVER_DOC_EDIT][COMPLIANCE] driver=$safeDriverRef valid=${compliance.validRequiredCount}/7 expired=${compliance.expiredRequiredTypeIds.length} expiringSoon=$expiringSoonForDriver missing=${compliance.missingRequiredTypeIds.length} attachmentMissing=${compliance.missingAttachmentRequiredTypeIds.length}',
        );
        debugPrint(
          '[DRIVER_DOCS_SYNC][DONE] driver=$safeDriverRef visible=$visibleCount',
        );
        debugPrint(
          '[DRIVER_DOCS_ADMIN][REFRESH_DRIVER] driver=${_shortDriverIdForDiag(driver.id)} ok=$ok count=$visibleCount',
        );
      }
    } finally {
      _adminDocsRefreshInFlight = false;
      if (mounted && refreshFailureStateChanged) {
        setState(() {});
      }
    }
  }

  Future<void> _refreshDriversFromBootstrap({
    required String reason,
    bool force = false,
  }) async {
    if (_refreshInFlight) {
      debugPrint(
        '[DRIVERS_PAGE][REFRESH_SKIP] reason=$reason throttle=false inFlight=true',
      );
      return;
    }
    final now = DateTime.now().toUtc();
    if (!force && _hasSuccessfulRefresh && _lastRefreshAtUtc != null) {
      final elapsed = now.difference(_lastRefreshAtUtc!);
      if (elapsed < const Duration(seconds: 5)) {
        debugPrint(
          '[DRIVERS_PAGE][REFRESH_SKIP] reason=$reason throttle=true inFlight=false',
        );
        return;
      }
    }
    debugPrint('[DRIVERS_PAGE][REFRESH_START] reason=$reason');
    _refreshInFlight = true;
    try {
      final ok = await _hydrateCompanyBootstrapFromActiveSession(
        reason: reason,
      );
      _reapplyRecentConfirmedDriverState();
      _lastRefreshOk = ok;
      try {
        await _refreshAdminDocumentsForVisibleDrivers(
          reason: reason,
          force: force,
        );
      } catch (error) {
        debugPrint(
          '[DRIVER_DOCS_ADMIN][REFRESH_OPTIONAL_ERROR] reason=$reason error=${_shortErrorForDiag(error)}',
        );
      }
      if (ok) {
        _lastRefreshAtUtc = DateTime.now().toUtc();
        _hasSuccessfulRefresh = true;
      }
      debugPrint('[DRIVERS_PAGE][REFRESH_DONE] reason=$reason ok=$ok');
    } finally {
      _refreshInFlight = false;
    }
  }

  void _reapplyRecentConfirmedDriverState() {
    final now = DateTime.now().toUtc();
    const keepFor = Duration(seconds: 25);
    final staleIds = <String>[];
    for (final entry in _recentConfirmedDriverActiveById.entries) {
      final driverId = entry.key.trim();
      final expected = entry.value.active;
      final atUtc = entry.value.atUtc;
      if (driverId.isEmpty || now.difference(atUtc) > keepFor) {
        staleIds.add(driverId);
        continue;
      }
      DriverProfile? current;
      for (final driver in driversNotifier.value) {
        if (driver.id.trim() == driverId) {
          current = driver;
          break;
        }
      }
      if (current == null) {
        staleIds.add(driverId);
        continue;
      }
      if (current.isActive == expected) continue;
      updateDriver(
        current.id,
        current.copyWith(isActive: expected),
        syncInventory: false,
      );
      debugPrint(
        '[DRIVER_STATE_PROPAGATE][NOTIFIER] driver=${_shortDriverIdForDiag(current.id)} updated=true drivers=${driversNotifier.value.length}',
      );
    }
    for (final id in staleIds) {
      _recentConfirmedDriverActiveById.remove(id);
    }
  }

  void _propagateDriverStateAfterConfirmedSave(DriverProfile updated) {
    final driverId = updated.id.trim();
    debugPrint(
      '[DRIVER_STATE_PROPAGATE][START] driver=${_shortDriverIdForDiag(driverId)} active=${updated.isActive}',
    );
    var existedBefore = false;
    for (final driver in driversNotifier.value) {
      if (driver.id.trim() == driverId) {
        existedBefore = true;
        break;
      }
    }
    debugPrint(
      '[DRIVER_STATE_PROPAGATE][LOCAL_LIST] driver=${_shortDriverIdForDiag(driverId)} updated=$existedBefore',
    );
    updateDriver(updated.id, updated, syncInventory: false);
    _recentConfirmedDriverActiveById[driverId] = (
      active: updated.isActive,
      atUtc: DateTime.now().toUtc(),
    );
    final total = driversNotifier.value.length;
    final active = driversNotifier.value.where((d) => d.isActive).length;
    debugPrint(
      '[DRIVER_STATE_PROPAGATE][NOTIFIER] driver=${_shortDriverIdForDiag(driverId)} updated=true drivers=$total',
    );
    debugPrint(
      '[DRIVER_STATE_PROPAGATE][TENANT_CACHE] driver=${_shortDriverIdForDiag(driverId)} saved=true',
    );
    debugPrint('[DRIVER_STATE_PROPAGATE][KPI] active=$active total=$total');
    debugPrint(
      '[DRIVER_STATE_PROPAGATE][DONE] driver=${_shortDriverIdForDiag(driverId)} active=${updated.isActive}',
    );
  }

  Future<void> _refreshAfterMutation({required String reason}) async {
    debugPrint('[DRIVER_MANAGEMENT][REFRESH_AFTER_MUTATION] reason=$reason');
    if (mounted) {
      setState(() {});
    }
    try {
      await _refreshDriversFromBootstrap(reason: reason, force: true);
      if (mounted) {
        setState(() {});
      }
      final driversCount = _adminVisibleDrivers().length;
      if (_lastRefreshOk) {
        debugPrint(
          '[DRIVER_MANAGEMENT][REFRESH_DONE] reason=$reason drivers=$driversCount',
        );
      } else {
        debugPrint(
          '[DRIVER_MANAGEMENT][REFRESH_FAILED] reason=$reason error=bootstrap_refresh_failed',
        );
      }
    } catch (error) {
      debugPrint(
        '[DRIVER_MANAGEMENT][REFRESH_FAILED] reason=$reason error=${_shortErrorForDiag(error)}',
      );
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(
      _ensureCompanySessionTokenForAdminView(reason: 'drivers_page_open'),
    );
    unawaited(
      _refreshDriversFromBootstrap(reason: 'drivers_page_open', force: true),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(
        _ensureCompanySessionTokenForAdminView(reason: 'drivers_page_resume'),
      );
      unawaited(_refreshDriversFromBootstrap(reason: 'drivers_page_resume'));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _CompanyDriverManagementPageBody(
      onRequestAdminDriverDocumentsRefresh:
          _refreshAdminDocumentsForVisibleDrivers,
      onRequestMutationRefresh: _refreshAfterMutation,
      documentRefreshFailedDriverIds: _docRefreshFailedDriverIds,
      onPropagateConfirmedDriverState: _propagateDriverStateAfterConfirmedSave,
    );
  }
}
