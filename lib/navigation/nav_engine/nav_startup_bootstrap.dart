// NAV-PARKING-ARRIVAL-DEPARTURE-ROUTE-CLARITY-BANNER-TELLERS-2 / Commit 1
//
// Pure, unit-testable startup/readiness state machine for a navigation session
// that begins from a parking lot, private access road, driveway or large
// commercial site — positions that do not immediately match the first
// public-road route segment.
//
// During bootstrap the app must NOT treat expected startup uncertainty as a
// "complex road situation", nor storm opposite-direction/wrong-street reroutes
// on the first unmatched parking samples. Bootstrap ends as soon as reliable
// movement/matching exists, subject to a safe upper bound (no long blind delay).

/// Diagnostic phases for [NAV_STARTUP_BOOTSTRAP]. PII-free.
enum NavStartupBootstrapPhase {
  started,
  waitingForFreshLocation,
  waitingForCourse,
  waitingForRouteMatch,
  readinessConfirmed,
  timeoutFallback,
}

extension NavStartupBootstrapPhaseLabel on NavStartupBootstrapPhase {
  String get label {
    switch (this) {
      case NavStartupBootstrapPhase.started:
        return 'started';
      case NavStartupBootstrapPhase.waitingForFreshLocation:
        return 'waiting_for_fresh_location';
      case NavStartupBootstrapPhase.waitingForCourse:
        return 'waiting_for_course';
      case NavStartupBootstrapPhase.waitingForRouteMatch:
        return 'waiting_for_route_match';
      case NavStartupBootstrapPhase.readinessConfirmed:
        return 'readiness_confirmed';
      case NavStartupBootstrapPhase.timeoutFallback:
        return 'timeout_fallback';
    }
  }
}

/// One evidence sample fed to the bootstrap gate on each GPS/route tick.
class NavStartupBootstrapSample {
  const NavStartupBootstrapSample({
    required this.elapsedSinceStartMs,
    required this.hasActiveSessionRoute,
    required this.gpsFixAgeMs,
    required this.gpsAccuracyM,
    required this.speedKmh,
    required this.hasUsableCourse,
    required this.mapMatched,
    required this.routeEntryProgressing,
    required this.coherentWithPreviousSample,
  });

  /// Milliseconds since the navigation session started.
  final int elapsedSinceStartMs;

  /// True once the current-session route is active (accepted geometry present).
  final bool hasActiveSessionRoute;

  /// Age of the most recent GPS fix (ms). Large = stale.
  final int gpsFixAgeMs;

  /// Horizontal accuracy in metres (negative/NaN = unknown).
  final double gpsAccuracyM;

  /// Current speed in km/h.
  final double speedKmh;

  /// True when a reliable course-over-ground exists (moving with valid heading).
  final bool hasUsableCourse;

  /// True when the position map-matches to the route.
  final bool mapMatched;

  /// True when the driver is clearly progressing onto the first route segment.
  final bool routeEntryProgressing;

  /// True when this sample is spatially coherent with the previous one
  /// (used to require multiple coherent samples, not a single lucky fix).
  final bool coherentWithPreviousSample;
}

/// Tunables for the bootstrap gate. Bounded — never a long blind delay.
class NavStartupBootstrapConfig {
  const NavStartupBootstrapConfig({
    this.maxFreshFixAgeMs = 4000,
    this.acceptableAccuracyM = 40.0,
    this.movingSpeedKmh = 6.0,
    this.requiredCoherentSamples = 2,
    this.safeUpperBoundMs = 12000,
  });

  final int maxFreshFixAgeMs;
  final double acceptableAccuracyM;
  final double movingSpeedKmh;
  final int requiredCoherentSamples;

  /// Hard cap: bootstrap always resolves (readiness or timeout fallback) by
  /// this time so a stubborn parking start never blocks navigation forever.
  final int safeUpperBoundMs;
}

/// Result of a single bootstrap evaluation.
class NavStartupBootstrapResult {
  const NavStartupBootstrapResult({
    required this.phase,
    required this.ready,
    required this.changed,
  });

  final NavStartupBootstrapPhase phase;

  /// True once the session is ready for strong heading/route/complexity
  /// conclusions (readiness confirmed OR timed-out fallback).
  final bool ready;

  /// True when [phase] changed since the previous evaluation (for bounded
  /// diagnostics — only log on change).
  final bool changed;
}

