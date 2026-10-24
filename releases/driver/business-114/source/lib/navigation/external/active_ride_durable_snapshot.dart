// ACTIVE-RIDE-DURABLE-RESTORE-P0-7
//
// Disk-durable snapshot of the active planned/street ride + external-nav
// session. Written before Google Maps handoff and on meter/lifecycle ticks so
// process death during PiP can restore the ride after cold start / PIN.

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
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
    this.ownerDriverId,
    this.ownerVehicleId,
    this.backendConfirmed,
    this.navigationDestination,
    this.meterPricing,
    this.isWaiting = false,
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
  final String? ownerDriverId;
  final String? ownerVehicleId;
  final bool? backendConfirmed;
  final ExternalNavigationDestinationPoint? navigationDestination;
  final Map<String, dynamic>? meterPricing;
  final bool isWaiting;

  bool get isStreet => rideType == 'street';
  bool get isPlanned => rideType == 'planned';

  Map<String, Object?> toJson() => <String, Object?>{
    'version': 2,
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
    'ownerDriverId': ownerDriverId,
    'ownerVehicleId': ownerVehicleId,
    'backendConfirmed': backendConfirmed,
    'navigationDestination': navigationDestination?.toJson(),
    'meterPricing': meterPricing,
    'isWaiting': isWaiting,
  };

  factory ActiveRideDurableSnapshot.fromJson(Map<String, dynamic> j) {
    final ext = j['externalNavSession'];
    return ActiveRideDurableSnapshot(
      ownerDriverId: (j['ownerDriverId'] as String?)?.trim(),
      ownerVehicleId: (j['ownerVehicleId'] as String?)?.trim(),
      backendConfirmed: j['backendConfirmed'] is bool
          ? j['backendConfirmed'] as bool
          : null,
      navigationDestination: j['navigationDestination'] is Map
          ? ExternalNavigationDestinationPoint.fromJson(
              (j['navigationDestination'] as Map).cast<String, dynamic>(),
            )
          : null,
      meterPricing: j['meterPricing'] is Map
          ? (j['meterPricing'] as Map).cast<String, dynamic>()
          : null,
      isWaiting: j['isWaiting'] == true,
      rideType: (j['rideType'] as String?)?.trim() ?? 'planned',
      bookingId: (j['bookingId'] as String?)?.trim() ?? '',
      parentBookingId: (j['parentBookingId'] as String?)?.trim(),
      activeLegId: (j['activeLegId'] as String?)?.trim(),
      tripId: (j['tripId'] as String?)?.trim(),
      lifecyclePhase: (j['lifecyclePhase'] as String?)?.trim() ?? 'active',
      startedAt:
          DateTime.tryParse((j['startedAt'] as String?) ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      updatedAt:
          DateTime.tryParse((j['updatedAt'] as String?) ?? '') ??
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
  static const String restoreNoticeFileName =
      'active_ride_restore_notice_v1.txt';

  static String _restoreNoticeIdentity(
    String tenantId,
    String companyId,
    ActiveRideDurableSnapshot snapshot,
  ) => sha256
      .convert(
        utf8.encode(
          [
            tenantId.trim(),
            companyId.trim(),
            snapshot.bookingId.trim(),
            (snapshot.tripId ?? '').trim(),
            snapshot.startedAt.toUtc().toIso8601String(),
          ].join('\u0000'),
        ),
      )
      .toString();
  static final Map<String, Future<void>> _writes = {};

  static Future<void> _serialize(
    String key,
    Future<void> Function() action,
  ) async {
    final previous = _writes[key] ?? Future<void>.value();
    final next = previous.catchError((Object _) {}).then((_) => action());
    _writes[key] = next;
    try {
      await next;
    } finally {
      if (identical(_writes[key], next)) _writes.remove(key);
    }
  }

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
    await _serialize('${tenantId.trim()}/${companyId.trim()}', () async {
      final file = await _file(tenantId: tenantId, companyId: companyId);
      // Complete bytes before replacing the prior checkpoint. A process crash
      // during a write must leave the previous valid checkpoint readable.
      final pending = File('${file.path}.pending');
      await pending.writeAsString(jsonEncode(snapshot.toJson()), flush: true);
      await pending.rename(file.path);
    });
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

  /// Shows the unresolved-recovery warning once per ride across app restarts.
  /// The notice marker contains only a hash; the ride snapshot stays intact.
  static Future<bool> claimRestoreNotice({
    required String tenantId,
    required String companyId,
    required ActiveRideDurableSnapshot snapshot,
  }) async {
    if (tenantId.trim().isEmpty ||
        companyId.trim().isEmpty ||
        snapshot.bookingId.trim().isEmpty) {
      return true;
    }
    final identity = _restoreNoticeIdentity(tenantId, companyId, snapshot);
    var shouldShow = false;
    try {
      await _serialize('${tenantId.trim()}/${companyId.trim()}', () async {
        final snapshotFile = await _file(
          tenantId: tenantId,
          companyId: companyId,
        );
        if (!await snapshotFile.exists()) return;
        final currentJson = jsonDecode(await snapshotFile.readAsString());
        if (currentJson is! Map) return;
        final current = ActiveRideDurableSnapshot.fromJson(
          currentJson.cast<String, dynamic>(),
        );
        if (current.bookingId.trim() != snapshot.bookingId.trim() ||
            (current.tripId ?? '').trim() != (snapshot.tripId ?? '').trim() ||
            current.startedAt.toUtc() != snapshot.startedAt.toUtc()) {
          return;
        }
        final notice = File(
          '${snapshotFile.parent.path}/$restoreNoticeFileName',
        );
        if (await notice.exists() &&
            (await notice.readAsString()).trim() == identity) {
          return;
        }
        final pending = File('${notice.path}.pending');
        await pending.writeAsString(identity, flush: true);
        await pending.rename(notice.path);
        shouldShow = true;
      });
    } catch (_) {
      // If the marker cannot be saved, retain the safety warning.
      return true;
    }
    return shouldShow;
  }

  /// Give an unshown claim back when its screen was disposed during the write.
  /// The ride snapshot is never deleted, and a newer ride's marker is retained.
  static Future<void> releaseUnshownRestoreNotice({
    required String tenantId,
    required String companyId,
    required ActiveRideDurableSnapshot snapshot,
  }) async {
    if (tenantId.trim().isEmpty ||
        companyId.trim().isEmpty ||
        snapshot.bookingId.trim().isEmpty) {
      return;
    }
    final identity = _restoreNoticeIdentity(tenantId, companyId, snapshot);
    try {
      await _serialize('${tenantId.trim()}/${companyId.trim()}', () async {
        final snapshotFile = await _file(
          tenantId: tenantId,
          companyId: companyId,
        );
        if (!await snapshotFile.exists()) return;
        final currentJson = jsonDecode(await snapshotFile.readAsString());
        if (currentJson is! Map) return;
        final current = ActiveRideDurableSnapshot.fromJson(
          currentJson.cast<String, dynamic>(),
        );
        if (_restoreNoticeIdentity(tenantId, companyId, current) != identity) {
          return;
        }
        final notice = File(
          '${snapshotFile.parent.path}/$restoreNoticeFileName',
        );
        if (await notice.exists() &&
            (await notice.readAsString()).trim() == identity) {
          await notice.delete();
        }
      });
    } catch (_) {
      // A failed release leaves the one-time marker intact, never the ride.
    }
  }

  static Future<void> clear({
    required String tenantId,
    required String companyId,
  }) async {
    try {
      await _serialize('${tenantId.trim()}/${companyId.trim()}', () async {
        final file = await _file(tenantId: tenantId, companyId: companyId);
        if (await file.exists()) await file.delete();
        final notice = File('${file.parent.path}/$restoreNoticeFileName');
        if (await notice.exists()) await notice.delete();
      });
    } catch (_) {}
  }
}
