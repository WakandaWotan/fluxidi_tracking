import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/company/subscription_fiscal_treatment.dart';

void main() {
  group('Belgian VAT profile resolves correctly', () {
    test('saved BE country + VAT number resolve belgian_vat without quotes', () {
      final verdict = resolveCompanySubscriptionFiscalTreatment(
        billingCountry: 'Belgium',
        companyCountry: 'BE',
        vatNumber: 'BE0123456749',
        vatEnabled: true,
      );
      expect(verdict.isKnown, isTrue);
      expect(verdict.taxTreatment, kSubscriptionTaxBelgianVat);
      expect(verdict.missingFields, isEmpty);
    });

    test('product quote belgian_vat wins when current quote is empty', () {
      final verdict = resolveCompanySubscriptionFiscalTreatment(
        quoteTaxTreatment: '',
        productQuoteTaxTreatment: kSubscriptionTaxBelgianVat,
        billingCountry: '',
        vatNumber: '',
      );
      expect(verdict.isKnown, isTrue);
      expect(verdict.taxTreatment, kSubscriptionTaxBelgianVat);
    });

    test('EU launch market with VAT number is reverse charge', () {
      final verdict = resolveCompanySubscriptionFiscalTreatment(
        companyCountry: 'NL',
        vatNumber: 'NL123456789B01',
        vatEnabled: true,
      );
      expect(verdict.isKnown, isTrue);
      expect(verdict.taxTreatment, kSubscriptionTaxEuReverseCharge);
    });
  });

  group('incomplete fiscal profile remains blocked', () {
    test('missing country and VAT number stay fail-closed', () {
      final verdict = resolveCompanySubscriptionFiscalTreatment(
        vatEnabled: true,
      );
      expect(verdict.isBlocked, isTrue);
      expect(verdict.taxTreatment, isEmpty);
      expect(
        verdict.missingFields,
        containsAll([kFiscalFieldBillingCountry, kFiscalFieldVatNumber]),
      );
    });

    test('BE country without VAT number stays blocked', () {
      final verdict = resolveCompanySubscriptionFiscalTreatment(
        billingCountry: 'BE',
        vatEnabled: true,
      );
      expect(verdict.isBlocked, isTrue);
      expect(verdict.missingFields, [kFiscalFieldVatNumber]);
    });

    test('explicitly disabled VAT stays blocked', () {
      final verdict = resolveCompanySubscriptionFiscalTreatment(
        billingCountry: 'BE',
        vatNumber: 'BE0123456749',
        vatEnabled: false,
      );
      expect(verdict.isBlocked, isTrue);
      expect(verdict.missingFields, [kFiscalFieldVatEnabled]);
    });

    test('pricing-market BE fallback is not used as a silent country', () {
      final country = resolveAuthoritativeFiscalCountry();
      expect(country, isEmpty);
    });
  });

  group('actionable missing-field message', () {
    test('names the missing VAT number and offers Open VAT settings', () {
      final message = subscriptionFiscalBlockedMessage(
        languageCode: 'nl',
        missingFields: const [kFiscalFieldVatNumber],
      );
      expect(message, contains('Fiscale behandeling onbekend'));
      expect(message, contains('btw-nummer'));
      expect(message, contains('Ontbrekend:'));
      expect(openVatSettingsActionLabel('en'), 'Open VAT settings');
      expect(openVatSettingsActionLabel('nl'), 'Open btw-instellingen');
    });
  });
}
