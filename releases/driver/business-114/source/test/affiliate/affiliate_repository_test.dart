import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/affiliate/affiliate_models.dart';
import 'package:fluxidi_tracking/affiliate/affiliate_repository.dart';
import 'package:fluxidi_tracking/customer_session_store.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'affiliate_fixture.dart';

Matcher fails(AffiliateFailure value) => throwsA(
  isA<AffiliateException>().having((e) => e.failure, 'failure', value),
);

void main() {
  test(
    'balance ledger history preserves server signed correction and exact cursor',
    () async {
      final fixture = AffiliateFixture(
        http: MockClient((request) async {
          if (request.url.path == '/affiliate/me')
            return http.Response(
              jsonEncode(affiliateOverview(status: 'active')),
              200,
              headers: affiliatePrivateHeaders,
            );
          expect(request.url.path, '/affiliate/entries');
          expect(request.url.queryParameters, {'limit': '20', 'cursor': '17'});
          return http.Response(
            jsonEncode({
              'ok': true,
              'items': [
                {
                  'id': 18,
                  'currency': 'EUR',
                  'cents': -250,
                  'kind': 'correction',
                  'period': '2026-10',
                  'created_at': '2026-10-04T12:00:00Z',
                },
              ],
              'next_cursor': '18',
            }),
            200,
            headers: affiliatePrivateHeaders,
          );
        }),
      );
      addTearDown(fixture.dispose);
      final overview = await fixture.repository.loadOverview();
      final entries = await fixture.repository.loadEntries(
        overview.owner,
        cursor: '17',
      );
      expect(entries.items.single.cents, -250);
      expect(entries.items.single.kind, 'correction');
      expect(entries.nextCursor, '18');
      expect(
        () => AffiliateEntryPage.parse({
          'ok': true,
          'items': [
            {
              'id': 18,
              'currency': 'EUR',
              'cents': 250,
              'kind': 'invented_earnings',
              'period': '2026-10',
              'created_at': '2026-10-04T12:00:00Z',
            },
          ],
        }),
        throwsFormatException,
      );
    },
  );
  test('guest never sends a request or borrows company credentials', () async {
    var calls = 0;
    final fixture = AffiliateFixture(
      guest: true,
      http: MockClient((_) async {
        calls++;
        return http.Response('{}', 200);
      }),
    );
    addTearDown(fixture.dispose);
    await expectLater(
      fixture.repository.loadOverview(),
      fails(AffiliateFailure.signInRequired),
    );
    expect(calls, 0);
  });

  test('real personal bearer only and private no-store overview', () async {
    final fixture = AffiliateFixture(
      http: MockClient((request) async {
        expect(request.method, 'GET');
        expect(
          request.url.toString(),
          'https://booking.example.test/affiliate/me',
        );
        expect(request.headers['Authorization'], 'Bearer personal_fixture_A');
        expect(request.body, isEmpty);
        return http.Response(
          jsonEncode(affiliateOverview()),
          200,
          headers: affiliatePrivateHeaders,
        );
      }),
    );
    addTearDown(fixture.dispose);
    final result = await fixture.repository.loadOverview();
    expect(result.data.status, 'not_enrolled');
    expect(result.data.balances, isEmpty);
    expect(result.data.referralCode, isNull);
  });

  for (final code in [200, 401]) {
    test('late A $code cannot expose A or clear newer B', () async {
      final pending = Completer<http.Response>();
      final started = Completer<void>();
      final fixture = AffiliateFixture(
        http: MockClient((_) {
          started.complete();
          return pending.future;
        }),
      );
      addTearDown(fixture.dispose);
      final request = fixture.repository.loadOverview();
      await started.future;
      fixture.replace(affiliateSession('B'));
      pending.complete(
        http.Response(
          jsonEncode(affiliateOverview()),
          code,
          headers: affiliatePrivateHeaders,
        ),
      );
      await expectLater(request, fails(AffiliateFailure.sessionChanged));
      expect(fixture.current!.customerId, 'B');
    });
  }

  test('delayed cold disk owner cannot adopt a replacement login', () async {
    final revision = ValueNotifier(0);
    final delayed = Completer<CustomerSession?>();
    CustomerSession? current;
    var requests = 0;
    final repository = AffiliateRepository(
      baseUrl: 'https://booking.example.test',
      revision: revision,
      currentSession: () => current,
      loadSession: () => delayed.future,
      transport: MockClient((_) async {
        requests++;
        return http.Response('{}', 200);
      }),
    );
    addTearDown(repository.dispose);
    addTearDown(revision.dispose);
    final request = repository.loadOverview();
    current = affiliateSession('B');
    revision.value++;
    delayed.complete(affiliateSession('A'));
    await expectLater(request, fails(AffiliateFailure.sessionChanged));
    expect(requests, 0);
    expect(current.customerId, 'B');
  });

  for (final invalid in [
    'wrong-person',
    'public-cache',
    'disabled',
    'money-string',
  ]) {
    test('reject $invalid without invented zero balances', () async {
      final json = affiliateOverview(status: 'active');
      if (invalid == 'wrong-person') json['affiliate_id'] = 'B';
      if (invalid == 'disabled') json['program_enabled'] = false;
      if (invalid == 'money-string')
        json['balances'] = [
          {
            'currency': 'EUR',
            'balance_cents': '100',
            'reserved_cents': 0,
            'available_cents': 100,
            'paid_cents': 0,
          },
        ];
      final fixture = AffiliateFixture(
        http: MockClient(
          (_) async => http.Response(
            jsonEncode(json),
            200,
            headers: invalid == 'public-cache'
                ? {'cache-control': 'public'}
                : affiliatePrivateHeaders,
          ),
        ),
      );
      addTearDown(fixture.dispose);
      await expectLater(
        fixture.repository.loadOverview(),
        fails(AffiliateFailure.unavailable),
      );
    });
  }

  test(
    'application uses captured personal owner and exact server terms only',
    () async {
      var calls = 0;
      final fixture = AffiliateFixture(
        http: MockClient((request) async {
          calls++;
          if (request.method == 'POST') {
            expect(request.url.path, '/affiliate/application');
            expect(jsonDecode(request.body), {
              'display_name': 'Human Fixture',
              'applicant_type': 'person',
              'terms_version': 'approved_fixture_v1',
              'accepted': true,
            });
            return http.Response(
              jsonEncode(affiliateOverview(status: 'pending')),
              200,
              headers: affiliatePrivateHeaders,
            );
          }
          return http.Response(
            jsonEncode(affiliateOverview()),
            200,
            headers: affiliatePrivateHeaders,
          );
        }),
      );
      addTearDown(fixture.dispose);
      final overview = await fixture.repository.loadOverview();
      final pending = await fixture.repository.apply(
        overview,
        displayName: ' Human Fixture ',
        accepted: true,
      );
      expect(pending.data.status, 'pending');
      expect(pending.data.referralCode, isNull);
      await expectLater(
        fixture.repository.apply(
          pending,
          displayName: 'Human Fixture',
          accepted: true,
        ),
        fails(AffiliateFailure.termsChanged),
      );
      expect(calls, 2);
      fixture.replace(affiliateSession('B'));
      await expectLater(
        fixture.repository.apply(overview, displayName: 'A', accepted: true),
        fails(AffiliateFailure.sessionChanged),
      );
      expect(calls, 2);
    },
  );

  test(
    'held receipts and prepared payouts never become earned or paid values',
    () {
      final json = affiliateOverview(status: 'active');
      json['held_receipts'] = 7;
      json['balances'] = [
        {
          'currency': 'EUR',
          'balance_cents': 3000,
          'reserved_cents': 1000,
          'available_cents': 2000,
          'paid_cents': 500,
        },
      ];
      final model = AffiliateOverview.parse(json, 'A');
      expect(model.heldReceipts, 7);
      expect(model.balances.single.paidCents, 500);
      final page = AffiliatePayoutPage.parse({
        'ok': true,
        'items': [
          {
            'id': 'fixture1',
            'period': '2026-10',
            'currency': 'EUR',
            'cents': 1000,
            'state': 'approved',
          },
          {
            'id': 'fixture2',
            'period': '2026-10',
            'currency': 'EUR',
            'cents': 200,
            'state': 'exported',
          },
        ],
        'next_cursor': null,
      });
      expect(page.items.map((e) => e.state), ['approved', 'exported']);
    },
  );

  test(
    'dispose prevents a pending response and expired personal login sends nothing',
    () async {
      final pending = Completer<http.Response>(), started = Completer<void>();
      final fixture = AffiliateFixture(
        http: MockClient((_) {
          started.complete();
          return pending.future;
        }),
      );
      final request = fixture.repository.loadOverview();
      await started.future;
      fixture.repository.dispose();
      pending.complete(
        http.Response(
          jsonEncode(affiliateOverview()),
          200,
          headers: affiliatePrivateHeaders,
        ),
      );
      await expectLater(request, fails(AffiliateFailure.sessionChanged));
      fixture.revision.dispose();
      var calls = 0;
      final expired = AffiliateFixture(
        session: affiliateSession(
          'A',
          expiry: DateTime.now().subtract(const Duration(seconds: 1)),
        ),
        http: MockClient((_) async {
          calls++;
          return http.Response('{}', 200);
        }),
      );
      addTearDown(expired.dispose);
      await expectLater(
        expired.repository.loadOverview(),
        fails(AffiliateFailure.sessionChanged),
      );
      expect(calls, 0);
    },
  );
}
