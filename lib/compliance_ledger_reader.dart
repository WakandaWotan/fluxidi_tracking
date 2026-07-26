import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:fluxidi_tracking/app_config.dart';
import 'package:fluxidi_tracking/company_session_store.dart';
import 'package:fluxidi_tracking/driver_session_store.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

String _sanitizeScopeSegment(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return 'default';
  final sanitized = trimmed.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
  if (sanitized.isEmpty) return 'default';
  return sanitized;
}

String _maskScope(String value) {
  final trimmed = value.trim();
  if (trimmed.length <= 6) return trimmed;
  return '${trimmed.substring(0, 3)}...${trimmed.substring(trimmed.length - 3)}';
}

({String tenantId, String companyId})? _activeComplianceScope() {
  final activeCompanyId = companyProfileNotifier.value?.companyId.trim() ?? '';
  if (activeCompanyId.isNotEmpty) {
    return (tenantId: activeCompanyId, companyId: activeCompanyId);
  }
  final sessionCompanyId =
      activeCompanySessionNotifier.value?.companyId.trim() ?? '';
  if (sessionCompanyId.isNotEmpty) {
    return (tenantId: sessionCompanyId, companyId: sessionCompanyId);
  }
  final driverSession = activeDriverSessionNotifier.value;
  final driverTenantId = (driverSession?.tenantId ?? '').trim();
  final driverCompanyId = (driverSession?.companyId ?? '').trim();
  if ((driverSession?.isVerifiedPairingSession ?? false) &&
      driverTenantId.isNotEmpty &&
      driverCompanyId.isNotEmpty) {
    return (tenantId: driverTenantId, companyId: driverCompanyId);
  }
  return null;
}

class ComplianceLedgerEntry {
  const ComplianceLedgerEntry({
    required this.eventType,
    required this.eventId,
    required this.rideId,
    required this.rideType,
    required this.lifecycleStatus,
    required this.tenantId,
    required this.companyId,
    required this.driverId,
    required this.vehicleId,
    required this.bookingId,
    required this.tripId,
    required this.sessionId,
    required this.startedAtUtc,
    required this.endedAtUtc,
    required this.createdAtUtc,
    required this.finalizedAtUtc,
    required this.durationSeconds,
    required this.distanceKm,
    required this.waitSecondsTotal,
    required this.fareTotalEur,
    required this.currency,
    required this.paymentStatus,
    required this.paymentMethod,
    required this.paymentSource,
    required this.paymentProvider,
    required this.paymentId,
    required this.paidAtUtc,
    required this.receiptReference,
    required this.planningReference,
    required this.publicBookingReference,
    required this.invoiceReference,
    required this.validationState,
    required this.backendConfirmed,
    required this.pickupLabel,
    required this.dropoffLabel,
    required this.raw,
    required this.sourceLineIndex,
  });

  final String eventType;
  final String eventId;
  final String rideId;
  final String rideType;
  final String lifecycleStatus;
  final String tenantId;
  final String companyId;
  final String driverId;
  final String vehicleId;
  final String bookingId;
  final String tripId;
  final String sessionId;
  final DateTime? startedAtUtc;
  final DateTime? endedAtUtc;
  final DateTime? createdAtUtc;
  final DateTime? finalizedAtUtc;
  final int? durationSeconds;
  final double? distanceKm;
  final int? waitSecondsTotal;
  final double? fareTotalEur;
  final String currency;
  final String paymentStatus;
  final String paymentMethod;
  final String paymentSource;
  final String paymentProvider;
  final String paymentId;
  final DateTime? paidAtUtc;
  final String receiptReference;
  final String planningReference;
  final String publicBookingReference;
  final String invoiceReference;
  final String validationState;
  final bool? backendConfirmed;
  final String pickupLabel;
  final String dropoffLabel;
  final Map<String, dynamic> raw;
  final int sourceLineIndex;

  bool get isPaymentUpdate =>
      eventType.toLowerCase().trim() == 'payment_update';

  DateTime? get sortTimestamp =>
      finalizedAtUtc ?? createdAtUtc ?? paidAtUtc ?? endedAtUtc ?? startedAtUtc;

