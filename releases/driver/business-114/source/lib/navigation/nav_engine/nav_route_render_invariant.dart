// NAV-PARKING-ARRIVAL-DEPARTURE-ROUTE-CLARITY-BANNER-TELLERS-2 / Commit 2
//
// Pure, unit-testable model of the "exactly one authoritative selected blue
// route" invariant. The live app renders the route with a single Mapbox
// PolylineAnnotationManager (no style LineLayer, no alternative routes). The
// two-blue-line field defect was an ORPHANED manager surviving a style swap:
// _recreateAnnotationManagers created a new route/pins/destination manager
// without removing the previous one, so the old blue polyline stayed on the
// new style beneath/next to the new one (most visible around roundabouts).
//
// This module encodes the invariant so it can be asserted in tests independent
// of the Mapbox platform channel.

/// The annotation-manager slots that must be disposed before recreation so no
/// orphan geometry (a second authoritative blue route) can survive a style
/// swap.
enum NavRouteManagerSlot { route, pins, destination }

/// Given which manager slots currently hold a live manager, return the slots
/// that MUST be disposed before recreating managers. The invariant is simple
/// and total: every currently-live manager must be disposed first — none may be
/// silently replaced (which would orphan its annotations on the new style).
Set<NavRouteManagerSlot> navRouteManagersToDisposeBeforeRecreate({
  required bool hasRouteManager,
  required bool hasPinsManager,
  required bool hasDestinationManager,
}) {
  return <NavRouteManagerSlot>{
    if (hasRouteManager) NavRouteManagerSlot.route,
    if (hasPinsManager) NavRouteManagerSlot.pins,
    if (hasDestinationManager) NavRouteManagerSlot.destination,
  };
}

/// Semantic role of a rendered route geometry package.
enum NavRouteGeometryRole {
  /// Blue path ahead of the vehicle — the primary path.
  remaining,

  /// Grey, already-driven path — distinct completed styling.
  completed,

  /// Full-route fallback (whole geometry) — must not remain primary blue
  /// beneath/next to the remaining path.
  fullFallback,

  /// Alternative route — must never use primary styling.
  alternative,
}

/// A rendered geometry with its owner identity and whether it is drawn with the
/// primary blue style (primary width + primary blue color).
class NavRenderedGeometry {
  const NavRenderedGeometry({
    required this.role,
    required this.primaryBlueStyle,
    required this.ownerSessionGeneration,
    required this.renderEpoch,
  });

  final NavRouteGeometryRole role;
  final bool primaryBlueStyle;
  final int ownerSessionGeneration;
  final int renderEpoch;
}

/// True when the currently rendered geometries satisfy the visual invariant:
/// exactly one primary-blue path owned by the current session/epoch, completed
/// styling stays distinct, and no alternative uses primary styling.
bool navSatisfiesSingleAuthoritativeBlueRoute(
  Iterable<NavRenderedGeometry> geometries, {
  required int currentSessionGeneration,
  required int currentRenderEpoch,
}) {
  // Alternatives can never be primary blue.
  final anyAlternativePrimaryBlue = geometries.any(
    (g) => g.role == NavRouteGeometryRole.alternative && g.primaryBlueStyle,
  );
  if (anyAlternativePrimaryBlue) return false;

  // Completed geometry must not be drawn primary-blue.
  final anyCompletedPrimaryBlue = geometries.any(
    (g) => g.role == NavRouteGeometryRole.completed && g.primaryBlueStyle,
  );
  if (anyCompletedPrimaryBlue) return false;

  // Exactly one primary-blue path owned by the current session + epoch.
  final currentPrimaryBlue = geometries.where(
    (g) =>
        g.primaryBlueStyle &&
        g.ownerSessionGeneration == currentSessionGeneration &&
        g.renderEpoch == currentRenderEpoch,
  );
  if (currentPrimaryBlue.length != 1) return false;

  // No stale-owner primary-blue geometry (orphan from a prior session/epoch).
  final stalePrimaryBlue = geometries.any(
    (g) =>
        g.primaryBlueStyle &&
        (g.ownerSessionGeneration != currentSessionGeneration ||
            g.renderEpoch != currentRenderEpoch),
  );
  if (stalePrimaryBlue) return false;

  return true;
}
