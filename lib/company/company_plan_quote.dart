// COMPANY-AGENDA-P0 — plan-form quote. Server calcPrice only. No local fares.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:fluxidi_tracking/app_config.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/company/company_agenda_http.dart';
import 'package:fluxidi_tracking/company/company_agenda_labels.dart';
import 'package:fluxidi_tracking/company/company_agenda_scope_io.dart'
    if (dart.library.html) 'package:fluxidi_tracking/company/company_agenda_scope_web.dart';
import 'package:fluxidi_tracking/company/company_booking_metrics.dart';
import 'package:fluxidi_tracking/company/company_plan_when.dart';
import 'package:fluxidi_tracking/company/company_ride_options.dart';
import 'package:fluxidi_tracking/limousine/limousine_address_lookup.dart';

const String kCompanyAgendaQuotePath = '/company/agenda/quote';
const Duration kCompanyPlanQuoteDebounce = Duration(milliseconds: 450);

const Key kCompanyPlanQuoteStatusKey = Key('company_plan_quote_status');
const Key kCompanyPlanQuoteRetryKey = Key('company_plan_quote_retry');
const Key kCompanyPlanQuotePriceKey = Key('company_plan_quote_price');
const Key kCompanyPlanQuoteManualDurationKey = Key(
  'company_plan_quote_manual_duration',
);

class CompanyPlanQuoteResult {
  const CompanyPlanQuoteResult({
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
    this.returnPickupLat,
    this.returnPickupLon,
    this.returnDropoffLat,
    this.returnDropoffLon,
    this.outboundPriceInclVat,
    this.totalPriceInclVat,
    this.message = '',
    this.breakdown,
    this.returnBreakdown,
  });

  final String fingerprint;
  final num? distanceKm;
  final int? durationMin;
  final num? priceInclVat;
  final num? priceExVat;
  final num? priceVat;
  final String currency;
  final String pricingSource;
  final bool priceAvailable;
  final bool requestQuoteRequired;
  final bool calculatorOff;
  final Map<String, dynamic>? fixedPriceSnapshot;
  final double? pickupLat;
  final double? pickupLon;
  final double? dropoffLat;
  final double? dropoffLon;
  final num? returnDistanceKm;
  final int? returnDurationMin;
  final num? returnPriceInclVat;
  final double? returnPickupLat;
  final double? returnPickupLon;
  final double? returnDropoffLat;
  final double? returnDropoffLon;
  final num? outboundPriceInclVat;
  final num? totalPriceInclVat;
  final String message;
  final CompanyPlanQuoteBreakdown? breakdown;
  final CompanyPlanQuoteBreakdown? returnBreakdown;

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

  num? get displayTotalPrice =>
      totalPriceInclVat ??
      _sumMoney(outboundPriceInclVat ?? priceInclVat, returnPriceInclVat);
}

class CompanyPlanQuoteRequest {
  const CompanyPlanQuoteRequest({
    required this.fingerprint,
    required this.body,
  });

  final String fingerprint;
  final Map<String, dynamic> body;
}

typedef CompanyPlanQuoteTransport =
    Future<CompanyPlanQuoteResult> Function(CompanyPlanQuoteRequest request);

class CompanyPlanQuoteBreakdown {
  const CompanyPlanQuoteBreakdown({
    this.startFeeEx,
    this.perKmEx,
    this.distanceCostEx,
    this.perMinEx,
    this.timeCostEx,
    this.waitingEx,
    this.bagsEx,
    this.extraStopsEx,
    this.surchargeAmountEx,
    this.surchargeRate,
    this.returnFeeEx,
    this.fuelSurchargeEx,
    this.airportRuleId = '',
    this.kind = '',
    this.vatRate,
    this.vatAmount,
    this.totalEx,
    this.totalIncl,
    this.vatMode = 'excl',
  });

  final num? startFeeEx;
  final num? perKmEx;
  final num? distanceCostEx;
  final num? perMinEx;
  final num? timeCostEx;
  final num? waitingEx;
  final num? bagsEx;
  final num? extraStopsEx;
  final num? surchargeAmountEx;
  final num? surchargeRate;
  final num? returnFeeEx;
  final num? fuelSurchargeEx;
  final String airportRuleId;
  final String kind;
  final num? vatRate;
  final num? vatAmount;
  final num? totalEx;
  final num? totalIncl;
  final String vatMode;

  num extrasEx() => (waitingEx ?? 0) + (bagsEx ?? 0);

  bool get explainsAsymmetry =>
      (waitingEx ?? 0) > 0.01 ||
      (bagsEx ?? 0) > 0.01 ||
      (surchargeAmountEx ?? 0) > 0.01 ||
      (returnFeeEx ?? 0) > 0.01 ||
      airportRuleId.isNotEmpty ||
      kind.contains('airport') ||
      kind.contains('fixed');
}

