import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:fluxidi_tracking/company/driver_management_app_session.dart';

const origin = 'https://fluxidi-booking-api.fluxidi.workers.dev';
const token = 'Bearer existing-company-session-not-a-new-login';
final ticket = List.filled(64, 'a').join();
Map<String, dynamic> readiness() => {
  'ok': true,
  'ready': true,
  'contract': 'fluxidi-driver-management-app-v2',
  'roster_read_only': true,
  'operator': {'company_id': 'own-company', 'tenant_id': 'own-tenant'},
  'capabilities': {
    'drivers_read': true,
    'partner_read': true,
    'partner_write': true,
    'export_csv': true,
    'settlement_read': false,
    'settlement_write': false,
    'financial_rule_write': false,
    'import_write': false,
    'bulk_assign': false,
    'bulk_write': false,
  },
};
void main() {
  test(
    'existing company session is reused; no second login or bearer in handoff',
    () async {
      final requests = <http.Request>[];
      final session = DriverManagementAppSession(
        companyId: 'own-company',
        authorization: token,
        expiresAt: null,
        sessionUnchanged: () async => true,
        client: MockClient((r) async {
          requests.add(r);
          return http.Response(
            jsonEncode(
              r.method == 'POST'
                  ? {
                      'ok': true,
                      'location': '$origin/driver-management/handoff#$ticket',
                    }
                  : readiness(),
            ),
            200,
          );
        }),
      );
      final location = await session.connect();
      expect(location.fragment, ticket);
      expect(location.toString(), isNot(contains(token)));
      expect(requests.map((r) => r.url.path), [
        '/driver-management/app-readiness',
        '/driver-management/host-session',
      ]);
      expect(requests.every((r) => r.headers['Authorization'] == token), true);
      expect(requests.every((r) => r.url.query.isEmpty), true);
      expect(requests.last.body, isEmpty);
      expect(requests.every((r) => !r.followRedirects), true);
      session.close();
    },
  );
  for (final mutation in [
    'wrong-company',
    'wrong-tenant',
    'wrong-contract',
    'financial',
    'refund-import',
    'missing-partner-read',
  ]) {
    test('unsafe readiness rejected: $mutation', () async {
      var posts = 0;
      final body = readiness();
      switch (mutation) {
        case 'wrong-company':
          body['operator']['company_id'] = 'foreign';
        case 'wrong-tenant':
          body['operator']['tenant_id'] = '';
        case 'wrong-contract':
          body['contract'] = 'legacy';
        case 'financial':
          body['capabilities']['settlement_write'] = true;
        case 'refund-import':
          body['capabilities']['import_write'] = true;
        case 'missing-partner-read':
          body['capabilities']['partner_read'] = false;
      }
      final session = DriverManagementAppSession(
        companyId: 'own-company',
        authorization: token,
        expiresAt: null,
        sessionUnchanged: () async => true,
        client: MockClient((r) async {
          if (r.method == 'POST') posts++;
          return http.Response(jsonEncode(body), 200);
        }),
      );
      await expectLater(
        session.connect(),
        throwsA(isA<DriverManagementAppFailure>()),
      );
      expect(posts, 0);
      session.close();
    });
  }
  test('session switch during readiness prevents ticket mint', () async {
    var current = true, posts = 0;
    final session = DriverManagementAppSession(
      companyId: 'own-company',
      authorization: token,
      expiresAt: null,
      sessionUnchanged: () async => current,
      client: MockClient((r) async {
        if (r.method == 'POST') posts++;
        current = false;
        return http.Response(jsonEncode(readiness()), 200);
      }),
    );
    await expectLater(
      session.connect(),
      throwsA(isA<DriverManagementAppFailure>()),
    );
    expect(posts, 0);
    session.close();
  });
  for (final status in [301, 302, 401, 403, 503]) {
    test(
      'host $status does not launch another origin or create a login',
      () async {
        final session = DriverManagementAppSession(
          companyId: 'own-company',
          authorization: token,
          expiresAt: null,
          sessionUnchanged: () async => true,
          client: MockClient(
            (_) async => http.Response(
              '{}',
              status,
              headers: {'location': 'https://foreign.invalid/'},
            ),
          ),
        );
        await expectLater(
          session.connect(),
          throwsA(isA<DriverManagementAppFailure>()),
        );
        session.close();
      },
    );
  }
  test(
    'external, file, data, javascript, API and foreign-scope navigation denied',
    () {
      final session = DriverManagementAppSession(
        companyId: 'own-company',
        authorization: token,
        expiresAt: null,
        sessionUnchanged: () async => true,
      );
      for (final path in [
        'https://foreign.invalid/driver-management/',
        'http://fluxidi-booking-api.fluxidi.workers.dev/driver-management/',
        'file:///local.html',
        'data:text/html,test',
        'javascript:alert(1)',
        '$origin/company/bootstrap',
        '$origin/driver-management/?company_id=foreign',
        '$origin/driver-management/handoff#bad',
      ])
        expect(session.allowsNavigation(path), false, reason: path);
      expect(session.allowsNavigation('$origin/driver-management/'), true);
      expect(
        session.allowsNavigation('$origin/driver-management/#partners'),
        true,
      );
      expect(
        session.allowsNavigation('$origin/driver-management/handoff#$ticket'),
        true,
      );
      session.close();
    },
  );
  test('CSV is authenticated with the current company session', () async {
    final paths = <String>[];
    final session = DriverManagementAppSession(
      companyId: 'own-company',
      authorization: token,
      expiresAt: null,
      sessionUnchanged: () async => true,
      client: MockClient((r) async {
        expect(r.headers['Authorization'], token);
        paths.add(r.url.path);
        return http.Response(
          'name\r\nOwn Driver',
          200,
          headers: {'content-type': 'text/csv; charset=utf-8'},
        );
      }),
    );
    expect(
      await session.exportCsv(
        '$origin/driver-management/api/drivers/export?q=Own',
      ),
      contains('Own Driver'),
    );
    expect(paths.length, 1);
    session.close();
  });
  for (final path in [
    'https://foreign.invalid/driver-management/api/drivers/export',
    '$origin/driver-management/api/drivers/export?company_id=foreign',
    '$origin/driver-management/api/drivers/export?tenant_id=foreign',
    '$origin/driver-management/api/drivers/export?settlement=true',
    '$origin/driver-management/api/drivers/export?q=a&q=b',
    '$origin/driver-management/api/drivers/settlements/export',
    'javascript:alert(1)',
  ]) {
    test('unsafe CSV URI rejected: $path', () async {
      var network = 0;
      final session = DriverManagementAppSession(
        companyId: 'own-company',
        authorization: token,
        expiresAt: null,
        sessionUnchanged: () async => true,
        client: MockClient((_) async {
          network++;
          return http.Response('', 200);
        }),
      );
      await expectLater(
        session.exportCsv(path),
        throwsA(isA<DriverManagementAppFailure>()),
      );
      expect(network, 0);
      session.close();
    });
  }
  test('synthetic and expired sessions cannot request a host ticket', () async {
    for (final synthetic in [true, false]) {
      var network = 0;
      final session = DriverManagementAppSession(
        companyId: 'own-company',
        authorization: token,
        synthetic: synthetic,
        expiresAt: DateTime.utc(2000),
        sessionUnchanged: () async => true,
        client: MockClient((_) async {
          network++;
          return http.Response('', 200);
        }),
      );
      await expectLater(
        session.connect(),
        throwsA(isA<DriverManagementAppFailure>()),
      );
      expect(network, 0);
      session.close();
    }
  });
}
