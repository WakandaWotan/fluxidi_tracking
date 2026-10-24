import 'driver_navigation_models.dart';
import 'nav_engine/nav_reroute_coordinator.dart';

String buildDriverDirectionsCoordinates({
  required DriverLonLat from,
  required DriverLonLat to,
}) {
  return '${from.lon},${from.lat};${to.lon},${to.lat}';
}

Uri buildDriverDirectionsUri({
  required DriverLonLat from,
  required DriverLonLat to,
  required String languageCode,
  required String accessToken,
  double? originHeadingDeg,
}) {
  final coords = buildDriverDirectionsCoordinates(from: from, to: to);
  final bearings = originHeadingDeg != null && originHeadingDeg.isFinite
      ? '&bearings=${Uri.encodeQueryComponent(NavRerouteCoordinator.bearingsQueryValue(originHeadingDeg))}'
      : '';
  return Uri.parse(
    'https://api.mapbox.com/directions/v5/mapbox/driving/$coords'
    '?alternatives=false&geometries=geojson&overview=full&steps=true'
    '&banner_instructions=true&roundabout_exits=true'
    '&language=$languageCode'
    '$bearings'
    '&access_token=$accessToken',
  );
}
