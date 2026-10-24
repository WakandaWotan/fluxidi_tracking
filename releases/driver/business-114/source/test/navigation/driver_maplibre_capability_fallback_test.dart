import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_gl/maplibre_gl.dart' as libre;
import 'package:fluxidi_tracking/navigation/driver_navigation_map_config.dart';
import 'package:fluxidi_tracking/navigation/presentation/navigation_driver_vehicle_model_layer.dart';
import 'package:fluxidi_tracking/navigation/presentation/navigation_presentation_flags.dart';
import 'package:fluxidi_tracking/navigation/presentation/navigation_presentation_mode.dart';
import 'package:fluxidi_tracking/navigation/rendering/driver_maplibre_surface.dart';

class NoNativeCalls implements libre.MapLibreMapController {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected native call: ${invocation.memberName}');
}

void main() {
  test('own light dark and perspective metadata never claim model or terrain', () {
    for (final entry in {
      kDriverMapStyleNavStreetLight: 'fluxidi-maplibre-light',
      kDriverMapStyleNavStreetDark: 'fluxidi-maplibre-dark',
      kDriverMapStyleStandard: 'fluxidi-maplibre-perspective',
    }.entries) {
      final cap = DriverCockpitMap3dCapability.resolve(
        styleUri: entry.key, visualMode: DriverMapVisualMode.threeD);
      expect(cap.styleFamily, entry.value);
      expect(cap.likelyFlatNavStyle, isTrue);
      expect(cap.is3dCandidate, isFalse);
      expect(cap.terrainLikelyAvailable, isFalse);
      expect(cap.note, contains('no_3d_model_binding'));
    }
  });
  test('removed satellite aliases light and unknown styles fail closed', () {
    expect(kDriverMapStyleSatellite, kDriverMapStyleNavStreetLight);
    expect(kDriverMapStyleStandardSatellite, kDriverMapStyleNavStreetLight);
    expect(kDriverMapSatelliteToggleEnabled, isFalse);
    expect(isExperimentalCockpit3dMapStyleUri(kDriverMapStyleStandard), isTrue);
    expect(isExperimentalCockpit3dMapStyleUri(kDriverMapStyleStandardSatellite), isFalse);
    expect(DriverCockpitMap3dCapability.resolve(
      styleUri: 'unknown-style', visualMode: DriverMapVisualMode.threeD,
    ).is3dCandidate, isFalse);
  });
  test('even stale positive native readiness cannot hide MapLibre HUD', () {
    for (final swapping in [false, true]) {
      final gate = resolveDriver3dVehicleEligibility(
        vehicleModelFlagEnabled: true, cockpitSceneEnabled: true,
        useDriverCockpitCamera: true, presentationMode: NavigationPresentationMode.driver,
        liveNavigationActive: true, followCamera: true,
        activeStyleUri: kDriverMapStyleStandard, visualMode: DriverMapVisualMode.threeD,
        cockpitSceneActive: true, cockpitVisualStyle: DriverCockpitMapVisualStyle.standard3d,
        sessionFallback2d: false, styleLoaded: true, styleSwapInProgress: swapping,
        modelRegistered: true, modelPoseApplied: true, hideHudIsolationFlagEnabled: true,
        layerCreated: true, sourceGeometryValid: true, modelActivationConfirmed: true,
        renderCredibilityConfirmed: true, assetLoaded: true,
        activeStyleGeneration: 3, activePresetGeneration: 2,
        confirmedStyleGeneration: 3, confirmedPresetGeneration: 2,
        modelLayerStyleGeneration: 3, modelLayerPresetGeneration: 2,
        followLiveActive: true, useDriver3dVehicleModel: true,
        native3dRendererActive: true,
      );
      expect(gate.eligible, isFalse);
      expect(gate.hudTaxiHidden, isFalse);
      expect(gate.mapbox2dTaxiHidden, isFalse);
      expect(gate.allowModelLayer, isFalse);
      expect(gate.allowMovementSync, isFalse);
      expect(gate.driver3dVisualReady, isFalse);
      expect(gate.hudFallbackAllowedToHide, isFalse);
    }
  });
  test('unbound model operations fail explicitly and feature flags stay off', () async {
    final style = DriverLibreStyle(NoNativeCalls(), (_) async {});
    await expectLater(style.setStyleLayerProperty('car', 'model-id', 'original-asset'),
      throwsUnsupportedError);
    expect(() => (style as dynamic).addStyleModel('car', 'original-asset'), throwsUnsupportedError);
    expect(kNavigation3dVehicleModelEnabled, isFalse);
    expect(kNavigation3dVehicleHideHudEnabled, isFalse);
    expect(kNavigationUseNativeFollowPuckEnabled, isFalse);
  });
}
