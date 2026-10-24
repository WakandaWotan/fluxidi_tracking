import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:fluxidi_customer_core/fluxidi_customer_core.dart';

import '../app/customer_app_config.dart';

/// Map camera and projection.
///
/// Ported from golden commit 9df7e7b92ecc86a11184ee995e255da7b8f6fb68:
/// `lib/customer_booking/customer_booking_route_camera.dart` —
/// `CustomerBookingMapCamera`, `customerBookingMercatorX/Y`,
/// `customerBookingProject`, `customerBookingPanCamera`,
/// `customerBookingFitCamera`, `_zoomForSpan`; and
/// `lib/customer_booking/customer_booking_route_map.dart` —
/// `_MapboxTileLayer`, `_CustomerBookingRoutePainter`.
///
/// Customer maps stay north-up, so no bearing is applied.
const double kCustomerMapMinZoom = 4;
const double kCustomerMapMaxZoom = 16;

@immutable
class CustomerMapCamera {
  const CustomerMapCamera({required this.center, required this.zoom});

  final FluxidiLonLat center;
  final double zoom;

  CustomerMapCamera copyWith({FluxidiLonLat? center, double? zoom}) =>
      CustomerMapCamera(center: center ?? this.center, zoom: zoom ?? this.zoom);
}

double customerMercatorX(double lon) => (lon + 180.0) / 360.0;

double customerMercatorY(double lat) {
  final clamped = lat.clamp(-85.05112878, 85.05112878);
  final rad = clamped * math.pi / 180.0;
  return (1 - math.log(math.tan(rad) + 1 / math.cos(rad)) / math.pi) / 2;
}

double customerLonFromX(double x) => x * 360.0 - 180.0;

double customerLatFromY(double y) {
  final n = math.pi - 2 * math.pi * y;
  return 180.0 / math.pi * math.atan((math.exp(n) - math.exp(-n)) / 2);
}

double customerWorldSize(double zoom) => 256.0 * math.pow(2.0, zoom);

Offset customerProject(
  FluxidiLonLat point,
  CustomerMapCamera camera,
  Size size,
) {
  final scale = customerWorldSize(camera.zoom);
  return Offset(
    size.width / 2 +
        (customerMercatorX(point.lon) - customerMercatorX(camera.center.lon)) *
            scale,
    size.height / 2 +
        (customerMercatorY(point.lat) - customerMercatorY(camera.center.lat)) *
            scale,
  );
}

CustomerMapCamera customerPanCamera(CustomerMapCamera camera, Offset delta) {
  final scale = customerWorldSize(camera.zoom);
  final x = customerMercatorX(camera.center.lon) - delta.dx / scale;
  final y = customerMercatorY(camera.center.lat) - delta.dy / scale;
  return camera.copyWith(
    center: FluxidiLonLat(customerLonFromX(x), customerLatFromY(y)),
  );
}

double _zoomForSpan(double span01, double pixels, double padding) {
  if (!span01.isFinite || span01 <= 1e-12) return 13.5;
  final usable = math.max(80.0, pixels - 2 * padding);
  final zoom = math.log(usable / (span01 * 256.0)) / math.ln2;
  return zoom.clamp(kCustomerMapMinZoom, kCustomerMapMaxZoom);
}

/// Camera that shows every point, keeping the route inside the visible area
/// that the draggable sheet leaves free.
CustomerMapCamera customerFitCamera({
  required List<FluxidiLonLat> points,
  required Size size,
  double padding = 48,
  EdgeInsets contentInsets = EdgeInsets.zero,
}) {
  final usable = Size(
    math.max(80.0, size.width - contentInsets.horizontal),
    math.max(80.0, size.height - contentInsets.vertical),
  );
  if (points.isEmpty) {
    return const CustomerMapCamera(
      center: FluxidiLonLat(4.35, 50.85),
      zoom: 8,
    );
  }
  var minX = 1.0;
  var maxX = 0.0;
  var minY = 1.0;
  var maxY = 0.0;
  for (final point in points) {
    final x = customerMercatorX(point.lon);
    final y = customerMercatorY(point.lat);
    minX = math.min(minX, x);
    maxX = math.max(maxX, x);
    minY = math.min(minY, y);
    maxY = math.max(maxY, y);
  }
  final center = FluxidiLonLat(
    customerLonFromX((minX + maxX) / 2),
    customerLatFromY((minY + maxY) / 2),
  );
  final zoom = math.min(
    _zoomForSpan(maxX - minX, usable.width, padding),
    _zoomForSpan(maxY - minY, usable.height, padding),
  );
  final fitted = CustomerMapCamera(center: center, zoom: zoom);

  var sum = Offset.zero;
  for (final point in points) {
    sum += customerProject(point, fitted, size);
  }
  final routeCenter = sum / points.length.toDouble();
  final holeCenter = Offset(
    contentInsets.left + usable.width / 2,
    contentInsets.top + usable.height / 2,
  );
  return customerPanCamera(fitted, holeCenter - routeCenter);
}

/// Mapbox raster tiles, the pickup and destination markers and the real route.
class CustomerRouteMap extends StatelessWidget {
  const CustomerRouteMap({
    super.key,
    required this.token,
    required this.pickup,
    required this.dropoff,
    required this.route,
    required this.contentInsets,
    this.config = kCustomerAppConfig,
  });

