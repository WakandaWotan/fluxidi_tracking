// NAV-RIDE-BOUNDARY-ROUTE-OWNERSHIP-1
//
// Pure ownership clocks and decisions that guarantee a new navigation
// session never restores or mutates route visuals belonging to a prior ride.
// Mapbox/Flutter wiring stays in driver_home_page_state; this file owns the
// authority model and PII-free diagnostics.

/// Monotonic ride/session identity. Bumped on every ride boundary.
class NavigationSessionGenerationClock {
  int _generation = 0;

  int get current => _generation;

  /// Invalidate the prior session and open a new ownership generation.
  int bump() {
    _generation += 1;
    return _generation;
  }
}

/// Monotonic style-request generation. When N+1 begins, N is stale immediately.
class StyleRequestGenerationClock {
  int _generation = 0;

  int get current => _generation;

  int begin() {
    _generation += 1;
    return _generation;
  }
}

/// Single active route-render package per navigation session.
///
/// Owns full / completed / remaining geometry slots together with the
/// generations that authorize mutation.
class RouteRenderOwnerPackage {
  final int sessionGeneration;
  final int styleGeneration;
  final int routeVersion;
  final int renderEpoch;
  final bool hasFullRoute;
  final bool hasCompletedRoute;
  final bool hasRemainingRoute;
  final bool hasDestinationMarker;
  final bool hasManeuverBannerState;
  final bool hasLaneState;

  const RouteRenderOwnerPackage({
    required this.sessionGeneration,
    required this.styleGeneration,
    required this.routeVersion,
    required this.renderEpoch,
    this.hasFullRoute = false,
    this.hasCompletedRoute = false,
    this.hasRemainingRoute = false,
    this.hasDestinationMarker = false,
    this.hasManeuverBannerState = false,
    this.hasLaneState = false,
  });

  bool get isEmpty =>
      !hasFullRoute &&
      !hasCompletedRoute &&
      !hasRemainingRoute &&
      !hasDestinationMarker &&
      !hasManeuverBannerState &&
      !hasLaneState;

  /// Atomically replace this package with [next].
  RouteRenderOwnerPackage replacedBy(RouteRenderOwnerPackage next) => next;

  RouteRenderOwnerPackage cleared({
    required int sessionGeneration,
    required int styleGeneration,
    required int routeVersion,
    required int renderEpoch,
  }) {
    return RouteRenderOwnerPackage(
      sessionGeneration: sessionGeneration,
      styleGeneration: styleGeneration,
      routeVersion: routeVersion,
      renderEpoch: renderEpoch,
    );
  }
}

enum NavRideBoundaryEvent {
  sessionStarted,
  priorSessionInvalidated,
  routeStateCleared,
  newRouteActivated,
}

enum NavRouteRenderOwnerEvent {
  activated,
  replaced,
  staleCallbackIgnored,
  styleRestoreAllowed,
  styleRestoreRejected,
  cleared,
}

enum StyleRestoreRejectReason {
  navigationNotLive,
  sessionMismatch,
  styleMismatch,
  renderEpochMismatch,
  routeVersionMismatch,
  emptyGeometry,
  packageOwnerMismatch,
}

class StyleRestoreDecision {
  final bool allowed;
  final StyleRestoreRejectReason? reason;

  const StyleRestoreDecision.allow() : allowed = true, reason = null;

  const StyleRestoreDecision.reject(this.reason) : allowed = false;
}

/// Captured ownership token for an async style/route operation.
///
/// NAV-PRESTART-FIELD-BLOCKER-3 (Problem A): [previewRestoreEligible] lets a
/// pre-start preview draft with an accepted route (>=2 coords, not live)
/// participate in style-restore. It never widens the live-ride contract; the
/// existing session/style/render-epoch owners still gate every redraw.
class NavRouteOwnershipCapture {
  final int sessionGeneration;
  final int styleGeneration;
  final int routeVersion;
  final int renderEpoch;
  final bool navigationLive;
  final int routeCoordCount;
  final bool previewRestoreEligible;

