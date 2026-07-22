import '../driver_navigation_models.dart';
import '../driver_navigation_route_parser.dart';

export 'nav_ride_boundary_ownership.dart';

/// Where a prepared navigation route package was sourced from.
enum DriverRouteResponseSource {
  worker,
  workerReroute,
  mapboxDirect,

  /// Booking-worker overview polyline (geometry only; no nav steps).
  bookingWorkerOverview,
}

/// NAV-SIGNAL-P0B2 version semantics:
///
/// `_routeStepsVersion` (accepted route-content generation):
///   Increments only after a prepared package passes the final acceptance
///   guard and is activated. Used by complexity, reroute stabilization,
///   streetlevel/native-follow accepted-route ownership, and instruction
///   ownership. Hard clear must NOT increment this.
///
/// `_routeRenderEpoch` (async Mapbox render ownership):
///   Increments on accepted activation AND on hard-clear / render
///   invalidation so in-flight annotation draws become stale without
///   impersonating a newly accepted route.

/// Why a route builder started a network request.
enum DriverRouteApplyPurpose { overview, pickup, destination, direct, reroute }

/// Immutable prepared route result — parse only, no active-state mutation.
class DriverPreparedRoutePackage {
  final List<DriverLonLat> coords;
  final List<DriverNavStep> navSteps;
  final double distanceMeters;
  final int durationSeconds;
  final DriverRouteResponseSource source;
  final int geometryFingerprint;
  final int stepsWithBannerCount;
  final int stepsWithLaneGuidanceCount;

  const DriverPreparedRoutePackage({
    required this.coords,
    required this.navSteps,
    required this.distanceMeters,
    required this.durationSeconds,
    required this.source,
    required this.geometryFingerprint,
    this.stepsWithBannerCount = 0,
    this.stepsWithLaneGuidanceCount = 0,
  });

  bool get hasValidGeometry => coords.length >= 2;

  /// Live navigation replacements must carry steps with the geometry.
  /// Overview preview may activate geometry-only packages.
  bool get hasUsableSteps => navSteps.isNotEmpty;

  bool isAcceptableFor(DriverRouteApplyPurpose purpose) {
    if (!hasValidGeometry) return false;
    if (purpose == DriverRouteApplyPurpose.overview) return true;
    return hasUsableSteps;
  }
}

/// Captured at request start; compared at final acceptance.
class DriverRouteRequestContext {
  final int requestGeneration;
  final int cleanupEpoch;
  final DriverRouteApplyPurpose purpose;
  final String? expectedBookingId;
  final bool requireDirectRide;
  final String? expectedTripId;
  final bool expectDirectRideActive;

  const DriverRouteRequestContext({
    required this.requestGeneration,
    required this.cleanupEpoch,
    required this.purpose,
    this.expectedBookingId,
    this.requireDirectRide = false,
    this.expectedTripId,
    this.expectDirectRideActive = false,
  });
}

/// Live ownership/phase snapshot at acceptance time.
class DriverRouteAcceptanceSnapshot {
  final bool mounted;
  final int latestRequestGeneration;
  final int cleanupEpoch;
  final String? activeBookingId;
  final String? activeTripId;
  final bool directRideActive;
  final bool liveRideActive;

  const DriverRouteAcceptanceSnapshot({
    required this.mounted,
    required this.latestRequestGeneration,
    required this.cleanupEpoch,
    required this.activeBookingId,
    required this.activeTripId,
    required this.directRideActive,
    required this.liveRideActive,
  });
}

enum DriverRouteRejectReason {
  notMounted,
  staleGeneration,
  cleanupEpoch,
  bookingChanged,
  sessionChanged,
  phaseChanged,
  invalidPackage,
  emptySteps,
}

class DriverRouteAcceptanceDecision {
  final bool accepted;
  final DriverRouteRejectReason? reason;

  const DriverRouteAcceptanceDecision.accept() : accepted = true, reason = null;

  const DriverRouteAcceptanceDecision.reject(this.reason) : accepted = false;
}

/// Monotonic network-request generation (not the applied `_routeStepsVersion`).
class DriverRouteRequestGenerationClock {
  int _latest = 0;

  int get latest => _latest;

  /// Start a new authoritative route request.
  int begin() {
    _latest += 1;
    return _latest;
  }

