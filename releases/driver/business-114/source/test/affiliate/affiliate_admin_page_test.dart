import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/affiliate/affiliate_admin_page.dart';
import 'package:fluxidi_tracking/affiliate/affiliate_admin_repository.dart';
import 'package:fluxidi_tracking/affiliate/affiliate_form_dialog.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'affiliate_fixture.dart';
import 'affiliate_admin_repository_test.dart' as data;

http.Response reply(Map<String, dynamic> json, [int code = 200]) =>
    http.Response(jsonEncode(json), code, headers: affiliatePrivateHeaders);
AffiliateFixture fixture(
  Future<http.Response> Function(http.Request) call, {
  bool ceo = true,
}) => AffiliateFixture(
  http: MockClient((r) async {
    if (r.url.path == '/affiliate/me')
      return reply(
        affiliateOverview(status: 'active')..['can_administer'] = ceo,
      );
    return call(r);
  }),
);
Future<AffiliateAdminRepository> show(
  WidgetTester tester,
  AffiliateFixture fixture, {
  Size size = const Size(400, 800),
}) async {
  final owned = await fixture.repository.loadOverview();
  final repository = AffiliateAdminRepository(fixture.repository, owned);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(home: AffiliateAdminPage(repository: repository)),
  );
  await tester.pumpAndSettle();
  return repository;
}

