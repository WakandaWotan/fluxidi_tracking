// GOOGLE-MAPS-DIRECT-LAUNCH-ANDROID-1

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/navigation/external/external_navigation_host.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<MethodCall> log;
  late ExternalNavigationHost host;

  setUp(() {
    log = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel(kExternalNavigationChannel),
      (MethodCall call) async {
        log.add(call);
        switch (call.method) {
          case 'isGoogleMapsInstalled':
            return true;
          case 'isPipSupported':
            return true;
          case 'launchGoogleNavigation':
            return <String, dynamic>{
              'ok': true,
              'package': 'com.google.android.apps.maps',
              'drivingMode': true,
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

  test('destination prefers coordinates in channel args', () {
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

  test('launchGoogleNavigation sends driving destination args', () async {
    // Host gates on TargetPlatform; force android for this unit test.
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    final out = await host.launchGoogleNavigation(
      const ExternalNavigationDestination(latitude: 50.85, longitude: 4.35),
    );
    expect(out['ok'], isTrue);
    expect(out['package'], 'com.google.android.apps.maps');
    expect(out['drivingMode'], isTrue);
    expect(log.single.method, 'launchGoogleNavigation');
    final args = log.single.arguments as Map;
    expect(args['latitude'], 50.85);
    expect(args['longitude'], 4.35);
  });

  test('missing destination short-circuits without channel call', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    final out = await host.launchGoogleNavigation(
      const ExternalNavigationDestination(),
    );
    expect(out['error'], 'missing_destination');
    expect(log, isEmpty);
  });

  test('enterFluxidiPip and returnToFluxidi round-trip', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    expect((await host.enterFluxidiPip())['pipActive'], isTrue);
    expect((await host.returnToFluxidi())['ok'], isTrue);
    expect(log.map((c) => c.method), [
      'enterFluxidiPip',
      'returnToFluxidi',
    ]);
  });
}
