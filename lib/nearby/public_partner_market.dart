// Explicit customer-market context for public partner catalogs.
// Taxi/airport and limousine stay separate even when one company offers both.

import 'package:flutter/widgets.dart';

import '../limousine/limousine_customer_discovery.dart';
import '../limousine/limousine_hero_contract.dart';
import '../limousine/limousine_provider_showroom.dart';
import '../limousine/limousine_service_capability.dart';

enum PublicPartnerMarket { taxi, airport, limousine }

const String kPublicPartnerMarketQueryKey = 'market';
const String kPublicPartnerProfilePath = '/partners/profile';

const Key kPublicPartnerProfileVehiclesSectionKey = ValueKey<String>(
  'public_partner_profile_vehicles',
);
const Key kPublicPartnerProfileServicesSectionKey = ValueKey<String>(
  'public_partner_profile_services',
);
const Key kPublicPartnerProfilePaymentsSectionKey = ValueKey<String>(
  'public_partner_profile_payments',
);

Key publicPartnerProfilePageKey(PublicPartnerMarket market) =>
    ValueKey<String>('public_partner_profile_${market.name}');

Key publicPartnerProfileVehicleKey(String vehicleId) =>
    ValueKey<String>('public_partner_profile_vehicle_$vehicleId');

class PublicPartnerMarketCatalog {
  const PublicPartnerMarketCatalog({
    required this.market,
    required this.vehicles,
    required this.services,
    required this.heroPhotoUrl,
    required this.gallery,
    required this.showLimousineOffers,
    required this.limousineVehicleIds,
  });

  final PublicPartnerMarket market;
  final List<Map<String, dynamic>> vehicles;
  final List<String> services;
  final String heroPhotoUrl;
  final List<String> gallery;
  final bool showLimousineOffers;
  final Set<String> limousineVehicleIds;

  bool get hasVehicles => vehicles.isNotEmpty;
  bool get hasServices => services.isNotEmpty;
}

PublicPartnerMarket parsePublicPartnerMarket(
  Object? raw, {
  PublicPartnerMarket fallback = PublicPartnerMarket.taxi,
}) {
  final token = normalizePublicServiceToken(raw?.toString());
  switch (token) {
    case 'airport':
    case 'airport_transfer':
    case 'airport_service':
      return PublicPartnerMarket.airport;
    case 'limousine':
    case 'limousine_service':
      return PublicPartnerMarket.limousine;
    case 'taxi':
    case 'taxi_vvb':
      return PublicPartnerMarket.taxi;
    default:
      return fallback;
  }
}

PublicPartnerMarket publicPartnerMarketFromUri(
  Uri uri, {
  PublicPartnerMarket fallback = PublicPartnerMarket.taxi,
}) {
  return parsePublicPartnerMarket(
    uri.queryParameters[kPublicPartnerMarketQueryKey] ??
        uri.queryParameters['public_market'],
    fallback: fallback,
  );
}

String publicPartnerMarketRouteName({
  required String partnerId,
  required PublicPartnerMarket market,
}) {
  return Uri(
    path: kPublicPartnerProfilePath,
    queryParameters: <String, String>{
      'partner_id': partnerId.trim(),
      kPublicPartnerMarketQueryKey: market.name,
    },
  ).toString();
}

RouteSettings publicPartnerMarketRouteSettings({
  required String partnerId,
  required PublicPartnerMarket market,
}) {
  return RouteSettings(
    name: publicPartnerMarketRouteName(partnerId: partnerId, market: market),
  );
}

String publicPartnerVehicleId(Map<String, dynamic> vehicle) {
  for (final key in const [
    'vehicle_id',
    'vehicleId',
    'public_vehicle_id',
    'publicVehicleId',
    'id',
  ]) {
    final id = (vehicle[key] ?? '').toString().trim();
    if (id.isNotEmpty) return id;
  }
  return '';
}

bool publicPartnerVehicleAssignedToLimousine(Map<String, dynamic> vehicle) {
  return isLimousineServiceToken(vehicle['service_category']?.toString()) ||
      isLimousineServiceToken(vehicle['serviceCategory']?.toString());
}

