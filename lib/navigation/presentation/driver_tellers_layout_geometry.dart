// NAV-TELLERS-EXACT-LIVE-VIEWPORT-1
//
// Single authoritative proportional geometry for the Tellers presentation.
// Every visual aperture, chrome panel, marker anchor, selector rect, gold
// frame and camera edge-padding value is derived from one resolve() call.
// Do not recalculate these independently in widgets or camera code.

import 'dart:math' as math;
import 'dart:ui' show Offset, Rect, Size;

import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/navigation/nav_engine/nav_camera_view_mode.dart';

/// Landscape left (meters/controls) share of the safe content width.
const double kTellersLandscapeLeftWidthFraction = 0.44;

/// Marker vertical position inside [DriverTellersLayoutGeometry.liveWindowRect]
/// as a fraction of the window height (0 = top, 1 = bottom). Lower-centre
/// matches the previous Alignment(0, 0.55) visual (≈ 0.775 from top).
const double kTellersMarkerAnchorYFraction = 0.775;

/// Inner inset of the camera focus within the live window (border / chrome).
const double kTellersLiveWindowCameraInnerInset = 8.0;

/// Corner radius of the gold live-window frame. Opaque chrome covers the
/// outside of this rectangle; corner bleed blockers match this radius.
const double kTellersLiveWindowCornerRadius = 20.0;

/// Localized "Live navigatie" label for the live-window chip.
String driverTellersLiveNavigationLabel(AppLanguage language) {
  return const LocalizedText(
    nl: 'Live navigatie',
    en: 'Live navigation',
    fr: 'Navigation en direct',
    es: 'Navegación en vivo',
  ).of(language);
}

/// Immutable, deterministic Tellers layout geometry in full-viewport coordinates
/// (origin at the physical display top-left, including system insets).
class DriverTellersLayoutGeometry {
  const DriverTellersLayoutGeometry({
    required this.viewportSize,
    required this.isLandscape,
    required this.isTablet,
    required this.metersPanelRect,
    required this.liveWindowRect,
    required this.controlsRect,
    required this.statusRect,
    required this.markerAnchor,
    required this.selectorRect,
    required this.labelRect,
    required this.cameraPadding,
    required this.cameraScreenAnchor,
    required this.cornerRadius,
  });

  final Size viewportSize;
  final bool isLandscape;
  final bool isTablet;

  /// Opaque meters + header (+ landscape controls) panel.
  final Rect metersPanelRect;

  /// Exact map aperture — gold frame equals this rectangle.
  final Rect liveWindowRect;

  /// Opaque Pauze | Centreren | Stop region (portrait bottom; landscape is
  /// nested inside [metersPanelRect] but still reported for tests).
  final Rect controlsRect;

  /// Compact status chip region (inside the meters panel).
  final Rect statusRect;

  /// Absolute screen position of the selected Car/Arrow marker.
  final Offset markerAnchor;

  /// Absolute bounds reserved for the Car/Arrow selector (top-right of live).
  final Rect selectorRect;

  /// Absolute bounds reserved for the "Live navigatie" label (top-left of live).
  final Rect labelRect;

  /// Camera edge padding derived from [liveWindowRect] vs [viewportSize].
  final NavCameraViewPadding cameraPadding;

  /// Normalised screen anchor (0–1) of the vehicle inside the full viewport,
  /// derived from [markerAnchor] so follow centres on the live window, not the
  /// full physical display.
  final Offset cameraScreenAnchor;

  final double cornerRadius;

