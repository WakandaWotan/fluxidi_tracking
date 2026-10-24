import 'package:flutter/painting.dart';

import 'navigation_driver_marker_choice.dart';

/// NAV-PHONE-LANDSCAPE-MARKER-SCALE-1 addendum / CAR VISUAL CENTERLINE
/// CALIBRATION.
///
/// Per-marker visual road-contact / centerline anchors, expressed as fractions
/// of the laid-out marker box (0 = left/top, 1 = right/bottom).
///
/// The projected authoritative navigation pose is anchored to the *layout*
/// centre of the marker widget. When artwork has asymmetric transparent
/// padding (or a visual centreline that is not the PNG centre), a paint offset
/// derived from these fractions moves the *visual* road-contact point onto
/// that layout centre — without moving the layout box, camera target, or
/// Street Level bottom edge.
///
/// Measured from `assets/navigation/driver_taxi_top.png` (490×490):
/// - opaque AABB (alpha > 16): L=143, T=55, R=141, B=42
/// - yellow-body / taxi-sign horizontal centreline ≈ 0.501
/// - opaque content vertical centre ≈ 0.512 (NOT applied — see below)
/// Arrow is a symmetric vector glyph → identity (0.5, 0.5).
///
/// Y stays at 0.5 so Car and Arrow keep the same layout bottom edge (Street
/// Level / camera nose baseline). Applying the measured vertical 0.512 would
/// paint-shift Car off that shared edge and risk a Car ↔ Arrow camera jump.
/// Field defect was horizontal (route left of Car centreline).

/// Car visual road-contact / body centreline inside the HUD box.
const Offset kDriverCarVisualAnchorFraction = Offset(0.501, 0.5);

/// Arrow visual centre (symmetric CustomPainter path).
const Offset kDriverArrowVisualAnchorFraction = Offset(0.5, 0.5);

/// Widget / layout centre that also receives the projected pose.
const Offset kDriverMarkerLayoutCenterFraction = Offset(0.5, 0.5);

/// Resolves the visual anchor fraction for a marker choice.
Offset driverNavigationMarkerVisualAnchorFraction(
  DriverNavigationMarkerChoice choice,
) {
  switch (choice) {
    case DriverNavigationMarkerChoice.car:
      return kDriverCarVisualAnchorFraction;
    case DriverNavigationMarkerChoice.arrow:
      return kDriverArrowVisualAnchorFraction;
  }
}

/// Paint-only offset that places [visualAnchorFraction] on the layout centre.
///
/// Positive X shifts the artwork right; the formula is
/// `(layoutCenter - visualAnchor) * layoutSize` so a visual centre that sits
/// right of the PNG centre (fraction > 0.5) yields a leftward paint shift.
Offset driverNavigationMarkerVisualPaintOffset({
  required double layoutSize,
  required Offset visualAnchorFraction,
}) {
  final size = layoutSize.isFinite && layoutSize > 0 ? layoutSize : 0.0;
  final fx = visualAnchorFraction.dx.isFinite
      ? visualAnchorFraction.dx
      : kDriverMarkerLayoutCenterFraction.dx;
  final fy = visualAnchorFraction.dy.isFinite
      ? visualAnchorFraction.dy
      : kDriverMarkerLayoutCenterFraction.dy;
  return Offset(
    (kDriverMarkerLayoutCenterFraction.dx - fx) * size,
    (kDriverMarkerLayoutCenterFraction.dy - fy) * size,
  );
}

/// Top-left of a [layoutSize] box so [visualAnchorFraction] lands on
/// [visualAnchorScreen]. Use when positioning a marker by its visual
/// road-contact point (Tellers / tests). Equivalent to centering the box on
/// the screen point when the fraction is (0.5, 0.5).
Offset driverNavigationMarkerTopLeftForVisualAnchor({
  required Offset visualAnchorScreen,
  required double layoutSize,
  required Offset visualAnchorFraction,
}) {
  final size = layoutSize.isFinite && layoutSize > 0 ? layoutSize : 0.0;
  final fx = visualAnchorFraction.dx.isFinite
      ? visualAnchorFraction.dx
      : kDriverMarkerLayoutCenterFraction.dx;
  final fy = visualAnchorFraction.dy.isFinite
      ? visualAnchorFraction.dy
      : kDriverMarkerLayoutCenterFraction.dy;
  return Offset(
    visualAnchorScreen.dx - fx * size,
    visualAnchorScreen.dy - fy * size,
  );
}

/// Screen position of the visual road-contact point for a marker whose layout
/// box has [layoutTopLeft] and [layoutSize].
Offset driverNavigationMarkerVisualAnchorScreen({
  required Offset layoutTopLeft,
  required double layoutSize,
  required Offset visualAnchorFraction,
}) {
  final size = layoutSize.isFinite && layoutSize > 0 ? layoutSize : 0.0;
  final fx = visualAnchorFraction.dx.isFinite
      ? visualAnchorFraction.dx
      : kDriverMarkerLayoutCenterFraction.dx;
  final fy = visualAnchorFraction.dy.isFinite
      ? visualAnchorFraction.dy
      : kDriverMarkerLayoutCenterFraction.dy;
  return Offset(
    layoutTopLeft.dx + fx * size,
    layoutTopLeft.dy + fy * size,
  );
}
