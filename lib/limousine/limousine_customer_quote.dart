// LIMOUSINE-MARKETPLACE-P2D2 — customer quote request, status and acceptance
// contracts. Uses the committed Worker DTOs. Status references stay opaque
// and memory-only; there is no approved secure-storage vault for limqs1.

import 'package:flutter/foundation.dart';

import 'limousine_offers.dart';
import 'limousine_pricing_overlay.dart';
import 'limousine_profile_identity.dart';
import 'limousine_quote_inbox.dart';

const Key kLimousineCustomerQuotePageKey = ValueKey<String>(
  'limousine_customer_quote_page',
);
const Key kLimousineCustomerStatusPageKey = ValueKey<String>(
  'limousine_customer_status_page',
);
const Key kLimousineCustomerEntryCardKey = ValueKey<String>(
  'limousine_customer_entry_card',
);
const Key kLimousineCustomerPhoneLayoutKey = ValueKey<String>(
  'limousine_customer_phone',
);
const Key kLimousineCustomerTabletLayoutKey = ValueKey<String>(
  'limousine_customer_tablet',
);
const Key kLimousineCustomerDiscoverEmptyKey = ValueKey<String>(
  'limousine_customer_discover_empty',
);
const Key kLimousineCustomerSubmitKey = ValueKey<String>(
  'limousine_customer_submit',
);
const Key kLimousineCustomerAcceptKey = ValueKey<String>(
  'limousine_customer_accept',
);
const Key kLimousineCustomerAcceptConfirmKey = ValueKey<String>(
  'limousine_customer_accept_confirm',
);
const Key kLimousineCustomerTermsCardKey = ValueKey<String>(
  'limousine_customer_terms_card',
);
const Key kLimousineCustomerUnavailableKey = ValueKey<String>(
  'limousine_customer_unavailable',
);
const Key kLimousineCustomerQuoteUpdatedKey = ValueKey<String>(
  'limousine_customer_quote_updated',
);

const Duration kLimousineStatusAutoPollInterval = Duration(seconds: 60);
const Duration kLimousineStatusManualDebounce = Duration(seconds: 8);
const int kLimousineStatusRateMax = 20;
const Duration kLimousineStatusRateWindow = Duration(minutes: 15);

const Set<String> kLimousineCustomerCreateAllowedKeys = <String>{
  'public_partner_id',
  'offer_id',
  'journey_type',
  'from',
  'to',
  'stops',
  'scheduled_pickup_iso',
  'roundtrip',
  'return_pickup_iso',
  'requested_duration_minutes',
  'pax',
  'bags',
  'selected_extra_ids',
  'customer_note',
  'occasion',
  'locale',
};

const Set<String> kLimousineCustomerBookAllowedKeys = <String>{
  'service_category',
  'public_partner_id',
  'offer_id',
  'journey_type',
  'from',
  'to',
  'stops',
  'scheduled_pickup_iso',
  'pickup_iso',
  'roundtrip',
  'return_pickup_iso',
  'requested_duration_minutes',
  'pax',
  'bags',
  'selected_extra_ids',
  'customer_note',
  'occasion',
  'locale',
};

const Set<String> kLimousineCustomerForbiddenSubmitKeys = <String>{
  'total_incl_vat_cents',
  'taxi_price',
  'price_incl_vat',
  'price_ex_vat',
  'price_vat',
  'vat_rate',
  'vat_amount',
  'mobilisation_amount_cents',
  'mobilisation_fee_cents',
  'pricing_revision',
  'offer_source_revision',
  'pricing_section_revision',
  'readiness',
  'limousine_entitled',
  'company_readiness',
  'tenant_id',
  'company_id',
  'vehicle_id',
  'service_class_id',
  'itinerary_fingerprint',
  'status_ref',
  'acceptance_reference',
  'customer_fingerprint',
};

enum LimousineCustomerQuoteStep {
  journey,
  providerOffer,
  detailsExtras,
  reviewRequest,
  waitingCompany,
  reviewQuote,
  acceptOffer,
}

enum LimousineCustomerQuotePhase {
  draft,
  submitting,
  live,
  accepting,
  unavailable,
}

enum LimousineCustomerDraftError {
  missingProviderOffer,
  unsupportedJourney,
  missingAddresses,
  invalidSchedule,
  invalidDuration,
  capacityExceeded,
  invalidExtra,
  forbiddenField,
}

