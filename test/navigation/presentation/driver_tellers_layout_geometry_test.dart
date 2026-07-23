// NAV-TELLERS-EXACT-LIVE-VIEWPORT-1

import 'dart:ui' show Offset, Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/navigation/nav_engine/nav_camera_view_mode.dart';
import 'package:fluxidi_tracking/navigation/presentation/driver_ride_meters.dart';
import 'package:fluxidi_tracking/navigation/presentation/driver_tellers_layout_geometry.dart';

void main() {
  group('DriverTellersLayoutGeometry', () {
    DriverTellersLayoutGeometry landscapeTablet() =>
        DriverTellersLayoutGeometry.resolve(
          viewportSize: const Size(1194, 834),
          safeTop: 0,
          safeBottom: 0,
          safeLeft: 0,
          safeRight: 0,
          isLandscape: true,
          isTablet: true,
        );

    DriverTellersLayoutGeometry portraitPhone() =>
        DriverTellersLayoutGeometry.resolve(
          viewportSize: const Size(390, 844),
          safeTop: 47,
          safeBottom: 34,
          safeLeft: 0,
          safeRight: 0,
          isLandscape: false,
          isTablet: false,
        );

    test('exactly one authoritative live-window rectangle exists', () {
      final g = landscapeTablet();
      expect(g.liveWindowRect.width, greaterThan(0));
      expect(g.liveWindowRect.height, greaterThan(0));
      expect(g.goldFrameEqualsLiveWindow, isTrue);
    });

    test('landscape left region is ~44%; right equals remaining space', () {
      final g = landscapeTablet();
      expect(
        g.landscapeLeftWidthFraction,
        closeTo(kTellersLandscapeLeftWidthFraction, 0.01),
      );
      // Live window starts after meters + gap and fills remaining width.
      expect(g.liveWindowRect.left, greaterThan(g.metersPanelRect.right));
      expect(
        g.liveWindowRect.right,
        closeTo(1194 - 20 /* hPad */, 0.5),
      );
      // No overlap between left chrome and live aperture.
      expect(g.metersPanelRect.overlaps(g.liveWindowRect), isFalse);
    });

    test('portrait top/bottom opaque regions leave a live middle band', () {
      final g = portraitPhone();
      expect(g.metersPanelRect.bottom, lessThanOrEqualTo(g.liveWindowRect.top));
      expect(
        g.liveWindowRect.bottom,
        lessThanOrEqualTo(g.controlsRect.top),
      );
      expect(g.metersPanelRect.overlaps(g.liveWindowRect), isFalse);
      expect(g.controlsRect.overlaps(g.liveWindowRect), isFalse);
      expect(g.liveWindowRect.height, greaterThanOrEqualTo(120));
    });

    test('label, selector and marker stay within liveWindowRect', () {
      for (final g in [landscapeTablet(), portraitPhone()]) {
        expect(g.liveWindowRect.contains(g.labelRect.center), isTrue);
        expect(g.liveWindowRect.contains(g.selectorRect.center), isTrue);
        expect(g.containsInLiveWindow(g.markerAnchor), isTrue);
        // Marker is lower-centre of the live window.
        expect(g.markerAnchor.dx, closeTo(g.liveWindowRect.center.dx, 0.5));
        expect(
          g.markerAnchor.dy,
          closeTo(
            g.liveWindowRect.top +
                g.liveWindowRect.height * kTellersMarkerAnchorYFraction,
            0.5,
          ),
        );
      }
    });

    test('camera padding derives from the same liveWindowRect', () {
      final g = landscapeTablet();
      final pad = g.cameraPadding;
      expect(
        pad.left,
        closeTo(g.liveWindowRect.left + kTellersLiveWindowCameraInnerInset, 0.5),
      );
      expect(
        pad.right,
        closeTo(
          g.viewportSize.width -
              g.liveWindowRect.right +
              kTellersLiveWindowCameraInnerInset,
          0.5,
        ),
      );
      // Public helper matches the geometry (single source of truth).
      final viaHelper = driverTellersLiveWindowCameraPadding(
        screenWidth: 1194,
        screenHeight: 834,
        isLandscape: true,
        isTablet: true,
        safeTop: 0,
        safeBottom: 0,
      );
      expect(viaHelper.left, closeTo(pad.left, 0.01));
      expect(viaHelper.top, closeTo(pad.top, 0.01));
      expect(viaHelper.right, closeTo(pad.right, 0.01));
      expect(viaHelper.bottom, closeTo(pad.bottom, 0.01));
    });

    test('camera screen anchor is normalised marker position', () {
      final g = portraitPhone();
      expect(
        g.cameraScreenAnchor.dx,
        closeTo(g.markerAnchor.dx / g.viewportSize.width, 0.001),
      );
      expect(
        g.cameraScreenAnchor.dy,
        closeTo(g.markerAnchor.dy / g.viewportSize.height, 0.001),
      );
      // Not the full-display centre when Tellers reserves top/bottom chrome.
      expect(g.cameraScreenAnchor.dy, isNot(closeTo(0.5, 0.05)));
    });

    test('opaque chrome slabs leave only the live aperture uncovered', () {
      final g = landscapeTablet();
      final chrome = driverTellersOpaqueChromeRects(g);
      expect(chrome, hasLength(4));
      // Sample points: outside live → covered by a chrome slab; inside → not.
      final outside = Offset(g.metersPanelRect.center.dx, g.metersPanelRect.center.dy);
      final inside = g.liveWindowRect.center;
      expect(chrome.any((r) => r.contains(outside)), isTrue);
      expect(chrome.any((r) => r.contains(inside)), isFalse);
    });

    test('corner bleed blockers sit on live-window corners', () {
      final g = landscapeTablet();
      final blockers = driverTellersCornerBleedBlockers(g);
      expect(blockers, hasLength(4));
      for (final b in blockers) {
        expect(g.liveWindowRect.contains(b.center), isTrue);
      }
    });

    test('portrait ↔ landscape recalculates geometry deterministically', () {
      final portrait = DriverTellersLayoutGeometry.resolve(
        viewportSize: const Size(834, 1194),
        safeTop: 24,
        safeBottom: 16,
        safeLeft: 0,
        safeRight: 0,
        isLandscape: false,
        isTablet: true,
      );
      final landscape = DriverTellersLayoutGeometry.resolve(
        viewportSize: const Size(1194, 834),
        safeTop: 0,
        safeBottom: 0,
        safeLeft: 0,
        safeRight: 0,
        isLandscape: true,
        isTablet: true,
      );
      expect(portrait.isLandscape, isFalse);
      expect(landscape.isLandscape, isTrue);
      expect(portrait.liveWindowRect, isNot(landscape.liveWindowRect));
      // Re-resolve is stable (idempotent for the same inputs).
      final again = DriverTellersLayoutGeometry.resolve(
        viewportSize: const Size(1194, 834),
        safeTop: 0,
        safeBottom: 0,
        safeLeft: 0,
        safeRight: 0,
        isLandscape: true,
        isTablet: true,
      );
      expect(again.liveWindowRect, landscape.liveWindowRect);
      expect(again.cameraPadding.left, landscape.cameraPadding.left);
    });

    test('recenter contract uses the same geometry (View/Tellers preserved)', () {
      const contract = DriverTellersRecenterContract(
        viewLevelBefore: 6,
        tellersActiveBefore: true,
      );
      expect(contract.preservesViewLevel, isTrue);
      expect(contract.staysInTellers, isTrue);
      expect(contract.usesExistingCameraOwner, isTrue);
      final g = landscapeTablet();
      // Centreren places the marker at the geometry anchor inside the aperture.
      expect(g.containsInLiveWindow(g.markerAnchor), isTrue);
    });

    test('Live navigatie label is localized (NL preserved)', () {
      expect(
        driverTellersLiveNavigationLabel(AppLanguage.nl),
        'Live navigatie',
      );
      expect(
        driverTellersLiveNavigationLabel(AppLanguage.en),
        'Live navigation',
      );
    });
  });
}
