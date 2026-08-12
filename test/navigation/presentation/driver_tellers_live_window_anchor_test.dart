// FLUXIDI-TELLERS-LIVE-MAP-FORWARD-VISIBILITY
//
// Tellers-only: vehicle nose / Mapbox focal resolve from the realized
// liveWindowRect (~72% height), not the full Navigatie viewport. Ordinary
// Navigation geometry must stay byte-stable.

import 'dart:ui' show Rect, Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/navigation/presentation/driver_tellers_layout_geometry.dart';
import 'package:fluxidi_tracking/navigation/presentation/driver_viewport_anchor_geometry.dart';
import 'package:fluxidi_tracking/navigation/presentation/navigation_driver_cockpit_camera.dart';

DriverTellersLayoutGeometry _tabletPortrait({
  Size size = const Size(800, 1280),
  double safeTop = 24,
  double safeBottom = 24,
}) {
  return DriverTellersLayoutGeometry.resolve(
    viewportSize: size,
    safeTop: safeTop,
    safeBottom: safeBottom,
    safeLeft: 0,
    safeRight: 0,
    isLandscape: false,
    isTablet: true,
  );
}

DriverTellersLayoutGeometry _tabletLandscape({
  Size size = const Size(1280, 800),
  double safeTop = 24,
  double safeBottom = 24,
}) {
  return DriverTellersLayoutGeometry.resolve(
    viewportSize: size,
    safeTop: safeTop,
    safeBottom: safeBottom,
    safeLeft: 0,
    safeRight: 0,
    isLandscape: true,
    isTablet: true,
  );
}

