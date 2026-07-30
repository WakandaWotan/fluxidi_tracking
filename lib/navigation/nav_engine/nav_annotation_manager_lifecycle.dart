// NAV-STYLE-MANAGER-CRASH-TELLERS-MARKER-1 / Commit 1
// NAV-ANNOTATION-MANAGER-TRANSACTIONAL-LIFECYCLE-2 / Commit
//
// Pure, unit-testable transactional executor for Mapbox annotation managers.
//
// Field crash (P0): after a style swap, Dart fired PolylineAnnotation.delete —
// and then, after Commit 1, PolylineAnnotation.CREATE — against a manager that
// had already been removed natively ("No manager found with id: 4"). Android
// terminated before Dart try/catch could recover.
//
// Commit 1 gated deletes but left create/update ungated and left a
// check-then-act window (pre-check → await → native op) during which disposal
// could remove the manager. This module now provides a LEASE: a native op
// acquires a lease atomically while ACTIVE (no await between the allow-check
// and the increment, so it is race-free in single-threaded Dart); disposal
// marks DRAINING (rejecting new ops) and then AWAITS all leases to reach zero
// before removeAnnotationManager. No create/update/delete/deleteAll can cross
// the Flutter → native boundary after its manager begins draining or is
// removed.

import 'dart:async';

/// Semantic role of a Mapbox annotation manager owned by driver navigation.
enum NavAnnotationManagerRole {
  route,
  pins,
  destination,
  driver,
}

/// Lifecycle state of one manager generation.
enum NavAnnotationManagerState {
  /// May accept create/update/delete/deleteAll against the native manager.
  active,

  /// Style/session replacement in progress. New ops for this generation are
  /// rejected; already-started ops may finish draining.
  draining,

  /// Native manager has been removed (or never existed). No native ops.
  disposed,
}

/// Kind of native annotation operation.
enum NavAnnotationOperationKind {
  create,
  update,
  delete,
  deleteAll,
  dispose,
  restore,
}

/// Reason a gated operation was rejected (PII-free).
enum NavAnnotationRejectReason {
  disposed,
  draining,
  generationMismatch,
  styleMismatch,
  sessionMismatch,
  epochMismatch,
  notActive,
}

/// Captured ownership for one annotation operation.
class NavAnnotationOwnership {
  const NavAnnotationOwnership({
    required this.managerGeneration,
    required this.styleGeneration,
    required this.sessionGeneration,
    required this.renderEpoch,
  });

  final int managerGeneration;
  final int styleGeneration;
  final int sessionGeneration;
  final int renderEpoch;
}

/// Result of a gate check. When [allowed] is false the caller MUST NOT cross
/// the Flutter → native boundary.
class NavAnnotationGateResult {
  const NavAnnotationGateResult.allow()
      : allowed = true,
        reason = null;

  const NavAnnotationGateResult.reject(this.reason)
      : allowed = false;

  final bool allowed;
  final NavAnnotationRejectReason? reason;
}

/// Outcome of a leased native operation run through the executor.
class NavAnnotationRunResult<T> {
  const NavAnnotationRunResult.ran(this.value)
      : ran = true,
        rejectReason = null;

  const NavAnnotationRunResult.stale(this.rejectReason)
      : ran = false,
        value = null;

  /// True when the native op actually ran under a held lease.
  final bool ran;

  /// The native op's return value (only when [ran]).
  final T? value;

  /// Why the op was rejected before start (only when not [ran]).
  final NavAnnotationRejectReason? rejectReason;
}

/// Bounded PII-free transaction event for [NAV_ANNOTATION_TX] diagnostics.
enum NavAnnotationTxEvent {
  queued,
  leaseAcquired,
  staleBeforeStart,
  nativeStarted,
  nativeCompleted,
  leaseReleased,
  drainStarted,
  drainWaiting,
  drainComplete,
  managerRemoved,
  commitAllowed,
  commitRejected,
}