  /// Invalidate every in-flight builder (clear/stop/session transition).
  int invalidateAll() {
    _latest += 1;
    return _latest;
  }
}

int driverRouteGeometryFingerprint(List<DriverLonLat> coords) {
  if (coords.length < 2) return 0;
  final first = coords.first;
  final mid = coords[coords.length ~/ 2];
  final last = coords.last;
  return Object.hash(
    coords.length,
    first.lat,
    first.lon,
    mid.lat,
    mid.lon,
    last.lat,
    last.lon,
  );
}

DriverPreparedRoutePackage prepareDriverRoutePackage({
  required DriverRouteParseResult parsed,
  required DriverRouteResponseSource source,
}) {
  return DriverPreparedRoutePackage(
    coords: List<DriverLonLat>.unmodifiable(parsed.coords),
    navSteps: List<DriverNavStep>.unmodifiable(parsed.navSteps),
    distanceMeters: parsed.distanceMeters,
    durationSeconds: parsed.durationSeconds,
    source: source,
    geometryFingerprint: driverRouteGeometryFingerprint(parsed.coords),
    stepsWithBannerCount: parsed.stepsWithBannerCount,
    stepsWithLaneGuidanceCount: parsed.stepsWithLaneGuidanceCount,
  );
}

/// Geometry-only overview package from the booking worker (empty nav steps).
DriverPreparedRoutePackage prepareBookingWorkerOverviewPackage({
  required List<DriverLonLat> coords,
  required double distanceMeters,
  required int durationSeconds,
}) {
  final frozen = List<DriverLonLat>.unmodifiable(coords);
  return DriverPreparedRoutePackage(
    coords: frozen,
    navSteps: const <DriverNavStep>[],
    distanceMeters: distanceMeters,
    durationSeconds: durationSeconds,
    source: DriverRouteResponseSource.bookingWorkerOverview,
    geometryFingerprint: driverRouteGeometryFingerprint(frozen),
  );
}

/// Pure dual counters for accepted route content vs async render ownership.
class DriverRouteVersionClocks {
  int _routeStepsVersion = 0;
  int _routeRenderEpoch = 0;

  int get routeStepsVersion => _routeStepsVersion;
  int get routeRenderEpoch => _routeRenderEpoch;

  /// Successful guarded activation: both counters advance (different concepts).
  ({int routeStepsVersion, int routeRenderEpoch}) activateAcceptedRoute() {
    _routeStepsVersion += 1;
    _routeRenderEpoch += 1;
    return (
      routeStepsVersion: _routeStepsVersion,
      routeRenderEpoch: _routeRenderEpoch,
    );
  }

  /// Hard clear / stop: invalidate drawings only — never a new accepted route.
  int invalidateRenderForHardClear() {
    _routeRenderEpoch += 1;
    return _routeRenderEpoch;
  }
}

/// @Deprecated Prefer [DriverRouteVersionClocks]. Kept for P0B1 test migration.
class DriverRouteAppliedRenderVersionClock {
  final DriverRouteVersionClocks _inner = DriverRouteVersionClocks();

  int get current => _inner.routeRenderEpoch;

  int activateAcceptedRoute() =>
      _inner.activateAcceptedRoute().routeRenderEpoch;

  int invalidateForHardClear() => _inner.invalidateRenderForHardClear();
}

/// Commit decision for operation-owned annotation creates.
enum DriverRouteAnnotationCommitAction {
  /// Captured version is stale: delete only locally created objects.
  abortDeleteLocalOnly,

  /// Captured version is still current: swap shared refs, then delete previous.
  commitSwapThenDeletePrevious,
}

class DriverRouteAnnotationCommitDecision {
  final DriverRouteAnnotationCommitAction action;

  const DriverRouteAnnotationCommitDecision(this.action);

  bool get shouldCommitShared =>
      action == DriverRouteAnnotationCommitAction.commitSwapThenDeletePrevious;

  bool get shouldDeleteLocalOrphansOnly =>
      action == DriverRouteAnnotationCommitAction.abortDeleteLocalOnly;
}

