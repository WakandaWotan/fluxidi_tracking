// LIMOUSINE-MARKETPLACE-P2D4C1E — customer discovery listing rules.
// Fail closed on the committed public nearby/profile projection.
// Never infer eligibility from names, drafts, preview state or private bases.

import 'package:flutter/foundation.dart';

import '../app_strings.dart';
import 'limousine_customer_discovery_labels.dart';
import 'limousine_customer_quote.dart';
import 'limousine_offers.dart';
import 'limousine_service_capability.dart';

const String kLimousineDiscoveryNearbyPath = '/partners/nearby';
const String kLimousineDiscoveryProfilePath = '/partners/profile';
const String kLimousineDiscoveryBookPath = '/book';
const String kLimousineDiscoveryFieldId = 'discovery';

const Key kLimousineCustomerDiscoveryPageKey = ValueKey<String>(
  'limousine_customer_discovery_page',
);
const Key kLimousineDiscoveryHeroKey = ValueKey<String>(
  'limousine_discovery_hero',
);
const Key kLimousineDiscoveryTitleKey = ValueKey<String>(
  'limousine_discovery_title',
);
const Key kLimousineDiscoverySearchActionKey = ValueKey<String>(
  'limousine_discovery_search',
);
const Key kLimousineDiscoveryLoadingKey = ValueKey<String>(
  'limousine_discovery_loading',
);
const Key kLimousineDiscoveryEmptyKey = ValueKey<String>(
  'limousine_discovery_empty',
);
const Key kLimousineDiscoveryGatesOffKey = ValueKey<String>(
  'limousine_discovery_gates_off',
);
const Key kLimousineDiscoverySearchOtherRegionKey = ValueKey<String>(
  'limousine_discovery_search_other_region',
);
const Key kLimousineDiscoveryLanguageTabsKey = ValueKey<String>(
  'limousine_discovery_language_tabs',
);
const Key kLimousineDiscoveryPhoneLayoutKey = ValueKey<String>(
  'limousine_discovery_phone',
);
const Key kLimousineDiscoveryTabletPortraitLayoutKey = ValueKey<String>(
  'limousine_discovery_tablet_portrait',
);
const Key kLimousineDiscoveryTabletLandscapeLayoutKey = ValueKey<String>(
  'limousine_discovery_tablet_landscape',
);
const Key kLimousineDiscoveryCardListKey = ValueKey<String>(
  'limousine_discovery_cards',
);
const Key kLimousineDiscoveryOpeningKey = ValueKey<String>(
  'limousine_discovery_opening',
);
const Key kLimousineDiscoveryProfileUnavailableKey = ValueKey<String>(
  'limousine_discovery_profile_unavailable',
);

Key limousineDiscoveryCardKey(String partnerId) =>
    ValueKey<String>('limousine_discovery_card_$partnerId');

Key limousineDiscoveryOffersCtaKey(String partnerId) =>
    ValueKey<String>('limousine_discovery_offers_$partnerId');

Key limousineDiscoveryProfileCtaKey(String partnerId) =>
    ValueKey<String>('limousine_discovery_profile_$partnerId');

/// Smallest Worker seam still missing on the committed nearby/profile persist
/// path. This phase does not patch a Worker.
const String kLimousineDiscoveryMissingWorkerContract = '''
GET /partners/nearby currently ignores service=limousine, sorts by public
coverage geometry, and returns partner_id, company_name, is_active,
subscription_status, supported_postcodes, optional distance_km, hero/logo
and services[]. It does not persist or return:

1. Honor service=limousine server-side (exclude taxi-only partners).
2. limousine_available (bool) = published partner + limousine capability
   + ≥1 active vehicle with service_category=limousine
   + ≥1 published limousine offer or enabled quote_required.
3. limousine_vehicles[] (max 2): safe photo_url, service_class_id,
   passenger_capacity, luggage_capacity — no plate, driver or private base.
4. limousine_price_presentation: quote_required | from_price | exact_fixed
   plus display_amount_cents/currency only when authoritative.
5. Safe public_city or service_region.
6. trust.verified_partner on nearby (already on GET /partners/profile).
7. Persist service_category on public vehicles.
8. Project limousine_offers onto GET /partners/profile.

Do not calculate proximity from private operating-base coordinates.
''';

