import 'package:geolocator/geolocator.dart' as geo;

geo.LocationSettings buildDriverTrackingLocationSettings() {
  return const geo.LocationSettings(
    accuracy: geo.LocationAccuracy.bestForNavigation,
    distanceFilter: 3,
  );
}
