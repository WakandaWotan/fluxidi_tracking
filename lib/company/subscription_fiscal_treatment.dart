/// Authoritative company SaaS fiscal treatment.
///
/// Reuses the existing subscription quote treatments (`belgian_vat`,
/// `eu_reverse_charge`) and the saved company / billing country + VAT
/// profile. Does not invent a rate, a total, or a third tax model.
library;

import 'package:fluxidi_tracking/app_config.dart';

const String kSubscriptionTaxBelgianVat = 'belgian_vat';
const String kSubscriptionTaxEuReverseCharge = 'eu_reverse_charge';

const String kFiscalFieldBillingCountry = 'billing_country';
const String kFiscalFieldVatNumber = 'vat_number';
const String kFiscalFieldVatEnabled = 'vat_enabled';

const Set<String> kKnownSubscriptionTaxTreatments = {
  kSubscriptionTaxBelgianVat,
  kSubscriptionTaxEuReverseCharge,
};

class SubscriptionFiscalVerdict {
  const SubscriptionFiscalVerdict({
    this.taxTreatment = '',
    this.missingFields = const <String>[],
  });

  final String taxTreatment;
  final List<String> missingFields;

  bool get isKnown =>
      knownSubscriptionTaxTreatment(taxTreatment) != null &&
      missingFields.isEmpty;

  bool get isBlocked => !isKnown;
}

String? knownSubscriptionTaxTreatment(String? raw) {
  final value = (raw ?? '').trim();
  if (kKnownSubscriptionTaxTreatments.contains(value)) return value;
  return null;
}

/// Country used for SaaS fiscal treatment. Billing country wins, then the
/// saved company country. Unlike [resolveActiveCompanyPricingMarket], this
/// never silently defaults to BE — a missing country stays missing.
String resolveAuthoritativeFiscalCountry({
  String billingCountry = '',
  String companyCountry = '',
}) {
  final fromBilling = normalizeFluxidiPricingMarket(billingCountry);
  if (fromBilling.isNotEmpty) return fromBilling;
  return normalizeFluxidiPricingMarket(companyCountry);
}

String resolveAuthoritativeVatNumber({
  String businessVatNumber = '',
  String companyVatNumber = '',
}) {
  final fromBusiness = businessVatNumber.trim();
  if (fromBusiness.isNotEmpty) return fromBusiness;
  return companyVatNumber.trim();
}

/// Resolve fiscal treatment for company subscription / add-on checkout.
///
/// Precedence:
///   1. a known treatment on the product quote (e.g. extra_vehicle);
///   2. a known treatment on the current display quote;
///   3. the saved company / billing country + VAT profile.
///
/// Incomplete fiscal data stays blocked and lists the exact missing fields.
SubscriptionFiscalVerdict resolveCompanySubscriptionFiscalTreatment({
  String quoteTaxTreatment = '',
  String productQuoteTaxTreatment = '',
  String billingCountry = '',
  String companyCountry = '',
  String vatNumber = '',
  bool? vatEnabled,
}) {
  final fromProduct = knownSubscriptionTaxTreatment(productQuoteTaxTreatment);
  if (fromProduct != null) {
    return SubscriptionFiscalVerdict(taxTreatment: fromProduct);
  }
  final fromQuote = knownSubscriptionTaxTreatment(quoteTaxTreatment);
  if (fromQuote != null) {
    return SubscriptionFiscalVerdict(taxTreatment: fromQuote);
  }

  final missing = <String>[];
  final country = resolveAuthoritativeFiscalCountry(
    billingCountry: billingCountry,
    companyCountry: companyCountry,
  );
  if (country.isEmpty) missing.add(kFiscalFieldBillingCountry);

  final vat = resolveAuthoritativeVatNumber(businessVatNumber: vatNumber);
  if (vat.isEmpty) missing.add(kFiscalFieldVatNumber);

  if (vatEnabled == false) missing.add(kFiscalFieldVatEnabled);

  if (missing.isNotEmpty) {
    return SubscriptionFiscalVerdict(missingFields: missing);
  }

  if (country == 'BE') {
    return const SubscriptionFiscalVerdict(
      taxTreatment: kSubscriptionTaxBelgianVat,
    );
  }
  if (isFluxidiLaunchMarket(country)) {
    return const SubscriptionFiscalVerdict(
      taxTreatment: kSubscriptionTaxEuReverseCharge,
    );
  }
  return const SubscriptionFiscalVerdict(
    missingFields: [kFiscalFieldBillingCountry],
  );
}

String subscriptionFiscalFieldLabel({
  required String field,
  required String languageCode,
}) {
  switch (field) {
    case kFiscalFieldBillingCountry:
      return _t(
        languageCode,
        nl: 'factuurland',
        en: 'billing country',
        fr: 'pays de facturation',
        es: 'país de facturación',
      );
    case kFiscalFieldVatNumber:
      return _t(
        languageCode,
        nl: 'btw-nummer',
        en: 'VAT number',
        fr: 'numéro de TVA',
        es: 'número de IVA',
      );
    case kFiscalFieldVatEnabled:
      return _t(
        languageCode,
        nl: 'btw-instelling',
        en: 'VAT setting',
        fr: 'paramètre TVA',
        es: 'ajuste de IVA',
      );
    default:
      return field;
  }
}

String subscriptionFiscalMissingFieldsMessage({
  required String languageCode,
  required List<String> missingFields,
}) {
  if (missingFields.isEmpty) return '';
  final labels = missingFields
      .map(
        (field) => subscriptionFiscalFieldLabel(
          field: field,
          languageCode: languageCode,
        ),
      )
      .toList(growable: false);
  final joined = labels.join(', ');
  return _t(
    languageCode,
    nl: 'Ontbrekend: $joined.',
    en: 'Missing: $joined.',
    fr: 'Manquant : $joined.',
    es: 'Falta: $joined.',
  );
}

String subscriptionFiscalBlockedMessage({
  required String languageCode,
  required List<String> missingFields,
}) {
  final base = _t(
    languageCode,
    nl: 'Fiscale behandeling onbekend. Checkout is geblokkeerd.',
    en: 'Tax treatment unknown. Checkout is blocked.',
    fr: 'Traitement fiscal inconnu. Le paiement est bloqué.',
    es: 'Tratamiento fiscal desconocido. El pago está bloqueado.',
  );
  final fields = subscriptionFiscalMissingFieldsMessage(
    languageCode: languageCode,
    missingFields: missingFields,
  );
  if (fields.isEmpty) return base;
  return '$base $fields';
}

String openVatSettingsActionLabel(String languageCode) {
  return _t(
    languageCode,
    nl: 'Open btw-instellingen',
    en: 'Open VAT settings',
    fr: 'Ouvrir les paramètres TVA',
    es: 'Abrir ajustes de IVA',
  );
}

String _t(
  String languageCode, {
  required String nl,
  required String en,
  required String fr,
  required String es,
}) {
  switch (languageCode.trim().toLowerCase()) {
    case 'en':
      return en;
    case 'fr':
      return fr;
    case 'es':
      return es;
    case 'nl':
    default:
      return nl;
  }
}