void main() {
  setUp(() => appLanguageNotifier.value = AppLanguage.nl);
  tearDown(() => appLanguageNotifier.value = AppLanguage.en);
  for (final size in [const Size(400, 800), const Size(1280, 1000)]) {
    testWidgets(
      'CEO phone/tablet application review requires decision and checked evidence $size',
      (tester) async {
        var posts = 0;
        var approved = false;
        final f = fixture((r) async {
          expect(r.headers['Authorization'], 'Bearer personal_fixture_A');
          if (r.method == 'POST') {
            posts++;
            expect(r.url.path, '/affiliate/admin/applications/review');
            expect(jsonDecode(r.body), {
              'affiliate_id': 'person_fixture',
              'expected_revision': 4,
              'status': 'active',
              'review_reference': 'invoice_review_fixture',
            });
            approved = true;
            return reply({'ok': true, 'status': 'active', 'revision': 5});
          }
          return reply({
            'ok': true,
            'items': [
              data.application(
                status: approved ? 'active' : 'pending',
                verified: false,
              ),
            ],
            'next_cursor': null,
          });
        });
        addTearDown(f.dispose);
        await show(tester, f, size: size);
        expect(find.text('Applicant Fixture'), findsOneWidget);
        await tester.ensureVisible(
          find.byKey(const Key('affiliate_review_person_fixture')),
        );
        await tester.tap(
          find.byKey(const Key('affiliate_review_person_fixture')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('affiliate_form_decision')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Goedkeuren').last);
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const Key('affiliate_form_reference')),
          'invoice_review_fixture',
        );
        await tester.tap(find.byKey(const Key('affiliate_form_submit')));
        await tester.pump();
        expect(posts, 0);
        await tester.ensureVisible(
          find.byKey(const Key('affiliate_form_checked')),
        );
        await tester.tap(find.byKey(const Key('affiliate_form_checked')));
        await tester.pump();
        await tester.tap(find.byKey(const Key('affiliate_form_submit')));
        await tester.pumpAndSettle();
        expect(posts, 1);
        expect(find.byType(AlertDialog), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
  testWidgets('non-CEO shows no private admin rows and sends no request', (
    tester,
  ) async {
    var calls = 0;
    final f = fixture((_) async {
      calls++;
      return reply({'ok': true});
    }, ceo: false);
    addTearDown(f.dispose);
    await show(tester, f);
    expect(calls, 0);
    expect(find.text('Je hebt geen toegang tot dit beheer.'), findsOneWidget);
    expect(find.text('Applicant Fixture'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('late loaded A rows after B replacement never render', (
    tester,
  ) async {
    final pending = Completer<http.Response>();
    final f = fixture((_) => pending.future);
    addTearDown(f.dispose);
    final owned = await f.repository.loadOverview();
    await tester.pumpWidget(
      MaterialApp(
        home: AffiliateAdminPage(
          repository: AffiliateAdminRepository(f.repository, owned),
        ),
      ),
    );
    await tester.pump();
    f.replace(affiliateSession('B'));
    await tester.pump();
    pending.complete(
      reply({
        'ok': true,
        'items': [data.application()],
        'next_cursor': null,
      }),
    );
    await tester.pumpAndSettle();
    expect(find.text('Applicant Fixture'), findsNothing);
    expect(f.current!.customerId, 'B');
    expect(find.text('Je hebt geen toegang tot dit beheer.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('logout inside approval dialog removes draft and cannot submit', (
    tester,
  ) async {
    var posts = 0;
    final f = fixture((r) async {
      if (r.method == 'POST') posts++;
      return reply({
        'ok': true,
        'items': [data.application(status: 'pending')],
        'next_cursor': null,
      });
    });
    addTearDown(f.dispose);
    await show(tester, f);
    await tester.ensureVisible(
      find.byKey(const Key('affiliate_review_person_fixture')),
    );
    await tester.tap(find.byKey(const Key('affiliate_review_person_fixture')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('affiliate_form_reference')),
      'private_review_draft',
    );
    f.replace(null);
    await tester.pumpAndSettle();
    expect(find.text('private_review_draft'), findsNothing);
    expect(find.byType(AlertDialog), findsNothing);
    expect(posts, 0);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'covered private dialog removes its own route on logout, retains unrelated route',
    (tester) async {
      final f = fixture(
        (_) async => reply({'ok': true, 'items': [], 'next_cursor': null}),
      );
      addTearDown(f.dispose);
      final owner = (await f.repository.loadOverview()).owner;
      final navigator = GlobalKey<NavigatorState>();
      Map<String, String>? result;
      var completed = false;
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigator,
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  result = await showAffiliateForm(
                    context,
                    repository: f.repository,
                    owner: owner,
                    title: 'bankAdd',
                    fields: const [AffiliateField('iban', 'iban')],
                  );
                  completed = true;
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('affiliate_form_iban')),
        'BE68539007547034',
      );
      unawaited(
        navigator.currentState!.push(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('Independent help page')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      f.replace(null);
      await tester.pumpAndSettle();
      expect(find.text('Independent help page'), findsOneWidget);
      expect(find.byType(AlertDialog, skipOffstage: false), findsNothing);
      expect(completed, true);
      expect(result, isNull);
      navigator.currentState!.pop();
      await tester.pumpAndSettle();
      expect(find.text('Open'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'held receipt gives clear reason and no basis shortcut for chargeback',
    (tester) async {
      final f = fixture(
        (r) async => reply({
          'ok': true,
          'items': r.url.path.endsWith('receipts/review')
              ? [
                  data.receipt(chargeback: 1)
                    ..['reason'] = 'provider_chargeback_requires_review',
                ]
              : [],
          'next_cursor': null,
        }),
      );
      addTearDown(f.dispose);
      await show(tester, f, size: const Size(1280, 1000));
      await tester.tap(find.byKey(const Key('affiliate_admin_receipts')));
      await tester.pumpAndSettle();
      expect(
        find.text('Terugbetaling of terugboeking moet worden gecontroleerd'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('affiliate_basis_tr_fixture')), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'export review shows server money and bank detail, never confirms payment',
    (tester) async {
      var posts = 0;
      final f = fixture((r) async {
        if (r.method == 'POST') {
          posts++;
          expect(r.url.path, '/affiliate/admin/batches/export');
          return reply(data.manifest(exported: true));
        }
        return reply({
          'ok': true,
          'items': r.url.path.endsWith('/batches')
              ? [
                  {
                    'id': 'batch_fixture',
                    'period': '2026-10',
                    'currency': 'EUR',
                    'manifest_hash': 'server_opaque_proof',
                  },
                ]
              : [],
          'next_cursor': null,
        });
      });
      addTearDown(f.dispose);
      await show(tester, f, size: const Size(1280, 1000));
      await tester.tap(find.byKey(const Key('affiliate_admin_batches')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('affiliate_export_batch_fixture')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('affiliate_form_checked')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('affiliate_form_submit')));
      await tester.pumpAndSettle();
      expect(posts, 1);
      expect(find.text('EUR 12,50'), findsOneWidget);
      expect(find.text('BE68539007547034'), findsOneWidget);
      expect(
        find.textContaining('bankformaat is nog niet gevalideerd'),
        findsOneWidget,
      );
      expect(find.text('Uitbetaald'), findsNothing);
      f.replace(null);
      await tester.pumpAndSettle();
      expect(find.text('BE68539007547034'), findsNothing);
      expect(find.text('EUR 12,50'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'administration unavailable stays honest and explicit refresh recovers',
    (tester) async {
      var calls = 0;
      final f = fixture((_) async {
        calls++;
        return calls == 1
            ? reply({'ok': false}, 503)
            : reply({
                'ok': true,
                'items': [data.application()],
                'next_cursor': null,
              });
      });
      addTearDown(f.dispose);
      await show(tester, f);
      expect(find.byKey(const Key('affiliate_admin_error')), findsOneWidget);
      expect(find.text('Applicant Fixture'), findsNothing);
      await tester.tap(find.byKey(const Key('affiliate_admin_refresh')));
      await tester.pumpAndSettle();
      expect(calls, 2);
      expect(find.text('Applicant Fixture'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
