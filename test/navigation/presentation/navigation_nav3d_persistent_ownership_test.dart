// NAV-3D-P0-PERSISTENT-VEHICLE-OWNERSHIP-1 — pure resolver / lifecycle tests.
//
// Proves that a requested cockpit 3D choice never becomes vehicle_choice_2d
// for temporary render gaps, that Native FollowPuck ownership survives ordinary
// GPS/presentation updates, and that Native + ModelLayer cannot both write.

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/navigation/driver_navigation_map_config.dart';
import 'package:fluxidi_tracking/navigation/presentation/navigation_driver_vehicle_model_layer.dart';
import 'package:fluxidi_tracking/navigation/presentation/navigation_presentation_mode.dart';

Driver3dVehicleEligibility _eligibility({
  required DriverVehiclePresentationChoice choice,
  bool native3dRendererActive = false,
  bool sessionFallback2d = false,
  bool styleSwapInProgress = false,
  bool styleLoaded = true,
  bool modelRegistered = false,
  bool modelPoseApplied = false,
  bool layerCreated = false,
  bool sourceGeometryValid = false,
  bool modelActivationConfirmed = false,
  bool renderCredibilityConfirmed = false,
  bool assetLoaded = true,
  int activeStyleGeneration = 3,
  int activePresetGeneration = 2,
  int confirmedStyleGeneration = -1,
  int confirmedPresetGeneration = -1,
  int modelLayerStyleGeneration = -1,
  int modelLayerPresetGeneration = -1,
  DriverCockpitMapVisualStyle? cockpitVisualStyle =
      DriverCockpitMapVisualStyle.standard3d,
  String? activeStyleUri = kDriverMapStyleStandard,
}) {
  return resolveDriver3dVehicleEligibility(
    vehicleModelFlagEnabled: true,
    cockpitSceneEnabled: true,
    useDriverCockpitCamera: true,
    presentationMode: NavigationPresentationMode.driver,
    liveNavigationActive: true,
    followCamera: true,
    activeStyleUri: activeStyleUri,
    visualMode: DriverMapVisualMode.street,
    cockpitSceneActive: true,
    cockpitVisualStyle: cockpitVisualStyle,
    sessionFallback2d: sessionFallback2d,
    styleLoaded: styleLoaded,
    styleSwapInProgress: styleSwapInProgress,
    modelRegistered: modelRegistered,
    modelPoseApplied: modelPoseApplied,
    hideHudIsolationFlagEnabled: true,
    layerCreated: layerCreated,
    sourceGeometryValid: sourceGeometryValid,
    modelActivationConfirmed: modelActivationConfirmed,
    renderCredibilityConfirmed: renderCredibilityConfirmed,
    assetLoaded: assetLoaded,
    activeStyleGeneration: activeStyleGeneration,
    activePresetGeneration: activePresetGeneration,
    confirmedStyleGeneration: confirmedStyleGeneration,
    confirmedPresetGeneration: confirmedPresetGeneration,
    modelLayerStyleGeneration: modelLayerStyleGeneration,
    modelLayerPresetGeneration: modelLayerPresetGeneration,
    followLiveActive: true,
    useDriver3dVehicleModel: true,
    selectedVehiclePresentation: choice,
    native3dRendererActive: native3dRendererActive,
  );
}

