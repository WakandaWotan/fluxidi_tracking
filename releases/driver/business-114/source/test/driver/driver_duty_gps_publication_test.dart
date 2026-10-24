import 'package:fluxidi_tracking/driver/authenticated_driver_vehicle.dart';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:fluxidi_tracking/driver/driver_duty_bridge.dart';
import 'package:fluxidi_tracking/driver/planned_tracking_lifecycle.dart';
import 'package:fluxidi_tracking/driver_session_store.dart';

ActiveDriverSession actor({String method = 'public_driver_login', String driver = 'D1', String vehicle = 'V1'}) => ActiveDriverSession(
  driverId: driver, employeeNumber: '1', fullName: 'Fixture', phone: '', loggedInAt: '', updatedAt: '',
  tenantId: 'T1', companyId: 'C1', assignedVehicleId: vehicle,
  driverSessionToken: 'fixture-$method-$driver', linkMethod: method,
  driverSessionExpiresAtUtc: DateTime.now().toUtc().add(const Duration(days: 1)).toIso8601String(),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const booking = 'https://booking.fixture.invalid';
  const tracking = 'https://tracking.fixture.invalid';
  final payload = {'tenant_id': 'T1', 'company_id': 'C1', 'driver_id': 'D1', 'vehicle_id': 'V1', 'lat': 51.1, 'lon': 4.1};
  var clock = DateTime.now();
  Map<dynamic, dynamic>? queried;
  Future<dynamic> ready(MethodCall call) async {
    if (call.method == 'status') {
      queried = (call.arguments as Map)['expected_config'] as Map;
      return {'running': true, 'activation_id': 'fixture-activation', 'native_device_id': 'fixture-device'};
    }
    return true;
  }
  setUp(() async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(DriverDutyBridge.channel, ready);
    await DriverDutyBridge.stop();
    nativeDriverDutySessionNotifier.value = null;
    activeDriverSessionNotifier.value = null;
    queried = null;
    clock = DateTime.now();
  });
  tearDown(() async {
    await DriverDutyBridge.stop();
    nativeDriverDutySessionNotifier.value = null;
    activeDriverSessionNotifier.value = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(DriverDutyBridge.channel, null);
    debugDefaultTargetPlatformOverride = null;
  });

  test('QR actor vehicle resolution passes native GPS owner on foreign company tablet', () async {
    final session=actor();nativeDriverDutySessionNotifier.value=session;activeDriverSessionNotifier.value=session;
    final vehicle=authenticatedDriverVehicleId(session:session,activeDriverId:session.driverId,vehicles:const []);
    final body=await DriverDutyBridge.sendGps(session:session,payload:{...payload,'vehicle_id':vehicle,'session_id':'fixture-trip'},
      bookingBaseUrl:booking,trackingBaseUrl:tracking,isCurrent:()=>true,
      request:(body,headers)async=>body);
    expect(body['vehicle_id'],'V1');expect(body['activation_id'],'fixture-activation');
    expect(body['native_device_id'],'fixture-device');
  });
  test('native owner proof is retained through preSTART and paid trip GPS', () async {
    final session = actor();
    nativeDriverDutySessionNotifier.value = session;
    activeDriverSessionNotifier.value = session;
    final uploads = <Map<String, dynamic>>[];
    final headersSeen = <Map<String, String>>[];
    Future<http.Response> send(Uri uri, Map<String, dynamic> body) async {
      if (uri.path != '/track/driver/location') {
        return http.Response(jsonEncode({
          'ok': true, 'session_id': 'trip-1',
          'tracking_sync': {'confirmed': true, 'assignment_version': 1, 'tracking_phase': 'en_route_pickup'},
        }), 200);
      }
      return DriverDutyBridge.sendGps(
        session: session, payload: body, bookingBaseUrl: booking, trackingBaseUrl: tracking,
        isCurrent: () => DriverDutyBridge.sameAuthenticatedActor(session, activeDriverSessionNotifier.value),
        request: (ownedBody, headers) async {
          uploads.add(ownedBody);
          headersSeen.add(headers);
          return http.Response('{"ok":true}', 200);
        },
      );
    }
    final lifecycle = PlannedTrackingLifecycle(bookingBaseUrl: booking, trackingBaseUrl: tracking, post: send, now: () => clock);
    await lifecycle.enRoute({...payload, 'booking_id': 'B1'}, legId: 'primary', isOperationalLeg: false);
    await lifecycle.uploadPreStart(latitude: 51.1, longitude: 4.1, speedMps: 0,
      heading: 0, accuracy: 5, capturedAt: clock);
    expect(uploads.single['pre_start'], isTrue);
    await lifecycle.start({...payload, 'booking_id': 'B1'}, legId: 'primary', isOperationalLeg: false);
    clock = clock.add(const Duration(seconds: 9));
    await lifecycle.gpsUploads.send(capturedAt: clock, request: () => DriverDutyBridge.sendGps(
      session: session, payload: {...payload, 'session_id': 'trip-1'},
      bookingBaseUrl: booking, trackingBaseUrl: tracking, isCurrent: () => true,
      request: (ownedBody, headers) async {
        uploads.add(ownedBody);
        headersSeen.add(headers);
        return http.Response('{"ok":true}', 200);
      },
    ));
    expect(uploads, hasLength(2));
    for (final body in uploads) {
      expect(body['activation_id'], 'fixture-activation');
      expect(body['native_device_id'], 'fixture-device');
    }
    expect(headersSeen.every((headers) => headers['Authorization'] == 'Bearer ${session.driverSessionToken}'), isTrue);
    expect(queried, containsPair('vehicle_id', 'V1'));
    expect(queried, containsPair('booking', booking));
    expect(queried, containsPair('tracking', tracking));
    expect(nativeDriverDutySessionNotifier.value, same(session));
  });
  test('operator preview for the same driver cannot borrow the paired owner proof', () async {
    nativeDriverDutySessionNotifier.value = actor();
    final preview = actor(method: kOperatorMintDriverLinkMethod);
    final body = await DriverDutyBridge.sendGps(
      session: preview, payload: payload, bookingBaseUrl: booking, trackingBaseUrl: tracking, isCurrent: () => true,
      request: (body, headers) async {
        expect(headers['Authorization'], 'Bearer ${preview.driverSessionToken}');
        return body;
      },
    );
    expect(body, isNot(contains('activation_id')));
    expect(body, isNot(contains('native_device_id')));
    expect(queried, isNull);
  });
  test('another payload vehicle never receives native publication ownership', () async {
    final session = actor();
    nativeDriverDutySessionNotifier.value = session;
    var requests = 0;
    await expectLater(DriverDutyBridge.sendGps(
      session: session, payload: {...payload, 'vehicle_id': 'V2'},
      bookingBaseUrl: booking, trackingBaseUrl: tracking, isCurrent: () => true,
      request: (body, headers) async => requests++,
    ), throwsStateError);
    expect(requests, 0);
    expect(queried, isNull);
  });
  test('missing matched device proof is not retried as legacy GPS', () async {
    final session = actor();
    nativeDriverDutySessionNotifier.value = session;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(DriverDutyBridge.channel,
      (call) async => {'running': true, 'activation_id': 'fixture-activation', 'native_device_id': ''});
    var requests = 0;
    await expectLater(DriverDutyBridge.sendGps(
      session: session, payload: payload, bookingBaseUrl: booking, trackingBaseUrl: tracking, isCurrent: () => true,
      request: (body, headers) async => requests++,
    ), throwsStateError);
    expect(requests, 0);
  });
  for (final changed in ['owner', 'navigation']) {
    test('late native status after $changed changes never uploads an old fix', () async {
      final pending = Completer<dynamic>();
      final queriedStatus = Completer<void>();
      final session = actor();
      nativeDriverDutySessionNotifier.value = session;
      var current = true;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(DriverDutyBridge.channel, (call) async {
        if (call.method == 'status') {
          if (!queriedStatus.isCompleted) queriedStatus.complete();
          return pending.future;
        }
        return true;
      });
      var requests = 0;
      final posting = DriverDutyBridge.sendGps(
        session: session, payload: payload, bookingBaseUrl: booking, trackingBaseUrl: tracking, isCurrent: () => current,
        request: (body, headers) async => requests++,
      );
      await queriedStatus.future;
      if (changed == 'owner') nativeDriverDutySessionNotifier.value = actor(driver: 'D2', vehicle: 'V2');
      else current = false;
      pending.complete({'running': true, 'activation_id': 'old-activation', 'native_device_id': 'fixture-device'});
      await expectLater(posting, throwsStateError);
      expect(requests, 0);
    });
  }
}
