// GOOGLE-MAPS-NAV-RETURN-SIGNAGE-RESTORE-P1
//
// Regression: Google Maps → return to NAV FLX must restore the current
// maneuver signage (DriverTurnInstructionBanner + NavManeuverSign) from the
// authoritative navigation state — without restarting NAV, clearing the route,
// or inventing a fake straight maneuver.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/navigation/driver_navigation_models.dart';
import 'package:fluxidi_tracking/navigation/external/external_nav_signage_restore.dart';
import 'package:fluxidi_tracking/navigation/external/external_navigation_session.dart';
import 'package:fluxidi_tracking/navigation/presentation/maneuver_presentation.dart';
import 'package:fluxidi_tracking/navigation/presentation/nav_maneuver_sign.dart';
import 'package:fluxidi_tracking/widgets/driver_nav_banners.dart';

String _tr({
  required String nl,
  required String en,
  required String fr,
  required String es,
}) =>
    nl;

ExternalNavigationSession _mapsSession({
  bool pipActive = true,
  bool suppressed = true,
}) {
  return ExternalNavigationSession(
    provider: ExternalNavProvider.googleMaps,
    bookingId: 'street_signage_restore_1',
    phase: ExternalNavPhase.activeRide,
    destination: const ExternalNavigationDestinationPoint(
      latitude: 51.05,
      longitude: 3.72,
    ),
    launchedAt: DateTime.utc(2026, 8, 8, 12),
    pipActive: pipActive,
    nativeGuidanceSuppressed: suppressed,
  );
}

NavInstructionSnapshot _turnRightSnapshot({double distanceM = 180}) {
  return NavInstructionSnapshot(
    distanceToManeuverMeters: distanceM,
    primaryText: 'Rechtsaf',
    secondaryText: 'Korenmarkt',
    maneuverType: 'turn',
    maneuverModifier: 'right',
    roadName: 'Korenmarkt',
    roadRef: '',
    isHighwayLike: false,
    lanes: const <DriverNavLaneGuidance>[],
    source: NavInstructionSource.banner,
  );
}

ResponsiveManeuverPresentation _presentation(
  NavInstructionSnapshot snap, {
  String languageCode = 'nl',
}) {
  return buildResponsiveManeuverPresentation(
    snapshot: snap,
    tr: _tr,
    languageCode: languageCode,
    useCaptionedSign: false,
  );
}

/// Mirrors the production gate used by DriverHomePage for banner visibility.
bool _bannerVisible({
  required ExternalNavigationSession? session,
  required bool cameraFollow,
  required NavInstructionSnapshot? snapshot,
}) {
  if (shouldSuppressNativeGuidance(session)) return false;
  if (!cameraFollow) return false;
  return snapshot?.hasInstruction == true;
}

