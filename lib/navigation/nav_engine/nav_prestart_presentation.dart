// NAV-PRESTART-FIELD-BLOCKER-3
//
// Pre-start presentation decisions for the driver map surface.
//
// Root causes addressed:
//
//   * Problem A (route line missing after style swap): the shared style-restore
//     gate rejects a redraw whenever the ride is not live. In the pre-start
//     preview the driver already has a valid destination and accepted route
//     geometry, so a style change (Light -> Dark -> 3D -> Satellite) silently
//     removes the blue line even though `_routeCoords` still holds >=2 points.
//     This module exposes an explicit `previewRouteRestoreEligible` bit that
//     callers thread into the ownership capture so restore may proceed for a
//     valid preview draft without touching the live-ride contract.
//
//   * Problem B (streetlevel not applied pre-start): the driver page derives
//     the navigation presentation state from `follow && liveRideActive` and
//     silently folds every non-live combination into overview. That leaves the
//     preview camera as a bounds-fit, so the marker sits centred instead of
//     low above the KPI panel. This module returns an explicit
//     `applyCockpitCamera` bit for a preview draft with streetlevel selected,
//     letting the caller run the existing cockpit camera pipeline before START
//     without allowing it to fire on an idle map.
//
// Pure decision only: no Mapbox handle, no widget state, no I/O. All side
// effects stay with the caller so the same decision can be exercised by
// widget-free unit tests.

/// The two presentation modes the pre-start preview surface may present.
enum NavPreviewPresentationMode {
  /// Route framed inside the viewport (existing behaviour).
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

  /// Opaque token from [NavPreviewViewModeTokens] describing what the driver
  /// picked on the camera-view-mode preset. Any unknown value falls back to
  /// [NavPreviewViewModeTokens.overview].
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
  /// pre-start preview draft. When false, the caller falls back to the
  /// existing overview/fit-bounds behaviour.
  final bool applyCockpitCamera;

  /// True when a style-restore in the pre-start preview may redraw the
  /// accepted route line + pins. Callers pass this through the ownership
  /// capture so the existing style-restore guard treats a valid preview draft
  /// as restorable without touching the live-ride contract.
  final bool previewRouteRestoreEligible;

  /// Short, sanitized reason token used in diagnostic logging.
  final String reason;

  bool get isStreetLevel => mode == NavPreviewPresentationMode.streetLevel;
}

/// Decides the pre-start preview presentation for the driver map surface.
///
/// Rules:
///   * Live ride wins. Preview presentation is a no-op during a live ride so
///     the live camera profile is never overridden by preview logic.
///   * Without a preview draft the surface stays in overview and no preview
///     camera pipeline may run. A style-restore must not accidentally paint a
///     stale route.
///   * With a preview draft the caller may choose overview (default) or
///     streetlevel. Only streetlevel triggers the cockpit camera pipeline.
///   * The route becomes restore-eligible as soon as >=2 coords exist and a
///     preview draft is present, independent of the selected mode.
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
  if (input.selectedViewMode == NavPreviewViewModeTokens.streetView) {
    return NavPreviewPresentationDecision(
      mode: NavPreviewPresentationMode.streetLevel,
      applyCockpitCamera: true,
      previewRouteRestoreEligible: restoreEligible,
      reason: 'preview_streetlevel',
    );
  }
  return NavPreviewPresentationDecision(
    mode: NavPreviewPresentationMode.overview,
    applyCockpitCamera: false,
    previewRouteRestoreEligible: restoreEligible,
    reason: 'preview_overview',
  );
}

/// Cycles the preview view mode when the driver taps the camera preset chip.
///
/// The chip is a two-state toggle in preview (overview <-> streetLevel). Any
/// other selection (northUp) is normalised to overview so the preview control
/// never lands on a live-only mode.
String cycleNavPreviewViewMode(String current) {
  if (current == NavPreviewViewModeTokens.streetView) {
    return NavPreviewViewModeTokens.overview;
  }
  return NavPreviewViewModeTokens.streetView;
}

/// Normalises any [current] view-mode token into a preview-safe token.
String normaliseNavPreviewViewMode(String current) {
  if (current == NavPreviewViewModeTokens.streetView) {
    return NavPreviewViewModeTokens.streetView;
  }
  return NavPreviewViewModeTokens.overview;
}

/// NAV-CAMERA-FIELD-REGRESSION-1: whether overview route framing (fit-bounds)
/// may run on the pre-start preview surface.
///
/// Streetlevel ownership must win: once the driver selects streetlevel, an
/// in-flight route-ready or style callback must not re-frame the whole route
/// (which parks the camera at regional/world zoom and looks like a horizon).
bool mayOverviewFitBoundsInPreview({
  required bool allowOverviewCamera,
  required String selectedViewMode,
  required bool liveRideActive,
}) {
  if (liveRideActive) return false;
  if (!allowOverviewCamera) return false;
  if (selectedViewMode == NavPreviewViewModeTokens.streetView) return false;
  return true;
}

/// NAV-CAMERA-FIELD-REGRESSION-1: whether a style switch in preview must
/// re-apply the cockpit streetlevel camera. Live rides keep the existing
/// `_followCameraTesla(style_switch)` path; preview never enters follow.
bool mayRestorePreviewCockpitCameraAfterStyleSwitch({
  required bool hasPreviewDraft,
  required String selectedViewMode,
  required bool liveRideActive,
}) {
  if (liveRideActive) return false;
  if (!hasPreviewDraft) return false;
  return selectedViewMode == NavPreviewViewModeTokens.streetView;
}
