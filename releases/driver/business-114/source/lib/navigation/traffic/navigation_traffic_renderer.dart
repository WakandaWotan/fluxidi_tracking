import 'navigation_traffic_controller.dart';
import '../nav_engine/nav_polyline_annotation_delete.dart';

/// The existing safe delete helper returns failures instead of throwing.
/// Preserve that result at the renderer boundary so its handle can be retried.
void ensureNavigationTrafficDeletion(NavPolylineDeleteResult result) {
  if (result.outcome == NavPolylineDeleteOutcome.unexpectedFailure) {
    throw StateError('traffic_delete_unavailable');
  }
}

class _RenderedTraffic<T> {
  _RenderedTraffic(this.handle, this.span);
  final T handle;
  NavigationTrafficSpan span;
}

/// Latest-wins serialized renderer. The host supplies its existing annotation
/// transaction/manager lease, so this class cannot cross a removed manager.
class NavigationTrafficRenderer<T> {
  final Map<String, _RenderedTraffic<T>> _rendered = {};
  Future<void> _tail = Future.value();
  int _managerGeneration = 0, _request = 0;
  bool get hasHandles => _rendered.isNotEmpty;
  int get handleCount => _rendered.length;
  void forgetManager() {
    _managerGeneration++;
    _request++;
    _rendered.clear();
  }

  Future<void> sync({
    required List<NavigationTrafficSpan> spans,
    required bool Function() isCurrent,
    required Future<T> Function(NavigationTrafficSpan) create,
    required Future<void> Function(T, NavigationTrafficSpan) update,
    required Future<void> Function(T) delete,
    bool recreate = false,
  }) {
    final managerGeneration = _managerGeneration, request = ++_request;
    bool current() =>
        managerGeneration == _managerGeneration &&
        request == _request &&
        isCurrent();
    final next = _tail.then((_) async {
      if (!current()) return;
      final wanted = {for (final span in spans) span.id: span};
      // Remove passed, expired, replaced and no-longer-bound evidence first.
      for (final id in _rendered.keys.toList()) {
        if (!current()) return;
        if (recreate || !wanted.containsKey(id)) {
          final old = _rendered[id]!;
          await delete(old.handle);
          if (identical(_rendered[id], old)) _rendered.remove(id);
        }
      }
      for (final span in spans) {
        if (!current()) return;
        final old = _rendered[span.id];
        if (old == null) {
          final handle = await create(span);
          if (!current()) {
            final stale = _RenderedTraffic(handle, span);
            if (managerGeneration == _managerGeneration) {
              _rendered[span.id] = stale;
            }
            await delete(handle);
            if (identical(_rendered[span.id], stale)) _rendered.remove(span.id);
            return;
          }
          _rendered[span.id] = _RenderedTraffic(handle, span);
        } else if (old.span.geometryKey != span.geometryKey ||
            old.span.color != span.color) {
          await update(old.handle, span);
          // Native side effects have happened even when a newer request arrived.
          // Keep the cache accurate so that request can restore its own geometry.
          if (managerGeneration == _managerGeneration &&
              identical(_rendered[span.id], old))
            old.span = span;
          if (!current()) return;
        }
      }
    });
    _tail = next.catchError((Object _) {});
    return next;
  }
}
