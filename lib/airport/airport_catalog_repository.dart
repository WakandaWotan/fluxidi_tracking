// Shared published airport catalog used by Luchthavenvervoer and Limousine.
// The generated `kAirportCatalog` stays the only airport list. This file only
// projects the same supported-country slice that AirportPage already used.

import 'airport_catalog.generated.dart';

const Set<String> kSupportedAirportCountryCodes = <String>{
  'BE',
  'NL',
  'FR',
  'DE',
  'LU',
  'ES',
  'GB',
};

const Set<String> kRequiredAirportIata = <String>{
  'AMS',
  'DUS',
  'BER',
  'MAD',
  'IBZ',
  'LYS',
};

class AirportCatalogAirport {
  const AirportCatalogAirport({
    required this.countryCode,
    required this.countryName,
    required this.city,
    required this.name,
    required this.iata,
    this.latitude,
    this.longitude,
    this.preciseAddress,
  });

  final String countryCode;
  final String countryName;
  final String city;
  final String name;
  final String iata;
  final double? latitude;
  final double? longitude;
  final String? preciseAddress;

  String get id => iata.trim().toLowerCase();

  String get displayLabel {
    final code = iata.trim().toUpperCase();
    final title = name.trim();
    if (title.isEmpty) return code;
    return '$title ($code)';
  }

  String get formattedAddress {
    final precise = (preciseAddress ?? '').trim();
    if (precise.isNotEmpty) return precise;
    final parts = <String>[
      name.trim(),
      if (city.trim().isNotEmpty) city.trim(),
      if (countryName.trim().isNotEmpty) countryName.trim(),
    ];
    return parts.join(', ');
  }
}

