// NAV-MOBILE-DATA-MINIMAL-SAFE-RELEASE-P0-1
//
// Bounded latest-wins background dispatcher primitives for the driver
// navigation GPS pipeline. Kept pure (no Mapbox / Flutter widget deps) so it
// can be exercised deterministically from unit tests.
//
// Rules enforced here:
//   - at most ONE async task in flight at any time;
//   - capacity-ONE latest pending input (a newer eligible input replaces an
//     older pending one — no unbounded queue);
//   - task exceptions are contained and reported through the [onError] hook,
//     they cannot break the dispatcher or the caller thread;
//   - disposal releases ownership and drops any pending work.
//
// The dispatchers themselves do not schedule Mapbox / HTTP work — the caller
// provides a `runner` callback that performs the actual operation. This keeps
// the dispatchers safe to import from test code.

import 'dart:async';

/// PII-free lifecycle event token emitted by a [NavBackgroundDispatcher].
///
/// Kept enumerated (not free-form strings) so field diagnostics can compare
/// exactly, and never accidentally include coordinates or IDs.
enum NavBackgroundDispatchEvent {
  /// Input accepted while nothing was in flight — task will start immediately.
  enqueuedStart,

  /// Input accepted while a task was in flight — held as the (single) pending
  /// latest input.
  enqueuedPending,

  /// A newer input replaced an older still-pending input.
  replacedPending,

  /// Input rejected because the dispatcher was already disposed.
  rejectedDisposed,

  /// Input rejected because a runner-provided eligibility check returned false
  /// (rate limiting, session missing, etc.). The caller decides the meaning.
  rejectedIneligible,

  /// A background task started executing.
  started,

  /// A background task completed successfully.
  completed,

  /// A background task completed with a caught error (contained).
  failed,

  /// A background task was aborted after a wall-clock timeout.
  timedOut,

  /// The dispatcher was disposed; any pending input was dropped.
  disposed,
}

/// PII-free observer hook signature.
typedef NavBackgroundDispatchObserver = void Function(
  NavBackgroundDispatchEvent event,
);

/// PII-free runner error observer.
typedef NavBackgroundDispatchErrorObserver = void Function(
  Object error,
  StackTrace stackTrace,
);

/// The signature callers provide to run one dispatched task. The dispatcher
/// awaits this future; the underlying resource ownership (HTTP client, Mapbox
/// annotation manager) belongs to the caller.
typedef NavBackgroundDispatchRunner<T> = Future<void> Function(T input);

/// Optional pre-run eligibility check. Returning false rejects the input as
/// [NavBackgroundDispatchEvent.rejectedIneligible] without starting the runner
/// and without changing pending/in-flight state.
typedef NavBackgroundDispatchEligibility<T> = bool Function(T input);

/// Bounded latest-wins background dispatcher.
///
/// Not thread-safe across isolates. The Flutter UI isolate runs a single
/// event loop; the dispatcher is designed for that model.
class NavBackgroundDispatcher<T> {
  NavBackgroundDispatcher({
    required NavBackgroundDispatchRunner<T> runner,
    NavBackgroundDispatchEligibility<T>? eligibility,
    NavBackgroundDispatchObserver? observer,
    NavBackgroundDispatchErrorObserver? onError,
    Duration? timeout,
  })  : _runner = runner,
        _eligibility = eligibility,
        _observer = observer,
        _onError = onError,
        _timeout = timeout;

  final NavBackgroundDispatchRunner<T> _runner;
  final NavBackgroundDispatchEligibility<T>? _eligibility;
  final NavBackgroundDispatchObserver? _observer;
  final NavBackgroundDispatchErrorObserver? _onError;
  final Duration? _timeout;

  bool _inFlight = false;
  bool _disposed = false;
  bool _hasPending = false;
  T? _pending;

  bool get inFlight => _inFlight;
  bool get hasPending => _hasPending;
  bool get disposed => _disposed;

  /// Enqueue a new input. If nothing is running, the runner starts on the
  /// next microtask. If a task is running, [input] replaces any older
  /// pending input.
  void enqueue(T input) {
    if (_disposed) {
      _emit(NavBackgroundDispatchEvent.rejectedDisposed);
      return;
    }
    final eligibility = _eligibility;
    if (eligibility != null && !eligibility(input)) {
      _emit(NavBackgroundDispatchEvent.rejectedIneligible);
      return;
    }
    if (_inFlight) {
      final wasPending = _hasPending;
      _pending = input;
      _hasPending = true;
      _emit(
        wasPending
            ? NavBackgroundDispatchEvent.replacedPending
            : NavBackgroundDispatchEvent.enqueuedPending,
      );
      return;
    }
    _pending = input;
    _hasPending = true;
    _emit(NavBackgroundDispatchEvent.enqueuedStart);
    scheduleMicrotask(_pump);
  }

  Future<void> _pump() async {
    if (_disposed) return;
    if (_inFlight) return;
    if (!_hasPending) return;
    final input = _pending as T;
    _pending = null;
    _hasPending = false;
    _inFlight = true;
    _emit(NavBackgroundDispatchEvent.started);
    try {
      final future = _runner(input);
      if (_timeout != null) {
        await future.timeout(_timeout);
      } else {
        await future;
      }
      _emit(NavBackgroundDispatchEvent.completed);
    } on TimeoutException catch (error, stack) {
      _emit(NavBackgroundDispatchEvent.timedOut);
      _reportError(error, stack);
    } catch (error, stack) {
      _emit(NavBackgroundDispatchEvent.failed);
      _reportError(error, stack);
    } finally {
      _inFlight = false;
      if (!_disposed && _hasPending) {
        scheduleMicrotask(_pump);
      }
    }
  }

  /// Dispose the dispatcher: no further enqueues are accepted, the pending
  /// input is dropped. Any task that is already in flight completes / fails
  /// as usual but its side effects are the caller's responsibility to
  /// guard (e.g. `if (!mounted) return`).
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _pending = null;
    _hasPending = false;
    _emit(NavBackgroundDispatchEvent.disposed);
  }

  void _emit(NavBackgroundDispatchEvent event) {
    final observer = _observer;
    if (observer == null) return;
    try {
      observer(event);
    } catch (_) {
      // Observer failures are never allowed to break the dispatcher.
    }
  }

  void _reportError(Object error, StackTrace stackTrace) {
    final onError = _onError;
    if (onError == null) return;
    try {
      onError(error, stackTrace);
    } catch (_) {
      // Observer failures are never allowed to break the dispatcher.
    }
  }
}
