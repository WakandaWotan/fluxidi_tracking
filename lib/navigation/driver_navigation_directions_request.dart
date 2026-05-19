import 'driver_navigation_models.dart';

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
}) {
  final coords = buildDriverDirectionsCoordinates(from: from, to: to);
  return Uri.parse(
    'https://api.mapbox.com/directions/v5/mapbox/driving/$coords'
    '?alternatives=false&geometries=geojson&overview=full&steps=true'
    '&language=$languageCode'
    '&access_token=$accessToken',
  );
}