/// Bounded startup readiness gate. Not thread-safe by design (single isolate).
class NavStartupBootstrapGate {
  NavStartupBootstrapPhase _phase = NavStartupBootstrapPhase.started;
  bool _ready = false;
  int _coherentSamples = 0;
  bool _started = false;

  final NavStartupBootstrapConfig config;

  NavStartupBootstrapGate({
    this.config = const NavStartupBootstrapConfig(),
  });

  NavStartupBootstrapPhase get phase => _phase;
  bool get ready => _ready;

  /// Begin a fresh bootstrap for a new session. Idempotent per session.
  void start() {
    _phase = NavStartupBootstrapPhase.started;
    _ready = false;
    _coherentSamples = 0;
    _started = true;
  }

  void reset() {
    _phase = NavStartupBootstrapPhase.started;
    _ready = false;
    _coherentSamples = 0;
    _started = false;
  }

  bool _accuracyAcceptable(double m) =>
      m.isFinite && m >= 0 && m <= config.acceptableAccuracyM;

  NavStartupBootstrapResult evaluate(NavStartupBootstrapSample s) {
    if (!_started) start();

    // Once ready (or timed-out), stay ready for the session. Genuine severe
    // deviations after readiness are handled by the normal engines.
    if (_ready) {
      return NavStartupBootstrapResult(
        phase: _phase,
        ready: true,
        changed: false,
      );
    }

    final prevPhase = _phase;

    // Safe upper bound: never block navigation forever on a stubborn start.
    if (s.elapsedSinceStartMs >= config.safeUpperBoundMs) {
      _phase = NavStartupBootstrapPhase.timeoutFallback;
      _ready = true;
      return NavStartupBootstrapResult(
        phase: _phase,
        ready: true,
        changed: prevPhase != _phase,
      );
    }

    final freshLocation =
        s.gpsFixAgeMs <= config.maxFreshFixAgeMs && _accuracyAcceptable(s.gpsAccuracyM);

    if (!freshLocation) {
      _coherentSamples = 0;
      _phase = NavStartupBootstrapPhase.waitingForFreshLocation;
      return NavStartupBootstrapResult(
        phase: _phase,
        ready: false,
        changed: prevPhase != _phase,
      );
    }

    // Count coherent fresh samples so a single lucky fix cannot confirm.
    if (s.coherentWithPreviousSample) {
      _coherentSamples += 1;
    } else {
      _coherentSamples = 1;
    }
    final haveEnoughSamples = _coherentSamples >= config.requiredCoherentSamples;

    // Route match OR clear route-entry progression ends bootstrap.
    final matched = s.mapMatched || s.routeEntryProgressing;

    // When the vehicle is moving, a usable course-over-ground is enough
    // evidence together with fresh, accurate, coherent samples.
    final moving = s.speedKmh >= config.movingSpeedKmh;

    if (!haveEnoughSamples) {
      _phase = NavStartupBootstrapPhase.waitingForFreshLocation;
      return NavStartupBootstrapResult(
        phase: _phase,
        ready: false,
        changed: prevPhase != _phase,
      );
    }

    if (matched && s.hasActiveSessionRoute) {
      _phase = NavStartupBootstrapPhase.readinessConfirmed;
      _ready = true;
      return NavStartupBootstrapResult(
        phase: _phase,
        ready: true,
        changed: prevPhase != _phase,
      );
    }

    if (moving && s.hasUsableCourse) {
      _phase = NavStartupBootstrapPhase.readinessConfirmed;
      _ready = true;
      return NavStartupBootstrapResult(
        phase: _phase,
        ready: true,
        changed: prevPhase != _phase,
      );
    }

    // Fresh + coherent, but not yet matched and not yet reliably moving.
    _phase = moving
        ? NavStartupBootstrapPhase.waitingForRouteMatch
        : NavStartupBootstrapPhase.waitingForCourse;
    return NavStartupBootstrapResult(
      phase: _phase,
      ready: false,
      changed: prevPhase != _phase,
    );
  }
}

/// PII-free bounded diagnostic line for `[NAV_STARTUP_BOOTSTRAP]`.
String formatNavStartupBootstrapDiagnostic({
  required NavStartupBootstrapPhase phase,
  required bool ready,
  int? elapsedMs,
}) {
  return '[NAV_STARTUP_BOOTSTRAP] phase=${phase.label} ready=$ready '
      'elapsedMs=${elapsedMs ?? -1}';
}
