import 'dart:math' as math;

/// NAV-STREETLEVEL-REALTIME-FOLLOW-PIPELINE-1
///
/// Pure, side-effect-free building blocks for the real-time streetlevel camera
/// follow pipeline. The widget layer owns all Mapbox calls and timers; this
/// module only provides:
///
///  * [NavStreetlevelPose] — the single authoritative live pose consumed by
///    both the vehicle visual and the camera (PART A / PART G).
///  * [NavStreetlevelBearingController] — the one authoritative heading
///    smoothing stage for streetlevel camera follow (PART B / PART E / PART F).
///  * [NavStreetlevelFollowPump] — a finite latest-state-wins consumer with a
///    single camera update in flight (PART C).
///  * [formatNavStreetlevelFollowDiag] / [logNavStreetlevelFollow] — bounded
///    diagnostics (PART H).
///
/// The R3 movement tick is the pose *producer*; the pump is the pose
/// *consumer*. There is no recursive scheduling, no microtask chain, and no
/// queue of stale camera targets in this module.

// ---------------------------------------------------------------------------
// PART C — pump cadence / animation bounds.
// ---------------------------------------------------------------------------

/// NAV-STREETLEVEL-FLUID-MOTION-1 (frame-driven pose): retained cadence
/// constant for the R3 visual-pose pump. This is the *internal* Dart-side
/// pose interpolator that runs at frame cadence to reconstruct smooth motion
/// between GPS fixes; it does NOT reach across the Mapbox platform channel.
/// Keeping the 16 ms tick here is safe because no camera / model / marker
/// writes happen on this timer.
const int kNavStreetlevelFrameTickMs = 16;

/// Legacy pump cadence constant retained for callers/tests that still reference
/// the 33 ms fallback. New code should use [kNavStreetlevelFrameTickMs] for
/// the pose interpolator and [kNavStreetlevelDefaultCameraTickMs] for the
/// camera-write pump.
const int kNavStreetlevelFollowPumpTickMs = 33;

/// FLUXIDI NAV-STREETLEVEL-FLUID-MOTION-2 (Phase 1 fallback, Part A): default
/// camera-write pump tick (10 Hz) when the native FollowPuck path is
/// disabled. The real cadence is chosen by
/// [NavAdaptiveCadenceController.currentTickMs] each tick; this constant is
/// only the initial value + a stable reference for the bearing controller's
/// `dtMs` when the widget has no measured interval yet.
const int kNavStreetlevelDefaultCameraTickMs = 100;

/// Bounded eased camera animation length. DEPRECATED for the streetlevel follow
/// path: the frame-driven pipeline uses an instant `setCamera` per frame rather
/// than restarting an eased animation on every pose. Retained only for any
/// non-follow caller that still needs a short ease.
const int kNavStreetlevelFollowCameraEaseMs = 80;

// ---------------------------------------------------------------------------
// PART B / E / F — single authoritative bearing smoothing constants.
// ---------------------------------------------------------------------------

/// Sub-deadband wobble is ignored so noisy heading does not spin the camera.
const double kNavStreetlevelBearingJitterDeadbandDeg = 1.5;

/// Below this speed the per-tick catch-up is capped to suppress GPS heading
/// noise while still allowing genuine route-tangent rotation into a turn.
const double kNavStreetlevelBearingLowSpeedKmh = 3.0;

/// Angular-delta bands driving adaptive catch-up (PART E).
const double kNavStreetlevelBearingSmallTurnDeg = 8.0;
const double kNavStreetlevelBearingMediumTurnDeg = 45.0;

/// Bounded per-tick maximum step by band. Larger deltas (sharp turns /
/// roundabouts) catch up faster than small jitter.
const double kNavStreetlevelBearingMaxStepSmallDeg = 6.0;
const double kNavStreetlevelBearingMaxStepMediumDeg = 16.0;
const double kNavStreetlevelBearingMaxStepLargeDeg = 34.0;

/// Per-tick cap while very slow / stopped.
const double kNavStreetlevelBearingLowSpeedMaxStepDeg = 10.0;

