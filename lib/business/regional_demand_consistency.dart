/// RELEASE-P0-PRIVACY-WEB-LOCALE-AND-DEMAND-RADAR-CONSISTENCY
///
/// Pure helpers for Demand Radar / Vraagradar regional consistency.
/// No Flutter imports — unit-testable without widget plumbing.
library;

/// Normalized country code (2-letter ISO), defaulting to BE when empty.
String normalizeDemandRadarCountry(String raw) {
  final cleaned = raw.trim().toUpperCase().replaceAll(RegExp(r'[^A-Z]'), '');
  if (cleaned.length >= 2) return cleaned.substring(0, 2);
  return 'BE';
}

/// Normalize a regional postcode for radar queries.
///
/// Belgian (and similar numeric) postcodes often arrive as
/// `"9688 Schorisse"` or `"B-9688"`. Those must collide with `"9688"`,
/// otherwise two companies in the same town query different KV keys and
/// see divergent counts (0+ vs 3+).
///
/// Rules:
/// 1. Uppercase, strip whitespace.
/// 2. If a leading 4-digit block exists (BE-style), keep only those digits.
/// 3. Otherwise keep A–Z / 0–9 only.
String normalizeDemandRadarPostcode(String raw) {
  final cleaned = raw.trim().toUpperCase().replaceAll(RegExp(r'\s+'), '');
  if (cleaned.isEmpty) return '';
  final beDigits = RegExp(r'(\d{4})').firstMatch(cleaned);
  if (beDigits != null) return beDigits.group(1)!;
  return cleaned.replaceAll(RegExp(r'[^A-Z0-9]'), '');
}

/// Parse a raw served-postcode field into unique normalized codes.
List<String> parseDemandRadarServedPostcodes(String raw) {
  final seen = <String>{};
  final out = <String>[];
  for (final token in raw.split(RegExp(r'[,;\n\r\s]+'))) {
    final code = normalizeDemandRadarPostcode(token);
    if (code.isEmpty || seen.contains(code)) continue;
    seen.add(code);
    out.add(code);
  }
  return out;
}

/// Build the ordered postcode query list: primary first, then served.
/// Cap at [limit] to keep request volume bounded.
List<String> buildDemandRadarPostcodeQueryList({
  required String primaryRaw,
  required String servedRaw,
  int limit = 50,
}) {
  final primary = normalizeDemandRadarPostcode(primaryRaw);
  final seen = <String>{};
  final out = <String>[];
  if (primary.isNotEmpty) {
    seen.add(primary);
    out.add(primary);
  }
  for (final code in parseDemandRadarServedPostcodes(servedRaw)) {
    if (seen.contains(code)) continue;
    seen.add(code);
    out.add(code);
  }
  if (out.length <= limit) return List<String>.unmodifiable(out);
  return List<String>.unmodifiable(out.take(limit));
}

/// Regional aggregation cache key. Intentionally excludes language, device,
/// and company/tenant — the product count is a public regional aggregate.
String demandRadarRegionCacheKey({
  required String country,
  required String postcode,
  required int radiusKm,
  String datasetVersion = 'region_interest_v1',
  String snapshotId = '',
}) {
  final c = normalizeDemandRadarCountry(country);
  final p = normalizeDemandRadarPostcode(postcode);
  final r = radiusKm.clamp(1, 100);
  final snap = snapshotId.trim();
  final snapPart = snap.isEmpty ? 'live' : snap;
  return '$datasetVersion|$c|$p|r$r|$snapPart';
}

/// Mask a tenant/company id for PII-free diagnostics (short stable hash-ish).
String maskDemandRadarTenantId(String raw) {
  final value = raw.trim();
  if (value.isEmpty) return 'none';
  var hash = 0;
  for (final unit in value.codeUnits) {
    hash = (hash * 31 + unit) & 0x7fffffff;
  }
  final hex = hash.toRadixString(16).padLeft(8, '0');
  return 't_${hex.substring(0, 8)}';
}

enum DemandRadarCountSource { network, cache, unavailable }

