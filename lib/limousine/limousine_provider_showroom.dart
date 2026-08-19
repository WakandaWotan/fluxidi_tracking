// Public limousine showroom / detail projection. Reads only the already
// loaded partner profile. Never uses taxi covers, taxi vehicles or private
// fleet fields. Transaction gates stay fail-closed.

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import '../app_strings.dart';
import '../nearby/public_partner_identity.dart';
import '../vehicle_gallery_contract.dart';
import 'limousine_customer_discovery.dart';
import 'limousine_customer_discovery_labels.dart';
import 'limousine_hero_contract.dart';
import 'limousine_offer_binding.dart';
import 'limousine_offers.dart';
import 'limousine_public_showroom.dart';
import 'limousine_customer_quote.dart';
import 'limousine_service_capability.dart';

const String kLimousineCustomerQuoteGateDefineKey = 'LIMOUSINE_QUOTE_ENABLED';
const String kLimousineCustomerManualQuoteGateDefineKey =
    'LIMOUSINE_MANUAL_QUOTE_ENABLED';
const String kLimousineCustomerBookGateDefineKey = 'LIMOUSINE_BOOK_ENABLED';

const bool kLimousineCustomerQuoteGateEnabled = bool.fromEnvironment(
  kLimousineCustomerQuoteGateDefineKey,
  defaultValue: false,
);
const bool kLimousineCustomerManualQuoteGateEnabled = bool.fromEnvironment(
  kLimousineCustomerManualQuoteGateDefineKey,
  defaultValue: false,
);
const bool kLimousineCustomerBookGateEnabled = bool.fromEnvironment(
  kLimousineCustomerBookGateDefineKey,
  defaultValue: false,
);

bool limousineCustomerQuoteCtaEnabled({
  bool quoteGate = kLimousineCustomerQuoteGateEnabled,
  bool manualQuoteGate = kLimousineCustomerManualQuoteGateEnabled,
}) {
  return quoteGate || manualQuoteGate;
}

bool limousineCustomerBookCtaEnabled({
  bool bookGate = kLimousineCustomerBookGateEnabled,
}) {
  return bookGate;
}

const Key kLimousineProviderShowroomPageKey = ValueKey<String>(
  'limousine_provider_showroom_page',
);
const Key kLimousineProviderShowroomHeroKey = ValueKey<String>(
  'limousine_provider_showroom_hero',
);
const Key kLimousineProviderShowroomCatalogKey = ValueKey<String>(
  'limousine_provider_showroom_catalog',
);
const Key kLimousineProviderShowroomEmptyKey = ValueKey<String>(
  'limousine_provider_showroom_empty',
);
const Key kLimousineVehicleDetailPageKey = ValueKey<String>(
  'limousine_vehicle_detail_page',
);
const Key kLimousineDetailQuoteCtaKey = ValueKey<String>(
  'limousine_vehicle_detail_quote_cta',
);
const Key kLimousineDetailBookCtaKey = ValueKey<String>(
  'limousine_vehicle_detail_book_cta',
);
const Key kLimousineDetailGateOffBannerKey = ValueKey<String>(
  'limousine_vehicle_detail_gate_off',
);
const Key kLimousineDetailGalleryKey = ValueKey<String>(
  'limousine_vehicle_detail_gallery',
);
const Key kLimousineDetailGalleryPrevKey = ValueKey<String>(
  'limousine_vehicle_detail_gallery_prev',
);
const Key kLimousineDetailGalleryNextKey = ValueKey<String>(
  'limousine_vehicle_detail_gallery_next',
);
const Key kLimousineDetailGalleryCounterKey = ValueKey<String>(
  'limousine_vehicle_detail_gallery_counter',
);
const Key kLimousineDetailGalleryThumbsKey = ValueKey<String>(
  'limousine_vehicle_detail_gallery_thumbs',
);
const Key kLimousinePublicProfilePageKey = ValueKey<String>(
  'limousine_public_profile_page',
);
const Key kLimousinePublicProfileHeroKey = ValueKey<String>(
  'limousine_public_profile_hero',
);
const Key kLimousinePublicProfileOffersCtaKey = ValueKey<String>(
  'limousine_public_profile_offers_cta',
);
const Key kLimousinePublicProfileFleetKey = ValueKey<String>(
  'limousine_public_profile_fleet',
);
const Key kLimousineDetailPricesSectionKey = ValueKey<String>(
  'limousine_vehicle_detail_prices',
);
const Key kLimousineDetailCompanyLogoKey = ValueKey<String>(
  'limousine_vehicle_detail_company_logo',
);
const Key kLimousineDetailCompanyNameFallbackKey = ValueKey<String>(
  'limousine_vehicle_detail_company_name_fallback',
);
const Key kLimousineDetailVehicleTitleKey = ValueKey<String>(
  'limousine_vehicle_detail_vehicle_title',
);
const Key kLimousineDetailComfortSectionKey = ValueKey<String>(
  'limousine_vehicle_detail_comfort',
);
const Key kLimousineDetailOfferKindEyebrowKey = ValueKey<String>(
  'limousine_vehicle_detail_offer_kind',
);
const Key kLimousineDetailOfferPriceKey = ValueKey<String>(
  'limousine_vehicle_detail_offer_price',
);

