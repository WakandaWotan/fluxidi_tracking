import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/driver/driver_duty_bridge.dart';
import 'package:fluxidi_tracking/driver_session_store.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:fluxidi_tracking/app_config.dart' show normalizeDriverAvailabilityState;

ActiveDriverSession fixtureSession(String id, {String method = 'public_driver_login', String? token, String? vehicle}) => ActiveDriverSession(
  driverId: id, employeeNumber: '1', fullName: 'Test', phone: '', loggedInAt: '', updatedAt: '',
  tenantId: 'tenant', companyId: 'company', assignedVehicleId: vehicle ?? 'vehicle-$id',
  driverSessionToken: token ?? 'fixture-token-$id', linkMethod: method,
  driverSessionExpiresAtUtc: DateTime.now().toUtc().add(const Duration(days: 1)).toIso8601String(),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final calls = <String>[];
  setUp(() async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(DriverDutyBridge.channel, (call) async {
          calls.add(call.method);
          return true;
        });
    await DriverDutyBridge.stop();
    nativeDriverDutySessionNotifier.value = null;
    calls.clear();
  });
  tearDown(() async {
    await DriverDutyBridge.stop();
    nativeDriverDutySessionNotifier.value = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(DriverDutyBridge.channel, null);
    debugDefaultTargetPlatformOverride = null;
  });
  test(
    'repeated reconciliation does not restart an already running service',
    () async {
      final owner = fixtureSession('one');
      nativeDriverDutySessionNotifier.value = owner;
      final config = <String, Object>{
        'token': owner.driverSessionToken!,
        'accepted': true,
      };
      expect(await DriverDutyBridge.start(config), isTrue);
      expect(await DriverDutyBridge.start(config), isTrue);
      expect(calls.where((c) => c == 'start').length, 1);
      expect(calls, contains('running'));
    },
  );
  test('actual Booking busy heartbeat keeps the native lease and its foreground GPS proof', () async {
    final body = jsonDecode(File('android/app/src/test/resources/driver_duty_busy_heartbeat.json').readAsStringSync()) as Map;
    final status = normalizeDriverAvailabilityState(body['availability_status']);
    expect(status, 'busy');
    final owner = fixtureSession('one');
    activeDriverSessionNotifier.value = owner;
    nativeDriverDutySessionNotifier.value = owner;
    String? activation;
    Map? nativeConfig;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(DriverDutyBridge.channel, (call) async {
      calls.add(call.method);
      final args = call.arguments as Map?;
      if (call.method == 'status') {
        final expected = args?['expected_config'] as Map?;
        final matched = expected != null && nativeConfig != null &&
            ['token', 'tenant_id', 'company_id', 'driver_id', 'vehicle_id', 'booking', 'tracking']
                .every((key) => expected[key] == nativeConfig![key]);
        return {'running': activation != null && matched, 'activation_id': matched ? activation ?? '' : '', 'native_device_id': matched ? 'install' : ''};
      }
      if (call.method == 'start') { nativeConfig = args; activation = args!['activation_id'] as String; return true; }
      if (call.method == 'running') return activation != null;
      if (call.method == 'stop') { activation = null; return null; }
      return true;
    });
    final config = <String, Object>{'token': owner.driverSessionToken!, 'accepted': true,
      'booking': 'https://booking.example', 'tracking': 'https://tracking.example'};
    expect(await DriverDutyBridge.start(config), isTrue);
    final original = activation;
    calls.clear();
    if (DriverDutyBridge.availabilityAllowsGps(status)) {
      expect(await DriverDutyBridge.start(config), isTrue);
    } else {
      await DriverDutyBridge.stop(owner: owner);
    }
    expect(calls, isNot(contains('stop')));
    expect(activation, original);
    final sent = await DriverDutyBridge.sendGps(
      session: owner, payload: {'session_id': 'trip', 'lat': 51.16, 'lon': 4.14},
      bookingBaseUrl: 'https://booking.example', trackingBaseUrl: 'https://tracking.example', isCurrent: () => true,
      request: (payload, headers) async {
        expect(headers['Authorization'], 'Bearer ${owner.driverSessionToken}');
        return payload;
      },
    );
    expect(sent['activation_id'], original); expect(sent['native_device_id'], 'install');
    expect(body['availability_status'], 'busy');
    for (final stopped in ['paused', 'offline', 'inactive', 'unknown', '']) {
      expect(DriverDutyBridge.availabilityAllowsGps(stopped), isFalse);
    }
  });
  test(
    'changing or clearing the authenticated driver stops the task',
    () async {
      final session = fixtureSession('one');
      activeDriverSessionNotifier.value = session;
      nativeDriverDutySessionNotifier.value = session;
      await DriverDutyBridge.start({
        'token': session.driverSessionToken!,
        'accepted': true,
      });
      calls.clear();
      nativeDriverDutySessionNotifier.value = null;
      await Future<void>.delayed(Duration.zero);
      expect(calls, contains('stop'));
    },
  );
  test('company preview, dashboard and UI detach preserve the real owner', () async {
    final owner = fixtureSession('one');
    nativeDriverDutySessionNotifier.value = owner;
    await DriverDutyBridge.start({'token': owner.driverSessionToken!, 'accepted': true});
    calls.clear();
    activeDriverSessionNotifier.value = fixtureSession('other', method: kOperatorMintDriverLinkMethod);
    DriverSessionStore.instance.prepareBusinessDriverCockpitEntry();
    activeDriverSessionNotifier.value = null;
    await Future<void>.delayed(Duration.zero);
    expect(calls, isNot(contains('stop')));
    expect(nativeDriverDutySessionNotifier.value, same(owner));
  });
  test('operator preview alone cannot start a publisher', () async {
    final preview = fixtureSession('one', method: kOperatorMintDriverLinkMethod);
    activeDriverSessionNotifier.value = preview;
    nativeDriverDutySessionNotifier.value = preview;
    calls.clear();
    expect(await DriverDutyBridge.start({'token': preview.driverSessionToken!, 'accepted': true}), isFalse);
    expect(calls, isEmpty);
  });
  test('a failed native ready ACK remains false and can be retried', () async {
    final owner = fixtureSession('one');
    nativeDriverDutySessionNotifier.value = owner;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(DriverDutyBridge.channel, (call) async {
      calls.add(call.method);
      return false;
    });
    final config = {'token': owner.driverSessionToken!, 'accepted': true};
    expect(await DriverDutyBridge.start(config), isFalse);
    expect(await DriverDutyBridge.start(config), isFalse);
    expect(calls.where((c) => c == 'start').length, 2);
  });
  test('explicit pause stops activation while keeping verified pairing for resume', () async {
    final owner = fixtureSession('one');
    nativeDriverDutySessionNotifier.value = owner;
    final config = {'token': owner.driverSessionToken!, 'accepted': true};
    expect(await DriverDutyBridge.start(config), isTrue);
    await DriverDutyBridge.stop();
    expect(nativeDriverDutySessionNotifier.value, same(owner));
    expect(await DriverDutyBridge.start(config), isTrue);
    expect(calls.where((c) => c == 'start').length, 2);
  });
  test('late old start ACK stops only its activation, not the new owner', () async {
    final pending = Completer<bool>();
    final arguments = <Map<dynamic, dynamic>?>[];
    var starts = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(DriverDutyBridge.channel, (call) async {
      if (call.method == 'start') {
        arguments.add(call.arguments as Map);
        return ++starts == 1 ? pending.future : true;
      }
      if (call.method == 'stop') arguments.add(call.arguments as Map?);
      return true;
    });
    final first = fixtureSession('one');
    nativeDriverDutySessionNotifier.value = first;
    final oldStart = DriverDutyBridge.start({'token': first.driverSessionToken!, 'accepted': true});
    await Future<void>.delayed(Duration.zero);
    final second = fixtureSession('two');
    nativeDriverDutySessionNotifier.value = second;
    await Future<void>.delayed(Duration.zero);
    expect(await DriverDutyBridge.start({'token': second.driverSessionToken!, 'accepted': true}), isTrue);
    pending.complete(true);
    expect(await oldStart, isFalse);
    final oldActivation = arguments.first!['activation_id'];
    expect(arguments.last, {'activation_id': oldActivation});
    expect(nativeDriverDutySessionNotifier.value, same(second));
  });
  test('concurrent starts for the same owner cannot accept an older ACK', () async {
    final firstAck = Completer<bool>();
    var starts = 0;
    final owner = fixtureSession('one');
    nativeDriverDutySessionNotifier.value = owner;
    final cleanup = <Map<dynamic, dynamic>>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(DriverDutyBridge.channel, (call) async {
      if (call.method == 'start') return ++starts == 1 ? firstAck.future : true;
      if (call.method == 'running') return false;
      if (call.method == 'stop' && call.arguments is Map) cleanup.add(call.arguments as Map);
      return true;
    });
    final config = {'token': owner.driverSessionToken!, 'accepted': true};
    final oldStart = DriverDutyBridge.start(config);
    await Future<void>.delayed(Duration.zero);
    expect(await DriverDutyBridge.start(config), isTrue);
    firstAck.complete(true);
    expect(await oldStart, isFalse);
    expect(cleanup.single.keys, ['activation_id']);
  });
  test('same bearer with another assigned vehicle reconfigures the native owner', () async {
    final startArgs = <Map<dynamic, dynamic>>[];
    final stopArgs = <Map<dynamic, dynamic>>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(DriverDutyBridge.channel, (call) async {
      if (call.method == 'status') return {'running': false};
      if (call.method == 'start') startArgs.add(call.arguments as Map);
      if (call.method == 'stop') stopArgs.add(call.arguments as Map);
      return true;
    });
    final first = fixtureSession('one', vehicle: 'vehicle-A');
    nativeDriverDutySessionNotifier.value = first;
    final config = {'token': first.driverSessionToken!, 'accepted': true};
    expect(await DriverDutyBridge.start(config), isTrue);
    final replacement = fixtureSession('one', vehicle: 'vehicle-B');
    nativeDriverDutySessionNotifier.value = replacement;
    await Future<void>.delayed(Duration.zero);
    expect(await DriverDutyBridge.start(config), isTrue);
    expect(startArgs.map((a) => a['vehicle_id']), ['vehicle-A', 'vehicle-B']);
    expect(startArgs[0]['activation_id'], isNot(startArgs[1]['activation_id']));
    expect(stopArgs.single, {'activation_id': startArgs[0]['activation_id']});
  });
  test('same authenticated identity with refreshed metadata keeps its activation', () async {
    final owner = fixtureSession('one');
    nativeDriverDutySessionNotifier.value = owner;
    final config = {'token': owner.driverSessionToken!, 'accepted': true};
    expect(await DriverDutyBridge.start(config), isTrue);
    nativeDriverDutySessionNotifier.value = fixtureSession('one');
    expect(await DriverDutyBridge.start(config), isTrue);
    expect(calls.where((c) => c == 'start'), hasLength(1));
    expect(calls, isNot(contains('stop')));
  });
  test('cold restore adopts only the exact matched ready activation', () async {
    final owner = fixtureSession('one');
    nativeDriverDutySessionNotifier.value = owner;
    Map<dynamic, dynamic>? queried;
    final stopArgs = <Map<dynamic, dynamic>>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(DriverDutyBridge.channel, (call) async {
      calls.add(call.method);
      if (call.method == 'status') {
        queried = (call.arguments as Map)['expected_config'] as Map;
        return {'running': true, 'activation_id': 'restored-owned-activation'};
      }
      if (call.method == 'stop') stopArgs.add(call.arguments as Map);
      return true;
    });
    expect(await DriverDutyBridge.start({'token': owner.driverSessionToken!, 'accepted': true}), isTrue);
    expect(queried, containsPair('tenant_id', 'tenant'));
    expect(queried, containsPair('company_id', 'company'));
    expect(queried, containsPair('driver_id', 'one'));
    expect(queried, containsPair('vehicle_id', 'vehicle-one'));
    expect(queried, containsPair('token', owner.driverSessionToken));
    expect(queried!.keys, containsAll(['booking', 'tracking']));
    expect(calls, isNot(contains('start')));
    await DriverDutyBridge.stop();
    expect(stopArgs.single, {'activation_id': 'restored-owned-activation'});
  });
  test('a mismatched native restore is not adopted or stopped implicitly', () async {
    final owner = fixtureSession('one');
    nativeDriverDutySessionNotifier.value = owner;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(DriverDutyBridge.channel, (call) async {
      calls.add(call.method);
      if (call.method == 'status') return {'running': false, 'activation_id': '', 'reason': 'owner_not_current'};
      return true;
    });
    await DriverDutyBridge.stop(owner: owner);
    expect(calls, isNot(contains('stop')));
    expect(await DriverDutyBridge.start({'token': owner.driverSessionToken!, 'accepted': true}), isTrue);
    expect(calls.where((c) => c == 'start'), hasLength(1));
  });
  test('a delayed old STOP completion cannot affect a newer ready owner', () async {
    final delayedStop = Completer<void>();
    String? oldActivation;
    String? nativeActivation;
    var firstStop = true;
    final stopArgs = <Map<dynamic, dynamic>>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(DriverDutyBridge.channel, (call) async {
      if (call.method == 'status') return {'running': false};
      if (call.method == 'start') {
        nativeActivation = (call.arguments as Map)['activation_id'] as String;
        oldActivation ??= nativeActivation;
        return true;
      }
      if (call.method == 'stop') {
        final arguments = call.arguments as Map;
        stopArgs.add(arguments);
        if (firstStop) {
          firstStop = false;
          await delayedStop.future;
        }
        if (arguments['activation_id'] == nativeActivation) nativeActivation = null;
      }
      return true;
    });
    final owner = fixtureSession('one');
    nativeDriverDutySessionNotifier.value = owner;
    expect(await DriverDutyBridge.start({'token': owner.driverSessionToken!, 'accepted': true}), isTrue);
    final stopping = DriverDutyBridge.stop();
    await Future<void>.delayed(Duration.zero);
    final replacement = fixtureSession('two');
    nativeDriverDutySessionNotifier.value = replacement;
    expect(await DriverDutyBridge.start({'token': replacement.driverSessionToken!, 'accepted': true}), isTrue);
    final replacementActivation = nativeActivation;
    delayedStop.complete();
    await stopping;
    expect(stopArgs.single, {'activation_id': oldActivation});
    expect(nativeActivation, replacementActivation);
    expect(nativeActivation, isNotNull);
  });
  test('a late old actor stop request never captures the replacement activation', () async {
    final first = fixtureSession('one');
    nativeDriverDutySessionNotifier.value = first;
    expect(await DriverDutyBridge.start({'token': first.driverSessionToken!, 'accepted': true}), isTrue);
    final second = fixtureSession('two');
    nativeDriverDutySessionNotifier.value = second;
    await Future<void>.delayed(Duration.zero);
    expect(await DriverDutyBridge.start({'token': second.driverSessionToken!, 'accepted': true}), isTrue);
    calls.clear();
    await DriverDutyBridge.stop(owner: first);
    expect(calls, isEmpty);
    expect(await DriverDutyBridge.start({'token': second.driverSessionToken!, 'accepted': true}), isTrue);
    // Reconciliation reads retirement status before checking readiness. Both
    // are read-only; a delayed foreign stop must cause no stop or new start.
    expect(calls, ['status', 'running']);
  });
  test('consent completion for old bearer A cannot authorize the same-actor new login B', () async {
    final consent = Completer<bool>();
    final first = fixtureSession('one', token: 'fixture-bearer-A');
    activeDriverSessionNotifier.value = first;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(DriverDutyBridge.channel,
      (call) async => call.method == 'consent' ? consent.future : true);
    final accepted = DriverDutyBridge.consentAccepted();
    final replacement = fixtureSession('one', token: 'fixture-bearer-B');
    activeDriverSessionNotifier.value = replacement;
    consent.complete(true);
    expect(await accepted, isTrue);
    expect(DriverDutyBridge.activationOwnerIsCurrent(first, businessPreview: false), isFalse);
    expect(DriverDutyBridge.activationOwnerIsCurrent(replacement, businessPreview: false), isTrue);
  });
  test('preview continuation validates the dedicated real bearer independently of UI mint', () {
    final first = fixtureSession('one', token: 'fixture-real-A');
    nativeDriverDutySessionNotifier.value = first;
    activeDriverSessionNotifier.value = fixtureSession('one', method: kOperatorMintDriverLinkMethod);
    expect(DriverDutyBridge.activationOwnerIsCurrent(first, businessPreview: true), isTrue);
    expect(DriverDutyBridge.activationOwnerIsCurrent(first, businessPreview: false), isFalse);
    nativeDriverDutySessionNotifier.value = fixtureSession('one', token: 'fixture-real-B');
    expect(DriverDutyBridge.activationOwnerIsCurrent(first, businessPreview: true), isFalse);
  });
}
