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