  /// Mapbox access token. Empty means no tiles may be requested.
  final String token;

  final FluxidiLonLat? pickup;
  final FluxidiLonLat? dropoff;

  /// Real route line. Empty means no line is drawn; never a straight fallback.
  final List<FluxidiLonLat> route;

  /// Area covered by the sheet, so the route is fitted in what stays visible.
  final EdgeInsets contentInsets;

  final CustomerAppConfig config;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        final points = <FluxidiLonLat>[
          ...route,
          if (route.isEmpty && pickup != null) pickup!,
          if (route.isEmpty && dropoff != null) dropoff!,
        ];
        final camera = customerFitCamera(
          points: points,
          size: size,
          contentInsets: contentInsets,
        );
        return Stack(
          fit: StackFit.expand,
          children: <Widget>[
            _MapboxTileLayer(camera: camera, size: size, token: token),
            CustomPaint(
              painter: _CustomerRoutePainter(
                camera: camera,
                pickup: pickup,
                dropoff: dropoff,
                route: route,
                line: config.brand.primary,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _MapboxTileLayer extends StatelessWidget {
  const _MapboxTileLayer({
    required this.camera,
    required this.size,
    required this.token,
  });

  final CustomerMapCamera camera;
  final Size size;
  final String token;

  @override
  Widget build(BuildContext context) {
    if (token.trim().isEmpty || size.width <= 0 || size.height <= 0) {
      return const SizedBox.expand();
    }
    final z = camera.zoom.floor().clamp(1, 16);
    final n = 1 << z;
    final scale = customerWorldSize(camera.zoom);
    final tileSize = scale / n;
    final worldLeft =
        customerMercatorX(camera.center.lon) * scale - size.width / 2;
    final worldTop =
        customerMercatorY(camera.center.lat) * scale - size.height / 2;
    final minX = (worldLeft / tileSize).floor() - 1;
    final minY = (worldTop / tileSize).floor() - 1;
    final maxX = ((worldLeft + size.width) / tileSize).ceil() + 1;
    final maxY = ((worldTop + size.height) / tileSize).ceil() + 1;

    final children = <Widget>[];
    for (var x = minX; x <= maxX; x++) {
      for (var y = minY; y <= maxY; y++) {
        if (y < 0 || y >= n) continue;
        final wrappedX = ((x % n) + n) % n;
        children.add(
          Positioned(
            key: ValueKey<String>('tile_${z}_${wrappedX}_$y'),
            left: x * tileSize - worldLeft,
            top: y * tileSize - worldTop,
            width: tileSize,
            height: tileSize,
            child: Image.network(
              'https://api.mapbox.com/styles/v1/mapbox/streets-v12/tiles/256/'
              '$z/$wrappedX/$y@2x?access_token=${token.trim()}',
              fit: BoxFit.cover,
              filterQuality: FilterQuality.medium,
              gaplessPlayback: true,
              errorBuilder: (_, __, ___) =>
                  const ColoredBox(color: Color(0xFFDCE6DC)),
            ),
          ),
        );
      }
    }
    return Stack(clipBehavior: Clip.hardEdge, children: children);
  }
}

class _CustomerRoutePainter extends CustomPainter {
  const _CustomerRoutePainter({
    required this.camera,
    required this.pickup,
    required this.dropoff,
    required this.route,
    required this.line,
  });

  final CustomerMapCamera camera;
  final FluxidiLonLat? pickup;
  final FluxidiLonLat? dropoff;
  final List<FluxidiLonLat> route;
  final Color line;

  @override
  void paint(Canvas canvas, Size size) {
    if (route.length >= 2) {
      final projected = <Offset>[
        for (final point in route) customerProject(point, camera, size),
      ];
      final path = Path()..moveTo(projected.first.dx, projected.first.dy);
      for (var i = 1; i < projected.length; i++) {
        path.lineTo(projected[i].dx, projected[i].dy);
      }
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 8
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..color = Colors.black.withValues(alpha: 0.45),
      );
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 5
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..color = line,
      );
    }
    _marker(canvas, size, pickup, Colors.white, line);
    _marker(canvas, size, dropoff, line, Colors.black);
  }

  void _marker(
    Canvas canvas,
    Size size,
    FluxidiLonLat? point,
    Color fill,
    Color ring,
  ) {
    if (point == null) return;
    final center = customerProject(point, camera, size);
    canvas.drawCircle(
      center,
      11,
      Paint()..color = Colors.black.withValues(alpha: 0.35),
    );
    canvas.drawCircle(center, 9, Paint()..color = ring);
    canvas.drawCircle(center, 5, Paint()..color = fill);
  }

  @override
  bool shouldRepaint(_CustomerRoutePainter oldDelegate) {
    return oldDelegate.camera.zoom != camera.zoom ||
        oldDelegate.camera.center.lat != camera.center.lat ||
        oldDelegate.camera.center.lon != camera.center.lon ||
        oldDelegate.route.length != route.length ||
        oldDelegate.pickup != pickup ||
        oldDelegate.dropoff != dropoff;
  }
}
