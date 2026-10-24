import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/driver/planned_tracking_lifecycle.dart';
import 'package:http/http.dart' as http;

const _scope = <String, dynamic>{
  'tenant_id': 'tenant-a',
  'company_id': 'company-a',
  'booking_id': 'booking-a',
  'driver_id': 'driver-a',
};

http.Response _confirmedSession() => http.Response(
  '{"ok":true,"session_id":"session-a","tracking_sync":{"confirmed":true,"assignment_version":2}}',
  200,
);

void main() {
  test('START identifies the rejected worker stage and bounded error code', () async {
    final lifecycle = PlannedTrackingLifecycle(
      bookingBaseUrl: 'https://booking.example',
      trackingBaseUrl: 'https://tracking.example',
      post: (uri, _) async => uri.path == '/track/session/start'
          ? _confirmedSession()
          : http.Response('{"ok":false,"error":"booking_not_assigned_to_driver"}', 403),
    );
    await expectLater(
      lifecycle.start(_scope, legId: 'primary', isOperationalLeg: false),
      throwsA(isA<TrackingLifecycleFailure>()
          .having((e) => e.stage, 'stage', '/tracking/start')
          .having((e) => e.statusCode, 'status', 403)
          .having((e) => e.code, 'code', 'booking_not_assigned_to_driver')),
    );
  });

  test('START never echoes arbitrary error text or malformed responses', () async {
    final unsafe = PlannedTrackingLifecycle(
      bookingBaseUrl: 'https://booking.example',
      trackingBaseUrl: 'https://tracking.example',
      post: (_, __) async => http.Response('{"ok":false,"error":"token=secret"}', 401),
    );
    await expectLater(
      unsafe.start(_scope, legId: 'primary', isOperationalLeg: false),
      throwsA(isA<TrackingLifecycleFailure>()
          .having((e) => e.stage, 'stage', '/track/session/start')
          .having((e) => e.code, 'code', 'unknown')),
    );
    final malformed = PlannedTrackingLifecycle(
      bookingBaseUrl: 'https://booking.example',
      trackingBaseUrl: 'https://tracking.example',
      post: (_, __) async => http.Response('<html>gateway error</html>', 502),
    );
    await expectLater(
      malformed.start(_scope, legId: 'primary', isOperationalLeg: false),
      throwsA(isA<TrackingLifecycleFailure>()
          .having((e) => e.code, 'code', 'invalid_response')),
    );
  });
}
