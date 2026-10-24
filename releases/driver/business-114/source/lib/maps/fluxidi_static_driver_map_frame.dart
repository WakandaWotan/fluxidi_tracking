import 'dart:math' as math;
import 'fluxidi_static_route_preview.dart';

/// Explicit north-up Mercator camera and marker projection for a static map.
/// Unlike an auto-fitted image, this keeps a local asset on its actual GPS point.
class FluxidiStaticDriverMapFrame {
  const FluxidiStaticDriverMapFrame({required this.url, required this.driverX,
    required this.driverY, this.width = 720, this.height = 360,
    this.cameraLongitude = 0, this.cameraLatitude = 0, this.cameraZoom = 0});
  final String url;
  final double driverX;
  final double driverY;
  final int width;
  final int height;
  final double cameraLongitude, cameraLatitude, cameraZoom;
}

FluxidiStaticDriverMapFrame? fluxidiDriverMapFrameGeometry({
  required FluxidiMapLonLat driver, List<FluxidiMapLonLat> route = const [],
}) => _fluxidiDriverMapFrame(driver:driver,route:route);

FluxidiStaticDriverMapFrame? fluxidiStaticDriverMapFrame({
  required FluxidiMapLonLat driver, List<FluxidiMapLonLat> route = const [],
  required String token,
}) => _fluxidiDriverMapFrame(driver:driver,route:route,token:token);

FluxidiStaticDriverMapFrame? _fluxidiDriverMapFrame({
  required FluxidiMapLonLat driver,
  List<FluxidiMapLonLat> route = const [],
  String? token,
}) {
  bool valid(FluxidiMapLonLat p) => p.lon.isFinite && p.lat.isFinite &&
      p.lon >= -180 && p.lon <= 180 && p.lat.abs() <= 85.0511;
  if ((token != null && token.trim().isEmpty) || !valid(driver)) return null;
  // Never bridge a gap in invalid geometry with an invented route segment.
  final usableRoute = route.length >= 2 && route.every(valid)
      ? downsampleFluxidiRoute(route) : <FluxidiMapLonLat>[];
  double x(FluxidiMapLonLat p) => (p.lon + 180) / 360;
  double y(FluxidiMapLonLat p) {
    final sine = math.sin(p.lat * math.pi / 180);
    return 0.5 - math.log((1 + sine) / (1 - sine)) / (4 * math.pi);
  }
  final driverX = x(driver);
  // Unwrap around the driver so a dateline crossing does not fit the world.
  double wrappedX(FluxidiMapLonLat p) {
    var result = x(p);
    while (result - driverX > 0.5) { result -= 1; }
    while (result - driverX < -0.5) { result += 1; }
    return result;
  }
  final points = <FluxidiMapLonLat>[driver, ...usableRoute];
  final xs = points.map(wrappedX).toList();
  final ys = points.map(y).toList();
  final minX = xs.reduce(math.min), maxX = xs.reduce(math.max);
  final minY = ys.reduce(math.min), maxY = ys.reduce(math.max);
  final centerX = (minX + maxX) / 2;
  final centerY = (minY + maxY) / 2;
  const width = 720, height = 360, padding = 112;
  double fitZoom(double span, int available) => span <= 0 ? 16 :
      math.log(available / (512 * span)) / math.ln2;
  final zoom = (math.min(16.0, math.min(
      fitZoom(maxX - minX, width - 2 * padding),
      fitZoom(maxY - minY, height - 2 * padding)))
      .clamp(0.0, 16.0) * 100).floor() / 100;
  final lon = ((centerX * 360 - 180 + 180) % 360) - 180;
  final n = math.pi * (1 - 2 * centerY);
  final lat = math.atan((math.exp(n) - math.exp(-n)) / 2) * 180 / math.pi;
  final scale = 512 * math.pow(2, zoom);
  final overlay = usableRoute.isEmpty ? '' :
      'path-5+2d8cff-0.86(${Uri.encodeComponent(encodeFluxidiPolyline5(usableRoute))})/';
  return FluxidiStaticDriverMapFrame(
    cameraLongitude:lon, cameraLatitude:lat, cameraZoom:zoom,
    url: token==null ? '' : 'https://api.mapbox.com/styles/v1/mapbox/navigation-night-v1/static/'
        '$overlay$lon,$lat,$zoom,0,0/${width}x$height?access_token=${Uri.encodeQueryComponent(token.trim())}',
    driverX: 0.5 + (driverX - centerX) * scale / width,
    driverY: 0.5 + (y(driver) - centerY) * scale / height,
  );
}
