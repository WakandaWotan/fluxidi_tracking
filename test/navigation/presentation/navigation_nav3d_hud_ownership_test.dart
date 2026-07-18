import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/navigation/driver_navigation_map_config.dart';
import 'package:fluxidi_tracking/navigation/presentation/navigation_driver_vehicle_model_layer.dart';
import 'package:fluxidi_tracking/navigation/presentation/navigation_presentation_mode.dart';
import 'package:fluxidi_tracking/navigation/widgets/navigation_driver_hud_overlay.dart';

Driver3dVehicleEligibility dedicated3dEligibility({
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
  bool hideHudIsolationFlagEnabled = true,
  String? activeStyleUri = kDriverMapStyleStandard,
  DriverCockpitMapVisualStyle? cockpitVisualStyle =
      DriverCockpitMapVisualStyle.standard3d,
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
    styleLoaded: true,
    styleSwapInProgress: false,
    modelRegistered: modelRegistered,
    modelPoseApplied: modelPoseApplied,
    hideHudIsolationFlagEnabled: hideHudIsolationFlagEnabled,
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
  );
}

Nav3dHudRenderDecision renderDecisionFor({
  required Driver3dVehicleEligibility eligibility,
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
  bool showDriverHudOverlay = true,
  bool hideHudFlagEnabled = true,
  bool followLiveActive = true,
  bool explicit2dFallback = false,
  bool observationalAssetLoaded = true,
}) {
  final handoffAssetLoaded = resolveNav3dHandoffAssetLoadedForRender(
    observationalAssetLoaded: observationalAssetLoaded,
    modelRegistered: modelRegistered,
    modelActivationConfirmed: modelActivationConfirmed,
  );
  final handoff = resolveNav3dHudHandoffForRender(
    eligibility: eligibility,
    useDriver3dVehicleModel: true,
    followLiveActive: followLiveActive,
    observationalAssetLoaded: observationalAssetLoaded,
    handoffAssetLoaded: handoffAssetLoaded,
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
    showDriverHudOverlay: showDriverHudOverlay,
    hideHudFlagEnabled: hideHudFlagEnabled,
    explicit2dFallback: explicit2dFallback,
  );
  return resolveNav3dHudRenderDecision(
    hideHudFlagEnabled: hideHudFlagEnabled,
    presentation3dActive: handoff.presentation3dActive,
    driver3dVisualReady: handoff.driver3dVisualReady,
    effectivelyActive: handoff.effectivelyActive,
    hudFallbackAllowedToHide: handoff.hudFallbackAllowedToHide,
    showDriverHudOverlay: showDriverHudOverlay,
    followLiveActive: followLiveActive,
    explicit2dFallback: explicit2dFallback,
    ownership: handoff.ownership,
  );
}