class LimousineDiscoveredProvider {
  const LimousineDiscoveredProvider({
    required this.partnerId,
    required this.companyName,
    this.heroPhotoUrl = '',
    this.logoUrl = '',
    this.serviceArea = const <String>[],
    this.limousineAvailable = false,
    this.distanceKm,
  });

  final String partnerId;
  final String companyName;
  final String heroPhotoUrl;
  final String logoUrl;
  final List<String> serviceArea;
  final bool limousineAvailable;
  final double? distanceKm;

  factory LimousineDiscoveredProvider.fromJson(Object? raw) {
    final map = raw is Map
        ? raw.map((key, value) => MapEntry(key.toString(), value))
        : <String, dynamic>{};
    final area = <String>[];
    final postcodes = map['supported_postcodes'] ?? map['supportedPostcodes'];
    if (postcodes is List) {
      for (final item in postcodes.take(20)) {
        final text = item.toString().trim();
        if (text.isNotEmpty) area.add(text);
      }
    }
    final distance = map['distance_km'] ?? map['distanceKm'];
    return LimousineDiscoveredProvider(
      partnerId: (map['partner_id'] ?? map['partnerId'] ?? '')
          .toString()
          .trim(),
      companyName: (map['company_name'] ?? map['companyName'] ?? '')
          .toString()
          .trim(),
      heroPhotoUrl: _httpsOnly(map['hero_photo_url'] ?? map['heroPhotoUrl']),
      logoUrl: limousineResolvePublishedLogoUrl(
        source: limousineHydratePublishedPartnerOverlay(map),
      ),
      serviceArea: area,
      limousineAvailable:
          map['limousine_available'] == true ||
          map['limousine_service_enabled'] == true,
      distanceKm: distance is num ? distance.toDouble() : null,
    );
  }
}

class LimousinePublishedOffer {
  const LimousinePublishedOffer({
    required this.offerId,
    required this.raw,
    this.title = const <String, String>{},
    this.description = const <String, String>{},
    this.targetType = '',
    this.vehicleId = '',
    this.serviceClassId = '',
    this.journeyTypes = const <String>[],
    this.pricePresentation = '',
    this.displayAmountCents,
    this.currency = '',
    this.passengerCapacity,
    this.luggageCapacity,
    this.photoUrl = '',
    this.color = '',
    this.includedServices = const <Map<String, dynamic>>[],
    this.paidExtras = const <Map<String, dynamic>>[],
    this.mobilisationDisclosure = const <String, String>{},
  });

  final String offerId;
  final Map<String, dynamic> raw;
  final Map<String, String> title;
  final Map<String, String> description;
  final String targetType;
  final String vehicleId;
  final String serviceClassId;
  final List<String> journeyTypes;
  final String pricePresentation;
  final int? displayAmountCents;
  final String currency;
  final int? passengerCapacity;
  final int? luggageCapacity;
  final String photoUrl;
  final String color;
  final List<Map<String, dynamic>> includedServices;
  final List<Map<String, dynamic>> paidExtras;
  final Map<String, String> mobilisationDisclosure;

  bool get isVehicleTargeted =>
      limousineOfferToken(targetType) == LimousineOfferTarget.vehicle;

  bool supportsJourney(String journeyType) {
    final wanted = limousineOfferToken(journeyType);
    if (wanted.isEmpty || journeyTypes.isEmpty) return true;
    return journeyTypes.contains(wanted);
  }

  factory LimousinePublishedOffer.fromJson(Object? raw) {
    final map = raw is Map
        ? raw.map((key, value) => MapEntry(key.toString(), value))
        : <String, dynamic>{};
    final vehicle = map['vehicle'] is Map
        ? Map<String, dynamic>.from(map['vehicle'] as Map)
        : const <String, dynamic>{};
    final journeys = <String>[];
    final types = map['journey_types'] ?? map['journeyTypes'];
    if (types is List) {
      for (final item in types) {
        final token = limousineOfferToken(item);
        if (token.isNotEmpty) journeys.add(token);
      }
    }
    return LimousinePublishedOffer(
      offerId: (map['offer_id'] ?? map['offerId'] ?? '').toString().trim(),
      raw: Map<String, dynamic>.from(map),
      title: _localized(map['title']),
      description: _localized(map['description']),
      targetType: limousineOfferToken(map['target_type'] ?? map['targetType']),
      vehicleId: (map['vehicle_id'] ?? map['vehicleId'] ?? '')
          .toString()
          .trim(),
      serviceClassId: limousineOfferToken(
        map['service_class_id'] ?? map['serviceClassId'],
      ),
      journeyTypes: journeys,
      pricePresentation: limousineOfferToken(
        map['price_presentation'] ?? map['pricePresentation'],
      ),
      displayAmountCents: limousineCentsOf(map['display_amount_cents']),
      currency: limousineCurrencyOf(map['currency']),
      passengerCapacity: limousineCentsOf(
        vehicle['passenger_capacity'] ??
            vehicle['pax'] ??
            map['passenger_capacity'],
      ),
      luggageCapacity: limousineCentsOf(
        vehicle['luggage_capacity'] ??
            vehicle['luggage'] ??
            map['luggage_capacity'],
      ),
      photoUrl: _httpsOnly(vehicle['photo_url'] ?? map['photo_url']),
      color: (vehicle['color'] ?? '').toString().trim(),
      includedServices: _objectList(map['included_services']),
      paidExtras: _objectList(map['paid_extras']),
      mobilisationDisclosure: _localized(
        map['mobilisation'] is Map
            ? (map['mobilisation'] as Map)['disclosure']
            : map['mobilisation_disclosure'],
      ),
    );
  }
}

