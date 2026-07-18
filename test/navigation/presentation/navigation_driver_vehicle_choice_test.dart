import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/navigation/driver_navigation_map_config.dart';
import 'package:fluxidi_tracking/navigation/presentation/navigation_driver_marker_choice.dart';
import 'package:fluxidi_tracking/navigation/presentation/navigation_driver_vehicle_model_layer.dart';
import 'package:fluxidi_tracking/navigation/presentation/navigation_presentation_mode.dart';
import 'package:fluxidi_tracking/navigation/widgets/navigation_driver_phone_map_controls.dart';
import 'package:fluxidi_tracking/navigation/widgets/navigation_driver_vehicle_choice_selector.dart';

Driver3dVehicleEligibility choiceEligibility({
  required DriverVehiclePresentationChoice selectedVehiclePresentation,
  bool modelRegistered = false,
  bool modelPoseApplied = false,
  bool layerCreated = false,
  bool sourceGeometryValid = false,
  bool assetLoaded = true,
  int activeStyleGeneration = 3,
  int activePresetGeneration = 2,
  int modelLayerStyleGeneration = -1,
  int modelLayerPresetGeneration = -1,
  bool sessionFallback2d = false,
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
    hideHudIsolationFlagEnabled: true,
    layerCreated: layerCreated,
    sourceGeometryValid: sourceGeometryValid,
    assetLoaded: assetLoaded,
    activeStyleGeneration: activeStyleGeneration,
    activePresetGeneration: activePresetGeneration,
    modelLayerStyleGeneration: modelLayerStyleGeneration,
    modelLayerPresetGeneration: modelLayerPresetGeneration,
    followLiveActive: true,
    useDriver3dVehicleModel: true,
    selectedVehiclePresentation: selectedVehiclePresentation,
  );
}

DriverVisualOwnership ownershipFor({
  required DriverVehiclePresentationChoice selectedVehiclePresentation,
  bool followLiveActive = true,
  bool showDriverHudOverlay = true,
  bool hideHudFlagEnabled = true,
  bool driver3dVisualReady = false,
  bool sessionFallback2d = false,
  bool presentation3dIntentActive = false,
}) {
  return resolveDriverVisualOwnership(
    followLiveActive: followLiveActive,
    showDriverHudOverlay: showDriverHudOverlay,
    hideHudFlagEnabled: hideHudFlagEnabled,
    driver3dVisualReady: driver3dVisualReady,
    explicit2dFallback: sessionFallback2d,
    selectedVehiclePresentation: selectedVehiclePresentation,
    runtimeFallbackState: resolveDriverVehicleRuntimeFallbackState(
      selectedVehiclePresentation: selectedVehiclePresentation,
      sessionFallback2d: sessionFallback2d,
    ),
    presentation3dIntentActive: presentation3dIntentActive,
  );
}

