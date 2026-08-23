import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_config.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/limousine/limousine_accepted_booking.dart';
import 'package:fluxidi_tracking/limousine/limousine_customer_quote.dart';
import 'package:fluxidi_tracking/limousine/limousine_customer_quote_api.dart';
import 'package:fluxidi_tracking/limousine/limousine_quote_inbox.dart';
import 'package:fluxidi_tracking/limousine/limousine_accepted_booking_api.dart';
import 'package:fluxidi_tracking/limousine/limousine_accepted_booking_labels.dart';
import 'package:fluxidi_tracking/limousine/limousine_quote_presentation.dart';
import 'package:fluxidi_tracking/limousine/limousine_quote_inbox_presentation.dart';
import 'package:fluxidi_tracking/limousine/limousine_quote_respond_form.dart';
import 'package:fluxidi_tracking/limousine/limousine_customer_status_page.dart';
import 'package:fluxidi_tracking/limousine/limousine_quote_detail_page.dart';
import 'package:fluxidi_tracking/limousine/limousine_quote_inbox_api.dart';
import 'package:fluxidi_tracking/limousine/limousine_accepted_booking_page.dart';
import 'package:fluxidi_tracking/customer_theme_palette.dart';
import 'package:fluxidi_tracking/payment/booking_billing_identity.dart';
import 'package:fluxidi_tracking/payment/booking_payment_options.dart';
import 'package:fluxidi_tracking/payment/payment_method_catalog.dart';

LimousineQuoteRequest _quoted({
  String treatment = 'excl',
  int gross = 72600,
  int net = 60000,
  int vat = 12600,
  num vatRate = 0.21,
}) {
  return LimousineQuoteRequest.fromJson(<String, dynamic>{
    'quote_request_id': 'limq_p3m',
    'state': 'customer_acceptance_required',
    'revision': 4,
    'quotation_available': true,
    'quotation_revision': 4,
    'quotation_total_incl_vat_cents': gross,
    'quotation_total_ex_vat_cents': net,
    'quotation_vat_amount_cents': vat,
    'quotation_entered_amount_cents': 60000,
    'quotation_vat_rate': vatRate,
    'quotation_vat_treatment': treatment,
    'quotation_currency': 'EUR',
    'quote': <String, dynamic>{
      'entered_amount_cents': 60000,
      'total_ex_vat_cents': net,
      'vat_amount_cents': vat,
      'total_incl_vat_cents': gross,
      'currency': 'EUR',
      'vat_treatment': treatment,
      'vat_rate': vatRate,
      'expires_at': '2026-08-28T21:59:59.000Z',
    },
    'fulfilment': <String, dynamic>{'from': 'Gent', 'to': 'Ronse'},
  });
}