bool companyPlanQuoteBreakdownHasLines(CompanyPlanQuoteBreakdown breakdown) {
  return breakdown.startFeeEx != null ||
      breakdown.distanceCostEx != null ||
      breakdown.timeCostEx != null ||
      breakdown.waitingEx != null ||
      breakdown.bagsEx != null ||
      breakdown.extraStopsEx != null ||
      breakdown.surchargeAmountEx != null ||
      breakdown.returnFeeEx != null ||
      breakdown.fuelSurchargeEx != null ||
      breakdown.totalEx != null ||
      breakdown.totalIncl != null ||
      breakdown.vatAmount != null;
}

CompanyPlanQuoteBreakdown? resolveCompanyBookingStoredBreakdown(
  Map<String, dynamic> raw,
) {
  Map<String, dynamic> asMap(Object? value) {
    if (value is Map) return Map<String, dynamic>.from(value);
    return const <String, dynamic>{};
  }

  final record = raw['record'] is Map ? asMap(raw['record']) : raw;
  final booking = asMap(record['booking']);
  final quote = asMap(record['quote'] ?? raw['quote']);
  final pricing = asMap(quote['pricing']);
  final pricingMain = asMap(quote['pricing_main']);
  for (final candidate in <Object?>[
    quote['breakdown'],
    quote['price_breakdown'],
    pricing['breakdown'],
    pricingMain['breakdown'],
    booking['breakdown'],
    record['breakdown'],
    raw['breakdown'],
  ]) {
    final parsed = parseCompanyPlanQuoteBreakdown(candidate);
    if (parsed != null && companyPlanQuoteBreakdownHasLines(parsed)) {
      return parsed;
    }
  }
  return null;
}

List<String> formatCompanyPlanQuoteBreakdownLines(
  CompanyPlanQuoteBreakdown breakdown, {
  required AppLanguage language,
  required String currency,
}) {
  String? line(LocalizedText label, num? value) {
    if (value == null || value == 0) return null;
    return '${label.of(language)}: ${formatCompanyPlanQuoteMoney(value, currency)}';
  }

  final total = breakdown.totalIncl ?? breakdown.totalEx;
  return <String?>[
    line(kCompanyAgendaStartFee, breakdown.startFeeEx),
    if (breakdown.distanceCostEx != null && breakdown.distanceCostEx != 0)
      language == AppLanguage.nl
          ? 'Afstand: ${formatCompanyPlanQuoteMoney(breakdown.distanceCostEx!, currency)}'
          : 'Distance: ${formatCompanyPlanQuoteMoney(breakdown.distanceCostEx!, currency)}',
    if (breakdown.timeCostEx != null && breakdown.timeCostEx != 0)
      language == AppLanguage.nl
          ? 'Tijd: ${formatCompanyPlanQuoteMoney(breakdown.timeCostEx!, currency)}'
          : 'Time: ${formatCompanyPlanQuoteMoney(breakdown.timeCostEx!, currency)}',
    line(kCompanyAgendaWaitPrice, breakdown.waitingEx),
    line(kCompanyAgendaBagsPrice, breakdown.bagsEx),
    if (breakdown.extraStopsEx != null && breakdown.extraStopsEx != 0)
      language == AppLanguage.nl
          ? 'Extra stops: ${formatCompanyPlanQuoteMoney(breakdown.extraStopsEx!, currency)}'
          : 'Extra stops: ${formatCompanyPlanQuoteMoney(breakdown.extraStopsEx!, currency)}',
    if (breakdown.surchargeAmountEx != null && breakdown.surchargeAmountEx != 0)
      language == AppLanguage.nl
          ? 'Toeslag: ${formatCompanyPlanQuoteMoney(breakdown.surchargeAmountEx!, currency)}'
          : 'Surcharge: ${formatCompanyPlanQuoteMoney(breakdown.surchargeAmountEx!, currency)}',
    if (breakdown.returnFeeEx != null && breakdown.returnFeeEx != 0)
      language == AppLanguage.nl
          ? 'Retour: ${formatCompanyPlanQuoteMoney(breakdown.returnFeeEx!, currency)}'
          : 'Return: ${formatCompanyPlanQuoteMoney(breakdown.returnFeeEx!, currency)}',
    if (breakdown.fuelSurchargeEx != null && breakdown.fuelSurchargeEx != 0)
      language == AppLanguage.nl
          ? 'Brandstof: ${formatCompanyPlanQuoteMoney(breakdown.fuelSurchargeEx!, currency)}'
          : 'Fuel: ${formatCompanyPlanQuoteMoney(breakdown.fuelSurchargeEx!, currency)}',
    if (breakdown.vatAmount != null && breakdown.vatAmount != 0)
      language == AppLanguage.nl
          ? 'Btw: ${formatCompanyPlanQuoteMoney(breakdown.vatAmount!, currency)}'
          : 'VAT: ${formatCompanyPlanQuoteMoney(breakdown.vatAmount!, currency)}',
    if (total != null)
      language == AppLanguage.nl
          ? 'Totaal: ${formatCompanyPlanQuoteMoney(total, currency)}'
          : 'Total: ${formatCompanyPlanQuoteMoney(total, currency)}',
  ].whereType<String>().toList(growable: false);
}

