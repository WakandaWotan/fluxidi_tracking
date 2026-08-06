// GOOGLE-MAPS-DIRECT-LAUNCH-ANDROID-1 / GOOGLE-MAPS-LAUNCH-CONTRACT-NOOP-P0-2
//
// Thin MethodChannel client for fluxidi.external_navigation.
// No tokens. Platform-specific; non-Android returns unavailable.
// Channel failures are mapped to a structured launch result (never thrown).

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'google_maps_launch_contract.dart';

const String kExternalNavigationChannel = 'fluxidi.external_navigation';
const String kExternalNavigationEventsChannel =
    'fluxidi.external_navigation/events';

class ExternalNavigationDestination {
  const ExternalNavigationDestination({
    this.latitude,
    this.longitude,
    this.address,
  });

  final double? latitude;
  final double? longitude;
  final String? address;

  bool get hasCoordinates =>
      GoogleMapsDestinationValidator.hasValidCoordinates(this);

  bool get hasAddress =>
      GoogleMapsDestinationValidator.hasUsableAddress(address);

  Map<String, Object?> toChannelArgs() => <String, Object?>{
        if (hasCoordinates) 'latitude': latitude,
        if (hasCoordinates) 'longitude': longitude,
        if (hasAddress) 'address': address!.trim(),
      };
}

class ExternalNavigationHost {
  ExternalNavigationHost({
    MethodChannel? channel,
    EventChannel? events,
  })  : _channel = channel ?? const MethodChannel(kExternalNavigationChannel),
        _events = events ?? const EventChannel(kExternalNavigationEventsChannel);

  final MethodChannel _channel;
  final EventChannel _events;

  bool get isAndroid => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<bool> isGoogleMapsInstalled() async {
    if (!isAndroid) return false;
    try {
      final raw = await _channel.invokeMethod<dynamic>('isGoogleMapsInstalled');
      if (raw is Map) {
        return raw['installed'] == true;
      }
      return raw == true;
    } on PlatformException {
      return false;
    }
  }

  Future<Map<String, dynamic>> probeGoogleMapsAvailability() async {
    if (!isAndroid) {
      return <String, dynamic>{
        'installed': false,
        'enabled': false,
        'error': 'unsupported_platform',
      };
    }
    try {
      final raw = await _channel.invokeMethod<dynamic>('probeGoogleMapsAvailability');
      return _asMap(raw);
    } on PlatformException catch (e) {
      return <String, dynamic>{
        'installed': false,
        'enabled': false,
        'error': e.code,
        'message': e.message,
      };
    }
  }

  Future<bool> isPipSupported() async {
    if (!isAndroid) return false;
    try {
      final raw = await _channel.invokeMethod<dynamic>('isPipSupported');
      return raw == true;
    } on PlatformException {
      return false;
    }
  }

  Future<GoogleMapsLaunchResult> launchGoogleNavigationResult(
    ExternalNavigationDestination destination, {
    String destinationSource = 'unknown',
  }) async {
    if (!isAndroid) {
      return const GoogleMapsLaunchResult(
        status: GoogleMapsLaunchStatus.unsupportedPlatform,
        failureCode: 'unsupported_platform',
      );
    }
    if (!GoogleMapsDestinationValidator.isLaunchable(destination)) {
      return const GoogleMapsLaunchResult(
        status: GoogleMapsLaunchStatus.invalidDestination,
        failureCode: 'invalid_destination',
      );
    }
    final args = <String, Object?>{
      ...destination.toChannelArgs(),
      'destinationSource': destinationSource,
    };
    try {
      final raw = await _channel.invokeMethod<dynamic>(
        'launchGoogleNavigation',
        args,
      );
      return GoogleMapsLaunchResult.fromChannelMap(_asMap(raw));
    } on PlatformException catch (e) {
      return GoogleMapsLaunchResult(
        status: GoogleMapsLaunchStatus.nativeException,
        failureCode: e.code,
        message: e.message,
      );
    } catch (e) {
      return GoogleMapsLaunchResult(
        status: GoogleMapsLaunchStatus.nativeException,
        failureCode: 'native_exception',
        message: e.toString(),
      );
    }
  }

  /// Legacy map shape kept for older call sites/tests.
  Future<Map<String, dynamic>> launchGoogleNavigation(
    ExternalNavigationDestination destination, {
    String destinationSource = 'unknown',
  }) async {
    final result = await launchGoogleNavigationResult(
      destination,
      destinationSource: destinationSource,
    );
    return <String, dynamic>{
      'ok': result.isSuccess,
      'status': _statusWire(result.status),
      'failure_code': result.failureCode,
      'error': result.failureCode,
      'pip_supported': result.pipSupported,
      'launch_dispatched': result.launchDispatched,
      'maps_launch_dispatched': result.launchDispatched,
      'maps_package_installed': result.mapsPackageInstalled,
      'maps_package_enabled': result.mapsPackageEnabled,
      'maps_intent_resolved': result.mapsIntentResolved,
      'message': result.message,
      'uri': result.uri,
      if (result.isSuccess) 'package': 'com.google.android.apps.maps',
      if (result.isSuccess) 'drivingMode': true,
    };
  }

