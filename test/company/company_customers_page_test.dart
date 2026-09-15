import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/company/company_agenda_labels.dart';
import 'package:fluxidi_tracking/company/company_customer_dossier.dart';
import 'package:fluxidi_tracking/company/company_customer_form_page.dart';
import 'package:fluxidi_tracking/company/company_customer_labels.dart';
import 'package:fluxidi_tracking/company/company_ops_workspace_page.dart';
import 'package:fluxidi_tracking/company/company_customer_models.dart';
import 'package:fluxidi_tracking/company/company_customers_page.dart';
import 'package:fluxidi_tracking/company/company_customers_repository.dart';

class _FakeCustomersRepository extends CompanyCustomersRepository {
  _FakeCustomersRepository({
    this.pages,
    this.detail,
    this.listError,
    this.emptyHasMore = false,
  }) : super(
         scopeQuery: const <String, String>{
           'tenant_id': 'TA',
           'company_id': 'CA',
         },
         headers: () async => const <String, String>{},
         listTransport: ({
           required path,
           required query,
           required headers,
         }) async => <String, dynamic>{'ok': true, 'items': <dynamic>[]},
         sendTransport: ({
           required method,
           required path,
           required query,
           required body,
           required headers,
           idempotencyKey,
         }) async => <String, dynamic>{
           'ok': true,
           'customer': _customerJson('cus_1', 'Ada'),
         },
       );

  List<CompanyCustomerListPage>? pages;
  CompanyCustomer? detail;
  CompanyCustomerException? listError;
  bool emptyHasMore;
  final List<String> listCursors = <String>[];
  final List<String> listQueries = <String>[];
  int createCalls = 0;

  static Map<String, dynamic> _customerJson(String id, String name) {
    return <String, dynamic>{
      'customer_id': id,
      'display_name': name,
      'status': 'active',
      'revision': 1,
      'email': 'ada@example.test',
      'internal_notes': 'staff only',
    };
  }

  @override
  Future<CompanyCustomerListPage> list({
    String status = 'active',
    String query = '',
    String cursor = '',
  }) async {
    listCursors.add(cursor);
    listQueries.add(query);
    if (listError != null) throw listError!;
    if (emptyHasMore && query.isNotEmpty) {
      return CompanyCustomerListPage(
        items: const <CompanyCustomerListItem>[],
        hasMore: true,
        nextCursor: 'more-${listCursors.length}',
        totalCount: null,
      );
    }
    if (pages == null || pages!.isEmpty) {
      return const CompanyCustomerListPage(
        items: <CompanyCustomerListItem>[],
        hasMore: false,
        nextCursor: null,
        totalCount: 0,
      );
    }
    if (cursor.isEmpty) return pages!.first;
    for (var i = 0; i < pages!.length; i += 1) {
      if (pages![i].nextCursor == cursor && i + 1 < pages!.length) {
        return pages![i + 1];
      }
    }
    return pages!.last;
  }

  @override
  Future<CompanyCustomer> getById(String customerId) async {
    return detail ??
        parseCompanyCustomer(_customerJson(customerId, 'Ada'));
  }

  @override
  Future<CompanyCustomerMutationResult> create(
    CompanyCustomerWrite write, {
    String? idempotencyKey,
  }) async {
    createCalls += 1;
    await Future<void>.delayed(const Duration(milliseconds: 40));
    return CompanyCustomerMutationResult(
      customer: parseCompanyCustomer(_customerJson('cus_new', write.displayName)),
    );
  }
}

