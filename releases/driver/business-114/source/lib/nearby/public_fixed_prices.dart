// COMPANY-CUSTOMER-OPS-P0 — public fixed prices shown on the partner profile.

import 'package:flutter/foundation.dart';

import '../app_strings.dart';

const LocalizedText kPublicFixedPricesTitle = LocalizedText(
  nl: 'Onze vaste prijzen',
  en: 'Our fixed prices',
  fr: 'Nos prix fixes',
  es: 'Nuestros precios fijos',
);

const LocalizedText kPublicFixedPricesIntro = LocalizedText(
  nl: 'Bedragen inclusief btw. Het exacte vertrekadres en de datum vult u bij het boeken in.',
  en: 'Amounts include VAT. You enter the exact departure address and date when booking.',
  fr: 'Montants TTC. Vous indiquez l’adresse de départ exacte et la date lors de la réservation.',
  es: 'Importes con IVA. Indique la dirección exacta de salida y la fecha al reservar.',
);

const LocalizedText kPublicFixedPricesAirports = LocalizedText(
  nl: 'Luchthavens',
  en: 'Airports',
  fr: 'Aéroports',
  es: 'Aeropuertos',
);

const LocalizedText kPublicFixedPricesCities = LocalizedText(
  nl: 'Dorpen en steden',
  en: 'Villages and cities',
  fr: 'Villages et villes',
  es: 'Pueblos y ciudades',
);

const LocalizedText kPublicFixedPricesAll = LocalizedText(
  nl: 'Alle vaste prijzen',
  en: 'All fixed prices',
  fr: 'Tous les prix fixes',
  es: 'Todos los precios fijos',
);

const LocalizedText kPublicFixedPricesSearch = LocalizedText(
  nl: 'Zoek op plaats, luchthaven of naam',
  en: 'Search by place, airport or name',
  fr: 'Rechercher par lieu, aéroport ou nom',
  es: 'Buscar por lugar, aeropuerto o nombre',
);

const LocalizedText kPublicFixedPricesNoSearchResult = LocalizedText(
  nl: 'Geen vaste prijs gevonden voor deze zoekopdracht.',
  en: 'No fixed price found for this search.',
  fr: 'Aucun prix fixe trouvé pour cette recherche.',
  es: 'No se encontró ningún precio fijo para esta búsqueda.',
);

const LocalizedText kPublicFixedPricesViewAndBook = LocalizedText(
  nl: 'Bekijk en boek',
  en: 'View and book',
  fr: 'Voir et réserver',
  es: 'Ver y reservar',
);

const LocalizedText kPublicFixedPricesOneWay = LocalizedText(
  nl: 'Enkele rit',
  en: 'One way',
  fr: 'Aller simple',
  es: 'Solo ida',
);

const LocalizedText kPublicFixedPricesPerLeg = LocalizedText(
  nl: 'Per ritdeel',
  en: 'Per leg',
  fr: 'Par trajet',
  es: 'Por trayecto',
);

const LocalizedText kPublicFixedPricesRoundtrip = LocalizedText(
  nl: 'Retour inbegrepen',
  en: 'Return included',
  fr: 'Retour inclus',
  es: 'Vuelta incluida',
);

const LocalizedText kPublicFixedPricesToAirport = LocalizedText(
  nl: 'Naar de luchthaven',
  en: 'To the airport',
  fr: 'Vers l’aéroport',
  es: 'Al aeropuerto',
);

const LocalizedText kPublicFixedPricesFromAirport = LocalizedText(
  nl: 'Vanaf de luchthaven',
  en: 'From the airport',
  fr: 'Depuis l’aéroport',
  es: 'Desde el aeropuerto',
);

const LocalizedText kPublicFixedPricesBothDirections = LocalizedText(
  nl: 'Beide richtingen',
  en: 'Both directions',
  fr: 'Les deux sens',
  es: 'Ambos sentidos',
);

const Key kPublicFixedPricesSectionKey = Key('public_fixed_prices_section');
const Key kPublicFixedPricesAllButtonKey = Key('public_fixed_prices_all');
const Key kPublicFixedPricesAllPageKey = Key('public_fixed_prices_all_page');
const Key kPublicFixedPricesSearchKey = Key('public_fixed_prices_search');

Key publicFixedPriceTileKey(String ruleId) =>
    Key('public_fixed_price_$ruleId');

Key publicFixedPriceBookKey(String ruleId) =>
    Key('public_fixed_price_book_$ruleId');

/// How many fares per group the profile shows before "All fixed prices".
const int kPublicFixedPricesPreviewCount = 3;