/// After local annotation creates complete, decide whether shared refs may swap.
DriverRouteAnnotationCommitDecision evaluateRouteAnnotationCommit({
  required int capturedRenderEpoch,
  required int currentRenderEpoch,
  int? capturedSessionGeneration,
  int? currentSessionGeneration,
}) {
  if (capturedSessionGeneration != null &&
      currentSessionGeneration != null &&
      capturedSessionGeneration != currentSessionGeneration) {
    return const DriverRouteAnnotationCommitDecision(
      DriverRouteAnnotationCommitAction.abortDeleteLocalOnly,
    );
  }
  if (shouldIgnoreStaleRouteDraw(
    drawAppliedRouteVersion: capturedRenderEpoch,
    currentAppliedRouteVersion: currentRenderEpoch,
  )) {
    return const DriverRouteAnnotationCommitDecision(
      DriverRouteAnnotationCommitAction.abortDeleteLocalOnly,
    );
  }
  return const DriverRouteAnnotationCommitDecision(
    DriverRouteAnnotationCommitAction.commitSwapThenDeletePrevious,
  );
}

/// Whether overview may clear prior overview annotations (never during live nav).
bool mayClearOverviewAnnotations({required bool liveRideActive}) {
  return !liveRideActive;
}

/// Style restore may redraw only when route content and render epoch remain valid.
///
/// NAV-RIDE-BOUNDARY: when session/style generations are supplied they must
/// also match, and navigation must remain live.
bool mayRestoreRouteRender({
  required int routeCoordCount,
  required int capturedRenderEpoch,
  required int currentRenderEpoch,
  int? capturedRouteStepsVersion,
  int? currentRouteStepsVersion,
  int? capturedSessionGeneration,
  int? currentSessionGeneration,
  int? capturedStyleGeneration,
  int? currentStyleGeneration,
  bool? navigationLive,
}) {
  if (routeCoordCount < 2) return false;
  if (navigationLive == false) return false;
  if (capturedSessionGeneration != null &&
      currentSessionGeneration != null &&
      capturedSessionGeneration != currentSessionGeneration) {
    return false;
  }
  if (capturedStyleGeneration != null &&
      currentStyleGeneration != null &&
      capturedStyleGeneration != currentStyleGeneration) {
    return false;
  }
  if (shouldIgnoreStaleRouteDraw(
    drawAppliedRouteVersion: capturedRenderEpoch,
    currentAppliedRouteVersion: currentRenderEpoch,
  )) {
    return false;
  }
  if (capturedRouteStepsVersion != null &&
      currentRouteStepsVersion != null &&
      capturedRouteStepsVersion != currentRouteStepsVersion) {
    return false;
  }
  return true;
}

String formatNavRouteRenderDiag({
  required String action,
  required String reason,
  required int renderEpoch,
  int? activeRouteVersion,
  int? sessionGeneration,
  int? styleGeneration,
}) {
  final routePart = activeRouteVersion == null
      ? ''
      : ' activeRouteVersion=$activeRouteVersion';
  final sessionPart = sessionGeneration == null
      ? ''
      : ' sessionGeneration=$sessionGeneration';
  final stylePart = styleGeneration == null
      ? ''
      : ' styleGeneration=$styleGeneration';
  return '[NAV_ROUTE_RENDER] '
      'action=$action '
      'reason=$reason '
      'renderEpoch=$renderEpoch'
      '$routePart'
      '$sessionPart'
      '$stylePart';
}

bool purposeStillValidForSnapshot({
  required DriverRouteApplyPurpose purpose,
  required DriverRouteAcceptanceSnapshot snapshot,
  required bool requireDirectRide,
}) {
  switch (purpose) {
    case DriverRouteApplyPurpose.overview:
      // Overview must not overwrite a live navigation session.
      return !snapshot.liveRideActive;
    case DriverRouteApplyPurpose.pickup:
      // Pickup is only valid before a trip session starts.
      return snapshot.activeTripId == null && !snapshot.directRideActive;
    case DriverRouteApplyPurpose.destination:
      return snapshot.activeTripId != null && !snapshot.directRideActive;
    case DriverRouteApplyPurpose.direct:
      return snapshot.directRideActive;
    case DriverRouteApplyPurpose.reroute:
      if (requireDirectRide || snapshot.directRideActive) {
        return snapshot.directRideActive;
      }
      if (snapshot.activeTripId != null) return true;
      // Reroute to pickup while approaching pickup.
      return snapshot.activeBookingId != null && snapshot.activeTripId == null;
  }
}

