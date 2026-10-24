import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/driver/driver_ride_alert.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('fluxidi/vehicle_ride_alert');
  tearDown(() { debugDefaultTargetPlatformOverride = null; TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null); });
  test('Android foreground alert and stop use dedicated native channel without ride data', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final methods = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      methods.add(call.method); expect(call.arguments, isNull); return null;
    });
    await DriverRideAlert.play(); await DriverRideAlert.stop(); expect(methods, ['play', 'stop']);
  });
  test('unavailable alert platform does not throw into acceptance UI', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (_) async => throw PlatformException(code: 'fixture_unavailable'));
    await DriverRideAlert.play(); await DriverRideAlert.stop();
  });
}
