import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:fluxidi_tracking/navigation/driver_location_stream_owner.dart';
import 'package:fluxidi_tracking/navigation/driver_navigation_location_config.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late DriverLocationStreamOwner owner;
  late List<StreamController<geo.Position>> streams;
  late List<bool> modes;
  var valid = false, allowed = true, confirmed = true;
  var active = 0, maximum = 0, samples = 0, checks = 0;
  var clock = DateTime.now();
  setUp(() {
    streams = [];
    modes = [];
    valid = false;
    allowed = true;
    confirmed = true;
    active = 0;
    maximum = 0;
    samples = 0;
    checks = 0;
    clock = DateTime.now();
    owner = DriverLocationStreamOwner(
      observeLifecycle: false,
      now: () => clock,
      retryDelay: const Duration(milliseconds: 10),
      operationValid: () => valid,
      permissionReady: () async {
        checks++;
        return allowed;
      },
      foregroundConfirmed: () async => confirmed,
      onPosition: (_) => samples++,
      openStream: (foreground) {
        modes.add(foreground);
        final stream = StreamController<geo.Position>(
          onListen: () {
            active++;
            if (active > maximum) maximum = active;
          },
          onCancel: () async {
            active--;
          },
        );
        streams.add(stream);
        return stream.stream;
      },
    );
  });
  tearDown(() async {
    await owner.dispose();
    for (final s in streams) {
      await s.close();
    }
  });
  test(
    'assigned preview has no FGS; confirmed NAV promotes exactly once',
    () async {
      expect(await owner.ensure(foreground: false), isTrue);
      expect(modes, [false]);
      expect(owner.foreground, isFalse);
      expect(await owner.ensure(foreground: true), isFalse);
      valid = true;
      expect(await owner.ensure(foreground: true), isTrue);
      await Future.wait([
        owner.ensure(foreground: true),
        owner.ensure(foreground: true),
      ]);
      expect(modes, [false, true]);
      expect(active, 1);
      expect(maximum, 1);
      final settings =
          buildDriverActiveNavigationLocationSettingsFor(
                NavGpsPlatform.android,
                foregroundTask: true,
              )
              as geo.AndroidSettings;
      expect(settings.foregroundNotificationConfig?.enableWakeLock, isTrue);
      expect(
        (buildDriverActiveNavigationLocationSettingsFor(NavGpsPlatform.android)
                as geo.AndroidSettings)
            .foregroundNotificationConfig,
        isNull,
      );
    },
  );
  test(
    'Maps/background/screen-off and healthy resume retain one stream; START retains identity',
    () async {
      valid = true;
      await owner.ensure(foreground: true);
      final original = owner.subscription;
      owner.didChangeAppLifecycleState(AppLifecycleState.paused);
      expect(owner.uploadingAllowed, isTrue);
      owner.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await owner.ensure(
        foreground: true,
      ); // same operation after successful START
      expect(identical(owner.subscription, original), isTrue);
      expect(modes, [true]);
      expect(maximum, 1);
    },
  );
  for (final event in [
    'STOP',
    'cancel',
    'unassign',
    'reassignment',
    'context exit',
  ]) {
    test('$event invalidates uploads and releases subscription', () async {
      valid = true;
      await owner.ensure(foreground: true);
      valid = false;
      final stopped = owner.stop();
      expect(owner.uploadingAllowed, isFalse);
      await stopped;
      expect(active, 0);
      expect(owner.foreground, isFalse);
      owner.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(modes, [true]);
    });
  }
  for (final failure in ['error', 'done']) {
    test('stream $failure recovers once with still valid scope', () async {
      valid = true;
      await owner.ensure(foreground: true);
      if (failure == 'error') {
        streams.last.addError(StateError('provider'));
      } else {
        await streams.last.close();
      }
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(modes, [true, true]);
      expect(active, 1);
      expect(maximum, 1);
    });
  }
  test(
    'provider off/on retries are bounded; visible resume recovers exhausted stream',
    () async {
      valid = true;
      await owner.ensure(foreground: true);
      allowed = false;
      streams.last.addError(StateError('location disabled'));
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(checks, 4);
      expect(active, 0);
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(checks, 4);
      allowed = true;
      owner.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await owner.ensure(foreground: true);
      expect(active, 1);
      expect(maximum, 1);
    },
  );
  test('permission refusal creates no half-started subscription', () async {
    valid = true;
    allowed = false;
    expect(await owner.ensure(foreground: true), isFalse);
    expect(modes, isEmpty);
    expect(owner.uploadingAllowed, isFalse);
  });
  test(
    'background stream failure does not start FGS until visible resume',
    () async {
      valid = true;
      await owner.ensure(foreground: true);
      owner.didChangeAppLifecycleState(AppLifecycleState.paused);
      streams.last.addError(StateError('provider'));
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(active, 0);
      expect(modes, [true]);
      owner.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await owner.ensure(foreground: true);
      expect(modes, [true, true]);
    },
  );
  test(
    'non-producing stream is replaced on resume instead of assumed healthy',
    () async {
      valid = true;
      await owner.ensure(foreground: true);
      clock = clock.add(const Duration(seconds: 31));
      owner.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await owner.ensure(foreground: true);
      expect(modes, [true, true]);
      expect(maximum, 1);
    },
  );
  test(
    'native FGS acknowledgement is awaited and stop defeats late acknowledgement',
    () async {
      valid = true;
      confirmed = false;
      var completed = false;
      final pending = owner.ensure(foreground: true).then((v) {
        completed = true;
        return v;
      });
      await Future<void>.delayed(const Duration(milliseconds: 25));
      expect(completed, isFalse);
      final stopped = owner.stop();
      confirmed = true;
      expect(await pending, isFalse);
      await stopped;
      expect(active, 0);
      expect(owner.uploadingAllowed, isFalse);
    },
  );
  test('permission exception is fail-closed', () async {
    await owner.dispose();
    owner = DriverLocationStreamOwner(
      observeLifecycle: false,
      openStream: (_) => throw StateError('must not open'),
      permissionReady: () async => throw StateError('permission'),
      foregroundConfirmed: () async => true,
      operationValid: () => true,
      onPosition: (_) {},
    );
    expect(await owner.ensure(foreground: true), isFalse);
  });
}