class PublicFixedPricePlace {
  const PublicFixedPricePlace({
    required this.type,
    required this.value,
    required this.label,
    required this.airportIata,
    this.lat,
    this.lng,
    this.radiusKm,
  });

  final String type;
  final String value;
  final String label;
  final String airportIata;
  final double? lat;
  final double? lng;
  final double? radiusKm;

  bool get isAirport => type == 'airport' || airportIata.isNotEmpty;

  String get displayText {
    if (label.trim().isNotEmpty) return label.trim();
    if (value.trim().isNotEmpty) return value.trim();
    return airportIata.trim();
  }

  static PublicFixedPricePlace fromJson(Object? raw) {
    final map = raw is Map
        ? raw.map((k, v) => MapEntry(k.toString(), v))
        : const <String, dynamic>{};
    return PublicFixedPricePlace(
      type: (map['type'] ?? '').toString().trim(),
      value: (map['value'] ?? '').toString().trim(),
      label: (map['label'] ?? '').toString().trim(),
      airportIata: (map['airport_iata'] ?? '').toString().trim(),
      lat: _toDouble(map['lat']),
      lng: _toDouble(map['lng']),
      radiusKm: _toDouble(map['radius_km']),
    );
  }
}

class PublicFixedPrice {
  const PublicFixedPrice({
    required this.ruleId,
    required this.name,
    required this.isAirport,
    required this.airportIata,
    required this.direction,
    required this.origin,
    required this.destination,
    required this.priceInclVat,
    required this.vatRate,
    required this.currency,
    required this.priceCovers,
    required this.tier,
    required this.paxMin,
    required this.paxMax,
    required this.bagsMax,
    required this.includesWait,
    required this.includesBags,
    required this.includesExtras,
    required this.includesNote,
    required this.ruleVersion,
    this.zoneSurcharge,
    this.extraPerKm,
    this.includedKm,
  });

  final String ruleId;
  final String name;
  final bool isAirport;
  final String airportIata;
  final String direction;
  final PublicFixedPricePlace origin;
  final PublicFixedPricePlace destination;
  final double priceInclVat;
  final double vatRate;
  final String currency;
  final String priceCovers;
  final String tier;
  final int paxMin;
  final int paxMax;
  final int bagsMax;
  final bool includesWait;
  final bool includesBags;
  final bool includesExtras;
  final String includesNote;
  final int ruleVersion;
  final double? zoneSurcharge;
  final double? extraPerKm;
  final double? includedKm;

  bool get startsAtAirport => origin.isAirport || direction == 'from_airport';

  /// The side the customer still has to fill in: the non-airport place.
  PublicFixedPricePlace get customerPlace =>
      startsAtAirport ? destination : origin;

  static PublicFixedPrice? fromJson(Object? raw) {
    final map = raw is Map
        ? raw.map((k, v) => MapEntry(k.toString(), v))
        : const <String, dynamic>{};
    final ruleId = (map['rule_id'] ?? '').toString().trim();
    final price = _toDouble(map['price_incl_vat']);
    if (ruleId.isEmpty || price == null || price <= 0) return null;
    final origin = PublicFixedPricePlace.fromJson(map['origin']);
    final destination = PublicFixedPricePlace.fromJson(map['destination']);
    final includes = map['includes'] is Map
        ? (map['includes'] as Map).map((k, v) => MapEntry(k.toString(), v))
        : const <String, dynamic>{};
    return PublicFixedPrice(
      ruleId: ruleId,
      name: (map['name'] ?? '').toString().trim(),
      isAirport: (map['kind'] ?? '').toString() == 'airport' ||
          origin.isAirport ||
          destination.isAirport,
      airportIata: (map['airport_iata'] ?? '').toString().trim(),
      direction: (map['direction'] ?? '').toString().trim(),
      origin: origin,
      destination: destination,
      priceInclVat: price,
      vatRate: _toDouble(map['vat_rate']) ?? 0,
      currency: (map['currency'] ?? 'EUR').toString().trim(),
      priceCovers: (map['price_covers'] ?? 'ride').toString().trim(),
      tier: (map['tier'] ?? '').toString().trim(),
      paxMin: _toInt(map['pax_min']) ?? 1,
      paxMax: _toInt(map['pax_max']) ?? 99,
      bagsMax: _toInt(map['bags_max']) ?? 99,
      includesWait: includes['wait'] == true,
      includesBags: includes['bags'] == true,
      includesExtras: includes['extras'] == true,
      includesNote: (includes['note'] ?? '').toString().trim(),
      ruleVersion: _toInt(map['rule_version']) ?? 1,
      zoneSurcharge: _toDouble(map['zone_surcharge']),
      extraPerKm: _toDouble(map['extra_per_km']),
      includedKm: _toDouble(map['included_km']),
    );
  }
}

