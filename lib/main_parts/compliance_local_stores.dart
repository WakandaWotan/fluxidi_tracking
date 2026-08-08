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

  /// DRIVER-HISTORY-PENDING-FLICKER-MONOTONICITY-P1:
  /// Drop only superseded `offline_stop_pending_finalize` rows whose trip_id
  /// now exists on the backend. Never touches genuine still-pending rows or
  /// unrelated local history (`local_only_direct_fallback`, etc.).
  static Future<int> removeSupersededOfflineStopPending({
    required String tenantId,
    required String companyId,
    required String driverId,
    required Set<String> confirmedTripIds,
  }) async {
    if (kIsWeb) return 0;
    final confirmed = confirmedTripIds
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet();
    if (confirmed.isEmpty) return 0;
    try {
      final normalizedTenantId = tenantId.trim();
      final normalizedCompanyId = companyId.trim();
      final normalizedDriverId = driverId.trim();
      if (normalizedTenantId.isEmpty ||
          normalizedCompanyId.isEmpty ||
          normalizedDriverId.isEmpty) {
        return 0;
      }
      final scopedFile = await _scopedFile(
        tenantId: normalizedTenantId,
        companyId: normalizedCompanyId,
      );
      if (!await scopedFile.exists()) return 0;
      // Read the full file (all drivers in scope) so a rewrite cannot drop
      // another driver's rows; then filter only this driver's superseded pending.
      final lines = await scopedFile.readAsLines();
      final keptLines = <String>[];
      var removed = 0;
      for (final raw in lines) {
        final line = raw.trim();
        if (line.isEmpty) continue;
        try {
          final decoded = jsonDecode(line);
          if (decoded is! Map) {
            keptLines.add(line);
            continue;
          }
          final map = Map<String, dynamic>.from(decoded);
          final rowDriver = (map['driver_id'] ?? '').toString().trim();
          if (rowDriver != normalizedDriverId) {
            keptLines.add(jsonEncode(map));
            continue;
          }
          final tripId =
              (map['trip_id'] ?? map['tripId'] ?? '').toString().trim();
          if (tripId.isNotEmpty &&
              confirmed.contains(tripId) &&
              isOfflineStopPendingFinalizeRecord(map)) {
            removed++;
            continue;
          }
          keptLines.add(jsonEncode(map));
        } catch (_) {
          keptLines.add(line);
        }
      }
      if (removed == 0) return 0;
      final body = keptLines.isEmpty ? '' : '${keptLines.join('\n')}\n';
      await scopedFile.writeAsString(body, flush: true);
      return removed;
    } catch (_) {
      return 0;
    }
  }
}

/// STREET-RIDE-DURABLE-COMPLETION-2: durable single-record store for the active
/// / last direct-trip session so a crash or restart can resume an active ride
/// or reconcile a stopped-but-unfinalized booking. Scoped under the same
/// tenant/company directory as the other local stores; the record also carries
/// driver_id so a device shared across drivers only recovers its own session.
class _DirectTripSessionStore {
  static const String _fileName = 'direct_trip_session_v1.json';

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

  static Future<void> save(
    DirectTripSession session, {
    required String tenantId,
    required String companyId,
    required String driverId,
  }) async {
    if (kIsWeb) return;
    final normalizedTenant = tenantId.trim();
    final normalizedCompany = companyId.trim();
    if (normalizedTenant.isEmpty || normalizedCompany.isEmpty) return;
    try {
      final file = await _scopedFile(
        tenantId: normalizedTenant,
        companyId: normalizedCompany,
      );
      final payload = session
          .copyWith(
            tenantId: normalizedTenant,
            companyId: normalizedCompany,
            driverId: driverId.trim().isEmpty ? session.driverId : driverId.trim(),
            updatedAtIso: DateTime.now().toUtc().toIso8601String(),
          )
          .toJson();
      await file.writeAsString(jsonEncode(payload), flush: true);
    } catch (_) {
      // Best-effort persistence; never break ride UX.
    }
  }

  static Future<DirectTripSession?> load({
    required String tenantId,
    required String companyId,
    required String driverId,
  }) async {
    if (kIsWeb) return null;
    final normalizedTenant = tenantId.trim();
    final normalizedCompany = companyId.trim();
    if (normalizedTenant.isEmpty || normalizedCompany.isEmpty) return null;
    try {
      final file = await _scopedFile(
        tenantId: normalizedTenant,
        companyId: normalizedCompany,
      );
      if (!await file.exists()) return null;
      final raw = (await file.readAsString()).trim();
      if (raw.isEmpty) return null;
      final session = DirectTripSession.fromJson(jsonDecode(raw));
      if (session == null) return null;
      final sessionDriver = (session.driverId ?? '').trim();
      final wantDriver = driverId.trim();
      // Only recover a session that belongs to the current driver (or a legacy
      // record with no driver stamp).
      if (sessionDriver.isNotEmpty &&
          wantDriver.isNotEmpty &&
          sessionDriver != wantDriver) {
        return null;
      }
      return session;
    } catch (_) {
      return null;
    }
  }

