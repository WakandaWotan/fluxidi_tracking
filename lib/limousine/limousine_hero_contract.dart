// Dedicated limousine *profile* cover. Never the taxi cover, never mixed
// with vehicle galleries after an explicit choice exists.
//
// Taxi authoritative fields / object:
//   publicHeroPhotoUrl / public_hero_photo_url
//   partner media.hero_photo_url
//   upload media_type company_hero → …/company/hero.{ext}
//
// Limousine authoritative fields / object (schema v1, additive):
//   limousine_profile_cover / published_limousine_profile_cover
//   upload media_type limousine_profile_cover → …/limousine/profile-cover.{ext}
// Legacy aliases (read + write): limousine_hero / published_limousine_hero.
// A URL whose object key is …/company/hero.* is always taxi-owned.

import 'package:flutter/material.dart';

const String kLimousineHeroSourceUpload = 'upload';
const String kLimousineHeroSourceVehicleMedia = 'vehicle_media';
const String kLimousineHeroSourceFallback = 'fallback';

const int kLimousineProfileCoverSchemaVersion = 1;
const String kLimousineProfileCoverKey = 'limousine_profile_cover';
const String kLimousinePublishedProfileCoverKey =
    'published_limousine_profile_cover';
const String kLimousineProfileCoverSchemaKey =
    'limousine_profile_cover_schema';
const String kLimousineProfileCoverMediaType = 'limousine_profile_cover';
const String kLimousineTaxiCompanyHeroMediaType = 'company_hero';

const Set<String> kLimousineHeroAlignments = <String>{
  'center',
  'top',
  'bottom',
  'left',
  'right',
};

const Set<String> kLimousineTaxiCoverFieldTokens = <String>{
  'hero_photo_url',
  'herophotourl',
  'cover_image_url',
  'coverimageurl',
  'public_hero_photo_url',
};

const Set<String> kLimousineExplicitHeroFieldTokens = <String>{
  'limousine_cover_url',
  'limousinecoverurl',
  'limousine_hero_url',
  'limousineherourl',
  'limousine_hero_photo_url',
  'limousineherophotourl',
  'limousine_profile_cover_url',
  'limousineprofilecoverurl',
};

class LimousineHeroSelection {
  const LimousineHeroSelection({
    this.photoUrl = '',
    this.sourceKind = '',
    this.vehicleId = '',
    this.alignment = 'center',
    this.sourceRevision = 0,
    this.explicit = false,
  });

  final String photoUrl;
  final String sourceKind;
  final String vehicleId;
  final String alignment;
  final int sourceRevision;
  final bool explicit;

  bool get hasPhoto => photoUrl.startsWith('https://');

  Alignment get flutterAlignment {
    switch (alignment) {
      case 'top':
        return Alignment.topCenter;
      case 'bottom':
        return Alignment.bottomCenter;
      case 'left':
        return Alignment.centerLeft;
      case 'right':
        return Alignment.centerRight;
      default:
        return Alignment.center;
    }
  }

  Map<String, dynamic> toSectionJson() {
    return <String, dynamic>{
      'photo_url': photoUrl,
      'source_kind': sourceKind,
      'vehicle_id': vehicleId,
      'alignment': alignment,
      'source_revision': sourceRevision,
    };
  }

  LimousineHeroSelection copyWith({
    String? photoUrl,
    String? sourceKind,
    String? vehicleId,
    String? alignment,
    int? sourceRevision,
    bool? explicit,
  }) {
    return LimousineHeroSelection(
      photoUrl: photoUrl ?? this.photoUrl,
      sourceKind: sourceKind ?? this.sourceKind,
      vehicleId: vehicleId ?? this.vehicleId,
      alignment: alignment ?? this.alignment,
      sourceRevision: sourceRevision ?? this.sourceRevision,
      explicit: explicit ?? this.explicit,
    );
  }
}

String _httpsOnly(Object? raw) {
  final text = (raw ?? '').toString().trim();
  return text.startsWith('https://') ? text : '';
}

String _token(Object? raw) => (raw ?? '')
    .toString()
    .trim()
    .toLowerCase()
    .replaceAll(RegExp(r'[\s-]+'), '_');

Map<String, dynamic> _mapOf(Object? raw) {
  if (raw is Map<String, dynamic>) return raw;
  if (raw is Map) return raw.map((key, value) => MapEntry(key.toString(), value));
  return <String, dynamic>{};
}

