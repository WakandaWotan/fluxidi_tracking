/// NAV-REROUTE-CURRENT-POSITION-HEADING-P0
///
/// Central reroute lifecycle owner (pure Dart). Driver UI wires GPS/decision
/// into this coordinator; network I/O stays outside. Generations ensure latest
/// wins and stale responses never overwrite a newer route.
library;

/// Lifecycle phase for one confirmed off-route → new route cycle.
enum NavReroutePhase {
  idle,
  suspected,
  confirmed,
  invalidated,
  requesting,
  responseReceived,
  activating,
  active,
  failed,
  timedOut,
}

/// Origin for a reroute Directions request (live vehicle pose).
class NavRerouteRequestOrigin {
  const NavRerouteRequestOrigin({
    required this.latitude,
    required this.longitude,
    required this.headingDeg,
    this.mapMatchedLatitude,
    this.mapMatchedLongitude,
    this.accuracyM,
    this.speedKmh,
  });

  final double latitude;
  final double longitude;
  final double headingDeg;
  final double? mapMatchedLatitude;
  final double? mapMatchedLongitude;
  final double? accuracyM;
  final double? speedKmh;

  /// Prefer road-matched coordinates when available; else raw GPS.
  double get requestLatitude => mapMatchedLatitude ?? latitude;
  double get requestLongitude => mapMatchedLongitude ?? longitude;
}

/// Destination preserved across reroute (same final destination).
class NavRerouteDestination {
  const NavRerouteDestination({
    required this.latitude,
    required this.longitude,
  });

  final double latitude;
  final double longitude;
}

/// Bounded PII-free latency anchors for one reroute generation.
class NavRerouteLatencyMarks {
  DateTime? reliableFixReceivedAt;
  DateTime? offRouteSuspectedAt;
  DateTime? offRouteConfirmedAt;
  DateTime? oldRouteInvalidatedAt;
  DateTime? rerouteRequestStartedAt;
  DateTime? responseReceivedAt;
  DateTime? routeParsedAt;
  DateTime? geometryRenderedAt;
  DateTime? maneuversActivatedAt;
  DateTime? progressActivatedAt;
  DateTime? cameraFollowAttachedAt;

  void clear() {
    reliableFixReceivedAt = null;
    offRouteSuspectedAt = null;
    offRouteConfirmedAt = null;
    oldRouteInvalidatedAt = null;
    rerouteRequestStartedAt = null;
    responseReceivedAt = null;
    routeParsedAt = null;
    geometryRenderedAt = null;
    maneuversActivatedAt = null;
    progressActivatedAt = null;
    cameraFollowAttachedAt = null;
  }

  /// Compact diagnostic line — no coordinates / PII.
  String toDiagLine({
    required int navigationSessionGeneration,
    required int rerouteGeneration,
    required int routeVersion,
  }) {
    int? ms(DateTime? a, DateTime? b) {
      if (a == null || b == null) return null;
      return b.difference(a).inMilliseconds;
    }

    final confirmMs = ms(offRouteSuspectedAt, offRouteConfirmedAt);
    final invalidateMs = ms(offRouteConfirmedAt, oldRouteInvalidatedAt);
    final requestMs = ms(oldRouteInvalidatedAt, rerouteRequestStartedAt);
    final responseMs = ms(rerouteRequestStartedAt, responseReceivedAt);
    final activateMs = ms(responseReceivedAt, maneuversActivatedAt);
    return 'navSession=$navigationSessionGeneration '
        'rerouteGen=$rerouteGeneration routeVersion=$routeVersion '
        'suspectToConfirmMs=${confirmMs ?? '-'} '
        'confirmToInvalidateMs=${invalidateMs ?? '-'} '
        'invalidateToRequestMs=${requestMs ?? '-'} '
        'requestToResponseMs=${responseMs ?? '-'} '
        'responseToManeuverMs=${activateMs ?? '-'}';
  }
}