  static Future<void> clear({
    required String tenantId,
    required String companyId,
  }) async {
    if (kIsWeb) return;
    final normalizedTenant = tenantId.trim();
    final normalizedCompany = companyId.trim();
    if (normalizedTenant.isEmpty || normalizedCompany.isEmpty) return;
    try {
      final file = await _scopedFile(
        tenantId: normalizedTenant,
        companyId: normalizedCompany,
      );
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {
      // Best-effort clear.
    }
  }
}

/// PLANNED-STOP-HISTORY-DURABILITY-P0-8: durable store for planned-ride STOP
/// intents that have not yet been confirmed materialized by the tracking
/// worker.
///
/// This is the planned-ride counterpart of [_DirectTripSessionStore]. A planned
/// ride only gets its durable trip / `trips_index` / driver-history / Chiron
/// chain from `POST /trip/record-planned-stop`, and nothing server-side can
/// recreate a trip row that was never written. So the measured STOP payload is
/// persisted here BEFORE the booking is projected COMPLETED, and replayed until
/// the worker confirms it. Replay is safe because the planned `trip_id` is
/// deterministic (see `plannedStopTripId`).
///
/// Scoped under the same tenant/company directory as the other local stores;
/// each record also carries `driver_id` so a shared device never replays another
/// driver's stop.
class _PlannedStopIntentStore {
  static const String _fileName = 'planned_stop_intents_v1.json';

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

  static Future<List<PlannedStopIntent>> _readAll({
    required String tenantId,
    required String companyId,
  }) async {
    try {
      final file = await _scopedFile(tenantId: tenantId, companyId: companyId);
      if (!await file.exists()) return const <PlannedStopIntent>[];
      final raw = (await file.readAsString()).trim();
      if (raw.isEmpty) return const <PlannedStopIntent>[];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const <PlannedStopIntent>[];
      return decoded
          .map(PlannedStopIntent.fromJson)
          .whereType<PlannedStopIntent>()
          .toList();
    } catch (_) {
      return const <PlannedStopIntent>[];
    }
  }

  static Future<bool> _writeAll(
    List<PlannedStopIntent> intents, {
    required String tenantId,
    required String companyId,
  }) async {
    try {
      final file = await _scopedFile(tenantId: tenantId, companyId: companyId);
      await file.writeAsString(
        jsonEncode(intents.map((e) => e.toJson()).toList()),
        flush: true,
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Persists [intent] durably.
  ///
  /// Returns true only when the bytes reached disk — the caller uses that as the
  /// invariant-B proof before projecting COMPLETED, so a failed write must never
  /// report success.
  static Future<bool> save(PlannedStopIntent intent) async {
    if (kIsWeb) return false;
    final tenantId = intent.tenantId.trim();
    final companyId = intent.companyId.trim();
    if (tenantId.isEmpty || companyId.isEmpty) return false;
    final existing = await _readAll(tenantId: tenantId, companyId: companyId);
    final ok = await _writeAll(
      upsertPlannedStopIntent(existing, intent),
      tenantId: tenantId,
      companyId: companyId,
    );
    debugPrint(
      '[PLANNED_STOP_INTENT][PERSIST] ok=$ok intent=${intent.intentId} '
      'booking=${intent.bookingId} tenant=${_maskLocalScopeId(tenantId)} '
      'company=${_maskLocalScopeId(companyId)}',
    );
    return ok;
  }

  /// Intents still awaiting confirmation for this tenant/company/driver.
  static Future<List<PlannedStopIntent>> pending({
    required String tenantId,
    required String companyId,
    required String driverId,
  }) async {
    if (kIsWeb) return const <PlannedStopIntent>[];
    final normalizedTenant = tenantId.trim();
    final normalizedCompany = companyId.trim();
    if (normalizedTenant.isEmpty || normalizedCompany.isEmpty) {
      return const <PlannedStopIntent>[];
    }
    final all = await _readAll(
      tenantId: normalizedTenant,
      companyId: normalizedCompany,
    );
    return plannedStopIntentsForScope(
      all,
      tenantId: normalizedTenant,
      companyId: normalizedCompany,
      driverId: driverId,
    );
  }

  /// Drops a confirmed intent.
  static Future<void> remove({
    required String tenantId,
    required String companyId,
    required String intentId,
  }) async {
    if (kIsWeb) return;
    final normalizedTenant = tenantId.trim();
    final normalizedCompany = companyId.trim();
    if (normalizedTenant.isEmpty || normalizedCompany.isEmpty) return;
    final existing = await _readAll(
      tenantId: normalizedTenant,
      companyId: normalizedCompany,
    );
    final next = removePlannedStopIntent(existing, intentId);
    if (next.length == existing.length) return;
    await _writeAll(
      next,
      tenantId: normalizedTenant,
      companyId: normalizedCompany,
    );
    debugPrint('[PLANNED_STOP_INTENT][CLEARED] intent=$intentId');
  }

  /// Records a failed replay so operators can see attempt counts in evidence.
  static Future<void> recordAttemptFailure({
    required PlannedStopIntent intent,
    required String error,
  }) async {
    if (kIsWeb) return;
    await save(
      intent.markAttemptFailed(nowUtc: DateTime.now().toUtc(), error: error),
    );
  }
}

/// ===============================
/// BRANDING (Fluxidi Taxi UI)
/// ===============================

/// Put your logo in this path (recommended):
///   assets/fluxidi/fluxidi_logo.png
/// and add it to pubspec.yaml under flutter/assets.
