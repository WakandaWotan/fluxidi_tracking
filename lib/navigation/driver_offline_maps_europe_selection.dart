// FLUXIDI-OFFLINE-MAPS-EUROPE-REGION-EXPANSION-P0-1
//
// Pure selection / geometry helpers for Europe-wide offline basemap downloads.
// Reuses [DriverOfflineMapsService] / TileRegion ownership — does not create a
// second offline stack. Administrative polygons are not assumed exact; the
// first release uses a truthful center + radius bounding box.

import 'dart:math' as math;

import 'driver_offline_maps_service.dart';

/// Approximate operational Europe envelope (includes nearby islands / cross-border
/// fringe). Selection centers outside this envelope are rejected.
const double kDriverOfflineEuropeWestLon = -31.5;
const double kDriverOfflineEuropeSouthLat = 34.0;
const double kDriverOfflineEuropeEastLon = 45.0;
const double kDriverOfflineEuropeNorthLat = 72.0;

/// Practical radius choices (km). Continent-scale downloads are rejected.
const List<int> kDriverOfflineEuropeRadiusOptionsKm = <int>[10, 20, 40, 60];
const int kDriverOfflineEuropeDefaultRadiusKm = 20;
const int kDriverOfflineEuropeMinRadiusKm = 5;
const int kDriverOfflineEuropeMaxRadiusKm = 80;

/// Hard cap on approximate download area (km²). A 80 km radius is ~20 100 km².
const double kDriverOfflineEuropeMaxAreaKm2 = 22000.0;

/// Street-detail zoom for custom Europe downloads (matches existing detail presets).
const int kDriverOfflineEuropeDetailMinZoom = kDriverOfflineMapsDefaultMinZoom;
const int kDriverOfflineEuropeDetailMaxZoom = kDriverOfflineMapsDefaultMaxZoom;

/// Legacy preset slugs that must remain recognized / manageable.
const Set<String> kDriverOfflineLegacyPresetSlugs = <String>{
  'belgium_base',
  'maarkedal_vlaamse_ardennen',
  'brussels_test',
};

/// A geocoded European place candidate (PII-light: no customer data).
class DriverOfflineEuropePlace {
  final String primaryName;
  final String countryCode;
  final String countryName;
  final double latitude;
  final double longitude;
  final String mapboxFeatureId;
  final String placeType;

  const DriverOfflineEuropePlace({
    required this.primaryName,
    required this.countryCode,
    required this.countryName,
    required this.latitude,
    required this.longitude,
    this.mapboxFeatureId = '',
    this.placeType = 'place',
  });

  /// User-visible label that disambiguates same city names across countries.
  String get displayLabel {
    final country = countryName.trim().isNotEmpty
        ? countryName.trim()
        : countryCode.toUpperCase();
    return '$primaryName, $country';
  }
}

/// A concrete download selection: place + radius → geometry + region id.
class DriverOfflineEuropeSelection {
  final DriverOfflineEuropePlace place;
  final int radiusKm;
  final int minZoom;
  final int maxZoom;

  const DriverOfflineEuropeSelection({
    required this.place,
    required this.radiusKm,
    this.minZoom = kDriverOfflineEuropeDetailMinZoom,
    this.maxZoom = kDriverOfflineEuropeDetailMaxZoom,
  });

  String get displayName =>
      '${place.displayLabel} · $radiusKm km';

  String get slug => driverOfflineEuropeRegionSlug(
        place: place,
        radiusKm: radiusKm,
        minZoom: minZoom,
        maxZoom: maxZoom,
      );

  String get regionId => driverOfflineMapRegionId(
        slug: slug,
        minZoom: minZoom,
        maxZoom: maxZoom,
      );

  Map<String, dynamic> get geometry =>
      driverOfflineEuropeRadiusBboxGeometry(
        latitude: place.latitude,
        longitude: place.longitude,
        radiusKm: radiusKm,
      );