/// NAV-STREETLEVEL-FLUID-MOTION-1: reference tick the per-step caps above were
/// tuned against (33 ms ≈ 30 fps). [NavStreetlevelBearingController.follow]
/// scales the per-tick cap by `dtMs / this` so the *angular velocity* (deg/s)
/// is frame-rate independent — running the follow at 16 ms (~60 fps) does not
/// double the turn rate or introduce over-fast rotation.
const double kNavStreetlevelBearingReferenceTickMs = 33.0;

/// Bounded look-ahead distance (metres) into the route curve, so the camera
/// bearing begins entering a bend before the vehicle reaches its apex. Scales
/// with speed and is clamped so it never over-anticipates at low speed nor
/// under-anticipates on fast roads. Pure helper — the widget samples the route
/// geometry this far ahead to derive the tangent bearing target.
const double kNavStreetlevelLookAheadMinMeters = 8.0;
const double kNavStreetlevelLookAheadMaxMeters = 45.0;

/// Look-ahead seconds of travel at the current speed (bounded by the metre
/// clamps above). ~0.9 s of travel enters bends naturally without cutting.
const double kNavStreetlevelLookAheadSeconds = 0.9;

/// Bounded look-ahead distance into the route curve for [speedKmh]. Below the
/// low-speed threshold the look-ahead collapses to the minimum so a stopped /
/// crawling vehicle does not swing the camera toward a distant bend.
double navStreetlevelLookAheadMeters(double speedKmh) {
  if (!speedKmh.isFinite || speedKmh <= kNavStreetlevelBearingLowSpeedKmh) {
    return kNavStreetlevelLookAheadMinMeters;
  }
  final metersPerSecond = speedKmh / 3.6;
  final raw = metersPerSecond * kNavStreetlevelLookAheadSeconds;
  return raw.clamp(
    kNavStreetlevelLookAheadMinMeters,
    kNavStreetlevelLookAheadMaxMeters,
  );
}

double _normalizeBearing(double bearing) {
  var b = bearing % 360.0;
  if (b < 0) b += 360.0;
  return b;
}

/// Signed shortest angular delta from [from] to [to] in (-180, 180].
double navStreetlevelShortestBearingDelta(double from, double to) {
  var delta = (_normalizeBearing(to) - _normalizeBearing(from)) % 360.0;
  if (delta > 180.0) delta -= 360.0;
  if (delta < -180.0) delta += 360.0;
  return delta;
}

/// Bounded adaptive per-tick step for the streetlevel camera bearing (PART E).
double navStreetlevelBearingMaxStepDeg({
  required double deltaDeg,
  required double speedKmh,
}) {
  final ad = deltaDeg.abs();
  double base;
  if (ad < kNavStreetlevelBearingSmallTurnDeg) {
    base = kNavStreetlevelBearingMaxStepSmallDeg;
  } else if (ad < kNavStreetlevelBearingMediumTurnDeg) {
    base = kNavStreetlevelBearingMaxStepMediumDeg;
  } else {
    base = kNavStreetlevelBearingMaxStepLargeDeg;
  }
  if (speedKmh < kNavStreetlevelBearingLowSpeedKmh) {
    base = math.min(base, kNavStreetlevelBearingLowSpeedMaxStepDeg);
  }
  return base;
}

/// PART A / PART G — the single authoritative live pose. Both the vehicle
/// visual and the camera consume the same pose generation so they never drift
/// onto separate delayed streams.
class NavStreetlevelPose {
  const NavStreetlevelPose({
    required this.lat,
    required this.lon,
    required this.bearingDeg,
    required this.headingDeg,
    required this.timestampMs,
    required this.routeGeneration,
    required this.poseGeneration,
    this.renderEpoch = 0,
    this.ownerMode = 'reliable_route',
  });

  /// Snapped display coordinate (same point the vehicle marker/model uses).
  final double lat;
  final double lon;

  /// Trusted camera-driving bearing (route tangent / interpolated course).
  final double bearingDeg;

  /// Vehicle heading used for the 2D/3D visual (kept consistent with bearing).
  final double headingDeg;

  final int timestampMs;
  final int routeGeneration;
  final int poseGeneration;

  /// Route render epoch stamped at publish time for stale rejection.
  final int renderEpoch;

