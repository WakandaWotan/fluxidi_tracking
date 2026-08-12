/// NAV-PHASE-CAMERA-TARGET-1: pure decisions for the single deterministic
/// camera contract that must be identical across every route phase.
///
/// Field-proven defect on commit c241f39 (tablet): the screen-fixed HUD Car
/// stayed put, but the map beneath it did not — because the prepared and the
/// active phases each used a different camera writer, different target
/// coordinate, and different zoom.
///
///  * The prepared preview centred the camera on the raw driver GPS while the
///    route polyline started at the booking pickup A, so the route did not
///    originate at the HUD nose and could point sideways.
///  * The recenter button called into `DriverNavCameraPolicy`, which computed
///    a speed-band zoom (~17.0–17.6) and bypassed the fixed L7 cockpit
///    profile whenever `_liveRideActive == false`. Pressing recenter in a
///    prepared route therefore mutated zoom and repositioned the map.
///  * The camera policy resolved `follow=false reason=inactive` for prepared
///    and toPickup phases, and `manual_recenter` was the only way through
///    that gate — reintroducing the wrong zoom.
///  * Map gestures locked only zoom; pan, rotate and pitch stayed active, so
///    a stray touch could pan or rotate the camera underneath the fixed HUD.
///
/// This module is the single source of truth for four decisions that must
/// agree in prepared booking, prepared street draft, NAV-to-pickup A and
/// active customer ride A→B:
///
///   1. which geographic coordinate the camera targets;
///   2. which Mapbox gestures are enabled;
///   3. whether the recenter button is offered at all;
///   4. whether a manual `user_recenter` command is allowed to mutate the
///      camera (never in a route phase).
///
/// Pure Dart, no Mapbox handles, no widget state, no I/O.
library;

import 'nav_fixed_hud_presentation.dart';

/// Where a resolved camera target came from. Bounded diagnostic use only.
enum NavPhaseCameraTargetSource {
  /// The prepared A→B booking pickup coordinate.
  pickupA,

  /// The first usable point on the accepted route polyline. Used as fallback
  /// when a pickup coordinate is unavailable and as the primary target for a
  /// prepared street draft (driver is already at A).
  firstRoutePoint,

  /// The snapped position on the accepted route. Used during guidance and
  /// live rides so the HUD nose always sits on top of the route line.
  snappedProgress,

  /// The raw driver GPS. Only used when nothing more reliable exists.
  driverGps,

  /// No usable coordinate; caller must not command the camera.
  none,
}

/// Bounded, PII-free label for [NavPhaseCameraTargetSource].
String navPhaseCameraTargetSourceLabel(NavPhaseCameraTargetSource source) {
  switch (source) {
    case NavPhaseCameraTargetSource.pickupA:
      return 'pickup_a';
    case NavPhaseCameraTargetSource.firstRoutePoint:
      return 'first_route_point';
    case NavPhaseCameraTargetSource.snappedProgress:
      return 'snapped_progress';
    case NavPhaseCameraTargetSource.driverGps:
      return 'driver_gps';
    case NavPhaseCameraTargetSource.none:
      return 'none';
  }
}

/// Resolved camera target coordinate + provenance.
class NavPhaseCameraTarget {
  const NavPhaseCameraTarget({
    required this.lat,
    required this.lon,
    required this.source,
  });

  final double lat;
  final double lon;
  final NavPhaseCameraTargetSource source;

  /// True when a caller may issue a camera command from this target.
  bool get hasCoordinate => source != NavPhaseCameraTargetSource.none;
}

bool _usable(double? v) => v != null && v.isFinite;

