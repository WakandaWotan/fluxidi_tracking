import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'driver_pin_verified_session.dart';

class DriverPinCredential {
  const DriverPinCredential(
    this.companyCode,
    this.driverCode, [
    this.serverSession,
  ]);
  final String companyCode, driverCode;
  final DriverPinServerSession? serverSession;
}

/// Device-local convenience credential. Unlock never creates a driver session:
/// the caller must still authenticate with the normal server login endpoint.
class VehicleDriverPinStore {
  VehicleDriverPinStore({
    FlutterSecureStorage? storage,
    DateTime Function()? now,
  }) : _storage = storage ?? const FlutterSecureStorage(),
       _now = now ?? DateTime.now;

  final FlutterSecureStorage _storage;
  final DateTime Function() _now;

  String _key(Map<String, dynamic> binding, String driverId) {
    final scope = [
      'tenant_id',
      'company_id',
      'vehicle_id',
      'device_id',
    ].map((key) => binding[key]);
    if (driverId.trim().isEmpty ||
        scope.any((value) => value is! String || value.trim().isEmpty)) {
      throw StateError('vehicle_pin_scope_invalid');
    }
    return 'vehicle_driver_pin_v1_${sha256.convert(utf8.encode(jsonEncode([...scope, driverId])))}';
  }

  Future<Map<String, dynamic>?> _read(String key) async {
    final raw = await _storage.read(key: key);
    if (raw == null) return null;
    final value = jsonDecode(raw);
    if (value is! Map<String, dynamic> || value['version'] != 1) {
      throw StateError('vehicle_pin_storage_invalid');
    }
    return value;
  }

  Future<bool> hasPin(Map<String, dynamic> binding, String driverId) async =>
      await _read(_key(binding, driverId)) != null;

  /// Call only after a successful server login for this exact driver/scope.
  Future<void> enroll(
    Map<String, dynamic> binding,
    String driverId,
    String companyCode,
    String driverCode,
    String pin, {
    Future<bool> Function()? stillAuthorized,
  }) async {
    if (!RegExp(r'^\d{6}$').hasMatch(pin) ||
        companyCode.trim().isEmpty ||
        driverCode.trim().isEmpty) {
      throw ArgumentError('vehicle_pin_enrollment_invalid');
    }
    await _enrollCredential(
      binding,
      driverId,
      companyCode,
      driverCode,
      pin,
      stillAuthorized: stillAuthorized,
    );
  }

  Future<void> _enrollCredential(
    Map<String, dynamic> binding,
    String driverId,
    String companyCode,
    String driverCode,
    String pin, {
    DriverPinServerSession? serverSession,
    Future<bool> Function()? stillAuthorized,
  }) async {
    final salt = base64UrlEncode(
      List.generate(32, (_) => Random.secure().nextInt(256)),
    );
    final hash = await compute(_derivePin, [pin, salt]);
    if (stillAuthorized != null && !await stillAuthorized()) {
      throw StateError('vehicle_pin_authorization_changed');
    }
    await _storage.write(
      key: _key(binding, driverId),
      value: jsonEncode({
        'version': 1, 'salt': salt, 'hash': hash,
        // Both the PIN verifier and credential remain inside platform encrypted
        // storage; neither belongs in preferences, logs, or public responses.
        'company_code': companyCode, 'driver_code': driverCode,
        if (serverSession != null) 'server_session': serverSession.toJson(),
        'failures': 0, 'locked_until': 0,
      }),
    );
  }

  Future<({String companyCode, String driverCode})?> unlock(
    Map<String, dynamic> binding,
    String driverId,
    String pin,
  ) async {
    final credential = await unlockForLogin(binding, driverId, pin);
    if (credential == null || credential.serverSession != null) return null;
    return (
      companyCode: credential.companyCode,
      driverCode: credential.driverCode,
    );
  }

