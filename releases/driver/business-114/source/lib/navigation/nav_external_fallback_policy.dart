// FLUXIDI-EXTERNAL-NAV-FALLBACK-POPUP-LOOP-P0-1
//
// Automatic Waze / Google Maps recommendations must never interrupt a
// functioning Fluxidi navigation session. External apps remain a deliberate
// manual action only.

/// Inputs for deciding whether an *automatic* external-navigation prompt may
/// be shown. Pure — no Flutter / Mapbox dependencies.
class NavExternalFallbackPromptInput {
  /// True once Fluxidi has successfully applied a navigable route / entered
  /// guidance for this attempt.
  final bool navigationSuccessfullyStarted;

  /// True when a usable route geometry or steps are still available.
  final bool hasUsableRoute;

  /// True only for terminal (non-retryable) failures. Retryable network /
  /// Directions failures must never auto-prompt.
  final bool failureIsTerminal;

  /// True when Fluxidi can still safely provide in-app navigation (existing
  /// route, follow mode, active ride, etc.).
  final bool fluxidiCanProvideNavigation;

  /// True while the driver is in NAV-to-pickup / active customer navigation /
  /// Street Level follow guidance.
  final bool driverInActiveNavigation;

  /// True after this navigation attempt already showed or dismissed an
  /// automatic external prompt.
  final bool alreadyShownOrDismissedThisAttempt;

  /// True for off-route / strong-mismatch / reroute-request / adaptation /
  /// GPS / lifecycle / style / camera recovery signals that must never open
  /// an external-nav recommendation.
  final bool transientNavigationSignal;

  const NavExternalFallbackPromptInput({
    this.navigationSuccessfullyStarted = false,
    this.hasUsableRoute = false,
    this.failureIsTerminal = false,
    this.fluxidiCanProvideNavigation = false,
    this.driverInActiveNavigation = false,
    this.alreadyShownOrDismissedThisAttempt = false,
    this.transientNavigationSignal = false,
  });
}

/// Decision for an automatic external-navigation prompt.
class NavExternalFallbackPromptDecision {
  final bool shouldShow;
  final String reason;

  const NavExternalFallbackPromptDecision({
    required this.shouldShow,
    required this.reason,
  });
}

/// Release policy: automatic external-navigation recommendations are denied
/// unless every strict terminal pre-start gate passes. In practice Fluxidi
/// keeps recovery in-app and retains Waze/Google only behind a manual tap, so
/// most call sites will resolve to [shouldShow] == false.
NavExternalFallbackPromptDecision resolveExternalNavAutoPrompt(
  NavExternalFallbackPromptInput input,
) {
  if (input.driverInActiveNavigation) {
    return const NavExternalFallbackPromptDecision(
      shouldShow: false,
      reason: 'active_navigation',
    );
  }
  if (input.navigationSuccessfullyStarted) {
    return const NavExternalFallbackPromptDecision(
      shouldShow: false,
      reason: 'navigation_started',
    );
  }
  if (input.hasUsableRoute) {
    return const NavExternalFallbackPromptDecision(
      shouldShow: false,
      reason: 'usable_route_present',
    );
  }
  if (input.fluxidiCanProvideNavigation) {
    return const NavExternalFallbackPromptDecision(
      shouldShow: false,
      reason: 'fluxidi_can_navigate',
    );
  }
  if (input.transientNavigationSignal) {
    return const NavExternalFallbackPromptDecision(
      shouldShow: false,
      reason: 'transient_signal',
    );
  }
  if (!input.failureIsTerminal) {
    return const NavExternalFallbackPromptDecision(
      shouldShow: false,
      reason: 'failure_not_terminal',
    );
  }
  if (input.alreadyShownOrDismissedThisAttempt) {
    return const NavExternalFallbackPromptDecision(
      shouldShow: false,
      reason: 'attempt_latched',
    );
  }
  return const NavExternalFallbackPromptDecision(
    shouldShow: true,
    reason: 'terminal_prestart_once',
  );
}

/// Whether a reroute / route-update failure may surface any automatic driver
/// popup while Fluxidi still owns an active or usable navigation session.
///
/// Release policy: never. Recovery stays silent and in-app.
bool shouldSurfaceRerouteFailurePopup({
  required bool hasUsableRoute,
  required bool driverInActiveNavigation,
  required bool rerouteStillRetryable,
}) {
  if (driverInActiveNavigation) return false;
  if (hasUsableRoute) return false;
  if (rerouteStillRetryable) return false;
  return false;
}

/// Session latch for a single navigation attempt: show-or-dismiss is sticky
/// until an explicit new-attempt reset. Not timer-based.
class NavExternalFallbackLatch {
  bool _latched = false;
  bool _inFlight = false;
  int _attemptId = 0;

  bool get isLatched => _latched;
  bool get inFlight => _inFlight;
  int get attemptId => _attemptId;

  /// Begin a new navigation attempt (new ride / new planned route). Clears
  /// dismissal and in-flight state. App resume must NOT call this.
  void beginNewNavigationAttempt() {
    _attemptId += 1;
    _latched = false;
    _inFlight = false;
  }

  /// Returns true only for the first presentation claim in this attempt.
  bool tryBeginPresentation() {
    if (_latched || _inFlight) return false;
    _inFlight = true;
    return true;
  }

  void markShownOrDismissed() {
    _latched = true;
    _inFlight = false;
  }

  void cancelInFlight() {
    _inFlight = false;
  }

  /// Test / diagnostics helper.
  void debugReset() {
    _latched = false;
    _inFlight = false;
    _attemptId = 0;
  }
}
