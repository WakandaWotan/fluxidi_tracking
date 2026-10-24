import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/navigation/nav_engine/nav_active_ride_controls.dart';
import 'package:fluxidi_tracking/navigation/nav_engine/nav_annotation_manager_lifecycle.dart';
import 'package:fluxidi_tracking/navigation/nav_engine/nav_fixed_streetlevel.dart';
import 'package:fluxidi_tracking/navigation/nav_engine/nav_prestart_presentation.dart';
import 'package:fluxidi_tracking/navigation/nav_engine/nav_prestart_preview_controls.dart';
import 'package:fluxidi_tracking/navigation/presentation/navigation_streetlevel_marker_anchor.dart';

// NAV-RELEASE-FINAL-FLOW-1
//
// Pure proofs for the final release navigation surface:
// no overview, no +/- zoom, fixed streetlevel, NAV=driver→A (unmetered),
// START=paid A→B, style available only before NAV/START.

void main() {
  group('NAV-RELEASE-FINAL-FLOW-1 prepared route → fixed Street Level', () {
    test('1) prepared draft owns streetlevel, never overview fitBounds', () {
      expect(
        fixedStreetLevelOwnsCamera(
          hasPreviewDraft: true,
          liveRideActive: false,
        ),
        isTrue,
      );
      expect(
        mayOverviewFitBoundsWithFixedStreetLevel(
          hasPreviewDraft: true,
          liveRideActive: false,
        ),
        isFalse,
      );
      expect(
        mayOverviewFitBoundsInPreview(
          allowOverviewCamera: true,
          selectedViewMode: NavPreviewViewModeTokens.overview,
          liveRideActive: false,
        ),
        isFalse,
      );
      final decision = decideNavPreviewPresentation(
        const NavPreviewPresentationInputs(
          hasPreviewDraft: true,
          selectedViewMode: NavPreviewViewModeTokens.overview,
          routePointCount: 20,
          liveRideActive: false,
        ),
      );
      expect(decision.mode, NavPreviewPresentationMode.streetLevel);
    });

    test('2) overview/fitBounds writers cannot take ownership once drafted', () {
      expect(
        mayOverviewFitBoundsWithFixedStreetLevel(
          hasPreviewDraft: true,
          liveRideActive: false,
        ),
        isFalse,
      );
      expect(
        mayOverviewFitBoundsWithFixedStreetLevel(
          hasPreviewDraft: false,
          liveRideActive: true,
        ),
        isFalse,
      );
      expect(
        mayOverviewFitBoundsWithFixedStreetLevel(
          hasPreviewDraft: true,
          liveRideActive: true,
        ),
        isFalse,
      );
    });

    test('3) +/- zoom controls are absent before and during navigation', () {
      final preview = resolveNavMapControlAvailability(
        liveRideActive: false,
        hasPreviewDestination: true,
        routePointCount: 20,
      );
      final live = resolveNavMapControlAvailability(
        liveRideActive: true,
        hasPreviewDestination: true,
        routePointCount: 20,
      );
      final guided = resolveNavMapControlAvailability(
        liveRideActive: false,
        hasPreviewDestination: true,
        routePointCount: 20,
        navigationGuidanceActive: true,
      );
      expect(preview.zoomControls, isFalse);
      expect(live.zoomControls, isFalse);
      expect(guided.zoomControls, isFalse);
      expect(
        navActiveRideZoomAllowed(liveRideActive: false),
        NavActiveRideBlockReason.liveRideActive,
      );
      expect(
        navActiveRideZoomAllowed(liveRideActive: true),
        NavActiveRideBlockReason.liveRideActive,
      );
      expect(fixedStreetLevelZoomAllowed(liveRideActive: false), isFalse);
      expect(fixedStreetLevelZoomAllowed(liveRideActive: true), isFalse);
    });

    test('4) marker selector available so persisted Car/Arrow can render/change',
        () {
      final preview = resolveNavMapControlAvailability(
        liveRideActive: false,
        hasPreviewDestination: true,
        routePointCount: 20,
      );
      expect(preview.markerSelector, isTrue);
      expect(preview.routePreview, isTrue);
    });

    test('5) marker remains centered just above KPI counters', () {
      final portrait = resolveStreetLevelMarkerBottomOffset(
        isLandscape: false,
        hasSecondaryActions: true,
        secondaryActionRowHeight: 48,
        primaryToSecondaryGap: 8,
      );
      // Panel (90) + secondary (48+8) + gap (16) = 162.
      expect(portrait, 162);
      expect(portrait, greaterThan(kCockpitPortraitBasePanelHeight));
      final landscape = resolveStreetLevelMarkerBottomOffset(
        isLandscape: true,
        hasSecondaryActions: false,
        secondaryActionRowHeight: 0,
        primaryToSecondaryGap: 0,
      );
      expect(landscape, kCockpitLandscapePanelHeight + kStreetLevelMarkerGapAboveKpi);
    });

    test('6) map-style selector remains available before NAV/START', () {
      final preview = resolveNavMapControlAvailability(
        liveRideActive: false,
        hasPreviewDestination: true,
        routePointCount: 20,
      );
      expect(preview.styleSelector, isTrue);
      expect(
        navActiveRideStyleTapAllowed(liveRideActive: false),
        NavActiveRideBlockReason.none,
      );
    });
  });

  group('NAV-RELEASE-FINAL-FLOW-1 NAV vs START', () {
    test('1/7) booking preview shows NAV-to-pickup', () {
      expect(
        navToPickupActionVisible(
          hasBooking: true,
          directRideDraft: false,
          directRideActive: false,
        ),
        isTrue,
      );
      expect(
        decideNavOpenRouteTarget(
          hasBooking: true,
          tripActive: false,
          hasDirectDestination: false,
          directRideActive: false,
        ),
        NavOpenRouteTarget.toPickup,
      );
    });

    test('2) direct street ride does not expose NAV preview-only action', () {
      expect(
        navToPickupActionVisible(
          hasBooking: false,
          directRideDraft: true,
          directRideActive: false,
        ),
        isFalse,
      );
      expect(
        decideNavOpenRouteTarget(
          hasBooking: false,
          tripActive: false,
          hasDirectDestination: true,
          directRideActive: false,
        ),
        NavOpenRouteTarget.none,
      );
    });

    test('3) NAV never starts metering (toPickup keeps startAction)', () {
      // Guided booking NAV locks style/zoom but START remains for paid A→B.
      final guided = resolveNavMapControlAvailability(
        liveRideActive: false,
        hasPreviewDestination: true,
        routePointCount: 20,
        navigationGuidanceActive: true,
      );
      expect(guided.startAction, isTrue);
      expect(guided.phase, isNot(NavMapSurfacePhase.activeRide));
      expect(
        decideNavOpenRouteTarget(
          hasBooking: true,
          tripActive: false,
          hasDirectDestination: false,
          directRideActive: false,
        ),
        isNot(NavOpenRouteTarget.toDropoff),
      );
    });

    test('4) all manual zoom paths blocked in prepared-route state', () {
      final preview = resolveNavMapControlAvailability(
        liveRideActive: false,
        hasPreviewDestination: true,
        routePointCount: 20,
      );
      expect(preview.zoomControls, isFalse);
      expect(
        navActiveRideZoomAllowed(liveRideActive: false),
        NavActiveRideBlockReason.liveRideActive,
      );
      expect(fixedStreetLevelZoomAllowed(liveRideActive: false), isFalse);
      final lock = resolveNavFixedZoomGestureLock(
        preparedRouteOrGuidanceOrLive: true,
      );
      expect(lock.allZoomGesturesDisabled, isTrue);
      expect(lock.pinchToZoomEnabled, isFalse);
      expect(lock.doubleTapToZoomInEnabled, isFalse);
      expect(lock.doubleTouchToZoomOutEnabled, isFalse);
      expect(lock.quickZoomEnabled, isFalse);
    });

    test('5) pre-start map-style selection remains available', () {
      final preview = resolveNavMapControlAvailability(
        liveRideActive: false,
        hasPreviewDestination: true,
        routePointCount: 20,
      );
      expect(preview.styleSelector, isTrue);
      expect(
        navActiveRideStyleTapAllowed(liveRideActive: false),
        NavActiveRideBlockReason.none,
      );
    });

    test('6) style switching cannot change fixed camera/zoom/anchor', () {
      expect(
        mayRestorePreviewCockpitCameraAfterStyleSwitch(
          hasPreviewDraft: true,
          selectedViewMode: NavPreviewViewModeTokens.overview,
          liveRideActive: false,
        ),
        isTrue,
      );
      expect(
        mayRestoreFixedStreetLevelAfterStyleSwitch(
          hasPreviewDraft: true,
          liveRideActive: false,
        ),
        isTrue,
      );
      // After restore, zoom gestures stay locked on the prepared surface.
      expect(
        resolveNavFixedZoomGestureLock(
          preparedRouteOrGuidanceOrLive: true,
        ).allZoomGesturesDisabled,
        isTrue,
      );
      final decision = decideNavPreviewPresentation(
        const NavPreviewPresentationInputs(
          hasPreviewDraft: true,
          selectedViewMode: NavPreviewViewModeTokens.overview,
          routePointCount: 12,
          liveRideActive: false,
        ),
      );
      expect(decision.mode, NavPreviewPresentationMode.streetLevel);
      expect(decision.applyCockpitCamera, isTrue);
    });

    test('9) START / live trip targets dropoff B (A→B customer route)', () {
      expect(
        decideNavOpenRouteTarget(
          hasBooking: true,
          tripActive: true,
          hasDirectDestination: false,
          directRideActive: false,
        ),
        NavOpenRouteTarget.toDropoff,
      );
      expect(
        decideNavOpenRouteTarget(
          hasBooking: false,
          tripActive: false,
          hasDirectDestination: true,
          directRideActive: true,
        ),
        NavOpenRouteTarget.toDropoff,
      );
      final live = resolveNavMapControlAvailability(
        liveRideActive: true,
        hasPreviewDestination: true,
        routePointCount: 20,
      );
      expect(live.startAction, isFalse);
      expect(live.phase, NavMapSurfacePhase.activeRide);
    });

    test('10) active Street Level stays fixed and deterministic', () {
      expect(
        decideNavActiveRideStart(prefersDark: false).enterStreetLevel,
        isTrue,
      );
      expect(
        fixedStreetLevelOwnsCamera(
          hasPreviewDraft: false,
          liveRideActive: true,
        ),
        isTrue,
      );
      expect(kNavActiveRideStyleSwitchEnabled, isFalse);
      expect(
        navStyleTapDecision(
          liveRideActive: true,
          styleTransactionRunning: false,
        ),
        NavStyleTapDecision.blocked,
      );
      final live = resolveNavMapControlAvailability(
        liveRideActive: true,
        hasPreviewDestination: false,
        routePointCount: 20,
      );
      expect(live.styleSelector, isFalse);
      expect(live.zoomControls, isFalse);
      expect(
        resolveNavFixedZoomGestureLock(
          preparedRouteOrGuidanceOrLive: true,
        ).allZoomGesturesDisabled,
        isTrue,
      );
    });
  });

  group('NAV-RELEASE-FINAL-FLOW-1 preserve / lock boundaries', () {
    test('prestart style carry-over is preserved into START decision', () {
      final carry = decideNavPreStartCarryOver(
        selection: const NavPreStartSelection(styleSelected: true),
        defaultViewLevel: 7,
      );
      expect(carry.preserveStyle, isTrue);
      expect(carry.reason, 'preserve_prestart_style');
    });

    test('NAV with nothing selected is a no-op target', () {
      expect(
        decideNavOpenRouteTarget(
          hasBooking: false,
          tripActive: false,
          hasDirectDestination: false,
          directRideActive: false,
        ),
        NavOpenRouteTarget.none,
      );
    });
  });
}