DriverRouteAcceptanceDecision evaluateDriverRouteAcceptance({
  required DriverRouteRequestContext context,
  required DriverRouteAcceptanceSnapshot snapshot,
  required DriverPreparedRoutePackage? package,
}) {
  if (!snapshot.mounted) {
    return const DriverRouteAcceptanceDecision.reject(
      DriverRouteRejectReason.notMounted,
    );
  }
  if (package == null || !package.hasValidGeometry) {
    return const DriverRouteAcceptanceDecision.reject(
      DriverRouteRejectReason.invalidPackage,
    );
  }
  if (!package.isAcceptableFor(context.purpose)) {
    return const DriverRouteAcceptanceDecision.reject(
      DriverRouteRejectReason.emptySteps,
    );
  }
  if (context.requestGeneration != snapshot.latestRequestGeneration) {
    return const DriverRouteAcceptanceDecision.reject(
      DriverRouteRejectReason.staleGeneration,
    );
  }
  if (context.cleanupEpoch != snapshot.cleanupEpoch) {
    return const DriverRouteAcceptanceDecision.reject(
      DriverRouteRejectReason.cleanupEpoch,
    );
  }
  if (context.expectedBookingId != null) {
    final active = snapshot.activeBookingId;
    if (active == null || active != context.expectedBookingId) {
      return const DriverRouteAcceptanceDecision.reject(
        DriverRouteRejectReason.bookingChanged,
      );
    }
  }
  if (context.requireDirectRide || context.expectDirectRideActive) {
    if (!snapshot.directRideActive) {
      return const DriverRouteAcceptanceDecision.reject(
        DriverRouteRejectReason.sessionChanged,
      );
    }
  }
  if (context.expectedTripId != null) {
    final trip = snapshot.activeTripId;
    if (trip == null || trip != context.expectedTripId) {
      return const DriverRouteAcceptanceDecision.reject(
        DriverRouteRejectReason.sessionChanged,
      );
    }
  }
  if (!purposeStillValidForSnapshot(
    purpose: context.purpose,
    snapshot: snapshot,
    requireDirectRide: context.requireDirectRide,
  )) {
    return const DriverRouteAcceptanceDecision.reject(
      DriverRouteRejectReason.phaseChanged,
    );
  }
  return const DriverRouteAcceptanceDecision.accept();
}

String driverRouteRejectReasonToken(DriverRouteRejectReason reason) {
  switch (reason) {
    case DriverRouteRejectReason.notMounted:
      return 'not_mounted';
    case DriverRouteRejectReason.staleGeneration:
      return 'stale_generation';
    case DriverRouteRejectReason.cleanupEpoch:
      return 'cleanup_epoch';
    case DriverRouteRejectReason.bookingChanged:
      return 'booking_changed';
    case DriverRouteRejectReason.sessionChanged:
      return 'session_changed';
    case DriverRouteRejectReason.phaseChanged:
      return 'phase_changed';
    case DriverRouteRejectReason.invalidPackage:
      return 'invalid_package';
    case DriverRouteRejectReason.emptySteps:
      return 'empty_steps';
  }
}

/// Bounded non-PII diagnostic line for [NAV_ROUTE_APPLY].
String formatNavRouteApplyDiag({
  required int requestGeneration,
  required int latestGeneration,
  required bool accepted,
  DriverRouteRejectReason? reason,
  int? routeVersion,
  int? renderEpoch,
  @Deprecated('Use routeVersion') int? appliedRouteVersion,
}) {
  final reasonToken = reason == null
      ? 'ok'
      : driverRouteRejectReasonToken(reason);
  final rv = routeVersion ?? appliedRouteVersion;
  final versionPart = rv == null ? '' : ' routeVersion=$rv';
  final epochPart = renderEpoch == null ? '' : ' renderEpoch=$renderEpoch';
  return '[NAV_ROUTE_APPLY] '
      'requestGeneration=$requestGeneration '
      'latestGeneration=$latestGeneration '
      'accepted=$accepted '
      'reason=$reasonToken'
      '$versionPart'
      '$epochPart';
}

/// Async Mapbox draw/annotation completion must not land on a newer route.
bool shouldIgnoreStaleRouteDraw({
  required int drawAppliedRouteVersion,
  required int currentAppliedRouteVersion,
}) {
  return drawAppliedRouteVersion != currentAppliedRouteVersion;
}