enum LimousineDiscoveryPriceKind { none, quoteRequired, fromPrice, exactFixed }

class LimousineDiscoveryVehicleThumb {
  const LimousineDiscoveryVehicleThumb({
    this.photoUrl = '',
    this.serviceClassId = '',
    this.passengerCapacity,
    this.luggageCapacity,
  });

  final String photoUrl;
  final String serviceClassId;
  final int? passengerCapacity;
  final int? luggageCapacity;
}

class LimousineDiscoveryPrice {
  const LimousineDiscoveryPrice({
    required this.kind,
    this.amountCents,
    this.currency = '',
  });

  final LimousineDiscoveryPriceKind kind;
  final int? amountCents;
  final String currency;

  bool get hasAuthoritativeAmount =>
      amountCents != null && amountCents! > 0 && currency.trim().isNotEmpty;
}

class LimousineDiscoveryCard {
  const LimousineDiscoveryCard({
    required this.publicPartnerId,
    required this.companyName,
    this.coverImageUrl = '',
    this.logoUrl = '',
    this.verifiedPartner = false,
    this.publicCity = '',
    this.distanceKm,
    this.vehicles = const <LimousineDiscoveryVehicleThumb>[],
    this.price = const LimousineDiscoveryPrice(
      kind: LimousineDiscoveryPriceKind.none,
    ),
  });

  final String publicPartnerId;
  final String companyName;
  final String coverImageUrl;
  final String logoUrl;
  final bool verifiedPartner;
  final String publicCity;
  final double? distanceKm;
  final List<LimousineDiscoveryVehicleThumb> vehicles;
  final LimousineDiscoveryPrice price;
}

class LimousineDiscoveryQuery {
  const LimousineDiscoveryQuery({this.postcode, this.lat, this.lng});

  final String? postcode;
  final double? lat;
  final double? lng;

  bool get isUsable {
    final code = (postcode ?? '').trim();
    return code.isNotEmpty || (lat != null && lng != null);
  }
}

class LimousineDiscoveryPageData {
  const LimousineDiscoveryPageData({
    this.cards = const <LimousineDiscoveryCard>[],
    this.gatesOff = false,
    this.networkError = false,
  });

  final List<LimousineDiscoveryCard> cards;
  final bool gatesOff;
  final bool networkError;
}

final RegExp _postcodePattern = RegExp(r'(?:^|\D)(\d{4})(?:\D|$)');

const Set<String> _kTaxiOrAirportTokens = <String>{
  'taxi',
  'airport',
  'airport_transfer',
};

String? limousineDiscoveryExtractPostcode(String raw) {
  final match = _postcodePattern.firstMatch(raw.trim());
  return match?.group(1);
}

LimousineDiscoveryQuery? limousineDiscoveryQueryFromAddress({
  required String displayText,
  double? lat,
  double? lon,
}) {
  if (lat != null && lon != null && lat.isFinite && lon.isFinite) {
    return LimousineDiscoveryQuery(lat: lat, lng: lon);
  }
  final postcode = limousineDiscoveryExtractPostcode(displayText);
  if (postcode != null) {
    return LimousineDiscoveryQuery(postcode: postcode);
  }
  return null;
}

