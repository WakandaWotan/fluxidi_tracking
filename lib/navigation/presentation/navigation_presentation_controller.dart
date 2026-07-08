import '../nav_engine/nav_camera_view_mode.dart';
import 'navigation_presentation_flags.dart';
import 'navigation_presentation_mode.dart';
import 'navigation_presentation_state.dart';

/// NAV-PRES-1: maps presentation mode to render flags without changing
/// committed NAV-R15A camera/marker behavior.
class NavigationPresentationController {
  const NavigationPresentationController({
    this.driverHudOverlayEnabled = kNavigationDriverHudOverlayEnabled,
  });

  /// When true, [NavigationPresentationMode.driver] may show the screen-fixed
  /// HUD overlay (NAV-PRES-2A). Injectable for tests.
  final bool driverHudOverlayEnabled;

  static const NavigationPresentationController instance =
      NavigationPresentationController();

  /// Resolves presentation flags for [mode].
  ///
  /// NAV-PRES-1: all modes keep the map annotation visible and delegate
  /// camera behavior through [navCameraViewMode]. NAV-PRES-2A adds optional
  /// [showDriverHudOverlay] when [driverHudOverlayEnabled] is true.
  NavigationPresentationState resolve(NavigationPresentationMode mode) {
    final navCameraViewMode = navCameraViewModeFromNavigationPresentationMode(
      mode,
    );
    final showDriverHudOverlay =
        mode == NavigationPresentationMode.driver && driverHudOverlayEnabled;
    return NavigationPresentationState(
      mode: mode,
      navCameraViewMode: navCameraViewMode,
      markerVisible: true,
      hudVisible: false,
      vehiclePresentation: NavigationVehiclePresentation.mapAnnotation,
      modeLabel: navigationPresentationModeLabel(mode),
      diagnosticsLabel: navigationPresentationDiagnosticsLabel(mode),
      showDriverHudOverlay: showDriverHudOverlay,
    );
  }

  /// Convenience adapter for the existing [_navCameraViewMode] field.
  NavigationPresentationState resolveForNavCameraViewMode(
    NavCameraViewMode viewMode, {
    bool? driverHudOverlayEnabled,
  }) {
    if (driverHudOverlayEnabled == null) {
      return resolve(
        navigationPresentationModeFromNavCameraViewMode(viewMode),
      );
    }
    return NavigationPresentationController(
      driverHudOverlayEnabled: driverHudOverlayEnabled,
    ).resolve(
      navigationPresentationModeFromNavCameraViewMode(viewMode),
    );
  }
}
