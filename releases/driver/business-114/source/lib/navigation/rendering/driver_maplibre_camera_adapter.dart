import 'dart:math' as math;
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as legacy;
import 'package:maplibre_gl/maplibre_gl.dart' as libre;

/// Renderer boundary only. Caller retains pose, follow ownership, smoothing,
/// viewport generation, cadence, route generation and animation decisions.
/// Legacy objects below are data transfer objects, never native map handles.
class DriverMapLibreCameraAdapter {
  DriverMapLibreCameraAdapter(this.controller, {required this.devicePixelRatio});
  final libre.MapLibreMapController controller;
  final double Function() devicePixelRatio;
  bool _paddingInitialized = false;
  legacy.MbxEdgeInsets _padding =
      legacy.MbxEdgeInsets(top: 0, left: 0, bottom: 0, right: 0);

  static libre.LatLng point(legacy.Point value) => libre.LatLng(
      value.coordinates.lat.toDouble(), value.coordinates.lng.toDouble());

  Future<void> _applyPadding(legacy.MbxEdgeInsets? padding) async {
    if (padding == null) return;
    if (_paddingInitialized && padding.top == _padding.top &&
        padding.bottom == _padding.bottom && padding.left == _padding.left &&
        padding.right == _padding.right) return;
    await controller.setPadding(top: padding.top, bottom: padding.bottom,
        left: padding.left, right: padding.right);
    _padding = padding;
    _paddingInitialized = true;
  }

  libre.CameraPosition _position(legacy.CameraOptions options) {
    final previous = controller.cameraPosition;
    if (previous == null && options.center == null) {
      throw StateError('Camera has no authoritative centre');
    }
    return libre.CameraPosition(
      target: options.center == null ? previous!.target : point(options.center!),
      zoom: options.zoom ?? previous?.zoom ?? 0,
      bearing: options.bearing ?? previous?.bearing ?? 0,
      tilt: options.pitch ?? previous?.tilt ?? 0,
    );
  }

  Future<void> setCamera(legacy.CameraOptions options) async {
    await _applyPadding(options.padding);
    await controller.moveCamera(libre.CameraUpdate.newCameraPosition(_position(options)));
  }

  Future<void> flyTo(legacy.CameraOptions options,
      legacy.MapAnimationOptions? animation) async {
    await _applyPadding(options.padding);
    await controller.animateCamera(
        libre.CameraUpdate.newCameraPosition(_position(options)),
        duration: Duration(milliseconds: animation?.duration ?? 0));
  }

  Future<legacy.CameraState> getCameraState() async {
    final camera = controller.cameraPosition;
    if (camera == null) throw StateError('Native camera state unavailable');
    return legacy.CameraState(
      center: legacy.Point(coordinates:
          legacy.Position(camera.target.longitude, camera.target.latitude)),
      padding: _padding, zoom: camera.zoom,
      bearing: camera.bearing, pitch: camera.tilt,
    );
  }

  /// Mapbox's Android CameraController returns logical pixels through
  /// toFLTScreenCoordinate(context). MapLibre's projection channel returns
  /// physical pixels. Preserve the existing caller's logical-pixel contract.
  Future<legacy.ScreenCoordinate> pixelForCoordinate(legacy.Point value) async {
    final screen = await controller.toScreenLocation(point(value));
    final ratio = devicePixelRatio();
    return legacy.ScreenCoordinate(x: screen.x / ratio, y: screen.y / ratio);
  }

  Future<legacy.Point> coordinateForPixel(legacy.ScreenCoordinate value) async {
    final coordinate = await controller.toLatLng(
        math.Point<double>(value.x * devicePixelRatio(), value.y * devicePixelRatio()));
    return legacy.Point(coordinates:
        legacy.Position(coordinate.longitude, coordinate.latitude));
  }
}
