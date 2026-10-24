/// SECURITY-REMOVE-CLIENT-ADMIN-TOKEN-P0-1 (Field Failure Fix, Commit 4)
///
/// Pure predicates for the deterministic STOP / navigation teardown.
///
/// Live-navigation is not a separate route — it is `DriverHomePage` rendered
/// in `_liveRideActive` mode. Exiting therefore means deterministically
/// clearing operational ride state so `_liveRideActive` resolves `false` and
/// the widget rebuilds into its normal driver-home / business-preview
/// rendering. This file encodes the invariant decisions of that teardown so
/// they can be unit-tested without pumping the full driver home widget.
///
/// Design invariants (enforced by tests):
///
///   1. Never uses `Navigator.pop` / `Navigator.popUntil` / `Navigator.maybePop`
///      as the mechanism for exiting the live navigation surface. State reset
///      is the only exit path.
///   2. Cleanup steps are independent of prior state:
///        - route/pin annotation cleanup runs regardless of whether
///          `_routeCoords` / `_routeSteps` are empty,
///        - wakelock release, camera/follow reset, native-follow disable,
///          booking-polling restart are all unconditional,
///        - every live-ride timer/callback is explicitly cancelled, never
///          delegated to a helper that early-returns when `_posSub == null`.
///   3. Drawer and bookings-hub are closed only through their owned state
///      (Scaffold's `closeDrawer()` and `_bookingsHubVisible = false`), never
///      by popping a generic route.
///   4. Preserves the minimum reconcile identity only when finalize is still
///      pending (`preservePendingDirectIdentity == true`); `_activeBooking`
///      and every other operational selection field is always cleared.
///   5. Idempotent — the state-class helper guards re-entry via a boolean
///      flag; every action here is safe to run on a duplicate call.
library;

/// Reason the teardown ran. Stable log token and test enum key. Never used
/// as a branch selector for the always-on cleanup fields — only the caller-
/// supplied `preservePendingDirectIdentity` decides identity preservation.
enum StopTeardownOutcome {
  /// Backend acknowledged the finalize (`/trip/stop` + `finalize-direct` or
  /// the shared reconcile ack).
  backendConfirmed,

  /// Local-only completion (no direct trip id was ever minted — legacy
  /// recovery from a client-only fallback). No reconcile is pending.
  localOnly,

  /// Backend `/trip/stop` or reconcile did not acknowledge finalize —
  /// preserve identity so a later reconcile can retry.
  finalizePending,

  /// HTTP 401/403 on `/trip/start-direct` — the ride never existed as a
  /// server-side session and nothing needs preservation.
  authFailure,

  /// Duplicate STOP tap or teardown called on already-cleared state. All
  /// idempotent actions still run so a partial prior teardown converges.
  alreadyCleared,
}

/// Inputs to `planDriverStopTeardown`. Every field is a plain value; nothing
/// depends on Flutter widgets or platform bindings.
class DriverStopTeardownContext {
  const DriverStopTeardownContext({
    required this.outcome,
    required this.isMounted,
    required this.bookingsHubVisible,
    required this.drawerOpen,
    required this.preservePendingDirectIdentity,
  });

  /// The reason teardown ran. Used only for logging + test enum coverage.
  final StopTeardownOutcome outcome;

  /// Whether the state class is still mounted. UI-side writes are
  /// short-circuited when `false`; state-only writes still run.
  final bool isMounted;

  /// Whether the bookings-hub overlay panel is currently visible. The panel
  /// is a boolean-driven overlay inside `DriverHomePage`, not a pushed
  /// route.
  final bool bookingsHubVisible;

  /// Whether a Scaffold-owned drawer is currently open. Read from
  /// `_scaffoldKey.currentState?.isDrawerOpen`. The drawer is closed via
  /// `ScaffoldState.closeDrawer()` (Scaffold-owned), never via a generic
  /// Navigator pop.
  final bool drawerOpen;

  /// Whether the minimum pending reconcile identity must survive teardown.
  /// Set by the caller when `wasDirectRide && !directFinalizeAcknowledged`.
  ///
  /// Preserved fields (state-class responsibility):
  ///   - `_activeDirectTripId`
  ///   - `_activeDirectBookingId`
  ///   - `_directRideKey`
  ///   - `_directStopFinalizePending`
  ///
  /// Never preserved (always cleared, even when this is true):
  ///   - `_activeBooking`
  ///   - `_activeTripId`
  ///   - `_directRideActive`
  ///   - meter / wait / km / ping state
  ///   - direct-ride destination / estimate / retry state
  final bool preservePendingDirectIdentity;
}