  DriverOfflineMapRegionRequest toRegionRequest({bool wifiOnly = true}) {
    return DriverOfflineMapRegionRequest(
      displayName: displayName,
      slug: slug,
      geometry: geometry,
      minZoom: minZoom,
      maxZoom: maxZoom,
      wifiOnly: wifiOnly,
    );
  }
}

class DriverOfflineEuropeAreaValidation {
  final bool accepted;
  final String reason;

  const DriverOfflineEuropeAreaValidation({
    required this.accepted,
    required this.reason,
  });
}

bool driverOfflineEuropeCenterInEnvelope({
  required double latitude,
  required double longitude,
}) {
  return longitude >= kDriverOfflineEuropeWestLon &&
      longitude <= kDriverOfflineEuropeEastLon &&
      latitude >= kDriverOfflineEuropeSouthLat &&
      latitude <= kDriverOfflineEuropeNorthLat;
}

bool driverOfflineEuropeRadiusAllowed(int radiusKm) {
  return radiusKm >= kDriverOfflineEuropeMinRadiusKm &&
      radiusKm <= kDriverOfflineEuropeMaxRadiusKm;
}

/// Approximate circular area (km²) for a radius — used only as a safeguard.
double driverOfflineEuropeApproxAreaKm2(int radiusKm) {
  final r = radiusKm.toDouble();
  return math.pi * r * r;
}

/// Bounding-box polygon for a center + radius. Cross-border is allowed when the
/// bbox extends past a country line; country membership does not clip geometry.
Map<String, dynamic> driverOfflineEuropeRadiusBboxGeometry({
  required double latitude,
  required double longitude,
  required int radiusKm,
}) {
  final latRad = latitude * math.pi / 180.0;
  final degLat = radiusKm / 111.32;
  final cosLat = math.cos(latRad).abs().clamp(0.2, 1.0);
  final degLon = radiusKm / (111.32 * cosLat);
  final west = longitude - degLon;
  final east = longitude + degLon;
  final south = latitude - degLat;
  final north = latitude + degLat;
  return driverOfflineMapBboxGeometry(
    westLon: west,
    southLat: south,
    eastLon: east,
    northLat: north,
  );
}

/// Bbox helper shared with the page presets (kept here for pure tests).
Map<String, dynamic> driverOfflineMapBboxGeometry({
  required double westLon,
  required double southLat,
  required double eastLon,
  required double northLat,
}) {
  return <String, dynamic>{
    'type': 'Polygon',
    'coordinates': <List<List<double>>>[
      <List<double>>[
        <double>[westLon, southLat],
        <double>[eastLon, southLat],
        <double>[eastLon, northLat],
        <double>[westLon, northLat],
        <double>[westLon, southLat],
      ],
    ],
  };
}

DriverOfflineEuropeAreaValidation validateDriverOfflineEuropeSelection({
  required double latitude,
  required double longitude,
  required int radiusKm,
}) {
  if (!latitude.isFinite || !longitude.isFinite) {
    return const DriverOfflineEuropeAreaValidation(
      accepted: false,
      reason: 'invalid_coordinate',
    );
  }
  if (!driverOfflineEuropeCenterInEnvelope(
    latitude: latitude,
    longitude: longitude,
  )) {
    return const DriverOfflineEuropeAreaValidation(
      accepted: false,
      reason: 'outside_europe_envelope',
    );
  }
  if (!driverOfflineEuropeRadiusAllowed(radiusKm)) {
    return const DriverOfflineEuropeAreaValidation(
      accepted: false,
      reason: 'radius_out_of_bounds',
    );
  }
  final area = driverOfflineEuropeApproxAreaKm2(radiusKm);
  if (area > kDriverOfflineEuropeMaxAreaKm2) {
    return const DriverOfflineEuropeAreaValidation(
      accepted: false,
      reason: 'area_too_large',
    );
  }
  return const DriverOfflineEuropeAreaValidation(
    accepted: true,
    reason: 'ok',
  );
}

