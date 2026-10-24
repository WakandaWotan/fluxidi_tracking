import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:fluxidi_tracking/navigation/driver_navigation_location_config.dart';

void main() {
  group('buildDriverActiveNavigationLocationSettingsFor', () {
    test(
      'Android requests bestForNavigation + 500ms interval + distanceFilter 0',
      () {
        final settings = buildDriverActiveNavigationLocationSettingsFor(
          NavGpsPlatform.android,
        );
        expect(settings, isA<geo.AndroidSettings>());
        final android = settings as geo.AndroidSettings;
        expect(android.accuracy, geo.LocationAccuracy.bestForNavigation);
        expect(android.distanceFilter, 0);
        expect(android.intervalDuration, const Duration(milliseconds: 500));
        expect(android.forceLocationManager, isFalse);
      },
    );

    test(
      'iOS requests automotiveNavigation + distanceFilter 0, no pausing',
      () {
        final settings = buildDriverActiveNavigationLocationSettingsFor(
          NavGpsPlatform.ios,
        );
        expect(settings, isA<geo.AppleSettings>());
        final apple = settings as geo.AppleSettings;
        expect(apple.accuracy, geo.LocationAccuracy.bestForNavigation);
        expect(apple.distanceFilter, 0);
        expect(apple.activityType, geo.ActivityType.automotiveNavigation);
        expect(apple.pauseLocationUpdatesAutomatically, isFalse);
      },
    );

    test(
      'other platforms fall back to bestForNavigation + distanceFilter 0',
      () {
        final settings = buildDriverActiveNavigationLocationSettingsFor(
          NavGpsPlatform.other,
        );
        expect(settings.accuracy, geo.LocationAccuracy.bestForNavigation);
        expect(settings.distanceFilter, 0);
      },
    );

    test('idle tracking settings are distinct and keep the 3m filter', () {
      final idle = buildDriverTrackingLocationSettings();
      expect(idle.accuracy, geo.LocationAccuracy.bestForNavigation);
      expect(idle.distanceFilter, 3);
    });
  });
}