  /// Camera-bearing owner mode label at publish time (PII-free).
  final String ownerMode;
}

/// PART B / E / F — the ONE authoritative heading smoothing stage for
/// streetlevel camera follow. Replaces the stacked
/// resolveDriverRouteBearing + applyDriverCockpitStreetlevelBearingLock
/// smoothing for the live follow path. Handles wraparound, jitter suppression,
/// low-speed stability and bounded adaptive catch-up.
class NavStreetlevelBearingController {
  double? _appliedBearing;
  double _lastTargetDeg = 0.0;
  double _lastAppliedDeltaDeg = 0.0;

  double? get appliedBearing => _appliedBearing;
  double get lastTargetDeg => _lastTargetDeg;
  double get lastAppliedDeltaDeg => _lastAppliedDeltaDeg;

  /// Advance the applied bearing one frame toward [targetBearingDeg].
  ///
  /// [dtMs] is the wall-clock interval since the previous follow tick. The
  /// per-tick catch-up cap is scaled by `dtMs / reference` so the angular
  /// velocity is frame-rate independent (NAV-STREETLEVEL-FLUID-MOTION-1): the
  /// same physical turn resolves over the same wall-time at 16 ms or 33 ms.
  double follow({
    required double targetBearingDeg,
    required double speedKmh,
    double dtMs = kNavStreetlevelBearingReferenceTickMs,
    bool travelAuthority = false,
  }) {
    final target = _normalizeBearing(targetBearingDeg);
    // Latest-wins retarget: every call replaces the pending target; there is
    // no animation queue and no delayed completion from an older target.
    _lastTargetDeg = target;
    final prev = _appliedBearing;
    if (prev == null || !prev.isFinite) {
      _appliedBearing = target;
      _lastAppliedDeltaDeg = 0.0;
      return target;
    }
    final delta = navStreetlevelShortestBearingDelta(prev, target);
    final ad = delta.abs();
    // PART F: ignore sub-deadband wobble so noisy heading does not spin.
    // Under travel authority keep a slightly tighter noise floor so sustained
    // real changes are not over-smoothed while GPS jitter stays filtered.
    final deadband = travelAuthority
        ? math.min(kNavStreetlevelBearingJitterDeadbandDeg, 2.0)
        : kNavStreetlevelBearingJitterDeadbandDeg;
    if (ad < deadband) {
      _lastAppliedDeltaDeg = 0.0;
      return prev;
    }
    // Frame-rate-independent angular velocity: scale the per-tick cap by the
    // actual frame interval relative to the reference tick. Bounded to a sane
    // window so a long stall (e.g. dt=500 ms) cannot snap a full turn instantly.
    final dtScale = (dtMs / kNavStreetlevelBearingReferenceTickMs).clamp(
      0.25,
      4.0,
    );
    var maxStep =
        navStreetlevelBearingMaxStepDeg(deltaDeg: delta, speedKmh: speedKmh) *
        dtScale;
    // NAV-CAMERA-ZERO-OLD-ROUTE-HOLD-P0: travel authority must begin a
    // meaningful heading change within ~100 ms and start 180° reversals
    // immediately — raise the per-tick ceiling for medium/large deltas.
    if (travelAuthority) {
      final travelCap = ad >= 90.0
          ? 90.0
          : ad >= 45.0
          ? 55.0
          : ad >= 20.0
          ? 28.0
          : 14.0;
      maxStep = math.max(maxStep, travelCap * dtScale);
    }
    final double next;
    if (ad <= maxStep) {
      next = target;
    } else {
      next = _normalizeBearing(prev + maxStep * delta.sign);
    }
    _appliedBearing = next;
    _lastAppliedDeltaDeg = navStreetlevelShortestBearingDelta(prev, next);
    return next;
  }

  void reset() {
    _appliedBearing = null;
    _lastTargetDeg = 0.0;
    _lastAppliedDeltaDeg = 0.0;
  }
}