CompanyPlanQuoteBreakdown? parseCompanyPlanQuoteBreakdown(Object? raw) {
  if (raw is! Map) return null;
  final map = Map<String, dynamic>.from(raw);
  num? money(String key) => _quoteMoney(map[key]);
  return CompanyPlanQuoteBreakdown(
    startFeeEx: money('start_fee_ex'),
    perKmEx: money('per_km_ex'),
    distanceCostEx: money('distance_cost_ex') ?? money('per_km_total_ex'),
    perMinEx: money('per_min_ex'),
    timeCostEx: money('time_cost_ex') ?? money('per_min_total_ex'),
    waitingEx: money('waiting_ex'),
    bagsEx: money('bags_ex'),
    extraStopsEx: money('extra_stops_ex'),
    surchargeAmountEx: money('surcharge_amount_ex'),
    surchargeRate: money('surcharge_rate'),
    returnFeeEx: money('return_fee_ex'),
    fuelSurchargeEx: money('fuel_surcharge_ex'),
    airportRuleId: map['fixed_fare_rule_id']?.toString().trim() ?? '',
    kind: map['kind']?.toString().trim() ?? '',
    vatRate: money('vat_rate'),
    vatAmount: money('vat_amount'),
    totalEx: money('total_ex'),
    totalIncl: money('total_incl'),
    vatMode: map['vat_mode']?.toString().trim() ?? 'excl',
  );
}

num? _quoteMoney(Object? raw) => parseCompanyBookingMoney(raw);

int? _quoteMinutes(Object? raw) => parseCompanyBookingDurationMin(raw);

bool _quoteFlagIsTrue(Object? raw) {
  if (raw == true || raw == 1) return true;
  final text = raw?.toString().trim().toLowerCase() ?? '';
  return text == 'true' || text == '1' || text == 'yes';
}

bool _quoteFlagIsFalse(Object? raw) {
  if (raw == false || raw == 0) return true;
  final text = raw?.toString().trim().toLowerCase() ?? '';
  return text == 'false' || text == '0' || text == 'no';
}

num? _sumMoney(num? left, num? right) {
  if (left == null && right == null) return null;
  return (left ?? 0) + (right ?? 0);
}

CompanyPlanQuoteResult companyPlanMergeLegQuotes({
  required CompanyPlanQuoteResult outbound,
  required CompanyPlanQuoteResult inbound,
}) {
  final outboundPrice = outbound.priceAvailable ? outbound.priceInclVat : null;
  final inboundPrice = inbound.priceAvailable ? inbound.priceInclVat : null;
  final total = _sumMoney(outboundPrice, inboundPrice);
  return CompanyPlanQuoteResult(
    fingerprint: '${outbound.fingerprint}||${inbound.fingerprint}',
    distanceKm: outbound.distanceKm,
    durationMin: outbound.durationMin,
    priceInclVat: total ?? outbound.priceInclVat,
    priceExVat: outbound.priceExVat,
    priceVat: outbound.priceVat,
    currency: outbound.currency,
    pricingSource: outbound.pricingSource,
    priceAvailable: total != null,
    requestQuoteRequired: outbound.requestQuoteRequired,
    calculatorOff: outbound.calculatorOff,
    fixedPriceSnapshot: outbound.fixedPriceSnapshot,
    pickupLat: outbound.pickupLat,
    pickupLon: outbound.pickupLon,
    dropoffLat: outbound.dropoffLat,
    dropoffLon: outbound.dropoffLon,
    returnDistanceKm: inbound.distanceKm,
    returnDurationMin: inbound.durationMin,
    returnPriceInclVat: inboundPrice,
    returnPickupLat: inbound.pickupLat,
    returnPickupLon: inbound.pickupLon,
    returnDropoffLat: inbound.dropoffLat,
    returnDropoffLon: inbound.dropoffLon,
    outboundPriceInclVat: outboundPrice,
    totalPriceInclVat: total,
    message: outbound.message,
    breakdown: outbound.breakdown,
    returnBreakdown: inbound.breakdown ?? inbound.returnBreakdown,
  );
}