  factory ComplianceLedgerEntry.fromRaw(
    Map<String, dynamic> raw, {
    required int sourceLineIndex,
  }) {
    String readText(String key) => _toStringOrEmpty(raw[key]);
    final pickup = _asMap(raw['pickup']);
    final dropoff = _asMap(raw['dropoff']);
    final fare = _asMap(raw['fare']);
    final payment = _asMap(raw['payment']);
    final references = _asMap(raw['references']);
    final provenance = _asMap(raw['provenance']);

    return ComplianceLedgerEntry(
      eventType: readText('event_type'),
      eventId: readText('event_id'),
      rideId: readText('ride_id'),
      rideType: readText('ride_type'),
      lifecycleStatus: readText('lifecycle_status'),
      tenantId: _firstNonEmptyText(<Object?>[
        raw['tenant_id'],
        raw['tenantId'],
      ]),
      companyId: _firstNonEmptyText(<Object?>[
        raw['company_id'],
        raw['companyId'],
      ]),
      driverId: readText('driver_id'),
      vehicleId: readText('vehicle_id'),
      bookingId: readText('booking_id'),
      tripId: readText('trip_id'),
      sessionId: readText('session_id'),
      startedAtUtc: _toDateTime(raw['started_at_utc']),
      endedAtUtc: _toDateTime(raw['ended_at_utc']),
      createdAtUtc: _toDateTime(raw['created_at_utc']),
      finalizedAtUtc: _toDateTime(raw['finalized_at_utc']),
      durationSeconds: _toInt(raw['duration_seconds']),
      distanceKm: _toDouble(raw['distance_km']),
      waitSecondsTotal: _toInt(raw['wait_seconds_total']),
      fareTotalEur: _toDouble(fare['total_eur']),
      currency: _toStringOrEmpty(fare['currency']),
      paymentStatus: _toStringOrEmpty(payment['status']),
      paymentMethod: _toStringOrEmpty(payment['method']),
      paymentSource: _toStringOrEmpty(payment['source']),
      paymentProvider: _toStringOrEmpty(payment['provider']),
      paymentId: _toStringOrEmpty(payment['payment_id']),
      paidAtUtc: _toDateTime(payment['paid_at_utc']),
      receiptReference: _firstNonEmptyText(<Object?>[
        references['receipt_reference'],
        references['receiptReference'],
        raw['receipt_reference'],
        raw['receiptReference'],
      ]),
      planningReference: _firstNonEmptyText(<Object?>[
        references['planning_reference'],
        references['planningReference'],
        raw['planning_reference'],
        raw['planningReference'],
      ]),
      publicBookingReference: _firstNonEmptyText(<Object?>[
        references['public_booking_reference'],
        references['publicBookingReference'],
        references['booking_reference'],
        references['bookingReference'],
        references['public_reference'],
        references['publicReference'],
        raw['public_booking_reference'],
        raw['publicBookingReference'],
        raw['booking_reference'],
        raw['bookingReference'],
        raw['public_reference'],
        raw['publicReference'],
      ]),
      invoiceReference: _toStringOrEmpty(references['invoice_reference']),
      validationState: _toStringOrEmpty(provenance['validation_state']),
      backendConfirmed: _toBool(provenance['backend_confirmed']),
      pickupLabel: _toStringOrEmpty(pickup['label']),
      dropoffLabel: _toStringOrEmpty(dropoff['label']),
      raw: raw,
      sourceLineIndex: sourceLineIndex,
    );
  }

  static Map<String, dynamic> _asMap(Object? value) {
    if (value is Map) return Map<String, dynamic>.from(value);
    return const <String, dynamic>{};
  }

  static String _toStringOrEmpty(Object? value) =>
      (value == null ? '' : value.toString().trim());

  static String _firstNonEmptyText(List<Object?> values) {
    for (final value in values) {
      final text = _toStringOrEmpty(value);
      if (text.isNotEmpty) return text;
    }
    return '';
  }

  static DateTime? _toDateTime(Object? value) {
    final text = _toStringOrEmpty(value);
    if (text.isEmpty) return null;
    return DateTime.tryParse(text);
  }

  static int? _toInt(Object? value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    final text = value.toString().trim();
    if (text.isEmpty) return null;
    return int.tryParse(text) ?? double.tryParse(text)?.toInt();
  }

  static double? _toDouble(Object? value) {
    if (value == null) return null;
    if (value is double) return value;
    if (value is num) return value.toDouble();
    final text = value.toString().trim().replaceAll(',', '.');
    if (text.isEmpty) return null;
    return double.tryParse(text);
  }

  static bool? _toBool(Object? value) {
    if (value == null) return null;
    if (value is bool) return value;
    final text = value.toString().trim().toLowerCase();
    if (text == 'true' || text == '1' || text == 'yes') return true;
    if (text == 'false' || text == '0' || text == 'no') return false;
    return null;
  }
}

class ComplianceLedgerReadResult {
  const ComplianceLedgerReadResult({
    required this.entries,
    required this.fileExists,
    required this.skippedMalformedLines,
    this.localCount = 0,
    this.backendCount = 0,
    this.mergedCount = 0,
    this.backendFetchOk = false,
    this.backendError,
    this.isSyncingBackend = false,
  });

  final List<ComplianceLedgerEntry> entries;
  final bool fileExists;
  final int skippedMalformedLines;
  final int localCount;
  final int backendCount;
  final int mergedCount;
  final bool backendFetchOk;
  final String? backendError;
  final bool isSyncingBackend;
}

class ComplianceLedgerReader {
  static const String fileName = 'compliance_ledger_v1.jsonl';
  static const String localDirectHistoryFileName =
      'local_direct_trip_history_v1.jsonl';

  static String _ledgerGroupToken(String raw) {
    return raw.trim().toLowerCase().replaceAll('-', '_').replaceAll(' ', '_');
  }

  static String? _ledgerGroupKeyPart(String prefix, String value) {
    final normalized = value.trim();
    if (normalized.isEmpty || normalized == '—') return null;
    return '$prefix:${normalized.toLowerCase()}';
  }

  /// Groups ledger rows by booking/trip/receipt so register detail can show
  /// full audit history even when a flat "latest N" slice would drop older rows.
  static String groupKeyFor(ComplianceLedgerEntry entry) {
    final booking = _ledgerGroupKeyPart('booking', entry.bookingId);
    if (booking != null) return booking;
    final trip = _ledgerGroupKeyPart('trip', entry.tripId);
    if (trip != null) return trip;
    final receipt = _ledgerGroupKeyPart('receipt', entry.receiptReference);
    if (receipt != null) return receipt;
    final ride = _ledgerGroupKeyPart('ride', entry.rideId);
    if (ride != null) return ride;
    final event = _ledgerGroupKeyPart('event', entry.eventId);
    if (event != null) return event;
    return 'event:index_${entry.sourceLineIndex}';
  }

  static bool isMeaningfulLifecycleToken(String raw) {
    switch (_ledgerGroupToken(raw)) {
      case '':
      case 'unknown':
      case 'payment_updated':
        return false;
      default:
        return true;
    }
  }

  static Future<Directory> _rootDir() async {
    final base = await getApplicationDocumentsDirectory();
    return Directory(base.path);
  }

  static Future<File> _legacyFile() async {
    final root = await _rootDir();
    return File('${root.path}${Platform.pathSeparator}$fileName');
  }

