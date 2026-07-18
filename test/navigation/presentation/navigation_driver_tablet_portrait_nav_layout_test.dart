import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/fluxidi_responsive.dart';
import 'package:fluxidi_tracking/navigation/widgets/navigation_driver_cockpit_camera_controls_layout.dart';
import 'package:fluxidi_tracking/navigation/widgets/navigation_driver_compact_nav_controls_layout.dart';
import 'package:fluxidi_tracking/navigation/widgets/navigation_driver_tablet_portrait_nav_layout.dart';

void main() {
  group('NAV-PRES-TABLET-PORTRAIT-POLISH-1 tablet portrait nav layout', () {
    test('phone layout resolver returns null polish', () {
      expect(
        resolveDriverTabletPortraitNavLayout(
          screenClass: FluxidiScreenClass.phone,
          orientation: Orientation.portrait,
        ),
        isNull,
      );
      expect(
        resolveDriverCompactNavControlsLayoutForNav(
          screenClass: FluxidiScreenClass.phone,
          orientation: Orientation.portrait,
        ),
        kDriverCompactNavControlsPhoneLayout,
      );
    });

    test('tablet landscape base metrics unchanged', () {
      final layout = resolveDriverCompactNavControlsLayout(
        screenClass: FluxidiScreenClass.tablet,
        orientation: Orientation.landscape,
      );
      expect(layout.buttonVisualSize, 52);
      expect(layout.minTouchTarget, 62);
      expect(layout.iconSize, 27);
      expect(layout.horizontalGap, 11);
      expect(layout.rowPadding, 4);
      expect(layout.metricsToPrimaryGap, 4);
      expect(layout.distributeSecondaryRowEvenly, isFalse);

      expect(
        resolveDriverTabletPortraitNavLayout(
          screenClass: FluxidiScreenClass.tablet,
          orientation: Orientation.landscape,
        ),
        isNull,
      );
      expect(
        resolveDriverCockpitCameraControlsPlacementHints(
          screenClass: FluxidiScreenClass.tablet,
          orientation: Orientation.landscape,
        ),
        isNull,
      );
    });

    test('tablet portrait bottom spacing polish applied', () {
      final polish = resolveDriverTabletPortraitNavLayout(
        screenClass: FluxidiScreenClass.tablet,
        orientation: Orientation.portrait,
      );
      expect(polish, isNotNull);

      final layout = resolveDriverCompactNavControlsLayoutForNav(
        screenClass: FluxidiScreenClass.tablet,
        orientation: Orientation.portrait,
      );
      expect(layout.buttonVisualSize, 56);
      expect(layout.minTouchTarget, 64);
      expect(layout.iconSize, 28);
      expect(layout.metricsToPrimaryGap, 9);
      expect(layout.primaryToSecondaryGap, 9);
      expect(layout.secondaryRowHorizontalInset, 10);
      expect(layout.distributeSecondaryRowEvenly, isTrue);
      expect(layout.rowHeight, 78);
      expect(layout.rowHeight - 72, lessThanOrEqualTo(6));
      expect(layout.minTouchTarget, greaterThanOrEqualTo(48));
    });

    test('tablet portrait view panel width inset and vertical offset', () {
      final polish = resolveDriverTabletPortraitNavLayout(
        screenClass: FluxidiScreenClass.tablet,
        orientation: Orientation.portrait,
      )!;
      final view = polish.viewPanel;
      expect(view.panelHorizontalPadding, 8);
      expect(view.panelWidthExtra, 4);
      expect(view.levelLabelFontSize, 11);
      expect(view.debugLabelFontSize, 7);
      expect(view.debugLabelOpacity, 0.55);
      expect(view.portraitBottomOffsetDelta, 11);
      expect(view.portraitRightInsetExtra, 12);

      const baseWidth = 48.0;
      final polishedWidth = estimateDriverCockpitCameraControlsPanelSize(
        buttonSize: 40,
        hasLevelLabel: true,
        hasDebugSubLabel: true,
        compactLandscape: false,
        panelWidthExtra: view.panelWidthExtra,
        panelHorizontalPadding: view.panelHorizontalPadding,
        levelLabelFontSize: view.levelLabelFontSize,
        debugLabelFontSize: view.debugLabelFontSize,
      ).width;
      expect(polishedWidth - baseWidth, inInclusiveRange(10, 14));

      final hints = resolveDriverCockpitCameraControlsPlacementHints(
        screenClass: FluxidiScreenClass.tablet,
        orientation: Orientation.portrait,
      )!;
      expect(
        hints.portraitBottomOffset,
        kDriverCockpitControlsPortraitBottomOffset +
            view.portraitBottomOffsetDelta,
      );
      expect(hints.rightInsetExtra, 12);

      const screenHeight = 1280.0;
      const safeTop = 24.0;
      const safeBottom = 24.0;
      final panelSize = estimateDriverCockpitCameraControlsPanelSize(
        buttonSize: 40,
        hasLevelLabel: true,
        hasDebugSubLabel: true,
        compactLandscape: false,
        panelWidthExtra: view.panelWidthExtra,
        panelHorizontalPadding: view.panelHorizontalPadding,
      );
      final baseLayout = resolveDriverCockpitCameraControlsLayout(
        screenHeight: screenHeight,
        safeTop: safeTop,
        safeBottom: safeBottom,
        safeRight: 0,
        isLandscape: false,
        panelHeight: panelSize.height,
        panelWidth: panelSize.width,
      );
      final polishedLayout = resolveDriverCockpitCameraControlsLayout(
        screenHeight: screenHeight,
        safeTop: safeTop,
        safeBottom: safeBottom,
        safeRight: 0,
        isLandscape: false,
        panelHeight: panelSize.height,
        panelWidth: panelSize.width,
        placementHints: hints,
      );
      expect(polishedLayout.panelTop, lessThan(baseLayout.panelTop - 7));
      expect(polishedLayout.right, baseLayout.right + 12);
    });

    test('tablet portrait banner height reduced about 10-12 percent', () {
      final banner = resolveDriverTabletPortraitNavLayout(
        screenClass: FluxidiScreenClass.tablet,
        orientation: Orientation.portrait,
      )!.banner;
      expect(banner.minHeight, 100);
      expect(112 - banner.minHeight, inInclusiveRange(10, 12));
      expect(banner.iconBoxSize, 58);
      expect(banner.iconSize, 35);
    });

    test('800x1280 portrait chrome fits without overlap', () {
      const screenWidth = 800.0;
      const screenHeight = 1280.0;
      const safeTop = 24.0;
      const safeBottom = 24.0;
      final polish = resolveDriverTabletPortraitNavLayout(
        screenClass: FluxidiScreenClass.tablet,
        orientation: Orientation.portrait,
      )!;
      final panelSize = estimateDriverCockpitCameraControlsPanelSize(
        buttonSize: 40,
        hasLevelLabel: true,
        hasDebugSubLabel: true,
        compactLandscape: false,
        panelWidthExtra: polish.viewPanel.panelWidthExtra,
        panelHorizontalPadding: polish.viewPanel.panelHorizontalPadding,
      );
      expect(
        driverTabletPortraitNavLayoutFitsViewport(
          screenWidth: screenWidth,
          screenHeight: screenHeight,
          safeTop: safeTop,
          safeBottom: safeBottom,
          safeRight: 0,
          panelWidth: panelSize.width,
          panelHeight: panelSize.height,
          layout: polish,
        ),
        isTrue,
      );
    });

    test('landscape panel size estimate unchanged without portrait hints', () {
      final landscape = estimateDriverCockpitCameraControlsPanelSize(
        buttonSize: 40,
        hasLevelLabel: true,
        hasDebugSubLabel: true,
        compactLandscape: true,
      );
      expect(landscape.width, 48);
    });
  });
}
