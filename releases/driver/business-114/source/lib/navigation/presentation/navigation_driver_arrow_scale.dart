import 'package:flutter/widgets.dart';

import 'navigation_presentation_mode.dart';

/// NAV-MARKER-ARROW-RESPONSIVE-SCALE-1: central responsive scale for the 2D
/// navigation arrow only.
///
/// The scale multiplies the shared HUD [iconSize]. Auto is never scaled here.
/// The Street Level bottom anchor is also never changed by this resolver — a
/// smaller arrow simply occupies less height above the same bottom edge, which
/// keeps the 12–20 px gap above the KPI meters and avoids covering extra road.
///
/// Overview / north-up always return 1.0 so those presentations stay visually
/// unchanged. Map style never feeds into this resolver.

/// Phone portrait: ~16% smaller (within the 15–20% acceptance band).
const double kDriverNavArrowScalePhonePortrait = 0.84;

/// Phone landscape: ~19% smaller — short viewports need a bit more clearance.
const double kDriverNavArrowScalePhoneLandscape = 0.81;

/// Compact phone landscape (shortest side under 360): floor of the band.
const double kDriverNavArrowScalePhoneLandscapeCompact = 0.78;

/// Tablet keeps the current large, clearly visible arrow.
const double kDriverNavArrowScaleTablet = 1.0;

/// Unscaled identity — overview, north-up, and any non-driver presentation.
const double kDriverNavArrowScaleIdentity = 1.0;

/// Resolves the multiplicative scale for the 2D navigation arrow.
///
/// Uses device class ([isTablet]) plus available viewport, not orientation
/// alone. Never returns a non-finite or non-positive value.
double resolveDriverNavigationArrowScale({
  required double viewportWidth,
  required double viewportHeight,
  required bool isTablet,
  required Orientation orientation,
  required NavigationPresentationMode presentationMode,
}) {
  // Overview / north-up: keep the previous visual size exactly.
  if (presentationMode != NavigationPresentationMode.driver) {
    return kDriverNavArrowScaleIdentity;
  }

  // Tablet: keep the large arrow; only identity for now (no automatic shrink).
  if (isTablet) {
    return kDriverNavArrowScaleTablet;
  }

  final width = viewportWidth.isFinite && viewportWidth > 0
      ? viewportWidth
      : 390.0;
  final height = viewportHeight.isFinite && viewportHeight > 0
      ? viewportHeight
      : 844.0;
  final shortestSide = width < height ? width : height;
  final landscapeByOrientation = orientation == Orientation.landscape;
  final landscapeByViewport = width > height;
  final isLandscape = landscapeByOrientation || landscapeByViewport;

  if (isLandscape) {
    // Compact / short phones get the lower end of the 0.78–0.84 band.
    if (shortestSide < 360) {
      return kDriverNavArrowScalePhoneLandscapeCompact;
    }
    return kDriverNavArrowScalePhoneLandscape;
  }

  return kDriverNavArrowScalePhonePortrait;
}

/// Applies [resolveDriverNavigationArrowScale] to a base HUD icon size.
///
/// Use only for the arrow marker. Pass the unscaled base size to Auto and to
/// the camera nose-anchor math so Car ↔ Arrow never jumps the camera.
double resolveDriverNavigationArrowIconSize({
  required double baseIconSize,
  required double viewportWidth,
  required double viewportHeight,
  required bool isTablet,
  required Orientation orientation,
  required NavigationPresentationMode presentationMode,
}) {
  final base = baseIconSize.isFinite && baseIconSize > 0 ? baseIconSize : 56.0;
  final scale = resolveDriverNavigationArrowScale(
    viewportWidth: viewportWidth,
    viewportHeight: viewportHeight,
    isTablet: isTablet,
    orientation: orientation,
    presentationMode: presentationMode,
  );
  return base * scale;
}
