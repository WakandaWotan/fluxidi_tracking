/// Dart-define key for the NAV-PRES-2A driver HUD overlay.
const String kNavigationDriverHudOverlayDefineKey =
    'FLUXIDI_NAV_DRIVER_HUD_OVERLAY';

/// NAV-PRES-2A: screen-fixed driver cockpit HUD overlay (default off).
///
/// Enable at build time:
/// `--dart-define=FLUXIDI_NAV_DRIVER_HUD_OVERLAY=true`
const bool kNavigationDriverHudOverlayEnabled = bool.fromEnvironment(
  kNavigationDriverHudOverlayDefineKey,
  defaultValue: false,
);

/// Dart-define key for NAV-PRES-2B Mapbox taxi suppression with driver HUD.
const String kNavigationHideMapboxTaxiMarkerWithDriverHudDefineKey =
    'FLUXIDI_NAV_HIDE_MAPBOX_TAXI_MARKER_WITH_DRIVER_HUD';

/// NAV-PRES-2B: hide the Mapbox taxi annotation when the driver HUD overlay
/// is active (default off; requires HUD overlay flag + driver mode).
///
/// Enable at build time:
/// `--dart-define=FLUXIDI_NAV_HIDE_MAPBOX_TAXI_MARKER_WITH_DRIVER_HUD=true`
const bool kNavigationHideMapboxTaxiMarkerWithDriverHudEnabled =
    bool.fromEnvironment(
      kNavigationHideMapboxTaxiMarkerWithDriverHudDefineKey,
      defaultValue: false,
    );

/// Dart-define key for NAV-PRES-3A driver cockpit camera profile.
const String kNavigationDriverCockpitCameraDefineKey =
    'FLUXIDI_NAV_DRIVER_COCKPIT_CAMERA';

/// NAV-PRES-3A: lower, forward-looking cockpit camera tuning in driver mode.
///
/// Enable at build time:
/// `--dart-define=FLUXIDI_NAV_DRIVER_COCKPIT_CAMERA=true`
const bool kNavigationDriverCockpitCameraEnabled = bool.fromEnvironment(
  kNavigationDriverCockpitCameraDefineKey,
  defaultValue: false,
);

/// Dart-define key for NAV-PRES-3C driver cockpit camera +/- controls.
const String kNavigationDriverCockpitCameraControlsDefineKey =
    'FLUXIDI_NAV_DRIVER_COCKPIT_CAMERA_CONTROLS';

/// NAV-PRES-3C: live +/- cockpit camera intensity controls in driver mode.
///
/// Requires [kNavigationDriverCockpitCameraEnabled]. Enable at build time:
/// `--dart-define=FLUXIDI_NAV_DRIVER_COCKPIT_CAMERA_CONTROLS=true`
const bool kNavigationDriverCockpitCameraControlsEnabled = bool.fromEnvironment(
  kNavigationDriverCockpitCameraControlsDefineKey,
  defaultValue: false,
);

/// Dart-define key for NAV-PRES-3K-B road-plane 3D driver vehicle model layer.
const String kNavigation3dVehicleModelDefineKey =
    'FLUXIDI_NAV_3D_VEHICLE_MODEL';

/// NAV-PRES-3K-B: Mapbox ModelLayer for a local GLB taxi in driver cockpit mode.
///
/// Dev/local testing only (bundled GLB ~1.4 MB). Enable at build time:
/// `--dart-define=FLUXIDI_NAV_3D_VEHICLE_MODEL=true`
const bool kNavigation3dVehicleModelEnabled = bool.fromEnvironment(
  kNavigation3dVehicleModelDefineKey,
  defaultValue: false,
);

/// Dart-define key for NAV-PRES-3K-C 3D vehicle visual isolation (hide HUD icon).
const String kNavigation3dVehicleHideHudDefineKey =
    'FLUXIDI_NAV_3D_VEHICLE_HIDE_HUD';

/// NAV-PRES-3K-C: hide only the screen-fixed HUD vehicle icon while testing the
/// road-plane ModelLayer (default off; requires 3D vehicle + cockpit camera).
///
/// Enable at build time:
/// `--dart-define=FLUXIDI_NAV_3D_VEHICLE_HIDE_HUD=true`
const bool kNavigation3dVehicleHideHudEnabled = bool.fromEnvironment(
  kNavigation3dVehicleHideHudDefineKey,
  defaultValue: false,
);

