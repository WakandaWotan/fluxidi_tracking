import 'dart:async';

/// Dashboard presentation only. No timer, polling or provider fallback.
/// At most one retry per retained key, after the existing route timeout (15s).
class DriverPreviewCache<T> {
  DriverPreviewCache({DateTime Function()? clock}) : clock = clock ?? DateTime.now;
  final DateTime Function() clock;
  final Map<Object, Future<T?>> _entries = {};
  final Map<Object, DateTime> _failedAt = {};
  final Map<Object, int> _attempts = {};
  Future<T?> load(Object key, Future<T?> Function() fetch) {
    final cached = _entries[key];
    final failed = _failedAt[key];
    if (cached != null && (failed == null || (_attempts[key] ?? 0) >= 2 ||
        clock().difference(failed) < const Duration(seconds: 15))) return cached;
    _failedAt.remove(key);
    _attempts[key] = (_attempts[key] ?? 0) + 1;
    final completer = Completer<T?>();
    final future = completer.future;
    _entries[key] = future;
    if (_entries.length > 16) {
      final oldest = _entries.keys.first;
      _entries.remove(oldest); _failedAt.remove(oldest); _attempts.remove(oldest);
    }
    Future<T?>.sync(fetch).then((value) {
      if (value == null && identical(_entries[key], future)) _failedAt[key] = clock();
      completer.complete(value);
    }, onError: (Object error, StackTrace stack) {
      if (identical(_entries[key], future)) _failedAt[key] = clock();
      completer.complete(null);
    });
    return future;
  }
  void clear() { _entries.clear(); _failedAt.clear(); _attempts.clear(); }
}