/// PART C — finite latest-state-wins camera follow pump.
///
/// The producer calls [submit] with each new pose. The consumer (a fixed
/// interval timer in the widget) calls [acquire] to obtain the newest
/// not-yet-applied pose, applies exactly one camera update, then calls
/// [complete]. Only one update is ever in flight; older intermediate poses are
/// discarded (counted in [droppedStaleTargets]). No recursion, no queue.
class NavStreetlevelFollowPump {
  NavStreetlevelPose? _latest;
  int _lastConsumedGeneration = -1;
  bool _inFlight = false;
  int _droppedStaleTargets = 0;
  int _coalescedCount = 0;
  int _expectedRouteGeneration = -1;
  int _expectedRenderEpoch = -1;
  int _staleCommandCancelled = 0;

  bool get inFlight => _inFlight;
  int get droppedStaleTargets => _droppedStaleTargets;

  /// Number of poses coalesced into the latest slot while a camera update was
  /// already in flight (PART C diagnostics).
  int get coalescedCount => _coalescedCount;
  NavStreetlevelPose? get latest => _latest;
  int get lastConsumedGeneration => _lastConsumedGeneration;
  int get expectedRouteGeneration => _expectedRouteGeneration;
  int get expectedRenderEpoch => _expectedRenderEpoch;
  int get staleCommandCancelled => _staleCommandCancelled;

  /// PART C / PART E — declare the current authoritative route generation.
  /// After a reroute handoff the widget bumps this; poses still tagged with an
  /// older route generation are then rejected so old-route camera writes can
  /// never compete with the newly applied route. Monotonic.
  void setExpectedRouteGeneration(int routeGeneration) {
    if (routeGeneration > _expectedRouteGeneration) {
      _expectedRouteGeneration = routeGeneration;
    }
  }

  /// NAV-CAMERA-ZERO-OLD-ROUTE-HOLD-P0: reject poses from a superseded render
  /// epoch so routeVersion N / epoch N cannot commit after N+1 is active.
  void setExpectedRenderEpoch(int renderEpoch) {
    if (renderEpoch > _expectedRenderEpoch) {
      _expectedRenderEpoch = renderEpoch;
    }
  }

  /// Producer entry point. Latest wins: if a not-yet-consumed pose is
  /// overwritten before it is applied, it is counted as a dropped stale target.
  void submit(NavStreetlevelPose pose) {
    final pending = _latest;
    if (pending != null &&
        pending.poseGeneration != _lastConsumedGeneration &&
        pending.poseGeneration != pose.poseGeneration) {
      _droppedStaleTargets += 1;
    }
    if (_inFlight) _coalescedCount += 1;
    _latest = pose;
  }

  /// Consumer entry point. Returns the newest unapplied pose, or null when a
  /// camera update is already in flight, nothing new is pending, or the newest
  /// pose belongs to a superseded route generation (rejected as stale).
  NavStreetlevelPose? acquire() {
    if (_inFlight) return null;
    final pose = _latest;
    if (pose == null) return null;
    if (pose.poseGeneration == _lastConsumedGeneration) return null;
    // PART E: atomic handoff — reject stale old-route poses after a reroute.
    if (_expectedRouteGeneration >= 0 &&
        pose.routeGeneration < _expectedRouteGeneration) {
      _lastConsumedGeneration = pose.poseGeneration;
      _droppedStaleTargets += 1;
      _staleCommandCancelled += 1;
      return null;
    }
    if (_expectedRenderEpoch >= 0 &&
        pose.renderEpoch < _expectedRenderEpoch) {
      _lastConsumedGeneration = pose.poseGeneration;
      _droppedStaleTargets += 1;
      _staleCommandCancelled += 1;
      return null;
    }
    _inFlight = true;
    _lastConsumedGeneration = pose.poseGeneration;
    return pose;
  }

  /// Marks the single in-flight camera update as finished.
  void complete() {
    _inFlight = false;
  }

  void reset() {
    _latest = null;
    _lastConsumedGeneration = -1;
    _inFlight = false;
    _droppedStaleTargets = 0;
    _coalescedCount = 0;
    _expectedRouteGeneration = -1;
    _expectedRenderEpoch = -1;
    _staleCommandCancelled = 0;
  }
}