  const NavRouteOwnershipCapture({
    required this.sessionGeneration,
    required this.styleGeneration,
    required this.routeVersion,
    required this.renderEpoch,
    required this.navigationLive,
    required this.routeCoordCount,
    this.previewRestoreEligible = false,
  });
}

/// Live ownership snapshot compared against a capture.
///
/// NAV-PRESTART-FIELD-BLOCKER-3 (Problem A): mirrors
/// [NavRouteOwnershipCapture.previewRestoreEligible] so restore is only
/// allowed when both capture and current live snapshot still qualify as either
/// a live ride or a valid pre-start preview draft.
class NavRouteOwnershipSnapshot {
  final int sessionGeneration;
  final int styleGeneration;
  final int routeVersion;
  final int renderEpoch;
  final bool navigationLive;
  final int? activePackageSessionGeneration;
  final int? activePackageRenderEpoch;
  final bool previewRestoreEligible;

  const NavRouteOwnershipSnapshot({
    required this.sessionGeneration,
    required this.styleGeneration,
    required this.routeVersion,
    required this.renderEpoch,
    required this.navigationLive,
    this.activePackageSessionGeneration,
    this.activePackageRenderEpoch,
    this.previewRestoreEligible = false,
  });
}

/// Style-loaded restore is allowed only when every captured owner still matches
/// and navigation is either live OR a valid pre-start preview draft owns the
/// route. Never reads mutable "current route" from an old callback — callers
/// must pass frozen capture + live snapshot.
StyleRestoreDecision evaluateStyleRouteRestore({
  required NavRouteOwnershipCapture capture,
  required NavRouteOwnershipSnapshot current,
}) {
  final captureAllowsRestore =
      capture.navigationLive || capture.previewRestoreEligible;
  final currentAllowsRestore =
      current.navigationLive || current.previewRestoreEligible;
  if (!captureAllowsRestore || !currentAllowsRestore) {
    return const StyleRestoreDecision.reject(
      StyleRestoreRejectReason.navigationNotLive,
    );
  }
  if (capture.routeCoordCount < 2) {
    return const StyleRestoreDecision.reject(
      StyleRestoreRejectReason.emptyGeometry,
    );
  }
  if (capture.sessionGeneration != current.sessionGeneration) {
    return const StyleRestoreDecision.reject(
      StyleRestoreRejectReason.sessionMismatch,
    );
  }
  if (capture.styleGeneration != current.styleGeneration) {
    return const StyleRestoreDecision.reject(
      StyleRestoreRejectReason.styleMismatch,
    );
  }
  if (capture.renderEpoch != current.renderEpoch) {
    return const StyleRestoreDecision.reject(
      StyleRestoreRejectReason.renderEpochMismatch,
    );
  }
  if (capture.routeVersion != current.routeVersion) {
    return const StyleRestoreDecision.reject(
      StyleRestoreRejectReason.routeVersionMismatch,
    );
  }
  if (current.activePackageSessionGeneration != null &&
      current.activePackageSessionGeneration != capture.sessionGeneration) {
    return const StyleRestoreDecision.reject(
      StyleRestoreRejectReason.packageOwnerMismatch,
    );
  }
  if (current.activePackageRenderEpoch != null &&
      current.activePackageRenderEpoch != capture.renderEpoch) {
    return const StyleRestoreDecision.reject(
      StyleRestoreRejectReason.packageOwnerMismatch,
    );
  }
  return const StyleRestoreDecision.allow();
}

/// Annotation commit must match session + render epoch.
enum RouteAnnotationOwnerCommitAction {
  abortDeleteLocalOnly,
  commitSwapThenDeletePrevious,
}

class RouteAnnotationOwnerCommitDecision {
  final RouteAnnotationOwnerCommitAction action;
  final StyleRestoreRejectReason? rejectReason;