  static Future<File> _legacyLocalDirectHistoryFile() async {
    final root = await _rootDir();
    return File(
      '${root.path}${Platform.pathSeparator}$localDirectHistoryFileName',
    );
  }

  static Future<File> _scopedFile({
    required String tenantId,
    required String companyId,
  }) async {
    final root = await _rootDir();
    final scopedDir = Directory(
      '${root.path}${Platform.pathSeparator}compliance_state${Platform.pathSeparator}tenant_${_sanitizeScopeSegment(tenantId)}${Platform.pathSeparator}company_${_sanitizeScopeSegment(companyId)}',
    );
    if (!await scopedDir.exists()) {
      await scopedDir.create(recursive: true);
    }
    return File('${scopedDir.path}${Platform.pathSeparator}$fileName');
  }

  static Future<File> _scopedLocalDirectHistoryFile({
    required String tenantId,
    required String companyId,
  }) async {
    final root = await _rootDir();
    final scopedDir = Directory(
      '${root.path}${Platform.pathSeparator}compliance_state${Platform.pathSeparator}tenant_${_sanitizeScopeSegment(tenantId)}${Platform.pathSeparator}company_${_sanitizeScopeSegment(companyId)}',
    );
    if (!await scopedDir.exists()) {
      await scopedDir.create(recursive: true);
    }
    return File(
      '${scopedDir.path}${Platform.pathSeparator}$localDirectHistoryFileName',
    );
  }

  static Future<File?> _file() async {
    final scope = _activeComplianceScope();
    if (scope == null) return null;
    return _scopedFile(tenantId: scope.tenantId, companyId: scope.companyId);
  }

  static Future<File?> _localDirectHistoryFile() async {
    final scope = _activeComplianceScope();
    if (scope == null) return null;
    return _scopedLocalDirectHistoryFile(
      tenantId: scope.tenantId,
      companyId: scope.companyId,
    );
  }

  bool _entryMatchesScope(
    ComplianceLedgerEntry entry, {
    required String tenantId,
    required String companyId,
    required bool allowLegacyWithoutScope,
  }) {
    final rowTenant = entry.tenantId.trim();
    final rowCompany = entry.companyId.trim();
    final activeTenant = tenantId.trim();
    final activeCompany = companyId.trim();
    if (rowTenant.isEmpty && rowCompany.isEmpty) {
      return allowLegacyWithoutScope;
    }
    if (rowTenant.isNotEmpty && rowTenant != activeTenant) return false;
    if (rowCompany.isNotEmpty && rowCompany != activeCompany) return false;
    return true;
  }

  Future<List<Map<String, dynamic>>> _readRawMaps(File file) async {
    if (!await file.exists()) return const <Map<String, dynamic>>[];
    final rawLines = await file.readAsLines();
    final out = <Map<String, dynamic>>[];
    for (final raw in rawLines) {
      final line = raw.trim();
      if (line.isEmpty) continue;
      try {
        final decoded = jsonDecode(line);
        if (decoded is! Map) continue;
        out.add(Map<String, dynamic>.from(decoded));
      } catch (_) {
        // Ignore malformed legacy lines for cleanup operations.
      }
    }
    return out;
  }

  Future<void> _pruneLegacyForScope({
    required String tenantId,
    required String companyId,
  }) async {
    final legacyLedger = await _legacyFile();
    final legacyDirect = await _legacyLocalDirectHistoryFile();
    await _pruneLegacyFileForScope(
      file: legacyLedger,
      tenantId: tenantId,
      companyId: companyId,
    );
    await _pruneLegacyFileForScope(
      file: legacyDirect,
      tenantId: tenantId,
      companyId: companyId,
    );
  }

  Future<void> _pruneLegacyFileForScope({
    required File file,
    required String tenantId,
    required String companyId,
  }) async {
    final rows = await _readRawMaps(file);
    if (rows.isEmpty) return;
    final retained = rows
        .where((row) {
          final entry = ComplianceLedgerEntry.fromRaw(row, sourceLineIndex: -1);
          return !_entryMatchesScope(
            entry,
            tenantId: tenantId,
            companyId: companyId,
            allowLegacyWithoutScope: false,
          );
        })
        .toList(growable: false);
    if (retained.length == rows.length) return;
    final buffer = StringBuffer();
    for (final row in retained) {
      buffer.writeln(jsonEncode(row));
    }
    await file.writeAsString(buffer.toString(), flush: true);
  }

  Future<void> clearLocalTestData() async {
    if (kIsWeb) return;
    final scope = _activeComplianceScope();
    if (scope == null) {
      debugPrint(
        '[LOCAL_SCOPE][CLEANUP] target=compliance skipped=true reason=missing_tenant_company_scope',
      );
      return;
    }
    final tenantId = scope.tenantId.trim();
    final companyId = scope.companyId.trim();
    final ledgerFile = await _file();
    final localDirectFile = await _localDirectHistoryFile();
    if (ledgerFile == null || localDirectFile == null) return;
    if (!await ledgerFile.exists()) {
      await ledgerFile.create(recursive: true);
    }
    if (!await localDirectFile.exists()) {
      await localDirectFile.create(recursive: true);
    }
    await ledgerFile.writeAsString('', flush: true);
    await localDirectFile.writeAsString('', flush: true);
    await clearHiddenGroupKeys();
    await _pruneLegacyForScope(tenantId: tenantId, companyId: companyId);
    debugPrint(
      '[LOCAL_SCOPE][CLEANUP] target=compliance tenant=${_maskScope(tenantId)} company=${_maskScope(companyId)}',
    );
  }

