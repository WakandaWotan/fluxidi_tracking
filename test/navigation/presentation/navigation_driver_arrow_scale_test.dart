import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/navigation/presentation/navigation_driver_arrow_scale.dart';
import 'package:fluxidi_tracking/navigation/presentation/navigation_driver_marker_choice.dart';
import 'package:fluxidi_tracking/navigation/presentation/navigation_presentation_mode.dart';
import 'package:fluxidi_tracking/navigation/presentation/navigation_streetlevel_marker_anchor.dart';
import 'package:fluxidi_tracking/navigation/widgets/navigation_driver_arrow_marker.dart';
import 'package:fluxidi_tracking/navigation/widgets/navigation_driver_hud_overlay.dart';

void main() {
  group('NAV-MARKER-ARROW-RESPONSIVE-SCALE-1 resolver', () {
    test('1. phone portrait uses a smaller scale (~0.82–0.85)', () {
      final scale = resolveDriverNavigationArrowScale(
        viewportWidth: 390,
        viewportHeight: 844,
        isTablet: false,
        orientation: Orientation.portrait,
        presentationMode: NavigationPresentationMode.driver,
      );
      expect(scale, kDriverNavArrowScalePhonePortrait);
      expect(scale, inInclusiveRange(0.82, 0.85));
      expect(scale, lessThan(1.0));
    });

    test('2. phone landscape uses a smaller scale (~0.78–0.84)', () {
      final scale = resolveDriverNavigationArrowScale(
        viewportWidth: 844,
        viewportHeight: 390,
        isTablet: false,
        orientation: Orientation.landscape,
        presentationMode: NavigationPresentationMode.driver,
      );
      expect(scale, kDriverNavArrowScalePhoneLandscape);
      expect(scale, inInclusiveRange(0.78, 0.84));
      expect(scale, lessThan(1.0));
    });

    test('2b. compact phone landscape uses the lower end of the band', () {
      final scale = resolveDriverNavigationArrowScale(
        viewportWidth: 640,
        viewportHeight: 320,
        isTablet: false,
        orientation: Orientation.landscape,
        presentationMode: NavigationPresentationMode.driver,
      );
      expect(scale, kDriverNavArrowScalePhoneLandscapeCompact);
      expect(scale, inInclusiveRange(0.78, 0.84));
    });

    test('3. tablet portrait keeps the large scale (1.0)', () {
      final scale = resolveDriverNavigationArrowScale(
        viewportWidth: 834,
        viewportHeight: 1112,
        isTablet: true,
        orientation: Orientation.portrait,
        presentationMode: NavigationPresentationMode.driver,
      );
      expect(scale, kDriverNavArrowScaleTablet);
      expect(scale, 1.0);
    });

    test('4. tablet landscape keeps the large scale (1.0)', () {
      final scale = resolveDriverNavigationArrowScale(
        viewportWidth: 1112,
        viewportHeight: 834,
        isTablet: true,
        orientation: Orientation.landscape,
        presentationMode: NavigationPresentationMode.driver,
      );
      expect(scale, kDriverNavArrowScaleTablet);
      expect(scale, 1.0);
    });

    test('7. overview and north-up remain unscaled', () {
      for (final mode in [
        NavigationPresentationMode.overview,
        NavigationPresentationMode.northUp,
      ]) {
        for (final isTablet in [false, true]) {
          final scale = resolveDriverNavigationArrowScale(
            viewportWidth: isTablet ? 834.0 : 390.0,
            viewportHeight: isTablet ? 1112.0 : 844.0,
            isTablet: isTablet,
            orientation: Orientation.portrait,
            presentationMode: mode,
          );
          expect(
            scale,
            kDriverNavArrowScaleIdentity,
            reason: 'mode=$mode isTablet=$isTablet',
          );
        }
      }
    });

    test('device class wins over a wide phone landscape width', () {
      // A landscape phone can be 600+ wide; isTablet=false must still shrink.
      final scale = resolveDriverNavigationArrowScale(
        viewportWidth: 720,
        viewportHeight: 360,
        isTablet: false,
        orientation: Orientation.landscape,
        presentationMode: NavigationPresentationMode.driver,
      );
      expect(scale, lessThan(1.0));
      expect(scale, inInclusiveRange(0.78, 0.84));
    });

    test('arrow icon size helper multiplies the base only', () {
      const base = 94.0;
      final sized = resolveDriverNavigationArrowIconSize(
        baseIconSize: base,
        viewportWidth: 390,
        viewportHeight: 844,
        isTablet: false,
        orientation: Orientation.portrait,
        presentationMode: NavigationPresentationMode.driver,
      );
      expect(sized, base * kDriverNavArrowScalePhonePortrait);
    });
  });

  group('NAV-MARKER-ARROW-RESPONSIVE-SCALE-1 Street Level anchor unchanged', () {
    test('5. Street Level bottom offset is independent of arrow scale', () {
      final portraitOffset = resolveStreetLevelMarkerBottomOffset(
        isLandscape: false,
        hasSecondaryActions: false,
        secondaryActionRowHeight: 44,
        primaryToSecondaryGap: 4,
      );
      final landscapeOffset = resolveStreetLevelMarkerBottomOffset(
        isLandscape: true,
        hasSecondaryActions: false,
        secondaryActionRowHeight: 44,
        primaryToSecondaryGap: 4,
      );

      // Anchor math never takes a scale input — Auto and Arrow share it.
      expect(
        portraitOffset,
        kCockpitPortraitBasePanelHeight + kStreetLevelMarkerGapAboveKpi,
      );
      expect(
        landscapeOffset,
        kCockpitLandscapePanelHeight + kStreetLevelMarkerGapAboveKpi,
      );

      final gapPortrait = portraitOffset - kCockpitPortraitBasePanelHeight;
      final gapLandscape = landscapeOffset - kCockpitLandscapePanelHeight;
      expect(
        gapPortrait,
        inInclusiveRange(
          kStreetLevelMarkerGapAboveKpiMin,
          kStreetLevelMarkerGapAboveKpiMax,
        ),
      );
      expect(
        gapLandscape,
        inInclusiveRange(
          kStreetLevelMarkerGapAboveKpiMin,
          kStreetLevelMarkerGapAboveKpiMax,
        ),
      );
    });
  });

  group('NAV-MARKER-ARROW-RESPONSIVE-SCALE-1 HUD Auto vs Arrow', () {
    testWidgets('6. Auto scale is unchanged by arrowScale', (tester) async {
      const base = 94.0;
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: NavigationDriverHudOverlay(
              iconSize: base,
              markerChoice: DriverNavigationMarkerChoice.car,
              arrowScale: 0.84,
            ),
          ),
        ),
      );
      // Auto renders via Image, never the arrow painter.
      expect(find.byType(NavigationDriverArrowMarker), findsNothing);
      expect(find.byType(Image), findsOneWidget);
      final imageSize = tester.getSize(find.byType(Image));
      expect(imageSize.width, base);
      expect(imageSize.height, base);
    });

    testWidgets('phone arrow is visibly smaller than the shared base', (
      tester,
    ) async {
      const base = 94.0;
      const scale = kDriverNavArrowScalePhonePortrait;
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: NavigationDriverHudOverlay(
              iconSize: base,
              markerChoice: DriverNavigationMarkerChoice.arrow,
              arrowScale: scale,
            ),
          ),
        ),
      );
      final arrow = find.byType(NavigationDriverArrowMarker);
      expect(arrow, findsOneWidget);
      final size = tester.getSize(arrow);
      expect(size.width, base * scale);
      expect(size.height, base * scale);
      expect(size.width, lessThan(base));
    });

    testWidgets('tablet arrow keeps the full shared base size', (tester) async {
      const base = 132.0;
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: NavigationDriverHudOverlay(
              iconSize: base,
              markerChoice: DriverNavigationMarkerChoice.arrow,
              arrowScale: kDriverNavArrowScaleTablet,
            ),
          ),
        ),
      );
      final size = tester.getSize(find.byType(NavigationDriverArrowMarker));
      expect(size.width, base);
      expect(size.height, base);
    });

    testWidgets(
      'Auto ↔ Arrow share the Positioned bottom; only glyph size changes',
      (tester) async {
        const base = 94.0;
        const bottom = 106.0; // KPI panel + gap example
        Widget hud(DriverNavigationMarkerChoice choice, double scale) {
          return MaterialApp(
            home: Scaffold(
              body: Stack(
                children: [
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: bottom,
                    child: Center(
                      child: NavigationDriverHudOverlay(
                        iconSize: base,
                        markerChoice: choice,
                        arrowScale: scale,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        await tester.pumpWidget(
          hud(DriverNavigationMarkerChoice.car, 0.84),
        );
        final carRect = tester.getRect(find.byType(Image));

        await tester.pumpWidget(
          hud(
            DriverNavigationMarkerChoice.arrow,
            kDriverNavArrowScalePhonePortrait,
          ),
        );
        final arrowRect = tester.getRect(
          find.byType(NavigationDriverArrowMarker),
        );

        // Same bottom edge (= Street Level anchor). Arrow is shorter above it.
        expect(carRect.bottom, arrowRect.bottom);
        expect(arrowRect.height, lessThan(carRect.height));
        expect(arrowRect.top, greaterThan(carRect.top));
      },
    );
  });
}