/// Output of `planDriverStopTeardown`. All boolean actions the state-class
/// helper must perform, computed from the context.
class DriverStopTeardownPlan {
  const DriverStopTeardownPlan({
    required this.outcome,
    required this.stopMeterTicker,
    required this.stopTracking,
    required this.releaseWakelock,
    required this.disableNativeFollow,
    required this.cancelMarkerSelfHealTimer,
    required this.cancelNavRouteRetryTimer,
    required this.cancelDriver3dActivationConfirmRetryTimer,
    required this.cancelDirectRideEstimateDebounce,
    required this.cancelDirectRideEstimateLocationRetryTimer,
    required this.resetPendingFollowCamera,
    required this.stopStreetlevelFollowPump,
    required this.resetNavR3MotionState,
    required this.flushNavValidationReport,
    required this.clearOperationalRideState,
    required this.resetCameraAndFollow,
    required this.clearRouteAndPinAnnotations,
    required this.restartBookingPolling,
    required this.preservePendingDirectIdentity,
    required this.closeScaffoldDrawer,
    required this.hideBookingsHubPanel,
  });

  final StopTeardownOutcome outcome;

  final bool stopMeterTicker;
  final bool stopTracking;
  final bool releaseWakelock;
  final bool disableNativeFollow;

  final bool cancelMarkerSelfHealTimer;
  final bool cancelNavRouteRetryTimer;
  final bool cancelDriver3dActivationConfirmRetryTimer;
  final bool cancelDirectRideEstimateDebounce;
  final bool cancelDirectRideEstimateLocationRetryTimer;
  final bool resetPendingFollowCamera;
  final bool stopStreetlevelFollowPump;
  final bool resetNavR3MotionState;
  final bool flushNavValidationReport;

  final bool clearOperationalRideState;
  final bool resetCameraAndFollow;
  final bool clearRouteAndPinAnnotations;
  final bool restartBookingPolling;

  final bool preservePendingDirectIdentity;

  final bool closeScaffoldDrawer;
  final bool hideBookingsHubPanel;
}

/// Pure predicate. Given a teardown context, decides which actions the
/// state-class helper must run.
///
/// The plan is deliberately conservative: every always-on cleanup field is
/// unconditionally `true` so a partially torn-down state converges on a
/// duplicate STOP. Only the drawer / hub closes and identity preservation
/// depend on the caller-supplied context.
DriverStopTeardownPlan planDriverStopTeardown(
  DriverStopTeardownContext context,
) {
  return DriverStopTeardownPlan(
    outcome: context.outcome,

    stopMeterTicker: true,
    stopTracking: true,
    releaseWakelock: true,
    disableNativeFollow: true,

    cancelMarkerSelfHealTimer: true,
    cancelNavRouteRetryTimer: true,
    cancelDriver3dActivationConfirmRetryTimer: true,
    cancelDirectRideEstimateDebounce: true,
    cancelDirectRideEstimateLocationRetryTimer: true,
    resetPendingFollowCamera: true,
    stopStreetlevelFollowPump: true,
    resetNavR3MotionState: true,
    flushNavValidationReport: true,

    clearOperationalRideState: true,
    resetCameraAndFollow: true,
    clearRouteAndPinAnnotations: true,
    restartBookingPolling: true,

    preservePendingDirectIdentity: context.preservePendingDirectIdentity,

    closeScaffoldDrawer: context.drawerOpen,
    hideBookingsHubPanel: context.bookingsHubVisible,
  );
}

/// Pure predicate mirroring `_liveRideActive` in the state class. Used by
/// tests to prove that the post-teardown values (`activeTripId == null`,
/// `directRideActive == false`) cause the DriverHomePage to rebuild into
/// its normal (non-live) rendering — no Navigator popping required.
bool computeLiveRideActiveForRendering({
  required String? activeTripId,
  required bool directRideActive,
}) {
  final trimmedTripId = activeTripId?.trim() ?? '';
  return trimmedTripId.isNotEmpty || directRideActive;
}