class LimousineProviderDetail {
  const LimousineProviderDetail({required this.provider, required this.offers});

  final LimousineDiscoveredProvider provider;
  final List<LimousinePublishedOffer> offers;
}

class LimousineQuoteCreateDraft {
  const LimousineQuoteCreateDraft({
    this.publicPartnerId = '',
    this.offerId = '',
    this.journeyType = 'point_to_point',
    this.from = '',
    this.to = '',
    this.stops = const <String>[],
    this.scheduledPickupIso = '',
    this.roundtrip = false,
    this.returnPickupIso = '',
    this.requestedDurationMinutes,
    this.pax,
    this.bags,
    this.selectedExtraIds = const <String>[],
    this.customerNote = '',
    this.occasion = '',
    this.locale = '',
  });

  final String publicPartnerId;
  final String offerId;
  final String journeyType;
  final String from;
  final String to;
  final List<String> stops;
  final String scheduledPickupIso;
  final bool roundtrip;
  final String returnPickupIso;
  final int? requestedDurationMinutes;
  final int? pax;
  final int? bags;
  final List<String> selectedExtraIds;
  final String customerNote;
  final String occasion;
  final String locale;

  LimousineQuoteCreateDraft copyWith({
    String? publicPartnerId,
    String? offerId,
    String? journeyType,
    String? from,
    String? to,
    List<String>? stops,
    String? scheduledPickupIso,
    bool? roundtrip,
    String? returnPickupIso,
    int? requestedDurationMinutes,
    int? pax,
    int? bags,
    List<String>? selectedExtraIds,
    String? customerNote,
    String? occasion,
    String? locale,
  }) {
    return LimousineQuoteCreateDraft(
      publicPartnerId: publicPartnerId ?? this.publicPartnerId,
      offerId: offerId ?? this.offerId,
      journeyType: journeyType ?? this.journeyType,
      from: from ?? this.from,
      to: to ?? this.to,
      stops: stops ?? this.stops,
      scheduledPickupIso: scheduledPickupIso ?? this.scheduledPickupIso,
      roundtrip: roundtrip ?? this.roundtrip,
      returnPickupIso: returnPickupIso ?? this.returnPickupIso,
      requestedDurationMinutes:
          requestedDurationMinutes ?? this.requestedDurationMinutes,
      pax: pax ?? this.pax,
      bags: bags ?? this.bags,
      selectedExtraIds: selectedExtraIds ?? this.selectedExtraIds,
      customerNote: customerNote ?? this.customerNote,
      occasion: occasion ?? this.occasion,
      locale: locale ?? this.locale,
    );
  }
}

class LimousineBookingRequestResult {
  const LimousineBookingRequestResult({
    required this.bookingId,
    this.idempotent = false,
  });

  final String bookingId;
  final bool idempotent;
}

class LimousineQuoteCreateResult {
  const LimousineQuoteCreateResult({
    required this.request,
    this.statusRef = '',
    this.statusExpiresAt = '',
    this.idempotent = false,
  });

  final LimousineQuoteRequest request;
  final String statusRef;
  final String statusExpiresAt;
  final bool idempotent;
}

class LimousineQuoteAcceptResult {
  const LimousineQuoteAcceptResult({
    required this.request,
    this.acceptanceReference = '',
    this.expiresAt = '',
  });

  final LimousineQuoteRequest request;
  final String acceptanceReference;
  final String expiresAt;
}

