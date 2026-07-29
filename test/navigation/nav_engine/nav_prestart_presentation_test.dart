import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/navigation/nav_engine/nav_prestart_presentation.dart';

// NAV-PRESTART-FIELD-BLOCKER-3 / NAV-RELEASE-SIMPLE-STREETLEVEL-1 unit tests.

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

    test('preview draft always fixed streetlevel regardless of token', () {
      for (final token in <String>[
        NavPreviewViewModeTokens.overview,
        NavPreviewViewModeTokens.streetView,
        NavPreviewViewModeTokens.northUp,
        'nonsense',
      ]) {
        final decision = decideNavPreviewPresentation(
          NavPreviewPresentationInputs(
            hasPreviewDraft: true,
            selectedViewMode: token,
            routePointCount: 12,
            liveRideActive: false,
          ),
        );
        expect(decision.mode, NavPreviewPresentationMode.streetLevel);
        expect(decision.applyCockpitCamera, isTrue);
        expect(decision.previewRouteRestoreEligible, isTrue);
        expect(decision.reason, 'preview_fixed_streetlevel');
      }
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
      expect(decision.mode, NavPreviewPresentationMode.streetLevel);
      expect(decision.applyCockpitCamera, isTrue);
      expect(decision.previewRouteRestoreEligible, isFalse);
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
  });

  group('normaliseNavPreviewViewMode', () {
    test('release normalisation is always streetView', () {
      expect(
        normaliseNavPreviewViewMode(NavPreviewViewModeTokens.overview),
        NavPreviewViewModeTokens.streetView,
      );
      expect(
        normaliseNavPreviewViewMode(NavPreviewViewModeTokens.northUp),
        NavPreviewViewModeTokens.streetView,
      );
    });
  });

  group('mayOverviewFitBoundsInPreview', () {
    test('always false on release surface', () {
      expect(
        mayOverviewFitBoundsInPreview(
          allowOverviewCamera: true,
          selectedViewMode: NavPreviewViewModeTokens.overview,
          liveRideActive: false,
        ),
        isFalse,
      );
    });
  });

  group('mayRestorePreviewCockpitCameraAfterStyleSwitch', () {
    test('any preview draft restores streetlevel', () {
      expect(
        mayRestorePreviewCockpitCameraAfterStyleSwitch(
          hasPreviewDraft: true,
          selectedViewMode: NavPreviewViewModeTokens.overview,
          liveRideActive: false,
        ),
        isTrue,
      );
    });

    test('live ride keeps preview restore off', () {
      expect(
        mayRestorePreviewCockpitCameraAfterStyleSwitch(
          hasPreviewDraft: true,
          selectedViewMode: NavPreviewViewModeTokens.streetView,
          liveRideActive: true,
        ),
        isFalse,
      );
    });
  });
}