/// Snapshot of coordinator state for UI / tests.
class NavRerouteCoordinatorSnapshot {
  const NavRerouteCoordinatorSnapshot({
    required this.phase,
    required this.navigationSessionGeneration,
    required this.rerouteGeneration,
    required this.routeVersion,
    required this.oldGuidanceInvalidated,
    required this.showRecalculatingBanner,
    required this.suppressComplexityCaution,
    required this.suppressOldManeuvers,
    required this.freezeOldRouteProgress,
    required this.inFlight,
    required this.pendingFollowUp,
    required this.deadEndUturnActive,
    required this.timeoutLocked,
    required this.lastReason,
    required this.requestOrigin,
    required this.destination,
    required this.latency,
  });

  final NavReroutePhase phase;
  final int navigationSessionGeneration;
  final int rerouteGeneration;
  final int routeVersion;
  final bool oldGuidanceInvalidated;
  final bool showRecalculatingBanner;
  final bool suppressComplexityCaution;
  final bool suppressOldManeuvers;
  final bool freezeOldRouteProgress;
  final bool inFlight;
  final bool pendingFollowUp;
  final bool deadEndUturnActive;
  final bool timeoutLocked;
  final String lastReason;
  final NavRerouteRequestOrigin? requestOrigin;
  final NavRerouteDestination? destination;
  final NavRerouteLatencyMarks latency;
}

