import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_config.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/limousine/limousine_accepted_booking.dart';
import 'package:fluxidi_tracking/limousine/limousine_customer_quote.dart';
import 'package:fluxidi_tracking/limousine/limousine_quote_inbox.dart';
import 'package:fluxidi_tracking/limousine/limousine_accepted_booking_api.dart';
import 'package:fluxidi_tracking/limousine/limousine_accepted_booking_labels.dart';
import 'package:fluxidi_tracking/limousine/limousine_quote_presentation.dart';
import 'package:fluxidi_tracking/limousine/limousine_quote_respond_form.dart';
import 'package:fluxidi_tracking/payment/booking_billing_identity.dart';
import 'package:fluxidi_tracking/payment/booking_payment_options.dart';
import 'package:fluxidi_tracking/payment/payment_method_catalog.dart';

LimousineQuoteRequest _quoted({
  String treatment = 'excl',
  int gross = 72600,
  int net = 60000,
  int vat = 12600,
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
    'quotation_vat_rate': 0.21,
    'quotation_vat_treatment': treatment,
    'quotation_currency': 'EUR',
    'quote': <String, dynamic>{
      'entered_amount_cents': 60000,
      'total_ex_vat_cents': net,
      'vat_amount_cents': vat,
      'total_incl_vat_cents': gross,
      'currency': 'EUR',
      'vat_treatment': treatment,
      'vat_rate': 0.21,
      'expires_at': '2026-08-28T21:59:59.000Z',
    },
    'fulfilment': <String, dynamic>{'from': 'Gent', 'to': 'Ronse'},
  });
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

  test('Flutter sends entered amount and rate, never a computed split', () {
    final draft = completeLimousineCompanyQuoteDraft(
      const LimousineCompanyQuoteDraft(
        totalInclVatCents: 60000,
        currency: 'EUR',
        vatTreatment: 'excl',
        vatRate: 0.21,
        expiresAt: '2026-08-28T21:59:59.000Z',
      ),
    );
    final payload = draft.toWorkerQuote();
    expect(payload['entered_amount_cents'], 60000);
    expect(payload['total_incl_vat_cents'], 60000);
    expect(payload['vat_treatment'], 'excl');
    expect(payload['vat_rate'], 0.21);
    expect(payload.containsKey('total_ex_vat_cents'), isFalse);
    expect(payload.containsKey('vat_amount_cents'), isFalse);
    expect(
      kLimousineCustomerForbiddenSubmitKeys,
      contains('entered_amount_cents'),
    );
  });

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