bool limousineDiscoveryResponseIsGatesOff(
  int statusCode,
  Map<String, dynamic> body,
) {
  if (looksTruthyPublicFlag(body['gate_off']) ||
      looksTruthyPublicFlag(body['gates_off']) ||
      looksFalseyPublicFlag(body['marketplace_enabled'])) {
    return true;
  }
  final gate = normalizePublicServiceToken(body['limousine_gate']?.toString());
  if (gate == 'off' || gate == 'disabled') return true;
  final error = normalizePublicServiceToken(body['error']?.toString());
  if (error == 'limousine_gate_off' ||
      error == 'marketplace_disabled' ||
      error == 'limousine_disabled') {
    return true;
  }
  return statusCode == 403 && error.contains('limousine');
}

bool limousineDiscoveryPartnerIsTaxiOnly(Map<String, dynamic> partner) {
  if (isWorkerMarkedLimousineEligible(partner)) return false;
  final services = publicServiceTokensFrom(partner['services']);
  if (services.isNotEmpty &&
      services.every(_isTaxiOrAirportToken) &&
      !services.any(isLimousineServiceToken)) {
    return true;
  }
  final vehicles = _discoveryVehicles(partner);
  if (vehicles.isEmpty) return services.any(_isTaxiOrAirportToken);
  return vehicles.every(_isTaxiOrAirportVehicle);
}

bool _isTaxiOrAirportToken(String token) {
  final normalized = normalizePublicServiceToken(token);
  return _kTaxiOrAirportTokens.contains(normalized) ||
      normalized.startsWith('taxi') ||
      normalized.startsWith('airport');
}

bool _isTaxiOrAirportVehicle(Map<String, dynamic> vehicle) {
  return _isTaxiOrAirportToken(
        (vehicle['service_category'] ?? vehicle['serviceCategory'] ?? '')
            .toString(),
      ) ||
      _isTaxiOrAirportToken(
        (vehicle['service'] ?? vehicle['service_id'] ?? '').toString(),
      );
}

bool _recordLooksDraftOrUnpublished(Map<String, dynamic> record) {
  if (looksTruthyPublicFlag(record['draft']) ||
      looksTruthyPublicFlag(record['is_draft']) ||
      looksTruthyPublicFlag(record['preview']) ||
      looksTruthyPublicFlag(record['client_preview'])) {
    return true;
  }
  final status = normalizePublicServiceToken(record['status']?.toString());
  if (status == 'draft' || status == 'unpublished' || status == 'preview') {
    return true;
  }
  if (record.containsKey('published') &&
      looksFalseyPublicFlag(record['published'])) {
    return true;
  }
  if (record.containsKey('enabled') &&
      looksFalseyPublicFlag(record['enabled'])) {
    return true;
  }
  return false;
}

bool _vehicleIsAuthoritativeLimousine(Map<String, dynamic> vehicle) {
  if (_recordLooksDraftOrUnpublished(vehicle)) return false;
  if (looksFalseyPublicFlag(vehicle['is_active']) ||
      looksFalseyPublicFlag(vehicle['isActive'])) {
    return false;
  }
  if (_isTaxiOrAirportVehicle(vehicle)) return false;
  return isLimousineServiceToken(vehicle['service_category']?.toString()) ||
      isLimousineServiceToken(vehicle['serviceCategory']?.toString());
}

List<Map<String, dynamic>> _discoveryVehicles(Map<String, dynamic> partner) {
  for (final key in const [
    'limousine_vehicles',
    'limousineVehicles',
    'vehicles',
    'public_vehicles',
    'publicVehicles',
  ]) {
    final raw = partner[key];
    if (raw is! List) continue;
    return raw.whereType<Map>().map(asStringKeyedMap).toList(growable: false);
  }
  return const <Map<String, dynamic>>[];
}

List<Map<String, dynamic>> _discoveryOffers(Map<String, dynamic> partner) {
  for (final key in const [
    'limousine_offers',
    'limousineOffers',
    'offers',
    'published_offers',
    'publishedOffers',
  ]) {
    final raw = partner[key];
    if (raw is! List) continue;
    return raw.whereType<Map>().map(asStringKeyedMap).toList(growable: false);
  }
  return const <Map<String, dynamic>>[];
}