bool limousineFieldLooksLikeTaxiCover(String fieldName) {
  return kLimousineTaxiCoverFieldTokens.contains(_token(fieldName));
}

/// Object path of a public media URL, query/fragment stripped.
String limousinePublicMediaObjectKey(String url) {
  final parsed = Uri.tryParse(url.trim());
  if (parsed == null || parsed.path.isEmpty) return '';
  var path = parsed.path;
  try {
    path = Uri.decodeFull(path);
  } catch (_) {}
  return path.toLowerCase();
}

/// Durable taxi-object rule: the shared company hero file is never limousine.
bool limousineUrlLooksLikeTaxiCompanyHero(String url) {
  final key = limousinePublicMediaObjectKey(url);
  if (key.isEmpty) return false;
  return key.contains('/company/hero.') || key.endsWith('/company/hero');
}

bool limousineSamePublicMediaObject(String left, String right) {
  final a = limousinePublicMediaObjectKey(left);
  final b = limousinePublicMediaObjectKey(right);
  if (a.isEmpty || b.isEmpty) return false;
  return a == b;
}

List<String> limousineCollectExclusiveCoverUrls(Map<String, dynamic> source) {
  final media = _mapOf(source['media']);
  final nested = _limousineProfileCoverMap(source);
  final published = limousinePublishedProfileCoverRaw(source);
  final publishedMap = published is Map
      ? _mapOf(published)
      : <String, dynamic>{};
  final out = <String>[];
  void add(Object? raw) {
    final url = _httpsOnly(raw);
    if (url.isEmpty || limousineUrlLooksLikeTaxiCompanyHero(url)) return;
    if (out.any((existing) => limousineSamePublicMediaObject(existing, url))) {
      return;
    }
    out.add(url);
  }

  add(nested['photo_url']);
  add(nested['photoUrl']);
  add(publishedMap['photo_url']);
  add(publishedMap['photoUrl']);
  add(published);
  add(source['limousine_hero_url']);
  add(source['limousineHeroUrl']);
  add(source['limousine_cover_url']);
  add(source['limousineCoverUrl']);
  add(source['limousine_profile_cover_url']);
  add(media['limousine_cover_url']);
  add(media['limousineCoverUrl']);
  add(media['limousine_hero_url']);
  add(media['limousine_profile_cover_url']);
  return out;
}

List<String> limousineCollectTaxiHeroUrls(Map<String, dynamic> source) {
  final media = _mapOf(source['media']);
  final exclusive = limousineCollectExclusiveCoverUrls(source);
  final out = <String>[];
  void add(Object? raw) {
    final url = _httpsOnly(raw);
    if (url.isEmpty) return;
    if (!limousineUrlLooksLikeTaxiCompanyHero(url) &&
        exclusive.any((item) => limousineSamePublicMediaObject(item, url))) {
      return;
    }
    if (out.any((existing) => limousineSamePublicMediaObject(existing, url))) {
      return;
    }
    out.add(url);
  }

  add(source['publicHeroPhotoUrl']);
  add(source['public_hero_photo_url']);
  add(source['hero_photo_url']);
  add(source['heroPhotoUrl']);
  add(media['hero_photo_url']);
  add(media['heroPhotoUrl']);
  return out;
}

bool limousineProfileCoverSharesTaxiHero(
  String coverUrl, {
  Iterable<String> taxiHeroUrls = const <String>[],
}) {
  final cover = _httpsOnly(coverUrl);
  if (cover.isEmpty) return false;
  if (limousineUrlLooksLikeTaxiCompanyHero(cover)) return true;
  for (final taxi in taxiHeroUrls) {
    if (limousineSamePublicMediaObject(cover, taxi)) return true;
  }
  return false;
}

String limousineSanitizeProfileCoverUrl(
  String coverUrl, {
  Iterable<String> taxiHeroUrls = const <String>[],
}) {
  final cover = _httpsOnly(coverUrl);
  if (cover.isEmpty) return '';
  if (limousineProfileCoverSharesTaxiHero(cover, taxiHeroUrls: taxiHeroUrls)) {
    return '';
  }
  return cover;
}

LimousineHeroSelection limousineSanitizeProfileCover(
  LimousineHeroSelection cover, {
  Iterable<String> taxiHeroUrls = const <String>[],
}) {
  final photo = limousineSanitizeProfileCoverUrl(
    cover.photoUrl,
    taxiHeroUrls: taxiHeroUrls,
  );
  if (photo == cover.photoUrl) return cover;
  return cover.copyWith(photoUrl: photo, explicit: photo.isNotEmpty);
}