Key limousineDetailOfferCardKey(String offerId) =>
    ValueKey<String>('limousine_vehicle_detail_offer_$offerId');
const Key kLimousineShowroomCompanyProfileCtaKey = ValueKey<String>(
  'limousine_showroom_company_profile_cta',
);

Key limousineShowroomVehicleCardKey(String vehicleKey) =>
    ValueKey<String>('limousine_showroom_vehicle_$vehicleKey');

Key limousineShowroomMoreInfoCtaKey(String vehicleKey) =>
    ValueKey<String>('limousine_showroom_more_info_$vehicleKey');

const Set<String> kLimousineShowroomForbiddenKeys = <String>{
  'tenant_id',
  'company_id',
  'license_plate',
  'vin',
  'driver_id',
  'operating_base',
  'operating_base_address',
  'base_address',
};

const Set<String> kLimousineTaxiCoverKeys = <String>{
  'hero_photo_url',
  'herophotourl',
  'cover_image_url',
  'coverimageurl',
  'public_hero_photo_url',
};

const Set<String> kLimousineExplicitCoverKeys = <String>{
  'limousine_cover_url',
  'limousinecoverurl',
  'limousine_hero_url',
  'limousineherourl',
  'limousine_hero_photo_url',
};

class LimousineShowroomVehicle {
  const LimousineShowroomVehicle({
    required this.key,
    this.name = '',
    this.brandModel = '',
    this.serviceClassId = '',
    this.photoUrls = const <String>[],
    this.passengerCapacity,
    this.luggageCapacity,
    this.features = const <String>[],
    this.color = '',
    this.length = '',
    this.vehicleId = '',
    this.offers = const <LimousinePublishedOffer>[],
  });

  final String key;
  final String name;
  final String brandModel;
  final String serviceClassId;
  final List<String> photoUrls;
  final int? passengerCapacity;
  final int? luggageCapacity;
  final List<String> features;
  final String color;
  final String length;
  final String vehicleId;
  final List<LimousinePublishedOffer> offers;

  String get displayName {
    if (name.trim().isNotEmpty) return name.trim();
    if (brandModel.trim().isNotEmpty) return brandModel.trim();
    return '';
  }

  String get primaryPhotoUrl => photoUrls.isEmpty ? '' : photoUrls.first;

  LimousinePublishedOffer? get primaryOffer =>
      limousineSelectSummaryOffer(offers);
}

