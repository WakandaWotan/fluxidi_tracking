import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';

/// Outcome of one official OS unlock attempt.
enum CustomerUnlockResult {
  success,
  canceled,
  failed,
  unavailable,
}

/// Device-bound unlock: fingerprint or face when present, device PIN otherwise.
///
/// Always uses the operating system's own dialog. There is no Fluxidi PIN.
abstract class CustomerDeviceUnlock {
  Future<bool> canProtect();

  Future<CustomerUnlockResult> authenticate({required String reason});
}

/// Production unlock via [LocalAuthentication].
class LocalAuthCustomerDeviceUnlock implements CustomerDeviceUnlock {
  LocalAuthCustomerDeviceUnlock({LocalAuthentication? auth})
    : _auth = auth ?? LocalAuthentication();

  final LocalAuthentication _auth;

  @override
  Future<bool> canProtect() async {
    try {
      if (await _auth.isDeviceSupported()) return true;
      return await _auth.canCheckBiometrics;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<CustomerUnlockResult> authenticate({required String reason}) async {
    try {
      if (!await canProtect()) return CustomerUnlockResult.unavailable;
      final ok = await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          biometricOnly: false,
          stickyAuth: true,
          useErrorDialogs: true,
          sensitiveTransaction: true,
        ),
      );
      return ok ? CustomerUnlockResult.success : CustomerUnlockResult.canceled;
    } on MissingPluginException {
      return CustomerUnlockResult.unavailable;
    } on PlatformException catch (error) {
      final code = error.code.toLowerCase();
      if (code.contains('cancel') ||
          code.contains('canceled') ||
          code.contains('cancelled') ||
          code.contains('user_cancel') ||
          code.contains('usercancel')) {
        return CustomerUnlockResult.canceled;
      }
      if (code.contains('not_available') ||
          code.contains('notavailable') ||
          code.contains('not_enrolled') ||
          code.contains('passcode_not_set') ||
          code.contains('error_not_available') ||
          code.contains('error_not_enrolled')) {
        return CustomerUnlockResult.unavailable;
      }
      return CustomerUnlockResult.failed;
    } catch (_) {
      return CustomerUnlockResult.failed;
    }
  }
}

/// In-memory unlock for widget and unit tests.
class FakeCustomerDeviceUnlock implements CustomerDeviceUnlock {
  FakeCustomerDeviceUnlock({
    this.protects = true,
    this.result = CustomerUnlockResult.success,
  });

  bool protects;
  CustomerUnlockResult result;
  int authenticateCount = 0;
  String? lastReason;

  @override
  Future<bool> canProtect() async => protects;

  @override
  Future<CustomerUnlockResult> authenticate({required String reason}) async {
    authenticateCount += 1;
    lastReason = reason;
    if (!protects) return CustomerUnlockResult.unavailable;
    return result;
  }
}