class PublicFixedPriceCatalog {
  const PublicFixedPriceCatalog({
    required this.airport,
    required this.city,
    required this.fallback,
  });

  final List<PublicFixedPrice> airport;
  final List<PublicFixedPrice> city;
  final String fallback;

  bool get isEmpty => airport.isEmpty && city.isEmpty;
  int get length => airport.length + city.length;

  static const PublicFixedPriceCatalog empty = PublicFixedPriceCatalog(
    airport: <PublicFixedPrice>[],
    city: <PublicFixedPrice>[],
    fallback: 'calculator',
  );
}

PublicFixedPriceCatalog publicFixedPricesFromProfile(Object? profile) {
  final map = profile is Map
      ? profile.map((k, v) => MapEntry(k.toString(), v))
      : const <String, dynamic>{};
  final raw = map['fixed_prices'];
  if (raw is! Map) return PublicFixedPriceCatalog.empty;
  final section = raw.map((k, v) => MapEntry(k.toString(), v));
  List<PublicFixedPrice> parse(Object? list) {
    if (list is! List) return const <PublicFixedPrice>[];
    final out = <PublicFixedPrice>[];
    for (final item in list) {
      final entry = PublicFixedPrice.fromJson(item);
      if (entry != null) out.add(entry);
    }
    return out;
  }

  return PublicFixedPriceCatalog(
    airport: parse(section['airport']),
    city: parse(section['city']),
    fallback: (section['fallback'] ?? 'calculator').toString(),
  );
}

String publicFixedPriceRouteText(PublicFixedPrice entry) {
  final from = entry.origin.displayText;
  final to = entry.destination.displayText;
  if (from.isEmpty && to.isEmpty) return entry.name;
  if (from.isEmpty) return to;
  if (to.isEmpty) return from;
  return '$from → $to';
}

String publicFixedPriceAmountText(PublicFixedPrice entry, AppLanguage lang) {
  final amount = publicFixedPriceMoneyText(entry.priceInclVat);
  final vatPercent = (entry.vatRate * 100).round();
  if (entry.vatRate <= 0) {
    return amount;
  }
  switch (lang) {
    case AppLanguage.en:
      return '$amount incl. $vatPercent% VAT';
    case AppLanguage.fr:
      return '$amount TVA $vatPercent% comprise';
    case AppLanguage.es:
      return '$amount IVA $vatPercent% incl.';
    case AppLanguage.de:
      return '$amount inkl. $vatPercent% MwSt.';
    case AppLanguage.nl:
      return '$amount incl. $vatPercent% btw';
  }
}

String publicFixedPriceMoneyText(double amount) {
  final rounded = (amount * 100).round() / 100;
  final text = rounded.toStringAsFixed(2).replaceAll('.', ',');
  return '€ $text';
}

String publicFixedPriceScopeLabel(PublicFixedPrice entry, AppLanguage lang) {
  if (entry.priceCovers == 'full_assignment') {
    return kPublicFixedPricesRoundtrip.of(lang);
  }
  if (entry.direction == 'both' || entry.direction == 'both_ways') {
    return kPublicFixedPricesPerLeg.of(lang);
  }
  return kPublicFixedPricesOneWay.of(lang);
}

String publicFixedPriceDirectionLabel(
  PublicFixedPrice entry,
  AppLanguage lang,
) {
  if (!entry.isAirport) return '';
  switch (entry.direction) {
    case 'to_airport':
      return kPublicFixedPricesToAirport.of(lang);
    case 'from_airport':
      return kPublicFixedPricesFromAirport.of(lang);
    case 'both':
    case 'both_ways':
      return kPublicFixedPricesBothDirections.of(lang);
    default:
      return '';
  }
}

String publicFixedPriceTierLabel(String tier, AppLanguage lang) {
  switch (tier.trim().toLowerCase()) {
    case 'comfort':
      return 'Comfort';
    case 'private':
      return 'Private';
    case 'premium':
      return 'Premium';
    default:
      return '';
  }
}

