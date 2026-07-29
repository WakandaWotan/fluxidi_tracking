import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/navigation/nav_engine/nav_active_ride_controls.dart';
import 'package:fluxidi_tracking/navigation/nav_engine/nav_prestart_preview_controls.dart';

void main() {
  // Street ride after "Continue": destination chosen, START not pressed.
  NavMapControlAvailability preStart({int routePointCount = 24}) {
    return resolveNavMapControlAvailability(
      liveRideActive: false,
      hasPreviewDestination: true,
      routePointCount: routePointCount,
    );
  }

  // Same ride after START.
  NavMapControlAvailability activeRide({int routePointCount = 24}) {
    return resolveNavMapControlAvailability(
      liveRideActive: true,
      hasPreviewDestination: false,
      routePointCount: routePointCount,
    );
  }

  group('NAV-PRESTART-PREVIEW-AND-STABLE-BEARING-P0 pre-start preview', () {
    test('preview phase is entered by destination alone, not by a live ride', () {
      expect(preStart().phase, NavMapSurfacePhase.preview);
      expect(
        resolveNavMapSurfacePhase(
          liveRideActive: false,
          hasPreviewDestination: true,
        ),
        NavMapSurfacePhase.preview,
      );
      expect(
        resolveNavMapSurfacePhase(
          liveRideActive: false,
          hasPreviewDestination: false,
        ),
        NavMapSurfacePhase.idle,
      );
    });

    test('route preview renders the route before START', () {
      expect(preStart(routePointCount: 24).routePreview, isTrue);
      expect(navPreviewRouteDrawable(24), isTrue);
    });

    test('a single coordinate is not a drawable route line', () {
      expect(preStart(routePointCount: 1).routePreview, isFalse);
      expect(navPreviewRouteDrawable(1), isFalse);
      expect(navPreviewRouteDrawable(kNavPreviewRoutePointMinimum), isTrue);
    });

    test('map-style controls are available before START', () {
      expect(preStart().styleSelector, isTrue);
    });

    test('zoom controls are available before START', () {
      expect(preStart().zoomControls, isTrue);
    });

    test('offline-map entry is available before START', () {
      expect(preStart().offlineMapsEntry, isTrue);
    });

    test('marker selector is available before START', () {
      expect(preStart().markerSelector, isTrue);
    });

    test('START action is offered in preview and not during the ride', () {
      expect(preStart().startAction, isTrue);
      expect(activeRide().startAction, isFalse);
    });

    test('idle surface exposes no controls', () {
      final idle = resolveNavMapControlAvailability(
        liveRideActive: false,
        hasPreviewDestination: false,
        routePointCount: 0,
      );
      expect(idle.phase, NavMapSurfacePhase.idle);
      expect(idle.styleSelector, isFalse);
      expect(idle.zoomControls, isFalse);
      expect(idle.markerSelector, isFalse);
      expect(idle.offlineMapsEntry, isFalse);
      expect(idle.startAction, isFalse);
    });

    test('phase labels are stable PII-free tokens', () {
      expect(navMapSurfacePhaseLabel(NavMapSurfacePhase.idle), 'idle');
      expect(navMapSurfacePhaseLabel(NavMapSurfacePhase.preview), 'preview');
      expect(
        navMapSurfacePhaseLabel(NavMapSurfacePhase.activeRide),
        'active_ride',
      );
    });
  });

  group('NAV-PRESTART-PREVIEW-AND-STABLE-BEARING-P0 active-ride lock', () {
    test('active-ride keeps style + zoom under fixed streetlevel', () {
      final live = activeRide();
      expect(live.phase, NavMapSurfacePhase.activeRide);
      expect(live.styleSelector, isTrue);
      expect(live.zoomControls, isTrue);
      expect(
        navActiveRideStyleTapAllowed(liveRideActive: true),
        NavActiveRideBlockReason.none,
      );
      expect(
        navActiveRideZoomAllowed(liveRideActive: true),
        NavActiveRideBlockReason.none,
      );
    });

    test('route stays visible during the active ride', () {
      expect(activeRide().routePreview, isTrue);
    });

    test('a live ride outranks a lingering preview destination', () {
      final live = resolveNavMapControlAvailability(
        liveRideActive: true,
        hasPreviewDestination: true,
        routePointCount: 24,
      );
      expect(live.phase, NavMapSurfacePhase.activeRide);
      expect(live.styleSelector, isTrue);
      expect(live.zoomControls, isTrue);
    });

    test('controls return after STOP', () {
      // STOP clears the live flags; the destination is still selected.
      final afterStop = resolveNavMapControlAvailability(
        liveRideActive: false,
        hasPreviewDestination: true,
        routePointCount: 24,
      );
      expect(afterStop.phase, NavMapSurfacePhase.preview);
      expect(afterStop.styleSelector, isTrue);
      expect(afterStop.zoomControls, isTrue);
      expect(afterStop.markerSelector, isTrue);
      expect(afterStop.offlineMapsEntry, isTrue);
      expect(
        navActiveRideStyleTapAllowed(liveRideActive: false),
        NavActiveRideBlockReason.none,
      );
      expect(
        navActiveRideZoomAllowed(liveRideActive: false),
        NavActiveRideBlockReason.none,
      );
    });
  });

  group('NAV-PRESTART-PREVIEW-AND-STABLE-BEARING-P0 START carry-over', () {
    test('selected settings carry into START', () {
      final decision = decideNavPreStartCarryOver(
        selection: const NavPreStartSelection(
          styleSelected: true,
          viewLevel: 11,
        ),
        defaultViewLevel: 7,
      );
      expect(decision.preserveStyle, isTrue);
      expect(decision.startViewLevel, 11);
      expect(decision.reason, 'preserve_prestart_style');
    });

    test('a preview camera level survives START without a style choice', () {
      final decision = decideNavPreStartCarryOver(
        selection: const NavPreStartSelection(viewLevel: 4),
        defaultViewLevel: 7,
      );
      expect(decision.preserveStyle, isFalse);
      expect(decision.startViewLevel, 4);
      expect(decision.reason, 'preserve_prestart_level');
    });

    test('an untouched preview falls back to the safe navigation style', () {
      final decision = decideNavPreStartCarryOver(
        selection: const NavPreStartSelection(),
        defaultViewLevel: 7,
      );
      expect(decision.preserveStyle, isFalse);
      expect(decision.startViewLevel, 7);
      expect(decision.reason, 'no_prestart_selection');
      // The fixed pair is still what an unselected START resolves to.
      expect(
        navActiveRideStyleLabel(
          decideNavActiveRideStart(prefersDark: true).style,
        ),
        'navigation-night-v1',
      );
      expect(
        navActiveRideStyleLabel(
          decideNavActiveRideStart(prefersDark: false).style,
        ),
        'navigation-day-v1',
      );
    });

    test('a style-only selection keeps the default starting level', () {
      final decision = decideNavPreStartCarryOver(
        selection: const NavPreStartSelection(styleSelected: true),
        defaultViewLevel: 9,
      );
      expect(decision.preserveStyle, isTrue);
      expect(decision.startViewLevel, 9);
    });

    test('START always enters Street Level', () {
      expect(
        decideNavActiveRideStart(prefersDark: false).enterStreetLevel,
        isTrue,
      );
    });
  });
}
