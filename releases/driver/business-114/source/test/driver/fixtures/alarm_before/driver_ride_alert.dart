import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

class DriverRideAlert {
  static const _channel = MethodChannel('fluxidi/vehicle_ride_alert');
  static bool _permissionRequested = false;
  static Future<bool> ensureNotifications() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return false;
    try {
      var status = await Permission.notification.status;
      if (!status.isGranted && !_permissionRequested) {
        _permissionRequested = true;
        status = await Permission.notification.request();
      }
      return status.isGranted;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> retainBackgroundDelivery(String token) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return false;
    try {
      if (await _channel.invokeMethod<bool>('backgroundReady', {
            'token': token,
          }) !=
          true)
        return false;
      return await _channel.invokeMethod<bool>('refreshOffers', {
            'token': token,
          }) ==
          true;
    } catch (_) {
      return false;
    }
  }

  static Future<void> presented(String id) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await _channel.invokeMethod<void>('presented', {'offer_id': id});
    } catch (_) {}
  }

  static Future<bool> takeInboxRequest() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return false;
    try {
      return await _channel.invokeMethod<bool>('takeInboxRequest') == true;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> torchAvailable() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return false;
    try {
      return await _channel.invokeMethod<bool>('torchAvailable') == true;
    } catch (_) {
      return false;
    }
  }

  static Future<void> play({
    bool flashlight = false,
    Map<String, Object?>? offerScope,
  }) async {
    try {
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
        await _channel.invokeMethod<void>('play', {
          ...?offerScope,
          'flashlight': flashlight,
        });
      } else {
        await SystemSound.play(SystemSoundType.alert);
        await HapticFeedback.heavyImpact();
      }
    } catch (_) {
      /* Alert failure must not submit or dismiss an offer. */
    }
  }

  static Future<void> stop() async {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      try {
        await _channel.invokeMethod<void>('stop');
      } catch (_) {}
    }
  }
}
