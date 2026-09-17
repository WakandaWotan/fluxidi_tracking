// Pins that the loopback QA customer path never sends the platform admin
// header. Complements the source scan in no_client_admin_token_test.dart with
// a behavioural check on the request that is actually built.

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/customer/local_qa_customer_session.dart';
import 'package:http/http.dart' as http;

void main() {
  test('the QA session request carries no x-admin-token header', () async {
    Map<String, String>? sent;
    try {
      await ensureLocalQaCustomerSession(
        bookingBaseUrl: 'http://127.0.0.1:8788',
        qaEnabled: true,
        runtimeEnv: 'local_test',
        adminToken: 'local-only-token',
        httpPost: (url, {headers, body}) async {
          sent = headers;
          return http.Response('{"ok":false,"error":"stubbed"}', 400);
        },
      );
    } catch (_) {
      // The stub refuses on purpose; only the outgoing headers matter here.
    }
    expect(sent, isNotNull, reason: 'the request must have been attempted');
    expect(sent!.containsKey('x-admin-token'), isFalse);
    expect(sent!.containsKey('X-Admin-Token'), isFalse);
    expect(sent![kLocalQaCustomerSessionHeader], 'local-only-token');
    expect(kLocalQaCustomerSessionHeader, isNot('x-admin-token'));
  });

  test('a production or non-loopback target is refused outright', () async {
    var attempted = false;
    Future<void> attempt({
      required String baseUrl,
      required String env,
      required bool enabled,
    }) async {
      try {
        await ensureLocalQaCustomerSession(
          bookingBaseUrl: baseUrl,
          qaEnabled: enabled,
          runtimeEnv: env,
          adminToken: 'local-only-token',
          httpPost: (url, {headers, body}) async {
            attempted = true;
            return http.Response('{"ok":true}', 200);
          },
        );
      } catch (_) {
        // Expected: the guard throws before any request is built.
      }
    }

    await attempt(
      baseUrl: 'https://booking.fluxidi.com',
      env: 'local_test',
      enabled: true,
    );
    await attempt(
      baseUrl: 'http://127.0.0.1:8788',
      env: 'production',
      enabled: true,
    );
    await attempt(
      baseUrl: 'http://127.0.0.1:8788',
      env: 'local_test',
      enabled: false,
    );
    expect(
      attempted,
      isFalse,
      reason: 'no request may leave the device outside the loopback QA gate',
    );
  });
}
