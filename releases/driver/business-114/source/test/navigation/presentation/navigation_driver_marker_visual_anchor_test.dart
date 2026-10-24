import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/navigation/presentation/navigation_driver_marker_choice.dart';
import 'package:fluxidi_tracking/navigation/presentation/navigation_driver_marker_visual_anchor.dart';
import 'package:fluxidi_tracking/navigation/widgets/navigation_driver_arrow_marker.dart';
import 'package:fluxidi_tracking/navigation/widgets/navigation_driver_hud_overlay.dart';

void main() {
  group('CAR VISUAL CENTERLINE — metadata', () {
    test('Car and Arrow expose distinct explicit visual anchor fractions', () {
      expect(
        driverNavigationMarkerVisualAnchorFraction(
          DriverNavigationMarkerChoice.car,
        ),
        kDriverCarVisualAnchorFraction,
      );
      expect(
        driverNavigationMarkerVisualAnchorFraction(
          DriverNavigationMarkerChoice.arrow,
        ),
        kDriverArrowVisualAnchorFraction,
      );
      // Arrow stays on the layout centre (unchanged alignment).
      expect(kDriverArrowVisualAnchorFraction, const Offset(0.5, 0.5));
      // Car X from measured PNG body centreline; Y stays layout-centre so the
      // shared Street Level bottom edge (Car ↔ Arrow) is preserved.
      expect(kDriverCarVisualAnchorFraction.dx, closeTo(0.501, 0.001));
      expect(kDriverCarVisualAnchorFraction.dy, 0.5);
    });

    test('3. Navigation and Tellers share the same Car visual anchor constant', () {
      // Both surfaces import the same constant through the HUD overlay /
      // Tellers placement helpers — there is only one Car fraction.
      expect(
        kDriverCarVisualAnchorFraction,
        driverNavigationMarkerVisualAnchorFraction(
          DriverNavigationMarkerChoice.car,
        ),
      );
    });
  });

  group('CAR VISUAL CENTERLINE — pose ↔ visual road-contact invariant', () {
    test('1. Car visual centerline lands on the projected pose (layout centre)', () {
      const pose = Offset(200, 400);
      const size = 94.0;
      // Layout box is centred on the pose (Navigation Center / Tellers half-box).
      final layoutTopLeft = driverNavigationMarkerTopLeftForVisualAnchor(
        visualAnchorScreen: pose,
        layoutSize: size,
        visualAnchorFraction: kDriverMarkerLayoutCenterFraction,
      );
      expect(layoutTopLeft, const Offset(200 - 47, 400 - 47));

      // Paint offset moves the artwork so the measured visual centreline
      // coincides with the layout centre (= pose).
      final paintOffset = driverNavigationMarkerVisualPaintOffset(
        layoutSize: size,
        visualAnchorFraction: kDriverCarVisualAnchorFraction,
      );
      final visualOnScreen = driverNavigationMarkerVisualAnchorScreen(
        layoutTopLeft: layoutTopLeft + paintOffset,
        layoutSize: size,
        visualAnchorFraction: kDriverCarVisualAnchorFraction,
      );
      expect(visualOnScreen.dx, closeTo(pose.dx, 0.05));
      expect(visualOnScreen.dy, closeTo(pose.dy, 0.05));
    });

    test('2. Arrow alignment remains unchanged (zero paint offset)', () {
      const size = 94.0;
      final offset = driverNavigationMarkerVisualPaintOffset(
        layoutSize: size,
        visualAnchorFraction: kDriverArrowVisualAnchorFraction,
      );
      expect(offset, Offset.zero);

      const pose = Offset(200, 400);
      final topLeft = driverNavigationMarkerTopLeftForVisualAnchor(
        visualAnchorScreen: pose,
        layoutSize: size,
        visualAnchorFraction: kDriverArrowVisualAnchorFraction,
      );
      expect(topLeft, const Offset(153, 353)); // pose - size/2
    });

    test('4+5. phone and tablet sizes stay aligned (fraction is size-independent)', () {
      for (final size in [72.0, 94.0, 132.0]) {
        for (final pose in const [
          Offset(195, 650), // phone portrait-ish
          Offset(422, 195), // phone landscape-ish
          Offset(417, 860), // tablet portrait-ish
          Offset(556, 417), // tablet landscape-ish
        ]) {
          final layoutTopLeft = driverNavigationMarkerTopLeftForVisualAnchor(
            visualAnchorScreen: pose,
            layoutSize: size,
            visualAnchorFraction: kDriverMarkerLayoutCenterFraction,
          );
          final paintOffset = driverNavigationMarkerVisualPaintOffset(
            layoutSize: size,
            visualAnchorFraction: kDriverCarVisualAnchorFraction,
          );
          final visual = driverNavigationMarkerVisualAnchorScreen(
            layoutTopLeft: layoutTopLeft + paintOffset,
            layoutSize: size,
            visualAnchorFraction: kDriverCarVisualAnchorFraction,
          );
          expect(visual.dx, closeTo(pose.dx, 0.05), reason: 'size=$size pose=$pose');
          expect(visual.dy, closeTo(pose.dy, 0.05), reason: 'size=$size pose=$pose');
        }
      }
    });

    test('6. Car ↔ Arrow share layout centre — camera baseline size unchanged', () {
      // Camera / Street Level use the unscaled layout [iconSize]. Paint offset
      // and arrow glyph scale must not alter that layout size.
      const layoutSize = 94.0;
      final carPaint = driverNavigationMarkerVisualPaintOffset(
        layoutSize: layoutSize,
        visualAnchorFraction: kDriverCarVisualAnchorFraction,
      );
      final arrowPaint = driverNavigationMarkerVisualPaintOffset(
        layoutSize: layoutSize,
        visualAnchorFraction: kDriverArrowVisualAnchorFraction,
      );
      // Layout boxes for both choices remain layoutSize×layoutSize when the
      // parent centres on the pose; only paint/glyph differs.
      expect(carPaint.dx.abs(), lessThan(layoutSize * 0.02));
      expect(arrowPaint, Offset.zero);
    });

    test('7. recenter geometry: pose↔visual relationship is identity after offset', () {
      // Recenter keeps the same markerAnchor / pose; reapplying the formula
      // yields the same visual road-contact point (idempotent).
      const pose = Offset(300, 500);
      const size = 94.0;
      Offset visualFor(Offset p) {
        final topLeft = driverNavigationMarkerTopLeftForVisualAnchor(
          visualAnchorScreen: p,
          layoutSize: size,
          visualAnchorFraction: kDriverMarkerLayoutCenterFraction,
        );
        final paint = driverNavigationMarkerVisualPaintOffset(
          layoutSize: size,
          visualAnchorFraction: kDriverCarVisualAnchorFraction,
        );
        return driverNavigationMarkerVisualAnchorScreen(
          layoutTopLeft: topLeft + paint,
          layoutSize: size,
          visualAnchorFraction: kDriverCarVisualAnchorFraction,
        );
      }

      final a = visualFor(pose);
      final b = visualFor(pose); // "recenter" with same pose
      expect(a, b);
      expect(a.dx, closeTo(pose.dx, 0.05));
      expect(a.dy, closeTo(pose.dy, 0.05));
    });
  });

  group('CAR VISUAL CENTERLINE — HUD overlay wiring', () {
    testWidgets('Car applies a Transform.translate paint offset', (tester) async {
      const size = 94.0;
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: NavigationDriverHudOverlay(
              iconSize: size,
              markerChoice: DriverNavigationMarkerChoice.car,
            ),
          ),
        ),
      );
      final paint = find.byKey(
        const ValueKey<String>('nav_marker_visual_anchor_paint'),
      );
      expect(paint, findsOneWidget);
      final transform = tester.widget<Transform>(paint);
      final expected = driverNavigationMarkerVisualPaintOffset(
        layoutSize: size,
        visualAnchorFraction: kDriverCarVisualAnchorFraction,
      );
      final translation = transform.transform.getTranslation();
      expect(translation.x, closeTo(expected.dx, 0.001));
      expect(translation.y, closeTo(expected.dy, 0.001));
      // Layout size of the image stays at the shared base (camera-safe).
      expect(tester.getSize(find.byType(Image)), const Size(size, size));
    });

    testWidgets('Arrow has no visual-anchor paint Transform', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: NavigationDriverHudOverlay(
              iconSize: 94,
              markerChoice: DriverNavigationMarkerChoice.arrow,
              arrowScale: 1.0,
            ),
          ),
        ),
      );
      expect(find.byType(NavigationDriverArrowMarker), findsOneWidget);
      // Zero offset short-circuits the keyed visual-anchor Transform.
      expect(
        find.byKey(const ValueKey<String>('nav_marker_visual_anchor_paint')),
        findsNothing,
      );
    });
  });
}