CompanyPlanQuoteResult parseCompanyPlanQuote(
  Map<String, dynamic> raw, {
  required String fingerprint,
}) {
  if (raw['ok'] != true) {
    throw CompanyAgendaException(
      raw['error']?.toString().trim().isNotEmpty == true
          ? raw['error'].toString()
          : 'route_failed',
    );
  }
  final returnRaw = raw['return'] is Map
      ? Map<String, dynamic>.from(raw['return'] as Map)
      : const <String, dynamic>{};
  final outboundPrice = _quoteMoney(
    raw['price_incl_vat_main'] ?? raw['price_incl_vat'],
  );
  final returnPrice = _quoteMoney(
    raw['return_price_incl_vat'] ??
        raw['price_incl_vat_return'] ??
        returnRaw['price_incl_vat'],
  );
  final totalPrice = _quoteMoney(
        raw['total_price_incl_vat'] ?? raw['price_incl_vat'],
      ) ??
      _sumMoney(outboundPrice, returnPrice);
  return CompanyPlanQuoteResult(
    fingerprint: fingerprint,
    distanceKm: _quoteMoney(raw['distance_km']),
    durationMin: _quoteMinutes(raw['duration_min']),
    priceInclVat: totalPrice ?? outboundPrice,
    priceExVat: _quoteMoney(raw['price_ex_vat']) ??
        _quoteMoney(raw['price_excl_vat']) ??
        parseCompanyPlanQuoteBreakdown(raw['breakdown'] ?? raw['pricing'])
            ?.totalEx,
    priceVat: _quoteMoney(raw['price_vat']) ??
        parseCompanyPlanQuoteBreakdown(raw['breakdown'] ?? raw['pricing'])
            ?.vatAmount,
    currency: (raw['currency']?.toString().trim().isNotEmpty == true)
        ? raw['currency'].toString().trim()
        : 'EUR',
    pricingSource: raw['pricing_source']?.toString().trim() ?? '',
    priceAvailable: _quoteFlagIsTrue(raw['price_available']) ||
        (!_quoteFlagIsFalse(raw['price_available']) &&
            (totalPrice ?? outboundPrice) != null &&
            (totalPrice ?? outboundPrice)! > 0 &&
            raw['request_quote_required'] != true &&
            raw['calculator_off'] != true),
    requestQuoteRequired: _quoteFlagIsTrue(raw['request_quote_required']),
    calculatorOff: _quoteFlagIsTrue(raw['calculator_off']),
    fixedPriceSnapshot: raw['fixed_price_snapshot'] is Map
        ? Map<String, dynamic>.from(raw['fixed_price_snapshot'] as Map)
        : null,
    pickupLat: _quoteMoney(raw['pickup_lat'])?.toDouble(),
    pickupLon: _quoteMoney(raw['pickup_lon'])?.toDouble(),
    dropoffLat: _quoteMoney(raw['dropoff_lat'])?.toDouble(),
    dropoffLon: _quoteMoney(raw['dropoff_lon'])?.toDouble(),
    returnDistanceKm: _quoteMoney(
      raw['return_distance_km'] ?? returnRaw['distance_km'],
    ),
    returnDurationMin: _quoteMinutes(
      raw['return_duration_min'] ?? returnRaw['duration_min'],
    ),
    returnPriceInclVat: returnPrice,
    returnPickupLat: _quoteMoney(raw['return_pickup_lat'])?.toDouble(),
    returnPickupLon: _quoteMoney(raw['return_pickup_lon'])?.toDouble(),
    returnDropoffLat: _quoteMoney(raw['return_dropoff_lat'])?.toDouble(),
    returnDropoffLon: _quoteMoney(raw['return_dropoff_lon'])?.toDouble(),
    outboundPriceInclVat: outboundPrice,
    totalPriceInclVat: totalPrice,
    message: raw['message']?.toString().trim() ?? '',
    breakdown: parseCompanyPlanQuoteBreakdown(
      raw['breakdown'] ?? raw['price_breakdown'],
    ),
    returnBreakdown: parseCompanyPlanQuoteBreakdown(
      raw['return_breakdown'] ?? returnRaw['breakdown'],
    ),
  );
}

String companyPlanQuotePricingSourceLabel(
  String source,
  AppLanguage language,
) {
  switch (source.trim().toLowerCase()) {
    case 'company_fixed_price':
    case 'fixed_price':
    case 'fixed':
      return language == AppLanguage.fr
          ? 'prix fixe'
          : language == AppLanguage.es
          ? 'precio fijo'
          : language == AppLanguage.nl
          ? 'vaste routeprijs'
          : 'fixed route price';
    case 'airport_fixed_fare':
    case 'airport_fixed_price':
      return language == AppLanguage.fr
          ? 'tarif aéroport'
          : language == AppLanguage.es
          ? 'tarifa de aeropuerto'
          : language == AppLanguage.nl
          ? 'luchthavenprijs'
          : 'airport price';
    case 'hourly':
    case 'hourly_package':
    case 'package':
    case 'limousine_hourly':
      return language == AppLanguage.fr
          ? 'location à l’heure'
          : language == AppLanguage.es
          ? 'alquiler por horas'
          : language == AppLanguage.nl
          ? 'uurhuur of pakket'
          : 'hourly or package';
    case 'manual':
      return language == AppLanguage.fr
          ? 'prix manuel'
          : language == AppLanguage.es
          ? 'precio manual'
          : language == AppLanguage.nl
          ? 'handmatige prijs'
          : 'manual price';
    case 'calculator_off':
    case 'request_quote':
      return language == AppLanguage.fr
          ? 'sans calcul automatique'
          : language == AppLanguage.es
          ? 'sin cálculo automático'
          : language == AppLanguage.nl
          ? 'geen automatische prijs'
          : 'no automatic price';
    default:
      return language == AppLanguage.fr
          ? 'tarifs de l’entreprise'
          : language == AppLanguage.es
          ? 'tarifas de la empresa'
          : language == AppLanguage.nl
          ? 'bedrijfstarieven'
          : 'company tariffs';
  }
}

