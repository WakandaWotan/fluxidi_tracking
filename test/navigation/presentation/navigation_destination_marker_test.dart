import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/navigation/driver_navigation_map_config.dart';
import 'package:fluxidi_tracking/navigation/driver_navigation_models.dart';
import 'package:fluxidi_tracking/navigation/presentation/navigation_destination_marker.dart';

void main() {
  group('NAV-PRES-3L navigation destination marker', () {
    const route = <DriverLonLat>[
      DriverLonLat(4.0, 50.0),
      DriverLonLat(4.01, 50.01),
      DriverLonLat(4.02, 50.02),
    ];
    const dropoff = DriverLonLat(3.9, 49.9);

    test('route geometry final coordinate is preferred', () {
      final resolved = resolveNavigationDestinationMarkerCoordinate(
        routeCoords: route,
        trustedDropoff: dropoff,
      );
      expect(resolved, isNotNull);
      expect(resolved!.source, 'route_end');
      expect(resolved.lat, route.last.lat);
      expect(resolved.lon, route.last.lon);
    });

    test('dropoff coordinate is used when route geometry is unavailable', () {
      final resolved = resolveNavigationDestinationMarkerCoordinate(
        routeCoords: const <DriverLonLat>[],
        trustedDropoff: dropoff,
      );
      expect(resolved, isNotNull);
      expect(resolved!.source, 'dropoff');
      expect(resolved.lat, dropoff.lat);
      expect(resolved.lon, dropoff.lon);
    });

    test('null returned when no safe destination coordinate exists', () {
      expect(
        resolveNavigationDestinationMarkerCoordinate(
          routeCoords: const <DriverLonLat>[],
          trustedDropoff: null,
        ),
        isNull,
      );
      expect(
        resolveNavigationDestinationMarkerCoordinate(
          routeCoords: const <DriverLonLat>[DriverLonLat(0, 0)],
          trustedDropoff: const DriverLonLat(0, 0),
        ),
        isNull,
      );
    });

    test('destination marker icon size is clearly visible on phone and tablet', () {
      expect(
        driverDestinationMarkerIconSize(isTablet: false),
        kDriverDestinationMarkerIconSizePhone,
      );
      expect(
        driverDestinationMarkerIconSize(isTablet: true),
        kDriverDestinationMarkerIconSizeTablet,
      );
      expect(kDriverDestinationMarkerIconSizePhone, greaterThanOrEqualTo(1.0));
      expect(kDriverDestinationMarkerIconSizeTablet, greaterThanOrEqualTo(1.25));
      expect(
        driverDestinationMarkerIconSize(isTablet: true),
        greaterThan(driverDestinationMarkerIconSize(isTablet: false)),
      );
    });

    test('finish flag asset path is registered for premium destination marker', () {
      expect(kDriverFinishFlagMarkerAssetPath, contains('driver_finish_flag'));
    });

    test('marker signature changes only when source or coordinate changes', () {
      final first = resolveNavigationDestinationMarkerCoordinate(
        routeCoords: route,
        trustedDropoff: dropoff,
      )!;
      final same = resolveNavigationDestinationMarkerCoordinate(
        routeCoords: route,
        trustedDropoff: dropoff,
      )!;
      final fallback = resolveNavigationDestinationMarkerCoordinate(
        routeCoords: const <DriverLonLat>[],
        trustedDropoff: dropoff,
      )!;
      expect(
        navigationDestinationMarkerSignature(first),
        navigationDestinationMarkerSignature(same),
      );
      expect(
        navigationDestinationMarkerSignature(first),
        isNot(navigationDestinationMarkerSignature(fallback)),
      );
    });
  });
}
