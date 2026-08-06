// GOOGLE-MAPS-DIRECT-LAUNCH-ANDROID-1
//
// Thin MethodChannel client for fluxidi.external_navigation.
// No tokens. Platform-specific; non-Android returns unavailable.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

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
      latitude != null &&
      longitude != null &&
      latitude!.isFinite &&
      longitude!.isFinite;

  bool get hasAddress => (address ?? '').trim().isNotEmpty;

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
    final raw = await _channel.invokeMethod<dynamic>('isGoogleMapsInstalled');
    return raw == true;
  }

  Future<bool> isPipSupported() async {
    if (!isAndroid) return false;
    final raw = await _channel.invokeMethod<dynamic>('isPipSupported');
    return raw == true;
  }

  Future<Map<String, dynamic>> launchGoogleNavigation(
    ExternalNavigationDestination destination, {
    String destinationSource = 'unknown',
  }) async {
    if (!isAndroid) {
      return <String, dynamic>{'ok': false, 'error': 'unsupported_platform'};
    }
    if (!destination.hasCoordinates && !destination.hasAddress) {
      return <String, dynamic>{'ok': false, 'error': 'missing_destination'};
    }
    final args = <String, Object?>{
      ...destination.toChannelArgs(),
      'destinationSource': destinationSource,
    };
    final raw = await _channel.invokeMethod<dynamic>(
      'launchGoogleNavigation',
      args,
    );
    return _asMap(raw);
  }

  /// Prepare PiP params (auto-enter on Android 12+) without entering yet.
  Future<Map<String, dynamic>> prepareFluxidiPipForHandoff() async {
    if (!isAndroid) {
      return <String, dynamic>{'ok': false, 'error': 'unsupported_platform'};
    }
    return _asMap(
      await _channel.invokeMethod<dynamic>('prepareFluxidiPipForHandoff'),
    );
  }

  Future<Map<String, dynamic>> enterFluxidiPip() async {
    if (!isAndroid) {
      return <String, dynamic>{'ok': false, 'error': 'unsupported_platform'};
    }
    return _asMap(await _channel.invokeMethod<dynamic>('enterFluxidiPip'));
  }

  Future<Map<String, dynamic>> exitFluxidiPip() async {
    if (!isAndroid) {
      return <String, dynamic>{'ok': false, 'error': 'unsupported_platform'};
    }
    return _asMap(await _channel.invokeMethod<dynamic>('exitFluxidiPip'));
  }

  Future<Map<String, dynamic>> updateFluxidiPip({
    Map<String, Object?>? meterSnapshot,
  }) async {
    if (!isAndroid) {
      return <String, dynamic>{'ok': false, 'error': 'unsupported_platform'};
    }
    return _asMap(
      await _channel.invokeMethod<dynamic>(
        'updateFluxidiPip',
        meterSnapshot ?? const <String, Object?>{},
      ),
    );
  }

  Future<Map<String, dynamic>> returnToFluxidi() async {
    if (!isAndroid) {
      return <String, dynamic>{'ok': false, 'error': 'unsupported_platform'};
    }
    return _asMap(await _channel.invokeMethod<dynamic>('returnToFluxidi'));
  }

  Future<Map<String, dynamic>> openGoogleMapsInstallPage() async {
    if (!isAndroid) {
      return <String, dynamic>{'ok': false, 'error': 'unsupported_platform'};
    }
    return _asMap(
      await _channel.invokeMethod<dynamic>('openGoogleMapsInstallPage'),
    );
  }

  Stream<Map<String, dynamic>> pipEvents() {
    if (!isAndroid) {
      return const Stream<Map<String, dynamic>>.empty();
    }
    return _events.receiveBroadcastStream().map(_asMap);
  }

  static Map<String, dynamic> _asMap(dynamic raw) {
    if (raw is Map) {
      return raw.map((key, value) => MapEntry(key.toString(), value));
    }
    return <String, dynamic>{'ok': false, 'error': 'invalid_channel_response'};
  }
}