class LimousineProviderShowroomData {
  const LimousineProviderShowroomData({
    required this.partnerId,
    required this.companyName,
    this.logoUrl = '',
    this.tagline = '',
    this.description = '',
    this.verifiedPartner = false,
    this.distanceKm,
    this.heroPhotoUrl = '',
    this.heroIsExplicit = false,
    this.heroAlignment = Alignment.center,
    this.vehicles = const <LimousineShowroomVehicle>[],
  });

  final String partnerId;
  final String companyName;
  final String logoUrl;
  final String tagline;
  final String description;
  final bool verifiedPartner;
  final double? distanceKm;
  final String heroPhotoUrl;
  final bool heroIsExplicit;
  final Alignment heroAlignment;
  final List<LimousineShowroomVehicle> vehicles;
}

String _httpsOnly(Object? raw) {
  final text = (raw ?? '').toString().trim();
  if (text.startsWith('https://')) return text;
  return '';
}

int? _positiveInt(Object? raw) {
  if (raw is int && raw > 0) return raw;
  if (raw is num && raw > 0) return raw.round();
  final parsed = int.tryParse((raw ?? '').toString().trim());
  if (parsed == null || parsed <= 0) return null;
  return parsed;
}

bool limousineShowroomPayloadLeaksPrivate(Map<String, dynamic> raw) {
  for (final key in raw.keys) {
    if (kLimousineShowroomForbiddenKeys.contains(
      normalizePublicServiceToken(key),
    )) {
      return true;
    }
  }
  return false;
}

bool limousineUrlLooksLikeTaxiCoverField(String fieldName) {
  return kLimousineTaxiCoverKeys.contains(
    normalizePublicServiceToken(fieldName),
  );
}

String limousineExplicitCoverUrl(Map<String, dynamic> source) {
  final media = asStringKeyedMap(source['media']);
  for (final map in <Map<String, dynamic>>[source, media]) {
    for (final entry in map.entries) {
      if (!kLimousineExplicitCoverKeys.contains(
        normalizePublicServiceToken(entry.key),
      )) {
        continue;
      }
      final url = _httpsOnly(entry.value);
      if (url.isNotEmpty) return url;
    }
  }
  return '';
}

String limousinePreferredCoverUrl({
  required Map<String, dynamic> source,
  required List<String> limousineVehiclePhotoUrls,
}) {
  return limousineResolvedHeroUrl(
    source: source,
    fallbackVehiclePhotoUrls: limousineVehiclePhotoUrls,
  );
}

List<Map<String, dynamic>> limousinePublicVehicleRecords(
  Map<String, dynamic> profile,
) {
  final out = <Map<String, dynamic>>[];
  final seen = <String>{};
  for (final key in const [
    'limousine_vehicles',
    'limousineVehicles',
    'vehicles',
    'public_vehicles',
    'publicVehicles',
  ]) {
    final raw = profile[key];
    if (raw is! List) continue;
    for (final item in raw) {
      if (item is! Map) continue;
      final map = asStringKeyedMap(item);
      final fingerprint = [
        map['vehicle_id'] ?? map['vehicleId'] ?? '',
        map['photo_url'] ?? map['photoUrl'] ?? '',
        map['name'] ?? '',
        map['service_class'] ?? map['service_class_id'] ?? '',
      ].join('|');
      if (!seen.add(fingerprint)) continue;
      out.add(map);
    }
  }
  return out;
}