String formatCompanyPlanQuoteRoute(
  CompanyPlanQuoteResult result,
  AppLanguage language,
) {
  final minutes = result.durationMin;
  final km = result.distanceKm;
  if (minutes == null || km == null) return '';
  final kmText = km.toStringAsFixed(1).replaceAll('.', ',');
  return '$minutes min · $kmText km';
}

String formatCompanyPlanQuoteMoney(num amount, String currency) {
  final formatted = formatCompanyBookingMoney(
    amount,
    currency,
  ).replaceFirst(' EUR', '').trim();
  final prefix = currency.toUpperCase() == 'EUR' ? '€' : currency;
  return '$prefix$formatted';
}

String formatCompanyPlanQuotePrice(
  CompanyPlanQuoteResult result,
  AppLanguage language, {
  bool includeSource = true,
}) {
  final amount = result.displayTotalPrice;
  if (!result.priceAvailable || amount == null) return '';
  final price = formatCompanyPlanQuoteMoney(amount, result.currency);
  if (!includeSource) return price;
  final source = companyPlanQuotePricingSourceLabel(
    result.pricingSource,
    language,
  );
  final verb = language == AppLanguage.fr
      ? 'calculé avec'
      : language == AppLanguage.es
      ? 'calculado con'
      : language == AppLanguage.nl
      ? 'berekend met'
      : 'calculated with';
  return '$price · $verb $source';
}

String formatCompanyPlanQuoteLegLine({
  required String label,
  required CompanyPlanQuoteResult result,
  required bool inbound,
  required AppLanguage language,
  DateTime? pickupLocal,
}) {
  final minutes = inbound ? result.returnDurationMin : result.durationMin;
  final km = inbound ? result.returnDistanceKm : result.distanceKm;
  final price = companyPlanQuoteDisplayedLegPrice(result, inbound: inbound);
  if (minutes == null || km == null) return '';
  final parts = <String>[
    label,
    if (pickupLocal != null)
      '${pickupLocal.hour.toString().padLeft(2, '0')}:${pickupLocal.minute.toString().padLeft(2, '0')}',
    '$minutes min',
    '${km.toStringAsFixed(1).replaceAll('.', ',')} km',
    if (price != null) formatCompanyPlanQuoteMoney(price, result.currency),
  ];
  return parts.join(' · ');
}

num? companyPlanQuoteLineIncl(
  CompanyPlanQuoteBreakdown? breakdown,
  num? amountEx,
) {
  if (breakdown == null || amountEx == null || amountEx <= 0) return null;
  if (breakdown.vatMode == 'incl') return amountEx;
  return amountEx * (1 + (breakdown.vatRate ?? 0));
}

num? companyPlanQuoteExtrasIncl(CompanyPlanQuoteBreakdown? breakdown) {
  if (breakdown == null) return null;
  final extras = breakdown.extrasEx();
  if (extras <= 0) return 0;
  return companyPlanQuoteLineIncl(breakdown, extras) ?? 0;
}

num? companyPlanQuoteDisplayedLegPrice(
  CompanyPlanQuoteResult result, {
  required bool inbound,
}) {
  final raw = inbound
      ? result.returnPriceInclVat
      : (result.outboundPriceInclVat ?? result.priceInclVat);
  if (raw == null) return null;
  final extras = companyPlanQuoteExtrasIncl(
    inbound ? result.returnBreakdown : result.breakdown,
  );
  if (extras == null || extras <= 0) return raw;
  return raw - extras;
}

class CompanyPlanQuoteSanity {
  const CompanyPlanQuoteSanity({
    required this.ok,
    this.reason = '',
  });

  final bool ok;
  final String reason;
}

