// COMPANY-AGENDA-P0 — plan-form quote. Server calcPrice only. No local fares.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:fluxidi_tracking/app_config.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/company/company_agenda_http.dart';
import 'package:fluxidi_tracking/company/company_agenda_models.dart';
import 'package:fluxidi_tracking/company/company_agenda_scope_io.dart'
    if (dart.library.html) 'package:fluxidi_tracking/company/company_agenda_scope_web.dart';
import 'package:fluxidi_tracking/company/company_booking_metrics.dart';
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
    this.message = '',
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
  final String message;

  bool get hasRoute =>
      distanceKm != null &&
      distanceKm! > 0 &&
      durationMin != null &&
      durationMin! > 0;
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

num? _quoteMoney(Object? raw) => parseCompanyBookingMoney(raw);

int? _quoteMinutes(Object? raw) => parseCompanyBookingDurationMin(raw);

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
  return CompanyPlanQuoteResult(
    fingerprint: fingerprint,
    distanceKm: _quoteMoney(raw['distance_km']),
    durationMin: _quoteMinutes(raw['duration_min']),
    priceInclVat: _quoteMoney(raw['price_incl_vat']),
    priceExVat: _quoteMoney(raw['price_ex_vat']),
    priceVat: _quoteMoney(raw['price_vat']),
    currency: (raw['currency']?.toString().trim().isNotEmpty == true)
        ? raw['currency'].toString().trim()
        : 'EUR',
    pricingSource: raw['pricing_source']?.toString().trim() ?? '',
    priceAvailable: raw['price_available'] == true,
    requestQuoteRequired: raw['request_quote_required'] == true,
    calculatorOff: raw['calculator_off'] == true,
    fixedPriceSnapshot: raw['fixed_price_snapshot'] is Map
        ? Map<String, dynamic>.from(raw['fixed_price_snapshot'] as Map)
        : null,
    pickupLat: _quoteMoney(raw['pickup_lat'])?.toDouble(),
    pickupLon: _quoteMoney(raw['pickup_lon'])?.toDouble(),
    dropoffLat: _quoteMoney(raw['dropoff_lat'])?.toDouble(),
    dropoffLon: _quoteMoney(raw['dropoff_lon'])?.toDouble(),
    message: raw['message']?.toString().trim() ?? '',
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

String formatCompanyPlanQuotePrice(
  CompanyPlanQuoteResult result,
  AppLanguage language,
) {
  if (!result.priceAvailable || result.priceInclVat == null) return '';
  final amount = formatCompanyBookingMoney(
    result.priceInclVat!,
    result.currency,
  ).replaceFirst(' EUR', '').trim();
  final source = companyPlanQuotePricingSourceLabel(
    result.pricingSource,
    language,
  );
  final prefix = result.currency.toUpperCase() == 'EUR' ? '€' : result.currency;
  final verb = language == AppLanguage.fr
      ? 'calculé avec'
      : language == AppLanguage.es
      ? 'calculado con'
      : language == AppLanguage.nl
      ? 'berekend met'
      : 'calculated with';
  return '$prefix$amount · $verb $source';
}

bool companyPlanAddressIsQuoteReady(LimousineAddressValue value) {
  if (!value.isRouteReady) return false;
  final text = value.routeText;
  return text.isNotEmpty;
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
  bool returnEnabled = false,
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
    minute(pickupLocal),
    options.service,
    options.tier,
    '${options.bags}',
    '${options.waitMin}',
    '$passengers',
    options.airportIata,
    options.airportDirection,
    returnEnabled ? 'rt' : 'one',
    if (returnEnabled) minute(returnPickupLocal),
    if (returnEnabled) coord(returnFrom ?? const LimousineAddressValue()),
    if (returnEnabled) coord(returnTo ?? const LimousineAddressValue()),
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
  bool returnEnabled = false,
  String currency = 'EUR',
}) {
  if (!companyPlanAddressIsQuoteReady(from) ||
      !companyPlanAddressIsQuoteReady(to) ||
      pickupLocal == null) {
    return null;
  }
  final fingerprint = companyPlanQuoteFingerprint(
    from: from,
    to: to,
    pickupLocal: pickupLocal,
    options: options,
    passengers: passengers,
    returnPickupLocal: returnPickupLocal,
    returnFrom: returnFrom,
    returnTo: returnTo,
    returnEnabled: returnEnabled,
  );
  final body = <String, dynamic>{
    'from': from.routeText,
    'to': to.routeText,
    'pickup_iso': pickupLocal.toUtc().toIso8601String(),
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
    'return_enabled': returnEnabled,
    if (returnEnabled && returnPickupLocal != null)
      'return_pickup_iso': returnPickupLocal.toUtc().toIso8601String(),
    if (returnEnabled && returnFrom != null && returnFrom.routeText.isNotEmpty)
      'return_from': returnFrom.routeText,
    if (returnEnabled && returnTo != null && returnTo.routeText.isNotEmpty)
      'return_to': returnTo.routeText,
  };
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
