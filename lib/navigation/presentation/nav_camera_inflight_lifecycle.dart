// NAV-CAMERA-INFLIGHT-SELF-HEAL-1
//
// Pure, injectable lifecycle for `_followCameraTesla`'s "in-flight camera
// animation" gate. Extracted so the state-machine (generation counter,
// clear-on-outcome, bounded timeout, latest-wins pending, style invalidation)
// is unit-testable without a widget tree or a live Mapbox instance.
//
// SAFETY CONTRACT
// ---------------
//  * Exactly one lifecycle owner per camera run. `begin()` bumps a monotonic
//    generation; the caller must pass that generation back to `tryClear(gen)`
//    from an outer `try/finally`.
//  * `tryClear(gen)` only clears when `gen == currentGeneration`, so an older
//    (stale) run cannot accidentally clear a newer run's in-flight state.
//  * `reset()` / `invalidate()` hard-clear AND bump the generation — any
//    lingering async outcome from before becomes stale and is a no-op.
//  * A missing Mapbox completion never blocks forever: either the caller's
//    `Future.timeout` or [armTimeout] releases the expired owner.
//  * At most one pending camera target is retained (latest-wins).
//  * User commands may supersede a passive owner without waiting seconds.
//  * `dispose()` cancels timers and rejects further begins.

import 'dart:async';
import 'dart:math' as math;

/// Camera command kinds used for priority and diagnostics.
enum NavCameraCommandKind {
  passiveFollow,
  pendingReplay,
  userViewZoom,
  userRecenter,
  userOverview,
  styleRestore,
  viewMode,
  other,
}

extension NavCameraCommandKindLabel on NavCameraCommandKind {
  String get label {
    switch (this) {
      case NavCameraCommandKind.passiveFollow:
        return 'passive_follow';
      case NavCameraCommandKind.pendingReplay:
        return 'pending_replay';
      case NavCameraCommandKind.userViewZoom:
        return 'user_view_zoom';
      case NavCameraCommandKind.userRecenter:
        return 'user_recenter';
      case NavCameraCommandKind.userOverview:
        return 'user_overview';
      case NavCameraCommandKind.styleRestore:
        return 'style_restore';
      case NavCameraCommandKind.viewMode:
        return 'view_mode';
      case NavCameraCommandKind.other:
        return 'other';
    }
  }

  bool get isUserCommand {
    switch (this) {
      case NavCameraCommandKind.userViewZoom:
      case NavCameraCommandKind.userRecenter:
      case NavCameraCommandKind.userOverview:
      case NavCameraCommandKind.viewMode:
        return true;
      case NavCameraCommandKind.passiveFollow:
      case NavCameraCommandKind.pendingReplay:
      case NavCameraCommandKind.styleRestore:
      case NavCameraCommandKind.other:
        return false;
    }
  }
}

/// Map a `_followCameraTesla` cameraReason string onto a command kind.
NavCameraCommandKind navCameraCommandKindFromReason(String reason) {
  switch (reason) {
    case 'cockpit_adjust':
      return NavCameraCommandKind.userViewZoom;
    case 'manual_recenter':
      return NavCameraCommandKind.userRecenter;
    case 'overview':
      return NavCameraCommandKind.userOverview;
    case 'view_mode':
      return NavCameraCommandKind.viewMode;
    case 'style_switch':
      return NavCameraCommandKind.styleRestore;
    case 'pending_latest':
      return NavCameraCommandKind.pendingReplay;
    case 'normal_follow':
      return NavCameraCommandKind.passiveFollow;
    default:
      return NavCameraCommandKind.other;
  }
}

/// Diagnostic event kinds required by NAV-CAMERA-INFLIGHT-SELF-HEAL-1.
enum NavCameraInFlightEvent {
  commandStarted,
  pendingReplaced,
  staleCompletionIgnored,
  commandCompleted,
  commandFailed,
  commandTimedOut,
  ownerInvalidated,
  pendingReplayed,
}

extension NavCameraInFlightEventLabel on NavCameraInFlightEvent {
  String get label {
    switch (this) {
      case NavCameraInFlightEvent.commandStarted:
        return 'command_started';
      case NavCameraInFlightEvent.pendingReplaced:
        return 'pending_replaced';
      case NavCameraInFlightEvent.staleCompletionIgnored:
        return 'stale_completion_ignored';
      case NavCameraInFlightEvent.commandCompleted:
        return 'command_completed';
      case NavCameraInFlightEvent.commandFailed:
        return 'command_failed';
      case NavCameraInFlightEvent.commandTimedOut:
        return 'command_timed_out';
      case NavCameraInFlightEvent.ownerInvalidated:
        return 'owner_invalidated';
      case NavCameraInFlightEvent.pendingReplayed:
        return 'pending_replayed';
    }
  }
}

