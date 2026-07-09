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

/// NAV-PRES-3L: fixed destination/arrival marker for active driver navigation.
const String kDriverDestinationMarkerIconImage = 'marker-15';
const int kDriverDestinationMarkerIconColor = 0xFF0B1326;
const int kDriverDestinationMarkerIconHaloColor = 0xFFFFD21F;
const double kDriverDestinationMarkerIconHaloWidth = 1.4;
const double kDriverDestinationMarkerIconSizePhone = 0.82;
const double kDriverDestinationMarkerIconSizeTablet = 0.90;

/// NAV-PRES-3L: screen-fixed destination marker size (no zoom scaling).
double driverDestinationMarkerIconSize({required bool isTablet}) {
  return isTablet
      ? kDriverDestinationMarkerIconSizeTablet
      : kDriverDestinationMarkerIconSizePhone;
}

/// NAV-MAPSTYLE: driver map visual modes.
enum DriverMapVisualMode {
  street,
  satellite,
}

/// NAV-PRES-3K: explicit driver cockpit map style choice (flagged builds only).
enum DriverCockpitMapVisualStyle {
  light,
  dark,
  standard3d,
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

/// NAV-PRES-3I: experimental Mapbox Standard styles for flagged 3D cockpit scene.
const String kDriverMapStyleStandard = 'mapbox://styles/mapbox/standard';
const String kDriverMapStyleStandardSatellite =
    'mapbox://styles/mapbox/standard-satellite';

/// Dart-define key for NAV-PRES-3I flagged 3D cockpit map style experiment.
const String kNavigation3dCockpitSceneDefineKey = 'FLUXIDI_NAV_3D_COCKPIT_SCENE';

/// NAV-PRES-3I: use Mapbox Standard / Standard Satellite in driver cockpit
/// when supported (default off; compile-time only).
///
/// Enable at build time:
/// `--dart-define=FLUXIDI_NAV_3D_COCKPIT_SCENE=true`
const bool kNavigation3dCockpitSceneEnabled = bool.fromEnvironment(
  kNavigation3dCockpitSceneDefineKey,
  defaultValue: false,
);

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

/// NAV-OS-R2: completed (already driven) route section is muted grey so the
/// remaining route ahead of the taxi stays visually dominant.
const double kDriverRouteLineCompletedWidth = 7.0;
const double kDriverRouteLineCompletedOpacity = 0.45;
const int kDriverRouteLineCompletedColor = 0xFF94A3B8;

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

/// Returns true for experimental 3D cockpit style URIs (Standard family).
bool isExperimentalCockpit3dMapStyleUri(String styleUri) {
  return styleUri == kDriverMapStyleStandard ||
      styleUri == kDriverMapStyleStandardSatellite;
}

/// NAV-PRES-3K: diagnostic label for explicit cockpit style choice.
String driverCockpitMapVisualStyleLogLabel(DriverCockpitMapVisualStyle style) {
  switch (style) {
    case DriverCockpitMapVisualStyle.light:
      return 'light';
    case DriverCockpitMapVisualStyle.dark:
      return 'dark';
    case DriverCockpitMapVisualStyle.standard3d:
      return '3d';
    case DriverCockpitMapVisualStyle.satellite:
      return 'satellite';
  }
}

/// NAV-PRES-3K: resolves style URI from an explicit driver cockpit choice.
///
/// Light/dark always use navigation-day/night. Standard / Standard Satellite
/// are used only when not present in [rejectedExperimentalUris]; rejected
/// experimental styles fall back to the safe baseline for that choice.
String driverMapStyleForExplicitCockpitChoice({
  required DriverCockpitMapVisualStyle choice,
  required bool isLightTheme,
  Set<String> rejectedExperimentalUris = const {},
}) {
  switch (choice) {
    case DriverCockpitMapVisualStyle.light:
      return kDriverMapStyleNavStreetLight;
    case DriverCockpitMapVisualStyle.dark:
      return kDriverMapStyleNavStreetDark;
    case DriverCockpitMapVisualStyle.standard3d:
      if (!rejectedExperimentalUris.contains(kDriverMapStyleStandard)) {
        return kDriverMapStyleStandard;
      }
      return isLightTheme
          ? kDriverMapStyleNavStreetLight
          : kDriverMapStyleNavStreetDark;
    case DriverCockpitMapVisualStyle.satellite:
      if (!rejectedExperimentalUris.contains(kDriverMapStyleStandardSatellite)) {
        return kDriverMapStyleStandardSatellite;
      }
      return kDriverMapStyleSatellite;
  }
}

/// NAV-PRES-3I: preferred 3D-capable style for driver cockpit (pure resolver).
///
/// When [rejectedExperimentalUris] contains the primary candidate, falls back
/// to the existing navigation-day/night or satellite-streets styles.
String driverMapStyleForCockpit3d({
  required bool preferSatellite,
  required bool isLightTheme,
  Set<String> rejectedExperimentalUris = const {},
}) {
  final experimental = preferSatellite
      ? kDriverMapStyleStandardSatellite
      : kDriverMapStyleStandard;
  if (!rejectedExperimentalUris.contains(experimental)) {
    return experimental;
  }
  return driverMapStyleForTheme(
    isLightTheme: isLightTheme,
    visualMode: preferSatellite
        ? DriverMapVisualMode.satellite
        : DriverMapVisualMode.street,
  );
}

/// NAV-PRES-3I/3K: resolves the active driver map style URI.
///
/// When the 3D cockpit scene flag is off or [cockpit3dSceneActive] is false,
/// returns the same URI as [driverMapStyleForTheme].
///
/// When the flag is on and [cockpitVisualStyle] is provided, uses the explicit
/// driver choice (light / dark / 3D / satellite) instead of inferring 3D from
/// street/satellite mode.
String resolveDriverMapStyleUri({
  required bool isLightTheme,
  required DriverMapVisualMode visualMode,
  required bool cockpit3dSceneActive,
  DriverCockpitMapVisualStyle? cockpitVisualStyle,
  Set<String> rejectedExperimentalUris = const {},
}) {
  final baseline = driverMapStyleForTheme(
    isLightTheme: isLightTheme,
    visualMode: visualMode,
  );
  if (!kNavigation3dCockpitSceneEnabled || !cockpit3dSceneActive) {
    return baseline;
  }
  if (cockpitVisualStyle != null) {
    return driverMapStyleForExplicitCockpitChoice(
      choice: cockpitVisualStyle,
      isLightTheme: isLightTheme,
      rejectedExperimentalUris: rejectedExperimentalUris,
    );
  }
  return driverMapStyleForCockpit3d(
    preferSatellite: visualMode == DriverMapVisualMode.satellite,
    isLightTheme: isLightTheme,
    rejectedExperimentalUris: rejectedExperimentalUris,
  );
}

/// Scales taxi marker down when zoomed out so it does not dominate the map.
double driverTaxiMarkerIconSizeForZoom(double zoom) {
  final z = zoom.isFinite ? zoom : kDriverMapInitialZoom;
  if (z <= 14.5) return 0.36;
  if (z <= 15.5) return 0.42;
  if (z <= 16.5) return 0.48;
  return kDriverTaxiMarkerIconSize;
}

/// NAV-PRES-3H: read-only 3D/street-level capability note for driver cockpit.
///
/// Current navigation-day/night and satellite-streets styles are optimized for
/// 2D turn-by-turn. High camera pitch can tilt the raster map but does not
/// provide true behind-the-car 3D without terrain, extruded buildings, or a
/// dedicated 3D navigation style patch (separate from HUD/camera level tuning).
class DriverCockpitMap3dCapability {
  const DriverCockpitMap3dCapability({
    required this.styleFamily,
    required this.likelyFlatNavStyle,
    required this.is3dCandidate,
    required this.terrainLikelyAvailable,
    required this.note,
  });

