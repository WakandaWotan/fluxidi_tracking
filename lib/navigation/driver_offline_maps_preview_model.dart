// OFFLINE-MAPS-DOWNLOADED-REGION-PREVIEW-P1
//
// Pure preview targeting for already-downloaded offline regions.
// No Mapbox imports, no I/O — so button visibility and camera math stay
// deterministic in unit tests.

import 'driver_offline_maps_europe_selection.dart';
import 'driver_offline_maps_service.dart';

/// Whether the downloaded-region row may offer “Kaart bekijken”.
///
/// Only canonical [DriverOfflineMapCompletionStatus.complete] / Volledig.
bool driverOfflineMapRegionPreviewAvailable(
  DriverOfflineMapRegionInfo region,
) {
  return region.completionStatus == DriverOfflineMapCompletionStatus.complete;
}

/// Resolved camera / perimeter target for a downloaded region preview.
class DriverOfflineMapPreviewTarget {
  final String regionId;
  final String displayName;
  final double centerLatitude;
  final double centerLongitude;
  final int? radiusKm;
  final Map<String, dynamic> geometry;
  final List<String> styleUris;
  final int minZoom;
  final int maxZoom;
  final String geometrySource;

  const DriverOfflineMapPreviewTarget({
    required this.regionId,
    required this.displayName,
    required this.centerLatitude,
    required this.centerLongitude,
    required this.geometry,
    required this.styleUris,
    required this.minZoom,
    required this.maxZoom,
    required this.geometrySource,
    this.radiusKm,
  });
}

class DriverOfflineMapPreviewBounds {
  final double westLon;
  final double southLat;
  final double eastLon;
  final double northLat;

  const DriverOfflineMapPreviewBounds({
    required this.westLon,
    required this.southLat,
    required this.eastLon,
    required this.northLat,
  });

  double get centerLongitude => (westLon + eastLon) / 2.0;
  double get centerLatitude => (southLat + northLat) / 2.0;

  bool contains({required double latitude, required double longitude}) {
    return longitude >= westLon &&
        longitude <= eastLon &&
        latitude >= southLat &&
        latitude <= northLat;
  }
}

/// Approximate initial zoom so a radius (km) fits on a tablet/phone preview.
double driverOfflineMapPreviewZoomForRadiusKm(int? radiusKm) {
  final km = radiusKm ?? 20;
  if (km <= 10) return 11.2;
  if (km <= 20) return 10.3;
  if (km <= 40) return 9.4;
  if (km <= 60) return 8.7;
  return 8.2;
}

DriverOfflineMapPreviewBounds? driverOfflineMapPreviewBoundsFromGeometry(
  Map<String, dynamic>? geometry,
) {
  if (geometry == null || geometry.isEmpty) return null;
  final coords = geometry['coordinates'];
  if (coords is! List || coords.isEmpty) return null;
  final ring = coords.first;
  if (ring is! List || ring.isEmpty) return null;
  double? west;
  double? east;
  double? south;
  double? north;
  for (final point in ring) {
    if (point is! List || point.length < 2) continue;
    final lon = (point[0] as num?)?.toDouble();
    final lat = (point[1] as num?)?.toDouble();
    if (lon == null || lat == null || !lon.isFinite || !lat.isFinite) continue;
    west = west == null ? lon : (lon < west ? lon : west);
    east = east == null ? lon : (lon > east ? lon : east);
    south = south == null ? lat : (lat < south ? lat : south);
    north = north == null ? lat : (lat > north ? lat : north);
  }
  if (west == null || east == null || south == null || north == null) {
    return null;
  }
  return DriverOfflineMapPreviewBounds(
    westLon: west,
    southLat: south,
    eastLon: east,
    northLat: north,
  );
}

/// Perimeter ring points (lon/lat) for a subtle outline. Empty when unknown.
List<List<double>> driverOfflineMapPreviewPerimeterRing(
  Map<String, dynamic>? geometry,
) {
  final coords = geometry?['coordinates'];
  if (coords is! List || coords.isEmpty) return const <List<double>>[];
  final ring = coords.first;
  if (ring is! List || ring.isEmpty) return const <List<double>>[];
  final out = <List<double>>[];
  for (final point in ring) {
    if (point is! List || point.length < 2) continue;
    final lon = (point[0] as num?)?.toDouble();
    final lat = (point[1] as num?)?.toDouble();
    if (lon == null || lat == null) continue;
    out.add(<double>[lon, lat]);
  }
  return out;
}

