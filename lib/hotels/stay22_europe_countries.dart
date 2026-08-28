import 'hotel_geo_taxonomy.dart';

part 'stay22_europe_destinations.dart';

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
/// Destination cities live in [kStay22EuropeDestinationSeeds] and are attached
/// through [kStay22EuropeanCountries].
const List<HotelGeoCountry> kStay22EuropeanCountryIdentities = <HotelGeoCountry>[
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

/// Unified extra-country catalogue: existing ISO labels plus curated major cities.
List<HotelGeoCountry> get kStay22EuropeanCountries =>
    stay22EuropeanCountriesWithDestinations();

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

class Stay22CountryIdentity {
  const Stay22CountryIdentity({
    required this.isoCode,
    required this.englishName,
    required this.localizedLabel,
    required this.hasSeededTaxonomy,
    this.hideRegionSelector = false,
  });

  final String isoCode;
  final String englishName;
  final String localizedLabel;
  final bool hasSeededTaxonomy;
  final bool hideRegionSelector;

  bool get showRegionSelector =>
      hasSeededTaxonomy && !hideRegionSelector;
  bool get showCitySelector => hasSeededTaxonomy;
}

String stay22NormalizeCountryLabel(String raw) {
  return raw
      .trim()
      .toLowerCase()
      .replaceAll('é', 'e')
      .replaceAll('è', 'e')
      .replaceAll('ê', 'e')
      .replaceAll('ë', 'e')
      .replaceAll('á', 'a')
      .replaceAll('à', 'a')
      .replaceAll('â', 'a')
      .replaceAll('ä', 'a')
      .replaceAll('í', 'i')
      .replaceAll('ì', 'i')
      .replaceAll('î', 'i')
      .replaceAll('ï', 'i')
      .replaceAll('ó', 'o')
      .replaceAll('ò', 'o')
      .replaceAll('ô', 'o')
      .replaceAll('ö', 'o')
      .replaceAll('ú', 'u')
      .replaceAll('ù', 'u')
      .replaceAll('û', 'u')
      .replaceAll('ü', 'u')
      .replaceAll('ñ', 'n')
      .replaceAll('ç', 'c')
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .trim();
}

Iterable<HotelGeoCountry> stay22AllKnownCountries() sync* {
  final seen = <String>{};
  for (final country in <HotelGeoCountry>[
    ...kHotelGeoTaxonomy,
    ...kStay22EuropeanCountries,
  ]) {
    final code = country.code.trim().toUpperCase();
    if (code.isEmpty || seen.contains(code)) continue;
    seen.add(code);
    yield country;
  }
}

Stay22CountryIdentity? stay22CountryIdentityFor({
  required String countryCode,
  required String languageCode,
}) {
  final country = stay22CatalogueCountryByCode(countryCode);
  if (country == null) return null;
  return Stay22CountryIdentity(
    isoCode: country.code.toUpperCase(),
    englishName: country.labels.en,
    localizedLabel: country.labels.of(languageCode),
    hasSeededTaxonomy: stay22CountryHasMajorCities(country),
    hideRegionSelector: country.hideRegionSelector,
  );
}

bool stay22CountryHasSeededTaxonomy(String countryCode) {
  return stay22CountryIdentityFor(
        countryCode: countryCode,
        languageCode: 'en',
      )?.hasSeededTaxonomy ==
      true;
}

String? stay22ResolveIsoCountryCode(String? raw) {
  final text = (raw ?? '').trim();
  if (text.isEmpty) return null;
  final upper = text.toUpperCase().replaceAll(RegExp(r'[^A-Z]'), '');
  if (upper.length == 2 && stay22EuropeanCountryByCode(upper) != null) {
    return upper;
  }
  final normalized = stay22NormalizeCountryLabel(text);
  if (normalized.isEmpty) return null;
  for (final country in stay22AllKnownCountries()) {
    if (stay22NormalizeCountryLabel(country.code) == normalized) {
      return country.code.toUpperCase();
    }
    if (country.labels.allValuesNormalized().contains(normalized) ||
        stay22NormalizeCountryLabel(country.labels.en) == normalized ||
        stay22NormalizeCountryLabel(country.labels.nl) == normalized ||
        stay22NormalizeCountryLabel(country.labels.fr) == normalized ||
        stay22NormalizeCountryLabel(country.labels.es) == normalized) {
      return country.code.toUpperCase();
    }
  }
  if (normalized == 'uk' ||
      normalized == 'great britain' ||
      normalized == 'britain') {
    return 'GB';
  }
  return null;
}

Set<String> stay22CountryFilterValues(String countryCode) {
  final iso = stay22ResolveIsoCountryCode(countryCode) ?? countryCode.trim();
  if (iso.isEmpty) return const <String>{};
  final values = <String>{iso.toLowerCase()};
  final country = stay22EuropeanCountryByCode(iso);
  if (country != null) {
    values.addAll(country.labels.allValuesNormalized());
    values.add(stay22NormalizeCountryLabel(country.labels.en));
  }
  values.addAll(hotelGeoCountryMatchValues(iso));
  return values;
}

bool stay22StayMatchesCountry({
  required String stayCountry,
  required String selectedCountryCode,
}) {
  if (selectedCountryCode.trim().isEmpty ||
      selectedCountryCode.trim().toLowerCase() == 'all') {
    return true;
  }
  final selectedIso =
      stay22ResolveIsoCountryCode(selectedCountryCode) ??
      selectedCountryCode.trim().toUpperCase();
  final stayIso = stay22ResolveIsoCountryCode(stayCountry);
  if (stayIso != null && stayIso == selectedIso) return true;
  final matchValues = stay22CountryFilterValues(selectedIso);
  return matchValues.contains(stay22NormalizeCountryLabel(stayCountry));
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
