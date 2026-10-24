/// Reads the server answer to `POST /quote`.
///
/// Ported from golden commit 9df7e7b92ecc86a11184ee995e255da7b8f6fb68:
/// - `lib/company/company_plan_quote.dart` — `CompanyPlanQuoteResult`,
///   `parseCompanyPlanQuote`, `CompanyPlanQuoteTotalCheck`,
///   `companyPlanQuoteTotalCheck`
/// - `lib/company/company_booking_metrics.dart` — `parseCompanyBookingMoney`,
///   `parseCompanyBookingDurationMin`
/// - `lib/company/company_plan_when.dart` — `companyPlanCanonicalDurationMin`
///
/// The server price is the only price. Nothing here computes or repairs a fare.
library;

class FluxidiQuoteException implements Exception {
  const FluxidiQuoteException(this.code);

  /// Server error code, e.g. `route_failed` or `calculator_off`.
  final String code;

  @override
  String toString() => 'FluxidiQuoteException($code)';
}

num? fluxidiParseMoney(Object? raw) {
  if (raw == null) return null;
  if (raw is num && raw.isFinite) return raw;
  final text = raw.toString().trim().replaceAll(',', '.');
  if (text.isEmpty) return null;
  return num.tryParse(text);
}

int? fluxidiParseDurationMin(Object? raw) {
  final value = fluxidiParseMoney(raw);
  if (value == null || value <= 0) return null;
  final rounded = value.round();
  return rounded <= 0 ? 1 : rounded;
}

bool _flagIsTrue(Object? raw) {
  if (raw == true || raw == 1) return true;
  final text = raw?.toString().trim().toLowerCase() ?? '';
  return text == 'true' || text == '1' || text == 'yes';
}

bool _flagIsFalse(Object? raw) {
  if (raw == false || raw == 0) return true;
  final text = raw?.toString().trim().toLowerCase() ?? '';
  return text == 'false' || text == '0' || text == 'no';
}

num? _sumMoney(num? left, num? right) {
  if (left == null && right == null) return null;
  return (left ?? 0) + (right ?? 0);
}

int? _cents(num? amount) => amount == null ? null : (amount * 100).round();

/// Compares a listed round-trip total with the sum of its legs, in cents.
class FluxidiQuoteTotalCheck {
  const FluxidiQuoteTotalCheck({
    required this.comparable,
    required this.legSumCents,
    required this.listedCents,
  });

  final bool comparable;
  final int? legSumCents;
  final int? listedCents;

  bool get consistent => !comparable || legSumCents == listedCents;
  int get driftCents => comparable ? (listedCents ?? 0) - (legSumCents ?? 0) : 0;
}

FluxidiQuoteTotalCheck fluxidiQuoteTotalCheck({
  required num? outboundInclVat,
  required num? returnInclVat,
  required num? listedTotalInclVat,
}) {
  final outbound = _cents(outboundInclVat);
  final inbound = _cents(returnInclVat);
  final listed = _cents(listedTotalInclVat);
  if (outbound == null || inbound == null || listed == null) {
    return FluxidiQuoteTotalCheck(
      comparable: false,
      legSumCents: outbound != null && inbound != null
          ? outbound + inbound
          : null,
      listedCents: listed,
    );
  }
  return FluxidiQuoteTotalCheck(
    comparable: true,
    legSumCents: outbound + inbound,
    listedCents: listed,
  );
}

class FluxidiQuoteResult {
  const FluxidiQuoteResult({
    required this.fingerprint,
    this.distanceKm,
    this.durationMin,
    this.priceInclVat,
    this.priceExVat,
    this.priceVat,
    this.currency = 'EUR',
    this.pricingSource = '',
    this.priceAvailable = false,
    this.requestQuoteRequired = false,
    this.calculatorOff = false,
    this.fixedPriceSnapshot,
    this.pickupLat,
    this.pickupLon,
    this.dropoffLat,
    this.dropoffLon,
    this.returnDistanceKm,
    this.returnDurationMin,
    this.returnPriceInclVat,
    this.outboundPriceInclVat,
    this.totalPriceInclVat,
    this.message = '',
  });

  /// Fingerprint of the request this answer belongs to.
  final String fingerprint;

  final num? distanceKm;
  final int? durationMin;
  final num? priceInclVat;
  final num? priceExVat;
  final num? priceVat;
  final String currency;
  final String pricingSource;

  /// The server says a price may be shown.
  final bool priceAvailable;

  /// The company wants to quote this ride manually.
  final bool requestQuoteRequired;

  /// The company's calculator is off, so there is no automatic price.
  final bool calculatorOff;

  final Map<String, dynamic>? fixedPriceSnapshot;
  final double? pickupLat;
  final double? pickupLon;
  final double? dropoffLat;
  final double? dropoffLon;
  final num? returnDistanceKm;
  final int? returnDurationMin;
  final num? returnPriceInclVat;
  final num? outboundPriceInclVat;
  final num? totalPriceInclVat;
  final String message;

  bool get hasRoute =>
      distanceKm != null &&
      distanceKm! > 0 &&
      durationMin != null &&
      durationMin! > 0;

