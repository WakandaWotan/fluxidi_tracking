part of '../main.dart';

String _localScopePathSegment(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return 'default';
  final sanitized = trimmed.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
  if (sanitized.isEmpty) return 'default';
  return sanitized;
}

String _maskLocalScopeId(String value) {
  final trimmed = value.trim();
  if (trimmed.length <= 6) return trimmed;
  return '${trimmed.substring(0, 3)}...${trimmed.substring(trimmed.length - 3)}';
}

({String tenantId, String companyId}) _activeLocalScopeIds() {
  final resolvedId = resolvedCompanyId.trim();
  final tenantId = resolvedId.isNotEmpty
      ? resolvedId
      : kOutboundTenantId.trim();
  final companyId = resolvedId.isNotEmpty ? resolvedId : tenantId;
  return (tenantId: tenantId, companyId: companyId);
}

({String tenantId, String companyId, String source})?
_strictActiveLocalScopeIdsWithSource() {
  final activeCompanyId = companyProfileNotifier.value?.companyId.trim() ?? '';
  if (activeCompanyId.isNotEmpty) {
    return (
      tenantId: activeCompanyId,
      companyId: activeCompanyId,
      source: 'company_profile',
    );
  }
  final sessionCompanyId =
      activeCompanySessionNotifier.value?.companyId.trim() ?? '';
  if (sessionCompanyId.isNotEmpty) {
    return (
      tenantId: sessionCompanyId,
      companyId: sessionCompanyId,
      source: 'company_session',
    );
  }
  final driverSession = activeDriverSessionNotifier.value;
  final driverTenantId = (driverSession?.tenantId ?? '').trim();
  final driverCompanyId = (driverSession?.companyId ?? '').trim();
  if ((driverSession?.isStandaloneLoginSession ?? false) &&
      driverTenantId.isNotEmpty &&
      driverCompanyId.isNotEmpty) {
    return (
      tenantId: driverTenantId,
      companyId: driverCompanyId,
      source: 'driver_session',
    );
  }
  return null;
}

({String tenantId, String companyId})? _strictActiveLocalScopeIds() {
  final resolved = _strictActiveLocalScopeIdsWithSource();
  if (resolved == null) return null;
  return (tenantId: resolved.tenantId, companyId: resolved.companyId);
}

({String tenantId, String companyId})? _resolveComplianceLedgerScope({
  String? tenantId,
  String? companyId,
}) {
  final recordTenant = (tenantId ?? '').trim();
  final recordCompany = (companyId ?? '').trim();
  if (recordTenant.isNotEmpty && recordCompany.isNotEmpty) {
    return (tenantId: recordTenant, companyId: recordCompany);
  }
  final strictLocal = _strictActiveLocalScopeIds();
  if (strictLocal != null) {
    return strictLocal;
  }
  final bookingScope = _strictActiveBookingScopeQuery();
  if (bookingScope != null) {
    final resolvedTenant =
        (bookingScope['tenant_id'] ?? bookingScope['tenantId'] ?? '')
            .toString()
            .trim();
    final resolvedCompany =
        (bookingScope['company_id'] ?? bookingScope['companyId'] ?? '')
            .toString()
            .trim();
    if (resolvedTenant.isNotEmpty && resolvedCompany.isNotEmpty) {
      return (tenantId: resolvedTenant, companyId: resolvedCompany);
    }
  }
  return null;
}

/// Phase 0b local-only compliance ledger sink (append-only JSONL).
/// Best-effort by design: write failures must never break ride UX.
class _ComplianceRideLedgerStore {
  static const String _fileName = 'compliance_ledger_v1.jsonl';

  static Future<File> _legacyFile() async {
    final base = await getApplicationDocumentsDirectory();
    return File('${base.path}${Platform.pathSeparator}$_fileName');
  }

