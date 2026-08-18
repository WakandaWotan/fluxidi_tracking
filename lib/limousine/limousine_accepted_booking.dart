// LIMOUSINE-MARKETPLACE-P2D3 — accepted-quote → existing /book handoff.
// Consumes only the committed P2C2 Worker contract. Never decodes limacc1.

import 'package:flutter/foundation.dart';

import '../app_config.dart';
import '../app_strings.dart';
import '../payment/payment_booking_selection.dart';
import '../payment/payment_method_catalog.dart';
import 'limousine_customer_quote.dart';
import 'limousine_quote_inbox.dart';

const Key kLimousineAcceptedBookingPageKey = ValueKey<String>(
  'limousine_accepted_booking_page',
);
const Key kLimousineAcceptedBookingReviewKey = ValueKey<String>(
  'limousine_accepted_booking_review',
);
const Key kLimousineAcceptedBookingConfirmKey = ValueKey<String>(
  'limousine_accepted_booking_confirm',
);
const Key kLimousineAcceptedBookingSubmitKey = ValueKey<String>(
  'limousine_accepted_booking_submit',
);
const Key kLimousineAcceptedBookingSuccessKey = ValueKey<String>(
  'limousine_accepted_booking_success',
);
const Key kLimousineAcceptedBookingCreatingKey = ValueKey<String>(
  'limousine_accepted_booking_creating',
);
const Key kLimousineAcceptedBookingOpenReviewKey = ValueKey<String>(
  'limousine_accepted_booking_open_review',
);
const Key kLimousineAcceptedBookingContinueKey = ValueKey<String>(
  'limousine_accepted_booking_continue',
);
const Key kLimousineAcceptedBookingDiscardKey = ValueKey<String>(
  'limousine_accepted_booking_discard',
);
const Key kLimousineAcceptedBookingBackToQuoteKey = ValueKey<String>(
  'limousine_accepted_booking_back_quote',
);
const Key kLimousineAcceptedBookingBackToProfileKey = ValueKey<String>(
  'limousine_accepted_booking_back_profile',
);

const Set<String> kLimousineAcceptedBookAllowedKeys = <String>{
  'limousine_acceptance_reference',
  'from',
  'to',
  'pickup_iso',
  'public_partner_id',
  'publicPartnerId',
  'partner_id',
  'partnerId',
  'tenant_id',
  'company_id',
  'tenantId',
  'companyId',
  'stops',
  'roundtrip',
  'return_enabled',
  'return_pickup_iso',
  'pax',
  'bags',
  'customer',
  'name',
  'phone',
  'email',
  'customer_name',
  'customer_phone',
  'customerPhone',
  'customer_email',
  'customer_id',
  'customerId',
  'phone_e164',
  'customer_phone_e164',
  'customerPhoneE164',
  'payment_mode',
  'paymentMode',
  'payment_provider',
  'paymentProvider',
  'payment_method',
  'paymentMethod',
  'booking_source',
  'entry_channel',
  'created_by_role',
};

const Set<String> kLimousineAcceptedBookForbiddenAuthorityKeys = <String>{
  'total_incl_vat_cents',
  'price_incl_vat',
  'price_ex_vat',
  'price_vat',
  'display_amount_cents',
  'taxi_price',
  'airport_fixed_fare',
  'quote_reference',
  'vehicle_id',
  'service_class_id',
  'itinerary_fingerprint',
  'limousine_entitled',
};

enum LimousineAcceptedBookingPhase {
  review,
  submitting,
  success,
  failed,
  ambiguous,
}

enum LimousineAcceptedBookingError {
  gateOff,
  missingAcceptanceReference,
  malformedAcceptanceReference,
  expiredAcceptanceReference,
  invalidAcceptanceReference,
  staleRevision,
  unauthorizedScope,
  missingCustomerScope,
  providerUnavailable,
  bookDisabled,
  unknownResponse,
  ambiguousTimeout,
  network,
}

class LimousineAcceptedBookingCustomer {
  const LimousineAcceptedBookingCustomer({
    required this.sessionToken,
    this.customerId = '',
    this.name = '',
    this.phone = '',
    this.email = '',
  });