String navAnnotationTxEventLabel(NavAnnotationTxEvent event) {
  switch (event) {
    case NavAnnotationTxEvent.queued:
      return 'queued';
    case NavAnnotationTxEvent.leaseAcquired:
      return 'lease_acquired';
    case NavAnnotationTxEvent.staleBeforeStart:
      return 'stale_before_start';
    case NavAnnotationTxEvent.nativeStarted:
      return 'native_started';
    case NavAnnotationTxEvent.nativeCompleted:
      return 'native_completed';
    case NavAnnotationTxEvent.leaseReleased:
      return 'lease_released';
    case NavAnnotationTxEvent.drainStarted:
      return 'drain_started';
    case NavAnnotationTxEvent.drainWaiting:
      return 'drain_waiting';
    case NavAnnotationTxEvent.drainComplete:
      return 'drain_complete';
    case NavAnnotationTxEvent.managerRemoved:
      return 'manager_removed';
    case NavAnnotationTxEvent.commitAllowed:
      return 'commit_allowed';
    case NavAnnotationTxEvent.commitRejected:
      return 'commit_rejected';
  }
}

/// Coarse bucket for queue depth / in-flight counts (PII-free, low-cardinality).
String navAnnotationCountBucket(int n) {
  if (n <= 0) return '0';
  if (n == 1) return '1';
  if (n <= 3) return '2-3';
  if (n <= 7) return '4-7';
  return '8+';
}

/// Latest-wins lifecycle owner for one annotation-manager role.
///
/// Pure: no Mapbox / platform I/O. The live app captures a token, checks
/// [allow], then only if allowed invokes the native manager.
class NavAnnotationManagerGate {
  NavAnnotationManagerGate(this.role);

  final NavAnnotationManagerRole role;

  int _managerGeneration = 0;
  NavAnnotationManagerState _state = NavAnnotationManagerState.disposed;
  int _styleGeneration = 0;
  int _sessionGeneration = 0;
  int _renderEpoch = 0;
  int _opsInFlight = 0;

  // NAV-ANNOTATION-MANAGER-TRANSACTIONAL-LIFECYCLE-2: lease bookkeeping. A lease
  // is held for the FULL duration of a native op; disposal awaits leases → 0
  // before removeAnnotationManager, so no op can race manager removal.
  int _leases = 0;
  Completer<void>? _drainCompleter;

  int get managerGeneration => _managerGeneration;
  NavAnnotationManagerState get state => _state;
  int get styleGeneration => _styleGeneration;
  int get sessionGeneration => _sessionGeneration;
  int get renderEpoch => _renderEpoch;
  int get opsInFlight => _opsInFlight;
  int get activeLeases => _leases;
  bool get isActive => _state == NavAnnotationManagerState.active;

  /// Activate a new manager generation (after native create). Bumps generation
  /// and binds the current ownership generations. Previous generation is
  /// immediately stale.
  NavAnnotationOwnership activate({
    required int styleGeneration,
    required int sessionGeneration,
    required int renderEpoch,
  }) {
    _managerGeneration += 1;
    _state = NavAnnotationManagerState.active;
    _styleGeneration = styleGeneration;
    _sessionGeneration = sessionGeneration;
    _renderEpoch = renderEpoch;
    _opsInFlight = 0;
    _leases = 0;
    _drainCompleter = null;
    return currentOwnership();
  }

  /// Begin draining the current generation: reject new ops, keep in-flight
  /// bookkeeping until [markDisposed]. Idempotent when already draining /
  /// disposed.
  void beginDrain() {
    if (_state == NavAnnotationManagerState.disposed) return;
    _state = NavAnnotationManagerState.draining;
  }

  /// Mark disposed. Idempotent — a second dispose is ignored.
  /// Returns true when this call transitioned into disposed.
  bool markDisposed() {
    if (_state == NavAnnotationManagerState.disposed) return false;
    _state = NavAnnotationManagerState.disposed;
    _opsInFlight = 0;
    _leases = 0;
    if (_drainCompleter != null && !_drainCompleter!.isCompleted) {
      _drainCompleter!.complete();
    }
    _drainCompleter = null;
    return true;
  }

  NavAnnotationOwnership currentOwnership() {
    return NavAnnotationOwnership(
      managerGeneration: _managerGeneration,
      styleGeneration: _styleGeneration,
      sessionGeneration: _sessionGeneration,
      renderEpoch: _renderEpoch,
    );
  }