void main() {
  group('NAV-3D-VEHICLE-CHOICE-3WAY-1 state model', () {
    test('default selection for a new session is the 2D taxi', () {
      expect(
        kDriverVehiclePresentationChoiceDefault,
        DriverVehiclePresentationChoice.taxi2d,
      );
      expect(
        driverVehiclePresentationChoiceIs3d(
          DriverVehiclePresentationChoice.taxi2d,
        ),
        isFalse,
      );
    });

    test('choice <-> preset mapping', () {
      expect(
        driverVehicle3dPresetForPresentationChoice(
          DriverVehiclePresentationChoice.taxi2d,
        ),
        isNull,
      );
      expect(
        driverVehicle3dPresetForPresentationChoice(
          DriverVehiclePresentationChoice.fluxidi3d,
        ),
        DriverVehicle3dPreset.fluxidiTaxi,
      );
      expect(
        driverVehicle3dPresetForPresentationChoice(
          DriverVehiclePresentationChoice.classic3d,
        ),
        DriverVehicle3dPreset.classicFlyingTaxi,
      );
      expect(
        driverVehiclePresentationChoiceFor3dPreset(
          DriverVehicle3dPreset.fluxidiTaxi,
        ),
        DriverVehiclePresentationChoice.fluxidi3d,
      );
      expect(
        driverVehiclePresentationChoiceFor3dPreset(
          DriverVehicle3dPreset.classicFlyingTaxi,
        ),
        DriverVehiclePresentationChoice.classic3d,
      );
    });

    test('runtime fallback state is separate from the selected choice', () {
      // A 2D selection is never a "fallback".
      expect(
        resolveDriverVehicleRuntimeFallbackState(
          selectedVehiclePresentation: DriverVehiclePresentationChoice.taxi2d,
          sessionFallback2d: true,
        ),
        DriverVehicleRuntimeFallbackState.none,
      );
      // A failing 3D selection produces a temporary fallback only.
      expect(
        resolveDriverVehicleRuntimeFallbackState(
          selectedVehiclePresentation:
              DriverVehiclePresentationChoice.fluxidi3d,
          sessionFallback2d: true,
        ),
        DriverVehicleRuntimeFallbackState.temporary2dFallback,
      );
      expect(
        resolveDriverVehicleRuntimeFallbackState(
          selectedVehiclePresentation:
              DriverVehiclePresentationChoice.classic3d,
          sessionFallback2d: false,
        ),
        DriverVehicleRuntimeFallbackState.none,
      );
    });
  });

  group('NAV-3D-VEHICLE-CHOICE-3WAY-1 state transitions', () {
    test('1. enter 3D map => default taxi2d => exactly one 2D taxi', () {
      final eligibility = choiceEligibility(
        selectedVehiclePresentation: kDriverVehiclePresentationChoiceDefault,
      );
      expect(eligibility.eligible, isFalse);
      expect(eligibility.reason, 'vehicle_choice_2d');
      expect(eligibility.allowModelLayer, isFalse);
      expect(eligibility.driver3dVisualReady, isFalse);
      // Normal 2D behavior: Mapbox marker is not force-hidden by 3D intent.
      expect(eligibility.mapbox2dTaxiHidden, isFalse);

      final ownership = ownershipFor(
        selectedVehiclePresentation: kDriverVehiclePresentationChoiceDefault,
      );
      expect(ownership.owner, DriverVisualOwner.hud2d);
      expect(ownership.reason, 'selected_taxi2d');
      expect(ownership.visibleDriverVisualCount, 1);
    });

    test('2. tap Fluxidi => 2D stays until activation confirmed', () {
      // Immediately after the tap the model is not registered yet.
      final activating = choiceEligibility(
        selectedVehiclePresentation: DriverVehiclePresentationChoice.fluxidi3d,
      );
      expect(activating.eligible, isTrue);
      expect(activating.allowModelLayer, isTrue);
      // NAV-3D-ACTIVATION-BINDING-JANK-1: selection alone must not hide 2D.
      expect(activating.mapbox2dTaxiHidden, isFalse);
      expect(activating.driver3dVisualReady, isFalse);

      final whileActivating = ownershipFor(
        selectedVehiclePresentation: DriverVehiclePresentationChoice.fluxidi3d,
        driver3dVisualReady: false,
        presentation3dIntentActive: true,
      );
      expect(whileActivating.owner, DriverVisualOwner.hud2d);
      expect(whileActivating.hudMounted, isTrue);
      expect(whileActivating.mapbox2dVisible, isFalse);
      expect(whileActivating.reason, 'hud2d_fallback');
      expect(whileActivating.visibleDriverVisualCount, 1);

      // Without 3D intent (e.g. non-3D style), the fallback owner holds.
      final withoutIntent = ownershipFor(
        selectedVehiclePresentation: DriverVehiclePresentationChoice.fluxidi3d,
        driver3dVisualReady: false,
      );
      expect(withoutIntent.owner, DriverVisualOwner.hud2d);
      expect(withoutIntent.visibleDriverVisualCount, 1);

      // Activation confirmed: Fluxidi 3D is the sole owner.
      final ready = ownershipFor(
        selectedVehiclePresentation: DriverVehiclePresentationChoice.fluxidi3d,
        driver3dVisualReady: true,
      );
      expect(ready.owner, DriverVisualOwner.model3d);
      expect(ready.hudMounted, isFalse);
      expect(ready.mapbox2dVisible, isFalse);
      expect(ready.visibleDriverVisualCount, 1);
    });

    test('3. tap Classic => Fluxidi replaced, Classic becomes sole owner', () {
      // Preset generation mismatch while the Classic model rebinds.
      final duringSwap = choiceEligibility(
        selectedVehiclePresentation: DriverVehiclePresentationChoice.classic3d,
        modelRegistered: true,
        layerCreated: true,
        sourceGeometryValid: true,
        modelPoseApplied: true,
        activePresetGeneration: 3,
        modelLayerStyleGeneration: 3,
        modelLayerPresetGeneration: 2,
      );
      expect(duringSwap.driver3dVisualReady, isFalse);

      // Classic bound + activation confirmed at the new generation.
      final afterSwap = choiceEligibility(
        selectedVehiclePresentation: DriverVehiclePresentationChoice.classic3d,
        modelRegistered: true,
        layerCreated: true,
        sourceGeometryValid: true,
        modelPoseApplied: true,
        activePresetGeneration: 3,
        modelLayerStyleGeneration: 3,
        modelLayerPresetGeneration: 3,
      );
      // Without activation confirmation, visual-ready stays false.
      expect(afterSwap.driver3dVisualReady, isFalse);

      final ownership = ownershipFor(
        selectedVehiclePresentation: DriverVehiclePresentationChoice.classic3d,
        driver3dVisualReady: true,
      );
      expect(ownership.owner, DriverVisualOwner.model3d);
      expect(ownership.visibleDriverVisualCount, 1);
    });

    test('4. tap 2D => 3D torn down => exactly one 2D taxi', () {
      final eligibility = choiceEligibility(
        selectedVehiclePresentation: DriverVehiclePresentationChoice.taxi2d,
        modelRegistered: true,
        layerCreated: true,
        sourceGeometryValid: true,
        modelPoseApplied: true,
        modelLayerStyleGeneration: 3,
        modelLayerPresetGeneration: 2,
      );
      // The 2D choice wins even while the model layer still reports bound.
      expect(eligibility.eligible, isFalse);
      expect(eligibility.reason, 'vehicle_choice_2d');
      expect(eligibility.driver3dVisualReady, isFalse);
      expect(eligibility.mapbox2dTaxiHidden, isFalse);

      final ownership = ownershipFor(
        selectedVehiclePresentation: DriverVehiclePresentationChoice.taxi2d,
      );
      expect(ownership.owner, DriverVisualOwner.hud2d);
      expect(ownership.visibleDriverVisualCount, 1);
    });

    test('5. zoom in/out does not change ownership', () {
      // Ownership scope has no camera/zoom inputs: identical scope inputs
      // must resolve identically on every evaluation.
      final owners = List.generate(
        3,
        (_) => resolveDriverVisualOwnerForChoice(
          followLiveActive: true,
          selectedVehiclePresentation:
              DriverVehiclePresentationChoice.fluxidi3d,
          runtimeFallbackState: DriverVehicleRuntimeFallbackState.none,
          hudEnabled: true,
          driver3dVisualReady: true,
          hideHudFlagEnabled: true,
        ),
      );
      expect(owners.toSet(), {DriverVisualOwner.model3d});
    });

    test('6. 3D failure => temporary fallback, choice remembered', () {
      const choice = DriverVehiclePresentationChoice.fluxidi3d;
      final fallbackState = resolveDriverVehicleRuntimeFallbackState(
        selectedVehiclePresentation: choice,
        sessionFallback2d: true,
      );
      expect(
        fallbackState,
        DriverVehicleRuntimeFallbackState.temporary2dFallback,
      );

      final ownership = ownershipFor(
        selectedVehiclePresentation: choice,
        sessionFallback2d: true,
      );
      expect(ownership.owner, DriverVisualOwner.hud2d);
      expect(ownership.reason, 'temporary_2d_fallback');
      expect(ownership.visibleDriverVisualCount, 1);
      // The fallback never mutates the selected choice: the same choice
      // input still resolves back to 3D once the fallback clears.
      expect(driverVehiclePresentationChoiceIs3d(choice), isTrue);
    });

    test('7. 3D recovery => fallback removed, selected model returns', () {
      final recovered = ownershipFor(
        selectedVehiclePresentation: DriverVehiclePresentationChoice.fluxidi3d,
        sessionFallback2d: false,
        driver3dVisualReady: true,
      );
      expect(recovered.owner, DriverVisualOwner.model3d);
      expect(recovered.hudMounted, isFalse);
      expect(recovered.visibleDriverVisualCount, 1);
    });

    test('8. style switch away from 3D => normal 2D behavior', () {
      final eligibility = choiceEligibility(
        selectedVehiclePresentation: DriverVehiclePresentationChoice.fluxidi3d,
        activeStyleUri: kDriverMapStyleNavStreetLight,
        cockpitVisualStyle: DriverCockpitMapVisualStyle.light,
      );
      expect(eligibility.eligible, isFalse);
      expect(eligibility.driver3dVisualReady, isFalse);

      final ownership = ownershipFor(
        selectedVehiclePresentation: DriverVehiclePresentationChoice.fluxidi3d,
        driver3dVisualReady: false,
      );
      expect(ownership.owner, DriverVisualOwner.hud2d);
      expect(ownership.visibleDriverVisualCount, 1);
    });

    test('9. new session default follows the session rule (taxi2d)', () {
      // Session reset re-applies the default; the default itself never
      // auto-selects a 3D model.
      expect(
        kDriverVehiclePresentationChoiceDefault,
        DriverVehiclePresentationChoice.taxi2d,
      );
      final ownership = ownershipFor(
        selectedVehiclePresentation: kDriverVehiclePresentationChoiceDefault,
      );
      expect(ownership.owner, isNot(DriverVisualOwner.model3d));
      expect(ownership.visibleDriverVisualCount, 1);
    });

    test('10. visibleDriverVisualCount == 1 at every state', () {
      for (final choice in DriverVehiclePresentationChoice.values) {
        for (final sessionFallback2d in [false, true]) {
          for (final ready in [false, true]) {
            for (final hudEnabled in [false, true]) {
              final ownership = ownershipFor(
                selectedVehiclePresentation: choice,
                sessionFallback2d: sessionFallback2d,
                driver3dVisualReady: ready,
                showDriverHudOverlay: hudEnabled,
              );
              expect(
                ownership.visibleDriverVisualCount,
                1,
                reason:
                    'choice=$choice fallback=$sessionFallback2d '
                    'ready=$ready hud=$hudEnabled',
              );
            }
          }
        }
      }
      // Outside live follow navigation there is no owner at all.
      final idle = ownershipFor(
        selectedVehiclePresentation: DriverVehiclePresentationChoice.fluxidi3d,
        followLiveActive: false,
        driver3dVisualReady: true,
      );
      expect(idle.owner, DriverVisualOwner.none);
      expect(idle.visibleDriverVisualCount, 0);
    });

    test('2D choice removes 3D presentation intent for the Mapbox marker', () {
      bool intentFor(DriverVehiclePresentationChoice choice) {
        return resolveNav3dPresentation3dIntent(
          vehicleModelFlagEnabled: true,
          cockpitSceneEnabled: true,
          useDriverCockpitCamera: true,
          presentationMode: NavigationPresentationMode.driver,
          liveNavigationActive: true,
          followCamera: true,
          cockpitSceneActive: true,
          sessionFallback2d: false,
          cockpitVisualStyle: DriverCockpitMapVisualStyle.standard3d,
          activeStyleUri: kDriverMapStyleStandard,
          selectedVehiclePresentation: choice,
        );
      }

      expect(intentFor(DriverVehiclePresentationChoice.taxi2d), isFalse);
      expect(intentFor(DriverVehiclePresentationChoice.fluxidi3d), isTrue);
      expect(intentFor(DriverVehiclePresentationChoice.classic3d), isTrue);
    });
  });

  group('NAV-VEHICLE-MODE-CAR-ARROW-1 tablet marker selector', () {
    testWidgets('renders exactly Auto and Pijl (no Fluxidi/Classic)', (
      WidgetTester tester,
    ) async {
      DriverNavigationMarkerChoice? tapped;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            backgroundColor: Colors.black,
            body: Center(
              child: NavigationDriverMarkerChoiceSelector(
                selectedChoice: DriverNavigationMarkerChoice.car,
                onSelected: (choice) => tapped = choice,
                accentColor: const Color(0xFFD4AF37),
                textColor: Colors.white,
                surfaceColor: const Color(0xFF14171C),
                language: AppLanguage.nl,
              ),
            ),
          ),
        ),
      );

      expect(find.text('Auto'), findsOneWidget);
      expect(find.text('Pijl'), findsOneWidget);
      expect(find.text('Fluxidi'), findsNothing);
      expect(find.text('Classic'), findsNothing);
      expect(find.text('2D'), findsNothing);

      await tester.tap(find.text('Pijl'));
      expect(tapped, DriverNavigationMarkerChoice.arrow);

      await tester.tap(find.text('Auto'));
      expect(tapped, DriverNavigationMarkerChoice.car);
    });

    testWidgets('buttons are large enough for driving use', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: NavigationDriverMarkerChoiceSelector(
                selectedChoice: DriverNavigationMarkerChoice.arrow,
                onSelected: (_) {},
                accentColor: const Color(0xFFD4AF37),
                textColor: Colors.white,
                surfaceColor: const Color(0xFF14171C),
                language: AppLanguage.nl,
              ),
            ),
          ),
        ),
      );

      final arrowSize = tester.getSize(
        find.ancestor(
          of: find.text('Pijl'),
          matching: find.byType(AnimatedContainer),
        ),
      );
      expect(arrowSize.height, greaterThanOrEqualTo(44));
      expect(arrowSize.width, greaterThanOrEqualTo(64));
    });
  });

  group('NAV-VEHICLE-MODE-CAR-ARROW-1 phone compact marker icon', () {
    testWidgets('compact icon opens popup with exactly Auto and Pijl', (
      WidgetTester tester,
    ) async {
      DriverNavigationMarkerChoice? selected;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: NavigationDriverMarkerCompactButton(
                selectedChoice: DriverNavigationMarkerChoice.car,
                onSelected: (choice) => selected = choice,
                accentColor: const Color(0xFFD4AF37),
                textColor: Colors.white,
                surfaceColor: const Color(0xFF14171C),
                language: AppLanguage.nl,
              ),
            ),
          ),
        ),
      );

      // No permanent marker text on the map — only the compact icon.
      expect(find.text('Auto'), findsNothing);
      expect(find.text('Pijl'), findsNothing);
      expect(find.text('Fluxidi'), findsNothing);
      expect(find.text('Classic'), findsNothing);
      expect(find.byIcon(Icons.local_taxi), findsOneWidget);

      await tester.tap(find.byIcon(Icons.local_taxi));
      await tester.pumpAndSettle();
      expect(find.text('Auto'), findsOneWidget);
      expect(find.text('Pijl'), findsOneWidget);
      expect(find.text('Fluxidi'), findsNothing);
      expect(find.text('Classic'), findsNothing);

      await tester.tap(find.text('Pijl'));
      await tester.pumpAndSettle();
      expect(selected, DriverNavigationMarkerChoice.arrow);
    });
  });
}