Future<void> _pumpPage(
  WidgetTester tester, {
  required _FakeCustomersRepository repository,
  required Size size,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(size: size),
        child: CompanyCustomersPage(
          repository: repository,
          language: AppLanguage.nl,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

CompanyCustomerListItem _item(String id, String name) {
  return CompanyCustomerListItem(
    customerId: id,
    displayName: name,
    companyName: '',
    phoneMasked: '***50',
    emailMasked: '*@example.test',
    status: 'active',
    updatedAt: '2026-09-10T00:00:00.000Z',
  );
}

void main() {
  testWidgets('empty loading error and offline states stay honest', (
    tester,
  ) async {
    final loading = _FakeCustomersRepository();
    await tester.binding.setSurfaceSize(const Size(390, 844));
    await tester.pumpWidget(
      MaterialApp(
        home: CompanyCustomersPage(
          key: const ValueKey<String>('customers-loading'),
          repository: loading,
          language: AppLanguage.nl,
        ),
      ),
    );
    expect(find.text(kCompanyCustomersLoading.of(AppLanguage.nl)), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.text(kCompanyCustomersEmptyActive.of(AppLanguage.nl)), findsOneWidget);

    final failed = _FakeCustomersRepository(
      listError: const CompanyCustomerException('boom'),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: CompanyCustomersPage(
          key: const ValueKey<String>('customers-failed'),
          repository: failed,
          language: AppLanguage.nl,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text(kCompanyCustomersError.of(AppLanguage.nl)), findsOneWidget);

    final offline = _FakeCustomersRepository(
      listError: const CompanyCustomerException('transport_failed', offline: true),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: CompanyCustomersPage(
          key: const ValueKey<String>('customers-offline'),
          repository: offline,
          language: AppLanguage.nl,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text(kCompanyCustomersOffline.of(AppLanguage.nl)), findsOneWidget);
  });

  testWidgets('search and server cursor load-more', (tester) async {
    final repo = _FakeCustomersRepository(
      pages: <CompanyCustomerListPage>[
        CompanyCustomerListPage(
          items: <CompanyCustomerListItem>[_item('cus_1', 'Ada')],
          hasMore: true,
          nextCursor: 'cursor-2',
          totalCount: 2,
        ),
        CompanyCustomerListPage(
          items: <CompanyCustomerListItem>[_item('cus_2', 'Alan')],
          hasMore: false,
          nextCursor: null,
          totalCount: 2,
        ),
      ],
    );
    await _pumpPage(tester, repository: repo, size: const Size(390, 844));
    expect(find.text('Ada'), findsOneWidget);
    expect(find.byKey(kCompanyCustomersDetailPaneKey), findsNothing);
    await tester.enterText(find.byKey(kCompanyCustomersSearchFieldKey), 'ada');
    await tester.pumpAndSettle();
    expect(repo.listQueries, contains('ada'));
    await tester.tap(find.byKey(kCompanyCustomersLoadMoreKey));
    await tester.pumpAndSettle();
    expect(repo.listCursors, contains('cursor-2'));
    expect(find.text('Alan'), findsOneWidget);
  });

  testWidgets('phone layout keeps the add action and avoids overflow', (
    tester,
  ) async {
    final repo = _FakeCustomersRepository(
      pages: <CompanyCustomerListPage>[
        CompanyCustomerListPage(
          items: <CompanyCustomerListItem>[_item('cus_1', 'Ada')],
          hasMore: false,
          nextCursor: null,
          totalCount: 1,
        ),
      ],
    );
    await _pumpPage(tester, repository: repo, size: const Size(390, 844));
    expect(find.byKey(kCompanyCustomersAddButtonKey), findsOneWidget);
    expect(find.byKey(kCompanyCustomersImportButtonKey), findsOneWidget);
    expect(find.byKey(kCompanyCustomersSearchFieldKey), findsOneWidget);
    expect(find.byKey(kCompanyCustomersDetailPaneKey), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('phone tap opens a full dossier page', (tester) async {
    final repo = _FakeCustomersRepository(
      pages: <CompanyCustomerListPage>[
        CompanyCustomerListPage(
          items: <CompanyCustomerListItem>[_item('cus_1', 'Ada')],
          hasMore: false,
          nextCursor: null,
          totalCount: 1,
        ),
      ],
      detail: parseCompanyCustomer(<String, dynamic>{
        'customer_id': 'cus_1',
        'display_name': 'Ada Lovelace',
        'first_name': 'Ada',
        'last_name': 'Lovelace',
        'status': 'active',
        'revision': 1,
        'email': 'ada@example.test',
        'phone': '+32470000011',
        'company_name': '',
        'internal_notes': 'staff only',
        'addresses': <dynamic>[
          <String, dynamic>{
            'type': 'home',
            'line1': 'Kerkstraat 1',
            'city': 'Gent',
            'postal_code': '9000',
            'country_code': 'BE',
          },
        ],
      }),
    );
    await _pumpPage(tester, repository: repo, size: const Size(390, 844));
    await tester.tap(find.byKey(const Key('company_customer_row_cus_1')));
    await tester.pumpAndSettle();
    expect(find.byKey(kCompanyCustomerDossierKey), findsOneWidget);
    expect(find.text(kCompanyCustomersIdentityGroup.of(AppLanguage.nl)), findsOneWidget);
    expect(find.text(kCompanyCustomersContactGroup.of(AppLanguage.nl)), findsOneWidget);
    expect(find.text(kCompanyCustomersAddresses.of(AppLanguage.nl)), findsOneWidget);
    expect(find.textContaining('niet zichtbaar voor de klant'), findsOneWidget);
    expect(find.textContaining('Kerkstraat 1'), findsOneWidget);
    expect(find.textContaining('staff only'), findsOneWidget);
    expect(find.textContaining(kCompanyCustomersNotFilled.of(AppLanguage.nl)), findsWidgets);
  });

  testWidgets('tablet portrait and landscape expose a second pane', (
    tester,
  ) async {
    final repo = _FakeCustomersRepository(
      pages: <CompanyCustomerListPage>[
        CompanyCustomerListPage(
          items: <CompanyCustomerListItem>[_item('cus_1', 'Ada')],
          hasMore: false,
          nextCursor: null,
          totalCount: 1,
        ),
      ],
      detail: parseCompanyCustomer(<String, dynamic>{
        'customer_id': 'cus_1',
        'display_name': 'Ada',
        'status': 'active',
        'revision': 1,
        'email': 'ada@example.test',
        'internal_notes': 'staff only',
      }),
    );
    for (final size in <Size>[const Size(800, 1280), const Size(1280, 800)]) {
      await _pumpPage(tester, repository: repo, size: size);
      expect(find.byKey(kCompanyCustomersDetailPaneKey), findsOneWidget);
      expect(find.byKey(kCompanyCustomersImportButtonKey), findsOneWidget);
      await tester.tap(find.byKey(const Key('company_customer_row_cus_1')));
      await tester.pumpAndSettle();
      expect(find.textContaining('ada@example.test'), findsWidgets);
      expect(find.textContaining('niet zichtbaar voor de klant'), findsOneWidget);
    }
  });

  testWidgets('desktop split view and a narrow window stay usable', (
    tester,
  ) async {
    final repo = _FakeCustomersRepository(
      pages: <CompanyCustomerListPage>[
        CompanyCustomerListPage(
          items: <CompanyCustomerListItem>[_item('cus_1', 'Ada')],
          hasMore: false,
          nextCursor: null,
          totalCount: 1,
        ),
      ],
      detail: parseCompanyCustomer(<String, dynamic>{
        'customer_id': 'cus_1',
        'display_name': 'Ada',
        'status': 'active',
        'revision': 1,
        'email': 'ada@example.test',
      }),
    );
    await _pumpPage(tester, repository: repo, size: const Size(1440, 900));
    expect(find.byKey(kCompanyCustomersDetailPaneKey), findsOneWidget);
    expect(find.byKey(kCompanyCustomersAddButtonKey), findsOneWidget);
    expect(find.byKey(kCompanyCustomersImportButtonKey), findsOneWidget);
    await _pumpPage(tester, repository: repo, size: const Size(680, 860));
    expect(find.byKey(kCompanyCustomersDetailPaneKey), findsNothing);
    expect(find.byKey(kCompanyCustomersAddButtonKey), findsOneWidget);
    expect(find.byKey(kCompanyCustomersImportButtonKey), findsOneWidget);
  });

  testWidgets('search follows server cursors instead of a final empty page', (
    tester,
  ) async {
    final repo = _FakeCustomersRepository(
      pages: <CompanyCustomerListPage>[
        const CompanyCustomerListPage(
          items: <CompanyCustomerListItem>[],
          hasMore: true,
          nextCursor: 'cursor-needle',
          totalCount: null,
        ),
        CompanyCustomerListPage(
          items: <CompanyCustomerListItem>[_item('cus_n', 'Needle Only')],
          hasMore: false,
          nextCursor: null,
          totalCount: null,
        ),
      ],
    );
    await _pumpPage(tester, repository: repo, size: const Size(390, 844));
    await tester.enterText(find.byKey(kCompanyCustomersSearchFieldKey), 'needle');
    await tester.pumpAndSettle();
    expect(repo.listCursors, contains('cursor-needle'));
    expect(find.text('Needle Only'), findsOneWidget);
    expect(find.text(kCompanyCustomersEmptySearch.of(AppLanguage.nl)), findsNothing);
  });

  testWidgets('search keeps continue when later pages remain unread', (
    tester,
  ) async {
    final repo = _FakeCustomersRepository(emptyHasMore: true);
    await _pumpPage(tester, repository: repo, size: const Size(390, 844));
    await tester.enterText(find.byKey(kCompanyCustomersSearchFieldKey), 'ghost');
    await tester.pumpAndSettle();
    expect(find.text(kCompanyCustomersSearchStillOpen.of(AppLanguage.nl)), findsOneWidget);
    expect(find.byKey(kCompanyCustomersContinueSearchKey), findsOneWidget);
    expect(find.text(kCompanyCustomersEmptySearch.of(AppLanguage.nl)), findsNothing);
  });

  testWidgets('CRM dossier has no calendar and no Rit plannen', (tester) async {
    final repo = _FakeCustomersRepository(
      pages: <CompanyCustomerListPage>[
        CompanyCustomerListPage(
          items: <CompanyCustomerListItem>[_item('cus_1', 'Ada')],
          hasMore: false,
          nextCursor: null,
          totalCount: 1,
        ),
      ],
      detail: parseCompanyCustomer(<String, dynamic>{
        'customer_id': 'cus_1',
        'display_name': 'Ada Lovelace',
        'status': 'active',
        'revision': 1,
        'email': 'ada@example.test',
        'internal_notes': 'staff only',
      }),
    );
    await _pumpPage(tester, repository: repo, size: const Size(1280, 800));
    await tester.tap(find.byKey(const Key('company_customer_row_cus_1')));
    await tester.pumpAndSettle();
    expect(find.byKey(kCompanyCustomerDossierKey), findsOneWidget);
    expect(find.byKey(kCompanyCustomersEditButtonKey), findsOneWidget);
    expect(find.text(kCompanyAgendaPlanRide.of(AppLanguage.nl)), findsNothing);
    expect(find.byKey(kCompanyAgendaPaneKey), findsNothing);
  });

  testWidgets('double submit is blocked on the form', (tester) async {
    final repo = _FakeCustomersRepository();
    await tester.pumpWidget(
      MaterialApp(
        home: CompanyCustomerFormPage(
          repository: repo,
          language: AppLanguage.nl,
        ),
      ),
    );
    await tester.enterText(find.byKey(kCompanyCustomerFormNameKey), 'Ada');
    await tester.enterText(find.byKey(kCompanyCustomerFormEmailKey), 'ada@example.test');
    await tester.pump();
    final save = find.byKey(kCompanyCustomersSaveButtonKey);
    await tester.tap(save);
    await tester.pump();
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(repo.createCalls, 1);
  });
}