  /// Capture ownership for a deferred / fire-and-forget operation.
  NavAnnotationOwnership capture() => currentOwnership();

  /// Book-keep an in-flight mutation. Returns false when the generation is
  /// not active (caller must not start the native op).
  bool beginOperation(NavAnnotationOwnership ownership) {
    final check = allow(ownership, NavAnnotationOperationKind.update);
    if (!check.allowed) return false;
    _opsInFlight += 1;
    return true;
  }

  void endOperation() {
    if (_opsInFlight > 0) _opsInFlight -= 1;
  }

  /// Atomically acquire a lease when [ownership] is [allow]ed. There is NO
  /// await between the allow-check and the increment, so — in single-threaded
  /// Dart — a lease can never be granted after [beginDrain]/[markDisposed]
  /// runs, and disposal can never remove the manager between the check and the
  /// native dispatch. Caller MUST pair a true result with [releaseLease] in a
  /// finally block. Returns false (op must NOT reach native) otherwise.
  bool tryAcquireLease(
    NavAnnotationOwnership ownership,
    NavAnnotationOperationKind kind,
  ) {
    final check = allow(ownership, kind);
    if (!check.allowed) return false;
    _leases += 1;
    return true;
  }

  void releaseLease() {
    if (_leases > 0) _leases -= 1;
    if (_leases == 0 &&
        _drainCompleter != null &&
        !_drainCompleter!.isCompleted) {
      _drainCompleter!.complete();
    }
  }

  /// Run [nativeOp] under a held lease. When ownership is stale/draining/
  /// disposed the native op is NEVER invoked and a stale result is returned.
  /// The lease guarantees the manager cannot be removed for the whole op.
  Future<NavAnnotationRunResult<T>> runGuarded<T>({
    required NavAnnotationOwnership ownership,
    required NavAnnotationOperationKind kind,
    required Future<T> Function() nativeOp,
  }) async {
    if (!tryAcquireLease(ownership, kind)) {
      final check = allow(ownership, kind);
      return NavAnnotationRunResult<T>.stale(check.reason);
    }
    try {
      final value = await nativeOp();
      return NavAnnotationRunResult<T>.ran(value);
    } finally {
      releaseLease();
    }
  }

  /// Await until all in-flight leases are released. Call AFTER [beginDrain]
  /// (which rejects new leases) and BEFORE removeAnnotationManager. Completes
  /// immediately when no lease is held.
  Future<void> awaitDrained() {
    if (_leases == 0) return Future<void>.value();
    _drainCompleter ??= Completer<void>();
    return _drainCompleter!.future;
  }

  /// True when the queue for [ownership.managerGeneration] has no in-flight
  /// ops (or the generation is already disposed). Used by style-swap drain.
  bool isQueueDrained(NavAnnotationOwnership ownership) {
    if (ownership.managerGeneration != _managerGeneration) return true;
    return _opsInFlight == 0;
  }

  /// Gate a native operation. Dispose is allowed while draining so the
  /// lifecycle can finish; every other kind requires an exact ownership match
  /// and [active] state.
  NavAnnotationGateResult allow(
    NavAnnotationOwnership ownership,
    NavAnnotationOperationKind kind,
  ) {
    if (ownership.managerGeneration != _managerGeneration) {
      return const NavAnnotationGateResult.reject(
        NavAnnotationRejectReason.generationMismatch,
      );
    }
    if (kind == NavAnnotationOperationKind.dispose) {
      if (_state == NavAnnotationManagerState.disposed) {
        return const NavAnnotationGateResult.reject(
          NavAnnotationRejectReason.disposed,
        );
      }
      return const NavAnnotationGateResult.allow();
    }
    if (_state == NavAnnotationManagerState.disposed) {
      return const NavAnnotationGateResult.reject(
        NavAnnotationRejectReason.disposed,
      );
    }
    if (_state == NavAnnotationManagerState.draining) {
      return const NavAnnotationGateResult.reject(
        NavAnnotationRejectReason.draining,
      );
    }
    if (ownership.styleGeneration != _styleGeneration) {
      return const NavAnnotationGateResult.reject(
        NavAnnotationRejectReason.styleMismatch,
      );
    }
    if (ownership.sessionGeneration != _sessionGeneration) {
      return const NavAnnotationGateResult.reject(
        NavAnnotationRejectReason.sessionMismatch,
      );
    }
    if (ownership.renderEpoch != _renderEpoch) {
      return const NavAnnotationGateResult.reject(
        NavAnnotationRejectReason.epochMismatch,
      );
    }
    if (_state != NavAnnotationManagerState.active) {
      return const NavAnnotationGateResult.reject(
        NavAnnotationRejectReason.notActive,
      );
    }
    return const NavAnnotationGateResult.allow();
  }