CompanyPlanQuoteSanity companyPlanQuoteSanityCheck(
  CompanyPlanQuoteResult result,
) {
  bool invalid(num? value) {
    if (value == null) return false;
    return value.isNaN || value.isInfinite || value < 0;
  }

  if (invalid(result.priceInclVat) ||
      invalid(result.returnPriceInclVat) ||
      invalid(result.totalPriceInclVat) ||
      invalid(result.distanceKm) ||
      invalid(result.returnDistanceKm)) {
    return const CompanyPlanQuoteSanity(
      ok: false,
      reason: 'invalid_money',
    );
  }
  if (result.distanceKm != null &&
      result.distanceKm! > 800 &&
      (result.durationMin ?? 0) < 180) {
    return const CompanyPlanQuoteSanity(
      ok: false,
      reason: 'distance_unit',
    );
  }
  final out = companyPlanQuoteDisplayedLegPrice(result, inbound: false);
  final back = companyPlanQuoteDisplayedLegPrice(result, inbound: true);
  final d1 = result.distanceKm;
  final d2 = result.returnDistanceKm;
  if (out != null &&
      back != null &&
      d1 != null &&
      d2 != null &&
      d1 > 0 &&
      d2 > 0) {
    final distRatio = d1 > d2 ? d1 / d2 : d2 / d1;
    final priceRatio = out > back ? out / back : back / out;
    final explained = (result.breakdown?.explainsAsymmetry ?? false) ||
        (result.returnBreakdown?.explainsAsymmetry ?? false);
    if (distRatio < 1.15 && priceRatio >= 1.8 && !explained) {
      return const CompanyPlanQuoteSanity(
        ok: false,
        reason: 'unexplained_price_gap',
      );
    }
  }
  return const CompanyPlanQuoteSanity(ok: true);
}

String formatCompanyPlanQuoteEta({
  required CompanyPlanQuoteResult result,
  required DateTime? pickupLocal,
}) {
  final minutes = result.durationMin;
  if (minutes == null || minutes <= 0 || pickupLocal == null) return '';
  final eta = pickupLocal.toLocal().add(Duration(minutes: minutes));
  final hour = eta.hour.toString().padLeft(2, '0');
  final minute = eta.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}

bool companyPlanAddressIsQuoteReady(LimousineAddressValue value) {
  if (!value.isRouteReady) return false;
  if (!value.hasCoordinates) return false;
  final text = value.routeText;
  return text.isNotEmpty;
}

enum CompanyPlanRouteStatus {
  missingEndpoints,
  confirmPickup,
  confirmDropoff,
  needsRestore,
  calculating,
  ready,
  failed,
}

bool companyPlanQuoteHasUsableCoords(CompanyPlanQuoteResult? quote) {
  if (quote == null) return false;
  return quote.pickupLat != null &&
      quote.pickupLon != null &&
      quote.dropoffLat != null &&
      quote.dropoffLon != null &&
      quote.pickupLat!.isFinite &&
      quote.pickupLon!.isFinite &&
      quote.dropoffLat!.isFinite &&
      quote.dropoffLon!.isFinite;
}

CompanyPlanRouteStatus companyPlanRouteStatus({
  required LimousineAddressValue from,
  required LimousineAddressValue to,
  required bool loading,
  CompanyPlanQuoteResult? quote,
  String? error,
  bool hasPolyline = false,
}) {
  final fromReady = companyPlanAddressIsQuoteReady(from);
  final toReady = companyPlanAddressIsQuoteReady(to);
  final hasText =
      from.displayText.trim().isNotEmpty && to.displayText.trim().isNotEmpty;
  final addressCoords = from.lat != null &&
      from.lon != null &&
      to.lat != null &&
      to.lon != null &&
      from.lat!.isFinite &&
      from.lon!.isFinite &&
      to.lat!.isFinite &&
      to.lon!.isFinite;
  final hasCoords = hasPolyline ||
      addressCoords ||
      (fromReady && toReady && companyPlanQuoteHasUsableCoords(quote));
  if (!hasCoords) {
    if (from.displayText.trim().isNotEmpty && !fromReady) {
      return CompanyPlanRouteStatus.confirmPickup;
    }
    if (to.displayText.trim().isNotEmpty && !toReady) {
      return CompanyPlanRouteStatus.confirmDropoff;
    }
    if (hasText) return CompanyPlanRouteStatus.needsRestore;
    return CompanyPlanRouteStatus.missingEndpoints;
  }
  if (loading) return CompanyPlanRouteStatus.calculating;
  if (error != null && error.trim().isNotEmpty) {
    return CompanyPlanRouteStatus.failed;
  }
  if (quote != null && quote.hasRoute) return CompanyPlanRouteStatus.ready;
  if (fromReady && toReady) return CompanyPlanRouteStatus.calculating;
  return CompanyPlanRouteStatus.ready;
}

