// NAV-TELLERS-EXACT-LIVE-VIEWPORT-1
// NAV-TELLERS-ROTATION-COMPOSITION-AND-POSE-LOCK-1

import 'dart:ui' show Offset, Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_strings.dart';
// driver_ride_meters re-exports driver_tellers_layout_geometry (all symbols).
import 'package:fluxidi_tracking/navigation/presentation/driver_ride_meters.dart';

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

    test('camera padding focal point lands exactly on the marker anchor', () {
      // NAV-TELLERS-POSE-ANCHOR-AND-DIAGNOSTICS-UI-1: the padding must place the
      // Mapbox camera `center` on the marker anchor (lower-centre), NOT the
      // live-window middle. Prove focal == markerAnchor == cameraTargetAnchor.
      for (final g in [landscapeTablet(), portraitPhone()]) {
        expect(g.cameraPaddingFocalPoint.dx, closeTo(g.markerAnchor.dx, 0.01));
        expect(g.cameraPaddingFocalPoint.dy, closeTo(g.markerAnchor.dy, 0.01));
        expect(
          g.cameraTargetAnchorGlobal.dx,
          closeTo(g.markerAnchorGlobal.dx, 0.001),
        );
        expect(
          g.cameraTargetAnchorGlobal.dy,
          closeTo(g.markerAnchorGlobal.dy, 0.001),
        );
        // All four insets remain valid (non-negative, on-screen).
        expect(g.cameraPadding.left, greaterThanOrEqualTo(0));
        expect(g.cameraPadding.right, greaterThanOrEqualTo(0));
        expect(g.cameraPadding.top, greaterThanOrEqualTo(0));
        expect(g.cameraPadding.bottom, greaterThanOrEqualTo(0));
        expect(
          g.cameraPadding.left + g.cameraPadding.right,
          lessThan(g.viewportSize.width),
        );
        expect(
          g.cameraPadding.top + g.cameraPadding.bottom,
          lessThan(g.viewportSize.height),
        );
      }
    });

    test('focal point is below the live-window centre (marker Y fraction)', () {
      // Regression guard for the field bug: the old padding centred the pose at
      // the live-window middle; the fixed padding must sit ~0.775 down instead.
      final g = portraitPhone();
      expect(
        g.cameraPaddingFocalPoint.dy,
        greaterThan(g.liveWindowRect.center.dy),
      );
    });

    test('public helper matches the geometry (single source of truth)', () {
      final g = landscapeTablet();
      final pad = g.cameraPadding;
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

    test('global geometry values are unambiguous and self-consistent', () {
      for (final g in [landscapeTablet(), portraitPhone()]) {
        expect(g.liveWindowRectGlobal, g.liveWindowRect);
        expect(g.mapViewportSize, g.viewportSize);
        expect(g.markerAnchorGlobal, g.markerAnchor);
        // Marker anchor lies inside the live aperture (never off-map).
        expect(g.containsInLiveWindow(g.markerAnchorGlobal), isTrue);
      }
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

  group('NAV-TELLERS-POSE-ANCHOR-AND-DIAGNOSTICS-UI-1 anchor math', () {
    // All four driver form factors: the focal point solved from cameraPadding
    // must coincide with the marker anchor (project(pose) == marker) and the
    // local→global conversion must happen exactly once (values already global).
    final cases = <String, DriverTellersLayoutGeometry>{
      'phone portrait': DriverTellersLayoutGeometry.resolve(
        viewportSize: const Size(390, 844),
        safeTop: 47,
        safeBottom: 34,
        safeLeft: 0,
        safeRight: 0,
        isLandscape: false,
        isTablet: false,
      ),
      'phone landscape': DriverTellersLayoutGeometry.resolve(
        viewportSize: const Size(844, 390),
        safeTop: 0,
        safeBottom: 0,
        safeLeft: 47,
        safeRight: 34,
        isLandscape: true,
        isTablet: false,
      ),
      'tablet portrait': DriverTellersLayoutGeometry.resolve(
        viewportSize: const Size(834, 1194),
        safeTop: 24,
        safeBottom: 16,
        safeLeft: 0,
        safeRight: 0,
        isLandscape: false,
        isTablet: true,
      ),
      'tablet landscape': DriverTellersLayoutGeometry.resolve(
        viewportSize: const Size(1194, 834),
        safeTop: 0,
        safeBottom: 0,
        safeLeft: 0,
        safeRight: 0,
        isLandscape: true,
        isTablet: true,
      ),
    };

    cases.forEach((name, g) {
      test('$name: focal point == marker anchor', () {
        expect(g.cameraPaddingFocalPoint.dx, closeTo(g.markerAnchor.dx, 0.02));
        expect(g.cameraPaddingFocalPoint.dy, closeTo(g.markerAnchor.dy, 0.02));
        // Padding stays valid (logical px, non-negative, on-screen).
        expect(g.cameraPadding.left, greaterThanOrEqualTo(0));
        expect(g.cameraPadding.right, greaterThanOrEqualTo(0));
        expect(g.cameraPadding.top, greaterThanOrEqualTo(0));
        expect(g.cameraPadding.bottom, greaterThanOrEqualTo(0));
      });
    });

    test('orientation flip recomputes the anchor exactly once and differs', () {
      final port = cases['tablet portrait']!;
      final land = cases['tablet landscape']!;
      expect(port.markerAnchorGlobal, isNot(land.markerAnchorGlobal));
      // Idempotent: re-resolving the same inputs yields the same anchor.
      final again = DriverTellersLayoutGeometry.resolve(
        viewportSize: const Size(834, 1194),
        safeTop: 24,
        safeBottom: 16,
        safeLeft: 0,
        safeRight: 0,
        isLandscape: false,
        isTablet: true,
      );
      expect(again.markerAnchorGlobal, port.markerAnchorGlobal);
      expect(again.cameraTargetAnchorGlobal, port.cameraTargetAnchorGlobal);
    });

    test('aligned diagnostic reports aligned when pose projects on marker', () {
      final g = cases['tablet portrait']!;
      final line = formatNavTellersAnchorDiagnostic(
        viewportGeneration: 3,
        isLandscape: g.isLandscape,
        markerAnchor: g.markerAnchorGlobal,
        projectedPose: g.markerAnchorGlobal, // perfect projection
        viewportSize: g.mapViewportSize,
      );
      expect(line, contains('gen=3'));
      expect(line, contains('orient=port'));
      expect(line, contains('aligned=true'));
      expect(line, contains('dx=le6'));
      expect(line, contains('dy=le6'));
    });

    test('diagnostic reports misalignment with bounded PII-free buckets', () {
      final g = cases['tablet portrait']!;
      final line = formatNavTellersAnchorDiagnostic(
        viewportGeneration: 1,
        isLandscape: g.isLandscape,
        markerAnchor: g.markerAnchorGlobal,
        // Simulate the OLD bug: pose projected ~190px above the marker.
        projectedPose: g.markerAnchorGlobal - const Offset(0, 190),
        viewportSize: g.mapViewportSize,
      );
      expect(line, contains('aligned=false'));
      expect(line, contains('dy=ngt96'));
      // Never leaks raw coordinates.
      expect(line, isNot(contains('.')));
    });

    test('delta and position buckets are coarse and bounded', () {
      expect(navTellersAnchorDeltaBucket(0), 'le6');
      expect(navTellersAnchorDeltaBucket(6), 'le6');
      expect(navTellersAnchorDeltaBucket(10), 'p7_16');
      expect(navTellersAnchorDeltaBucket(-10), 'n7_16');
      expect(navTellersAnchorDeltaBucket(500), 'pgt96');
      expect(navTellersAnchorPositionBucket(0.1), 'lo');
      expect(navTellersAnchorPositionBucket(0.5), 'mid');
      expect(navTellersAnchorPositionBucket(0.9), 'hi');
      expect(navTellersAnchorAligned(deltaX: 3, deltaY: 4), isTrue);
      expect(navTellersAnchorAligned(deltaX: 3, deltaY: 40), isFalse);
    });
  });

  // ==========================================================================
  // COMMIT 1 — opaque + atomic geometry switch
  // ==========================================================================
  group('NAV-TELLERS-ROTATION Commit 1: validity + atomic geometry', () {
    DriverTellersLayoutGeometry resolve(Size size, {bool landscape = false}) =>
        DriverTellersLayoutGeometry.resolve(
          viewportSize: size,
          safeTop: 0,
          safeBottom: 0,
          safeLeft: 0,
          safeRight: 0,
          isLandscape: landscape,
          isTablet: false,
        );

    test('valid geometry is reported valid; the aperture is within the view',
        () {
      final g = resolve(const Size(390, 844));
      expect(g.isValid, isTrue);
      final live = g.liveWindowRect;
      expect(live.left, greaterThanOrEqualTo(-0.5));
      expect(live.top, greaterThanOrEqualTo(-0.5));
      expect(live.right, lessThanOrEqualTo(390 + 0.5));
      expect(live.bottom, lessThanOrEqualTo(844 + 0.5));
    });

    test('zero / degenerate viewport sizes are rejected', () {
      expect(resolve(const Size(0, 0)).isValid, isFalse);
      expect(resolve(const Size(390, 0)).isValid, isFalse);
      expect(resolve(const Size(0, 844)).isValid, isFalse);
      expect(resolve(const Size(-10, -10)).isValid, isFalse);
    });

    test('resolve never throws on a tiny transitional viewport (clamp guard)',
        () {
      // Before the clamp guard, a small contentH made maxTop < 220 and
      // preferred.clamp(220, maxTop) threw during a rotation frame.
      for (final size in const <Size>[
        Size(390, 120),
        Size(390, 200),
        Size(390, 260),
        Size(120, 390),
      ]) {
        expect(() => resolve(size), returnsNormally);
      }
    });

    test('latch retains the last VALID geometry across an invalid frame', () {
      final latch = DriverTellersGeometryLatch();
      final portrait = resolve(const Size(390, 844));
      final committed = latch.commit(portrait);
      expect(committed.liveWindowRect, portrait.liveWindowRect);
      expect(latch.generation, 1);

      // A transitional (invalid) frame must NOT replace the committed geometry.
      final invalid = resolve(const Size(390, 0));
      final retained = latch.commit(invalid);
      expect(retained.liveWindowRect, portrait.liveWindowRect);
      expect(latch.lastValid!.liveWindowRect, portrait.liveWindowRect);
      expect(latch.generation, 1, reason: 'no bump on rejected frame');
    });

    test('portrait geometry is retained until valid landscape commits', () {
      final latch = DriverTellersGeometryLatch();
      final portrait = latch.commit(resolve(const Size(390, 844)));
      // Invalid intermediate frames during the resize.
      latch.commit(resolve(const Size(844, 0)));
      latch.commit(resolve(const Size(0, 390)));
      expect(latch.lastValid!.liveWindowRect, portrait.liveWindowRect);
      // Valid landscape arrives → one atomic commit, generation bumps once.
      final landscape = latch.commit(resolve(const Size(844, 390),
          landscape: true));
      expect(landscape.isLandscape, isTrue);
      expect(latch.generation, 2);
      expect(landscape.liveWindowRect, isNot(portrait.liveWindowRect));
    });

    test('re-committing the same layout does not bump the generation', () {
      final latch = DriverTellersGeometryLatch();
      latch.commit(resolve(const Size(390, 844)));
      latch.commit(resolve(const Size(390, 844)));
      latch.commit(resolve(const Size(390, 844)));
      expect(latch.generation, 1);
    });

    test('opaque map backdrop is fully opaque (never shows the route below)',
        () {
      expect(kFluxidiMapBackdrop.alpha, 0xFF);
    });

    test('chrome + corner blockers cover every region outside the aperture',
        () {
      final g = resolve(const Size(390, 844));
      final chrome = driverTellersOpaqueChromeRects(g);
      final live = g.liveWindowRect;
      // Sample a grid; every point outside the live window must be covered by
      // an opaque chrome slab (nothing beneath the map can leak there).
      for (var x = 4.0; x < 390; x += 32) {
        for (var y = 4.0; y < 844; y += 48) {
          final p = Offset(x, y);
          if (live.contains(p)) continue;
          expect(
            chrome.any((r) => r.contains(p)),
            isTrue,
            reason: 'point $p outside live window must be opaque',
          );
        }
      }
    });
  });

}