  final String sessionToken;
  final String customerId;
  final String name;
  final String phone;
  final String email;

  bool get hasAuthenticatedScope => sessionToken.trim().isNotEmpty;
}

class LimousineAcceptedBookingReview {
  const LimousineAcceptedBookingReview({
    required this.providerName,
    required this.offerTitle,
    required this.serviceClassId,
    required this.serviceClassLabel,
    required this.vehicleSupplied,
    required this.journeyType,
    required this.from,
    required this.to,
    required this.stops,
    required this.scheduledPickupIso,
    required this.roundtrip,
    required this.returnPickupIso,
    required this.pax,
    required this.bags,
    required this.acceptedExtras,
    required this.includedServices,
    required this.mobilisationDisclosure,
    required this.totalInclVatCents,
    required this.currency,
    required this.vatTreatment,
    required this.termsRevision,
    required this.terms,
  });

  final String providerName;
  final String offerTitle;
  final String serviceClassId;
  final String serviceClassLabel;
  final bool vehicleSupplied;
  final String journeyType;
  final String from;
  final String to;
  final List<String> stops;
  final String scheduledPickupIso;
  final bool roundtrip;
  final String returnPickupIso;
  final int? pax;
  final int? bags;
  final List<Map<String, dynamic>> acceptedExtras;
  final List<Map<String, dynamic>> includedServices;
  final Map<String, String> mobilisationDisclosure;
  final int totalInclVatCents;
  final String currency;
  final String vatTreatment;
  final int termsRevision;
  final Map<String, dynamic> terms;
}

class LimousineAcceptedBookResult {
  const LimousineAcceptedBookResult({
    required this.bookingId,
    this.publicReference = '',
    this.raw = const <String, dynamic>{},
  });

  final String bookingId;
  final String publicReference;
  final Map<String, dynamic> raw;
}

class LimousineAcceptedBookException implements Exception {
  const LimousineAcceptedBookException({
    required this.code,
    this.statusCode = 0,
    this.ambiguous = false,
  });

  final String code;
  final int statusCode;
  final bool ambiguous;
}

LimousineAcceptedBookingReview buildLimousineAcceptedBookingReview({
  required LimousineAcceptedQuoteHandoff handoff,
  required LimousineQuoteCreateDraft draft,
  LimousineQuoteRequest? request,
  LimousinePublishedOffer? offer,
  String providerName = '',
  AppLanguage language = AppLanguage.nl,
}) {
  final quote = request?.quote;
  final title = offer == null
      ? handoff.offerId
      : localizedLimousineText(offer.title, languageCode: language.name);
  return LimousineAcceptedBookingReview(
    providerName: providerName.trim(),
    offerTitle: title.trim().isEmpty ? handoff.offerId : title.trim(),
    serviceClassId: request?.serviceClassId ?? offer?.serviceClassId ?? '',
    serviceClassLabel: limousineServiceClassLabel(
      request?.serviceClassId ?? offer?.serviceClassId,
      language,
    ),
    vehicleSupplied:
        (request?.vehicleId ?? '').trim().isNotEmpty ||
        (offer?.isVehicleTargeted ?? false),
    journeyType: (request?.journeyType ?? draft.journeyType).trim(),
    from: handoff.from,
    to: handoff.to,
    stops: List<String>.from(draft.stops),
    scheduledPickupIso: handoff.scheduledPickupIso,
    roundtrip: request?.roundtrip ?? draft.roundtrip,
    returnPickupIso: draft.returnPickupIso,
    pax: request?.pax ?? draft.pax,
    bags: request?.bags ?? draft.bags,
    acceptedExtras: quote?.separatelyPricedExtras ?? const [],
    includedServices: quote?.includedServices ?? const [],
    mobilisationDisclosure:
        quote?.mobilisationDisclosure ?? const <String, String>{},
    totalInclVatCents: handoff.totalInclVatCents,
    currency: handoff.currency,
    vatTreatment: quote?.vatTreatment ?? '',
    termsRevision: handoff.termsRevision,
    terms: quote?.terms ?? const <String, dynamic>{},
  );
}

