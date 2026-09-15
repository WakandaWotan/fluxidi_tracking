// Shared Mapbox static route preview used by Driver Home and Rit plannen.
// Windows has no native Mapbox Maps plugin; this is the existing reliable surface.

import 'package:fluxidi_tracking/app_config.dart';

class FluxidiMapLonLat {
  const FluxidiMapLonLat(this.lon, this.lat);
  final double lon;
  final double lat;
}

List<FluxidiMapLonLat> downsampleFluxidiRoute(
  List<FluxidiMapLonLat> coords, {
  int maxPoints = 92,
}) {
  if (coords.length <= maxPoints) return coords;
  final out = <FluxidiMapLonLat>[coords.first];
  final stride = (coords.length - 2) / (maxPoints - 2);
  var cursor = 1.0;
  while (out.length < maxPoints - 1) {
    final idx = cursor.round().clamp(1, coords.length - 2);
    out.add(coords[idx]);
    cursor += stride;
  }
  out.add(coords.last);
  return out;
}

String encodeFluxidiPolyline5(List<FluxidiMapLonLat> points) {
  if (points.isEmpty) return '';
  final sb = StringBuffer();
  var lastLat = 0;
  var lastLon = 0;
  void encodeDelta(int delta) {
    var v = delta < 0 ? ~(delta << 1) : (delta << 1);
    while (v >= 0x20) {
      sb.writeCharCode((0x20 | (v & 0x1f)) + 63);
      v >>= 5;
    }
    sb.writeCharCode(v + 63);
  }

  for (final p in points) {
    final lat = (p.lat * 1e5).round();
    final lon = (p.lon * 1e5).round();
    encodeDelta(lat - lastLat);
    encodeDelta(lon - lastLon);
    lastLat = lat;
    lastLon = lon;
  }
  return sb.toString();
}

String? fluxidiStaticRoutePreviewUrl({
  required FluxidiMapLonLat pickup,
  required FluxidiMapLonLat dropoff,
  List<FluxidiMapLonLat> route = const <FluxidiMapLonLat>[],
  String token = kMapboxToken,
  int width = 720,
  int height = 280,
}) {
  final access = token.trim();
  if (access.isEmpty) return null;
  final overlays = StringBuffer()
    ..write('pin-s-a+f4c542(${pickup.lon},${pickup.lat}),')
    ..write('pin-s-b+ff5a4f(${dropoff.lon},${dropoff.lat})');
  if (route.length >= 2) {
    final polyline = Uri.encodeComponent(
      encodeFluxidiPolyline5(downsampleFluxidiRoute(route)),
    );
    overlays.write(',path-5+2d8cff-0.86($polyline)');
  }
  return 'https://api.mapbox.com/styles/v1/mapbox/navigation-night-v1/static/'
      '${overlays.toString()}/auto/${width}x$height'
      '?padding=34,22,34,22&access_token=$access';
}
