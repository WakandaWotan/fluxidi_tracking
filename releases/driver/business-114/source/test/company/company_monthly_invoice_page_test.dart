import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/company/company_customer_models.dart';
import 'package:fluxidi_tracking/company/company_customers_repository.dart';
import 'package:fluxidi_tracking/company/company_monthly_invoice_page.dart';

void main() {
  monthlyHistoryTests();
  test(
    'repository refuses changed company and foreign monthly response',
    () async {
      var scope = {'tenant_id': 'T', 'company_id': 'C'};
      final repository = CompanyCustomersRepository(
        scopeResolver: () => scope,
        listTransport:
            ({required path, required query, required headers}) async => {
              'ok': true,
              'invoice': {
                'tenant_id': 'T',
                'company_id': 'FOREIGN',
                'customer_id': 'customer1',
                'month': '2026-09',
              },
            },
        sendTransport:
            ({
              required method,
              required path,
              required query,
              required body,
              required headers,
              idempotencyKey,
            }) async => throw StateError('must not write'),
      );
      final original = repository.monthlyInvoiceScope;
      await expectLater(
        repository.monthlyInvoice('customer1', 'preview', month: '2026-09'),
        throwsA(
          isA<CompanyCustomerException>().having(
            (e) => e.code,
            'code',
            'invoice_scope_mismatch',
          ),
        ),
      );
      scope = {'tenant_id': 'T', 'company_id': 'OTHER'};
      await expectLater(
        repository.monthlyInvoice(
          'customer1',
          'issue',
          month: '2026-09',
          expectedScope: original,
        ),
        throwsA(
          isA<CompanyCustomerException>().having(
            (e) => e.code,
            'code',
            'invoice_scope_changed',
          ),
        ),
      );
    },
  );

  testWidgets(
    'preview never issues or emails, cancellation and month change invalidate actions',
    (tester) async {
      var writes = 0;
      final repository = CompanyCustomersRepository(
        scopeQuery: {'tenant_id': 'T', 'company_id': 'C'},
        listTransport:
            ({required path, required query, required headers}) async {
              if (path.endsWith('/detail'))
                throw const CompanyCustomerException(
                  'monthly_invoice_not_issued',
                );
              return {
                'ok': true,
                'content_hash': 'fixture',
                'invoice': {
                  'tenant_id': 'T',
                  'company_id': 'C',
                  'customer_id': 'customer1',
                  'month': query['month'],
                  'currency': 'EUR',
                  'totals': {'gross_cents': 10600},
                  'lines': [],
                },
              };
            },
        sendTransport:
            ({
              required method,
              required path,
              required query,
              required body,
              required headers,
              idempotencyKey,
            }) async {
              writes++;
              return {'ok': true};
            },
      );
      await tester.pumpWidget(
        MaterialApp(
          home: CompanyMonthlyInvoicePage(
            customerId: 'customer1',
            repository: repository,
            language: AppLanguage.nl,
          ),
        ),
      );
      await tester.tap(find.text('Maand bekijken'));
      await tester.pumpAndSettle();
      expect(writes, 0);
      expect(find.text('Factuur uitgeven'), findsOneWidget);
      await tester.tap(find.text('Factuur uitgeven'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Annuleren'));
      await tester.pumpAndSettle();
      expect(writes, 0);
      await tester.enterText(find.byType(TextField), '2026-08');
      await tester.pumpAndSettle();
      expect(find.text('Factuur uitgeven'), findsNothing);
      expect(writes, 0);
    },
  );
}

void monthlyHistoryTests() {
  testWidgets(
    'history reads and month selection never issue or send an invoice',
    (tester) async {
      final reads = <String>[];
      final repository = CompanyCustomersRepository(
        scopeQuery: {'tenant_id': 'T', 'company_id': 'C'},
        listTransport:
            ({required path, required query, required headers}) async {
              reads.add(path);
              if (path.endsWith('/list'))
                return {
                  'ok': true,
                  'next_cursor': null,
                  'items': [
                    {
                      'month': '2026-09',
                      'state': 'issued',
                      'document_number': 'INV-2026-000001',
                      'gross_cents': 10600,
                      'currency': 'EUR',
                      'delivery_state': 'sent',
                    },
                  ],
                };
              return {
                'ok': true,
                'document': {
                  'document_number': 'INV-2026-000001',
                  'immutable_snapshot': {
                    'monthly_invoice': {
                      'tenant_id': 'T',
                      'company_id': 'C',
                      'customer_id': 'customer1',
                      'month': query['month'],
                      'currency': 'EUR',
                      'totals': {'gross_cents': 10600},
                      'lines': [],
                    },
                  },
                },
              };
            },
        sendTransport:
            ({
              required method,
              required path,
              required query,
              required body,
              required headers,
              idempotencyKey,
            }) async => throw StateError('read-only history must not write'),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: CompanyMonthlyInvoicePage(
            customerId: 'customer1',
            repository: repository,
            language: AppLanguage.nl,
          ),
        ),
      );
      await tester.tap(find.text('Factuurgeschiedenis'));
      await tester.pumpAndSettle();
      expect(find.text('Verzonden'), findsOneWidget);
      expect(find.text('106.00 EUR'), findsOneWidget);
      await tester.tap(find.text('2026-09 INV-2026-000001'));
      await tester.pumpAndSettle();
      expect(reads.map((path) => path.split('/').last), ['list', 'detail']);
      expect(find.text('Factuur uitgeven'), findsNothing);
      expect(find.text('INV-2026-000001'), findsOneWidget);
    },
  );
}
