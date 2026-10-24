import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_config.dart';
import 'package:fluxidi_tracking/private_chauffeur/private_chauffeur_quote_inbox.dart';
import 'package:fluxidi_tracking/private_chauffeur/private_chauffeur_setup_validation.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('manual quotes need a mode but no automatic tariff', () {
    expect(
      validatePrivateChauffeurSetup(
        offered: true,
        pricingMode: 'quote_required',
        tariffValid: false,
      ),
      isNull,
    );
    expect(
      validatePrivateChauffeurSetup(
        offered: true,
        pricingMode: '',
        tariffValid: false,
      ),
      PrivateChauffeurSetupIssue.pricingModeRequired,
    );
    expect(
      validatePrivateChauffeurSetup(
        offered: true,
        pricingMode: 'calculator',
        tariffValid: false,
      ),
      PrivateChauffeurSetupIssue.tariffRequired,
    );
    expect(
      validatePrivateChauffeurSetup(
        offered: true,
        pricingMode: 'calculator',
        tariffValid: true,
      ),
      isNull,
    );
    expect(
      validatePrivateChauffeurSetup(
        offered: false,
        pricingMode: '',
        tariffValid: false,
      ),
      isNull,
    );
  });

  test('profile settings round-trip through the business profile json', () {
    final saved = BackendBusinessProfile(
      companyName: 'Atelier Noord',
      legalName: 'Atelier Noord BV',
      vatNumber: 'BE0000000000',
      companyRegistrationNumber: '',
      address: 'Markt 1',
      postcode: '9000',
      city: 'Gent',
      country: 'BE',
      phone: '',
      email: 'desk@example.test',
      website: '',
      bookingEmail: '',
      invoiceEmail: '',
      iban: '',
      paymentReferencePrefix: 'FLX',
      invoiceReceiptFooterText: '',
      publicServiceIds: const <String>['private_chauffeur'],
      publicServicesConfigured: true,
      airportScheduledDispatchMode: 'manager_first',
      airportOutOfAreaMode: 'request_quote',
      privateChauffeurPricingMode: 'calculator',
      privateChauffeurMinimumHoursDeclared: true,
      privateChauffeurMinimumHours: 3,
      privateChauffeurHourlyRateExVat: 65,
      privateChauffeurKmRateExVat: 1.5,
      privateChauffeurVatPercent: 6,
    );
    final loaded = BackendBusinessProfile.fromJson(saved.toJson());
    expect(loaded.privateChauffeurPricingMode, 'calculator');
    expect(loaded.privateChauffeurMinimumHours, 3);
    expect(loaded.privateChauffeurHourlyRateExVat, 65);
    expect(loaded.privateChauffeurKmRateExVat, 1.5);
    expect(loaded.privateChauffeurVatPercent, 6);
    expect(loaded.airportScheduledDispatchMode, 'manager_first');
    expect(loaded.airportOutOfAreaMode, 'request_quote');
    expect(loaded.publicServiceIds, contains('private_chauffeur'));

    final cleared = BackendBusinessProfile.fromJson(<String, dynamic>{
      'companyName': 'Atelier Noord',
      'legalName': 'Atelier Noord BV',
      'vatNumber': '',
      'companyRegistrationNumber': '',
      'address': '',
      'postcode': '',
      'city': '',
      'country': 'BE',
      'phone': '',
      'email': '',
      'website': '',
      'bookingEmail': '',
      'invoiceEmail': '',
      'iban': '',
      'paymentReferencePrefix': 'FLX',
      'invoiceReceiptFooterText': '',
    });
    expect(cleared.privateChauffeurPricingMode, isEmpty);
    expect(cleared.privateChauffeurMinimumHoursDeclared, isFalse);
    expect(
      cleared.toJson().containsKey('private_chauffeur_pricing_mode'),
      isFalse,
    );
  });

  test('inbox uses the existing quote endpoint and keeps the service', () {
    final uri = privateChauffeurInboxUri(
      bookingBaseUrl: 'https://booking.test',
      tenantId: 'co_1',
      companyId: 'co_1',
    );
    expect(uri.path, '/admin/limousine/quote-requests');
    expect(uri.queryParameters['service'], 'private_chauffeur');
    final body = privateChauffeurCompanyQuoteBody(
      quoteRequestId: 'limq_test',
      expectedRevision: 1,
      totalInclVatCents: 18500,
      scope: adminTenantCompanyScope(tenantId: 'co_1', companyId: 'co_1'),
    );
    expect(body['tenant_id'], 'co_1');
    expect(body['company_id'], 'co_1');
    expect(body['service'], 'private_chauffeur');
    expect(body['action'], 'quote');
    expect(body['total_incl_vat_cents'], 18500);
    expect(body.containsKey('price_incl_vat'), isFalse);
    final items = privateChauffeurInboxItemsFromJson(<String, dynamic>{
      'items': <Map<String, dynamic>>[
        <String, dynamic>{
          'quote_request_id': 'limq_test',
          'service_type': 'private_chauffeur',
          'state': 'submitted',
          'revision': 1,
          'fulfilment': <String, dynamic>{
            'from': 'Markt',
            'to': 'Station',
            'requested_duration_minutes': 180,
            'customer_note': 'Bruiloft',
          },
        },
        <String, dynamic>{
          'quote_request_id': 'limq_limo',
          'service_type': 'limousine',
          'fulfilment': <String, dynamic>{'from': 'A', 'to': 'B'},
        },
      ],
    });
    expect(items, hasLength(1));
    expect(items.single.id, 'limq_test');
    expect(items.single.durationMinutes, 180);
    expect(items.single.customerNote, 'Bruiloft');
    expect(isPrivateChauffeurServiceToken('private_chauffeur'), isTrue);
    expect(isPrivateChauffeurServiceToken('taxi'), isFalse);
    expect(isPrivateChauffeurServiceToken('limousine'), isFalse);
    expect(isPrivateChauffeurServiceToken('airport'), isFalse);
  });

  testWidgets('assigned request is quoted from the company inbox', (
    tester,
  ) async {
    final gateway = MemoryPrivateChauffeurInboxGateway(
      items: const <PrivateChauffeurInboxItem>[
        PrivateChauffeurInboxItem(
          id: 'limq_test',
          from: 'Markt',
          to: 'Station',
          state: 'submitted',
          durationMinutes: 180,
          customerNote: 'Bruiloft',
        ),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: PrivateChauffeurQuoteInboxPanel(gateway: gateway)),
      ),
    );
    await tester.tap(find.byKey(const Key('private_chauffeur_inbox_load')));
    await tester.pumpAndSettle();
    expect(find.text('Privéchauffeur · 180 min'), findsOneWidget);
    expect(find.text('Markt → Station'), findsOneWidget);
    expect(
      gateway.lastListUri?.queryParameters['service'],
      'private_chauffeur',
    );

    await tester.enterText(
      find.byKey(const Key('private_chauffeur_inbox_cents')),
      '18500',
    );
    await tester.tap(
      find.byKey(const Key('private_chauffeur_inbox_quote_limq_test')),
    );
    await tester.pumpAndSettle();
    expect(gateway.quoteCalls, 1);
    expect(gateway.lastQuoteBody?['service'], 'private_chauffeur');
    expect(gateway.lastQuoteBody?['quote_request_id'], 'limq_test');
    expect(gateway.lastQuoteBody?['total_incl_vat_cents'], 18500);
  });
}