  Future<DriverPinCredential?> unlockForLogin(
    Map<String, dynamic> binding,
    String driverId,
    String pin,
  ) async {
    final key = _key(binding, driverId);
    final value = await _read(key);
    if (value == null) return null;
    if (value['locked_until'] is! int ||
        value['failures'] is! int ||
        value['salt'] is! String ||
        value['hash'] is! String ||
        value['company_code'] is! String ||
        value['driver_code'] is! String) {
      throw StateError('vehicle_pin_storage_invalid');
    }
    final now = _now().millisecondsSinceEpoch;
    if (value['locked_until'] > now) throw StateError('vehicle_pin_locked');
    final valid =
        RegExp(r'^\d{6}$').hasMatch(pin) &&
        _constantTimeEqual(
          await compute(_derivePin, [pin, value['salt'] as String]),
          value['hash'] as String,
        );
    if (!valid) {
      final failures =
          (value['locked_until'] > 0 ? 0 : value['failures'] as int) + 1;
      value['failures'] = failures;
      value['locked_until'] = failures >= 5
          ? now + const Duration(minutes: 15).inMilliseconds
          : 0;
      await _storage.write(key: key, value: jsonEncode(value));
      if (failures >= 5) throw StateError('vehicle_pin_locked');
      return null;
    }
    value['failures'] = 0;
    value['locked_until'] = 0;
    await _storage.write(key: key, value: jsonEncode(value));
    final rawSession = value['server_session'];
    final serverSession = rawSession == null
        ? null
        : DriverPinServerSession.fromJson(
            Map<String, dynamic>.from(rawSession as Map),
          );
    if (serverSession != null &&
        (serverSession.session.driverId != driverId ||
            serverSession.session.tenantId != binding['tenant_id'] ||
            serverSession.session.companyId != binding['company_id'] ||
            serverSession.session.companyCode != value['company_code'])) {
      throw StateError('personal_pin_scope_invalid');
    }
    return DriverPinCredential(
      value['company_code'] as String,
      value['driver_code'] as String,
      serverSession,
    );
  }

  Future<void> forget(Map<String, dynamic> binding, String driverId) =>
      _storage.delete(key: _key(binding, driverId));
}

/// Personal phone credential: scoped to the authenticated company and driver,
/// stored on this device only. It does not claim a vehicle-device pairing.
/// The same server login and PIN retry protection still apply.
class DriverPersonalPinStore extends VehicleDriverPinStore {
  DriverPersonalPinStore({super.storage, super.now});

  Future<void> enrollServerSession(
    DriverPinServerSession credential,
    String pin, {
    required Future<bool> Function() stillAuthorized,
  }) async {
    final session = credential.session;
    DriverPinServerSession.fromVerifiedSession(session);
    if (!RegExp(r'^\d{6}$').hasMatch(pin))
      throw ArgumentError('personal_pin_invalid');
    await _enrollCredential(
      {'tenant_id': session.tenantId, 'company_id': session.companyId},
      session.driverId,
      session.companyCode!,
      '',
      pin,
      serverSession: credential,
      stillAuthorized: stillAuthorized,
    );
  }

  @override
  String _key(Map<String, dynamic> binding, String driverId) {
    final scope = ['tenant_id', 'company_id'].map((key) => binding[key]);
    if (driverId.trim().isEmpty ||
        scope.any((value) => value is! String || value.trim().isEmpty)) {
      throw StateError('personal_pin_scope_invalid');
    }
    return 'driver_personal_pin_v1_${sha256.convert(utf8.encode(jsonEncode([...scope, driverId])))}';
  }

  Future<void> rememberDriver(
    Map<String, dynamic> scope,
    String driverId,
    String name,
  ) async {
    final key = _key(scope, driverId);
    final value = await _read(key);
    if (value == null) throw StateError('personal_pin_not_enrolled');
    await _storage.write(
      key: key,
      value: jsonEncode({
        ...value,
        'tenant_id': scope['tenant_id'],
        'company_id': scope['company_id'],
        'driver_id': driverId,
        'driver_name': name,
      }),
    );
    await _storage.write(
      key: 'driver_personal_pin_last_scope_v1',
      value: jsonEncode({
        'tenant_id': scope['tenant_id'],
        'company_id': scope['company_id'],
      }),
    );
  }