  const RouteAnnotationOwnerCommitDecision.commit()
    : action = RouteAnnotationOwnerCommitAction.commitSwapThenDeletePrevious,
      rejectReason = null;

  const RouteAnnotationOwnerCommitDecision.abort(this.rejectReason)
    : action = RouteAnnotationOwnerCommitAction.abortDeleteLocalOnly;

  bool get shouldCommitShared =>
      action == RouteAnnotationOwnerCommitAction.commitSwapThenDeletePrevious;

  bool get shouldDeleteLocalOrphansOnly =>
      action == RouteAnnotationOwnerCommitAction.abortDeleteLocalOnly;
}

RouteAnnotationOwnerCommitDecision evaluateOwnedRouteAnnotationCommit({
  required int capturedSessionGeneration,
  required int currentSessionGeneration,
  required int capturedRenderEpoch,
  required int currentRenderEpoch,
}) {
  if (capturedSessionGeneration != currentSessionGeneration) {
    return const RouteAnnotationOwnerCommitDecision.abort(
      StyleRestoreRejectReason.sessionMismatch,
    );
  }
  if (capturedRenderEpoch != currentRenderEpoch) {
    return const RouteAnnotationOwnerCommitDecision.abort(
      StyleRestoreRejectReason.renderEpochMismatch,
    );
  }
  return const RouteAnnotationOwnerCommitDecision.commit();
}

/// Logical hard-clear payload for ride-boundary reset (idempotent).
class RideBoundaryClearState {
  final bool routeGeometryCleared;
  final bool completedRouteCleared;
  final bool remainingRouteCleared;
  final bool alternativeRouteCleared;
  final bool destinationMarkerCleared;
  final bool routeAnnotationsCleared;
  final bool maneuverBannerCleared;
  final bool laneStateCleared;
  final bool routeProgressReset;
  final bool rerouteTrackerReset;
  final bool styleRestoreInvalidated;
  final bool priorSessionInvalidated;
  final int sessionGeneration;
  final int styleGeneration;
  final int routeVersion;
  final int renderEpoch;

  const RideBoundaryClearState({
    required this.routeGeometryCleared,
    required this.completedRouteCleared,
    required this.remainingRouteCleared,
    required this.alternativeRouteCleared,
    required this.destinationMarkerCleared,
    required this.routeAnnotationsCleared,
    required this.maneuverBannerCleared,
    required this.laneStateCleared,
    required this.routeProgressReset,
    required this.rerouteTrackerReset,
    required this.styleRestoreInvalidated,
    required this.priorSessionInvalidated,
    required this.sessionGeneration,
    required this.styleGeneration,
    required this.routeVersion,
    required this.renderEpoch,
  });

  bool get isFullyCleared =>
      routeGeometryCleared &&
      completedRouteCleared &&
      remainingRouteCleared &&
      alternativeRouteCleared &&
      destinationMarkerCleared &&
      routeAnnotationsCleared &&
      maneuverBannerCleared &&
      laneStateCleared &&
      routeProgressReset &&
      rerouteTrackerReset &&
      styleRestoreInvalidated &&
      priorSessionInvalidated;
}