LimousineShowroomVehicle? tryParseLimousineShowroomVehicle(
  Map<String, dynamic> vehicle, {
  required int index,
}) {
  if (!limousinePublicVehicleIsClassified(vehicle)) return null;
  final vehicleId = (vehicle['vehicle_id'] ?? vehicle['vehicleId'] ?? '')
      .toString()
      .trim();
  final name = (vehicle['name'] ?? '').toString().trim();
  final brand = (vehicle['brand_model'] ?? vehicle['brandModel'] ?? '')
      .toString()
      .trim();
  final serviceClass = limousineOfferToken(
    vehicle['service_class'] ??
        vehicle['serviceClass'] ??
        vehicle['service_class_id'] ??
        vehicle['serviceClassId'],
  );
  final primaryUrl = _httpsOnly(
    vehicle['primary_photo_url'] ??
        vehicle['primaryPhotoUrl'] ??
        vehicle['photo_url'] ??
        vehicle['photoUrl'] ??
        vehicle['public_photo_url'] ??
        vehicle['publicPhotoUrl'],
  );
  final galleryRaw = <Object?>[];
  for (final key in const [
    'gallery_photo_urls',
    'galleryPhotoUrls',
    'gallery',
    'photos',
  ]) {
    final raw = vehicle[key];
    if (raw is! List) continue;
    galleryRaw.addAll(raw);
  }
  final photos = orderPublicVehicleGalleryUrls(
    primaryUrl: primaryUrl,
    galleryUrls: [for (final item in galleryRaw) _httpsOnly(item)],
  );
  final features = <String>[];
  final rawFeatures = vehicle['features'];
  if (rawFeatures is List) {
    for (final item in rawFeatures) {
      final text = item.toString().trim();
      if (text.isEmpty) continue;
      if (kLimousineShowroomForbiddenKeys.contains(
        normalizePublicServiceToken(text),
      )) {
        continue;
      }
      features.add(text);
    }
  }
  final key = vehicleId.isNotEmpty
      ? vehicleId
      : 'vehicle_${index}_${serviceClass}_${photos.isEmpty ? name : photos.first}';
  return LimousineShowroomVehicle(
    key: key,
    name: name,
    brandModel: brand,
    serviceClassId: serviceClass,
    photoUrls: photos.toList(growable: false),
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
    features: features,
    color: (vehicle['color'] ?? '').toString().trim(),
    length:
        (vehicle['length'] ??
                vehicle['length_m'] ??
                vehicle['vehicle_length'] ??
                vehicle['vehicleLength'] ??
                '')
            .toString()
            .trim(),
    vehicleId: vehicleId,
  );
}

List<LimousinePublishedOffer> _offersForVehicle({
  required LimousineShowroomVehicle vehicle,
  required List<LimousinePublishedOffer> offers,
  required Iterable<String> selectedVehicleIds,
}) {
  final matched = <LimousinePublishedOffer>[];
  for (final offer in offers) {
    if (!limousinePublishedOfferAppliesToVehicle(
      offer: offer,
      vehicleId: vehicle.vehicleId,
      selectedVehicleIds: selectedVehicleIds,
    )) {
      continue;
    }
    matched.add(offer);
  }
  return limousineSortPublishedOffers(matched);
}

