import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/company/company_customer_import_labels.dart';
import 'package:fluxidi_tracking/company/company_customer_import_models.dart';
import 'package:fluxidi_tracking/company/company_customer_import_page.dart';
import 'package:fluxidi_tracking/company/company_customer_import_parse.dart';
import 'package:fluxidi_tracking/company/company_customer_import_session.dart';
import 'package:fluxidi_tracking/company/company_customer_models.dart';
import 'package:fluxidi_tracking/company/company_customers_page.dart';
import 'package:fluxidi_tracking/company/company_customers_repository.dart';

class _FakeImportRepository extends CompanyCustomersRepository {
  _FakeImportRepository({
    this.failFirstBatch = false,
    this.expireImport = false,
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
         }) async => <String, dynamic>{
           'ok': true,
           'import': <String, dynamic>{
             'import_id': 'imp_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
             'added': 1,
             'skipped': 0,
             'failed': 0,
             'processed': 1,
             'rows': <String, dynamic>{
               'r2': <String, dynamic>{
                 'outcome': 'created',
                 'customer_id': 'cus_1',
               },
             },
           },
         },
         sendTransport: ({
           required method,
           required path,
           required query,
           required body,
           required headers,
           idempotencyKey,
         }) async => <String, dynamic>{'ok': true, 'matches': <dynamic>[]},
       );

  final bool failFirstBatch;
  final bool expireImport;
  int lookupCalls = 0;
  int batchCalls = 0;
  final List<Map<String, dynamic>> batchRows = <Map<String, dynamic>>[];

  @override
  Future<List<CompanyCustomerImportCompanyMatch>> lookupImportContacts({
    required String importId,
    required List<Map<String, String>> contacts,
  }) async {
    lookupCalls += 1;
    return const <CompanyCustomerImportCompanyMatch>[];
  }

  @override
  Future<CompanyCustomerImportBatchResult> importBatch({
    required String importId,
    required List<Map<String, dynamic>> rows,
  }) async {
    batchCalls += 1;
    batchRows.addAll(rows);
    if (failFirstBatch && batchCalls == 1) {
      throw const CompanyCustomerException('transport_failed', offline: true);
    }
    return CompanyCustomerImportBatchResult(
      importId: importId,
      added: rows.where((row) => row['decision'] != 'skip').length,
      skipped: rows.where((row) => row['decision'] == 'skip').length,
      failed: 0,
      processed: rows.length,
      rows: [
        for (final row in rows)
          CompanyCustomerImportRowOutcome(
            rowKey: row['row_key']?.toString() ?? '',
            outcome: row['decision'] == 'skip' ? 'skipped' : 'created',
            customerId: 'cus_${row['row_key']}',
            idempotent: failFirstBatch && batchCalls > 1,
          ),
      ],
    );
  }

  @override
  Future<CompanyCustomerImportStatus> getImport(String importId) async {
    if (expireImport) {
      throw const CompanyCustomerException('import_expired');
    }
    return CompanyCustomerImportStatus(
      importId: importId,
      added: 1,
      skipped: 0,
      failed: 0,
      processed: 1,
      rows: <String, CompanyCustomerImportRowOutcome>{
        'r2': const CompanyCustomerImportRowOutcome(
          rowKey: 'r2',
          outcome: 'created',
          customerId: 'cus_1',
        ),
      },
    );
  }
}

