import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class FluxidiAppLockStore {
  FluxidiAppLockStore._();

  static final FluxidiAppLockStore instance = FluxidiAppLockStore._();

  static const String _enabledKey = 'app_lock_enabled';
  static const String _pinHashKey = 'pin_hash';
  static const String _pinSaltKey = 'pin_salt';

  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  bool isValidPinFormat(String pin) {
    final normalized = pin.trim();
    return RegExp(r'^\d{4,6}$').hasMatch(normalized);
  }

  Future<bool> isEnabled() async {
    try {
      final value = (await _storage.read(key: _enabledKey) ?? '').trim();
      if (value.isEmpty) return true;
      return value.toLowerCase() == 'true';
    } catch (_) {
      return true;
    }
  }

  Future<bool> hasPin() async {
    try {
      final pinHash = (await _storage.read(key: _pinHashKey) ?? '').trim();
      final pinSalt = (await _storage.read(key: _pinSaltKey) ?? '').trim();
      return pinHash.isNotEmpty && pinSalt.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<void> setPin(String pin) async {
    final normalized = pin.trim();
    if (!isValidPinFormat(normalized)) {
      throw ArgumentError('PIN must be 4 to 6 digits.');
    }
    final salt = _generateSalt();
    final hash = _hashPin(normalized, salt);
    await _storage.write(key: _pinSaltKey, value: salt);
    await _storage.write(key: _pinHashKey, value: hash);
    await _storage.write(key: _enabledKey, value: 'true');
  }

  Future<bool> verifyPin(String pin) async {
    final normalized = pin.trim();
    if (!isValidPinFormat(normalized)) return false;
    try {
      final savedHash = (await _storage.read(key: _pinHashKey) ?? '').trim();
      final savedSalt = (await _storage.read(key: _pinSaltKey) ?? '').trim();
      if (savedHash.isEmpty || savedSalt.isEmpty) return false;
      final incomingHash = _hashPin(normalized, savedSalt);
      return incomingHash == savedHash;
    } catch (_) {
      return false;
    }
  }

  Future<void> disable() async {
    await _storage.delete(key: _pinHashKey);
    await _storage.delete(key: _pinSaltKey);
    await _storage.write(key: _enabledKey, value: 'false');
  }

  String _generateSalt() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return base64UrlEncode(bytes);
  }

  String _hashPin(String pin, String salt) {
    return sha256.convert(utf8.encode('$salt:$pin')).toString();
  }
}