LimousineProviderShowroomData buildLimousineProviderShowroomData({
  required Map<String, dynamic> profile,
  String partnerIdFallback = '',
  String companyNameFallback = '',
  double? distanceKm,
  LimousineDiscoveryCard? discoveryCard,
  AppLanguage language = AppLanguage.nl,
}) {
  final partnerId =
      (profile['partner_id'] ?? profile['partnerId'] ?? partnerIdFallback)
          .toString()
          .trim();
  final publishedTitle = limousineDiscoveryLocalizedText(
    limousineDiscoveryPublishedTitleMap(profile),
    language,
  ).trim();
  final companyName = publishedTitle.isNotEmpty
      ? publishedTitle
      : sanitizePublicPartnerBrandName(
          (profile['company_name'] ??
                  profile['companyName'] ??
                  companyNameFallback)
              .toString(),
        );
  final media = asStringKeyedMap(profile['media']);
  final logoUrl = _httpsOnly(
    profile['logo_url'] ??
        profile['logoUrl'] ??
        media['logo_url'] ??
        media['logoUrl'],
  );
  final publishedDescription = limousineDiscoveryLocalizedText(
    limousineDiscoveryPublishedDescriptionMap(profile),
    language,
  );
  final tagline = publishedDescription.isNotEmpty
      ? publishedDescription
      : (profile['tagline'] ?? '').toString().trim();
  final description = (profile['about_short'] ?? profile['aboutShort'] ?? '')
      .toString()
      .trim();
  final trust = asStringKeyedMap(profile['trust']);
  final verified =
      profile['verified_partner'] == true || trust['verified_partner'] == true;
  final offers = collectLimousineShowroomOffers(profile);
  final parsed = <LimousineShowroomVehicle>[];
  final records = limousinePublicVehicleRecords(profile);
  for (var i = 0; i < records.length; i++) {
    final vehicle = tryParseLimousineShowroomVehicle(records[i], index: i);
    if (vehicle != null) parsed.add(vehicle);
  }
  if (parsed.isEmpty && discoveryCard != null) {
    for (var i = 0; i < discoveryCard.vehicles.length; i++) {
      final thumb = discoveryCard.vehicles[i];
      parsed.add(
        LimousineShowroomVehicle(
          key: 'discovery_$i',
          serviceClassId: thumb.serviceClassId,
          photoUrls: thumb.photoUrl.isEmpty
              ? const <String>[]
              : <String>[thumb.photoUrl],
          passengerCapacity: thumb.passengerCapacity,
          luggageCapacity: thumb.luggageCapacity,
        ),
      );
    }
  }
  final selectedIds = [
    for (final vehicle in parsed)
      if (vehicle.vehicleId.isNotEmpty) vehicle.vehicleId,
  ];
  final vehicles = [
    for (final vehicle in parsed)
      LimousineShowroomVehicle(
        key: vehicle.key,
        name: vehicle.name,
        brandModel: vehicle.brandModel,
        serviceClassId: vehicle.serviceClassId,
        photoUrls: vehicle.photoUrls,
        passengerCapacity: vehicle.passengerCapacity,
        luggageCapacity: vehicle.luggageCapacity,
        features: vehicle.features,
        color: vehicle.color,
        length: vehicle.length,
        vehicleId: vehicle.vehicleId,
        offers: _offersForVehicle(
          vehicle: vehicle,
          offers: offers,
          selectedVehicleIds: selectedIds,
        ),
      ),
  ];
  final hero = resolveLimousineHero(
    source: profile,
    fallbackVehiclePhotoUrls: [
      for (final vehicle in vehicles)
        if (vehicle.primaryPhotoUrl.isNotEmpty) vehicle.primaryPhotoUrl,
    ],
  );
  return LimousineProviderShowroomData(
    partnerId: partnerId,
    companyName: companyName,
    logoUrl: logoUrl,
    tagline: tagline,
    description: description,
    verifiedPartner: verified,
    distanceKm: distanceKm ?? _positiveDouble(profile['distance_km']),
    heroPhotoUrl: hero.photoUrl,
    heroIsExplicit: hero.explicit,
    heroAlignment: hero.flutterAlignment,
    vehicles: vehicles,
  );
}

double? _positiveDouble(Object? raw) {
  if (raw is num && raw.isFinite && raw >= 0) return raw.toDouble();
  return null;
}

String limousineShowroomVehiclePriceLabel(
  LimousineShowroomVehicle vehicle,
  AppLanguage language,
) {
  final summary = limousineSelectSummaryOffer(vehicle.offers);
  if (summary == null) {
    return kLimousineDiscoveryQuoteOnRequest.of(language);
  }
  final price = limousineFormatPublishedOfferPrice(summary, language);
  final extra = limousineShowroomOffersExtraLabel(
    vehicle.offers.length - 1,
    language,
  );
  if (extra.isEmpty) return price;
  return '$price · $extra';
}

LimousineShowroomCta limousineDetailCtaFor(LimousinePublishedOffer? offer) {
  if (offer == null) return LimousineShowroomCta.none;
  return limousineShowroomCtaFor(offer);
}