bool _isValidPublishedLimousineOffer(Map<String, dynamic> offer) {
  if (_recordLooksDraftOrUnpublished(offer)) return false;
  final presentation = limousineOfferToken(
    offer['price_presentation'] ?? offer['pricePresentation'],
  );
  if (presentation == LimousinePricePresentation.unavailable) return false;
  if (presentation == LimousinePricePresentation.quoteRequired ||
      looksTruthyPublicFlag(offer['quote_required'])) {
    return true;
  }
  if (presentation == LimousinePricePresentation.fromPrice ||
      presentation == LimousinePricePresentation.exactFixed ||
      presentation == LimousinePricePresentation.indicative) {
    return true;
  }
  return false;
}

bool _hasAuthoritativeLimousineOffer(Map<String, dynamic> partner) {
  final partnerPresentation = limousineOfferToken(
    partner['limousine_price_presentation'] ??
        partner['limousinePricePresentation'],
  );
  if (partnerPresentation == LimousinePricePresentation.quoteRequired ||
      looksTruthyPublicFlag(partner['price_on_request']) ||
      looksTruthyPublicFlag(partner['quote_required'])) {
    return true;
  }
  for (final offer in _discoveryOffers(partner)) {
    if (_isValidPublishedLimousineOffer(offer)) return true;
  }
  return false;
}

bool _hasAuthoritativeLimousineVehicle(Map<String, dynamic> partner) {
  for (final vehicle in _discoveryVehicles(partner)) {
    if (_vehicleIsAuthoritativeLimousine(vehicle)) return true;
  }
  return false;
}

bool _partnerLooksPublicAndActive(Map<String, dynamic> partner) {
  if (looksFalseyPublicFlag(partner['is_active']) ||
      looksFalseyPublicFlag(partner['isActive'])) {
    return false;
  }
  if (looksTruthyPublicFlag(partner['deleted']) ||
      looksTruthyPublicFlag(partner['is_deleted']) ||
      looksTruthyPublicFlag(partner['suspended'])) {
    return false;
  }
  if (looksFalseyPublicFlag(partner['profile_enabled']) ||
      looksFalseyPublicFlag(partner['profileEnabled'])) {
    return false;
  }
  return true;
}

/// Strict listing gate for the customer discovery page.
///
/// Requires the same nearby/profile payload to prove: worker limousine mark,
/// an active vehicle with service_category=limousine, and a published offer
/// or quote-required capability. Name/brand, services[] alone, draft offers,
/// taxi/airport classification, marketplace-entry define and private
/// operating-base coordinates never include a company.
bool limousineDiscoveryPartnerIsIncludable(Map<String, dynamic> partner) {
  final id = (partner['partner_id'] ?? partner['partnerId'] ?? '')
      .toString()
      .trim();
  if (id.isEmpty) return false;
  if (!_partnerLooksPublicAndActive(partner)) return false;
  if (limousineDiscoveryPartnerIsTaxiOnly(partner)) return false;
  if (!isWorkerMarkedLimousineEligible(partner)) return false;
  if (!_hasAuthoritativeLimousineVehicle(partner)) return false;
  if (!_hasAuthoritativeLimousineOffer(partner)) return false;
  return true;
}

List<LimousineDiscoveryCard> limousineDiscoveryCardsFromNearbyPartners(
  Iterable<dynamic> rawPartners,
) {
  final cards = <LimousineDiscoveryCard>[];
  for (final item in rawPartners) {
    if (item is! Map) continue;
    final card = tryParseLimousineDiscoveryCard(asStringKeyedMap(item));
    if (card != null) cards.add(card);
  }
  return cards;
}

