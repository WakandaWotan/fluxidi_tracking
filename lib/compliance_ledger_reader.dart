import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:fluxidi_tracking/company_session_store.dart';
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
  });

  final List<ComplianceLedgerEntry> entries;
  final bool fileExists;
  final int skippedMalformedLines;
}

class ComplianceLedgerReader {
  static const String fileName = 'compliance_ledger_v1.jsonl';
  static const String localDirectHistoryFileName =
      'local_direct_trip_history_v1.jsonl';

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
    await _pruneLegacyForScope(tenantId: tenantId, companyId: companyId);
    debugPrint(
      '[LOCAL_SCOPE][CLEANUP] target=compliance tenant=${_maskScope(tenantId)} company=${_maskScope(companyId)}',
    );
  }

  Future<ComplianceLedgerReadResult> readLatest({
    int limit = 20,
    bool allowLegacyWithoutScope = false,
  }) async {
    if (kIsWeb) {
      return const ComplianceLedgerReadResult(
        entries: <ComplianceLedgerEntry>[],
        fileExists: false,
        skippedMalformedLines: 0,
      );
    }

    final scope = _activeComplianceScope();
    if (scope == null) {
      return const ComplianceLedgerReadResult(
        entries: <ComplianceLedgerEntry>[],
        fileExists: false,
        skippedMalformedLines: 0,
      );
    }
    final tenantId = scope.tenantId.trim();
    final companyId = scope.companyId.trim();
    final scopedFile = await _file();
    if (scopedFile == null) {
      return const ComplianceLedgerReadResult(
        entries: <ComplianceLedgerEntry>[],
        fileExists: false,
        skippedMalformedLines: 0,
      );
    }
    final legacyFile = await _legacyFile();
    final useScoped = await scopedFile.exists();
    final file = useScoped ? scopedFile : legacyFile;
    if (!await file.exists()) {
      return const ComplianceLedgerReadResult(
        entries: <ComplianceLedgerEntry>[],
        fileExists: false,
        skippedMalformedLines: 0,
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

    int compareDateDesc(DateTime? a, DateTime? b) {
      if (a == null && b == null) return 0;
      if (a == null) return 1;
      if (b == null) return -1;
      return b.compareTo(a);
    }

    parsed.sort((a, b) {
      final byFinalized = compareDateDesc(a.finalizedAtUtc, b.finalizedAtUtc);
      if (byFinalized != 0) return byFinalized;
      final byCreated = compareDateDesc(a.createdAtUtc, b.createdAtUtc);
      if (byCreated != 0) return byCreated;
      return b.sourceLineIndex.compareTo(a.sourceLineIndex);
    });

    final effectiveLimit = limit <= 0 ? 20 : limit;
    final latest = parsed.take(effectiveLimit).toList(growable: false);
    debugPrint(
      '[LOCAL_SCOPE][COMPLIANCE_FILTER] tenant=${_maskScope(tenantId)} company=${_maskScope(companyId)} source=${useScoped ? 'scoped' : 'legacy'} kept=${latest.length} malformed=$skippedMalformedLines',
    );

    return ComplianceLedgerReadResult(
      entries: latest,
      fileExists: true,
      skippedMalformedLines: skippedMalformedLines,
    );
  }
}
