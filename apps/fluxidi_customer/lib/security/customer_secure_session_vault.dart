import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Encrypted at-rest store for the customer session JSON and the lock flag.
abstract class CustomerSecureSessionVault {
  Future<String?> readSessionJson();

  /// True only when a following read returns [json].
  Future<bool> writeSessionJson(String json);

  Future<void> deleteSession();

  Future<bool> readUnlockEnabled();

  /// True only when a following read returns [enabled].
  Future<bool> writeUnlockEnabled(bool enabled);
}

/// Platform keystore / keychain. Never logs the payload.
class PlatformCustomerSecureSessionVault implements CustomerSecureSessionVault {
  PlatformCustomerSecureSessionVault({FlutterSecureStorage? storage})
    : _storage =
          storage ??
          const FlutterSecureStorage(
            // A keystore read error must not wipe the session and the unlock
            // flag. The plugin default does that, and the next launch then
            // has nothing left to lock.
            aOptions: AndroidOptions(resetOnError: false),
          );

  static const String sessionKey = 'fluxidi.customer.session.v1';
  static const String enabledKey = 'fluxidi.customer.unlock.enabled.v1';

  final FlutterSecureStorage _storage;

  @override
  Future<String?> readSessionJson() async {
    try {
      final raw = await _storage.read(key: sessionKey);
      if (raw == null || raw.trim().isEmpty) return null;
      return raw;
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  @override
  Future<bool> writeSessionJson(String json) async {
    final payload = json.trim();
    if (payload.isEmpty) {
      await deleteSession();
      return (await readSessionJson()) == null;
    }
    try {
      await _storage.write(key: sessionKey, value: payload);
      return await readSessionJson() == payload;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<void> deleteSession() async {
    try {
      await _storage.delete(key: sessionKey);
    } on MissingPluginException {
      return;
    } on PlatformException {
      return;
    }
  }

  @override
  Future<bool> readUnlockEnabled() async {
    try {
      final raw = (await _storage.read(key: enabledKey) ?? '').trim();
      return raw == 'true';
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<bool> writeUnlockEnabled(bool enabled) async {
    try {
      await _storage.write(key: enabledKey, value: enabled ? 'true' : 'false');
      return await readUnlockEnabled() == enabled;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }
}

/// In-memory vault for tests.
class MemoryCustomerSecureSessionVault implements CustomerSecureSessionVault {
  String? sessionJson;
  bool unlockEnabled = false;

  @override
  Future<String?> readSessionJson() async => sessionJson;

  @override
  Future<bool> writeSessionJson(String json) async {
    sessionJson = json.trim().isEmpty ? null : json;
    return true;
  }

  @override
  Future<void> deleteSession() async {
    sessionJson = null;
  }

  @override
  Future<bool> readUnlockEnabled() async => unlockEnabled;

  @override
  Future<bool> writeUnlockEnabled(bool enabled) async {
    unlockEnabled = enabled;
    return true;
  }
}
