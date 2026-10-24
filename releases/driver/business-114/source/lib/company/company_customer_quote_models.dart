// COMPANY-CUSTOMER-OPS-P0 — company-issued customer quotes.

import 'package:fluxidi_tracking/company/company_customer_models.dart';
import 'package:fluxidi_tracking/company/company_ride_options.dart';
import 'package:fluxidi_tracking/company/company_roundtrip.dart';

const String kCompanyCustomerQuotesPathSuffix = '/quotes';
const String kCompanyCustomerQuotesPath = '/company/customer-quotes';

class CompanyCustomerQuote {
  const CompanyCustomerQuote({
    required this.quoteId,
    required this.customerId,
    required this.state,
    required this.revision,
    required this.issuerName,
    required this.pickup,
    required this.dropoff,
    required this.startAt,
    required this.passengers,
    required this.description,
    required this.passengerName,
    required this.passengerEmail,
    required this.passengerPhone,
    required this.enteredAmountCents,
    required this.currency,
    required this.vatTreatment,
    this.vatRate,
    required this.validUntil,
    required this.createdAt,
    required this.updatedAt,
    this.pickupLat,
    this.pickupLon,
    this.pickupPlaceId = '',
    this.dropoffLat,
    this.dropoffLon,
    this.dropoffPlaceId = '',
    this.bookingId = '',
    this.bookingListReady = false,
    this.publicToken = '',
    this.publicUrl = '',
    this.delivery = '',
    this.deliveryProven = false,
    this.testSend = false,
    this.rideOptions = const CompanyRideOptions(),
    this.roundtripChoice = CompanyRoundtripChoice.single,
    this.returnPickupIso = '',
    this.returnFrom = '',
    this.returnTo = '',
    this.returnDurationMin,
    this.occupancyWaitMin,
    this.occupancyUnknown = false,
    this.returnPickupLat,
    this.returnPickupLon,
    this.returnPickupPlaceId = '',
    this.returnDropoffLat,
    this.returnDropoffLon,
    this.returnDropoffPlaceId = '',
    this.priceCovers = '',
    this.fixedPriceSnapshot,
  });

  final String quoteId;
  final String customerId;
  final String state;
  final int revision;
  final String issuerName;
  final String pickup;
  final String dropoff;
  final String startAt;
  final int passengers;
  final String description;
  final String passengerName;
  final String passengerEmail;
  final String passengerPhone;
  final int? enteredAmountCents;
  final String currency;
  final String vatTreatment;
  final double? vatRate;
  final String validUntil;
  final String createdAt;
  final String updatedAt;
  final double? pickupLat;
  final double? pickupLon;
  final String pickupPlaceId;
  final double? dropoffLat;
  final double? dropoffLon;
  final String dropoffPlaceId;
  final String bookingId;
  final bool bookingListReady;
  final String publicToken;
  final String publicUrl;
  final String delivery;
  final bool deliveryProven;
  final bool testSend;
  final CompanyRideOptions rideOptions;
  final CompanyRoundtripChoice roundtripChoice;
  final String returnPickupIso;
  final String returnFrom;
  final String returnTo;
  final int? returnDurationMin;
  final int? occupancyWaitMin;
  final bool occupancyUnknown;
  final double? returnPickupLat;
  final double? returnPickupLon;
  final String returnPickupPlaceId;
  final double? returnDropoffLat;
  final double? returnDropoffLon;
  final String returnDropoffPlaceId;
  final String priceCovers;
  final Map<String, dynamic>? fixedPriceSnapshot;

  bool get isDraft => state == 'draft';
  bool get isAccepted => state == 'accepted';
  bool get isTestSend =>
      testSend || delivery == kCompanyCustomerQuoteDeliveryTestAdapter;
  bool get isAdapterAccepted =>
      delivery == kCompanyCustomerQuoteDeliveryAdapterAccepted && !isTestSend;
}

const String kCompanyCustomerQuoteDeliveryTestAdapter = 'test_adapter';
const String kCompanyCustomerQuoteDeliveryAdapterAccepted = 'adapter_accepted';

