import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import '../driver_navigation_models.dart';
import '../driver_navigation_geometry.dart';
import 'navigation_traffic_model.dart';

class NavigationTrafficAlert {
  const NavigationTrafficAlert({
    required this.event,
    required this.traffic,
    required this.distanceMeters,
    this.delaySeconds,
  });
  final NavigationTrafficEvent event;
  final NavigationTrafficClass traffic;
  final double distanceMeters;
  final double? delaySeconds;
  String get displayKey =>
      '${event.name}:${traffic.name}:${(distanceMeters / 100).floor()}:${delaySeconds?.round()}';
}

class NavigationTrafficSpan {
  const NavigationTrafficSpan({
    required this.id,
    required this.coordinates,
    required this.traffic,
    required this.geometryKey,
  });
  final String id, geometryKey;
  final List<DriverLonLat> coordinates;
  final NavigationTrafficClass traffic;
  int get color => navigationTrafficColor(traffic);
}

/// Owns presentation only. No routing/ETA/network/GPS timers or permission logic.
class NavigationTrafficController {
  final alert = ValueNotifier<NavigationTrafficAlert?>(null);
  NavigationTrafficSnapshot _snapshot =
      const NavigationTrafficSnapshot.unavailable();
  List<DriverLonLat> _geometry = const [];
  List<double> _along = const [];
  final Map<NavigationTrafficSegment, NavigationTrafficSpan> _fullSpans = {};
  double _progress = 0;
  double _progressOriginMeters = 0;
  bool _progressTrusted = false;
  int generation = 0;
  NavigationTrafficSourceState stateAt(DateTime now) => _snapshot.stateAt(now);
  bool get hasEvidence => _snapshot.segments.isNotEmpty;
  double get progressMeters => _progress;

  void install({
    required List<DriverLonLat> geometry,
    required NavigationTrafficSnapshot snapshot,
    required DateTime now,
    double progressOriginMeters = 0,
  }) {
    generation++;
    _snapshot = snapshot;
    _geometry = const [];
    _along = const [];
    _fullSpans.clear();
    _progress = 0;
    _progressOriginMeters = 0;
    _progressTrusted = false;
    if (snapshot.stateAt(now) == NavigationTrafficSourceState.available) {
      if (!progressOriginMeters.isFinite ||
          progressOriginMeters < 0 ||
          geometry.length < 2 ||
          snapshot.geometryFingerprint !=
              navigationTrafficGeometryFingerprint(geometry)) {
        _snapshot = const NavigationTrafficSnapshot(
          state: NavigationTrafficSourceState.unbound,
        );
      } else {
        _geometry = List.unmodifiable(geometry);
        final along = <double>[0];
        for (var i = 1; i < geometry.length; i++) {
          along.add(
            along.last + driverMetersBetween(geometry[i - 1], geometry[i]),
          );
        }
        _along = List.unmodifiable(along);
        // Existing reroute acceptance trims the displayed route and restarts
        // progress at zero. Keep its authoritative offset in the bound route.
        _progressOriginMeters = progressOriginMeters.clamp(0.0, _along.last);
        _progress = _progressOriginMeters;
        for (final segment in snapshot.segments) {
          _fullSpans[segment] = NavigationTrafficSpan(
            id: '${segment.start}:${segment.end}',
            coordinates: List.unmodifiable(
              geometry.sublist(segment.start, segment.end + 1),
            ),
            traffic: segment.traffic,
            geometryKey: '$generation:${segment.start}:${segment.end}:full',
          );
        }
      }
    }
    _refreshAlert(now);
  }

  void clear() => install(
    geometry: const [],
    snapshot: const NavigationTrafficSnapshot.unavailable(),
    now: DateTime.now(),
  );
  void dispose() {
    alert.dispose();
  }

  void updateProgress(
    double? progressMeters, {
    required bool trusted,
    required DateTime now,
  }) {
    _progressTrusted =
        trusted &&
        progressMeters != null &&
        progressMeters.isFinite &&
        progressMeters >= 0;
    // Retain the last trustworthy passed distance on a GPS gap; do not revive old segments.
    if (_progressTrusted && _along.isNotEmpty) {
      _progress = math
          .max(_progress, _progressOriginMeters + progressMeters!)
          .clamp(0.0, _along.last);
    }
    if (hasEvidence) _refreshAlert(now);
  }