Set<String> publicPartnerLimousineAssignedVehicleIds(
  Map<String, dynamic> profile,
) {
  final ids = <String>{};
  for (final key in const ['limousine_vehicles', 'limousineVehicles']) {
    final raw = profile[key];
    if (raw is! List) continue;
    for (final item in raw) {
      if (item is! Map) continue;
      final id = publicPartnerVehicleId(asStringKeyedMap(item));
      if (id.isNotEmpty) ids.add(id);
    }
  }
  for (final vehicle in limousinePublicVehicleRecords(profile)) {
    if (!publicPartnerVehicleAssignedToLimousine(vehicle) &&
        !limousinePublicVehicleIsClassified(vehicle)) {
      continue;
    }
    final id = publicPartnerVehicleId(vehicle);
    if (id.isNotEmpty) ids.add(id);
  }
  return ids;
}

List<Map<String, dynamic>> publicPartnerTaxiCatalogVehicles(
  Map<String, dynamic> profile,
) {
  final assigned = publicPartnerLimousineAssignedVehicleIds(profile);
  final out = <Map<String, dynamic>>[];
  final seen = <String>{};
  for (final key in const ['vehicles', 'public_vehicles', 'publicVehicles']) {
    final raw = profile[key];
    if (raw is! List) continue;
    for (final item in raw) {
      if (item is! Map) continue;
      final vehicle = asStringKeyedMap(item);
      final id = publicPartnerVehicleId(vehicle);
      final fingerprint = id.isNotEmpty
          ? id
          : [
              vehicle['name'] ?? '',
              vehicle['photo_url'] ?? vehicle['photoUrl'] ?? '',
            ].join('|');
      if (!seen.add(fingerprint)) continue;
      if (id.isNotEmpty && assigned.contains(id)) continue;
      if (publicPartnerVehicleAssignedToLimousine(vehicle)) continue;
      if (limousinePublicVehicleIsClassified(vehicle)) continue;
      out.add(vehicle);
    }
  }
  return out;
}

List<Map<String, dynamic>> publicPartnerLimousineCatalogVehicles(
  Map<String, dynamic> profile,
) {
  return [
    for (final vehicle in limousinePublicVehicleRecords(profile))
      if (limousinePublicVehicleIsClassified(vehicle)) vehicle,
  ];
}

Set<String> publicPartnerLimousineMediaUrls(Map<String, dynamic> profile) {
  final urls = <String>{};
  void addUrl(Object? raw) {
    final url = (raw ?? '').toString().trim();
    if (url.startsWith('https://')) urls.add(url);
  }

  addUrl(limousineReadExplicitHeroUrl(profile));
  for (final vehicle in limousinePublicVehicleRecords(profile)) {
    if (!publicPartnerVehicleAssignedToLimousine(vehicle) &&
        !limousinePublicVehicleIsClassified(vehicle)) {
      continue;
    }
    addUrl(
      vehicle['primary_photo_url'] ??
          vehicle['primaryPhotoUrl'] ??
          vehicle['photo_url'] ??
          vehicle['photoUrl'] ??
          vehicle['public_photo_url'] ??
          vehicle['publicPhotoUrl'],
    );
    for (final key in const [
      'gallery_photo_urls',
      'galleryPhotoUrls',
      'gallery',
    ]) {
      final raw = vehicle[key];
      if (raw is! List) continue;
      for (final item in raw) {
        addUrl(item);
      }
    }
  }
  return urls;
}

String publicPartnerTaxiHeroUrl(Map<String, dynamic> profile) {
  final media = asStringKeyedMap(profile['media']);
  for (final raw in <Object?>[
    media['hero_photo_url'],
    media['heroPhotoUrl'],
    profile['hero_photo_url'],
    profile['heroPhotoUrl'],
  ]) {
    final url = (raw ?? '').toString().trim();
    if (!url.startsWith('https://')) continue;
    if (publicPartnerLimousineMediaUrls(profile).contains(url)) return '';
    return url;
  }
  return '';
}

List<String> publicPartnerTaxiGallery(Map<String, dynamic> profile) {
  final media = asStringKeyedMap(profile['media']);
  final raw = media['gallery'];
  if (raw is! List) return const <String>[];
  final blocked = publicPartnerLimousineMediaUrls(profile);
  return [
    for (final item in raw)
      if ((item ?? '').toString().trim().startsWith('https://') &&
          !blocked.contains(item.toString().trim()))
        item.toString().trim(),
  ];
}

