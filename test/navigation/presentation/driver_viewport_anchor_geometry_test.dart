// FLUXIDI-VEHICLE-CAMERA-VIEWPORT-ANCHOR-P0
//
// Pure geometry: painted HUD nose and camera focal must share one host-aware
// model across fullscreen, vertical split, horizontal split, and restore.

import 'package:flutter/painting.dart' show Size;
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/navigation/driver_navigation_map_config.dart';
import 'package:fluxidi_tracking/navigation/presentation/driver_viewport_anchor_geometry.dart';
import 'package:fluxidi_tracking/navigation/presentation/navigation_driver_cockpit_camera.dart';
import 'package:fluxidi_tracking/navigation/presentation/navigation_driver_marker_scale.dart';
import 'package:fluxidi_tracking/navigation/widgets/navigation_driver_hud_overlay.dart';

void main() {
  const tabletFull = (w: 800.0, h: 1280.0);
  const tabletVertical = (w: 400.0, h: 1280.0);
  const tabletHorizontal = (w: 800.0, h: 400.0);
  const phone = (w: 390.0, h: 844.0);

  /// Representative Street Level KPI bottom + safe bottom on portrait tablet.
  const layoutBottomPortrait = 220.0;
  const layoutBottomLandscape = 140.0;
  const safeTop = 24.0;
  const safeBottom = 0.0;

  DriverViewportAnchorGeometry anchor({
    required bool hostIsTablet,
    required double w,
    required double h,
    double? layoutBottom,
  }) {
    final landscape = w > h;
    return resolveDriverViewportAnchorGeometry(
      hostIsTablet: hostIsTablet,
      viewportWidth: w,
      viewportHeight: h,
      layoutBottomHudHeightPx:
          layoutBottom ??
          (landscape ? layoutBottomLandscape : layoutBottomPortrait),
      safeTop: safeTop,
      safeBottom: safeBottom,
    );
  }

  group('TEST A — fullscreen tablet', () {
    test('HUD and camera both 132; nose == focal', () {
      final g = anchor(
        hostIsTablet: true,
        w: tabletFull.w,
        h: tabletFull.h,
      );
      expect(g.vehicleIconSize, kDriverCockpitPro2HudTabletL7);
      expect(g.vehicleIconSize, 132);
      expect(g.isAligned(tolerancePx: 1.0), isTrue);
      expect(g.deltaX.abs(), lessThan(1.0));
      expect(g.deltaY.abs(), lessThan(1.0));
    });
  });

  group('TEST B — vertical split tablet host', () {
    test('painted HUD stays 132 (not phone 94); nose == focal', () {
      final g = anchor(
        hostIsTablet: true,
        w: tabletVertical.w,
        h: tabletVertical.h,
      );
      expect(g.vehicleIconSize, 132);
      expect(g.vehicleIconSize, isNot(kDriverCockpitPro2HudPhoneL7));
      // Window-only classifier would wrongly pick phone on ss=400.
      expect(
        driverNavigationIsTabletDevice(
          const Size(400, 1280),
        ),
        isFalse,
      );
      expect(
        NavigationDriverHudOverlay.resolveIconSize(
          screenWidth: tabletVertical.w,
          screenHeight: tabletVertical.h,
          cockpitBoost: true,
          hostIsTablet: true,
        ),
        132,
      );
      expect(g.isAligned(tolerancePx: 1.0), isTrue);
      expect(g.deltaX.abs(), lessThan(1.0));
      expect(g.deltaY.abs(), lessThan(1.0));
    });
  });

  group('TEST C — horizontal split', () {
    test('shared clamped anchor; nose == focal', () {
      final g = anchor(
        hostIsTablet: true,
        w: tabletHorizontal.w,
        h: tabletHorizontal.h,
        layoutBottom: 120.0,
      );
      expect(g.vehicleIconSize, 132);
      expect(g.isAligned(tolerancePx: 1.0), isTrue);
      // Paint bottom and camera padding both derived from final clamped fraction.
      expect(
        g.vehicleNoseScreenPoint.dy,
        closeTo(g.anchorFraction * tabletHorizontal.h, 1.0),
      );
      expect(
        g.cameraFocalScreenPoint.dy,
        closeTo(g.anchorFraction * tabletHorizontal.h, 1.0),
      );
    });
  });

  group('TEST D — multiple divider positions', () {
    test('no divergence across pane sizes', () {
      const panes = <(double, double)>[
        (380, 1280),
        (420, 1280),
        (500, 1280),
        (800, 500),
        (800, 400),
      ];
      for (final (w, h) in panes) {
        final g = anchor(hostIsTablet: true, w: w, h: h);
        expect(g.vehicleIconSize, 132, reason: '${w}x$h size');
        expect(g.isAligned(tolerancePx: 1.0), isTrue, reason: '${w}x$h align');
        expect(g.deltaX.abs(), lessThan(1.0), reason: '${w}x$h dx');
        expect(g.deltaY.abs(), lessThan(1.0), reason: '${w}x$h dy');
      }
    });
  });

  group('TEST E — restore sequence', () {
    test('fullscreen → vertical → horizontal → fullscreen restores anchor', () {
      final full1 = anchor(
        hostIsTablet: true,
        w: tabletFull.w,
        h: tabletFull.h,
      );
      final vertical = anchor(
        hostIsTablet: true,
        w: tabletVertical.w,
        h: tabletVertical.h,
      );
      final horizontal = anchor(
        hostIsTablet: true,
        w: tabletHorizontal.w,
        h: tabletHorizontal.h,
      );
      final full2 = anchor(
        hostIsTablet: true,
        w: tabletFull.w,
        h: tabletFull.h,
      );
      expect(vertical.isAligned(), isTrue);
      expect(horizontal.isAligned(), isTrue);
      expect(full2.vehicleIconSize, full1.vehicleIconSize);
      expect(
        full2.anchorFraction,
        closeTo(full1.anchorFraction, 1e-9),
      );
      expect(
        full2.vehicleNoseScreenPoint.dy,
        closeTo(full1.vehicleNoseScreenPoint.dy, 1e-6),
      );
      expect(
        full2.cameraFocalScreenPoint.dy,
        closeTo(full1.cameraFocalScreenPoint.dy, 1e-6),
      );
    });
  });

  group('TEST F — phone host', () {
    test('stays 94; never promoted by wide window alone', () {
      final g = anchor(hostIsTablet: false, w: phone.w, h: phone.h);
      expect(g.vehicleIconSize, kDriverCockpitPro2HudPhoneL7);
      expect(g.vehicleIconSize, 94);
      expect(g.isAligned(tolerancePx: 1.0), isTrue);

      // Wide landscape phone window must not become tablet when host says phone.
      final widePhone = resolveDriverViewportAnchorGeometry(
        hostIsTablet: false,
        viewportWidth: 900,
        viewportHeight: 390,
        layoutBottomHudHeightPx: layoutBottomLandscape,
        safeTop: safeTop,
        safeBottom: safeBottom,
      );
      expect(widePhone.vehicleIconSize, 94);
      expect(widePhone.isAligned(tolerancePx: 1.0), isTrue);
    });
  });

  group('TEST G — style-independent geometry', () {
    test('anchor invariant is style-agnostic; L7 zoom/pitch unchanged', () {
      final g = anchor(
        hostIsTablet: true,
        w: tabletVertical.w,
        h: tabletVertical.h,
      );
      expect(g.isAligned(), isTrue);

      for (final style in const [
        DriverCockpitMapVisualStyle.light,
        DriverCockpitMapVisualStyle.dark,
        DriverCockpitMapVisualStyle.satellite,
        DriverCockpitMapVisualStyle.standard3d,
      ]) {
        final t = resolveDriverCockpitStreetlevelL7Targets(
          isTablet: true,
          isLandscape: false,
          mapVisualStyle: style,
        );
        if (style == DriverCockpitMapVisualStyle.standard3d) {
          expect(t.zoom, 18.4, reason: style.name);
          expect(t.pitch, 75.0, reason: style.name);
        } else {
          expect(t.zoom, 17.0, reason: style.name);
          expect(t.pitch, 62.0, reason: style.name);
        }
      }
    });
  });

  group('shared clamp reconciliation', () {
    test('when clamp binds, paint bottom moves to match focal', () {
      // Force a short pane where raw nose fraction is below tablet min 0.50.
      final g = resolveDriverViewportAnchorGeometry(
        hostIsTablet: true,
        viewportWidth: 800,
        viewportHeight: 360,
        layoutBottomHudHeightPx: 200,
        safeTop: 0,
        safeBottom: 0,
      );
      expect(g.anchorClamped, isTrue);
      expect(g.anchorFraction, greaterThanOrEqualTo(0.50));
      expect(g.isAligned(tolerancePx: 1.0), isTrue);
      expect(
        (g.bottomHudHeightPx - g.layoutBottomHudHeightPx).abs(),
        greaterThan(0.5),
      );
    });
  });
}
