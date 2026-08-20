// LIMOUSINE-MARKETPLACE-P2D4C1F — customer discovery listing rules.
// Fail closed on the committed public nearby/profile projection.
// Never infer eligibility from names, drafts, preview state or private bases.

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import '../app_strings.dart';
import 'limousine_customer_discovery_labels.dart';
import 'limousine_customer_quote.dart';
import 'limousine_hero_contract.dart';
import 'limousine_offer_binding.dart';
import 'limousine_pricing_overlay.dart';
import 'limousine_profile_identity.dart';
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
const Key kLimousineDiscoveryRecommendedKey = ValueKey<String>(
  'limousine_discovery_recommended',
);
const Key kLimousineDiscoveryTestEnvironmentKey = ValueKey<String>(
  'limousine_discovery_test_environment',
);

Key limousineDiscoveryCardKey(String partnerId) =>
    ValueKey<String>('limousine_discovery_card_$partnerId');

Key limousineDiscoveryOffersCtaKey(String partnerId) =>
    ValueKey<String>('limousine_discovery_offers_$partnerId');

Key limousineDiscoveryProfileCtaKey(String partnerId) =>
    ValueKey<String>('limousine_discovery_profile_$partnerId');

const Key kLimousineDiscoveryCompanyLogoKey = ValueKey<String>(
  'limousine_discovery_company_logo',
);
const Key kLimousineDiscoveryCompanyNameFallbackKey = ValueKey<String>(
  'limousine_discovery_company_name_fallback',
);

/// Alias for [limousineDiscoveryOffersCtaKey]. Kept so existing discovery
/// tests still press the primary "Bekijk aanbod" action.
Key limousineDiscoveryViewLimousinesCtaKey(String partnerId) =>
    limousineDiscoveryOffersCtaKey(partnerId);

Key limousineDiscoveryCardTitleKey(String partnerId) =>
    ValueKey<String>('limousine_discovery_card_title_$partnerId');

Key limousineDiscoveryCardDescriptionKey(String partnerId) =>
    ValueKey<String>('limousine_discovery_card_description_$partnerId');

Key limousineDiscoveryCardCoverKey(String partnerId) =>
    ValueKey<String>('limousine_discovery_card_cover_$partnerId');

Key limousineDiscoveryCardVehiclesKey(String partnerId) =>
    ValueKey<String>('limousine_discovery_card_vehicles_$partnerId');

Key limousineDiscoveryCardPriceKey(String partnerId) =>
    ValueKey<String>('limousine_discovery_card_price_$partnerId');

/// Visiting-card cover source. Vehicle / gallery photos are never used here.
enum LimousineDiscoveryCoverSource { publishedHero, emptyPlaceholder }

/// P2D4C1F server contract consumed by discovery. Lives on the isolated
/// Worker branch; Flutter never invents these fields locally.
const String kLimousineDiscoveryWorkerContract = '''
GET /partners/nearby?service=limousine
- Unscoped (no postcode/lat/lng) returns allowlisted test-preview companies.
- Region or lat/lng refines the same bounded listing.
- Same three loaders: directory, profiles, booking-routes (max 6 KV gets).
- Fields: limousine_available, public_city/service_region,
  trust.verified_partner, limousine_vehicles[<=2] with
  service_category=limousine, limousine_price_presentation,
  optional display_amount_cents/currency,
  optional distance_km only for geo queries, test_preview,
  limousine_listing_mode=test_preview.
GET /partners/profile projects published limousine_offers when allowlisted.
Do not calculate proximity from private operating-base coordinates.
''';

