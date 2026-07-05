import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mb;

const bool kDriverMapTextureView = true;
const mb.AndroidPlatformViewHostingMode kDriverMapHostingMode =
    mb.AndroidPlatformViewHostingMode.HC;
const double kDriverMapInitialCenterLon = 3.62;
const double kDriverMapInitialCenterLat = 50.78;
const double kDriverMapInitialZoom = 12.0;

/// Top-down taxi bitmap for the live driver vehicle marker on the map.
const String kDriverTaxiMarkerAssetPath =
    'assets/navigation/driver_taxi_top.png';

/// Scales the taxi PNG on screen (490×490 source). Tune after field test.
const double kDriverTaxiMarkerIconSize = 0.52;

const String kDriverMapStyleLight = 'mapbox://styles/mapbox/streets-v12';
const String kDriverMapStyleDark = 'mapbox://styles/mapbox/navigation-night-v1';

String driverMapStyleForTheme({required bool isLightTheme}) {
  return isLightTheme ? kDriverMapStyleLight : kDriverMapStyleDark;
}
