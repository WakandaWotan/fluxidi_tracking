import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/customer_session_store.dart';
import 'package:fluxidi_tracking/affiliate/affiliate_page.dart';
import 'package:fluxidi_tracking/affiliate/affiliate_admin_page.dart';
import 'package:fluxidi_tracking/affiliate/affiliate_admin_repository.dart';
import 'package:fluxidi_tracking/affiliate/affiliate_admin_models.dart';
import 'package:fluxidi_tracking/affiliate/affiliate_models.dart';
import 'package:fluxidi_tracking/affiliate/affiliate_repository.dart';
import 'package:fluxidi_tracking/affiliate/affiliate_labels.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'affiliate_fixture.dart';

http.Response reply(Map<String, dynamic> data, [int status = 200]) =>
    http.Response(jsonEncode(data), status, headers: affiliatePrivateHeaders);

Map<String, dynamic> businessOverview({
  String status = 'pending',
  String type = 'business',
  String? registration,
  String? vat,
  int revision = 7,
}) => affiliateOverview(status: status)
  ..addAll({
    'revision': revision,
    'profile': <String, dynamic>{
      'display_name': 'Actual Applicant',
      'applicant_type': type,
      if (registration != null) 'company_registration_number': registration,
      if (vat != null) 'vat_number': vat,
    },
    'bank_verified': true,
    'bank_revision': 3,
    'balances': [
      {
        'currency': 'EUR',
        'balance_cents': 400,
        'reserved_cents': 100,
        'available_cents': 300,
        'paid_cents': 200,
      },
    ],
  });

http.Response emptyPage() =>
    reply({'ok': true, 'items': [], 'next_cursor': null});
Matcher fails(AffiliateFailure failure) => throwsA(
  isA<AffiliateException>().having((e) => e.failure, 'failure', failure),
);