/// Opaque handoff for a future /book UI. Never decode or persist limacc1.
class LimousineAcceptedQuoteHandoff {
  const LimousineAcceptedQuoteHandoff({
    required this.acceptanceReference,
    required this.quoteRequestId,
    required this.quoteRevision,
    required this.termsRevision,
    required this.totalInclVatCents,
    required this.currency,
    required this.offerId,
    required this.publicPartnerId,
    required this.from,
    required this.to,
    required this.scheduledPickupIso,
  });

  final String acceptanceReference;
  final String quoteRequestId;
  final int quoteRevision;
  final int termsRevision;
  final int totalInclVatCents;
  final String currency;
  final String offerId;
  final String publicPartnerId;
  final String from;
  final String to;
  final String scheduledPickupIso;

  Map<String, dynamic> toBookPayloadFields() {
    return <String, dynamic>{
      'limousine_acceptance_reference': acceptanceReference,
      'from': from,
      'to': to,
      'pickup_iso': scheduledPickupIso,
    };
  }
}

abstract class LimousineStatusReferenceStore {
  Future<void> retain({
    required String accountScope,
    required String requestKey,
    required String statusRef,
  });

  Future<String?> read({
    required String accountScope,
    required String requestKey,
  });

  Future<void> clear({
    required String accountScope,
    required String requestKey,
  });

  Future<void> clearAccount(String accountScope);

  Future<void> clearAll();

  bool get persistsAcrossRestarts;
}

/// Memory-only holder. Persistent resume is intentionally blocked until an
/// approved secure vault exists. Do not write limqs1 to SharedPreferences.
class LimousineInMemoryStatusReferenceStore
    implements LimousineStatusReferenceStore {
  LimousineInMemoryStatusReferenceStore();

  final Map<String, String> _values = <String, String>{};

  String _key(String accountScope, String requestKey) =>
      '${accountScope.trim()}::${requestKey.trim()}';

  @override
  bool get persistsAcrossRestarts => false;

  @override
  Future<void> retain({
    required String accountScope,
    required String requestKey,
    required String statusRef,
  }) async {
    final ref = statusRef.trim();
    if (accountScope.trim().isEmpty ||
        requestKey.trim().isEmpty ||
        ref.isEmpty) {
      return;
    }
    _values[_key(accountScope, requestKey)] = ref;
  }

  @override
  Future<String?> read({
    required String accountScope,
    required String requestKey,
  }) async {
    return _values[_key(accountScope, requestKey)];
  }

  @override
  Future<void> clear({
    required String accountScope,
    required String requestKey,
  }) async {
    _values.remove(_key(accountScope, requestKey));
  }

  @override
  Future<void> clearAccount(String accountScope) async {
    final prefix = '${accountScope.trim()}::';
    _values.removeWhere((key, _) => key.startsWith(prefix));
  }

  @override
  Future<void> clearAll() async {
    _values.clear();
  }
}

bool isWorkerMarkedLimousineEligible(Map<String, dynamic> partner) {
  return partner['limousine_available'] == true ||
      partner['limousine_service_enabled'] == true;
}

List<LimousineDiscoveredProvider> filterWorkerEligibleLimousineProviders(
  Iterable<LimousineDiscoveredProvider> providers,
) {
  return providers
      .where(
        (provider) =>
            provider.limousineAvailable && provider.partnerId.isNotEmpty,
      )
      .toList(growable: false);
}

List<LimousinePublishedOffer> sortLimousineOffersVehicleFirst(
  Iterable<LimousinePublishedOffer> offers,
) {
  final list = offers.where((offer) => offer.offerId.isNotEmpty).toList();
  list.sort((a, b) {
    if (a.isVehicleTargeted == b.isVehicleTargeted) return 0;
    return a.isVehicleTargeted ? -1 : 1;
  });
  return list;
}

bool limousineCustomerRouteDraftChanged(
  LimousineQuoteCreateDraft previous,
  LimousineQuoteCreateDraft next,
) {
  return previous.from != next.from ||
      previous.to != next.to ||
      previous.scheduledPickupIso != next.scheduledPickupIso ||
      previous.roundtrip != next.roundtrip ||
      previous.returnPickupIso != next.returnPickupIso ||
      previous.journeyType != next.journeyType ||
      previous.stops.join('\u0001') != next.stops.join('\u0001');
}

