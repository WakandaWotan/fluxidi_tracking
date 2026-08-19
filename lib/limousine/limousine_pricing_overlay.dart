// Local overlay for visiting-card fields and the authoritative published
// offer snapshot. The live booking worker may strip or append these. The
// overlay never writes taxi hero/logo or VehicleProfile fields.

import 'limousine_hero_contract.dart';
import 'limousine_offers.dart';
import 'limousine_pricing_local_store.dart';
import 'limousine_profile_identity.dart';
import 'limousine_vehicle_public_copy.dart';

const String kLimousinePublishedOffersOverlayKey = 'published_limousine_offers';

bool _localizedHasText(Object? raw) {
  return limousineLocalizedOf(raw).values.any((value) => value.trim().isNotEmpty);
}

bool _coverHasPhoto(Object? raw) {
  if (raw is Map) {
    return limousineSanitizeProfileCover(
      limousineHeroFromSection(<String, dynamic>{
        kLimousineProfileCoverKey: raw,
        'limousine_hero': raw,
      }),
    ).hasPhoto;
  }
  final url = (raw ?? '').toString().trim();
  return url.startsWith('https://') &&
      limousineSanitizeProfileCoverUrl(url).isNotEmpty;
}

bool _logoHasPhoto(Object? raw) {
  return limousineLogoFromValue(raw).hasOverride;
}

bool _listHasItems(Object? raw) => raw is List && raw.isNotEmpty;

int _revisionOf(Map<String, dynamic> source) {
  return int.tryParse('${source['source_revision'] ?? 0}') ?? 0;
}

bool _overlayWins({
  required bool overlayHasValue,
  required bool serverHasValue,
  required int overlayRev,
  required int serverRev,
}) {
  if (!overlayHasValue) return false;
  return !serverHasValue || overlayRev >= serverRev;
}

void _takeIfWins(
  Map<String, dynamic> next, {
  required Map<String, dynamic> overlay,
  required String key,
  required bool overlayHasValue,
  required bool serverHasValue,
  required int overlayRev,
  required int serverRev,
}) {
  if (!_overlayWins(
    overlayHasValue: overlayHasValue,
    serverHasValue: serverHasValue,
    overlayRev: overlayRev,
    serverRev: serverRev,
  )) {
    return;
  }
  if (!overlay.containsKey(key)) return;
  next[key] = overlay[key];
}

Map<String, dynamic> limousineMergeVisitingCardOverlay({
  required Map<String, dynamic> section,
  required Map<String, dynamic> overlay,
}) {
  if (overlay.isEmpty) return Map<String, dynamic>.from(section);
  final next = Map<String, dynamic>.from(section);
  final serverRev = _revisionOf(section);
  final overlayRev = _revisionOf(overlay);

  void takeLocalized(String key) {
    _takeIfWins(
      next,
      overlay: overlay,
      key: key,
      overlayHasValue: _localizedHasText(overlay[key]),
      serverHasValue: _localizedHasText(section[key]),
      overlayRev: overlayRev,
      serverRev: serverRev,
    );
  }

  void takeCover(String key) {
    _takeIfWins(
      next,
      overlay: overlay,
      key: key,
      overlayHasValue: _coverHasPhoto(overlay[key]),
      serverHasValue: _coverHasPhoto(section[key]),
      overlayRev: overlayRev,
      serverRev: serverRev,
    );
  }

  void takeLogo(String key) {
    _takeIfWins(
      next,
      overlay: overlay,
      key: key,
      overlayHasValue: _logoHasPhoto(overlay[key]),
      serverHasValue: _logoHasPhoto(section[key]),
      overlayRev: overlayRev,
      serverRev: serverRev,
    );
  }

  void takeCard(String key) {
    final overlayCard = overlay[key];
    final serverCard = section[key];
    final overlayHas = overlayCard is Map &&
        (_localizedHasText(overlayCard['public_title']) ||
            _localizedHasText(overlayCard['public_description']) ||
            _coverHasPhoto(overlayCard['cover']) ||
            _logoHasPhoto(overlayCard['logo']));
    final serverHas = serverCard is Map &&
        (_localizedHasText(serverCard['public_title']) ||
            _localizedHasText(serverCard['public_description']) ||
            _coverHasPhoto(serverCard['cover']) ||
            _logoHasPhoto(serverCard['logo']));
    _takeIfWins(
      next,
      overlay: overlay,
      key: key,
      overlayHasValue: overlayHas,
      serverHasValue: serverHas,
      overlayRev: overlayRev,
      serverRev: serverRev,
    );
  }

  takeLocalized('public_title');
  takeLocalized('public_description');
  takeLocalized('published_public_title');
  takeLocalized('published_public_description');
  takeCover(kLimousineProfileCoverKey);
  takeCover('limousine_hero');
  takeCover(kLimousinePublishedProfileCoverKey);
  takeCover('published_limousine_hero');
  takeLogo(kLimousineProfileLogoKey);
  takeLogo('limousine_logo');
  takeLogo(kLimousinePublishedProfileLogoKey);
  takeLogo('published_limousine_logo');
  takeCard(kLimousineVisitingCardKey);
  takeCard(kLimousinePublishedVisitingCardKey);
  return next;
}

