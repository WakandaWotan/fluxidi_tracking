import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mb;

const bool kDriverMapTextureView = true;
const mb.AndroidPlatformViewHostingMode kDriverMapHostingMode =
    mb.AndroidPlatformViewHostingMode.HC;
const double kDriverMapInitialCenterLon = 3.62;
const double kDriverMapInitialCenterLat = 50.78;
const double kDriverMapInitialZoom = 12.0;

const String kDriverMapStyleLight = 'mapbox://styles/mapbox/streets-v12';
const String kDriverMapStyleDark = 'mapbox://styles/mapbox/navigation-night-v1';

String driverMapStyleForTheme({required bool isLightTheme}) {
  return isLightTheme ? kDriverMapStyleLight : kDriverMapStyleDark;
}
