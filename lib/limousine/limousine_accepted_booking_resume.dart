// LIMOUSINE-MARKETPLACE-P2D4A — minimal accepted-quote resume envelope.
// Review totals are evidence only. Never decode or display limacc1.

import 'limousine_accepted_booking.dart';
import 'limousine_customer_quote.dart';

const int kLimousineAcceptedBookingResumeSchemaVersion = 1;

const String kLimousineAcceptedBookingResumeStorageKey =
    'limousine_accepted_booking_resume_v1';

class LimousineAcceptedBookingResumeScope {
  const LimousineAcceptedBookingResumeScope({
    required this.customerId,
    this.publicPartnerId,
    this.tenantId,
    this.companyId,
  });

  final String customerId;
  final String? publicPartnerId;
  final String? tenantId;
  final String? companyId;
}

class LimousineAcceptedBookingResumeEnvelope {
  const LimousineAcceptedBookingResumeEnvelope({
    required this.schemaVersion,
    required this.handoff,
    required this.draft,
    required this.review,
    required this.publicPartnerId,
    required this.tenantId,
    required this.companyId,
    required this.customerId,
    required this.createdAt,
    required this.expiresAt,
    this.providerName = '',
  });

  final int schemaVersion;
  final LimousineAcceptedQuoteHandoff handoff;
  final LimousineQuoteCreateDraft draft;
  final LimousineAcceptedBookingReview review;
  final String publicPartnerId;
  final String tenantId;
  final String companyId;
  final String customerId;
  final DateTime createdAt;
  final DateTime expiresAt;
  final String providerName;

  bool matches(LimousineAcceptedBookingResumeScope scope) {
    if (customerId != scope.customerId.trim()) return false;
    final partner = (scope.publicPartnerId ?? '').trim();
    if (partner.isNotEmpty && partner != publicPartnerId) return false;
    final tenant = (scope.tenantId ?? '').trim();
    if (tenant.isNotEmpty && tenant != tenantId) return false;
    final company = (scope.companyId ?? '').trim();
    if (company.isNotEmpty && company != companyId) return false;
    return true;
  }

  bool isExpired(DateTime now) => !now.toUtc().isBefore(expiresAt.toUtc());

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'schema_version': schemaVersion,
      'acceptance_reference': handoff.acceptanceReference,
      'quote_request_id': handoff.quoteRequestId,
      'quote_revision': handoff.quoteRevision,
      'terms_revision': handoff.termsRevision,
      'total_incl_vat_cents': handoff.totalInclVatCents,
      'currency': handoff.currency,
      'offer_id': handoff.offerId,
      'public_partner_id': publicPartnerId,
      'tenant_id': tenantId,
      'company_id': companyId,
      'customer_id': customerId,
      'from': handoff.from,
      'to': handoff.to,
      'scheduled_pickup_iso': handoff.scheduledPickupIso,
      'created_at': createdAt.toUtc().toIso8601String(),
      'expires_at': expiresAt.toUtc().toIso8601String(),
      'provider_name': providerName,
      'draft': _draftToJson(draft),
      'review': _reviewToJson(review),
    };
  }
}

bool limousineAcceptedBookingResumeJsonLooksSafe(Map<String, dynamic> json) {
  const forbidden = <String>{
    'customer_session_token',
    'customerSessionToken',
    'authorization',
    'Authorization',
    'bearer',
    'Bearer',
    'session_token',
    'mollie',
    'card_number',
    'LIMOUSINE_ACCEPTANCE_SECRET',
  };
  for (final key in json.keys) {
    if (forbidden.contains(key)) return false;
  }
  return true;
}

