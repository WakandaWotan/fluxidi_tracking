import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../driver_session_store.dart';

/// Local presentation preference only; no authentication or availability data.
class DriverRideAlertPreferences {
  DriverRideAlertPreferences({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();
  final FlutterSecureStorage _storage;
  String? _key(ActiveDriverSession session) {
    if (!session.isStandaloneLoginSession ||
        [
          session.tenantId,
          session.companyId,
          session.driverId,
        ].any((s) => (s ?? '').trim().isEmpty))
      return null;
    return 'driver_ride_flash_v1_${sha256.convert(utf8.encode(jsonEncode([session.tenantId, session.companyId, session.driverId])))}';
  }

  Future<bool> flashlight(ActiveDriverSession session) async {
    final key = _key(session);
    if (key == null) return false;
    try {
      return await _storage.read(key: key) == 'enabled';
    } catch (_) {
      return false;
    }
  }

  Future<void> setFlashlight(ActiveDriverSession session, bool enabled) async {
    final key = _key(session);
    if (key == null) throw StateError('driver_scope_required');
    await _storage.write(key: key, value: enabled ? 'enabled' : 'disabled');
  }
}
