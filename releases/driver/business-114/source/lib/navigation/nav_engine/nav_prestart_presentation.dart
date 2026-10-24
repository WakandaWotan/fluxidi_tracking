// NAV-PRESTART-FIELD-BLOCKER-3
// NAV-RELEASE-SIMPLE-STREETLEVEL-1
//
// Pre-start presentation decisions for the driver map surface.
//
// Release simplification: once a preview draft exists, fixed streetlevel is
// the only presentation. Overview / View-mode selection is removed from the
// product surface; fitBounds must not own the camera.
//
// Pure decision only: no Mapbox handle, no widget state, no I/O.

/// The two presentation modes the pre-start preview surface may present.
enum NavPreviewPresentationMode {
  /// Route framed inside the viewport (legacy; unused by release UI).
  overview,

  /// Driver cockpit view: taxi anchored low above the KPI panel.
  streetLevel,
}

/// Opaque tokens for the selected view mode, so this pure module never depends
/// on the driver-page enum and stays free of Flutter imports.
class NavPreviewViewModeTokens {
  const NavPreviewViewModeTokens._();

  static const String overview = 'overview';
  static const String streetView = 'streetView';
  static const String northUp = 'northUp';
}

/// Inputs for [decideNavPreviewPresentation]. All fields are cheap snapshots
/// of driver-page state at build time.
class NavPreviewPresentationInputs {
  const NavPreviewPresentationInputs({
    required this.hasPreviewDraft,
    required this.selectedViewMode,
    required this.routePointCount,
    required this.liveRideActive,
  });

  /// True when a street-ride draft (destination chosen, START not pressed) or
  /// any other preview draft is currently active on the driver page.
  final bool hasPreviewDraft;

  /// Opaque token from [NavPreviewViewModeTokens]. Release always treats a
  /// preview draft as streetlevel regardless of this token.
  final String selectedViewMode;

  /// Live coord count. Values below 2 mark the route as not yet drawable.
  final int routePointCount;

  /// True when a live ride is active. A live ride always wins.
  final bool liveRideActive;
}

/// Outcome of [decideNavPreviewPresentation].
class NavPreviewPresentationDecision {
  const NavPreviewPresentationDecision({
    required this.mode,
    required this.applyCockpitCamera,
    required this.previewRouteRestoreEligible,
    required this.reason,
  });

  /// The presentation the caller must render on the map surface.
  final NavPreviewPresentationMode mode;

  /// True when the caller must run the driver-cockpit camera pipeline for a
  /// pre-start preview draft.
  final bool applyCockpitCamera;

  /// True when a style-restore in the pre-start preview may redraw the
  /// accepted route line + pins.
  final bool previewRouteRestoreEligible;

  /// Short, sanitized reason token used in diagnostic logging.
  final String reason;

  bool get isStreetLevel => mode == NavPreviewPresentationMode.streetLevel;
}

/// Decides the pre-start preview presentation for the driver map surface.
///
/// Rules:
///   * Live ride wins. Preview presentation is a no-op during a live ride.
///   * Without a preview draft the surface stays in overview and no preview
///     camera pipeline may run.
///   * With a preview draft, fixed streetlevel always owns the camera
///     (NAV-RELEASE-SIMPLE-STREETLEVEL-1).
NavPreviewPresentationDecision decideNavPreviewPresentation(
  NavPreviewPresentationInputs input,
) {
  if (input.liveRideActive) {
    return const NavPreviewPresentationDecision(
      mode: NavPreviewPresentationMode.overview,
      applyCockpitCamera: false,
      previewRouteRestoreEligible: false,
      reason: 'live_ride_active',
    );
  }
  if (!input.hasPreviewDraft) {
    return const NavPreviewPresentationDecision(
      mode: NavPreviewPresentationMode.overview,
      applyCockpitCamera: false,
      previewRouteRestoreEligible: false,
      reason: 'no_preview_draft',
    );
  }
  final restoreEligible = input.routePointCount >= 2;
  return NavPreviewPresentationDecision(
    mode: NavPreviewPresentationMode.streetLevel,
    applyCockpitCamera: true,
    previewRouteRestoreEligible: restoreEligible,
    reason: 'preview_fixed_streetlevel',
  );
}

/// Legacy cycle helper kept for tests; release UI no longer exposes a toggle.
String cycleNavPreviewViewMode(String current) {
  if (current == NavPreviewViewModeTokens.streetView) {
    return NavPreviewViewModeTokens.overview;
  }
  return NavPreviewViewModeTokens.streetView;
}

/// Normalises any [current] view-mode token into the release-safe streetlevel.
String normaliseNavPreviewViewMode(String current) {
  return NavPreviewViewModeTokens.streetView;
}

/// NAV-RELEASE-SIMPLE-STREETLEVEL-1: overview fit-bounds is never permitted
/// on the navigation surface once a draft or live ride exists. Callers keep
/// the old parameters for source compatibility.
bool mayOverviewFitBoundsInPreview({
  required bool allowOverviewCamera,
  required String selectedViewMode,
  required bool liveRideActive,
}) {
  // Fixed streetlevel owns the camera; fitBounds is retired for release.
  return false;
}

/// Style switch in preview must re-apply the fixed streetlevel camera for any
/// active preview draft (selection no longer matters).
bool mayRestorePreviewCockpitCameraAfterStyleSwitch({
  required bool hasPreviewDraft,
  required String selectedViewMode,
  required bool liveRideActive,
}) {
  if (liveRideActive) return false;
  if (!hasPreviewDraft) return false;
  return true;
}