/// Parse Europe slug cells: `…_r40_n5075_e360…` → center + radius.
({double latitude, double longitude, int radiusKm})?
    driverOfflineMapPreviewCenterFromRegionId(String regionId) {
  final id = regionId.trim().toLowerCase();
  final match = RegExp(
    r'_r(\d+)_(n|s)(\d+)_(e|w)(\d+)(?:_|$)',
  ).firstMatch(id);
  if (match == null) return null;
  final radius = int.tryParse(match.group(1)!);
  final latRaw = int.tryParse(match.group(3)!);
  final lonRaw = int.tryParse(match.group(5)!);
  if (radius == null || latRaw == null || lonRaw == null) return null;
  final lat = (match.group(2) == 's' ? -latRaw : latRaw) / 100.0;
  final lon = (match.group(4) == 'w' ? -lonRaw : lonRaw) / 100.0;
  if (!lat.isFinite || !lon.isFinite) return null;
  return (latitude: lat, longitude: lon, radiusKm: radius);
}

/// Legacy shortcut geometries (must stay aligned with offline page presets).
Map<String, dynamic>? driverOfflineMapPreviewLegacyPresetGeometry(
  String regionId,
) {
  final id = regionId.trim().toLowerCase();
  if (id.contains('maarkedal_vlaamse_ardennen')) {
    return driverOfflineMapBboxGeometry(
      westLon: 3.45,
      southLat: 50.70,
      eastLon: 3.85,
      northLat: 50.90,
    );
  }
  if (id.contains('belgium_base')) {
    return driverOfflineMapBboxGeometry(
      westLon: 2.50,
      southLat: 49.45,
      eastLon: 6.45,
      northLat: 51.55,
    );
  }
  if (id.contains('brussels_test')) {
    return driverOfflineMapBboxGeometry(
      westLon: 4.30,
      southLat: 50.82,
      eastLon: 4.45,
      northLat: 50.90,
    );
  }
  return null;
}

/// Builds a preview target from a listed region (metadata / slug / presets).
///
/// Order: stored geometry → stored center/radius → Europe slug cells →
/// legacy preset geometry. Returns null when nothing usable is available.
DriverOfflineMapPreviewTarget? resolveDriverOfflineMapPreviewTarget(
  DriverOfflineMapRegionInfo region,
) {
  if (!driverOfflineMapRegionPreviewAvailable(region)) return null;

  Map<String, dynamic>? geometry = region.geometry == null
      ? null
      : Map<String, dynamic>.from(region.geometry!);
  var source = 'metadata_geometry';
  double? centerLat = region.centerLatitude;
  double? centerLon = region.centerLongitude;
  int? radiusKm = region.radiusKm;

  if (geometry == null || geometry.isEmpty) {
    final fromSlug = driverOfflineMapPreviewCenterFromRegionId(region.id);
    if (fromSlug != null) {
      centerLat ??= fromSlug.latitude;
      centerLon ??= fromSlug.longitude;
      radiusKm ??= fromSlug.radiusKm;
      geometry = driverOfflineEuropeRadiusBboxGeometry(
        latitude: fromSlug.latitude,
        longitude: fromSlug.longitude,
        radiusKm: fromSlug.radiusKm,
      );
      source = 'region_id_slug';
    }
  }

  if (geometry == null || geometry.isEmpty) {
    final legacy = driverOfflineMapPreviewLegacyPresetGeometry(region.id);
    if (legacy != null) {
      geometry = legacy;
      source = 'legacy_preset';
    }
  }

  if ((centerLat == null || centerLon == null) && geometry != null) {
    final bounds = driverOfflineMapPreviewBoundsFromGeometry(geometry);
    if (bounds != null) {
      centerLat ??= bounds.centerLatitude;
      centerLon ??= bounds.centerLongitude;
    }
  }

  if (centerLat == null ||
      centerLon == null ||
      !centerLat.isFinite ||
      !centerLon.isFinite) {
    return null;
  }

  geometry ??= driverOfflineEuropeRadiusBboxGeometry(
    latitude: centerLat,
    longitude: centerLon,
    radiusKm: radiusKm ?? 20,
  );

  final styles = region.styleUris.isNotEmpty
      ? List<String>.from(region.styleUris)
      : List<String>.from(kDriverOfflineMapsDefaultStyleUris);

  return DriverOfflineMapPreviewTarget(
    regionId: region.id,
    displayName: region.displayName,
    centerLatitude: centerLat,
    centerLongitude: centerLon,
    radiusKm: radiusKm,
    geometry: geometry,
    styleUris: styles,
    minZoom: region.minZoom,
    maxZoom: region.maxZoom,
    geometrySource: source,
  );
}