/// Dart-define key for NAV-PRES-3K-E 3D vehicle placement/render debug.
const String kNavigation3dVehicleDebugPlacementDefineKey =
    'FLUXIDI_NAV_3D_VEHICLE_DEBUG_PLACEMENT';

/// NAV-PRES-3K-E: force visible placement + debug dot + screen diagnostics.
///
/// Requires [kNavigation3dVehicleModelEnabled] and cockpit camera. Enable at
/// build time: `--dart-define=FLUXIDI_NAV_3D_VEHICLE_DEBUG_PLACEMENT=true`
const bool kNavigation3dVehicleDebugPlacementEnabled = bool.fromEnvironment(
  kNavigation3dVehicleDebugPlacementDefineKey,
  defaultValue: false,
);

/// NAV-3D-VEHICLE-VISIBILITY-FAILSAFE-1: optional debug calibration overrides.
/// Only applied when [kNavigation3dVehicleDebugPlacementEnabled] is true.
const String kNavigation3dVehicleDebugScaleDefineKey =
    'FLUXIDI_NAV_3D_VEHICLE_DEBUG_SCALE';
const String kNavigation3dVehicleDebugYawDefineKey =
    'FLUXIDI_NAV_3D_VEHICLE_DEBUG_YAW';
const String kNavigation3dVehicleDebugElevationDefineKey =
    'FLUXIDI_NAV_3D_VEHICLE_DEBUG_ELEVATION';

const String _navigation3dVehicleDebugScaleRaw = String.fromEnvironment(
  kNavigation3dVehicleDebugScaleDefineKey,
  defaultValue: '',
);
const String _navigation3dVehicleDebugYawRaw = String.fromEnvironment(
  kNavigation3dVehicleDebugYawDefineKey,
  defaultValue: '',
);
const String _navigation3dVehicleDebugElevationRaw = String.fromEnvironment(
  kNavigation3dVehicleDebugElevationDefineKey,
  defaultValue: '',
);

double? navigation3dVehicleDebugScaleOverride() {
  if (!kNavigation3dVehicleDebugPlacementEnabled) return null;
  if (_navigation3dVehicleDebugScaleRaw.isEmpty) return null;
  return double.tryParse(_navigation3dVehicleDebugScaleRaw);
}

double? navigation3dVehicleDebugYawOffsetDeg() {
  if (!kNavigation3dVehicleDebugPlacementEnabled) return null;
  if (_navigation3dVehicleDebugYawRaw.isEmpty) return null;
  return double.tryParse(_navigation3dVehicleDebugYawRaw);
}

double? navigation3dVehicleDebugElevationOverrideMeters() {
  if (!kNavigation3dVehicleDebugPlacementEnabled) return null;
  if (_navigation3dVehicleDebugElevationRaw.isEmpty) return null;
  return double.tryParse(_navigation3dVehicleDebugElevationRaw);
}

/// FLUXIDI NAV-STREETLEVEL-FLUID-MOTION-2 gate for the Phase 2A native
/// FollowPuckViewportState + custom LocationProvider follow-camera pipeline.
///
/// When false (Phase 1 default) the streetlevel follow camera runs on the
/// existing Dart pump with the bounded adaptive-cadence controller (6-10 Hz,
/// `setCamera` primitive, no repeated `easeTo` / `flyTo`).
///
/// When true (Phase 2A, Android-only, dev-build) the widget hands camera
/// following to Mapbox's native `FollowPuckViewportState` fed by a custom
/// Kotlin LocationProvider receiving Fluxidi's route-snapped / predicted pose
/// through a Pigeon HostApi at 5-10 Hz. The Phase 2A code path itself is not
/// landed in Phase 1; this flag exists so Phase 1 wiring can already branch
/// safely and future Phase 2A landings do not have to touch the fallback
/// path again.
///
/// Enable at build time (Phase 2A dev only):
/// `--dart-define=FLUXIDI_NAV_USE_NATIVE_FOLLOW_PUCK=true`
const String kNavigationUseNativeFollowPuckDefineKey =
    'FLUXIDI_NAV_USE_NATIVE_FOLLOW_PUCK';

const bool kNavigationUseNativeFollowPuckEnabled = bool.fromEnvironment(
  kNavigationUseNativeFollowPuckDefineKey,
  defaultValue: false,
);
