import 'hotel_geo_taxonomy.dart';

/// Priority Stay22 markets. These are shortcuts, not an allowlist.
const List<String> kStay22PriorityCountryCodes = <String>[
  'BE',
  'NL',
  'LU',
  'FR',
  'DE',
  'ES',
  'GB',
];

const Set<String> kStay22EuroAreaCountryCodes = <String>{
  'AT',
  'BE',
  'CY',
  'DE',
  'EE',
  'ES',
  'FI',
  'FR',
  'GR',
  'HR',
  'IE',
  'IT',
  'LT',
  'LU',
  'LV',
  'MT',
  'NL',
  'PT',
  'SI',
  'SK',
};

/// Localized European countries available in the hotel country picker.
/// Extra countries have no native featured inventory; they only improve Stay22
/// destination resolution.
const List<HotelGeoCountry> kStay22EuropeanCountries = <HotelGeoCountry>[
  HotelGeoCountry(
    code: 'AL',
    labels: HotelGeoLabel(
      nl: 'Albanië',
      en: 'Albania',
      fr: 'Albanie',
      es: 'Albania',
    ),
  ),
  HotelGeoCountry(
    code: 'AD',
    labels: HotelGeoLabel(
      nl: 'Andorra',
      en: 'Andorra',
      fr: 'Andorre',
      es: 'Andorra',
    ),
  ),
  HotelGeoCountry(
    code: 'AT',
    labels: HotelGeoLabel(
      nl: 'Oostenrijk',
      en: 'Austria',
      fr: 'Autriche',
      es: 'Austria',
    ),
  ),
  HotelGeoCountry(
    code: 'BA',
    labels: HotelGeoLabel(
      nl: 'Bosnië en Herzegovina',
      en: 'Bosnia and Herzegovina',
      fr: 'Bosnie-Herzégovine',
      es: 'Bosnia y Herzegovina',
    ),
  ),
  HotelGeoCountry(
    code: 'BG',
    labels: HotelGeoLabel(
      nl: 'Bulgarije',
      en: 'Bulgaria',
      fr: 'Bulgarie',
      es: 'Bulgaria',
    ),
  ),
  HotelGeoCountry(
    code: 'CH',
    labels: HotelGeoLabel(
      nl: 'Zwitserland',
      en: 'Switzerland',
      fr: 'Suisse',
      es: 'Suiza',
    ),
  ),
  HotelGeoCountry(
    code: 'CY',
    labels: HotelGeoLabel(
      nl: 'Cyprus',
      en: 'Cyprus',
      fr: 'Chypre',
      es: 'Chipre',
    ),
  ),
  HotelGeoCountry(
    code: 'CZ',
    labels: HotelGeoLabel(
      nl: 'Tsjechië',
      en: 'Czechia',
      fr: 'Tchéquie',
      es: 'Chequia',
    ),
  ),
  HotelGeoCountry(
    code: 'DK',
    labels: HotelGeoLabel(
      nl: 'Denemarken',
      en: 'Denmark',
      fr: 'Danemark',
      es: 'Dinamarca',
    ),
  ),
  HotelGeoCountry(
    code: 'EE',
    labels: HotelGeoLabel(
      nl: 'Estland',
      en: 'Estonia',
      fr: 'Estonie',
      es: 'Estonia',
    ),
  ),
  HotelGeoCountry(
    code: 'FI',
    labels: HotelGeoLabel(
      nl: 'Finland',
      en: 'Finland',
      fr: 'Finlande',
      es: 'Finlandia',
    ),
  ),
  HotelGeoCountry(
    code: 'GR',
    labels: HotelGeoLabel(
      nl: 'Griekenland',
      en: 'Greece',
      fr: 'Grèce',
      es: 'Grecia',
    ),
  ),
  HotelGeoCountry(
    code: 'HR',
    labels: HotelGeoLabel(
      nl: 'Kroatië',
      en: 'Croatia',
      fr: 'Croatie',
      es: 'Croacia',
    ),
  ),
  HotelGeoCountry(
    code: 'HU',
    labels: HotelGeoLabel(
      nl: 'Hongarije',
      en: 'Hungary',
      fr: 'Hongrie',
      es: 'Hungría',
    ),
  ),
  HotelGeoCountry(
    code: 'IE',
    labels: HotelGeoLabel(
      nl: 'Ierland',
      en: 'Ireland',
      fr: 'Irlande',
      es: 'Irlanda',
    ),
  ),
  HotelGeoCountry(
    code: 'IS',
    labels: HotelGeoLabel(
      nl: 'IJsland',
      en: 'Iceland',
      fr: 'Islande',
      es: 'Islandia',
    ),
  ),
  HotelGeoCountry(
    code: 'IT',
    labels: HotelGeoLabel(
      nl: 'Italië',
      en: 'Italy',
      fr: 'Italie',
      es: 'Italia',
    ),
  ),
  HotelGeoCountry(
    code: 'LI',
    labels: HotelGeoLabel(
      nl: 'Liechtenstein',
      en: 'Liechtenstein',
      fr: 'Liechtenstein',
      es: 'Liechtenstein',
    ),
  ),
  HotelGeoCountry(
    code: 'LT',
    labels: HotelGeoLabel(
      nl: 'Litouwen',
      en: 'Lithuania',
      fr: 'Lituanie',
      es: 'Lituania',
    ),
  ),
  HotelGeoCountry(
    code: 'LV',
    labels: HotelGeoLabel(
      nl: 'Letland',
      en: 'Latvia',
      fr: 'Lettonie',
      es: 'Letonia',
    ),
  ),
  HotelGeoCountry(
    code: 'MC',
    labels: HotelGeoLabel(
      nl: 'Monaco',
      en: 'Monaco',
      fr: 'Monaco',
      es: 'Mónaco',
    ),
  ),
  HotelGeoCountry(
    code: 'MD',
    labels: HotelGeoLabel(
      nl: 'Moldavië',
      en: 'Moldova',
      fr: 'Moldavie',
      es: 'Moldavia',
    ),
  ),
  HotelGeoCountry(
    code: 'ME',
    labels: HotelGeoLabel(
      nl: 'Montenegro',
      en: 'Montenegro',
      fr: 'Monténégro',
      es: 'Montenegro',
    ),
  ),
  HotelGeoCountry(
    code: 'MK',
    labels: HotelGeoLabel(
      nl: 'Noord-Macedonië',
      en: 'North Macedonia',
      fr: 'Macédoine du Nord',
      es: 'Macedonia del Norte',
    ),
  ),
  HotelGeoCountry(
    code: 'MT',
    labels: HotelGeoLabel(nl: 'Malta', en: 'Malta', fr: 'Malte', es: 'Malta'),
  ),
  HotelGeoCountry(
    code: 'NO',
    labels: HotelGeoLabel(
      nl: 'Noorwegen',
      en: 'Norway',
      fr: 'Norvège',
      es: 'Noruega',
    ),
  ),
  HotelGeoCountry(
    code: 'PL',
    labels: HotelGeoLabel(
      nl: 'Polen',
      en: 'Poland',
      fr: 'Pologne',
      es: 'Polonia',
    ),
  ),
  HotelGeoCountry(
    code: 'PT',
    labels: HotelGeoLabel(
      nl: 'Portugal',
      en: 'Portugal',
      fr: 'Portugal',
      es: 'Portugal',
    ),
  ),
  HotelGeoCountry(
    code: 'RO',
    labels: HotelGeoLabel(
      nl: 'Roemenië',
      en: 'Romania',
      fr: 'Roumanie',
      es: 'Rumanía',
    ),
  ),
  HotelGeoCountry(
    code: 'RS',
    labels: HotelGeoLabel(
      nl: 'Servië',
      en: 'Serbia',
      fr: 'Serbie',
      es: 'Serbia',
    ),
  ),
  HotelGeoCountry(
    code: 'SE',
    labels: HotelGeoLabel(
      nl: 'Zweden',
      en: 'Sweden',
      fr: 'Suède',
      es: 'Suecia',
    ),
  ),
  HotelGeoCountry(
    code: 'SI',
    labels: HotelGeoLabel(
      nl: 'Slovenië',
      en: 'Slovenia',
      fr: 'Slovénie',
      es: 'Eslovenia',
    ),
  ),
  HotelGeoCountry(
    code: 'SK',
    labels: HotelGeoLabel(
      nl: 'Slowakije',
      en: 'Slovakia',
      fr: 'Slovaquie',
      es: 'Eslovaquia',
    ),
  ),
  HotelGeoCountry(
    code: 'SM',
    labels: HotelGeoLabel(
      nl: 'San Marino',
      en: 'San Marino',
      fr: 'Saint-Marin',
      es: 'San Marino',
    ),
  ),
  HotelGeoCountry(
    code: 'UA',
    labels: HotelGeoLabel(
      nl: 'Oekraïne',
      en: 'Ukraine',
      fr: 'Ukraine',
      es: 'Ucrania',
    ),
  ),
  HotelGeoCountry(
    code: 'VA',
    labels: HotelGeoLabel(
      nl: 'Vaticaanstad',
      en: 'Vatican City',
      fr: 'Cité du Vatican',
      es: 'Ciudad del Vaticano',
    ),
  ),
  HotelGeoCountry(
    code: 'XK',
    labels: HotelGeoLabel(
      nl: 'Kosovo',
      en: 'Kosovo',
      fr: 'Kosovo',
      es: 'Kosovo',
    ),
  ),
];