({
  bool presentation3dActive,
  bool driver3dVisualReady,
  bool effectivelyActive,
  bool hudFallbackAllowedToHide,
  DriverVisualOwnership ownership,
}) _handoff({
  required Driver3dVehicleEligibility eligibility,
  required DriverVehiclePresentationChoice choice,
  bool native3dRendererActive = false,
  bool modelRegistered = false,
  bool layerCreated = false,
  bool sourceGeometryValid = false,
  bool modelPoseApplied = false,
  bool modelActivationConfirmed = false,
  bool renderCredibilityConfirmed = false,
  int activeStyleGeneration = 3,
  int activePresetGeneration = 2,
  int modelLayerStyleGeneration = -1,
  int modelLayerPresetGeneration = -1,
  int confirmedStyleGeneration = -1,
  int confirmedPresetGeneration = -1,
  bool explicit2dFallback = false,
}) {
  return resolveNav3dHudHandoffForRender(
    eligibility: eligibility,
    useDriver3dVehicleModel: true,
    followLiveActive: true,
    observationalAssetLoaded: true,
    handoffAssetLoaded: true,
    modelRegistered: modelRegistered,
    layerCreated: layerCreated,
    sourceGeometryValid: sourceGeometryValid,
    modelPoseApplied: modelPoseApplied,
    modelActivationConfirmed: modelActivationConfirmed,
    renderCredibilityConfirmed: renderCredibilityConfirmed,
    activeStyleGeneration: activeStyleGeneration,
    activePresetGeneration: activePresetGeneration,
    modelLayerStyleGeneration: modelLayerStyleGeneration,
    modelLayerPresetGeneration: modelLayerPresetGeneration,
    confirmedStyleGeneration: confirmedStyleGeneration,
    confirmedPresetGeneration: confirmedPresetGeneration,
    showDriverHudOverlay: true,
    hideHudFlagEnabled: true,
    explicit2dFallback: explicit2dFallback,
    selectedVehiclePresentation: choice,
    native3dRendererActive: native3dRendererActive,
  );
}

