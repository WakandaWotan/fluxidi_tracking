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

    test('live ride with default kill switch: blocked', () {
      // Final release flow: style switching locked during the paid trip.
      expect(
        navActiveRideStyleTapAllowed(liveRideActive: true),
        NavActiveRideBlockReason.liveRideActive,
      );
    });

    test('live ride with kill switch explicitly enabled: allowed', () {
      expect(
        navActiveRideStyleTapAllowed(
          liveRideActive: true,
          activeRideStyleSwitchEnabled: true,
        ),
        NavActiveRideBlockReason.none,
      );
    });
  });

  group('navActiveRideZoomAllowed', () {
    test('non-live ride: blocked (no +/- on preview either)', () {
      expect(
        navActiveRideZoomAllowed(liveRideActive: false),
        NavActiveRideBlockReason.liveRideActive,
      );
    });

    test('live ride: blocked (fixed streetlevel owns zoom)', () {
      expect(
        navActiveRideZoomAllowed(liveRideActive: true),
        NavActiveRideBlockReason.liveRideActive,
      );
    });
  });
}