List<LimousineCustomerDraftError> validateLimousineCustomerDraft(
  LimousineQuoteCreateDraft draft, {
  LimousinePublishedOffer? offer,
}) {
  final errors = <LimousineCustomerDraftError>[];
  if (draft.publicPartnerId.trim().isEmpty || draft.offerId.trim().isEmpty) {
    errors.add(LimousineCustomerDraftError.missingProviderOffer);
  }
  if (offer != null && !offer.supportsJourney(draft.journeyType)) {
    errors.add(LimousineCustomerDraftError.unsupportedJourney);
  }
  if (draft.from.trim().isEmpty || draft.to.trim().isEmpty) {
    errors.add(LimousineCustomerDraftError.missingAddresses);
  }
  final pickup = DateTime.tryParse(draft.scheduledPickupIso);
  if (pickup == null) {
    errors.add(LimousineCustomerDraftError.invalidSchedule);
  } else if (draft.roundtrip) {
    final ret = DateTime.tryParse(draft.returnPickupIso);
    if (ret == null || !ret.isAfter(pickup)) {
      errors.add(LimousineCustomerDraftError.invalidSchedule);
    }
  }
  final hourly = limousineOfferToken(draft.journeyType) == 'hourly_package';
  if (hourly &&
      (draft.requestedDurationMinutes == null ||
          draft.requestedDurationMinutes! <= 0)) {
    errors.add(LimousineCustomerDraftError.invalidDuration);
  }
  if (offer != null) {
    if (offer.passengerCapacity != null &&
        draft.pax != null &&
        draft.pax! > offer.passengerCapacity!) {
      errors.add(LimousineCustomerDraftError.capacityExceeded);
    }
    if (offer.luggageCapacity != null &&
        draft.bags != null &&
        draft.bags! > offer.luggageCapacity!) {
      errors.add(LimousineCustomerDraftError.capacityExceeded);
    }
    final allowedExtras = offer.paidExtras
        .map(
          (extra) => (extra['extra_id'] ?? extra['extraId'] ?? '').toString(),
        )
        .where((id) => id.isNotEmpty)
        .toSet();
    for (final extraId in draft.selectedExtraIds) {
      if (!allowedExtras.contains(extraId)) {
        errors.add(LimousineCustomerDraftError.invalidExtra);
        break;
      }
    }
  }
  return errors;
}

Map<String, dynamic> limousineCustomerCreateBody(
  LimousineQuoteCreateDraft draft,
) {
  final body = <String, dynamic>{
    'public_partner_id': draft.publicPartnerId.trim(),
    'offer_id': draft.offerId.trim(),
    'journey_type': limousineOfferToken(draft.journeyType),
    'from': draft.from.trim(),
    'to': draft.to.trim(),
    'scheduled_pickup_iso': draft.scheduledPickupIso.trim(),
    'locale': draft.locale.trim(),
  };
  if (draft.stops.isNotEmpty) {
    body['stops'] = draft.stops
        .map((stop) => stop.trim())
        .where((stop) => stop.isNotEmpty)
        .take(8)
        .toList(growable: false);
  }
  if (draft.roundtrip && draft.returnPickupIso.trim().isNotEmpty) {
    body['roundtrip'] = true;
    body['return_pickup_iso'] = draft.returnPickupIso.trim();
  }
  if (draft.requestedDurationMinutes != null) {
    body['requested_duration_minutes'] = draft.requestedDurationMinutes;
  }
  if (draft.pax != null) body['pax'] = draft.pax;
  if (draft.bags != null) body['bags'] = draft.bags;
  if (draft.selectedExtraIds.isNotEmpty) {
    body['selected_extra_ids'] = List<String>.from(draft.selectedExtraIds);
  }
  if (draft.customerNote.trim().isNotEmpty) {
    body['customer_note'] = draft.customerNote.trim();
  }
  if (draft.occasion.trim().isNotEmpty) {
    body['occasion'] = draft.occasion.trim();
  }
  body.removeWhere(
    (key, value) => value == null || (value is String && value.isEmpty),
  );
  return body;
}

Map<String, dynamic> limousineCustomerBookBody(LimousineQuoteCreateDraft draft) {
  final quoteBody = limousineCustomerCreateBody(draft);
  final body = <String, dynamic>{
    'service_category': 'limousine',
    ...quoteBody,
  };
  if (draft.scheduledPickupIso.trim().isNotEmpty) {
    body['pickup_iso'] = draft.scheduledPickupIso.trim();
  }
  body.removeWhere(
    (key, value) => value == null || (value is String && value.isEmpty),
  );
  return body;
}