/// Deterministic, collision-safe slug: name + country + radius + rounded cell.
String driverOfflineEuropeRegionSlug({
  required DriverOfflineEuropePlace place,
  required int radiusKm,
  required int minZoom,
  required int maxZoom,
}) {
  final nameSlug = driverOfflineMapSlugFromDisplayName(place.primaryName);
  final country = place.countryCode.trim().toLowerCase();
  final safeCountry =
      country.isEmpty ? 'eu' : driverOfflineMapSlugFromDisplayName(country);
  // ~1.1 km cells — same place + radius collide; nearby distinct cells differ.
  final latCell = (place.latitude * 100).round();
  final lonCell = (place.longitude * 100).round();
  final latTag = latCell < 0 ? 's${-latCell}' : 'n$latCell';
  final lonTag = lonCell < 0 ? 'w${-lonCell}' : 'e$lonCell';
  return '${nameSlug}_${safeCountry}_r${radiusKm}_${latTag}_$lonTag';
}

bool driverOfflineMapIsLegacyPresetRegionId(String regionId) {
  final id = regionId.trim().toLowerCase();
  for (final slug in kDriverOfflineLegacyPresetSlugs) {
    if (id.contains(slug)) return true;
  }
  return false;
}

/// True when [candidateRegionId] already exists among downloaded region ids.
bool driverOfflineMapRegionIdAlreadyPresent({
  required String candidateRegionId,
  required Iterable<String> existingRegionIds,
}) {
  final target = candidateRegionId.trim();
  if (target.isEmpty) return false;
  for (final id in existingRegionIds) {
    if (id.trim() == target) return true;
  }
  return false;
}

/// Parse Mapbox Geocoding v5 feature maps into Europe place candidates.
List<DriverOfflineEuropePlace> parseDriverOfflineEuropeGeocodeFeatures(
  List<dynamic> features,
) {
  final out = <DriverOfflineEuropePlace>[];
  for (final raw in features) {
    if (raw is! Map) continue;
    final m = Map<String, dynamic>.from(raw);
    final center = m['center'];
    if (center is! List || center.length < 2) continue;
    final lon = (center[0] as num?)?.toDouble();
    final lat = (center[1] as num?)?.toDouble();
    if (lon == null || lat == null) continue;
    if (!driverOfflineEuropeCenterInEnvelope(latitude: lat, longitude: lon)) {
      continue;
    }

    final text = (m['text'] ?? '').toString().trim();
    final placeName = (m['place_name'] ?? '').toString().trim();
    final primary = text.isNotEmpty
        ? text
        : (placeName.isNotEmpty ? placeName.split(',').first.trim() : '');
    if (primary.isEmpty) continue;

    var countryCode = '';
    var countryName = '';
    final context = m['context'];
    if (context is List) {
      for (final c in context) {
        if (c is! Map) continue;
        final id = (c['id'] ?? '').toString();
        if (id.startsWith('country.')) {
          countryCode = (c['short_code'] ?? '').toString().toLowerCase();
          countryName = (c['text'] ?? '').toString().trim();
          break;
        }
      }
    }
    // Some top-level features are countries themselves.
    final props = m['properties'];
    if (countryCode.isEmpty && props is Map) {
      countryCode = (props['short_code'] ?? '').toString().toLowerCase();
    }
    if (countryName.isEmpty && placeName.contains(',')) {
      countryName = placeName.split(',').last.trim();
    }

    final types = m['place_type'];
    final placeType = types is List && types.isNotEmpty
        ? types.first.toString()
        : 'place';

    out.add(
      DriverOfflineEuropePlace(
        primaryName: primary,
        countryCode: countryCode,
        countryName: countryName.isNotEmpty ? countryName : countryCode.toUpperCase(),
        latitude: lat,
        longitude: lon,
        mapboxFeatureId: (m['id'] ?? '').toString(),
        placeType: placeType,
      ),
    );
  }
  return out;
}

/// ISO country codes used to bias Mapbox search across Europe (not a hard
/// geometry clip — selected radius may still cross borders).
const String kDriverOfflineEuropeGeocodeCountryCsv =
    'be,fr,nl,de,es,lu,gb,ie,pt,it,at,ch,pl,cz,dk,se,no,fi,gr,hr,hu,ro,bg,sk,si,ee,lv,lt,mt,cy,is';