List<Map<String, dynamic>> _offerMapsOf(Object? raw) {
  if (raw is! List) return const <Map<String, dynamic>>[];
  return [
    for (final item in raw)
      if (item is Map)
        Map<String, dynamic>.from(item),
  ];
}

Map<String, dynamic> limousineMergeOffersOverlay({
  required Map<String, dynamic> section,
  required Map<String, dynamic> overlay,
}) {
  final next = Map<String, dynamic>.from(section);
  final overlayOffers = _offerMapsOf(
    overlay[kLimousinePublishedOffersOverlayKey] ?? overlay['offers'],
  );
  if (overlayOffers.isEmpty) return next;
  next['offers'] = overlayOffers;
  next['limousine_offers'] = overlayOffers;
  next[kLimousinePublishedOffersOverlayKey] = overlayOffers;
  return next;
}

Map<String, dynamic> limousineMergePricingOverlay({
  required Map<String, dynamic> section,
  required Map<String, dynamic> overlay,
}) {
  var next = limousineMergeVehiclePublicCopyOverlay(
    section: section,
    overlay: overlay,
  );
  next = limousineMergeVisitingCardOverlay(section: next, overlay: overlay);
  return limousineMergeOffersOverlay(section: next, overlay: overlay);
}

Map<String, dynamic> limousinePublishedVisitingCardOverlayFields({
  required Map<String, dynamic> displayPayload,
  required List<Map<String, dynamic>> publishedOffers,
  required bool updatePublished,
}) {
  final fields = <String, dynamic>{
    'public_title': displayPayload['public_title'],
    'public_description': displayPayload['public_description'],
    kLimousineProfileCoverKey: displayPayload[kLimousineProfileCoverKey],
    'limousine_hero': displayPayload['limousine_hero'],
    kLimousineProfileLogoKey: displayPayload[kLimousineProfileLogoKey],
    'limousine_logo': displayPayload['limousine_logo'],
    kLimousineVisitingCardKey: displayPayload[kLimousineVisitingCardKey],
  };
  if (!updatePublished) return fields;
  fields['published_public_title'] = displayPayload['published_public_title'];
  fields['published_public_description'] =
      displayPayload['published_public_description'];
  fields[kLimousinePublishedProfileCoverKey] =
      displayPayload[kLimousinePublishedProfileCoverKey];
  fields['published_limousine_hero'] = displayPayload['published_limousine_hero'];
  fields[kLimousinePublishedProfileLogoKey] =
      displayPayload[kLimousinePublishedProfileLogoKey];
  fields['published_limousine_logo'] = displayPayload['published_limousine_logo'];
  fields[kLimousinePublishedVisitingCardKey] =
      displayPayload[kLimousinePublishedVisitingCardKey];
  fields[kLimousinePublishedOffersOverlayKey] = [
    for (final offer in publishedOffers) Map<String, dynamic>.from(offer),
  ];
  return fields;
}

Map<String, dynamic> limousineHydratePublicPartnerOverlay(
  Map<String, dynamic> partner, {
  LimousinePricingLocalStore? store,
}) {
  final partnerId = (partner['partner_id'] ?? partner['partnerId'] ?? '')
      .toString()
      .trim();
  final overlay = (store ?? limousinePricingLocalStore).peekMerged(
    limousineDefaultLocalPricingScopeKeys(partnerId: partnerId),
  );
  if (overlay.isEmpty) return Map<String, dynamic>.from(partner);
  var next = limousineMergeVisitingCardOverlay(
    section: partner,
    overlay: overlay,
  );
  next = limousineMergeVehiclePublicCopyOverlay(
    section: next,
    overlay: overlay,
  );
  final overlayOffers = _offerMapsOf(overlay[kLimousinePublishedOffersOverlayKey]);
  if (overlayOffers.isNotEmpty) {
    next['limousine_offers'] = overlayOffers;
    next['offers'] = overlayOffers;
  }
  return next;
}

bool limousineOverlaySectionIsPresent(Map<String, dynamic> section) {
  if (limousineVehiclePublicCopyById(
        section[kLimousineVehiclePublicCopyKey],
      ).isNotEmpty ||
      limousineVehiclePublicCopyById(
        section[kLimousinePublishedVehiclePublicCopyKey],
      ).isNotEmpty) {
    return true;
  }
  if (_localizedHasText(section['public_title']) ||
      _localizedHasText(section['published_public_title']) ||
      _localizedHasText(section['public_description']) ||
      _localizedHasText(section['published_public_description'])) {
    return true;
  }
  if (_coverHasPhoto(section[kLimousineProfileCoverKey]) ||
      _coverHasPhoto(section[kLimousinePublishedProfileCoverKey]) ||
      _coverHasPhoto(section['limousine_hero']) ||
      _coverHasPhoto(section['published_limousine_hero'])) {
    return true;
  }
  if (_logoHasPhoto(section[kLimousineProfileLogoKey]) ||
      _logoHasPhoto(section[kLimousinePublishedProfileLogoKey])) {
    return true;
  }
  return _listHasItems(section[kLimousinePublishedOffersOverlayKey]) ||
      _listHasItems(section['offers']);
}