List<String> publicFixedPriceConditionLabels(
  PublicFixedPrice entry,
  AppLanguage lang,
) {
  final out = <String>[];
  final tier = publicFixedPriceTierLabel(entry.tier, lang);
  if (tier.isNotEmpty) {
    out.add(
      _pick(
        lang,
        nl: 'Voertuig: $tier',
        en: 'Vehicle: $tier',
        fr: 'Véhicule : $tier',
        es: 'Vehículo: $tier',
      ),
    );
  }
  final paxText = _passengerText(entry, lang);
  if (paxText.isNotEmpty) out.add(paxText);
  if (entry.bagsMax > 0 && entry.bagsMax < 99) {
    out.add(
      _pick(
        lang,
        nl: 'Tot ${entry.bagsMax} bagagestukken',
        en: 'Up to ${entry.bagsMax} bags',
        fr: 'Jusqu’à ${entry.bagsMax} bagages',
        es: 'Hasta ${entry.bagsMax} maletas',
      ),
    );
  }
  if (entry.includesWait) {
    out.add(
      _pick(
        lang,
        nl: 'Wachten inbegrepen',
        en: 'Waiting included',
        fr: 'Attente incluse',
        es: 'Espera incluida',
      ),
    );
  }
  if (entry.includesBags) {
    out.add(
      _pick(
        lang,
        nl: 'Bagage inbegrepen',
        en: 'Luggage included',
        fr: 'Bagages inclus',
        es: 'Equipaje incluido',
      ),
    );
  }
  if (entry.includesExtras) {
    out.add(
      _pick(
        lang,
        nl: 'Extra’s inbegrepen',
        en: 'Extras included',
        fr: 'Suppléments inclus',
        es: 'Extras incluidos',
      ),
    );
  }
  if (entry.includesNote.isNotEmpty) out.add(entry.includesNote);
  return out;
}

List<String> publicFixedPriceSurchargeLabels(
  PublicFixedPrice entry,
  AppLanguage lang,
) {
  final out = <String>[];
  final zone = entry.zoneSurcharge;
  if (zone != null && zone > 0) {
    final amount = publicFixedPriceMoneyText(zone);
    out.add(
      _pick(
        lang,
        nl: 'Gebiedstoeslag $amount buiten het inbegrepen gebied',
        en: 'Area surcharge $amount outside the included area',
        fr: 'Supplément de zone $amount hors de la zone incluse',
        es: 'Recargo de zona $amount fuera del área incluida',
      ),
    );
  }
  final perKm = entry.extraPerKm;
  if (perKm != null && perKm > 0) {
    final amount = publicFixedPriceMoneyText(perKm);
    out.add(
      _pick(
        lang,
        nl: '$amount per extra km buiten het inbegrepen gebied',
        en: '$amount per extra km outside the included area',
        fr: '$amount par km supplémentaire hors zone incluse',
        es: '$amount por km adicional fuera del área incluida',
      ),
    );
  }
  return out;
}

bool publicFixedPriceMatchesQuery(PublicFixedPrice entry, String query) {
  final needle = query.trim().toLowerCase();
  if (needle.isEmpty) return true;
  final haystack = <String>[
    entry.name,
    entry.origin.displayText,
    entry.destination.displayText,
    entry.origin.value,
    entry.destination.value,
    entry.airportIata,
    entry.origin.airportIata,
    entry.destination.airportIata,
  ].join(' ').toLowerCase();
  return haystack.contains(needle);
}

List<PublicFixedPrice> publicFixedPricesMatching(
  List<PublicFixedPrice> entries,
  String query,
) {
  return entries
      .where((entry) => publicFixedPriceMatchesQuery(entry, query))
      .toList(growable: false);
}

String _passengerText(PublicFixedPrice entry, AppLanguage lang) {
  final min = entry.paxMin;
  final max = entry.paxMax;
  if (min <= 1 && max >= 99) return '';
  if (min > 1 && max < 99) {
    return _pick(
      lang,
      nl: '$min–$max passagiers',
      en: '$min–$max passengers',
      fr: '$min–$max passagers',
      es: '$min–$max pasajeros',
    );
  }
  if (max < 99) {
    return _pick(
      lang,
      nl: 'Tot $max passagiers',
      en: 'Up to $max passengers',
      fr: 'Jusqu’à $max passagers',
      es: 'Hasta $max pasajeros',
    );
  }
  return _pick(
    lang,
    nl: 'Vanaf $min passagiers',
    en: 'From $min passengers',
    fr: 'À partir de $min passagers',
    es: 'Desde $min pasajeros',
  );
}

String _pick(
  AppLanguage lang, {
  required String nl,
  required String en,
  required String fr,
  required String es,
}) {
  switch (lang) {
    case AppLanguage.en:
      return en;
    case AppLanguage.fr:
      return fr;
    case AppLanguage.es:
      return es;
    case AppLanguage.de:
      return en;
    case AppLanguage.nl:
      return nl;
  }
}

double? _toDouble(Object? value) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value.replaceAll(',', '.'));
  return null;
}

int? _toInt(Object? value) {
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value.trim());
  return null;
}