/// Apply an idempotent hard clear against mutable logical slots.
///
/// [hadVisibleRoute] / similar flags describe pre-clear presence; the result
/// always reports cleared=true so repeated clears stay idempotent.
RideBoundaryClearState applyRideBoundaryHardClear({
  required int sessionGeneration,
  required int styleGeneration,
  required int routeVersion,
  required int renderEpoch,
  // Presence flags document pre-clear occupancy for callers/tests; the clear
  // itself is always idempotent and reports success regardless.
  bool hadFullRoute = false,
  bool hadCompletedRoute = false,
  bool hadRemainingRoute = false,
  bool hadAlternativeRoute = false,
  bool hadDestinationMarker = false,
  bool hadRouteAnnotations = false,
  bool hadManeuverBanner = false,
  bool hadLaneState = false,
  bool hadRouteProgress = false,
  bool hadRerouteTrackerState = false,
  bool hadPendingStyleRestore = false,
  bool priorSessionWasActive = false,
}) {
  // Keep named presence args part of the public API for call-site clarity.
  final _ = (
    hadFullRoute,
    hadCompletedRoute,
    hadRemainingRoute,
    hadAlternativeRoute,
    hadDestinationMarker,
    hadRouteAnnotations,
    hadManeuverBanner,
    hadLaneState,
    hadRouteProgress,
    hadRerouteTrackerState,
    hadPendingStyleRestore,
    priorSessionWasActive,
  );
  return RideBoundaryClearState(
    routeGeometryCleared: true,
    completedRouteCleared: true,
    remainingRouteCleared: true,
    alternativeRouteCleared: true,
    destinationMarkerCleared: true,
    routeAnnotationsCleared: true,
    maneuverBannerCleared: true,
    laneStateCleared: true,
    routeProgressReset: true,
    rerouteTrackerReset: true,
    styleRestoreInvalidated: true,
    priorSessionInvalidated: true,
    sessionGeneration: sessionGeneration,
    styleGeneration: styleGeneration,
    routeVersion: routeVersion,
    renderEpoch: renderEpoch,
  );
}

/// In-memory simulator used by deterministic ownership tests.
class RideBoundaryOwnershipSimulator {
  final NavigationSessionGenerationClock sessionClock =
      NavigationSessionGenerationClock();
  final StyleRequestGenerationClock styleClock = StyleRequestGenerationClock();
  int routeVersion = 0;
  int renderEpoch = 0;

  RouteRenderOwnerPackage? activePackage;
  List<String> fullRouteGeometry = <String>[];
  List<String> completedRouteGeometry = <String>[];
  List<String> remainingRouteGeometry = <String>[];
  List<String> alternativeRouteGeometry = <String>[];
  bool hasDestinationMarker = false;
  bool hasManeuverBanner = false;
  bool hasLaneState = false;
  bool hasRouteProgress = false;
  bool hasRerouteTrackerState = false;
  bool navigationLive = false;
  int oppositeDirectionSamples = 0;
  int wrongStreetSamples = 0;
  DateTime? strongEvidenceAt;
  int successfulRerouteCooldownOwnerSession = 0;

  final List<String> events = <String>[];

  int beginNewSession({required String reason}) {
    final prior = sessionClock.current;
    final next = sessionClock.bump();
    if (prior > 0) {
      events.add(
        formatNavRideBoundaryDiag(
          event: NavRideBoundaryEvent.priorSessionInvalidated,
          sessionGeneration: next,
          styleGeneration: styleClock.current,
          routeVersion: routeVersion,
          renderEpoch: renderEpoch,
        ),
      );
    }
    final clear = hardClear(reason: reason);
    navigationLive = true;
    events.add(
      formatNavRideBoundaryDiag(
        event: NavRideBoundaryEvent.sessionStarted,
        sessionGeneration: next,
        styleGeneration: styleClock.current,
        routeVersion: routeVersion,
        renderEpoch: renderEpoch,
      ),
    );
    assert(clear.isFullyCleared);
    return next;
  }

  void stopSession({required String reason}) {
    hardClear(reason: reason);
    navigationLive = false;
    sessionClock.bump();
    events.add(
      formatNavRideBoundaryDiag(
        event: NavRideBoundaryEvent.priorSessionInvalidated,
        sessionGeneration: sessionClock.current,
        styleGeneration: styleClock.current,
        routeVersion: routeVersion,
        renderEpoch: renderEpoch,
      ),
    );
  }

