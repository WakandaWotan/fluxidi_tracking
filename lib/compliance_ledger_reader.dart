import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path_provider/path_provider.dart';

class ComplianceLedgerEntry {
  const ComplianceLedgerEntry({
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
    required this.invoiceReference,
    required this.validationState,
    required this.backendConfirmed,
    required this.pickupLabel,
    required this.dropoffLabel,
    required this.raw,
    required this.sourceLineIndex,
  });

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
  final String invoiceReference;
  final String validationState;
  final bool? backendConfirmed;
  final String pickupLabel;
  final String dropoffLabel;
  final Map<String, dynamic> raw;
  final int sourceLineIndex;

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
      rideId: readText('ride_id'),
      rideType: readText('ride_type'),
      lifecycleStatus: readText('lifecycle_status'),
      tenantId: readText('tenant_id'),
      companyId: readText('company_id'),
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
      receiptReference: _toStringOrEmpty(references['receipt_reference']),
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

  static Future<File> _file() async {
    final base = await getApplicationDocumentsDirectory();
    return File('${base.path}${Platform.pathSeparator}$fileName');
  }

  Future<ComplianceLedgerReadResult> readLatest({int limit = 20}) async {
    if (kIsWeb) {
      return const ComplianceLedgerReadResult(
        entries: <ComplianceLedgerEntry>[],
        fileExists: false,
        skippedMalformedLines: 0,
      );
    }

    final file = await _file();
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
        parsed.add(ComplianceLedgerEntry.fromRaw(map, sourceLineIndex: i));
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

    return ComplianceLedgerReadResult(
      entries: latest,
      fileExists: true,
      skippedMalformedLines: skippedMalformedLines,
    );
  }
}
