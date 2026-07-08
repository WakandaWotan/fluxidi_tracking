import '../nav_engine/nav_camera_view_mode.dart';
import 'navigation_presentation_mode.dart';
import 'navigation_presentation_state.dart';

/// NAV-PRES-1: maps presentation mode to render flags without changing
/// committed NAV-R15A camera/marker behavior.
class NavigationPresentationController {
  const NavigationPresentationController._();

  static const NavigationPresentationController instance =
      NavigationPresentationController._();

  /// Resolves presentation flags for [mode].
  ///
  /// NAV-PRES-1: all modes keep the map annotation visible, no HUD, and
  /// delegate camera behavior through [navCameraViewMode].
  NavigationPresentationState resolve(NavigationPresentationMode mode) {
    final navCameraViewMode = navCameraViewModeFromNavigationPresentationMode(
      mode,
    );
    return NavigationPresentationState(
      mode: mode,
      navCameraViewMode: navCameraViewMode,
      markerVisible: true,
      hudVisible: false,
      vehiclePresentation: NavigationVehiclePresentation.mapAnnotation,
      modeLabel: navigationPresentationModeLabel(mode),
      diagnosticsLabel: navigationPresentationDiagnosticsLabel(mode),
    );
  }

  /// Convenience adapter for the existing [_navCameraViewMode] field.
  NavigationPresentationState resolveForNavCameraViewMode(
    NavCameraViewMode viewMode,
  ) {
    return resolve(
      navigationPresentationModeFromNavCameraViewMode(viewMode),
    );
  }
}
