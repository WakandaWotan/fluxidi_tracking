import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class FluxidiAppLockStorageUnavailableException implements Exception {
  const FluxidiAppLockStorageUnavailableException();
}

class FluxidiAppLockState {
  const FluxidiAppLockState({
    required this.storageAvailable,
    required this.hasPin,
    required this.enabled,
  });

  final bool storageAvailable;
  final bool hasPin;
  final bool enabled;
}

class FluxidiPinVerifyResult {
  const FluxidiPinVerifyResult({
    required this.ok,
    required this.storageAvailable,
  });

  final bool ok;
  final bool storageAvailable;
}

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

  Future<FluxidiAppLockState> readState() async {
    try {
      final enabledRaw = (await _storage.read(key: _enabledKey) ?? '').trim();
      final pinHash = (await _storage.read(key: _pinHashKey) ?? '').trim();
      final pinSalt = (await _storage.read(key: _pinSaltKey) ?? '').trim();
      final hasPin = pinHash.isNotEmpty && pinSalt.isNotEmpty;
      final enabled = enabledRaw.isEmpty || enabledRaw.toLowerCase() == 'true';
      return FluxidiAppLockState(
        storageAvailable: true,
        hasPin: hasPin,
        enabled: enabled,
      );
    } catch (_) {
      return const FluxidiAppLockState(
        storageAvailable: false,
        hasPin: false,
        enabled: false,
      );
    }
  }

  Future<bool> isEnabled() async {
    final state = await readState();
    if (!state.storageAvailable) return false;
    return state.enabled;
  }

  Future<bool> hasPin() async {
    final state = await readState();
    if (!state.storageAvailable) return false;
    return state.hasPin;
  }

  Future<void> setPin(String pin) async {
    final normalized = pin.trim();
    if (!isValidPinFormat(normalized)) {
      throw ArgumentError('PIN must be 4 to 6 digits.');
    }
    final salt = _generateSalt();
    final hash = _hashPin(normalized, salt);
    try {
      await _storage.write(key: _pinSaltKey, value: salt);
      await _storage.write(key: _pinHashKey, value: hash);
      await _storage.write(key: _enabledKey, value: 'true');
    } catch (_) {
      throw const FluxidiAppLockStorageUnavailableException();
    }
  }

  Future<bool> verifyPin(String pin) async {
    final result = await verifyPinDetailed(pin);
    return result.ok;
  }

  Future<FluxidiPinVerifyResult> verifyPinDetailed(String pin) async {
    final normalized = pin.trim();
    if (!isValidPinFormat(normalized)) {
      return const FluxidiPinVerifyResult(ok: false, storageAvailable: true);
    }
    try {
      final savedHash = (await _storage.read(key: _pinHashKey) ?? '').trim();
      final savedSalt = (await _storage.read(key: _pinSaltKey) ?? '').trim();
      if (savedHash.isEmpty || savedSalt.isEmpty) {
        return const FluxidiPinVerifyResult(ok: false, storageAvailable: true);
      }
      final incomingHash = _hashPin(normalized, savedSalt);
      return FluxidiPinVerifyResult(
        ok: incomingHash == savedHash,
        storageAvailable: true,
      );
    } catch (_) {
      return const FluxidiPinVerifyResult(ok: false, storageAvailable: false);
    }
  }

  Future<void> disable() async {
    try {
      await _storage.delete(key: _pinHashKey);
      await _storage.delete(key: _pinSaltKey);
      await _storage.write(key: _enabledKey, value: 'false');
    } catch (_) {
      throw const FluxidiAppLockStorageUnavailableException();
    }
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