HotelGeoCountry? stay22EuropeanCountryByCode(String countryCode) {
  final normalized = countryCode.trim().toUpperCase();
  if (normalized.isEmpty) return null;
  for (final country in kStay22EuropeanCountries) {
    if (country.code.toUpperCase() == normalized) return country;
  }
  for (final country in kHotelGeoTaxonomy) {
    if (country.code.toUpperCase() == normalized) return country;
  }
  return null;
}

String? stay22EnglishCountryName(String countryCode) {
  final country = stay22EuropeanCountryByCode(countryCode);
  return country?.labels.en;
}

/// Country picker options: priority markets first, then the rest of Europe,
/// sorted locally, without duplicate ISO codes.
List<HotelGeoOption> stay22CountryPickerOptions(String languageCode) {
  final byCode = <String, HotelGeoCountry>{};
  for (final country in kHotelGeoTaxonomy) {
    byCode[country.code.toUpperCase()] = country;
  }
  for (final country in kStay22EuropeanCountries) {
    byCode.putIfAbsent(country.code.toUpperCase(), () => country);
  }

  HotelGeoOption optionFor(String code) {
    final country = byCode[code]!;
    return HotelGeoOption(
      value: country.code,
      label: country.labels.of(languageCode),
    );
  }

  final priority =
      kStay22PriorityCountryCodes
          .where(byCode.containsKey)
          .map(optionFor)
          .toList()
        ..sort((a, b) => a.label.compareTo(b.label));
  final rest =
      byCode.keys
          .where((code) => !kStay22PriorityCountryCodes.contains(code))
          .map(optionFor)
          .toList()
        ..sort((a, b) => a.label.compareTo(b.label));
  return <HotelGeoOption>[...priority, ...rest];
}