/// Resolves the single camera target coordinate for the current route phase.
///
/// Selection rules (in precedence order per phase):
///
///  * `preparedRoute` with `hasPickup == true` (prepared booking A→B):
///    `firstRoutePoint` → `pickupA`. The first usable A→B route geometry
///    point wins over the raw geocoded pickup A, because a geocoded pickup
///    coordinate can sit inside a building, driveway or parking area — the
///    route polyline does not leave from that exact pin, so anchoring the
///    HUD on the raw pickup would visually detach the route from the nose.
///    Once the route has loaded, the first route point IS the visible route
///    start and matches the HUD nose exactly. Pickup A remains the fallback
///    for the brief window before route geometry arrives. The camera must
///    NEVER target the raw driver GPS in this phase — that is what put the
///    HUD off the route in the field failure.
///  * `preparedRoute` without pickup (prepared direct street draft):
///    `firstRoutePoint` → `snappedProgress` → `driverGps`. All three should
///    coincide when the driver is at A; the ordering guarantees the HUD nose
///    sits on the route line even if the driver has drifted slightly.
///  * `toPickup` (unmetered NAV): `snappedProgress` → `driverGps` →
///    `firstRoutePoint`.
///  * `liveRide` (A→B metered): `snappedProgress` → `driverGps` →
///    `firstRoutePoint`.
///  * `idle`: none.
NavPhaseCameraTarget resolveNavPhaseCameraTarget({
  required NavFixedHudPhase phase,
  required bool hasPickup,
  double? pickupLat,
  double? pickupLon,
  double? firstRouteLat,
  double? firstRouteLon,
  double? snappedLat,
  double? snappedLon,
  double? driverLat,
  double? driverLon,
}) {
  NavPhaseCameraTarget? pickup() {
    if (!hasPickup) return null;
    if (!_usable(pickupLat) || !_usable(pickupLon)) return null;
    return NavPhaseCameraTarget(
      lat: pickupLat!,
      lon: pickupLon!,
      source: NavPhaseCameraTargetSource.pickupA,
    );
  }

  NavPhaseCameraTarget? firstRoute() {
    if (!_usable(firstRouteLat) || !_usable(firstRouteLon)) return null;
    return NavPhaseCameraTarget(
      lat: firstRouteLat!,
      lon: firstRouteLon!,
      source: NavPhaseCameraTargetSource.firstRoutePoint,
    );
  }

  NavPhaseCameraTarget? snapped() {
    if (!_usable(snappedLat) || !_usable(snappedLon)) return null;
    return NavPhaseCameraTarget(
      lat: snappedLat!,
      lon: snappedLon!,
      source: NavPhaseCameraTargetSource.snappedProgress,
    );
  }

  NavPhaseCameraTarget? driver() {
    if (!_usable(driverLat) || !_usable(driverLon)) return null;
    return NavPhaseCameraTarget(
      lat: driverLat!,
      lon: driverLon!,
      source: NavPhaseCameraTargetSource.driverGps,
    );
  }

  const none = NavPhaseCameraTarget(
    lat: 0.0,
    lon: 0.0,
    source: NavPhaseCameraTargetSource.none,
  );

  switch (phase) {
    case NavFixedHudPhase.idle:
      return none;
    case NavFixedHudPhase.preparedRoute:
      if (hasPickup) {
        return firstRoute() ?? pickup() ?? none;
      }
      return firstRoute() ?? snapped() ?? driver() ?? none;
    case NavFixedHudPhase.toPickup:
    case NavFixedHudPhase.liveRide:
      return snapped() ?? driver() ?? firstRoute() ?? none;
  }
}

/// Mapbox gesture settings for the fixed HUD surface. Extends the existing
/// zoom-only lock with pan / rotate / pitch, because the fixed HUD contract
/// requires the map to be non-interactive underneath it in every route phase
/// — otherwise a stray touch shifts the map beneath the screen-fixed marker.
class NavPhaseGestureLock {
  const NavPhaseGestureLock({
    required this.pinchToZoomEnabled,
    required this.doubleTapToZoomInEnabled,
    required this.doubleTouchToZoomOutEnabled,
    required this.quickZoomEnabled,
    required this.scrollEnabled,
    required this.rotateEnabled,
    required this.pitchEnabled,
  });

  final bool pinchToZoomEnabled;
  final bool doubleTapToZoomInEnabled;
  final bool doubleTouchToZoomOutEnabled;
  final bool quickZoomEnabled;

  /// Mapbox pan gesture (single-finger drag).
  final bool scrollEnabled;

  final bool rotateEnabled;
  final bool pitchEnabled;

