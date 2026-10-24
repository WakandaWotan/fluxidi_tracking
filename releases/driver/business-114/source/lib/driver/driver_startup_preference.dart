import 'dart:convert';
import 'dart:io';

import 'package:fluxidi_tracking/driver_session_store.dart';
import 'package:path_provider/path_provider.dart';

/// Only remembers which standalone role the user last chose. It contains no
/// bearer and never grants access; DriverSessionGatePage still probes the server.
class DriverStartupPreference {
  DriverStartupPreference({Directory? testRoot}) : _testRoot = testRoot;

  static final instance = DriverStartupPreference();
  static const _fileName = 'preferred_standalone_driver_v1.json';
  final Directory? _testRoot;

  Future<File> _file() async {
    final root = _testRoot ?? await getApplicationSupportDirectory();
    if (!await root.exists()) await root.create(recursive: true);
    return File('${root.path}${Platform.pathSeparator}$_fileName');
  }

  Future<PreferredStandaloneDriver?> load() async {
    try {
      final file = await _file();
      if (!await file.exists()) return null;
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) return null;
      return PreferredStandaloneDriver.fromJson(
        Map<String, dynamic>.from(decoded),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> markDriver(ActiveDriverSession? session) async {
    final preference = PreferredStandaloneDriver.fromSession(session);
    if (preference == null) return;
    try {
      await (await _file()).writeAsString(jsonEncode(preference.toJson()));
    } catch (_) {
      // A failed role hint must not destroy or replace the actual session.
    }
  }

  /// Remove only the captured driver's optional role hint during a switch.
  /// A replacement personal actor/preference is never cleared by this request.
  Future<bool> clearForDriverSwitch({
    required ActiveDriverSession expectedOwner,
    required bool Function() isCurrent,
  }) async {
    final expected = PreferredStandaloneDriver.fromSession(expectedOwner);
    bool current() {
      final actual = activeDriverSessionNotifier.value;
      return isCurrent() && expected != null && expected.matches(actual) &&
          actual?.assignedVehicleId == expectedOwner.assignedVehicleId &&
          actual?.driverSessionToken == expectedOwner.driverSessionToken;
    }
    if (!current()) return false;
    try {
      final file = await _file();
      if (!current()) return false;
      if (!file.existsSync()) return true;
      final decoded = jsonDecode(file.readAsStringSync());
      if (decoded is! Map) return false;
      final saved = PreferredStandaloneDriver.fromJson(Map<String, dynamic>.from(decoded));
      if (saved == null || !saved.matches(expectedOwner) || !current()) return false;
      // Keep the final owner/content check and this small metadata deletion in
      // one event-loop step so an async delete cannot erase a replacement hint.
      file.deleteSync();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> clear() async {
    try {
      final file = await _file();
      if (await file.exists()) await file.delete();
    } catch (_) {
      // The hint is optional; logout clears the bearer independently.
    }
  }
}

class PreferredStandaloneDriver {
  const PreferredStandaloneDriver({
    required this.tenantId,
    required this.companyId,
    required this.driverId,
  });

  final String tenantId;
  final String companyId;
  final String driverId;

  static PreferredStandaloneDriver? fromSession(ActiveDriverSession? session) {
    if (session == null ||
        !session.isStandaloneLoginSession ||
        (session.driverSessionToken ?? '').trim().isEmpty) {
      return null;
    }
    final tenantId = (session.tenantId ?? '').trim();
    final companyId = (session.companyId ?? '').trim();
    final driverId = session.driverId.trim();
    if (tenantId.isEmpty || companyId.isEmpty || driverId.isEmpty) return null;
    return PreferredStandaloneDriver(
      tenantId: tenantId,
      companyId: companyId,
      driverId: driverId,
    );
  }

  static PreferredStandaloneDriver? fromJson(Map<String, dynamic> json) {
    final tenantId = (json['tenant_id'] ?? '').toString().trim();
    final companyId = (json['company_id'] ?? '').toString().trim();
    final driverId = (json['driver_id'] ?? '').toString().trim();
    if (tenantId.isEmpty || companyId.isEmpty || driverId.isEmpty) return null;
    return PreferredStandaloneDriver(
      tenantId: tenantId,
      companyId: companyId,
      driverId: driverId,
    );
  }

  Map<String, String> toJson() => {
    'tenant_id': tenantId,
    'company_id': companyId,
    'driver_id': driverId,
  };

  bool matches(ActiveDriverSession? session) =>
      session != null &&
      session.isStandaloneLoginSession &&
      (session.driverSessionToken ?? '').trim().isNotEmpty &&
      tenantId == (session.tenantId ?? '').trim() &&
      companyId == (session.companyId ?? '').trim() &&
      driverId == session.driverId.trim();
}
