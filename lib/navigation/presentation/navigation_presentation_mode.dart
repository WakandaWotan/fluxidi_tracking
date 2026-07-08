import '../nav_engine/nav_camera_view_mode.dart';

/// NAV-PRES-1: logical navigation presentation modes.
///
/// [driver] maps to legacy [NavCameraViewMode.streetView] camera behavior
/// until a real screen-fixed cockpit HUD lands in a later patch.
enum NavigationPresentationMode {
  northUp,
  overview,
  driver,
}

/// Where the vehicle is drawn on screen (presentation-only).
enum NavigationVehiclePresentation {
  /// Mapbox point annotation on the map surface (current production path).
  mapAnnotation,
}

/// Stable user-facing / diagnostic labels for [NavigationPresentationMode].
String navigationPresentationModeLabel(NavigationPresentationMode mode) {
  switch (mode) {
    case NavigationPresentationMode.northUp:
      return 'north_up';
    case NavigationPresentationMode.overview:
      return 'overview';
    case NavigationPresentationMode.driver:
      return 'driver';
  }
}

/// Bounded diagnostics token for presentation events (no coordinates).
String navigationPresentationDiagnosticsLabel(NavigationPresentationMode mode) {
  switch (mode) {
    case NavigationPresentationMode.northUp:
      return 'NAV_PRES_north_up';
    case NavigationPresentationMode.overview:
      return 'NAV_PRES_overview';
    case NavigationPresentationMode.driver:
      return 'NAV_PRES_driver';
  }
}

/// Maps committed NAV-R15A camera view modes to presentation modes.
NavigationPresentationMode navigationPresentationModeFromNavCameraViewMode(
  NavCameraViewMode viewMode,
) {
  switch (viewMode) {
    case NavCameraViewMode.northUp:
      return NavigationPresentationMode.northUp;
    case NavCameraViewMode.overview:
      return NavigationPresentationMode.overview;
    case NavCameraViewMode.streetView:
      return NavigationPresentationMode.driver;
  }
}

/// Maps presentation modes back to the legacy camera pipeline enum.
NavCameraViewMode navCameraViewModeFromNavigationPresentationMode(
  NavigationPresentationMode mode,
) {
  switch (mode) {
    case NavigationPresentationMode.northUp:
      return NavCameraViewMode.northUp;
    case NavigationPresentationMode.overview:
      return NavCameraViewMode.overview;
    case NavigationPresentationMode.driver:
      return NavCameraViewMode.streetView;
  }
}

/// Cycles north up -> overview -> driver -> north up (mirrors NAV-R15A toggle).
NavigationPresentationMode toggleNavigationPresentationMode(
  NavigationPresentationMode current,
) {
  switch (current) {
    case NavigationPresentationMode.northUp:
      return NavigationPresentationMode.overview;
    case NavigationPresentationMode.overview:
      return NavigationPresentationMode.driver;
    case NavigationPresentationMode.driver:
      return NavigationPresentationMode.northUp;
  }
}
