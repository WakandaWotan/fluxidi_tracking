import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/company/auth_failure_kind.dart';

void main() {
  test('loopback plus missing company is wrong environment, not expired', () {
    expect(
      classifyRemoteAuthFailure(
        statusCode: 403,
        error: 'verification_failed',
        loopbackHost: true,
        companyResolvable: false,
      ),
      AuthFailureKind.wrongEnvironment,
    );
    expect(
      classifyRemoteAuthFailure(
        statusCode: 404,
        error: 'company_not_found',
        loopbackHost: true,
      ),
      AuthFailureKind.wrongEnvironment,
    );
  });

  test('resolvable local company plus bad code stays verification_failed', () {
    expect(
      classifyRemoteAuthFailure(
        statusCode: 403,
        error: 'verification_failed',
        loopbackHost: true,
        companyResolvable: true,
      ),
      AuthFailureKind.verificationFailed,
    );
  });

  test('network on loopback is local worker unreachable', () {
    expect(
      classifyRemoteAuthFailure(networkException: true, loopbackHost: true),
      AuthFailureKind.localWorkerUnreachable,
    );
    expect(
      classifyThrownAuthFailure(
        Exception('TimeoutException after 0:00:12'),
        loopbackHost: true,
      ),
      AuthFailureKind.localWorkerUnreachable,
    );
  });

  test('email_not_linked stays distinct from a generic send failure', () {
    expect(
      classifyThrownAuthFailure(
        Exception('email_not_linked'),
        loopbackHost: true,
      ),
      AuthFailureKind.emailNotLinked,
    );
  });

  test('sms_not_configured on loopback is local SMS unavailable', () {
    expect(
      classifyThrownAuthFailure(
        Exception('sms_not_configured'),
        loopbackHost: true,
      ),
      AuthFailureKind.localSmsUnavailable,
    );
  });

  test('production company_not_found stays company_not_found', () {
    expect(
      classifyRemoteAuthFailure(
        statusCode: 404,
        error: 'company_not_found',
        loopbackHost: false,
      ),
      AuthFailureKind.companyNotFound,
    );
  });

  test('public host description never includes a path or query', () {
    expect(
      describePublicAuthHost('http://127.0.0.1:8788/public/company/link/verify'),
      'http://127.0.0.1:8788',
    );
    expect(
      describePublicAuthHost(
        'https://fluxidi-booking-api.fluxidi.workers.dev/admin',
      ),
      'https://fluxidi-booking-api.fluxidi.workers.dev:443',
    );
  });
}