  final String styleFamily;
  final bool likelyFlatNavStyle;
  final bool is3dCandidate;
  final bool terrainLikelyAvailable;
  final String note;

  static DriverCockpitMap3dCapability resolve({
    required String styleUri,
    required DriverMapVisualMode visualMode,
  }) {
    if (styleUri.contains('/standard-satellite')) {
      return const DriverCockpitMap3dCapability(
        styleFamily: 'standard-satellite',
        likelyFlatNavStyle: false,
        is3dCandidate: true,
        terrainLikelyAvailable: false,
        note: 'experimental_3d_candidate_no_terrain_enabled',
      );
    }
    if (styleUri.contains('/standard')) {
      return const DriverCockpitMap3dCapability(
        styleFamily: 'standard',
        likelyFlatNavStyle: false,
        is3dCandidate: true,
        terrainLikelyAvailable: false,
        note: 'experimental_3d_candidate_no_terrain_enabled',
      );
    }
    if (styleUri.contains('satellite-streets')) {
      return const DriverCockpitMap3dCapability(
        styleFamily: 'satellite-streets',
        likelyFlatNavStyle: true,
        is3dCandidate: false,
        terrainLikelyAvailable: false,
        note: 'raster_satellite_high_pitch_not_true_street_3d',
      );
    }
    if (styleUri.contains('navigation-day') ||
        styleUri.contains('navigation-night')) {
      return const DriverCockpitMap3dCapability(
        styleFamily: 'navigation-v1',
        likelyFlatNavStyle: true,
        is3dCandidate: false,
        terrainLikelyAvailable: false,
        note: 'flat_nav_style_needs_terrain_or_3d_style_patch',
      );
    }
    return const DriverCockpitMap3dCapability(
      styleFamily: 'other',
      likelyFlatNavStyle: true,
      is3dCandidate: false,
      terrainLikelyAvailable: false,
      note: 'unknown_style_assume_flat_until_3d_patch',
    );
  }

  String toDiagnosticLine() {
    return 'style=$styleFamily flat=$likelyFlatNavStyle '
        '3dCandidate=$is3dCandidate terrain=$terrainLikelyAvailable '
        'reason=$note';
  }
}

/// Fallback triangle marker scale for non-taxi mode.
double driverFallbackMarkerIconSizeForZoom(double zoom) {
  final taxiScale =
      driverTaxiMarkerIconSizeForZoom(zoom) / kDriverTaxiMarkerIconSize;
  return (1.5 * taxiScale).clamp(1.05, 1.5);
}
