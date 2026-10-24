import 'package:maplibre_gl/maplibre_gl.dart' as ml;

/// Serializes global native offline state across overlapping preview lifetimes.
/// A popped screen cannot reconnect a newer preview while its arm is pending.
class MapLibreOfflinePreviewLease {
  MapLibreOfflinePreviewLease({required this.setOffline});
  static final shared = MapLibreOfflinePreviewLease(
    setOffline: (value) async {
      await ml.setOffline(value);
    },
  );
  final Future<void> Function(bool) setOffline;
  final Set<Object> _owners = {};
  Future<void> _tail = Future<void>.value();

  Future<void> _run(Future<void> Function() action) {
    final task = _tail.then((_) => action());
    _tail = task.catchError((Object _) {});
    return task;
  }

  Future<void> acquire(Object owner) => _run(() async {
    if (_owners.contains(owner)) return;
    if (_owners.isEmpty) await setOffline(true);
    _owners.add(owner);
  });

  Future<void> release(Object owner) => _run(() async {
    if (!_owners.contains(owner)) return;
    // Retain ownership if reconnection fails, so a later release can retry.
    if (_owners.length == 1) await setOffline(false);
    _owners.remove(owner);
  });
}