  Future<
    ({
      List<ComplianceLedgerEntry> entries,
      bool fileExists,
      int skippedMalformedLines,
      bool useScoped,
    })?
  >
  _readScopedEntries({bool allowLegacyWithoutScope = false}) async {
    if (kIsWeb) return null;

    final scope = _activeComplianceScope();
    if (scope == null) return null;
    final tenantId = scope.tenantId.trim();
    final companyId = scope.companyId.trim();
    final scopedFile = await _file();
    if (scopedFile == null) return null;
    final legacyFile = await _legacyFile();
    final useScoped = await scopedFile.exists();
    final file = useScoped ? scopedFile : legacyFile;
    if (!await file.exists()) {
      return (
        entries: const <ComplianceLedgerEntry>[],
        fileExists: false,
        skippedMalformedLines: 0,
        useScoped: useScoped,
      );
    }

    final rawLines = await file.readAsLines();
    final parsed = <ComplianceLedgerEntry>[];
    var skippedMalformedLines = 0;

    for (var i = 0; i < rawLines.length; i++) {
      final line = rawLines[i].trim();
      if (line.isEmpty) continue;
      try {
        final decoded = jsonDecode(line);
        if (decoded is! Map) {
          skippedMalformedLines += 1;
          continue;
        }
        final map = Map<String, dynamic>.from(decoded);
        final entry = ComplianceLedgerEntry.fromRaw(map, sourceLineIndex: i);
        if (!_entryMatchesScope(
          entry,
          tenantId: tenantId,
          companyId: companyId,
          allowLegacyWithoutScope: allowLegacyWithoutScope,
        )) {
          continue;
        }
        parsed.add(entry);
      } catch (_) {
        skippedMalformedLines += 1;
      }
    }

    return (
      entries: parsed,
      fileExists: true,
      skippedMalformedLines: skippedMalformedLines,
      useScoped: useScoped,
    );
  }

  static int _compareEntriesNewestFirst(
    ComplianceLedgerEntry a,
    ComplianceLedgerEntry b,
  ) {
    int compareDateDesc(DateTime? left, DateTime? right) {
      if (left == null && right == null) return 0;
      if (left == null) return 1;
      if (right == null) return -1;
      return right.compareTo(left);
    }

    final byFinalized = compareDateDesc(a.finalizedAtUtc, b.finalizedAtUtc);
    if (byFinalized != 0) return byFinalized;
    final byCreated = compareDateDesc(a.createdAtUtc, b.createdAtUtc);
    if (byCreated != 0) return byCreated;
    return b.sourceLineIndex.compareTo(a.sourceLineIndex);
  }

  Future<ComplianceLedgerReadResult> readLatest({
    int limit = 20,
    bool allowLegacyWithoutScope = false,
  }) async {
    final read = await _readScopedEntries(
      allowLegacyWithoutScope: allowLegacyWithoutScope,
    );
    if (read == null) {
      return const ComplianceLedgerReadResult(
        entries: <ComplianceLedgerEntry>[],
        fileExists: false,
        skippedMalformedLines: 0,
      );
    }
    if (!read.fileExists) {
      return ComplianceLedgerReadResult(
        entries: read.entries,
        fileExists: false,
        skippedMalformedLines: read.skippedMalformedLines,
      );
    }

    final parsed = [...read.entries]..sort(_compareEntriesNewestFirst);
    final effectiveLimit = limit <= 0 ? 20 : limit;
    final latest = parsed.take(effectiveLimit).toList(growable: false);
    final scope = _activeComplianceScope();
    debugPrint(
      '[LOCAL_SCOPE][COMPLIANCE_FILTER] tenant=${_maskScope(scope?.tenantId ?? '')} company=${_maskScope(scope?.companyId ?? '')} source=${read.useScoped ? 'scoped' : 'legacy'} kept=${latest.length} malformed=${read.skippedMalformedLines}',
    );

    return ComplianceLedgerReadResult(
      entries: latest,
      fileExists: true,
      skippedMalformedLines: read.skippedMalformedLines,
    );
  }

  Future<ComplianceLedgerReadResult> readLatestGrouped({
    int groupLimit = 20,
    bool allowLegacyWithoutScope = false,
  }) async {
    final read = await _readScopedEntries(
      allowLegacyWithoutScope: allowLegacyWithoutScope,
    );
    if (read == null) {
      return const ComplianceLedgerReadResult(
        entries: <ComplianceLedgerEntry>[],
        fileExists: false,
        skippedMalformedLines: 0,
      );
    }
    if (!read.fileExists) {
      return ComplianceLedgerReadResult(
        entries: read.entries,
        fileExists: false,
        skippedMalformedLines: read.skippedMalformedLines,
      );
    }

    final grouped = <String, List<ComplianceLedgerEntry>>{};
    for (final entry in read.entries) {
      grouped
          .putIfAbsent(groupKeyFor(entry), () => <ComplianceLedgerEntry>[])
          .add(entry);
    }

    DateTime? newestInGroup(List<ComplianceLedgerEntry> group) {
      DateTime? newest;
      for (final entry in group) {
        final ts = entry.sortTimestamp;
        if (ts == null) continue;
        if (newest == null || ts.isAfter(newest)) newest = ts;
      }
      return newest;
    }

    final groups = grouped.entries.toList(growable: false)
      ..sort((a, b) {
        final aNewest = newestInGroup(a.value);
        final bNewest = newestInGroup(b.value);
        if (aNewest != null && bNewest != null) {
          final byTime = bNewest.compareTo(aNewest);
          if (byTime != 0) return byTime;
        } else if (aNewest != null) {
          return -1;
        } else if (bNewest != null) {
          return 1;
        }
        final aIndex = a.value
            .map((entry) => entry.sourceLineIndex)
            .fold<int>(0, (prev, next) => next > prev ? next : prev);
        final bIndex = b.value
            .map((entry) => entry.sourceLineIndex)
            .fold<int>(0, (prev, next) => next > prev ? next : prev);
        return bIndex.compareTo(aIndex);
      });

    final effectiveGroupLimit = groupLimit <= 0 ? 20 : groupLimit;
    final selectedGroups = groups.take(effectiveGroupLimit);
    final merged = <ComplianceLedgerEntry>[];
    for (final group in selectedGroups) {
      merged.addAll(group.value);
    }

    final scope = _activeComplianceScope();
    debugPrint(
      '[LOCAL_SCOPE][COMPLIANCE_FILTER] tenant=${_maskScope(scope?.tenantId ?? '')} company=${_maskScope(scope?.companyId ?? '')} source=${read.useScoped ? 'scoped' : 'legacy'} grouped=${selectedGroups.length} kept=${merged.length} malformed=${read.skippedMalformedLines}',
    );

    return ComplianceLedgerReadResult(
      entries: merged,
      fileExists: true,
      skippedMalformedLines: read.skippedMalformedLines,
    );
  }

