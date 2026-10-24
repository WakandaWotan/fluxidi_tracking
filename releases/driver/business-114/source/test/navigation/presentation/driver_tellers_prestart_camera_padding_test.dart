// FLUXIDI-TELLERS-PRESTART-LIVE-ANCHOR
//
// Pre-START Tellers must consume liveWindowRect camera padding while keeping
// the exact latched geographic preview target. Ordinary Navigatie padding is
// bit-stable when Tellers is inactive.

import 'dart:ui' show Offset, Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/navigation/nav_engine/nav_fixed_hud_presentation.dart';
import 'package:fluxidi_tracking/navigation/nav_engine/nav_phase_camera_target.dart';
import 'package:fluxidi_tracking/navigation/presentation/driver_tellers_layout_geometry.dart';
import 'package:fluxidi_tracking/navigation/presentation/driver_viewport_anchor_geometry.dart';

void main() {
  group('FLUXIDI-TELLERS-PRESTART-LIVE-ANCHOR', () {
    final ordinary = resolveDriverViewportAnchorGeometry(
      hostIsTablet: true,
      viewportWidth: 880,
      viewportHeight: 1408,
      layoutBottomHudHeightPx: 188,
      safeTop: 24,
      safeBottom: 48,
    ).cameraPadding;

    final tellers = DriverTellersLayoutGeometry.resolve(
      viewportSize: const Size(880, 1408),
      safeTop: 24,
      safeBottom: 48,
      safeLeft: 0,
      safeRight: 0,
      isLandscape: false,
      isTablet: true,
      reserveActionBar: false,
    );

    test('Tellers inactive keeps ordinary cockpit padding unchanged', () {
      final resolved = resolveTellersAwarePreviewCameraPadding(
        tellersActive: false,
        ordinaryCockpitPadding: ordinary,
        tellersLiveWindowPadding: tellers.cameraPadding,
      );
      expect(resolved.top, ordinary.top);
      expect(resolved.bottom, ordinary.bottom);
      expect(resolved.left, ordinary.left);
      expect(resolved.right, ordinary.right);
      // Byte-stable vs a second Navigatie resolve with identical inputs.
      final ordinary2 = resolveDriverViewportAnchorGeometry(
        hostIsTablet: true,
        viewportWidth: 880,
        viewportHeight: 1408,
        layoutBottomHudHeightPx: 188,
        safeTop: 24,
        safeBottom: 48,
      ).cameraPadding;
      expect(ordinary.top, ordinary2.top);
      expect(ordinary.bottom, ordinary2.bottom);
      expect(ordinary.left, ordinary2.left);
      expect(ordinary.right, ordinary2.right);
    });

    test('Tellers active consumes live-window padding, not ordinary', () {
      final resolved = resolveTellersAwarePreviewCameraPadding(
        tellersActive: true,
        ordinaryCockpitPadding: ordinary,
        tellersLiveWindowPadding: tellers.cameraPadding,
      );
      expect(resolved.top, tellers.cameraPadding.top);
      expect(resolved.bottom, tellers.cameraPadding.bottom);
      expect(resolved.left, tellers.cameraPadding.left);
      expect(resolved.right, tellers.cameraPadding.right);
      expect(resolved.top, isNot(ordinary.top));
    });

    test('null Tellers padding falls back to ordinary even if active', () {
      final resolved = resolveTellersAwarePreviewCameraPadding(
        tellersActive: true,
        ordinaryCockpitPadding: ordinary,
        tellersLiveWindowPadding: null,
      );
      expect(resolved.top, ordinary.top);
      expect(resolved.bottom, ordinary.bottom);
    });

    test('fullscreen Tellers realizes 20–24 lp tail margin', () {
      final tailGap =
          tellers.liveWindowRect.bottom - tellers.vehicleTailGlobal.dy;
      expect(tailGap, greaterThanOrEqualTo(20 - 0.5));
      expect(tailGap, lessThanOrEqualTo(24 + 0.5));
      expect(tellers.cameraPaddingFocalPoint, tellers.vehicleCenterGlobal);
    });

    test('horizontal split short pane stays unclipped with low anchor', () {
      final split = DriverTellersLayoutGeometry.resolve(
        viewportSize: const Size(880, 704),
        safeTop: 24,
        safeBottom: 24,
        safeLeft: 0,
        safeRight: 0,
        isLandscape: false,
        isTablet: true,
        reserveActionBar: false,
      );
      expect(split.liveWindowRect.height, greaterThan(80));
      expect(
        split.vehicleTailGlobal.dy,
        lessThanOrEqualTo(split.liveWindowRect.bottom + 0.5),
      );
      expect(
        split.markerAnchor.dy,
        greaterThanOrEqualTo(split.liveWindowRect.top - 0.5),
      );
      final gap = split.liveWindowRect.bottom - split.vehicleTailGlobal.dy;
      expect(gap, greaterThanOrEqualTo(0));
      expect(gap, lessThanOrEqualTo(24 + 0.5));
    });

    test('vertical split pane keeps vehicle inside live window', () {
      final split = DriverTellersLayoutGeometry.resolve(
        viewportSize: const Size(440, 1408),
        safeTop: 24,
        safeBottom: 48,
        safeLeft: 0,
        safeRight: 0,
        isLandscape: false,
        isTablet: true,
        reserveActionBar: false,
      );
      expect(split.containsInLiveWindow(split.vehicleCenterGlobal), isTrue);
      expect(split.containsInLiveWindow(split.vehicleTailGlobal), isTrue);
      final gap = split.liveWindowRect.bottom - split.vehicleTailGlobal.dy;
      expect(gap, closeTo(kTellersLiveWindowVehicleBottomMarginPx, 1.5));
    });

    test('preview target source/lat/lon unchanged across Tellers padding swap', () {
      const latched = NavPhaseCameraTarget(
        lat: 50.770123,
        lon: 3.660456,
        source: NavPhaseCameraTargetSource.firstRoutePoint,
      );
      // Reseed while Tellers open must keep latched route target.
      final afterReseed = resolvePrestartPreviewTargetAcrossViewportResize(
        resolved: const NavPhaseCameraTarget(
          lat: 50.771000,
          lon: 3.661000,
          source: NavPhaseCameraTargetSource.driverGps,
        ),
        latched: latched,
        isViewportReseed: true,
      );
      expect(afterReseed.source, NavPhaseCameraTargetSource.firstRoutePoint);
      expect(afterReseed.lat, latched.lat);
      expect(afterReseed.lon, latched.lon);

      final tellersPad = resolveTellersAwarePreviewCameraPadding(
        tellersActive: true,
        ordinaryCockpitPadding: ordinary,
        tellersLiveWindowPadding: tellers.cameraPadding,
      );
      final navPad = resolveTellersAwarePreviewCameraPadding(
        tellersActive: false,
        ordinaryCockpitPadding: ordinary,
        tellersLiveWindowPadding: tellers.cameraPadding,
      );
      // Padding differs; geographic target identity is independent and equal.
      expect(tellersPad.top, isNot(navPad.top));
      expect(afterReseed.lat, 50.770123);
      expect(afterReseed.lon, 3.660456);
    });

    test('valid latched route target never becomes driver_gps on reseed', () {
      const latched = NavPhaseCameraTarget(
        lat: 50.77,
        lon: 3.66,
        source: NavPhaseCameraTargetSource.firstRoutePoint,
      );
      for (final resolved in <NavPhaseCameraTarget>[
        const NavPhaseCameraTarget(
          lat: 50.78,
          lon: 3.67,
          source: NavPhaseCameraTargetSource.driverGps,
        ),
        const NavPhaseCameraTarget(
          lat: 0,
          lon: 0,
          source: NavPhaseCameraTargetSource.none,
        ),
      ]) {
        final out = resolvePrestartPreviewTargetAcrossViewportResize(
          resolved: resolved,
          latched: latched,
          isViewportReseed: true,
        );
        expect(out.source, isNot(NavPhaseCameraTargetSource.driverGps));
        expect(out.source, NavPhaseCameraTargetSource.firstRoutePoint);
        expect(out.lat, latched.lat);
        expect(out.lon, latched.lon);
      }
    });

    test('prepared booking phase prefers first_route_point over driver_gps', () {
      final target = resolveNavPhaseCameraTarget(
        phase: NavFixedHudPhase.preparedRoute,
        hasPickup: true,
        pickupLat: 50.77,
        pickupLon: 3.66,
        firstRouteLat: 50.7701,
        firstRouteLon: 3.6602,
        driverLat: 50.78,
        driverLon: 3.67,
      );
      expect(target.source, NavPhaseCameraTargetSource.firstRoutePoint);
      expect(target.lat, 50.7701);
      expect(target.lon, 3.6602);
    });

    test('latest viewport geometry wins padding (divider drag)', () {
      final a = DriverTellersLayoutGeometry.resolve(
        viewportSize: const Size(880, 1408),
        safeTop: 24,
        safeBottom: 48,
        safeLeft: 0,
        safeRight: 0,
        isLandscape: false,
        isTablet: true,
      );
      final b = DriverTellersLayoutGeometry.resolve(
        viewportSize: const Size(880, 900),
        safeTop: 24,
        safeBottom: 24,
        safeLeft: 0,
        safeRight: 0,
        isLandscape: false,
        isTablet: true,
      );
      final padA = resolveTellersAwarePreviewCameraPadding(
        tellersActive: true,
        ordinaryCockpitPadding: ordinary,
        tellersLiveWindowPadding: a.cameraPadding,
      );
      final padB = resolveTellersAwarePreviewCameraPadding(
        tellersActive: true,
        ordinaryCockpitPadding: ordinary,
        tellersLiveWindowPadding: b.cameraPadding,
      );
      expect(padB.top, isNot(padA.top));
      expect(padB.top, b.cameraPadding.top);
      expect(padB.bottom, b.cameraPadding.bottom);
    });

    test('closing Tellers: ordinary padding selection restored', () {
      final whileOpen = resolveTellersAwarePreviewCameraPadding(
        tellersActive: true,
        ordinaryCockpitPadding: ordinary,
        tellersLiveWindowPadding: tellers.cameraPadding,
      );
      final afterClose = resolveTellersAwarePreviewCameraPadding(
        tellersActive: false,
        ordinaryCockpitPadding: ordinary,
        tellersLiveWindowPadding: tellers.cameraPadding,
      );
      expect(whileOpen.top, tellers.cameraPadding.top);
      expect(afterClose.top, ordinary.top);
      expect(afterClose.bottom, ordinary.bottom);
    });

    test('SM-X400-like fullscreen Tellers pad focal is below ordinary nose', () {
      // Measured device logical ~880×1408 at DPR 1.5 from 1320×2112.
      final nav = resolveDriverViewportAnchorGeometry(
        hostIsTablet: true,
        viewportWidth: 880,
        viewportHeight: 1408,
        layoutBottomHudHeightPx: 188,
        safeTop: 24,
        safeBottom: 48,
      );
      final tellersPadFocal = Offset(
        (tellers.cameraPadding.left +
                (880 - tellers.cameraPadding.right)) /
            2,
        (tellers.cameraPadding.top +
                (1408 - tellers.cameraPadding.bottom)) /
            2,
      );
      expect(tellersPadFocal.dy, greaterThan(nav.cameraFocalScreenPoint.dy));
      final live = tellers.liveWindowRect;
      final gap = live.bottom - tellers.vehicleTailGlobal.dy;
      expect(gap, closeTo(22, 1.0));
    });
  });
}
