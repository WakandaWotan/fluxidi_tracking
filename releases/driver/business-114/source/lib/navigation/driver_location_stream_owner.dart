import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:geolocator/geolocator.dart' as geo;

/// Owns the existing GPS subscription. No second location source or upload timer.
class DriverLocationStreamOwner with WidgetsBindingObserver {
  DriverLocationStreamOwner({
    required this.openStream,
    required this.permissionReady,
    required this.foregroundConfirmed,
    required this.operationValid,
    required this.onPosition,
    DateTime Function()? now,
    this.android = true,
    this.retryDelay = const Duration(seconds: 2),
    this.observeLifecycle = true,
  }) : now = now ?? DateTime.now {
    if (observeLifecycle) {
      _visible =
          WidgetsBinding.instance.lifecycleState == null ||
          WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
      WidgetsBinding.instance.addObserver(this);
    }
  }
  final Stream<geo.Position> Function(bool foreground) openStream;
  final Future<bool> Function() permissionReady;
  final Future<bool> Function() foregroundConfirmed;
  final bool Function() operationValid;
  final void Function(geo.Position) onPosition;
  final DateTime Function() now;
  final bool android, observeLifecycle;
  final Duration retryDelay;
  StreamSubscription<geo.Position>? subscription;
  Future<void> _serial = Future.value();
  Timer? _retry;
  bool _foreground = false, _wanted = false, _disposed = false;
  bool _visible = true;
  int _generation = 0, _intentGeneration = 0, _retries = 0;
  DateTime? _lastSample, _openedAt;
  bool get foreground => _foreground && subscription != null;
  bool get uploadingAllowed =>
      !_disposed &&
      _wanted &&
      subscription != null &&
      (!_foreground || operationValid());

  Future<T> _queue<T>(Future<T> Function() work) {
    final result = _serial.then((_) => work());
    _serial = result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

  /// Calls are serialized, including plugin cancellation, so promotion cannot
  /// leave the preview subscription alive beside the foreground subscription.
  Future<bool> ensure({required bool foreground}) {
    if (_disposed) return Future.value(false);
    _wanted = true;
    final generation = _intentGeneration;
    return _queue(() async {
      if (!_wanted || _disposed || generation != _intentGeneration)
        return false;
      if (foreground && !operationValid()) {
        await _cancel();
        return false;
      }
      bool allowed;
      try {
        allowed = await permissionReady();
      } catch (_) {
        allowed = false;
      }
      if (!allowed || !_wanted || generation != _intentGeneration) {
        await _cancel();
        return false;
      }
      final age = now().difference(_lastSample ?? _openedAt ?? now());
      if (subscription != null &&
          _foreground == foreground &&
          age < const Duration(seconds: 30)) {
        if (!foreground || !android) return true;
        try {
          if (await foregroundConfirmed()) return true;
        } catch (_) {
          /* Recreate only while visible. */
        }
      }
      // Android 14 while-in-use restriction: never create a location FGS from
      // a cold/background callback. The next visible resume can recover it.
      if (foreground && !_visible) return false;
      await _cancel();
      if (!_wanted ||
          generation != _intentGeneration ||
          (foreground && !operationValid()))
        return false;
      _foreground = foreground;
      _openedAt = now();
      _lastSample = null;
      final streamGeneration = ++_generation;
      try {
        subscription = openStream(foreground).listen(
          (position) {
            if (streamGeneration != _generation || !_wanted || _disposed)
              return;
            if (_foreground && !operationValid()) {
              unawaited(stop());
              return;
            }
            if (now().difference(position.timestamp) >
                const Duration(seconds: 30))
              return;
            _lastSample = now();
            onPosition(position);
          },
          onError: (Object _) => _failed(streamGeneration),
          onDone: () => _failed(streamGeneration),
        );
        if (foreground && android) {
          for (var attempt = 0; attempt < 30; attempt++) {
            if (!_wanted ||
                streamGeneration != _generation ||
                !operationValid()) {
              await _cancel();
              return false;
            }
            if (await foregroundConfirmed()) return true;
            await Future<void>.delayed(const Duration(milliseconds: 100));
          }
          await _cancel();
          return false;
        }
        return true;
      } catch (_) {
        await _cancel();
        return false;
      }
    });
  }

  void _failed(int generation) {
    if (generation != _generation || _disposed) return;
    final intent = _intentGeneration;
    _generation++;
    unawaited(
      _queue(() async {
        if (intent != _intentGeneration) return;
        await _cancel();
        if (!_wanted || !_visible || !operationValid() || _retries >= 3) return;
        _scheduleRecovery(intent);
      }),
    );
  }

  void _scheduleRecovery(int intent) {
    if (intent != _intentGeneration ||
        !_wanted ||
        _disposed ||
        !_visible ||
        !operationValid() ||
        _retries >= 3)
      return;
    _retries++;
    _retry?.cancel();
    _retry = Timer(retryDelay * _retries, () async {
      if (intent != _intentGeneration ||
          !_wanted ||
          _disposed ||
          !_visible ||
          !operationValid())
        return;
      if (!await ensure(foreground: true)) _scheduleRecovery(intent);
    });
  }

  Future<void> _cancel() async {
    final old = subscription;
    subscription = null;
    _foreground = false;
    _lastSample = null;
    await old?.cancel(); // plugin releases notification + partial wakelock
  }

  Future<void> stop() {
    _wanted = false;
    _intentGeneration++;
    _generation++;
    _retries = 0;
    _retry?.cancel();
    _retry = null;
    return _queue(_cancel);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _visible = state == AppLifecycleState.resumed;
    if (!_visible || !_wanted || _disposed) return;
    if (!operationValid()) {
      unawaited(stop());
      return;
    }
    unawaited(ensure(foreground: true));
  }

  Future<void> dispose() async {
    _disposed = true;
    if (observeLifecycle) WidgetsBinding.instance.removeObserver(this);
    await stop();
  }
}