class CompanyCustomerQuoteWrite {
  const CompanyCustomerQuoteWrite({
    required this.pickup,
    required this.dropoff,
    required this.startAt,
    required this.passengers,
    required this.description,
    required this.passengerName,
    required this.passengerEmail,
    required this.passengerPhone,
    required this.enteredAmountCents,
    this.currency = 'EUR',
    this.vatTreatment = '',
    this.vatRate,
    this.validUntil = '',
    this.issuerName = '',
    this.pickupLat,
    this.pickupLon,
    this.pickupPlaceId = '',
    this.dropoffLat,
    this.dropoffLon,
    this.dropoffPlaceId = '',
    this.rideOptions = const CompanyRideOptions(),
    this.roundtripChoice = CompanyRoundtripChoice.single,
    this.returnPickupIso = '',
    this.returnFrom = '',
    this.returnTo = '',
    this.returnDurationMin,
    this.returnPickupLat,
    this.returnPickupLon,
    this.returnPickupPlaceId = '',
    this.returnDropoffLat,
    this.returnDropoffLon,
    this.returnDropoffPlaceId = '',
    this.fixedPriceSnapshot,
  });

  final String pickup;
  final String dropoff;
  final String startAt;
  final int passengers;
  final String description;
  final String passengerName;
  final String passengerEmail;
  final String passengerPhone;
  final int? enteredAmountCents;
  final String currency;
  final String vatTreatment;
  final double? vatRate;
  final String validUntil;
  final String issuerName;
  final double? pickupLat;
  final double? pickupLon;
  final String pickupPlaceId;
  final double? dropoffLat;
  final double? dropoffLon;
  final String dropoffPlaceId;
  final CompanyRideOptions rideOptions;
  final CompanyRoundtripChoice roundtripChoice;
  final String returnPickupIso;
  final String returnFrom;
  final String returnTo;
  final int? returnDurationMin;
  final double? returnPickupLat;
  final double? returnPickupLon;
  final String returnPickupPlaceId;
  final double? returnDropoffLat;
  final double? returnDropoffLon;
  final String returnDropoffPlaceId;
  final Map<String, dynamic>? fixedPriceSnapshot;

  Map<String, dynamic> toJson({int? revision}) {
    return <String, dynamic>{
      'pickup': pickup.trim(),
      'dropoff': dropoff.trim(),
      'start_at': startAt.trim(),
      'passengers': passengers,
      'description': description.trim(),
      'passenger_name': passengerName.trim(),
      if (passengerEmail.trim().isNotEmpty) 'passenger_email': passengerEmail.trim(),
      if (passengerPhone.trim().isNotEmpty) 'passenger_phone': passengerPhone.trim(),
      if (enteredAmountCents != null) 'entered_amount_cents': enteredAmountCents,
      'currency': currency.trim().isEmpty ? 'EUR' : currency.trim().toUpperCase(),
      if (vatTreatment.trim().isNotEmpty) 'vat_treatment': vatTreatment.trim(),
      if (vatRate != null && vatRate!.isFinite) 'vat_rate': vatRate,
      if (validUntil.trim().isNotEmpty) 'valid_until': validUntil.trim(),
      if (issuerName.trim().isNotEmpty) 'issuer_name': issuerName.trim(),
      if (pickupLat != null && pickupLat!.isFinite) 'pickup_lat': pickupLat,
      if (pickupLon != null && pickupLon!.isFinite) 'pickup_lon': pickupLon,
      if (pickupPlaceId.trim().isNotEmpty) 'pickup_place_id': pickupPlaceId.trim(),
      if (dropoffLat != null && dropoffLat!.isFinite) 'dropoff_lat': dropoffLat,
      if (dropoffLon != null && dropoffLon!.isFinite) 'dropoff_lon': dropoffLon,
      if (dropoffPlaceId.trim().isNotEmpty) 'dropoff_place_id': dropoffPlaceId.trim(),
      'ride_options': rideOptions.toJson(),
      'return_enabled': roundtripChoice != CompanyRoundtripChoice.single,
      'roundtrip_dispatch_mode': companyRoundtripChoiceWire(roundtripChoice),
      if (returnPickupIso.trim().isNotEmpty) 'return_pickup_iso': returnPickupIso.trim(),
      if (returnFrom.trim().isNotEmpty) 'return_from': returnFrom.trim(),
      if (returnTo.trim().isNotEmpty) 'return_to': returnTo.trim(),
      if (returnDurationMin != null && returnDurationMin! > 0)
        'return_duration_min': returnDurationMin,
      if (returnPickupLat != null && returnPickupLat!.isFinite)
        'return_pickup_lat': returnPickupLat,
      if (returnPickupLon != null && returnPickupLon!.isFinite)
        'return_pickup_lon': returnPickupLon,
      if (returnPickupPlaceId.trim().isNotEmpty)
        'return_pickup_place_id': returnPickupPlaceId.trim(),
      if (returnDropoffLat != null && returnDropoffLat!.isFinite)
        'return_dropoff_lat': returnDropoffLat,
      if (returnDropoffLon != null && returnDropoffLon!.isFinite)
        'return_dropoff_lon': returnDropoffLon,
      if (returnDropoffPlaceId.trim().isNotEmpty)
        'return_dropoff_place_id': returnDropoffPlaceId.trim(),
      if (fixedPriceSnapshot != null &&
          (fixedPriceSnapshot!['fixed_fare_rule_id']?.toString().isNotEmpty ??
              false))
        'fixed_price_snapshot': fixedPriceSnapshot,
      if (revision != null) 'revision': revision,
    };
  }
}