  bool get hasReturnRoute =>
      returnDistanceKm != null &&
      returnDistanceKm! > 0 &&
      returnDurationMin != null &&
      returnDurationMin! > 0;

  bool get isFixedPrice => fixedPriceSnapshot != null;

  num? get _outboundForTotalCheck =>
      outboundPriceInclVat ??
      (returnPriceInclVat == null ? priceInclVat : outboundPriceInclVat);

  /// Compares the server total with the sum of its legs. A round trip of
  /// 200 + 200 listed as 401 must surface as a problem, never be rewritten.
  FluxidiQuoteTotalCheck get totalCheck => fluxidiQuoteTotalCheck(
    outboundInclVat: _outboundForTotalCheck,
    returnInclVat: returnPriceInclVat,
    listedTotalInclVat: totalPriceInclVat ?? priceInclVat,
  );

  /// The authoritative server total, never a locally repaired number.
  num? get displayTotalPrice => totalPriceInclVat ?? priceInclVat;
}

FluxidiQuoteResult parseFluxidiQuote(
  Map<String, dynamic> raw, {
  required String fingerprint,
}) {
  if (raw['ok'] != true) {
    final error = raw['error']?.toString().trim() ?? '';
    throw FluxidiQuoteException(error.isEmpty ? 'route_failed' : error);
  }
  final returnRaw = raw['return'] is Map
      ? Map<String, dynamic>.from(raw['return'] as Map)
      : const <String, dynamic>{};

  final outboundPrice = fluxidiParseMoney(
    raw['price_incl_vat_main'] ??
        raw['outbound_price_incl_vat'] ??
        (returnRaw.isEmpty ? raw['price_incl_vat'] : null),
  );
  final returnPrice = fluxidiParseMoney(
    raw['return_price_incl_vat'] ??
        raw['price_incl_vat_return'] ??
        returnRaw['price_incl_vat'],
  );
  final listedTotal = fluxidiParseMoney(raw['total_price_incl_vat']);
  final totalPrice =
      listedTotal ??
      (returnPrice != null
          ? _sumMoney(outboundPrice, returnPrice)
          : (outboundPrice ?? fluxidiParseMoney(raw['price_incl_vat'])));

  return FluxidiQuoteResult(
    fingerprint: fingerprint,
    distanceKm: fluxidiParseMoney(raw['distance_km']),
    durationMin: fluxidiParseDurationMin(raw['duration_min']),
    priceInclVat: totalPrice ?? outboundPrice,
    priceExVat:
        fluxidiParseMoney(raw['price_ex_vat']) ??
        fluxidiParseMoney(raw['price_excl_vat']),
    priceVat: fluxidiParseMoney(raw['price_vat']),
    currency: (raw['currency']?.toString().trim().isNotEmpty == true)
        ? raw['currency'].toString().trim()
        : 'EUR',
    pricingSource: raw['pricing_source']?.toString().trim() ?? '',
    priceAvailable:
        _flagIsTrue(raw['price_available']) ||
        (!_flagIsFalse(raw['price_available']) &&
            (totalPrice ?? outboundPrice) != null &&
            (totalPrice ?? outboundPrice)! > 0 &&
            raw['request_quote_required'] != true &&
            raw['calculator_off'] != true),
    requestQuoteRequired: _flagIsTrue(raw['request_quote_required']),
    calculatorOff: _flagIsTrue(raw['calculator_off']),
    fixedPriceSnapshot: raw['fixed_price_snapshot'] is Map
        ? Map<String, dynamic>.from(raw['fixed_price_snapshot'] as Map)
        : null,
    // The public /quote answers with from_/to_ coordinates; the company agenda
    // quote uses pickup_/dropoff_. Both shapes are read.
    pickupLat: fluxidiParseMoney(
      raw['pickup_lat'] ?? raw['from_lat'],
    )?.toDouble(),
    pickupLon: fluxidiParseMoney(
      raw['pickup_lon'] ?? raw['from_lng'],
    )?.toDouble(),
    dropoffLat: fluxidiParseMoney(
      raw['dropoff_lat'] ?? raw['to_lat'],
    )?.toDouble(),
    dropoffLon: fluxidiParseMoney(
      raw['dropoff_lon'] ?? raw['to_lng'],
    )?.toDouble(),
    returnDistanceKm: fluxidiParseMoney(
      raw['return_distance_km'] ?? returnRaw['distance_km'],
    ),
    returnDurationMin: fluxidiParseDurationMin(
      raw['return_duration_min'] ?? returnRaw['duration_min'],
    ),
    returnPriceInclVat: returnPrice,
    outboundPriceInclVat: outboundPrice,
    totalPriceInclVat: totalPrice,
    message: raw['message']?.toString().trim() ?? '',
  );
}

/// Ride duration to show: the quote wins, then a route estimate.
int? fluxidiCanonicalDurationMin({
  int? quoteDurationMin,
  int? routeDurationMin,
}) {
  if (quoteDurationMin != null && quoteDurationMin > 0) return quoteDurationMin;
  if (routeDurationMin != null && routeDurationMin > 0) return routeDurationMin;
  return null;
}
