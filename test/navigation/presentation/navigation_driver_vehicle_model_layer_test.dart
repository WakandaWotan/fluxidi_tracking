import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/navigation/driver_navigation_map_config.dart';
import 'package:fluxidi_tracking/navigation/presentation/navigation_driver_vehicle_model_layer.dart';
import 'package:fluxidi_tracking/navigation/presentation/navigation_presentation_flags.dart';
import 'package:fluxidi_tracking/navigation/presentation/navigation_presentation_mode.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mb;

void main() {
  Driver3dVehicleEligibility dedicated3dEligibility({
    bool modelRegistered = false,
    bool modelPoseApplied = false,
    bool layerCreated = false,
    bool sourceGeometryValid = false,
    bool modelActivationConfirmed = false,
    bool renderCredibilityConfirmed = false,
    bool assetLoaded = true,
    bool debugRenderProbeActive = false,
    int activeStyleGeneration = 0,
    int activePresetGeneration = 0,
    int confirmedStyleGeneration = -1,
    int confirmedPresetGeneration = -1,
    int modelLayerStyleGeneration = -1,
    int modelLayerPresetGeneration = -1,
    bool sessionFallback2d = false,
    bool styleLoaded = true,
    bool styleSwapInProgress = false,
    bool hideHudIsolationFlagEnabled = true,
    NavigationPresentationMode presentationMode =
        NavigationPresentationMode.driver,
    String? activeStyleUri = kDriverMapStyleStandard,
    DriverCockpitMapVisualStyle? cockpitVisualStyle =
        DriverCockpitMapVisualStyle.standard3d,
    bool liveNavigationActive = true,
    bool followCamera = true,
  }) {
    return resolveDriver3dVehicleEligibility(
      vehicleModelFlagEnabled: true,
      cockpitSceneEnabled: true,
      useDriverCockpitCamera: true,
      presentationMode: presentationMode,
      liveNavigationActive: liveNavigationActive,
      followCamera: followCamera,
      activeStyleUri: activeStyleUri,
      visualMode: DriverMapVisualMode.street,
      cockpitSceneActive: true,
      cockpitVisualStyle: cockpitVisualStyle,
      sessionFallback2d: sessionFallback2d,
      styleLoaded: styleLoaded,
      styleSwapInProgress: styleSwapInProgress,
      modelRegistered: modelRegistered,
      modelPoseApplied: modelPoseApplied,
      hideHudIsolationFlagEnabled: hideHudIsolationFlagEnabled,
      layerCreated: layerCreated,
      sourceGeometryValid: sourceGeometryValid,
      modelActivationConfirmed: modelActivationConfirmed,
      renderCredibilityConfirmed: renderCredibilityConfirmed,
      assetLoaded: assetLoaded,
      debugRenderProbeActive: debugRenderProbeActive,
      activeStyleGeneration: activeStyleGeneration,
      activePresetGeneration: activePresetGeneration,
      confirmedStyleGeneration: confirmedStyleGeneration,
      confirmedPresetGeneration: confirmedPresetGeneration,
      modelLayerStyleGeneration: modelLayerStyleGeneration,
      modelLayerPresetGeneration: modelLayerPresetGeneration,
      followLiveActive: true,
      useDriver3dVehicleModel: true,
    );
  }

  Driver3dVehicleEligibility confirmed3dHandoffEligibility({
    int styleGeneration = 3,
    int presetGeneration = 2,
    bool hideHudIsolationFlagEnabled = true,
  }) {
    return dedicated3dEligibility(
      modelRegistered: true,
      layerCreated: true,
      sourceGeometryValid: true,
      modelPoseApplied: true,
      modelActivationConfirmed: true,
      renderCredibilityConfirmed: true,
      assetLoaded: true,
      activeStyleGeneration: styleGeneration,
      activePresetGeneration: presetGeneration,
      confirmedStyleGeneration: styleGeneration,
      confirmedPresetGeneration: presetGeneration,
      modelLayerStyleGeneration: styleGeneration,
      modelLayerPresetGeneration: presetGeneration,
      hideHudIsolationFlagEnabled: hideHudIsolationFlagEnabled,
    );
  }

  group('NAV-PRES-3K-B driver vehicle model layer', () {
    test('flag defaults to false', () {
      expect(kNavigation3dVehicleModelEnabled, isFalse);
      expect(navigation3dVehicleModelFlagDefaultOff(), isTrue);
      expect(
        kNavigation3dVehicleModelDefineKey,
        'FLUXIDI_NAV_3D_VEHICLE_MODEL',
      );
      expect(kNavigation3dVehicleHideHudEnabled, isFalse);
      expect(navigation3dVehicleHideHudFlagDefaultOff(), isTrue);
      expect(
        kNavigation3dVehicleHideHudDefineKey,
        'FLUXIDI_NAV_3D_VEHICLE_HIDE_HUD',
      );
      expect(kNavigation3dVehicleDebugPlacementEnabled, isFalse);
      expect(navigation3dVehicleDebugPlacementFlagDefaultOff(), isTrue);
      expect(
        kNavigation3dVehicleDebugPlacementDefineKey,
        'FLUXIDI_NAV_3D_VEHICLE_DEBUG_PLACEMENT',
      );
    });

    test('asset URI uses asset:// scheme for bundled GLB', () {
      expect(
        kDriverVehicleModelAssetUri,
        'asset://assets/navigation/driver_taxi_3d.glb',
      );
    });

    test('model ids are stable and non-empty', () {
      expect(kDriverVehicleModelId, isNotEmpty);
      expect(kDriverVehicleModelSourceId, isNotEmpty);
      expect(kDriverVehicleModelLayerId, isNotEmpty);
      expect(kDriverVehicleDebugStyleDotSourceId, isNotEmpty);
      expect(kDriverVehicleDebugStyleDotLayerId, isNotEmpty);
      expect(kDriverVehicleModelId, 'fluxidi-driver-taxi-3d');
      expect(kDriverVehicleModelSourceId, 'fluxidi-driver-vehicle-source');
      expect(kDriverVehicleModelLayerId, 'fluxidi-driver-vehicle-model');
      expect(
        kDriverVehicleDebugStyleDotSourceId,
        'fluxidi-driver-vehicle-debug-dot-source',
      );
      expect(
        kDriverVehicleDebugStyleDotLayerId,
        'fluxidi-driver-vehicle-debug-dot',
      );
    });

    test('adaptive scale constants define piecewise calibration bounds', () {
      expect(kDriverVehicleModelScaleCalibrationPoints, [
        (16.5, 10.8),
        (17.2, 9.2),
        (18.0, 7.2),
        (18.7, 5.8),
        (19.1, 5.0),
        (19.9, 3.8),
        (21.0, 2.75),
      ]);
      expect(kDriverVehicleModelScaleMin, 2.4);
      expect(kDriverVehicleModelScaleMax, 11.5);
    });

    test('presentation active requires flag and cockpit camera', () {
      expect(
        resolveDriver3dVehicleModelPresentationActive(
          flagEnabled: false,
          useDriverCockpitCamera: true,
        ),
        isFalse,
      );
      expect(
        resolveDriver3dVehicleModelPresentationActive(
          flagEnabled: true,
          useDriverCockpitCamera: false,
        ),
        isFalse,
      );
      expect(
        resolveDriver3dVehicleModelPresentationActive(
          flagEnabled: true,
          useDriverCockpitCamera: true,
        ),
        isTrue,
      );
    });

    test(
      'runtime active requires presentation plus live follow and 3D style',
      () {
        const presentation = true;
        expect(
          resolveDriver3dVehicleModelRuntimeActive(
            presentationActive: presentation,
            liveRideActive: false,
            followCamera: true,
            styleActive: true,
          ),
          isFalse,
        );
        expect(
          resolveDriver3dVehicleModelRuntimeActive(
            presentationActive: presentation,
            liveRideActive: true,
            followCamera: false,
            styleActive: true,
          ),
          isFalse,
        );
        expect(
          resolveDriver3dVehicleModelRuntimeActive(
            presentationActive: presentation,
            liveRideActive: true,
            followCamera: true,
            styleActive: false,
          ),
          isFalse,
        );
        expect(
          resolveDriver3dVehicleModelRuntimeActive(
            presentationActive: presentation,
            liveRideActive: true,
            followCamera: true,
            styleActive: true,
          ),
          isTrue,
        );
        expect(
          resolveDriver3dVehicleModelRuntimeActive(
            presentationActive: false,
            liveRideActive: true,
            followCamera: true,
            styleActive: true,
          ),
          isFalse,
        );
      },
    );

    test('follow runtime excludes style gate', () {
      const presentation = true;
      expect(
        resolveDriver3dVehicleModelFollowRuntimeActive(
          presentationActive: presentation,
          liveRideActive: true,
          followCamera: true,
        ),
        isTrue,
      );
      expect(
        resolveDriver3dVehicleModelFollowRuntimeActive(
              presentationActive: presentation,
              liveRideActive: true,
              followCamera: true,
            ) &&
            resolveDriver3dVehicleModelStyleActive(
              activeStyleUri: kDriverMapStyleNavStreetLight,
              visualMode: DriverMapVisualMode.street,
            ),
        isFalse,
      );
    });

    test('2D taxi suppression only when HUD hide active at presentation', () {
      expect(
        resolveHideMapboxTaxiMarkerForPresentation(
          hideForHudOverlay: false,
          useDriver3dVehicleModel: false,
        ),
        isFalse,
      );
      expect(
        resolveHideMapboxTaxiMarkerForPresentation(
          hideForHudOverlay: true,
          useDriver3dVehicleModel: false,
        ),
        isTrue,
      );
      expect(
        resolveHideMapboxTaxiMarkerForPresentation(
          hideForHudOverlay: false,
          useDriver3dVehicleModel: true,
        ),
        isFalse,
      );
    });

    test('model rotation normalizes bearing to [0, 360)', () {
      expect(driverVehicleModelRotation(-15), [0, 0, 345]);
      expect(driverVehicleModelRotation(0), [0, 0, 0]);
      expect(driverVehicleModelRotation(90), [0, 0, 90]);
      expect(driverVehicleModelRotation(450), [0, 0, 90]);
      expect(normalizeDriverVehicleModelBearingDeg(720), 0);
    });

    test('geojson feature encodes lon/lat and registered model_id', () {
      final modelId = resolveDriverVehicle3dStyleModelId(
        DriverVehicle3dPreset.fluxidiTaxi,
      );
      final data = driverVehicleModelGeoJsonData(
        lon: 24.94,
        lat: 60.17,
        modelId: modelId,
      );
      expect(data, contains('"type":"Point"'));
      expect(data, contains('"type":"Feature"'));
      expect(data, isNot(contains('"type":"FeatureCollection"')));
      expect(data, contains('[24.94,60.17]'));
      expect(data, contains('"$kDriverVehicleModelSourceModelIdProperty"'));
      expect(data, isNot(contains('address')));
      final parsed = parseDriverVehicleModelSourceJson(data);
      expect(parsed.sourceFeaturePresent, isTrue);
      expect(parsed.sourceHasValidPosition, isTrue);
      expect(parsed.sourceModelId, modelId);
    });

    test('no behavior change when flag false', () {
      expect(
        resolveDriver3dVehicleModelPresentationActive(
          flagEnabled: kNavigation3dVehicleModelEnabled,
          useDriverCockpitCamera: true,
        ),
        isFalse,
      );
      expect(
        resolveHideMapboxTaxiMarkerForPresentation(
          hideForHudOverlay: false,
          useDriver3dVehicleModel: false,
        ),
        isFalse,
      );
      expect(
        resolveHideDriverHudVehicleFor3dVisualIsolation(
          driver3dVehicleModelEnabled: kNavigation3dVehicleModelEnabled,
          driver3dVehicleHideHudEnabled: kNavigation3dVehicleHideHudEnabled,
          useDriverCockpitCamera: true,
          isDriverMode: true,
        ),
        isFalse,
      );
    });
  });

  group('NAV-PRES-3K-C 3D vehicle visual isolation', () {
    test(
      'hide HUD requires 3D vehicle + hide flag + cockpit + driver mode',
      () {
        expect(
          resolveHideDriverHudVehicleFor3dVisualIsolation(
            driver3dVehicleModelEnabled: true,
            driver3dVehicleHideHudEnabled: true,
            useDriverCockpitCamera: true,
            isDriverMode: true,
          ),
          isTrue,
        );
        expect(
          resolveHideDriverHudVehicleFor3dVisualIsolation(
            driver3dVehicleModelEnabled: false,
            driver3dVehicleHideHudEnabled: true,
            useDriverCockpitCamera: true,
            isDriverMode: true,
          ),
          isFalse,
        );
        expect(
          resolveHideDriverHudVehicleFor3dVisualIsolation(
            driver3dVehicleModelEnabled: true,
            driver3dVehicleHideHudEnabled: false,
            useDriverCockpitCamera: true,
            isDriverMode: true,
          ),
          isFalse,
        );
        expect(
          resolveHideDriverHudVehicleFor3dVisualIsolation(
            driver3dVehicleModelEnabled: true,
            driver3dVehicleHideHudEnabled: true,
            useDriverCockpitCamera: false,
            isDriverMode: true,
          ),
          isFalse,
        );
        expect(
          resolveHideDriverHudVehicleFor3dVisualIsolation(
            driver3dVehicleModelEnabled: true,
            driver3dVehicleHideHudEnabled: true,
            useDriverCockpitCamera: true,
            isDriverMode: false,
          ),
          isFalse,
        );
      },
    );

    test('show HUD vehicle overlay respects isolation hide', () {
      expect(
        resolveShowDriverHudVehicleOverlay(
          showDriverHudOverlay: true,
          hideDriverHudVehicleOverlay: false,
        ),
        isTrue,
      );
      expect(
        resolveShowDriverHudVehicleOverlay(
          showDriverHudOverlay: true,
          hideDriverHudVehicleOverlay: true,
        ),
        isFalse,
      );
      expect(
        resolveShowDriverHudVehicleOverlay(
          showDriverHudOverlay: false,
          hideDriverHudVehicleOverlay: true,
        ),
        isFalse,
      );
    });

    test(
      'mapbox 2D taxi suppression unchanged by hide HUD flag at presentation',
      () {
        expect(
          resolveHideMapboxTaxiMarkerForPresentation(
            hideForHudOverlay: false,
            useDriver3dVehicleModel: true,
          ),
          isFalse,
        );
        expect(
          resolveHideMapboxTaxiMarkerForPresentation(
            hideForHudOverlay: false,
            useDriver3dVehicleModel: false,
          ),
          isFalse,
        );
      },
    );
  });

  group('NAV-PRES-3K-D 3D vehicle visibility calibration', () {
    test('final rotation includes base X/Y and normalized route heading', () {
      expect(resolveDriverVehicleModelFinalRotation(308), [0, 0, 308]);
      expect(
        resolveDriverVehicleModelFinalRotation(
          90,
          baseRotationXDeg: 5,
          baseRotationYDeg: -3,
        ),
        [5, -3, 90],
      );
    });

    test('heading offset normalization wraps route bearing + offset', () {
      expect(
        resolveDriverVehicleModelHeadingDeg(
          routeBearingDeg: 350,
          headingOffsetDeg: 20,
        ),
        10,
      );
      expect(
        resolveDriverVehicleModelHeadingDeg(
          routeBearingDeg: -15,
          headingOffsetDeg: 0,
        ),
        345,
      );
      expect(
        resolveDriverVehicleModelFinalRotation(350, headingOffsetDeg: 20),
        [0, 0, 10],
      );
    });

    test('translation lifts model by altitude constant', () {
      expect(driverVehicleModelTranslation(), [
        0,
        0,
        kDriverVehicleModelAltitudeMeters,
      ]);
      expect(driverVehicleModelTranslation(debugPlacementActive: true), [
        0,
        0,
        kDriverVehicleModelDebugAltitudeMeters,
      ]);
      expect(kDriverVehicleModelAltitudeMeters, greaterThanOrEqualTo(0));
    });

    test('calibration constants are easy to tune defaults', () {
      expect(kDriverVehicleModelBaseRotationXDeg, 0.0);
      expect(kDriverVehicleModelBaseRotationYDeg, 0.0);
      expect(kDriverVehicleModelHeadingOffsetDeg, 0.0);
      expect(kDriverVehicleModelAltitudeMeters, 0.2);
    });
  });

  group('NAV-PRES-3K-H4 adaptive 3D vehicle model scale', () {
    double scaleAt({required double zoom, double pitch = 70.0}) {
      return resolveDriverVehicleModelScale(
        appliedZoom: zoom,
        appliedPitch: pitch,
      ).first;
    }

    test('zoom 16.5 pitch 70 returns near 10.8', () {
      expect(scaleAt(zoom: 16.5, pitch: 70), closeTo(10.8, 0.05));
    });

    test('zoom 17.2 pitch 70 returns near 9.2', () {
      expect(scaleAt(zoom: 17.2, pitch: 70), closeTo(9.2, 0.05));
    });

    test('zoom 18.0 pitch 75 returns near 7.2', () {
      expect(scaleAt(zoom: 18.0, pitch: 75), closeTo(7.2, 0.05));
    });

    test('zoom 18.7 pitch 76 returns near 5.8', () {
      expect(scaleAt(zoom: 18.7, pitch: 76), closeTo(5.8, 0.05));
    });

    test('zoom 19.1 pitch 78 returns near 5.0', () {
      expect(scaleAt(zoom: 19.1, pitch: 78), closeTo(5.0, 0.05));
    });

    test('zoom 19.9 pitch 80 returns near 3.8', () {
      expect(scaleAt(zoom: 19.9, pitch: 80), closeTo(3.8, 0.05));
    });

    test('zoom 21.0 pitch 80 returns near 2.75', () {
      expect(scaleAt(zoom: 21.0, pitch: 80), closeTo(2.75, 0.05));
    });

    test('very low zoom clamps <= 11.5', () {
      expect(
        scaleAt(zoom: 10.0, pitch: 60.0),
        lessThanOrEqualTo(kDriverVehicleModelScaleMax),
      );
    });

    test('very high zoom clamps >= 2.4', () {
      expect(
        scaleAt(zoom: 30.0, pitch: 90.0),
        greaterThanOrEqualTo(kDriverVehicleModelScaleMin),
      );
    });

    test('scale list returns uniform [s,s,s]', () {
      final scale = resolveDriverVehicleModelScale(
        appliedZoom: 18.7,
        appliedPitch: 76.0,
      );
      expect(scale, hasLength(3));
      expect(scale[0], closeTo(scale[1], 0.0001));
      expect(scale[1], closeTo(scale[2], 0.0001));
    });

    test('steep pitch does not reduce scale', () {
      final flat = scaleAt(zoom: 19.1, pitch: 70.0);
      final steep = scaleAt(zoom: 19.1, pitch: 90.0);
      expect(steep, closeTo(flat, 0.0001));
    });

    test('product and debug paths both use registered_id contract', () {
      expect(
        resolveDriverVehicle3dModelSpec(
          DriverVehicle3dPreset.fluxidiTaxi,
        ).assetUri,
        kDriverVehicleModelAssetUri,
      );
      expect(
        resolveDriverVehicle3dModelSpec(
          DriverVehicle3dPreset.classicFlyingTaxi,
        ).assetUri,
        kDriverVehicleClassicFlyingTaxiAssetUri,
      );
      expect(
        resolveDriverVehicleModelLayerModelId(debugPlacementActive: true),
        resolveDriverVehicle3dStyleModelId(DriverVehicle3dPreset.fluxidiTaxi),
      );
      expect(
        resolveDriverVehicleModelLayerModelId(debugPlacementActive: false),
        resolveDriverVehicle3dStyleModelId(DriverVehicle3dPreset.fluxidiTaxi),
      );
      expect(
        resolveDriverVehicleModelIdModeLabel(debugPlacementActive: true),
        kDriverVehicleModelIdModeRegistered,
      );
      expect(
        resolveDriverVehicleModelIdModeLabel(debugPlacementActive: false),
        kDriverVehicleModelIdModeRegistered,
      );
      expect(
        resolveDriverVehicleModelRequiresStyleModelRegistration(
          debugPlacementActive: true,
        ),
        isTrue,
      );
      expect(
        resolveDriverVehicleModelRequiresStyleModelRegistration(
          debugPlacementActive: false,
        ),
        isTrue,
      );
    });

    test('no style gate behavior changes', () {
      expect(
        resolveDriver3dVehicleModelStyleActive(
          activeStyleUri: kDriverMapStyleNavStreetLight,
          visualMode: DriverMapVisualMode.street,
        ),
        isFalse,
      );
      expect(
        resolveDriver3dVehicleModelRuntimeActive(
          presentationActive: true,
          liveRideActive: true,
          followCamera: true,
          styleActive: false,
        ),
        isFalse,
      );
    });
  });

  group('NAV-PRES-3K-J 3D vehicle preset selector', () {
    test('default preset is fluxidiTaxi', () {
      expect(kDriverVehicle3dPresetDefault, DriverVehicle3dPreset.fluxidiTaxi);
    });

    test('fluxidiTaxi resolves direct fluxidi asset URI', () {
      expect(
        resolveDriverVehicle3dModelSpec(
          DriverVehicle3dPreset.fluxidiTaxi,
        ).assetUri,
        'asset://assets/navigation/driver_taxi_3d.glb',
      );
    });

    test('classicFlyingTaxi resolves direct classic asset URI', () {
      expect(
        resolveDriverVehicle3dModelSpec(
          DriverVehicle3dPreset.classicFlyingTaxi,
        ).assetUri,
        'asset://assets/navigation/vehicles/classic_flying_taxi.glb',
      );
    });

    test('each preset has stable label', () {
      expect(
        resolveDriverVehicle3dModelSpec(
          DriverVehicle3dPreset.fluxidiTaxi,
        ).label,
        'Fluxidi taxi',
      );
      expect(
        resolveDriverVehicle3dModelSpec(
          DriverVehicle3dPreset.classicFlyingTaxi,
        ).label,
        'Classic taxi',
      );
    });

    test(
      'selected preset uses registered style model id on ModelLayer',
      () {
        expect(
          resolveDriverVehicleModelLayerModelId(
            debugPlacementActive: false,
            preset: DriverVehicle3dPreset.classicFlyingTaxi,
          ),
          resolveDriverVehicle3dStyleModelId(
            DriverVehicle3dPreset.classicFlyingTaxi,
          ),
        );
        expect(
          resolveDriverVehicleModelLayerModelId(
            debugPlacementActive: false,
            preset: DriverVehicle3dPreset.fluxidiTaxi,
          ),
          resolveDriverVehicle3dStyleModelId(DriverVehicle3dPreset.fluxidiTaxi),
        );
        expect(
          resolveDriverVehicleModelIdModeLabel(debugPlacementActive: false),
          kDriverVehicleModelIdModeRegistered,
        );
        expect(
          resolveDriverVehicleModelRequiresStyleModelRegistration(
            debugPlacementActive: false,
          ),
          isTrue,
        );
      },
    );

    test('product mode debugPlacement=false keeps debug dot hidden', () {
      expect(
        resolveShowDriver3dVehicleDebugStyleDot(
          debugPlacementActive: false,
          runtimeActive: true,
        ),
        isFalse,
      );
    });

    test('preset switch does not change style gate', () {
      expect(
        resolveDriver3dVehicleModelStyleActive(
          activeStyleUri: kDriverMapStyleStandard,
          visualMode: DriverMapVisualMode.street,
        ),
        isTrue,
      );
      expect(
        resolveDriver3dVehicleModelStyleActive(
          activeStyleUri: kDriverMapStyleNavStreetLight,
          visualMode: DriverMapVisualMode.street,
        ),
        isFalse,
      );
    });

    test('preset switch does not enable 3D on navigation-day flat styles', () {
      expect(
        resolveDriver3dVehicleModelRuntimeActive(
          presentationActive: true,
          liveRideActive: true,
          followCamera: true,
          styleActive: resolveDriver3dVehicleModelStyleActive(
            activeStyleUri: kDriverMapStyleNavStreetLight,
            visualMode: DriverMapVisualMode.street,
          ),
        ),
        isFalse,
      );
    });

    test('H4 scale base values remain unchanged', () {
      expect(
        resolveDriverVehicleModelScale(
          appliedZoom: 16.5,
          appliedPitch: 70,
        ).first,
        closeTo(10.8, 0.05),
      );
      expect(
        resolveDriverVehicleModelScale(
          appliedZoom: 21.0,
          appliedPitch: 80,
        ).first,
        closeTo(2.75, 0.05),
      );
    });

    test('scaleMultiplier is applied to returned modelScale', () {
      // NAV-3D-INSTANT-SWITCH-SCALE-AND-HEADING-POLISH-1: preset scale is
      // owned by the centralized footprint resolver (spec multiplier applied).
      final footprint = resolveDriverVehicle3dFootprintScale(
        appliedZoom: 18.7,
        preset: DriverVehicle3dPreset.fluxidiTaxi,
      ).resolvedScale;
      final withPreset = resolveDriverVehicleModelScaleForPreset(
        appliedZoom: 18.7,
        appliedPitch: 76,
        preset: DriverVehicle3dPreset.fluxidiTaxi,
      ).first;
      expect(withPreset, closeTo(footprint, 0.0001));
    });

    test('invalid registration failure falls back safely to fluxidiTaxi', () {
      expect(
        resolveDriverVehicle3dPresetAfterRegistrationFailure(
          requestedPreset: DriverVehicle3dPreset.classicFlyingTaxi,
          registerSucceeded: false,
        ),
        DriverVehicle3dPreset.fluxidiTaxi,
      );
      expect(
        resolveDriverVehicle3dPresetAfterRegistrationFailure(
          requestedPreset: DriverVehicle3dPreset.fluxidiTaxi,
          registerSucceeded: false,
        ),
        DriverVehicle3dPreset.fluxidiTaxi,
      );
    });

    test(
      'selector gate requires dedicated 3D presentation and live follow',
      () {
        expect(
          resolveShowDriverVehicle3dPresetSelector(
            vehicleModelFlagEnabled: true,
            cockpitSceneEnabled: true,
            useDriverCockpitCamera: true,
            useDriver3dVehicleModel: true,
            liveNavigationActive: true,
            followCamera: true,
            activeStyleUri: kDriverMapStyleStandard,
            visualMode: DriverMapVisualMode.street,
            cockpitSceneActive: true,
            cockpitVisualStyle: DriverCockpitMapVisualStyle.standard3d,
            sessionFallback2d: false,
            styleLoaded: true,
            styleSwapInProgress: false,
          ),
          isTrue,
        );
        expect(
          resolveShowDriverVehicle3dPresetSelector(
            vehicleModelFlagEnabled: false,
            cockpitSceneEnabled: true,
            useDriverCockpitCamera: true,
            useDriver3dVehicleModel: true,
            liveNavigationActive: true,
            followCamera: true,
            activeStyleUri: kDriverMapStyleStandard,
            visualMode: DriverMapVisualMode.street,
            cockpitSceneActive: true,
            cockpitVisualStyle: DriverCockpitMapVisualStyle.standard3d,
            sessionFallback2d: false,
            styleLoaded: true,
            styleSwapInProgress: false,
          ),
          isFalse,
        );
        expect(
          resolveShowDriverVehicle3dPresetSelector(
            vehicleModelFlagEnabled: true,
            cockpitSceneEnabled: false,
            useDriverCockpitCamera: true,
            useDriver3dVehicleModel: true,
            liveNavigationActive: true,
            followCamera: true,
            activeStyleUri: kDriverMapStyleStandard,
            visualMode: DriverMapVisualMode.street,
            cockpitSceneActive: true,
            cockpitVisualStyle: DriverCockpitMapVisualStyle.standard3d,
            sessionFallback2d: false,
            styleLoaded: true,
            styleSwapInProgress: false,
          ),
          isFalse,
        );
      },
    );

    test(
      'phone selector capability stays visible for every vehicle lifecycle state',
      () {
        bool visible({String? style = kDriverMapStyleStandard}) {
          return resolveShowDriverVehicle3dPhoneSelector(
            vehicleModelFlagEnabled: true,
            cockpitSceneEnabled: true,
            useDriverCockpitCamera: true,
            useDriver3dVehicleModel: true,
            liveNavigationActive: true,
            presentationMode: NavigationPresentationMode.driver,
            followCamera: true,
            activeStyleUri: style,
            cockpitSceneActive: true,
            cockpitVisualStyle: DriverCockpitMapVisualStyle.standard3d,
          );
        }

        // Choice / owner / model-ready / temporary-fallback state are not
        // inputs to this capability decision, so 2D, Fluxidi, Classic and a
        // recovery fallback all keep the same compact phone control visible.
        expect(visible(), isTrue, reason: 'selected 2D');
        expect(visible(), isTrue, reason: 'Fluxidi model active');
        expect(visible(), isTrue, reason: 'Classic model active');
        expect(visible(), isTrue, reason: 'temporary 2D fallback');
        expect(
          visible(style: kDriverMapStyleNavStreetLight),
          isFalse,
          reason: 'leaving the dedicated 3D style follows the normal rule',
        );
      },
    );
  });

  group('NAV-PRES-3K-I product render decoupled from debug placement', () {
    test(
      'debugPlacement false resolves registered_id product render path',
      () {
        expect(
          resolveDriverVehicle3dModelSpec(
            DriverVehicle3dPreset.fluxidiTaxi,
          ).assetUri,
          kDriverVehicleModelAssetUri,
        );
        expect(
          resolveDriverVehicleModelLayerModelId(debugPlacementActive: false),
          resolveDriverVehicle3dStyleModelId(DriverVehicle3dPreset.fluxidiTaxi),
        );
        expect(
          resolveDriverVehicleModelIdModeLabel(debugPlacementActive: false),
          kDriverVehicleModelIdModeRegistered,
        );
        expect(
          resolveDriverVehicleModelRequiresStyleModelRegistration(
            debugPlacementActive: false,
          ),
          isTrue,
        );
      },
    );

    test('debugPlacement false does not register or show debug dot', () {
      expect(
        resolveShowDriver3dVehicleDebugStyleDot(
          debugPlacementActive: false,
          runtimeActive: true,
        ),
        isFalse,
      );
      expect(
        resolveShowDriver3dVehicleDebugDot(
          debugPlacementActive: false,
          runtimeActive: true,
        ),
        isFalse,
      );
    });

    test('debugPlacement true still shows debug dot when runtime active', () {
      expect(
        resolveShowDriver3dVehicleDebugStyleDot(
          debugPlacementActive: true,
          runtimeActive: true,
        ),
        isTrue,
      );
    });

    test('debugPlacement true may use camera-center placement', () {
      final placement = resolveDriverVehicleModelDebugPlacementCoordinate(
        debugPlacementActive: true,
        visualLon: 24.94,
        visualLat: 60.17,
        visualSource: 'nav_visual',
        cameraCenterLon: 24.95,
        cameraCenterLat: 60.18,
        visualOnScreen: true,
      );
      expect(placement.placementSource, 'camera_center');
      expect(
        resolveDriverVehicleModelPlacementMode(
          debugPlacementActive: true,
          placementSource: placement.placementSource,
        ),
        'camera_center',
      );
    });

    test('debugPlacement false uses snapped vehicle coordinate placement', () {
      final placement = resolveDriverVehicleModelDebugPlacementCoordinate(
        debugPlacementActive: false,
        visualLon: 24.94,
        visualLat: 60.17,
        visualSource: 'nav_visual',
        cameraCenterLon: 24.95,
        cameraCenterLat: 60.18,
        visualOnScreen: true,
      );
      expect(placement.lon, 24.94);
      expect(placement.lat, 60.17);
      expect(placement.placementSource, 'nav_visual');
      expect(
        resolveDriverVehicleModelPlacementMode(
          debugPlacementActive: false,
          placementSource: placement.placementSource,
        ),
        'snapped_vehicle',
      );
    });

    test('product mode still uses H4 adaptive scale', () {
      expect(
        resolveDriverVehicleModelScale(
          appliedZoom: 19.1,
          appliedPitch: 78,
        ).first,
        closeTo(5.0, 0.05),
      );
    });

    test('style gate remains unchanged', () {
      expect(
        resolveDriver3dVehicleModelStyleActive(
          activeStyleUri: kDriverMapStyleNavStreetLight,
          visualMode: DriverMapVisualMode.street,
        ),
        isFalse,
      );
      expect(
        resolveDriver3dVehicleModelStyleActive(
          activeStyleUri: kDriverMapStyleStandard,
          visualMode: DriverMapVisualMode.street,
        ),
        isTrue,
      );
    });
  });

  group('NAV-PRES-3K-E 3D vehicle render proof and placement', () {
    test('debug placement active only with 3D + debug + cockpit + driver', () {
      expect(
        resolveDriver3dVehicleDebugPlacementActive(
          modelFlagEnabled: true,
          debugPlacementFlagEnabled: true,
          useDriverCockpitCamera: true,
          isDriverMode: true,
        ),
        isTrue,
      );
      expect(
        resolveDriver3dVehicleDebugPlacementActive(
          modelFlagEnabled: false,
          debugPlacementFlagEnabled: true,
          useDriverCockpitCamera: true,
          isDriverMode: true,
        ),
        isFalse,
      );
      expect(
        resolveDriver3dVehicleDebugPlacementActive(
          modelFlagEnabled: true,
          debugPlacementFlagEnabled: false,
          useDriverCockpitCamera: true,
          isDriverMode: true,
        ),
        isFalse,
      );
    });

    test('debug style dot only when debug placement and runtime active', () {
      expect(
        resolveShowDriver3dVehicleDebugStyleDot(
          debugPlacementActive: true,
          runtimeActive: true,
        ),
        isTrue,
      );
      expect(
        resolveShowDriver3dVehicleDebugStyleDot(
          debugPlacementActive: false,
          runtimeActive: true,
        ),
        isFalse,
      );
      expect(
        resolveShowDriver3dVehicleDebugStyleDot(
          debugPlacementActive: true,
          runtimeActive: false,
        ),
        isFalse,
      );
    });

    test('debug dot only when debug placement and runtime active', () {
      expect(
        resolveShowDriver3dVehicleDebugDot(
          debugPlacementActive: true,
          runtimeActive: true,
        ),
        isTrue,
      );
      expect(
        resolveShowDriver3dVehicleDebugDot(
          debugPlacementActive: false,
          runtimeActive: true,
        ),
        isFalse,
      );
      expect(
        resolveShowDriver3dVehicleDebugDot(
          debugPlacementActive: true,
          runtimeActive: false,
        ),
        isFalse,
      );
    });

    test('debug placement prefers camera center when debug active', () {
      final placement = resolveDriverVehicleModelDebugPlacementCoordinate(
        debugPlacementActive: true,
        visualLon: 24.94,
        visualLat: 60.17,
        visualSource: 'route_snap',
        cameraCenterLon: 24.95,
        cameraCenterLat: 60.18,
        visualOnScreen: false,
      );
      expect(placement.placementSource, 'camera_center');
      expect(placement.lon, 24.95);
      expect(placement.lat, 60.18);
    });

    test('debug placement off keeps visual coordinate unchanged', () {
      final placement = resolveDriverVehicleModelDebugPlacementCoordinate(
        debugPlacementActive: false,
        visualLon: 24.94,
        visualLat: 60.17,
        visualSource: 'route_snap',
        cameraCenterLon: 24.95,
        cameraCenterLat: 60.18,
        visualOnScreen: false,
      );
      expect(placement.placementSource, 'route_snap');
      expect(placement.lon, 24.94);
      expect(placement.lat, 60.17);
    });

    test('viewport helper detects on-screen pixels without PII', () {
      expect(
        resolveDriverVehicleScreenOnViewport(
          screenX: 100,
          screenY: 200,
          viewportWidth: 400,
          viewportHeight: 800,
        ),
        isTrue,
      );
      expect(
        resolveDriverVehicleScreenOnViewport(
          screenX: -1,
          screenY: 200,
          viewportWidth: 400,
          viewportHeight: 800,
        ),
        isFalse,
      );
      expect(
        formatDriverVehicleViewportForLog(width: 390, height: 844),
        '390x844',
      );
    });

    test('register guard blocks in-flight and cooldown retries', () {
      final now = DateTime(2026, 7, 10, 12);
      expect(
        resolveDriverVehicleModelCanAttemptRegister(
          registered: false,
          registerInFlight: true,
          lastFailureAt: null,
          now: now,
        ),
        isFalse,
      );
      expect(
        resolveDriverVehicleModelCanAttemptRegister(
          registered: false,
          registerInFlight: false,
          lastFailureAt: now.subtract(const Duration(milliseconds: 500)),
          now: now,
        ),
        isFalse,
      );
      expect(
        resolveDriverVehicleModelCanAttemptRegister(
          registered: false,
          registerInFlight: false,
          lastFailureAt: now.subtract(const Duration(seconds: 3)),
          now: now,
        ),
        isTrue,
      );
      expect(
        resolveDriverVehicleModelCanAttemptRegister(
          registered: true,
          registerInFlight: false,
          lastFailureAt: null,
          now: now,
        ),
        isFalse,
      );
    });

    test('HUD isolation unchanged when debug placement flag false', () {
      expect(
        resolveHideDriverHudVehicleFor3dVisualIsolation(
          driver3dVehicleModelEnabled: true,
          driver3dVehicleHideHudEnabled: true,
          useDriverCockpitCamera: true,
          isDriverMode: true,
        ),
        isTrue,
      );
      expect(kNavigation3dVehicleDebugPlacementEnabled, isFalse);
    });
  });

  group('NAV-PRES-3K-G style capability gate and 2D fallback', () {
    test('navigation-day/night styles are not 3D active', () {
      expect(
        resolveDriver3dVehicleModelStyleActive(
          activeStyleUri: kDriverMapStyleNavStreetLight,
          visualMode: DriverMapVisualMode.street,
        ),
        isFalse,
      );
      expect(
        resolveDriver3dVehicleModelStyleActive(
          activeStyleUri: kDriverMapStyleNavStreetDark,
          visualMode: DriverMapVisualMode.street,
        ),
        isFalse,
      );
    });

    test('standard style is dedicated 3D active; satellite is not', () {
      expect(
        resolveDriver3dVehicleModelStyleActive(
          activeStyleUri: kDriverMapStyleStandard,
          visualMode: DriverMapVisualMode.street,
        ),
        isTrue,
      );
      expect(
        resolveDriver3dVehicleModelStyleActive(
          activeStyleUri: kDriverMapStyleStandardSatellite,
          visualMode: DriverMapVisualMode.satellite,
        ),
        isFalse,
      );
    });

    test(
      'flat style blocks runtime even when 3D intent and follow are true',
      () {
        expect(
          resolveDriver3dVehicleModelRuntimeActive(
            presentationActive: true,
            liveRideActive: true,
            followCamera: true,
            styleActive: false,
          ),
          isFalse,
        );
      },
    );

    test(
      'flat style restores 2D taxi fallback and does not hide HUD from 3D intent',
      () {
        expect(
          resolveHideMapboxTaxiMarkerFor3dVehicleRuntime(
            hideForHudOverlay: false,
            driver3dVehicleModelActuallyActive: false,
          ),
          isFalse,
        );
        expect(
          resolveHideDriverHudVehicleFor3dVisualIsolationRuntime(
            driver3dVehicleModelActuallyActive: false,
            driver3dVehicleHideHudEnabled: true,
            useDriverCockpitCamera: true,
            isDriverMode: true,
          ),
          isFalse,
        );
      },
    );

    test(
      'true 3D handoff suppresses 2D taxi and can hide HUD with isolation flag',
      () {
        final handoff = confirmed3dHandoffEligibility();
        expect(
          resolveHideMapboxTaxiMarkerFromEligibility(
            hideForHudOverlay: false,
            eligibility: handoff,
          ),
          isTrue,
        );
        expect(
          resolveHideDriverHudVehicleFromEligibility(eligibility: handoff),
          isTrue,
        );
      },
    );

    test(
      'debug dot requires runtime active so flat style avoids no-vehicle state',
      () {
        expect(
          resolveShowDriver3dVehicleDebugStyleDot(
            debugPlacementActive: true,
            runtimeActive: false,
          ),
          isFalse,
        );
        expect(
          resolveShowDriver3dVehicleDebugStyleDot(
            debugPlacementActive: true,
            runtimeActive: resolveDriver3dVehicleModelRuntimeActive(
              presentationActive: true,
              liveRideActive: true,
              followCamera: true,
              styleActive: true,
            ),
          ),
          isTrue,
        );
      },
    );

    test('empty style uri is not 3D active', () {
      expect(
        resolveDriver3dVehicleModelStyleActive(
          activeStyleUri: '',
          visualMode: DriverMapVisualMode.street,
        ),
        isFalse,
      );
      expect(
        resolveDriver3dVehicleModelStyleActive(
          activeStyleUri: null,
          visualMode: DriverMapVisualMode.street,
        ),
        isFalse,
      );
    });
  });

  group('NAV-PRES-3K-F official render path proof', () {
    test('debug style dot config is large red with white stroke', () {
      final config = resolveDriverVehicleDebugStyleDotLayerConfig();
      expect(config.radius, greaterThanOrEqualTo(28));
      expect(config.color, kDriverVehicleDebugStyleDotColor);
      expect(config.strokeColor, kDriverVehicleDebugStyleDotStrokeColor);
      expect(config.strokeWidth, greaterThanOrEqualTo(5));
      expect(config.pitchAlignment, mb.CirclePitchAlignment.VIEWPORT);
      expect(config.pitchScale, mb.CirclePitchScale.VIEWPORT);
    });

    test('product and debug model layers use registered style model ids', () {
      expect(
        resolveDriverVehicleModelLayerModelId(debugPlacementActive: true),
        resolveDriverVehicle3dStyleModelId(DriverVehicle3dPreset.fluxidiTaxi),
      );
      expect(
        resolveDriverVehicleModelLayerModelId(debugPlacementActive: false),
        resolveDriverVehicle3dStyleModelId(DriverVehicle3dPreset.fluxidiTaxi),
      );
      expect(
        resolveDriverVehicleModelLayerModelId(
          debugPlacementActive: false,
          preset: DriverVehicle3dPreset.classicFlyingTaxi,
        ),
        resolveDriverVehicle3dStyleModelId(
          DriverVehicle3dPreset.classicFlyingTaxi,
        ),
      );
      expect(
        resolveDriverVehicleModelIdModeLabel(debugPlacementActive: true),
        kDriverVehicleModelIdModeRegistered,
      );
      expect(
        resolveDriverVehicleModelIdModeLabel(debugPlacementActive: false),
        kDriverVehicleModelIdModeRegistered,
      );
      expect(
        resolveDriverVehicleModelRequiresStyleModelRegistration(
          debugPlacementActive: true,
        ),
        isTrue,
      );
      expect(
        resolveDriverVehicleModelRequiresStyleModelRegistration(
          debugPlacementActive: false,
        ),
        isTrue,
      );
    });

    test('style-not-loaded gate uses bounded cooldown', () {
      final now = DateTime(2026, 7, 10, 12);
      expect(
        resolveDriverVehicleModelShouldSkipForStyleNotLoaded(
          styleLoaded: false,
          lastStyleNotLoadedSkipAt: null,
          now: now,
        ),
        isTrue,
      );
      expect(
        resolveDriverVehicleModelShouldSkipForStyleNotLoaded(
          styleLoaded: false,
          lastStyleNotLoadedSkipAt: now.subtract(
            const Duration(milliseconds: 100),
          ),
          now: now,
        ),
        isTrue,
      );
      expect(
        resolveDriverVehicleModelShouldSkipForStyleNotLoaded(
          styleLoaded: false,
          lastStyleNotLoadedSkipAt: now.subtract(const Duration(seconds: 1)),
          now: now,
        ),
        isFalse,
      );
      expect(
        resolveDriverVehicleModelShouldSkipForStyleNotLoaded(
          styleLoaded: true,
          lastStyleNotLoadedSkipAt: now,
          now: now,
        ),
        isFalse,
      );
    });

    test('register failure clears registered state', () {
      expect(
        resolveDriverVehicleModelRegisteredAfterFailure(
          registerSucceeded: false,
        ),
        isFalse,
      );
      expect(
        resolveDriverVehicleModelRegisteredAfterFailure(
          registerSucceeded: true,
        ),
        isTrue,
      );
    });

    test('platform exception formatter includes code message details', () {
      final formatted = formatNavPres3dVehicleError(
        PlatformException(
          code: 'register_failed',
          message: 'layer exists',
          details: 'fluxidi-driver-vehicle-model',
        ),
      );
      expect(formatted, contains('PlatformException'));
      expect(formatted, contains('code=register_failed'));
      expect(formatted, contains('message=layer exists'));
      expect(formatted, contains('details=fluxidi-driver-vehicle-model'));
    });

    test('flag-off behavior unchanged for debug dot visibility', () {
      expect(kNavigation3dVehicleDebugPlacementEnabled, isFalse);
      expect(
        resolveDriverVehicleModelLayerModelId(
          debugPlacementActive: kNavigation3dVehicleDebugPlacementEnabled,
        ),
        resolveDriverVehicle3dStyleModelId(DriverVehicle3dPreset.fluxidiTaxi),
      );
      expect(
        resolveShowDriver3dVehicleDebugStyleDot(
          debugPlacementActive: kNavigation3dVehicleDebugPlacementEnabled,
          runtimeActive: true,
        ),
        isFalse,
      );
    });
  });

  group('NAV-ASSET-3D-SWAP-1 vehicle swap lifecycle', () {
    test('each preset resolves a unique stable style model id', () {
      expect(
        resolveDriverVehicle3dStyleModelId(DriverVehicle3dPreset.fluxidiTaxi),
        kDriverVehicleFluxidiTaxiStyleModelId,
      );
      expect(
        resolveDriverVehicle3dStyleModelId(
          DriverVehicle3dPreset.classicFlyingTaxi,
        ),
        kDriverVehicleClassicFlyingTaxiStyleModelId,
      );
      expect(
        resolveDriverVehicle3dStyleModelId(DriverVehicle3dPreset.fluxidiTaxi),
        isNot(
          resolveDriverVehicle3dStyleModelId(
            DriverVehicle3dPreset.classicFlyingTaxi,
          ),
        ),
      );
      expect(allDriverVehicle3dStyleModelIds(), hasLength(2));
    });

    test('layer binds registered style model id per preset', () {
      final classicSpec = resolveDriverVehicle3dModelSpec(
        DriverVehicle3dPreset.classicFlyingTaxi,
      );
      expect(classicSpec.assetUri, kDriverVehicleClassicFlyingTaxiAssetUri);
      expect(
        resolveDriverVehicleModelLayerModelId(
          debugPlacementActive: false,
          preset: DriverVehicle3dPreset.classicFlyingTaxi,
        ),
        resolveDriverVehicle3dStyleModelId(
          DriverVehicle3dPreset.classicFlyingTaxi,
        ),
      );
    });

    test('latest generation wins during overlapping async swaps', () {
      expect(
        shouldIgnoreStaleDriverVehicle3dSwap(
          requestGeneration: 2,
          currentGeneration: 3,
        ),
        isTrue,
      );
      expect(
        shouldIgnoreStaleDriverVehicle3dSwap(
          requestGeneration: 3,
          currentGeneration: 3,
        ),
        isFalse,
      );
    });

    test('repeated A -> B -> A keeps latest preset selection', () {
      var generation = 0;

      final firstSwapGeneration = ++generation;
      expect(firstSwapGeneration, 1);

      final secondSwapGeneration = ++generation;
      expect(secondSwapGeneration, 2);

      expect(
        shouldIgnoreStaleDriverVehicle3dSwap(
          requestGeneration: firstSwapGeneration,
          currentGeneration: generation,
        ),
        isTrue,
      );
      expect(
        shouldIgnoreStaleDriverVehicle3dSwap(
          requestGeneration: secondSwapGeneration,
          currentGeneration: generation,
        ),
        isFalse,
      );

      const selected = DriverVehicle3dPreset.fluxidiTaxi;
      expect(
        resolveDriverVehicle3dPresetForOverlappingSwaps(
          firstRequested: DriverVehicle3dPreset.classicFlyingTaxi,
          secondRequested: DriverVehicle3dPreset.fluxidiTaxi,
        ),
        selected,
      );
      expect(
        resolveDriverVehicleModelLayerModelId(
          debugPlacementActive: false,
          preset: selected,
        ),
        resolveDriverVehicle3dStyleModelId(selected),
      );
    });

    test(
      'style restore path uses currently selected preset not cached preset',
      () {
        const current = DriverVehicle3dPreset.classicFlyingTaxi;
        expect(
          resolveDriverVehicleModelLayerModelId(
            debugPlacementActive: false,
            preset: current,
          ),
          resolveDriverVehicle3dStyleModelId(current),
        );
        expect(
          resolveDriverVehicleModelRequiresStyleModelRegistration(
            debugPlacementActive: false,
          ),
          isTrue,
        );
      },
    );

    test('classic vehicle swap applies its calibrated visual footprint', () {
      const zoom = 18.7;
      const pitch = 76.0;
      final scaleBefore = resolveDriverVehicleModelScaleForPreset(
        appliedZoom: zoom,
        appliedPitch: pitch,
        preset: DriverVehicle3dPreset.fluxidiTaxi,
      );
      final scaleAfter = resolveDriverVehicleModelScaleForPreset(
        appliedZoom: zoom,
        appliedPitch: pitch,
        preset: DriverVehicle3dPreset.classicFlyingTaxi,
      );
      // NAV-MOBILE-3D-SELECTOR-SCALE-AND-BOTTOM-PRIORITY-1: the authored
      // Classic GLB bounds are smaller, so its physical scale compensates by
      // the preset calibration while keeping the same zoom curve.
      expect(
        scaleAfter.first / scaleBefore.first,
        closeTo(kNav3dClassicFootprintMultiplier, 0.0001),
      );
      expect(scaleBefore.first, closeTo(6.0, 0.1));
    });
  });

  group('NAV-ASSET-3D-SYNC-1 movement sync lifecycle', () {
    DriverVehicle3dMovementPose pose({
      double lon = 4.9,
      double lat = 52.3,
      double bearing = 90,
      String source = 'route_snap',
      int generation = 1,
    }) {
      return DriverVehicle3dMovementPose(
        lon: lon,
        lat: lat,
        bearingDeg: bearing,
        source: source,
        appliedZoom: 18.7,
        appliedPitch: 76.0,
        preset: DriverVehicle3dPreset.fluxidiTaxi,
        movementGeneration: generation,
      );
    }

    test('allows at most one movement update in flight', () {
      final lifecycle = NavVehicleModelSyncLifecycle();
      final now = DateTime(2026, 7, 11, 12);

      expect(lifecycle.queueMovement(pose()), 'queued');
      expect(lifecycle.beginMovementUpdate(now), isTrue);
      expect(lifecycle.beginMovementUpdate(now), isFalse);
      expect(lifecycle.updateInFlight, isTrue);
    });

    test('latest request wins while update is active', () {
      final lifecycle = NavVehicleModelSyncLifecycle();
      final now = DateTime(2026, 7, 11, 12);

      lifecycle.queueMovement(pose(lon: 1, lat: 1));
      expect(lifecycle.beginMovementUpdate(now), isTrue);
      expect(lifecycle.queueMovement(pose(lon: 2, lat: 2)), 'coalesced');
      expect(lifecycle.pendingUpdate, isTrue);

      lifecycle.consumeLatestRequest();
      expect(lifecycle.finishMovementUpdate(applied: true, now: now), isTrue);
      expect(lifecycle.latestRequest?.lon, 2);
      expect(lifecycle.latestRequest?.lat, 2);
    });

    test(
      'repeated 30 Hz requests collapse to latest pose without parallel sync',
      () {
        final lifecycle = NavVehicleModelSyncLifecycle();
        final now = DateTime(2026, 7, 11, 12);

        for (var i = 0; i < 30; i++) {
          lifecycle.queueMovement(
            pose(lon: i.toDouble(), bearing: i.toDouble()),
          );
        }

        expect(lifecycle.latestRequest?.lon, 29);
        expect(lifecycle.beginMovementUpdate(now), isTrue);
        expect(lifecycle.beginMovementUpdate(now), isFalse);

        final consumed = lifecycle.consumeLatestRequest();
        expect(consumed?.lon, 29);
        expect(
          lifecycle.finishMovementUpdate(applied: true, now: now),
          isFalse,
        );
        expect(lifecycle.updateInFlight, isFalse);
      },
    );

    test('unchanged pose is skipped by write plan', () {
      final scale = resolveDriverVehicleModelScaleForPreset(
        appliedZoom: 18.7,
        appliedPitch: 76.0,
        preset: DriverVehicle3dPreset.fluxidiTaxi,
      );
      final translation = driverVehicleModelTranslationForPreset(
        debugPlacementActive: false,
        preset: DriverVehicle3dPreset.fluxidiTaxi,
      );
      final rotation = resolveDriverVehicleModelFinalRotationForPreset(
        90,
        preset: DriverVehicle3dPreset.fluxidiTaxi,
      );
      final applied = DriverVehicleModelAppliedMovementState(
        lon: 4.9,
        lat: 52.3,
        bearingDeg: 90,
        preset: DriverVehicle3dPreset.fluxidiTaxi,
        scale: scale,
        translation: translation,
        rotation: rotation,
      );

      expect(
        driverVehicleModelMovementRequiresNativeUpdate(
          applied: applied,
          lon: 4.9,
          lat: 52.3,
          bearingDeg: 90,
          preset: DriverVehicle3dPreset.fluxidiTaxi,
          scale: scale,
          translation: translation,
          rotation: rotation,
        ),
        isFalse,
      );
    });

    test('preset swap with unchanged bearing still requires rotation write', () {
      const bearing = 90.0;
      final fluxidiRotation = resolveDriverVehicleModelFinalRotationForPreset(
        bearing,
        preset: DriverVehicle3dPreset.fluxidiTaxi,
      );
      final classicRotation = resolveDriverVehicleModelFinalRotationForPreset(
        bearing,
        preset: DriverVehicle3dPreset.classicFlyingTaxi,
      );
      final scale = resolveDriverVehicleModelScaleForPreset(
        appliedZoom: 18.7,
        appliedPitch: 76.0,
        preset: DriverVehicle3dPreset.fluxidiTaxi,
      );
      final translation = driverVehicleModelTranslationForPreset(
        debugPlacementActive: false,
        preset: DriverVehicle3dPreset.fluxidiTaxi,
      );
      final applied = DriverVehicleModelAppliedMovementState(
        lon: 4.9,
        lat: 52.3,
        bearingDeg: bearing,
        preset: DriverVehicle3dPreset.fluxidiTaxi,
        scale: scale,
        translation: translation,
        rotation: fluxidiRotation,
      );
      final plan = resolveDriverVehicleModelMovementWritePlan(
        applied: applied,
        lon: 4.9,
        lat: 52.3,
        bearingDeg: bearing,
        preset: DriverVehicle3dPreset.classicFlyingTaxi,
        scale: scale,
        translation: translation,
        rotation: classicRotation,
      );
      expect(plan.rotationChanged, isTrue);
      expect(
        driverVehicleModelMovementRequiresNativeUpdate(
          applied: applied,
          lon: 4.9,
          lat: 52.3,
          bearingDeg: bearing,
          preset: DriverVehicle3dPreset.classicFlyingTaxi,
          scale: scale,
          translation: translation,
          rotation: classicRotation,
        ),
        isTrue,
      );
    });

    test('preset swap clears pending movement requests', () {
      final lifecycle = NavVehicleModelSyncLifecycle();
      final now = DateTime(2026, 7, 11, 12);

      lifecycle.queueMovement(pose());
      expect(lifecycle.beginMovementUpdate(now), isTrue);
      lifecycle.queueMovement(pose(lon: 9));

      lifecycle.pauseForSwap();
      expect(lifecycle.pendingUpdate, isFalse);
      expect(lifecycle.latestRequest, isNull);
      expect(lifecycle.queueMovement(pose()), 'ignored');

      lifecycle.resumeAfterSwap(movementGeneration: 2);
      expect(lifecycle.queueMovement(pose(generation: 2)), 'queued');
      expect(lifecycle.shouldIgnoreStaleMovement(1), isTrue);
    });

    test('timeout triggers session fallback threshold', () {
      final lifecycle = NavVehicleModelSyncLifecycle();
      final started = DateTime(2026, 7, 11, 12);

      expect(lifecycle.beginMovementUpdate(started), isTrue);
      final later = started.add(
        Duration(milliseconds: kDriverVehicleModelMovementTimeoutMs + 1),
      );
      expect(lifecycle.shouldTriggerFallback(now: later), isTrue);
    });

    test('repeated failures trigger session fallback', () {
      final lifecycle = NavVehicleModelSyncLifecycle();
      final now = DateTime(2026, 7, 11, 12);

      for (
        var i = 0;
        i < kDriverVehicleModelMovementMaxConsecutiveFailures;
        i++
      ) {
        expect(lifecycle.beginMovementUpdate(now), isTrue);
        lifecycle.finishMovementUpdate(
          applied: false,
          now: now,
          countFailure: true,
        );
      }

      expect(lifecycle.shouldTriggerFallback(now: now), isTrue);
      lifecycle.enableSessionFallback2d();
      expect(lifecycle.sessionFallback2d, isTrue);
      expect(lifecycle.queueMovement(pose()), 'ignored');
    });

    test('movement write plan never implies registration recreation', () {
      final layer = DriverVehicleModelLayer();
      expect(layer.isRegistered, isFalse);
      expect(layer.registerInFlight, isFalse);

      final plan = resolveDriverVehicleModelMovementWritePlan(
        applied: null,
        lon: 4.9,
        lat: 52.3,
        bearingDeg: 90,
        preset: DriverVehicle3dPreset.fluxidiTaxi,
        scale: const [5.8, 5.8, 5.8],
        translation: const [0, 0, 0.2],
        rotation: const [0, 0, 90],
      );

      expect(plan.positionChanged, isTrue);
      expect(layer.isRegistered, isFalse);
    });

    test('style restore clears movement state but keeps session fallback', () {
      final lifecycle = NavVehicleModelSyncLifecycle();
      lifecycle.enableSessionFallback2d();
      expect(lifecycle.sessionFallback2d, isTrue);

      lifecycle.resetForStyleRestore();
      expect(lifecycle.sessionFallback2d, isTrue);
      expect(lifecycle.queueMovement(pose()), 'ignored');
    });

    test('new navigation session reset clears session fallback', () {
      final lifecycle = NavVehicleModelSyncLifecycle();
      lifecycle.enableSessionFallback2d();
      lifecycle.resetForNewNavigationSession();
      expect(lifecycle.sessionFallback2d, isFalse);
      expect(lifecycle.queueMovement(pose()), 'queued');
    });

    test('throttle prefers 10 Hz and caps backlog drain at 15 Hz', () {
      final lifecycle = NavVehicleModelSyncLifecycle();
      final now = DateTime(2026, 7, 11, 12);

      expect(lifecycle.movementThrottleDelayMs(now, drainPending: false), 0);

      lifecycle.finishMovementUpdate(applied: true, now: now);
      expect(lifecycle.beginMovementUpdate(now), isTrue);
      lifecycle.finishMovementUpdate(applied: true, now: now);

      expect(
        lifecycle.movementThrottleDelayMs(now, drainPending: false),
        kDriverVehicleModelMovementPreferredIntervalMs,
      );
      expect(
        lifecycle.movementThrottleDelayMs(now, drainPending: true),
        kDriverVehicleModelMovementMinimumIntervalMs,
      );
    });
  });

  group('NAV-ASSET-3D-MODE-GATE-1 dedicated 3D vehicle eligibility', () {
    test('selector hidden in Light navigation style', () {
      final eligibility = resolveDriver3dVehicleEligibility(
        vehicleModelFlagEnabled: true,
        cockpitSceneEnabled: true,
        useDriverCockpitCamera: true,
        presentationMode: NavigationPresentationMode.driver,
        liveNavigationActive: true,
        followCamera: true,
        activeStyleUri: kDriverMapStyleNavStreetLight,
        visualMode: DriverMapVisualMode.street,
        cockpitSceneActive: true,
        cockpitVisualStyle: DriverCockpitMapVisualStyle.light,
        sessionFallback2d: false,
        styleLoaded: true,
        styleSwapInProgress: false,
        modelRegistered: false,
        modelPoseApplied: false,
        hideHudIsolationFlagEnabled: true,
      );
      expect(eligibility.selectorVisible, isFalse);
      expect(eligibility.reason, 'not_dedicated_3d_choice');
    });

    test('selector hidden in Dark navigation style', () {
      final eligibility = resolveDriver3dVehicleEligibility(
        vehicleModelFlagEnabled: true,
        cockpitSceneEnabled: true,
        useDriverCockpitCamera: true,
        presentationMode: NavigationPresentationMode.driver,
        liveNavigationActive: true,
        followCamera: true,
        activeStyleUri: kDriverMapStyleNavStreetDark,
        visualMode: DriverMapVisualMode.street,
        cockpitSceneActive: true,
        cockpitVisualStyle: DriverCockpitMapVisualStyle.dark,
        sessionFallback2d: false,
        styleLoaded: true,
        styleSwapInProgress: false,
        modelRegistered: false,
        modelPoseApplied: false,
        hideHudIsolationFlagEnabled: true,
      );
      expect(eligibility.selectorVisible, isFalse);
      expect(eligibility.reason, 'not_dedicated_3d_choice');
    });

    test('selector hidden in Satellite presentation', () {
      final eligibility = resolveDriver3dVehicleEligibility(
        vehicleModelFlagEnabled: true,
        cockpitSceneEnabled: true,
        useDriverCockpitCamera: true,
        presentationMode: NavigationPresentationMode.driver,
        liveNavigationActive: true,
        followCamera: true,
        activeStyleUri: kDriverMapStyleStandardSatellite,
        visualMode: DriverMapVisualMode.satellite,
        cockpitSceneActive: true,
        cockpitVisualStyle: DriverCockpitMapVisualStyle.satellite,
        sessionFallback2d: false,
        styleLoaded: true,
        styleSwapInProgress: false,
        modelRegistered: false,
        modelPoseApplied: false,
        hideHudIsolationFlagEnabled: true,
      );
      expect(eligibility.selectorVisible, isFalse);
      expect(eligibility.reason, 'not_dedicated_3d_choice');
    });

    test('selector visible only in dedicated 3D presentation', () {
      expect(dedicated3dEligibility().selectorVisible, isTrue);
      expect(
        dedicated3dEligibility(
          presentationMode: NavigationPresentationMode.overview,
        ).selectorVisible,
        isFalse,
      );
      expect(
        dedicated3dEligibility(
          presentationMode: NavigationPresentationMode.northUp,
        ).selectorVisible,
        isFalse,
      );
    });

    test('movement sync blocked outside dedicated 3D', () {
      expect(dedicated3dEligibility().allowMovementSync, isTrue);
      expect(
        dedicated3dEligibility(
          activeStyleUri: kDriverMapStyleNavStreetLight,
          cockpitVisualStyle: DriverCockpitMapVisualStyle.light,
        ).allowMovementSync,
        isFalse,
      );
    });

    test('HUD taxi remains visible while model is loading', () {
      final loading = dedicated3dEligibility(
        modelRegistered: true,
        modelPoseApplied: false,
        hideHudIsolationFlagEnabled: true,
      );
      expect(loading.hudTaxiHidden, isFalse);
      expect(loading.mapbox2dTaxiHidden, isFalse);
      expect(
        resolveHideMapboxTaxiMarkerFromEligibility(
          hideForHudOverlay: false,
          eligibility: loading,
        ),
        isFalse,
      );
    });

    test('HUD taxi restored on model failure via missing handoff', () {
      final failed = dedicated3dEligibility(
        modelRegistered: false,
        modelPoseApplied: false,
        hideHudIsolationFlagEnabled: true,
      );
      expect(failed.hudTaxiHidden, isFalse);
      expect(failed.mapbox2dTaxiHidden, isFalse);
    });

    test('fallback survives style reload movement reset', () {
      final lifecycle = NavVehicleModelSyncLifecycle();
      lifecycle.enableSessionFallback2d();
      lifecycle.clearMovementStateForStyleRestore();
      expect(lifecycle.sessionFallback2d, isTrue);
      final eligibility = dedicated3dEligibility(sessionFallback2d: true);
      expect(eligibility.selectorVisible, isFalse);
      expect(eligibility.reason, 'session_fallback_2d');
    });

    test('new navigation session resets fallback', () {
      final lifecycle = NavVehicleModelSyncLifecycle();
      lifecycle.enableSessionFallback2d();
      lifecycle.resetForNewNavigationSession();
      expect(lifecycle.sessionFallback2d, isFalse);
      expect(dedicated3dEligibility().allowMovementSync, isTrue);
    });

    test('leaving 3D tears down eligibility and restores normal taxi', () {
      final leaving = dedicated3dEligibility(
        modelRegistered: true,
        modelPoseApplied: true,
        presentationMode: NavigationPresentationMode.overview,
      );
      expect(leaving.allowModelLayer, isFalse);
      expect(leaving.mapbox2dTaxiHidden, isFalse);
      expect(leaving.hudTaxiHidden, isFalse);
    });

    test('entering 3D hides HUD only after activation confirmation', () {
      final registeredOnly = dedicated3dEligibility(
        modelRegistered: true,
        layerCreated: true,
        sourceGeometryValid: true,
        modelPoseApplied: false,
      );
      expect(registeredOnly.mapbox2dTaxiHidden, isFalse);
      expect(registeredOnly.hudTaxiHidden, isFalse);
      expect(registeredOnly.driver3dVisualReady, isFalse);

      final poseOnly = dedicated3dEligibility(
        modelRegistered: true,
        layerCreated: true,
        sourceGeometryValid: true,
        modelPoseApplied: true,
        modelActivationConfirmed: false,
        activeStyleGeneration: 1,
        activePresetGeneration: 4,
        modelLayerStyleGeneration: 1,
        modelLayerPresetGeneration: 4,
      );
      expect(poseOnly.mapbox2dTaxiHidden, isFalse);
      expect(poseOnly.hudTaxiHidden, isFalse);
      expect(poseOnly.driver3dVisualReady, isFalse);

      final handoff = confirmed3dHandoffEligibility();
      expect(handoff.modelReady, isTrue);
      expect(handoff.mapbox2dTaxiHidden, isTrue);
      expect(handoff.hudTaxiHidden, isTrue);
      expect(handoff.hudFallbackAllowedToHide, isTrue);
    });

    test(
      'Classic preset keeps HUD until activation confirmation',
      () {
        final classicPoseOnly = resolveDriver3dVehicleEligibility(
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
          modelActivationConfirmed: false,
          activeStyleGeneration: 1,
          activePresetGeneration: 4,
          confirmedStyleGeneration: -1,
          confirmedPresetGeneration: -1,
          modelLayerStyleGeneration: 1,
          modelLayerPresetGeneration: 4,
          followLiveActive: true,
          useDriver3dVehicleModel: true,
        );
        expect(classicPoseOnly.hudTaxiHidden, isFalse);
        expect(classicPoseOnly.mapbox2dTaxiHidden, isFalse);
        expect(classicPoseOnly.driver3dVisualReady, isFalse);
      },
    );

    test('hide HUD flag alone does not hide taxi without model handoff', () {
      final intentOnly = dedicated3dEligibility(
        hideHudIsolationFlagEnabled: true,
        modelRegistered: false,
        modelPoseApplied: false,
      );
      expect(intentOnly.hudTaxiHidden, isFalse);
    });
  });

  group('NAV-3D-VEHICLE-RESTORE-DIAG-1 activation diagnostics', () {
    Driver3dVehicleEligibility dedicatedEligible() {
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
        sessionFallback2d: false,
        styleLoaded: true,
        styleSwapInProgress: false,
        modelRegistered: true,
        modelPoseApplied: true,
        hideHudIsolationFlagEnabled: true,
      );
    }

    test('feature flag off maps to feature_disabled', () {
      final snapshot = resolveNav3dVehicleDiagnosticSnapshot(
        presentationActive: true,
        featureEnabled: false,
        cockpitSceneEnabled: true,
        cockpitVisualStyle: DriverCockpitMapVisualStyle.standard3d,
        vehiclePreset: DriverVehicle3dPreset.fluxidiTaxi,
        activeStyleUri: kDriverMapStyleStandard,
        eligibility: dedicatedEligible(),
        assetLoaded: true,
        modelRegistered: false,
        layerCreated: false,
        modelPoseApplied: false,
        modelActivationConfirmed: false,
        registerInFlight: false,
      );
      expect(
        snapshot.fallbackReason,
        Nav3dVehicleFallbackReason.featureDisabled,
      );
      expect(snapshot.effectivelyActive, isFalse);
    });

    test('light cockpit choice maps to vehicle_choice_not_3d', () {
      final eligibility = resolveDriver3dVehicleEligibility(
        vehicleModelFlagEnabled: true,
        cockpitSceneEnabled: true,
        useDriverCockpitCamera: true,
        presentationMode: NavigationPresentationMode.driver,
        liveNavigationActive: true,
        followCamera: true,
        activeStyleUri: kDriverMapStyleNavStreetLight,
        visualMode: DriverMapVisualMode.street,
        cockpitSceneActive: true,
        cockpitVisualStyle: DriverCockpitMapVisualStyle.light,
        sessionFallback2d: false,
        styleLoaded: true,
        styleSwapInProgress: false,
        modelRegistered: false,
        modelPoseApplied: false,
        hideHudIsolationFlagEnabled: false,
      );
      final snapshot = resolveNav3dVehicleDiagnosticSnapshot(
        presentationActive: true,
        featureEnabled: true,
        cockpitSceneEnabled: true,
        cockpitVisualStyle: DriverCockpitMapVisualStyle.light,
        vehiclePreset: DriverVehicle3dPreset.fluxidiTaxi,
        activeStyleUri: kDriverMapStyleNavStreetLight,
        eligibility: eligibility,
        assetLoaded: true,
        modelRegistered: false,
        layerCreated: false,
        modelPoseApplied: false,
        modelActivationConfirmed: false,
        registerInFlight: false,
      );
      expect(
        snapshot.fallbackReason,
        Nav3dVehicleFallbackReason.vehicleChoiceNot3d,
      );
      expect(snapshot.styleEligible, isFalse);
    });

    test('Fluxidi taxi preset is GLB path not HUD overlay', () {
      final fluxidi = resolveDriverVehicle3dModelSpec(
        DriverVehicle3dPreset.fluxidiTaxi,
      );
      expect(fluxidi.label, 'Fluxidi taxi');
      expect(fluxidi.assetUri, 'asset://assets/navigation/driver_taxi_3d.glb');
      expect(
        driverVehicle3dAssetBundlePath(fluxidi.assetUri),
        'assets/navigation/driver_taxi_3d.glb',
      );
      expect(kDriverTaxiMarkerAssetPath, isNot(contains('.glb')));
    });

    test(
      'NAV-VEHICLE-MODE-CAR-ARROW-1: 3D vehicle GLB assets are retired from '
      'the app bundle and disk',
      () async {
        TestWidgetsFlutterBinding.ensureInitialized();
        final manifest = await rootBundle.loadString('AssetManifest.json');
        expect(
          manifest,
          isNot(contains('assets/navigation/driver_taxi_3d.glb')),
        );
        expect(
          File('assets/navigation/driver_taxi_3d.glb').existsSync(),
          isFalse,
        );
        expect(
          File(
            'assets/navigation/vehicles/classic_flying_taxi.glb',
          ).existsSync(),
          isFalse,
        );
      },
    );

    test('effective activation requires registered layer and pose', () {
      final eligibility = dedicatedEligible();
      final pending = resolveNav3dVehicleDiagnosticSnapshot(
        presentationActive: true,
        featureEnabled: true,
        cockpitSceneEnabled: true,
        cockpitVisualStyle: DriverCockpitMapVisualStyle.standard3d,
        vehiclePreset: DriverVehicle3dPreset.classicFlyingTaxi,
        activeStyleUri: kDriverMapStyleStandard,
        eligibility: eligibility,
        assetLoaded: true,
        modelRegistered: true,
        layerCreated: true,
        modelPoseApplied: false,
        modelActivationConfirmed: false,
        registerInFlight: false,
      );
      expect(pending.effectivelyActive, isFalse);
      expect(pending.fallbackReason, Nav3dVehicleFallbackReason.none);

      final active = resolveNav3dVehicleDiagnosticSnapshot(
        presentationActive: true,
        featureEnabled: true,
        cockpitSceneEnabled: true,
        cockpitVisualStyle: DriverCockpitMapVisualStyle.standard3d,
        vehiclePreset: DriverVehicle3dPreset.classicFlyingTaxi,
        activeStyleUri: kDriverMapStyleStandard,
        eligibility: eligibility,
        assetLoaded: true,
        modelRegistered: true,
        layerCreated: true,
        modelPoseApplied: true,
        modelActivationConfirmed: true,
        renderCredibilityConfirmed: true,
        registerInFlight: false,
      );
      expect(active.effectivelyActive, isTrue);
      expect(active.fallbackReason, Nav3dVehicleFallbackReason.none);
    });
  });

  group('NAV-3D-ASSET-PROBE-LIFECYCLE-OOM-1 asset lifecycle', () {
    Driver3dVehicleAssetLoadContext eligibleLoadContext({
      bool vehicleModelFlagEnabled = true,
      bool cockpitSceneEnabled = true,
      bool useDriverCockpitCamera = true,
      NavigationPresentationMode presentationMode =
          NavigationPresentationMode.driver,
      bool liveNavigationActive = true,
      bool followCamera = true,
      String? activeStyleUri = kDriverMapStyleStandard,
      DriverMapVisualMode visualMode = DriverMapVisualMode.street,
      bool cockpitSceneActive = true,
      DriverCockpitMapVisualStyle? cockpitVisualStyle =
          DriverCockpitMapVisualStyle.standard3d,
      bool sessionFallback2d = false,
      bool styleLoaded = true,
      bool styleSwapInProgress = false,
    }) {
      return Driver3dVehicleAssetLoadContext(
        vehicleModelFlagEnabled: vehicleModelFlagEnabled,
        cockpitSceneEnabled: cockpitSceneEnabled,
        useDriverCockpitCamera: useDriverCockpitCamera,
        presentationMode: presentationMode,
        liveNavigationActive: liveNavigationActive,
        followCamera: followCamera,
        activeStyleUri: activeStyleUri,
        visualMode: visualMode,
        cockpitSceneActive: cockpitSceneActive,
        cockpitVisualStyle: cockpitVisualStyle,
        sessionFallback2d: sessionFallback2d,
        styleLoaded: styleLoaded,
        styleSwapInProgress: styleSwapInProgress,
      );
    }

    test('asset load eligibility mirrors dedicated 3D runtime gate', () {
      expect(
        resolveDriver3dVehicleAssetLoadEligible(eligibleLoadContext()),
        isTrue,
      );
      expect(
        resolveDriver3dVehicleAssetLoadIneligibleReason(
          eligibleLoadContext(useDriverCockpitCamera: false),
        ),
        'cockpit_camera_off',
      );
      expect(
        resolveDriver3dVehicleAssetLoadEligible(
          eligibleLoadContext(
            presentationMode: NavigationPresentationMode.overview,
          ),
        ),
        isFalse,
      );
      expect(
        resolveDriver3dVehicleAssetLoadEligible(
          eligibleLoadContext(liveNavigationActive: false),
        ),
        isFalse,
      );
      expect(
        resolveDriver3dVehicleAssetLoadEligible(
          eligibleLoadContext(
            cockpitVisualStyle: DriverCockpitMapVisualStyle.light,
            activeStyleUri: kDriverMapStyleNavStreetLight,
          ),
        ),
        isFalse,
      );
      expect(
        resolveDriver3dVehicleAssetLoadEligible(
          eligibleLoadContext(activeStyleUri: kDriverMapStyleNavStreetDark),
        ),
        isFalse,
      );
      expect(
        resolveDriver3dVehicleAssetLoadEligible(
          eligibleLoadContext(
            activeStyleUri: kDriverMapStyleStandardSatellite,
          ),
        ),
        isFalse,
      );
      expect(
        resolveDriver3dVehicleAssetLoadEligible(
          eligibleLoadContext(styleLoaded: false),
        ),
        isFalse,
      );
      expect(
        resolveDriver3dVehicleAssetLoadEligible(
          eligibleLoadContext(vehicleModelFlagEnabled: false),
        ),
        isFalse,
      );
    });

    test('startup-style diagnostic contexts skip asset loader', () async {
      var loadCalls = 0;
      final lifecycle = Driver3dVehicleAssetLifecycle(
        loader: (_) async {
          loadCalls++;
          return 1024;
        },
      );

      final overview = eligibleLoadContext(
        presentationMode: NavigationPresentationMode.overview,
        useDriverCockpitCamera: false,
        cockpitSceneActive: false,
      );
      expect(await lifecycle.ensureLoadedIfEligible(
        context: overview,
        preset: DriverVehicle3dPreset.fluxidiTaxi,
        styleGeneration: 0,
        presetGeneration: 0,
      ), isFalse);
      expect(loadCalls, 0);

      final cockpitOff = eligibleLoadContext(useDriverCockpitCamera: false);
      expect(await lifecycle.ensureLoadedIfEligible(
        context: cockpitOff,
        preset: DriverVehicle3dPreset.fluxidiTaxi,
        styleGeneration: 0,
        presetGeneration: 0,
      ), isFalse);
      expect(loadCalls, 0);

      expect(
        lifecycle.observationalAssetLoaded(
          preset: DriverVehicle3dPreset.fluxidiTaxi,
          styleGeneration: 0,
          presetGeneration: 0,
        ),
        isFalse,
      );
    });

    test('eligible 3D mode loads once and diagnostics stay observational', () async {
      var loadCalls = 0;
      final lifecycle = Driver3dVehicleAssetLifecycle(
        loader: (_) async {
          loadCalls++;
          return 2048;
        },
      );
      const preset = DriverVehicle3dPreset.fluxidiTaxi;
      const context = Driver3dVehicleAssetLoadContext(
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
      );

      expect(await lifecycle.ensureLoadedIfEligible(
        context: context,
        preset: preset,
        styleGeneration: 1,
        presetGeneration: 2,
      ), isTrue);
      expect(loadCalls, 1);
      expect(lifecycle.loadInvocationCount, 1);

      expect(await lifecycle.ensureLoadedIfEligible(
        context: context,
        preset: preset,
        styleGeneration: 1,
        presetGeneration: 2,
      ), isTrue);
      expect(loadCalls, 1);

      expect(
        lifecycle.observationalAssetLoaded(
          preset: preset,
          styleGeneration: 1,
          presetGeneration: 2,
        ),
        isTrue,
      );
    });

    test('concurrent eligible requests coalesce to one load', () async {
      var loadCalls = 0;
      final lifecycle = Driver3dVehicleAssetLifecycle(
        loader: (_) async {
          loadCalls++;
          await Future<void>.delayed(const Duration(milliseconds: 20));
          return 4096;
        },
      );
      const context = Driver3dVehicleAssetLoadContext(
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
      );

      final results = await Future.wait([
        lifecycle.ensureLoadedIfEligible(
          context: context,
          preset: DriverVehicle3dPreset.fluxidiTaxi,
          styleGeneration: 0,
          presetGeneration: 0,
        ),
        lifecycle.ensureLoadedIfEligible(
          context: context,
          preset: DriverVehicle3dPreset.fluxidiTaxi,
          styleGeneration: 0,
          presetGeneration: 0,
        ),
      ]);
      expect(results, [isTrue, isTrue]);
      expect(loadCalls, 1);
    });

    test('stale generation completion is ignored after invalidation', () async {
      final completer = Completer<int>();
      var loadCalls = 0;
      final lifecycle = Driver3dVehicleAssetLifecycle(
        loader: (_) async {
          loadCalls++;
          return completer.future;
        },
      );
      const context = Driver3dVehicleAssetLoadContext(
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
      );

      final inFlight = lifecycle.ensureLoadedIfEligible(
        context: context,
        preset: DriverVehicle3dPreset.fluxidiTaxi,
        styleGeneration: 0,
        presetGeneration: 0,
      );
      lifecycle.invalidateForStyleGeneration();
      completer.complete(8192);
      expect(await inFlight, isFalse);
      expect(loadCalls, 1);

      expect(
        lifecycle.observationalAssetLoaded(
          preset: DriverVehicle3dPreset.fluxidiTaxi,
          styleGeneration: 0,
          presetGeneration: 0,
        ),
        isFalse,
      );
    });

    test('load failure is cached and keeps observational assetLoaded false', () async {
      final lifecycle = Driver3dVehicleAssetLifecycle(
        loader: (_) async {
          throw StateError('simulated_load_failure');
        },
      );
      const context = Driver3dVehicleAssetLoadContext(
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
      );

      expect(await lifecycle.ensureLoadedIfEligible(
        context: context,
        preset: DriverVehicle3dPreset.classicFlyingTaxi,
        styleGeneration: 3,
        presetGeneration: 4,
      ), isFalse);
      expect(lifecycle.loadInvocationCount, 1);

      expect(await lifecycle.ensureLoadedIfEligible(
        context: context,
        preset: DriverVehicle3dPreset.classicFlyingTaxi,
        styleGeneration: 3,
        presetGeneration: 4,
      ), isFalse);
      expect(lifecycle.loadInvocationCount, 1);

      final eligibility = dedicated3dEligibility();
      final snapshot = resolveNav3dVehicleDiagnosticSnapshot(
        presentationActive: true,
        featureEnabled: true,
        cockpitSceneEnabled: true,
        cockpitVisualStyle: DriverCockpitMapVisualStyle.standard3d,
        vehiclePreset: DriverVehicle3dPreset.classicFlyingTaxi,
        activeStyleUri: kDriverMapStyleStandard,
        eligibility: eligibility,
        assetLoaded: lifecycle.observationalAssetLoaded(
          preset: DriverVehicle3dPreset.classicFlyingTaxi,
          styleGeneration: 3,
          presetGeneration: 4,
        ),
        modelRegistered: false,
        layerCreated: false,
        modelPoseApplied: false,
        modelActivationConfirmed: false,
        registerInFlight: false,
      );
      expect(snapshot.assetLoaded, isFalse);
      expect(snapshot.fallbackReason, Nav3dVehicleFallbackReason.assetMissing);
      expect(snapshot.effectivelyActive, isFalse);
    });

    test('preset generation invalidation requires a new load', () async {
      var loadCalls = 0;
      final lifecycle = Driver3dVehicleAssetLifecycle(
        loader: (_) async {
          loadCalls++;
          return 512;
        },
      );
      const context = Driver3dVehicleAssetLoadContext(
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
      );

      expect(await lifecycle.ensureLoadedIfEligible(
        context: context,
        preset: DriverVehicle3dPreset.fluxidiTaxi,
        styleGeneration: 1,
        presetGeneration: 1,
      ), isTrue);
      lifecycle.invalidateForPresetGeneration();
      expect(await lifecycle.ensureLoadedIfEligible(
        context: context,
        preset: DriverVehicle3dPreset.classicFlyingTaxi,
        styleGeneration: 1,
        presetGeneration: 2,
      ), isTrue);
      expect(loadCalls, 2);
    });
  });

  group('NAV-3D-DIAGNOSTIC-RECURSION-STACKOVERFLOW-1 logging coordinator', () {
    Nav3dVehicleDiagnosticSnapshot testDiagnosticSnapshot({
      Driver3dVehicleEligibility? eligibility,
      bool assetLoaded = false,
    }) {
      return resolveNav3dVehicleDiagnosticSnapshot(
        presentationActive: false,
        featureEnabled: true,
        cockpitSceneEnabled: true,
        cockpitVisualStyle: DriverCockpitMapVisualStyle.standard3d,
        vehiclePreset: DriverVehicle3dPreset.fluxidiTaxi,
        activeStyleUri: kDriverMapStyleStandard,
        eligibility: eligibility ?? dedicated3dEligibility(),
        assetLoaded: assetLoaded,
        modelRegistered: false,
        layerCreated: false,
        modelPoseApplied: false,
        modelActivationConfirmed: false,
        registerInFlight: false,
      );
    }

    Nav3dVehicleHandoffSnapshot testHandoffSnapshot() {
      return const Nav3dVehicleHandoffSnapshot(
        preset: 'fluxidi_taxi',
        modelRegistered: false,
        layerCreated: false,
        sourceGeometryValid: false,
        modelPoseApplied: false,
        modelActivationConfirmed: false,
        hudFallbackAllowedToHide: false,
        hudTaxiHidden: false,
        activeStyleGeneration: 0,
        activePresetGeneration: 0,
        confirmedStyleGeneration: -1,
        confirmedPresetGeneration: -1,
        styleModelId: kDriverVehicleFluxidiTaxiStyleModelId,
        assetUri: kDriverVehicleModelAssetUri,
        appliedScale: '0.0',
        appliedRotation: '0.0',
        appliedElevation: 0.0,
      );
    }

    test('single coordinator call invokes each leaf exactly once', () {
      final coordinator = Driver3dVehicleDiagnosticLogCoordinator();
      final eligibility = dedicated3dEligibility();
      coordinator.logStateIfChanged(
        eligibility: eligibility,
        diagnosticSnapshot: testDiagnosticSnapshot(eligibility: eligibility),
        handoffSnapshot: testHandoffSnapshot(),
      );
      expect(coordinator.coordinatorInvocations, 1);
      expect(coordinator.gateLeafInvocations, 1);
      expect(coordinator.diagnosticLeafInvocations, 1);
      expect(coordinator.handoffLeafInvocations, 1);
    });

    test('leaf loggers never call back into the coordinator', () {
      final coordinator = Driver3dVehicleDiagnosticLogCoordinator();
      final eligibility = resolveDriver3dVehicleEligibility(
        vehicleModelFlagEnabled: true,
        cockpitSceneEnabled: true,
        useDriverCockpitCamera: false,
        presentationMode: NavigationPresentationMode.overview,
        liveNavigationActive: true,
        followCamera: true,
        activeStyleUri: kDriverMapStyleNavStreetDark,
        visualMode: DriverMapVisualMode.street,
        cockpitSceneActive: false,
        cockpitVisualStyle: DriverCockpitMapVisualStyle.dark,
        sessionFallback2d: false,
        styleLoaded: true,
        styleSwapInProgress: false,
        modelRegistered: false,
        modelPoseApplied: false,
        hideHudIsolationFlagEnabled: true,
      );
      final diagnostic = testDiagnosticSnapshot(eligibility: eligibility);
      final handoff = testHandoffSnapshot();

      for (var i = 0; i < 200; i++) {
        coordinator.logStateIfChanged(
          eligibility: eligibility,
          diagnosticSnapshot: diagnostic,
          handoffSnapshot: handoff,
        );
      }

      expect(coordinator.coordinatorInvocations, 200);
      expect(coordinator.gateLeafInvocations, 200);
      expect(coordinator.diagnosticLeafInvocations, 200);
      expect(coordinator.handoffLeafInvocations, 200);
    });

    test('dark style switch with cockpit off stays bounded and linear', () {
      final coordinator = Driver3dVehicleDiagnosticLogCoordinator();
      final lightStyle = resolveDriver3dVehicleEligibility(
        vehicleModelFlagEnabled: true,
        cockpitSceneEnabled: true,
        useDriverCockpitCamera: false,
        presentationMode: NavigationPresentationMode.overview,
        liveNavigationActive: true,
        followCamera: true,
        activeStyleUri: kDriverMapStyleNavStreetLight,
        visualMode: DriverMapVisualMode.street,
        cockpitSceneActive: false,
        cockpitVisualStyle: DriverCockpitMapVisualStyle.light,
        sessionFallback2d: false,
        styleLoaded: true,
        styleSwapInProgress: false,
        modelRegistered: false,
        modelPoseApplied: false,
        hideHudIsolationFlagEnabled: true,
      );
      final darkStyle = resolveDriver3dVehicleEligibility(
        vehicleModelFlagEnabled: true,
        cockpitSceneEnabled: true,
        useDriverCockpitCamera: false,
        presentationMode: NavigationPresentationMode.overview,
        liveNavigationActive: true,
        followCamera: true,
        activeStyleUri: kDriverMapStyleNavStreetDark,
        visualMode: DriverMapVisualMode.street,
        cockpitSceneActive: false,
        cockpitVisualStyle: DriverCockpitMapVisualStyle.dark,
        sessionFallback2d: false,
        styleLoaded: true,
        styleSwapInProgress: false,
        modelRegistered: false,
        modelPoseApplied: false,
        hideHudIsolationFlagEnabled: true,
      );

      coordinator.logStateIfChanged(
        eligibility: lightStyle,
        diagnosticSnapshot: testDiagnosticSnapshot(eligibility: lightStyle),
        handoffSnapshot: testHandoffSnapshot(),
      );
      coordinator.logStateIfChanged(
        eligibility: darkStyle,
        diagnosticSnapshot: testDiagnosticSnapshot(eligibility: darkStyle),
        handoffSnapshot: testHandoffSnapshot(),
      );

      expect(coordinator.coordinatorInvocations, 2);
      expect(coordinator.gateLeafInvocations, 2);
      expect(coordinator.diagnosticLeafInvocations, 2);
      expect(coordinator.handoffLeafInvocations, 2);
      expect(lightStyle.reason, 'cockpit_camera_off');
      expect(darkStyle.reason, 'cockpit_camera_off');
    });

    test('re-entrant coordinator call during logging is ignored', () {
      final coordinator = Driver3dVehicleDiagnosticLogCoordinator();
      final eligibility = dedicated3dEligibility();
      final diagnostic = testDiagnosticSnapshot(eligibility: eligibility);
      final handoff = testHandoffSnapshot();
      var nestedAttempts = 0;

      coordinator.onDuringLogForTest = () {
        nestedAttempts++;
        coordinator.logStateIfChanged(
          eligibility: eligibility,
          diagnosticSnapshot: diagnostic,
          handoffSnapshot: handoff,
        );
      };

      coordinator.logStateIfChanged(
        eligibility: eligibility,
        diagnosticSnapshot: diagnostic,
        handoffSnapshot: handoff,
      );

      expect(nestedAttempts, 1);
      expect(coordinator.coordinatorInvocations, 1);
      expect(coordinator.gateLeafInvocations, 1);
    });

    test('repeated identical gate state deduplicates gate emission', () {
      final coordinator = Driver3dVehicleDiagnosticLogCoordinator();
      final eligibility = dedicated3dEligibility();
      final diagnostic = testDiagnosticSnapshot(eligibility: eligibility);
      final handoff = testHandoffSnapshot();

      coordinator.logStateIfChanged(
        eligibility: eligibility,
        diagnosticSnapshot: diagnostic,
        handoffSnapshot: handoff,
      );
      coordinator.logStateIfChanged(
        eligibility: eligibility,
        diagnosticSnapshot: diagnostic,
        handoffSnapshot: handoff,
      );

      expect(coordinator.coordinatorInvocations, 2);
      expect(coordinator.gateLeafInvocations, 2);
      expect(
        driver3dVehicleGateLogSignature(eligibility),
        driver3dVehicleGateLogSignature(eligibility),
      );
    });

    test('ineligible style switch does not invoke asset loader', () async {
      var loadCalls = 0;
      final lifecycle = Driver3dVehicleAssetLifecycle(
        loader: (_) async {
          loadCalls++;
          return 1024;
        },
      );
      const overviewDark = Driver3dVehicleAssetLoadContext(
        vehicleModelFlagEnabled: true,
        cockpitSceneEnabled: true,
        useDriverCockpitCamera: false,
        presentationMode: NavigationPresentationMode.overview,
        liveNavigationActive: true,
        followCamera: true,
        activeStyleUri: kDriverMapStyleNavStreetDark,
        visualMode: DriverMapVisualMode.street,
        cockpitSceneActive: false,
        cockpitVisualStyle: DriverCockpitMapVisualStyle.dark,
        sessionFallback2d: false,
        styleLoaded: true,
        styleSwapInProgress: false,
      );

      expect(await lifecycle.ensureLoadedIfEligible(
        context: overviewDark,
        preset: DriverVehicle3dPreset.fluxidiTaxi,
        styleGeneration: 0,
        presetGeneration: 0,
      ), isFalse);
      expect(loadCalls, 0);
    });
  });

  group('NAV-3D-FIRST-POSE-ACTIVATION-1 first pose lifecycle', () {
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
          force: false,
          firstPoseRequired: false,
        ),
        isFalse,
      );
      expect(
        resolveDriver3dVehicleFirstPoseBypassThrottle(
          force: true,
          firstPoseRequired: false,
        ),
        isTrue,
      );
    });

    test('style restore syncs movement generation for stale guard', () {
      final lifecycle = NavVehicleModelSyncLifecycle();
      lifecycle.bumpMovementGeneration();
      lifecycle.bumpMovementGeneration();
      expect(lifecycle.movementGeneration, 2);

      lifecycle.clearMovementStateForStyleRestore(movementGeneration: 0);
      expect(lifecycle.movementGeneration, 0);
      expect(lifecycle.shouldIgnoreStaleMovement(0), isFalse);
      expect(lifecycle.shouldIgnoreStaleMovement(2), isTrue);
      expect(lifecycle.firstPoseRequired, isTrue);
    });

    test('requeue restores pose consumed before registration completed', () {
      final lifecycle = NavVehicleModelSyncLifecycle();
      final now = DateTime(2026, 7, 13, 12);
      final pose = DriverVehicle3dMovementPose(
        lon: 4.9,
        lat: 52.3,
        bearingDeg: 180,
        source: 'first_pose_register_done',
        appliedZoom: 18.7,
        appliedPitch: 76,
        preset: DriverVehicle3dPreset.fluxidiTaxi,
        movementGeneration: 0,
      );

      expect(lifecycle.queueMovement(pose), 'queued');
      expect(lifecycle.beginMovementUpdate(now), isTrue);
      expect(lifecycle.consumeLatestRequest(), isNotNull);
      lifecycle.requeuePose(pose);
      lifecycle.cancelMovementUpdate();

      expect(lifecycle.queueMovement(pose), 'queued');
      expect(lifecycle.beginMovementUpdate(now), isTrue);
      expect(lifecycle.consumeLatestRequest()?.source, 'first_pose_register_done');
    });

    test('first pose satisfied clears bypass until handoff reset', () {
      final lifecycle = NavVehicleModelSyncLifecycle();
      expect(lifecycle.firstPoseRequired, isTrue);
      lifecycle.markFirstPoseSatisfied();
      expect(lifecycle.shouldBypassThrottleForFirstPose(), isFalse);
      lifecycle.markFirstPoseRequired();
      expect(lifecycle.shouldBypassThrottleForFirstPose(), isTrue);
    });

    test('confirmed handoff requires matching style and preset generations', () {
      final pending = dedicated3dEligibility(
        modelRegistered: true,
        layerCreated: true,
        sourceGeometryValid: true,
        modelPoseApplied: true,
        modelActivationConfirmed: false,
        activeStyleGeneration: 4,
        activePresetGeneration: 0,
      );
      expect(pending.hudFallbackAllowedToHide, isFalse);
      expect(pending.modelReady, isFalse);

      final confirmed = dedicated3dEligibility(
        modelRegistered: true,
        layerCreated: true,
        sourceGeometryValid: true,
        modelPoseApplied: true,
        modelActivationConfirmed: true,
        renderCredibilityConfirmed: true,
        assetLoaded: true,
        activeStyleGeneration: 4,
        activePresetGeneration: 0,
        confirmedStyleGeneration: 4,
        confirmedPresetGeneration: 0,
      );
      expect(confirmed.hudFallbackAllowedToHide, isTrue);
      expect(confirmed.modelReady, isTrue);
    });

    test('effectively active only after pose and activation confirmed', () {
      final eligibility = dedicated3dEligibility(
        modelRegistered: true,
        layerCreated: true,
        sourceGeometryValid: true,
        modelPoseApplied: true,
        modelActivationConfirmed: true,
        activeStyleGeneration: 4,
        activePresetGeneration: 0,
        confirmedStyleGeneration: 4,
        confirmedPresetGeneration: 0,
      );
      final snapshot = resolveNav3dVehicleDiagnosticSnapshot(
        presentationActive: true,
        featureEnabled: true,
        cockpitSceneEnabled: true,
        cockpitVisualStyle: DriverCockpitMapVisualStyle.standard3d,
        vehiclePreset: DriverVehicle3dPreset.fluxidiTaxi,
        activeStyleUri: kDriverMapStyleStandard,
        eligibility: eligibility,
        assetLoaded: true,
        modelRegistered: true,
        layerCreated: true,
        modelPoseApplied: true,
        modelActivationConfirmed: true,
        renderCredibilityConfirmed: true,
        registerInFlight: false,
      );
      expect(snapshot.effectivelyActive, isTrue);
    });

    test('effectively active false when assetLoaded is false', () {
      final eligibility = dedicated3dEligibility(
        modelRegistered: true,
        layerCreated: true,
        sourceGeometryValid: true,
        modelPoseApplied: true,
        modelActivationConfirmed: true,
        renderCredibilityConfirmed: true,
        assetLoaded: false,
        activeStyleGeneration: 4,
        activePresetGeneration: 0,
        confirmedStyleGeneration: 4,
        confirmedPresetGeneration: 0,
      );
      final snapshot = resolveNav3dVehicleDiagnosticSnapshot(
        presentationActive: true,
        featureEnabled: true,
        cockpitSceneEnabled: true,
        cockpitVisualStyle: DriverCockpitMapVisualStyle.standard3d,
        vehiclePreset: DriverVehicle3dPreset.fluxidiTaxi,
        activeStyleUri: kDriverMapStyleStandard,
        eligibility: eligibility,
        assetLoaded: false,
        modelRegistered: true,
        layerCreated: true,
        modelPoseApplied: true,
        modelActivationConfirmed: true,
        renderCredibilityConfirmed: true,
        registerInFlight: false,
      );
      expect(snapshot.effectivelyActive, isFalse);
    });

    test('failed pose keeps HUD fallback visible', () {
      final failed = dedicated3dEligibility(
        modelRegistered: true,
        layerCreated: true,
        sourceGeometryValid: true,
        modelPoseApplied: false,
        modelActivationConfirmed: false,
      );
      expect(failed.hudTaxiHidden, isFalse);
      expect(failed.hudFallbackAllowedToHide, isFalse);
    });
  });

  group('NAV-3D-RENDER-VISIBILITY-PROOF-1 render credibility', () {
    test('activation cannot confirm when assetLoaded is false', () {
      expect(
        resolveNav3dVehicleRenderCredibility(
          readback: const Nav3dVehicleRenderReadback(
            layerExists: true,
            sourceExists: true,
            layerVisible: true,
            sourceFeaturePresent: true,
            sourceHasValidPosition: true,
            modelIdBound: true,
            sourceModelIdBound: true,
            layerModelId: kDriverVehicleModelAssetUri,
          ),
          assetLoaded: false,
          modelPoseApplied: true,
        ),
        isFalse,
      );
    });

    test('activation cannot confirm without exact model-id binding', () {
      expect(
        resolveNav3dVehicleRenderCredibility(
          readback: const Nav3dVehicleRenderReadback(
            layerExists: true,
            sourceExists: true,
            layerVisible: true,
            sourceFeaturePresent: true,
            sourceHasValidPosition: true,
            modelIdBound: false,
            sourceModelIdBound: false,
            layerModelId: 'wrong-id',
          ),
          assetLoaded: true,
          modelPoseApplied: true,
        ),
        isFalse,
      );
    });

    test('activation cannot confirm when source feature is missing', () {
      expect(
        resolveNav3dVehicleRenderCredibility(
          readback: Nav3dVehicleRenderReadback.empty,
          assetLoaded: true,
          modelPoseApplied: true,
        ),
        isFalse,
      );
    });

    test('activation cannot confirm when layer visibility is none', () {
      expect(
        resolveNav3dVehicleRenderCredibility(
          readback: const Nav3dVehicleRenderReadback(
            layerExists: true,
            sourceExists: true,
            layerVisible: false,
            sourceFeaturePresent: true,
            sourceHasValidPosition: true,
            modelIdBound: true,
            sourceModelIdBound: true,
            layerVisibility: 'none',
          ),
          assetLoaded: true,
          modelPoseApplied: true,
        ),
        isFalse,
      );
    });

    test('debug mode keeps all 2D fallbacks visible', () {
      final debug = dedicated3dEligibility(
        modelRegistered: true,
        layerCreated: true,
        sourceGeometryValid: true,
        modelPoseApplied: true,
        modelActivationConfirmed: true,
        renderCredibilityConfirmed: true,
        assetLoaded: true,
        debugRenderProbeActive: true,
        activeStyleGeneration: 2,
        activePresetGeneration: 1,
        confirmedStyleGeneration: 2,
        confirmedPresetGeneration: 1,
      );
      expect(debug.hudFallbackAllowedToHide, isFalse);
      expect(debug.hudTaxiHidden, isFalse);
      expect(debug.mapbox2dTaxiHidden, isFalse);
    });

    test('production mode does not apply debug probe scale override', () {
      final productionScale = resolveDriverVehicleModelScaleForPreset(
        appliedZoom: 18.7,
        appliedPitch: 76,
        preset: DriverVehicle3dPreset.fluxidiTaxi,
        debugPlacementActive: false,
      );
      final probeScale = resolveDriverVehicleModelScaleForPreset(
        appliedZoom: 18.7,
        appliedPitch: 76,
        preset: DriverVehicle3dPreset.fluxidiTaxi,
        debugPlacementActive: false,
        debugProbeScale: 150,
      );
      expect(productionScale.first, lessThan(12));
      expect(probeScale, [150, 150, 150]);
    });

    test('both presets bind registered model id on feature and layer', () {
      for (final preset in DriverVehicle3dPreset.values) {
        final contract = resolveDriverVehicle3dBindingContract(preset);
        final data = driverVehicleModelGeoJsonData(
          lon: 10,
          lat: 59,
          modelId: contract.registeredModelId,
        );
        final parsed = parseDriverVehicleModelSourceJson(data);
        expect(parsed.sourceModelId, contract.registeredModelId);
        expect(
          resolveDriverVehicleModelLayerModelId(
            debugPlacementActive: false,
            preset: preset,
          ),
          contract.registeredModelId,
        );
        expect(
          contract.layerModelIdExpression,
          ['get', kDriverVehicleModelSourceModelIdProperty],
        );
      }
    });

    test('readback mismatch keeps hud handoff blocked', () {
      final blocked = dedicated3dEligibility(
        modelRegistered: true,
        layerCreated: true,
        sourceGeometryValid: true,
        modelPoseApplied: true,
        modelActivationConfirmed: true,
        renderCredibilityConfirmed: false,
        assetLoaded: true,
        activeStyleGeneration: 1,
        activePresetGeneration: 0,
        confirmedStyleGeneration: 1,
        confirmedPresetGeneration: 0,
      );
      expect(blocked.hudFallbackAllowedToHide, isFalse);
      expect(blocked.modelReady, isFalse);
    });

    test('registration verified restores observational assetLoaded after swap', () {
      final lifecycle = Driver3dVehicleAssetLifecycle();
      lifecycle.invalidateForPresetGeneration();
      lifecycle.markRegistrationVerified(
        preset: DriverVehicle3dPreset.classicFlyingTaxi,
        styleGeneration: 2,
        presetGeneration: 5,
      );
      expect(
        resolveObservationalAssetLoaded(
          lifecycle: lifecycle,
          preset: DriverVehicle3dPreset.classicFlyingTaxi,
          styleGeneration: 2,
          presetGeneration: 5,
          modelRegistered: true,
        ),
        isTrue,
      );
    });

    test('debug render probe scheduler cycles scale and altitude variants', () {
      final scheduler = Nav3dVehicleDebugRenderProbeScheduler();
      final seen = <String>{};
      for (var i = 0; i < 12; i++) {
        final probe = scheduler.advance();
        seen.add('${probe.scale}:${probe.altitude}');
      }
      expect(seen, contains('5.0:0.2'));
      expect(seen, contains('150.0:10.0'));
      expect(seen.length, greaterThan(1));
    });

    test('parse accepts legacy bare Point geojson', () {
      final legacy = json.encode({
        'type': 'Point',
        'coordinates': [24.94, 60.17],
      });
      final parsed = parseDriverVehicleModelSourceJson(legacy);
      expect(parsed.sourceFeaturePresent, isTrue);
      expect(parsed.sourceHasValidPosition, isTrue);
      expect(parsed.sourceLon, 24.94);
      expect(parsed.sourceLat, 60.17);
    });
  });

  group('NAV-3D-REGRESSION-BISECT-LAST-WORKING-1', () {
    test('source/layer JSON uses registered_id Feature binding contract', () {
      final contract = resolveDriverVehicle3dBindingContract(
        DriverVehicle3dPreset.fluxidiTaxi,
      );
      final geo = driverVehicleModelGeoJsonData(
        lon: 24.94,
        lat: 60.17,
        modelId: contract.registeredModelId,
      );
      expect(geo, contains('"type":"Point"'));
      expect(geo, contains('"type":"Feature"'));
      expect(geo, isNot(contains('FeatureCollection')));
      expect(geo, contains('"$kDriverVehicleModelSourceModelIdProperty"'));

      for (final preset in DriverVehicle3dPreset.values) {
        final binding = resolveDriverVehicle3dBindingContract(preset);
        final spec = resolveDriverVehicle3dModelSpec(preset);
        expect(
          resolveDriverVehicleModelLayerModelId(
            debugPlacementActive: false,
            preset: preset,
          ),
          binding.registeredModelId,
        );
        expect(spec.assetUri, startsWith('asset://assets/navigation/'));
        expect(binding.registeredModelId, isNot(contains('asset://')));
      }

      expect(
        resolveDriverVehicleModelRequiresStyleModelRegistration(
          debugPlacementActive: false,
        ),
        isTrue,
      );
      expect(
        resolveDriverVehicleModelIdModeLabel(debugPlacementActive: false),
        kDriverVehicleModelIdModeRegistered,
      );
    });
  });

  group('NAV-3D-PRESET-ORIENTATION-AND-HUD-HANDOFF-1', () {
    test('fluxidi preset headingOffsetDeg is 0 and classic is 180', () {
      final fluxidi = resolveDriverVehicle3dModelSpec(
        DriverVehicle3dPreset.fluxidiTaxi,
      );
      final classic = resolveDriverVehicle3dModelSpec(
        DriverVehicle3dPreset.classicFlyingTaxi,
      );
      expect(fluxidi.headingOffsetDeg, 0.0);
      expect(classic.headingOffsetDeg, 180.0);
    });

    test('classic final rotation includes +180° offset exactly once', () {
      const routeBearing = 90.0;
      final fluxidi = resolveDriverVehicleModelFinalRotationForPreset(
        routeBearing,
        preset: DriverVehicle3dPreset.fluxidiTaxi,
      );
      final classic = resolveDriverVehicleModelFinalRotationForPreset(
        routeBearing,
        preset: DriverVehicle3dPreset.classicFlyingTaxi,
      );
      expect(fluxidi, [0.0, 0.0, routeBearing]);
      expect(classic, [0.0, 0.0, routeBearing + 180.0]);
    });

    test('preset swap updates orientation immediately', () {
      const routeBearing = 45.0;
      final fluxidi = resolveDriverVehicleModelFinalRotationForPreset(
        routeBearing,
        preset: DriverVehicle3dPreset.fluxidiTaxi,
      );
      final classic = resolveDriverVehicleModelFinalRotationForPreset(
        routeBearing,
        preset: DriverVehicle3dPreset.classicFlyingTaxi,
      );
      expect(fluxidi[2], routeBearing);
      expect(classic[2], routeBearing + 180.0);
    });

    test('HUD hides after visual-ready with hide flag enabled', () {
      final confirmed = confirmed3dHandoffEligibility(
        hideHudIsolationFlagEnabled: true,
      );
      expect(confirmed.effectivelyActive, isTrue);
      expect(confirmed.driver3dVisualReady, isTrue);
      expect(confirmed.hudFallbackAllowedToHide, isTrue);
      expect(confirmed.hudTaxiHidden, isTrue);
      expect(confirmed.mapbox2dTaxiHidden, isTrue);

      final poseOnly = dedicated3dEligibility(
        modelRegistered: true,
        layerCreated: true,
        sourceGeometryValid: true,
        modelPoseApplied: true,
        modelActivationConfirmed: false,
        activeStyleGeneration: 3,
        activePresetGeneration: 2,
        modelLayerStyleGeneration: 3,
        modelLayerPresetGeneration: 2,
        hideHudIsolationFlagEnabled: true,
      );
      expect(poseOnly.driver3dVisualReady, isFalse);
      expect(poseOnly.hudTaxiHidden, isFalse);
      expect(poseOnly.mapbox2dTaxiHidden, isFalse);

      final diagnostic = confirmed3dHandoffEligibility(
        hideHudIsolationFlagEnabled: false,
      );
      expect(diagnostic.hudTaxiHidden, isFalse);
      expect(diagnostic.mapbox2dTaxiHidden, isTrue);
    });

    test('HUD stays visible when driver3dVisualReady is false', () {
      final partial = dedicated3dEligibility(
        modelRegistered: true,
        layerCreated: true,
        sourceGeometryValid: true,
        modelPoseApplied: true,
        modelActivationConfirmed: true,
        renderCredibilityConfirmed: false,
        assetLoaded: true,
        activeStyleGeneration: 3,
        activePresetGeneration: 2,
        confirmedStyleGeneration: 3,
        confirmedPresetGeneration: 2,
        modelLayerStyleGeneration: 2,
        modelLayerPresetGeneration: 2,
        hideHudIsolationFlagEnabled: true,
      );
      expect(partial.effectivelyActive, isFalse);
      expect(partial.driver3dVisualReady, isFalse);
      expect(partial.hudTaxiHidden, isFalse);
      expect(partial.mapbox2dTaxiHidden, isFalse);
    });

    test('HUD returns when driver3dVisualReady becomes false', () {
      final blocked = dedicated3dEligibility(
        modelRegistered: true,
        layerCreated: true,
        sourceGeometryValid: true,
        modelPoseApplied: true,
        modelActivationConfirmed: true,
        renderCredibilityConfirmed: true,
        assetLoaded: true,
        activeStyleGeneration: 4,
        activePresetGeneration: 1,
        confirmedStyleGeneration: 3,
        confirmedPresetGeneration: 1,
        modelLayerStyleGeneration: 3,
        modelLayerPresetGeneration: 1,
        hideHudIsolationFlagEnabled: true,
      );
      expect(blocked.hudFallbackAllowedToHide, isFalse);
      expect(blocked.driver3dVisualReady, isFalse);
      expect(blocked.hudTaxiHidden, isFalse);
      expect(blocked.mapbox2dTaxiHidden, isFalse);
      expect(blocked.modelReady, isFalse);
    });

    test('HUD returns on registration failure or pose invalidation', () {
      final regFailed = dedicated3dEligibility(
        modelRegistered: false,
        layerCreated: true,
        sourceGeometryValid: true,
        modelPoseApplied: true,
        modelActivationConfirmed: true,
        renderCredibilityConfirmed: true,
        assetLoaded: true,
        activeStyleGeneration: 3,
        activePresetGeneration: 2,
        confirmedStyleGeneration: 3,
        confirmedPresetGeneration: 2,
        hideHudIsolationFlagEnabled: true,
      );
      expect(regFailed.effectivelyActive, isFalse);
      expect(regFailed.hudTaxiHidden, isFalse);

      final poseInvalid = dedicated3dEligibility(
        modelRegistered: true,
        layerCreated: true,
        sourceGeometryValid: true,
        modelPoseApplied: false,
        modelActivationConfirmed: true,
        renderCredibilityConfirmed: true,
        assetLoaded: true,
        activeStyleGeneration: 3,
        activePresetGeneration: 2,
        confirmedStyleGeneration: 3,
        confirmedPresetGeneration: 2,
        hideHudIsolationFlagEnabled: true,
      );
      expect(poseInvalid.effectivelyActive, isFalse);
      expect(poseInvalid.hudTaxiHidden, isFalse);
    });

    test('registered_id binding remains intact for both presets', () {
      for (final preset in DriverVehicle3dPreset.values) {
        final contract = resolveDriverVehicle3dBindingContract(preset);
        expect(
          resolveDriverVehicleModelLayerModelId(
            debugPlacementActive: false,
            preset: preset,
          ),
          contract.registeredModelId,
        );
        expect(
          resolveDriverVehicleModelRequiresStyleModelRegistration(
            debugPlacementActive: false,
          ),
          isTrue,
        );
        expect(contract.registeredModelId, isNot(contains('asset://')));
      }
    });
  });

  group('NAV-3D-ORIENTATION-AND-PRODUCTION-HANDOFF-2', () {
    test('canonical pipeline applies preset offset exactly once', () {
      const bearing = 120.0;
      final fluxidi = resolveDriverVehicle3dModelOrientation(
        rawNavigationBearing: bearing,
        preset: DriverVehicle3dPreset.fluxidiTaxi,
      );
      final classic = resolveDriverVehicle3dModelOrientation(
        rawNavigationBearing: bearing,
        preset: DriverVehicle3dPreset.classicFlyingTaxi,
      );
      expect(fluxidi.presetOffsetDeg, 0.0);
      expect(classic.presetOffsetDeg, 180.0);
      expect(fluxidi.finalRotation, [0.0, 0.0, bearing]);
      expect(classic.finalRotation, [0.0, 0.0, bearing + 180.0]);
      expect(fluxidi.normalizedBearingDeg, bearing);
    });

    test('same bearing from all update sources produces identical rotation', () {
      const bearing = 45.0;
      const preset = DriverVehicle3dPreset.classicFlyingTaxi;
      final sources = [
        'first_pose_register_done',
        'route_snap',
        'snapshot',
        'camera_scale_cockpit_adjust',
        'movement_update',
        'register',
        'style_restore',
      ];
      final expected = resolveDriverVehicle3dModelOrientation(
        rawNavigationBearing: bearing,
        preset: preset,
      ).finalRotation;
      for (final source in sources) {
        final rotation = resolveDriverVehicleModelRotationForWrite(
          rawNavigationBearing: bearing,
          preset: preset,
          source: source,
          styleGeneration: 3,
          presetGeneration: 2,
        );
        expect(rotation, expected, reason: 'source=$source');
      }
    });

    test('camera-scale update preserves preset offset when bearing unchanged', () {
      const bearing = 90.0;
      const preset = DriverVehicle3dPreset.classicFlyingTaxi;
      final rotation = resolveDriverVehicle3dModelOrientation(
        rawNavigationBearing: bearing,
        preset: preset,
      ).finalRotation;
      final scaleBefore = resolveDriverVehicleModelScaleForPreset(
        appliedZoom: 18.0,
        appliedPitch: 70.0,
        preset: preset,
      );
      final scaleAfter = resolveDriverVehicleModelScaleForPreset(
        appliedZoom: 19.5,
        appliedPitch: 76.0,
        preset: preset,
      );
      final applied = DriverVehicleModelAppliedMovementState(
        lon: 4.9,
        lat: 52.3,
        bearingDeg: bearing,
        preset: preset,
        scale: scaleBefore,
        translation: driverVehicleModelTranslationForPreset(
          debugPlacementActive: false,
          preset: preset,
        ),
        rotation: rotation,
      );
      final plan = resolveDriverVehicleModelMovementWritePlan(
        applied: applied,
        lon: 4.9,
        lat: 52.3,
        bearingDeg: bearing,
        preset: preset,
        scale: scaleAfter,
        translation: driverVehicleModelTranslationForPreset(
          debugPlacementActive: false,
          preset: preset,
        ),
        rotation: rotation,
      );
      expect(plan.scaleChanged, isTrue);
      expect(plan.rotationChanged, isFalse);
      expect(rotation[2], bearing + 180.0);
    });

    test('style restore keeps correct orientation via canonical resolver', () {
      const bearing = 200.0;
      final rotation = resolveDriverVehicleModelRotationForWrite(
        rawNavigationBearing: bearing,
        preset: DriverVehicle3dPreset.classicFlyingTaxi,
        source: 'style_restore',
        styleGeneration: 5,
        presetGeneration: 1,
      );
      expect(rotation[2], 20.0);
    });
  });
}