  /// Resolve every Tellers rect from the safe viewport. Pure and deterministic.
  factory DriverTellersLayoutGeometry.resolve({
    required Size viewportSize,
    required double safeTop,
    required double safeBottom,
    required double safeLeft,
    required double safeRight,
    required bool isLandscape,
    required bool isTablet,
  }) {
    final hPad = isTablet ? 20.0 : 12.0;
    final vPad = isLandscape ? 8.0 : 12.0;
    const gap = 12.0;

    final contentLeft = safeLeft + hPad;
    final contentTop = safeTop + vPad;
    final contentRight = viewportSize.width - safeRight - hPad;
    final contentBottom = viewportSize.height - safeBottom - vPad;
    final contentW = math.max(0.0, contentRight - contentLeft);
    final contentH = math.max(0.0, contentBottom - contentTop);

    late final Rect metersPanelRect;
    late final Rect liveWindowRect;
    late final Rect controlsRect;
    late final Rect statusRect;

    if (isLandscape) {
      // LEFT ≈ 44% opaque chrome; RIGHT = remaining after gap = live aperture.
      final leftW = contentW * kTellersLandscapeLeftWidthFraction;
      final liveW = math.max(0.0, contentW - leftW - gap);
      metersPanelRect = Rect.fromLTWH(
        contentLeft,
        contentTop,
        leftW,
        contentH,
      );
      liveWindowRect = Rect.fromLTWH(
        contentLeft + leftW + gap,
        contentTop,
        liveW,
        contentH,
      );
      // Controls sit at the bottom of the left panel.
      final controlsH = math.min(72.0, contentH * 0.18);
      controlsRect = Rect.fromLTWH(
        metersPanelRect.left + 10,
        metersPanelRect.bottom - controlsH - 10,
        math.max(0.0, metersPanelRect.width - 20),
        controlsH,
      );
      final statusH = isTablet ? 28.0 : 24.0;
      statusRect = Rect.fromLTWH(
        metersPanelRect.left + 10,
        controlsRect.top - statusH - 8,
        math.min(180.0, metersPanelRect.width - 20),
        statusH,
      );
    } else {
      // TOP opaque meters; MIDDLE live aperture; BOTTOM opaque controls.
      final controlsH = isTablet ? 76.0 : 68.0;
      final topH = _portraitTopRegionHeight(
        contentH: contentH,
        controlsH: controlsH,
        gap: gap,
        isTablet: isTablet,
      );
      metersPanelRect = Rect.fromLTWH(
        contentLeft,
        contentTop,
        contentW,
        topH,
      );
      final liveTop = contentTop + topH + gap;
      final liveBottom = contentBottom - controlsH - gap;
      final liveH = math.max(120.0, liveBottom - liveTop);
      liveWindowRect = Rect.fromLTWH(
        contentLeft,
        liveTop,
        contentW,
        liveH,
      );
      controlsRect = Rect.fromLTWH(
        contentLeft,
        contentBottom - controlsH,
        contentW,
        controlsH,
      );
      final statusH = isTablet ? 28.0 : 24.0;
      statusRect = Rect.fromLTWH(
        metersPanelRect.left + 10,
        metersPanelRect.bottom - statusH - 10,
        math.min(180.0, metersPanelRect.width - 20),
        statusH,
      );
    }

    final markerAnchor = Offset(
      liveWindowRect.left + liveWindowRect.width / 2,
      liveWindowRect.top + liveWindowRect.height * kTellersMarkerAnchorYFraction,
    );

    final selectorW = isTablet ? 168.0 : 148.0;
    final selectorH = isTablet ? 40.0 : 36.0;
    final selectorRect = Rect.fromLTWH(
      liveWindowRect.right - 8 - selectorW,
      liveWindowRect.top + 8,
      selectorW,
      selectorH,
    );

    final labelW = isTablet ? 120.0 : 108.0;
    final labelH = isTablet ? 28.0 : 24.0;
    final labelRect = Rect.fromLTWH(
      liveWindowRect.left + 8,
      liveWindowRect.top + 8,
      labelW,
      labelH,
    );

    // NAV-TELLERS-POSE-ANCHOR-AND-DIAGNOSTICS-UI-1: solve the camera padding so
    // the authoritative navigation pose projects onto EXACTLY the on-screen
    // Car/Arrow anchor (lower-centre), not the geometric live-window centre.
    //
    // Mapbox places the camera `center` at the geometric centre of the viewport
    // rectangle remaining after padding (zoom is set explicitly, so padding only
    // moves the focal point):
    //   focalX = (padLeft + (W - padRight)) / 2
    //   focalY = (padTop  + (H - padBottom)) / 2
    // We want focal == markerAnchor  ⇔  project(pose) == tellersVehicleMarker.
    // Per axis that requires  padStart - padEnd == 2*anchor - extent, which we
    // satisfy with the minimal non-negative split below (one side collapses to
    // 0). This is exact for any anchor in [0, extent] and never negative.
    //
    // The previous formula centred the pose at the live-window MIDDLE (≈0.5)
    // while the marker sits at kTellersMarkerAnchorYFraction (≈0.775) — the
    // downward gap seen in the field where the blue route began above the
    // marker. The camera padding never accounted for the marker's Y fraction.
    final padLeft = math.max(0.0, 2 * markerAnchor.dx - viewportSize.width);
    final padRight = math.max(0.0, viewportSize.width - 2 * markerAnchor.dx);
    final padTop = math.max(0.0, 2 * markerAnchor.dy - viewportSize.height);
    final padBottom = math.max(0.0, viewportSize.height - 2 * markerAnchor.dy);
    final cameraPadding = NavCameraViewPadding(
      top: padTop,
      bottom: padBottom,
      left: padLeft,
      right: padRight,
    );

    final cameraScreenAnchor = Offset(
      viewportSize.width <= 0 ? 0.5 : markerAnchor.dx / viewportSize.width,
      viewportSize.height <= 0 ? 0.5 : markerAnchor.dy / viewportSize.height,
    );

    return DriverTellersLayoutGeometry(
      viewportSize: viewportSize,
      isLandscape: isLandscape,
      isTablet: isTablet,
      metersPanelRect: metersPanelRect,
      liveWindowRect: liveWindowRect,
      controlsRect: controlsRect,
      statusRect: statusRect,
      markerAnchor: markerAnchor,
      selectorRect: selectorRect,
      labelRect: labelRect,
      cameraPadding: cameraPadding,
      cameraScreenAnchor: cameraScreenAnchor,
      cornerRadius: kTellersLiveWindowCornerRadius,
    );
  }