/// Legacy phase labels kept for existing call sites / log formatting.
enum NavCameraInFlightPhase {
  start,
  complete,
  timeout,
  error,
  stale,
  cleared,
}

extension NavCameraInFlightPhaseLabel on NavCameraInFlightPhase {
  String get label {
    switch (this) {
      case NavCameraInFlightPhase.start:
        return 'start';
      case NavCameraInFlightPhase.complete:
        return 'complete';
      case NavCameraInFlightPhase.timeout:
        return 'timeout';
      case NavCameraInFlightPhase.error:
        return 'error';
      case NavCameraInFlightPhase.stale:
        return 'stale';
      case NavCameraInFlightPhase.cleared:
        return 'cleared';
    }
  }
}

/// Outcome of a single async camera run.
enum NavCameraInFlightOutcome {
  /// flyTo resolved before the bounded timeout.
  success,

  /// flyTo did not resolve within the bounded timeout window. Follow must
  /// resume and pending must be re-scheduled.
  timeout,

  /// Synchronous OR asynchronous throw. Follow must resume; the caller may
  /// log the reason via `onPhase`.
  error,

  /// The lifecycle was already advanced by a newer run before this outcome
  /// arrived. The state must NOT be cleared here.
  stale,

  /// Lifecycle was disposed before the run completed.
  disposed,
}

/// One latest-wins pending camera target.
class NavCameraPendingTarget<T> {
  const NavCameraPendingTarget({
    required this.kind,
    required this.target,
  });

  final NavCameraCommandKind kind;
  final T target;
}

/// In-flight gate + monotonic generation for the driver-home follow camera.
///
/// Not thread-safe by design: the driver-home camera path is single-isolate
/// (Flutter main isolate), and `begin`/`tryClear` calls always run on the
/// same event loop.
class NavCameraInFlightLifecycle {
  bool _inFlight = false;
  int _currentGeneration = 0;
  NavCameraCommandKind? _activeKind;
  DateTime? _startedAt;
  Duration? _expectedDuration;
  bool _disposed = false;
  Timer? _timeoutTimer;
  NavCameraPendingTarget<Object?>? _pending;
  void Function(NavCameraInFlightEvent event, {String? reason})? onEvent;

  /// True while a camera animation is owned by SOME run.
  bool get inFlight => _inFlight;

  /// The generation last handed out by [begin] (or 0 if none yet).
  int get currentGeneration => _currentGeneration;

  /// Active command kind, if any.
  NavCameraCommandKind? get activeKind => _activeKind;

  /// True after [dispose].
  bool get isDisposed => _disposed;

  /// True when a latest-wins pending target is waiting.
  bool get hasPending => _pending != null;

  /// Pending command kind, if any.
  NavCameraCommandKind? get pendingKind => _pending?.kind;

  /// Pending target payload (opaque to the lifecycle).
  Object? get pendingTarget => _pending?.target;

  DateTime? get startedAt => _startedAt;

  Duration? get expectedDuration => _expectedDuration;

  /// Begin a new camera run. Returns a monotonically increasing generation
  /// token that MUST be passed back to [tryClear] from an outer `finally`.
  ///
  /// Returns `null` when the lifecycle is disposed.
  int? begin({
    NavCameraCommandKind kind = NavCameraCommandKind.other,
    Duration? expectedDuration,
    DateTime Function() now = _defaultNow,
  }) {
    if (_disposed) return null;
    _cancelTimeoutTimer();
    _inFlight = true;
    _currentGeneration += 1;
    _activeKind = kind;
    _startedAt = now();
    _expectedDuration = expectedDuration;
    onEvent?.call(
      NavCameraInFlightEvent.commandStarted,
      reason: kind.label,
    );
    return _currentGeneration;
  }

  /// Attempt to clear the in-flight flag for [generation]. Returns `true` when
  /// [generation] still matches the current run (so the caller may schedule
  /// pending follow-ups), or `false` when a newer run already owns the state
  /// (in which case the caller must NOT touch pending / flags — the newer
  /// run's own `tryClear` will do it).
  bool tryClear(int generation, {NavCameraInFlightEvent? successEvent}) {
    if (_disposed) return false;
    // A completion/timeout/failure may clear only while this generation is
    // still the active in-flight owner. After timeout/supersede/invalidate,
    // the same generation must be ignored (stale).
    if (!_inFlight || generation != _currentGeneration) {
      onEvent?.call(
        NavCameraInFlightEvent.staleCompletionIgnored,
        reason: !_inFlight ? 'already_released' : 'newer_run_owns',
      );
      return false;
    }
    _cancelTimeoutTimer();
    _inFlight = false;
    _activeKind = null;
    _startedAt = null;
    _expectedDuration = null;
    if (successEvent != null) {
      onEvent?.call(successEvent);
    }
    return true;
  }

