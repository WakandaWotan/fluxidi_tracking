// GOOGLE-MAPS-DIRECT-LAUNCH-ANDROID-1 / GOOGLE-MAPS-LAUNCH-CONTRACT-NOOP-P0-2

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/navigation/external/external_navigation_host.dart';
import 'package:fluxidi_tracking/navigation/external/google_maps_launch_contract.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<MethodCall> log;
  late ExternalNavigationHost host;
  late bool throwOnLaunch;

  setUp(() {
    log = <MethodCall>[];
    throwOnLaunch = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel(kExternalNavigationChannel),
      (MethodCall call) async {
        log.add(call);
        switch (call.method) {
          case 'isGoogleMapsInstalled':
            return true;
          case 'probeGoogleMapsAvailability':
            return <String, dynamic>{'installed': true, 'enabled': true};
          case 'isPipSupported':
            return true;
          case 'prepareFluxidiPipForHandoff':
            return <String, dynamic>{'ok': true, 'autoEnterPrepared': true};
          case 'launchGoogleNavigation':
            if (throwOnLaunch) {
              throw PlatformException(
                code: 'channel_boom',
                message: 'native failure',
              );
            }
            return <String, dynamic>{
              'ok': true,
              'status': 'launched',
              'package': 'com.google.android.apps.maps',
              'drivingMode': true,
              'launch_dispatched': true,
              'pip_supported': true,
              'maps_package_installed': true,
              'maps_package_enabled': true,
              'maps_intent_resolved': true,
            };
          case 'enterFluxidiPip':
            return <String, dynamic>{'ok': true, 'pipActive': true};
          case 'returnToFluxidi':
            return <String, dynamic>{'ok': true};
          case 'openGoogleMapsInstallPage':
            return <String, dynamic>{'ok': true, 'via': 'market'};
          default:
            return null;
        }
      },
    );
    host = ExternalNavigationHost();
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel(kExternalNavigationChannel),
      null,
    );
  });

  test('1) button path invokes platform channel', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    final out = await host.launchGoogleNavigationResult(
      const ExternalNavigationDestination(latitude: 50.85, longitude: 4.35),
    );
    expect(out.isSuccess, isTrue);
    expect(log.single.method, 'launchGoogleNavigation');
  });

  test('2) destination prefers coordinates in channel args', () {
    const dest = ExternalNavigationDestination(
      latitude: 51.05,
      longitude: 3.72,
      address: 'ignored when coords present for channel shape',
    );
    final args = dest.toChannelArgs();
    expect(args['latitude'], 51.05);
    expect(args['longitude'], 3.72);
    expect(args['address'], isNotNull);
  });

  test('3) launchGoogleNavigation sends driving destination args', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    final out = await host.launchGoogleNavigation(
      const ExternalNavigationDestination(latitude: 50.85, longitude: 4.35),
    );
    expect(out['ok'], isTrue);
    expect(out['status'], 'launched');
    expect(out['launch_dispatched'], isTrue);
    expect(out['package'], 'com.google.android.apps.maps');
    expect(out['drivingMode'], isTrue);
    expect(log.single.method, 'launchGoogleNavigation');
    final args = log.single.arguments as Map;
    expect(args['latitude'], 50.85);
    expect(args['longitude'], 4.35);
  });

  test('4) missing destination short-circuits without channel call', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    final out = await host.launchGoogleNavigationResult(
      const ExternalNavigationDestination(),
    );
    expect(out.status, GoogleMapsLaunchStatus.invalidDestination);
    expect(log, isEmpty);
  });

  test('5) PlatformException maps to visible native_exception result', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    throwOnLaunch = true;

    final out = await host.launchGoogleNavigationResult(
      const ExternalNavigationDestination(latitude: 51.0, longitude: 3.7),
    );
    expect(out.status, GoogleMapsLaunchStatus.nativeException);
    expect(out.failureCode, 'channel_boom');
    expect(out.isSuccess, isFalse);
  });

  test('6) enterFluxidiPip and returnToFluxidi round-trip', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    expect((await host.enterFluxidiPip())['pipActive'], isTrue);
    expect((await host.returnToFluxidi())['ok'], isTrue);
    expect(log.map((c) => c.method), [
      'enterFluxidiPip',
      'returnToFluxidi',
    ]);
  });

  test('7) handoff order: prepare then launch then enter PiP', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    await host.prepareFluxidiPipForHandoff();
    await host.launchGoogleNavigation(
      const ExternalNavigationDestination(latitude: 51.0, longitude: 3.7),
      destinationSource: 'pickup_a',
    );
    await host.enterFluxidiPip();
    expect(log.map((c) => c.method).toList(), [
      'prepareFluxidiPipForHandoff',
      'launchGoogleNavigation',
      'enterFluxidiPip',
    ]);
    final launchArgs = log[1].arguments as Map;
    expect(launchArgs['destinationSource'], 'pickup_a');
  });

  test('8) no silent no-op on channel failure (structured failure)', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    throwOnLaunch = true;
    final out = await host.launchGoogleNavigation(
      const ExternalNavigationDestination(latitude: 51.0, longitude: 3.7),
    );
    expect(out['ok'], isFalse);
    expect(out['status'], 'native_exception');
    expect(out['failure_code'], isNotNull);
  });
}
