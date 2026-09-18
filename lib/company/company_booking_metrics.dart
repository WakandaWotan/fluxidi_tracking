num? parseCompanyBookingMoney(Object? raw) {
  if (raw == null) return null;
  if (raw is num && raw.isFinite) return raw;
  final text = raw.toString().trim().replaceAll(',', '.');
  if (text.isEmpty) return null;
  return num.tryParse(text);
}

int? parseCompanyBookingDurationMin(Object? raw) {
  final money = parseCompanyBookingMoney(raw);
  if (money == null || money <= 0) return null;
  return money.round();
}

Object? _firstRaw(Map<String, dynamic> raw, List<String> keys) {
  for (final key in keys) {
    if (!raw.containsKey(key) || raw[key] == null) continue;
    return raw[key];
  }
  return null;
}

Map<String, dynamic> _asMap(Object? raw) {
  if (raw is Map) return Map<String, dynamic>.from(raw);
  return const <String, dynamic>{};
}

List<Map<String, dynamic>> _legsOf(Map<String, dynamic> raw) {
  final record = raw['record'] is Map ? _asMap(raw['record']) : raw;
  final booking = _asMap(record['booking']);
  final fromRecord = record['operational_legs'] ?? record['operationalLegs'];
  final fromBooking = booking['operational_legs'] ?? booking['operationalLegs'];
  final source = fromRecord is List && fromRecord.isNotEmpty
      ? fromRecord
      : fromBooking;
  if (source is! List) return const <Map<String, dynamic>>[];
  return [
    for (final item in source)
      if (item is Map) Map<String, dynamic>.from(item),
  ];
}

Map<String, dynamic> _outboundLeg(Map<String, dynamic> raw) {
  final legs = _legsOf(raw);
  for (final leg in legs) {
    final type = (leg['leg_type'] ?? leg['legType'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    if (type == 'outbound') return leg;
  }
  return legs.isEmpty ? const <String, dynamic>{} : legs.first;
}

Map<String, dynamic> _returnLeg(Map<String, dynamic> raw) {
  final legs = _legsOf(raw);
  for (final leg in legs) {
    final type = (leg['leg_type'] ?? leg['legType'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    if (type == 'return' || type == 'inbound') return leg;
  }
  return const <String, dynamic>{};
}

int? resolveCompanyBookingDurationMin(Map<String, dynamic> raw) {
  final record = raw['record'] is Map ? _asMap(raw['record']) : raw;
  final booking = _asMap(record['booking']);
  final quote = _asMap(record['quote'] ?? raw['quote']);
  final pricingMain = _asMap(quote['pricing_main']);
  final breakdown = _asMap(pricingMain['breakdown']);
  final outbound = _outboundLeg(raw);
  const keys = <String>[
    'duration_min',
    'durationMin',
    'duration_minutes',
    'durationMinutes',
    'duration_route_min',
    'route_duration_min',
    'requested_duration_minutes',
  ];
  for (final source in <Map<String, dynamic>>[
    raw,
    record,
    booking,
    outbound,
    quote,
    breakdown,
  ]) {
    final parsed = parseCompanyBookingDurationMin(_firstRaw(source, keys));
    if (parsed != null) return parsed;
  }
  return null;
}

num? resolveCompanyBookingPriceInclVat(Map<String, dynamic> raw) {
  final record = raw['record'] is Map ? _asMap(raw['record']) : raw;
  final booking = _asMap(record['booking']);
  final quote = _asMap(record['quote'] ?? raw['quote']);
  final pricing = _asMap(quote['pricing']);
  final pricingMain = _asMap(quote['pricing_main']);
  final outbound = _outboundLeg(raw);
  const totalKeys = <String>[
    'total_price_incl_vat',
    'totalPriceInclVat',
    'total_price',
    'totalPrice',
  ];
  for (final source in <Map<String, dynamic>>[
    raw,
    record,
    booking,
    quote,
    pricing,
  ]) {
    final parsed = parseCompanyBookingMoney(_firstRaw(source, totalKeys));
    if (parsed != null) return parsed;
  }
  final outboundPrice = parseCompanyBookingMoney(
    _firstRaw(outbound, const [
      'price_incl_vat',
      'priceInclVat',
    ]) ??
        _firstRaw(pricingMain, const [
          'price_incl_vat',
          'priceInclVat',
          'price_incl_vat_main',
        ]) ??
        _firstRaw(raw, const [
          'outbound_price_incl_vat',
          'price_incl_vat',
          'priceInclVat',
        ]),
  );
  final inbound = _returnLeg(raw);
  final returnPrice = parseCompanyBookingMoney(
    _firstRaw(raw, const [
      'return_price_incl_vat',
      'price_incl_vat_return',
    ]) ??
        _firstRaw(record, const [
          'return_price_incl_vat',
          'price_incl_vat_return',
        ]) ??
        _firstRaw(booking, const [
          'return_price_incl_vat',
          'price_incl_vat_return',
        ]) ??
        _firstRaw(quote, const [
          'return_price_incl_vat',
          'price_incl_vat_return',
        ]) ??
        _firstRaw(inbound, const [
          'price_incl_vat',
          'priceInclVat',
        ]),
  );
  if (outboundPrice != null && returnPrice != null) {
    return outboundPrice + returnPrice;
  }
  const keys = <String>[
    'price_incl_vat',
    'priceInclVat',
    'amount_incl_vat',
    'price',
  ];
  for (final source in <Map<String, dynamic>>[
    raw,
    record,
    booking,
    outbound,
    pricing,
    pricingMain,
    quote,
  ]) {
    final parsed = parseCompanyBookingMoney(_firstRaw(source, keys));
    if (parsed != null) return parsed;
  }
  return outboundPrice ?? returnPrice;
}

String resolveCompanyBookingCurrency(Map<String, dynamic> raw) {
  final record = raw['record'] is Map ? _asMap(raw['record']) : raw;
  final booking = _asMap(record['booking']);
  final quote = _asMap(record['quote'] ?? raw['quote']);
  final pricing = _asMap(quote['pricing']);
  for (final source in <Map<String, dynamic>>[raw, record, booking, quote, pricing]) {
    final value = (source['currency'] ?? '').toString().trim();
    if (value.isNotEmpty) return value;
  }
  return 'EUR';
}

String formatCompanyBookingMoney(num amount, [String currency = 'EUR']) {
  final unit = currency.trim().isEmpty ? 'EUR' : currency.trim();
  return '${amount.toStringAsFixed(2).replaceAll('.', ',')} $unit';
}

String formatCompanyBookingDurationMin(int minutes) => '$minutes min';
