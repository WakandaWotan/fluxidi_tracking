import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/navigation/driver_navigation_map_config.dart';
import 'package:fluxidi_tracking/navigation/presentation/navigation_driver_vehicle_model_layer.dart';
import 'package:fluxidi_tracking/navigation/presentation/navigation_presentation_mode.dart';
import 'package:fluxidi_tracking/navigation/widgets/navigation_driver_hud_overlay.dart';

/// Mirrors the final Stack mount gate in driver_home_page_state.dart.
class DriverHudMountHarness extends StatelessWidget {
  const DriverHudMountHarness({
    super.key,
    required this.decision,
    this.iconSize = 56,
    this.followLiveActive = true,
  });

  final Nav3dHudRenderDecision decision;
  final double iconSize;
  final bool followLiveActive;

  @override
  Widget build(BuildContext context) {
    if (followLiveActive) {
      logNav3dHudRenderDecision(decision);
    }
    return Stack(
      children: [
        if (followLiveActive && decision.actualHudVisible)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Center(
              child: NavigationDriverHudOverlay(iconSize: iconSize),
            ),
          ),
      ],
    );
  }
}

void main() {
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
      sessionFallback2d: false,
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

  ({
    bool presentation3dActive,
    bool driver3dVisualReady,
    bool effectivelyActive,
    bool hudFallbackAllowedToHide,
    DriverVisualOwnership ownership,
  }) handoffFor({
    required Driver3dVehicleEligibility eligibility,
    bool observationalAssetLoaded = true,
    bool modelActivationConfirmed = false,
    bool modelRegistered = false,
    bool layerCreated = false,
    bool sourceGeometryValid = false,
    bool modelPoseApplied = false,
    bool renderCredibilityConfirmed = false,
    int activeStyleGeneration = 3,
    int activePresetGeneration = 2,
    int modelLayerStyleGeneration = -1,
    int modelLayerPresetGeneration = -1,
    int confirmedStyleGeneration = -1,
    int confirmedPresetGeneration = -1,
    bool useDriver3dVehicleModel = true,
    bool followLiveActive = true,
    bool showDriverHudOverlay = true,
    bool hideHudFlagEnabled = true,
    bool explicit2dFallback = false,
  }) {
    final handoffAssetLoaded = resolveNav3dHandoffAssetLoadedForRender(
      observationalAssetLoaded: observationalAssetLoaded,
      modelRegistered: modelRegistered,
      modelActivationConfirmed: modelActivationConfirmed,
    );
    return resolveNav3dHudHandoffForRender(
      eligibility: eligibility,
      useDriver3dVehicleModel: useDriver3dVehicleModel,
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
  }

  Nav3dHudRenderDecision renderDecisionFor({
    required Driver3dVehicleEligibility eligibility,
    bool hideHudFlagEnabled = true,
    bool showDriverHudOverlay = true,
    bool followLiveActive = true,
    bool explicit2dFallback = false,
    bool observationalAssetLoaded = true,
    bool modelActivationConfirmed = false,
    bool modelRegistered = false,
    bool layerCreated = false,
    bool sourceGeometryValid = false,
    bool modelPoseApplied = false,
    bool renderCredibilityConfirmed = false,
    int activeStyleGeneration = 3,
    int activePresetGeneration = 2,
    int modelLayerStyleGeneration = -1,
    int modelLayerPresetGeneration = -1,
    int confirmedStyleGeneration = -1,
    int confirmedPresetGeneration = -1,
    bool useDriver3dVehicleModel = true,
  }) {
    final handoff = handoffFor(
      eligibility: eligibility,
      observationalAssetLoaded: observationalAssetLoaded,
      modelActivationConfirmed: modelActivationConfirmed,
      modelRegistered: modelRegistered,
      layerCreated: layerCreated,
      sourceGeometryValid: sourceGeometryValid,
      modelPoseApplied: modelPoseApplied,
      renderCredibilityConfirmed: renderCredibilityConfirmed,
      activeStyleGeneration: activeStyleGeneration,
      activePresetGeneration: activePresetGeneration,
      modelLayerStyleGeneration: modelLayerStyleGeneration,
      modelLayerPresetGeneration: modelLayerPresetGeneration,
      confirmedStyleGeneration: confirmedStyleGeneration,
      confirmedPresetGeneration: confirmedPresetGeneration,
      useDriver3dVehicleModel: useDriver3dVehicleModel,
      followLiveActive: followLiveActive,
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

  Future<void> pumpHarness(
    WidgetTester tester,
    Nav3dHudRenderDecision decision, {
    bool followLiveActive = true,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DriverHudMountHarness(
            decision: decision,
            followLiveActive: followLiveActive,
          ),
        ),
      ),
    );
    await tester.pump();
  }

  group('NAV-3D-HUD-OWNERSHIP-FINAL-1 handoff render gate', () {
    test('visual-ready 3D + hideHud=true hides HUD and Mapbox 2D taxi', () {
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

      expect(decision.presentation3d, isTrue);
      expect(decision.driver3dVisualReady, isTrue);
      expect(decision.owner, DriverVisualOwner.model3d);
      expect(decision.shouldHideHud, isTrue);
      expect(decision.actualHudVisible, isFalse);
      expect(decision.mapbox2dVisible, isFalse);
      expect(decision.reason, 'model3d_visual_ready');
    });

    test('without activation confirmation HUD stays visible', () {
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

      expect(decision.shouldHideHud, isFalse);
      expect(decision.actualHudVisible, isTrue);
      expect(decision.driver3dVisualReady, isFalse);
      expect(decision.reason, 'hud2d_fallback');
    });

    test('hideHud=false keeps yellow HUD visible only before visual-ready', () {
      final eligibility = dedicated3dEligibility(
        modelRegistered: true,
        layerCreated: true,
        sourceGeometryValid: true,
        modelPoseApplied: false,
        hideHudIsolationFlagEnabled: false,
      );
      final decision = renderDecisionFor(
        eligibility: eligibility,
        hideHudFlagEnabled: false,
        modelRegistered: true,
        layerCreated: true,
        sourceGeometryValid: true,
        modelPoseApplied: false,
      );

      expect(decision.actualHudVisible, isTrue);
      expect(decision.mapbox2dVisible, isFalse);
      expect(decision.reason, 'hide_flag_disabled');
    });

    test('3D not ready => yellow HUD visible', () {
      final eligibility = dedicated3dEligibility(
        modelRegistered: false,
        layerCreated: false,
        assetLoaded: false,
      );
      final decision = renderDecisionFor(
        eligibility: eligibility,
      );

      expect(decision.driver3dVisualReady, isFalse);
      expect(decision.actualHudVisible, isTrue);
      expect(decision.owner, DriverVisualOwner.hud2d);
      expect(decision.mapbox2dVisible, isFalse);
      expect(decision.reason, 'hud2d_fallback');
    });

    test('preset swap before layer generation match => yellow HUD visible', () {
      final eligibility = dedicated3dEligibility(
        modelRegistered: true,
        layerCreated: true,
        sourceGeometryValid: true,
        modelPoseApplied: true,
        activeStyleGeneration: 4,
        activePresetGeneration: 2,
        modelLayerStyleGeneration: 3,
        modelLayerPresetGeneration: 1,
      );
      final decision = renderDecisionFor(
        eligibility: eligibility,
        modelRegistered: true,
        layerCreated: true,
        sourceGeometryValid: true,
        modelPoseApplied: true,
        activeStyleGeneration: 4,
        activePresetGeneration: 2,
        modelLayerStyleGeneration: 3,
        modelLayerPresetGeneration: 1,
      );

      expect(decision.driver3dVisualReady, isFalse);
      expect(decision.actualHudVisible, isTrue);
      expect(decision.reason, 'hud2d_fallback');
    });

    test('new preset generation matched => yellow HUD hidden again', () {
      final decision = renderDecisionFor(
        eligibility: dedicated3dEligibility(
          modelRegistered: true,
          layerCreated: true,
          sourceGeometryValid: true,
          modelPoseApplied: true,
          modelActivationConfirmed: true,
          renderCredibilityConfirmed: true,
          activeStyleGeneration: 4,
          activePresetGeneration: 2,
          confirmedStyleGeneration: 4,
          confirmedPresetGeneration: 2,
          modelLayerStyleGeneration: 4,
          modelLayerPresetGeneration: 2,
        ),
        modelRegistered: true,
        layerCreated: true,
        sourceGeometryValid: true,
        modelPoseApplied: true,
        modelActivationConfirmed: true,
        renderCredibilityConfirmed: true,
        activeStyleGeneration: 4,
        activePresetGeneration: 2,
        confirmedStyleGeneration: 4,
        confirmedPresetGeneration: 2,
        modelLayerStyleGeneration: 4,
        modelLayerPresetGeneration: 2,
      );

      expect(decision.actualHudVisible, isFalse);
      expect(decision.reason, 'model3d_visual_ready');
    });

    test('style switch away from 3D => yellow HUD visible', () {
      final eligibility = dedicated3dEligibility(
        modelRegistered: true,
        layerCreated: true,
        sourceGeometryValid: true,
        modelPoseApplied: true,
        modelLayerStyleGeneration: 3,
        modelLayerPresetGeneration: 2,
        activeStyleUri: kDriverMapStyleNavStreetLight,
        cockpitVisualStyle: DriverCockpitMapVisualStyle.light,
      );
      final decision = renderDecisionFor(
        eligibility: eligibility,
        modelRegistered: true,
        layerCreated: true,
        sourceGeometryValid: true,
        modelPoseApplied: true,
        modelLayerStyleGeneration: 3,
        modelLayerPresetGeneration: 2,
      );

      expect(eligibility.eligible, isFalse);
      expect(decision.presentation3d, isFalse);
      expect(decision.shouldHideHud, isFalse);
      expect(decision.actualHudVisible, isTrue);
      expect(decision.reason, 'hud2d_fallback');
    });
  });

  group('NAV-3D-HUD-OWNERSHIP-FINAL-1 widget mount gate', () {
    testWidgets('visual-ready 3D + hideHud=true => yellow HUD widget absent', (
      tester,
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
      await pumpHarness(tester, decision);

      expect(find.byType(NavigationDriverHudOverlay), findsNothing);
      expect(find.bySemanticsLabel('Driver navigation vehicle'), findsNothing);
    });

    testWidgets('hideHud=false before visual-ready => yellow HUD widget present', (
      tester,
    ) async {
      final decision = renderDecisionFor(
        eligibility: dedicated3dEligibility(
          modelRegistered: true,
          layerCreated: true,
          sourceGeometryValid: true,
          modelPoseApplied: false,
          hideHudIsolationFlagEnabled: false,
        ),
        hideHudFlagEnabled: false,
        modelRegistered: true,
        layerCreated: true,
        sourceGeometryValid: true,
        modelPoseApplied: false,
      );
      await pumpHarness(tester, decision);

      expect(find.byType(NavigationDriverHudOverlay), findsOneWidget);
    });

    testWidgets('3D not ready => yellow HUD widget present', (tester) async {
      final decision = renderDecisionFor(
        eligibility: dedicated3dEligibility(modelRegistered: false),
      );
      await pumpHarness(tester, decision);

      expect(find.byType(NavigationDriverHudOverlay), findsOneWidget);
    });

    testWidgets('preset swap before generation match => yellow HUD temporarily visible',
        (tester) async {
      final decision = renderDecisionFor(
        eligibility: dedicated3dEligibility(
          modelRegistered: true,
          layerCreated: true,
          sourceGeometryValid: true,
          modelPoseApplied: true,
          activeStyleGeneration: 5,
          activePresetGeneration: 3,
          modelLayerStyleGeneration: 4,
          modelLayerPresetGeneration: 2,
        ),
        modelRegistered: true,
        layerCreated: true,
        sourceGeometryValid: true,
        modelPoseApplied: true,
        activeStyleGeneration: 5,
        activePresetGeneration: 3,
        modelLayerStyleGeneration: 4,
        modelLayerPresetGeneration: 2,
      );
      await pumpHarness(tester, decision);

      expect(find.byType(NavigationDriverHudOverlay), findsOneWidget);
    });

    testWidgets('new preset generation matched => yellow HUD absent again', (
      tester,
    ) async {
      final decision = renderDecisionFor(
        eligibility: dedicated3dEligibility(
          modelRegistered: true,
          layerCreated: true,
          sourceGeometryValid: true,
          modelPoseApplied: true,
          modelActivationConfirmed: true,
          renderCredibilityConfirmed: true,
          activeStyleGeneration: 5,
          activePresetGeneration: 3,
          confirmedStyleGeneration: 5,
          confirmedPresetGeneration: 3,
          modelLayerStyleGeneration: 5,
          modelLayerPresetGeneration: 3,
        ),
        modelRegistered: true,
        layerCreated: true,
        sourceGeometryValid: true,
        modelPoseApplied: true,
        modelActivationConfirmed: true,
        renderCredibilityConfirmed: true,
        activeStyleGeneration: 5,
        activePresetGeneration: 3,
        confirmedStyleGeneration: 5,
        confirmedPresetGeneration: 3,
        modelLayerStyleGeneration: 5,
        modelLayerPresetGeneration: 3,
      );
      await pumpHarness(tester, decision);

      expect(find.byType(NavigationDriverHudOverlay), findsNothing);
    });

    testWidgets('style switch away from 3D => yellow HUD widget present', (
      tester,
    ) async {
      final decision = renderDecisionFor(
        eligibility: dedicated3dEligibility(
          modelRegistered: true,
          layerCreated: true,
          sourceGeometryValid: true,
          modelPoseApplied: true,
          modelLayerStyleGeneration: 3,
          modelLayerPresetGeneration: 2,
          activeStyleUri: kDriverMapStyleNavStreetLight,
          cockpitVisualStyle: DriverCockpitMapVisualStyle.light,
        ),
        modelRegistered: true,
        layerCreated: true,
        sourceGeometryValid: true,
        modelPoseApplied: true,
        modelLayerStyleGeneration: 3,
        modelLayerPresetGeneration: 2,
      );
      await pumpHarness(tester, decision);

      expect(find.byType(NavigationDriverHudOverlay), findsOneWidget);
    });
  });
}
