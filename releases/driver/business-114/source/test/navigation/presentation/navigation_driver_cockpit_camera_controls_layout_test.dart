import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/navigation/widgets/navigation_driver_cockpit_camera_controls.dart';
import 'package:fluxidi_tracking/navigation/widgets/navigation_driver_cockpit_camera_controls_layout.dart';

void main() {
  group('NAV-PRES-3E-FIX1 driver view controls layout', () {
    const safeTop = 24.0;
    const safeBottom = 24.0;
    const safeRight = 0.0;
    const margin = kDriverCockpitControlsEdgeMargin;

    Size panelSize({required bool compactLandscape}) {
      return estimateDriverCockpitCameraControlsPanelSize(
        buttonSize: 40.0,
        hasLevelLabel: true,
        hasDebugSubLabel: true,
        compactLandscape: compactLandscape,
      );
    }

    bool isInsideViewport({
      required double screenHeight,
      required DriverCockpitCameraControlsLayoutResult layout,
      required double panelHeight,
      required double panelWidth,
      required double safeTopInset,
      required double safeBottomInset,
      required double safeRightInset,
      double navBannerReserve = 0.0,
    }) {
      final minTop = safeTopInset + margin + navBannerReserve;
      final maxBottom = screenHeight - safeBottomInset - margin;
      final top = layout.panelTop;
      final bottom = top + panelHeight;
      final right = layout.right;
      final left = right + panelWidth;
      return top >= minTop &&
          bottom <= maxBottom &&
          right >= safeRightInset + margin &&
          left <= double.infinity;
    }

    test('landscape level 13 stays inside viewport', () {
      const screenHeight = 360.0;
      final size = panelSize(compactLandscape: true);
      final layout = resolveDriverCockpitCameraControlsLayout(
        screenHeight: screenHeight,
        safeTop: safeTop,
        safeBottom: safeBottom,
        safeRight: safeRight,
        isLandscape: true,
        panelHeight: size.height,
        panelWidth: size.width,
        navBannerReserve: kDriverCockpitControlsLandscapeBannerReserve,
      );

      expect(
        isInsideViewport(
          screenHeight: screenHeight,
          layout: layout,
          panelHeight: size.height,
          panelWidth: size.width,
          safeTopInset: safeTop,
          safeBottomInset: safeBottom,
          safeRightInset: safeRight,
          navBannerReserve: kDriverCockpitControlsLandscapeBannerReserve,
        ),
        isTrue,
      );
      expect(layout.panelTop, greaterThanOrEqualTo(safeTop + margin));
      expect(
        layout.panelTop + size.height,
        lessThanOrEqualTo(screenHeight - safeBottom - margin),
      );
    });

    test('landscape level 1 stays inside viewport', () {
      const screenHeight = 360.0;
      final size = panelSize(compactLandscape: true);
      final layout = resolveDriverCockpitCameraControlsLayout(
        screenHeight: screenHeight,
        safeTop: safeTop,
        safeBottom: safeBottom,
        safeRight: safeRight,
        isLandscape: true,
        panelHeight: size.height,
        panelWidth: size.width,
        navBannerReserve: kDriverCockpitControlsLandscapeBannerReserve,
      );

      expect(
        isInsideViewport(
          screenHeight: screenHeight,
          layout: layout,
          panelHeight: size.height,
          panelWidth: size.width,
          safeTopInset: safeTop,
          safeBottomInset: safeBottom,
          safeRightInset: safeRight,
          navBannerReserve: kDriverCockpitControlsLandscapeBannerReserve,
        ),
        isTrue,
      );
    });

    test('portrait level 13 stays inside viewport', () {
      const screenHeight = 780.0;
      final size = panelSize(compactLandscape: false);
      final layout = resolveDriverCockpitCameraControlsLayout(
        screenHeight: screenHeight,
        safeTop: safeTop,
        safeBottom: safeBottom,
        safeRight: safeRight,
        isLandscape: false,
        panelHeight: size.height,
        panelWidth: size.width,
      );

      expect(
        isInsideViewport(
          screenHeight: screenHeight,
          layout: layout,
          panelHeight: size.height,
          panelWidth: size.width,
          safeTopInset: safeTop,
          safeBottomInset: safeBottom,
          safeRightInset: safeRight,
        ),
        isTrue,
      );
    });

    test('debug line panel size does not overflow landscape viewport', () {
      const screenHeight = 360.0;
      final compactSize = panelSize(compactLandscape: true);
      final layout = resolveDriverCockpitCameraControlsLayout(
        screenHeight: screenHeight,
        safeTop: safeTop,
        safeBottom: safeBottom,
        safeRight: safeRight,
        isLandscape: true,
        panelHeight: compactSize.height,
        panelWidth: compactSize.width,
        navBannerReserve: kDriverCockpitControlsLandscapeBannerReserve,
      );

      expect(compactSize.height, lessThan(screenHeight - safeTop - safeBottom));
      expect(layout.panelTop + compactSize.height,
          lessThanOrEqualTo(screenHeight - safeBottom - margin));
    });

    test('landscape placement is HUD-independent at level 13', () {
      const screenHeight = 360.0;
      final size = panelSize(compactLandscape: true);
      final level13 = resolveDriverCockpitCameraControlsLayout(
        screenHeight: screenHeight,
        safeTop: safeTop,
        safeBottom: safeBottom,
        safeRight: safeRight,
        isLandscape: true,
        panelHeight: size.height,
        panelWidth: size.width,
        navBannerReserve: kDriverCockpitControlsLandscapeBannerReserve,
      );
      final level1 = resolveDriverCockpitCameraControlsLayout(
        screenHeight: screenHeight,
        safeTop: safeTop,
        safeBottom: safeBottom,
        safeRight: safeRight,
        isLandscape: true,
        panelHeight: size.height,
        panelWidth: size.width,
        navBannerReserve: kDriverCockpitControlsLandscapeBannerReserve,
      );

      expect(level13.panelTop, equals(level1.panelTop));
      expect(level13.bottom, equals(level1.bottom));
    });
  });

  group('NAV-PRES-3E-FIX1 driver view controls widget', () {
    testWidgets('label remains View X/13 with debug line', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NavigationDriverCockpitCameraControls(
              onPlus: () {},
              onMinus: () {},
              accentColor: Colors.blue,
              textColor: Colors.white,
              surfaceColor: Colors.black,
              levelLabel: 'View 13/13',
              debugSubLabel: 'Z21.6 P84 A0.82',
            ),
          ),
        ),
      );

      expect(find.text('View 13/13'), findsOneWidget);
      expect(find.text('Z21.6 P84 A0.82'), findsOneWidget);
    });

    testWidgets('compact landscape keeps debug line visible', (tester) async {
      await tester.binding.setSurfaceSize(const Size(780, 360));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(780, 360),
              padding: EdgeInsets.only(top: 24, bottom: 24),
            ),
            child: Scaffold(
              body: NavigationDriverCockpitCameraControls(
                onPlus: () {},
                onMinus: () {},
                accentColor: Colors.blue,
                textColor: Colors.white,
                surfaceColor: Colors.black,
                levelLabel: 'View 13/13',
                debugSubLabel: 'Z21.6 P84 A0.82',
                compactLandscape: true,
              ),
            ),
          ),
        ),
      );

      final panelBox = tester.renderObject<RenderBox>(
        find.byType(NavigationDriverCockpitCameraControls),
      );
      expect(panelBox.size.height, lessThanOrEqualTo(360 - 24 - 24));
      expect(find.text('View 13/13'), findsOneWidget);
      expect(find.text('Z21.6 P84 A0.82'), findsOneWidget);
    });
  });
}
