import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/navigation/nav_engine/nav_route_render_invariant.dart';
import 'package:fluxidi_tracking/navigation/driver_navigation_draw_state.dart';
import 'package:fluxidi_tracking/navigation/driver_navigation_models.dart';
import 'package:fluxidi_tracking/navigation/driver_navigation_directions_request.dart';

NavRenderedGeometry _g(
  NavRouteGeometryRole role, {
  bool blue = true,
  int session = 1,
  int epoch = 1,
}) {
  return NavRenderedGeometry(
    role: role,
    primaryBlueStyle: blue,
    ownerSessionGeneration: session,
    renderEpoch: epoch,
  );
}

void main() {
  group('single authoritative blue route invariant', () {
    test('1. one active selected route => one primary-blue visual path', () {
      final ok = navSatisfiesSingleAuthoritativeBlueRoute(
        [
          _g(NavRouteGeometryRole.remaining),
          _g(NavRouteGeometryRole.completed, blue: false),
        ],
        currentSessionGeneration: 1,
        currentRenderEpoch: 1,
      );
      expect(ok, isTrue);
    });

    test('2. alternatives cannot use primary-route styling', () {
      final ok = navSatisfiesSingleAuthoritativeBlueRoute(
        [
          _g(NavRouteGeometryRole.remaining),
          _g(NavRouteGeometryRole.alternative, blue: true),
        ],
        currentSessionGeneration: 1,
        currentRenderEpoch: 1,
      );
      expect(ok, isFalse);
    });

    test('3. full + remaining cannot both be primary blue', () {
      final ok = navSatisfiesSingleAuthoritativeBlueRoute(
        [
          _g(NavRouteGeometryRole.remaining),
          _g(NavRouteGeometryRole.fullFallback, blue: true),
        ],
        currentSessionGeneration: 1,
        currentRenderEpoch: 1,
      );
      expect(ok, isFalse);
    });

    test('4. completed styling must stay distinct (not primary blue)', () {
      final ok = navSatisfiesSingleAuthoritativeBlueRoute(
        [
          _g(NavRouteGeometryRole.remaining),
          _g(NavRouteGeometryRole.completed, blue: true),
        ],
        currentSessionGeneration: 1,
        currentRenderEpoch: 1,
      );
      expect(ok, isFalse);
    });

    test('6. stale-owner primary-blue geometry (orphan) fails invariant', () {
      final ok = navSatisfiesSingleAuthoritativeBlueRoute(
        [
          _g(NavRouteGeometryRole.remaining, session: 2, epoch: 3),
          // Orphan from a prior style/session still blue on the map.
          _g(NavRouteGeometryRole.remaining, session: 1, epoch: 1),
        ],
        currentSessionGeneration: 2,
        currentRenderEpoch: 3,
      );
      expect(ok, isFalse);
    });
  });

  group('no orphan managers before recreate', () {
    test('7. all live managers are scheduled for disposal before recreate', () {
      final dispose = navRouteManagersToDisposeBeforeRecreate(
        hasRouteManager: true,
        hasPinsManager: true,
        hasDestinationManager: true,
      );
      expect(dispose, {
        NavRouteManagerSlot.route,
        NavRouteManagerSlot.pins,
        NavRouteManagerSlot.destination,
      });
    });

    test('first creation (no managers) disposes nothing', () {
      final dispose = navRouteManagersToDisposeBeforeRecreate(
        hasRouteManager: false,
        hasPinsManager: false,
        hasDestinationManager: false,
      );
      expect(dispose, isEmpty);
    });
  });

  group('reroute reshape draw signature', () {
    test('5/9. reshaped middle geometry (roundabout arm) changes signature', () {
      final a = [
        const DriverLonLat(4.0000, 51.0000),
        const DriverLonLat(4.0010, 51.0005),
        const DriverLonLat(4.0020, 51.0000),
      ];
      // Same length + endpoints, different middle (different roundabout arm).
      final b = [
        const DriverLonLat(4.0000, 51.0000),
        const DriverLonLat(4.0010, 50.9995),
        const DriverLonLat(4.0020, 51.0000),
      ];
      expect(
        driverRouteDrawSignature(a),
        isNot(driverRouteDrawSignature(b)),
      );
    });

    test('reshaped route is not skipped by the debounce', () {
      final a = [
        const DriverLonLat(4.0000, 51.0000),
        const DriverLonLat(4.0010, 51.0005),
        const DriverLonLat(4.0020, 51.0000),
      ];
      final b = [
        const DriverLonLat(4.0000, 51.0000),
        const DriverLonLat(4.0010, 50.9995),
        const DriverLonLat(4.0020, 51.0000),
      ];
      final now = DateTime(2026, 1, 1, 12, 0, 0);
      final skip = driverShouldSkipDraw(
        signature: driverRouteDrawSignature(b),
        lastSignature: driverRouteDrawSignature(a),
        lastDrawAt: now,
        debounce: const Duration(seconds: 2),
        now: now.add(const Duration(milliseconds: 500)),
      );
      expect(skip, isFalse);
    });
  });

  group('route-selection policy unchanged', () {
    test('10. directions request keeps alternatives=false (no alternatives)', () {
      final uri = buildDriverDirectionsUri(
        from: const DriverLonLat(4.0, 51.0),
        to: const DriverLonLat(4.1, 51.1),
        accessToken: 'test',
        languageCode: 'nl',
      );
      expect(uri.toString(), contains('alternatives=false'));
      expect(uri.toString(), contains('/directions/v5/mapbox/driving/'));
    });
  });
}