void main() {
  group('NAV-3D-P0-PERSISTENT-VEHICLE-OWNERSHIP-1', () {
    test('1. cockpit3d + compatible style never yields vehicle_choice_2d', () {
      for (final choice in [
        DriverVehiclePresentationChoice.fluxidi3d,
        DriverVehiclePresentationChoice.classic3d,
      ]) {
        final e = _eligibility(choice: choice);
        expect(e.eligible, isTrue);
        expect(e.reason, 'eligible');
        expect(e.reason, isNot('vehicle_choice_2d'));
      }
    });

    test('2. cockpit3d survives repeated presentation-state rebuilds', () {
      const choice = DriverVehiclePresentationChoice.fluxidi3d;
      DriverVisualOwner? last;
      for (var i = 0; i < 20; i++) {
        final e = _eligibility(choice: choice, native3dRendererActive: true);
        final h = _handoff(
          eligibility: e,
          choice: choice,
          native3dRendererActive: true,
        );
        expect(e.reason, isNot('vehicle_choice_2d'));
        expect(h.ownership.owner, DriverVisualOwner.model3d);
        last = h.ownership.owner;
      }
      expect(last, DriverVisualOwner.model3d);
    });

    test('3. cockpit3d survives 100 ordinary GPS/movement updates', () {
      const choice = DriverVehiclePresentationChoice.fluxidi3d;
      final e = _eligibility(choice: choice, native3dRendererActive: true);
      for (var i = 0; i < 100; i++) {
        final h = _handoff(
          eligibility: e,
          choice: choice,
          native3dRendererActive: true,
        );
        expect(h.driver3dVisualReady, isTrue);
        expect(h.ownership.owner, DriverVisualOwner.model3d);
        expect(
          resolveNav3dOwnershipSurvivesOrdinaryUpdate(
            requestedChoice: choice,
            ownerBefore: DriverVisualOwner.model3d,
            ownerAfter: h.ownership.owner,
            eligibilityReason: e.reason,
            activationConfirmed: true,
          ),
          isTrue,
        );
      }
    });

    test('4-5. first pose then next GPS: owner stays 3D (field symptom)', () {
      const choice = DriverVehiclePresentationChoice.fluxidi3d;

      // t0: native owns 3D after first credible pose.
      final e0 = _eligibility(choice: choice, native3dRendererActive: true);
      final h0 = _handoff(
        eligibility: e0,
        choice: choice,
        native3dRendererActive: true,
      );
      expect(e0.eligible, isTrue);
      expect(e0.reason, isNot('vehicle_choice_2d'));
      expect(h0.driver3dVisualReady, isTrue);
      expect(h0.effectivelyActive, isTrue);
      expect(h0.ownership.owner, DriverVisualOwner.model3d);
      expect(h0.ownership.hudMounted, isFalse);

      // t1: ordinary next GPS/presentation update — no teardown.
      final e1 = _eligibility(choice: choice, native3dRendererActive: true);
      final h1 = _handoff(
        eligibility: e1,
        choice: choice,
        native3dRendererActive: true,
      );
      expect(h1.ownership.owner, DriverVisualOwner.model3d);
      expect(h1.driver3dVisualReady, isTrue);
      expect(h1.ownership.hudMounted, isFalse);
      expect(e1.reason, isNot('vehicle_choice_2d'));
    });

    test('6. style/preset generations stay acknowledged after movement', () {
      const choice = DriverVehiclePresentationChoice.fluxidi3d;
      final ready = _eligibility(
        choice: choice,
        modelRegistered: true,
        layerCreated: true,
        sourceGeometryValid: true,
        modelPoseApplied: true,
        modelActivationConfirmed: true,
        renderCredibilityConfirmed: true,
        modelLayerStyleGeneration: 3,
        modelLayerPresetGeneration: 2,
        confirmedStyleGeneration: 3,
        confirmedPresetGeneration: 2,
      );
      expect(ready.driver3dVisualReady, isTrue);
      // Movement-only re-eval with same generations.
      final afterMove = _eligibility(
        choice: choice,
        modelRegistered: true,
        layerCreated: true,
        sourceGeometryValid: true,
        modelPoseApplied: true,
        modelActivationConfirmed: true,
        renderCredibilityConfirmed: true,
        modelLayerStyleGeneration: 3,
        modelLayerPresetGeneration: 2,
        confirmedStyleGeneration: 3,
        confirmedPresetGeneration: 2,
      );
      expect(afterMove.driver3dVisualReady, isTrue);
      expect(afterMove.effectivelyActive, isTrue);
    });

    test('7-8. stale style/preset completions cannot tear down current', () {
      expect(
        shouldIgnoreStaleDriverVehicle3dSwap(
          requestGeneration: 4,
          currentGeneration: 5,
        ),
        isTrue,
      );
      expect(
        shouldIgnoreStaleDriverVehicle3dSwap(
          requestGeneration: 5,
          currentGeneration: 5,
        ),
        isFalse,
      );
    });

    test('9-10. style reload falls back safely but preserves requested3d', () {
      const choice = DriverVehiclePresentationChoice.fluxidi3d;
      final during = _eligibility(
        choice: choice,
        styleSwapInProgress: true,
        native3dRendererActive: true,
      );
      expect(during.eligible, isFalse);
      expect(during.reason, 'style_swap_in_progress');
      expect(during.reason, isNot('vehicle_choice_2d'));
      expect(during.driver3dVisualReady, isFalse);

      final restored = _eligibility(
        choice: choice,
        native3dRendererActive: true,
      );
      expect(restored.eligible, isTrue);
      expect(restored.driver3dVisualReady, isTrue);
    });

    test('11. explicit taxi2d produces vehicle_choice_2d', () {
      final e = _eligibility(choice: DriverVehiclePresentationChoice.taxi2d);
      expect(e.eligible, isFalse);
      expect(e.reason, 'vehicle_choice_2d');
      final h = _handoff(
        eligibility: e,
        choice: DriverVehiclePresentationChoice.taxi2d,
      );
      expect(h.ownership.owner, DriverVisualOwner.hud2d);
      expect(h.ownership.reason, 'selected_taxi2d');
    });

    test('12-14. asset/registration/first-pose failure keeps HUD + requested3d',
        () {
      const choice = DriverVehiclePresentationChoice.fluxidi3d;
      final failed = _eligibility(
        choice: choice,
        assetLoaded: false,
        modelRegistered: false,
      );
      expect(failed.eligible, isTrue);
      expect(failed.reason, isNot('vehicle_choice_2d'));
      expect(failed.driver3dVisualReady, isFalse);
      final h = _handoff(eligibility: failed, choice: choice);
      // Intent-active selection may own model3d immediately; HUD hide still
      // requires visual ready — actual HUD mount follows ownership rules.
      expect(h.driver3dVisualReady, isFalse);
      expect(
        resolveNav3dHudShouldHide(
          hideHudFlagEnabled: true,
          driver3dVisualReady: h.driver3dVisualReady,
        ),
        isFalse,
      );
    });

    test('15-16. successful first pose hides HUD; no duplicate 2D+3D', () {
      const choice = DriverVehiclePresentationChoice.fluxidi3d;
      final e = _eligibility(choice: choice, native3dRendererActive: true);
      final h = _handoff(
        eligibility: e,
        choice: choice,
        native3dRendererActive: true,
      );
      final decision = resolveNav3dHudRenderDecision(
        hideHudFlagEnabled: true,
        presentation3dActive: h.presentation3dActive,
        driver3dVisualReady: h.driver3dVisualReady,
        effectivelyActive: h.effectivelyActive,
        hudFallbackAllowedToHide: h.hudFallbackAllowedToHide,
        showDriverHudOverlay: true,
        followLiveActive: true,
        explicit2dFallback: false,
        ownership: h.ownership,
        selectedVehiclePresentation: choice,
      );
      expect(decision.shouldHideHud, isTrue);
      expect(decision.actualHudVisible, isFalse);
      expect(decision.mapbox2dVisible, isFalse);
      expect(decision.visibleDriverVisualCount, 1);
    });

    test('17. Native FollowPuck and ModelLayer cannot both own', () {
      expect(
        resolveDriverVehicleRenderersMutuallyExclusive(
          nativeFollowActive: true,
          modelLayerWritingPoses: true,
        ),
        isFalse,
      );
      expect(
        resolveDriverVehicleRenderersMutuallyExclusive(
          nativeFollowActive: true,
          modelLayerWritingPoses: false,
        ),
        isTrue,
      );
      expect(
        resolveDriverVehicleRendererKind(
          nativeFollowActive: true,
          requestedChoice: DriverVehiclePresentationChoice.fluxidi3d,
          owner: DriverVisualOwner.model3d,
          modelLayerWritingPoses: false,
        ),
        DriverVehicleRendererKind.native3d,
      );
    });

    test('20-23. Fluxidi/Classic selection persists; switch is latest-wins', () {
      final fluxidi = _eligibility(
        choice: DriverVehiclePresentationChoice.fluxidi3d,
        native3dRendererActive: true,
      );
      expect(fluxidi.eligible, isTrue);
      final classic = _eligibility(
        choice: DriverVehiclePresentationChoice.classic3d,
        native3dRendererActive: true,
      );
      expect(classic.eligible, isTrue);
      expect(
        driverVehicle3dPresetForPresentationChoice(
          DriverVehiclePresentationChoice.classic3d,
        ),
        DriverVehicle3dPreset.classicFlyingTaxi,
      );
      expect(
        driverVehicle3dPresetForPresentationChoice(
          DriverVehiclePresentationChoice.fluxidi3d,
        ),
        DriverVehicle3dPreset.fluxidiTaxi,
      );
    });

    test('24. route N → N+1 keeps active 3D ownership (route version ignored)',
        () {
      const choice = DriverVehiclePresentationChoice.fluxidi3d;
      // Route version is not an eligibility input — ownership must be identical.
      final before = _handoff(
        eligibility: _eligibility(choice: choice, native3dRendererActive: true),
        choice: choice,
        native3dRendererActive: true,
      );
      final after = _handoff(
        eligibility: _eligibility(choice: choice, native3dRendererActive: true),
        choice: choice,
        native3dRendererActive: true,
      );
      expect(before.ownership.owner, DriverVisualOwner.model3d);
      expect(after.ownership.owner, DriverVisualOwner.model3d);
      expect(before.driver3dVisualReady, after.driver3dVisualReady);
    });

    test('25-26. banner/lanes/complexity/view/recenter are not eligibility inputs',
        () {
      // Pure contract: eligibility depends only on the documented gates.
      final e = _eligibility(
        choice: DriverVehiclePresentationChoice.fluxidi3d,
        native3dRendererActive: true,
      );
      expect(e.eligible, isTrue);
      expect(e.driver3dVisualReady, isTrue);
    });

    test('location component must stay enabled under native follow', () {
      expect(
        resolveShouldHideMapboxUserLocationPuck(
          nativeFollowActive: true,
          routePreviewOrNav: true,
          hasActiveTaxiMarker: true,
          followLiveActive: true,
        ),
        isFalse,
      );
      expect(
        resolveShouldHideMapboxUserLocationPuck(
          nativeFollowActive: false,
          routePreviewOrNav: true,
          hasActiveTaxiMarker: false,
          followLiveActive: true,
        ),
        isTrue,
      );
    });

    test('diagnostic vehicleChoice includes presentation, not only cockpit', () {
      final e = _eligibility(
        choice: DriverVehiclePresentationChoice.fluxidi3d,
      );
      final snap = resolveNav3dVehicleDiagnosticSnapshot(
        presentationActive: true,
        featureEnabled: true,
        cockpitSceneEnabled: true,
        cockpitVisualStyle: DriverCockpitMapVisualStyle.standard3d,
        vehiclePreset: DriverVehicle3dPreset.fluxidiTaxi,
        activeStyleUri: kDriverMapStyleStandard,
        eligibility: e,
        assetLoaded: false,
        modelRegistered: false,
        layerCreated: false,
        modelPoseApplied: false,
        modelActivationConfirmed: false,
        registerInFlight: false,
        selectedVehiclePresentation: DriverVehiclePresentationChoice.fluxidi3d,
      );
      expect(snap.vehicleChoice, contains('presentation=fluxidi3d'));
      expect(snap.vehicleChoice, contains('cockpit='));
    });

    test(
      'native readiness: requested3d alone never yields native visual-ready',
      () {
        const choice = DriverVehiclePresentationChoice.fluxidi3d;

        // Session up but configure not acknowledged → keep HUD fallback.
        expect(
          resolveNative3dRendererCrediblyActive(
            requested3d: true,
            nativeFollowSessionActive: true,
            nativePresetConfigureAcknowledged: false,
            nativeCommandGenerationCurrent: false,
            navigationStoppingOrDisposing: false,
          ),
          isFalse,
        );
        final pending = _eligibility(choice: choice);
        final pendingHandoff = _handoff(
          eligibility: pending,
          choice: choice,
          // Caller must not pass native3dRendererActive until configure ack.
          native3dRendererActive: false,
        );
        expect(pending.reason, isNot('vehicle_choice_2d'));
        expect(pendingHandoff.driver3dVisualReady, isFalse);
        expect(
          resolveNav3dHudShouldHide(
            hideHudFlagEnabled: true,
            driver3dVisualReady: pendingHandoff.driver3dVisualReady,
          ),
          isFalse,
        );

        // Stale/failed command (ack lost / generation not current).
        expect(
          resolveNative3dRendererCrediblyActive(
            requested3d: true,
            nativeFollowSessionActive: true,
            nativePresetConfigureAcknowledged: true,
            nativeCommandGenerationCurrent: false,
            navigationStoppingOrDisposing: false,
          ),
          isFalse,
        );

        // Credibly active current generation → visual-ready after eligibility.
        expect(
          resolveNative3dRendererCrediblyActive(
            requested3d: true,
            nativeFollowSessionActive: true,
            nativePresetConfigureAcknowledged: true,
            nativeCommandGenerationCurrent: true,
            navigationStoppingOrDisposing: false,
            locationComponentEnabledForNative: true,
          ),
          isTrue,
        );
        final ready = _eligibility(
          choice: choice,
          native3dRendererActive: true,
        );
        final readyHandoff = _handoff(
          eligibility: ready,
          choice: choice,
          native3dRendererActive: true,
        );
        expect(ready.driver3dVisualReady, isTrue);
        expect(readyHandoff.ownership.hudMounted, isFalse);
      },
    );
  });
}
