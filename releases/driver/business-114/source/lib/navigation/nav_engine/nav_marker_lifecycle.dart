/// NAV-R12-D: pure decision state for taxi marker self-heal and update
/// coalescing.
///
/// Holds no Mapbox/Flutter references so the transitions are unit-testable:
/// the widget layer reports events (native failure, self-heal attempt,
/// successful apply) and asks this object what to do next. All timing is
/// injected via `DateTime now` parameters.
class NavMarkerLifecycle {
  /// Backoff schedule between self-heal attempts within one degradation
  /// episode. The last entry repeats, so retries never stop while
  /// navigation is active but can never busy-loop either.
  static const List<Duration> backoffSchedule = <Duration>[
    Duration(milliseconds: 250),
    Duration(milliseconds: 500),
    Duration(seconds: 1),
    Duration(seconds: 2),
    Duration(seconds: 4),
    Duration(seconds: 8),
  ];

  bool _degraded = false;
  String _lastFailureReason = 'none';
  int _selfHealAttempts = 0;
  DateTime? _nextSelfHealAt;
  DateTime? _lastUpdateAttemptAt;
  DateTime? _lastAppliedAt;
  bool _updateInFlight = false;
  bool _pendingUpdate = false;

  /// True after a native manager/marker failure until a self-heal or a
  /// successful marker apply proves the pipeline healthy again.
  bool get degraded => _degraded;

  String get lastFailureReason => _lastFailureReason;

  /// Self-heal attempts within the current degradation episode.
  int get selfHealAttempts => _selfHealAttempts;

  /// Earliest moment the next self-heal attempt may run (null when healthy).
  DateTime? get nextSelfHealAt => _nextSelfHealAt;

  DateTime? get lastUpdateAttemptAt => _lastUpdateAttemptAt;

  DateTime? get lastAppliedAt => _lastAppliedAt;

  /// True while a native marker update is awaiting its platform call.
  bool get updateInFlight => _updateInFlight;

  /// True when at least one newer fix arrived while an update was in flight.
  bool get pendingUpdate => _pendingUpdate;

  /// Backoff before attempt number [attempt] (0-based); clamps to the last
  /// schedule entry.
  static Duration backoffForAttempt(int attempt) {
    if (attempt <= 0) return backoffSchedule.first;
    if (attempt >= backoffSchedule.length) return backoffSchedule.last;
    return backoffSchedule[attempt];
  }

  /// Native manager/marker failure: mark degraded and compute the earliest
  /// next self-heal moment.
  void noteFailure(String reason, DateTime now) {
    _degraded = true;
    _lastFailureReason = reason;
    _nextSelfHealAt = now.add(backoffForAttempt(_selfHealAttempts));
  }

  /// Whether a self-heal attempt may run now.
  bool shouldAttemptSelfHeal(DateTime now) {
    if (!_degraded) return false;
    final next = _nextSelfHealAt;
    return next == null || !now.isBefore(next);
  }

  /// Delay until the next allowed self-heal attempt (zero when overdue).
  Duration selfHealDelay(DateTime now) {
    final next = _nextSelfHealAt;
    if (next == null || !now.isBefore(next)) return Duration.zero;
    return next.difference(now);
  }

  /// Records the start of a self-heal attempt; returns its 1-based number.
  int noteSelfHealAttemptStarted(DateTime now) {
    _selfHealAttempts += 1;
    return _selfHealAttempts;
  }

  void noteSelfHealSucceeded(DateTime now) {
    _degraded = false;
    _lastFailureReason = 'none';
    _selfHealAttempts = 0;
    _nextSelfHealAt = null;
  }

  void noteSelfHealFailed(String reason, DateTime now) {
    _degraded = true;
    _lastFailureReason = reason;
    _nextSelfHealAt = now.add(backoffForAttempt(_selfHealAttempts));
  }

  /// Gate for a coalesced marker update. Returns true when the caller may
  /// start a native update now; returns false (and remembers a pending
  /// update) when one is already in flight — last-wins.
  bool beginUpdate(DateTime now) {
    if (_updateInFlight) {
      _pendingUpdate = true;
      return false;
    }
    _updateInFlight = true;
    _lastUpdateAttemptAt = now;
    return true;
  }

  /// Completes an update. Returns true when a newer fix arrived meanwhile
  /// and the caller should immediately run one more update with the latest
  /// data.
  bool finishUpdate({required bool applied, required DateTime now}) {
    _updateInFlight = false;
    if (applied) {
      _lastAppliedAt = now;
      // A successful native write proves the manager is healthy.
      _degraded = false;
      _lastFailureReason = 'none';
      _selfHealAttempts = 0;
      _nextSelfHealAt = null;
    }
    final rerun = _pendingUpdate;
    _pendingUpdate = false;
    return rerun;
  }

  /// Full reset when active navigation stops or the map is torn down.
  void reset() {
    _degraded = false;
    _lastFailureReason = 'none';
    _selfHealAttempts = 0;
    _nextSelfHealAt = null;
    _lastUpdateAttemptAt = null;
    _lastAppliedAt = null;
    _updateInFlight = false;
    _pendingUpdate = false;
  }
}
