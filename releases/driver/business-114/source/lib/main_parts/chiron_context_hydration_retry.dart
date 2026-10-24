/* CHIRON-RELEASE-PRESENTATION-REPAIR-1 A:
 * Deterministic first-load coordinator for Chiron surfaces.
 *
 * Waits for company-session auth + company id (profile or session), listens
 * for later hydration, coalesces to one latest-wins load, and ignores stale
 * completions after dispose. No sleeps / fixed delays.
 */

import 'package:flutter/foundation.dart';

/// Sanitized diagnostic stage names (never include tokens / company ids).
abstract final class ChironLoadDiag {
  static const waitingForSession = 'waiting_for_session';
  static const waitingForCompanyProfile = 'waiting_for_company_profile';
  static const prerequisitesReady = 'prerequisites_ready';
  static const initialLoadStarted = 'initial_load_started';
  static const initialLoadCompleted = 'initial_load_completed';
  static const initialLoadFailed = 'initial_load_failed';
  static const loadCoalesced = 'load_coalesced';
  static const staleCompletionIgnored = 'stale_completion_ignored';
}

typedef ChironLoadDiagSink = void Function(String stage);

/// Pure, testable load coordinator.
///
/// Prerequisites:
/// - [hasCompanySession] must be true (company-owner bearer available);
/// - [companyId] must be non-empty (from profile and/or session).
class ChironContextLoadCoordinator {
  ChironContextLoadCoordinator({
    required this.listenables,
    required this.hasCompanySession,
    required this.companyId,
    required this.runLoad,
    this.onDiag,
  });

  final List<Listenable> listenables;
  final bool Function() hasCompanySession;
  final String Function() companyId;
  final Future<void> Function(int generation) runLoad;
  final ChironLoadDiagSink? onDiag;

  bool _attached = false;
  bool _disposed = false;
  int _generation = 0;
  bool _loadInFlight = false;
  bool _pendingAfterInFlight = false;
  bool _initialCompleted = false;
  bool _sawReady = false;
  String _lastReadyKey = '';

  bool get isAttached => _attached;
  bool get isDisposed => _disposed;
  int get generation => _generation;
  bool get loadInFlight => _loadInFlight;
  @visibleForTesting
  bool get pendingAfterInFlight => _pendingAfterInFlight;

  bool get prerequisitesReady {
    if (!hasCompanySession()) return false;
    return companyId().trim().isNotEmpty;
  }

  String get _readyKey =>
      '${hasCompanySession() ? '1' : '0'}:${companyId().trim()}';

  void attach() {
    if (_attached || _disposed) return;
    for (final listenable in listenables) {
      listenable.addListener(_onContextChanged);
    }
    _attached = true;
    _evaluate();
  }

  void detach() {
    if (!_attached) return;
    for (final listenable in listenables) {
      listenable.removeListener(_onContextChanged);
    }
    _attached = false;
  }

  void dispose() {
    _disposed = true;
    detach();
  }

  /// Manual refresh: latest-wins; coalesces if a load is already in flight.
  void requestManualRefresh() {
    if (_disposed) return;
    if (!prerequisitesReady) {
      _emitWaiting();
      return;
    }
    _scheduleLoad();
  }

  @visibleForTesting
  void debugFireContextChanged() => _onContextChanged();

  void _onContextChanged() {
    if (_disposed) return;
    _evaluate();
  }

  void _evaluate() {
    if (_disposed) return;
    if (!prerequisitesReady) {
      _sawReady = false;
      _lastReadyKey = '';
      _emitWaiting();
      return;
    }
    final edge = !_sawReady;
    final key = _readyKey;
    final keyChanged = key != _lastReadyKey;
    _sawReady = true;
    _diag(ChironLoadDiag.prerequisitesReady);
    // Auto-load on the not-ready → ready edge, or on first attach if already ready.
    if (edge && !_initialCompleted) {
      _lastReadyKey = key;
      _scheduleLoad();
      return;
    }
    // Rapid prerequisite churn (e.g. company id updates) while a load is
    // in flight → coalesce one latest-wins follow-up; no overlapping start.
    if (_loadInFlight && keyChanged) {
      _lastReadyKey = key;
      _pendingAfterInFlight = true;
      _diag(ChironLoadDiag.loadCoalesced);
    }
  }

  void _emitWaiting() {
    if (!hasCompanySession()) {
      _diag(ChironLoadDiag.waitingForSession);
      return;
    }
    if (companyId().trim().isEmpty) {
      _diag(ChironLoadDiag.waitingForCompanyProfile);
    }
  }

  void _scheduleLoad() {
    if (_disposed) return;
    if (!prerequisitesReady) {
      _emitWaiting();
      return;
    }
    if (_loadInFlight) {
      _pendingAfterInFlight = true;
      _diag(ChironLoadDiag.loadCoalesced);
      return;
    }
    final gen = ++_generation;
    _loadInFlight = true;
    _pendingAfterInFlight = false;
    _diag(ChironLoadDiag.initialLoadStarted);
    // ignore: discarded_futures
    _runGeneration(gen);
  }

  Future<void> _runGeneration(int gen) async {
    var failed = false;
    try {
      await runLoad(gen);
    } catch (_) {
      failed = true;
    } finally {
      final stale = _disposed || gen != _generation;
      if (stale) {
        _diag(ChironLoadDiag.staleCompletionIgnored);
      } else {
        _initialCompleted = true;
        _diag(
          failed
              ? ChironLoadDiag.initialLoadFailed
              : ChironLoadDiag.initialLoadCompleted,
        );
      }
      if (gen == _generation) {
        _loadInFlight = false;
        if (!_disposed && _pendingAfterInFlight) {
          _pendingAfterInFlight = false;
          _scheduleLoad();
        }
      }
    }
  }

  /// Call from [runLoad] before applying UI results.
  bool shouldApplyGeneration(int gen) {
    if (_disposed || gen != _generation) {
      _diag(ChironLoadDiag.staleCompletionIgnored);
      return false;
    }
    return true;
  }

  void _diag(String stage) {
    onDiag?.call(stage);
  }
}
