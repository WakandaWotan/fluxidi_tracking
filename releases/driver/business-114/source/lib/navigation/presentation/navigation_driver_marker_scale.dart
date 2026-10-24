import 'package:flutter/widgets.dart';

import '../../fluxidi_responsive.dart';
import 'navigation_driver_arrow_scale.dart';
import 'navigation_driver_cockpit_camera.dart';
import 'navigation_presentation_mode.dart';

/// NAV-PHONE-LANDSCAPE-MARKER-SCALE-1: authoritative phone/tablet classification
/// for navigation vehicle markers (Car and Arrow).
///
/// Uses [FluxidiBreakpoints.classifyDeviceSize] (shortest side) so a phone in
/// landscape is never promoted to tablet merely because its width exceeds 600.
/// Matches the cockpit-controls form-factor gate in the driver home Stack.
bool driverNavigationIsTabletDevice(Size viewportSize) {
  final screenClass = FluxidiBreakpoints.classifyDeviceSize(viewportSize);
  return screenClass == FluxidiScreenClass.tablet ||
      screenClass == FluxidiScreenClass.desktop;
}

/// Shared base HUD icon size for Car and Arrow (camera nose-anchor baseline).
///
/// Prefer [hostIsTablet] (physical display / sticky latch) when available so a
/// tablet host keeps size 132 in a narrow multi-window pane. Falls back to
/// window shortest-side classification only when host identity is unknown.
/// View level does not affect size.
double resolveDriverNavigationMarkerBaseIconSize({
  required Size viewportSize,
  required bool cockpitBoost,
  bool? hostIsTablet,
}) {
  final isTablet = hostIsTablet ?? driverNavigationIsTabletDevice(viewportSize);
  if (!cockpitBoost) {
    return isTablet ? 80.0 : 72.0;
  }
  return driverCockpitFixedHudIconSize(isTablet: isTablet);
}

/// Resolved marker presentation for one vehicle choice. Car and Arrow share the
/// same [sizeClassIsTablet] and [baseIconSize]; only Arrow applies
/// [glyphScale] < 1 on phone (existing responsive arrow shrink).
class DriverNavigationMarkerSizeResolution {
  const DriverNavigationMarkerSizeResolution({
    required this.sizeClassIsTablet,
    required this.baseIconSize,
    required this.glyphScale,
  });

  final bool sizeClassIsTablet;
  final double baseIconSize;

  /// Multiplier applied to the glyph. Always 1.0 for Car; phone Arrow may be
  /// smaller (see [resolveDriverNavigationArrowScale]).
  final double glyphScale;

  double get glyphIconSize => baseIconSize * glyphScale;
}

/// One policy for Car and Arrow: same device class + same base size; Arrow may
/// apply the phone-landscape/portrait glyph scale on top.
DriverNavigationMarkerSizeResolution resolveDriverNavigationMarkerSize({
  required Size viewportSize,
  required bool cockpitBoost,
  required Orientation orientation,
  required NavigationPresentationMode presentationMode,
  required bool isArrow,
  bool? hostIsTablet,
}) {
  final isTablet = hostIsTablet ?? driverNavigationIsTabletDevice(viewportSize);
  final base = resolveDriverNavigationMarkerBaseIconSize(
    viewportSize: viewportSize,
    cockpitBoost: cockpitBoost,
    hostIsTablet: isTablet,
  );
  final scale = isArrow
      ? resolveDriverNavigationArrowScale(
          viewportWidth: viewportSize.width,
          viewportHeight: viewportSize.height,
          isTablet: isTablet,
          orientation: orientation,
          presentationMode: presentationMode,
        )
      : kDriverNavArrowScaleIdentity;
  return DriverNavigationMarkerSizeResolution(
    sizeClassIsTablet: isTablet,
    baseIconSize: base,
    glyphScale: scale,
  );
}
