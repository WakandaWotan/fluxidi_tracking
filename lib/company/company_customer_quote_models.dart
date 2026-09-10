// COMPANY-CUSTOMER-OPS-P0 — company-issued customer quotes.

import 'package:fluxidi_tracking/company/company_customer_models.dart';

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
    required this.validUntil,
    required this.createdAt,
    required this.updatedAt,
    this.bookingId = '',
    this.publicToken = '',
    this.delivery = '',
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
  final String validUntil;
  final String createdAt;
  final String updatedAt;
  final String bookingId;
  final String publicToken;
  final String delivery;

  bool get isDraft => state == 'draft';
  bool get isAccepted => state == 'accepted';
}

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
    this.validUntil = '',
    this.issuerName = '',
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
  final String validUntil;
  final String issuerName;

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
      if (validUntil.trim().isNotEmpty) 'valid_until': validUntil.trim(),
      if (issuerName.trim().isNotEmpty) 'issuer_name': issuerName.trim(),
      if (revision != null) 'revision': revision,
    };
  }
}

int? parseEuroToCents(String raw) {
  final text = raw.trim().replaceAll(',', '.');
  if (text.isEmpty) return null;
  final value = double.tryParse(text);
  if (value == null || value < 0 || value > 999999) return null;
  return (value * 100).round();
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
    validUntil: quoteRaw['valid_until']?.toString().trim() ?? '',
    createdAt: quoteRaw['created_at']?.toString().trim() ?? '',
    updatedAt: quoteRaw['updated_at']?.toString().trim() ?? '',
    bookingId: quoteRaw['booking_id']?.toString().trim() ?? '',
    publicToken: quoteRaw['public_token']?.toString().trim() ?? '',
    delivery: raw['delivery']?.toString().trim() ?? '',
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