  /// Record only a server-verified identity, even when setup was declined or
  /// login used QR. This is a presentation hint, never a login credential.
  Future<void> rememberVerifiedDriver(
    Map<String, dynamic> scope,
    String driverId,
    String name,
    String companyCode,
  ) async {
    final key = _key(
      scope,
      driverId,
    ).replaceFirst('driver_personal_pin_v1_', 'driver_personal_choice_v1_');
    await _storage.write(
      key: key,
      value: jsonEncode({
        'version': 1,
        'tenant_id': scope['tenant_id'],
        'company_id': scope['company_id'],
        'driver_id': driverId,
        'driver_name': name,
        'company_code': companyCode,
      }),
    );
    await _storage.write(
      key: 'driver_personal_pin_last_scope_v1',
      value: jsonEncode({
        'tenant_id': scope['tenant_id'],
        'company_id': scope['company_id'],
      }),
    );
  }

  /// Only for recovery following fresh QR verification. The caller must still
  /// reauthenticate these credentials with the server and verify the exact
  /// driver/company before changing a PIN. This method grants no session.
  Future<({String companyCode, String driverCode})?>
  credentialsForReverification(
    Map<String, dynamic> scope,
    String driverId,
  ) async {
    final value = await _read(_key(scope, driverId));
    if (value == null ||
        value['server_session'] != null ||
        value['company_code'] is! String ||
        value['driver_code'] is! String)
      return null;
    return (
      companyCode: value['company_code'] as String,
      driverCode: value['driver_code'] as String,
    );
  }

  Future<Map<String, dynamic>?> preferredChoices() async {
    final raw = await _storage.read(key: 'driver_personal_pin_last_scope_v1');
    if (raw == null) return null;
    final scope = jsonDecode(raw);
    if (scope is! Map<String, dynamic>) return null;
    return rememberedChoices(scope);
  }

  /// Previously verified names are presentation only. Every unlock still goes
  /// through server authentication; cached names never grant fleet access.
  Future<Map<String, dynamic>?> rememberedChoices(
    Map<String, dynamic> scope,
  ) async {
    _key(scope, 'scope-validation');
    final drivers = <String, Map<String, String>>{};
    String companyCode = '';
    for (final entry in (await _storage.readAll()).entries) {
      final pinRecord = entry.key.startsWith('driver_personal_pin_v1_');
      final choiceRecord = entry.key.startsWith('driver_personal_choice_v1_');
      if (!pinRecord && !choiceRecord) continue;
      final value = await _read(entry.key);
      if (value == null ||
          value['tenant_id'] != scope['tenant_id'] ||
          value['company_id'] != scope['company_id'] ||
          value['driver_id'] is! String ||
          (value['driver_id'] as String).isEmpty ||
          value['driver_name'] is! String ||
          value['company_code'] is! String ||
          entry.key !=
              (choiceRecord
                  ? _key(scope, value['driver_id'] as String).replaceFirst(
                      'driver_personal_pin_v1_',
                      'driver_personal_choice_v1_',
                    )
                  : _key(scope, value['driver_id'] as String)))
        continue;
      drivers[value['driver_id'] as String] = {
        'driver_id': value['driver_id'] as String,
        'name': value['driver_name'] as String,
      };
      companyCode = value['company_code'] as String;
    }
    if (drivers.isEmpty) return null;
    return {
      'tenant_id': scope['tenant_id'],
      'company_id': scope['company_id'],
      'vehicle_id': '',
      'company_code': companyCode,
      'drivers': drivers.values.toList(),
    };
  }
}

String _derivePin(List<String> input) {
  final hmac = Hmac(sha256, utf8.encode(input[0]));
  var block = hmac.convert([...base64Url.decode(input[1]), 0, 0, 0, 1]).bytes;
  final result = List<int>.from(block);
  for (var iteration = 1; iteration < 100000; iteration++) {
    block = hmac.convert(block).bytes;
    for (var i = 0; i < result.length; i++) {
      result[i] ^= block[i];
    }
  }
  return base64UrlEncode(result);
}

bool _constantTimeEqual(String a, String b) {
  if (a.length != b.length) return false;
  var difference = 0;
  for (var i = 0; i < a.length; i++) {
    difference |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
  }
  return difference == 0;
}