  // NAV-TELLERS-POSE-ANCHOR-AND-DIAGNOSTICS-UI-1: unambiguous, single-space
  // camera-facing geometry. All values below are full-viewport GLOBAL logical
  // pixels (origin = physical display top-left, including system insets). The
  // local→global conversion happens exactly once, inside resolve().

  /// On-screen anchor of the visible Car/Arrow marker (global logical pixels).
  /// Identical to the value the Flutter marker widget is positioned at.
  Offset get markerAnchorGlobal => markerAnchor;

  /// The global screen point the authoritative navigation pose must project
  /// onto while Tellers follow is active. Equal to [markerAnchorGlobal] by
  /// construction, so project(authoritativeNavigationPose) lands on the marker.
  Offset get cameraTargetAnchorGlobal => markerAnchor;

  /// The live map aperture in the same global coordinate space.
  Rect get liveWindowRectGlobal => liveWindowRect;

  /// Full map viewport size (global logical pixels).
  Size get mapViewportSize => viewportSize;

  /// Focal point Mapbox will place the camera `center` at, derived purely from
  /// [cameraPadding] and [viewportSize]. Must equal [cameraTargetAnchorGlobal]
  /// within rounding, proving padding targets the marker (not the window mid).
  Offset get cameraPaddingFocalPoint => Offset(
        (cameraPadding.left + (viewportSize.width - cameraPadding.right)) / 2,
        (cameraPadding.top + (viewportSize.height - cameraPadding.bottom)) / 2,
      );

  /// True when [point] lies inside the authoritative live aperture.
  bool containsInLiveWindow(Offset point) => liveWindowRect.contains(point);

  /// Gold frame equals the live window by construction.
  bool get goldFrameEqualsLiveWindow => true;

  /// Landscape left region width as a fraction of safe content width.
  double get landscapeLeftWidthFraction {
    if (!isLandscape || viewportSize.width <= 0) return 0;
    return metersPanelRect.width /
        (metersPanelRect.width +
            (liveWindowRect.left - metersPanelRect.right) +
            liveWindowRect.width);
  }
}

double _portraitTopRegionHeight({
  required double contentH,
  required double controlsH,
  required double gap,
  required bool isTablet,
}) {
  // Leave at least 120 px for the live band; prefer a readable meters block
  // (header + 2×2 tiles + status + panel padding) that does not overflow.
  final maxTop = math.max(200.0, contentH - controlsH - 2 * gap - 120.0);
  final preferred = isTablet ? 340.0 : 310.0;
  return preferred.clamp(220.0, maxTop);
}

/// Follow-camera padding derived from the single authoritative
/// [DriverTellersLayoutGeometry.liveWindowRect]. Padding only — never View
/// level, zoom, pitch or the normal (non-Tellers) follow behaviour.
NavCameraViewPadding driverTellersLiveWindowCameraPadding({
  required double screenWidth,
  required double screenHeight,
  required bool isLandscape,
  required bool isTablet,
  required double safeTop,
  required double safeBottom,
  double safeLeft = 0,
  double safeRight = 0,
}) {
  return DriverTellersLayoutGeometry.resolve(
    viewportSize: Size(screenWidth, screenHeight),
    safeTop: safeTop,
    safeBottom: safeBottom,
    safeLeft: safeLeft,
    safeRight: safeRight,
    isLandscape: isLandscape,
    isTablet: isTablet,
  ).cameraPadding;
}

/// Opaque aperture chrome slabs that leave only [liveWindowRect] uncovered.
/// Coordinates are relative to the same full-viewport origin as [geometry].
List<Rect> driverTellersOpaqueChromeRects(DriverTellersLayoutGeometry geometry) {
  final live = geometry.liveWindowRect;
  final w = geometry.viewportSize.width;
  final h = geometry.viewportSize.height;
  return <Rect>[
    // Top slab
    Rect.fromLTRB(0, 0, w, live.top),
    // Bottom slab
    Rect.fromLTRB(0, live.bottom, w, h),
    // Left slab (between top and bottom of the aperture)
    Rect.fromLTRB(0, live.top, live.left, live.bottom),
    // Right slab
    Rect.fromLTRB(live.right, live.top, w, live.bottom),
  ];
}

