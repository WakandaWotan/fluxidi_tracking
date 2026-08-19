// Dedicated limousine company hero. Never the taxi cover, never auto-mixed
// with vehicle galleries after an explicit choice exists.

import 'package:flutter/material.dart';

const String kLimousineHeroSourceUpload = 'upload';
const String kLimousineHeroSourceVehicleMedia = 'vehicle_media';
const String kLimousineHeroSourceFallback = 'fallback';

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

String limousineReadExplicitHeroUrl(Map<String, dynamic> source) {
  final media = _mapOf(source['media']);
  final nested = _mapOf(source['limousine_hero'] ?? source['limousineHero']);
  for (final map in <Map<String, dynamic>>[nested, source, media]) {
    for (final entry in map.entries) {
      if (limousineFieldLooksLikeTaxiCover(entry.key)) continue;
      if (!kLimousineExplicitHeroFieldTokens.contains(_token(entry.key)) &&
          _token(entry.key) != 'photo_url') {
        continue;
      }
      if (_token(entry.key) == 'photo_url' && !identical(map, nested)) {
        continue;
      }
      final url = _httpsOnly(entry.value);
      if (url.isNotEmpty) return url;
    }
  }
  return '';
}

LimousineHeroSelection limousineHeroFromSection(Map<String, dynamic> section) {
  final nested = _mapOf(section['limousine_hero'] ?? section['limousineHero']);
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
        section['limousineHeroAlignment'],
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

/// Profile / showroom / settings hero. Explicit choice wins. Otherwise the
/// first selected limousine primary photo is a temporary fallback. Taxi cover
/// is never used.
LimousineHeroSelection resolveLimousineHero({
  required Map<String, dynamic> source,
  List<String> fallbackVehiclePhotoUrls = const <String>[],
}) {
  final stored = limousineHeroFromSection(source);
  if (stored.hasPhoto) return stored;
  for (final url in fallbackVehiclePhotoUrls) {
    final safe = _httpsOnly(url);
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

String limousineResolvedHeroUrl({
  required Map<String, dynamic> source,
  List<String> fallbackVehiclePhotoUrls = const <String>[],
}) {
  return resolveLimousineHero(
    source: source,
    fallbackVehiclePhotoUrls: fallbackVehiclePhotoUrls,
  ).photoUrl;
}
