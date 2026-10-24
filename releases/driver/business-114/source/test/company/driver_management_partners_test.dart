import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/company/driver_management_native_repository.dart';
import 'driver_management_native_test_support.dart';

Map<String, dynamic> partner(
  NativeDriverFixture f, {
  String relation = 'partner_company',
}) => {
  'tenant_id': f.tenant,
  'company_id': f.company,
  'id': 'partner-1',
  'business_name': 'Bestaande samenwerking',
  'contact_person': null,
  'relationship_type': relation,
  'status': 'active',
  'revision': 1,
  'driver_ids': ['driver-1'],
  'vehicle_ids': ['vehicle-1'],
  'rule_id': null,
  'rule_version': null,
};
void main() {
  for (final scope in [
    ('tenant-a', 'mario'),
    ('tenant-a', 'diva'),
    ('tenant-b', 'mario'),
    ('future-tenant', 'new-company'),
  ]) {
    test('Native partner list shares authenticated scope $scope', () async {
      final f = NativeDriverFixture(tenant: scope.$1, company: scope.$2);
      final repo = f.repository();
      await repo.connect();
      expect(await repo.partners(), isEmpty);
      f.partnerRecords.add(partner(f));
      expect((await repo.partners()).single['company_id'], f.company);
      expect((await repo.driverOptions()).single['driver_id'], 'driver-1');
      expect(repo.vehicles, hasLength(2));
      expect(
        f.requests.every(
          (u) =>
              u.queryParameters['company_id'] == null &&
              u.queryParameters['tenant_id'] == null,
        ),
        isTrue,
      );
    });
  }
  for (final key in ['company_id', 'tenant_id'])
    test('Native rejects foreign partner $key', () async {
      final f = NativeDriverFixture();
      f.partnerRecords.add({...partner(f), key: 'other'});
      final repo = f.repository();
      await repo.connect();
      await expectLater(
        repo.partners(),
        throwsA(isA<DriverManagementReadFailure>()),
      );
      await expectLater(
        repo.list({}),
        throwsA(isA<DriverManagementReadFailure>()),
      );
    });
  test(
    'Native rejects duplicate identities rather than double-counting',
    () async {
      final f = NativeDriverFixture();
      f.partnerRecords.addAll([partner(f), partner(f)]);
      final repo = f.repository();
      await repo.connect();
      await expectLater(
        repo.partners(),
        throwsA(isA<DriverManagementReadFailure>()),
      );
    },
  );
  for (final relation in [
    'individual_subcontractor',
    'subcontractor_company',
    'partner_company',
    'employee',
  ]) {
    test(
      'Exact relation, revision and existing membership preserved: $relation',
      () async {
        final f = NativeDriverFixture();
        final p = partner(f, relation: relation);
        Map<String, dynamic>? sent;
        final repo = DriverManagementNativeRepository(
          companyId: f.company,
          authorization: 'Bearer local-test',
          sessionUnchanged: () async => f.current,
          get: f.get,
          post: (uri, headers, body) async {
            expect(uri.path, '/driver-management/api/drivers/partners');
            expect(headers['Origin'], uri.origin);
            expect(headers['x-driver-management'], '1');
            expect(headers['Authorization'], 'Bearer local-test');
            final envelope = jsonDecode(body) as Map<String, dynamic>;
            expect(envelope['confirm'], isTrue);
            sent = envelope['partner'];
            return (
              status: 200,
              body: jsonEncode({
                'ok': true,
                'partner': {...p, 'revision': 2},
              }),
            );
          },
        );
        await repo.connect();
        await repo.partners();
        final draft = {
          for (final key in [
            'id',
            'business_name',
            'contact_person',
            'relationship_type',
            'status',
            'driver_ids',
            'vehicle_ids',
            'rule_id',
            'rule_version',
          ])
            key: p[key],
          'expected_revision': 1,
        };
        expect((await repo.savePartner(draft))['revision'], 2);
        expect(sent!['relationship_type'], relation);
        expect(sent!['expected_revision'], 1);
        expect(sent!['driver_ids'], ['driver-1']);
        expect(sent!.containsKey('tenant_id'), isFalse);
      },
    );
  }
  test(
    'Missing write permission and rotated session prevent native POST',
    () async {
      final f = NativeDriverFixture()..partnerWrite = false;
      var writes = 0;
      final repo = DriverManagementNativeRepository(
        companyId: f.company,
        authorization: 'Bearer local-test',
        sessionUnchanged: () async => f.current,
        get: f.get,
        post: (u, h, b) async {
          writes++;
          return (status: 200, body: '{}');
        },
      );
      await repo.connect();
      await repo.partners();
      await expectLater(
        repo.savePartner({}),
        throwsA(isA<DriverManagementReadFailure>()),
      );
      f.current = false;
      await expectLater(
        repo.partners(),
        throwsA(isA<DriverManagementReadFailure>()),
      );
      expect(writes, 0);
    },
  );
  test(
    'Session changes while saving cannot reveal the returned partner',
    () async {
      final f = NativeDriverFixture();
      final repo = DriverManagementNativeRepository(
        companyId: f.company,
        authorization: 'Bearer local-test',
        sessionUnchanged: () async => f.current,
        get: f.get,
        post: (u, h, b) async {
          f.current = false;
          return (
            status: 200,
            body: jsonEncode({'ok': true, 'partner': partner(f)}),
          );
        },
      );
      await repo.connect();
      await repo.partners();
      await expectLater(
        repo.savePartner({'id': 'partner-1'}),
        throwsA(isA<DriverManagementReadFailure>()),
      );
    },
  );
  test('Financial or import capability activation is rejected', () async {
    final f = NativeDriverFixture();
    final repo = f.repository(
      get: (u, h) async {
        final r = await f.get(u, h);
        if (!u.path.endsWith('/app-readiness')) return r;
        final data = jsonDecode(r.body) as Map<String, dynamic>;
        data['capabilities']['settlement_write'] = true;
        return (status: 200, body: jsonEncode(data));
      },
    );
    await repo.connect();
    await expectLater(
      repo.partners(),
      throwsA(isA<DriverManagementReadFailure>()),
    );
  });
}
