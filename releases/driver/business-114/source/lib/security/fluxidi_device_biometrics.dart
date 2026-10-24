import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';

/// Outcome of one OS biometric attempt on the Business/Driver lock.
///
/// Success only means the device accepted an enrolled fingerprint or face.
/// The Fluxidi PIN and the stored company session stay the fallback.
enum FluxidiBiometricResult { success, canceled, failed, unavailable }

/// Device biometrics for the Business session lock.
///
/// The label and this API do not name Face ID. Android and iOS each show
/// whichever biometric the device has enrolled.
abstract class FluxidiDeviceBiometrics {
  Future<bool> isAvailable();

  Future<FluxidiBiometricResult> authenticate({required String reason});
}

/// Production unlock via [LocalAuthentication].
///
/// [AuthenticationOptions.biometricOnly] stays true so a device PIN cannot
/// replace the Fluxidi PIN. When the device has no enrolled biometric, the
/// keypad remains the way in.
class LocalAuthFluxidiDeviceBiometrics implements FluxidiDeviceBiometrics {
  LocalAuthFluxidiDeviceBiometrics({LocalAuthentication? auth})
    : _auth = auth ?? LocalAuthentication();

  final LocalAuthentication _auth;

  @override
  Future<bool> isAvailable() async {
    try {
      final supported = await _auth.isDeviceSupported();
      final canCheck = await _auth.canCheckBiometrics;
      if (!supported && !canCheck) return false;
      final enrolled = await _auth.getAvailableBiometrics();
      return enrolled.isNotEmpty;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<FluxidiBiometricResult> authenticate({required String reason}) async {
    try {
      if (!await isAvailable()) return FluxidiBiometricResult.unavailable;
      final ok = await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
          useErrorDialogs: true,
          sensitiveTransaction: true,
        ),
      );
      return ok
          ? FluxidiBiometricResult.success
          : FluxidiBiometricResult.canceled;
    } on MissingPluginException {
      return FluxidiBiometricResult.unavailable;
    } on PlatformException catch (error) {
      final code = error.code.toLowerCase();
      if (code.contains('cancel') ||
          code.contains('canceled') ||
          code.contains('cancelled')) {
        return FluxidiBiometricResult.canceled;
      }
      if (code.contains('notavailable') ||
          code.contains('not_available') ||
          code.contains('notenrolled') ||
          code.contains('not_enrolled') ||
          code.contains('passcode_not_set') ||
          code.contains('error_not_available') ||
          code.contains('error_not_enrolled')) {
        return FluxidiBiometricResult.unavailable;
      }
      return FluxidiBiometricResult.failed;
    } catch (_) {
      return FluxidiBiometricResult.failed;
    }
  }
}