LimousineDiscoveryCard? tryParseLimousineDiscoveryCard(
  Map<String, dynamic> partner,
) {
  if (!limousineDiscoveryPartnerIsIncludable(partner)) return null;
  final id = (partner['partner_id'] ?? partner['partnerId'] ?? '')
      .toString()
      .trim();
  final name =
      (partner['company_name'] ??
              partner['companyName'] ??
              partner['public_trading_name'] ??
              partner['publicTradingName'] ??
              '')
          .toString()
          .trim();
  if (name.isEmpty) return null;
  return LimousineDiscoveryCard(
    publicPartnerId: id,
    companyName: name,
    coverImageUrl: _httpsOnly(
      partner['hero_photo_url'] ??
          partner['heroPhotoUrl'] ??
          partner['cover_image_url'] ??
          partner['coverImageUrl'],
    ),
    logoUrl: _httpsOnly(partner['logo_url'] ?? partner['logoUrl']),
    verifiedPartner: _verifiedPartner(partner),
    publicCity: _publicCity(partner),
    distanceKm: _authoritativeDistanceKm(partner),
    vehicles: _publicLimousineThumbs(partner),
    price: _authoritativePrice(partner),
  );
}

bool _verifiedPartner(Map<String, dynamic> partner) {
  final trust = asStringKeyedMap(partner['trust']);
  return partner['verified_partner'] == true ||
      trust['verified_partner'] == true;
}

String _publicCity(Map<String, dynamic> partner) {
  final coverage = asStringKeyedMap(partner['coverage']);
  for (final value in <Object?>[
    partner['public_city'],
    partner['publicCity'],
    partner['service_region'],
    partner['serviceRegion'],
    coverage['city'],
    coverage['region'],
    coverage['public_city'],
  ]) {
    final text = (value ?? '').toString().trim();
    if (text.isNotEmpty) return text;
  }
  return '';
}

double? _authoritativeDistanceKm(Map<String, dynamic> partner) {
  final raw = partner['distance_km'] ?? partner['distanceKm'];
  if (raw is num && raw.isFinite && raw >= 0) return raw.toDouble();
  return null;
}

List<LimousineDiscoveryVehicleThumb> _publicLimousineThumbs(
  Map<String, dynamic> partner,
) {
  final thumbs = <LimousineDiscoveryVehicleThumb>[];
  for (final vehicle in _discoveryVehicles(partner)) {
    if (!_vehicleIsAuthoritativeLimousine(vehicle)) continue;
    thumbs.add(
      LimousineDiscoveryVehicleThumb(
        photoUrl: _httpsOnly(vehicle['photo_url'] ?? vehicle['photoUrl']),
        serviceClassId: limousineOfferToken(
          vehicle['service_class_id'] ?? vehicle['serviceClassId'],
        ),
        passengerCapacity: _positiveInt(
          vehicle['passenger_capacity'] ??
              vehicle['passengerCapacity'] ??
              vehicle['pax'],
        ),
        luggageCapacity: _positiveInt(
          vehicle['luggage_capacity'] ??
              vehicle['luggageCapacity'] ??
              vehicle['luggage'],
        ),
      ),
    );
    if (thumbs.length == 2) break;
  }
  return thumbs;
}

LimousineDiscoveryPrice _authoritativePrice(Map<String, dynamic> partner) {
  final partnerPresentation = limousineOfferToken(
    partner['limousine_price_presentation'] ??
        partner['limousinePricePresentation'],
  );
  final partnerAmount = _positiveInt(
    partner['display_amount_cents'] ?? partner['displayAmountCents'],
  );
  final partnerCurrency = (partner['currency'] ?? '').toString().trim();
  LimousineDiscoveryPrice? fromPartner;
  if (partnerPresentation.isNotEmpty) {
    fromPartner = _priceFromPresentation(
      partnerPresentation,
      partnerAmount,
      partnerCurrency,
    );
  }

  LimousineDiscoveryPrice? bestOffer;
  for (final offer in _discoveryOffers(partner)) {
    if (!_isValidPublishedLimousineOffer(offer)) continue;
    final parsed = _priceFromPresentation(
      limousineOfferToken(
        offer['price_presentation'] ?? offer['pricePresentation'],
      ),
      _positiveInt(
        offer['display_amount_cents'] ?? offer['displayAmountCents'],
      ),
      (offer['currency'] ?? '').toString().trim(),
    );
    if (parsed == null) continue;
    if (bestOffer == null ||
        (parsed.hasAuthoritativeAmount && !bestOffer.hasAuthoritativeAmount)) {
      bestOffer = parsed;
    }
  }
  return bestOffer ??
      fromPartner ??
      const LimousineDiscoveryPrice(kind: LimousineDiscoveryPriceKind.none);
}