/// PART H — bounded diagnostics line (no per-frame spam; caller dedups).
String formatNavStreetlevelFollowDiag({
  required int poseGeneration,
  required int cameraGeneration,
  required int vehicleGeneration,
  required int poseAgeMs,
  required int cameraUpdateIntervalMs,
  required double bearingTarget,
  required double bearingApplied,
  required double bearingDelta,
  required bool cameraInFlight,
  required int droppedStaleTargets,
  required String reason,
}) {
  return '[NAV_STREETLEVEL_FOLLOW] '
      'poseGeneration=$poseGeneration '
      'cameraGeneration=$cameraGeneration '
      'vehicleGeneration=$vehicleGeneration '
      'poseAgeMs=$poseAgeMs '
      'cameraUpdateIntervalMs=$cameraUpdateIntervalMs '
      'bearingTarget=${bearingTarget.toStringAsFixed(1)} '
      'bearingApplied=${bearingApplied.toStringAsFixed(1)} '
      'bearingDelta=${bearingDelta.toStringAsFixed(1)} '
      'cameraInFlight=$cameraInFlight '
      'droppedStaleTargets=$droppedStaleTargets '
      'reason=$reason';
}

/// NAV-LATENCY-1 (Part C) — bounded, rate-limited single-owner camera trace.
/// The caller dedups/rate-limits; this only formats. No coordinates.
String formatNavLatencyCameraDiag({
  required String owner,
  required int targetGeneration,
  required int appliedGeneration,
  required int targetAgeMs,
  required int requestToApplyMs,
  required int applyIntervalMs,
  required bool animationInFlight,
  required int coalescedCount,
  required int droppedCount,
  required String skipReason,
}) {
  return '[NAV_LATENCY_CAMERA] '
      'owner=$owner '
      'targetGeneration=$targetGeneration '
      'appliedGeneration=$appliedGeneration '
      'targetAgeMs=$targetAgeMs '
      'requestToApplyMs=$requestToApplyMs '
      'applyIntervalMs=$applyIntervalMs '
      'animationInFlight=$animationInFlight '
      'coalescedCount=$coalescedCount '
      'droppedCount=$droppedCount '
      'skipReason=${skipReason.isEmpty ? '-' : skipReason}';
}

// ---------------------------------------------------------------------------
// NAV-STREETLEVEL-FLUID-MOTION-1 — position correction blend policy.
// ---------------------------------------------------------------------------

/// Distance bands (metres) and bounded blend windows for correcting the
/// displayed pose toward a fresh GPS/engine anchor. Small deviations blend
/// smoothly; normal ones complete within ~250–500 ms; large/off-route ones use
/// a bounded recovery window; and irreconcilable jumps hard-reset instead of
/// smearing the vehicle across the map (never remain visually on the wrong road
/// for excessive smoothing, never teleport unless safety/correctness requires
/// it). Pure and side-effect-free.
class NavStreetlevelCorrectionPolicy {
  /// At/under this the correction is trivial — a short smooth blend.
  static const double smallM = 1.0;

  /// At/under this the correction is "normal" — completes within ~250–500 ms.
  static const double normalM = 15.0;

  /// Between [normalM] and [hardResetM] the correction is large/off-route and
  /// uses a single bounded recovery window (no unbounded slow smear).
  static const double hardResetM = 120.0;

  static const int minBlendMs = 250;
  static const int normalBlendMs = 500;
  static const int boundedRecoveryMs = 750;

  /// Whether the correction distance is so large that smoothing would keep the
  /// vehicle visibly on the wrong road: a hard reset (snap) is required.
  static bool requiresHardReset(double distanceM) =>
      !distanceM.isFinite || distanceM.abs() >= hardResetM;

  /// Suggested blend duration (ms) for a correction of [distanceM].
  ///
  ///  * <= 1 m  -> 250 ms smooth micro-correction
  ///  * <= 15 m -> linear 250 → 500 ms (normal correction)
  ///  * < 120 m -> 750 ms bounded recovery (large / off-route)
  ///  * >= 120 m -> 0 ms (hard reset — see [requiresHardReset])
  static int blendDurationMs(double distanceM) {
    final d = distanceM.abs();
    if (!d.isFinite) return 0;
    if (d <= smallM) return minBlendMs;
    if (d <= normalM) {
      final t = (d - smallM) / (normalM - smallM);
      return (minBlendMs + (normalBlendMs - minBlendMs) * t).round();
    }
    if (d < hardResetM) return boundedRecoveryMs;
    return 0;
  }