String companyPlanQuoteErrorText(String? raw, AppLanguage language) {
  final code = raw?.trim() ?? '';
  if (code.isEmpty) return '';
  final lower = code.toLowerCase();
  if (code == 'route_required') {
    return kCompanyAgendaRouteRetry.of(language);
  }
  if (code == 'pickup_iso_required' || code == 'invalid_pickup_iso') {
    return kCompanyAgendaPickupRequired.of(language);
  }
  if (code == 'quote_unavailable' ||
      code == 'price_unavailable' ||
      code == 'calculator_off') {
    return kCompanyAgendaQuoteUnavailable.of(language);
  }
  if (lower.contains('price') ||
      lower.contains('tariff') ||
      lower.contains('calculator') ||
      lower.contains('prijs')) {
    return kCompanyAgendaPriceInvalid.of(language);
  }
  if (code.contains(' ') || code.contains('.') || code.length > 32) {
    return code;
  }
  return kCompanyAgendaRouteRetry.of(language);
}

bool companyPlanQuoteErrorIsMissingRoute(
  String? raw,
  LimousineAddressValue from,
  LimousineAddressValue to,
) {
  if (raw?.trim() != 'route_required') return false;
  return !companyPlanAddressIsQuoteReady(from) ||
      !companyPlanAddressIsQuoteReady(to);
}

String companyPlanQuoteFingerprint({
  required LimousineAddressValue from,
  required LimousineAddressValue to,
  required DateTime? pickupLocal,
  required CompanyRideOptions options,
  required int passengers,
  DateTime? returnPickupLocal,
  LimousineAddressValue? returnFrom,
  LimousineAddressValue? returnTo,
  List<LimousineAddressValue> stops = const <LimousineAddressValue>[],
  List<LimousineAddressValue> returnStops = const <LimousineAddressValue>[],
  bool returnEnabled = false,
  bool whenNow = false,
  String vehicleId = '',
}) {
  String coord(LimousineAddressValue value) {
    final lat = value.lat;
    final lon = value.lon;
    if (lat != null && lon != null && lat.isFinite && lon.isFinite) {
      return '${lat.toStringAsFixed(5)},${lon.toStringAsFixed(5)}';
    }
    return '${value.placeId ?? ''}|${value.routeText}';
  }

  String minute(DateTime? value) {
    if (value == null) return '';
    final local = value.toLocal();
    return '${local.year}-${local.month}-${local.day}T${local.hour}:${local.minute}';
  }

  return <String>[
    coord(from),
    coord(to),
    whenNow ? 'now' : minute(pickupLocal),
    options.service,
    options.tier,
    options.vehicleType,
    '${options.bags}',
    '${options.waitMin}',
    '$passengers',
    options.airportIata,
    options.airportDirection,
    returnEnabled ? 'rt' : 'one',
    if (returnEnabled) minute(returnPickupLocal),
    if (returnEnabled) coord(returnFrom ?? const LimousineAddressValue()),
    if (returnEnabled) coord(returnTo ?? const LimousineAddressValue()),
    for (final stop in stops) coord(stop),
    for (final stop in returnStops) 'r:${coord(stop)}',
    vehicleId.trim(),
  ].join('|');
}

