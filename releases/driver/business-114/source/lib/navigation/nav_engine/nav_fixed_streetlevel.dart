// NAV-RELEASE-SIMPLE-STREETLEVEL-1
//
// Pure decisions for the release-simplified navigation camera: one fixed
// streetlevel owner, zoom-only +/- around the proven Pro2 L7 pitch/anchor,
// and a sticky bottom-chrome reserve that never shrinks on a temporary
// incomplete measurement.
//
// No Mapbox handle, no widget state, no I/O.

/// Whether the fixed streetlevel camera must own the map surface.
///
/// True as soon as a destination draft or live ride is present. Overview /
/// fitBounds / alternate presentation modes must not own the camera then.
bool fixedStreetLevelOwnsCamera({
  required bool hasPreviewDraft,
  required bool liveRideActive,
}) {
  return hasPreviewDraft || liveRideActive;
}

/// Overview fit-bounds is never allowed once fixed streetlevel owns the map.
bool mayOverviewFitBoundsWithFixedStreetLevel({
  required bool hasPreviewDraft,
  required bool liveRideActive,
}) {
  return !fixedStreetLevelOwnsCamera(
    hasPreviewDraft: hasPreviewDraft,
    liveRideActive: liveRideActive,
  );
}

/// Style-switch restore: always re-apply fixed streetlevel in preview drafts.
bool mayRestoreFixedStreetLevelAfterStyleSwitch({
  required bool hasPreviewDraft,
  required bool liveRideActive,
}) {
  if (liveRideActive) return false;
  return hasPreviewDraft;
}

/// Sticky bottom-chrome reserve: never shrink when a new measurement is
/// temporarily smaller or incomplete. Grow when chrome grows.
double stickyBottomChromeReserve({
  required double measured,
  double? lastReliable,
}) {
  final safeMeasured = measured.isFinite && measured > 0 ? measured : 0.0;
  if (lastReliable == null || !lastReliable.isFinite || lastReliable <= 0) {
    return safeMeasured;
  }
  if (safeMeasured <= 0) return lastReliable;
  return safeMeasured >= lastReliable ? safeMeasured : lastReliable;
}

/// Manual +/- zoom is retired for the final release surface. Pitch/anchor
/// stay at the fixed L7 streetlevel profile; zoom is never driver-adjustable.
bool fixedStreetLevelZoomAllowed({required bool liveRideActive}) {
  // liveRideActive is accepted for API clarity; zoom is always blocked.
  return false;
}

/// Native Mapbox zoom-gesture flags for the fixed streetlevel surface.
///
/// When [lockManualZoom] is true (prepared route, active NAV, or live ride),
/// every Mapbox zoom gesture is off so the fixed standard zoom cannot change.
class NavFixedZoomGestureLock {
  const NavFixedZoomGestureLock({
    required this.pinchToZoomEnabled,
    required this.doubleTapToZoomInEnabled,
    required this.doubleTouchToZoomOutEnabled,
    required this.quickZoomEnabled,
  });

  final bool pinchToZoomEnabled;
  final bool doubleTapToZoomInEnabled;
  final bool doubleTouchToZoomOutEnabled;
  final bool quickZoomEnabled;

  bool get allZoomGesturesDisabled =>
      !pinchToZoomEnabled &&
      !doubleTapToZoomInEnabled &&
      !doubleTouchToZoomOutEnabled &&
      !quickZoomEnabled;
}

/// Resolves Mapbox zoom-gesture settings for the current surface.
NavFixedZoomGestureLock resolveNavFixedZoomGestureLock({
  required bool preparedRouteOrGuidanceOrLive,
}) {
  if (!preparedRouteOrGuidanceOrLive) {
    return const NavFixedZoomGestureLock(
      pinchToZoomEnabled: true,
      doubleTapToZoomInEnabled: true,
      doubleTouchToZoomOutEnabled: true,
      quickZoomEnabled: true,
    );
  }
  return const NavFixedZoomGestureLock(
    pinchToZoomEnabled: false,
    doubleTapToZoomInEnabled: false,
    doubleTouchToZoomOutEnabled: false,
    quickZoomEnabled: false,
  );
}

/// Compact diagnostic label — never "View N/13".
String fixedStreetLevelZoomLabel(double zoom) {
  if (!zoom.isFinite) return '';
  return zoom.toStringAsFixed(1);
}