Future<void> _pumpImport(
  WidgetTester tester, {
  required _FakeImportRepository repository,
  required Size size,
  CompanyCustomerImportPickedFile? file,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(size: size),
        child: CompanyCustomerImportPage(
          key: ValueKey<String>('import-${size.width}x${size.height}-${file?.name}'),
          repository: repository,
          language: AppLanguage.nl,
          initialFile: file,
          sessionStore: MemoryCompanyCustomerImportSessionStore(),
          importIdFactory: () => 'imp_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
          picker: () async => file,
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

CompanyCustomerImportPickedFile _csvTwo() {
  return CompanyCustomerImportPickedFile(
    name: 'two.csv',
    bytes: utf8.encode(
      'Naam,E-mail\nAda Lovelace,ada@example.test\nAlan,alan@example.test\n',
    ),
  );
}

void main() {
  testWidgets('phone tablet and desktop walk pick map review import', (
    tester,
  ) async {
    for (final size in <Size>[
      const Size(390, 844),
      const Size(800, 1280),
      const Size(1440, 900),
    ]) {
      final repo = _FakeImportRepository();
      await _pumpImport(
        tester,
        repository: repo,
        size: size,
        file: _csvTwo(),
      );
      expect(find.byKey(kCompanyCustomerImportPageKey), findsOneWidget);
      expect(find.byKey(kCompanyCustomerImportNextKey), findsOneWidget);
      await tester.ensureVisible(find.byKey(kCompanyCustomerImportNextKey));
      await tester.tap(find.byKey(kCompanyCustomerImportNextKey));
      await tester.pumpAndSettle();
      expect(find.textContaining('2 / 2 / 0'), findsOneWidget);
      await tester.ensureVisible(find.byKey(kCompanyCustomerImportStartKey));
      await tester.tap(find.byKey(kCompanyCustomerImportStartKey));
      await tester.pumpAndSettle();
      expect(find.byKey(kCompanyCustomerImportResultKey), findsOneWidget);
      expect(repo.batchCalls, greaterThan(0));
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('partial import requires an explicit confirm', (tester) async {
    final repo = _FakeImportRepository();
    await _pumpImport(
      tester,
      repository: repo,
      size: const Size(390, 844),
      file: CompanyCustomerImportPickedFile(
        name: 'partial.csv',
        bytes: utf8.encode('Naam,E-mail\nAda,ada@example.test\nGhost,\n'),
      ),
    );
    if (find.byKey(kCompanyCustomerImportNextKey).evaluate().isEmpty) {
      await tester.tap(find.byKey(kCompanyCustomerImportChooseFileKey));
      await tester.pumpAndSettle();
    }
    await tester.ensureVisible(find.byKey(kCompanyCustomerImportNextKey));
    await tester.tap(find.byKey(kCompanyCustomerImportNextKey));
    await tester.pumpAndSettle();
    expect(find.byKey(kCompanyCustomerImportConfirmPartialKey), findsOneWidget);
    await tester.tap(find.byKey(kCompanyCustomerImportStartKey));
    await tester.pumpAndSettle();
    expect(repo.batchCalls, 0);
    await tester.tap(find.byKey(kCompanyCustomerImportConfirmPartialKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(kCompanyCustomerImportStartKey));
    await tester.pumpAndSettle();
    expect(repo.batchCalls, greaterThan(0));
  });

  testWidgets('timeout after a confirmed write resumes without a second customer', (
    tester,
  ) async {
    final repo = _FakeImportRepository(failFirstBatch: true);
    await _pumpImport(
      tester,
      repository: repo,
      size: const Size(800, 1280),
      file: _csvTwo(),
    );
    if (find.byKey(kCompanyCustomerImportNextKey).evaluate().isEmpty) {
      await tester.tap(find.byKey(kCompanyCustomerImportChooseFileKey));
      await tester.pumpAndSettle();
    }
    await tester.ensureVisible(find.byKey(kCompanyCustomerImportNextKey));
    await tester.tap(find.byKey(kCompanyCustomerImportNextKey));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(kCompanyCustomerImportStartKey));
    await tester.tap(find.byKey(kCompanyCustomerImportStartKey));
    await tester.pumpAndSettle();
    expect(repo.batchCalls, greaterThan(1));
    expect(find.byKey(kCompanyCustomerImportResultKey), findsOneWidget);
  });

  testWidgets('expired server import shows a new-import next step', (
    tester,
  ) async {
    final repo = _FakeImportRepository(expireImport: true);
    final store = MemoryCompanyCustomerImportSessionStore();
    await store.save(
      CompanyCustomerImportSession(
        importId: 'imp_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        companyId: 'CA',
        expiresAt: DateTime.now().add(const Duration(hours: 2)),
        rows: prepareCompanyCustomerImportRows(
          table: parseCompanyCustomerImportBytes(
            bytes: _csvTwo().bytes,
            fileName: _csvTwo().name,
          ),
          mappings: const <String>['display_name', 'email'],
        ),
        outcomes: <String, CompanyCustomerImportRowOutcome>{
          'r1': const CompanyCustomerImportRowOutcome(
            rowKey: 'r1',
            outcome: 'created',
            customerId: 'cus_old',
          ),
        },
        defaultCallingCode: '',
      ),
    );
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(size: Size(390, 844)),
          child: CompanyCustomerImportPage(
            repository: repo,
            language: AppLanguage.nl,
            sessionStore: store,
            importIdFactory: () => 'imp_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.byKey(kCompanyCustomerImportResumeKey));
    await tester.pumpAndSettle();
    expect(
      find.text(kCompanyCustomerImportExpired.of(AppLanguage.nl)),
      findsOneWidget,
    );
    expect(repo.batchCalls, 0);
  });

  testWidgets('metadata-only resume asks for the same file', (tester) async {
    final repo = _FakeImportRepository();
    final bytes = utf8.encode(
      'Naam,E-mail\nAda Lovelace,ada@example.test\nAlan,alan@example.test\n',
    );
    final table = parseCompanyCustomerImportBytes(
      bytes: bytes,
      fileName: 'two.csv',
    );
    final mappings = suggestCompanyCustomerImportMappings(table.headers);
    final store = MemoryCompanyCustomerImportSessionStore();
    await store.save(
      CompanyCustomerImportSession(
        importId: 'imp_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        companyId: 'CA',
        expiresAt: DateTime.now().add(const Duration(hours: 2)),
        rows: const <CompanyCustomerImportPreparedRow>[],
        outcomes: const <String, CompanyCustomerImportRowOutcome>{
          'r1': CompanyCustomerImportRowOutcome(
            rowKey: 'r1',
            outcome: 'created',
            customerId: 'cus_1',
          ),
        },
        defaultCallingCode: '',
        mappings: mappings,
        fingerprint: buildCompanyCustomerImportFingerprint(
          file: CompanyCustomerImportPickedFile(name: 'two.csv', bytes: bytes),
          table: table,
          mappings: mappings,
        ),
      ),
    );
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(size: Size(390, 844)),
          child: CompanyCustomerImportPage(
            repository: repo,
            language: AppLanguage.nl,
            sessionStore: store,
            importIdFactory: () => 'imp_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
            picker: () async => CompanyCustomerImportPickedFile(
              name: 'two.csv',
              bytes: bytes,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byKey(kCompanyCustomerImportRepickKey), findsOneWidget);
    expect(find.byKey(kCompanyCustomerImportResumeKey), findsNothing);
    await tester.tap(find.byKey(kCompanyCustomerImportRepickKey));
    await tester.pumpAndSettle();
    expect(find.byKey(kCompanyCustomerImportResumeKey), findsOneWidget);
  });

  testWidgets('customers page opens the import wizard', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: CompanyCustomersPage(
          language: AppLanguage.nl,
          repository: CompanyCustomersRepository(
            scopeQuery: const <String, String>{
              'tenant_id': 'TA',
              'company_id': 'CA',
            },
            headers: () async => const <String, String>{},
            listTransport: ({
              required path,
              required query,
              required headers,
            }) async => <String, dynamic>{
              'ok': true,
              'items': <dynamic>[],
              'has_more': false,
              'next_cursor': null,
              'total_count': 0,
            },
            sendTransport: ({
              required method,
              required path,
              required query,
              required body,
              required headers,
              idempotencyKey,
            }) async => <String, dynamic>{'ok': true},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(kCompanyCustomersImportButtonKey));
    await tester.pumpAndSettle();
    expect(find.byKey(kCompanyCustomerImportPageKey), findsOneWidget);
    expect(find.text(kCompanyCustomerImportPick.of(AppLanguage.nl)), findsOneWidget);
  });
}