Future<void> showPage(
  WidgetTester tester,
  AffiliateFixture fixture, {
  Size size = const Size(600, 1400),
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

Future<void> chooseType(WidgetTester tester, String label) async {
  await tester.ensureVisible(find.byKey(const Key('affiliate_applicant_type')));
  await tester.tap(find.byKey(const Key('affiliate_applicant_type')));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

Future<void> openEdit(WidgetTester tester) async {
  await tester.ensureVisible(
    find.byKey(const Key('affiliate_edit_identifiers')),
  );
  await tester.tap(find.byKey(const Key('affiliate_edit_identifiers')));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => appLanguageNotifier.value = AppLanguage.nl);
  tearDown(() => appLanguageNotifier.value = AppLanguage.en);
  testWidgets('business application has actual optional identifier inputs', (
    tester,
  ) async {
    final f = AffiliateFixture(
      http: MockClient((_) async => reply(affiliateOverview())),
    );
    addTearDown(f.dispose);
    await showPage(tester, f);
    await tester.ensureVisible(
      find.byKey(const Key('affiliate_applicant_type')),
    );
    await tester.tap(find.byKey(const Key('affiliate_applicant_type')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bedrijf').last);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('affiliate_company_registration_number')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('affiliate_vat_number')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('CEO sees real business identifiers in application review', (
    tester,
  ) async {
    final f = AffiliateFixture(
      http: MockClient(
        (r) async => reply(
          r.url.path == '/affiliate/me'
              ? (affiliateOverview(status: 'active')..['can_administer'] = true)
              : {
                  'ok': true,
                  'items': [
                    {
                      'id': 'fixture_business',
                      'status': 'pending',
                      'revision': 4,
                      'profile': {
                        'display_name': 'Fixture',
                        'applicant_type': 'business',
                        'company_registration_number': 'Real Company 123',
                        'vat_number': 'Real VAT 456',
                      },
                      'bank_revision': 0,
                      'bank_verified': 0,
                    },
                  ],
                  'next_cursor': null,
                },
        ),
      ),
    );
    addTearDown(f.dispose);
    final owned = await f.repository.loadOverview();
    await tester.pumpWidget(
      MaterialApp(
        home: AffiliateAdminPage(
          repository: AffiliateAdminRepository(f.repository, owned),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Real Company 123'), findsOneWidget);
    expect(find.textContaining('Real VAT 456'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  test(
    'typed own and CEO profiles preserve actual identifiers and legacy unknowns',
    () {
      final json = businessOverview(registration: ' ab-123 ', vat: ' nl-x-9 ');
      final own = AffiliateOverview.parse(json, 'A');
      expect(own.profile!.companyRegistrationNumber, ' ab-123 ');
      expect(own.profile!.vatNumber, ' nl-x-9 ');
      final legacy = AffiliateOverview.parse(businessOverview(), 'A');
      expect(legacy.profile!.companyRegistrationNumber, '');
      expect(legacy.profile!.vatNumber, '');
      final ceo = AffiliateApplication.parse({
        'id': 'A',
        'status': 'pending',
        'revision': 7,
        'bank_revision': 3,
        'bank_verified': 1,
        'profile': json['profile'],
      });
      expect(ceo.companyRegistrationNumber, ' ab-123 ');
      expect(ceo.vatNumber, ' nl-x-9 ');
      expect(
        AffiliateOverview.parse(
          affiliateOverview(status: 'pending'),
          'A',
        ).profile,
        isNull,
      );
    },
  );

  test(
    'typed own profile rejects malformed identifiers and mixed personal data',
    () {
      for (final bad in [
        123,
        'x' * 65,
        'bad\nnumber',
        'bad\u0085number',
        'bad\u2028number',
        'bad\u2029number',
      ]) {
        final json = businessOverview();
        (json['profile'] as Map)['vat_number'] = bad;
        expect(() => AffiliateOverview.parse(json, 'A'), throwsFormatException);
        expect(
          () => AffiliateApplication.parse({
            'id': 'A',
            'status': 'pending',
            'revision': 7,
            'bank_revision': 0,
            'profile': json['profile'],
          }),
          throwsFormatException,
        );
      }
      expect(
        () => AffiliateOverview.parse(
          businessOverview(type: 'person', vat: 'not-personal'),
          'A',
        ),
        throwsFormatException,
      );
      expect(affiliateIdentifier('x' * 64), 'x' * 64);
    },
  );

  test(
    'business creation sends exact optional identifiers under personal bearer',
    () async {
      var posts = 0;
      final f = AffiliateFixture(
        http: MockClient((r) async {
          if (r.method == 'GET') return reply(affiliateOverview());
          posts++;
          expect(r.url.path, '/affiliate/application');
          expect(r.headers['Authorization'], 'Bearer personal_fixture_A');
          expect(jsonDecode(r.body), {
            'display_name': 'Actual Applicant',
            'applicant_type': 'business',
            'company_registration_number': ' ab-123 ',
            'vat_number': ' nl-x-9 ',
            'terms_version': 'approved_fixture_v1',
            'accepted': true,
          });
          return reply(
            businessOverview(registration: ' ab-123 ', vat: ' nl-x-9 '),
          );
        }),
      );
      addTearDown(f.dispose);
      final result = await f.repository.apply(
        await f.repository.loadOverview(),
        displayName: 'Actual Applicant',
        accepted: true,
        applicantType: 'business',
        companyRegistrationNumber: ' ab-123 ',
        vatNumber: ' nl-x-9 ',
      );
      expect(posts, 1);
      expect(result.data.profile!.vatNumber, ' nl-x-9 ');
    },
  );

  test(
    'blank identifiers remain optional without any inferred business number',
    () async {
      final f = AffiliateFixture(
        http: MockClient((r) async {
          if (r.method == 'GET') return reply(affiliateOverview());
          final body = jsonDecode(r.body) as Map;
          expect(body.containsKey('company_registration_number'), false);
          expect(body.containsKey('vat_number'), false);
          return reply(businessOverview());
        }),
      );
      addTearDown(f.dispose);
      final result = await f.repository.apply(
        await f.repository.loadOverview(),
        displayName: 'Actual Applicant',
        accepted: true,
        applicantType: 'business',
      );
      expect(result.data.profile!.vatNumber, '');
    },
  );

  test(
    'invalid or personal identifiers are rejected before any POST',
    () async {
      var posts = 0;
      final f = AffiliateFixture(
        http: MockClient((r) async {
          if (r.method == 'POST') posts++;
          return reply(affiliateOverview());
        }),
      );
      addTearDown(f.dispose);
      final own = await f.repository.loadOverview();
      for (final bad in [
        'x' * 65,
        'bad\n',
        'bad\u0085',
        'bad\u2028',
        'bad\u2029',
      ]) {
        await expectLater(
          f.repository.apply(
            own,
            displayName: 'Actual Applicant',
            accepted: true,
            applicantType: 'business',
            vatNumber: bad,
          ),
          fails(AffiliateFailure.identifiersInvalid),
        );
      }
      await expectLater(
        f.repository.apply(
          own,
          displayName: 'Actual Applicant',
          accepted: true,
          vatNumber: 'supplied-for-person',
        ),
        fails(AffiliateFailure.identifiersInvalid),
      );
      expect(posts, 0);
    },
  );

  test(
    'pending business update sends exact revision, clears blank and keeps server money/bank/terms',
    () async {
      var posts = 0;
      final f = AffiliateFixture(
        http: MockClient((r) async {
          if (r.method == 'GET')
            return reply(businessOverview(registration: 'old', vat: 'old-vat'));
          posts++;
          expect(r.url.path, '/affiliate/application/identifiers');
          expect(r.headers['Authorization'], 'Bearer personal_fixture_A');
          expect(jsonDecode(r.body), {
            'expected_revision': 7,
            'company_registration_number': ' exact-new ',
            'vat_number': '',
          });
          return reply(
            businessOverview(registration: ' exact-new ', vat: '', revision: 8),
          );
        }),
      );
      addTearDown(f.dispose);
      final result = await f.repository.updateApplicationIdentifiers(
        await f.repository.loadOverview(),
        companyRegistrationNumber: ' exact-new ',
        vatNumber: '',
      );
      expect(posts, 1);
      expect(result.data.revision, 8);
      expect(result.data.status, 'pending');
      expect(result.data.profile!.companyRegistrationNumber, ' exact-new ');
      expect(result.data.profile!.vatNumber, '');
      expect(result.data.bankVerified, true);
      expect(result.data.bankRevision, 3);
      expect(result.data.termsVersion, 'approved_fixture_v1');
      expect(result.data.balances.single.balanceCents, 400);
    },
  );

  for (final state in [
    'active',
    'rejected',
    'suspended',
    'not_enrolled',
    'pending-person',
    'pending-unknown',
  ]) {
    test('no identifier update request for $state', () async {
      var posts = 0;
      final json = state == 'pending-unknown'
          ? affiliateOverview(status: 'pending')
          : businessOverview(
              status: state == 'pending-person' ? 'pending' : state,
              type: state == 'pending-person' ? 'person' : 'business',
            );
      final f = AffiliateFixture(
        http: MockClient((r) async {
          if (r.method == 'POST') posts++;
          return reply(json);
        }),
      );
      addTearDown(f.dispose);
      await expectLater(
        f.repository.updateApplicationIdentifiers(
          await f.repository.loadOverview(),
          companyRegistrationNumber: 'new',
          vatNumber: '',
        ),
        fails(AffiliateFailure.termsChanged),
      );
      expect(posts, 0);
    });
  }

  for (final status in [200, 401, 409]) {
    for (final samePerson in [false, true]) {
      test(
        'late identifier $status cannot enter ${samePerson ? 'renewed A' : 'B'} session',
        () async {
          final pending = Completer<http.Response>(),
              started = Completer<void>();
          final f = AffiliateFixture(
            http: MockClient((r) async {
              if (r.method == 'GET') return reply(businessOverview());
              expect(r.headers['Authorization'], 'Bearer personal_fixture_A');
              started.complete();
              return pending.future;
            }),
          );
          addTearDown(f.dispose);
          final operation = f.repository.updateApplicationIdentifiers(
            await f.repository.loadOverview(),
            companyRegistrationNumber: 'A-private',
            vatNumber: '',
          );
          final assertion = expectLater(
            operation,
            fails(AffiliateFailure.sessionChanged),
          );
          await started.future;
          final replacement = samePerson
              ? CustomerSession.fromJson(
                  affiliateSession('A').toJson()
                    ..['customerSessionToken'] = 'renewed_fixture_A'
                    ..['customer_session_token'] = 'renewed_fixture_A',
                )
              : affiliateSession('B');
          f.replace(replacement);
          if (samePerson)
            expect(replacement.customerSessionToken, 'renewed_fixture_A');
          pending.complete(
            reply(
              businessOverview(registration: 'A-private', revision: 8),
              status,
            ),
          );
          await assertion;
          expect(f.current, same(replacement));
        },
      );
    }
  }

  test(
    'current stale revision and invalid identifier response remain rejected',
    () async {
      var count = 0;
      final f = AffiliateFixture(
        http: MockClient((r) async {
          if (r.method == 'GET') return reply(businessOverview());
          count++;
          return reply({
            'ok': false,
            'error': count == 1
                ? 'affiliate_revision_conflict'
                : 'affiliate_application_identifier_invalid',
          }, count == 1 ? 409 : 400);
        }),
      );
      addTearDown(f.dispose);
      final own = await f.repository.loadOverview();
      await expectLater(
        f.repository.updateApplicationIdentifiers(
          own,
          companyRegistrationNumber: 'new',
          vatNumber: '',
        ),
        fails(AffiliateFailure.termsChanged),
      );
      await expectLater(
        f.repository.updateApplicationIdentifiers(
          own,
          companyRegistrationNumber: 'new',
          vatNumber: '',
        ),
        fails(AffiliateFailure.identifiersInvalid),
      );
      expect(f.current!.customerId, 'A');
      expect(own.data.revision, 7);
    },
  );

  for (final language in AppLanguage.values) {
    testWidgets(
      'pending business owns localized optional identifier dialog $language on phone',
      (tester) async {
        appLanguageNotifier.value = language;
        var posts = 0;
        final f = AffiliateFixture(
          http: MockClient((r) async {
            if (r.url.path == '/affiliate/me') return reply(businessOverview());
            if (r.method == 'GET') return emptyPage();
            posts++;
            expect(jsonDecode(r.body), {
              'expected_revision': 7,
              'company_registration_number': '',
              'vat_number': '',
            });
            return reply(businessOverview(revision: 7));
          }),
        );
        addTearDown(f.dispose);
        await showPage(tester, f, size: const Size(400, 800));
        expect(
          find.textContaining(affiliateLabel('identifierUnknown', language)),
          findsNWidgets(2),
        );
        await openEdit(tester);
        expect(
          find.text(affiliateLabel('editIdentifiers', language)),
          findsWidgets,
        );
        final field = tester.widget<TextFormField>(
          find.byKey(const Key('affiliate_form_vat_number')),
        );
        expect(field.controller!.text, '');
        expect(
          tester
              .widget<TextField>(
                find.descendant(
                  of: find.byKey(const Key('affiliate_form_vat_number')),
                  matching: find.byType(TextField),
                ),
              )
              .maxLength,
          64,
        );
        expect(
          find.text(affiliateLabel('vatNumber', language)),
          findsOneWidget,
        );
        await tester.tap(find.byKey(const Key('affiliate_form_submit')));
        await tester.pumpAndSettle();
        expect(posts, 1);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets(
    'pending edit uses real server fields and submits exact untrimmed values',
    (tester) async {
      var posts = 0;
      final f = AffiliateFixture(
        http: MockClient((r) async {
          if (r.url.path == '/affiliate/me')
            return reply(
              businessOverview(
                registration: ' saved-number ',
                vat: 'saved-vat',
              ),
            );
          if (r.method == 'GET') return emptyPage();
          posts++;
          expect(jsonDecode(r.body), {
            'expected_revision': 7,
            'company_registration_number': ' saved-number ',
            'vat_number': ' edited-vat ',
          });
          return reply(
            businessOverview(
              registration: ' saved-number ',
              vat: ' edited-vat ',
              revision: 8,
            ),
          );
        }),
      );
      addTearDown(f.dispose);
      await showPage(tester, f);
      await openEdit(tester);
      expect(
        tester
            .widget<TextFormField>(
              find.byKey(
                const Key('affiliate_form_company_registration_number'),
              ),
            )
            .controller!
            .text,
        ' saved-number ',
      );
      await tester.enterText(
        find.byKey(const Key('affiliate_form_vat_number')),
        ' edited-vat ',
      );
      await tester.tap(find.byKey(const Key('affiliate_form_submit')));
      await tester.pumpAndSettle();
      expect(posts, 1);
      expect(find.textContaining(' edited-vat '), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final state in ['active', 'rejected', 'suspended', 'pending-person']) {
    testWidgets('$state view is read-only for business identifiers', (
      tester,
    ) async {
      final f = AffiliateFixture(
        http: MockClient(
          (r) async => r.url.path == '/affiliate/me'
              ? reply(
                  businessOverview(
                    status: state == 'pending-person' ? 'pending' : state,
                    type: state == 'pending-person' ? 'person' : 'business',
                    registration: state == 'pending-person'
                        ? null
                        : 'readonly-number',
                  ),
                )
              : emptyPage(),
        ),
      );
      addTearDown(f.dispose);
      await showPage(tester, f);
      expect(find.byKey(const Key('affiliate_edit_identifiers')), findsNothing);
      expect(
        find.textContaining('readonly-number'),
        state == 'pending-person' ? findsNothing : findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets(
    'logout clears identifiers in covered owned edit dialog and retains unrelated route',
    (tester) async {
      var posts = 0;
      final f = AffiliateFixture(
        http: MockClient((r) async {
          if (r.method == 'POST') posts++;
          return r.url.path == '/affiliate/me'
              ? reply(businessOverview())
              : emptyPage();
        }),
      );
      addTearDown(f.dispose);
      await showPage(tester, f);
      await openEdit(tester);
      final field = find.byKey(const Key('affiliate_form_vat_number'));
      await tester.enterText(field, 'private-vat-draft');
      final controller = tester.widget<TextFormField>(field).controller!;
      final navigator = Navigator.of(tester.element(find.byType(AlertDialog)));
      unawaited(
        navigator.push(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('Unrelated help')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      f.replace(null);
      expect(controller.text, '');
      await tester.pumpAndSettle();
      expect(find.text('Unrelated help'), findsOneWidget);
      expect(find.byType(AlertDialog, skipOffstage: false), findsNothing);
      expect(find.text('private-vat-draft', skipOffstage: false), findsNothing);
      expect(posts, 0);
      navigator.pop();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('affiliate_edit_identifiers')), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('late A edit response never renders after B replaced owner', (
    tester,
  ) async {
    final pending = Completer<http.Response>();
    final f = AffiliateFixture(
      http: MockClient((r) async {
        if (r.method == 'POST') return pending.future;
        return r.url.path == '/affiliate/me'
            ? reply(businessOverview())
            : emptyPage();
      }),
    );
    addTearDown(f.dispose);
    await showPage(tester, f);
    await openEdit(tester);
    await tester.enterText(
      find.byKey(const Key('affiliate_form_vat_number')),
      'A-private-edit',
    );
    await tester.tap(find.byKey(const Key('affiliate_form_submit')));
    await tester.pump();
    f.replace(affiliateSession('B'));
    pending.complete(
      reply(businessOverview(vat: 'A-private-edit', revision: 8)),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('A-private-edit'), findsNothing);
    expect(find.byKey(const Key('affiliate_own_vat_number')), findsNothing);
    expect(f.current!.customerId, 'B');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'personal switch and logout evict optional creation identifier drafts',
    (tester) async {
      final f = AffiliateFixture(
        http: MockClient((_) async => reply(affiliateOverview())),
      );
      addTearDown(f.dispose);
      await showPage(tester, f);
      await chooseType(tester, 'Bedrijf');
      await tester.enterText(
        find.byKey(const Key('affiliate_vat_number')),
        'private-vat-draft',
      );
      final controller = tester
          .widget<TextField>(find.byKey(const Key('affiliate_vat_number')))
          .controller!;
      await chooseType(tester, 'Persoon');
      expect(controller.text, '');
      expect(find.byKey(const Key('affiliate_vat_number')), findsNothing);
      await chooseType(tester, 'Bedrijf');
      expect(controller.text, '');
      await tester.enterText(
        find.byKey(const Key('affiliate_vat_number')),
        'private-vat-draft',
      );
      f.replace(null);
      expect(controller.text, '');
      await tester.pumpAndSettle();
      expect(find.text('private-vat-draft'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'actual business application form posts supplied identifiers without guesses',
    (tester) async {
      var posts = 0;
      final f = AffiliateFixture(
        http: MockClient((r) async {
          if (r.method == 'POST') {
            posts++;
            expect(r.headers['Authorization'], 'Bearer personal_fixture_A');
            expect(r.url.path, '/affiliate/application');
            expect(jsonDecode(r.body), {
              'display_name': 'Actual Applicant',
              'applicant_type': 'business',
              'company_registration_number': ' typed-company ',
              'vat_number': ' typed-vat ',
              'terms_version': 'approved_fixture_v1',
              'accepted': true,
            });
            return reply(
              businessOverview(
                registration: ' typed-company ',
                vat: ' typed-vat ',
              ),
            );
          }
          return r.url.path == '/affiliate/me'
              ? reply(affiliateOverview())
              : emptyPage();
        }),
      );
      addTearDown(f.dispose);
      await showPage(tester, f);
      await tester.enterText(
        find.byKey(const Key('affiliate_name')),
        'Actual Applicant',
      );
      await chooseType(tester, 'Bedrijf');
      await tester.enterText(
        find.byKey(const Key('affiliate_company_registration_number')),
        ' typed-company ',
      );
      await tester.enterText(
        find.byKey(const Key('affiliate_vat_number')),
        ' typed-vat ',
      );
      await tester.ensureVisible(find.byKey(const Key('affiliate_accept')));
      await tester.tap(find.byKey(const Key('affiliate_accept')));
      await tester.pump();
      await tester.ensureVisible(find.byKey(const Key('affiliate_apply')));
      await tester.tap(find.byKey(const Key('affiliate_apply')));
      await tester.pumpAndSettle();
      expect(posts, 1);
      expect(find.textContaining(' typed-company '), findsOneWidget);
      expect(find.textContaining(' typed-vat '), findsOneWidget);
      expect(find.byKey(const Key('affiliate_code')), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