  RideBoundaryClearState hardClear({required String reason}) {
    renderEpoch += 1;
    final clear = applyRideBoundaryHardClear(
      sessionGeneration: sessionClock.current,
      styleGeneration: styleClock.current,
      routeVersion: routeVersion,
      renderEpoch: renderEpoch,
      hadFullRoute: fullRouteGeometry.isNotEmpty,
      hadCompletedRoute: completedRouteGeometry.isNotEmpty,
      hadRemainingRoute: remainingRouteGeometry.isNotEmpty,
      hadAlternativeRoute: alternativeRouteGeometry.isNotEmpty,
      hadDestinationMarker: hasDestinationMarker,
      hadRouteAnnotations: activePackage != null,
      hadManeuverBanner: hasManeuverBanner,
      hadLaneState: hasLaneState,
      hadRouteProgress: hasRouteProgress,
      hadRerouteTrackerState: hasRerouteTrackerState,
      hadPendingStyleRestore: true,
      priorSessionWasActive: navigationLive || activePackage != null,
    );
    fullRouteGeometry = <String>[];
    completedRouteGeometry = <String>[];
    remainingRouteGeometry = <String>[];
    alternativeRouteGeometry = <String>[];
    hasDestinationMarker = false;
    hasManeuverBanner = false;
    hasLaneState = false;
    hasRouteProgress = false;
    hasRerouteTrackerState = false;
    oppositeDirectionSamples = 0;
    wrongStreetSamples = 0;
    strongEvidenceAt = null;
    successfulRerouteCooldownOwnerSession = 0;
    activePackage = RouteRenderOwnerPackage(
      sessionGeneration: sessionClock.current,
      styleGeneration: styleClock.current,
      routeVersion: routeVersion,
      renderEpoch: renderEpoch,
    );
    events.add(
      formatNavRideBoundaryDiag(
        event: NavRideBoundaryEvent.routeStateCleared,
        sessionGeneration: sessionClock.current,
        styleGeneration: styleClock.current,
        routeVersion: routeVersion,
        renderEpoch: renderEpoch,
        extra: 'reason=$reason',
      ),
    );
    events.add(
      formatNavRouteRenderOwnerDiag(
        event: NavRouteRenderOwnerEvent.cleared,
        sessionGeneration: sessionClock.current,
        styleGeneration: styleClock.current,
        routeVersion: routeVersion,
        renderEpoch: renderEpoch,
      ),
    );
    return clear;
  }

  int beginStyleRequest() => styleClock.begin();

  /// Activate a new route package, atomically replacing any previous owner.
  RouteRenderOwnerPackage activateRoute({
    required String routeId,
    bool withCompleted = false,
    bool withRemaining = true,
    bool withDestination = true,
    bool withBanner = true,
    bool withLane = true,
  }) {
    routeVersion += 1;
    renderEpoch += 1;
    final previous = activePackage;
    final next = RouteRenderOwnerPackage(
      sessionGeneration: sessionClock.current,
      styleGeneration: styleClock.current,
      routeVersion: routeVersion,
      renderEpoch: renderEpoch,
      hasFullRoute: true,
      hasCompletedRoute: withCompleted,
      hasRemainingRoute: withRemaining,
      hasDestinationMarker: withDestination,
      hasManeuverBannerState: withBanner,
      hasLaneState: withLane,
    );
    // Atomic replace: old geometry slots are dropped before new ones land.
    fullRouteGeometry = <String>[routeId];
    completedRouteGeometry = withCompleted
        ? <String>['${routeId}_completed']
        : <String>[];
    remainingRouteGeometry = withRemaining
        ? <String>['${routeId}_remaining']
        : <String>[];
    alternativeRouteGeometry = <String>[];
    hasDestinationMarker = withDestination;
    hasManeuverBanner = withBanner;
    hasLaneState = withLane;
    hasRouteProgress = true;
    activePackage = previous == null ? next : previous.replacedBy(next);
    events.add(
      formatNavRouteRenderOwnerDiag(
        event: previous == null
            ? NavRouteRenderOwnerEvent.activated
            : NavRouteRenderOwnerEvent.replaced,
        sessionGeneration: next.sessionGeneration,
        styleGeneration: next.styleGeneration,
        routeVersion: next.routeVersion,
        renderEpoch: next.renderEpoch,
      ),
    );
    events.add(
      formatNavRideBoundaryDiag(
        event: NavRideBoundaryEvent.newRouteActivated,
        sessionGeneration: next.sessionGeneration,
        styleGeneration: next.styleGeneration,
        routeVersion: next.routeVersion,
        renderEpoch: next.renderEpoch,
      ),
    );
    return next;
  }