CompanyPlanQuoteRequest? companyPlanQuoteRequestFromAddresses({
  required LimousineAddressValue from,
  required LimousineAddressValue to,
  required DateTime? pickupLocal,
  required CompanyRideOptions options,
  required int passengers,
  DateTime? returnPickupLocal,
  LimousineAddressValue? returnFrom,
  LimousineAddressValue? returnTo,
  List<LimousineAddressValue> stops = const <LimousineAddressValue>[],
  List<LimousineAddressValue> returnStops = const <LimousineAddressValue>[],
  bool returnEnabled = false,
  String currency = 'EUR',
  bool whenNow = false,
  String vehicleId = '',
}) {
  if (!companyPlanAddressIsQuoteReady(from) ||
      !companyPlanAddressIsQuoteReady(to) ||
      (!whenNow && pickupLocal == null)) {
    return null;
  }
  final fingerprint = companyPlanQuoteFingerprint(
    from: from,
    to: to,
    pickupLocal: whenNow ? null : pickupLocal,
    options: options,
    passengers: passengers,
    returnPickupLocal: returnPickupLocal,
    returnFrom: returnFrom,
    returnTo: returnTo,
    stops: stops,
    returnStops: returnStops,
    returnEnabled: returnEnabled,
    whenNow: whenNow,
    vehicleId: vehicleId,
  );
  final stopTexts = [
    for (final stop in stops)
      if (stop.routeText.isNotEmpty) stop.routeText,
  ];
  final returnStopTexts = [
    for (final stop in returnStops)
      if (stop.routeText.isNotEmpty) stop.routeText,
  ];
  final body = <String, dynamic>{
    'from': from.routeText,
    'to': to.routeText,
    'passengers': passengers,
    'currency': currency,
    'ride_options': options.toJson(),
    if (options.service.isNotEmpty) 'service': options.service,
    if (options.tier.isNotEmpty) 'tier': options.tier,
    if (options.bags > 0) 'bags': options.bags,
    if (options.waitMin > 0) 'wait_min': options.waitMin,
    if (options.airportIata.isNotEmpty) 'airport_iata': options.airportIata,
    if (options.airportDirection.isNotEmpty)
      'airport_direction': options.airportDirection,
    if (from.lat != null && from.lon != null) ...<String, dynamic>{
      'pickup_lat': from.lat,
      'pickup_lon': from.lon,
      'from_lat': from.lat,
      'from_lng': from.lon,
    },
    if (to.lat != null && to.lon != null) ...<String, dynamic>{
      'dropoff_lat': to.lat,
      'dropoff_lon': to.lon,
      'to_lat': to.lat,
      'to_lng': to.lon,
    },
    if (stopTexts.isNotEmpty) 'stops': stopTexts,
    'return_enabled': returnEnabled,
    if (returnEnabled && returnPickupLocal != null)
      'return_pickup_iso': returnPickupLocal.toUtc().toIso8601String(),
    if (returnEnabled && returnFrom != null && returnFrom.routeText.isNotEmpty)
      'return_from': returnFrom.routeText,
    if (returnEnabled && returnTo != null && returnTo.routeText.isNotEmpty)
      'return_to': returnTo.routeText,
    if (returnEnabled && returnFrom != null && returnFrom.lat != null && returnFrom.lon != null)
      ...<String, dynamic>{
        'return_from_lat': returnFrom.lat,
        'return_from_lng': returnFrom.lon,
      },
    if (returnEnabled && returnTo != null && returnTo.lat != null && returnTo.lon != null)
      ...<String, dynamic>{
        'return_to_lat': returnTo.lat,
        'return_to_lng': returnTo.lon,
      },
    if (returnStopTexts.isNotEmpty) 'return_stops': returnStopTexts,
    if (vehicleId.trim().isNotEmpty) ...<String, dynamic>{
      'vehicle_id': vehicleId.trim(),
      'preferred_vehicle_id': vehicleId.trim(),
    },
  };
  if (whenNow) {
    body.addAll(companyPlanWhenWireFields(whenNow: true));
    companyPlanStripClientScheduleFields(body);
  } else if (pickupLocal != null) {
    body['pickup_iso'] = pickupLocal.toUtc().toIso8601String();
  }
  return CompanyPlanQuoteRequest(fingerprint: fingerprint, body: body);
}

class CompanyPlanQuoteCoordinator {
  CompanyPlanQuoteCoordinator({required this.transport});

  final CompanyPlanQuoteTransport transport;

  String? _key;
  Future<CompanyPlanQuoteResult>? _inFlight;
  CompanyPlanQuoteResult? cached;

  Future<CompanyPlanQuoteResult> quote(CompanyPlanQuoteRequest request) {
    if (_key == request.fingerprint && cached != null) {
      return Future<CompanyPlanQuoteResult>.value(cached);
    }
    if (_key == request.fingerprint && _inFlight != null) {
      return _inFlight!;
    }
    _key = request.fingerprint;
    cached = null;
    final pending = transport(request);
    _inFlight = pending;
    return pending.then((result) {
      if (_key == request.fingerprint) {
        cached = result;
        if (identical(_inFlight, pending)) _inFlight = null;
      }
      return result;
    }).catchError((Object error, StackTrace stack) {
      if (identical(_inFlight, pending)) _inFlight = null;
      throw error;
    });
  }

  void invalidate() {
    _key = null;
    cached = null;
    _inFlight = null;
  }
}

Future<CompanyPlanQuoteResult> fetchCompanyAgendaQuote(
  CompanyPlanQuoteRequest request, {
  Future<Map<String, String>> Function()? headers,
  Map<String, String>? Function()? scopeResolver,
}) async {
  final scope = (scopeResolver ?? resolveCompanyAgendaScopeQuery)();
  if (scope == null) {
    throw const CompanyAgendaException('missing_company_scope');
  }
  try {
    final resolved = await (headers ?? resolveCompanyAgendaHeaders)();
    final res = await http
        .post(
          Uri.parse('$kBookingBaseUrl$kCompanyAgendaQuotePath').replace(
            queryParameters: scope,
          ),
          headers: <String, String>{
            ...resolved,
            'Content-Type': 'application/json',
          },
          body: jsonEncode(<String, dynamic>{...scope, ...request.body}),
        )
        .timeout(const Duration(seconds: 20));
    final decoded = tryDecodeCompanyAgendaJson(res.bodyBytes);
    if (decoded == null) {
      throw CompanyAgendaException('http_${res.statusCode}');
    }
    if (decoded['ok'] != true) {
      throw CompanyAgendaException(
        decoded['message']?.toString().trim().isNotEmpty == true
            ? decoded['message'].toString()
            : (decoded['error']?.toString().trim().isNotEmpty == true
                  ? decoded['error'].toString()
                  : 'route_failed'),
      );
    }
    return parseCompanyPlanQuote(decoded, fingerprint: request.fingerprint);
  } catch (error) {
    throwCompanyAgendaHttpError(error);
  }
}
