import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/company/subscription_checkout_quote_pipeline.dart';
import 'package:fluxidi_tracking/company/subscription_fiscal_treatment.dart';

void main() {
  const fixturePrices = SubscriptionProfilePriceSlice(
    baseExclCents: 6900,
    extraVehicleExclCents: 1900,
    extraDriverExclCents: 900,
    pdfBundleExclCents: {
      kSubscriptionProductPdf500: 500,
      kSubscriptionProductPdf1000: 900,
      kSubscriptionProductPdf5000: 2900,
    },
  );

  const routeMissing = SubscriptionQuoteFetchVerdict(
    kind: SubscriptionQuoteFailureKind.routeMissing,
    statusCode: 404,
    errorToken: 'quote_route_missing',
  );

  SubscriptionPurchaseQuoteResolution resolveKnown({
    required String productCode,
    required SubscriptionQuoteFetchVerdict live,
    int quantity = 1,
    bool quoteCallReached = true,
    String treatment = kSubscriptionTaxBelgianVat,
  }) {
    return resolveSubscriptionPurchaseQuote(
      productCode: productCode,
      quantity: quantity,
      fiscalKnown: true,
      fiscalTreatment: treatment,
      fiscalMissingFields: const [],
      profilePrices: fixturePrices,
      live: live,
      quoteCallReached: quoteCallReached,
    );
  }

  group('HTTP classification', () {
    test('404 text/plain Not Found is routeMissing, not parseError', () {
      final verdict = classifySubscriptionQuoteHttp(
        statusCode: 404,
        contentType: 'text/plain',
        body: 'Not Found',
      );
      expect(verdict.kind, SubscriptionQuoteFailureKind.routeMissing);
      expect(verdict.isLiveQuote, isFalse);
    });

    test('401 unauthorized is not hidden as quote unavailable', () {
      final verdict = classifySubscriptionQuoteHttp(
        statusCode: 401,
        contentType: 'application/json',
        body: '{"ok":false,"error":"unauthorized"}',
      );
      expect(verdict.kind, SubscriptionQuoteFailureKind.unauthorized);
      final message = subscriptionQuoteFailureMessage(
        languageCode: 'nl',
        kind: verdict.kind,
      );
      expect(isGenericQuoteUnavailableMessage(message), isFalse);
      expect(message, contains('sessie'));
    });

    test('403 forbidden is not hidden as quote unavailable', () {
      final verdict = classifySubscriptionQuoteHttp(
        statusCode: 403,
        contentType: 'application/json',
        body: '{"error":"forbidden"}',
      );
      expect(verdict.kind, SubscriptionQuoteFailureKind.forbidden);
      expect(
        isGenericQuoteUnavailableMessage(
          subscriptionQuoteFailureMessage(
            languageCode: 'en',
            kind: verdict.kind,
          ),
        ),
        isFalse,
      );
    });

    test('200 JSON without a parseable object is parseError', () {
      final verdict = classifySubscriptionQuoteHttp(
        statusCode: 200,
        contentType: 'application/json',
        body: 'not-json',
      );
      expect(verdict.kind, SubscriptionQuoteFailureKind.parseError);
    });

    test('live quote with server amount is used as-is', () {
      final verdict = classifySubscriptionQuoteHttp(
        statusCode: 200,
        contentType: 'application/json',
        body:
            '{"quote":{"quote_id":"q_live","unit_excl_vat_cents":1900,"subtotal_excl_vat_cents":1900,"vat_amount_cents":399,"total_incl_vat_cents":2299,"mollie_amount_cents":2299,"tax_treatment":"belgian_vat","currency":"EUR"}}',
      );
      expect(verdict.isLiveQuote, isTrue);
      expect(verdict.mollieAmountCents, 2299);
      expect(verdict.quoteId, 'q_live');
      final resolved = resolveKnown(
        productCode: kSubscriptionProductExtraVehicle,
        live: verdict,
      );
      expect(resolved.canConfirm, isTrue);
      expect(resolved.quote!.source, SubscriptionQuoteSource.live);
      expect(resolved.quote!.mollieAmountCents, 2299);
      expect(resolved.quote!.quoteId, 'q_live');
    });
  });

  group('profile-backed confirmation when quote route is missing', () {
    const products = <String, int>{
      kSubscriptionProductBase: 6900,
      kSubscriptionProductExtraVehicle: 1900,
      kSubscriptionProductExtraDriver: 900,
      kSubscriptionProductPdf500: 500,
      kSubscriptionProductPdf1000: 900,
      kSubscriptionProductPdf5000: 2900,
    };

    for (final entry in products.entries) {
      test('${entry.key} confirms from profile excl + treatment, not invented VAT', () {
        final resolved = resolveKnown(
          productCode: entry.key,
          live: routeMissing,
        );
        expect(resolved.quoteCallReached, isTrue);
        expect(resolved.canConfirm, isTrue);
        expect(resolved.quote!.source, SubscriptionQuoteSource.profile);
        expect(resolved.quote!.unitExclVatCents, entry.value);
        expect(resolved.quote!.subtotalExclVatCents, entry.value);
        expect(resolved.quote!.taxTreatment, kSubscriptionTaxBelgianVat);
        expect(resolved.quote!.mollieAmountCents, isNull);
        expect(resolved.quote!.vatAmountCents, isNull);
        expect(resolved.quote!.quoteId, isEmpty);
        final view = confirmationViewForQuote(resolved.quote!);
        expect(view.exclCents, entry.value);
        expect(view.taxTreatment, kSubscriptionTaxBelgianVat);
        expect(view.showsVatAmount, isFalse);
        expect(view.showsTotal, isFalse);
        expect(view.inventsBelgianVatAmount, isFalse);
        expect(view.inventsMollieTotal, isFalse);
        expect(
          subscriptionConfirmTreatmentLine(
            languageCode: 'nl',
            taxTreatment: view.taxTreatment,
          ),
          contains('Belgische btw'),
        );
      });
    }
  });

  group('fiscal gate before quote HTTP', () {
    test('Belgian VAT reaches the quote call', () {
      final resolved = resolveKnown(
        productCode: kSubscriptionProductExtraVehicle,
        live: routeMissing,
        quoteCallReached: true,
      );
      expect(resolved.quoteCallReached, isTrue);
      expect(resolved.canConfirm, isTrue);
    });

    test('missing VAT number is named and never reaches quote HTTP', () {
      final resolved = resolveSubscriptionPurchaseQuote(
        productCode: kSubscriptionProductExtraVehicle,
        quantity: 1,
        fiscalKnown: false,
        fiscalTreatment: '',
        fiscalMissingFields: const [kFiscalFieldVatNumber],
        profilePrices: fixturePrices,
        live: routeMissing,
        quoteCallReached: false,
      );
      expect(resolved.failure, SubscriptionQuoteFailureKind.fiscalBlocked);
      expect(resolved.quoteCallReached, isFalse);
      expect(resolved.errorToken, contains(kFiscalFieldVatNumber));
      expect(
        subscriptionQuoteFailureMessage(
          languageCode: 'nl',
          kind: resolved.failure,
          missingFiscalFields: const [kFiscalFieldVatNumber],
        ),
        contains(kFiscalFieldVatNumber),
      );
    });
  });

  group('fail-closed product and quantity', () {
    test('unknown SKU cannot confirm', () {
      final resolved = resolveKnown(
        productCode: 'pdf_9999',
        live: routeMissing,
      );
      expect(resolved.canConfirm, isFalse);
      expect(resolved.failure, SubscriptionQuoteFailureKind.unknownProduct);
    });

    test('quantity other than 1 cannot confirm', () {
      final resolved = resolveKnown(
        productCode: kSubscriptionProductExtraVehicle,
        live: routeMissing,
        quantity: 2,
      );
      expect(resolved.canConfirm, isFalse);
      expect(resolved.failure, SubscriptionQuoteFailureKind.invalidQuantity);
    });

    test('missing profile amount stays blocked', () {
      final resolved = resolveSubscriptionPurchaseQuote(
        productCode: kSubscriptionProductExtraVehicle,
        quantity: 1,
        fiscalKnown: true,
        fiscalTreatment: kSubscriptionTaxBelgianVat,
        fiscalMissingFields: const [],
        profilePrices: const SubscriptionProfilePriceSlice(
          baseExclCents: 6900,
          extraVehicleExclCents: 0,
          extraDriverExclCents: 900,
          pdfBundleExclCents: {},
        ),
        live: routeMissing,
        quoteCallReached: true,
      );
      expect(resolved.canConfirm, isFalse);
      expect(resolved.failure, SubscriptionQuoteFailureKind.missingAmount);
    });
  });

  group('purchase session lifecycle', () {
    test('cancel leaves the starting metric unchanged', () {
      final session = SubscriptionPurchaseSession(
        productCode: kSubscriptionProductExtraVehicle,
        startingMetric: 3,
      );
      session.confirmationAccepted = true;
      session.cancel();
      expect(session.metric, 3);
      expect(session.mayMutateEntitlement, isFalse);
      expect(session.checkoutStartCount, 0);
    });

    test('quote or payment failure does not change capacity or credits', () {
      final session = SubscriptionPurchaseSession(
        productCode: kSubscriptionProductPdf500,
        startingMetric: 12,
      );
      session.confirmationAccepted = true;
      expect(session.beginCheckoutIfConfirmed(), isTrue);
      session.markFailure();
      expect(session.metric, 12);
      expect(session.activated, isFalse);
      expect(session.mayMutateEntitlement, isFalse);
    });

    test('double-tap starts checkout at most once', () {
      final session = SubscriptionPurchaseSession(
        productCode: kSubscriptionProductExtraDriver,
        startingMetric: 3,
      );
      session.confirmationAccepted = true;
      expect(session.beginCheckoutIfConfirmed(), isTrue);
      expect(session.beginCheckoutIfConfirmed(), isFalse);
      expect(session.checkoutStartCount, 1);
      expect(session.metric, 3);
    });

    test('metric changes only after confirmed success', () {
      final session = SubscriptionPurchaseSession(
        productCode: kSubscriptionProductExtraVehicle,
        startingMetric: 3,
      );
      session.confirmationAccepted = true;
      expect(session.beginCheckoutIfConfirmed(), isTrue);
      session.markActivated(nextMetric: 4);
      expect(session.metric, 4);
      expect(session.mayMutateEntitlement, isTrue);
    });
  });
}
