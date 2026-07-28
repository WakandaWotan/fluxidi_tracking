// NAV-PRESTART-PREVIEW-AND-STABLE-BEARING-P0 — Problem 1
//
// Pure decision helpers for the pre-START route-preview surface.
//
// Before this module the driver-page build gated every map control on
// `_cameraMode == follow` (only set at START) or on a non-empty route (only
// built at START). Between choosing a destination and pressing START the driver
// therefore saw a dark map with no route and no controls, and after START the
// same controls appeared but were deliberately blocked — an impossible
// interaction.
//
// The rule encoded here: the preview surface owns the controls, the active ride
// locks them. A preview needs a destination, not a live ride.
//
// Owns no widget state, no Mapbox handle, no camera lifecycle.

/// Minimum coordinate count for a drawable route line.
const int kNavPreviewRoutePointMinimum = 2;

/// Which controls the driver map surface should expose right now.
class NavMapControlAvailability {
  const NavMapControlAvailability({
    required this.routePreview,
    required this.styleSelector,
    required this.zoomControls,
    required this.markerSelector,
    required this.offlineMapsEntry,
    required this.startAction,
    required this.phase,
  });

  /// Route line + origin/destination markers + distance/duration readout.
  final bool routePreview;

  /// Satellite / light / dark / 3D selector.
  final bool styleSelector;

  /// Manual zoom + and -.
  final bool zoomControls;

  /// 2D car / navigation-arrow vehicle marker selector.
  final bool markerSelector;

  /// Direct entry to the Offline Maps page.
  final bool offlineMapsEntry;

  /// The START action.
  final bool startAction;

  final NavMapSurfacePhase phase;
}

/// Which phase the single driver map surface is in. There is exactly one
/// MapWidget; only the phase changes.
enum NavMapSurfacePhase {
  /// No destination and no booking selected.
  idle,

  /// Destination chosen, START not pressed. Controls are the driver's.
  preview,

  /// Live ride. Presentation is locked for the duration.
  activeRide,
}

String navMapSurfacePhaseLabel(NavMapSurfacePhase phase) {
  switch (phase) {
    case NavMapSurfacePhase.idle:
      return 'idle';
    case NavMapSurfacePhase.preview:
      return 'preview';
    case NavMapSurfacePhase.activeRide:
      return 'active_ride';
  }
}

/// Resolves the map surface phase.
///
/// A live ride always wins. Otherwise a chosen destination (street ride draft)
/// or a selected booking puts the surface in preview — deliberately *not*
/// conditional on the route having arrived yet, so the controls do not flicker
/// in while the directions request is still in flight.
NavMapSurfacePhase resolveNavMapSurfacePhase({
  required bool liveRideActive,
  required bool hasPreviewDestination,
}) {
  if (liveRideActive) return NavMapSurfacePhase.activeRide;
  if (hasPreviewDestination) return NavMapSurfacePhase.preview;
  return NavMapSurfacePhase.idle;
}

/// Whether enough geometry exists to draw a route line.
bool navPreviewRouteDrawable(int routePointCount) =>
    routePointCount >= kNavPreviewRoutePointMinimum;

/// Resolves which map controls are available.
///
/// Product rules:
///   * preview → route + style + zoom + marker + offline + START, with no live
///     ride required;
///   * active ride → presentation locked: style selection and manual zoom are
///     hidden, the route stays visible, offline entry and the marker selector
///     stay usable;
///   * after STOP the surface falls back to preview/idle, which restores the
///     controls without any extra call.
NavMapControlAvailability resolveNavMapControlAvailability({
  required bool liveRideActive,
  required bool hasPreviewDestination,
  required int routePointCount,
}) {
  final phase = resolveNavMapSurfacePhase(
    liveRideActive: liveRideActive,
    hasPreviewDestination: hasPreviewDestination,
  );
  final routeDrawable = navPreviewRouteDrawable(routePointCount);
  switch (phase) {
    case NavMapSurfacePhase.idle:
      return NavMapControlAvailability(
        routePreview: routeDrawable,
        styleSelector: false,
        zoomControls: false,
        markerSelector: false,
        offlineMapsEntry: false,
        startAction: false,
        phase: phase,
      );
    case NavMapSurfacePhase.preview:
      return NavMapControlAvailability(
        routePreview: routeDrawable,
        styleSelector: true,
        zoomControls: true,
        markerSelector: true,
        offlineMapsEntry: true,
        startAction: true,
        phase: phase,
      );
    case NavMapSurfacePhase.activeRide:
      return NavMapControlAvailability(
        routePreview: routeDrawable,
        styleSelector: false,
        zoomControls: false,
        markerSelector: true,
        offlineMapsEntry: true,
        startAction: false,
        phase: phase,
      );
  }
}

/// What the driver selected on the pre-START preview surface and must keep
/// after START. Style/marker/level are opaque here on purpose: the widget layer
/// owns the enums, this module only decides whether the selection survives.
class NavPreStartSelection {
  const NavPreStartSelection({
    this.styleSelected = false,
    this.viewLevel,
  });

  /// The driver actively chose a style on the preview surface (as opposed to
  /// inheriting the theme default).
  final bool styleSelected;

  /// The preview camera level, when the driver adjusted it.
  final int? viewLevel;

  bool get hasSelection => styleSelected || viewLevel != null;
}

/// START transition decision for the preview selection.
class NavPreStartCarryOverDecision {
  const NavPreStartCarryOverDecision({
    required this.preserveStyle,
    required this.startViewLevel,
    required this.reason,
  });

  /// True when the driver's pre-start style must survive START unchanged.
  final bool preserveStyle;

  /// The camera level the active ride starts from.
  final int startViewLevel;

  final String reason;
}

/// Decides what a valid pre-start selection carries into the active ride.
///
/// The previous behaviour reset the visual mode and cockpit style on every
/// START, so a driver who had just picked Satellite or 3D was thrown back to
/// the navigation-day/-night pair. A style the driver legitimately selected on
/// the preview surface is preserved; the preview camera level becomes the
/// active-ride starting level instead of being discarded.
NavPreStartCarryOverDecision decideNavPreStartCarryOver({
  required NavPreStartSelection selection,
  required int defaultViewLevel,
}) {
  if (!selection.hasSelection) {
    return NavPreStartCarryOverDecision(
      preserveStyle: false,
      startViewLevel: defaultViewLevel,
      reason: 'no_prestart_selection',
    );
  }
  return NavPreStartCarryOverDecision(
    preserveStyle: selection.styleSelected,
    startViewLevel: selection.viewLevel ?? defaultViewLevel,
    reason: selection.styleSelected
        ? 'preserve_prestart_style'
        : 'preserve_prestart_level',
  );
}
