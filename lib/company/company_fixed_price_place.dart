// COMPANY-CUSTOMER-OPS-P0 — readable place text for company fixed prices.

const _kCountryNames = <String>{
  'belgium',
  'belgie',
  'belgië',
  'belgique',
  'netherlands',
  'nederland',
  'france',
  'frankrijk',
  'germany',
  'duitsland',
  'deutschland',
  'luxembourg',
  'luxemburg',
  'spain',
  'spanje',
  'españa',
  'united kingdom',
  'verenigd koninkrijk',
};

String companyFixedPriceLocality(String text) {
  final parts = text
      .split(',')
      .map((part) => part.trim())
      .where((part) => part.isNotEmpty);
  for (final part in parts) {
    final withoutPostal = part
        .replaceAll(RegExp(r'\b\d{4,5}\b'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (withoutPostal.isEmpty) continue;
    if (_kCountryNames.contains(withoutPostal.toLowerCase())) continue;
    return withoutPostal;
  }
  return text.trim();
}

String? companyFixedPricePostcode(String text) {
  final match = RegExp(r'\b(\d{4,5})\b').firstMatch(text.trim());
  return match?.group(1);
}

String companyFixedPricePlaceTypeLabel(String type) {
  switch (type.trim().toLowerCase()) {
    case 'airport':
      return 'Luchthaven';
    case 'postcode':
    case 'zone':
      return 'Postcode of gebied';
    case 'radius':
      return 'Gebied met straal';
    case 'city':
    default:
      return 'Dorp, gemeente of stad';
  }
}

String companyFixedPriceUiPlaceType(String storedType) {
  switch (storedType.trim().toLowerCase()) {
    case 'airport':
      return 'airport';
    case 'postcode':
    case 'zone':
      return 'postcode';
    case 'radius':
    case 'city':
    default:
      return 'city';
  }
}

String companyFixedPriceDirectionLabel(String direction, {required bool airport}) {
  switch (direction.trim().toLowerCase()) {
    case 'both':
    case 'both_ways':
      return 'Beide richtingen';
    case 'to_airport':
      return 'Naar de luchthaven';
    case 'from_airport':
      return 'Vanaf de luchthaven';
    default:
      return airport ? 'Eén richting' : 'Eén richting';
  }
}

String companyFixedPriceRuleSummary(Map<String, dynamic> rule) {
  final origin = rule['origin'] is Map
      ? Map<String, dynamic>.from(rule['origin'] as Map)
      : const <String, dynamic>{};
  final dest = rule['destination'] is Map
      ? Map<String, dynamic>.from(rule['destination'] as Map)
      : const <String, dynamic>{};
  final from = _placeLabel(origin, fallback: rule['airport_iata']?.toString());
  final to = _placeLabel(dest, fallback: rule['airport_iata']?.toString());
  final amount = rule['price_incl_vat'];
  final airport = rule['kind']?.toString() == 'airport' ||
      origin['type']?.toString() == 'airport' ||
      dest['type']?.toString() == 'airport';
  final parts = <String>[
    if (rule['enabled'] == false) 'Uitgeschakeld',
    if (from.isNotEmpty && to.isNotEmpty) '$from → $to',
    if (amount != null) '€$amount incl. btw',
    companyFixedPriceDirectionLabel(
      rule['direction']?.toString() ?? '',
      airport: airport,
    ),
  ];
  return parts.where((part) => part.trim().isNotEmpty).join(' · ');
}

enum CompanyFixedPricesCatalog { airport, city }

bool companyFixedPriceRuleIsAirport(Map<String, dynamic> rule) {
  if (rule['kind']?.toString() == 'airport') return true;
  if ((rule['airport_iata'] ?? '').toString().trim().isNotEmpty) return true;
  bool placeIsAirport(Object? raw) {
    if (raw is! Map) return false;
    return raw['type']?.toString() == 'airport' ||
        (raw['airport_iata'] ?? '').toString().trim().isNotEmpty;
  }

  return placeIsAirport(rule['origin']) || placeIsAirport(rule['destination']);
}

List<Map<String, dynamic>> companyFixedPriceRulesForCatalog(
  Iterable<Map<String, dynamic>> rules,
  CompanyFixedPricesCatalog catalog,
) {
  return rules
      .where(
        (rule) => catalog == CompanyFixedPricesCatalog.airport
            ? companyFixedPriceRuleIsAirport(rule)
            : !companyFixedPriceRuleIsAirport(rule),
      )
      .toList();
}

String _placeLabel(Map<String, dynamic> place, {String? fallback}) {
  for (final key in const ['label', 'value', 'airport_iata', 'city', 'postcode']) {
    final text = place[key]?.toString().trim() ?? '';
    if (text.isNotEmpty) return text;
  }
  return fallback?.trim() ?? '';
}