double? _quoteCoord(Object? raw) {
  if (raw is num && raw.isFinite) return raw.toDouble();
  if (raw is String) {
    final parsed = double.tryParse(raw.trim());
    if (parsed != null && parsed.isFinite) return parsed;
  }
  return null;
}

int? parseEuroToCents(String raw) {
  final text = raw.trim().replaceAll(',', '.');
  if (text.isEmpty) return null;
  final value = double.tryParse(text);
  if (value == null || value < 0 || value > 999999) return null;
  return (value * 100).round();
}

bool hasExplicitQuotePrice(String raw) {
  final cents = parseEuroToCents(raw);
  return cents != null;
}

String formatQuoteEuros(int? cents, {String currency = 'EUR'}) {
  if (cents == null) return '$currency —';
  return '$currency ${(cents / 100).toStringAsFixed(2)}';
}

CompanyCustomerQuote parseCompanyCustomerQuote(Map<dynamic, dynamic> raw) {
  final quoteRaw = raw['quote'] is Map ? raw['quote'] as Map : raw;
  final amount = quoteRaw['entered_amount_cents'];
  return CompanyCustomerQuote(
    quoteId: quoteRaw['quote_id']?.toString().trim() ?? '',
    customerId: quoteRaw['customer_id']?.toString().trim() ?? '',
    state: quoteRaw['state']?.toString().trim() ?? '',
    revision: (quoteRaw['revision'] as num?)?.toInt() ?? 1,
    issuerName: quoteRaw['issuer_name']?.toString().trim() ?? '',
    pickup: quoteRaw['pickup']?.toString().trim() ?? '',
    dropoff: quoteRaw['dropoff']?.toString().trim() ?? '',
    startAt: quoteRaw['start_at']?.toString().trim() ?? '',
    passengers: (quoteRaw['passengers'] as num?)?.toInt() ?? 1,
    description: quoteRaw['description']?.toString().trim() ?? '',
    passengerName: quoteRaw['passenger_name']?.toString().trim() ?? '',
    passengerEmail: quoteRaw['passenger_email']?.toString().trim() ?? '',
    passengerPhone: quoteRaw['passenger_phone']?.toString().trim() ?? '',
    enteredAmountCents: amount is num ? amount.toInt() : null,
    currency: quoteRaw['currency']?.toString().trim() ?? 'EUR',
    vatTreatment: quoteRaw['vat_treatment']?.toString().trim() ?? '',
    vatRate: _quoteCoord(quoteRaw['vat_rate'] ?? quoteRaw['vatRate']),
    validUntil: quoteRaw['valid_until']?.toString().trim() ?? '',
    createdAt: quoteRaw['created_at']?.toString().trim() ?? '',
    updatedAt: quoteRaw['updated_at']?.toString().trim() ?? '',
    pickupLat: _quoteCoord(quoteRaw['pickup_lat'] ?? quoteRaw['pickupLat']),
    pickupLon: _quoteCoord(quoteRaw['pickup_lon'] ?? quoteRaw['pickupLon']),
    pickupPlaceId:
        quoteRaw['pickup_place_id']?.toString().trim() ??
        quoteRaw['pickupPlaceId']?.toString().trim() ??
        '',
    dropoffLat: _quoteCoord(quoteRaw['dropoff_lat'] ?? quoteRaw['dropoffLat']),
    dropoffLon: _quoteCoord(quoteRaw['dropoff_lon'] ?? quoteRaw['dropoffLon']),
    dropoffPlaceId:
        quoteRaw['dropoff_place_id']?.toString().trim() ??
        quoteRaw['dropoffPlaceId']?.toString().trim() ??
        '',
    bookingId: quoteRaw['booking_id']?.toString().trim() ?? '',
    bookingListReady: quoteRaw['booking_list_ready'] == true ||
        raw['booking_list_ready'] == true,
    publicToken: quoteRaw['public_token']?.toString().trim() ?? '',
    publicUrl: quoteRaw['public_url']?.toString().trim().isNotEmpty == true
        ? quoteRaw['public_url'].toString().trim()
        : raw['public_url']?.toString().trim() ?? '',
    delivery: quoteRaw['delivery']?.toString().trim().isNotEmpty == true
        ? quoteRaw['delivery'].toString().trim()
        : raw['delivery']?.toString().trim() ?? '',
    deliveryProven: quoteRaw['delivery_proven'] == true ||
        raw['delivery_proven'] == true,
    testSend: quoteRaw['test_send'] == true || raw['test_send'] == true,
    rideOptions: parseCompanyRideOptions(
      quoteRaw['ride_options'] ?? quoteRaw['rideOptions'],
    ),
    roundtripChoice: parseCompanyRoundtripChoice(
      quoteRaw['roundtrip_dispatch_mode'] ?? quoteRaw['roundtrip_choice'],
    ),
    returnPickupIso: quoteRaw['return_pickup_iso']?.toString().trim() ?? '',
    returnFrom: quoteRaw['return_from']?.toString().trim() ?? '',
    returnTo: quoteRaw['return_to']?.toString().trim() ?? '',
    returnDurationMin: (quoteRaw['return_duration_min'] as num?)?.toInt(),
    occupancyWaitMin: (quoteRaw['occupancy_wait_min'] as num?)?.toInt(),
    occupancyUnknown: quoteRaw['occupancy_unknown'] == true,
    returnPickupLat: _quoteCoord(quoteRaw['return_pickup_lat']),
    returnPickupLon: _quoteCoord(quoteRaw['return_pickup_lon']),
    returnPickupPlaceId:
        quoteRaw['return_pickup_place_id']?.toString().trim() ?? '',
    returnDropoffLat: _quoteCoord(quoteRaw['return_dropoff_lat']),
    returnDropoffLon: _quoteCoord(quoteRaw['return_dropoff_lon']),
    returnDropoffPlaceId:
        quoteRaw['return_dropoff_place_id']?.toString().trim() ?? '',
    priceCovers: quoteRaw['price_covers']?.toString().trim() ?? '',
    fixedPriceSnapshot: quoteRaw['fixed_price_snapshot'] is Map
        ? Map<String, dynamic>.from(quoteRaw['fixed_price_snapshot'] as Map)
        : null,
  );
}

List<CompanyCustomerQuote> parseCompanyCustomerQuotes(Map<dynamic, dynamic> raw) {
  if (raw['ok'] != true) {
    throw CompanyCustomerException(
      raw['error']?.toString().trim().isNotEmpty == true
          ? raw['error'].toString()
          : 'quote_not_ok',
    );
  }
  final items = raw['items'];
  if (items is! List) throw const CompanyCustomerException('invalid_payload');
  return [
    for (final item in items)
      if (item is Map) parseCompanyCustomerQuote(item),
  ].where((quote) => quote.quoteId.isNotEmpty).toList();
}
