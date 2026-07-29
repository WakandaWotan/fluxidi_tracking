import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/navigation/nav_engine/nav_active_ride_controls.dart';

// NAV-MOBILE-DATA-MINIMAL-SAFE-RELEASE-P0-1 Part D — pure product-rule
// tests for the active-ride control gates and START style decision.

void main() {
  group('decideNavActiveRideStart', () {
    test('always enters Street Level and always discards preview zoom', () {
      final light = decideNavActiveRideStart(prefersDark: false);
      expect(light.style, NavActiveRideStyle.navigationDay);
      expect(light.enterStreetLevel, isTrue);
      expect(light.discardPreviewZoom, isTrue);

      final dark = decideNavActiveRideStart(prefersDark: true);
      expect(dark.style, NavActiveRideStyle.navigationNight);
      expect(dark.enterStreetLevel, isTrue);
      expect(dark.discardPreviewZoom, isTrue);
    });

    test('the fixed active-ride style is never Satellite or Standard', () {
      final choices = <NavActiveRideStyle>{
        chooseNavActiveRideStyle(prefersDark: false),
        chooseNavActiveRideStyle(prefersDark: true),
      };
      expect(
        choices,
        {NavActiveRideStyle.navigationDay, NavActiveRideStyle.navigationNight},
      );
    });

    test('label helpers are bounded and never leak URIs', () {
      expect(
        navActiveRideStyleLabel(NavActiveRideStyle.navigationDay),
        'navigation-day-v1',
      );
      expect(
        navActiveRideStyleLabel(NavActiveRideStyle.navigationNight),
        'navigation-night-v1',
      );
    });
  });

  group('navActiveRideStyleTapAllowed', () {
    test('non-live ride: always allowed', () {
      expect(
        navActiveRideStyleTapAllowed(liveRideActive: false),
        NavActiveRideBlockReason.none,
      );
    });

    test('live ride with default kill switch: allowed', () {
      // NAV-RELEASE-SIMPLE-STREETLEVEL-1: style switching stays available.
      expect(
        navActiveRideStyleTapAllowed(liveRideActive: true),
        NavActiveRideBlockReason.none,
      );
    });

    test('live ride with kill switch explicitly disabled: blocked', () {
      expect(
        navActiveRideStyleTapAllowed(
          liveRideActive: true,
          activeRideStyleSwitchEnabled: false,
        ),
        NavActiveRideBlockReason.liveRideActive,
      );
    });
  });

  group('navActiveRideZoomAllowed', () {
    test('non-live ride: allowed', () {
      expect(
        navActiveRideZoomAllowed(liveRideActive: false),
        NavActiveRideBlockReason.none,
      );
    });

    test('live ride: allowed (fixed streetlevel zoom-only)', () {
      expect(
        navActiveRideZoomAllowed(liveRideActive: true),
        NavActiveRideBlockReason.none,
      );
    });
  });
}