const List<AirportCatalogAirport> kAirportCatalogFallback = <AirportCatalogAirport>[
  AirportCatalogAirport(
    countryCode: 'BE',
    countryName: 'België',
    city: 'Brussel',
    name: 'Brussels Airport',
    iata: 'BRU',
  ),
  AirportCatalogAirport(
    countryCode: 'BE',
    countryName: 'België',
    city: 'Charleroi',
    name: 'Brussels South Charleroi Airport',
    iata: 'CRL',
  ),
  AirportCatalogAirport(
    countryCode: 'BE',
    countryName: 'België',
    city: 'Antwerpen',
    name: 'Antwerp Airport',
    iata: 'ANR',
  ),
  AirportCatalogAirport(
    countryCode: 'BE',
    countryName: 'België',
    city: 'Oostende/Brugge',
    name: 'Ostend-Bruges Airport',
    iata: 'OST',
  ),
  AirportCatalogAirport(
    countryCode: 'BE',
    countryName: 'België',
    city: 'Luik',
    name: 'Liège Airport',
    iata: 'LGG',
  ),
  AirportCatalogAirport(
    countryCode: 'NL',
    countryName: 'Nederland',
    city: 'Amsterdam',
    name: 'Amsterdam Schiphol',
    iata: 'AMS',
    latitude: 52.308601,
    longitude: 4.763890,
    preciseAddress: 'Evert van de Beekstraat 202, 1118 CP Schiphol, Nederland',
  ),
  AirportCatalogAirport(
    countryCode: 'NL',
    countryName: 'Nederland',
    city: 'Eindhoven',
    name: 'Eindhoven Airport',
    iata: 'EIN',
  ),
  AirportCatalogAirport(
    countryCode: 'NL',
    countryName: 'Nederland',
    city: 'Rotterdam/Den Haag',
    name: 'Rotterdam The Hague Airport',
    iata: 'RTM',
  ),
  AirportCatalogAirport(
    countryCode: 'NL',
    countryName: 'Nederland',
    city: 'Maastricht',
    name: 'Maastricht Aachen Airport',
    iata: 'MST',
  ),
  AirportCatalogAirport(
    countryCode: 'NL',
    countryName: 'Nederland',
    city: 'Groningen',
    name: 'Groningen Airport Eelde',
    iata: 'GRQ',
  ),
  AirportCatalogAirport(
    countryCode: 'FR',
    countryName: 'Frankrijk',
    city: 'Parijs',
    name: 'Paris Charles de Gaulle',
    iata: 'CDG',
  ),
  AirportCatalogAirport(
    countryCode: 'FR',
    countryName: 'Frankrijk',
    city: 'Parijs',
    name: 'Paris Orly',
    iata: 'ORY',
  ),
  AirportCatalogAirport(
    countryCode: 'FR',
    countryName: 'Frankrijk',
    city: 'Beauvais',
    name: 'Paris Beauvais',
    iata: 'BVA',
  ),
  AirportCatalogAirport(
    countryCode: 'FR',
    countryName: 'Frankrijk',
    city: 'Lyon',
    name: 'Lyon-Saint Exupéry Airport',
    iata: 'LYS',
    latitude: 45.725996,
    longitude: 5.090139,
    preciseAddress: '69125 Colombier-Saugnieu, Frankrijk',
  ),
  AirportCatalogAirport(
    countryCode: 'FR',
    countryName: 'Frankrijk',
    city: 'Marseille',
    name: 'Marseille Provence Airport',
    iata: 'MRS',
  ),
  AirportCatalogAirport(
    countryCode: 'FR',
    countryName: 'Frankrijk',
    city: 'Nice',
    name: 'Nice Côte d’Azur Airport',
    iata: 'NCE',
  ),
  AirportCatalogAirport(
    countryCode: 'DE',
    countryName: 'Duitsland',
    city: 'Frankfurt',
    name: 'Frankfurt Airport',
    iata: 'FRA',
  ),
  AirportCatalogAirport(
    countryCode: 'DE',
    countryName: 'Duitsland',
    city: 'München',
    name: 'Munich Airport',
    iata: 'MUC',
  ),
  AirportCatalogAirport(
    countryCode: 'DE',
    countryName: 'Duitsland',
    city: 'Düsseldorf',
    name: 'Düsseldorf Airport',
    iata: 'DUS',
    latitude: 51.289501,
    longitude: 6.766780,
    preciseAddress: 'Flughafenstraße 105, 40474 Düsseldorf, Duitsland',
  ),
  AirportCatalogAirport(
    countryCode: 'DE',
    countryName: 'Duitsland',
    city: 'Keulen/Bonn',
    name: 'Cologne Bonn Airport',
    iata: 'CGN',
  ),
  AirportCatalogAirport(
    countryCode: 'DE',
    countryName: 'Duitsland',
    city: 'Berlijn',
    name: 'Berlin Brandenburg Airport',
    iata: 'BER',
    latitude: 52.361738,
    longitude: 13.502341,
    preciseAddress: 'Willy-Brandt-Platz, 12529 Schönefeld, Duitsland',
  ),
  AirportCatalogAirport(
    countryCode: 'DE',
    countryName: 'Duitsland',
    city: 'Hamburg',
    name: 'Hamburg Airport',
    iata: 'HAM',
  ),
  AirportCatalogAirport(
    countryCode: 'LU',
    countryName: 'Luxemburg',
    city: 'Luxemburg',
    name: 'Luxembourg Airport',
    iata: 'LUX',
  ),
  AirportCatalogAirport(
    countryCode: 'ES',
    countryName: 'Spanje',
    city: 'Madrid',
    name: 'Madrid Barajas Airport',
    iata: 'MAD',
    latitude: 40.493407,
    longitude: -3.572249,
    preciseAddress: 'Av de la Hispanidad, s/n, 28042 Madrid, Spanje',
  ),
  AirportCatalogAirport(
    countryCode: 'ES',
    countryName: 'Spanje',
    city: 'Barcelona',
    name: 'Barcelona El Prat Airport',
    iata: 'BCN',
  ),
  AirportCatalogAirport(
    countryCode: 'ES',
    countryName: 'Spanje',
    city: 'Málaga',
    name: 'Málaga-Costa del Sol Airport',
    iata: 'AGP',
  ),
  AirportCatalogAirport(
    countryCode: 'ES',
    countryName: 'Spanje',
    city: 'Alicante',
    name: 'Alicante-Elche Miguel Hernández Airport',
    iata: 'ALC',
  ),
  AirportCatalogAirport(
    countryCode: 'ES',
    countryName: 'Spanje',
    city: 'Valencia',
    name: 'Valencia Airport',
    iata: 'VLC',
  ),
  AirportCatalogAirport(
    countryCode: 'ES',
    countryName: 'Spanje',
    city: 'Sevilla',
    name: 'Seville Airport',
    iata: 'SVQ',
  ),
  AirportCatalogAirport(
    countryCode: 'ES',
    countryName: 'Spanje',
    city: 'Palma de Mallorca',
    name: 'Palma de Mallorca Airport',
    iata: 'PMI',
  ),
  AirportCatalogAirport(
    countryCode: 'ES',
    countryName: 'Spanje',
    city: 'Ibiza',
    name: 'Ibiza Airport',
    iata: 'IBZ',
    latitude: 38.872898,
    longitude: 1.373120,
    preciseAddress: '07820 Sant Jordi de ses Salines, Ibiza, Spanje',
  ),
  AirportCatalogAirport(
    countryCode: 'ES',
    countryName: 'Spanje',
    city: 'Tenerife',
    name: 'Tenerife South Airport',
    iata: 'TFS',
  ),
  AirportCatalogAirport(
    countryCode: 'ES',
    countryName: 'Spanje',
    city: 'Gran Canaria',
    name: 'Gran Canaria Airport',
    iata: 'LPA',
  ),
  AirportCatalogAirport(
    countryCode: 'GB',
    countryName: 'Verenigd Koninkrijk',
    city: 'Londen',
    name: 'London Heathrow',
    iata: 'LHR',
  ),
  AirportCatalogAirport(
    countryCode: 'GB',
    countryName: 'Verenigd Koninkrijk',
    city: 'Londen',
    name: 'London Gatwick',
    iata: 'LGW',
  ),
  AirportCatalogAirport(
    countryCode: 'GB',
    countryName: 'Verenigd Koninkrijk',
    city: 'Londen',
    name: 'London Stansted',
    iata: 'STN',
  ),
  AirportCatalogAirport(
    countryCode: 'GB',
    countryName: 'Verenigd Koninkrijk',
    city: 'Londen',
    name: 'London Luton',
    iata: 'LTN',
  ),
  AirportCatalogAirport(
    countryCode: 'GB',
    countryName: 'Verenigd Koninkrijk',
    city: 'Manchester',
    name: 'Manchester Airport',
    iata: 'MAN',
  ),
  AirportCatalogAirport(
    countryCode: 'GB',
    countryName: 'Verenigd Koninkrijk',
    city: 'Birmingham',
    name: 'Birmingham Airport',
    iata: 'BHX',
  ),
];