  /// Mark [generation] completed successfully.
  bool complete(int generation) => tryClear(
        generation,
        successEvent: NavCameraInFlightEvent.commandCompleted,
      );

  /// Mark [generation] failed. Only clears matching owner.
  bool fail(int generation, {String? reason}) {
    final cleared = tryClear(
      generation,
      successEvent: NavCameraInFlightEvent.commandFailed,
    );
    if (!cleared && reason != null) {
      onEvent?.call(
        NavCameraInFlightEvent.staleCompletionIgnored,
        reason: reason,
      );
    }
    return cleared;
  }

  /// Mark [generation] timed out. Only clears matching owner.
  bool markTimedOut(int generation) => tryClear(
        generation,
        successEvent: NavCameraInFlightEvent.commandTimedOut,
      );

  /// Hard clear used by stop/dispose. Any in-flight run's later `tryClear`
  /// call becomes stale because the generation is bumped.
  void reset({String reason = 'reset'}) {
    if (_disposed) return;
    _cancelTimeoutTimer();
    final hadOwner = _inFlight || _pending != null;
    _inFlight = false;
    _activeKind = null;
    _startedAt = null;
    _expectedDuration = null;
    _pending = null;
    _currentGeneration += 1;
    if (hadOwner) {
      onEvent?.call(
        NavCameraInFlightEvent.ownerInvalidated,
        reason: reason,
      );
    }
  }

  /// Style / route / session ownership change. Clears obsolete pending and
  /// invalidates the previous camera generation.
  void invalidate({String reason = 'style_or_session'}) =>
      reset(reason: reason);

  /// Retain at most one pending target. Newer targets replace older ones.
  void setPending<T>(NavCameraCommandKind kind, T target) {
    if (_disposed) return;
    final replaced = _pending != null;
    _pending = NavCameraPendingTarget<Object?>(kind: kind, target: target);
    if (replaced) {
      onEvent?.call(
        NavCameraInFlightEvent.pendingReplaced,
        reason: kind.label,
      );
    }
  }

  /// Take and clear the pending target. Returns null when empty/disposed.
  NavCameraPendingTarget<Object?>? takePending({bool reportReplay = false}) {
    if (_disposed) return null;
    final pending = _pending;
    _pending = null;
    if (pending != null && reportReplay) {
      onEvent?.call(
        NavCameraInFlightEvent.pendingReplayed,
        reason: pending.kind.label,
      );
    }
    return pending;
  }

  /// Clear pending without bumping generation.
  void clearPending() {
    _pending = null;
  }

  /// Arm a timeout that releases only [generation] when it fires.
  void armTimeout({
    required int generation,
    required Duration timeout,
    void Function(int generation)? onTimeout,
  }) {
    if (_disposed) return;
    _cancelTimeoutTimer();
    if (!_inFlight || generation != _currentGeneration) return;
    _timeoutTimer = Timer(timeout, () {
      _timeoutTimer = null;
      if (_disposed) return;
      if (!_inFlight || generation != _currentGeneration) return;
      markTimedOut(generation);
      onTimeout?.call(generation);
    });
  }

  /// Cancel any armed timeout timer.
  void cancelTimeout() => _cancelTimeoutTimer();

  /// Dispose the lifecycle: cancel timers, invalidate owner, reject begins.
  void dispose() {
    _cancelTimeoutTimer();
    _inFlight = false;
    _activeKind = null;
    _startedAt = null;
    _expectedDuration = null;
    _pending = null;
    _currentGeneration += 1;
    _disposed = true;
    onEvent?.call(
      NavCameraInFlightEvent.ownerInvalidated,
      reason: 'disposed',
    );
  }

  void _cancelTimeoutTimer() {
    _timeoutTimer?.cancel();
    _timeoutTimer = null;
  }
}

/// Bounded timeout for a single camera flyTo. Never dips below `animMs+400 ms`
/// and doubles the animation time to absorb one-frame stalls without ever
/// letting a broken/never-completing flyTo leave the state in-flight forever.
///
/// Kept as a top-level function so the tuning knob is trivially unit-testable.
/// Maximum for normal follow/view animMs (<=1000) stays at 2000 ms — never
/// a 10–30 s hang.
Duration computeNavCameraInFlightTimeout(int animMs) {
  final baseMs = animMs.isFinite && animMs > 0 ? animMs : 220;
  final doubled = baseMs * 2;
  final withHeadroom = baseMs + 400;
  final ms = math.max(doubled, withHeadroom);
  // Hard ceiling so a misconfigured animMs cannot recreate multi-second hangs.
  final capped = math.min(ms, 2500);
  return Duration(milliseconds: capped);
}