DriverTurnInstructionBanner _banner(ResponsiveManeuverPresentation p) {
  return DriverTurnInstructionBanner(
    compact: false,
    isTablet: false,
    isArrival: p.isArrival,
    isHighwayLike: p.isHighwayLike,
    distancePrefix: 'Over',
    distanceText: p.distanceLabel,
    primaryText: p.primaryInstruction,
    secondaryText: p.secondaryInstruction,
    icon: driverManeuverVisualIconData(p.maneuverVisual),
    presentation: p,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('preserve + restore decisions', () {
    test('1) active NAV keeps maneuver fields while Google Maps suppresses', () {
      expect(shouldClearManeuverPresentationWhileSuppressed(), isFalse);
      final session = _mapsSession(pipActive: true, suppressed: true);
      expect(shouldSuppressNativeGuidance(session), isTrue);
      final snap = _turnRightSnapshot();
      expect(snap.hasInstruction, isTrue);
      expect(snap.maneuverModifier, 'right');
    });

    test('2) open Google Maps: suppression hides banner but keeps presentation',
        () {
      final session = _mapsSession(pipActive: true, suppressed: true);
      final snap = _turnRightSnapshot();
      final p = _presentation(snap);
      expect(shouldSuppressNativeGuidance(session), isTrue);
      expect(
        _bannerVisible(
          session: session,
          cameraFollow: true,
          snapshot: snap,
        ),
        isFalse,
      );
      expect(p.signAssetPath.toLowerCase(), contains('right'));
      expect(p.signAssetPath, contains('/nl/'));
    });

    test('3) return to NAV FLX unsuppresses + rehydrates current maneuver', () {
      final session = _mapsSession(pipActive: true, suppressed: true);
      final decision = decideExternalNavSignageRestore(
        trigger: ExternalNavSignageRestoreTrigger.pipReturnToFluxidi,
        liveRideActive: true,
        cameraFollow: true,
        hadExternalSession: true,
      );
      expect(decision.unsuppressNativeGuidance, isTrue);
      expect(decision.restoreNavigationGuidanceActive, isTrue);
      expect(decision.rehydrateManeuverFromCurrentState, isTrue);

      final restored = applyExternalNavSignageRestoreToSession(
        session: session,
        decision: decision,
      )!;
      expect(restored.pipActive, isFalse);
      expect(restored.nativeGuidanceSuppressed, isFalse);
      expect(shouldSuppressNativeGuidance(restored), isFalse);

      final snap = _turnRightSnapshot(distanceM: 160);
      expect(
        _bannerVisible(
          session: restored,
          cameraFollow: true,
          snapshot: snap,
        ),
        isTrue,
      );
    });

    testWidgets(
      '4) same/current maneuver sign becomes visible again after return',
      (tester) async {
        final before = _presentation(_turnRightSnapshot());
        final afterReturn = _presentation(_turnRightSnapshot(distanceM: 155));
        expect(afterReturn.signAssetPath, before.signAssetPath);
        expect(afterReturn.maneuverVisual, before.maneuverVisual);

        // Simulate return: session unsuppressed + banner mounted again.
        final restored = applyExternalNavSignageRestoreToSession(
          session: _mapsSession(),
          decision: decideExternalNavSignageRestore(
            trigger: ExternalNavSignageRestoreTrigger.pipReturnToFluxidi,
            liveRideActive: true,
            cameraFollow: true,
            hadExternalSession: true,
          ),
        )!;
        expect(shouldSuppressNativeGuidance(restored), isFalse);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Align(
                alignment: Alignment.topCenter,
                child: _banner(afterReturn),
              ),
            ),
          ),
        );
        await tester.pump();

        expect(find.byType(DriverTurnInstructionBanner), findsOneWidget);
        expect(find.byType(NavManeuverSign), findsOneWidget);
        final sign = tester.widget<NavManeuverSign>(
          find.byType(NavManeuverSign),
        );
        expect(sign.assetPath, afterReturn.signAssetPath);
        expect(sign.assetPath, before.signAssetPath);
      },
    );

    test('5) correct language asset path remains selected', () {
      final nl = _presentation(_turnRightSnapshot(), languageCode: 'nl');
      final fr = _presentation(_turnRightSnapshot(), languageCode: 'fr');
      expect(nl.signAssetPath, contains('/nl/'));
      expect(fr.signAssetPath, contains('/fr/'));
      expect(nl.signAssetPath, isNot(equals(fr.signAssetPath)));
      expect(nl.signAssetPath.toLowerCase(), isNot(contains('straight')));
      expect(nl.signAssetPath.toLowerCase(), contains('right'));
    });

    test('6) route and ride remain active (restore does not clear route)', () {
      final decision = decideExternalNavSignageRestore(
        trigger: ExternalNavSignageRestoreTrigger.pipReturnToFluxidi,
        liveRideActive: true,
        cameraFollow: true,
        hadExternalSession: true,
      );
      expect(decision.rehydrateManeuverFromCurrentState, isTrue);
      expect(decision.restoreNavigationGuidanceActive, isTrue);
      final end = decideExternalNavSignageRestore(
        trigger: ExternalNavSignageRestoreTrigger.endExternalSession,
        liveRideActive: true,
        cameraFollow: true,
        hadExternalSession: true,
      );
      expect(end.rehydrateManeuverFromCurrentState, isTrue);
      expect(end.unsuppressNativeGuidance, isFalse);
    });

    test('7) NAV 3D / follow camera gate unchanged by restore decision', () {
      // Restore may re-enable guidance for a live ride, but must NOT bypass
      // the follow-camera gate used by DriverTurnInstructionBanner.
      final decision = decideExternalNavSignageRestore(
        trigger: ExternalNavSignageRestoreTrigger.pipReturnToFluxidi,
        liveRideActive: true,
        cameraFollow: true,
        hadExternalSession: true,
      );
      expect(decision.restoreNavigationGuidanceActive, isTrue);

      final restored = applyExternalNavSignageRestoreToSession(
        session: _mapsSession(),
        decision: decision,
      )!;
      expect(
        _bannerVisible(
          session: restored,
          cameraFollow: false,
          snapshot: _turnRightSnapshot(),
        ),
        isFalse,
        reason: 'Follow/3D camera mode remains required for banner visibility',
      );
      expect(
        _bannerVisible(
          session: restored,
          cameraFollow: true,
          snapshot: _turnRightSnapshot(),
        ),
        isTrue,
      );
    });

    test('8) repeated Google Maps → NAV FLX transitions remain stable', () {
      var session = _mapsSession(pipActive: false, suppressed: false);
      String? lastAsset;
      for (var i = 0; i < 3; i++) {
        session = session.copyWith(
          pipActive: true,
          nativeGuidanceSuppressed: true,
        );
        expect(shouldSuppressNativeGuidance(session), isTrue);
        expect(shouldClearManeuverPresentationWhileSuppressed(), isFalse);

        final decision = decideExternalNavSignageRestore(
          trigger: ExternalNavSignageRestoreTrigger.pipReturnToFluxidi,
          liveRideActive: true,
          cameraFollow: true,
          hadExternalSession: true,
        );
        session = applyExternalNavSignageRestoreToSession(
          session: session,
          decision: decision,
        )!;
        expect(shouldSuppressNativeGuidance(session), isFalse);

        final p = _presentation(_turnRightSnapshot(distanceM: 200 - i * 10));
        lastAsset ??= p.signAssetPath;
        expect(p.signAssetPath, lastAsset);
        expect(
          _bannerVisible(
            session: session,
            cameraFollow: true,
            snapshot: _turnRightSnapshot(),
          ),
          isTrue,
        );
      }
    });
  });

  group('source contract — driver home wiring', () {
    late String homeSource;

    setUpAll(() {
      homeSource =
          File('lib/main_parts/driver_home_page_state.dart').readAsStringSync();
    });

    test('does not wipe maneuver snapshot while Google Maps suppresses', () {
      expect(
        homeSource,
        contains('GOOGLE-MAPS-NAV-RETURN-SIGNAGE-RESTORE-P1'),
      );
      expect(
        homeSource,
        contains('shouldClearManeuverPresentationWhileSuppressed()'),
      );
      expect(
        homeSource,
        contains('_restoreFluxidiNavSignageAfterExternalReturn'),
      );
      expect(
        homeSource.contains(
          'GOOGLE-MAPS-WITH-FLUXIDI-PIP-RELEASE-1: while Google Maps owns guidance,\n'
          '    // suppress Fluxidi maneuver banners / stale instruction ownership. GPS,\n'
          '    // fare, wait and trip timers keep updating elsewhere.\n'
          '    if (shouldSuppressNativeGuidance(_externalNavigationSession)) {\n'
          '      if (_nextNavInstruction != null ||',
        ),
        isFalse,
        reason: 'Destructive clear-while-suppressed block must be removed',
      );
    });

    test('PiP return + end-session restore paths are wired', () {
      expect(
        homeSource,
        contains('ExternalNavSignageRestoreTrigger.pipReturnToFluxidi'),
      );
      expect(
        homeSource,
        contains('ExternalNavSignageRestoreTrigger.endExternalSession'),
      );
      expect(homeSource, contains('event=signage_restore'));
      expect(
        homeSource,
        contains('Offstage(offstage: true, child: driverBody)'),
      );
    });
  });
}
