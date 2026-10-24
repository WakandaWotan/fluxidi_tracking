import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/affiliate/affiliate_page.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'affiliate_fixture.dart';

Future<void> showAffiliate(
  WidgetTester tester,
  AffiliateFixture fixture, {
  Size size = const Size(400, 800),
  Future<void> Function(BuildContext)? signIn,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: AffiliatePage(repository: fixture.repository, onSignIn: signIn),
    ),
  );
  await tester.pumpAndSettle();
}

http.Response response(Map<String, dynamic> json, {int status = 200}) =>
    http.Response(jsonEncode(json), status, headers: affiliatePrivateHeaders);

void main() {
  setUp(() => appLanguageNotifier.value = AppLanguage.nl);
  tearDown(() => appLanguageNotifier.value = AppLanguage.en);

  for (final size in [const Size(400, 800), const Size(1280, 800)]) {
    testWidgets(
      'phone/tablet real server terms apply once and pending has no active code $size',
      (tester) async {
        final pending = Completer<http.Response>();
        var posts = 0;
        final fixture = AffiliateFixture(
          http: MockClient((request) async {
            if (request.method == 'POST') {
              posts++;
              return pending.future;
            }
            if (request.url.path == '/affiliate/payouts' ||
                request.url.path == '/affiliate/entries')
              return response({'ok': true, 'items': [], 'next_cursor': null});
            return response(affiliateOverview());
          }),
        );
        addTearDown(fixture.dispose);
        await showAffiliate(tester, fixture, size: size);
        expect(find.text('Fixturevoorwaarden van de server.'), findsOneWidget);
        expect(find.byKey(const Key('affiliate_code')), findsNothing);
        await tester.enterText(
          find.byKey(const Key('affiliate_name')),
          'Fixture Naam',
        );
        await tester.tap(find.byKey(const Key('affiliate_accept')));
        await tester.pump();
        await tester.ensureVisible(find.byKey(const Key('affiliate_apply')));
        await tester.tap(find.byKey(const Key('affiliate_apply')));
        await tester.pump();
        await tester.tap(find.byKey(const Key('affiliate_apply')));
        await tester.pump();
        expect(posts, 1);
        pending.complete(response(affiliateOverview(status: 'pending')));
        await tester.pumpAndSettle();
        expect(find.text('Aanmelding in behandeling'), findsOneWidget);
        expect(find.byKey(const Key('affiliate_code')), findsNothing);
        expect(find.byKey(const Key('affiliate_name')), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets(
    'balances are server values and held/prepared history is not paid',
    (tester) async {
      final overview = affiliateOverview(status: 'active');
      overview['held_receipts'] = 3;
      overview['referred_companies'] = 2;
      overview['balances'] = [
        {
          'currency': 'EUR',
          'balance_cents': 3000,
          'reserved_cents': 1000,
          'available_cents': 2000,
          'paid_cents': 500,
        },
      ];
      final fixture = AffiliateFixture(
        http: MockClient(
          (request) async => response(
            request.url.path == '/affiliate/entries'
                ? {'ok': true, 'items': [], 'next_cursor': null}
                : request.url.path == '/affiliate/payouts'
                ? {
                    'ok': true,
                    'items': [
                      {
                        'id': 'a',
                        'period': '2026-10',
                        'currency': 'EUR',
                        'cents': 1000,
                        'state': 'approved',
                      },
                      {
                        'id': 'b',
                        'period': '2026-10',
                        'currency': 'EUR',
                        'cents': 200,
                        'state': 'exported',
                      },
                    ],
                    'next_cursor': null,
                  }
                : overview,
          ),
        ),
      );
      addTearDown(fixture.dispose);
      await showAffiliate(tester, fixture, size: const Size(1280, 1000));
      expect(find.text('Openstaand saldo: EUR 30,00'), findsOneWidget);
      expect(find.text('Beschikbaar saldo: EUR 20,00'), findsOneWidget);
      expect(find.text('Uitbetaald: EUR 5,00'), findsOneWidget);
      expect(find.text('Betalingen in beoordeling: 3'), findsOneWidget);
      expect(find.text('Goedgekeurd, nog niet uitbetaald'), findsOneWidget);
      expect(
        find.text('Klaargezet voor de bank, nog niet uitbetaald'),
        findsOneWidget,
      );
      fixture.replace(null);
      await tester.pumpAndSettle();
      expect(find.textContaining('EUR'), findsNothing);
      expect(find.byKey(const Key('affiliate_code')), findsNothing);
      expect(
        find.text('Je account is gewijzigd. Vernieuw je overzicht.'),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('unavailable never becomes empty balance and retry is owned', (
    tester,
  ) async {
    var calls = 0;
    final fixture = AffiliateFixture(
      http: MockClient((_) async {
        calls++;
        return calls == 1
            ? response({'ok': false}, status: 503)
            : response(affiliateOverview());
      }),
    );
    addTearDown(fixture.dispose);
    await showAffiliate(tester, fixture);
    expect(
      find.text('Je overzicht is momenteel niet beschikbaar.'),
      findsOneWidget,
    );
    expect(find.text('Er is nog geen opgebouwd saldo.'), findsNothing);
    await tester.tap(find.byKey(const Key('affiliate_retry')));
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(find.byKey(const Key('affiliate_terms')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'late personal A application cannot display private data after B login',
    (tester) async {
      final pending = Completer<http.Response>();
      final fixture = AffiliateFixture(
        http: MockClient(
          (request) async => request.method == 'POST'
              ? pending.future
              : response(affiliateOverview()),
        ),
      );
      addTearDown(fixture.dispose);
      await showAffiliate(tester, fixture);
      await tester.enterText(
        find.byKey(const Key('affiliate_name')),
        'A draft',
      );
      await tester.tap(find.byKey(const Key('affiliate_accept')));
      await tester.pump();
      await tester.ensureVisible(find.byKey(const Key('affiliate_apply')));
      await tester.tap(find.byKey(const Key('affiliate_apply')));
      await tester.pump();
      fixture.replace(affiliateSession('B'));
      await tester.pump();
      pending.complete(response(affiliateOverview(status: 'active')));
      await tester.pumpAndSettle();
      expect(find.text('A draft'), findsNothing);
      expect(find.byKey(const Key('affiliate_code')), findsNothing);
      expect(find.text('Actief'), findsNothing);
      expect(fixture.current!.customerId, 'B');
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'history failure is honest and retry does not erase outstanding balance',
    (tester) async {
      var historyCalls = 0;
      final fixture = AffiliateFixture(
        http: MockClient((request) async {
          if (request.url.path == '/affiliate/entries')
            return response({'ok': true, 'items': [], 'next_cursor': null});
          if (request.url.path != '/affiliate/payouts')
            return response(affiliateOverview(status: 'pending'));
          historyCalls++;
          return historyCalls == 1
              ? response({'ok': false}, status: 503)
              : response({'ok': true, 'items': [], 'next_cursor': null});
        }),
      );
      addTearDown(fixture.dispose);
      await showAffiliate(tester, fixture);
      expect(find.text('Er zijn nog geen uitbetalingen.'), findsNothing);
      await tester.ensureVisible(
        find.byKey(const Key('affiliate_history_retry')),
      );
      await tester.tap(find.byKey(const Key('affiliate_history_retry')));
      await tester.pumpAndSettle();
      expect(historyCalls, 2);
      expect(find.text('Er zijn nog geen uitbetalingen.'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'personal sign in callback reloads overview, returning page keeps one route',
    (tester) async {
      final fixture = AffiliateFixture(
        guest: true,
        http: MockClient((_) async => response(affiliateOverview())),
      );
      addTearDown(fixture.dispose);
      var logins = 0;
      await showAffiliate(
        tester,
        fixture,
        signIn: (context) async {
          logins++;
          fixture.replace(affiliateSession('A'));
        },
      );
      expect(find.byKey(const Key('affiliate_signin')), findsOneWidget);
      await tester.tap(find.byKey(const Key('affiliate_signin')));
      await tester.pumpAndSettle();
      expect(logins, 1);
      expect(find.byKey(const Key('affiliate_terms')), findsOneWidget);
      expect(find.byType(AffiliatePage), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final language in AppLanguage.values) {
    testWidgets('labels work in $language without layout overflow', (
      tester,
    ) async {
      appLanguageNotifier.value = language;
      final fixture = AffiliateFixture(
        http: MockClient((_) async => response(affiliateOverview())),
      );
      addTearDown(fixture.dispose);
      await showAffiliate(tester, fixture, size: const Size(320, 700));
      expect(find.text('Fixturevoorwaarden van de server.'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
