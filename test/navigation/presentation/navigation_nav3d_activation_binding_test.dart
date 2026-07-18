import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/navigation/driver_navigation_map_config.dart';
import 'package:fluxidi_tracking/navigation/presentation/navigation_driver_vehicle_model_layer.dart';
import 'package:fluxidi_tracking/navigation/presentation/navigation_presentation_mode.dart';

Driver3dVehicleEligibility eligibility({
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
  bool sessionFallback2d = false,
  DriverVehiclePresentationChoice selected =
      DriverVehiclePresentationChoice.fluxidi3d,
}) {
  return resolveDriver3dVehicleEligibility(
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
    sessionFallback2d: sessionFallback2d,
    styleLoaded: true,
    styleSwapInProgress: false,
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
    selectedVehiclePresentation: selected,
  );
}

DriverVisualOwnership ownership({
  required bool driver3dVisualReady,
  bool sessionFallback2d = false,
  DriverVehiclePresentationChoice selected =
      DriverVehiclePresentationChoice.fluxidi3d,
}) {
  return resolveDriverVisualOwnership(
    followLiveActive: true,
    showDriverHudOverlay: true,
    hideHudFlagEnabled: true,
    driver3dVisualReady: driver3dVisualReady,
    explicit2dFallback: sessionFallback2d,
    selectedVehiclePresentation: selected,
    runtimeFallbackState: resolveDriverVehicleRuntimeFallbackState(
      selectedVehiclePresentation: selected,
      sessionFallback2d: sessionFallback2d,
    ),
    presentation3dIntentActive: true,
  );
}