void main() {
  group('NAV-3D-HUD-OWNERSHIP-FINAL-1', () {
    test('1. 3D visible-ready after activation confirmation => model3d owner', () {
      final eligibility = dedicated3dEligibility(
        modelRegistered: true,
        layerCreated: true,
        sourceGeometryValid: true,
        modelPoseApplied: true,
        modelActivationConfirmed: true,
        renderCredibilityConfirmed: true,
        confirmedStyleGeneration: 3,
        confirmedPresetGeneration: 2,
        modelLayerStyleGeneration: 3,
        modelLayerPresetGeneration: 2,
      );
      final decision = renderDecisionFor(
        eligibility: eligibility,
        modelRegistered: true,
        layerCreated: true,
        sourceGeometryValid: true,
        modelPoseApplied: true,
        modelActivationConfirmed: true,
        renderCredibilityConfirmed: true,
        confirmedStyleGeneration: 3,
        confirmedPresetGeneration: 2,
        modelLayerStyleGeneration: 3,
        modelLayerPresetGeneration: 2,
      );

      expect(eligibility.driver3dVisualReady, isTrue);
      expect(decision.owner, DriverVisualOwner.model3d);
      expect(decision.actualHudVisible, isFalse);
      expect(decision.mapbox2dVisible, isFalse);
      expect(decision.visibleDriverVisualCount, 1);
    });

    test(
      '2. activationConfirmed=false => HUD remains (no premature hide)',
      () {
        final decision = renderDecisionFor(
          eligibility: dedicated3dEligibility(
            modelRegistered: true,
            layerCreated: true,
            sourceGeometryValid: true,
            modelPoseApplied: true,
            modelLayerStyleGeneration: 3,
            modelLayerPresetGeneration: 2,
          ),
          modelRegistered: true,
          layerCreated: true,
          sourceGeometryValid: true,
          modelPoseApplied: true,
          modelActivationConfirmed: false,
          renderCredibilityConfirmed: false,
          modelLayerStyleGeneration: 3,
          modelLayerPresetGeneration: 2,
        );

        expect(decision.driver3dVisualReady, isFalse);
        expect(decision.owner, DriverVisualOwner.hud2d);
        expect(decision.actualHudVisible, isTrue);
        expect(decision.effectivelyActive, isFalse);
      },
    );

    test(
      '3. renderCredibilityConfirmed=false => HUD remains',
      () {
        final decision = renderDecisionFor(
          eligibility: dedicated3dEligibility(
            modelRegistered: true,
            layerCreated: true,
            sourceGeometryValid: true,
            modelPoseApplied: true,
            modelActivationConfirmed: true,
            renderCredibilityConfirmed: false,
            modelLayerStyleGeneration: 3,
            modelLayerPresetGeneration: 2,
          ),
          modelRegistered: true,
          layerCreated: true,
          sourceGeometryValid: true,
          modelPoseApplied: true,
          modelActivationConfirmed: true,
          renderCredibilityConfirmed: false,
          modelLayerStyleGeneration: 3,
          modelLayerPresetGeneration: 2,
        );

        expect(decision.driver3dVisualReady, isFalse);
        expect(decision.owner, DriverVisualOwner.hud2d);
        expect(decision.actualHudVisible, isTrue);
      },
    );

    test('4. layer/source lost => owner falls back to hud2d', () {
      final decision = renderDecisionFor(
        eligibility: dedicated3dEligibility(
          modelRegistered: true,
          layerCreated: false,
          sourceGeometryValid: false,
          modelPoseApplied: false,
        ),
        modelRegistered: true,
        layerCreated: false,
        sourceGeometryValid: false,
        modelPoseApplied: false,
      );

      expect(decision.driver3dVisualReady, isFalse);
      expect(decision.owner, DriverVisualOwner.hud2d);
      expect(decision.actualHudVisible, isTrue);
      expect(decision.mapbox2dVisible, isFalse);
    });

    test('5. style generation mismatch => owner falls back to hud2d', () {
      final decision = renderDecisionFor(
        eligibility: dedicated3dEligibility(
          modelRegistered: true,
          layerCreated: true,
          sourceGeometryValid: true,
          modelPoseApplied: true,
          activeStyleGeneration: 4,
          modelLayerStyleGeneration: 3,
          modelLayerPresetGeneration: 2,
        ),
        modelRegistered: true,
        layerCreated: true,
        sourceGeometryValid: true,
        modelPoseApplied: true,
        activeStyleGeneration: 4,
        activePresetGeneration: 2,
        modelLayerStyleGeneration: 3,
        modelLayerPresetGeneration: 2,
      );

      expect(decision.driver3dVisualReady, isFalse);
      expect(decision.owner, DriverVisualOwner.hud2d);
      expect(decision.actualHudVisible, isTrue);
    });

    test('6. preset generation mismatch => owner falls back to hud2d', () {
      final decision = renderDecisionFor(
        eligibility: dedicated3dEligibility(
          modelRegistered: true,
          layerCreated: true,
          sourceGeometryValid: true,
          modelPoseApplied: true,
          activePresetGeneration: 3,
          modelLayerStyleGeneration: 3,
          modelLayerPresetGeneration: 2,
        ),
        modelRegistered: true,
        layerCreated: true,
        sourceGeometryValid: true,
        modelPoseApplied: true,
        activeStyleGeneration: 3,
        activePresetGeneration: 3,
        modelLayerStyleGeneration: 3,
        modelLayerPresetGeneration: 2,
      );

      expect(decision.driver3dVisualReady, isFalse);
      expect(decision.owner, DriverVisualOwner.hud2d);
      expect(decision.actualHudVisible, isTrue);
    });

    test('7. leave 3D => owner=hud2d in normal follow mode', () {
      final eligibility = dedicated3dEligibility(
        activeStyleUri: kDriverMapStyleNavStreetLight,
        cockpitVisualStyle: DriverCockpitMapVisualStyle.light,
      );
      final decision = renderDecisionFor(
        eligibility: eligibility,
        followLiveActive: true,
      );

      expect(eligibility.driver3dVisualReady, isFalse);
      expect(decision.owner, DriverVisualOwner.hud2d);
      expect(decision.actualHudVisible, isTrue);
    });

    test('8. HUD disabled in 2D => owner=mapbox2d', () {
      final eligibility = dedicated3dEligibility(
        activeStyleUri: kDriverMapStyleNavStreetLight,
        cockpitVisualStyle: DriverCockpitMapVisualStyle.light,
      );
      final decision = renderDecisionFor(
        eligibility: eligibility,
        showDriverHudOverlay: false,
      );

      expect(decision.owner, DriverVisualOwner.mapbox2d);
      expect(decision.actualHudVisible, isFalse);
      expect(decision.mapbox2dVisible, isTrue);
    });

    test('9. invariant: visibleDriverVisualCount never exceeds 1', () {
      final cases = <Nav3dHudRenderDecision>[
        renderDecisionFor(
          eligibility: dedicated3dEligibility(
            modelRegistered: true,
            layerCreated: true,
            sourceGeometryValid: true,
            modelPoseApplied: true,
            modelLayerStyleGeneration: 3,
            modelLayerPresetGeneration: 2,
          ),
          modelRegistered: true,
          layerCreated: true,
          sourceGeometryValid: true,
          modelPoseApplied: true,
          modelLayerStyleGeneration: 3,
          modelLayerPresetGeneration: 2,
        ),
        renderDecisionFor(
          eligibility: dedicated3dEligibility(
            modelRegistered: true,
            layerCreated: true,
            sourceGeometryValid: true,
            modelPoseApplied: false,
          ),
          modelRegistered: true,
          layerCreated: true,
          sourceGeometryValid: true,
          modelPoseApplied: false,
        ),
        renderDecisionFor(
          eligibility: dedicated3dEligibility(
            activeStyleUri: kDriverMapStyleNavStreetLight,
            cockpitVisualStyle: DriverCockpitMapVisualStyle.light,
          ),
          showDriverHudOverlay: false,
        ),
      ];

      for (final decision in cases) {
        expect(decision.visibleDriverVisualCount, lessThanOrEqualTo(1));
      }
    });

    test('10. preset/style swap: only one owner at each state transition', () {
      final beforeSwap = renderDecisionFor(
        eligibility: dedicated3dEligibility(
          modelRegistered: true,
          layerCreated: true,
          sourceGeometryValid: true,
          modelPoseApplied: true,
          modelActivationConfirmed: true,
          renderCredibilityConfirmed: true,
          confirmedStyleGeneration: 3,
          confirmedPresetGeneration: 2,
          modelLayerStyleGeneration: 3,
          modelLayerPresetGeneration: 2,
        ),
        modelRegistered: true,
        layerCreated: true,
        sourceGeometryValid: true,
        modelPoseApplied: true,
        modelActivationConfirmed: true,
        renderCredibilityConfirmed: true,
        confirmedStyleGeneration: 3,
        confirmedPresetGeneration: 2,
        modelLayerStyleGeneration: 3,
        modelLayerPresetGeneration: 2,
      );
      expect(beforeSwap.owner, DriverVisualOwner.model3d);
      expect(beforeSwap.visibleDriverVisualCount, 1);

      final duringSwap = renderDecisionFor(
        eligibility: dedicated3dEligibility(
          modelRegistered: true,
          layerCreated: true,
          sourceGeometryValid: true,
          modelPoseApplied: true,
          modelActivationConfirmed: true,
          renderCredibilityConfirmed: true,
          activePresetGeneration: 3,
          confirmedStyleGeneration: 3,
          confirmedPresetGeneration: 2,
          modelLayerStyleGeneration: 3,
          modelLayerPresetGeneration: 2,
        ),
        modelRegistered: true,
        layerCreated: true,
        sourceGeometryValid: true,
        modelPoseApplied: true,
        modelActivationConfirmed: true,
        renderCredibilityConfirmed: true,
        activePresetGeneration: 3,
        confirmedStyleGeneration: 3,
        confirmedPresetGeneration: 2,
        modelLayerStyleGeneration: 3,
        modelLayerPresetGeneration: 2,
      );
      expect(duringSwap.owner, DriverVisualOwner.hud2d);
      expect(duringSwap.visibleDriverVisualCount, 1);

      final afterSwap = renderDecisionFor(
        eligibility: dedicated3dEligibility(
          modelRegistered: true,
          layerCreated: true,
          sourceGeometryValid: true,
          modelPoseApplied: true,
          modelActivationConfirmed: true,
          renderCredibilityConfirmed: true,
          activePresetGeneration: 3,
          confirmedStyleGeneration: 3,
          confirmedPresetGeneration: 3,
          modelLayerStyleGeneration: 3,
          modelLayerPresetGeneration: 3,
        ),
        modelRegistered: true,
        layerCreated: true,
        sourceGeometryValid: true,
        modelPoseApplied: true,
        modelActivationConfirmed: true,
        renderCredibilityConfirmed: true,
        activePresetGeneration: 3,
        confirmedStyleGeneration: 3,
        confirmedPresetGeneration: 3,
        modelLayerStyleGeneration: 3,
        modelLayerPresetGeneration: 3,
      );
      expect(afterSwap.owner, DriverVisualOwner.model3d);
      expect(afterSwap.visibleDriverVisualCount, 1);
    });

    testWidgets('HUD widget mount gate mirrors ownership decision', (
      WidgetTester tester,
    ) async {
      final decision = renderDecisionFor(
        eligibility: dedicated3dEligibility(
          modelRegistered: true,
          layerCreated: true,
          sourceGeometryValid: true,
          modelPoseApplied: true,
          modelActivationConfirmed: true,
          renderCredibilityConfirmed: true,
          confirmedStyleGeneration: 3,
          confirmedPresetGeneration: 2,
          modelLayerStyleGeneration: 3,
          modelLayerPresetGeneration: 2,
        ),
        modelRegistered: true,
        layerCreated: true,
        sourceGeometryValid: true,
        modelPoseApplied: true,
        modelActivationConfirmed: true,
        renderCredibilityConfirmed: true,
        confirmedStyleGeneration: 3,
        confirmedPresetGeneration: 2,
        modelLayerStyleGeneration: 3,
        modelLayerPresetGeneration: 2,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                if (decision.actualHudVisible)
                  const Center(child: NavigationDriverHudOverlay(iconSize: 56)),
              ],
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.byType(NavigationDriverHudOverlay), findsNothing);
    });
  });
}