/// PII-free bounded diagnostic line for `[NAV_CAMERA_INFLIGHT]`. Never
/// includes coordinates, bookingIds, or driver identifiers — only structural
/// facts about the camera run.
String formatNavCameraInFlightDiagnostic({
  required NavCameraInFlightPhase phase,
  required int generation,
  int? animMs,
  int? ageMs,
  bool hasPending = false,
  String? reason,
  String? commandKind,
  String? event,
}) {
  final buffer = StringBuffer('[NAV_CAMERA_INFLIGHT] ')
    ..write('phase=${phase.label} ')
    ..write('generation=$generation ')
    ..write('animMs=${animMs ?? -1} ')
    ..write('ageMs=${ageMs ?? -1} ')
    ..write('hasPending=$hasPending ')
    ..write(
      'commandKind=${(commandKind == null || commandKind.isEmpty) ? 'none' : commandKind} ',
    )
    ..write(
      'event=${(event == null || event.isEmpty) ? 'none' : event} ',
    )
    ..write('reason=${(reason == null || reason.isEmpty) ? 'none' : reason}');
  return buffer.toString();
}

/// Injectable runner for a single camera flyTo. Guarantees the in-flight
/// state is cleared on every outcome:
///
///   * success        -> phase=complete + tryClear -> phase=cleared
///   * timeout        -> phase=timeout  + tryClear -> phase=cleared
///   * sync/async err -> phase=error    + tryClear -> phase=cleared
///   * newer run ran  -> phase=stale    (do NOT clear; newer run owns state)
///
/// The [flyToFactory] is invoked eagerly so a synchronous throw inside the
/// factory is caught by the runner (this is the crucial safety net that the
/// bug report identified: 275 lines of synchronous code between SET and the
/// existing inner try/finally).
Future<NavCameraInFlightOutcome> runNavCameraInFlightFlyTo({
  required NavCameraInFlightLifecycle lifecycle,
  required int generation,
  required int animMs,
  required Future<void> Function() flyToFactory,
  required void Function(NavCameraInFlightPhase phase, {String? reason}) onPhase,
  DateTime Function() now = _defaultNow,
}) async {
  if (lifecycle.isDisposed) {
    onPhase(NavCameraInFlightPhase.stale, reason: 'disposed');
    return NavCameraInFlightOutcome.disposed;
  }
  final startedAt = now();
  onPhase(NavCameraInFlightPhase.start);
  final timeout = computeNavCameraInFlightTimeout(animMs);
  NavCameraInFlightOutcome outcome;
  try {
    Future<void> future;
    try {
      future = flyToFactory();
    } catch (e) {
      onPhase(NavCameraInFlightPhase.error, reason: 'sync_throw');
      return _finish(
        lifecycle,
        generation,
        onPhase,
        NavCameraInFlightOutcome.error,
      );
    }
    try {
      await future.timeout(timeout);
      onPhase(NavCameraInFlightPhase.complete);
      outcome = NavCameraInFlightOutcome.success;
    } on TimeoutException {
      final ageMs = now().difference(startedAt).inMilliseconds;
      onPhase(
        NavCameraInFlightPhase.timeout,
        reason: 'flyTo_no_completion_${ageMs}ms',
      );
      outcome = NavCameraInFlightOutcome.timeout;
    } catch (e) {
      onPhase(NavCameraInFlightPhase.error, reason: 'async_throw');
      outcome = NavCameraInFlightOutcome.error;
    }
  } finally {
    // nothing: the tryClear + cleared/stale phase is emitted below so callers
    // observe a single ordering (start -> outcome-phase -> cleared|stale).
  }
  return _finish(lifecycle, generation, onPhase, outcome);
}

NavCameraInFlightOutcome _finish(
  NavCameraInFlightLifecycle lifecycle,
  int generation,
  void Function(NavCameraInFlightPhase, {String? reason}) onPhase,
  NavCameraInFlightOutcome outcome,
) {
  final event = switch (outcome) {
    NavCameraInFlightOutcome.success => NavCameraInFlightEvent.commandCompleted,
    NavCameraInFlightOutcome.timeout => NavCameraInFlightEvent.commandTimedOut,
    NavCameraInFlightOutcome.error => NavCameraInFlightEvent.commandFailed,
    NavCameraInFlightOutcome.stale => null,
    NavCameraInFlightOutcome.disposed => null,
  };
  final cleared = lifecycle.tryClear(generation, successEvent: event);
  if (cleared) {
    onPhase(NavCameraInFlightPhase.cleared);
  } else {
    onPhase(NavCameraInFlightPhase.stale, reason: 'newer_run_owns');
    return NavCameraInFlightOutcome.stale;
  }
  return outcome;
}

DateTime _defaultNow() => DateTime.now();