  static const String _hiddenRegisterFileName =
      'local_ride_register_hidden_v1.json';

  static Future<File?> _hiddenRegisterFile() async {
    final scope = _activeComplianceScope();
    if (scope == null) return null;
    return _scopedHiddenRegisterFile(
      tenantId: scope.tenantId,
      companyId: scope.companyId,
    );
  }

  static Future<File> _scopedHiddenRegisterFile({
    required String tenantId,
    required String companyId,
  }) async {
    final root = await _rootDir();
    final scopedDir = Directory(
      '${root.path}${Platform.pathSeparator}compliance_state${Platform.pathSeparator}tenant_${_sanitizeScopeSegment(tenantId)}${Platform.pathSeparator}company_${_sanitizeScopeSegment(companyId)}',
    );
    if (!await scopedDir.exists()) {
      await scopedDir.create(recursive: true);
    }
    return File(
      '${scopedDir.path}${Platform.pathSeparator}$_hiddenRegisterFileName',
    );
  }

  Future<Set<String>> loadHiddenGroupKeys() async {
    if (kIsWeb) return <String>{};
    final file = await _hiddenRegisterFile();
    if (file == null || !await file.exists()) return <String>{};
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) return <String>{};
      final raw = decoded['hidden_group_keys'];
      if (raw is! List) return <String>{};
      return raw
          .map((value) => value.toString().trim())
          .where((value) => value.isNotEmpty)
          .toSet();
    } catch (_) {
      return <String>{};
    }
  }

  Future<void> hideGroupFromRegister(String groupKey) async {
    if (kIsWeb) return;
    final scope = _activeComplianceScope();
    if (scope == null) return;
    final normalized = groupKey.trim();
    if (normalized.isEmpty) return;
    final file = await _scopedHiddenRegisterFile(
      tenantId: scope.tenantId,
      companyId: scope.companyId,
    );
    final hidden = await loadHiddenGroupKeys();
    hidden.add(normalized);
    await file.writeAsString(
      jsonEncode(<String, dynamic>{
        'hidden_group_keys': hidden.toList(growable: false)..sort(),
      }),
      flush: true,
    );
    debugPrint('[LOCAL_RIDE_REGISTER][HIDE_LOCAL] key=$normalized');
  }

  Future<void> clearHiddenGroupKeys() async {
    if (kIsWeb) return;
    final scope = _activeComplianceScope();
    if (scope == null) return;
    final file = await _scopedHiddenRegisterFile(
      tenantId: scope.tenantId,
      companyId: scope.companyId,
    );
    if (await file.exists()) {
      await file.writeAsString(
        jsonEncode(const <String, dynamic>{'hidden_group_keys': <String>[]}),
        flush: true,
      );
    }
  }

  List<ComplianceLedgerEntry> _filterHiddenGroups(
    List<ComplianceLedgerEntry> entries,
    Set<String> hiddenGroupKeys,
  ) {
    if (hiddenGroupKeys.isEmpty) return entries;
    return entries
        .where((entry) => !hiddenGroupKeys.contains(groupKeyFor(entry)))
        .toList(growable: false);
  }

  static String entryDedupKey(
    ComplianceLedgerEntry entry, {
    String? backendKey,
  }) {
    final eventId = entry.eventId.trim();
    if (eventId.isNotEmpty) return 'event_id:${eventId.toLowerCase()}';
    final key = (backendKey ?? '').trim();
    if (key.isNotEmpty) return 'backend_key:${key.toLowerCase()}';
    final ts = entry.sortTimestamp?.toUtc().toIso8601String() ?? '';
    return [
      entry.eventType.trim().toLowerCase(),
      entry.bookingId.trim().toLowerCase(),
      entry.tripId.trim().toLowerCase(),
      entry.receiptReference.trim().toLowerCase(),
      entry.publicBookingReference.trim().toLowerCase(),
      ts,
      entry.paymentStatus.trim().toLowerCase(),
      entry.paymentMethod.trim().toLowerCase(),
      entry.lifecycleStatus.trim().toLowerCase(),
    ].join('|');
  }

  static Map<String, dynamic> backendEventToLedgerRaw(
    Map<String, dynamic> event, {
    required String tenantId,
    required String companyId,
  }) {
    Map<String, dynamic> asMap(Object? value) {
      if (value is Map) return Map<String, dynamic>.from(value);
      return const <String, dynamic>{};
    }

    String text(String key) => (event[key] ?? '').toString().trim();
    String? nestedText(Map<String, dynamic> map, String key) {
      final value = (map[key] ?? '').toString().trim();
      return value.isEmpty ? null : value;
    }

    final timestamps = asMap(event['timestamps']);
    final payment = asMap(event['payment']);
    final fare = asMap(event['fare']);
    final provenance = asMap(event['provenance']);
    final driver = asMap(event['driver']);
    final vehicle = asMap(event['vehicle']);
    final locations = asMap(event['locations']);
    final pickup = asMap(locations['pickup']);
    final dropoff = asMap(locations['dropoff']);

    final eventType = text('event_type').isEmpty
        ? 'unknown'
        : text('event_type');
    final backendKey = text('key');
    final eventId = text('event_id').isEmpty ? backendKey : text('event_id');
    final startedAt =
        nestedText(timestamps, 'started_at_utc') ??
        nestedText(timestamps, 'started_at');
    final stoppedAt =
        nestedText(timestamps, 'stopped_at_utc') ??
        nestedText(timestamps, 'stopped_at') ??
        nestedText(timestamps, 'event_at_utc');
    final paidAt =
        nestedText(timestamps, 'paid_at_utc') ??
        nestedText(payment, 'paid_at_utc') ??
        nestedText(payment, 'paid_at');
    final createdAt = text('created_at_utc').isEmpty
        ? (stoppedAt ?? paidAt ?? DateTime.now().toUtc().toIso8601String())
        : text('created_at_utc');

    var lifecycle = text('lifecycle_status');
    if (lifecycle.isEmpty) lifecycle = text('ride_status');
    if (lifecycle.isEmpty) lifecycle = text('status');
    if (eventType == 'ride_stop' && lifecycle == 'stopped') {
      lifecycle = 'completed';
    }
    if (eventType == 'payment_update') {
      lifecycle = 'payment_updated';
    }

    final publicBookingReference =
        ComplianceLedgerEntry._firstNonEmptyText(<Object?>[
          event['public_booking_reference'],
          event['publicBookingReference'],
          event['booking_reference'],
          event['bookingReference'],
          event['public_reference'],
          event['publicReference'],
        ]);
    final receiptReference = ComplianceLedgerEntry._firstNonEmptyText(<Object?>[
      event['receipt_reference'],
      event['receiptReference'],
    ]);
    final planningReference = ComplianceLedgerEntry._firstNonEmptyText(
      <Object?>[event['planning_reference'], event['planningReference']],
    );

    double? totalEur = ComplianceLedgerEntry._toDouble(fare['total_eur']);
    totalEur ??= ComplianceLedgerEntry._toDouble(fare['total_amount']);

    final paymentPayload = <String, dynamic>{
      if (nestedText(payment, 'status') != null) 'status': payment['status'],
      if (nestedText(payment, 'method') != null) 'method': payment['method'],
      if (nestedText(payment, 'source') != null) 'source': payment['source'],
      if (nestedText(payment, 'provider') != null)
        'provider': payment['provider'],
      if (nestedText(payment, 'payment_id') != null)
        'payment_id': payment['payment_id'],
      if (paidAt != null) 'paid_at_utc': paidAt,
    };

    return <String, dynamic>{
      'ledger_version': '1.0',
      'event_type': eventType,
      'event_id': eventId,
      '_backend_key': backendKey,
      'ride_id': text('ride_id'),
      'ride_type': text('ride_type'),
      'lifecycle_status': lifecycle,
      'tenant_id': text('tenant_id').isEmpty ? tenantId : text('tenant_id'),
      'company_id': text('company_id').isEmpty ? companyId : text('company_id'),
      'driver_id': nestedText(driver, 'driver_id') ?? text('driver_id'),
      'vehicle_id': nestedText(vehicle, 'vehicle_id') ?? text('vehicle_id'),
      'booking_id': text('booking_id'),
      'trip_id': text('trip_id'),
      'session_id': text('session_id'),
      'started_at_utc': startedAt,
      'ended_at_utc': stoppedAt,
      'created_at_utc': createdAt,
      'finalized_at_utc': stoppedAt ?? paidAt ?? createdAt,
      'distance_km': fare['distance_km'],
      'wait_seconds_total': fare['wait_seconds_total'],
      'pickup': pickup.isEmpty
          ? <String, dynamic>{}
          : <String, dynamic>{'label': pickup['label']},
      'dropoff': dropoff.isEmpty
          ? <String, dynamic>{}
          : <String, dynamic>{'label': dropoff['label']},
      'fare': <String, dynamic>{
        if (totalEur != null) 'total_eur': totalEur,
        'currency': (fare['currency'] ?? payment['currency'] ?? 'EUR')
            .toString()
            .trim(),
      },
      'payment': paymentPayload,
      'references': <String, dynamic>{
        if (receiptReference.isNotEmpty) 'receipt_reference': receiptReference,
        if (planningReference.isNotEmpty)
          'planning_reference': planningReference,
        if (publicBookingReference.isNotEmpty)
          'public_booking_reference': publicBookingReference,
      },
      'provenance': <String, dynamic>{
        ...provenance,
        'backend_confirmed': provenance['backend_confirmed'] ?? true,
        'validation_state':
            provenance['validation_state'] ??
            (eventType == 'payment_update' ? 'payment_update' : 'exportable'),
        'cache_source': 'backend_restore',
      },
    };
  }

  static List<ComplianceLedgerEntry> mergeLedgerEntries({
    required List<ComplianceLedgerEntry> localEntries,
    required List<ComplianceLedgerEntry> backendEntries,
  }) {
    final merged = <String, ComplianceLedgerEntry>{};
    for (final entry in localEntries) {
      final backendKey = ComplianceLedgerEntry._toStringOrEmpty(
        entry.raw['_backend_key'],
      );
      merged[entryDedupKey(entry, backendKey: backendKey)] = entry;
    }
    for (final entry in backendEntries) {
      final backendKey = ComplianceLedgerEntry._toStringOrEmpty(
        entry.raw['_backend_key'],
      );
      final key = entryDedupKey(entry, backendKey: backendKey);
      final existing = merged[key];
      if (existing == null || _compareEntriesNewestFirst(entry, existing) < 0) {
        merged[key] = entry;
      }
    }
    final out = merged.values.toList(growable: false)
      ..sort(_compareEntriesNewestFirst);
    return out;
  }

  ComplianceLedgerReadResult _groupedFromEntries({
    required List<ComplianceLedgerEntry> entries,
    required int groupLimit,
    required int skippedMalformedLines,
    required bool fileExists,
    int localCount = 0,
    int backendCount = 0,
    int mergedCount = 0,
    bool backendFetchOk = false,
    String? backendError,
    bool isSyncingBackend = false,
  }) {
    final grouped = <String, List<ComplianceLedgerEntry>>{};
    for (final entry in entries) {
      grouped
          .putIfAbsent(groupKeyFor(entry), () => <ComplianceLedgerEntry>[])
          .add(entry);
    }

    DateTime? newestInGroup(List<ComplianceLedgerEntry> group) {
      DateTime? newest;
      for (final entry in group) {
        final ts = entry.sortTimestamp;
        if (ts == null) continue;
        if (newest == null || ts.isAfter(newest)) newest = ts;
      }
      return newest;
    }

    final groups = grouped.entries.toList(growable: false)
      ..sort((a, b) {
        final aNewest = newestInGroup(a.value);
        final bNewest = newestInGroup(b.value);
        if (aNewest != null && bNewest != null) {
          final byTime = bNewest.compareTo(aNewest);
          if (byTime != 0) return byTime;
        } else if (aNewest != null) {
          return -1;
        } else if (bNewest != null) {
          return 1;
        }
        final aIndex = a.value
            .map((entry) => entry.sourceLineIndex)
            .fold<int>(0, (prev, next) => next > prev ? next : prev);
        final bIndex = b.value
            .map((entry) => entry.sourceLineIndex)
            .fold<int>(0, (prev, next) => next > prev ? next : prev);
        return bIndex.compareTo(aIndex);
      });

    final effectiveGroupLimit = groupLimit <= 0 ? 20 : groupLimit;
    final selectedGroups = groups.take(effectiveGroupLimit);
    final merged = <ComplianceLedgerEntry>[];
    for (final group in selectedGroups) {
      merged.addAll(group.value);
    }

    return ComplianceLedgerReadResult(
      entries: merged,
      fileExists: fileExists,
      skippedMalformedLines: skippedMalformedLines,
      localCount: localCount,
      backendCount: backendCount,
      mergedCount: mergedCount,
      backendFetchOk: backendFetchOk,
      backendError: backendError,
      isSyncingBackend: isSyncingBackend,
    );
  }

  Future<ComplianceLedgerReadResult> readLocalGrouped({
    int groupLimit = 20,
    bool allowLegacyWithoutScope = false,
  }) async {
    final read = await _readScopedEntries(
      allowLegacyWithoutScope: allowLegacyWithoutScope,
    );
    if (read == null) {
      return const ComplianceLedgerReadResult(
        entries: <ComplianceLedgerEntry>[],
        fileExists: false,
        skippedMalformedLines: 0,
      );
    }
    final hidden = await loadHiddenGroupKeys();
    final visible = _filterHiddenGroups(read.entries, hidden);
    debugPrint(
      '[LOCAL_RIDE_REGISTER][LOAD_LOCAL] count=${visible.length} hidden=${hidden.length}',
    );
    return _groupedFromEntries(
      entries: visible,
      groupLimit: groupLimit,
      skippedMalformedLines: read.skippedMalformedLines,
      fileExists: read.fileExists,
      localCount: visible.length,
      mergedCount: visible.length,
    );
  }

  /// CHIRON-P0-2A: backend Local Ride Register fetch. Routes through the
  /// booking worker's company-session authenticated proxy — the client no
  /// longer holds a direct compliance admin bearer.
  Future<({List<ComplianceLedgerEntry> entries, bool ok, String? error})>
  fetchBackendEntries({int limit = 100}) async {
    final scope = _activeComplianceScope();
    if (scope == null) {
      return (
        entries: const <ComplianceLedgerEntry>[],
        ok: false,
        error: 'missing_scope',
      );
    }
    debugPrint(
      '[LOCAL_RIDE_REGISTER][FETCH_BACKEND] scope=tenant:${_maskScope(scope.tenantId)} company:${_maskScope(scope.companyId)}',
    );

    if (!hasCompanyOwnerAuthContext()) {
      return (
        entries: const <ComplianceLedgerEntry>[],
        ok: false,
        error: 'missing_company_session',
      );
    }

    final base = appConfig.bookingBaseUrl.trim();
    if (base.isEmpty) {
      return (
        entries: const <ComplianceLedgerEntry>[],
        ok: false,
        error: 'missing_api_base_url',
      );
    }

    final uri = Uri.parse('$base/compliance/events/recent').replace(
      queryParameters: <String, String>{
        'tenant_id': scope.tenantId,
        'company_id': scope.companyId,
        'tenantId': scope.tenantId,
        'companyId': scope.companyId,
        'limit': '$limit',
      },
    );
    final auth = await resolveCompanyOwnerAuthHeaders(json: false);
    try {
      final res = await http
          .get(uri, headers: auth.headers)
          .timeout(const Duration(seconds: 12));
      Map<String, dynamic> asMap(Object? value) {
        if (value is Map) return Map<String, dynamic>.from(value);
        return const <String, dynamic>{};
      }

      final contentType = (res.headers['content-type'] ?? '').toLowerCase();
      Map<String, dynamic> payload = const <String, dynamic>{};
      if (contentType.contains('application/json') && res.body.isNotEmpty) {
        try {
          payload = asMap(jsonDecode(res.body));
        } catch (err) {
          debugPrint(
            '[LOCAL_RIDE_REGISTER][FETCH_RESULT] count=0 status=error error=json_parse_failed status_code=${res.statusCode}',
          );
        }
      }
      if (res.statusCode < 200 || res.statusCode >= 300) {
        final err = (payload['error'] ?? '').toString().trim();
        debugPrint(
          '[LOCAL_RIDE_REGISTER][FETCH_RESULT] count=0 status=error status_code=${res.statusCode} error=$err',
        );
        return (
          entries: const <ComplianceLedgerEntry>[],
          ok: false,
          error: err.isEmpty ? 'backend_fetch_failed' : err,
        );
      }

      final eventsRaw = payload['events'];
      final events = eventsRaw is List
          ? eventsRaw
                .whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e))
                .toList(growable: false)
          : const <Map<String, dynamic>>[];
      final parsed = <ComplianceLedgerEntry>[];
      for (var i = 0; i < events.length; i++) {
        final raw = backendEventToLedgerRaw(
          events[i],
          tenantId: scope.tenantId,
          companyId: scope.companyId,
        );
        parsed.add(ComplianceLedgerEntry.fromRaw(raw, sourceLineIndex: i));
      }
      debugPrint(
        '[LOCAL_RIDE_REGISTER][FETCH_RESULT] count=${parsed.length} status=ok',
      );
      return (entries: parsed, ok: true, error: null);
    } catch (err) {
      debugPrint(
        '[LOCAL_RIDE_REGISTER][FETCH_RESULT] count=0 status=error error=${err.runtimeType}',
      );
      return (
        entries: const <ComplianceLedgerEntry>[],
        ok: false,
        error: err.runtimeType.toString(),
      );
    }
  }

  Future<void> saveCacheEntries(List<ComplianceLedgerEntry> entries) async {
    if (kIsWeb) return;
    final scope = _activeComplianceScope();
    if (scope == null) return;
    final file = await _scopedFile(
      tenantId: scope.tenantId,
      companyId: scope.companyId,
    );
    if (!await file.parent.exists()) {
      await file.parent.create(recursive: true);
    }
    final buffer = StringBuffer();
    for (final entry in entries) {
      buffer.writeln(jsonEncode(entry.raw));
    }
    await file.writeAsString(buffer.toString(), flush: true);
    debugPrint('[LOCAL_RIDE_REGISTER][CACHE_SAVE] count=${entries.length}');
  }

  /// CHIRON-P0-2A: no more `apiBaseUrl` / `adminToken` — the backend fetch
  /// now routes through the booking worker with the active company-owner
  /// session bearer.
  Future<ComplianceLedgerReadResult> loadRegisterGrouped({
    required int groupLimit,
    bool allowLegacyWithoutScope = false,
    void Function(ComplianceLedgerReadResult localSnapshot)? onLocalLoaded,
  }) async {
    final localRead = await _readScopedEntries(
      allowLegacyWithoutScope: allowLegacyWithoutScope,
    );
    final hidden = await loadHiddenGroupKeys();
    final localEntries = localRead?.entries ?? const <ComplianceLedgerEntry>[];
    final visibleLocal = _filterHiddenGroups(localEntries, hidden);
    final localSnapshot = _groupedFromEntries(
      entries: visibleLocal,
      groupLimit: groupLimit,
      skippedMalformedLines: localRead?.skippedMalformedLines ?? 0,
      fileExists: localRead?.fileExists ?? false,
      localCount: visibleLocal.length,
      mergedCount: visibleLocal.length,
      isSyncingBackend: true,
    );
    onLocalLoaded?.call(localSnapshot);

    final backend = await fetchBackendEntries();
    if (!backend.ok) {
      return localSnapshot.copyWith(
        backendFetchOk: false,
        backendError: backend.error,
        isSyncingBackend: false,
      );
    }

    final mergedAll = mergeLedgerEntries(
      localEntries: localEntries,
      backendEntries: backend.entries,
    );
    debugPrint(
      '[LOCAL_RIDE_REGISTER][MERGE] local=${localEntries.length} backend=${backend.entries.length} merged=${mergedAll.length} deduped=${localEntries.length + backend.entries.length - mergedAll.length}',
    );
    await saveCacheEntries(mergedAll);

    final visibleMerged = _filterHiddenGroups(mergedAll, hidden);
    return _groupedFromEntries(
      entries: visibleMerged,
      groupLimit: groupLimit,
      skippedMalformedLines: localRead?.skippedMalformedLines ?? 0,
      fileExists: true,
      localCount: localEntries.length,
      backendCount: backend.entries.length,
      mergedCount: mergedAll.length,
      backendFetchOk: true,
      isSyncingBackend: false,
    );
  }
}

extension _ComplianceLedgerReadResultCopy on ComplianceLedgerReadResult {
  ComplianceLedgerReadResult copyWith({
    List<ComplianceLedgerEntry>? entries,
    bool? fileExists,
    int? skippedMalformedLines,
    int? localCount,
    int? backendCount,
    int? mergedCount,
    bool? backendFetchOk,
    String? backendError,
    bool? isSyncingBackend,
  }) {
    return ComplianceLedgerReadResult(
      entries: entries ?? this.entries,
      fileExists: fileExists ?? this.fileExists,
      skippedMalformedLines:
          skippedMalformedLines ?? this.skippedMalformedLines,
      localCount: localCount ?? this.localCount,
      backendCount: backendCount ?? this.backendCount,
      mergedCount: mergedCount ?? this.mergedCount,
      backendFetchOk: backendFetchOk ?? this.backendFetchOk,
      backendError: backendError ?? this.backendError,
      isSyncingBackend: isSyncingBackend ?? this.isSyncingBackend,
    );
  }
}
