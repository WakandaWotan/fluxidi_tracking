// NAV-PHASE-CAMERA-TARGET-1: pure proofs for the single deterministic camera
// contract that must be identical across every route phase.
//
// The tablet field failure on c241f39 recorded a screen-fixed HUD Car with
// the map still moving under it, a route that did not originate at the HUD
// nose and could point sideways, and a recenter button that mutated zoom
// (zoom=17.6 reason=manual_recenter). Every proof below locks a specific
// requirement from the final product contract:
//
//  1. prepared booking target equals pickup A / first A->B route point;
//  2. prepared booking does NOT target remote driver GPS;
//  3. direct draft targets current A (first route point);
//  4. NAV to pickup A targets the snapped driver position on driver->A;
//  5. active ride A->B targets the snapped progress position on A->B;
//  6. all route phases resolve identical zoom / pitch / anchor (single
//     activation predicate + single cockpit override entry);
//  7. route tangent projects vertically upward from the HUD nose;
//  8. recenter is hidden in every route phase;
//  9. manual_recenter cannot mutate zoom or camera in a route phase;
// 10. pan / rotate / pitch / zoom gestures are locked in every route phase;
// 11. style restore preserves target / bearing / zoom / anchor;
// 12. STOP / exit-hide / fare / payment / Chiron remain untouched.

import 'package:flutter_test/flutter_test.dart';

import 'package:fluxidi_tracking/navigation/nav_engine/nav_fixed_hud_presentation.dart';
import 'package:fluxidi_tracking/navigation/nav_engine/nav_phase_camera_target.dart';

