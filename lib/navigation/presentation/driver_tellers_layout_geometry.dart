// NAV-TELLERS-EXACT-LIVE-VIEWPORT-1
//
// Single authoritative proportional geometry for the Tellers presentation.
// Every visual aperture, chrome panel, marker anchor, selector rect, gold
// frame and camera edge-padding value is derived from one resolve() call.
// Do not recalculate these independently in widgets or camera code.

import 'dart:math' as math;
import 'dart:ui' show Color, Offset, Rect, Size;

import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/navigation/nav_engine/nav_camera_view_mode.dart';

/// NAV-TELLERS-ROTATION-COMPOSITION-AND-POSE-LOCK-1 (Commit 1): opaque neutral
/// map-background fallback. Painted directly below the retained MapWidget and
/// inside the live-window aperture when the Hybrid-Composition platform-view
/// surface has no frame (e.g. during an orientation resize). Fully opaque so
/// the previous Navigator route can never show through — never a transparent
/// or screenshot copy of the map.
const Color kFluxidiMapBackdrop = Color(0xFF0A0E14);

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

  // NAV-TELLERS-ROTATION-COMPOSITION-AND-POSE-LOCK-1 (Commit 1): atomic geometry
  // switch. A transitional orientation frame can hand us a zero/partial viewport
  // (width/height <= 0, live window outside the viewport). Callers retain the
  // last VALID geometry until a complete one resolves, and never install an
  // incomplete aperture that would expose the layer beneath the map.

  /// The road-contact anchor (global logical pixels) of the visible Car/Arrow
  /// marker. Identical to [cameraTargetAnchorGlobal] by construction so the
  /// authoritative navigation pose projects exactly onto the marker.
  Offset get markerRoadContactAnchorGlobal => markerAnchor;

  /// True only when every camera-facing rect is finite, positive and the live
  /// aperture lies within the viewport. An invalid geometry must never be
  /// committed as the active Tellers layout.
  bool get isValid {
    final w = viewportSize.width;
    final h = viewportSize.height;
    if (!w.isFinite || !h.isFinite || w <= 0 || h <= 0) return false;
    final live = liveWindowRect;
    if (!live.width.isFinite || !live.height.isFinite) return false;
    if (live.width <= 0 || live.height <= 0) return false;
    // Live window must sit within the viewport (small epsilon for rounding).
    const eps = 0.5;
    if (live.left < -eps || live.top < -eps) return false;
    if (live.right > w + eps || live.bottom > h + eps) return false;
    return true;
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
  // NAV-TELLERS-ROTATION-COMPOSITION-AND-POSE-LOCK-1 (Commit 1): on a
  // transitional rotation frame contentH can be tiny, making maxTop < 220.
  // clamp(lower, upper) requires lower <= upper, so bound the lower limit.
  final lower = math.min(220.0, maxTop);
  return preferred.clamp(lower, maxTop);
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

// NAV-TELLERS-ROTATION-COMPOSITION-AND-POSE-LOCK-1 (Commit 2): bounded,
// PII-free `[NAV_TELLERS_POSE_LOCK]` proof emitted after the Tellers follow
// camera settles. It projects the authoritative matched pose through Mapbox and
// reports only coarse buckets — never coordinates, addresses, GPS or trip ids.
// It extends the earlier `[NAV_TELLERS_ANCHOR]` line with device class and the
// active View 1–13 level so field logs prove alignment per device/orientation.
String formatNavTellersPoseLockDiagnostic({
  required int viewportGeneration,
  required bool isLandscape,
  required bool isTablet,
  required int viewLevel,
  required Offset markerAnchor,
  required Offset projectedPose,
  required Size viewportSize,
  // NAV-TELLERS-ROUTE-CENTERLINE-LOCK-1: OPTIONAL. When the caller can also
  // project the matched-route snap point, the diagnostic reports the extra
  // marker↔route-centreline delta (coarse buckets only). Absent → line is
  // byte-for-byte identical to the pre-existing pose-lock diagnostic, so
  // downstream log parsers and unit tests remain valid.
  Offset? projectedSnappedRoute,
  TellersAuthoritativePoseSource? poseSource,
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
  final baseLine = 'gen=$viewportGeneration '
      'device=${isTablet ? 'tablet' : 'phone'} '
      'orient=${isLandscape ? 'land' : 'port'} '
      'view=$viewLevel '
      'markerX=${navTellersAnchorPositionBucket(markerFracX)} '
      'markerY=${navTellersAnchorPositionBucket(markerFracY)} '
      'poseX=${navTellersAnchorPositionBucket(poseFracX)} '
      'poseY=${navTellersAnchorPositionBucket(poseFracY)} '
      'dx=${navTellersAnchorDeltaBucket(deltaX)} '
      'dy=${navTellersAnchorDeltaBucket(deltaY)} '
      'aligned=$aligned';
  if (projectedSnappedRoute == null && poseSource == null) return baseLine;
  final parts = <String>[baseLine];
  if (poseSource != null) {
    parts.add('poseSource=${poseSource == TellersAuthoritativePoseSource.snappedRoute ? 'snap' : 'visual'}');
  }
  if (projectedSnappedRoute != null) {
    final snapDx = projectedSnappedRoute.dx - markerAnchor.dx;
    final snapDy = projectedSnappedRoute.dy - markerAnchor.dy;
    final routeAligned =
        navTellersAnchorAligned(deltaX: snapDx, deltaY: snapDy);
    parts.add('snapDx=${navTellersAnchorDeltaBucket(snapDx)}');
    parts.add('snapDy=${navTellersAnchorDeltaBucket(snapDy)}');
    parts.add('routeAligned=$routeAligned');
  }
  return parts.join(' ');
}

// ===========================================================================
// NAV-TELLERS-ROUTE-CENTERLINE-LOCK-1 — one authoritative Tellers pose.
//
// In Tellers follow mode the on-screen Car/Arrow marker is a screen-fixed
// Flutter widget positioned at [DriverTellersLayoutGeometry.markerAnchor], so
// its visual relation to the blue route depends on which geographic pose the
// follow camera projects onto that marker anchor.
//
// The visible remaining route always starts at the reliable, matched
// `snap.point` (route projection of the GPS). If the follow camera projects
// `visual.point` (prediction / R3 interpolation / forceRaw) — which may differ
// from `snap.point` — the marker sits beside the blue route.
//
// This resolver is the pure, unit-testable single source of truth for the
// Tellers-only camera / pose-lock target. Ordinary Navigation is unaffected.
// ===========================================================================

/// Source classification for the pose returned by
/// [resolveTellersAuthoritativePose].
enum TellersAuthoritativePoseSource {
  /// Matched route-snap point (`progress.snappedLatitude/Longitude` or
  /// equivalent). Used whenever the snap is trustworthy and the vehicle is
  /// on-route.
  snappedRoute,

  /// Visual pose (prediction / interpolation / raw). Fallback used when no
  /// reliable snap exists or the vehicle is genuinely off-route.
  visualFallback,
}

/// Inputs consumed by [resolveTellersAuthoritativePose]. Pure data — no
/// Mapbox, no GPS types, no side-effects.
class TellersAuthoritativePoseInput {
  const TellersAuthoritativePoseInput({
    required this.visualLat,
    required this.visualLon,
    required this.snappedLat,
    required this.snappedLon,
    required this.hasReliableMatchedSnap,
    required this.trustRouteSnap,
    required this.offRouteLikely,
  });

  /// Current visual pose (predicted / interpolated / raw). ALWAYS provided —
  /// this is the existing owner used when no reliable snap wins.
  final double visualLat;
  final double visualLon;

  /// Latest matched-route snapped pose. Null when no snap is available.
  final double? snappedLat;
  final double? snappedLon;

  /// The snap engine reports a reliable, forward-progress route snap.
  final bool hasReliableMatchedSnap;

  /// The confidence engine trusts the current route snap.
  final bool trustRouteSnap;

  /// Any deviation / off-route heuristic is active.
  final bool offRouteLikely;
}

/// Result of [resolveTellersAuthoritativePose]. Carries the chosen lat/lon and
/// which source won so callers can log a bounded, PII-free reason.
class TellersAuthoritativePose {
  const TellersAuthoritativePose({
    required this.lat,
    required this.lon,
    required this.source,
  });

  final double lat;
  final double lon;
  final TellersAuthoritativePoseSource source;

  bool get usesSnappedRoute =>
      source == TellersAuthoritativePoseSource.snappedRoute;

  bool get usesVisualFallback =>
      source == TellersAuthoritativePoseSource.visualFallback;

  /// Short PII-free tag ready for a bounded diagnostic line.
  String get sourceTag => usesSnappedRoute ? 'snap' : 'visual';
}

bool _tellersLatLonValid(double? lat, double? lon) {
  if (lat == null || lon == null) return false;
  if (!lat.isFinite || !lon.isFinite) return false;
  // Sentinel: (0, 0) is a common uninitialised default that would silently
  // pull the camera into the Gulf of Guinea. Treat as invalid.
  if (lat == 0.0 && lon == 0.0) return false;
  return true;
}

/// Pure resolver for the single authoritative Tellers navigation pose.
///
/// Policy:
/// A. Reliable route-follow state ([TellersAuthoritativePoseInput.hasReliableMatchedSnap]
///    && [TellersAuthoritativePoseInput.trustRouteSnap] && ![TellersAuthoritativePoseInput.offRouteLikely]
///    && a valid snappedLat/snappedLon) → return the snapped pose. Prediction
///    or interpolation must NOT override this in Tellers.
/// B. Otherwise → return the visual pose unchanged (existing behaviour). Raw
///    GPS / forceRaw continues to flow through when the snap is not trusted
///    or the vehicle is genuinely off-route.
TellersAuthoritativePose resolveTellersAuthoritativePose(
  TellersAuthoritativePoseInput input,
) {
  final snapValid = _tellersLatLonValid(input.snappedLat, input.snappedLon);
  final reliable = input.hasReliableMatchedSnap &&
      input.trustRouteSnap &&
      !input.offRouteLikely &&
      snapValid;
  if (reliable) {
    return TellersAuthoritativePose(
      lat: input.snappedLat!,
      lon: input.snappedLon!,
      source: TellersAuthoritativePoseSource.snappedRoute,
    );
  }
  return TellersAuthoritativePose(
    lat: input.visualLat,
    lon: input.visualLon,
    source: TellersAuthoritativePoseSource.visualFallback,
  );
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
