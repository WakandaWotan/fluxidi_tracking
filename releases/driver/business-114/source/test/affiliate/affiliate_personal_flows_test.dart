import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/affiliate/affiliate_page.dart';
import 'package:fluxidi_tracking/affiliate/affiliate_repository.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'affiliate_fixture.dart';

http.Response reply(Map<String, dynamic> json, [int status = 200]) =>
    http.Response(jsonEncode(json), status, headers: affiliatePrivateHeaders);
Matcher failure(AffiliateFailure value) => throwsA(
  isA<AffiliateException>().having((e) => e.failure, 'failure', value),
);
Map<String, dynamic> bankUpdated({bool verified = false}) =>
    affiliateOverview(status: 'active')
      ..['revision'] = 2
      ..['bank_revision'] = 1
      ..['bank_verified'] = verified;
http.Response emptyPage() =>
    reply({'ok': true, 'items': [], 'next_cursor': null});
Future<void> show(
  WidgetTester tester,
  AffiliateFixture fixture, {
  Size size = const Size(400, 800),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(home: AffiliatePage(repository: fixture.repository)),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => appLanguageNotifier.value = AppLanguage.nl);
  tearDown(() => appLanguageNotifier.value = AppLanguage.en);
  test(
    'bank change sends exact revision under captured person and revokes verified flag',
    () async {
      final fixture = AffiliateFixture(
        http: MockClient((r) async {
          expect(r.headers['Authorization'], 'Bearer personal_fixture_A');
          if (r.method == 'GET')
            return reply(affiliateOverview(status: 'active'));
          expect(r.url.path, '/affiliate/bank-account');
          expect(jsonDecode(r.body), {
            'iban': 'BE68539007547034',
            'account_holder': 'Human Fixture',
            'expected_revision': 1,
          });
          return reply(bankUpdated());
        }),
      );
      addTearDown(fixture.dispose);
      final overview = await fixture.repository.loadOverview();
      final saved = await fixture.repository.saveBank(
        overview,
        iban: 'be68 5390 0754 7034',
        holder: ' Human Fixture ',
      );
      expect(saved.data.bankRevision, 1);
      expect(saved.data.bankVerified, false);
      expect(saved.data.revision, 2);
    },
  );
  test('bank response cannot pretend account is already verified', () async {
    final fixture = AffiliateFixture(
      http: MockClient(
        (r) async => reply(
          r.method == 'GET'
              ? affiliateOverview(status: 'active')
              : bankUpdated(verified: true),
        ),
      ),
    );
    addTearDown(fixture.dispose);
    await expectLater(
      fixture.repository.saveBank(
        await fixture.repository.loadOverview(),
        iban: 'BE68539007547034',
        holder: 'Fixture',
      ),
      failure(AffiliateFailure.unavailable),
    );
  });
  test(
    'business applicant preserves actual fields without using company credentials',
    () async {
      final fixture = AffiliateFixture(
        http: MockClient((r) async {
          if (r.method == 'GET') return reply(affiliateOverview());
          expect(r.headers['Authorization'], 'Bearer personal_fixture_A');
          expect(jsonDecode(r.body), {
            'display_name': 'Fixture',
            'applicant_type': 'business',
            'legal_name': 'Fixture Company',
            'address': 'Fixture Address',
            'country': 'BE',
            'terms_version': 'approved_fixture_v1',
            'accepted': true,
          });
          return reply(affiliateOverview(status: 'pending'));
        }),
      );
      addTearDown(fixture.dispose);
      final result = await fixture.repository.apply(
        await fixture.repository.loadOverview(),
        displayName: 'Fixture',
        accepted: true,
        applicantType: 'business',
        legalName: 'Fixture Company',
        address: 'Fixture Address',
        country: 'be',
      );
      expect(result.data.status, 'pending');
      expect(result.data.referralCode, isNull);
    },
  );
  for (final status in [200, 401]) {
    test('late bank A $status cannot enter B account state', () async {
      final started = Completer<void>(), pending = Completer<http.Response>();
      final fixture = AffiliateFixture(
        http: MockClient((r) async {
          if (r.method == 'GET')
            return reply(affiliateOverview(status: 'active'));
          started.complete();
          return pending.future;
        }),
      );
      addTearDown(fixture.dispose);
      final overview = await fixture.repository.loadOverview();
      final save = fixture.repository.saveBank(
        overview,
        iban: 'BE68539007547034',
        holder: 'Fixture',
      );
      await started.future;
      fixture.replace(affiliateSession('B'));
      pending.complete(reply(bankUpdated(), status));
      await expectLater(save, failure(AffiliateFailure.sessionChanged));
      expect(fixture.current!.customerId, 'B');
    });
  }
  for (final size in [const Size(400, 800), const Size(1280, 800)]) {
    testWidgets(
      'phone/tablet real bank dialog saves once, history stays server-owned $size',
      (tester) async {
        final pending = Completer<http.Response>();
        var calls = 0;
        final fixture = AffiliateFixture(
          http: MockClient((r) async {
            if (r.url.path == '/affiliate/me')
              return reply(affiliateOverview(status: 'active'));
            if (r.method == 'POST') {
              calls++;
              expect(jsonDecode(r.body)['expected_revision'], 1);
              return pending.future;
            }
            return emptyPage();
          }),
        );
        addTearDown(fixture.dispose);
        await show(tester, fixture, size: size);
        await tester.ensureVisible(find.byKey(const Key('affiliate_bank')));
        await tester.tap(find.byKey(const Key('affiliate_bank')));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const Key('affiliate_form_iban')),
          'BE68539007547034',
        );
        await tester.enterText(
          find.byKey(const Key('affiliate_form_holder')),
          'Fixture Person',
        );
        await tester.tap(find.byKey(const Key('affiliate_form_submit')));
        await tester.pump();
        expect(calls, 1);
        pending.complete(reply(bankUpdated()));
        await tester.pumpAndSettle();
        expect(
          find.text('Bankrekening nog niet gecontroleerd'),
          findsOneWidget,
        );
        expect(find.text('BE68539007547034'), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
  testWidgets(
    'logout during bank dialog clears private IBAN and sends no POST',
    (tester) async {
      var posts = 0;
      final fixture = AffiliateFixture(
        http: MockClient((r) async {
          if (r.method == 'POST') posts++;
          return r.url.path == '/affiliate/me'
              ? reply(affiliateOverview(status: 'active'))
              : emptyPage();
        }),
      );
      addTearDown(fixture.dispose);
      await show(tester, fixture);
      await tester.ensureVisible(find.byKey(const Key('affiliate_bank')));
      await tester.tap(find.byKey(const Key('affiliate_bank')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('affiliate_form_iban')),
        'BE68539007547034',
      );
      fixture.replace(null);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('BE68539007547034'), findsNothing);
      expect(posts, 0);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'referrals are lazy, preserve held state and paginate actual cursor',
    (tester) async {
      var referrals = 0;
      final fixture = AffiliateFixture(
        http: MockClient((r) async {
          if (r.url.path == '/affiliate/me')
            return reply(affiliateOverview(status: 'active'));
          if (r.url.path != '/affiliate/referrals') return emptyPage();
          referrals++;
          expect(r.url.queryParameters['limit'], '20');
          expect(
            r.url.queryParameters['cursor'],
            referrals == 1 ? null : 'ref_1',
          );
          return reply({
            'ok': true,
            'items': [
              {
                'referral_id': 'ref_$referrals',
                'state': referrals == 1 ? 'held_owner_review' : 'active',
                'revision': 1,
                'created_at': '2026-10-04T12:00:00Z',
              },
            ],
            'next_cursor': referrals == 1 ? 'ref_1' : null,
          });
        }),
      );
      addTearDown(fixture.dispose);
      await show(tester, fixture, size: const Size(1280, 1200));
      expect(referrals, 0);
      await tester.ensureVisible(find.byKey(const Key('affiliate_referrals')));
      await tester.tap(find.byKey(const Key('affiliate_referrals')));
      await tester.pumpAndSettle();
      expect(referrals, 1);
      expect(
        find.textContaining('Eigendom bedrijf in beoordeling'),
        findsOneWidget,
      );
      await tester.ensureVisible(find.byKey(const Key('affiliate_referrals')));
      await tester.tap(find.byKey(const Key('affiliate_referrals')));
      await tester.pumpAndSettle();
      expect(referrals, 2);
      fixture.replace(null);
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Eigendom bedrijf in beoordeling'),
        findsNothing,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );
}
