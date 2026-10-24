import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/fluxidi_responsive.dart';
import 'package:fluxidi_tracking/navigation/widgets/navigation_driver_compact_nav_controls_layout.dart';

void main() {
  group('NAV-PRES-TABLET-CONTROLS-ZOOM-1 compact nav controls layout', () {
    test('phone control metrics unchanged', () {
      final phone = resolveDriverCompactNavControlsLayout(
        screenClass: FluxidiScreenClass.phone,
        orientation: Orientation.portrait,
      );
      expect(phone, kDriverCompactNavControlsPhoneLayout);
      expect(phone.buttonVisualSize, 44);
      expect(phone.minTouchTarget, 44);
      expect(phone.iconSize, 18);
      expect(phone.horizontalGap, 6);
      expect(phone.isTablet, isFalse);
    });

    test('tablet portrait metrics enlarged', () {
      final layout = resolveDriverCompactNavControlsLayout(
        screenClass: FluxidiScreenClass.tablet,
        orientation: Orientation.portrait,
      );
      expect(layout.isTablet, isTrue);
      expect(layout.isLandscape, isFalse);
      expect(layout.buttonVisualSize, 56);
      expect(layout.minTouchTarget, 64);
      expect(layout.iconSize, 28);
      expect(layout.horizontalGap, 9);
      expect(layout.minTouchTarget, greaterThanOrEqualTo(48));
    });

    test('tablet landscape metrics enlarged', () {
      final layout = resolveDriverCompactNavControlsLayout(
        screenClass: FluxidiScreenClass.tablet,
        orientation: Orientation.landscape,
      );
      expect(layout.isTablet, isTrue);
      expect(layout.isLandscape, isTrue);
      expect(layout.buttonVisualSize, 52);
      expect(layout.minTouchTarget, 62);
      expect(layout.iconSize, 27);
      expect(layout.horizontalGap, 11);
      expect(layout.minTouchTarget, greaterThanOrEqualTo(60));
    });

    test('no row overflow for max expanded tablet action count portrait', () {
      const actionCount = 8;
      const availableWidth = 768.0;
      final layout = resolveDriverCompactNavControlsLayout(
        screenClass: FluxidiScreenClass.tablet,
        orientation: Orientation.portrait,
      );
      expect(
        driverCompactNavControlsRowFits(
          layout: layout,
          actionCount: actionCount,
          availableWidth: availableWidth,
        ),
        isTrue,
      );
    });

    test('no row overflow for max expanded tablet action count landscape', () {
      const actionCount = 8;
      const availableWidth = 1024.0;
      final layout = resolveDriverCompactNavControlsLayout(
        screenClass: FluxidiScreenClass.tablet,
        orientation: Orientation.landscape,
      );
      expect(
        driverCompactNavControlsRowFits(
          layout: layout,
          actionCount: actionCount,
          availableWidth: availableWidth,
        ),
        isTrue,
      );
    });

    test('touch targets meet minimum 48 dp on tablet', () {
      for (final orientation in Orientation.values) {
        final layout = resolveDriverCompactNavControlsLayout(
          screenClass: FluxidiScreenClass.tablet,
          orientation: orientation,
        );
        expect(layout.minTouchTarget, greaterThanOrEqualTo(48));
        expect(layout.rowHeight, greaterThanOrEqualTo(layout.minTouchTarget));
      }
    });
  });
}