  bool get allInteractionsDisabled =>
      !pinchToZoomEnabled &&
      !doubleTapToZoomInEnabled &&
      !doubleTouchToZoomOutEnabled &&
      !quickZoomEnabled &&
      !scrollEnabled &&
      !rotateEnabled &&
      !pitchEnabled;

  bool get allZoomGesturesDisabled =>
      !pinchToZoomEnabled &&
      !doubleTapToZoomInEnabled &&
      !doubleTouchToZoomOutEnabled &&
      !quickZoomEnabled;
}

/// Every interaction that could move, rotate, tilt or scale the map is
/// disabled for a route phase; the idle phase keeps Mapbox platform defaults.
NavPhaseGestureLock resolveNavPhaseGestureLock({
  required NavFixedHudPhase phase,
}) {
  if (phase == NavFixedHudPhase.idle) {
    return const NavPhaseGestureLock(
      pinchToZoomEnabled: true,
      doubleTapToZoomInEnabled: true,
      doubleTouchToZoomOutEnabled: true,
      quickZoomEnabled: true,
      scrollEnabled: true,
      rotateEnabled: true,
      pitchEnabled: true,
    );
  }
  return const NavPhaseGestureLock(
    pinchToZoomEnabled: false,
    doubleTapToZoomInEnabled: false,
    doubleTouchToZoomOutEnabled: false,
    quickZoomEnabled: false,
    scrollEnabled: false,
    rotateEnabled: false,
    pitchEnabled: false,
  );
}

/// True when the recenter button must be offered. Every route phase resolves
/// the camera deterministically from the phase target, so there is nothing
/// to "recenter" — offering the button was itself a bug because pressing it
/// forced a manual zoom-mutating camera command.
bool navPhaseRecenterVisible({required NavFixedHudPhase phase}) {
  return phase == NavFixedHudPhase.idle;
}

/// True when a user-issued `manual_recenter` / `user_recenter` command is
/// allowed to write the Mapbox camera. Always false during a route phase; the
/// fixed HUD contract owns the camera and no manual writer may mutate it.
bool navPhaseManualCameraMutationAllowed({required NavFixedHudPhase phase}) {
  return phase == NavFixedHudPhase.idle;
}

/// FLUXIDI-PRESTART-VIEWPORT-TARGET-PRESERVE-P0: true when [source] is a
/// durable prepared-route / route-projected preview center (never raw GPS).
bool isAuthoritativePrestartPreviewTargetSource(
  NavPhaseCameraTargetSource source,
) {
  switch (source) {
    case NavPhaseCameraTargetSource.pickupA:
    case NavPhaseCameraTargetSource.firstRoutePoint:
    case NavPhaseCameraTargetSource.snappedProgress:
      return true;
    case NavPhaseCameraTargetSource.driverGps:
    case NavPhaseCameraTargetSource.none:
      return false;
  }
}

/// True when [target] may be latched as the pre-START geographic camera center.
bool canLatchPrestartPreviewCameraTarget(NavPhaseCameraTarget target) {
  return target.hasCoordinate &&
      isAuthoritativePrestartPreviewTargetSource(target.source);
}

/// Viewport-only resize must not silently replace a valid prepared-route
/// preview center with raw [NavPhaseCameraTargetSource.driverGps].
///
/// Field evidence (`viewport_reseed_prestart`): PiP / split return can flip
/// phase toward `toPickup` so `resolveNavPhaseCameraTarget` briefly prefers
/// snapped → driver while the accepted route still exists (~12 m offset).
/// [isViewportReseed] reuses the latched authoritative target when present.
/// Non-reseed calls still fall back to the latched route target when the
/// live resolve collapses to driver GPS / none.
NavPhaseCameraTarget resolvePrestartPreviewTargetAcrossViewportResize({
  required NavPhaseCameraTarget resolved,
  NavPhaseCameraTarget? latched,
  required bool isViewportReseed,
}) {
  if (latched == null || !canLatchPrestartPreviewCameraTarget(latched)) {
    return resolved;
  }
  if (isViewportReseed) {
    return latched;
  }
  if (!resolved.hasCoordinate ||
      resolved.source == NavPhaseCameraTargetSource.driverGps) {
    return latched;
  }
  return resolved;
}
