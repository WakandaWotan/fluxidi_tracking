import '../nav_engine/nav_camera_view_mode.dart';
import 'navigation_presentation_mode.dart';

/// NAV-PRES-1: resolved presentation flags for one navigation frame.
///
/// Pure Dart — no Mapbox/Flutter references. Camera zoom/tilt/bearing are
/// intentionally omitted here; the legacy camera pipeline still reads
/// [navCameraViewMode] directly until a later migration step.
class NavigationPresentationState {
  final NavigationPresentationMode mode;

  /// Legacy NAV-R15A view mode delegated to by the camera/marker pipeline.
  final NavCameraViewMode navCameraViewMode;

  /// Whether the map taxi point annotation should be shown.
  final bool markerVisible;

  /// Whether a screen-fixed cockpit HUD should be shown.
  final bool hudVisible;

  /// How the vehicle icon is rendered.
  final NavigationVehiclePresentation vehiclePresentation;

  /// Stable presentation label (`north_up`, `overview`, `driver`).
  final String modeLabel;

  /// Bounded diagnostics token (`NAV_PRES_*`).
  final String diagnosticsLabel;

  /// NAV-PRES-2A: screen-fixed driver HUD overlay (driver mode + feature flag).
  final bool showDriverHudOverlay;

  /// NAV-PRES-2B: suppress Mapbox taxi marker when HUD overlay is active.
  final bool hideMapboxTaxiMarker;

  /// NAV-PRES-3A: apply driver cockpit camera zoom/pitch/padding profile.
  final bool useDriverCockpitCamera;

  /// NAV-PRES-3C: show live +/- cockpit camera intensity controls.
  final bool showDriverCockpitCameraControls;

  /// NAV-PRES-3K-B: road-plane Mapbox ModelLayer for the driver vehicle.
  final bool useDriver3dVehicleModel;

  /// NAV-PRES-3K-C: hide HUD vehicle icon for 3D visual isolation testing.
  final bool hideDriverHudVehicleOverlay;

  const NavigationPresentationState({
    required this.mode,
    required this.navCameraViewMode,
    required this.markerVisible,
    required this.hudVisible,
    required this.vehiclePresentation,
    required this.modeLabel,
    required this.diagnosticsLabel,
    required this.showDriverHudOverlay,
    required this.hideMapboxTaxiMarker,
    required this.useDriverCockpitCamera,
    required this.showDriverCockpitCameraControls,
    required this.useDriver3dVehicleModel,
    required this.hideDriverHudVehicleOverlay,
  });

  @override
  bool operator ==(Object other) {
    return other is NavigationPresentationState &&
        other.mode == mode &&
        other.navCameraViewMode == navCameraViewMode &&
        other.markerVisible == markerVisible &&
        other.hudVisible == hudVisible &&
        other.vehiclePresentation == vehiclePresentation &&
        other.modeLabel == modeLabel &&
        other.diagnosticsLabel == diagnosticsLabel &&
        other.showDriverHudOverlay == showDriverHudOverlay &&
        other.hideMapboxTaxiMarker == hideMapboxTaxiMarker &&
        other.useDriverCockpitCamera == useDriverCockpitCamera &&
        other.showDriverCockpitCameraControls ==
            showDriverCockpitCameraControls &&
        other.useDriver3dVehicleModel == useDriver3dVehicleModel &&
        other.hideDriverHudVehicleOverlay == hideDriverHudVehicleOverlay;
  }

  @override
  int get hashCode => Object.hash(
        mode,
        navCameraViewMode,
        markerVisible,
        hudVisible,
        vehiclePresentation,
        modeLabel,
        diagnosticsLabel,
        showDriverHudOverlay,
        hideMapboxTaxiMarker,
        useDriverCockpitCamera,
        showDriverCockpitCameraControls,
        useDriver3dVehicleModel,
        hideDriverHudVehicleOverlay,
      );
}
