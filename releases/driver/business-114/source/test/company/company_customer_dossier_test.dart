import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/company/company_agenda_models.dart';
import 'package:fluxidi_tracking/company/company_customer_dossier.dart';
import 'package:fluxidi_tracking/company/company_customer_labels.dart';
import 'package:fluxidi_tracking/company/company_customer_models.dart';
import 'package:fluxidi_tracking/company/company_customer_quote_labels.dart';
import 'package:fluxidi_tracking/company/company_customer_quote_list.dart';
import 'package:fluxidi_tracking/company/company_customer_quote_models.dart';
import 'package:fluxidi_tracking/company/company_customer_quote_page.dart';
import 'package:fluxidi_tracking/company/company_customers_repository.dart';

CompanyCustomer _marie() {
  return parseCompanyCustomer(<String, dynamic>{
    'customer_id': 'cus_marie',
    'tenant_id': 'TA',
    'company_id': 'CA',
    'display_name': 'Marie-Claire Dubois',
    'status': 'active',
    'revision': 1,
    'email': 'marieclaire.dubois.p0@example.test',
    'phone': '0470112222',
  });
}

CompanyCustomerQuote _draftQuote() {
  return parseCompanyCustomerQuote(<String, dynamic>{
    'ok': true,
    'quote': <String, dynamic>{
      'quote_id': 'cqq_dossier_draft',
      'customer_id': 'cus_marie',
      'state': 'draft',
      'revision': 1,
      'issuer_name': 'Fluxidi Demo Cars',
      'pickup': 'Gent-Sint-Pieters',
      'dropoff': 'Brussels Airport',
      'start_at': '2026-09-20T09:00:00.000Z',
      'passengers': 2,
      'description': '',
      'passenger_name': 'Marie-Claire Dubois',
      'passenger_email': 'marieclaire.dubois.p0@example.test',
      'entered_amount_cents': 11000,
      'currency': 'EUR',
      'vat_treatment': 'incl',
      'created_at': '2026-09-12T00:00:00.000Z',
      'updated_at': '2026-09-12T00:00:00.000Z',
    },
  });
}

class _FakeQuoteListRepository extends CompanyCustomersRepository {
  _FakeQuoteListRepository({this.quotes, this.error})
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
        }) async => <String, dynamic>{'ok': true, 'items': <dynamic>[]},
        sendTransport: ({
          required method,
          required path,
          required query,
          required body,
          required headers,
          idempotencyKey,
        }) async => <String, dynamic>{'ok': true},
      );

  final List<CompanyCustomerQuote>? quotes;
  final CompanyCustomerException? error;
  int listCalls = 0;

  @override
  Future<List<CompanyCustomerQuote>> listQuotes(String customerId) async {
    listCalls += 1;
    if (error != null) throw error!;
    return quotes ?? const <CompanyCustomerQuote>[];
  }
}

void main() {
  test('draft list title uses Concept, ride date, destination and amount', () {
    final title = companyCustomerQuoteListTitle(
      quote: _draftQuote(),
      language: AppLanguage.nl,
    );
    expect(title, contains(kCompanyCustomerQuoteStateDraft.of(AppLanguage.nl)));
    expect(title, contains('Brussels Airport'));
    expect(title, contains('EUR 110.00'));
    expect(title.contains('draft'), isFalse);
  });

  testWidgets('dossier shows saved drafts under Offertes', (tester) async {
    final repo = _FakeQuoteListRepository(quotes: <CompanyCustomerQuote>[_draftQuote()]);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CompanyCustomerDossier(
            customer: _marie(),
            language: AppLanguage.nl,
            repository: repo,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text(kCompanyCustomerQuotesTitle.of(AppLanguage.nl)), findsOneWidget);
    expect(find.text(kCompanyCustomersNoQuotes.of(AppLanguage.nl)), findsNothing);
    expect(find.byKey(companyCustomerQuoteRowKey('cqq_dossier_draft')), findsOneWidget);
    expect(find.textContaining('Concept'), findsOneWidget);
    expect(find.textContaining('Brussels Airport'), findsWidgets);
    expect(find.textContaining('EUR 110.00'), findsOneWidget);
    await tester.tap(find.byKey(companyCustomerQuoteRowKey('cqq_dossier_draft')));
    await tester.pumpAndSettle();
    expect(find.byKey(kCompanyCustomerQuotePageKey), findsOneWidget);
    expect(find.text('Marie-Claire Dubois'), findsWidgets);
    expect(find.text('Brussels Airport'), findsWidgets);
  });

  testWidgets('dossier lists planned agenda rides that are not quote bookings', (
    tester,
  ) async {
    final repo = _FakeQuoteListRepository();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CompanyCustomerDossier(
            customer: _marie(),
            language: AppLanguage.nl,
            repository: repo,
            plannedRides: const <CompanyAgendaRide>[
              CompanyAgendaRide(
                bookingId: 'agb_w38_marie',
                customerId: 'cus_marie',
                customerName: 'Marie-Claire Dubois',
                fromAddress: 'Korenmarkt 1, Gent',
                toAddress: 'Veldstraat 12, Gent',
                pickupIso: '2026-09-16T07:00:00.000Z',
                status: 'PENDING',
                assignedDriverId: 'drv_demo_company_p0_8',
                assignedVehicleId: '',
                durationUnknown: false,
                durationMin: 15,
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text(kCompanyCustomersNoBookings.of(AppLanguage.nl)), findsNothing);
    expect(find.byKey(companyCustomerPlannedBookingRowKey('agb_w38_marie')), findsOneWidget);
    expect(find.textContaining('Korenmarkt 1, Gent'), findsOneWidget);
    expect(find.textContaining('Veldstraat 12, Gent'), findsOneWidget);
  });

  testWidgets('dossier shows a retry when quotes fail to load', (tester) async {
    final repo = _FakeQuoteListRepository(
      error: const CompanyCustomerException('quote_not_ok'),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CompanyCustomerDossier(
            customer: _marie(),
            language: AppLanguage.nl,
            repository: repo,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text(kCompanyCustomersQuotesError.of(AppLanguage.nl)), findsOneWidget);
    expect(find.text(kCompanyCustomersNoQuotes.of(AppLanguage.nl)), findsNothing);
  });
}