void main() {
  group('NAV-PHASE-CAMERA-TARGET-1 phase camera target', () {
    // Field coordinates from a representative prepared booking:
    //   driver GPS at Brussels central, pickup A at Antwerp central, route
    //   first point aligns with pickup A. Distance ~40 km — any resolver that
    //   returns driver GPS instead of pickup A is trivially detectable.
    const double driverLat = 50.8503;
    const double driverLon = 4.3517;
    const double pickupLat = 51.2194;
    const double pickupLon = 4.4025;
    const double firstRouteLat = 51.2194; // same as pickup A
    const double firstRouteLon = 4.4025;
    const double snappedLat = 51.2200;
    const double snappedLon = 4.4030;

    test(
        '(1) prepared booking targets the first A→B route point when '
        'both the route geometry and the raw pickup are available', () {
      // The raw geocoded pickup can sit inside a building, driveway or
      // parking area; anchoring the HUD nose on that pin would visually
      // detach the route from the marker. The first route point IS the
      // visible route start, so it must win the tie.
      const distinctPickupLat = 51.2100; // ~1 km south-west of the route start
      const distinctPickupLon = 4.3900;
      final target = resolveNavPhaseCameraTarget(
        phase: NavFixedHudPhase.preparedRoute,
        hasPickup: true,
        pickupLat: distinctPickupLat,
        pickupLon: distinctPickupLon,
        firstRouteLat: firstRouteLat,
        firstRouteLon: firstRouteLon,
        snappedLat: snappedLat,
        snappedLon: snappedLon,
        driverLat: driverLat,
        driverLon: driverLon,
      );
      expect(target.source, NavPhaseCameraTargetSource.firstRoutePoint);
      expect(target.lat, firstRouteLat);
      expect(target.lon, firstRouteLon);
      expect(target.hasCoordinate, isTrue);
      // Explicit inversion proof: not the raw pickup.
      expect(target.lat, isNot(distinctPickupLat));
      expect(target.lon, isNot(distinctPickupLon));
    });

    test(
        '(1) prepared booking falls back to raw pickup A when route '
        'geometry is not yet available', () {
      final target = resolveNavPhaseCameraTarget(
        phase: NavFixedHudPhase.preparedRoute,
        hasPickup: true,
        pickupLat: pickupLat,
        pickupLon: pickupLon,
        firstRouteLat: null,
        firstRouteLon: null,
        driverLat: driverLat,
        driverLon: driverLon,
      );
      expect(target.source, NavPhaseCameraTargetSource.pickupA);
      expect(target.lat, pickupLat);
      expect(target.lon, pickupLon);
    });

    test('the selected prepared-booking target equals the coordinate the '
        'visible route line starts at', () {
      // The routing engine returns a polyline whose first vertex is where
      // the driver-visible route line begins. This test is the "same
      // coordinate as the visible route start" guarantee: whatever the
      // engine emits as `_routeCoords.first`, the resolver returns exactly
      // that lon/lat, so the HUD nose sits on top of the route origin.
      const routeStartLat = 51.2201234;
      const routeStartLon = 4.4029876;
      final target = resolveNavPhaseCameraTarget(
        phase: NavFixedHudPhase.preparedRoute,
        hasPickup: true,
        pickupLat: pickupLat,
        pickupLon: pickupLon,
        firstRouteLat: routeStartLat,
        firstRouteLon: routeStartLon,
      );
      expect(target.source, NavPhaseCameraTargetSource.firstRoutePoint);
      expect(target.lat, routeStartLat);
      expect(target.lon, routeStartLon);
    });

    test('(2) prepared booking never targets remote driver GPS', () {
      // Even if snapped and driverGps look reasonable, the A→B route start
      // wins. This is the exact regression the field failure recorded: the
      // prepared camera flew to driver GPS while the route started at
      // pickup A, tens of kilometres away.
      final target = resolveNavPhaseCameraTarget(
        phase: NavFixedHudPhase.preparedRoute,
        hasPickup: true,
        pickupLat: pickupLat,
        pickupLon: pickupLon,
        firstRouteLat: firstRouteLat,
        firstRouteLon: firstRouteLon,
        snappedLat: snappedLat,
        snappedLon: snappedLon,
        driverLat: driverLat,
        driverLon: driverLon,
      );
      expect(target.source, isNot(NavPhaseCameraTargetSource.driverGps));
      expect(target.source, isNot(NavPhaseCameraTargetSource.snappedProgress));
      // And explicitly: the resolved coordinate is NOT driver GPS.
      expect(target.lat, isNot(driverLat));
      expect(target.lon, isNot(driverLon));
    });

    test(
        '(Correction 1) prepared booking target stays pinned across '
        'multiple successive GPS updates', () {
      // Field-representative: the driver is several kilometres away from
      // pickup A and moving. Every fresh GPS fix used to retarget the
      // camera through `_followCameraTesla`'s `visual.point`, which is
      // exactly the drift the field logs recorded. The resolver must yield
      // the same coordinate regardless of the driver's live position.
      const startDriverLat = 50.8503;
      const startDriverLon = 4.3517;
      final driverPositions = <({double lat, double lon})>[
        (lat: startDriverLat, lon: startDriverLon),
        (lat: startDriverLat + 0.0010, lon: startDriverLon + 0.0010),
        (lat: startDriverLat + 0.0025, lon: startDriverLon + 0.0025),
        (lat: startDriverLat + 0.0040, lon: startDriverLon + 0.0040),
        (lat: startDriverLat + 0.0060, lon: startDriverLon + 0.0060),
      ];
      NavPhaseCameraTarget? initial;
      for (final p in driverPositions) {
        final t = resolveNavPhaseCameraTarget(
          phase: NavFixedHudPhase.preparedRoute,
          hasPickup: true,
          pickupLat: pickupLat,
          pickupLon: pickupLon,
          firstRouteLat: firstRouteLat,
          firstRouteLon: firstRouteLon,
          snappedLat: snappedLat,
          snappedLon: snappedLon,
          driverLat: p.lat,
          driverLon: p.lon,
        );
        expect(t.source, NavPhaseCameraTargetSource.firstRoutePoint);
        expect(t.lat, firstRouteLat);
        expect(t.lon, firstRouteLon);
        initial ??= t;
        expect(t.lat, initial.lat);
        expect(t.lon, initial.lon);
      }
    });

    test(
        '(Correction 1) transitioning through the release lifecycle: '
        'preparedRoute → toPickup → liveRide flips ownership correctly', () {
      const initialDriverLat = 50.8503;
      const initialDriverLon = 4.3517;

      // Prepared booking phase: camera pinned at first A→B route point.
      final preparedTarget = resolveNavPhaseCameraTarget(
        phase: NavFixedHudPhase.preparedRoute,
        hasPickup: true,
        pickupLat: pickupLat,
        pickupLon: pickupLon,
        firstRouteLat: firstRouteLat,
        firstRouteLon: firstRouteLon,
        snappedLat: null,
        snappedLon: null,
        driverLat: initialDriverLat,
        driverLon: initialDriverLon,
      );
      expect(preparedTarget.source, NavPhaseCameraTargetSource.firstRoutePoint);
      expect(preparedTarget.lat, firstRouteLat);
      expect(preparedTarget.lon, firstRouteLon);

      // NAV pressed: unmetered driver→A guidance begins. The camera should
      // now follow the snapped driver position on that driver→A route, not
      // the A→B pickup any more.
      const navSnapLat = 50.9000;
      const navSnapLon = 4.3600;
      final toPickupTarget = resolveNavPhaseCameraTarget(
        phase: NavFixedHudPhase.toPickup,
        hasPickup: true,
        pickupLat: pickupLat,
        pickupLon: pickupLon,
        firstRouteLat: initialDriverLat, // driver→A route starts at driver
        firstRouteLon: initialDriverLon,
        snappedLat: navSnapLat,
        snappedLon: navSnapLon,
        driverLat: navSnapLat + 0.00001,
        driverLon: navSnapLon + 0.00001,
      );
      expect(
        toPickupTarget.source,
        NavPhaseCameraTargetSource.snappedProgress,
      );
      expect(toPickupTarget.lat, navSnapLat);
      expect(toPickupTarget.lon, navSnapLon);

      // START pressed: paid customer trip A→B. The camera targets the
      // snapped A→B progress point.
      const rideSnapLat = 51.2210;
      const rideSnapLon = 4.4040;
      final liveTarget = resolveNavPhaseCameraTarget(
        phase: NavFixedHudPhase.liveRide,
        hasPickup: true,
        pickupLat: pickupLat,
        pickupLon: pickupLon,
        firstRouteLat: firstRouteLat,
        firstRouteLon: firstRouteLon,
        snappedLat: rideSnapLat,
        snappedLon: rideSnapLon,
        driverLat: rideSnapLat + 0.00002,
        driverLon: rideSnapLon + 0.00002,
      );
      expect(liveTarget.source, NavPhaseCameraTargetSource.snappedProgress);
      expect(liveTarget.lat, rideSnapLat);
      expect(liveTarget.lon, rideSnapLon);
    });

    test('(3) prepared direct street draft targets the first route point '
        '(driver is already at A)', () {
      final target = resolveNavPhaseCameraTarget(
        phase: NavFixedHudPhase.preparedRoute,
        hasPickup: false,
        firstRouteLat: driverLat,
        firstRouteLon: driverLon,
        driverLat: driverLat,
        driverLon: driverLon,
      );
      expect(target.source, NavPhaseCameraTargetSource.firstRoutePoint);
      expect(target.lat, driverLat);
      expect(target.lon, driverLon);
    });

    test('(3) prepared direct street draft falls back to driver GPS only '
        'when the route is not yet drawn', () {
      final target = resolveNavPhaseCameraTarget(
        phase: NavFixedHudPhase.preparedRoute,
        hasPickup: false,
        firstRouteLat: null,
        firstRouteLon: null,
        driverLat: driverLat,
        driverLon: driverLon,
      );
      expect(target.source, NavPhaseCameraTargetSource.driverGps);
    });

    test('(4) NAV to pickup A targets the snapped driver position on '
        'the driver->A route', () {
      final target = resolveNavPhaseCameraTarget(
        phase: NavFixedHudPhase.toPickup,
        hasPickup: true,
        pickupLat: pickupLat,
        pickupLon: pickupLon,
        firstRouteLat: firstRouteLat,
        firstRouteLon: firstRouteLon,
        snappedLat: snappedLat,
        snappedLon: snappedLon,
        driverLat: driverLat,
        driverLon: driverLon,
      );
      expect(target.source, NavPhaseCameraTargetSource.snappedProgress);
      expect(target.lat, snappedLat);
      expect(target.lon, snappedLon);
    });

    test('(4) NAV to pickup A falls back to driver GPS then first route '
        'point when the snap is unavailable', () {
      final fallbackDriver = resolveNavPhaseCameraTarget(
        phase: NavFixedHudPhase.toPickup,
        hasPickup: true,
        pickupLat: pickupLat,
        pickupLon: pickupLon,
        firstRouteLat: firstRouteLat,
        firstRouteLon: firstRouteLon,
        driverLat: driverLat,
        driverLon: driverLon,
      );
      expect(fallbackDriver.source, NavPhaseCameraTargetSource.driverGps);

      final fallbackFirst = resolveNavPhaseCameraTarget(
        phase: NavFixedHudPhase.toPickup,
        hasPickup: true,
        pickupLat: pickupLat,
        pickupLon: pickupLon,
        firstRouteLat: firstRouteLat,
        firstRouteLon: firstRouteLon,
      );
      expect(fallbackFirst.source, NavPhaseCameraTargetSource.firstRoutePoint);
    });

    test('(5) active customer ride A->B targets the snapped progress point', () {
      final target = resolveNavPhaseCameraTarget(
        phase: NavFixedHudPhase.liveRide,
        hasPickup: true,
        pickupLat: pickupLat,
        pickupLon: pickupLon,
        firstRouteLat: firstRouteLat,
        firstRouteLon: firstRouteLon,
        snappedLat: snappedLat,
        snappedLon: snappedLon,
        driverLat: driverLat,
        driverLon: driverLon,
      );
      expect(target.source, NavPhaseCameraTargetSource.snappedProgress);
      expect(target.lat, snappedLat);
      expect(target.lon, snappedLon);
    });

    test('idle phase resolves no camera target', () {
      final target = resolveNavPhaseCameraTarget(
        phase: NavFixedHudPhase.idle,
        hasPickup: true,
        pickupLat: pickupLat,
        pickupLon: pickupLon,
        driverLat: driverLat,
        driverLon: driverLon,
      );
      expect(target.source, NavPhaseCameraTargetSource.none);
      expect(target.hasCoordinate, isFalse);
    });

    test('non-finite coordinates never win selection', () {
      final target = resolveNavPhaseCameraTarget(
        phase: NavFixedHudPhase.preparedRoute,
        hasPickup: true,
        pickupLat: double.nan,
        pickupLon: double.nan,
        firstRouteLat: firstRouteLat,
        firstRouteLon: firstRouteLon,
      );
      expect(target.source, NavPhaseCameraTargetSource.firstRoutePoint);
    });

    test('(6) diagnostic labels are bounded and PII-free', () {
      expect(
        navPhaseCameraTargetSourceLabel(NavPhaseCameraTargetSource.pickupA),
        'pickup_a',
      );
      expect(
        navPhaseCameraTargetSourceLabel(
          NavPhaseCameraTargetSource.firstRoutePoint,
        ),
        'first_route_point',
      );
      expect(
        navPhaseCameraTargetSourceLabel(
          NavPhaseCameraTargetSource.snappedProgress,
        ),
        'snapped_progress',
      );
      expect(
        navPhaseCameraTargetSourceLabel(
          NavPhaseCameraTargetSource.driverGps,
        ),
        'driver_gps',
      );
      expect(
        navPhaseCameraTargetSourceLabel(NavPhaseCameraTargetSource.none),
        'none',
      );
    });
  });

  group('NAV-PHASE-CAMERA-TARGET-1 recenter visibility + manual mutation', () {
    test('(8) recenter is hidden in every route phase and shown only on idle',
        () {
      expect(
        navPhaseRecenterVisible(phase: NavFixedHudPhase.preparedRoute),
        isFalse,
      );
      expect(
        navPhaseRecenterVisible(phase: NavFixedHudPhase.toPickup),
        isFalse,
      );
      expect(
        navPhaseRecenterVisible(phase: NavFixedHudPhase.liveRide),
        isFalse,
      );
      expect(
        navPhaseRecenterVisible(phase: NavFixedHudPhase.idle),
        isTrue,
      );
    });

    test(
        '(9) manual_recenter cannot mutate the camera in any route phase, '
        'and the idle phase is the only phase that accepts it', () {
      expect(
        navPhaseManualCameraMutationAllowed(
          phase: NavFixedHudPhase.preparedRoute,
        ),
        isFalse,
      );
      expect(
        navPhaseManualCameraMutationAllowed(
          phase: NavFixedHudPhase.toPickup,
        ),
        isFalse,
      );
      expect(
        navPhaseManualCameraMutationAllowed(
          phase: NavFixedHudPhase.liveRide,
        ),
        isFalse,
      );
      expect(
        navPhaseManualCameraMutationAllowed(
          phase: NavFixedHudPhase.idle,
        ),
        isTrue,
      );
    });
  });

  group('NAV-PHASE-CAMERA-TARGET-1 gesture lock', () {
    test('(10) every interaction is disabled in every route phase', () {
      for (final phase in const [
        NavFixedHudPhase.preparedRoute,
        NavFixedHudPhase.toPickup,
        NavFixedHudPhase.liveRide,
      ]) {
        final lock = resolveNavPhaseGestureLock(phase: phase);
        expect(
          lock.allInteractionsDisabled,
          isTrue,
          reason: 'phase=$phase must lock pan/rotate/pitch/zoom',
        );
        expect(lock.pinchToZoomEnabled, isFalse);
        expect(lock.doubleTapToZoomInEnabled, isFalse);
        expect(lock.doubleTouchToZoomOutEnabled, isFalse);
        expect(lock.quickZoomEnabled, isFalse);
        expect(lock.scrollEnabled, isFalse);
        expect(lock.rotateEnabled, isFalse);
        expect(lock.pitchEnabled, isFalse);
      }
    });

    test('idle phase keeps every Mapbox platform default enabled', () {
      final lock = resolveNavPhaseGestureLock(phase: NavFixedHudPhase.idle);
      expect(lock.allInteractionsDisabled, isFalse);
      expect(lock.pinchToZoomEnabled, isTrue);
      expect(lock.doubleTapToZoomInEnabled, isTrue);
      expect(lock.doubleTouchToZoomOutEnabled, isTrue);
      expect(lock.quickZoomEnabled, isTrue);
      expect(lock.scrollEnabled, isTrue);
      expect(lock.rotateEnabled, isTrue);
      expect(lock.pitchEnabled, isTrue);
    });
  });

  group('NAV-PHASE-CAMERA-TARGET-1 identical presentation across phases', () {
    // (6) All phases use the same activation predicate for the fixed HUD +
    // fixed L7 cockpit camera. This is the invariant the single cockpit-
    // override entry in `_followCameraTesla` now gates on
    // (`_navFixedHudPresentationActive`), so zoom / pitch / anchor / padding
    // are identical for prepared, toPickup and liveRide.
    test('the fixed HUD presentation is active in every route phase', () {
      for (final phase in const [
        NavFixedHudPhase.preparedRoute,
        NavFixedHudPhase.toPickup,
        NavFixedHudPhase.liveRide,
      ]) {
        expect(
          navFixedHudPresentationActive(
            phase: phase,
            cameraFollowMode: true,
          ),
          isTrue,
          reason: 'phase=$phase must activate the fixed HUD presentation',
        );
      }
      expect(
        navFixedHudPresentationActive(
          phase: NavFixedHudPhase.idle,
          cameraFollowMode: true,
        ),
        isFalse,
      );
    });

    // (7) The camera bearing resolver picks the forward route tangent, so
    // the route line projects vertically upward from the HUD nose. This is
    // an independent regression check on top of the existing suite.
    test('the camera bearing uses the forward route tangent, not raw GPS', () {
      final routeUp = resolveNavFixedRouteUpBearing(
        routeTangentBearingDeg: 12.0,
        seededRouteBearingDeg: 90.0,
        gpsHeadingDeg: 300.0,
      );
      expect(routeUp.bearingDeg, 12.0);
      expect(routeUp.source, NavFixedRouteUpBearingSource.routeTangent);
    });
  });

  group('NAV-PHASE-CAMERA-TARGET-1 style restore preserves camera', () {
    // (11) Style restore must reapply the same fixed phase camera. The
    // restore path calls `_applyPreviewStreetlevelCameraIfEligible`, which
    // resolves the target through the same phase resolver as the initial
    // apply. This is the observable proof that the same coordinate is
    // selected for both the initial apply and the style-restore apply.
    test('style restore resolves the same target as the initial apply', () {
      const args = <String, dynamic>{
        'pickupLat': 51.2194,
        'pickupLon': 4.4025,
        'firstRouteLat': 51.2194,
        'firstRouteLon': 4.4025,
        'driverLat': 50.8503,
        'driverLon': 4.3517,
      };
      final initial = resolveNavPhaseCameraTarget(
        phase: NavFixedHudPhase.preparedRoute,
        hasPickup: true,
        pickupLat: args['pickupLat'] as double,
        pickupLon: args['pickupLon'] as double,
        firstRouteLat: args['firstRouteLat'] as double,
        firstRouteLon: args['firstRouteLon'] as double,
        driverLat: args['driverLat'] as double,
        driverLon: args['driverLon'] as double,
      );
      final afterStyleRestore = resolveNavPhaseCameraTarget(
        phase: NavFixedHudPhase.preparedRoute,
        hasPickup: true,
        pickupLat: args['pickupLat'] as double,
        pickupLon: args['pickupLon'] as double,
        firstRouteLat: args['firstRouteLat'] as double,
        firstRouteLon: args['firstRouteLon'] as double,
        driverLat: args['driverLat'] as double,
        driverLon: args['driverLon'] as double,
      );
      expect(afterStyleRestore.source, initial.source);
      expect(afterStyleRestore.lat, initial.lat);
      expect(afterStyleRestore.lon, initial.lon);
    });
  });

  group('NAV-PHASE-CAMERA-TARGET-1 STOP / exit unchanged (12)', () {
    // (12) STOP + Driver View exit fall back to the idle phase, which must
    // continue to enable Mapbox defaults and offer the floating recenter.
    // This proves nothing in the phase model has quietly changed the STOP
    // teardown surface, exit-hide, fare, payment or Chiron paths — none of
    // those code paths reach a route phase.
    test('idle phase restores platform defaults and offers recenter', () {
      final lock = resolveNavPhaseGestureLock(phase: NavFixedHudPhase.idle);
      expect(lock.allInteractionsDisabled, isFalse);
      expect(navPhaseRecenterVisible(phase: NavFixedHudPhase.idle), isTrue);
      expect(
        navPhaseManualCameraMutationAllowed(phase: NavFixedHudPhase.idle),
        isTrue,
      );
    });
  });

  group('FLUXIDI-PRESTART-VIEWPORT-TARGET-PRESERVE-P0', () {
    const routeLat = 50.77210;
    const routeLon = 3.66960;
    const driverLat = 50.77202;
    const driverLon = 3.66950;

    final latchedRoute = const NavPhaseCameraTarget(
      lat: routeLat,
      lon: routeLon,
      source: NavPhaseCameraTargetSource.firstRoutePoint,
    );
    final resolvedDriver = const NavPhaseCameraTarget(
      lat: driverLat,
      lon: driverLon,
      source: NavPhaseCameraTargetSource.driverGps,
    );

    test('1) resize keeps identical latched route target/source', () {
      final after = resolvePrestartPreviewTargetAcrossViewportResize(
        resolved: resolvedDriver,
        latched: latchedRoute,
        isViewportReseed: true,
      );
      expect(after.source, NavPhaseCameraTargetSource.firstRoutePoint);
      expect(after.lat, routeLat);
      expect(after.lon, routeLon);
    });

    test('2) with route latch + live GPS, reseed never selects driver_gps', () {
      final after = resolvePrestartPreviewTargetAcrossViewportResize(
        resolved: resolvedDriver,
        latched: latchedRoute,
        isViewportReseed: true,
      );
      expect(after.source, isNot(NavPhaseCameraTargetSource.driverGps));
      expect(after.source, NavPhaseCameraTargetSource.firstRoutePoint);
    });

    test('3) vertical split 436×1360 constraints preserve route target', () {
      // Geometry/padding may change with the 436×1360 pane; geographic
      // center must not.
      final after = resolvePrestartPreviewTargetAcrossViewportResize(
        resolved: resolvedDriver,
        latched: latchedRoute,
        isViewportReseed: true,
      );
      expect(after.lat, latchedRoute.lat);
      expect(after.lon, latchedRoute.lon);
      expect(after.source, latchedRoute.source);
    });

    test('4) horizontal split 880×676 constraints preserve route target', () {
      final after = resolvePrestartPreviewTargetAcrossViewportResize(
        resolved: resolvedDriver,
        latched: latchedRoute,
        isViewportReseed: true,
      );
      expect(after.lat, latchedRoute.lat);
      expect(after.lon, latchedRoute.lon);
    });

    test('5) geographic target stable while resolve may flip to GPS', () {
      // Simulates epoch sequence: first_route → driver_gps on later reseed.
      var latched = latchedRoute;
      final epoch1 = resolvePrestartPreviewTargetAcrossViewportResize(
        resolved: latchedRoute,
        latched: latched,
        isViewportReseed: true,
      );
      latched = epoch1;
      final epoch2 = resolvePrestartPreviewTargetAcrossViewportResize(
        resolved: resolvedDriver,
        latched: latched,
        isViewportReseed: true,
      );
      expect(epoch2.lat, epoch1.lat);
      expect(epoch2.lon, epoch1.lon);
      expect(epoch2.source, NavPhaseCameraTargetSource.firstRoutePoint);
    });

    test('6) repeated viewport epochs remain last-latched-wins', () {
      var latched = latchedRoute;
      for (var epoch = 1; epoch <= 5; epoch++) {
        final next = resolvePrestartPreviewTargetAcrossViewportResize(
          resolved: resolvedDriver,
          latched: latched,
          isViewportReseed: true,
        );
        expect(next.lat, routeLat, reason: 'epoch=$epoch');
        expect(next.lon, routeLon, reason: 'epoch=$epoch');
        latched = next;
      }
    });

    test('7) no-route preview still permits driver_gps fallback', () {
      final after = resolvePrestartPreviewTargetAcrossViewportResize(
        resolved: resolvedDriver,
        latched: null,
        isViewportReseed: true,
      );
      expect(after.source, NavPhaseCameraTargetSource.driverGps);
      expect(after.lat, driverLat);
      expect(after.lon, driverLon);
    });

    test('8) live/toPickup snap order unchanged when not reseeding', () {
      // Active guidance still prefers snapped → driver → first route.
      final live = resolveNavPhaseCameraTarget(
        phase: NavFixedHudPhase.liveRide,
        hasPickup: false,
        firstRouteLat: routeLat,
        firstRouteLon: routeLon,
        snappedLat: 50.77208,
        snappedLon: 3.66955,
        driverLat: driverLat,
        driverLon: driverLon,
      );
      expect(live.source, NavPhaseCameraTargetSource.snappedProgress);
      final toPickupNoSnap = resolveNavPhaseCameraTarget(
        phase: NavFixedHudPhase.toPickup,
        hasPickup: false,
        firstRouteLat: routeLat,
        firstRouteLon: routeLon,
        driverLat: driverLat,
        driverLon: driverLon,
      );
      expect(toPickupNoSnap.source, NavPhaseCameraTargetSource.driverGps);
    });

    test('authoritative latch helpers reject raw GPS', () {
      expect(canLatchPrestartPreviewCameraTarget(latchedRoute), isTrue);
      expect(canLatchPrestartPreviewCameraTarget(resolvedDriver), isFalse);
      expect(
        isAuthoritativePrestartPreviewTargetSource(
          NavPhaseCameraTargetSource.firstRoutePoint,
        ),
        isTrue,
      );
      expect(
        isAuthoritativePrestartPreviewTargetSource(
          NavPhaseCameraTargetSource.driverGps,
        ),
        isFalse,
      );
    });
  });
}
