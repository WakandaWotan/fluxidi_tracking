import 'dart:math' as math;
import 'dart:ui';

import 'package:fluxidi_tracking/maps/fluxidi_static_route_preview.dart';

const double kCustomerBookingMapMinZoom = 4;
const double kCustomerBookingMapMaxZoom = 16;
const double kCustomerBookingRouteWideBreakpoint = 900;

class CustomerBookingMapCamera {
  const CustomerBookingMapCamera({
    required this.center,
    required this.zoom,
  });

  final FluxidiMapLonLat center;
  final double zoom;

  CustomerBookingMapCamera copyWith({
    FluxidiMapLonLat? center,
    double? zoom,
  }) {
    return CustomerBookingMapCamera(
      center: center ?? this.center,
      zoom: zoom ?? this.zoom,
    );
  }
}

double customerBookingMercatorX(double lon) => (lon + 180.0) / 360.0;

double customerBookingMercatorY(double lat) {
  final clamped = lat.clamp(-85.05112878, 85.05112878);
  final rad = clamped * math.pi / 180.0;
  return (1 - math.log(math.tan(rad) + 1 / math.cos(rad)) / math.pi) / 2;
}

double customerBookingLonFromX(double x) => x * 360.0 - 180.0;

double customerBookingLatFromY(double y) {
  final n = math.pi - 2 * math.pi * y;
  return 180.0 / math.pi * math.atan((math.exp(n) - math.exp(-n)) / 2);
}

double customerBookingWorldSize(double zoom) => 256.0 * math.pow(2.0, zoom);

Offset customerBookingProject(
  FluxidiMapLonLat point,
  CustomerBookingMapCamera camera,
  Size size,
) {
  final scale = customerBookingWorldSize(camera.zoom);
  final dx =
      (customerBookingMercatorX(point.lon) -
          customerBookingMercatorX(camera.center.lon)) *
      scale;
  final dy =
      (customerBookingMercatorY(point.lat) -
          customerBookingMercatorY(camera.center.lat)) *
      scale;
  return Offset(size.width / 2 + dx, size.height / 2 + dy);
}

FluxidiMapLonLat customerBookingUnproject(
  Offset pixel,
  CustomerBookingMapCamera camera,
  Size size,
) {
  final scale = customerBookingWorldSize(camera.zoom);
  final x =
      customerBookingMercatorX(camera.center.lon) +
      (pixel.dx - size.width / 2) / scale;
  final y =
      customerBookingMercatorY(camera.center.lat) +
      (pixel.dy - size.height / 2) / scale;
  return FluxidiMapLonLat(customerBookingLonFromX(x), customerBookingLatFromY(y));
}

CustomerBookingMapCamera customerBookingPanCamera(
  CustomerBookingMapCamera camera,
  Offset delta,
) {
  final scale = customerBookingWorldSize(camera.zoom);
  final x = customerBookingMercatorX(camera.center.lon) - delta.dx / scale;
  final y = customerBookingMercatorY(camera.center.lat) - delta.dy / scale;
  return camera.copyWith(
    center: FluxidiMapLonLat(
      customerBookingLonFromX(x),
      customerBookingLatFromY(y),
    ),
  );
}

CustomerBookingMapCamera customerBookingZoomCamera({
  required CustomerBookingMapCamera camera,
  required Size size,
  required Offset focal,
  required double nextZoom,
}) {
  final zoom = nextZoom.clamp(
    kCustomerBookingMapMinZoom,
    kCustomerBookingMapMaxZoom,
  );
  if (zoom == camera.zoom) return camera;
  final held = customerBookingUnproject(focal, camera, size);
  final zoomed = camera.copyWith(zoom: zoom);
  final projected = customerBookingProject(held, zoomed, size);
  return customerBookingPanCamera(zoomed, focal - projected);
}

double _zoomForSpan(double span01, double pixels, double padding) {
  if (!span01.isFinite || span01 <= 1e-12) return 13.5;
  final usable = math.max(80.0, pixels - 2 * padding);
  final zoom = math.log(usable / (span01 * 256.0)) / math.ln2;
  return zoom.clamp(kCustomerBookingMapMinZoom, kCustomerBookingMapMaxZoom);
}

CustomerBookingMapCamera customerBookingFitCamera({
  required List<FluxidiMapLonLat> points,
  required Size size,
  double padding = 64,
}) {
  if (points.isEmpty || size.width <= 0 || size.height <= 0) {
    return const CustomerBookingMapCamera(
      center: FluxidiMapLonLat(4.35, 50.85),
      zoom: 8,
    );
  }
  var minX = 1.0;
  var maxX = 0.0;
  var minY = 1.0;
  var maxY = 0.0;
  for (final point in points) {
    final x = customerBookingMercatorX(point.lon);
    final y = customerBookingMercatorY(point.lat);
    minX = math.min(minX, x);
    maxX = math.max(maxX, x);
    minY = math.min(minY, y);
    maxY = math.max(maxY, y);
  }
  final zoom = math.min(
    _zoomForSpan(maxX - minX, size.width, padding),
    _zoomForSpan(maxY - minY, size.height, padding),
  );
  return CustomerBookingMapCamera(
    center: FluxidiMapLonLat(
      customerBookingLonFromX((minX + maxX) / 2),
      customerBookingLatFromY((minY + maxY) / 2),
    ),
    zoom: zoom,
  );
}

List<Offset> customerBookingRoutePrefix(List<Offset> points, double t) {
  if (points.length < 2) return points;
  final progress = t.clamp(0.0, 1.0);
  if (progress <= 0) return <Offset>[points.first];
  if (progress >= 1) return points;
  final distances = <double>[0];
  var total = 0.0;
  for (var i = 1; i < points.length; i++) {
    total += (points[i] - points[i - 1]).distance;
    distances.add(total);
  }
  if (total <= 0) return <Offset>[points.first, points.last];
  final target = total * progress;
  final out = <Offset>[points.first];
  for (var i = 1; i < points.length; i++) {
    if (distances[i] < target) {
      out.add(points[i]);
      continue;
    }
    final span = distances[i] - distances[i - 1];
    final f = span <= 0 ? 1.0 : ((target - distances[i - 1]) / span);
    out.add(Offset.lerp(points[i - 1], points[i], f.clamp(0.0, 1.0))!);
    break;
  }
  return out;
}

String customerBookingRouteFingerprint({
  required FluxidiMapLonLat? pickup,
  required FluxidiMapLonLat? dropoff,
  List<FluxidiMapLonLat> stops = const <FluxidiMapLonLat>[],
}) {
  String coord(FluxidiMapLonLat? value) {
    if (value == null) return '';
    return '${value.lon.toStringAsFixed(5)},${value.lat.toStringAsFixed(5)}';
  }

  return <String>[
    coord(pickup),
    for (final stop in stops) coord(stop),
    coord(dropoff),
  ].join('|');
}

FluxidiMapLonLat? customerBookingLonLat(double? lat, double? lon) {
  if (lat == null || lon == null || !lat.isFinite || !lon.isFinite) {
    return null;
  }
  if (lat.abs() > 90 || lon.abs() > 180) return null;
  return FluxidiMapLonLat(lon, lat);
}