  /// Upper bound (ms) a correction of [distanceM] may blend. Used to *cap* an
  /// otherwise interval-derived following duration so large corrections never
  /// smear, while leaving normal following untouched (returns a high cap).
  static int maxBlendMsFor(double distanceM) {
    final d = distanceM.abs();
    if (!d.isFinite) return 0;
    if (d <= normalM) return normalBlendMs;
    if (d < hardResetM) return boundedRecoveryMs;
    return 0;
  }

  /// Monotonic ease-out fraction in [0, 1] for [elapsedMs] of [durationMs].
  /// Cubic ease-out ends with zero velocity so corrections never overshoot.
  static double easeFraction(int elapsedMs, int durationMs) {
    if (durationMs <= 0) return 1.0;
    final t = (elapsedMs / durationMs).clamp(0.0, 1.0);
    final inv = 1.0 - t;
    return 1.0 - inv * inv * inv;
  }
}

// ---------------------------------------------------------------------------
// NAV-STREETLEVEL-FLUID-MOTION-1 — rolling cadence statistics.
// ---------------------------------------------------------------------------

/// Bounded rolling window of intervals (ms) with median / p95 accessors, used
/// to distinguish the five cadences (raw GPS, engine-anchor, visual-pose,
/// camera-apply, rendered-frame) against the performance budget. Pure — the
/// widget feeds intervals and reads back summary statistics for diagnostics.
class NavFrameCadenceStats {
  NavFrameCadenceStats({this.capacity = 240});

  final int capacity;
  final List<double> _samples = <double>[];

  int get count => _samples.length;

  void add(double intervalMs) {
    if (!intervalMs.isFinite || intervalMs < 0) return;
    _samples.add(intervalMs);
    if (_samples.length > capacity) {
      _samples.removeAt(0);
    }
  }

  void reset() => _samples.clear();

  double get medianMs => _percentile(0.50);
  double get p95Ms => _percentile(0.95);
  double get maxMs =>
      _samples.isEmpty ? 0.0 : _samples.reduce((a, b) => a > b ? a : b);

  /// Count of intervals exceeding [thresholdMs] (e.g. >100 ms freezes).
  int freezesOver(double thresholdMs) =>
      _samples.where((s) => s > thresholdMs).length;

  double _percentile(double q) {
    if (_samples.isEmpty) return 0.0;
    final sorted = List<double>.from(_samples)..sort();
    final idx = (q * (sorted.length - 1)).round().clamp(0, sorted.length - 1);
    return sorted[idx];
  }
}

/// Formats the five-cadence budget line (NAV-STREETLEVEL-FLUID-MOTION-1).
/// Values are median/p95 interval milliseconds. Caller rate-limits.
String formatNavCadenceDiag({
  required double gpsMedianMs,
  required double anchorMedianMs,
  required double poseMedianMs,
  required double cameraApplyMedianMs,
  required double frameMedianMs,
  required double frameP95Ms,
  required int frameFreezesOver100,
  required double uiBuildMedianMs,
  required double rasterMedianMs,
}) {
  return '[NAV_LATENCY_CADENCE] '
      'gpsMedianMs=${gpsMedianMs.toStringAsFixed(0)} '
      'anchorMedianMs=${anchorMedianMs.toStringAsFixed(0)} '
      'poseMedianMs=${poseMedianMs.toStringAsFixed(0)} '
      'cameraApplyMedianMs=${cameraApplyMedianMs.toStringAsFixed(0)} '
      'frameMedianMs=${frameMedianMs.toStringAsFixed(1)} '
      'frameP95Ms=${frameP95Ms.toStringAsFixed(1)} '
      'frameFreezesOver100=$frameFreezesOver100 '
      'uiBuildMedianMs=${uiBuildMedianMs.toStringAsFixed(1)} '
      'rasterMedianMs=${rasterMedianMs.toStringAsFixed(1)}';
}