Map<String, dynamic> limousineSanitizeProfileCoverMap(
  Map<String, dynamic> cover, {
  Iterable<String> taxiHeroUrls = const <String>[],
}) {
  final url = _httpsOnly(cover['photo_url'] ?? cover['photoUrl']);
  if (url.isEmpty) return Map<String, dynamic>.from(cover);
  if (limousineProfileCoverSharesTaxiHero(url, taxiHeroUrls: taxiHeroUrls)) {
    final next = Map<String, dynamic>.from(cover);
    next['photo_url'] = '';
    next['photoUrl'] = '';
    return next;
  }
  return Map<String, dynamic>.from(cover);
}

Map<String, dynamic> _limousineProfileCoverMap(Map<String, dynamic> source) {
  final preferred = _mapOf(
    source[kLimousineProfileCoverKey] ?? source['limousineProfileCover'],
  );
  if (preferred.isNotEmpty) return preferred;
  return _mapOf(source['limousine_hero'] ?? source['limousineHero']);
}

Object? limousinePublishedProfileCoverRaw(Map<String, dynamic> source) {
  return source[kLimousinePublishedProfileCoverKey] ??
      source['publishedLimousineProfileCover'] ??
      source['published_limousine_hero'] ??
      source['publishedLimousineHero'];
}

bool limousineHasPublishedProfileCoverKey(Map<String, dynamic> source) {
  return source.containsKey(kLimousinePublishedProfileCoverKey) ||
      source.containsKey('publishedLimousineProfileCover') ||
      source.containsKey('published_limousine_hero') ||
      source.containsKey('publishedLimousineHero');
}

String limousineReadExplicitHeroUrl(Map<String, dynamic> source) {
  final taxiHeroUrls = limousineCollectTaxiHeroUrls(source);
  final media = _mapOf(source['media']);
  final nested = _limousineProfileCoverMap(source);
  for (final map in <Map<String, dynamic>>[nested, source]) {
    for (final entry in map.entries) {
      if (limousineFieldLooksLikeTaxiCover(entry.key)) continue;
      if (!kLimousineExplicitHeroFieldTokens.contains(_token(entry.key)) &&
          _token(entry.key) != 'photo_url') {
        continue;
      }
      if (_token(entry.key) == 'photo_url' && !identical(map, nested)) {
        continue;
      }
      final url = limousineSanitizeProfileCoverUrl(
        _httpsOnly(entry.value),
        taxiHeroUrls: taxiHeroUrls,
      );
      if (url.isNotEmpty) return url;
    }
  }
  // Never fall through to taxi media.hero_photo_url.
  for (final entry in media.entries) {
    if (limousineFieldLooksLikeTaxiCover(entry.key)) continue;
    if (!kLimousineExplicitHeroFieldTokens.contains(_token(entry.key))) {
      continue;
    }
    final url = limousineSanitizeProfileCoverUrl(
      _httpsOnly(entry.value),
      taxiHeroUrls: taxiHeroUrls,
    );
    if (url.isNotEmpty) return url;
  }
  return '';
}

LimousineHeroSelection limousineHeroFromSection(Map<String, dynamic> section) {
  final nested = _limousineProfileCoverMap(section);
  final photo = limousineReadExplicitHeroUrl(section);
  final source = _token(
    nested['source_kind'] ??
        nested['sourceKind'] ??
        section['limousine_hero_source'] ??
        section['limousineHeroSource'],
  );
  final alignment = _token(
    nested['alignment'] ??
        section['limousine_hero_alignment'] ??
        section['limousineHeroAlignment'] ??
        section['alignment'],
  );
  return LimousineHeroSelection(
    photoUrl: photo,
    sourceKind: source == kLimousineHeroSourceVehicleMedia
        ? kLimousineHeroSourceVehicleMedia
        : (photo.isEmpty ? '' : kLimousineHeroSourceUpload),
    vehicleId: (nested['vehicle_id'] ?? nested['vehicleId'] ?? '')
        .toString()
        .trim(),
    alignment: kLimousineHeroAlignments.contains(alignment)
        ? alignment
        : 'center',
    sourceRevision:
        int.tryParse(
          '${nested['source_revision'] ?? nested['sourceRevision'] ?? section['limousine_hero_revision'] ?? 0}',
        ) ??
        0,
    explicit: photo.isNotEmpty,
  );
}