/// Central reroute coordinator — one owner for confirm → invalidate → request
/// → stale reject → atomic activate.
class NavRerouteCoordinator {
  NavRerouteCoordinator({
    this.requestTimeout = const Duration(seconds: 12),
    this.maxRetries = 2,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final Duration requestTimeout;
  final int maxRetries;
  final DateTime Function() _clock;

  int navigationSessionGeneration = 0;
  int rerouteGeneration = 0;
  int routeVersion = 0;

  NavReroutePhase phase = NavReroutePhase.idle;
  String lastReason = 'none';
  bool oldGuidanceInvalidated = false;
  bool pendingFollowUp = false;
  String? pendingFollowUpReason;
  bool deadEndUturnActive = false;
  double? _deadEndEntryHeadingDeg;
  int _retryCount = 0;
  DateTime? _requestDeadline;
  NavRerouteRequestOrigin? requestOrigin;
  NavRerouteDestination? destination;
  final NavRerouteLatencyMarks latency = NavRerouteLatencyMarks();

  bool get inFlight =>
      phase == NavReroutePhase.requesting ||
      phase == NavReroutePhase.responseReceived ||
      phase == NavReroutePhase.activating;

  bool get showRecalculatingBanner =>
      oldGuidanceInvalidated &&
      (phase == NavReroutePhase.invalidated ||
          phase == NavReroutePhase.requesting ||
          phase == NavReroutePhase.responseReceived ||
          phase == NavReroutePhase.activating);

  /// Stable single loading state — not re-flashed per GPS tick.
  bool get suppressComplexityCaution =>
      oldGuidanceInvalidated ||
      phase == NavReroutePhase.requesting ||
      phase == NavReroutePhase.confirmed ||
      phase == NavReroutePhase.invalidated;

  bool get suppressOldManeuvers => oldGuidanceInvalidated || inFlight;

  bool get freezeOldRouteProgress => oldGuidanceInvalidated && !isActive;

  bool get isActive => phase == NavReroutePhase.active;

  bool get timeoutLocked => false; // timeouts never permanently lock

  NavRerouteCoordinatorSnapshot snapshot() {
    return NavRerouteCoordinatorSnapshot(
      phase: phase,
      navigationSessionGeneration: navigationSessionGeneration,
      rerouteGeneration: rerouteGeneration,
      routeVersion: routeVersion,
      oldGuidanceInvalidated: oldGuidanceInvalidated,
      showRecalculatingBanner: showRecalculatingBanner,
      suppressComplexityCaution: suppressComplexityCaution,
      suppressOldManeuvers: suppressOldManeuvers,
      freezeOldRouteProgress: freezeOldRouteProgress,
      inFlight: inFlight,
      pendingFollowUp: pendingFollowUp,
      deadEndUturnActive: deadEndUturnActive,
      timeoutLocked: timeoutLocked,
      lastReason: lastReason,
      requestOrigin: requestOrigin,
      destination: destination,
      latency: latency,
    );
  }

  void beginNavigationSession({int? sessionGeneration}) {
    navigationSessionGeneration =
        sessionGeneration ?? (navigationSessionGeneration + 1);
    resetCycle(clearSession: false);
  }

  void resetCycle({bool clearSession = true}) {
    phase = NavReroutePhase.idle;
    lastReason = 'none';
    oldGuidanceInvalidated = false;
    pendingFollowUp = false;
    pendingFollowUpReason = null;
    deadEndUturnActive = false;
    _deadEndEntryHeadingDeg = null;
    _retryCount = 0;
    _requestDeadline = null;
    requestOrigin = null;
    if (clearSession) {
      destination = null;
      latency.clear();
    } else {
      latency.clear();
    }
  }

  void noteReliableFix(DateTime? at) {
    latency.reliableFixReceivedAt = at ?? _clock();
  }

  void noteSuspected({required String reason, DateTime? at}) {
    if (phase == NavReroutePhase.idle || phase == NavReroutePhase.active) {
      phase = NavReroutePhase.suspected;
    }
    lastReason = reason;
    latency.offRouteSuspectedAt ??= at ?? _clock();
  }

  /// Confirmed deviation: bump generation, invalidate old guidance immediately.
  int confirmOffRoute({
    required String reason,
    required NavRerouteRequestOrigin origin,
    required NavRerouteDestination dest,
    DateTime? at,
  }) {
    final now = at ?? _clock();
    if (inFlight) {
      // Latest-wins: bump generation and queue one follow-up.
      rerouteGeneration += 1;
      pendingFollowUp = true;
      pendingFollowUpReason = reason;
      requestOrigin = origin;
      destination = dest;
      lastReason = reason;
      oldGuidanceInvalidated = true;
      phase = NavReroutePhase.invalidated;
      latency.offRouteConfirmedAt = now;
      latency.oldRouteInvalidatedAt = now;
      return rerouteGeneration;
    }

    rerouteGeneration += 1;
    phase = NavReroutePhase.confirmed;
    lastReason = reason;
    requestOrigin = origin;
    destination = dest;
    latency.offRouteConfirmedAt = now;
    invalidateOldGuidance(at: now);
    return rerouteGeneration;
  }

  void invalidateOldGuidance({DateTime? at}) {
    oldGuidanceInvalidated = true;
    phase = NavReroutePhase.invalidated;
    latency.oldRouteInvalidatedAt = at ?? _clock();
  }

  /// Start network request for [expectedGeneration]. Returns false if stale.
  bool beginRequest({
    required int expectedGeneration,
    NavRerouteRequestOrigin? origin,
    DateTime? at,
  }) {
    if (expectedGeneration != rerouteGeneration) return false;
    if (origin != null) requestOrigin = origin;
    phase = NavReroutePhase.requesting;
    final now = at ?? _clock();
    latency.rerouteRequestStartedAt = now;
    _requestDeadline = now.add(requestTimeout);
    return true;
  }

  /// Whether a response for [responseGeneration] may be applied.
  bool acceptResponseGeneration(int responseGeneration) {
    return responseGeneration == rerouteGeneration;
  }

  void noteResponseReceived({
    required int responseGeneration,
    DateTime? at,
  }) {
    if (!acceptResponseGeneration(responseGeneration)) return;
    phase = NavReroutePhase.responseReceived;
    latency.responseReceivedAt = at ?? _clock();
  }

  void noteRouteParsed({required int responseGeneration, DateTime? at}) {
    if (!acceptResponseGeneration(responseGeneration)) return;
    latency.routeParsedAt = at ?? _clock();
  }

  /// Atomic activation: advances [routeVersion] only when generation matches.
  /// Returns new routeVersion or null if rejected.
  int? activateAtomic({
    required int responseGeneration,
    DateTime? at,
    bool deadEndUturn = false,
  }) {
    if (!acceptResponseGeneration(responseGeneration)) return null;
    final now = at ?? _clock();
    phase = NavReroutePhase.activating;
    routeVersion += 1;
    latency.geometryRenderedAt = now;
    latency.maneuversActivatedAt = now;
    latency.progressActivatedAt = now;
    latency.cameraFollowAttachedAt = now;
    oldGuidanceInvalidated = false;
    pendingFollowUp = false;
    pendingFollowUpReason = null;
    _retryCount = 0;
    _requestDeadline = null;
    deadEndUturnActive = deadEndUturn;
    if (deadEndUturn && requestOrigin != null) {
      _deadEndEntryHeadingDeg = requestOrigin!.headingDeg;
    } else {
      _deadEndEntryHeadingDeg = null;
    }
    phase = NavReroutePhase.active;
    return routeVersion;
  }

  /// Mark failure; never permanently locks. Returns whether a retry is allowed.
  bool noteFailure({
    required int responseGeneration,
    required String reason,
    DateTime? at,
  }) {
    if (responseGeneration != rerouteGeneration) return false;
    lastReason = reason;
    phase = NavReroutePhase.failed;
    oldGuidanceInvalidated = true;
    _requestDeadline = null;
    if (_retryCount < maxRetries) {
      _retryCount += 1;
      pendingFollowUp = true;
      pendingFollowUpReason = reason;
      return true;
    }
    return false;
  }

  /// Timed-out in-flight request: unlock and allow a fresh generation.
  bool noteTimeout({required int responseGeneration, DateTime? at}) {
    if (responseGeneration != rerouteGeneration) return false;
    phase = NavReroutePhase.timedOut;
    lastReason = 'timeout';
    oldGuidanceInvalidated = true;
    _requestDeadline = null;
    pendingFollowUp = true;
    pendingFollowUpReason = 'timeout_retry';
    // Bump generation so a stuck Future cannot block later confirms.
    rerouteGeneration += 1;
    return true;
  }

  bool isRequestTimedOut({DateTime? at}) {
    final deadline = _requestDeadline;
    if (deadline == null) return false;
    return (at ?? _clock()).isAfter(deadline);
  }

  /// Consume pending follow-up after in-flight clear. Returns reason or null.
  String? takePendingFollowUp() {
    if (!pendingFollowUp) return null;
    final reason = (pendingFollowUpReason ?? lastReason).trim();
    pendingFollowUp = false;
    pendingFollowUpReason = null;
    return reason.isEmpty ? 'follow_up' : reason;
  }

  /// Stable dead-end U-turn copy while still heading into the dead end.
  /// When heading reverses enough, clears dead-end lock so routing continues.
  String? deadEndUturnInstruction({
    required double currentHeadingDeg,
    required String Function({
      required String nl,
      required String en,
      required String fr,
      required String es,
    })
    tr,
  }) {
    if (!deadEndUturnActive) return null;
    final entry = _deadEndEntryHeadingDeg;
    if (entry != null) {
      final delta = _headingDeltaDeg(entry, currentHeadingDeg);
      if (delta >= 120) {
        // Vehicle turned around — allow normal progress again.
        deadEndUturnActive = false;
        _deadEndEntryHeadingDeg = null;
        return null;
      }
    }
    return tr(
      nl: 'Keer om zodra dit veilig mogelijk is',
      en: 'Turn around when it is safe',
      fr: 'Faites demi-tour dès que c’est possible en sécurité',
      es: 'Dé la vuelta cuando sea seguro',
    );
  }

  /// Mapbox / worker bearings token: heading + 45° influence at origin.
  static String bearingsQueryValue(double headingDeg) {
    var h = headingDeg;
    if (!h.isFinite || h < 0) h = 0;
    h = h % 360.0;
    if (h < 0) h += 360.0;
    // Origin constrained; destination unconstrained (`;`).
    return '${h.toStringAsFixed(1)},45;';
  }

  static bool looksLikeDeadEndUturn({
    required String? maneuverType,
    required String? maneuverModifier,
    required String? instructionText,
  }) {
    final t = (maneuverType ?? '').toLowerCase();
    final m = (maneuverModifier ?? '').toLowerCase();
    final text = (instructionText ?? '').toLowerCase();
    if (m.contains('uturn') || m.contains('u-turn')) return true;
    if (t.contains('uturn') || t.contains('u-turn')) return true;
    if (text.contains('keer om') ||
        text.contains('turn around') ||
        text.contains('u-turn') ||
        text.contains('demi-tour')) {
      return true;
    }
    return false;
  }

  static double _headingDeltaDeg(double a, double b) {
    var d = (b - a) % 360.0;
    if (d < 0) d += 360.0;
    if (d > 180.0) d = 360.0 - d;
    return d;
  }
}