  static Future<File> _scopedFile({
    required String tenantId,
    required String companyId,
  }) async {
    final base = await getApplicationDocumentsDirectory();
    final scopedDir = Directory(
      '${base.path}${Platform.pathSeparator}compliance_state${Platform.pathSeparator}tenant_${_localScopePathSegment(tenantId)}${Platform.pathSeparator}company_${_localScopePathSegment(companyId)}',
    );
    if (!await scopedDir.exists()) {
      await scopedDir.create(recursive: true);
    }
    final file = File('${scopedDir.path}${Platform.pathSeparator}$_fileName');
    debugPrint(
      '[LOCAL_SCOPE][COMPLIANCE_FILTER] target=write tenant=${_maskLocalScopeId(tenantId)} company=${_maskLocalScopeId(companyId)} file=${file.path}',
    );
    return file;
  }

  static Future<File> _fileForRecord(Map<String, dynamic> record) async {
    final resolved = _resolveComplianceLedgerScope(
      tenantId: (record['tenant_id'] ?? '').toString(),
      companyId: (record['company_id'] ?? '').toString(),
    );
    if (resolved == null) {
      final activeScope = _activeLocalScopeIds();
      return _scopedFile(
        tenantId: activeScope.tenantId,
        companyId: activeScope.companyId,
      );
    }
    return _scopedFile(
      tenantId: resolved.tenantId,
      companyId: resolved.companyId,
    );
  }

  static Future<void> append(Map<String, dynamic> record) async {
    if (kIsWeb) return;
    try {
      final file = await _fileForRecord(record);
      if (!await file.exists()) {
        await file.create(recursive: true);
      }
      final line = '${jsonEncode(record)}\n';
      await file.writeAsString(line, mode: FileMode.append, flush: true);
    } catch (_) {
      // Keep stop-flow resilient; caller handles logging.
    }
  }
}

Future<void> _writeComplianceLedgerRecord({
  required Map<String, dynamic> record,
}) async {
  final recordTenant = (record['tenant_id'] ?? '').toString().trim();
  final recordCompany = (record['company_id'] ?? '').toString().trim();
  final scopeSource = recordTenant.isNotEmpty && recordCompany.isNotEmpty
      ? 'record'
      : (_strictActiveLocalScopeIds() != null
            ? 'strict_local'
            : 'strict_booking');
  final resolved = _resolveComplianceLedgerScope(
    tenantId: recordTenant,
    companyId: recordCompany,
  );
  if (resolved == null) {
    debugPrint(
      '[COMPLIANCE_LEDGER][SKIP_SCOPE] reason=missing_tenant_company_scope',
    );
    return;
  }
  final payload = Map<String, dynamic>.from(record)
    ..['tenant_id'] = resolved.tenantId
    ..['company_id'] = resolved.companyId;
  try {
    await _ComplianceRideLedgerStore.append(payload);
    debugPrint(
      '[COMPLIANCE_LEDGER][WRITE] scope_source=$scopeSource event_type=${payload['event_type']} ride_type=${payload['ride_type']} validation_state=${payload['provenance']?['validation_state']} backend_confirmed=${payload['provenance']?['backend_confirmed']} tenant=${_maskLocalScopeId(resolved.tenantId)} company=${_maskLocalScopeId(resolved.companyId)}',
    );
  } catch (e) {
    debugPrint('[COMPLIANCE_LEDGER][WARN] write_failed reason=$e');
  }
}

/// Local fallback store for direct rides that stayed local-only (no backend trip).
/// Kept isolated from backend history to avoid changing server behavior.
class _LocalDirectTripHistoryStore {
  static const String _fileName = 'local_direct_trip_history_v1.jsonl';

  static Future<File> _legacyFile() async {
    final base = await getApplicationDocumentsDirectory();
    return File('${base.path}${Platform.pathSeparator}$_fileName');
  }

  static Future<File> _scopedFile({
    required String tenantId,
    required String companyId,
  }) async {
    final base = await getApplicationDocumentsDirectory();
    final scopedDir = Directory(
      '${base.path}${Platform.pathSeparator}compliance_state${Platform.pathSeparator}tenant_${_localScopePathSegment(tenantId)}${Platform.pathSeparator}company_${_localScopePathSegment(companyId)}',
    );
    if (!await scopedDir.exists()) {
      await scopedDir.create(recursive: true);
    }
    return File('${scopedDir.path}${Platform.pathSeparator}$_fileName');
  }

