// NAV-STYLE-MANAGER-CRASH-TELLERS-MARKER-1 / Commit 1
//
// Pure, unit-testable lifecycle gate for Mapbox annotation managers.
//
// Field crash (P0): after a style swap, Dart fired PolylineAnnotation.delete
// against a manager that had already been removed natively
// ("No manager found with id: 4"). Android terminated before Dart try/catch
// could recover. This module guarantees every native annotation operation is
// gated by a monotonically increasing managerGeneration and an explicit
// active → draining → disposed lifecycle BEFORE the Flutter → native boundary.

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

  int get managerGeneration => _managerGeneration;
  NavAnnotationManagerState get state => _state;
  int get styleGeneration => _styleGeneration;
  int get sessionGeneration => _sessionGeneration;
  int get renderEpoch => _renderEpoch;
  int get opsInFlight => _opsInFlight;
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