LimousineAcceptedBookingResumeEnvelope?
parseLimousineAcceptedBookingResumeEnvelope(Object? raw) {
  if (raw is! Map) return null;
  final map = raw.map((key, value) => MapEntry(key.toString(), value));
  if (!limousineAcceptedBookingResumeJsonLooksSafe(map)) return null;
  final schema = map['schema_version'];
  if (schema != kLimousineAcceptedBookingResumeSchemaVersion) return null;
  final acceptance = (map['acceptance_reference'] ?? '').toString().trim();
  if (!looksLikeLimousineAcceptanceRef(acceptance)) return null;
  final customerId = (map['customer_id'] ?? '').toString().trim();
  final publicPartnerId = (map['public_partner_id'] ?? '').toString().trim();
  final tenantId = (map['tenant_id'] ?? '').toString().trim();
  final companyId = (map['company_id'] ?? '').toString().trim();
  final from = (map['from'] ?? '').toString().trim();
  final to = (map['to'] ?? '').toString().trim();
  final pickup = (map['scheduled_pickup_iso'] ?? '').toString().trim();
  final createdAt = DateTime.tryParse((map['created_at'] ?? '').toString());
  final expiresAt = DateTime.tryParse((map['expires_at'] ?? '').toString());
  if (customerId.isEmpty ||
      publicPartnerId.isEmpty ||
      tenantId.isEmpty ||
      companyId.isEmpty ||
      from.isEmpty ||
      to.isEmpty ||
      pickup.isEmpty ||
      createdAt == null ||
      expiresAt == null) {
    return null;
  }
  final draft = _draftFromJson(
    map['draft'],
    fallbackPartnerId: publicPartnerId,
  );
  final review = _reviewFromJson(
    map['review'],
    from: from,
    to: to,
    pickup: pickup,
    totalInclVatCents: _intOf(map['total_incl_vat_cents']) ?? 0,
    currency: (map['currency'] ?? '').toString(),
    termsRevision: _intOf(map['terms_revision']) ?? 0,
  );
  if (draft == null || review == null) return null;
  return LimousineAcceptedBookingResumeEnvelope(
    schemaVersion: kLimousineAcceptedBookingResumeSchemaVersion,
    handoff: LimousineAcceptedQuoteHandoff(
      acceptanceReference: acceptance,
      quoteRequestId: (map['quote_request_id'] ?? '').toString(),
      quoteRevision: _intOf(map['quote_revision']) ?? 0,
      termsRevision: _intOf(map['terms_revision']) ?? 0,
      totalInclVatCents: _intOf(map['total_incl_vat_cents']) ?? 0,
      currency: (map['currency'] ?? '').toString(),
      offerId: (map['offer_id'] ?? '').toString(),
      publicPartnerId: publicPartnerId,
      from: from,
      to: to,
      scheduledPickupIso: pickup,
    ),
    draft: draft,
    review: review,
    publicPartnerId: publicPartnerId,
    tenantId: tenantId,
    companyId: companyId,
    customerId: customerId,
    createdAt: createdAt.toUtc(),
    expiresAt: expiresAt.toUtc(),
    providerName: (map['provider_name'] ?? '').toString(),
  );
}

LimousineAcceptedBookingResumeEnvelope?
buildLimousineAcceptedBookingResumeEnvelope({
  required LimousineAcceptedQuoteHandoff handoff,
  required LimousineQuoteCreateDraft draft,
  required LimousineAcceptedBookingReview review,
  required String customerId,
  required DateTime createdAt,
  required DateTime expiresAt,
  String providerName = '',
}) {
  final partnerId = handoff.publicPartnerId.trim();
  final customer = customerId.trim();
  if (customer.isEmpty ||
      partnerId.isEmpty ||
      !looksLikeLimousineAcceptanceRef(handoff.acceptanceReference) ||
      handoff.from.trim().isEmpty ||
      handoff.to.trim().isEmpty ||
      handoff.scheduledPickupIso.trim().isEmpty) {
    return null;
  }
  return LimousineAcceptedBookingResumeEnvelope(
    schemaVersion: kLimousineAcceptedBookingResumeSchemaVersion,
    handoff: handoff,
    draft: draft,
    review: review,
    publicPartnerId: partnerId,
    tenantId: partnerId,
    companyId: partnerId,
    customerId: customer,
    createdAt: createdAt.toUtc(),
    expiresAt: expiresAt.toUtc(),
    providerName: providerName.trim(),
  );
}

int? _intOf(Object? raw) {
  if (raw is int) return raw;
  if (raw is num) return raw.toInt();
  return int.tryParse((raw ?? '').toString().trim());
}

Map<String, dynamic> _draftToJson(LimousineQuoteCreateDraft draft) {
  return <String, dynamic>{
    'public_partner_id': draft.publicPartnerId,
    'offer_id': draft.offerId,
    'journey_type': draft.journeyType,
    'from': draft.from,
    'to': draft.to,
    'stops': List<String>.from(draft.stops),
    'scheduled_pickup_iso': draft.scheduledPickupIso,
    'roundtrip': draft.roundtrip,
    'return_pickup_iso': draft.returnPickupIso,
    if (draft.pax != null) 'pax': draft.pax,
    if (draft.bags != null) 'bags': draft.bags,
    'selected_extra_ids': List<String>.from(draft.selectedExtraIds),
    if (draft.requestedDurationMinutes != null)
      'requested_duration_minutes': draft.requestedDurationMinutes,
    if (draft.customerNote.trim().isNotEmpty)
      'customer_note': draft.customerNote.trim(),
    if (draft.occasion.trim().isNotEmpty) 'occasion': draft.occasion.trim(),
    'locale': draft.locale,
  };
}

LimousineQuoteCreateDraft? _draftFromJson(
  Object? raw, {
  required String fallbackPartnerId,
}) {
  if (raw != null && raw is! Map) return null;
  final map = raw is Map
      ? raw.map((key, value) => MapEntry(key.toString(), value))
      : <String, dynamic>{};
  final stops = <String>[];
  final rawStops = map['stops'];
  if (rawStops is List) {
    for (final item in rawStops) {
      final text = item.toString().trim();
      if (text.isNotEmpty) stops.add(text);
    }
  }
  final extras = <String>[];
  final rawExtras = map['selected_extra_ids'];
  if (rawExtras is List) {
    for (final item in rawExtras) {
      final text = item.toString().trim();
      if (text.isNotEmpty) extras.add(text);
    }
  }
  return LimousineQuoteCreateDraft(
    publicPartnerId: (map['public_partner_id'] ?? fallbackPartnerId).toString(),
    offerId: (map['offer_id'] ?? '').toString(),
    journeyType: (map['journey_type'] ?? 'point_to_point').toString(),
    from: (map['from'] ?? '').toString(),
    to: (map['to'] ?? '').toString(),
    stops: stops,
    scheduledPickupIso: (map['scheduled_pickup_iso'] ?? '').toString(),
    roundtrip: map['roundtrip'] == true,
    returnPickupIso: (map['return_pickup_iso'] ?? '').toString(),
    pax: _intOf(map['pax']),
    bags: _intOf(map['bags']),
    selectedExtraIds: extras,
    requestedDurationMinutes: _intOf(map['requested_duration_minutes']),
    customerNote: (map['customer_note'] ?? '').toString(),
    occasion: (map['occasion'] ?? '').toString(),
    locale: (map['locale'] ?? '').toString(),
  );
}

