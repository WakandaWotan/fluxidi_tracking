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

  const NavigationPresentationState({
    required this.mode,
    required this.navCameraViewMode,
    required this.markerVisible,
    required this.hudVisible,
    required this.vehiclePresentation,
    required this.modeLabel,
    required this.diagnosticsLabel,
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
        other.diagnosticsLabel == diagnosticsLabel;
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
      );
}
