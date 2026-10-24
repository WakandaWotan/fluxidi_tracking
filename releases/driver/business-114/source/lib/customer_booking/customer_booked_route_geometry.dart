import 'customer_live_tracking.dart';

/// An archived passenger route from the current authorized booking grant.
/// This supplies map context only; it never grants GPS, ETA or navigation.
List<CustomerLivePoint> customerBookedRoutePoints(Object? raw, {
  required CustomerLivePoint? pickup, required CustomerLivePoint? destination,
}) {
  bool same(Object? value, CustomerLivePoint? expected) => value is Map &&
      expected != null && value['latitude'] is num && value['longitude'] is num &&
      (value['latitude'] as num).isFinite && (value['longitude'] as num).isFinite &&
      ((value['latitude'] as num).toDouble()-expected.latitude).abs() <= 1e-7 &&
      ((value['longitude'] as num).toDouble()-expected.longitude).abs() <= 1e-7;
  if (raw is! Map || raw['schema'] != 'fluxidi-booked-route-geometry-v1' ||
      raw['type'] != 'LineString' || !same(raw['pickup'],pickup) ||
      !same(raw['destination'],destination)) return const [];
  final coordinates=raw['coordinates'];
  if(coordinates is! List || coordinates.length<2 || coordinates.length>100000) return const [];
  final result=<CustomerLivePoint>[];
  for(final point in coordinates){
    if(point is! List || point.length!=2 || point[0] is! num || point[1] is! num) return const [];
    final longitude=(point[0] as num).toDouble(),latitude=(point[1] as num).toDouble();
    if(!latitude.isFinite || !longitude.isFinite || latitude.abs()>90 || longitude.abs()>180) return const [];
    result.add(CustomerLivePoint(latitude:latitude,longitude:longitude));
  }
  return List.unmodifiable(result);
}
