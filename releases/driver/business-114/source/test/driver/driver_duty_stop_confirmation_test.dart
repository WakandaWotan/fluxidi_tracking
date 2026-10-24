import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/driver/driver_duty_bridge.dart';
import 'package:fluxidi_tracking/driver_session_store.dart';

ActiveDriverSession actor(String id) => ActiveDriverSession(
  driverId: id,
  employeeNumber: 'fixture',
  fullName: 'Fixture',
  phone: '',
  loggedInAt: '',
  updatedAt: '',
  tenantId: 'fixture-tenant',
  companyId: 'fixture-company',
  assignedVehicleId: 'fixture-vehicle-$id',
  driverSessionToken: 'fixture-bearer-$id',
  linkMethod: 'public_driver_login',
  driverSessionExpiresAtUtc: DateTime.now()
      .toUtc()
      .add(const Duration(days: 1))
      .toIso8601String(),
);

Map<String, Object> nativeState(
  String state, {
  String activation = 'fixture-A',
}) => {
  'running': state == 'ready',
  'state': state,
  'activation_id': activation,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final calls = <MethodCall>[];
  void handler(Future<dynamic> Function(MethodCall) handle) {
    messenger.setMockMethodCallHandler(DriverDutyBridge.channel, (call) async {
      calls.add(call);
      return handle(call);
    });
  }

  setUp(() async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    handler(
      (call) async => call.method == 'status'
          ? {...nativeState('stopped'), 'reason': 'owner_not_current'}
          : true,
    );
    await DriverDutyBridge.stop();
    nativeDriverDutySessionNotifier.value = null;
    activeDriverSessionNotifier.value = null;
    await Future<void>.delayed(Duration.zero);
    calls.clear();
  });
  tearDown(() async {
    handler(
      (call) async => call.method == 'status'
          ? {...nativeState('stopped'), 'reason': 'owner_not_current'}
          : true,
    );
    await DriverDutyBridge.stop();
    nativeDriverDutySessionNotifier.value = null;
    activeDriverSessionNotifier.value = null;
    await Future<void>.delayed(Duration.zero);
    messenger.setMockMethodCallHandler(DriverDutyBridge.channel, null);
    debugDefaultTargetPlatformOverride = null;
  });

  test('retired GPS lease cannot auto-reclaim; explicit stop allows authenticated retry', () async {
    final owner = actor('A');
    nativeDriverDutySessionNotifier.value = owner;
    activeDriverSessionNotifier.value = owner;
    var state = 'stopped';
    var activation = '';
    var starts = 0;
    handler((call) async {
      if (call.method == 'status') return {
        ...nativeState(state, activation: activation),
        'reason': state == 'retired' ? 'location_owner_retired' : '',
      };
      if (call.method == 'running') return state == 'ready';
      if (call.method == 'start') {
        activation = (call.arguments as Map)['activation_id'] as String;
        starts++;
        state = 'ready';
        return true;
      }
      if (call.method == 'stop') { state = 'stopped'; return true; }
      return true;
    });
    final config = <String, Object>{
      'token': owner.driverSessionToken!,
      'booking': 'https://booking.example',
      'tracking': 'https://tracking.example',
      'accepted': true,
    };
    expect(await DriverDutyBridge.start(config), isTrue);
    final retired = activation;
    state = 'retired';
    for (var i = 0; i < 3; i++) {
      expect(await DriverDutyBridge.start(config), isFalse);
    }
    expect(starts, 1);
    expect(activation, retired);
    await DriverDutyBridge.stop(owner: owner);
    expect(await DriverDutyBridge.start(config), isTrue);
    expect(starts, 2);
    expect(activation, isNot(retired));
    expect(nativeDriverDutySessionNotifier.value, same(owner));
  });

  for (final state in ['ready', 'starting']) {
    test(
      '$state activation requires its exact positive native stop ACK',
      () async {
        final owner = actor('A');
        nativeDriverDutySessionNotifier.value = owner;
        activeDriverSessionNotifier.value = owner;
        handler(
          (call) async => call.method == 'status' ? nativeState(state) : true,
        );
        expect(await DriverDutyBridge.stopConfirmed(owner: owner), isTrue);
        final stops = calls.where((call) => call.method == 'stop').toList();
        expect(stops, hasLength(1));
        expect(stops.single.arguments, {'activation_id': 'fixture-A'});
        expect(nativeDriverDutySessionNotifier.value, same(owner));
        expect(activeDriverSessionNotifier.value, same(owner));
      },
    );
  }

  for (final ack in [false, null]) {
    test(
      'native stop ACK $ack preserves ownership and permits a confirmed retry',
      () async {
        final owner = actor('A');
        nativeDriverDutySessionNotifier.value = owner;
        activeDriverSessionNotifier.value = owner;
        var confirmed = false;
        handler(
          (call) async => call.method == 'status'
              ? nativeState('ready')
              : confirmed
              ? true
              : ack,
        );
        expect(await DriverDutyBridge.stopConfirmed(owner: owner), isFalse);
        expect(nativeDriverDutySessionNotifier.value, same(owner));
        expect(activeDriverSessionNotifier.value, same(owner));
        confirmed = true;
        expect(await DriverDutyBridge.stopConfirmed(owner: owner), isTrue);
        expect(calls.where((call) => call.method == 'stop'), hasLength(2));
      },
    );
  }

  for (final failure in ['platform', 'missing_plugin']) {
    test('$failure stop failure is not confirmation', () async {
      final owner = actor('A');
      nativeDriverDutySessionNotifier.value = owner;
      activeDriverSessionNotifier.value = owner;
      handler((call) async {
        if (call.method == 'status') return nativeState('ready');
        if (failure == 'platform')
          throw PlatformException(code: 'fixture-stop-failed');
        throw MissingPluginException('fixture');
      });
      expect(await DriverDutyBridge.stopConfirmed(owner: owner), isFalse);
      expect(nativeDriverDutySessionNotifier.value, same(owner));
      expect(activeDriverSessionNotifier.value, same(owner));
    });
  }

  test('invalid status cannot confirm or issue a global stop', () async {
    final owner = actor('A');
    nativeDriverDutySessionNotifier.value = owner;
    handler((call) async => true);
    expect(await DriverDutyBridge.stopConfirmed(owner: owner), isFalse);
    expect(calls.where((call) => call.method == 'stop'), isEmpty);
  });

  for (final state in ['stopped', 'failed']) {
    test(
      'explicit native $state confirms an idempotent no-owner logout',
      () async {
        final owner = actor('A');
        nativeDriverDutySessionNotifier.value = owner;
        var reads = 0;
        handler((call) async {
          reads++;
          return reads == 1
              ? {...nativeState('stopped'), 'reason': 'owner_not_current'}
              : nativeState(state);
        });
        expect(await DriverDutyBridge.stopConfirmed(owner: owner), isTrue);
        expect(calls, hasLength(2));
        expect(calls.every((call) => call.method == 'status'), isTrue);
        expect(calls.last.arguments, isNull);
      },
    );
  }

  test(
    'foreign native activation is neither stopped nor accepted as a no-op',
    () async {
      final owner = actor('A');
      nativeDriverDutySessionNotifier.value = owner;
      handler(
        (call) async => call.arguments == null
            ? nativeState('ready', activation: 'foreign-B')
            : {...nativeState('stopped'), 'reason': 'owner_not_current'},
      );
      expect(await DriverDutyBridge.stopConfirmed(owner: owner), isFalse);
      expect(calls.where((call) => call.method == 'stop'), isEmpty);
    },
  );

  test(
    'already selected replacement owner refuses the old stop request',
    () async {
      final old = actor('A');
      final replacement = actor('B');
      nativeDriverDutySessionNotifier.value = replacement;
      expect(await DriverDutyBridge.stopConfirmed(owner: old), isFalse);
      expect(calls, isEmpty);
      expect(nativeDriverDutySessionNotifier.value, same(replacement));
    },
  );

  test(
    'owner replacement during status cannot stop the replacement activation',
    () async {
      final owner = actor('A');
      nativeDriverDutySessionNotifier.value = owner;
      final pending = Completer<dynamic>();
      final queried = Completer<void>();
      handler((call) async {
        if (call.method == 'status' && !queried.isCompleted) {
          queried.complete();
          return pending.future;
        }
        return call.method == 'status'
            ? {...nativeState('stopped'), 'reason': 'owner_not_current'}
            : true;
      });
      final stopping = DriverDutyBridge.stopConfirmed(owner: owner);
      await queried.future;
      final replacement = actor('B');
      nativeDriverDutySessionNotifier.value = replacement;
      pending.complete(nativeState('ready'));
      expect(await stopping, isFalse);
      expect(calls.where((call) => call.method == 'stop'), isEmpty);
      expect(nativeDriverDutySessionNotifier.value, same(replacement));
    },
  );

  test(
    'delayed old positive ACK cannot clear a replacement activation',
    () async {
      final owner = actor('A');
      nativeDriverDutySessionNotifier.value = owner;
      var activation = 'fixture-A';
      final pending = Completer<bool>();
      final sent = Completer<void>();
      handler((call) async {
        if (call.method == 'status') {
          final expected = (call.arguments as Map?)?['expected_config'] as Map?;
          if (activation == 'replacement-B' && expected?['driver_id'] == 'A') {
            return {...nativeState('stopped'), 'reason': 'owner_not_current'};
          }
          return nativeState('ready', activation: activation);
        }
        if (call.method == 'stop' && !sent.isCompleted) {
          sent.complete();
          return pending.future;
        }
        return true;
      });
      final stopping = DriverDutyBridge.stopConfirmed(owner: owner);
      await sent.future;
      final replacement = actor('B');
      nativeDriverDutySessionNotifier.value = replacement;
      activation = 'replacement-B';
      expect(
        await DriverDutyBridge.start({
          'token': replacement.driverSessionToken!,
          'accepted': true,
        }),
        isTrue,
      );
      pending.complete(true);
      expect(await stopping, isFalse);
      calls.clear();
      expect(
        await DriverDutyBridge.start({
          'token': replacement.driverSessionToken!,
          'accepted': true,
        }),
        isTrue,
      );
      expect(calls.map((call) => call.method), ['status', 'running']);
      expect(nativeDriverDutySessionNotifier.value, same(replacement));
    },
  );

  test(
    'non-Android has no native publisher and performs no native calls',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      expect(await DriverDutyBridge.stopConfirmed(owner: actor('A')), isTrue);
      expect(calls, isEmpty);
    },
  );
}