void main() {
  group('FLUXIDI-TELLERS-LIVE-MAP-FORWARD-VISIBILITY', () {
    test(
      'ordinary Navigation viewport geometry is unchanged (Tellers inactive)',
      () {
        final nav = resolveDriverViewportAnchorGeometry(
          hostIsTablet: true,
          viewportWidth: 800,
          viewportHeight: 1280,
          layoutBottomHudHeightPx: 188,
          safeTop: 24,
          safeBottom: 24,
        );
        expect(nav.vehicleIconSize, 132);
        expect(nav.isAligned(), isTrue);
        // Stable tablet cockpit band — not liveWindow-relative.
        expect(nav.anchorFraction, greaterThan(0.45));
        expect(nav.anchorFraction, lessThan(0.90));
      },
    );

    test('Tellers geometry is based on liveWindowRect, not full page mid', () {
      final g = _tabletPortrait();
      final liveMidY = g.liveWindowRect.center.dy;
      expect(g.markerAnchor.dy, greaterThan(liveMidY + 20));
      expect(
        g.markerAnchor.dy,
        closeTo(
          g.liveWindowRect.top +
              g.liveWindowRect.height * g.realizedNoseFractionInLive,
          0.5,
        ),
      );
    });

    test('unclamped tablet nose is ~72% of usable live window height', () {
      final g = _tabletPortrait();
      expect(g.requestedNoseFractionInLive, 0.72);
      expect(g.noseFractionClamped, isFalse);
      expect(g.realizedNoseFractionInLive, closeTo(0.72, 0.01));
      expect(g.vehicleIconSize, 132);
    });

    test('HUD nose and Mapbox focal resolve to the same global point', () {
      for (final g in <DriverTellersLayoutGeometry>[
        _tabletPortrait(),
        _tabletLandscape(),
        _tabletPortrait(size: const Size(436, 1360)),
        _tabletLandscape(size: const Size(880, 676)),
      ]) {
        expect(g.cameraPaddingFocalPoint.dx, closeTo(g.markerAnchor.dx, 0.5));
        expect(g.cameraPaddingFocalPoint.dy, closeTo(g.markerAnchor.dy, 0.5));
        final anchor = resolveTellersLiveWindowVehicleAnchor(
          liveWindowRect: g.liveWindowRect,
          viewportSize: g.viewportSize,
          isTablet: g.isTablet,
        );
        expect(anchor.noseMatchesFocal, isTrue);
        expect(anchor.vehicleNoseGlobal, g.markerAnchor);
      }
    });

    test('vehicle tail remains inside the live window with bottom margin', () {
      for (final g in <DriverTellersLayoutGeometry>[
        _tabletPortrait(),
        _tabletLandscape(),
      ]) {
        expect(
          g.vehicleTailGlobal.dy,
          lessThanOrEqualTo(g.liveWindowRect.bottom),
        );
        expect(
          g.vehicleTailGlobal.dy,
          lessThanOrEqualTo(
            g.liveWindowRect.bottom -
                kTellersLiveWindowVehicleBottomMarginPx +
                0.5,
          ),
        );
        expect(g.containsInLiveWindow(g.markerAnchor), isTrue);
      }
    });

    test('horizontal split pane recalculates from its liveWindowRect', () {
      final full = _tabletLandscape(size: const Size(1280, 800));
      final split = _tabletLandscape(size: const Size(880, 676));
      expect(split.liveWindowRect.height, isNot(full.liveWindowRect.height));
      // Short landscape panes may clamp below 0.72 so the 132 px tail fits.
      expect(split.requestedNoseFractionInLive, 0.72);
      expect(
        split.realizedNoseFractionInLive,
        lessThanOrEqualTo(split.requestedNoseFractionInLive + 1e-9),
      );
      expect(
        split.markerAnchor.dy,
        closeTo(
          split.liveWindowRect.top +
              split.liveWindowRect.height * split.realizedNoseFractionInLive,
          0.5,
        ),
      );
      expect(split.cameraPaddingFocalPoint, split.markerAnchor);
      expect(
        split.vehicleTailGlobal.dy,
        lessThanOrEqualTo(
          split.liveWindowRect.bottom -
              kTellersLiveWindowVehicleBottomMarginPx +
              0.5,
        ),
      );
    });

    test('vertical split pane recalculates from its liveWindowRect', () {
      final full = _tabletPortrait(size: const Size(800, 1280));
      final split = _tabletPortrait(size: const Size(436, 1360));
      expect(split.liveWindowRect.width, lessThan(full.liveWindowRect.width));
      expect(split.realizedNoseFractionInLive, closeTo(0.72, 0.02));
      expect(split.vehicleIconSize, 132);
    });

    test('divider resize: last liveWindow wins nose/focal (epoch-style)', () {
      final a = _tabletPortrait(size: const Size(800, 1280));
      final b = _tabletPortrait(size: const Size(700, 1100));
      final c = _tabletPortrait(size: const Size(800, 1280));
      // Latest resolve is authoritative — A and C match; B differs.
      expect(a.markerAnchor, c.markerAnchor);
      expect(b.markerAnchor, isNot(a.markerAnchor));
      expect(c.cameraPaddingFocalPoint, c.markerAnchor);
    });

    test(
      'closing Tellers restores ordinary Navigation anchor model exactly',
      () {
        final tellers = _tabletPortrait();
        final nav = resolveDriverViewportAnchorGeometry(
          hostIsTablet: true,
          viewportWidth: 800,
          viewportHeight: 1280,
          layoutBottomHudHeightPx: 188,
          safeTop: 24,
          safeBottom: 24,
        );
        // Different presentation geometry spaces — Tellers must not equal nav.
        expect(
          tellers.markerAnchor.dy,
          isNot(closeTo(nav.vehicleNoseScreenPoint.dy, 1)),
        );
        // Ordinary model remains self-aligned for Navigatie restore.
        expect(nav.isAligned(), isTrue);
        expect(nav.vehicleIconSize, 132);
      },
    );

    test('Tellers vehicle anchor does not alter geographic pose selection', () {
      const visual = TellersAuthoritativePoseInput(
        visualLat: 50.77,
        visualLon: 3.66,
        snappedLat: 50.7701,
        snappedLon: 3.6602,
        hasReliableMatchedSnap: true,
        trustRouteSnap: true,
        offRouteLikely: false,
      );
      final before = resolveTellersAuthoritativePose(visual);
      // Screen geometry resolve has no geo side effects.
      resolveTellersLiveWindowVehicleAnchor(
        liveWindowRect: const Rect.fromLTWH(40, 300, 720, 500),
        viewportSize: const Size(800, 1280),
        isTablet: true,
      );
      final after = resolveTellersAuthoritativePose(visual);
      expect(after.lat, before.lat);
      expect(after.lon, before.lon);
      expect(after.source, TellersAuthoritativePoseSource.snappedRoute);
    });

    test('short live window clamps nose so tail stays inside', () {
      final live = const Rect.fromLTWH(20, 40, 200, 160);
      final anchor = resolveTellersLiveWindowVehicleAnchor(
        liveWindowRect: live,
        viewportSize: const Size(240, 400),
        isTablet: true,
      );
      expect(anchor.noseClamped, isTrue);
      expect(anchor.realizedNoseFractionInLive, lessThan(0.72));
      expect(
        anchor.vehicleTailGlobal.dy,
        lessThanOrEqualTo(
          live.bottom - kTellersLiveWindowVehicleBottomMarginPx + 0.5,
        ),
      );
    });

    test('phone Tellers keeps 94 px vehicle; tablet keeps 132', () {
      final phone = resolveTellersLiveWindowVehicleAnchor(
        liveWindowRect: const Rect.fromLTWH(12, 200, 366, 420),
        viewportSize: const Size(390, 844),
        isTablet: false,
      );
      final tablet = resolveTellersLiveWindowVehicleAnchor(
        liveWindowRect: const Rect.fromLTWH(20, 320, 760, 640),
        viewportSize: const Size(800, 1280),
        isTablet: true,
      );
      expect(phone.vehicleIconSize, 94);
      expect(tablet.vehicleIconSize, 132);
    });

    test('diagnostic line is bounded and includes requested vs realized', () {
      final g = _tabletPortrait();
      final line = formatNavTellersLiveWindowGeometryDiagnostic(
        reason: 'enter',
        viewportEpoch: 3,
        viewportGeneration: 7,
        tellersActive: true,
        anchor: resolveTellersLiveWindowVehicleAnchor(
          liveWindowRect: g.liveWindowRect,
          viewportSize: g.viewportSize,
          isTablet: true,
        ),
        mapWidgetGeneration: 1,
      );
      expect(line, contains('reason=enter'));
      expect(line, contains('tellers=1'));
      expect(line, contains('reqNose=0.720'));
      expect(line, contains('realNose='));
      expect(line, contains('mapGen=1'));
      expect(line, isNot(contains('50.77')));
    });

    test('centre and tail derive from existing HUD nose/tail fractions', () {
      final g = _tabletPortrait();
      final nose = g.markerAnchor.dy;
      final top =
          nose - g.vehicleIconSize * kDriverHudVehicleNoseFractionFromTop;
      expect(
        g.vehicleCenterGlobal.dy,
        closeTo(top + g.vehicleIconSize / 2, 0.5),
      );
      expect(
        g.vehicleTailGlobal.dy,
        closeTo(
          top + g.vehicleIconSize * kDriverHudVehicleTailFractionFromTop,
          0.5,
        ),
      );
    });
  });
}