bool publicPartnerHasTaxiActivation(Map<String, dynamic> partner) {
  if (publicServiceTokensFrom(
    partner['services'],
  ).any(isTaxiOrAirportServiceToken)) {
    return true;
  }
  for (final value in <Object?>[
    partner['taxi_service_enabled'],
    partner['taxiServiceEnabled'],
  ]) {
    if (looksTruthyPublicFlag(value)) return true;
  }
  final booking = asStringKeyedMap(partner['booking_capabilities']);
  for (final value in <Object?>[booking['taxi'], booking['taxi_vvb']]) {
    if (looksTruthyPublicFlag(value)) return true;
  }
  return false;
}

bool publicPartnerAppearsInTaxiSearch(Map<String, dynamic> partner) {
  if (publicPartnerHasTaxiActivation(partner)) return true;
  if (publicPartnerTaxiCatalogVehicles(partner).isNotEmpty) return true;
  final services = publicServiceTokensFrom(partner['services']);
  if (services.isNotEmpty && services.every(isLimousineServiceToken)) {
    return false;
  }
  final limousineOnly =
      publicPartnerLimousineAssignedVehicleIds(partner).isNotEmpty &&
      publicPartnerTaxiCatalogVehicles(partner).isEmpty &&
      (looksTruthyPublicFlag(partner['limousine_available']) ||
          looksTruthyPublicFlag(partner['limousine_service_enabled']) ||
          partnerHasExplicitLimousineCapability(partner));
  if (services.isEmpty && limousineOnly) return false;
  return true;
}

bool _isAirportServiceToken(String token) {
  final normalized = normalizePublicServiceToken(token);
  return normalized == 'airport' ||
      normalized == 'airport_transfer' ||
      normalized == 'airport_service' ||
      normalized == 'airportservice';
}

List<String> selectPublicPartnerMarketServices({
  required Iterable<String> services,
  required PublicPartnerMarket market,
  required bool airportServiceEnabled,
}) {
  return [
    for (final service in services)
      if (_keepMarketService(
        service,
        market: market,
        airportServiceEnabled: airportServiceEnabled,
      ))
        service,
  ];
}

bool _keepMarketService(
  String service, {
  required PublicPartnerMarket market,
  required bool airportServiceEnabled,
}) {
  if (isLimousineServiceToken(service)) {
    return market == PublicPartnerMarket.limousine;
  }
  if (market == PublicPartnerMarket.limousine) return false;
  if (_isAirportServiceToken(service) &&
      !airportServiceEnabled &&
      market != PublicPartnerMarket.airport) {
    return false;
  }
  return true;
}

/// Shared public-profile selector. Apply this before building sections.
PublicPartnerMarketCatalog selectPublicPartnerMarketCatalog({
  required Map<String, dynamic> profile,
  required PublicPartnerMarket market,
  bool airportServiceEnabled = true,
}) {
  final services = selectPublicPartnerMarketServices(
    services: publicServiceTokensFrom(profile['services']),
    market: market,
    airportServiceEnabled: airportServiceEnabled,
  );
  if (market == PublicPartnerMarket.limousine) {
    final hero = resolveLimousineHero(source: profile);
    return PublicPartnerMarketCatalog(
      market: market,
      vehicles: publicPartnerLimousineCatalogVehicles(profile),
      services: services,
      heroPhotoUrl: hero.photoUrl,
      gallery: const <String>[],
      showLimousineOffers: true,
      limousineVehicleIds: publicPartnerLimousineAssignedVehicleIds(profile),
    );
  }
  return PublicPartnerMarketCatalog(
    market: market,
    vehicles: publicPartnerTaxiCatalogVehicles(profile),
    services: services,
    heroPhotoUrl: publicPartnerTaxiHeroUrl(profile),
    gallery: publicPartnerTaxiGallery(profile),
    showLimousineOffers: false,
    limousineVehicleIds: publicPartnerLimousineAssignedVehicleIds(profile),
  );
}

/// UI defense-in-depth: drop limousine records that slipped into a taxi payload.
List<Map<String, dynamic>> publicPartnerSafeTaxiVehicles(
  Iterable<Map<String, dynamic>> vehicles, {
  required Set<String> limousineVehicleIds,
}) {
  return [
    for (final vehicle in vehicles)
      if (!publicPartnerVehicleAssignedToLimousine(vehicle) &&
          !limousinePublicVehicleIsClassified(vehicle) &&
          !limousineVehicleIds.contains(publicPartnerVehicleId(vehicle)))
        vehicle,
  ];
}

List<String> publicPartnerSafeTaxiServices(Iterable<String> services) {
  return [
    for (final service in services)
      if (!isLimousineServiceToken(service)) service,
  ];
}