  NavRouteOwnershipCapture captureForStyleRestore({
    required int styleGeneration,
    List<String>? frozenRouteGeometry,
  }) {
    final geometry = frozenRouteGeometry ?? fullRouteGeometry;
    return NavRouteOwnershipCapture(
      sessionGeneration: sessionClock.current,
      styleGeneration: styleGeneration,
      routeVersion: routeVersion,
      renderEpoch: renderEpoch,
      navigationLive: navigationLive,
      routeCoordCount: geometry.length >= 2
          ? geometry.length
          : (geometry.isEmpty ? 0 : 2),
    );
  }

  NavRouteOwnershipSnapshot snapshot() {
    return NavRouteOwnershipSnapshot(
      sessionGeneration: sessionClock.current,
      styleGeneration: styleClock.current,
      routeVersion: routeVersion,
      renderEpoch: renderEpoch,
      navigationLive: navigationLive,
      activePackageSessionGeneration: activePackage?.sessionGeneration,
      activePackageRenderEpoch: activePackage?.renderEpoch,
    );
  }

  /// Attempt style restore using a frozen capture. On reject, geometry is
  /// unchanged. On allow, restores only the active package's route id.
  bool tryStyleRestore(NavRouteOwnershipCapture capture) {
    final decision = evaluateStyleRouteRestore(
      capture: capture,
      current: snapshot(),
    );
    if (!decision.allowed) {
      events.add(
        formatNavRouteRenderOwnerDiag(
          event: NavRouteRenderOwnerEvent.styleRestoreRejected,
          sessionGeneration: sessionClock.current,
          styleGeneration: styleClock.current,
          routeVersion: routeVersion,
          renderEpoch: renderEpoch,
          rejectionReason: styleRestoreRejectReasonToken(decision.reason!),
        ),
      );
      return false;
    }
    // Restore from capture ownership only — never from a foreign package.
    if (activePackage == null || activePackage!.isEmpty) {
      // Capture was for a live package; reinstate owned slots.
      fullRouteGeometry = <String>['restored'];
      remainingRouteGeometry = <String>['restored_remaining'];
      hasDestinationMarker = true;
    }
    events.add(
      formatNavRouteRenderOwnerDiag(
        event: NavRouteRenderOwnerEvent.styleRestoreAllowed,
        sessionGeneration: capture.sessionGeneration,
        styleGeneration: capture.styleGeneration,
        routeVersion: capture.routeVersion,
        renderEpoch: capture.renderEpoch,
      ),
    );
    return true;
  }

  /// Late reroute draw completion — must not add a second line when stale.
  bool tryCommitRerouteDraw({
    required int capturedSessionGeneration,
    required int capturedRenderEpoch,
    required String routeId,
  }) {
    final decision = evaluateOwnedRouteAnnotationCommit(
      capturedSessionGeneration: capturedSessionGeneration,
      currentSessionGeneration: sessionClock.current,
      capturedRenderEpoch: capturedRenderEpoch,
      currentRenderEpoch: renderEpoch,
    );
    if (!decision.shouldCommitShared) {
      events.add(
        formatNavRouteRenderOwnerDiag(
          event: NavRouteRenderOwnerEvent.staleCallbackIgnored,
          sessionGeneration: sessionClock.current,
          styleGeneration: styleClock.current,
          routeVersion: routeVersion,
          renderEpoch: renderEpoch,
          rejectionReason: styleRestoreRejectReasonToken(
            decision.rejectReason ??
                StyleRestoreRejectReason.renderEpochMismatch,
          ),
        ),
      );
      return false;
    }
    activateRoute(routeId: routeId);
    return true;
  }