/// Result of deciding what the hero total should show.
class DemandRadarHeroTotal {
  const DemandRadarHeroTotal({
    required this.available,
    required this.count,
    required this.source,
    this.stale = false,
    this.cacheAgeSeconds,
  });

  final bool available;
  final int count;
  final DemandRadarCountSource source;
  final bool stale;
  final int? cacheAgeSeconds;

  /// Numeric `N+` only when a successful response exists (including true zero).
  String displayCountOrEmpty() {
    if (!available) return '';
    return '${count.clamp(0, 999999)}+';
  }
}

/// Decide the hero total from a list of per-postcode fetch outcomes.
///
/// Product rule: the hero reflects the **primary region** aggregate so two
/// companies with the same normalized primary postcode + radius + snapshot
/// see the same number. Served-postcode rows remain visible in the list but
/// must not silently inflate the hero.
///
/// - Primary row successful (count may be 0) → show `N+`
/// - Primary missing/unavailable and no successful primary → unavailable
/// - Empty query list → unavailable
DemandRadarHeroTotal decideDemandRadarHeroTotal({
  required String primaryPostcode,
  required List<({String postcode, int count, bool unavailable})> rows,
}) {
  final primary = normalizeDemandRadarPostcode(primaryPostcode);
  if (primary.isEmpty || rows.isEmpty) {
    return const DemandRadarHeroTotal(
      available: false,
      count: 0,
      source: DemandRadarCountSource.unavailable,
    );
  }
  for (final row in rows) {
    if (normalizeDemandRadarPostcode(row.postcode) != primary) continue;
    if (row.unavailable) {
      return const DemandRadarHeroTotal(
        available: false,
        count: 0,
        source: DemandRadarCountSource.unavailable,
      );
    }
    return DemandRadarHeroTotal(
      available: true,
      count: row.count.clamp(0, 999999),
      source: DemandRadarCountSource.network,
    );
  }
  return const DemandRadarHeroTotal(
    available: false,
    count: 0,
    source: DemandRadarCountSource.unavailable,
  );
}

/// Localized "data currently unavailable" copy. Language-only; never affects
/// counts or cache keys.
String demandRadarUnavailableLabel(String languageCode) {
  switch (languageCode.trim().toLowerCase()) {
    case 'en':
      return 'Data currently unavailable';
    case 'fr':
      return 'Données momentanément indisponibles';
    case 'es':
      return 'Datos no disponibles temporalmente';
    case 'nl':
    default:
      return 'Gegevens momenteel niet beschikbaar';
  }
}

/// Row display for a single postcode: never show `0+` on failure.
String demandRadarRowDisplayCount({
  required bool unavailable,
  required int count,
  required String languageCode,
  String? serverDisplayCount,
}) {
  if (unavailable) return demandRadarUnavailableLabel(languageCode);
  final raw = (serverDisplayCount ?? '').trim();
  if (raw.isNotEmpty) return raw;
  return '${count.clamp(0, 999999)}+';
}

/// Bounded PII-free diagnostic line for logs / field triage.
String formatDemandRadarDiag({
  required String correlationId,
  required String country,
  required String postcode,
  required int radiusKm,
  required int? httpStatus,
  required DemandRadarCountSource source,
  required bool cacheHit,
  int? cacheAgeSeconds,
  String? companyId,
  String? snapshotId,
}) {
  final region = normalizeDemandRadarPostcode(postcode);
  final maskedRegion = region.isEmpty
      ? 'none'
      : (region.length <= 2
          ? '**'
          : '${region.substring(0, 2)}**');
  final tenant = maskDemandRadarTenantId(companyId ?? '');
  final status = httpStatus?.toString() ?? 'none';
  final age = cacheAgeSeconds?.toString() ?? 'n/a';
  final snap = (snapshotId ?? '').trim().isEmpty ? 'live' : snapshotId!.trim();
  return '[DEMAND_RADAR_DIAG] corr=$correlationId '
      'region=$maskedRegion country=${normalizeDemandRadarCountry(country)} '
      'radius=$radiusKm status=$status snap=$snap '
      'cache=${cacheHit ? 'hit' : 'miss'} age_s=$age '
      'source=${source.name} tenant=$tenant';
}