  void expire(DateTime now) {
    _refreshAlert(now);
  }

  DateTime? nextExpiry(DateTime now) {
    if (_snapshot.stateAt(now) != NavigationTrafficSourceState.available)
      return null;
    DateTime? earliest = _snapshot.expiresAt;
    for (final segment in _snapshot.segments) {
      if (segment.isFresh(now) &&
          (earliest == null || segment.expiresAt.isBefore(earliest)))
        earliest = segment.expiresAt;
    }
    return earliest != null && earliest.isAfter(now) ? earliest : null;
  }

  int _indexAt(double distance) {
    var low = 0, high = _along.length - 1;
    while (low < high) {
      final mid = (low + high + 1) ~/ 2;
      if (_along[mid] <= distance) {
        low = mid;
      } else {
        high = mid - 1;
      }
    }
    return low.clamp(0, _geometry.length - 2);
  }

  List<NavigationTrafficSpan> spansAt(DateTime now) {
    if (_snapshot.stateAt(now) != NavigationTrafficSourceState.available ||
        _along.isEmpty)
      return const [];
    final spans = <NavigationTrafficSpan>[];
    for (final segment in _snapshot.segments) {
      if (!segment.isFresh(now) ||
          segment.confidence < navigationTrafficVisualConfidence ||
          _progress >= _along[segment.end] ||
          _along[segment.end] <= _along[segment.start])
        continue;
      final full = _fullSpans[segment]!;
      if (_progress <= _along[segment.start]) {
        spans.add(full);
        continue;
      }
      final index = _indexAt(_progress).clamp(segment.start, segment.end - 1);
      final distance = _along[index + 1] - _along[index];
      final t = distance > 0
          ? ((_progress - _along[index]) / distance).clamp(0.0, 1.0)
          : 1.0;
      final a = _geometry[index], b = _geometry[index + 1];
      spans.add(
        NavigationTrafficSpan(
          id: full.id,
          traffic: full.traffic,
          geometryKey:
              '$generation:$index:${t.toStringAsFixed(6)}:${segment.end}',
          coordinates: List.unmodifiable([
            DriverLonLat(
              a.lon + (b.lon - a.lon) * t,
              a.lat + (b.lat - a.lat) * t,
            ),
            ..._geometry.sublist(index + 1, segment.end + 1),
          ]),
        ),
      );
    }
    return spans;
  }

  void _refreshAlert(DateTime now) {
    NavigationTrafficSegment? best;
    if (_progressTrusted &&
        _snapshot.stateAt(now) == NavigationTrafficSourceState.available) {
      int priority(NavigationTrafficSegment s) => switch (s.event) {
        NavigationTrafficEvent.closure => 0,
        NavigationTrafficEvent.incident ||
        NavigationTrafficEvent.roadworks => 1,
        NavigationTrafficEvent.congestion =>
          s.traffic == NavigationTrafficClass.heavy ||
                  s.traffic == NavigationTrafficClass.severe
              ? 2
              : 3,
      };
      for (final segment in _snapshot.segments) {
        if (!segment.isFresh(now) ||
            segment.confidence < navigationTrafficAlertConfidence ||
            _progress >= _along[segment.end] ||
            segment.event == NavigationTrafficEvent.congestion &&
                segment.traffic == NavigationTrafficClass.normal ||
            _along[segment.start] - _progress > 10000)
          continue;
        if (best == null ||
            priority(segment) < priority(best) ||
            priority(segment) == priority(best) && segment.start < best.start)
          best = segment;
      }
    }
    final next = best == null
        ? null
        : NavigationTrafficAlert(
            event: best.event,
            traffic: best.traffic,
            distanceMeters: math.max(0, _along[best.start] - _progress),
            // A whole-segment delay is not a remaining ETA. Once inside the
            // segment, omit it instead of creating a second ETA engine.
            delaySeconds: _progress <= _along[best.start]
                ? best.delaySeconds
                : null,
          );
    if (alert.value?.displayKey != next?.displayKey) alert.value = next;
  }
}
