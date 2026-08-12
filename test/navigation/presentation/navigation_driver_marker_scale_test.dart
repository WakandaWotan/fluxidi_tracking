import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/navigation/presentation/navigation_driver_arrow_scale.dart';
import 'package:fluxidi_tracking/navigation/presentation/navigation_driver_cockpit_camera.dart';
import 'package:fluxidi_tracking/navigation/presentation/navigation_driver_marker_scale.dart';
import 'package:fluxidi_tracking/navigation/presentation/navigation_presentation_mode.dart';
import 'package:fluxidi_tracking/navigation/widgets/navigation_driver_hud_overlay.dart';

void main() {
  group('NAV-PHONE-LANDSCAPE-MARKER-SCALE-1 device class', () {
    test('1. same phone remains phone in portrait and landscape', () {
      const portrait = Size(390, 844);
      const landscape = Size(844, 390);
      expect(driverNavigationIsTabletDevice(portrait), isFalse);
      expect(driverNavigationIsTabletDevice(landscape), isFalse);
    });

    test('4. tablet portrait/landscape remains tablet', () {
      const portrait = Size(834, 1112);
      const landscape = Size(1112, 834);
      expect(driverNavigationIsTabletDevice(portrait), isTrue);
      expect(driverNavigationIsTabletDevice(landscape), isTrue);
    });

    test('wide phone landscape width never promotes to tablet', () {
      // Material-style "width >= 600" would wrongly say tablet here.
      expect(
        driverNavigationIsTabletDevice(const Size(720, 360)),
        isFalse,
      );
      expect(
        driverNavigationIsTabletDevice(const Size(926, 428)),
        isFalse,
      );
    });
  });

  group('NAV-PHONE-LANDSCAPE-MARKER-SCALE-1 base icon size', () {
    test('2. phone landscape marker is not larger than phone portrait', () {
      final portrait = NavigationDriverHudOverlay.resolveIconSize(
        screenWidth: 390,
        screenHeight: 844,
        cockpitBoost: true,
      );
      final landscape = NavigationDriverHudOverlay.resolveIconSize(
        screenWidth: 844,
        screenHeight: 390,
        cockpitBoost: true,
      );
      expect(portrait, kDriverCockpitPro2HudPhoneL7);
      expect(landscape, kDriverCockpitPro2HudPhoneL7);
      expect(landscape, lessThanOrEqualTo(portrait));
    });

    test('preserves phone portrait size (94) and tablet size (132)', () {
      expect(
        resolveDriverNavigationMarkerBaseIconSize(
          viewportSize: const Size(390, 844),
          cockpitBoost: true,
        ),
        kDriverCockpitPro2HudPhoneL7,
      );
      expect(
        resolveDriverNavigationMarkerBaseIconSize(
          viewportSize: const Size(834, 1112),
          cockpitBoost: true,
        ),
        kDriverCockpitPro2HudTabletL7,
      );
    });

    test(
      'host tablet keeps 132 in narrow vertical-split pane (not window 94)',
      () {
        const narrow = Size(400, 1280);
        expect(driverNavigationIsTabletDevice(narrow), isFalse);
        expect(
          resolveDriverNavigationMarkerBaseIconSize(
            viewportSize: narrow,
            cockpitBoost: true,
          ),
          kDriverCockpitPro2HudPhoneL7,
        );
        expect(
          resolveDriverNavigationMarkerBaseIconSize(
            viewportSize: narrow,
            cockpitBoost: true,
            hostIsTablet: true,
          ),
          kDriverCockpitPro2HudTabletL7,
        );
        expect(
          NavigationDriverHudOverlay.resolveIconSize(
            screenWidth: narrow.width,
            screenHeight: narrow.height,
            cockpitBoost: true,
            hostIsTablet: true,
          ),
          kDriverCockpitPro2HudTabletL7,
        );
      },
    );

    test('3. compact phone landscape uses the compact arrow scale', () {
      final scale = resolveDriverNavigationArrowScale(
        viewportWidth: 640,
        viewportHeight: 320,
        isTablet: driverNavigationIsTabletDevice(const Size(640, 320)),
        orientation: Orientation.landscape,
        presentationMode: NavigationPresentationMode.driver,
      );
      expect(scale, kDriverNavArrowScalePhoneLandscapeCompact);
    });
  });

  group('NAV-PHONE-LANDSCAPE-MARKER-SCALE-1 Car and Arrow share size class', () {
    test('5. Car and Arrow use the same resolved size class', () {
      for (final size in const [
        Size(390, 844),
        Size(844, 390),
        Size(834, 1112),
        Size(1112, 834),
        Size(720, 360),
      ]) {
        final orientation = size.width > size.height
            ? Orientation.landscape
            : Orientation.portrait;
        final car = resolveDriverNavigationMarkerSize(
          viewportSize: size,
          cockpitBoost: true,
          orientation: orientation,
          presentationMode: NavigationPresentationMode.driver,
          isArrow: false,
        );
        final arrow = resolveDriverNavigationMarkerSize(
          viewportSize: size,
          cockpitBoost: true,
          orientation: orientation,
          presentationMode: NavigationPresentationMode.driver,
          isArrow: true,
        );
        expect(
          car.sizeClassIsTablet,
          arrow.sizeClassIsTablet,
          reason: 'size=$size',
        );
        expect(car.baseIconSize, arrow.baseIconSize, reason: 'size=$size');
        // Car glyph stays at the shared base; Arrow may shrink on phone only.
        expect(car.glyphScale, 1.0);
        if (car.sizeClassIsTablet) {
          expect(arrow.glyphScale, 1.0);
        } else if (orientation == Orientation.landscape) {
          expect(arrow.glyphScale, lessThanOrEqualTo(car.glyphScale));
          expect(
            arrow.glyphIconSize,
            lessThanOrEqualTo(
              resolveDriverNavigationMarkerSize(
                viewportSize: Size(size.height, size.width),
                cockpitBoost: true,
                orientation: Orientation.portrait,
                presentationMode: NavigationPresentationMode.driver,
                isArrow: true,
              ).glyphIconSize,
            ),
          );
        }
      }
    });

    test('7. Tellers marker size matches Navigation for the same class', () {
      // Tellers passes a synthetic portrait phone/tablet size derived from
      // the authoritative isTablet class (same as driver_ride_meters).
      for (final isTablet in [false, true]) {
        final tellers = NavigationDriverHudOverlay.resolveIconSize(
          screenWidth: isTablet ? 800 : 390,
          screenHeight: isTablet ? 1200 : 844,
          cockpitBoost: true,
        );
        final navigation = NavigationDriverHudOverlay.resolveIconSize(
          screenWidth: isTablet ? 834 : 390,
          screenHeight: isTablet ? 1112 : 844,
          cockpitBoost: true,
        );
        expect(tellers, navigation);
        expect(
          tellers,
          isTablet
              ? kDriverCockpitPro2HudTabletL7
              : kDriverCockpitPro2HudPhoneL7,
        );
      }
    });

    test('phone landscape glyph sizes are not larger than portrait', () {
      final carPortrait = resolveDriverNavigationMarkerSize(
        viewportSize: const Size(390, 844),
        cockpitBoost: true,
        orientation: Orientation.portrait,
        presentationMode: NavigationPresentationMode.driver,
        isArrow: false,
      );
      final carLandscape = resolveDriverNavigationMarkerSize(
        viewportSize: const Size(844, 390),
        cockpitBoost: true,
        orientation: Orientation.landscape,
        presentationMode: NavigationPresentationMode.driver,
        isArrow: false,
      );
      final arrowPortrait = resolveDriverNavigationMarkerSize(
        viewportSize: const Size(390, 844),
        cockpitBoost: true,
        orientation: Orientation.portrait,
        presentationMode: NavigationPresentationMode.driver,
        isArrow: true,
      );
      final arrowLandscape = resolveDriverNavigationMarkerSize(
        viewportSize: const Size(844, 390),
        cockpitBoost: true,
        orientation: Orientation.landscape,
        presentationMode: NavigationPresentationMode.driver,
        isArrow: true,
      );
      expect(
        carLandscape.glyphIconSize,
        lessThanOrEqualTo(carPortrait.glyphIconSize),
      );
      expect(
        arrowLandscape.glyphIconSize,
        lessThanOrEqualTo(arrowPortrait.glyphIconSize),
      );
      // Regression: the old width>=600 path made landscape base 132 and the
      // scaled arrow (~107) larger than portrait arrow (~79).
      expect(
        arrowLandscape.glyphIconSize,
        lessThan(kDriverCockpitPro2HudPhoneL7),
      );
    });
  });
}