AirportCatalogAirport airportCatalogAirportFromEntry(AirportCatalogEntry entry) {
  return AirportCatalogAirport(
    countryCode: entry.countryCode,
    countryName: entry.countryName,
    city: entry.municipality,
    name: entry.name,
    iata: entry.iata,
    latitude: entry.latitude,
    longitude: entry.longitude,
    preciseAddress: entry.preciseAddress,
  );
}

List<AirportCatalogAirport> publishedAirportCatalog({
  List<AirportCatalogEntry> catalog = kAirportCatalog,
  Set<String> supportedCountryCodes = kSupportedAirportCountryCodes,
  Set<String> requiredIata = kRequiredAirportIata,
  List<AirportCatalogAirport> fallback = kAirportCatalogFallback,
}) {
  final generated = catalog
      .where(
        (entry) =>
            supportedCountryCodes.contains(entry.countryCode) &&
            entry.iata.trim().length == 3,
      )
      .map(airportCatalogAirportFromEntry)
      .toList(growable: false);
  if (generated.isEmpty) return List<AirportCatalogAirport>.unmodifiable(fallback);
  final iataSet = generated.map((airport) => airport.iata).toSet();
  final missingRequired = requiredIata
      .where((iata) => !iataSet.contains(iata))
      .toList(growable: false);
  if (missingRequired.isNotEmpty) {
    return List<AirportCatalogAirport>.unmodifiable(fallback);
  }
  return List<AirportCatalogAirport>.unmodifiable(generated);
}

List<String> publishedAirportCountryCodes([
  List<AirportCatalogAirport>? airports,
]) {
  final unique = <String>{};
  final codes = <String>[];
  for (final airport in airports ?? publishedAirportCatalog()) {
    if (unique.add(airport.countryCode)) {
      codes.add(airport.countryCode);
    }
  }
  return List<String>.unmodifiable(codes);
}

List<AirportCatalogAirport> airportsForCountry(
  String countryCode, [
  List<AirportCatalogAirport>? airports,
]) {
  final code = countryCode.trim().toUpperCase();
  return List<AirportCatalogAirport>.unmodifiable(
    (airports ?? publishedAirportCatalog()).where(
      (airport) => airport.countryCode == code,
    ),
  );
}

AirportCatalogAirport? airportByIata(
  String iata, {
  String? countryCode,
  List<AirportCatalogAirport>? airports,
}) {
  final code = iata.trim().toUpperCase();
  if (code.length != 3) return null;
  final country = countryCode?.trim().toUpperCase();
  for (final airport in airports ?? publishedAirportCatalog()) {
    if (airport.iata != code) continue;
    if (country != null && country.isNotEmpty && airport.countryCode != country) {
      return null;
    }
    return airport;
  }
  return null;
}

bool isCanonicalPublishedAirport({
  required String iata,
  String? countryCode,
  List<AirportCatalogAirport>? airports,
}) {
  return airportByIata(iata, countryCode: countryCode, airports: airports) !=
      null;
}