bool limousineCustomerBookBodyIsBounded(Map<String, dynamic> body) {
  for (final key in body.keys) {
    if (!kLimousineCustomerBookAllowedKeys.contains(key)) return false;
    if (kLimousineCustomerForbiddenSubmitKeys.contains(key)) return false;
  }
  return true;
}

bool limousineCustomerCreateBodyIsBounded(Map<String, dynamic> body) {
  for (final key in body.keys) {
    if (!kLimousineCustomerCreateAllowedKeys.contains(key)) return false;
    if (kLimousineCustomerForbiddenSubmitKeys.contains(key)) return false;
  }
  return true;
}

Map<String, dynamic> limousineCustomerAcceptBody({
  required String quoteRequestId,
  required int expectedRevision,
  required int termsRevision,
}) {
  return <String, dynamic>{
    'quote_request_id': quoteRequestId.trim(),
    'expected_revision': expectedRevision,
    'terms_revision': termsRevision,
  };
}

bool looksLikeLimousineStatusRef(String? raw) {
  final text = (raw ?? '').trim();
  final parts = text.split('.');
  return parts.length == 3 &&
      parts[0] == 'limqs1' &&
      parts[1].isNotEmpty &&
      parts[2].isNotEmpty;
}

bool looksLikeLimousineAcceptanceRef(String? raw) {
  final text = (raw ?? '').trim();
  final parts = text.split('.');
  return parts.length == 3 &&
      parts[0] == 'limacc1' &&
      parts[1].isNotEmpty &&
      parts[2].isNotEmpty;
}

bool limousineCustomerQuoteExpired(
  LimousineQuoteRequest request, {
  DateTime? now,
}) {
  final expires = DateTime.tryParse(request.quote?.expiresAt ?? '');
  if (expires == null) return false;
  return (now ?? DateTime.now().toUtc()).isAfter(expires.toUtc());
}

bool limousineCustomerCanAccept(
  LimousineQuoteRequest request, {
  DateTime? now,
}) {
  if (request.acceptanceAllowed != true) return false;
  if (request.acceptanceBlockedReason.isNotEmpty) return false;
  if (request.missingTerms.isNotEmpty) return false;
  if (request.quote == null) return false;
  if ((request.quote!.termsRevision ?? 0) <= 0) return false;
  if (limousineCustomerQuoteExpired(request, now: now)) return false;
  if (request.isUnknownState) return false;
  final terms = request.quote!.terms ?? const <String, dynamic>{};
  for (final key in kLimousineRequiredTermsKeys) {
    if (terms[key] == null) return false;
  }
  return LimousineQuoteStateId.waitingForCustomer.contains(
    LimousineQuoteStateId.normalize(request.state),
  );
}

bool limousineCustomerShouldPoll(String state) {
  return !LimousineQuoteStateId.isTerminal(state) &&
      LimousineQuoteStateId.normalize(state) != LimousineQuoteStateId.accepted;
}

List<String> limousineCustomerRequiredTermsPresent(
  Map<String, dynamic>? terms,
) {
  final src = terms ?? const <String, dynamic>{};
  return kLimousineRequiredTermsKeys
      .where((key) => src.containsKey(key))
      .toList(growable: false);
}

bool limousineTextLooksLikeSecret(String text) {
  final value = text.trim();
  if (value.isEmpty) return false;
  return value.contains('limqs1.') ||
      value.contains('limacc1.') ||
      value.contains('Bearer ') ||
      value.contains('itinerary_fingerprint') ||
      value.contains('customer_fingerprint') ||
      value.contains('operating_base_address') ||
      value.contains('internal_cost');
}

String _httpsOnly(Object? raw) {
  final text = (raw ?? '').toString().trim();
  if (text.startsWith('https://')) return text;
  return '';
}

Map<String, String> _localized(Object? raw) {
  if (raw is! Map) return const <String, String>{};
  final out = <String, String>{};
  for (final lang in const <String>['nl', 'en', 'fr', 'es']) {
    final text = (raw[lang] ?? '').toString().trim();
    if (text.isNotEmpty) out[lang] = text;
  }
  return out;
}

List<Map<String, dynamic>> _objectList(Object? raw) {
  if (raw is! List) return const <Map<String, dynamic>>[];
  final out = <Map<String, dynamic>>[];
  for (final item in raw.take(20)) {
    if (item is Map) {
      out.add(item.map((key, value) => MapEntry(key.toString(), value)));
    }
  }
  return out;
}