LimousineAcceptedBookingError? limousineAcceptedBookPreflightError({
  required bool entryEnabled,
  LimousineAcceptedQuoteHandoff? handoff,
  LimousineAcceptedBookingCustomer? customer,
}) {
  if (!entryEnabled) return LimousineAcceptedBookingError.gateOff;
  if (handoff == null || handoff.acceptanceReference.trim().isEmpty) {
    return LimousineAcceptedBookingError.missingAcceptanceReference;
  }
  if (!looksLikeLimousineAcceptanceRef(handoff.acceptanceReference)) {
    return LimousineAcceptedBookingError.malformedAcceptanceReference;
  }
  if (handoff.publicPartnerId.trim().isEmpty) {
    return LimousineAcceptedBookingError.unauthorizedScope;
  }
  if (handoff.from.trim().isEmpty ||
      handoff.to.trim().isEmpty ||
      handoff.scheduledPickupIso.trim().isEmpty) {
    return LimousineAcceptedBookingError.staleRevision;
  }
  if (customer == null || !customer.hasAuthenticatedScope) {
    return LimousineAcceptedBookingError.missingCustomerScope;
  }
  return null;
}

Map<String, dynamic> limousineAcceptedBookPayload({
  required LimousineAcceptedQuoteHandoff handoff,
  required LimousineQuoteCreateDraft draft,
  required LimousineAcceptedBookingCustomer customer,
  LimousineQuoteRequest? request,
}) {
  final partnerId = handoff.publicPartnerId.trim();
  final payment = BookingPaymentSelection.fromMethodId(PaymentMethodIds.cash);
  final phone = customer.phone.trim();
  final email = customer.email.trim();
  final name = customer.name.trim();
  final customerId = customer.customerId.trim();
  final payload = <String, dynamic>{
    ...handoff.toBookPayloadFields(),
    'public_partner_id': partnerId,
    'publicPartnerId': partnerId,
    'partner_id': partnerId,
    'partnerId': partnerId,
    'tenant_id': partnerId,
    'company_id': partnerId,
    'tenantId': partnerId,
    'companyId': partnerId,
    'roundtrip': request?.roundtrip ?? draft.roundtrip,
    'return_enabled': request?.roundtrip ?? draft.roundtrip,
    'booking_source': 'flutter_app',
    'entry_channel': 'flutter_calculator',
    'created_by_role': 'customer',
    ...payment.toPayloadFields(),
    'customer': <String, dynamic>{
      if (name.isNotEmpty) 'name': name,
      if (name.isNotEmpty) 'full_name': name,
      if (phone.isNotEmpty) 'phone': phone,
      if (phone.isNotEmpty) 'phone_e164': phone,
      if (email.isNotEmpty) 'email': email,
      if (customerId.isNotEmpty) 'customer_id': customerId,
    },
    if (name.isNotEmpty) 'name': name,
    if (name.isNotEmpty) 'customer_name': name,
    if (phone.isNotEmpty) 'phone': phone,
    if (phone.isNotEmpty) 'customer_phone': phone,
    if (phone.isNotEmpty) 'customerPhone': phone,
    if (phone.isNotEmpty) 'phone_e164': phone,
    if (phone.isNotEmpty) 'customer_phone_e164': phone,
    if (phone.isNotEmpty) 'customerPhoneE164': phone,
    if (email.isNotEmpty) 'email': email,
    if (email.isNotEmpty) 'customer_email': email,
    if (customerId.isNotEmpty) 'customer_id': customerId,
    if (customerId.isNotEmpty) 'customerId': customerId,
  };
  if (draft.stops.isNotEmpty) payload['stops'] = List<String>.from(draft.stops);
  if (draft.returnPickupIso.trim().isNotEmpty) {
    payload['return_pickup_iso'] = draft.returnPickupIso.trim();
  }
  final pax = request?.pax ?? draft.pax;
  final bags = request?.bags ?? draft.bags;
  if (pax != null) payload['pax'] = pax;
  if (bags != null) payload['bags'] = bags;
  return payload;
}

