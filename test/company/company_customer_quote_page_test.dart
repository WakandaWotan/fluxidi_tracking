import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/company/company_customer_models.dart';
import 'package:fluxidi_tracking/company/company_customer_quote_labels.dart';
import 'package:fluxidi_tracking/company/company_customer_quote_models.dart';
import 'package:fluxidi_tracking/company/company_customer_quote_page.dart';
import 'package:fluxidi_tracking/company/company_customers_repository.dart';

CompanyCustomer _guest() {
  return parseCompanyCustomer(<String, dynamic>{
    'customer_id': 'cus_guest',
    'tenant_id': 'TA',
    'company_id': 'CA',
    'display_name': 'No App Guest',
    'status': 'active',
    'revision': 1,
    'email': '',
    'phone': '+32470000080',
  });
}

Map<String, dynamic> _quoteJson({
  String state = 'draft',
  String email = '',
  int revision = 1,
}) {
  return <String, dynamic>{
    'ok': true,
    'quote': <String, dynamic>{
      'quote_id': 'cqq_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      'customer_id': 'cus_guest',
      'state': state,
      'revision': revision,
      'issuer_name': 'Fluxidi Demo Cars',
      'pickup': 'Station',
      'dropoff': 'Airport',
      'start_at': '2026-09-20T09:00:00.000Z',
      'passengers': 2,
      'description': 'Transfer',
      'passenger_name': 'No App Guest',
      'passenger_email': email,
      'entered_amount_cents': 8000,
      'currency': 'EUR',
      'vat_treatment': 'incl',
      'valid_until': '2026-09-25T00:00:00.000Z',
      'created_at': '2026-09-10T00:00:00.000Z',
      'updated_at': '2026-09-10T00:00:00.000Z',
    },
    if (state == 'sent') 'delivery': 'test_adapter',
  };
}

class _FakeQuoteRepository extends CompanyCustomersRepository {
  _FakeQuoteRepository()
      : super(
          scopeQuery: const <String, String>{
            'tenant_id': 'TA',
            'company_id': 'CA',
          },
          headers: () async => const <String, String>{},
          listTransport: ({
            required path,
            required query,
            required headers,
          }) async =>
              <String, dynamic>{
            'ok': true,
            'items': <dynamic>[],
          },
          sendTransport: ({
            required method,
            required path,
            required query,
            required body,
            required headers,
            idempotencyKey,
          }) async =>
              <String, dynamic>{'ok': true},
        );

  CompanyCustomerQuote? draft;
  int createCalls = 0;
  int updateCalls = 0;
  int sendCalls = 0;

  @override
  Future<CompanyCustomerQuote> createQuote(
    String customerId,
    CompanyCustomerQuoteWrite write,
  ) async {
    createCalls += 1;
    draft = parseCompanyCustomerQuote(
      _quoteJson(email: write.passengerEmail, revision: 1),
    );
    return draft!;
  }

  @override
  Future<CompanyCustomerQuote> updateQuote(
    String quoteId,
    CompanyCustomerQuoteWrite write, {
    required int revision,
  }) async {
    updateCalls += 1;
    draft = parseCompanyCustomerQuote(
      _quoteJson(email: write.passengerEmail, revision: revision),
    );
    return draft!;
  }

  @override
  Future<CompanyCustomerQuote> sendQuote(String quoteId) async {
    sendCalls += 1;
    draft = parseCompanyCustomerQuote(
      _quoteJson(state: 'sent', email: 'guest@p0quote.test'),
    );
    return draft!;
  }

  @override
  Future<CompanyCustomerQuote> getQuote(String quoteId) async {
    return draft ?? parseCompanyCustomerQuote(_quoteJson());
  }

  @override
  Future<List<CompanyCustomerQuote>> listQuotes(String customerId) async {
    return draft == null ? const <CompanyCustomerQuote>[] : <CompanyCustomerQuote>[draft!];
  }
}

Future<void> _pumpQuote(
  WidgetTester tester, {
  required _FakeQuoteRepository repository,
  required Size size,
  CompanyCustomerQuote? existing,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(size: size),
        child: CompanyCustomerQuotePage(
          key: ValueKey<String>('quote-${size.width}'),
          repository: repository,
          customer: _guest(),
          existing: existing,
          language: AppLanguage.nl,
          issuerName: 'Fluxidi Demo Cars',
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('phone and tablet keep quote actions reachable', (tester) async {
    for (final size in <Size>[
      const Size(390, 844),
      const Size(800, 1280),
    ]) {
      final repo = _FakeQuoteRepository();
      await _pumpQuote(tester, repository: repo, size: size);
      expect(find.textContaining('Fluxidi Demo Cars'), findsWidgets);
      expect(find.byKey(kCompanyCustomerQuotePriceKey), findsOneWidget);
      await tester.ensureVisible(find.byKey(kCompanyCustomerQuoteSaveKey));
      await tester.ensureVisible(find.byKey(kCompanyCustomerQuoteSendKey));
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('draft of 80 euro can be saved without email and reopened', (
    tester,
  ) async {
    final repo = _FakeQuoteRepository();
    await _pumpQuote(tester, repository: repo, size: const Size(390, 844));
    await tester.enterText(find.byKey(kCompanyCustomerQuotePriceKey), '80');
    await tester.enterText(find.byKey(kCompanyCustomerQuoteEmailKey), '');
    await tester.ensureVisible(find.byKey(kCompanyCustomerQuoteSaveKey));
    await tester.tap(find.byKey(kCompanyCustomerQuoteSaveKey));
    await tester.pumpAndSettle();
    expect(repo.createCalls, 1);
    expect(repo.draft?.enteredAmountCents, 8000);

    await _pumpQuote(
      tester,
      repository: repo,
      size: const Size(800, 1280),
      existing: repo.draft,
    );
    expect(find.text('80.00'), findsOneWidget);
    expect(find.textContaining('Fluxidi Demo Cars'), findsWidgets);
    await tester.ensureVisible(find.byKey(kCompanyCustomerQuoteSendKey));
    await tester.tap(find.byKey(kCompanyCustomerQuoteSendKey));
    await tester.pumpAndSettle();
    expect(repo.sendCalls, 0);
    expect(find.text(kCompanyCustomerQuoteEmailRequired.of(AppLanguage.nl)), findsWidgets);

    await tester.enterText(
      find.byKey(kCompanyCustomerQuoteEmailKey),
      'guest@p0quote.test',
    );
    await tester.tap(find.byKey(kCompanyCustomerQuoteReviewKey));
    await tester.pumpAndSettle();
    expect(find.textContaining('EUR 80.00'), findsWidgets);
    await tester.tap(find.byKey(kCompanyCustomerQuoteSendKey));
    await tester.pumpAndSettle();
    expect(repo.sendCalls, 1);
    expect(find.text(kCompanyCustomerQuoteSent.of(AppLanguage.nl)), findsOneWidget);
  });
}