const String kLimousineDiscoveryMissingWorkerContract =
    kLimousineDiscoveryWorkerContract;

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
    this.publicTitle = const <String, String>{},
    this.publicDescription = const <String, String>{},
    this.coverImageUrl = '',
    this.coverAlignment = Alignment.center,
    this.coverIsExplicit = false,
    this.coverSource = LimousineDiscoveryCoverSource.emptyPlaceholder,
    this.logoUrl = '',
    this.verifiedPartner = false,
    this.publicCity = '',
    this.distanceKm,
    this.vehicles = const <LimousineDiscoveryVehicleThumb>[],
    this.price = const LimousineDiscoveryPrice(
      kind: LimousineDiscoveryPriceKind.none,
    ),
    this.testPreview = false,
    this.logoImage,
  });

  final String publicPartnerId;
  final String companyName;
  final Map<String, String> publicTitle;
  final Map<String, String> publicDescription;
  final String coverImageUrl;
  final Alignment coverAlignment;
  final bool coverIsExplicit;
  final LimousineDiscoveryCoverSource coverSource;
  final String logoUrl;
  final bool verifiedPartner;
  final String publicCity;
  final double? distanceKm;
  final List<LimousineDiscoveryVehicleThumb> vehicles;
  final LimousineDiscoveryPrice price;
  final bool testPreview;
  final ImageProvider? logoImage;

  bool get coverIsPlaceholder =>
      coverSource == LimousineDiscoveryCoverSource.emptyPlaceholder ||
      coverImageUrl.isEmpty;

  LimousineDiscoveryCard copyWith({
    double? distanceKm,
    bool clearDistance = false,
    ImageProvider? logoImage,
  }) {
    return LimousineDiscoveryCard(
      publicPartnerId: publicPartnerId,
      companyName: companyName,
      publicTitle: publicTitle,
      publicDescription: publicDescription,
      coverImageUrl: coverImageUrl,
      coverAlignment: coverAlignment,
      coverIsExplicit: coverIsExplicit,
      coverSource: coverSource,
      logoUrl: logoUrl,
      verifiedPartner: verifiedPartner,
      publicCity: publicCity,
      distanceKm: clearDistance ? null : (distanceKm ?? this.distanceKm),
      vehicles: vehicles,
      price: price,
      testPreview: testPreview,
      logoImage: logoImage ?? this.logoImage,
    );
  }
}

class LimousineDiscoveryQuery {
  const LimousineDiscoveryQuery({this.postcode, this.lat, this.lng});

  final String? postcode;
  final double? lat;
  final double? lng;

  bool get isUnscoped {
    final code = (postcode ?? '').trim();
    return code.isEmpty && lat == null && lng == null;
  }

  bool get isUsable => true;
}

class LimousineDiscoveryPageData {
  const LimousineDiscoveryPageData({
    this.cards = const <LimousineDiscoveryCard>[],
    this.gatesOff = false,
    this.networkError = false,
    this.listingMode = '',
  });

  final List<LimousineDiscoveryCard> cards;
  final bool gatesOff;
  final bool networkError;
  final String listingMode;