bool limousineAcceptedBookPayloadIsSafe(Map<String, dynamic> payload) {
  for (final key in payload.keys) {
    if (!kLimousineAcceptedBookAllowedKeys.contains(key)) return false;
    if (kLimousineAcceptedBookForbiddenAuthorityKeys.contains(key)) {
      return false;
    }
  }
  final reference = (payload['limousine_acceptance_reference'] ?? '')
      .toString()
      .trim();
  if (!looksLikeLimousineAcceptanceRef(reference)) return false;
  if ((payload['from'] ?? '').toString().trim().isEmpty) return false;
  if ((payload['to'] ?? '').toString().trim().isEmpty) return false;
  if ((payload['pickup_iso'] ?? '').toString().trim().isEmpty) return false;
  if ((payload['public_partner_id'] ?? '').toString().trim().isEmpty) {
    return false;
  }
  return true;
}

String firstLimousineBookingReference(Map<String, dynamic> body) {
  final booking = body['booking'] is Map
      ? Map<String, dynamic>.from(body['booking'] as Map)
      : const <String, dynamic>{};
  for (final value in <dynamic>[
    body['bookingId'],
    body['booking_id'],
    body['public_booking_id'],
    body['publicBookingId'],
    body['id'],
    booking['bookingId'],
    booking['booking_id'],
    booking['public_booking_id'],
    booking['publicBookingId'],
    booking['id'],
  ]) {
    final text = (value ?? '').toString().trim();
    if (text.isNotEmpty) return text;
  }
  return '';
}

String firstLimousinePublicBookingReference(Map<String, dynamic> body) {
  final booking = body['booking'] is Map
      ? Map<String, dynamic>.from(body['booking'] as Map)
      : const <String, dynamic>{};
  for (final value in <dynamic>[
    body['public_reference'],
    body['publicReference'],
    body['public_booking_reference'],
    body['publicBookingReference'],
    body['booking_reference'],
    body['bookingReference'],
    body['customer_reference'],
    body['customerReference'],
    booking['public_reference'],
    booking['publicReference'],
    booking['public_booking_reference'],
    booking['publicBookingReference'],
    booking['booking_reference'],
    booking['bookingReference'],
  ]) {
    final text = (value ?? '').toString().trim();
    if (text.isNotEmpty) return text;
  }
  return firstLimousineBookingReference(body);
}

LimousineAcceptedBookingError limousineAcceptedBookErrorFromCode(String code) {
  switch (code.trim()) {
    case 'acceptance_reference_malformed':
    case 'acceptance_reference_version':
      return LimousineAcceptedBookingError.malformedAcceptanceReference;
    case 'acceptance_reference_expired':
      return LimousineAcceptedBookingError.expiredAcceptanceReference;
    case 'acceptance_reference_invalid':
    case 'acceptance_secret_missing':
      return LimousineAcceptedBookingError.invalidAcceptanceReference;
    case 'limousine_quote_refresh_required':
    case 'stale_revision':
    case 'limousine_quote_not_accepted':
      return LimousineAcceptedBookingError.staleRevision;
    case 'unauthorized_scope':
      return LimousineAcceptedBookingError.unauthorizedScope;
    case 'missing_customer_scope':
      return LimousineAcceptedBookingError.missingCustomerScope;
    case 'subscription_suspended':
    case 'not_eligible':
    case 'limousine_unavailable':
      return LimousineAcceptedBookingError.providerUnavailable;
    case 'limousine_book_disabled':
    case 'manual_quote_gate_off':
      return LimousineAcceptedBookingError.bookDisabled;
    case 'ambiguous_timeout':
      return LimousineAcceptedBookingError.ambiguousTimeout;
    case 'unknown_response':
      return LimousineAcceptedBookingError.unknownResponse;
    case 'gate_off':
      return LimousineAcceptedBookingError.gateOff;
    default:
      return LimousineAcceptedBookingError.network;
  }
}

bool limousineAcceptedBookingTextLeaksToken(String text) {
  return limousineTextLooksLikeSecret(text);
}