Map<String, dynamic> _reviewToJson(LimousineAcceptedBookingReview review) {
  return <String, dynamic>{
    'provider_name': review.providerName,
    'offer_title': review.offerTitle,
    'service_class_id': review.serviceClassId,
    'service_class_label': review.serviceClassLabel,
    'vehicle_supplied': review.vehicleSupplied,
    'journey_type': review.journeyType,
    'from': review.from,
    'to': review.to,
    'stops': List<String>.from(review.stops),
    'scheduled_pickup_iso': review.scheduledPickupIso,
    'roundtrip': review.roundtrip,
    'return_pickup_iso': review.returnPickupIso,
    if (review.pax != null) 'pax': review.pax,
    if (review.bags != null) 'bags': review.bags,
    'accepted_extras': review.acceptedExtras,
    'included_services': review.includedServices,
    'mobilisation_disclosure': review.mobilisationDisclosure,
    'total_incl_vat_cents': review.totalInclVatCents,
    if (review.totalExVatCents != null)
      'total_ex_vat_cents': review.totalExVatCents,
    if (review.vatAmountCents != null)
      'vat_amount_cents': review.vatAmountCents,
    if (review.vatRate != null) 'vat_rate': review.vatRate,
    'currency': review.currency,
    'vat_treatment': review.vatTreatment,
    'terms_revision': review.termsRevision,
    'terms': review.terms,
  };
}

LimousineAcceptedBookingReview? _reviewFromJson(
  Object? raw, {
  required String from,
  required String to,
  required String pickup,
  required int totalInclVatCents,
  required String currency,
  required int termsRevision,
}) {
  if (raw != null && raw is! Map) return null;
  final map = raw is Map
      ? raw.map((key, value) => MapEntry(key.toString(), value))
      : <String, dynamic>{};
  List<String> stringList(Object? value) {
    if (value is! List) return const <String>[];
    return value
        .map((item) => item.toString().trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
  }

  List<Map<String, dynamic>> mapList(Object? value) {
    if (value is! List) return const <Map<String, dynamic>>[];
    return value
        .whereType<Map>()
        .map((item) => item.map((key, val) => MapEntry(key.toString(), val)))
        .toList(growable: false);
  }

  Map<String, String> stringMap(Object? value) {
    if (value is! Map) return const <String, String>{};
    return value.map((key, val) => MapEntry(key.toString(), val.toString()));
  }

  Map<String, dynamic> dynamicMap(Object? value) {
    if (value is! Map) return const <String, dynamic>{};
    return value.map((key, val) => MapEntry(key.toString(), val));
  }

  return LimousineAcceptedBookingReview(
    providerName: (map['provider_name'] ?? '').toString(),
    offerTitle: (map['offer_title'] ?? '').toString(),
    serviceClassId: (map['service_class_id'] ?? '').toString(),
    serviceClassLabel: (map['service_class_label'] ?? '').toString(),
    vehicleSupplied: map['vehicle_supplied'] == true,
    journeyType: (map['journey_type'] ?? '').toString(),
    from: ((map['from'] ?? from).toString()),
    to: ((map['to'] ?? to).toString()),
    stops: stringList(map['stops']),
    scheduledPickupIso: ((map['scheduled_pickup_iso'] ?? pickup).toString()),
    roundtrip: map['roundtrip'] == true,
    returnPickupIso: (map['return_pickup_iso'] ?? '').toString(),
    pax: _intOf(map['pax']),
    bags: _intOf(map['bags']),
    acceptedExtras: mapList(map['accepted_extras']),
    includedServices: mapList(map['included_services']),
    mobilisationDisclosure: stringMap(map['mobilisation_disclosure']),
    totalInclVatCents: _intOf(map['total_incl_vat_cents']) ?? totalInclVatCents,
    totalExVatCents: _intOf(map['total_ex_vat_cents']),
    vatAmountCents: _intOf(map['vat_amount_cents']),
    vatRate: map['vat_rate'] is num
        ? map['vat_rate'] as num
        : num.tryParse('${map['vat_rate'] ?? ''}'),
    currency: (map['currency'] ?? currency).toString(),
    vatTreatment: (map['vat_treatment'] ?? '').toString(),
    termsRevision: _intOf(map['terms_revision']) ?? termsRevision,
    terms: dynamicMap(map['terms']),
  );
}
