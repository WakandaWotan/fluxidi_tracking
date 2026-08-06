// ACTIVE-RIDE-DURABLE-RESTORE-P0-7
//
// Disk-durable snapshot of the active planned/street ride + external-nav
// session. Written before Google Maps handoff and on meter/lifecycle ticks so
// process death during PiP can restore the ride after cold start / PIN.

import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'external_navigation_session.dart';

class ActiveRideDurableSnapshot {
  const ActiveRideDurableSnapshot({
    required this.rideType,
    required this.bookingId,
    required this.startedAt,
    required this.updatedAt,
    this.parentBookingId,
    this.activeLegId,
    this.tripId,
    this.lifecyclePhase = 'active',
    this.lastLat,
    this.lastLon,
    this.trackedDistanceKm,
    this.waitingSeconds,
    this.currentOrFixedFare,
    this.paymentState,
    this.finalizePending = false,
    this.externalNavSession,
  });

  /// `street` or `planned`.
  final String rideType;
  final String bookingId;
  final String? parentBookingId;
  final String? activeLegId;
  final String? tripId;
  final String lifecyclePhase;
  final DateTime startedAt;
  final DateTime updatedAt;
  final double? lastLat;
  final double? lastLon;
  final double? trackedDistanceKm;
  final int? waitingSeconds;
  final double? currentOrFixedFare;
  final String? paymentState;
  final bool finalizePending;
  final ExternalNavigationSession? externalNavSession;

  bool get isStreet => rideType == 'street';
  bool get isPlanned => rideType == 'planned';

  Map<String, Object?> toJson() => <String, Object?>{
        'version': 1,
        'rideType': rideType,
        'bookingId': bookingId,
        'parentBookingId': parentBookingId,
        'activeLegId': activeLegId,
        'tripId': tripId,
        'lifecyclePhase': lifecyclePhase,
        'startedAt': startedAt.toUtc().toIso8601String(),
        'updatedAt': updatedAt.toUtc().toIso8601String(),
        'lastLat': lastLat,
        'lastLon': lastLon,
        'trackedDistanceKm': trackedDistanceKm,
        'waitingSeconds': waitingSeconds,
        'currentOrFixedFare': currentOrFixedFare,
        'paymentState': paymentState,
        'finalizePending': finalizePending,
        'externalNavSession': externalNavSession?.toJson(),
      };

  factory ActiveRideDurableSnapshot.fromJson(Map<String, dynamic> j) {
    final ext = j['externalNavSession'];
    return ActiveRideDurableSnapshot(
      rideType: (j['rideType'] as String?)?.trim() ?? 'planned',
      bookingId: (j['bookingId'] as String?)?.trim() ?? '',
      parentBookingId: (j['parentBookingId'] as String?)?.trim(),
      activeLegId: (j['activeLegId'] as String?)?.trim(),
      tripId: (j['tripId'] as String?)?.trim(),
      lifecyclePhase: (j['lifecyclePhase'] as String?)?.trim() ?? 'active',
      startedAt: DateTime.tryParse((j['startedAt'] as String?) ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      updatedAt: DateTime.tryParse((j['updatedAt'] as String?) ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      lastLat: (j['lastLat'] as num?)?.toDouble(),
      lastLon: (j['lastLon'] as num?)?.toDouble(),
      trackedDistanceKm: (j['trackedDistanceKm'] as num?)?.toDouble(),
      waitingSeconds: (j['waitingSeconds'] as num?)?.toInt(),
      currentOrFixedFare: (j['currentOrFixedFare'] as num?)?.toDouble(),
      paymentState: (j['paymentState'] as String?)?.trim(),
      finalizePending: j['finalizePending'] == true,
      externalNavSession: ext is Map
          ? ExternalNavigationSession.fromJson(ext.cast<String, dynamic>())
          : null,
    );
  }
}

class ActiveRideDurableSnapshotStore {
  static const String fileName = 'active_ride_snapshot_v1.json';

  static Future<File> _file({
    required String tenantId,
    required String companyId,
  }) async {
    final root = await getApplicationDocumentsDirectory();
    final dir = Directory(
      '${root.path}/fluxidi/active_ride/'
      'tenant_${tenantId.trim()}/company_${companyId.trim()}',
    );
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return File('${dir.path}/$fileName');
  }

  static Future<void> save({
    required String tenantId,
    required String companyId,
    required ActiveRideDurableSnapshot snapshot,
  }) async {
    if (tenantId.trim().isEmpty ||
        companyId.trim().isEmpty ||
        snapshot.bookingId.trim().isEmpty) {
      return;
    }
    final file = await _file(tenantId: tenantId, companyId: companyId);
    await file.writeAsString(jsonEncode(snapshot.toJson()), flush: true);
  }

  static Future<ActiveRideDurableSnapshot?> load({
    required String tenantId,
    required String companyId,
  }) async {
    try {
      final file = await _file(tenantId: tenantId, companyId: companyId);
      if (!await file.exists()) return null;
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final snap = ActiveRideDurableSnapshot.fromJson(
        decoded.cast<String, dynamic>(),
      );
      if (snap.bookingId.trim().isEmpty) return null;
      return snap;
    } catch (_) {
      return null;
    }
  }

  static Future<void> clear({
    required String tenantId,
    required String companyId,
  }) async {
    try {
      final file = await _file(tenantId: tenantId, companyId: companyId);
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }
}