// NAV-TELLERS-POSE-ANCHOR-AND-DIAGNOSTICS-UI-1: bounded, PII-free bucketing for
// the [NAV_TELLERS_ANCHOR] development diagnostic. These NEVER expose
// coordinates, addresses or GPS — only coarse pixel-delta / position buckets.

/// Rendering tolerance (logical px) within which the projected pose and the
/// marker anchor are considered aligned.
const double kTellersAnchorAlignTolerancePx = 6.0;

/// Bucket a normalised (0–1) anchor position into low / mid / high thirds.
String navTellersAnchorPositionBucket(double fraction) {
  if (!fraction.isFinite) return 'na';
  if (fraction < 0.34) return 'lo';
  if (fraction < 0.67) return 'mid';
  return 'hi';
}

/// Bucket a signed pixel delta into a coarse, bounded label (no raw value).
String navTellersAnchorDeltaBucket(double deltaPx) {
  if (!deltaPx.isFinite) return 'na';
  final a = deltaPx.abs();
  if (a <= kTellersAnchorAlignTolerancePx) return 'le6';
  final sign = deltaPx > 0 ? 'p' : 'n';
  if (a <= 16) return '${sign}7_16';
  if (a <= 40) return '${sign}17_40';
  if (a <= 96) return '${sign}41_96';
  return '${sign}gt96';
}

/// True when the projected pose is within [kTellersAnchorAlignTolerancePx] of
/// the marker anchor on both axes.
bool navTellersAnchorAligned({
  required double deltaX,
  required double deltaY,
}) =>
    deltaX.isFinite &&
    deltaY.isFinite &&
    deltaX.abs() <= kTellersAnchorAlignTolerancePx &&
    deltaY.abs() <= kTellersAnchorAlignTolerancePx;

/// Build the bounded, PII-free `[NAV_TELLERS_ANCHOR]` diagnostic payload from
/// the projected pose screen point and the authoritative marker anchor. The
/// returned string contains only generation, orientation and coarse buckets.
String formatNavTellersAnchorDiagnostic({
  required int viewportGeneration,
  required bool isLandscape,
  required Offset markerAnchor,
  required Offset projectedPose,
  required Size viewportSize,
}) {
  final deltaX = projectedPose.dx - markerAnchor.dx;
  final deltaY = projectedPose.dy - markerAnchor.dy;
  final markerFracX =
      viewportSize.width <= 0 ? double.nan : markerAnchor.dx / viewportSize.width;
  final markerFracY = viewportSize.height <= 0
      ? double.nan
      : markerAnchor.dy / viewportSize.height;
  final poseFracX = viewportSize.width <= 0
      ? double.nan
      : projectedPose.dx / viewportSize.width;
  final poseFracY = viewportSize.height <= 0
      ? double.nan
      : projectedPose.dy / viewportSize.height;
  final aligned = navTellersAnchorAligned(deltaX: deltaX, deltaY: deltaY);
  return 'gen=$viewportGeneration '
      'orient=${isLandscape ? 'land' : 'port'} '
      'markerX=${navTellersAnchorPositionBucket(markerFracX)} '
      'markerY=${navTellersAnchorPositionBucket(markerFracY)} '
      'poseX=${navTellersAnchorPositionBucket(poseFracX)} '
      'poseY=${navTellersAnchorPositionBucket(poseFracY)} '
      'dx=${navTellersAnchorDeltaBucket(deltaX)} '
      'dy=${navTellersAnchorDeltaBucket(deltaY)} '
      'aligned=$aligned';
}

/// Small opaque blockers covering the rounded-corner wedges of the live
/// aperture so map pixels cannot bleed outside the gold frame.
List<Rect> driverTellersCornerBleedBlockers(
  DriverTellersLayoutGeometry geometry,
) {
  final r = geometry.cornerRadius;
  final live = geometry.liveWindowRect;
  if (r <= 0 || live.width <= 0 || live.height <= 0) return const <Rect>[];
  final side = math.min(r, math.min(live.width, live.height) / 2);
  return <Rect>[
    Rect.fromLTWH(live.left, live.top, side, side),
    Rect.fromLTWH(live.right - side, live.top, side, side),
    Rect.fromLTWH(live.left, live.bottom - side, side, side),
    Rect.fromLTWH(live.right - side, live.bottom - side, side, side),
  ];
}