  bool get isTestPreview =>
      listingMode.trim().toLowerCase() == 'test_preview' ||
      cards.any((card) => card.testPreview);
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

bool limousineDiscoveryLabelIsPostcodeLed(String value) {
  return RegExp(r'^\d{4}\b').hasMatch(value.trim());
}

LimousineDiscoveryQuery? limousineDiscoveryQueryFromAddress({
  required String displayText,
  double? lat,
  double? lon,
  bool explicitCurrentLocation = false,
}) {
  final hasCoords = lat != null && lon != null && lat.isFinite && lon.isFinite;
  // Explicit "Huidige locatie" always keeps GPS, even if reverse-geocode
  // text happens to contain a Belgian postcode.
  if (explicitCurrentLocation && hasCoords) {
    return LimousineDiscoveryQuery(lat: lat, lng: lon);
  }
  final postcode = limousineDiscoveryExtractPostcode(displayText);
  // Postcode-led selections such as "9688, Maarkedal" or typed "9000 Gent"
  // use the postcode filter. Street-level suggestions with server coords
  // keep GPS so a place pick does not collapse to a private base.
  if (postcode != null && limousineDiscoveryLabelIsPostcodeLed(displayText)) {
    return LimousineDiscoveryQuery(postcode: postcode);
  }
  if (hasCoords) {
    return LimousineDiscoveryQuery(lat: lat, lng: lon);
  }
  if (postcode != null) {
    return LimousineDiscoveryQuery(postcode: postcode);
  }
  return const LimousineDiscoveryQuery();
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

/// Authoritative taxi/airport service token. Never inferred from names.
bool isTaxiOrAirportServiceToken(String? raw) =>
    _isTaxiOrAirportToken(raw ?? '');

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
  return limousinePublicVehicleIsClassified(vehicle);
}

/// Server-authoritative public vehicle. Never inferred from `category`,
/// Premium, name or taxi/airport tokens.
bool limousinePublicVehicleIsClassified(Map<String, dynamic> vehicle) {
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
      partnerPresentation == LimousinePricePresentation.fromPrice ||
      partnerPresentation == LimousinePricePresentation.exactFixed ||
      partnerPresentation == LimousinePricePresentation.indicative ||
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
  partner = limousineHydratePublicPartnerOverlay(partner);
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
  final title = limousineDiscoveryPublishedTitleMap(partner);
  final description = limousineDiscoveryPublishedDescriptionMap(partner);
  if (name.isEmpty && !_localizedHasText(title)) return null;
  final cover = limousineDiscoveryPublishedCover(partner);
  return LimousineDiscoveryCard(
    publicPartnerId: id,
    companyName: name,
    publicTitle: title,
    publicDescription: description,
    coverImageUrl: cover.photoUrl,
    coverAlignment: cover.flutterAlignment,
    coverIsExplicit: cover.explicit,
    coverSource: cover.hasPhoto
        ? LimousineDiscoveryCoverSource.publishedHero
        : LimousineDiscoveryCoverSource.emptyPlaceholder,
    logoUrl: limousineDiscoveryEffectiveLogoUrl(partner),
    verifiedPartner: _verifiedPartner(partner),
    publicCity: _publicCity(partner),
    distanceKm: _authoritativeDistanceKm(partner),
    vehicles: _publicLimousineThumbs(partner),
    price: _authoritativePrice(partner),
    testPreview: partner['test_preview'] == true,
  );
}

bool _localizedHasText(Map<String, String> map) {
  return map.values.any((value) => value.trim().isNotEmpty);
}

Map<String, dynamic> _limousineSectionOf(Map<String, dynamic> partner) {
  final nested = asStringKeyedMap(partner['limousine'] ?? partner['pricing']);
  final merged = nested.isEmpty
      ? Map<String, dynamic>.from(partner)
      : <String, dynamic>{...partner, ...nested};
  final visiting = asStringKeyedMap(
    merged[kLimousinePublishedVisitingCardKey] ??
        merged['publishedLimousineVisitingCard'] ??
        partner[kLimousinePublishedVisitingCardKey],
  );
  if (visiting.isEmpty) return merged;
  if (visiting['public_title'] != null) {
    merged['published_public_title'] = visiting['public_title'];
  }
  if (visiting['public_description'] != null) {
    merged['published_public_description'] = visiting['public_description'];
  }
  if (visiting['cover'] != null) {
    merged[kLimousinePublishedProfileCoverKey] = visiting['cover'];
    merged['published_limousine_hero'] = visiting['cover'];
  }
  if (visiting['logo'] != null) {
    merged[kLimousinePublishedProfileLogoKey] = visiting['logo'];
    merged['published_limousine_logo'] = visiting['logo'];
  }
  return merged;
}

String limousineDiscoveryPublishedLogoOverride(Map<String, dynamic> partner) {
  final source = _limousineSectionOf(partner);
  if (!limousineHasPublishedProfileLogoKey(source)) return '';
  return limousinePublishedLogoFromSection(source).photoUrl;
}

String limousineDiscoveryEffectiveLogoUrl(Map<String, dynamic> partner) {
  final computed = limousineEffectiveLogoUrl(
    overrideUrl: limousineDiscoveryPublishedLogoOverride(partner),
    companyLogoUrl: limousineCompanyLogoUrl(partner),
  );
  if (computed.isNotEmpty) return computed;
  return _httpsOnly(
    partner['limousine_logo_url'] ?? partner['limousineLogoUrl'],
  );
}

Map<String, String> _publishedOrLiveLocalized(
  Map<String, dynamic> partner, {
  required String publishedKey,
  required String liveKey,
}) {
  final source = _limousineSectionOf(partner);
  final hasPublishedKey =
      source.containsKey(publishedKey) ||
      source.containsKey(_camel(publishedKey));
  final published = limousineLocalizedOf(
    source[publishedKey] ?? source[_camel(publishedKey)],
  );
  if (_localizedHasText(published)) return published;
  // An explicit empty published snapshot must not leak a draft working copy.
  if (hasPublishedKey) return published;
  return limousineLocalizedOf(source[liveKey] ?? source[_camel(liveKey)]);
}

String _camel(String snake) {
  final parts = snake.split('_');
  if (parts.length < 2) return snake;
  final rest = parts.skip(1).map((part) {
    if (part.isEmpty) return part;
    return '${part[0].toUpperCase()}${part.substring(1)}';
  }).join();
  return '${parts.first}$rest';
}

Map<String, String> limousineDiscoveryPublishedTitleMap(
  Map<String, dynamic> partner,
) {
  return _publishedOrLiveLocalized(
    partner,
    publishedKey: 'published_public_title',
    liveKey: 'public_title',
  );
}

Map<String, String> limousineDiscoveryPublishedDescriptionMap(
  Map<String, dynamic> partner,
) {
  return _publishedOrLiveLocalized(
    partner,
    publishedKey: 'published_public_description',
    liveKey: 'public_description',
  );
}

String limousineDiscoveryCardTitle(
  LimousineDiscoveryCard card,
  AppLanguage language,
) {
  final localized = limousineDiscoveryLocalizedText(card.publicTitle, language);
  if (localized.isNotEmpty) return localized;
  if (card.companyName.trim().isNotEmpty) return card.companyName.trim();
  return kLimousineDiscoveryCompanyFallback.of(language);
}

String limousineDiscoveryCardDescription(
  LimousineDiscoveryCard card,
  AppLanguage language,
) {
  return limousinePublicCardDescriptionText(
    limousineDiscoveryLocalizedText(card.publicDescription, language),
  );
}

/// Keeps entered paragraphs and line breaks. Only normalizes newlines.
String limousinePublicCardDescriptionText(String raw) {
  return raw.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
}

String limousineDiscoveryLocalizedText(
  Map<String, String> map,
  AppLanguage language,
) {
  return _firstLocalized(map, language);
}

String _firstLocalized(Map<String, String> map, AppLanguage language) {
  final direct = limousineLocalizedFor(map, language).trim();
  if (direct.isNotEmpty) return direct;
  for (final lang in const ['nl', 'en', 'fr', 'es', 'de']) {
    final value = (map[lang] ?? '').trim();
    if (value.isNotEmpty) return value;
  }
  return '';
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
        photoUrl: _httpsOnly(
          vehicle['primary_photo_url'] ??
              vehicle['primaryPhotoUrl'] ??
              vehicle['photo_url'] ??
              vehicle['photoUrl'],
        ),
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
    if (thumbs.length == kLimousineDiscoveryCardVehicleCap) break;
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

  final offerMaps = <Map<String, dynamic>>[
    for (final offer in _discoveryOffers(partner))
      if (_isValidPublishedLimousineOffer(offer)) offer,
  ];
  if (offerMaps.isNotEmpty) {
    return limousineDiscoveryPriceFromOffers(offerMaps);
  }
  return fromPartner ??
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

/// Visiting-card cover from step 3 "Publieke weergave".
///
/// Fallback order (documented product rule):
/// 1. published limousine hero / explicit limousine cover URL
/// 2. empty placeholder — never taxi `hero_photo_url`, never the first
///    vehicle/gallery photo. Those belong on "Bekijk aanbod" and detail.
LimousineHeroSelection limousineDiscoveryPublishedCover(
  Map<String, dynamic> partner,
) {
  final source = _limousineSectionOf(partner);
  final taxiHeroUrls = limousineCollectTaxiHeroUrls(partner)
    ..addAll(limousineCollectTaxiHeroUrls(source));
  final publishedHero = limousinePublishedProfileCoverRaw(source);
  if (limousineHasPublishedProfileCoverKey(source)) {
    final resolved = limousineSanitizeProfileCover(
      _heroFromPublishedValue(publishedHero),
      taxiHeroUrls: taxiHeroUrls,
    );
    if (resolved.hasPhoto) return resolved;
    return const LimousineHeroSelection(
      sourceKind: kLimousineHeroSourceFallback,
    );
  }
  final live = resolveLimousineHero(
    source: <String, dynamic>{...partner, ...source},
  );
  if (live.hasPhoto) return live;
  return const LimousineHeroSelection(sourceKind: kLimousineHeroSourceFallback);
}

LimousineHeroSelection _heroFromPublishedValue(Object? publishedHero) {
  if (publishedHero is Map) {
    return resolveLimousineHero(
      source: <String, dynamic>{
        kLimousineProfileCoverKey: publishedHero,
        'limousine_hero': publishedHero,
      },
    );
  }
  final url = (publishedHero ?? '').toString().trim();
  if (url.startsWith('https://')) {
    return resolveLimousineHero(
      source: <String, dynamic>{'limousine_hero_url': url},
    );
  }
  return const LimousineHeroSelection(sourceKind: kLimousineHeroSourceFallback);
}

/// Discovery cover: published public hero only. Kept as a URL helper for tests.
String limousinePreferredDiscoveryCoverUrl(Map<String, dynamic> partner) {
  return limousineDiscoveryPublishedCover(partner).photoUrl;
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

const String kLimousineSetupPreviewPartnerId = 'setup_preview';
const int kLimousineDiscoveryCardVehicleCap = 2;

/// Settings preview and nearby cards share this view-model.
LimousineDiscoveryCard limousineDiscoveryCardFromSetupPreview({
  required String companyName,
  required String logoUrl,
  required Map<String, String> publicTitle,
  required Map<String, String> publicDescription,
  required LimousineHeroSelection cover,
  List<LimousineDiscoveryVehicleThumb> vehicles =
      const <LimousineDiscoveryVehicleThumb>[],
  LimousineDiscoveryPrice price = const LimousineDiscoveryPrice(
    kind: LimousineDiscoveryPriceKind.none,
  ),
}) {
  return LimousineDiscoveryCard(
    publicPartnerId: kLimousineSetupPreviewPartnerId,
    companyName: companyName,
    publicTitle: publicTitle,
    publicDescription: publicDescription,
    coverImageUrl: cover.photoUrl,
    coverAlignment: cover.flutterAlignment,
    coverIsExplicit: cover.explicit && cover.hasPhoto,
    coverSource: cover.hasPhoto
        ? LimousineDiscoveryCoverSource.publishedHero
        : LimousineDiscoveryCoverSource.emptyPlaceholder,
    logoUrl: logoUrl,
    vehicles: vehicles.length <= kLimousineDiscoveryCardVehicleCap
        ? vehicles
        : vehicles
              .take(kLimousineDiscoveryCardVehicleCap)
              .toList(growable: false),
    price: price,
  );
}

/// Published offers only. An empty list must not invent "quote required".
LimousineDiscoveryPrice limousineDiscoveryPublishedPrice(
  Iterable<Map<String, dynamic>> offers,
) {
  final published = [
    for (final offer in offers)
      if (offer['published'] == true && offer['enabled'] != false)
        Map<String, dynamic>.from(offer),
  ];
  if (published.isEmpty) {
    return const LimousineDiscoveryPrice(
      kind: LimousineDiscoveryPriceKind.none,
    );
  }
  return limousineDiscoveryPriceFromOffers(published);
}

List<LimousineDiscoveryVehicleThumb> limousineDiscoveryVehicleThumbsFromSetup({
  required Iterable<Map<String, dynamic>> vehicles,
}) {
  final thumbs = <LimousineDiscoveryVehicleThumb>[];
  for (final vehicle in vehicles) {
    if (!_vehicleIsAuthoritativeLimousine(vehicle) &&
        !isLimousineServiceToken(
          (vehicle['service_category'] ?? vehicle['serviceCategory'] ?? '')
              .toString(),
        )) {
      continue;
    }
    thumbs.add(
      LimousineDiscoveryVehicleThumb(
        photoUrl: _httpsOnly(
          vehicle['primary_photo_url'] ??
              vehicle['primaryPhotoUrl'] ??
              vehicle['photo_url'] ??
              vehicle['photoUrl'] ??
              vehicle['publicPhotoUrl'],
        ),
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
    if (thumbs.length == kLimousineDiscoveryCardVehicleCap) break;
  }
  return thumbs;
}

String limousineDiscoveryVehicleSummary(
  List<LimousineDiscoveryVehicleThumb> vehicles,
  AppLanguage language,
) {
  if (vehicles.isEmpty) return '';
  final count = vehicles.length;
  final noun = count == 1
      ? kLimousineDiscoveryVehicleOne.of(language)
      : '$count ${kLimousineDiscoveryVehicleMany.of(language)}';
  var maxPax = 0;
  for (final vehicle in vehicles) {
    final pax = vehicle.passengerCapacity ?? 0;
    if (pax > maxPax) maxPax = pax;
  }
  if (maxPax <= 0) return noun;
  return '$noun · ${kLimousineDiscoveryUpTo.of(language)} $maxPax ${kLimousineDiscoveryPassengers.of(language)}';
}

bool limousineDiscoveryCardShowsFabricatedSocialProof(String text) {
  final lower = text.toLowerCase();
  return lower.contains('★') ||
      lower.contains('rating') ||
      lower.contains('beoordeling') ||
      lower.contains('reviews') ||
      RegExp(r'\b\d+[.,]\d+\s*\(\d+\)').hasMatch(lower);
}