  int visibleRouteCount() => fullRouteGeometry.length;

  bool get hasAnyPriorRouteResidue =>
      fullRouteGeometry.isNotEmpty ||
      completedRouteGeometry.isNotEmpty ||
      remainingRouteGeometry.isNotEmpty ||
      alternativeRouteGeometry.isNotEmpty ||
      hasDestinationMarker ||
      hasManeuverBanner ||
      hasLaneState;
}

String styleRestoreRejectReasonToken(StyleRestoreRejectReason reason) {
  switch (reason) {
    case StyleRestoreRejectReason.navigationNotLive:
      return 'navigation_not_live';
    case StyleRestoreRejectReason.sessionMismatch:
      return 'session_mismatch';
    case StyleRestoreRejectReason.styleMismatch:
      return 'style_mismatch';
    case StyleRestoreRejectReason.renderEpochMismatch:
      return 'render_epoch_mismatch';
    case StyleRestoreRejectReason.routeVersionMismatch:
      return 'route_version_mismatch';
    case StyleRestoreRejectReason.emptyGeometry:
      return 'empty_geometry';
    case StyleRestoreRejectReason.packageOwnerMismatch:
      return 'package_owner_mismatch';
  }
}

String navRideBoundaryEventToken(NavRideBoundaryEvent event) {
  switch (event) {
    case NavRideBoundaryEvent.sessionStarted:
      return 'session_started';
    case NavRideBoundaryEvent.priorSessionInvalidated:
      return 'prior_session_invalidated';
    case NavRideBoundaryEvent.routeStateCleared:
      return 'route_state_cleared';
    case NavRideBoundaryEvent.newRouteActivated:
      return 'new_route_activated';
  }
}

String navRouteRenderOwnerEventToken(NavRouteRenderOwnerEvent event) {
  switch (event) {
    case NavRouteRenderOwnerEvent.activated:
      return 'activated';
    case NavRouteRenderOwnerEvent.replaced:
      return 'replaced';
    case NavRouteRenderOwnerEvent.staleCallbackIgnored:
      return 'stale_callback_ignored';
    case NavRouteRenderOwnerEvent.styleRestoreAllowed:
      return 'style_restore_allowed';
    case NavRouteRenderOwnerEvent.styleRestoreRejected:
      return 'style_restore_rejected';
    case NavRouteRenderOwnerEvent.cleared:
      return 'cleared';
  }
}

String formatNavRideBoundaryDiag({
  required NavRideBoundaryEvent event,
  required int sessionGeneration,
  required int styleGeneration,
  required int routeVersion,
  required int renderEpoch,
  String? extra,
}) {
  final extraPart = (extra == null || extra.isEmpty) ? '' : ' $extra';
  return '[NAV_RIDE_BOUNDARY] '
      'event=${navRideBoundaryEventToken(event)} '
      'sessionGeneration=$sessionGeneration '
      'styleGeneration=$styleGeneration '
      'routeVersion=$routeVersion '
      'renderEpoch=$renderEpoch'
      '$extraPart';
}

String formatNavRouteRenderOwnerDiag({
  required NavRouteRenderOwnerEvent event,
  required int sessionGeneration,
  required int styleGeneration,
  required int routeVersion,
  required int renderEpoch,
  String? rejectionReason,
}) {
  final rejectPart = rejectionReason == null
      ? ''
      : ' rejectionReason=$rejectionReason';
  return '[NAV_ROUTE_RENDER_OWNER] '
      'event=${navRouteRenderOwnerEventToken(event)} '
      'sessionGeneration=$sessionGeneration '
      'styleGeneration=$styleGeneration '
      'routeVersion=$routeVersion '
      'renderEpoch=$renderEpoch'
      '$rejectPart';
}