  /// Prepare PiP params (auto-enter on Android 12+) without entering yet.
  Future<Map<String, dynamic>> prepareFluxidiPipForHandoff() async {
    if (!isAndroid) {
      return <String, dynamic>{'ok': false, 'error': 'unsupported_platform'};
    }
    try {
      return _asMap(
        await _channel.invokeMethod<dynamic>('prepareFluxidiPipForHandoff'),
      );
    } on PlatformException catch (e) {
      return <String, dynamic>{
        'ok': false,
        'error': e.code,
        'message': e.message,
      };
    }
  }

  Future<Map<String, dynamic>> enterFluxidiPip() async {
    if (!isAndroid) {
      return <String, dynamic>{'ok': false, 'error': 'unsupported_platform'};
    }
    try {
      return _asMap(await _channel.invokeMethod<dynamic>('enterFluxidiPip'));
    } on PlatformException catch (e) {
      return <String, dynamic>{
        'ok': false,
        'error': e.code,
        'message': e.message,
      };
    }
  }

  Future<Map<String, dynamic>> exitFluxidiPip() async {
    if (!isAndroid) {
      return <String, dynamic>{'ok': false, 'error': 'unsupported_platform'};
    }
    try {
      return _asMap(await _channel.invokeMethod<dynamic>('exitFluxidiPip'));
    } on PlatformException catch (e) {
      return <String, dynamic>{
        'ok': false,
        'error': e.code,
        'message': e.message,
      };
    }
  }

  Future<Map<String, dynamic>> updateFluxidiPip({
    Map<String, Object?>? meterSnapshot,
  }) async {
    if (!isAndroid) {
      return <String, dynamic>{'ok': false, 'error': 'unsupported_platform'};
    }
    try {
      return _asMap(
        await _channel.invokeMethod<dynamic>(
          'updateFluxidiPip',
          meterSnapshot ?? const <String, Object?>{},
        ),
      );
    } on PlatformException catch (e) {
      return <String, dynamic>{
        'ok': false,
        'error': e.code,
        'message': e.message,
      };
    }
  }

  Future<Map<String, dynamic>> returnToFluxidi() async {
    if (!isAndroid) {
      return <String, dynamic>{'ok': false, 'error': 'unsupported_platform'};
    }
    try {
      return _asMap(await _channel.invokeMethod<dynamic>('returnToFluxidi'));
    } on PlatformException catch (e) {
      return <String, dynamic>{
        'ok': false,
        'error': e.code,
        'message': e.message,
      };
    }
  }

  Future<Map<String, dynamic>> openGoogleMapsInstallPage() async {
    if (!isAndroid) {
      return <String, dynamic>{'ok': false, 'error': 'unsupported_platform'};
    }
    try {
      return _asMap(
        await _channel.invokeMethod<dynamic>('openGoogleMapsInstallPage'),
      );
    } on PlatformException catch (e) {
      return <String, dynamic>{
        'ok': false,
        'error': e.code,
        'message': e.message,
      };
    }
  }

  Stream<Map<String, dynamic>> pipEvents() {
    if (!isAndroid) {
      return const Stream<Map<String, dynamic>>.empty();
    }
    return _events.receiveBroadcastStream().map(_asMap);
  }

  static String _statusWire(GoogleMapsLaunchStatus status) {
    switch (status) {
      case GoogleMapsLaunchStatus.launched:
        return 'launched';
      case GoogleMapsLaunchStatus.mapsNotInstalled:
        return 'maps_not_installed';
      case GoogleMapsLaunchStatus.mapsDisabled:
        return 'maps_disabled';
      case GoogleMapsLaunchStatus.invalidDestination:
        return 'invalid_destination';
      case GoogleMapsLaunchStatus.intentNotResolved:
        return 'intent_not_resolved';
      case GoogleMapsLaunchStatus.activityNotFound:
        return 'activity_not_found';
      case GoogleMapsLaunchStatus.securityException:
        return 'security_exception';
      case GoogleMapsLaunchStatus.cancelled:
        return 'cancelled';
      case GoogleMapsLaunchStatus.unsupportedPlatform:
        return 'unsupported_platform';
      case GoogleMapsLaunchStatus.nativeException:
        return 'native_exception';
    }
  }

  static Map<String, dynamic> _asMap(dynamic raw) {
    if (raw is Map) {
      return raw.map((key, value) => MapEntry(key.toString(), value));
    }
    return <String, dynamic>{
      'ok': false,
      'status': 'native_exception',
      'failure_code': 'invalid_channel_response',
      'error': 'invalid_channel_response',
    };
  }
}
