import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'fluxidi_maplibre_preview_style.dart';

/// A renderer for existing point/radius data. It performs no routing or lookup.
class FluxidiMapLibrePointsMap extends StatefulWidget {
  const FluxidiMapLibrePointsMap({
    super.key,
    required this.points,
    required this.center,
    required this.zoom,
    required this.dark,
    this.ring = const [],
    this.lineColor = '#E5B641',
    this.onTap,
  });
  final Map<String, LatLng> points;
  final LatLng center;
  final double zoom;
  final bool dark;
  final List<LatLng> ring;
  final String lineColor;
  final ValueChanged<String>? onTap;
  @override
  State<FluxidiMapLibrePointsMap> createState() => _PointsMapState();
}

class _PointsMapState extends State<FluxidiMapLibrePointsMap> {
  MapLibreMapController? _map;
  String? _style;
  bool _failed = false, _ready = false, _busy = false, _pending = false;
  int _styleEpoch = 0, _dataEpoch = 0;
  final Map<String, String> _ids = {};
  @override
  void initState() {
    super.initState();
    unawaited(_loadStyle());
  }

  Future<void> _loadStyle() async {
    final epoch = ++_styleEpoch;
    _ready = false;
    _ids.clear();
    try {
      final style = await customerBookingBasemapStyle(widget.dark);
      if (!mounted || epoch != _styleEpoch) return;
      setState(() {
        _style = style;
        _failed = false;
      });
    } catch (_) {
      if (mounted && epoch == _styleEpoch) setState(() => _failed = true);
    }
  }

  @override
  void didUpdateWidget(FluxidiMapLibrePointsMap old) {
    super.didUpdateWidget(old);
    if (old.dark != widget.dark) {
      unawaited(_loadStyle());
    }
    if (!mapEquals(old.points, widget.points) ||
        !listEquals(old.ring, widget.ring) ||
        old.center != widget.center ||
        old.zoom != widget.zoom ||
        old.lineColor != widget.lineColor) {
      _dataEpoch++;
      unawaited(_render());
    }
  }

  void _tap(Circle circle) {
    final id = _ids[circle.id];
    if (mounted && _ready && id != null && widget.points.containsKey(id)) {
      widget.onTap?.call(id);
    }
  }

  Future<void> _render() async {
    _pending = true;
    if (!_ready || _busy || !mounted) return;
    _busy = true;
    var attemptedDataEpoch = _dataEpoch, attemptedStyleEpoch = _styleEpoch;
    try {
      while (_pending && mounted && _ready) {
        _pending = false;
        final epoch = _dataEpoch, styleEpoch = _styleEpoch, map = _map!;
        attemptedDataEpoch = epoch;
        attemptedStyleEpoch = styleEpoch;
        final points = Map<String, LatLng>.of(widget.points);
        final ring = List<LatLng>.of(widget.ring);
        bool current() =>
            mounted &&
            _ready &&
            epoch == _dataEpoch &&
            styleEpoch == _styleEpoch &&
            identical(map, _map);
        _ids.clear();
        await map.clearCircles();
        if (!current()) continue;
        await map.clearLines();
        if (!current()) continue;
        final entries = points.entries.toList();
        final circles = await map.addCircles([
          for (final point in entries)
            CircleOptions(
              geometry: point.value,
              circleColor: '#E5B641',
              circleRadius: 10.5,
              circleStrokeColor: '#FFFFFF',
              circleStrokeWidth: 2.5,
            ),
        ]);
        if (!current()) continue;
        for (var i = 0; i < circles.length; i++) {
          _ids[circles[i].id] = entries[i].key;
        }
        if (ring.length >= 2) {
          await map.addLine(
            LineOptions(
              geometry: ring,
              lineColor: widget.lineColor,
              lineWidth: 2.2,
              lineOpacity: .82,
            ),
          );
          if (!current()) continue;
        }
        await map.animateCamera(
          CameraUpdate.newLatLngZoom(widget.center, widget.zoom),
          duration: const Duration(milliseconds: 450),
        );
      }
    } catch (_) {
      if (mounted && attemptedDataEpoch == _dataEpoch && attemptedStyleEpoch == _styleEpoch) {
        _ready = false;
        setState(() => _failed = true);
      }
    } finally {
      _busy = false;
      if (_pending && _ready && mounted) unawaited(_render());
    }
  }

  @override
  void dispose() {
    _ready = false;
    _styleEpoch++;
    _dataEpoch++;
    _map?.onCircleTapped.remove(_tap);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_failed)
      return const Center(child: Text('Kaart tijdelijk niet beschikbaar'));
    if (_style == null) return const SizedBox.expand();
    return MapLibreMap(
      styleString: _style!,
      initialCameraPosition: CameraPosition(
        target: widget.center,
        zoom: widget.zoom,
      ),
      myLocationEnabled: false,
      onMapCreated: (map) {
        _map = map;
        map.onCircleTapped.add(_tap);
      },
      onStyleLoadedCallback: () {
        _ready = true;
        unawaited(_render());
      },
    );
  }
}
