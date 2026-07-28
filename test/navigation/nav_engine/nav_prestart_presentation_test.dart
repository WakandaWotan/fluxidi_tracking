import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/navigation/nav_engine/nav_prestart_presentation.dart';

// NAV-PRESTART-FIELD-BLOCKER-3 unit tests.
//
// These pure tests pin the decision matrix for the pre-start preview
// presentation so a future change cannot silently reintroduce the field-blocker
// behaviour where street-level was unreachable before START and where a style
// swap silently dropped the accepted preview route.

void main() {
  group('decideNavPreviewPresentation', () {
    test('live ride always wins: no cockpit apply, no preview restore', () {
      final decision = decideNavPreviewPresentation(
        const NavPreviewPresentationInputs(
          hasPreviewDraft: true,
          selectedViewMode: NavPreviewViewModeTokens.streetView,
          routePointCount: 12,
          liveRideActive: true,
        ),
      );
      expect(decision.mode, NavPreviewPresentationMode.overview);
      expect(decision.applyCockpitCamera, isFalse);
      expect(decision.previewRouteRestoreEligible, isFalse);
      expect(decision.reason, 'live_ride_active');
    });

    test('no preview draft: overview only, no cockpit apply, no restore', () {
      final decision = decideNavPreviewPresentation(
        const NavPreviewPresentationInputs(
          hasPreviewDraft: false,
          selectedViewMode: NavPreviewViewModeTokens.streetView,
          routePointCount: 12,
          liveRideActive: false,
        ),
      );
      expect(decision.mode, NavPreviewPresentationMode.overview);
      expect(decision.applyCockpitCamera, isFalse);
      expect(decision.previewRouteRestoreEligible, isFalse);
      expect(decision.reason, 'no_preview_draft');
    });

    test('preview draft + overview mode: overview, restore-eligible', () {
      final decision = decideNavPreviewPresentation(
        const NavPreviewPresentationInputs(
          hasPreviewDraft: true,
          selectedViewMode: NavPreviewViewModeTokens.overview,
          routePointCount: 12,
          liveRideActive: false,
        ),
      );
      expect(decision.mode, NavPreviewPresentationMode.overview);
      expect(decision.applyCockpitCamera, isFalse);
      expect(decision.previewRouteRestoreEligible, isTrue);
      expect(decision.reason, 'preview_overview');
    });

    test('preview draft + streetView: streetlevel, cockpit apply, restore', () {
      final decision = decideNavPreviewPresentation(
        const NavPreviewPresentationInputs(
          hasPreviewDraft: true,
          selectedViewMode: NavPreviewViewModeTokens.streetView,
          routePointCount: 12,
          liveRideActive: false,
        ),
      );
      expect(decision.mode, NavPreviewPresentationMode.streetLevel);
      expect(decision.isStreetLevel, isTrue);
      expect(decision.applyCockpitCamera, isTrue);
      expect(decision.previewRouteRestoreEligible, isTrue);
      expect(decision.reason, 'preview_streetlevel');
    });

    test('preview draft with <2 coords: restore not eligible', () {
      final decision = decideNavPreviewPresentation(
        const NavPreviewPresentationInputs(
          hasPreviewDraft: true,
          selectedViewMode: NavPreviewViewModeTokens.overview,
          routePointCount: 1,
          liveRideActive: false,
        ),
      );
      expect(decision.mode, NavPreviewPresentationMode.overview);
      expect(decision.previewRouteRestoreEligible, isFalse);
    });

    test('northUp token in preview folds into overview presentation', () {
      final decision = decideNavPreviewPresentation(
        const NavPreviewPresentationInputs(
          hasPreviewDraft: true,
          selectedViewMode: NavPreviewViewModeTokens.northUp,
          routePointCount: 12,
          liveRideActive: false,
        ),
      );
      expect(decision.mode, NavPreviewPresentationMode.overview);
      expect(decision.applyCockpitCamera, isFalse);
    });

    test('unknown selectedViewMode token falls back to overview', () {
      final decision = decideNavPreviewPresentation(
        const NavPreviewPresentationInputs(
          hasPreviewDraft: true,
          selectedViewMode: 'nonsense',
          routePointCount: 12,
          liveRideActive: false,
        ),
      );
      expect(decision.mode, NavPreviewPresentationMode.overview);
      expect(decision.applyCockpitCamera, isFalse);
    });
  });

  group('cycleNavPreviewViewMode', () {
    test('overview toggles to streetView', () {
      expect(
        cycleNavPreviewViewMode(NavPreviewViewModeTokens.overview),
        NavPreviewViewModeTokens.streetView,
      );
    });

    test('streetView toggles to overview', () {
      expect(
        cycleNavPreviewViewMode(NavPreviewViewModeTokens.streetView),
        NavPreviewViewModeTokens.overview,
      );
    });

    test('northUp folds to streetView on first tap', () {
      expect(
        cycleNavPreviewViewMode(NavPreviewViewModeTokens.northUp),
        NavPreviewViewModeTokens.streetView,
      );
    });
  });

  group('normaliseNavPreviewViewMode', () {
    test('preserves streetView', () {
      expect(
        normaliseNavPreviewViewMode(NavPreviewViewModeTokens.streetView),
        NavPreviewViewModeTokens.streetView,
      );
    });

    test('collapses northUp into overview', () {
      expect(
        normaliseNavPreviewViewMode(NavPreviewViewModeTokens.northUp),
        NavPreviewViewModeTokens.overview,
      );
    });

    test('collapses unknown token into overview', () {
      expect(
        normaliseNavPreviewViewMode('nonsense'),
        NavPreviewViewModeTokens.overview,
      );
    });
  });
}
