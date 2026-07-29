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

/// Manual zoom remains allowed in preview and during a live ride for the
/// release-simplified control surface (zoom only; pitch/anchor stay at L7).
bool fixedStreetLevelZoomAllowed({required bool liveRideActive}) {
  // liveRideActive is accepted for API clarity; zoom is never blocked.
  return true;
}

/// Compact diagnostic label — never "View N/13".
String fixedStreetLevelZoomLabel(double zoom) {
  if (!zoom.isFinite) return '';
  return zoom.toStringAsFixed(1);
}