  static Future<File> _fileForRecord(Map<String, dynamic> record) async {
    final activeScope = _activeLocalScopeIds();
    final tenantId = (record['tenant_id'] ?? '').toString().trim().isNotEmpty
        ? (record['tenant_id'] ?? '').toString().trim()
        : activeScope.tenantId;
    final companyId = (record['company_id'] ?? '').toString().trim().isNotEmpty
        ? (record['company_id'] ?? '').toString().trim()
        : activeScope.companyId;
    return _scopedFile(tenantId: tenantId, companyId: companyId);
  }

  static bool _matchesScope(
    Map<String, dynamic> row, {
    required String tenantId,
    required String companyId,
    required bool allowLegacyWithoutScope,
  }) {
    final rowTenant = (row['tenant_id'] ?? '').toString().trim();
    final rowCompany = (row['company_id'] ?? '').toString().trim();
    if (rowTenant.isEmpty && rowCompany.isEmpty) {
      return allowLegacyWithoutScope;
    }
    if (rowTenant.isNotEmpty && rowTenant != tenantId.trim()) return false;
    if (rowCompany.isNotEmpty && rowCompany != companyId.trim()) return false;
    return true;
  }

  static Future<List<Map<String, dynamic>>> _readFromFile(
    File file, {
    required String tenantId,
    required String companyId,
    required String driverId,
    required int limit,
    required bool allowLegacyWithoutScope,
  }) async {
    if (!await file.exists()) return const <Map<String, dynamic>>[];
    final lines = await file.readAsLines();
    final parsed = <Map<String, dynamic>>[];
    for (final raw in lines) {
      final line = raw.trim();
      if (line.isEmpty) continue;
      try {
        final decoded = jsonDecode(line);
        if (decoded is! Map) continue;
        final map = Map<String, dynamic>.from(decoded);
        final rowDriver = (map['driver_id'] ?? '').toString().trim();
        if (rowDriver != driverId.trim()) continue;
        if (!_matchesScope(
          map,
          tenantId: tenantId,
          companyId: companyId,
          allowLegacyWithoutScope: allowLegacyWithoutScope,
        )) {
          continue;
        }
        parsed.add(map);
      } catch (_) {
        // Ignore malformed JSONL entries to keep history resilient.
      }
    }
    if (parsed.length <= limit) return parsed;
    return parsed.sublist(parsed.length - limit);
  }

  static Future<void> append(Map<String, dynamic> record) async {
    if (kIsWeb) return;
    try {
      final file = await _fileForRecord(record);
      if (!await file.exists()) {
        await file.create(recursive: true);
      }
      await file.writeAsString(
        '${jsonEncode(record)}\n',
        mode: FileMode.append,
        flush: true,
      );
    } catch (_) {
      // Best-effort only; do not break ride stop flow.
    }
  }

  static Future<List<Map<String, dynamic>>> readFor({
    required String tenantId,
    required String companyId,
    required String driverId,
    int limit = 120,
  }) async {
    if (kIsWeb) return const <Map<String, dynamic>>[];
    try {
      final normalizedTenantId = tenantId.trim();
      final normalizedCompanyId = companyId.trim();
      if (normalizedTenantId.isEmpty || normalizedCompanyId.isEmpty) {
        return const <Map<String, dynamic>>[];
      }
      final scopedFile = await _scopedFile(
        tenantId: normalizedTenantId,
        companyId: normalizedCompanyId,
      );
      if (await scopedFile.exists()) {
        return _readFromFile(
          scopedFile,
          tenantId: normalizedTenantId,
          companyId: normalizedCompanyId,
          driverId: driverId,
          limit: limit,
          allowLegacyWithoutScope: false,
        );
      }
      final legacyFile = await _legacyFile();
      return _readFromFile(
        legacyFile,
        tenantId: normalizedTenantId,
        companyId: normalizedCompanyId,
        driverId: driverId,
        limit: limit,
        allowLegacyWithoutScope: false,
      );
    } catch (_) {
      return const <Map<String, dynamic>>[];
    }
  }
}

/// ===============================
/// BRANDING (Fluxidi Taxi UI)
/// ===============================

/// Put your logo in this path (recommended):
///   assets/fluxidi/fluxidi_logo.png
/// and add it to pubspec.yaml under flutter/assets.
