// COMPANY-CUSTOMER-OPS-P0 — existing language and calling-code choices.

import 'package:fluxidi_tracking/app_strings.dart';

class CompanyCustomerLocaleOption {
  const CompanyCustomerLocaleOption({
    required this.code,
    required this.label,
  });

  final String code;
  final LocalizedText label;
}

class CompanyCustomerCallingCodeOption {
  const CompanyCustomerCallingCodeOption({
    required this.callingCode,
    required this.countryCode,
    required this.label,
  });

  final String callingCode;
  final String countryCode;
  final LocalizedText label;
}

const List<CompanyCustomerLocaleOption> kCompanyCustomerLocaleOptions =
    <CompanyCustomerLocaleOption>[
      CompanyCustomerLocaleOption(
        code: 'nl',
        label: LocalizedText(
          nl: 'Nederlands',
          en: 'Dutch',
          fr: 'Néerlandais',
          es: 'Neerlandés',
        ),
      ),
      CompanyCustomerLocaleOption(
        code: 'en',
        label: LocalizedText(
          nl: 'Engels',
          en: 'English',
          fr: 'Anglais',
          es: 'Inglés',
        ),
      ),
      CompanyCustomerLocaleOption(
        code: 'fr',
        label: LocalizedText(
          nl: 'Frans',
          en: 'French',
          fr: 'Français',
          es: 'Francés',
        ),
      ),
      CompanyCustomerLocaleOption(
        code: 'es',
        label: LocalizedText(
          nl: 'Spaans',
          en: 'Spanish',
          fr: 'Espagnol',
          es: 'Español',
        ),
      ),
      CompanyCustomerLocaleOption(
        code: 'de',
        label: LocalizedText(
          nl: 'Duits',
          en: 'German',
          fr: 'Allemand',
          es: 'Alemán',
        ),
      ),
    ];

const List<CompanyCustomerCallingCodeOption> kCompanyCustomerCallingCodeOptions =
    <CompanyCustomerCallingCodeOption>[
      CompanyCustomerCallingCodeOption(
        callingCode: '31',
        countryCode: 'NL',
        label: LocalizedText(
          nl: 'Nederland (+31)',
          en: 'Netherlands (+31)',
          fr: 'Pays-Bas (+31)',
          es: 'Países Bajos (+31)',
        ),
      ),
      CompanyCustomerCallingCodeOption(
        callingCode: '32',
        countryCode: 'BE',
        label: LocalizedText(
          nl: 'België (+32)',
          en: 'Belgium (+32)',
          fr: 'Belgique (+32)',
          es: 'Bélgica (+32)',
        ),
      ),
      CompanyCustomerCallingCodeOption(
        callingCode: '33',
        countryCode: 'FR',
        label: LocalizedText(
          nl: 'Frankrijk (+33)',
          en: 'France (+33)',
          fr: 'France (+33)',
          es: 'Francia (+33)',
        ),
      ),
      CompanyCustomerCallingCodeOption(
        callingCode: '34',
        countryCode: 'ES',
        label: LocalizedText(
          nl: 'Spanje (+34)',
          en: 'Spain (+34)',
          fr: 'Espagne (+34)',
          es: 'España (+34)',
        ),
      ),
      CompanyCustomerCallingCodeOption(
        callingCode: '44',
        countryCode: 'GB',
        label: LocalizedText(
          nl: 'Verenigd Koninkrijk (+44)',
          en: 'United Kingdom (+44)',
          fr: 'Royaume-Uni (+44)',
          es: 'Reino Unido (+44)',
        ),
      ),
      CompanyCustomerCallingCodeOption(
        callingCode: '49',
        countryCode: 'DE',
        label: LocalizedText(
          nl: 'Duitsland (+49)',
          en: 'Germany (+49)',
          fr: 'Allemagne (+49)',
          es: 'Alemania (+49)',
        ),
      ),
    ];

String normalizeCompanyCustomerCallingCode(String raw) =>
    raw.replaceAll(RegExp(r'[^0-9]'), '');