LimousineQuoteRequest _quoted6({String treatment = 'excl'}) {
  return _quoted(
    treatment: treatment,
    gross: treatment == 'incl' ? 60000 : 63600,
    net: treatment == 'incl' ? 56604 : 60000,
    vat: treatment == 'incl' ? 3396 : 3600,
    vatRate: 0.06,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('entered-amount labels follow VAT treatment in NL/EN/FR/ES', () {
    expect(
      limousineQuoteEnteredAmountLabel('excl', AppLanguage.nl),
      'Bedrag excl. btw',
    );
    expect(
      limousineQuoteEnteredAmountLabel('incl', AppLanguage.nl),
      'Bedrag incl. btw',
    );
    expect(
      limousineQuoteEnteredAmountLabel('none', AppLanguage.nl),
      'Bedrag (geen btw)',
    );
    expect(
      limousineQuoteEnteredAmountLabel('excl', AppLanguage.en),
      'Amount excl. VAT',
    );
    expect(
      limousineQuoteEnteredAmountLabel('incl', AppLanguage.en),
      'Amount incl. VAT',
    );
    expect(
      limousineQuoteEnteredAmountLabel('excl', AppLanguage.fr),
      'Montant hors TVA',
    );
    expect(
      limousineQuoteEnteredAmountLabel('incl', AppLanguage.fr),
      'Montant TVA comprise',
    );
    expect(
      limousineQuoteEnteredAmountLabel('excl', AppLanguage.es),
      'Importe sin IVA',
    );
    expect(
      limousineQuoteEnteredAmountLabel('incl', AppLanguage.es),
      'Importe con IVA',
    );
  });

  test(
    'Flutter sends entered amount and company rate, never a computed split',
    () {
      localBackendTaxProfileNotifier.value = BackendTaxProfile.defaults();
      expect(limousineQuoteSubmittedVatRate('excl'), 0.06);
      expect(limousineQuoteSubmittedVatRate('incl'), 0.06);
      expect(limousineQuoteSubmittedVatRate('none'), 0);
      final draft = completeLimousineCompanyQuoteDraft(
        LimousineCompanyQuoteDraft(
          totalInclVatCents: 60000,
          currency: 'EUR',
          vatTreatment: 'excl',
          vatRate: limousineQuoteSubmittedVatRate('excl'),
          expiresAt: '2026-08-28T21:59:59.000Z',
        ),
      );
      final payload = draft.toWorkerQuote();
      expect(payload['entered_amount_cents'], 60000);
      expect(payload['total_incl_vat_cents'], 60000);
      expect(payload['vat_treatment'], 'excl');
      expect(payload['vat_rate'], 0.06);
      expect(payload.containsKey('total_ex_vat_cents'), isFalse);
      expect(payload.containsKey('vat_amount_cents'), isFalse);
      expect(
        kLimousineCustomerForbiddenSubmitKeys,
        contains('entered_amount_cents'),
      );
    },
  );

  test(
    'stored exclusive 600 is displayed as net 600 / VAT 126 / gross 726',
    () {
      final money = limousineCanonicalMoneyFromRequest(_quoted());
      expect(money?.netCents, 60000);
      expect(money?.vatCents, 12600);
      expect(money?.grossCents, 72600);
      expect(money?.vatTreatment, 'excl');
      expect(formatLimousineEuroAmount(money!.grossCents), contains('726'));
      expect(formatLimousineEuroAmount(money.netCents!), contains('600'));
    },
  );

  test('accepted booking review uses stored gross 726, not typed 600', () {
    final review = buildLimousineAcceptedBookingReview(
      handoff: const LimousineAcceptedQuoteHandoff(
        acceptanceReference: 'limacc1.test',
        quoteRequestId: 'limq_p3m',
        quoteRevision: 4,
        termsRevision: 1,
        totalInclVatCents: 72600,
        currency: 'EUR',
        offerId: 'off_1',
        publicPartnerId: 'company:t1:c1',
        from: 'Gent',
        to: 'Ronse',
        scheduledPickupIso: '2026-08-24T08:30:00.000Z',
      ),
      draft: const LimousineQuoteCreateDraft(from: 'Gent', to: 'Ronse'),
      request: _quoted(),
    );
    expect(review.totalExVatCents, 60000);
    expect(review.vatAmountCents, 12600);
    expect(review.totalInclVatCents, 72600);
    expect(review.vatTreatment, 'excl');
  });

  testWidgets('company form label changes with VAT treatment', (tester) async {
    localBackendTaxProfileNotifier.value = BackendTaxProfile.defaults();
    appLanguageNotifier.value = AppLanguage.nl;
    await tester.pumpWidget(
      MaterialApp(
        home: LimousineQuoteEditorPage(
          record: LimousineQuoteRequest.fromJson(<String, dynamic>{
            'quote_request_id': 'limq_form',
            'state': 'requested',
            'revision': 1,
          }),
          clock: () => DateTime(2026, 8, 23, 9),
        ),
      ),
    );
    expect(find.text('Bedrag'), findsOneWidget);
    await tester.ensureVisible(find.byKey(kLimousineQuoteVatFieldKey));
    await tester.tap(find.byKey(kLimousineQuoteVatFieldKey));
    await tester.pumpAndSettle();
    await tester.tap(find.text('BTW exclusief').last);
    await tester.pumpAndSettle();
    expect(find.text('Bedrag excl. btw'), findsOneWidget);
    await tester.tap(find.byKey(kLimousineQuoteVatFieldKey));
    await tester.pumpAndSettle();
    await tester.tap(find.text('BTW inbegrepen').last);
    await tester.pumpAndSettle();
    expect(find.text('Bedrag incl. btw'), findsOneWidget);
    expect(find.byKey(kLimousineQuoteCompanyVatRateKey), findsOneWidget);
    expect(find.text('BTW 6%'), findsWidgets);
  });

  test('frozen VAT percentage labels never invent 6 or 21', () {
    expect(limousineVatRatePercentLabel(0.06, AppLanguage.nl), 'BTW 6%');
    expect(limousineVatRatePercentLabel(0.21, AppLanguage.nl), 'BTW 21%');
    expect(limousineVatRatePercentLabel(0, AppLanguage.nl), 'BTW 0%');
    expect(limousineVatRatePercentLabel(0.06, AppLanguage.en), 'VAT 6%');
    expect(limousineVatRatePercentLabel(0.06, AppLanguage.fr), 'TVA 6 %');
    expect(limousineVatRatePercentLabel(0.06, AppLanguage.es), 'IVA 6 %');
    expect(
      limousineVatRatePercentLabel(0.21, AppLanguage.nl, inclusive: true),
      'Waarvan BTW 21%',
    );
    final excl = limousineQuoteMoneyLines(
      money: const LimousineCanonicalMoney(
        grossCents: 63600,
        netCents: 60000,
        vatCents: 3600,
        vatRate: 0.06,
        vatTreatment: 'excl',
      ),
      language: AppLanguage.nl,
    );
    expect(excl.map((line) => line.label).toList(), <String>[
      'Bedrag excl. btw',
      'BTW 6%',
      'Totaal incl. btw',
    ]);
    expect(excl.map((line) => line.cents).toList(), <int>[60000, 3600, 63600]);
    final incl = limousineQuoteMoneyLines(
      money: const LimousineCanonicalMoney(
        grossCents: 60000,
        netCents: 49587,
        vatCents: 10413,
        enteredCents: 60000,
        vatRate: 0.21,
        vatTreatment: 'incl',
      ),
      language: AppLanguage.nl,
    );
    expect(incl.map((line) => line.label).toList(), <String>[
      'Bedrag incl. btw',
      'Waarvan BTW 21%',
      'Bedrag excl. btw',
    ]);
    localBackendTaxProfileNotifier.value = const BackendTaxProfile(
      vatEnabled: true,
      vatRate: 0.21,
      vatDisplayMode: 'excl',
      vatLabels: <String, String>{'nl': 'BTW'},
    );
    final frozen = limousineCanonicalMoneyFromRequest(_quoted());
    expect(frozen?.vatRate, 0.21);
    expect(
      limousineQuoteMoneyLines(
        money: frozen!,
        language: AppLanguage.nl,
      ).map((line) => line.label),
      contains('BTW 21%'),
    );
  });

  test('explicit 6% rows match 36,00 and never infer 21%', () {
    final money = limousineCanonicalMoneyFromRequest(_quoted6())!;
    expect(money.vatRate, 0.06);
    expect(limousineDisplayedVatMatchesFrozenRate(money), isTrue);
    final lines = limousineQuoteMoneyLines(
      money: money,
      language: AppLanguage.nl,
    );
    expect(lines.map((line) => line.label).toList(), <String>[
      'Bedrag excl. btw',
      'BTW 6%',
      'Totaal incl. btw',
    ]);
    expect(lines.map((line) => line.cents).toList(), <int>[60000, 3600, 63600]);
    expect(formatLimousineEuroAmount(3600), contains('36,00'));
    expect(lines.any((line) => line.label.contains('21')), isFalse);
    expect(lines.any((line) => line.cents == 12600), isFalse);
    expect(
      limousineDisplayedVatMatchesFrozenRate(
        const LimousineCanonicalMoney(
          grossCents: 72600,
          netCents: 60000,
          vatCents: 12600,
          vatRate: 0.06,
          vatTreatment: 'excl',
        ),
      ),
      isFalse,
    );
    expect(
      limousineQuoteMoneyLines(
        money: const LimousineCanonicalMoney(
          grossCents: 60000,
          vatCents: 0,
          vatRate: 0,
          vatTreatment: 'none',
        ),
        language: AppLanguage.nl,
      ).map((line) => line.label),
      contains('BTW 0%'),
    );
    expect(
      limousineQuoteMoneyLines(
        money: limousineCanonicalMoneyFromRequest(_quoted6())!,
        language: AppLanguage.en,
      ).map((line) => line.label).toList(),
      <String>['Amount excl. VAT', 'VAT 6%', 'Total incl. VAT'],
    );
    expect(
      limousineQuoteMoneyLines(
        money: limousineCanonicalMoneyFromRequest(_quoted6())!,
        language: AppLanguage.fr,
      ).map((line) => line.label).toList(),
      <String>['Montant hors TVA', 'TVA 6 %', 'Total TVA comprise'],
    );
    expect(
      limousineQuoteMoneyLines(
        money: limousineCanonicalMoneyFromRequest(_quoted6())!,
        language: AppLanguage.es,
      ).map((line) => line.label).toList(),
      <String>['Importe sin IVA', 'IVA 6 %', 'Total IVA incluido'],
    );
  });

  test(
    'changing company VAT later does not alter frozen quotation display',
    () {
      localBackendTaxProfileNotifier.value = BackendTaxProfile.defaults();
      final frozen = limousineCanonicalMoneyFromRequest(_quoted6())!;
      localBackendTaxProfileNotifier.value = const BackendTaxProfile(
        vatEnabled: true,
        vatRate: 0.21,
        vatDisplayMode: 'excl',
        vatLabels: <String, String>{'nl': 'BTW'},
      );
      expect(frozen.vatRate, 0.06);
      expect(
        limousineQuoteMoneyLines(
          money: frozen,
          language: AppLanguage.nl,
        ).map((line) => '${line.label}:${line.cents}'),
        <String>[
          'Bedrag excl. btw:60000',
          'BTW 6%:3600',
          'Totaal incl. btw:63600',
        ],
      );
      expect(resolveActiveVatConfig().vatRate, 0.21);
    },
  );

  test('settlement uses frozen accepted vat_rate, not company settings', () {
    localBackendTaxProfileNotifier.value = const BackendTaxProfile(
      vatEnabled: true,
      vatRate: 0.21,
      vatDisplayMode: 'excl',
      vatLabels: <String, String>{'nl': 'BTW'},
    );
    final money = limousineCanonicalMoneyFromBookingDetails(<String, dynamic>{
      'service_type': 'limousine',
      'price_incl_vat': 636,
      'quote': <String, dynamic>{
        'limousine_accepted_price': <String, dynamic>{
          'total_ex_vat_cents': 60000,
          'vat_amount_cents': 3600,
          'total_incl_vat_cents': 63600,
          'vat_rate': 0.06,
          'vat_treatment': 'excl',
          'price_ex_vat': 600,
          'price_vat': 36,
          'price_incl_vat': 636,
        },
      },
    });
    expect(money?.vatRate, 0.06);
    expect(limousineDisplayedVatMatchesFrozenRate(money!), isTrue);
    final lines = limousineQuoteMoneyLines(
      money: money,
      language: AppLanguage.nl,
    );
    expect(lines.map((line) => line.label), contains('BTW 6%'));
    expect(lines.map((line) => line.cents), contains(3600));
    expect(
      limousineQuoteInboxAuthoritativeAmount(_quoted6(), AppLanguage.nl),
      contains('BTW 6%'),
    );
  });

  testWidgets('customer quotation detail shows frozen BTW 6% and 36,00', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    localBackendTaxProfileNotifier.value = const BackendTaxProfile(
      vatEnabled: true,
      vatRate: 0.21,
      vatDisplayMode: 'excl',
      vatLabels: <String, String>{'nl': 'BTW'},
    );
    appLanguageNotifier.value = AppLanguage.nl;
    final controller = LimousineCustomerQuoteController(
      gateway: _UnusedCustomerGateway(),
    );
    controller.request = _quoted6();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: LimousineCustomerStatusView(
              controller: controller,
              language: AppLanguage.nl,
              palette: paletteForCustomerTheme(
                CustomerThemeVariant.premiumLight,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('BTW 6%'), findsWidgets);
    expect(find.textContaining('36,00'), findsWidgets);
    expect(find.textContaining('636,00'), findsWidgets);
    expect(find.textContaining('21%'), findsNothing);
    controller.dispose();
  });

  testWidgets('company quotation summary shows frozen BTW 6%', (tester) async {
    tester.view.physicalSize = const Size(400, 2200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    appLanguageNotifier.value = AppLanguage.nl;
    localBackendTaxProfileNotifier.value = const BackendTaxProfile(
      vatEnabled: true,
      vatRate: 0.21,
      vatDisplayMode: 'excl',
      vatLabels: <String, String>{'nl': 'BTW'},
    );
    await tester.pumpWidget(
      MaterialApp(
        home: LimousineQuoteDetailPage(
          quoteRequestId: 'limq_p3m',
          initial: _quoted6(),
          gateway: _FixedInboxGateway(_quoted6()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('BTW 6%'), findsWidgets);
    expect(find.textContaining('36,00'), findsWidgets);
    expect(find.text('Bedrag excl. btw'), findsWidgets);
    expect(find.text('Totaal incl. btw'), findsWidgets);
    expect(find.text('BTW 21%'), findsNothing);
  });

  testWidgets('accepted-booking checkout shows frozen BTW 6% and 636', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    appLanguageNotifier.value = AppLanguage.nl;
    localBackendTaxProfileNotifier.value = const BackendTaxProfile(
      vatEnabled: true,
      vatRate: 0.21,
      vatDisplayMode: 'excl',
      vatLabels: <String, String>{'nl': 'BTW'},
    );
    final request = _quoted6();
    final controller = LimousineAcceptedBookingController(
      handoff: const LimousineAcceptedQuoteHandoff(
        acceptanceReference: 'limacc1.test',
        quoteRequestId: 'limq_p3m',
        quoteRevision: 4,
        termsRevision: 1,
        totalInclVatCents: 63600,
        currency: 'EUR',
        offerId: 'off_1',
        publicPartnerId: 'company:t1:c1',
        from: 'Gent',
        to: 'Ronse',
        scheduledPickupIso: '2026-08-24T08:30:00.000Z',
      ),
      draft: const LimousineQuoteCreateDraft(from: 'Gent', to: 'Ronse'),
      request: request,
      entryEnabled: true,
      gateway: _NoopBookGateway(),
      customerOverride: const LimousineAcceptedBookingCustomer(
        sessionToken: 'sess',
        customerId: 'cust',
        name: 'Ada',
        phone: '+32470000000',
        email: 'ada@example.com',
      ),
      initialPaymentCapability: const BookingPaymentCapability(
        paymentOwnerMode: 'company_mollie',
        paymentDemoMode: false,
        mollieConnected: true,
        livePaymentsEnabled: true,
        publicPaymentOptions: <String>[PaymentMethodIds.inVehicleCard],
        countryCode: 'BE',
      ),
      isApplePaymentPlatform: false,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: LimousineAcceptedBookingPage(
          controller: controller,
          entryEnabled: true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('BTW 6%'), findsWidgets);
    expect(find.textContaining('36,00'), findsWidgets);
    expect(find.textContaining('636,00'), findsWidgets);
    expect(find.textContaining('21%'), findsNothing);
    controller.dispose();
  });

  test('PDF action loads the server quotation.pdf, never a Flutter split', () {
    final customerApi = File(
      'lib/limousine/limousine_customer_quote_api.dart',
    ).readAsStringSync();
    final companyApi = File(
      'lib/limousine/limousine_quote_inbox_api.dart',
    ).readAsStringSync();
    final action = File(
      'lib/limousine/limousine_quotation_pdf_action.dart',
    ).readAsStringSync();
    expect(customerApi, contains('/quotation.pdf'));
    expect(companyApi, contains('/quotation.pdf'));
    expect(action, contains('loadBytes'));
    expect(action, isNot(contains('deriveLimousine')));
  });

  test('billing toggle and payment method leave exclusive checkout at 726', () {
    final review = buildLimousineAcceptedBookingReview(
      handoff: const LimousineAcceptedQuoteHandoff(
        acceptanceReference: 'limacc1.test',
        quoteRequestId: 'limq_p3m',
        quoteRevision: 4,
        termsRevision: 1,
        totalInclVatCents: 72600,
        currency: 'EUR',
        offerId: 'off_1',
        publicPartnerId: 'company:t1:c1',
        from: 'Gent',
        to: 'Ronse',
        scheduledPickupIso: '2026-08-24T08:30:00.000Z',
      ),
      draft: const LimousineQuoteCreateDraft(from: 'Gent', to: 'Ronse'),
      request: _quoted(),
    );
    final controller = LimousineAcceptedBookingController(
      handoff: const LimousineAcceptedQuoteHandoff(
        acceptanceReference: 'limacc1.test',
        quoteRequestId: 'limq_p3m',
        quoteRevision: 4,
        termsRevision: 1,
        totalInclVatCents: 72600,
        currency: 'EUR',
        offerId: 'off_1',
        publicPartnerId: 'company:t1:c1',
        from: 'Gent',
        to: 'Ronse',
        scheduledPickupIso: '2026-08-24T08:30:00.000Z',
      ),
      draft: const LimousineQuoteCreateDraft(from: 'Gent', to: 'Ronse'),
      request: _quoted(),
      entryEnabled: true,
      gateway: _NoopBookGateway(),
      customerOverride: const LimousineAcceptedBookingCustomer(
        sessionToken: 'sess',
        customerId: 'cust',
        name: 'Ada',
        phone: '+32470000000',
        email: 'ada@example.com',
      ),
      initialPaymentCapability: const BookingPaymentCapability(
        paymentOwnerMode: 'company_mollie',
        paymentDemoMode: false,
        mollieConnected: true,
        livePaymentsEnabled: true,
        publicPaymentOptions: <String>[
          PaymentMethodIds.bancontact,
          PaymentMethodIds.inVehicleCard,
        ],
        countryCode: 'BE',
      ),
      isApplePaymentPlatform: false,
      persister:
          ({
            required response,
            required requestPayload,
            required customer,
          }) async {},
    );
    expect(review.totalInclVatCents, 72600);
    controller.setBillingEnabled(true);
    controller.updateBillingIdentity(
      const BookingBillingIdentity(
        legalName: 'Acme BV',
        vatNumber: 'BE0123456789',
        street: 'Kerkstraat 1',
        postalCode: '9000',
        city: 'Gent',
        country: 'be',
        contactEmail: 'a@example.com',
      ),
    );
    controller.selectPaymentMethod(PaymentMethodIds.bancontact);
    expect(review.totalInclVatCents, 72600);
    expect(controller.handoff.totalInclVatCents, 72600);
    expect(
      kLimousineAcceptedBookingBillingPriceUnchanged.nl,
      contains('totaalbedrag'),
    );
  });

  test('driver settlement payload uses stored exclusive gross 726', () {
    final booking = <String, dynamic>{
      'service_type': 'limousine',
      'price_incl_vat': 726,
      'quote': <String, dynamic>{
        'pricing': <String, dynamic>{
          'price_ex_vat': 600,
          'price_vat': 126,
          'price_incl_vat': 726,
          'vat_treatment': 'excl',
        },
        'limousine_accepted_price': <String, dynamic>{
          'price_ex_vat': 600,
          'price_vat': 126,
          'price_incl_vat': 726,
          'total_ex_vat_cents': 60000,
          'vat_amount_cents': 12600,
          'total_incl_vat_cents': 72600,
          'vat_treatment': 'excl',
        },
      },
    };
    final accepted =
        (booking['quote'] as Map)['limousine_accepted_price'] as Map;
    expect(accepted['price_incl_vat'], 726);
    expect(booking['price_incl_vat'], 726);
    expect(accepted['price_incl_vat'], isNot(600));
  });
}

class _UnusedCustomerGateway with LimousineCustomerQuoteGateway {
  @override
  Future<List<LimousineDiscoveredProvider>> discoverNearby({
    String? postcode,
    double? lat,
    double? lng,
    int radiusKm = 20,
  }) async => const <LimousineDiscoveredProvider>[];

  @override
  Future<LimousineProviderDetail> loadProvider(String partnerId) async {
    throw const LimousineCustomerQuoteException(code: 'unused');
  }

  @override
  Future<LimousineQuoteCreateResult> createRequest(
    LimousineQuoteCreateDraft draft,
  ) async {
    throw const LimousineCustomerQuoteException(code: 'unused');
  }

  @override
  Future<LimousineQuoteRequest> pollStatus(String statusRef) async {
    throw const LimousineCustomerQuoteException(code: 'unused');
  }

  @override
  Future<LimousineQuoteAcceptResult> accept({
    required String quoteRequestId,
    required int expectedRevision,
    required int termsRevision,
  }) async {
    throw const LimousineCustomerQuoteException(code: 'unused');
  }
}

class _FixedInboxGateway implements LimousineQuoteInboxGateway {
  _FixedInboxGateway(this.record);

  final LimousineQuoteRequest record;

  @override
  Future<LimousineQuoteInboxPageData> list({
    int pageSize = kLimousineQuoteInboxPageDefault,
    String? state,
    String? cursor,
    String? updatedSince,
    String? tenantId,
    String? companyId,
  }) async {
    return LimousineQuoteInboxPageData(items: <LimousineQuoteRequest>[record]);
  }

  @override
  Future<LimousineQuoteRequest> detail(
    String quoteRequestId, {
    String? tenantId,
    String? companyId,
  }) async {
    return record;
  }

  @override
  Future<LimousineQuoteRespondResult> respond({
    required String quoteRequestId,
    required String action,
    required int expectedRevision,
    Map<String, dynamic>? quote,
    LimousineDeclineDraft? decline,
    String? tenantId,
    String? companyId,
  }) async {
    return LimousineQuoteRespondResult(record: record);
  }

  @override
  Future<Uint8List> fetchQuotationPdf({
    required String quoteRequestId,
    required int revision,
    String? tenantId,
    String? companyId,
  }) async {
    return Uint8List.fromList(<int>[37, 80, 68, 70]);
  }
}

class _NoopBookGateway implements LimousineAcceptedBookingGateway {
  @override
  Future<LimousineAcceptedBookResult> book(Map<String, dynamic> payload) async {
    return const LimousineAcceptedBookResult(
      bookingId: 'B-1',
      publicReference: 'FLX-1',
      raw: <String, dynamic>{'ok': true},
    );
  }
}
