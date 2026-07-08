import '../nav_engine/nav_camera_view_mode.dart';
import 'navigation_presentation_flags.dart';
import 'navigation_presentation_mode.dart';
import 'navigation_presentation_state.dart';

/// NAV-PRES-1: maps presentation mode to render flags without changing
/// committed NAV-R15A camera/marker behavior.
class NavigationPresentationController {
  const NavigationPresentationController({
    this.driverHudOverlayEnabled = kNavigationDriverHudOverlayEnabled,
    this.hideMapboxTaxiMarkerWithDriverHudEnabled =
        kNavigationHideMapboxTaxiMarkerWithDriverHudEnabled,
    this.driverCockpitCameraEnabled = kNavigationDriverCockpitCameraEnabled,
    this.driverCockpitCameraControlsEnabled =
        kNavigationDriverCockpitCameraControlsEnabled,
  });

  /// When true, [NavigationPresentationMode.driver] may show the screen-fixed
  /// HUD overlay (NAV-PRES-2A). Injectable for tests.
  final bool driverHudOverlayEnabled;

  /// When true with an active driver HUD overlay, the Mapbox taxi marker may
  /// be visually suppressed (NAV-PRES-2B). Injectable for tests.
  final bool hideMapboxTaxiMarkerWithDriverHudEnabled;

  /// When true, [NavigationPresentationMode.driver] uses the cockpit camera
  /// profile (NAV-PRES-3A). Injectable for tests.
  final bool driverCockpitCameraEnabled;

  /// When true with cockpit camera active, show live +/- intensity controls
  /// (NAV-PRES-3C). Injectable for tests.
  final bool driverCockpitCameraControlsEnabled;

  static const NavigationPresentationController instance =
      NavigationPresentationController();

  /// Resolves presentation flags for [mode].
  NavigationPresentationState resolve(NavigationPresentationMode mode) {
    final navCameraViewMode = navCameraViewModeFromNavigationPresentationMode(
      mode,
    );
    final showDriverHudOverlay =
        mode == NavigationPresentationMode.driver && driverHudOverlayEnabled;
    final hideMapboxTaxiMarker = showDriverHudOverlay &&
        hideMapboxTaxiMarkerWithDriverHudEnabled;
    final useDriverCockpitCamera =
        mode == NavigationPresentationMode.driver && driverCockpitCameraEnabled;
    final showDriverCockpitCameraControls = useDriverCockpitCamera &&
        driverCockpitCameraControlsEnabled;
    return NavigationPresentationState(
      mode: mode,
      navCameraViewMode: navCameraViewMode,
      markerVisible: true,
      hudVisible: false,
      vehiclePresentation: NavigationVehiclePresentation.mapAnnotation,
      modeLabel: navigationPresentationModeLabel(mode),
      diagnosticsLabel: navigationPresentationDiagnosticsLabel(mode),
      showDriverHudOverlay: showDriverHudOverlay,
      hideMapboxTaxiMarker: hideMapboxTaxiMarker,
      useDriverCockpitCamera: useDriverCockpitCamera,
      showDriverCockpitCameraControls: showDriverCockpitCameraControls,
    );
  }

  /// Convenience adapter for the existing [_navCameraViewMode] field.
  NavigationPresentationState resolveForNavCameraViewMode(
    NavCameraViewMode viewMode, {
    bool? driverHudOverlayEnabled,
    bool? hideMapboxTaxiMarkerWithDriverHudEnabled,
    bool? driverCockpitCameraEnabled,
    bool? driverCockpitCameraControlsEnabled,
  }) {
    if (driverHudOverlayEnabled == null &&
        hideMapboxTaxiMarkerWithDriverHudEnabled == null &&
        driverCockpitCameraEnabled == null &&
        driverCockpitCameraControlsEnabled == null) {
      return resolve(
        navigationPresentationModeFromNavCameraViewMode(viewMode),
      );
    }
    return NavigationPresentationController(
      driverHudOverlayEnabled:
          driverHudOverlayEnabled ?? this.driverHudOverlayEnabled,
      hideMapboxTaxiMarkerWithDriverHudEnabled:
          hideMapboxTaxiMarkerWithDriverHudEnabled ??
              this.hideMapboxTaxiMarkerWithDriverHudEnabled,
      driverCockpitCameraEnabled:
          driverCockpitCameraEnabled ?? this.driverCockpitCameraEnabled,
      driverCockpitCameraControlsEnabled:
          driverCockpitCameraControlsEnabled ??
              this.driverCockpitCameraControlsEnabled,
    ).resolve(
      navigationPresentationModeFromNavCameraViewMode(viewMode),
    );
  }
}
