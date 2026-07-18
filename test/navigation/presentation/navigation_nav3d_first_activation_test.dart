import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/navigation/driver_navigation_map_config.dart';
import 'package:fluxidi_tracking/navigation/presentation/navigation_driver_vehicle_model_layer.dart';
import 'package:fluxidi_tracking/navigation/presentation/navigation_presentation_mode.dart';

void main() {
  group('NAV-3D-FIRST-ACTIVATION-AND-REAL-2D-OVERLAY-FIX-1', () {
    test('first pose bypasses movement throttle', () {
      expect(
        resolveDriver3dVehicleFirstPoseBypassThrottle(
          force: false,
          firstPoseRequired: true,
        ),
        isTrue,
      );
      expect(
        resolveDriver3dVehicleFirstPoseBypassThrottle(
          force: true,
          firstPoseRequired: false,
        ),
        isTrue,
      );
      expect(
        resolveDriver3dVehicleFirstPoseBypassThrottle(
          force: false,
          firstPoseRequired: false,
        ),
        isFalse,
      );
    });

    test('skipped unchanged on first pose still confirms activation', () {
      expect(
        resolveNav3dFirstActivationConfirmsOnSkippedUnchanged(
          firstPoseRequired: true,
        ),
        isTrue,
      );
      expect(
        resolveNav3dFirstActivationConfirmsOnSkippedUnchanged(
          firstPoseRequired: false,
        ),
        isFalse,
      );
    });

    test('movement write plan forces native write when applied state is null', () {
      final plan = resolveDriverVehicleModelMovementWritePlan(
        applied: null,
        lon: 4.9,
        lat: 52.3,
        bearingDeg: 90,
        preset: DriverVehicle3dPreset.fluxidiTaxi,
        scale: const [1, 1, 1],
        translation: const [0, 0, 0.2],
        rotation: const [0, 0, 90],
        force: false,
      );
      expect(plan.positionChanged, isTrue);
      expect(plan.rotationChanged, isTrue);
      expect(plan.scaleChanged, isTrue);
      expect(plan.translationChanged, isTrue);
    });

    test('first pose force flag requires native write even with matching applied state',
        () {
      const applied = DriverVehicleModelAppliedMovementState(
        lon: 4.9,
        lat: 52.3,
        bearingDeg: 90,
        preset: DriverVehicle3dPreset.fluxidiTaxi,
        scale: [7.7, 7.7, 7.7],
        translation: [0, 0, 0.2],
        rotation: [0, 0, 90],
      );
      final plan = resolveDriverVehicleModelMovementWritePlan(
        applied: applied,
        lon: 4.9,
        lat: 52.3,
        bearingDeg: 90,
        preset: DriverVehicle3dPreset.fluxidiTaxi,
        scale: const [7.7, 7.7, 7.7],
        translation: const [0, 0, 0.2],
        rotation: const [0, 0, 90],
        force: true,
      );
      expect(plan.positionChanged, isTrue);
      expect(plan.rotationChanged, isTrue);
    });

    test('3D eligible registration path marks first pose required on style restore', () {
      final lifecycle = NavVehicleModelSyncLifecycle();
      lifecycle.clearMovementStateForStyleRestore(movementGeneration: 0);
      expect(lifecycle.firstPoseRequired, isTrue);
      expect(lifecycle.movementGeneration, 0);
    });

    test('first 2D to Fluxidi activation resumes shared swap lifecycle first', () {
      final lifecycle = NavVehicleModelSyncLifecycle();
      lifecycle.pauseForSwap();
      final generation = lifecycle.bumpMovementGeneration();
      lifecycle.resumeAfterSwap(movementGeneration: generation);
      final pose = DriverVehicle3dMovementPose(
        lon: 4.9,
        lat: 52.3,
        bearingDeg: 180,
        source: 'first_pose_register_done',
        appliedZoom: 17.8,
        appliedPitch: 45,
        preset: DriverVehicle3dPreset.fluxidiTaxi,
        movementGeneration: generation,
      );
      expect(lifecycle.queueMovement(pose), 'queued');
      expect(lifecycle.shouldIgnoreStaleMovement(generation), isFalse);
    });

    test('first 2D to Classic activation uses the same resumed pose path', () {
      final lifecycle = NavVehicleModelSyncLifecycle();
      lifecycle.pauseForSwap();
      final generation = lifecycle.bumpMovementGeneration();
      lifecycle.resumeAfterSwap(movementGeneration: generation);
      final pose = DriverVehicle3dMovementPose(
        lon: 4.9,
        lat: 52.3,
        bearingDeg: 180,
        source: 'first_pose_register_done',
        appliedZoom: 17.8,
        appliedPitch: 45,
        preset: DriverVehicle3dPreset.classicFlyingTaxi,
        movementGeneration: generation,
      );
      expect(lifecycle.queueMovement(pose), 'queued');
      expect(lifecycle.shouldIgnoreStaleMovement(generation), isFalse);
      expect(lifecycle.firstPoseRequired, isTrue);
    });

    test('stale movement generation is requeued for first pose', () {
      final lifecycle = NavVehicleModelSyncLifecycle();
      lifecycle.clearMovementStateForStyleRestore(movementGeneration: 1);
      expect(
        lifecycle.shouldIgnoreStaleMovement(0),
        isTrue,
      );
      lifecycle.requeuePose(
        DriverVehicle3dMovementPose(
          lon: 4.9,
          lat: 52.3,
          bearingDeg: 180,
          source: 'first_pose_register_done',
          appliedZoom: 17.8,
          appliedPitch: 45,
          preset: DriverVehicle3dPreset.fluxidiTaxi,
          movementGeneration: 1,
        ),
      );
      expect(lifecycle.latestRequest?.movementGeneration, 1);
    });

    test('visual-ready 3D + hideHud hides HUD widget mount gate', () {
      final eligibility = resolveDriver3dVehicleEligibility(
        vehicleModelFlagEnabled: true,
        cockpitSceneEnabled: true,
        useDriverCockpitCamera: true,
        presentationMode: NavigationPresentationMode.driver,
        liveNavigationActive: true,
        followCamera: true,
        activeStyleUri: kDriverMapStyleStandard,
        visualMode: DriverMapVisualMode.street,
        cockpitSceneActive: true,
        cockpitVisualStyle: DriverCockpitMapVisualStyle.standard3d,
        sessionFallback2d: false,
        styleLoaded: true,
        styleSwapInProgress: false,
        modelRegistered: true,
        modelPoseApplied: true,
        hideHudIsolationFlagEnabled: true,
        layerCreated: true,
        sourceGeometryValid: true,
        modelActivationConfirmed: true,
        renderCredibilityConfirmed: true,
        assetLoaded: true,
        activeStyleGeneration: 2,
        activePresetGeneration: 0,
        confirmedStyleGeneration: 2,
        confirmedPresetGeneration: 0,
        modelLayerStyleGeneration: 2,
        modelLayerPresetGeneration: 0,
        followLiveActive: true,
        useDriver3dVehicleModel: true,
      );
      final handoff = resolveNav3dHudHandoffForRender(
        eligibility: eligibility,
        useDriver3dVehicleModel: true,
        followLiveActive: true,
        observationalAssetLoaded: true,
        handoffAssetLoaded: true,
        modelRegistered: true,
        layerCreated: true,
        sourceGeometryValid: true,
        modelPoseApplied: true,
        modelActivationConfirmed: true,
        renderCredibilityConfirmed: true,
        activeStyleGeneration: 2,
        activePresetGeneration: 0,
        modelLayerStyleGeneration: 2,
        modelLayerPresetGeneration: 0,
        confirmedStyleGeneration: 2,
        confirmedPresetGeneration: 0,
        showDriverHudOverlay: true,
        hideHudFlagEnabled: true,
        explicit2dFallback: false,
      );
      final decision = resolveNav3dHudRenderDecision(
        hideHudFlagEnabled: true,
        presentation3dActive: handoff.presentation3dActive,
        driver3dVisualReady: handoff.driver3dVisualReady,
        effectivelyActive: handoff.effectivelyActive,
        hudFallbackAllowedToHide: handoff.hudFallbackAllowedToHide,
        showDriverHudOverlay: true,
        followLiveActive: true,
        explicit2dFallback: false,
        ownership: handoff.ownership,
      );
      expect(decision.actualHudVisible, isFalse);
      expect(decision.mapbox2dVisible, isFalse);
    });

    test('before first pose HUD fallback stays visible (Mapbox suppressed by isolation)',
        () {
      final eligibility = resolveDriver3dVehicleEligibility(
        vehicleModelFlagEnabled: true,
        cockpitSceneEnabled: true,
        useDriverCockpitCamera: true,
        presentationMode: NavigationPresentationMode.driver,
        liveNavigationActive: true,
        followCamera: true,
        activeStyleUri: kDriverMapStyleStandard,
        visualMode: DriverMapVisualMode.street,
        cockpitSceneActive: true,
        cockpitVisualStyle: DriverCockpitMapVisualStyle.standard3d,
        sessionFallback2d: false,
        styleLoaded: true,
        styleSwapInProgress: false,
        modelRegistered: true,
        modelPoseApplied: false,
        hideHudIsolationFlagEnabled: true,
        layerCreated: true,
        sourceGeometryValid: true,
        modelActivationConfirmed: false,
        renderCredibilityConfirmed: false,
        assetLoaded: true,
        activeStyleGeneration: 2,
        activePresetGeneration: 0,
        confirmedStyleGeneration: -1,
        confirmedPresetGeneration: -1,
      );
      final handoff = resolveNav3dHudHandoffForRender(
        eligibility: eligibility,
        useDriver3dVehicleModel: true,
        followLiveActive: true,
        observationalAssetLoaded: true,
        handoffAssetLoaded: true,
        modelRegistered: true,
        layerCreated: true,
        sourceGeometryValid: true,
        modelPoseApplied: false,
        modelActivationConfirmed: false,
        renderCredibilityConfirmed: false,
        activeStyleGeneration: 2,
        activePresetGeneration: 0,
        modelLayerStyleGeneration: -1,
        modelLayerPresetGeneration: -1,
        confirmedStyleGeneration: -1,
        confirmedPresetGeneration: -1,
        showDriverHudOverlay: true,
        hideHudFlagEnabled: true,
        explicit2dFallback: false,
      );
      final decision = resolveNav3dHudRenderDecision(
        hideHudFlagEnabled: true,
        presentation3dActive: handoff.presentation3dActive,
        driver3dVisualReady: handoff.driver3dVisualReady,
        effectivelyActive: handoff.effectivelyActive,
        hudFallbackAllowedToHide: handoff.hudFallbackAllowedToHide,
        showDriverHudOverlay: true,
        followLiveActive: true,
        explicit2dFallback: false,
        ownership: handoff.ownership,
      );
      expect(decision.actualHudVisible, isTrue);
      expect(decision.mapbox2dVisible, isFalse);
    });

    test('preset swap unconfirmed shows fallback then hides after generation match', () {
      final unconfirmed = resolveNav3dHudRenderDecision(
        hideHudFlagEnabled: true,
        presentation3dActive: true,
        driver3dVisualReady: false,
        effectivelyActive: false,
        hudFallbackAllowedToHide: false,
        showDriverHudOverlay: true,
        followLiveActive: true,
        explicit2dFallback: false,
      );
      expect(unconfirmed.actualHudVisible, isTrue);

      final confirmed = resolveNav3dHudRenderDecision(
        hideHudFlagEnabled: true,
        presentation3dActive: true,
        driver3dVisualReady: true,
        effectivelyActive: true,
        hudFallbackAllowedToHide: true,
        showDriverHudOverlay: true,
        followLiveActive: true,
        explicit2dFallback: false,
      );
      expect(confirmed.actualHudVisible, isFalse);
      expect(confirmed.mapbox2dVisible, isFalse);
    });

    test('style switch away from 3D restores 2D fallback visibility', () {
      final decision = resolveNav3dHudRenderDecision(
        hideHudFlagEnabled: true,
        presentation3dActive: false,
        driver3dVisualReady: false,
        effectivelyActive: false,
        hudFallbackAllowedToHide: false,
        showDriverHudOverlay: true,
        followLiveActive: true,
        explicit2dFallback: false,
      );
      expect(decision.actualHudVisible, isTrue);
      expect(decision.mapbox2dVisible, isFalse);
    });

    test('stale model-layer generations keep HUD fallback visible', () {
      final eligibility = resolveDriver3dVehicleEligibility(
        vehicleModelFlagEnabled: true,
        cockpitSceneEnabled: true,
        useDriverCockpitCamera: true,
        presentationMode: NavigationPresentationMode.driver,
        liveNavigationActive: true,
        followCamera: true,
        activeStyleUri: kDriverMapStyleStandard,
        visualMode: DriverMapVisualMode.street,
        cockpitSceneActive: true,
        cockpitVisualStyle: DriverCockpitMapVisualStyle.standard3d,
        sessionFallback2d: false,
        styleLoaded: true,
        styleSwapInProgress: false,
        modelRegistered: true,
        modelPoseApplied: true,
        hideHudIsolationFlagEnabled: true,
        layerCreated: true,
        sourceGeometryValid: true,
        modelActivationConfirmed: true,
        renderCredibilityConfirmed: true,
        assetLoaded: true,
        activeStyleGeneration: 3,
        activePresetGeneration: 1,
        confirmedStyleGeneration: 2,
        confirmedPresetGeneration: 1,
        modelLayerStyleGeneration: 2,
        modelLayerPresetGeneration: 1,
        followLiveActive: true,
        useDriver3dVehicleModel: true,
      );
      final handoff = resolveNav3dHudHandoffForRender(
        eligibility: eligibility,
        useDriver3dVehicleModel: true,
        followLiveActive: true,
        observationalAssetLoaded: true,
        handoffAssetLoaded: true,
        modelRegistered: true,
        layerCreated: true,
        sourceGeometryValid: true,
        modelPoseApplied: true,
        modelActivationConfirmed: true,
        renderCredibilityConfirmed: true,
        activeStyleGeneration: 3,
        activePresetGeneration: 1,
        modelLayerStyleGeneration: 2,
        modelLayerPresetGeneration: 1,
        confirmedStyleGeneration: 2,
        confirmedPresetGeneration: 1,
        showDriverHudOverlay: true,
        hideHudFlagEnabled: true,
        explicit2dFallback: false,
      );
      expect(handoff.driver3dVisualReady, isFalse);
      expect(handoff.hudFallbackAllowedToHide, isFalse);
    });
  });
}
