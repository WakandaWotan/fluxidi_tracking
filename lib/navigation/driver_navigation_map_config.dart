import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mb;

const bool kDriverMapTextureView = true;
const mb.AndroidPlatformViewHostingMode kDriverMapHostingMode =
    mb.AndroidPlatformViewHostingMode.HC;
const double kDriverMapInitialCenterLon = 3.62;
const double kDriverMapInitialCenterLat = 50.78;
const double kDriverMapInitialZoom = 12.0;

/// Top-down taxi bitmap for the live driver vehicle marker on the map.
const String kDriverTaxiMarkerAssetPath =
    'assets/navigation/driver_taxi_top.png';

/// Scales the taxi PNG on screen (490×490 source). Tune after field test.
const double kDriverTaxiMarkerIconSize = 0.52;

/// NAV-MAPSTYLE: driver map visual modes.
enum DriverMapVisualMode {
  street,
  satellite,
}

/// Safe to toggle at runtime via [StyleManager.setStyleURI] + annotation redraw.
const bool kDriverMapSatelliteToggleEnabled = true;

/// NAV-MAPSTYLE: clearer navigation styles (preferred for active follow).
const String kDriverMapStyleNavStreetLight =
    'mapbox://styles/mapbox/navigation-day-v1';
const String kDriverMapStyleNavStreetDark =
    'mapbox://styles/mapbox/navigation-night-v1';
const String kDriverMapStyleSatellite =
    'mapbox://styles/mapbox/satellite-streets-v12';

/// Legacy alias kept for offline tile packs and existing imports.
const String kDriverMapStyleLight = kDriverMapStyleNavStreetLight;
const String kDriverMapStyleDark = kDriverMapStyleNavStreetDark;

/// NAV-MAPSTYLE: active route polyline styling (professional, high contrast).
const double kDriverRouteLineWidth = 11.0;
const double kDriverRouteLineOutlineWidth = 14.5;
const double kDriverRouteLineOpacity = 0.98;
const double kDriverRouteLineOutlineOpacity = 0.72;
const int kDriverRouteLineColor = 0xFF2B6CB0;
const int kDriverRouteLineOutlineColor = 0xCC0F172A;

/// NAV-MAPSTYLE: try hiding non-essential POI layers on navigation street styles.
const bool kDriverMapClutterReductionEnabled = true;
const List<String> kDriverMapClutterLayerIds = <String>[
  'poi-label',
  'transit-label',
  'airport-label',
  'natural-point-label',
];

/// NAV-R1: lane row hidden until NAV Engine v2 validates lane reliability.
const bool kDriverNavLaneGuidanceEnabled = false;

/// NAV-R1: max distance (m) to show explicit U-turn / turn-around instructions.
const double kDriverNavR1UturnMaxDisplayDistanceM = 300.0;

/// NAV-R1: maneuver distance (m) at which follow camera may zoom in.
const double kDriverNavR1NearManeuverCameraDistanceM = 300.0;

String driverMapStyleForTheme({
  required bool isLightTheme,
  DriverMapVisualMode visualMode = DriverMapVisualMode.street,
}) {
  if (visualMode == DriverMapVisualMode.satellite) {
    return kDriverMapStyleSatellite;
  }
  return isLightTheme ? kDriverMapStyleNavStreetLight : kDriverMapStyleNavStreetDark;
}

/// Scales taxi marker down when zoomed out so it does not dominate the map.
double driverTaxiMarkerIconSizeForZoom(double zoom) {
  final z = zoom.isFinite ? zoom : kDriverMapInitialZoom;
  if (z <= 14.5) return 0.36;
  if (z <= 15.5) return 0.42;
  if (z <= 16.5) return 0.48;
  return kDriverTaxiMarkerIconSize;
}

/// Fallback triangle marker scale for non-taxi mode.
double driverFallbackMarkerIconSizeForZoom(double zoom) {
  final taxiScale =
      driverTaxiMarkerIconSizeForZoom(zoom) / kDriverTaxiMarkerIconSize;
  return (1.5 * taxiScale).clamp(1.05, 1.5);
}
