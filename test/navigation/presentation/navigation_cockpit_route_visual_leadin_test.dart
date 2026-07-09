import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/navigation/driver_navigation_geometry.dart';
import 'package:fluxidi_tracking/navigation/driver_navigation_models.dart';
import 'package:fluxidi_tracking/navigation/presentation/navigation_destination_marker.dart';
import 'package:fluxidi_tracking/navigation/presentation/navigation_driver_cockpit_camera.dart';

void main() {
  group('NAV-PRES-3L-A cockpit route visual lead-in', () {
    const route = <DriverLonLat>[
      DriverLonLat(4.0, 50.0),
      DriverLonLat(4.001, 50.0),
      DriverLonLat(4.002, 50.0),
      DriverLonLat(4.003, 50.0),
    ];
    const snap = DriverRouteSnap(
      point: DriverLonLat(4.0015, 50.0),
      distanceFromRouteM: 0.5,
      distanceAlongRouteM: 120.0,
      segmentIndex: 1,
      segmentT: 0.5,
    );

    test('lead-in meters are minimal for overview and stronger for streetlevel', () {
      expect(driverCockpitRouteVisualLeadInMeters(1), 0.0);
      expect(driverCockpitRouteVisualLeadInMeters(6), lessThanOrEqualTo(8.0));
      expect(driverCockpitRouteVisualLeadInMeters(7), inInclusiveRange(25.0, 45.0));
      expect(driverCockpitRouteVisualLeadInMeters(9), inInclusiveRange(25.0, 45.0));
      expect(driverCockpitRouteVisualLeadInMeters(10), inInclusiveRange(45.0, 75.0));
      expect(driverCockpitRouteVisualLeadInMeters(11), inInclusiveRange(45.0, 75.0));
      expect(driverCockpitRouteVisualLeadInMeters(13), inInclusiveRange(75.0, 120.0));
    });

    test('View 13 lead-in exceeds View 7 lead-in', () {
      expect(
        driverCockpitRouteVisualLeadInMeters(13),
        greaterThan(driverCockpitRouteVisualLeadInMeters(7)),
      );
    });

    test('visual lead-in adds a segment before snap for high cockpit views', () {
      final base = driverRouteCoordsFromSnap(route, snap);
      final withLeadIn = driverRouteCoordsWithCockpitVisualLeadIn(
        routeCoords: route,
        snap: snap,
        leadInM: 20.0,
      );
      expect(withLeadIn.length, greaterThan(base.length));
      expect(
        driverRouteLengthMeters(withLeadIn),
        greaterThan(driverRouteLengthMeters(base)),
      );
    });

    test('lead-in clamps at route start and never creates invalid geometry', () {
      final nearStartSnap = DriverRouteSnap(
        point: DriverLonLat(4.0002, 50.0),
        distanceFromRouteM: 0.2,
        distanceAlongRouteM: 15.0,
        segmentIndex: 0,
        segmentT: 0.2,
      );
      final withLeadIn = driverRouteCoordsWithCockpitVisualLeadIn(
        routeCoords: route,
        snap: nearStartSnap,
        leadInM: 120.0,
      );
      expect(withLeadIn.first.lat, route.first.lat);
      expect(withLeadIn.first.lon, route.first.lon);
      expect(withLeadIn.length, greaterThanOrEqualTo(2));
    });

    test('zero lead-in keeps existing remaining route geometry', () {
      final base = driverRouteCoordsFromSnap(route, snap);
      final unchanged = driverRouteCoordsWithCockpitVisualLeadIn(
        routeCoords: route,
        snap: snap,
        leadInM: 0.0,
      );
      expect(unchanged.length, base.length);
      expect(unchanged.first.lat, base.first.lat);
      expect(unchanged.first.lon, base.first.lon);
    });

    test('completed/up-to-snap geometry is unchanged by visual lead-in helper', () {
      final completed = driverRouteCoordsUpToSnap(route, snap);
      final withLeadIn = driverRouteCoordsWithCockpitVisualLeadIn(
        routeCoords: route,
        snap: snap,
        leadInM: 25.0,
      );
      expect(withLeadIn.last.lat, route.last.lat);
      expect(withLeadIn.last.lon, route.last.lon);
      expect(completed.last.lat, snap.point.lat);
      expect(completed.last.lon, snap.point.lon);
    });

    test('tablet dynamic nose anchor increases for overview and stays clamped', () {
      final phoneL7 = driverCockpitViewLevelTargetAnchorFraction(
        isTablet: false,
        isLandscape: false,
        level: 13,
      );
      final tabletL6 = driverCockpitViewLevelTargetAnchorFraction(
        isTablet: true,
        isLandscape: false,
        level: 6,
      );
      final tabletL13 = driverCockpitViewLevelTargetAnchorFraction(
        isTablet: true,
        isLandscape: false,
        level: 13,
      );
      final tabletL1 = driverCockpitViewLevelTargetAnchorFraction(
        isTablet: true,
        isLandscape: false,
        level: 1,
      );
      expect(phoneL7, closeTo(kDriverCockpitPro2PhoneAnchorL7, 0.10));
      expect(tabletL1, greaterThan(tabletL13));
      expect(tabletL13, greaterThan(tabletL6 * 0.9));
      expect(
        tabletL13,
        inInclusiveRange(
          kDriverCockpitNoseAnchorMinTablet,
          kDriverCockpitNoseAnchorMaxTablet,
        ),
      );
    });

    test('destination marker coordinate ignores visual lead-in', () {
      final destination = resolveNavigationDestinationMarkerCoordinate(
        routeCoords: route,
        trustedDropoff: const DriverLonLat(3.9, 49.9),
      );
      expect(destination, isNotNull);
      expect(destination!.source, 'route_end');
      expect(destination.lat, route.last.lat);
      expect(destination.lon, route.last.lon);
    });
  });
}
