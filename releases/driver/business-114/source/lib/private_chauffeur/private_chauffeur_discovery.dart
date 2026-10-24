// Company cards for Privéchauffeur.
// Nearby still applies region, visibility and account status. This layer only
// keeps companies that explicitly offer private_chauffeur. It never invents a
// fare and never relabels a taxi or limousine company.

import '../limousine/limousine_customer_discovery.dart';
import '../limousine/limousine_service_capability.dart';
import 'private_chauffeur_capability.dart';

class PrivateChauffeurDiscoveryPageData {
  const PrivateChauffeurDiscoveryPageData({
    this.cards = const <LimousineDiscoveryCard>[],
    this.needPlace = false,
    this.networkError = false,
  });

  final List<LimousineDiscoveryCard> cards;
  final bool needPlace;
  final bool networkError;
}

List<LimousineDiscoveryCard> privateChauffeurCardsFromNearbyPartners(
  Iterable<dynamic> rawPartners,
) {
  final cards = <LimousineDiscoveryCard>[];
  for (final item in rawPartners) {
    if (item is! Map) continue;
    final card = tryParsePrivateChauffeurCard(asStringKeyedMap(item));
    if (card != null) cards.add(card);
  }
  return cards;
}

LimousineDiscoveryCard? tryParsePrivateChauffeurCard(
  Map<String, dynamic> partner,
) {
  if (!privateChauffeurPartnerIsListable(partner)) return null;
  final id = privateChauffeurPartnerId(partner);
  final name = privateChauffeurCompanyName(partner);
  if (name.isEmpty) return null;
  final hero = _https(partner['hero_photo_url'] ?? partner['heroPhotoUrl']);
  final logo = _https(partner['logo_url'] ?? partner['logoUrl']);
  return LimousineDiscoveryCard(
    publicPartnerId: id,
    companyName: name,
    publicCity: _city(partner),
    logoUrl: logo,
    coverImageUrl: hero,
    coverSource: hero.isEmpty
        ? LimousineDiscoveryCoverSource.emptyPlaceholder
        : LimousineDiscoveryCoverSource.publishedHero,
    distanceKm: _distance(partner['distance_km'] ?? partner['distanceKm']),
    price: const LimousineDiscoveryPrice(
      kind: LimousineDiscoveryPriceKind.none,
    ),
  );
}

String _https(Object? raw) {
  final text = (raw ?? '').toString().trim();
  if (text.startsWith('https://')) return text;
  return '';
}

String _city(Map<String, dynamic> partner) {
  for (final value in <Object?>[
    partner['public_city'],
    partner['publicCity'],
    partner['service_region'],
    partner['serviceRegion'],
  ]) {
    final text = (value ?? '').toString().trim();
    if (text.isNotEmpty) return text;
  }
  return '';
}

double? _distance(Object? raw) {
  if (raw is num && raw.isFinite && raw >= 0) return raw.toDouble();
  final parsed = double.tryParse((raw ?? '').toString().trim());
  if (parsed == null || !parsed.isFinite || parsed < 0) return null;
  return parsed;
}
