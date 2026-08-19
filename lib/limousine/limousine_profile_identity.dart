// Dedicated limousine *profile* identity: title, description, cover, logo.
// Never written into the taxi profile, taxi snapshot, vehicle records or
// galleries. The company logo is a read-only fallback for the mark only.

import 'limousine_hero_contract.dart';

const int kLimousineProfileLogoSchemaVersion = 1;
const String kLimousineProfileLogoKey = 'limousine_profile_logo';
const String kLimousinePublishedProfileLogoKey =
    'published_limousine_profile_logo';
const String kLimousineProfileLogoSchemaKey = 'limousine_profile_logo_schema';
const String kLimousineProfileLogoMediaType = 'limousine_profile_logo';
const String kLimousineTaxiCompanyLogoMediaType = 'company_logo';
const String kLimousineVisitingCardKey = 'limousine_visiting_card';
const String kLimousinePublishedVisitingCardKey =
    'published_limousine_visiting_card';

class LimousineProfileLogoSelection {
  const LimousineProfileLogoSelection({
    this.photoUrl = '',
    this.sourceRevision = 0,
    this.explicitOverride = false,
  });

  final String photoUrl;
  final int sourceRevision;
  final bool explicitOverride;

  bool get hasOverride =>
      explicitOverride && photoUrl.startsWith('https://');

  Map<String, dynamic> toSectionJson() {
    return <String, dynamic>{
      'photo_url': photoUrl,
      'source_revision': sourceRevision,
      'explicit_override': explicitOverride,
    };
  }

  LimousineProfileLogoSelection copyWith({
    String? photoUrl,
    int? sourceRevision,
    bool? explicitOverride,
  }) {
    return LimousineProfileLogoSelection(
      photoUrl: photoUrl ?? this.photoUrl,
      sourceRevision: sourceRevision ?? this.sourceRevision,
      explicitOverride: explicitOverride ?? this.explicitOverride,
    );
  }
}

String _httpsOnly(Object? raw) {
  final text = (raw ?? '').toString().trim();
  return text.startsWith('https://') ? text : '';
}

Map<String, dynamic> _mapOf(Object? raw) {
  if (raw is Map<String, dynamic>) return raw;
  if (raw is Map) {
    return raw.map((key, value) => MapEntry(key.toString(), value));
  }
  return <String, dynamic>{};
}

bool limousineUrlLooksLikeTaxiCompanyLogo(String url) {
  final key = limousinePublicMediaObjectKey(url);
  if (key.isEmpty) return false;
  return key.contains('/company/logo.') || key.endsWith('/company/logo');
}

/// Override URL only. A company/logo object is never stored as the override.
String limousineSanitizeProfileLogoOverrideUrl(String logoUrl) {
  final url = _httpsOnly(logoUrl);
  if (url.isEmpty) return '';
  if (limousineUrlLooksLikeTaxiCompanyHero(url)) return '';
  if (limousineUrlLooksLikeTaxiCompanyLogo(url)) return '';
  return url;
}

Map<String, dynamic> limousineSanitizeProfileLogoMap(Map<String, dynamic> logo) {
  final url = limousineSanitizeProfileLogoOverrideUrl(
    _httpsOnly(logo['photo_url'] ?? logo['photoUrl']),
  );
  final next = Map<String, dynamic>.from(logo);
  next['photo_url'] = url;
  next['photoUrl'] = url;
  next['explicit_override'] = url.isNotEmpty;
  return next;
}

LimousineProfileLogoSelection limousineSanitizeProfileLogo(
  LimousineProfileLogoSelection logo,
) {
  final url = limousineSanitizeProfileLogoOverrideUrl(logo.photoUrl);
  if (url == logo.photoUrl && logo.explicitOverride == url.isNotEmpty) {
    return logo;
  }
  return logo.copyWith(photoUrl: url, explicitOverride: url.isNotEmpty);
}

Object? limousinePublishedProfileLogoRaw(Map<String, dynamic> source) {
  return source[kLimousinePublishedProfileLogoKey] ??
      source['publishedLimousineProfileLogo'] ??
      source['published_limousine_logo'] ??
      source['publishedLimousineLogo'];
}

bool limousineHasPublishedProfileLogoKey(Map<String, dynamic> source) {
  return source.containsKey(kLimousinePublishedProfileLogoKey) ||
      source.containsKey('publishedLimousineProfileLogo') ||
      source.containsKey('published_limousine_logo') ||
      source.containsKey('publishedLimousineLogo');
}

