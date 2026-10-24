import 'package:flutter/material.dart';

import '../driver_navigation_map_config.dart';
import '../presentation/navigation_driver_cockpit_camera.dart';
import '../presentation/navigation_driver_marker_choice.dart';
import '../presentation/navigation_driver_marker_scale.dart';
import '../presentation/navigation_driver_marker_visual_anchor.dart';
import 'navigation_driver_arrow_marker.dart';
// NAV-TELLERS-MARKER-CHOICE-APPLY-1: re-export so the driver page (part of
// main.dart, which already imports this HUD overlay) can rasterise the Arrow
// glyph into Mapbox PointAnnotation bytes without a new main.dart import.
export 'navigation_driver_arrow_marker.dart'
    show renderNavigationDriverArrowMarkerPngBytes, NavigationDriverArrowMarker;

/// NAV-PRES-2A: screen-fixed driver vehicle HUD (visual foundation only).
///
/// No GPS, route, camera, or Mapbox dependencies. Parent positions this
/// above the bottom cockpit bar inside the navigation [Stack].
///
/// NAV-VEHICLE-MODE-CAR-ARROW-1: this single overlay is the one visible marker
/// owner. It renders either the 2D Car (existing yellow taxi asset) or the 2D
/// Arrow ([NavigationDriverArrowMarker]) depending on [markerChoice] — never
/// both. Both share the exact same screen *bottom* position and (map-driven)
/// course. Arrow may apply a responsive [arrowScale] (phone only); Auto always
/// uses the unscaled [iconSize] so Car ↔ Arrow never jumps the camera or the
/// Street Level bottom anchor.
///
/// CAR VISUAL CENTERLINE: Car artwork is paint-shifted by
/// [driverNavigationMarkerVisualPaintOffset] so the measured visual road-
/// contact / body centreline lands on the layout centre (projected pose).
/// Layout size and bottom edge stay unchanged — Navigation and Tellers share
/// this path; Arrow keeps a zero offset.
class NavigationDriverHudOverlay extends StatelessWidget {
  const NavigationDriverHudOverlay({
    super.key,
    this.iconSize = 56.0,
    this.markerChoice = DriverNavigationMarkerChoice.car,
    this.arrowScale = 1.0,
  });

  /// NAV-PRES-3D-PRO2 / NAV-PHONE-LANDSCAPE-MARKER-SCALE-1 /
  /// FLUXIDI-VEHICLE-CAMERA-VIEWPORT-ANCHOR-P0: shared HUD base size for Car
  /// and Arrow (and the camera nose-anchor baseline).
  ///
  /// Pass [hostIsTablet] from the sticky host form-factor latch so a physical
  /// tablet keeps size 132 in a narrow split pane. Without it, classification
  /// falls back to window shortest side (never landscape width alone).
  /// Arrow-only responsive shrinkage lives in
  /// [resolveDriverNavigationArrowScale] and is applied via [arrowScale].
  static double resolveIconSize({
    required double screenWidth,
    required double screenHeight,
    required bool cockpitBoost,
    int viewLevel = kDriverCockpitViewLevelDefault,
    bool? hostIsTablet,
  }) {
    // viewLevel is retained for call-site compatibility; size is level-independent.
    return resolveDriverNavigationMarkerBaseIconSize(
      viewportSize: Size(screenWidth, screenHeight),
      cockpitBoost: cockpitBoost,
      hostIsTablet: hostIsTablet,
    );
  }

  final double iconSize;
  final DriverNavigationMarkerChoice markerChoice;

  /// NAV-MARKER-ARROW-RESPONSIVE-SCALE-1: multiplicative scale applied only to
  /// the arrow glyph. Always 1.0 for Auto. Computed by
  /// [resolveDriverNavigationArrowScale] — never a magic number at the call site.
  final double arrowScale;

  @override
  Widget build(BuildContext context) {
    if (markerChoice == DriverNavigationMarkerChoice.arrow) {
      final scale = arrowScale.isFinite && arrowScale > 0 ? arrowScale : 1.0;
      final glyphSize = iconSize * scale;
      // Arrow visual anchor is (0.5, 0.5) → paint offset is zero; still route
      // through the same helper so Car/Arrow share one policy.
      final paintOffset = driverNavigationMarkerVisualPaintOffset(
        layoutSize: glyphSize,
        visualAnchorFraction: kDriverArrowVisualAnchorFraction,
      );
      final arrow = NavigationDriverArrowMarker(size: glyphSize);
      if (paintOffset == Offset.zero) return arrow;
      return Transform.translate(
        key: const ValueKey<String>('nav_marker_visual_anchor_paint'),
        offset: paintOffset,
        child: arrow,
      );
    }
    // Car: unscaled shared HUD size + measured visual-centreline paint offset.
    final paintOffset = driverNavigationMarkerVisualPaintOffset(
      layoutSize: iconSize,
      visualAnchorFraction: kDriverCarVisualAnchorFraction,
    );
    final car = IgnorePointer(
      child: Semantics(
        label: 'Driver navigation vehicle',
        child: Image.asset(
          kDriverTaxiMarkerAssetPath,
          width: iconSize,
          height: iconSize,
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) {
            return _NavigationDriverHudFallback(iconSize: iconSize);
          },
        ),
      ),
    );
    if (paintOffset == Offset.zero) return car;
    return Transform.translate(
      key: const ValueKey<String>('nav_marker_visual_anchor_paint'),
      offset: paintOffset,
      child: car,
    );
  }
}

class _NavigationDriverHudFallback extends StatelessWidget {
  const _NavigationDriverHudFallback({required this.iconSize});

  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: iconSize,
      height: iconSize,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xFFFFD21F).withValues(alpha: 0.92),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white.withValues(alpha: 0.9), width: 2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.35),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Icon(
          Icons.navigation,
          color: const Color(0xFF0B1326),
          size: iconSize * 0.55,
        ),
      ),
    );
  }
}