void main() {
  group('NAV-3D-ACTIVATION-BINDING-JANK-1 model-id contract', () {
    test('registered_id is the sole product model-id mode', () {
      for (final preset in DriverVehicle3dPreset.values) {
        final contract = resolveDriverVehicle3dBindingContract(preset);
        expect(contract.modelIdMode, kDriverVehicleModelIdModeRegistered);
        expect(contract.registeredModelId, isNot(contains('asset://')));
        expect(
          resolveDriverVehicleModelLayerModelId(
            debugPlacementActive: false,
            preset: preset,
          ),
          contract.registeredModelId,
        );
        expect(
          resolveDriverVehicleModelIdModeLabel(
            debugPlacementActive: false,
            preset: preset,
          ),
          kDriverVehicleModelIdModeRegistered,
        );
        expect(
          resolveDriverVehicleModelRequiresStyleModelRegistration(
            debugPlacementActive: false,
          ),
          isTrue,
        );
        expect(
          contract.layerModelIdExpression,
          ['get', kDriverVehicleModelSourceModelIdProperty],
        );
      }
    });

    test('feature, layer expression and registered id share one contract', () {
      const preset = DriverVehicle3dPreset.fluxidiTaxi;
      final contract = resolveDriverVehicle3dBindingContract(preset);
      final geo = driverVehicleModelGeoJsonData(
        lon: 24.94,
        lat: 60.17,
        modelId: contract.registeredModelId,
      );
      final parsed = parseDriverVehicleModelSourceJson(geo);

      expect(geo, contains('"type":"Feature"'));
      expect(geo, contains('"$kDriverVehicleModelSourceModelIdProperty"'));
      expect(parsed.sourceFeaturePresent, isTrue);
      expect(parsed.sourceModelId, contract.registeredModelId);
      expect(
        resolveNav3dVehicleModelIdBound(
          actualModelId: parsed.sourceModelId,
          expectedModelId: contract.registeredModelId,
        ),
        isTrue,
      );
      expect(
        resolveNav3dVehicleLayerModelIdBound(
          layerModelId: null,
          modelIdExpression: contract.layerModelIdExpression,
          expectedRegisteredModelId: contract.registeredModelId,
        ),
        isTrue,
      );
      expect(
        resolveNav3dVehicleLayerModelIdBound(
          layerModelId: contract.assetUri,
          modelIdExpression: null,
          expectedRegisteredModelId: contract.registeredModelId,
        ),
        isFalse,
      );
    });

    test('missing or wrong source-feature model_id blocks activation', () {
      final contract = resolveDriverVehicle3dBindingContract(
        DriverVehicle3dPreset.fluxidiTaxi,
      );
      final missing = parseDriverVehicleModelSourceJson(
        '{"type":"Feature","geometry":{"type":"Point","coordinates":[1,2]},'
        '"properties":{}}',
      );
      expect(missing.sourceFeaturePresent, isTrue);
      expect(missing.sourceModelId, isNull);
      expect(
        resolveNav3dVehicleModelIdBound(
          actualModelId: missing.sourceModelId,
          expectedModelId: contract.registeredModelId,
        ),
        isFalse,
      );

      final wrong = parseDriverVehicleModelSourceJson(
        '{"type":"Feature","geometry":{"type":"Point","coordinates":[1,2]},'
        '"properties":{"model_id":"asset://assets/navigation/driver_taxi_3d.glb"}}',
      );
      expect(
        resolveNav3dVehicleModelIdBound(
          actualModelId: wrong.sourceModelId,
          expectedModelId: contract.registeredModelId,
        ),
        isFalse,
      );
    });
  });

  group('NAV-3D-ACTIVATION-BINDING-JANK-1 2D/3D handoff', () {
    test('1. selected but not registered => 2D visible', () {
      final e = eligibility(selected: DriverVehiclePresentationChoice.fluxidi3d);
      expect(e.eligible, isTrue);
      expect(e.driver3dVisualReady, isFalse);
      expect(e.mapbox2dTaxiHidden, isFalse);
      expect(e.hudTaxiHidden, isFalse);

      final o = ownership(driver3dVisualReady: false);
      expect(o.owner, DriverVisualOwner.hud2d);
      expect(o.hudMounted, isTrue);
      expect(o.reason, isNot('model3d_selected_pending'));
    });

    test('2. registered but feature missing => 2D visible', () {
      final e = eligibility(
        modelRegistered: true,
        layerCreated: true,
        sourceGeometryValid: false,
        modelPoseApplied: false,
        modelLayerStyleGeneration: 3,
        modelLayerPresetGeneration: 2,
      );
      expect(e.driver3dVisualReady, isFalse);
      expect(e.mapbox2dTaxiHidden, isFalse);
      expect(e.hudTaxiHidden, isFalse);
    });

    test('3. feature exists but binding wrong => activation not confirmed', () {
      expect(
        resolveIsDriver3dVehicleActivationConfirmed(
          modelActivationConfirmed: false,
          renderCredibilityConfirmed: false,
          eligible: true,
          explicit2dFallback: false,
        ),
        isFalse,
      );
      final e = eligibility(
        modelRegistered: true,
        layerCreated: true,
        sourceGeometryValid: true,
        modelPoseApplied: true,
        modelActivationConfirmed: false,
        renderCredibilityConfirmed: false,
        modelLayerStyleGeneration: 3,
        modelLayerPresetGeneration: 2,
      );
      expect(e.driver3dVisualReady, isFalse);
      expect(e.mapbox2dTaxiHidden, isFalse);
    });

    test('4. first pose applied but verification pending => 2D visible', () {
      final e = eligibility(
        modelRegistered: true,
        layerCreated: true,
        sourceGeometryValid: true,
        modelPoseApplied: true,
        modelActivationConfirmed: false,
        renderCredibilityConfirmed: false,
        activeStyleGeneration: 3,
        activePresetGeneration: 2,
        modelLayerStyleGeneration: 3,
        modelLayerPresetGeneration: 2,
      );
      expect(e.driver3dVisualReady, isFalse);
      expect(e.hudTaxiHidden, isFalse);
      expect(e.mapbox2dTaxiHidden, isFalse);
      expect(ownership(driver3dVisualReady: false).hudMounted, isTrue);
    });

    test('5. activation confirmed => 2D may hide', () {
      final e = eligibility(
        modelRegistered: true,
        layerCreated: true,
        sourceGeometryValid: true,
        modelPoseApplied: true,
        modelActivationConfirmed: true,
        renderCredibilityConfirmed: true,
        activeStyleGeneration: 3,
        activePresetGeneration: 2,
        confirmedStyleGeneration: 3,
        confirmedPresetGeneration: 2,
        modelLayerStyleGeneration: 3,
        modelLayerPresetGeneration: 2,
      );
      expect(e.driver3dVisualReady, isTrue);
      expect(e.mapbox2dTaxiHidden, isTrue);
      expect(e.hudTaxiHidden, isTrue);
      final o = ownership(driver3dVisualReady: true);
      expect(o.owner, DriverVisualOwner.model3d);
      expect(o.hudMounted, isFalse);
    });

    test('6. activation falls back => 2D immediately visible', () {
      final e = eligibility(sessionFallback2d: true);
      expect(e.driver3dVisualReady, isFalse);
      expect(e.mapbox2dTaxiHidden, isFalse);
      expect(e.hudTaxiHidden, isFalse);
      final o = ownership(
        driver3dVisualReady: false,
        sessionFallback2d: true,
      );
      expect(o.owner, DriverVisualOwner.hud2d);
      expect(o.hudMounted, isTrue);
      expect(o.reason, 'temporary_2d_fallback');
    });
  });

  group('NAV-3D-ACTIVATION-BINDING-JANK-1 async guards + failures', () {
    test('late success after timeout is ignored; one failure counted', () {
      final lifecycle = NavVehicleModelSyncLifecycle();
      final started = DateTime(2026, 7, 18, 8);

      expect(lifecycle.beginMovementUpdate(started), isTrue);
      final opId = lifecycle.activeMovementOperationId;
      expect(opId, isNotNull);

      final timedOutAt = started.add(
        Duration(milliseconds: kDriverVehicleModelMovementTimeoutMs + 5),
      );
      lifecycle.bumpMovementGeneration();
      expect(
        lifecycle.finishMovementUpdate(
          applied: false,
          now: timedOutAt,
          timedOut: true,
          countFailure: false,
          operationId: opId,
        ),
        isFalse,
      );
      expect(lifecycle.consecutiveFailures, 1);

      // Late success for the same operation must not mutate state.
      expect(
        lifecycle.finishMovementUpdate(
          applied: true,
          now: timedOutAt.add(const Duration(milliseconds: 70)),
          timedOut: false,
          countFailure: false,
          operationId: opId,
        ),
        isFalse,
      );
      expect(lifecycle.consecutiveFailures, 1);
      expect(lifecycle.sessionFallback2d, isFalse);
    });

    test('late failure after timeout is not double-counted', () {
      final lifecycle = NavVehicleModelSyncLifecycle();
      final now = DateTime(2026, 7, 18, 9);
      expect(lifecycle.beginMovementUpdate(now), isTrue);
      final opId = lifecycle.activeMovementOperationId!;

      lifecycle.finishMovementUpdate(
        applied: false,
        now: now,
        timedOut: true,
        operationId: opId,
      );
      expect(lifecycle.consecutiveFailures, 1);

      lifecycle.finishMovementUpdate(
        applied: false,
        now: now,
        timedOut: false,
        countFailure: true,
        operationId: opId,
      );
      expect(lifecycle.consecutiveFailures, 1);
    });

    test('fallback is idempotent and invalidates generation', () {
      final lifecycle = NavVehicleModelSyncLifecycle();
      final gen0 = lifecycle.movementGeneration;
      expect(lifecycle.enableSessionFallback2d(), isTrue);
      expect(lifecycle.sessionFallback2d, isTrue);
      expect(lifecycle.movementGeneration, greaterThan(gen0));
      expect(lifecycle.enableSessionFallback2d(), isFalse);
      expect(lifecycle.fallbackStarted, isTrue);
      expect(lifecycle.queueMovement(
        DriverVehicle3dMovementPose(
          lon: 1,
          lat: 2,
          bearingDeg: 0,
          source: 'test',
          appliedZoom: 17,
          appliedPitch: 60,
          preset: DriverVehicle3dPreset.fluxidiTaxi,
          movementGeneration: lifecycle.movementGeneration,
        ),
      ), 'ignored');
    });

    test('preset/style swap generation mismatch blocks visual ready', () {
      final duringPresetSwap = eligibility(
        modelRegistered: true,
        layerCreated: true,
        sourceGeometryValid: true,
        modelPoseApplied: true,
        modelActivationConfirmed: true,
        renderCredibilityConfirmed: true,
        activeStyleGeneration: 3,
        activePresetGeneration: 5,
        confirmedStyleGeneration: 3,
        confirmedPresetGeneration: 4,
        modelLayerStyleGeneration: 3,
        modelLayerPresetGeneration: 4,
      );
      expect(duringPresetSwap.driver3dVisualReady, isFalse);

      final duringStyleSwap = eligibility(
        modelRegistered: true,
        layerCreated: true,
        sourceGeometryValid: true,
        modelPoseApplied: true,
        modelActivationConfirmed: true,
        renderCredibilityConfirmed: true,
        activeStyleGeneration: 8,
        activePresetGeneration: 2,
        confirmedStyleGeneration: 7,
        confirmedPresetGeneration: 2,
        modelLayerStyleGeneration: 7,
        modelLayerPresetGeneration: 2,
      );
      expect(duringStyleSwap.driver3dVisualReady, isFalse);
    });

    test('teardown/reset clears settle state; new generation can activate', () {
      final lifecycle = NavVehicleModelSyncLifecycle();
      expect(lifecycle.beginMovementUpdate(DateTime(2026, 7, 18)), isTrue);
      lifecycle.enableSessionFallback2d();
      expect(lifecycle.sessionFallback2d, isTrue);

      lifecycle.resetForNewNavigationSession();
      expect(lifecycle.sessionFallback2d, isFalse);
      expect(lifecycle.fallbackStarted, isFalse);
      expect(lifecycle.consecutiveFailures, 0);
      expect(lifecycle.movementGeneration, 0);

      final e = eligibility(
        modelRegistered: true,
        layerCreated: true,
        sourceGeometryValid: true,
        modelPoseApplied: true,
        modelActivationConfirmed: true,
        renderCredibilityConfirmed: true,
        activeStyleGeneration: 1,
        activePresetGeneration: 1,
        confirmedStyleGeneration: 1,
        confirmedPresetGeneration: 1,
        modelLayerStyleGeneration: 1,
        modelLayerPresetGeneration: 1,
      );
      expect(e.driver3dVisualReady, isTrue);
      expect(e.mapbox2dTaxiHidden, isTrue);
    });

    test('activation retry budget is bounded to one delay', () {
      expect(kNav3dActivationConfirmRetryDelaysMs.length, 1);
      final budget = Nav3dActivationConfirmRetryLifecycle();
      expect(
        budget.nextDelay(styleGeneration: 1, presetGeneration: 1),
        isNotNull,
      );
      expect(
        budget.nextDelay(styleGeneration: 1, presetGeneration: 1),
        isNull,
      );
      expect(budget.markExhaustedOnce(), isTrue);
      expect(budget.markExhaustedOnce(), isFalse);
    });
  });
}