LimousineProfileLogoSelection limousineLogoFromValue(Object? raw) {
  if (raw is Map) {
    final map = _mapOf(raw);
    final url = limousineSanitizeProfileLogoOverrideUrl(
      _httpsOnly(map['photo_url'] ?? map['photoUrl'] ?? map['url']),
    );
    final revision =
        int.tryParse('${map['source_revision'] ?? map['sourceRevision'] ?? 0}') ??
        0;
    return LimousineProfileLogoSelection(
      photoUrl: url,
      sourceRevision: revision,
      explicitOverride: url.isNotEmpty,
    );
  }
  final url = limousineSanitizeProfileLogoOverrideUrl(_httpsOnly(raw));
  return LimousineProfileLogoSelection(
    photoUrl: url,
    explicitOverride: url.isNotEmpty,
  );
}

LimousineProfileLogoSelection limousineLogoFromSection(
  Map<String, dynamic> section,
) {
  final nested = _mapOf(
    section[kLimousineProfileLogoKey] ??
        section['limousineProfileLogo'] ??
        section['limousine_logo'] ??
        section['limousineLogo'],
  );
  if (nested.isNotEmpty) return limousineLogoFromValue(nested);
  final flat = limousineSanitizeProfileLogoOverrideUrl(
    _httpsOnly(
      section['limousine_logo_override_url'] ??
          section['limousineLogoOverrideUrl'],
    ),
  );
  return LimousineProfileLogoSelection(
    photoUrl: flat,
    explicitOverride: flat.isNotEmpty,
  );
}

LimousineProfileLogoSelection limousinePublishedLogoFromSection(
  Map<String, dynamic> section,
) {
  if (!limousineHasPublishedProfileLogoKey(section)) {
    return const LimousineProfileLogoSelection();
  }
  return limousineLogoFromValue(limousinePublishedProfileLogoRaw(section));
}

String limousineCompanyLogoUrl(Map<String, dynamic> source) {
  final media = _mapOf(source['media']);
  for (final raw in <Object?>[
    source['logo_url'],
    source['logoUrl'],
    source['publicLogoUrl'],
    source['public_logo_url'],
    media['logo_url'],
    media['logoUrl'],
  ]) {
    final url = _httpsOnly(raw);
    if (url.isEmpty) continue;
    if (limousineUrlLooksLikeTaxiCompanyHero(url)) continue;
    return url;
  }
  return '';
}

/// Effective limousine mark: override wins, otherwise the general company
/// logo is used read-only. Never copies the company logo into the override.
String limousineEffectiveLogoUrl({
  required String overrideUrl,
  required String companyLogoUrl,
}) {
  final override = limousineSanitizeProfileLogoOverrideUrl(overrideUrl);
  if (override.isNotEmpty) return override;
  final company = _httpsOnly(companyLogoUrl);
  if (company.isEmpty) return '';
  if (limousineUrlLooksLikeTaxiCompanyHero(company)) return '';
  return company;
}

bool limousineLogoFallbackMutatesOverride({
  required Map<String, dynamic> workingLogo,
  required String companyLogoUrl,
}) {
  final stored = limousineSanitizeProfileLogoOverrideUrl(
    _httpsOnly(workingLogo['photo_url'] ?? workingLogo['photoUrl']),
  );
  final company = _httpsOnly(companyLogoUrl);
  if (stored.isEmpty || company.isEmpty) return false;
  return limousineSamePublicMediaObject(stored, company);
}

/// Taxi / general company logo only. Never writes a limousine override.
Map<String, dynamic> taxiReplaceBusinessLogo({
  required Map<String, dynamic> businessProfile,
  required String logoUrl,
}) {
  final next = Map<String, dynamic>.from(businessProfile);
  next['publicLogoUrl'] = logoUrl;
  next['public_logo_url'] = logoUrl;
  next.remove(kLimousineProfileLogoKey);
  next.remove(kLimousinePublishedProfileLogoKey);
  next.remove('limousine_logo');
  next.remove('published_limousine_logo');
  return next;
}

Map<String, dynamic> limousinePublishedSnapshotOrPrevious({
  required bool publishSucceeded,
  required Map<String, dynamic> incomingPublished,
  required Map<String, dynamic> previousPublished,
}) {
  if (!publishSucceeded) {
    return Map<String, dynamic>.from(previousPublished);
  }
  return Map<String, dynamic>.from(incomingPublished);
}