LimousineDiscoveryPrice? _priceFromPresentation(
  String presentation,
  int? amountCents,
  String currency,
) {
  if (presentation == LimousinePricePresentation.quoteRequired) {
    return const LimousineDiscoveryPrice(
      kind: LimousineDiscoveryPriceKind.quoteRequired,
    );
  }
  if (presentation == LimousinePricePresentation.fromPrice) {
    return LimousineDiscoveryPrice(
      kind: LimousineDiscoveryPriceKind.fromPrice,
      amountCents: amountCents,
      currency: currency,
    );
  }
  if (presentation == LimousinePricePresentation.exactFixed) {
    return LimousineDiscoveryPrice(
      kind: LimousineDiscoveryPriceKind.exactFixed,
      amountCents: amountCents,
      currency: currency,
    );
  }
  return null;
}

int? _positiveInt(Object? raw) {
  if (raw is int && raw > 0) return raw;
  if (raw is num && raw > 0) return raw.round();
  final parsed = int.tryParse((raw ?? '').toString().trim());
  if (parsed == null || parsed <= 0) return null;
  return parsed;
}

String _httpsOnly(Object? raw) {
  final text = (raw ?? '').toString().trim();
  if (text.startsWith('https://')) return text;
  return '';
}

String limousineDiscoveryDistanceLabel(
  double kilometers,
  AppLanguage language,
) {
  final rounded = kilometers.round();
  return '$rounded ${kLimousineDiscoveryDistanceFromSearch.of(language)}';
}

String limousineDiscoveryPriceLabel(
  LimousineDiscoveryPrice price,
  AppLanguage language,
) {
  switch (price.kind) {
    case LimousineDiscoveryPriceKind.none:
      return '';
    case LimousineDiscoveryPriceKind.quoteRequired:
      return kLimousineDiscoveryQuoteOnRequest.of(language);
    case LimousineDiscoveryPriceKind.fromPrice:
      if (!price.hasAuthoritativeAmount) return '';
      return '${kLimousineDiscoveryFromPrice.of(language)} ${_formatMoney(price)}';
    case LimousineDiscoveryPriceKind.exactFixed:
      final fixed = kLimousineDiscoveryFixedPrice.of(language);
      if (!price.hasAuthoritativeAmount) return fixed;
      return '$fixed · ${_formatMoney(price)}';
  }
}

String _formatMoney(LimousineDiscoveryPrice price) {
  final amount = (price.amountCents! / 100).toStringAsFixed(
    price.amountCents! % 100 == 0 ? 0 : 2,
  );
  final currency = price.currency.toUpperCase();
  if (currency == 'EUR') return '€$amount';
  return '$amount $currency';
}

String limousineDiscoveryServiceClassLabel(String serviceClassId) {
  final token = limousineOfferToken(serviceClassId);
  if (token.isEmpty) return '';
  return token.replaceAll('_', ' ');
}

bool limousineDiscoveryCardShowsFabricatedSocialProof(String text) {
  final lower = text.toLowerCase();
  return lower.contains('★') ||
      lower.contains('rating') ||
      lower.contains('beoordeling') ||
      lower.contains('reviews') ||
      RegExp(r'\b\d+[.,]\d+\s*\(\d+\)').hasMatch(lower);
}