/// Profile / showroom / settings hero. Explicit limousine cover wins.
/// Taxi cover is never used, including the shared company/hero object.
LimousineHeroSelection resolveLimousineHero({
  required Map<String, dynamic> source,
  List<String> fallbackVehiclePhotoUrls = const <String>[],
}) {
  final stored = limousineSanitizeProfileCover(
    limousineHeroFromSection(source),
    taxiHeroUrls: limousineCollectTaxiHeroUrls(source),
  );
  if (stored.hasPhoto) return stored;
  for (final url in fallbackVehiclePhotoUrls) {
    final safe = limousineSanitizeProfileCoverUrl(
      url,
      taxiHeroUrls: limousineCollectTaxiHeroUrls(source),
    );
    if (safe.isNotEmpty) {
      return LimousineHeroSelection(
        photoUrl: safe,
        sourceKind: kLimousineHeroSourceFallback,
        alignment: stored.alignment,
        sourceRevision: stored.sourceRevision,
        explicit: false,
      );
    }
  }
  return stored;
}

/// Limousine pricing document only. Never writes taxi business-profile fields.
Map<String, dynamic> limousineReplacePricingSection({
  required Map<String, dynamic> pricingDocument,
  required Map<String, dynamic> limousineSection,
}) {
  return <String, dynamic>{
    ...pricingDocument,
    'limousine': Map<String, dynamic>.from(limousineSection),
  };
}

/// Taxi business-profile hero only. Never writes limousine cover fields.
Map<String, dynamic> taxiReplaceBusinessHero({
  required Map<String, dynamic> businessProfile,
  required String heroUrl,
}) {
  final next = Map<String, dynamic>.from(businessProfile);
  next['publicHeroPhotoUrl'] = heroUrl;
  next['public_hero_photo_url'] = heroUrl;
  next.remove(kLimousineProfileCoverKey);
  next.remove(kLimousinePublishedProfileCoverKey);
  next.remove('limousine_hero');
  next.remove('published_limousine_hero');
  next.remove('limousine_profile_logo');
  next.remove('published_limousine_profile_logo');
  next.remove('limousine_logo');
  next.remove('published_limousine_logo');
  return next;
}

Map<String, dynamic> taxiPublishedPartnerMedia({
  required String heroUrl,
  String logoUrl = '',
}) {
  return <String, dynamic>{
    'logo_url': logoUrl,
    'hero_photo_url': heroUrl,
    'gallery': const <String>[],
  };
}

String limousineResolvedHeroUrl({
  required Map<String, dynamic> source,
  List<String> fallbackVehiclePhotoUrls = const <String>[],
}) {
  return resolveLimousineHero(
    source: source,
    fallbackVehiclePhotoUrls: fallbackVehiclePhotoUrls,
  ).photoUrl;
}

/// Public limousine pages read the published snapshot only.
LimousineHeroSelection limousineResolvePublishedProfileCover({
  required Map<String, dynamic> source,
  List<String> fallbackVehiclePhotoUrls = const <String>[],
}) {
  if (!limousineHasPublishedProfileCoverKey(source)) {
    return resolveLimousineHero(
      source: source,
      fallbackVehiclePhotoUrls: fallbackVehiclePhotoUrls,
    );
  }
  final published = limousinePublishedProfileCoverRaw(source);
  final fromSnapshot = published is Map
      ? limousineHeroFromSection(<String, dynamic>{
          kLimousineProfileCoverKey: published,
          'limousine_hero': published,
        })
      : limousineHeroFromSection(<String, dynamic>{
          'limousine_hero_url': published,
        });
  final sanitized = limousineSanitizeProfileCover(
    fromSnapshot,
    taxiHeroUrls: limousineCollectTaxiHeroUrls(source),
  );
  if (sanitized.hasPhoto) return sanitized;
  for (final url in fallbackVehiclePhotoUrls) {
    final safe = limousineSanitizeProfileCoverUrl(
      url,
      taxiHeroUrls: limousineCollectTaxiHeroUrls(source),
    );
    if (safe.isNotEmpty) {
      return LimousineHeroSelection(
        photoUrl: safe,
        sourceKind: kLimousineHeroSourceFallback,
        alignment: sanitized.alignment,
        sourceRevision: sanitized.sourceRevision,
        explicit: false,
      );
    }
  }
  return sanitized;
}