  /// PII-free diagnostic line for [NAV_ANNOTATION_MANAGER] logs.
  String formatDiag({
    required String event,
    NavAnnotationOperationKind? operation,
    NavAnnotationRejectReason? reason,
    int? routeVersion,
  }) {
    final buf = StringBuffer('role=${role.name} ')
      ..write('managerGeneration=$_managerGeneration ')
      ..write('state=${_state.name} ')
      ..write('styleGeneration=$_styleGeneration ')
      ..write('sessionGeneration=$_sessionGeneration ')
      ..write('renderEpoch=$_renderEpoch ')
      ..write('event=$event');
    if (operation != null) buf.write(' operation=${operation.name}');
    if (reason != null) buf.write(' reason=${reason.name}');
    if (routeVersion != null) buf.write(' routeVersion=$routeVersion');
    return buf.toString();
  }
}

/// NAV-ANNOTATION-MANAGER-TRANSACTIONAL-LIFECYCLE-2 / Phase 6 —
/// NAV-MOBILE-DATA-MINIMAL-SAFE-RELEASE-P0-1 Part D: central emergency
/// kill-switch for active-ride map-style switching.
///
/// Final release navigation flow: map-style switching is locked during active
/// NAV guidance and during the paid customer trip. Preview (before NAV/START)
/// keeps the style selector; the selected style is preserved into the ride.
const bool kNavActiveRideStyleSwitchEnabled = false;

/// Fail-safe decision (Phase 6): given whether a live ride is active and a
/// style transaction is already running, should a new style tap begin a swap
/// now, be coalesced (latest-wins, re-applied on completion), or be blocked by
/// the emergency kill-switch?
enum NavStyleTapDecision { begin, coalesce, blocked }

NavStyleTapDecision navStyleTapDecision({
  required bool liveRideActive,
  required bool styleTransactionRunning,
  bool activeRideStyleSwitchEnabled = kNavActiveRideStyleSwitchEnabled,
}) {
  if (liveRideActive && !activeRideStyleSwitchEnabled) {
    return NavStyleTapDecision.blocked;
  }
  if (styleTransactionRunning) return NavStyleTapDecision.coalesce;
  return NavStyleTapDecision.begin;
}

/// True when a Tellers presentation-mode change must NOT request a map style
/// change. Tellers is HUD/viewport only.
bool tellersPresentationMustNotChangeMapStyle() => true;

/// Style-swap drain sequence for one manager role. Pure decision helper used
/// by tests and diagnostics — the live app mirrors these steps.
enum NavAnnotationStyleSwapStep {
  beginDrain,
  rejectNewOps,
  invalidateStaleQueued,
  awaitInFlight,
  disposeOnce,
  nullReferences,
  activateNewGeneration,
  restoreCurrentOwner,
}

/// Ordered steps that a style replacement MUST execute for each manager role.
List<NavAnnotationStyleSwapStep> navAnnotationStyleSwapSteps() {
  return const <NavAnnotationStyleSwapStep>[
    NavAnnotationStyleSwapStep.beginDrain,
    NavAnnotationStyleSwapStep.rejectNewOps,
    NavAnnotationStyleSwapStep.invalidateStaleQueued,
    NavAnnotationStyleSwapStep.awaitInFlight,
    NavAnnotationStyleSwapStep.disposeOnce,
    NavAnnotationStyleSwapStep.nullReferences,
    NavAnnotationStyleSwapStep.activateNewGeneration,
    NavAnnotationStyleSwapStep.restoreCurrentOwner,
  ];
}
