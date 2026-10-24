/// Coordinate pair and route identity.
///
/// Ported from golden commit 9df7e7b92ecc86a11184ee995e255da7b8f6fb68:
/// - `lib/maps/fluxidi_static_route_preview.dart` — `FluxidiMapLonLat`,
///   `downsampleFluxidiRoute`
/// - `lib/customer_booking/customer_booking_route_camera.dart` —
///   `customerBookingLonLat`, `customerBookingRouteFingerprint`
library;

class FluxidiLonLat {
  const FluxidiLonLat(this.lon, this.lat);

  final double lon;
  final double lat;

  @override
  String toString() => 'FluxidiLonLat($lon, $lat)';
}

/// Null unless both values are finite and inside real coordinate bounds.
FluxidiLonLat? fluxidiLonLat(double? lat, double? lon) {
  if (lat == null || lon == null || !lat.isFinite || !lon.isFinite) return null;
  if (lat.abs() > 90 || lon.abs() > 180) return null;
  return FluxidiLonLat(lon, lat);
}

/// Identifies a route by its endpoints, so a cached line is never reused for a
/// different ride.
String fluxidiRouteFingerprint({
  required FluxidiLonLat? pickup,
  required FluxidiLonLat? dropoff,
  List<FluxidiLonLat> stops = const <FluxidiLonLat>[],
}) {
  String coord(FluxidiLonLat? value) {
    if (value == null) return '';
    return '${value.lon.toStringAsFixed(5)},${value.lat.toStringAsFixed(5)}';
  }

  return <String>[
    coord(pickup),
    for (final stop in stops) coord(stop),
    coord(dropoff),
  ].join('|');
}

/// Keeps a long route drawable without losing its shape.
List<FluxidiLonLat> downsampleFluxidiRoute(
  List<FluxidiLonLat> coords, {
  int maxPoints = 92,
}) {
  if (coords.length <= maxPoints) return coords;
  final out = <FluxidiLonLat>[coords.first];
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
