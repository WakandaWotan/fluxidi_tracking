/* CHIRON-LAST-GOOD-DATA-PRESERVATION-1
 *
 * In-memory last-good Chiron backend-events presentation cache.
 *
 * - Process-scoped / not persisted to disk.
 * - Partitioned by tenantId + companyId (single active slot).
 * - Never stores tokens, credentials, or raw HTTP payloads beyond the
 *   already-authorized presentation model supplied by the caller.
 */

/// Pure presentation decision after a network attempt completes.
class ChironLastGoodPresentation<T> {
  const ChironLastGoodPresentation({
    required this.showLoading,
    required this.showStaleWarning,
    this.display,
    this.hardErrorMessage,
  });

  /// True only while waiting for the first-ever result with no cache.
  final bool showLoading;

  /// Non-destructive banner: keep showing [display] after a refresh failure.
  final bool showStaleWarning;

  /// Last-good (or freshly successful) presentation payload.
  final T? display;

  /// Hard error when there is no last-good data to keep on screen.
  final String? hardErrorMessage;
}

/// Single-slot cache keyed by tenant + company.
class ChironLastGoodEventsCache<T> {
  ChironLastGoodEventsCache();

  String? _tenantId;
  String? _companyId;
  T? _payload;

  String? get storedTenantId => _tenantId;
  String? get storedCompanyId => _companyId;
  bool get hasEntry => _payload != null;

  /// Returns the cached payload only when [tenantId]/[companyId] match.
  T? peek({required String tenantId, required String companyId}) {
    final t = tenantId.trim();
    final c = companyId.trim();
    if (t.isEmpty || c.isEmpty) return null;
    if (_tenantId != t || _companyId != c) return null;
    return _payload;
  }

  /// Remembers a successful presentation payload for one company scope.
  /// Overwrites any previous slot (company change cannot leak prior data).
  void remember({
    required String tenantId,
    required String companyId,
    required T payload,
  }) {
    final t = tenantId.trim();
    final c = companyId.trim();
    if (t.isEmpty || c.isEmpty) return;
    _tenantId = t;
    _companyId = c;
    _payload = payload;
  }

  void clear() {
    _tenantId = null;
    _companyId = null;
    _payload = null;
  }

  /// Drops the entry when it belongs to a different authenticated company.
  void clearIfScopeMismatch({
    required String tenantId,
    required String companyId,
  }) {
    if (_payload == null) return;
    final t = tenantId.trim();
    final c = companyId.trim();
    if (_tenantId != t || _companyId != c) {
      clear();
    }
  }
}

/// Initial mount / remount presentation from cache (no network result yet).
ChironLastGoodPresentation<T> initialChironEventsPresentation<T>({
  required T? cachedForActiveScope,
}) {
  if (cachedForActiveScope != null) {
    return ChironLastGoodPresentation<T>(
      showLoading: false,
      showStaleWarning: false,
      display: cachedForActiveScope,
    );
  }
  return ChironLastGoodPresentation<T>(
    showLoading: true,
    showStaleWarning: false,
  );
}

/// Apply a completed load attempt against optional last-good cache.
ChironLastGoodPresentation<T> applyChironEventsLoadResult<T>({
  required bool resultOk,
  required T? successPayload,
  required String resultErrorMessage,
  required T? cachedForActiveScope,
  required String defaultHardError,
}) {
  if (resultOk && successPayload != null) {
    return ChironLastGoodPresentation<T>(
      showLoading: false,
      showStaleWarning: false,
      display: successPayload,
    );
  }
  if (cachedForActiveScope != null) {
    return ChironLastGoodPresentation<T>(
      showLoading: false,
      showStaleWarning: true,
      display: cachedForActiveScope,
    );
  }
  final msg = resultErrorMessage.trim();
  return ChironLastGoodPresentation<T>(
    showLoading: false,
    showStaleWarning: false,
    hardErrorMessage: msg.isEmpty ? defaultHardError : msg,
  );
}
