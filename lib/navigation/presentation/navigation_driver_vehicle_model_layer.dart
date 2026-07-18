import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'package:flutter/services.dart';

import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mb;

import '../driver_navigation_map_config.dart';
import 'navigation_presentation_flags.dart';
import 'navigation_presentation_mode.dart';

/// Registered style model id for the bundled taxi GLB (legacy alias).

const String kDriverVehicleModelId = 'fluxidi-driver-taxi-3d';

/// NAV-ASSET-3D-SWAP-1: unique Mapbox style model id per vehicle preset.

const String kDriverVehicleFluxidiTaxiStyleModelId =
    'fluxidi_vehicle_fluxidi_taxi_v1';

const String kDriverVehicleClassicFlyingTaxiStyleModelId =
    'fluxidi_vehicle_classic_v1';

/// GeoJSON source id anchoring the model position.

const String kDriverVehicleModelSourceId = 'fluxidi-driver-vehicle-source';

/// Model layer id rendered on the map.

const String kDriverVehicleModelLayerId = 'fluxidi-driver-vehicle-model';

/// NAV-PRES-3K-F: dedicated GeoJSON source for the style-layer debug dot.

const String kDriverVehicleDebugStyleDotSourceId =
    'fluxidi-driver-vehicle-debug-dot-source';

/// NAV-PRES-3K-F: CircleLayer id for the style-layer debug dot.

const String kDriverVehicleDebugStyleDotLayerId =
    'fluxidi-driver-vehicle-debug-dot';

/// Local bundled GLB referenced via Mapbox asset URI scheme.

const String kDriverVehicleModelAssetUri =
    'asset://assets/navigation/driver_taxi_3d.glb';

/// NAV-PRES-3K-J: bundled classic flying taxi GLB (test asset).

const String kDriverVehicleClassicFlyingTaxiAssetUri =
    'asset://assets/navigation/vehicles/classic_flying_taxi.glb';

/// NAV-PRES-3K-J: selectable 3D vehicle presets for cockpit navigation.

enum DriverVehicle3dPreset { fluxidiTaxi, classicFlyingTaxi }

/// NAV-PRES-3K-J: default product preset.

const DriverVehicle3dPreset kDriverVehicle3dPresetDefault =
    DriverVehicle3dPreset.fluxidiTaxi;

/// NAV-3D-VEHICLE-CHOICE-3WAY-1: first-class driver vehicle presentation
/// choice inside the 3D map. This is an explicit user selection, not a
/// fallback state.
enum DriverVehiclePresentationChoice { taxi2d, fluxidi3d, classic3d }

/// NAV-3D-VEHICLE-CHOICE-3WAY-1: default choice for a new navigation session.
const DriverVehiclePresentationChoice kDriverVehiclePresentationChoiceDefault =
    DriverVehiclePresentationChoice.taxi2d;

/// NAV-3D-VEHICLE-CHOICE-3WAY-1: runtime-only fallback while a selected 3D
/// model fails to become usable. Never mutates the user's selected choice.
enum DriverVehicleRuntimeFallbackState { none, temporary2dFallback }

bool driverVehiclePresentationChoiceIs3d(
  DriverVehiclePresentationChoice choice,
) {
  return choice != DriverVehiclePresentationChoice.taxi2d;
}

/// Maps a 3D presentation choice to its model preset (`null` for 2D taxi).
DriverVehicle3dPreset? driverVehicle3dPresetForPresentationChoice(
  DriverVehiclePresentationChoice choice,
) {
  switch (choice) {
    case DriverVehiclePresentationChoice.taxi2d:
      return null;
    case DriverVehiclePresentationChoice.fluxidi3d:
      return DriverVehicle3dPreset.fluxidiTaxi;
    case DriverVehiclePresentationChoice.classic3d:
      return DriverVehicle3dPreset.classicFlyingTaxi;
  }
}

DriverVehiclePresentationChoice driverVehiclePresentationChoiceFor3dPreset(
  DriverVehicle3dPreset preset,
) {
  switch (preset) {
    case DriverVehicle3dPreset.fluxidiTaxi:
      return DriverVehiclePresentationChoice.fluxidi3d;
    case DriverVehicle3dPreset.classicFlyingTaxi:
      return DriverVehiclePresentationChoice.classic3d;
  }
}

String driverVehiclePresentationChoiceLabel(
  DriverVehiclePresentationChoice choice,
) {
  switch (choice) {
    case DriverVehiclePresentationChoice.taxi2d:
      return '2D taxi';
    case DriverVehiclePresentationChoice.fluxidi3d:
      return 'Fluxidi taxi';
    case DriverVehiclePresentationChoice.classic3d:
      return 'Classic taxi';
  }
}

String driverVehiclePresentationChoiceLogLabel(
  DriverVehiclePresentationChoice choice,
) {
  switch (choice) {
    case DriverVehiclePresentationChoice.taxi2d:
      return 'taxi2d';
    case DriverVehiclePresentationChoice.fluxidi3d:
      return 'fluxidi3d';
    case DriverVehiclePresentationChoice.classic3d:
      return 'classic3d';
  }
}

String? _lastNav3dVehicleSwitchLogSignature;

/// NAV-3D-INSTANT-SWITCH-SCALE-AND-HEADING-POLISH-1: bounded diagnostics for
/// every explicit vehicle presentation switch.
void logNav3dVehicleSwitch({
  required DriverVehiclePresentationChoice from,
  required DriverVehiclePresentationChoice to,
  required String ownerBefore,
  required String ownerAfter,
  required bool rebuildTriggered,
  required bool modelEnsureStarted,
  required int timestampMs,
}) {
  final signature =
      '${from.name}|${to.name}|$ownerBefore|$ownerAfter|'
      '$rebuildTriggered|$modelEnsureStarted';
  if (signature == _lastNav3dVehicleSwitchLogSignature) return;
  _lastNav3dVehicleSwitchLogSignature = signature;
  debugPrint(
    '[NAV_3D_VEHICLE_SWITCH] '
    'from=${driverVehiclePresentationChoiceLogLabel(from)} '
    'to=${driverVehiclePresentationChoiceLogLabel(to)} '
    'ownerBefore=$ownerBefore '
    'ownerAfter=$ownerAfter '
    'rebuildTriggered=$rebuildTriggered '
    'modelEnsureStarted=$modelEnsureStarted '
    'timestampMs=$timestampMs',
  );
}

/// NAV-3D-VEHICLE-CHOICE-3WAY-1: temporary fallback only exists while a
/// selected 3D model genuinely failed to become usable this session.
DriverVehicleRuntimeFallbackState resolveDriverVehicleRuntimeFallbackState({
  required DriverVehiclePresentationChoice selectedVehiclePresentation,
  required bool sessionFallback2d,
}) {
  if (!driverVehiclePresentationChoiceIs3d(selectedVehiclePresentation)) {
    return DriverVehicleRuntimeFallbackState.none;
  }
  return sessionFallback2d
      ? DriverVehicleRuntimeFallbackState.temporary2dFallback
      : DriverVehicleRuntimeFallbackState.none;
}

/// NAV-PRES-3K-J: metadata for a selectable 3D vehicle preset.

class DriverVehicle3dModelSpec {
  const DriverVehicle3dModelSpec({
    required this.preset,

    required this.label,

    required this.assetUri,

    required this.scaleMultiplier,

    required this.headingOffsetDeg,

    required this.altitudeMeters,
  });

  final DriverVehicle3dPreset preset;

  final String label;

  final String assetUri;

  final double scaleMultiplier;

  final double headingOffsetDeg;

  final double altitudeMeters;
}

String driverVehicle3dPresetLogLabel(DriverVehicle3dPreset preset) {
  switch (preset) {
    case DriverVehicle3dPreset.fluxidiTaxi:
      return 'fluxidi_taxi';

    case DriverVehicle3dPreset.classicFlyingTaxi:
      return 'classic_flying_taxi';
  }
}

DriverVehicle3dModelSpec resolveDriverVehicle3dModelSpec(
  DriverVehicle3dPreset preset,
) {
  switch (preset) {
    case DriverVehicle3dPreset.fluxidiTaxi:
      return const DriverVehicle3dModelSpec(
        preset: DriverVehicle3dPreset.fluxidiTaxi,

        label: 'Fluxidi taxi',

        assetUri: kDriverVehicleModelAssetUri,

        scaleMultiplier: 1.0,

        headingOffsetDeg: 0.0,

        altitudeMeters: 0.2,
      );

    case DriverVehicle3dPreset.classicFlyingTaxi:
      return const DriverVehicle3dModelSpec(
        preset: DriverVehicle3dPreset.classicFlyingTaxi,

        label: 'Classic taxi',

        assetUri: kDriverVehicleClassicFlyingTaxiAssetUri,

        scaleMultiplier: 1.0,

        headingOffsetDeg: 180.0,

        altitudeMeters: 0.2,
      );
  }
}

/// NAV-ASSET-3D-MODE-GATE-1: authoritative 3D vehicle eligibility snapshot.

class Driver3dVehicleEligibility {
  const Driver3dVehicleEligibility({
    required this.eligible,
    required this.reason,
    required this.presentation,
    required this.styleFamily,
    required this.modelReady,
    required this.fallback2d,
    required this.selectorVisible,
    required this.hudTaxiHidden,
    required this.mapbox2dTaxiHidden,
    required this.allowModelLayer,
    required this.allowMovementSync,
    required this.layerCreated,
    required this.sourceGeometryValid,
    required this.modelPoseApplied,
    required this.modelActivationConfirmed,
    required this.hudFallbackAllowedToHide,
    required this.effectivelyActive,
    required this.driver3dVisualReady,
  });

  /// Dedicated 3D navigation presentation allows the 3D vehicle feature.
  final bool eligible;

  /// Bounded ineligibility token (or `eligible` when [eligible] is true).
  final String reason;

  final String presentation;
  final String styleFamily;

  /// Confirmed 3D handoff: all activation gates satisfied.
  final bool modelReady;

  final bool fallback2d;
  final bool selectorVisible;
  final bool hudTaxiHidden;
  final bool mapbox2dTaxiHidden;
  final bool allowModelLayer;
  final bool allowMovementSync;

  /// NAV-3D-VEHICLE-VISIBILITY-FAILSAFE-1: explicit activation snapshot fields.
  final bool layerCreated;
  final bool sourceGeometryValid;
  final bool modelPoseApplied;
  final bool modelActivationConfirmed;
  final bool hudFallbackAllowedToHide;
  final bool effectivelyActive;

  /// NAV-3D-HUD-OWNERSHIP-FINAL-1: concrete render-ready without activation
  /// confirmation readback.
  final bool driver3dVisualReady;
}

/// NAV-3D-HUD-OWNERSHIP-FINAL-1: scoped sole owner of the driver vehicle visual.
enum DriverVisualOwner {
  none,
  hud2d,
  mapbox2d,
  model3d,
}

/// NAV-3D-P0-PERSISTENT-VEHICLE-OWNERSHIP-1: which production renderer may write
/// the visible vehicle. Exactly one kind may be active at a time.
enum DriverVehicleRendererKind {
  none,
  native3d,
  model3d,
  hud2d,
  mapbox2d,
}

/// NAV-3D-P0: Native FollowPuck's LocationPuck3D uses the Mapbox location
/// component — never disable it while native follow owns the vehicle.
bool resolveShouldHideMapboxUserLocationPuck({
  required bool nativeFollowActive,
  required bool routePreviewOrNav,
  required bool hasActiveTaxiMarker,
  required bool followLiveActive,
}) {
  if (nativeFollowActive) return false;
  if (routePreviewOrNav) return true;
  if (hasActiveTaxiMarker) return true;
  return followLiveActive;
}

/// NAV-3D-P0: resolve the single production vehicle renderer for diagnostics
/// and mutual-exclusion checks.
DriverVehicleRendererKind resolveDriverVehicleRendererKind({
  required bool nativeFollowActive,
  required DriverVehiclePresentationChoice requestedChoice,
  required DriverVisualOwner owner,
  required bool modelLayerWritingPoses,
}) {
  if (!driverVehiclePresentationChoiceIs3d(requestedChoice)) {
    if (owner == DriverVisualOwner.mapbox2d) {
      return DriverVehicleRendererKind.mapbox2d;
    }
    if (owner == DriverVisualOwner.hud2d) {
      return DriverVehicleRendererKind.hud2d;
    }
    return DriverVehicleRendererKind.none;
  }
  if (nativeFollowActive) return DriverVehicleRendererKind.native3d;
  if (owner == DriverVisualOwner.model3d || modelLayerWritingPoses) {
    return DriverVehicleRendererKind.model3d;
  }
  if (owner == DriverVisualOwner.hud2d) return DriverVehicleRendererKind.hud2d;
  if (owner == DriverVisualOwner.mapbox2d) {
    return DriverVehicleRendererKind.mapbox2d;
  }
  return DriverVehicleRendererKind.none;
}

/// NAV-3D-P0: Native FollowPuck and Dart ModelLayer must never both write.
bool resolveDriverVehicleRenderersMutuallyExclusive({
  required bool nativeFollowActive,
  required bool modelLayerWritingPoses,
}) {
  return !(nativeFollowActive && modelLayerWritingPoses);
}

/// NAV-3D-P0: ordinary GPS / route-progress / camera updates must not flip a
/// confirmed 3D owner back to HUD while the requested choice remains 3D.
bool resolveNav3dOwnershipSurvivesOrdinaryUpdate({
  required DriverVehiclePresentationChoice requestedChoice,
  required DriverVisualOwner ownerBefore,
  required DriverVisualOwner ownerAfter,
  required String eligibilityReason,
  required bool activationConfirmed,
}) {
  if (!driverVehiclePresentationChoiceIs3d(requestedChoice)) return false;
  if (eligibilityReason == 'vehicle_choice_2d') return false;
  if (!activationConfirmed) return false;
  if (ownerBefore != DriverVisualOwner.model3d) return false;
  return ownerAfter == DriverVisualOwner.model3d;
}

/// NAV-3D-P0: native visual-ready must not be derived from requestedChoice alone.
///
/// Requires coherent runtime readiness. Style compatibility/readiness is applied
/// separately via eligibility (`nativeOwns = this && eligible`).
bool resolveNative3dRendererCrediblyActive({
  required bool requested3d,
  required bool nativeFollowSessionActive,
  required bool nativePresetConfigureAcknowledged,
  required bool nativeCommandGenerationCurrent,
  required bool navigationStoppingOrDisposing,
  bool locationComponentEnabledForNative = true,
}) {
  if (!requested3d) return false;
  if (navigationStoppingOrDisposing) return false;
  if (!nativeFollowSessionActive) return false;
  if (!nativePresetConfigureAcknowledged) return false;
  if (!nativeCommandGenerationCurrent) return false;
  if (!locationComponentEnabledForNative) return false;
  return true;
}

/// NAV-3D-HUD-OWNERSHIP-FINAL-1: authoritative 3D visual-ready signal.
///
/// True when the ModelLayer has valid geometry and a successfully written first
/// pose for the active style/preset generation. Does not wait for
/// [modelActivationConfirmed] or [renderCredibilityConfirmed].
///
/// NAV-3D-P0-PERSISTENT-VEHICLE-OWNERSHIP-1: when [native3dRendererActive] is
/// true, Native FollowPuck's LocationPuck3D owns the vehicle and ModelLayer
/// pose/registration gates are not required.
bool resolveDriver3dVisualReady({
  required bool followLiveActive,
  required bool presentation3dActive,
  required bool eligible,
  required bool modelFeatureEnabled,
  required bool modelRegistered,
  required bool layerCreated,
  required bool sourceGeometryValid,
  required bool modelPoseApplied,
  required int activeStyleGeneration,
  required int activePresetGeneration,
  required int modelLayerStyleGeneration,
  required int modelLayerPresetGeneration,
  required bool explicit2dFallback,
  bool debugRenderProbeActive = false,
  bool native3dRendererActive = false,
}) {
  if (debugRenderProbeActive) return false;
  if (!followLiveActive) return false;
  if (!presentation3dActive) return false;
  if (!eligible) return false;
  if (!modelFeatureEnabled) return false;
  if (explicit2dFallback) return false;
  if (native3dRendererActive) return true;
  if (!modelRegistered ||
      !layerCreated ||
      !sourceGeometryValid ||
      !modelPoseApplied) {
    return false;
  }
  if (modelLayerStyleGeneration < 0 || modelLayerPresetGeneration < 0) {
    return false;
  }
  return activeStyleGeneration == modelLayerStyleGeneration &&
      activePresetGeneration == modelLayerPresetGeneration;
}

/// NAV-3D-VEHICLE-CHOICE-3WAY-1: single scoped visual owner resolver keyed on
/// the explicit vehicle presentation choice plus the runtime fallback state.
///
/// NAV-3D-INSTANT-SWITCH-SCALE-AND-HEADING-POLISH-1:
/// [immediateModel3dOnSelection] makes an explicit 3D selection own the
/// driver visual in the same interaction (both 2D visuals suppressed at
/// once) instead of waiting for [driver3dVisualReady]. If the selected model
/// then fails within the bounded activation lifecycle, the temporary 2D
/// fallback restores a 2D owner.
DriverVisualOwner resolveDriverVisualOwnerForChoice({
  required bool followLiveActive,
  required DriverVehiclePresentationChoice selectedVehiclePresentation,
  required DriverVehicleRuntimeFallbackState runtimeFallbackState,
  required bool hudEnabled,
  required bool driver3dVisualReady,
  required bool hideHudFlagEnabled,
  bool immediateModel3dOnSelection = false,
}) {
  if (!followLiveActive) return DriverVisualOwner.none;
  final fallbackOwner = hudEnabled
      ? DriverVisualOwner.hud2d
      : DriverVisualOwner.mapbox2d;
  if (runtimeFallbackState ==
      DriverVehicleRuntimeFallbackState.temporary2dFallback) {
    return fallbackOwner;
  }
  switch (selectedVehiclePresentation) {
    case DriverVehiclePresentationChoice.taxi2d:
      return fallbackOwner;
    case DriverVehiclePresentationChoice.fluxidi3d:
    case DriverVehiclePresentationChoice.classic3d:
      if (hideHudFlagEnabled &&
          (driver3dVisualReady || immediateModel3dOnSelection)) {
        return DriverVisualOwner.model3d;
      }
      return fallbackOwner;
  }
}

/// NAV-3D-HUD-OWNERSHIP-FINAL-1: single scoped visual owner resolver.
///
/// Legacy entry point that implies an active 3D selection; delegates to
/// [resolveDriverVisualOwnerForChoice].
DriverVisualOwner resolveDriverVisualOwner({
  required bool followLiveActive,
  required bool hudEnabled,
  required bool driver3dVisualReady,
  required bool hideHudFlagEnabled,
}) {
  return resolveDriverVisualOwnerForChoice(
    followLiveActive: followLiveActive,
    selectedVehiclePresentation: DriverVehiclePresentationChoice.fluxidi3d,
    runtimeFallbackState: DriverVehicleRuntimeFallbackState.none,
    hudEnabled: hudEnabled,
    driver3dVisualReady: driver3dVisualReady,
    hideHudFlagEnabled: hideHudFlagEnabled,
  );
}

/// NAV-3D-HUD-OWNERSHIP-FINAL-1: derived final visibility from scoped owner.
class DriverVisualOwnership {
  const DriverVisualOwnership({
    required this.owner,
    required this.driver3dVisualReady,
    required this.hudMounted,
    required this.mapbox2dVisible,
    required this.mapbox2dMarkerOpacity,
    required this.model3dActivePresentation,
    required this.visibleDriverVisualCount,
    required this.reason,
  });

  final DriverVisualOwner owner;
  final bool driver3dVisualReady;
  final bool hudMounted;
  final bool mapbox2dVisible;
  final double mapbox2dMarkerOpacity;
  final bool model3dActivePresentation;
  final int visibleDriverVisualCount;
  final String reason;

  String get diagnosticSignature =>
      '${owner.name}|$driver3dVisualReady|$hudMounted|$mapbox2dVisible|'
      '$mapbox2dMarkerOpacity|$model3dActivePresentation|'
      '$visibleDriverVisualCount|$reason';
}

int resolveVisibleDriverVisualCount({
  required DriverVisualOwner owner,
  required bool followLiveActive,
}) {
  if (!followLiveActive) return 0;
  switch (owner) {
    case DriverVisualOwner.none:
      return 0;
    case DriverVisualOwner.hud2d:
    case DriverVisualOwner.mapbox2d:
    case DriverVisualOwner.model3d:
      return 1;
  }
}

/// NAV-3D-HUD-OWNERSHIP-FINAL-1: authoritative final driver visual ownership.
///
/// NAV-3D-VEHICLE-CHOICE-3WAY-1: [selectedVehiclePresentation] carries the
/// explicit user choice. When omitted (legacy callers) an active 3D selection
/// is implied so ownership still keys off [driver3dVisualReady] alone.
DriverVisualOwnership resolveDriverVisualOwnership({
  required bool followLiveActive,
  required bool showDriverHudOverlay,
  required bool hideHudFlagEnabled,
  required bool driver3dVisualReady,
  required bool explicit2dFallback,
  DriverVehiclePresentationChoice? selectedVehiclePresentation,
  DriverVehicleRuntimeFallbackState? runtimeFallbackState,
  // NAV-3D-INSTANT-SWITCH-SCALE-AND-HEADING-POLISH-1: when the 3D
  // presentation intent is active (eligible 3D style + live follow), an
  // explicit 3D selection owns the visual immediately.
  bool presentation3dIntentActive = false,
}) {
  final choice =
      selectedVehiclePresentation ?? DriverVehiclePresentationChoice.fluxidi3d;
  final fallbackState =
      runtimeFallbackState ??
      resolveDriverVehicleRuntimeFallbackState(
        selectedVehiclePresentation: choice,
        sessionFallback2d: explicit2dFallback,
      );
  final owner = resolveDriverVisualOwnerForChoice(
    followLiveActive: followLiveActive,
    selectedVehiclePresentation: choice,
    runtimeFallbackState: fallbackState,
    hudEnabled: showDriverHudOverlay,
    driver3dVisualReady: driver3dVisualReady,
    hideHudFlagEnabled: hideHudFlagEnabled,
    immediateModel3dOnSelection:
        selectedVehiclePresentation != null && presentation3dIntentActive,
  );
  final hudMounted = followLiveActive && owner == DriverVisualOwner.hud2d;
  final mapbox2dVisible =
      followLiveActive &&
      !explicit2dFallback &&
      owner == DriverVisualOwner.mapbox2d;
  final mapbox2dMarkerOpacity = mapbox2dVisible ? 1.0 : (followLiveActive ? 0.0 : 1.0);
  final model3dActivePresentation =
      followLiveActive && owner == DriverVisualOwner.model3d;
  final visibleDriverVisualCount = resolveVisibleDriverVisualCount(
    owner: owner,
    followLiveActive: followLiveActive,
  );
  final reason = resolveDriverVisualOwnershipReason(
    followLiveActive: followLiveActive,
    showDriverHudOverlay: showDriverHudOverlay,
    hideHudFlagEnabled: hideHudFlagEnabled,
    driver3dVisualReady: driver3dVisualReady,
    explicit2dFallback: explicit2dFallback,
    owner: owner,
    selectedVehiclePresentation: selectedVehiclePresentation,
    runtimeFallbackState: fallbackState,
  );
  return DriverVisualOwnership(
    owner: owner,
    driver3dVisualReady: driver3dVisualReady,
    hudMounted: hudMounted,
    mapbox2dVisible: mapbox2dVisible,
    mapbox2dMarkerOpacity: mapbox2dMarkerOpacity,
    model3dActivePresentation: model3dActivePresentation,
    visibleDriverVisualCount: visibleDriverVisualCount,
    reason: reason,
  );
}

String resolveDriverVisualOwnershipReason({
  required bool followLiveActive,
  required bool showDriverHudOverlay,
  required bool hideHudFlagEnabled,
  required bool driver3dVisualReady,
  required bool explicit2dFallback,
  required DriverVisualOwner owner,
  DriverVehiclePresentationChoice? selectedVehiclePresentation,
  DriverVehicleRuntimeFallbackState runtimeFallbackState =
      DriverVehicleRuntimeFallbackState.none,
}) {
  if (!followLiveActive) return 'not_follow_live';
  // NAV-3D-VEHICLE-CHOICE-3WAY-1: explicit choice-aware reason tokens.
  if (selectedVehiclePresentation != null) {
    if (runtimeFallbackState ==
        DriverVehicleRuntimeFallbackState.temporary2dFallback) {
      return 'temporary_2d_fallback';
    }
    if (selectedVehiclePresentation ==
        DriverVehiclePresentationChoice.taxi2d) {
      return 'selected_taxi2d';
    }
  }
  if (explicit2dFallback) return 'explicit_2d_fallback';
  switch (owner) {
    case DriverVisualOwner.model3d:
      // NAV-3D-INSTANT-SWITCH-SCALE-AND-HEADING-POLISH-1: explicit selection
      // owns the visual immediately, before the first pose confirms.
      if (!driver3dVisualReady) return 'model3d_selected_pending';
      return 'model3d_visual_ready';
    case DriverVisualOwner.hud2d:
      if (!showDriverHudOverlay) return 'hud_overlay_disabled';
      if (!hideHudFlagEnabled) return 'hide_flag_disabled';
      if (driver3dVisualReady) return 'unexpected_hud_with_3d_ready';
      return 'hud2d_fallback';
    case DriverVisualOwner.mapbox2d:
      return 'mapbox2d_owner';
    case DriverVisualOwner.none:
      return 'no_owner';
  }
}

/// NAV-3D-PRESET-ORIENTATION-AND-HUD-HANDOFF-1: confirmed 3D render activation.
bool resolveNav3dVehicleEffectivelyActive({
  required bool eligible,
  required bool assetLoaded,
  required bool modelRegistered,
  required bool layerCreated,
  required bool modelPoseApplied,
  required bool modelActivationConfirmed,
  required bool renderCredibilityConfirmed,
  bool native3dRendererActive = false,
}) {
  if (native3dRendererActive) return eligible;
  return eligible &&
      assetLoaded &&
      modelRegistered &&
      layerCreated &&
      modelPoseApplied &&
      modelActivationConfirmed &&
      renderCredibilityConfirmed;
}

/// NAV-3D-VEHICLE-VISIBILITY-FAILSAFE-1: strict HUD hide preconditions.
bool resolveDriver3dVehicleHudFallbackAllowedToHide({
  required bool eligible,
  required bool assetLoaded,
  required bool modelRegistered,
  required bool layerCreated,
  required bool sourceGeometryValid,
  required bool modelPoseApplied,
  required bool modelActivationConfirmed,
  required bool renderCredibilityConfirmed,
  required int activeStyleGeneration,
  required int activePresetGeneration,
  required int confirmedStyleGeneration,
  required int confirmedPresetGeneration,
  bool debugRenderProbeActive = false,
  bool native3dRendererActive = false,
}) {
  if (debugRenderProbeActive) return false;
  if (!eligible) return false;
  // NAV-3D-P0: Native LocationPuck3D is visually credible once the session
  // owns follow + the requested 3D choice is eligible.
  if (native3dRendererActive) return true;
  if (!assetLoaded ||
      !modelRegistered ||
      !layerCreated ||
      !sourceGeometryValid ||
      !modelPoseApplied ||
      !modelActivationConfirmed ||
      !renderCredibilityConfirmed) {
    return false;
  }
  return activeStyleGeneration == confirmedStyleGeneration &&
      activePresetGeneration == confirmedPresetGeneration;
}

/// NAV-3D-VEHICLE-VISIBILITY-FAILSAFE-1: HUD may hide only after 3D visual ready.
bool resolveDriver3dVehicleHudTaxiHidden({
  required bool driver3dVisualReady,
  required bool hideHudIsolationFlagEnabled,
  required bool useDriverCockpitCamera,
  required NavigationPresentationMode presentationMode,
}) {
  return driver3dVisualReady &&
      hideHudIsolationFlagEnabled &&
      useDriverCockpitCamera &&
      presentationMode == NavigationPresentationMode.driver;
}

/// NAV-ASSET-3D-MODE-GATE-1: true only for Mapbox Standard (not satellite).
bool resolveDriver3dVehicleDedicatedStyleActive({
  required String? activeStyleUri,
}) {
  final uri = activeStyleUri?.trim() ?? '';
  if (uri.isEmpty) return false;
  if (uri.contains('/standard-satellite')) return false;
  return uri.contains('/standard');
}

/// NAV-ASSET-3D-MODE-GATE-1: explicit cockpit choice is dedicated 3D only.
bool resolveDriver3dVehicleDedicatedCockpitChoiceActive({
  required bool cockpitSceneEnabled,
  required DriverCockpitMapVisualStyle? cockpitVisualStyle,
}) {
  if (!cockpitSceneEnabled) return false;
  return cockpitVisualStyle == DriverCockpitMapVisualStyle.standard3d;
}

/// NAV-ASSET-3D-MODE-GATE-1: single authoritative 3D vehicle feature gate.
Driver3dVehicleEligibility resolveDriver3dVehicleEligibility({
  required bool vehicleModelFlagEnabled,
  required bool cockpitSceneEnabled,
  required bool useDriverCockpitCamera,
  required NavigationPresentationMode presentationMode,
  required bool liveNavigationActive,
  required bool followCamera,
  required String? activeStyleUri,
  required DriverMapVisualMode visualMode,
  required bool cockpitSceneActive,
  required DriverCockpitMapVisualStyle? cockpitVisualStyle,
  required bool sessionFallback2d,
  required bool styleLoaded,
  required bool styleSwapInProgress,
  required bool modelRegistered,
  required bool modelPoseApplied,
  required bool hideHudIsolationFlagEnabled,
  bool layerCreated = false,
  bool sourceGeometryValid = false,
  bool modelActivationConfirmed = false,
  bool renderCredibilityConfirmed = false,
  bool assetLoaded = false,
  bool debugRenderProbeActive = false,
  int activeStyleGeneration = 0,
  int activePresetGeneration = 0,
  int confirmedStyleGeneration = -1,
  int confirmedPresetGeneration = -1,
  int modelLayerStyleGeneration = -1,
  int modelLayerPresetGeneration = -1,
  bool followLiveActive = false,
  bool useDriver3dVehicleModel = false,
  // NAV-3D-VEHICLE-CHOICE-3WAY-1: explicit three-way vehicle presentation
  // choice. `null` keeps legacy behavior (3D implied by style/scene gates).
  DriverVehiclePresentationChoice? selectedVehiclePresentation,
  // NAV-3D-P0-PERSISTENT-VEHICLE-OWNERSHIP-1: Native FollowPuck owns LocationPuck3D.
  bool native3dRendererActive = false,
}) {
  final capability = DriverCockpitMap3dCapability.resolve(
    styleUri: activeStyleUri?.trim() ?? '',
    visualMode: visualMode,
  );
  final presentation = navigationPresentationModeLabel(presentationMode);
  final styleFamily = capability.styleFamily;
  final requested3d = selectedVehiclePresentation == null
      ? true
      : driverVehiclePresentationChoiceIs3d(selectedVehiclePresentation);

  String reason = 'eligible';
  if (!vehicleModelFlagEnabled) {
    reason = 'feature_flag_disabled';
  } else if (!cockpitSceneEnabled) {
    reason = 'cockpit_scene_flag_disabled';
  } else if (!useDriverCockpitCamera) {
    reason = 'cockpit_camera_off';
  } else if (presentationMode != NavigationPresentationMode.driver) {
    reason = 'not_driver_presentation';
  } else if (!liveNavigationActive) {
    reason = 'not_live_navigation';
  } else if (!followCamera) {
    reason = 'not_follow_camera';
  } else if (!cockpitSceneActive) {
    reason = 'cockpit_scene_inactive';
  } else if (selectedVehiclePresentation != null && !requested3d) {
    // NAV-3D-VEHICLE-CHOICE-3WAY-1 / NAV-3D-P0: only when the authoritative
    // requested choice is explicitly 2D — never for temporary render gaps.
    reason = 'vehicle_choice_2d';
  } else if (sessionFallback2d) {
    reason = 'session_fallback_2d';
  } else if (styleSwapInProgress) {
    reason = 'style_swap_in_progress';
  } else if (!styleLoaded) {
    reason = 'style_not_loaded';
  } else if (!resolveDriver3dVehicleDedicatedCockpitChoiceActive(
    cockpitSceneEnabled: cockpitSceneEnabled,
    cockpitVisualStyle: cockpitVisualStyle,
  )) {
    reason = 'not_dedicated_3d_choice';
  } else if (!resolveDriver3dVehicleDedicatedStyleActive(
    activeStyleUri: activeStyleUri,
  )) {
    reason = 'not_dedicated_3d_style';
  }

  final eligible = reason == 'eligible';
  // Native ownership only counts when the requested choice is still 3D and
  // the feature is otherwise eligible — temporary ineligibility keeps HUD.
  final nativeOwns =
      native3dRendererActive && requested3d && eligible;
  final hudFallbackAllowedToHide =
      resolveDriver3dVehicleHudFallbackAllowedToHide(
        eligible: eligible,
        assetLoaded: assetLoaded,
        modelRegistered: modelRegistered,
        layerCreated: layerCreated,
        sourceGeometryValid: sourceGeometryValid,
        modelPoseApplied: modelPoseApplied,
        modelActivationConfirmed: modelActivationConfirmed,
        renderCredibilityConfirmed: renderCredibilityConfirmed,
        activeStyleGeneration: activeStyleGeneration,
        activePresetGeneration: activePresetGeneration,
        confirmedStyleGeneration: confirmedStyleGeneration,
        confirmedPresetGeneration: confirmedPresetGeneration,
        debugRenderProbeActive: debugRenderProbeActive,
        native3dRendererActive: nativeOwns,
      );
  final effectivelyActive = resolveNav3dVehicleEffectivelyActive(
    eligible: eligible,
    assetLoaded: assetLoaded,
    modelRegistered: modelRegistered,
    layerCreated: layerCreated,
    modelPoseApplied: modelPoseApplied,
    modelActivationConfirmed: modelActivationConfirmed,
    renderCredibilityConfirmed: renderCredibilityConfirmed,
    native3dRendererActive: nativeOwns,
  );
  final confirmedHandoff = effectivelyActive && hudFallbackAllowedToHide;
  final modelReady = confirmedHandoff;
  final presentation3dActive = resolveNav3dPresentationActive(
    eligible: eligible,
    useDriver3dVehicleModel: useDriver3dVehicleModel,
    followLiveActive: followLiveActive,
  );
  final driver3dVisualReady = resolveDriver3dVisualReady(
    followLiveActive: followLiveActive,
    presentation3dActive: presentation3dActive,
    eligible: eligible,
    modelFeatureEnabled: vehicleModelFlagEnabled,
    modelRegistered: modelRegistered,
    layerCreated: layerCreated,
    sourceGeometryValid: sourceGeometryValid,
    modelPoseApplied: modelPoseApplied,
    activeStyleGeneration: activeStyleGeneration,
    activePresetGeneration: activePresetGeneration,
    modelLayerStyleGeneration: modelLayerStyleGeneration,
    modelLayerPresetGeneration: modelLayerPresetGeneration,
    explicit2dFallback: sessionFallback2d,
    debugRenderProbeActive: debugRenderProbeActive,
    native3dRendererActive: nativeOwns,
  );
  final hudTaxiHidden = resolveDriver3dVehicleHudTaxiHidden(
    driver3dVisualReady: driver3dVisualReady,
    hideHudIsolationFlagEnabled: hideHudIsolationFlagEnabled,
    useDriverCockpitCamera: useDriverCockpitCamera,
    presentationMode: presentationMode,
  );
  final mapbox2dTaxiHidden = !debugRenderProbeActive &&
      (driver3dVisualReady || (eligible && !sessionFallback2d));

  return Driver3dVehicleEligibility(
    eligible: eligible,
    reason: reason,
    presentation: presentation,
    styleFamily: styleFamily,
    modelReady: modelReady,
    fallback2d: sessionFallback2d,
    selectorVisible: eligible,
    hudTaxiHidden: hudTaxiHidden,
    mapbox2dTaxiHidden: mapbox2dTaxiHidden,
    allowModelLayer: eligible,
    allowMovementSync: eligible,
    layerCreated: layerCreated,
    sourceGeometryValid: sourceGeometryValid,
    modelPoseApplied: modelPoseApplied,
    modelActivationConfirmed: modelActivationConfirmed,
    hudFallbackAllowedToHide: hudFallbackAllowedToHide,
    effectivelyActive: effectivelyActive,
    driver3dVisualReady: driver3dVisualReady,
  );
}

/// NAV-3D-VEHICLE-RESTORE-DIAG-1: bounded fallback reason for field diagnostics.
enum Nav3dVehicleFallbackReason {
  none,
  featureDisabled,
  styleNotEligible,
  vehicleChoiceNot3d,
  assetMissing,
  modelRegistrationFailed,
  layerCreationFailed,
  styleTransition,
  unsupportedRuntime,
}

String nav3dVehicleFallbackReasonLabel(Nav3dVehicleFallbackReason reason) {
  switch (reason) {
    case Nav3dVehicleFallbackReason.none:
      return 'none';
    case Nav3dVehicleFallbackReason.featureDisabled:
      return 'feature_disabled';
    case Nav3dVehicleFallbackReason.styleNotEligible:
      return 'style_not_eligible';
    case Nav3dVehicleFallbackReason.vehicleChoiceNot3d:
      return 'vehicle_choice_not_3d';
    case Nav3dVehicleFallbackReason.assetMissing:
      return 'asset_missing';
    case Nav3dVehicleFallbackReason.modelRegistrationFailed:
      return 'model_registration_failed';
    case Nav3dVehicleFallbackReason.layerCreationFailed:
      return 'layer_creation_failed';
    case Nav3dVehicleFallbackReason.styleTransition:
      return 'style_transition';
    case Nav3dVehicleFallbackReason.unsupportedRuntime:
      return 'unsupported_runtime';
  }
}

/// NAV-3D-VEHICLE-RESTORE-DIAG-1: single-line activation snapshot.
class Nav3dVehicleDiagnosticSnapshot {
  const Nav3dVehicleDiagnosticSnapshot({
    required this.presentationActive,
    required this.styleEligible,
    required this.vehicleChoice,
    required this.featureEnabled,
    required this.assetPath,
    required this.assetLoaded,
    required this.modelRegistered,
    required this.layerCreated,
    required this.effectivelyActive,
    required this.fallbackReason,
  });

  final bool presentationActive;
  final bool styleEligible;
  final String vehicleChoice;
  final bool featureEnabled;
  final String assetPath;
  final bool assetLoaded;
  final bool modelRegistered;
  final bool layerCreated;
  final bool effectivelyActive;
  final Nav3dVehicleFallbackReason fallbackReason;

  String get signature =>
      '$presentationActive|$styleEligible|$vehicleChoice|$featureEnabled|'
      '$assetPath|$assetLoaded|$modelRegistered|$layerCreated|'
      '$effectivelyActive|${fallbackReason.name}';
}

/// NAV-3D-VEHICLE-RESTORE-DIAG-1: Mapbox Standard + explicit 3D cockpit choice.
bool resolveNav3dVehicleStyleEligible({
  required bool cockpitSceneEnabled,
  required DriverCockpitMapVisualStyle? cockpitVisualStyle,
  required String? activeStyleUri,
}) {
  if (!cockpitSceneEnabled) return false;
  return resolveDriver3dVehicleDedicatedCockpitChoiceActive(
        cockpitSceneEnabled: cockpitSceneEnabled,
        cockpitVisualStyle: cockpitVisualStyle,
      ) &&
      resolveDriver3dVehicleDedicatedStyleActive(
        activeStyleUri: activeStyleUri,
      );
}

/// NAV-3D-MAPBOX-2D-MARKER-ISOLATION-FIX-1: intent to be in 3D presentation.
///
/// Creation-time-only signal: independent of transient conditions such as
/// `styleSwapInProgress`, `styleLoaded`, activation confirmation, or handoff
/// generation matches. Marker create/recreate paths use this signal (via
/// [resolveNav3dMapbox2dTaxiCreateOpacity]) to snap iconOpacity=0 during any
/// moment the driver *intends* to be in 3D mode, so the Mapbox 2D taxi never
/// becomes visibly recreated underneath the ModelLayer while activation is
/// still transitioning.
bool resolveNav3dPresentation3dIntent({
  required bool vehicleModelFlagEnabled,
  required bool cockpitSceneEnabled,
  required bool useDriverCockpitCamera,
  required NavigationPresentationMode presentationMode,
  required bool liveNavigationActive,
  required bool followCamera,
  required bool cockpitSceneActive,
  required bool sessionFallback2d,
  required DriverCockpitMapVisualStyle? cockpitVisualStyle,
  required String? activeStyleUri,
  // NAV-3D-VEHICLE-CHOICE-3WAY-1: 2D taxi selection means no 3D intent.
  DriverVehiclePresentationChoice? selectedVehiclePresentation,
}) {
  if (selectedVehiclePresentation != null &&
      !driverVehiclePresentationChoiceIs3d(selectedVehiclePresentation)) {
    return false;
  }
  if (!vehicleModelFlagEnabled) return false;
  if (!cockpitSceneEnabled) return false;
  if (!useDriverCockpitCamera) return false;
  if (presentationMode != NavigationPresentationMode.driver) return false;
  if (!liveNavigationActive) return false;
  if (!followCamera) return false;
  if (!cockpitSceneActive) return false;
  if (sessionFallback2d) return false;
  return resolveNav3dVehicleStyleEligible(
    cockpitSceneEnabled: cockpitSceneEnabled,
    cockpitVisualStyle: cockpitVisualStyle,
    activeStyleUri: activeStyleUri,
  );
}

/// NAV-3D-MAPBOX-2D-MARKER-ISOLATION-FIX-1 /
/// NAV-3D-YELLOW-TAXI-FINAL-VISIBILITY-FIX-1: single authoritative Mapbox 2D
/// taxi marker `iconOpacity`.
///
/// Rules (strict precedence order):
///   1. Not follow-live navigation          → 1.0 (idle map, visible)
///   2. HUD overlay owns the driver visual  → 0.0 (never underneath the HUD)
///   3. Explicit session fallback to 2D     → 1.0 (must show 2D)
///   4. Intended 3D presentation            → 0.0 (Mapbox 2D taxi hidden)
///   5. Otherwise                           → 1.0 (default 2D visible)
///
/// Rule 2 restores the pre-isolation-fix invariant enforced by
/// [resolveNav3dMapbox2dTaxiVisible]: while the screen-fixed Flutter HUD taxi
/// is the active driver visual, the native Mapbox marker must never be
/// visible, in 2D follow mode, 3D transitions, preset swaps, style restores,
/// self-heal and asset upgrades alike. It intentionally outranks the
/// explicit 2D fallback because the HUD taxi still covers the vehicle then.
///
/// Every marker create, recreate, asset-upgrade, self-heal, retry-restore and
/// update path must resolve its opacity through this helper. Callers must not
/// invent their own opacity decision or wait for full 3D activation
/// confirmation before hiding the native marker.
double resolveNav3dMapbox2dTaxiCreateOpacity({
  required bool followLiveActive,
  required bool hideForHudOverlay,
  required bool presentation3dIntent,
  required bool explicit2dFallback,
}) {
  if (!followLiveActive) return 1.0;
  if (hideForHudOverlay) return 0.0;
  if (explicit2dFallback) return 1.0;
  if (presentation3dIntent) return 0.0;
  return 1.0;
}

/// NAV-3D-MAPBOX-2D-MARKER-ISOLATION-FIX-1: bounded log budget per activation.
const int kNav3dMapbox2dMaxLogsPerActivation = 24;

int _nav3dMapbox2dLogCount = 0;
String? _lastNav3dMapbox2dSignature;

/// NAV-3D-MAPBOX-2D-MARKER-ISOLATION-FIX-1: reset the diagnostic log budget.
void resetNav3dMapbox2dLogBudget() {
  _nav3dMapbox2dLogCount = 0;
  _lastNav3dMapbox2dSignature = null;
}

/// NAV-3D-MAPBOX-2D-MARKER-ISOLATION-FIX-1: bounded diagnostics for the
/// Mapbox 2D taxi marker opacity ownership pipeline. Emits a single line
/// with the desired/pending/applied opacity and the source event so field
/// traces can show exactly which create/update path last touched the native
/// marker.
void logNav3dMapbox2d({
  required String event,
  required bool presentation3dIntent,
  required bool explicit2dFallback,
  required double desiredOpacity,
  required double? pendingOpacity,
  required bool markerExists,
  required double? appliedOpacity,
  required String source,
}) {
  final signature =
      '$event|$presentation3dIntent|$explicit2dFallback|'
      '${desiredOpacity.toStringAsFixed(2)}|'
      '${pendingOpacity?.toStringAsFixed(2) ?? 'null'}|'
      '$markerExists|'
      '${appliedOpacity?.toStringAsFixed(2) ?? 'null'}|$source';
  if (signature == _lastNav3dMapbox2dSignature) return;
  if (_nav3dMapbox2dLogCount >= kNav3dMapbox2dMaxLogsPerActivation) return;
  _lastNav3dMapbox2dSignature = signature;
  _nav3dMapbox2dLogCount += 1;
  debugPrint(
    '[NAV_3D_MAPBOX_2D] event=$event '
    'presentation3dIntent=$presentation3dIntent '
    'explicit2dFallback=$explicit2dFallback '
    'desiredOpacity=${desiredOpacity.toStringAsFixed(2)} '
    'pendingOpacity=${pendingOpacity?.toStringAsFixed(2) ?? 'null'} '
    'markerExists=$markerExists '
    'appliedOpacity=${appliedOpacity?.toStringAsFixed(2) ?? 'null'} '
    'source=$source',
  );
}

/// NAV-3D-YELLOW-TAXI-FINAL-VISIBILITY-FIX-1: bounded retry delays for the
/// 3D activation confirmation readback. Max 3 attempts per style/preset
/// generation pair.
const List<int> kNav3dActivationConfirmRetryDelaysMs = <int>[80, 180, 350];

/// NAV-3D-YELLOW-TAXI-FINAL-VISIBILITY-FIX-1: generation-keyed retry budget
/// for `_tryConfirmDriver3dVehicleModelActivation`.
///
/// The activation confirmation readback can fail transiently (style mid-swap,
/// asset flag not settled, render probe raced native layer creation) after a
/// valid pose write. Without a retry the HUD fallback can remain mounted
/// indefinitely on top of an already-rendering ModelLayer. This lifecycle
/// hands out at most [kNav3dActivationConfirmRetryDelaysMs] delays per
/// (styleGeneration, presetGeneration) pair; a generation change starts a
/// fresh budget and implicitly abandons the old one.
class Nav3dActivationConfirmRetryLifecycle {
  int _styleGeneration = -1;
  int _presetGeneration = -1;
  int _attempts = 0;
  bool _exhaustedLogged = false;

  int get attempts => _attempts;

  /// Delay before the next retry for the given generation pair, or `null`
  /// when the bounded budget is exhausted.
  Duration? nextDelay({
    required int styleGeneration,
    required int presetGeneration,
  }) {
    if (styleGeneration != _styleGeneration ||
        presetGeneration != _presetGeneration) {
      _styleGeneration = styleGeneration;
      _presetGeneration = presetGeneration;
      _attempts = 0;
      _exhaustedLogged = false;
    }
    if (_attempts >= kNav3dActivationConfirmRetryDelaysMs.length) return null;
    final delay = Duration(
      milliseconds: kNav3dActivationConfirmRetryDelaysMs[_attempts],
    );
    _attempts += 1;
    return delay;
  }

  /// True exactly once per generation pair after the budget is exhausted,
  /// so the host emits a single bounded failure diagnostic.
  bool markExhaustedOnce() {
    if (_exhaustedLogged) return false;
    _exhaustedLogged = true;
    return true;
  }

  void reset() {
    _styleGeneration = -1;
    _presetGeneration = -1;
    _attempts = 0;
    _exhaustedLogged = false;
  }
}

/// NAV-3D-YELLOW-TAXI-FINAL-VISIBILITY-FIX-1: pure cancellation check for a
/// scheduled activation-confirm retry. The retry must be dropped when the
/// world moved on while the timer was pending.
bool nav3dActivationConfirmRetryStillValid({
  required int scheduledStyleGeneration,
  required int scheduledPresetGeneration,
  required int currentStyleGeneration,
  required int currentPresetGeneration,
  required bool activationConfirmed,
  required bool eligible,
  required bool presentation3dIntent,
  required bool layerCreated,
  required bool sourceGeometryValid,
  required bool sessionFallback2d,
}) {
  if (activationConfirmed) return false;
  if (scheduledStyleGeneration != currentStyleGeneration) return false;
  if (scheduledPresetGeneration != currentPresetGeneration) return false;
  if (!eligible) return false;
  if (!presentation3dIntent) return false;
  if (!layerCreated) return false;
  if (!sourceGeometryValid) return false;
  if (sessionFallback2d) return false;
  return true;
}

/// NAV-3D-VEHICLE-RESTORE-DIAG-1: bundle path from Mapbox asset URI.
String driverVehicle3dAssetBundlePath(String assetUri) {
  const prefix = 'asset://';
  if (assetUri.startsWith(prefix)) {
    return assetUri.substring(prefix.length);
  }
  return assetUri;
}

/// NAV-3D-ASSET-PROBE-LIFECYCLE-OOM-1: inputs for GLB byte-load eligibility.
class Driver3dVehicleAssetLoadContext {
  const Driver3dVehicleAssetLoadContext({
    required this.vehicleModelFlagEnabled,
    required this.cockpitSceneEnabled,
    required this.useDriverCockpitCamera,
    required this.presentationMode,
    required this.liveNavigationActive,
    required this.followCamera,
    required this.activeStyleUri,
    required this.visualMode,
    required this.cockpitSceneActive,
    required this.cockpitVisualStyle,
    required this.sessionFallback2d,
    required this.styleLoaded,
    required this.styleSwapInProgress,
  });

  final bool vehicleModelFlagEnabled;
  final bool cockpitSceneEnabled;
  final bool useDriverCockpitCamera;
  final NavigationPresentationMode presentationMode;
  final bool liveNavigationActive;
  final bool followCamera;
  final String? activeStyleUri;
  final DriverMapVisualMode visualMode;
  final bool cockpitSceneActive;
  final DriverCockpitMapVisualStyle? cockpitVisualStyle;
  final bool sessionFallback2d;
  final bool styleLoaded;
  final bool styleSwapInProgress;
}

/// NAV-3D-ASSET-PROBE-LIFECYCLE-OOM-1: GLB bytes may load only when fully eligible.
bool resolveDriver3dVehicleAssetLoadEligible(
  Driver3dVehicleAssetLoadContext context,
) {
  return resolveDriver3dVehicleEligibility(
    vehicleModelFlagEnabled: context.vehicleModelFlagEnabled,
    cockpitSceneEnabled: context.cockpitSceneEnabled,
    useDriverCockpitCamera: context.useDriverCockpitCamera,
    presentationMode: context.presentationMode,
    liveNavigationActive: context.liveNavigationActive,
    followCamera: context.followCamera,
    activeStyleUri: context.activeStyleUri,
    visualMode: context.visualMode,
    cockpitSceneActive: context.cockpitSceneActive,
    cockpitVisualStyle: context.cockpitVisualStyle,
    sessionFallback2d: context.sessionFallback2d,
    styleLoaded: context.styleLoaded,
    styleSwapInProgress: context.styleSwapInProgress,
    modelRegistered: false,
    modelPoseApplied: false,
    hideHudIsolationFlagEnabled: false,
  ).eligible;
}

/// NAV-3D-ASSET-PROBE-LIFECYCLE-OOM-1: bounded ineligibility token for asset loads.
String resolveDriver3dVehicleAssetLoadIneligibleReason(
  Driver3dVehicleAssetLoadContext context,
) {
  return resolveDriver3dVehicleEligibility(
    vehicleModelFlagEnabled: context.vehicleModelFlagEnabled,
    cockpitSceneEnabled: context.cockpitSceneEnabled,
    useDriverCockpitCamera: context.useDriverCockpitCamera,
    presentationMode: context.presentationMode,
    liveNavigationActive: context.liveNavigationActive,
    followCamera: context.followCamera,
    activeStyleUri: context.activeStyleUri,
    visualMode: context.visualMode,
    cockpitSceneActive: context.cockpitSceneActive,
    cockpitVisualStyle: context.cockpitVisualStyle,
    sessionFallback2d: context.sessionFallback2d,
    styleLoaded: context.styleLoaded,
    styleSwapInProgress: context.styleSwapInProgress,
    modelRegistered: false,
    modelPoseApplied: false,
    hideHudIsolationFlagEnabled: false,
  ).reason;
}

typedef DriverVehicle3dAssetLoader = Future<int> Function(String bundlePath);

/// NAV-3D-ASSET-PROBE-LIFECYCLE-OOM-1: single authoritative GLB byte-load lifecycle.
class Driver3dVehicleAssetLifecycle {
  Driver3dVehicleAssetLifecycle({DriverVehicle3dAssetLoader? loader})
    : _loader = loader ?? _defaultLoadBytes;

  static Future<int> _defaultLoadBytes(String path) async {
    final data = await rootBundle.load(path);
    return data.lengthInBytes;
  }

  final DriverVehicle3dAssetLoader _loader;

  /// Test-only counter for rootBundle-equivalent load invocations.
  int loadInvocationCount = 0;

  bool? _cachedLoaded;
  DriverVehicle3dPreset? _cachedPreset;
  int? _cachedStyleGeneration;
  int? _cachedPresetGeneration;
  int? _cachedBytes;

  int _requestGeneration = 0;
  Future<bool>? _inFlight;

  /// Observational only — never initiates a load.
  bool observationalAssetLoaded({
    required DriverVehicle3dPreset preset,
    required int styleGeneration,
    required int presetGeneration,
  }) {
    if (_cachedPreset != preset ||
        _cachedStyleGeneration != styleGeneration ||
        _cachedPresetGeneration != presetGeneration) {
      return false;
    }
    return _cachedLoaded ?? false;
  }

  void invalidateForStyleGeneration() {
    _requestGeneration++;
    _inFlight = null;
    _cachedLoaded = null;
    _cachedPreset = null;
    _cachedStyleGeneration = null;
    _cachedPresetGeneration = null;
    _cachedBytes = null;
    _registrationVerified = null;
  }

  void invalidateForPresetGeneration() {
    _requestGeneration++;
    _inFlight = null;
    _cachedLoaded = null;
    _cachedPreset = null;
    _cachedStyleGeneration = null;
    _cachedPresetGeneration = null;
    _cachedBytes = null;
    _registrationVerified = null;
  }

  bool? _registrationVerified;

  /// True when Mapbox registration succeeded for the current generation without
  /// requiring a fresh Dart [rootBundle] load (e.g. after preset swap).
  bool observationalRegistrationVerified({
    required DriverVehicle3dPreset preset,
    required int styleGeneration,
    required int presetGeneration,
  }) {
    if (_cachedPreset != preset ||
        _cachedStyleGeneration != styleGeneration ||
        _cachedPresetGeneration != presetGeneration) {
      return false;
    }
    return _registrationVerified ?? false;
  }

  /// Marks the GLB as credibly available for the active generation after native
  /// registration succeeds (even when Dart byte-load cache was invalidated).
  void markRegistrationVerified({
    required DriverVehicle3dPreset preset,
    required int styleGeneration,
    required int presetGeneration,
  }) {
    _cachedPreset = preset;
    _cachedStyleGeneration = styleGeneration;
    _cachedPresetGeneration = presetGeneration;
    _registrationVerified = true;
    _cachedLoaded = true;
  }

  void cancelInFlightForIneligibility({required String reason}) {
    _requestGeneration++;
    _inFlight = null;
    logNav3dAssetLifecycle(
      action: 'skip',
      reason: reason,
      preset: 'none',
      eligibility: false,
      styleGeneration: -1,
      presetGeneration: -1,
    );
  }

  Future<bool> ensureLoadedIfEligible({
    required Driver3dVehicleAssetLoadContext context,
    required DriverVehicle3dPreset preset,
    required int styleGeneration,
    required int presetGeneration,
  }) async {
    final presetLabel = driverVehicle3dPresetLogLabel(preset);
    final eligible = resolveDriver3dVehicleAssetLoadEligible(context);

    if (!eligible) {
      logNav3dAssetLifecycle(
        action: 'skip',
        reason: resolveDriver3dVehicleAssetLoadIneligibleReason(context),
        preset: presetLabel,
        eligibility: false,
        styleGeneration: styleGeneration,
        presetGeneration: presetGeneration,
      );
      return false;
    }

    if (_cachedPreset == preset &&
        _cachedStyleGeneration == styleGeneration &&
        _cachedPresetGeneration == presetGeneration &&
        _cachedLoaded == true) {
      logNav3dAssetLifecycle(
        action: 'skip',
        reason: 'already_loaded',
        preset: presetLabel,
        eligibility: true,
        styleGeneration: styleGeneration,
        presetGeneration: presetGeneration,
        bytes: _cachedBytes,
      );
      return true;
    }

    if (_cachedPreset == preset &&
        _cachedStyleGeneration == styleGeneration &&
        _cachedPresetGeneration == presetGeneration &&
        _cachedLoaded == false) {
      logNav3dAssetLifecycle(
        action: 'skip',
        reason: 'load_failed_cached',
        preset: presetLabel,
        eligibility: true,
        styleGeneration: styleGeneration,
        presetGeneration: presetGeneration,
      );
      return false;
    }

    if (_inFlight != null) {
      logNav3dAssetLifecycle(
        action: 'skip',
        reason: 'load_in_flight',
        preset: presetLabel,
        eligibility: true,
        styleGeneration: styleGeneration,
        presetGeneration: presetGeneration,
      );
      return _inFlight!;
    }

    final requestGeneration = ++_requestGeneration;
    logNav3dAssetLifecycle(
      action: 'request',
      reason: 'eligible',
      preset: presetLabel,
      eligibility: true,
      styleGeneration: styleGeneration,
      presetGeneration: presetGeneration,
    );

    _inFlight = _performLoad(
      preset: preset,
      presetLabel: presetLabel,
      styleGeneration: styleGeneration,
      presetGeneration: presetGeneration,
      requestGeneration: requestGeneration,
    ).whenComplete(() {
      _inFlight = null;
    });
    return _inFlight!;
  }

  Future<bool> _performLoad({
    required DriverVehicle3dPreset preset,
    required String presetLabel,
    required int styleGeneration,
    required int presetGeneration,
    required int requestGeneration,
  }) async {
    final path = driverVehicle3dAssetBundlePath(
      resolveDriverVehicle3dModelSpec(preset).assetUri,
    );

    logNav3dAssetLifecycle(
      action: 'load_start',
      reason: 'eligible',
      preset: presetLabel,
      eligibility: true,
      styleGeneration: styleGeneration,
      presetGeneration: presetGeneration,
    );

    try {
      loadInvocationCount++;
      final bytes = await _loader(path);
      if (requestGeneration != _requestGeneration) {
        logNav3dAssetLifecycle(
          action: 'skip',
          reason: 'stale_generation',
          preset: presetLabel,
          eligibility: true,
          styleGeneration: styleGeneration,
          presetGeneration: presetGeneration,
        );
        return false;
      }

      _cachedPreset = preset;
      _cachedStyleGeneration = styleGeneration;
      _cachedPresetGeneration = presetGeneration;
      _cachedLoaded = true;
      _cachedBytes = bytes;

      logNav3dAssetLifecycle(
        action: 'load_done',
        reason: 'eligible',
        preset: presetLabel,
        eligibility: true,
        styleGeneration: styleGeneration,
        presetGeneration: presetGeneration,
        bytes: bytes,
      );
      return true;
    } catch (_) {
      if (requestGeneration != _requestGeneration) {
        return false;
      }
      _cachedPreset = preset;
      _cachedStyleGeneration = styleGeneration;
      _cachedPresetGeneration = presetGeneration;
      _cachedLoaded = false;
      _cachedBytes = null;

      logNav3dAssetLifecycle(
        action: 'failure',
        reason: 'load_exception',
        preset: presetLabel,
        eligibility: true,
        styleGeneration: styleGeneration,
        presetGeneration: presetGeneration,
      );
      return false;
    }
  }
}

/// NAV-3D-RENDER-VISIBILITY-PROOF-1: observational asset state for diagnostics.
bool resolveObservationalAssetLoaded({
  required Driver3dVehicleAssetLifecycle lifecycle,
  required DriverVehicle3dPreset preset,
  required int styleGeneration,
  required int presetGeneration,
  required bool modelRegistered,
}) {
  if (lifecycle.observationalAssetLoaded(
    preset: preset,
    styleGeneration: styleGeneration,
    presetGeneration: presetGeneration,
  )) {
    return true;
  }
  if (modelRegistered &&
      lifecycle.observationalRegistrationVerified(
        preset: preset,
        styleGeneration: styleGeneration,
        presetGeneration: presetGeneration,
      )) {
    return true;
  }
  return false;
}

String? _lastNav3dAssetLifecycleSignature;

/// NAV-3D-ASSET-PROBE-LIFECYCLE-OOM-1: bounded asset lifecycle diagnostics.
void logNav3dAssetLifecycle({
  required String action,
  required String reason,
  required String preset,
  required bool eligibility,
  required int styleGeneration,
  required int presetGeneration,
  int? bytes,
}) {
  final signature =
      '$action|$reason|$preset|$eligibility|'
      '$styleGeneration|$presetGeneration|${bytes ?? -1}';
  if (signature == _lastNav3dAssetLifecycleSignature) return;
  _lastNav3dAssetLifecycleSignature = signature;
  debugPrint(
    '[NAV_3D_ASSET_LIFECYCLE] action=$action reason=$reason preset=$preset '
    'eligibility=$eligibility styleGeneration=$styleGeneration '
    'presetGeneration=$presetGeneration'
    '${bytes != null ? ' bytes=$bytes' : ''}',
  );
}

Nav3dVehicleFallbackReason resolveNav3dVehicleFallbackReason({
  required Driver3dVehicleEligibility eligibility,
  required bool featureEnabled,
  required bool assetLoaded,
  required bool modelRegistered,
  required bool layerCreated,
  required bool modelPoseApplied,
  required bool registerInFlight,
}) {
  if (eligibility.eligible &&
      assetLoaded &&
      modelRegistered &&
      layerCreated &&
      modelPoseApplied &&
      eligibility.modelActivationConfirmed) {
    return Nav3dVehicleFallbackReason.none;
  }
  if (!featureEnabled) {
    return Nav3dVehicleFallbackReason.featureDisabled;
  }
  switch (eligibility.reason) {
    case 'vehicle_choice_2d':
    case 'not_dedicated_3d_choice':
      return Nav3dVehicleFallbackReason.vehicleChoiceNot3d;
    case 'not_dedicated_3d_style':
      return Nav3dVehicleFallbackReason.styleNotEligible;
    case 'style_swap_in_progress':
    case 'style_not_loaded':
      return Nav3dVehicleFallbackReason.styleTransition;
    case 'session_fallback_2d':
      return Nav3dVehicleFallbackReason.modelRegistrationFailed;
    case 'eligible':
      break;
    default:
      if (!eligibility.eligible) {
        return Nav3dVehicleFallbackReason.unsupportedRuntime;
      }
  }
  if (registerInFlight) {
    return Nav3dVehicleFallbackReason.styleTransition;
  }
  if (!assetLoaded) {
    return Nav3dVehicleFallbackReason.assetMissing;
  }
  if (!modelRegistered) {
    return Nav3dVehicleFallbackReason.modelRegistrationFailed;
  }
  if (!layerCreated) {
    return Nav3dVehicleFallbackReason.layerCreationFailed;
  }
  return Nav3dVehicleFallbackReason.none;
}

Nav3dVehicleDiagnosticSnapshot resolveNav3dVehicleDiagnosticSnapshot({
  required bool presentationActive,
  required bool featureEnabled,
  required bool cockpitSceneEnabled,
  required DriverCockpitMapVisualStyle? cockpitVisualStyle,
  required DriverVehicle3dPreset vehiclePreset,
  required String? activeStyleUri,
  required Driver3dVehicleEligibility eligibility,
  required bool assetLoaded,
  required bool modelRegistered,
  required bool layerCreated,
  required bool modelPoseApplied,
  required bool modelActivationConfirmed,
  bool renderCredibilityConfirmed = false,
  required bool registerInFlight,
  // NAV-3D-P0: authoritative requested presentation (distinct from cockpit style).
  DriverVehiclePresentationChoice? selectedVehiclePresentation,
  bool native3dRendererActive = false,
}) {
  final spec = resolveDriverVehicle3dModelSpec(vehiclePreset);
  final cockpitLabel = cockpitVisualStyle == null
      ? 'none'
      : driverCockpitMapVisualStyleLogLabel(cockpitVisualStyle);
  final presentationLabel = selectedVehiclePresentation == null
      ? 'legacy'
      : driverVehiclePresentationChoiceLogLabel(selectedVehiclePresentation);
  // NAV-3D-P0: never alias cockpit map style as the vehicle presentation choice.
  final vehicleChoice =
      'cockpit=$cockpitLabel presentation=$presentationLabel '
      'preset=${driverVehicle3dPresetLogLabel(vehiclePreset)}';
  final styleEligible = resolveNav3dVehicleStyleEligible(
    cockpitSceneEnabled: cockpitSceneEnabled,
    cockpitVisualStyle: cockpitVisualStyle,
    activeStyleUri: activeStyleUri,
  );
  final effectivelyActive = resolveNav3dVehicleEffectivelyActive(
    eligible: eligibility.eligible,
    assetLoaded: assetLoaded,
    modelRegistered: modelRegistered,
    layerCreated: layerCreated,
    modelPoseApplied: modelPoseApplied,
    modelActivationConfirmed: modelActivationConfirmed,
    renderCredibilityConfirmed: renderCredibilityConfirmed,
    native3dRendererActive: native3dRendererActive && eligibility.eligible,
  );
  final fallbackReason = resolveNav3dVehicleFallbackReason(
    eligibility: eligibility,
    featureEnabled: featureEnabled,
    assetLoaded: assetLoaded,
    modelRegistered: modelRegistered,
    layerCreated: layerCreated,
    modelPoseApplied: modelPoseApplied,
    registerInFlight: registerInFlight,
  );
  return Nav3dVehicleDiagnosticSnapshot(
    presentationActive: presentationActive,
    styleEligible: styleEligible,
    vehicleChoice: vehicleChoice,
    featureEnabled: featureEnabled,
    assetPath: driverVehicle3dAssetBundlePath(spec.assetUri),
    assetLoaded: assetLoaded,
    modelRegistered: modelRegistered,
    layerCreated: layerCreated,
    effectivelyActive: effectivelyActive,
    fallbackReason: fallbackReason,
  );
}

String? _lastNav3dVehicleDiagnosticSignature;

/// NAV-3D-VEHICLE-RESTORE-DIAG-1: bounded one-line activation diagnostics.
void logNav3dVehicleDiagnostic(Nav3dVehicleDiagnosticSnapshot snapshot) {
  if (snapshot.signature == _lastNav3dVehicleDiagnosticSignature) return;
  _lastNav3dVehicleDiagnosticSignature = snapshot.signature;
  debugPrint(
    '[NAV_3D_VEHICLE] presentationActive=${snapshot.presentationActive} '
    'styleEligible=${snapshot.styleEligible} '
    'vehicleChoice=${snapshot.vehicleChoice} '
    'featureEnabled=${snapshot.featureEnabled} '
    'assetPath=${snapshot.assetPath} '
    'assetLoaded=${snapshot.assetLoaded} '
    'modelRegistered=${snapshot.modelRegistered} '
    'layerCreated=${snapshot.layerCreated} '
    'effectivelyActive=${snapshot.effectivelyActive} '
    'fallbackReason=${nav3dVehicleFallbackReasonLabel(snapshot.fallbackReason)}',
  );
}

/// NAV-3D-VEHICLE-VISIBILITY-FAILSAFE-1: handoff gate snapshot for field logs.
class Nav3dVehicleHandoffSnapshot {
  const Nav3dVehicleHandoffSnapshot({
    required this.preset,
    required this.modelRegistered,
    required this.layerCreated,
    required this.sourceGeometryValid,
    required this.modelPoseApplied,
    required this.modelActivationConfirmed,
    required this.hudFallbackAllowedToHide,
    required this.hudTaxiHidden,
    required this.activeStyleGeneration,
    required this.activePresetGeneration,
    required this.confirmedStyleGeneration,
    required this.confirmedPresetGeneration,
    required this.styleModelId,
    required this.assetUri,
    required this.appliedScale,
    required this.appliedRotation,
    required this.appliedElevation,
  });

  final String preset;
  final bool modelRegistered;
  final bool layerCreated;
  final bool sourceGeometryValid;
  final bool modelPoseApplied;
  final bool modelActivationConfirmed;
  final bool hudFallbackAllowedToHide;
  final bool hudTaxiHidden;
  final int activeStyleGeneration;
  final int activePresetGeneration;
  final int confirmedStyleGeneration;
  final int confirmedPresetGeneration;
  final String styleModelId;
  final String assetUri;
  final String appliedScale;
  final String appliedRotation;
  final double appliedElevation;

  String get signature =>
      '$preset|$modelRegistered|$layerCreated|$sourceGeometryValid|'
      '$modelPoseApplied|$modelActivationConfirmed|$hudFallbackAllowedToHide|'
      '$hudTaxiHidden|$activeStyleGeneration|$activePresetGeneration|'
      '$confirmedStyleGeneration|$confirmedPresetGeneration';
}

String? _lastNav3dVehicleHandoffSignature;

void logNav3dVehicleHandoff(Nav3dVehicleHandoffSnapshot snapshot) {
  if (snapshot.signature == _lastNav3dVehicleHandoffSignature) return;
  _lastNav3dVehicleHandoffSignature = snapshot.signature;
  debugPrint(
    '[NAV_3D_VEHICLE_HANDOFF] preset=${snapshot.preset} '
    'modelRegistered=${snapshot.modelRegistered} '
    'layerCreated=${snapshot.layerCreated} '
    'sourceGeometryValid=${snapshot.sourceGeometryValid} '
    'modelPoseApplied=${snapshot.modelPoseApplied} '
    'modelActivationConfirmed=${snapshot.modelActivationConfirmed} '
    'hudFallbackAllowedToHide=${snapshot.hudFallbackAllowedToHide} '
    'hudTaxiHidden=${snapshot.hudTaxiHidden} '
    'styleGen=${snapshot.activeStyleGeneration}/${snapshot.confirmedStyleGeneration} '
    'presetGen=${snapshot.activePresetGeneration}/${snapshot.confirmedPresetGeneration} '
    'styleModelId=${snapshot.styleModelId} assetUri=${snapshot.assetUri} '
    'scale=${snapshot.appliedScale} rotation=${snapshot.appliedRotation} '
    'elevation=${snapshot.appliedElevation.toStringAsFixed(2)}',
  );
}

/// NAV-3D-DIAGNOSTIC-RECURSION-STACKOVERFLOW-1: gate log dedupe signature.
String driver3dVehicleGateLogSignature(Driver3dVehicleEligibility eligibility) {
  return '${eligibility.eligible}|${eligibility.reason}|'
      '${eligibility.presentation}|${eligibility.styleFamily}|'
      '${eligibility.modelReady}|${eligibility.fallback2d}|'
      '${eligibility.selectorVisible}|${eligibility.hudTaxiHidden}';
}

/// NAV-3D-DIAGNOSTIC-RECURSION-STACKOVERFLOW-1: one-way 3D diagnostic coordinator.
class Driver3dVehicleDiagnosticLogCoordinator {
  bool _isLogging = false;
  String? _lastGateSignature;

  /// Test hook invoked while [_isLogging] is true.
  @visibleForTesting
  void Function()? onDuringLogForTest;

  /// Test-visible counters — each should increment once per coordinator call.
  int coordinatorInvocations = 0;
  int gateLeafInvocations = 0;
  int diagnosticLeafInvocations = 0;
  int handoffLeafInvocations = 0;

  void logStateIfChanged({
    required Driver3dVehicleEligibility eligibility,
    required Nav3dVehicleDiagnosticSnapshot diagnosticSnapshot,
    required Nav3dVehicleHandoffSnapshot handoffSnapshot,
    String? handoffReason,
  }) {
    if (_isLogging) return;
    _isLogging = true;
    coordinatorInvocations++;
    try {
      onDuringLogForTest?.call();
      _logGateSnapshot(eligibility);
      _logDiagnosticSnapshot(diagnosticSnapshot);
      _logHandoffSnapshot(handoffSnapshot, handoffReason: handoffReason);
    } finally {
      _isLogging = false;
    }
  }

  void _logGateSnapshot(Driver3dVehicleEligibility eligibility) {
    gateLeafInvocations++;
    final signature = driver3dVehicleGateLogSignature(eligibility);
    if (signature == _lastGateSignature) return;
    _lastGateSignature = signature;
    logNav3dVehicleGate(eligibility);
  }

  void _logDiagnosticSnapshot(Nav3dVehicleDiagnosticSnapshot snapshot) {
    diagnosticLeafInvocations++;
    logNav3dVehicleDiagnostic(snapshot);
  }

  void _logHandoffSnapshot(
    Nav3dVehicleHandoffSnapshot snapshot, {
    String? handoffReason,
  }) {
    handoffLeafInvocations++;
    logNav3dVehicleHandoff(snapshot);
    if (handoffReason != null) {
      debugPrint('[NAV_3D_VEHICLE_HANDOFF] reason=$handoffReason');
    }
  }

  @visibleForTesting
  void resetForTest() {
    _isLogging = false;
    _lastGateSignature = null;
    coordinatorInvocations = 0;
    gateLeafInvocations = 0;
    diagnosticLeafInvocations = 0;
    handoffLeafInvocations = 0;
  }
}

/// NAV-PRES-3K-J / NAV-ASSET-3D-MODE-GATE-1: in-cockpit preset selector gate.
bool resolveShowDriverVehicle3dPresetSelector({
  required bool vehicleModelFlagEnabled,
  required bool cockpitSceneEnabled,
  required bool useDriverCockpitCamera,
  required bool useDriver3dVehicleModel,
  required bool liveNavigationActive,
  NavigationPresentationMode presentationMode =
      NavigationPresentationMode.driver,
  required bool followCamera,
  required String? activeStyleUri,
  required DriverMapVisualMode visualMode,
  required bool cockpitSceneActive,
  required DriverCockpitMapVisualStyle? cockpitVisualStyle,
  required bool sessionFallback2d,
  required bool styleLoaded,
  required bool styleSwapInProgress,
}) {
  if (!useDriver3dVehicleModel) return false;
  return resolveDriver3dVehicleEligibility(
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
    modelRegistered: false,
    modelPoseApplied: false,
    hideHudIsolationFlagEnabled: false,
  ).selectorVisible;
}

/// NAV-MOBILE-3D-SELECTOR-SCALE-AND-BOTTOM-PRIORITY-1: phone selector UI
/// capability gate.
///
/// Unlike the model eligibility gate above, this deliberately does not depend
/// on model activation/readiness, visual ownership, or a temporary 2D
/// fallback. A driver must be able to change vehicle while the selected model
/// is loading, active, or recovering. It only answers whether the live,
/// follow-navigation phone UI is currently in the dedicated 3D map context.
bool resolveShowDriverVehicle3dPhoneSelector({
  required bool vehicleModelFlagEnabled,
  required bool cockpitSceneEnabled,
  required bool useDriverCockpitCamera,
  required bool useDriver3dVehicleModel,
  required bool liveNavigationActive,
  required NavigationPresentationMode presentationMode,
  required bool followCamera,
  required String? activeStyleUri,
  required bool cockpitSceneActive,
  required DriverCockpitMapVisualStyle? cockpitVisualStyle,
}) {
  return vehicleModelFlagEnabled &&
      cockpitSceneEnabled &&
      useDriverCockpitCamera &&
      useDriver3dVehicleModel &&
      liveNavigationActive &&
      presentationMode == NavigationPresentationMode.driver &&
      followCamera &&
      cockpitSceneActive &&
      resolveDriver3dVehicleDedicatedCockpitChoiceActive(
        cockpitSceneEnabled: cockpitSceneEnabled,
        cockpitVisualStyle: cockpitVisualStyle,
      ) &&
      resolveDriver3dVehicleDedicatedStyleActive(
        activeStyleUri: activeStyleUri,
      );
}

/// NAV-PRES-3K-J: safe fallback when a preset asset fails to register.

DriverVehicle3dPreset resolveDriverVehicle3dPresetAfterRegistrationFailure({
  required DriverVehicle3dPreset requestedPreset,

  required bool registerSucceeded,
}) {
  if (registerSucceeded ||
      requestedPreset == DriverVehicle3dPreset.fluxidiTaxi) {
    return requestedPreset;
  }

  return DriverVehicle3dPreset.fluxidiTaxi;
}

/// NAV-ASSET-3D-SWAP-1: stable unique Mapbox style model id per preset.

String resolveDriverVehicle3dStyleModelId(DriverVehicle3dPreset preset) {
  switch (preset) {
    case DriverVehicle3dPreset.fluxidiTaxi:
      return kDriverVehicleFluxidiTaxiStyleModelId;

    case DriverVehicle3dPreset.classicFlyingTaxi:
      return kDriverVehicleClassicFlyingTaxiStyleModelId;
  }
}

/// NAV-ASSET-3D-SWAP-1: all registered style model ids (teardown/style restore).

List<String> allDriverVehicle3dStyleModelIds() {
  return const [
    kDriverVehicleFluxidiTaxiStyleModelId,

    kDriverVehicleClassicFlyingTaxiStyleModelId,
  ];
}

/// NAV-ASSET-3D-SWAP-1: ignore stale async swap completion.

bool shouldIgnoreStaleDriverVehicle3dSwap({
  required int requestGeneration,

  required int currentGeneration,
}) {
  return requestGeneration != currentGeneration;
}

/// NAV-ASSET-3D-SWAP-1: latest preset wins when swaps overlap.

DriverVehicle3dPreset resolveDriverVehicle3dPresetForOverlappingSwaps({
  required DriverVehicle3dPreset firstRequested,

  required DriverVehicle3dPreset secondRequested,
}) {
  return secondRequested;
}

/// NAV-PRES-3K-H4: piecewise zoom→scale calibration points (far → near).

const List<(double zoom, double scale)>
kDriverVehicleModelScaleCalibrationPoints = [
  (16.5, 10.8),

  (17.2, 9.2),

  (18.0, 7.2),

  (18.7, 5.8),

  (19.1, 5.0),

  (19.9, 3.8),

  (21.0, 2.75),
];

/// NAV-PRES-3K-H4: adaptive scale clamp bounds.

const double kDriverVehicleModelScaleMin = 2.4;

const double kDriverVehicleModelScaleMax = 11.5;

/// NAV-PRES-3K-D: base pitch (X) calibration in degrees.

const double kDriverVehicleModelBaseRotationXDeg = 0.0;

/// NAV-PRES-3K-D: base roll (Y) calibration in degrees.

const double kDriverVehicleModelBaseRotationYDeg = 0.0;

/// NAV-PRES-3K-D: heading offset added to route bearing (Z) in degrees.

const double kDriverVehicleModelHeadingOffsetDeg = 0.0;

/// NAV-PRES-3K-D: vertical lift in meters (model-translation altitude axis).

const double kDriverVehicleModelAltitudeMeters = 0.2;

/// NAV-PRES-3K-E: elevated altitude for debug placement visibility tests.

const double kDriverVehicleModelDebugAltitudeMeters = 3.0;

/// NAV-PRES-3K-E: cooldown between register retries after a native failure.

const int kDriverVehicleModelRegisterRetryCooldownMs = 2000;

/// NAV-PRES-3K-F: cooldown when style is not loaded yet (avoid register spam).

const int kDriverVehicleModelStyleNotLoadedCooldownMs = 500;

/// NAV-PRES-3K-F: impossible-to-miss style-layer debug dot radius (px).

const double kDriverVehicleDebugStyleDotRadius = 28.0;

/// NAV-PRES-3K-F: style-layer debug dot fill color (red).

const int kDriverVehicleDebugStyleDotColor = 0xFFFF1744;

/// NAV-PRES-3K-F: style-layer debug dot stroke color (white).

const int kDriverVehicleDebugStyleDotStrokeColor = 0xFFFFFFFF;

/// NAV-PRES-3K-F: style-layer debug dot stroke width (px).

const double kDriverVehicleDebugStyleDotStrokeWidth = 5.0;

/// NAV-PRES-3K-F: log label when ModelLayer uses direct asset URI (debug path).

const String kDriverVehicleModelIdModeDirectAsset = 'direct_asset';

/// NAV-PRES-3K-F: log label when ModelLayer uses registered style model id.

const String kDriverVehicleModelIdModeRegistered = 'registered_id';

/// NAV-PRES-3K-B: presentation-level gate (flag + cockpit camera profile).

bool resolveDriver3dVehicleModelPresentationActive({
  required bool flagEnabled,

  required bool useDriverCockpitCamera,
}) {
  return flagEnabled && useDriverCockpitCamera;
}

/// NAV-PRES-3K-B/G: follow-navigation runtime without style capability gate.

bool resolveDriver3dVehicleModelFollowRuntimeActive({
  required bool presentationActive,

  required bool liveRideActive,

  required bool followCamera,
}) {
  return presentationActive && liveRideActive && followCamera;
}

/// NAV-PRES-3K-G: true only when the active map style is dedicated 3D Standard.

bool resolveDriver3dVehicleModelStyleActive({
  required String? activeStyleUri,

  required DriverMapVisualMode visualMode,
}) {
  return resolveDriver3dVehicleDedicatedStyleActive(
    activeStyleUri: activeStyleUri,
  );
}

/// NAV-PRES-3K-G: effective 3D vehicle runtime (follow + 3D-capable style).

bool resolveDriver3dVehicleModelRuntimeActive({
  required bool presentationActive,

  required bool liveRideActive,

  required bool followCamera,

  required bool styleActive,
}) {
  return resolveDriver3dVehicleModelFollowRuntimeActive(
        presentationActive: presentationActive,

        liveRideActive: liveRideActive,

        followCamera: followCamera,
      ) &&
      styleActive;
}

/// NAV-PRES-3K-E: debug placement active (3D model + debug flag + cockpit).

bool resolveDriver3dVehicleDebugPlacementActive({
  required bool modelFlagEnabled,

  required bool debugPlacementFlagEnabled,

  required bool useDriverCockpitCamera,

  required bool isDriverMode,
}) {
  return isDriverMode &&
      modelFlagEnabled &&
      debugPlacementFlagEnabled &&
      useDriverCockpitCamera;
}

/// NAV-PRES-3K-E/F: show the style-layer debug dot at the model coordinate.

bool resolveShowDriver3dVehicleDebugDot({
  required bool debugPlacementActive,

  required bool runtimeActive,
}) {
  return debugPlacementActive && runtimeActive;
}

/// NAV-PRES-3K-F: alias for style-layer debug dot gate (tests/clarity).

bool resolveShowDriver3dVehicleDebugStyleDot({
  required bool debugPlacementActive,

  required bool runtimeActive,
}) {
  return resolveShowDriver3dVehicleDebugDot(
    debugPlacementActive: debugPlacementActive,

    runtimeActive: runtimeActive,
  );
}

/// NAV-PRES-3K-I/J: ModelLayer binds the bundled GLB via direct asset URI.
/// NAV-3D-REGRESSION-BISECT-LAST-WORKING-1: restored after registered-id swap regression.
String resolveDriverVehicleModelLayerModelId({
  required bool debugPlacementActive,
  DriverVehicle3dPreset preset = kDriverVehicle3dPresetDefault,
}) {
  return resolveDriverVehicle3dModelSpec(preset).assetUri;
}

/// NAV-PRES-3K-I: product path uses direct asset URI on the layer (no addStyleModel).
String resolveDriverVehicleModelIdModeLabel({
  required bool debugPlacementActive,
}) {
  if (resolveDriverVehicleModelRequiresStyleModelRegistration(
    debugPlacementActive: debugPlacementActive,
  )) {
    return kDriverVehicleModelIdModeRegistered;
  }

  return kDriverVehicleModelIdModeDirectAsset;
}

/// NAV-PRES-3K-I: skip addStyleModel; Mapbox Flutter local GLBs bind via asset:// on layer.
bool resolveDriverVehicleModelRequiresStyleModelRegistration({
  required bool debugPlacementActive,
}) {
  return false;
}

/// NAV-PRES-3K-I: placement mode label for bounded diagnostics.

String resolveDriverVehicleModelPlacementMode({
  required bool debugPlacementActive,

  required String placementSource,
}) {
  if (debugPlacementActive && placementSource == 'camera_center') {
    return 'camera_center';
  }

  return 'snapped_vehicle';
}

/// NAV-PRES-3K-F: resolved CircleLayer paint config for the debug style dot.

({
  double radius,

  int color,

  int strokeColor,

  double strokeWidth,

  mb.CirclePitchAlignment pitchAlignment,

  mb.CirclePitchScale pitchScale,
})
resolveDriverVehicleDebugStyleDotLayerConfig() {
  return (
    radius: kDriverVehicleDebugStyleDotRadius,

    color: kDriverVehicleDebugStyleDotColor,

    strokeColor: kDriverVehicleDebugStyleDotStrokeColor,

    strokeWidth: kDriverVehicleDebugStyleDotStrokeWidth,

    pitchAlignment: mb.CirclePitchAlignment.VIEWPORT,

    pitchScale: mb.CirclePitchScale.VIEWPORT,
  );
}

/// NAV-PRES-3K-F: skip register attempts while style is still loading.

bool resolveDriverVehicleModelShouldSkipForStyleNotLoaded({
  required bool styleLoaded,

  required DateTime? lastStyleNotLoadedSkipAt,

  required DateTime now,

  int cooldownMs = kDriverVehicleModelStyleNotLoadedCooldownMs,
}) {
  if (styleLoaded) return false;

  if (lastStyleNotLoadedSkipAt == null) return true;

  return now.difference(lastStyleNotLoadedSkipAt).inMilliseconds < cooldownMs;
}

/// NAV-PRES-3K-F: after a failed register, registered state must be cleared.

bool resolveDriverVehicleModelRegisteredAfterFailure({
  required bool registerSucceeded,
}) {
  return registerSucceeded;
}

/// NAV-PRES-2B: hide Mapbox taxi when HUD overlay suppression is active.

bool resolveHideMapboxTaxiMarkerForPresentation({
  required bool hideForHudOverlay,

  required bool useDriver3dVehicleModel,
}) {
  return hideForHudOverlay;
}

/// NAV-ASSET-3D-MODE-GATE-1: runtime Mapbox taxi suppression after 3D handoff.

bool resolveHideMapboxTaxiMarkerFor3dVehicleRuntime({
  required bool hideForHudOverlay,

  required bool driver3dVehicleModelActuallyActive,
}) {
  return hideForHudOverlay || driver3dVehicleModelActuallyActive;
}

/// NAV-ASSET-3D-MODE-GATE-1: derive runtime taxi suppression from eligibility.

bool resolveHideMapboxTaxiMarkerFromEligibility({
  required bool hideForHudOverlay,
  required Driver3dVehicleEligibility eligibility,
}) {
  return resolveHideMapboxTaxiMarkerFor3dVehicleRuntime(
    hideForHudOverlay: hideForHudOverlay,
    driver3dVehicleModelActuallyActive: eligibility.mapbox2dTaxiHidden,
  );
}

/// NAV-PRES-3K-C: hide HUD vehicle icon only when 3D model intent + isolation flag.

bool resolveHideDriverHudVehicleFor3dVisualIsolation({
  required bool driver3dVehicleModelEnabled,

  required bool driver3dVehicleHideHudEnabled,

  required bool useDriverCockpitCamera,

  required bool isDriverMode,
}) {
  return isDriverMode &&
      driver3dVehicleModelEnabled &&
      driver3dVehicleHideHudEnabled &&
      useDriverCockpitCamera;
}

/// NAV-ASSET-3D-MODE-GATE-1: runtime HUD hide only after confirmed 3D handoff.

bool resolveHideDriverHudVehicleFor3dVisualIsolationRuntime({
  required bool driver3dVehicleModelActuallyActive,

  required bool driver3dVehicleHideHudEnabled,

  required bool useDriverCockpitCamera,

  required bool isDriverMode,
}) {
  return driver3dVehicleModelActuallyActive &&
      driver3dVehicleHideHudEnabled &&
      useDriverCockpitCamera &&
      isDriverMode;
}

/// NAV-ASSET-3D-MODE-GATE-1: derive runtime HUD hide from eligibility.
///
/// When [hideHudFlagEnabled], [useDriverCockpitCamera], and [presentationMode]
/// are supplied, recomputes the hide gate from the eligibility snapshot using
/// the presentation context at the final render decision (avoids stale
/// [Driver3dVehicleEligibility.hudTaxiHidden] baked under a different frame).
bool resolveHideDriverHudVehicleFromEligibility({
  required Driver3dVehicleEligibility eligibility,
  bool? hideHudFlagEnabled,
  bool? useDriverCockpitCamera,
  NavigationPresentationMode? presentationMode,
}) {
  if (hideHudFlagEnabled == null &&
      useDriverCockpitCamera == null &&
      presentationMode == null) {
    return eligibility.hudTaxiHidden;
  }
  return resolveDriver3dVehicleHudTaxiHidden(
    driver3dVisualReady: eligibility.driver3dVisualReady,
    hideHudIsolationFlagEnabled: hideHudFlagEnabled ?? false,
    useDriverCockpitCamera: useDriverCockpitCamera ?? false,
    presentationMode: presentationMode ?? NavigationPresentationMode.overview,
  );
}

/// Whether the screen-fixed HUD vehicle widget should render.

bool resolveShowDriverHudVehicleOverlay({
  required bool showDriverHudOverlay,

  required bool hideDriverHudVehicleOverlay,
}) {
  return showDriverHudOverlay && !hideDriverHudVehicleOverlay;
}

/// NAV-3D-HUD-ACTUAL-VISIBILITY-FIX-2: 3D presentation active for HUD render gate.
bool resolveNav3dPresentationActive({
  required bool eligible,
  required bool useDriver3dVehicleModel,
  required bool followLiveActive,
}) {
  return followLiveActive && eligible && useDriver3dVehicleModel;
}

/// NAV-3D-HUD-ACTUAL-VISIBILITY-FIX-2: keep confirmed handoff latched while
/// observational [assetLoaded] flickers after the ModelLayer is already visible.
bool resolveNav3dHandoffAssetLoadedForRender({
  required bool observationalAssetLoaded,
  required bool modelRegistered,
  required bool modelActivationConfirmed,
}) {
  return observationalAssetLoaded ||
      (modelRegistered && modelActivationConfirmed);
}

/// NAV-3D-HUD-OWNERSHIP-FINAL-1: final hide gate wired to visual-ready ownership.
bool resolveNav3dHudShouldHide({
  required bool hideHudFlagEnabled,
  required bool driver3dVisualReady,
}) {
  return hideHudFlagEnabled && driver3dVisualReady;
}

/// NAV-3D-HUD-ACTUAL-VISIBILITY-FIX-2: final yellow HUD widget mount boolean.
bool resolveNav3dHudActualVisible({
  required bool showDriverHudOverlay,
  required bool followLiveActive,
  required bool shouldHideHud,
}) {
  return followLiveActive && showDriverHudOverlay && !shouldHideHud;
}

/// NAV-3D-HUD-OWNERSHIP-FINAL-1: final Mapbox 2D taxi visibility from owner.
bool resolveNav3dMapbox2dTaxiVisible({
  required bool followLiveActive,
  required bool explicit2dFallback,
  required DriverVisualOwner owner,
}) {
  if (!followLiveActive) return true;
  if (explicit2dFallback) return true;
  return owner == DriverVisualOwner.mapbox2d;
}

/// NAV-3D-HUD-OWNERSHIP-FINAL-1: build visual-ready + health signals for render.
({
  bool presentation3dActive,
  bool driver3dVisualReady,
  bool effectivelyActive,
  bool hudFallbackAllowedToHide,
  DriverVisualOwnership ownership,
}) resolveNav3dHudHandoffForRender({
  required Driver3dVehicleEligibility eligibility,
  required bool useDriver3dVehicleModel,
  required bool followLiveActive,
  required bool observationalAssetLoaded,
  required bool handoffAssetLoaded,
  required bool modelRegistered,
  required bool layerCreated,
  required bool sourceGeometryValid,
  required bool modelPoseApplied,
  required bool modelActivationConfirmed,
  required bool renderCredibilityConfirmed,
  required int activeStyleGeneration,
  required int activePresetGeneration,
  required int modelLayerStyleGeneration,
  required int modelLayerPresetGeneration,
  required int confirmedStyleGeneration,
  required int confirmedPresetGeneration,
  required bool showDriverHudOverlay,
  required bool hideHudFlagEnabled,
  required bool explicit2dFallback,
  bool debugRenderProbeActive = false,
  // NAV-3D-VEHICLE-CHOICE-3WAY-1: explicit vehicle presentation choice.
  DriverVehiclePresentationChoice? selectedVehiclePresentation,
  // NAV-3D-P0-PERSISTENT-VEHICLE-OWNERSHIP-1
  bool native3dRendererActive = false,
}) {
  final presentation3dActive = resolveNav3dPresentationActive(
    eligible: eligibility.eligible,
    useDriver3dVehicleModel: useDriver3dVehicleModel,
    followLiveActive: followLiveActive,
  );
  final requested3d = selectedVehiclePresentation == null
      ? true
      : driverVehiclePresentationChoiceIs3d(selectedVehiclePresentation);
  final nativeOwns =
      native3dRendererActive && requested3d && eligibility.eligible;
  final driver3dVisualReady = resolveDriver3dVisualReady(
    followLiveActive: followLiveActive,
    presentation3dActive: presentation3dActive,
    eligible: eligibility.eligible,
    modelFeatureEnabled: true,
    modelRegistered: modelRegistered,
    layerCreated: layerCreated,
    sourceGeometryValid: sourceGeometryValid,
    modelPoseApplied: modelPoseApplied,
    activeStyleGeneration: activeStyleGeneration,
    activePresetGeneration: activePresetGeneration,
    modelLayerStyleGeneration: modelLayerStyleGeneration,
    modelLayerPresetGeneration: modelLayerPresetGeneration,
    explicit2dFallback: explicit2dFallback,
    debugRenderProbeActive: debugRenderProbeActive,
    native3dRendererActive: nativeOwns,
  );
  final effectivelyActive = resolveNav3dVehicleEffectivelyActive(
    eligible: eligibility.eligible,
    assetLoaded: handoffAssetLoaded,
    modelRegistered: modelRegistered,
    layerCreated: layerCreated,
    modelPoseApplied: modelPoseApplied,
    modelActivationConfirmed: modelActivationConfirmed,
    renderCredibilityConfirmed: renderCredibilityConfirmed,
    native3dRendererActive: nativeOwns,
  );
  final hudFallbackAllowedToHide = resolveDriver3dVehicleHudFallbackAllowedToHide(
    eligible: eligibility.eligible,
    assetLoaded: handoffAssetLoaded,
    modelRegistered: modelRegistered,
    layerCreated: layerCreated,
    sourceGeometryValid: sourceGeometryValid,
    modelPoseApplied: modelPoseApplied,
    modelActivationConfirmed: modelActivationConfirmed,
    renderCredibilityConfirmed: renderCredibilityConfirmed,
    activeStyleGeneration: activeStyleGeneration,
    activePresetGeneration: activePresetGeneration,
    confirmedStyleGeneration: confirmedStyleGeneration,
    confirmedPresetGeneration: confirmedPresetGeneration,
    debugRenderProbeActive: debugRenderProbeActive,
    native3dRendererActive: nativeOwns,
  );
  final ownership = resolveDriverVisualOwnership(
    followLiveActive: followLiveActive,
    showDriverHudOverlay: showDriverHudOverlay,
    hideHudFlagEnabled: hideHudFlagEnabled,
    driver3dVisualReady: driver3dVisualReady,
    explicit2dFallback: explicit2dFallback,
    selectedVehiclePresentation: selectedVehiclePresentation,
    presentation3dIntentActive: presentation3dActive,
  );
  return (
    presentation3dActive: presentation3dActive,
    driver3dVisualReady: driver3dVisualReady,
    effectivelyActive: effectivelyActive,
    hudFallbackAllowedToHide: hudFallbackAllowedToHide,
    ownership: ownership,
  );
}

/// NAV-3D-HUD-OWNERSHIP-FINAL-1: final HUD + Mapbox 2D taxi render decision.
class Nav3dHudRenderDecision {
  const Nav3dHudRenderDecision({
    required this.hideFlag,
    required this.presentation3d,
    required this.driver3dVisualReady,
    required this.effectivelyActive,
    required this.hudFallbackAllowedToHide,
    required this.owner,
    required this.shouldHideHud,
    required this.actualHudVisible,
    required this.mapbox2dVisible,
    required this.visibleDriverVisualCount,
    required this.reason,
  });

  final bool hideFlag;
  final bool presentation3d;
  final bool driver3dVisualReady;
  final bool effectivelyActive;
  final bool hudFallbackAllowedToHide;
  final DriverVisualOwner owner;
  final bool shouldHideHud;
  final bool actualHudVisible;
  final bool mapbox2dVisible;
  final int visibleDriverVisualCount;
  final String reason;

  /// Back-compat for FIX-1 callers/tests.
  bool get hideDriverHudVehicleOverlay => shouldHideHud;

  String get diagnosticSignature =>
      '$hideFlag|$presentation3d|$driver3dVisualReady|$effectivelyActive|'
      '$hudFallbackAllowedToHide|${owner.name}|$shouldHideHud|'
      '$actualHudVisible|$mapbox2dVisible|$visibleDriverVisualCount|$reason';

  String get sourceDiagnosticSignature =>
      '$actualHudVisible|$mapbox2dVisible|$driver3dVisualReady|'
      '${owner.name}|$hideFlag|$reason';
}

/// NAV-3D-HUD-OWNERSHIP-FINAL-1: authoritative final yellow-taxi visibility.
Nav3dHudRenderDecision resolveNav3dHudRenderDecision({
  required bool hideHudFlagEnabled,
  required bool presentation3dActive,
  required bool driver3dVisualReady,
  required bool effectivelyActive,
  required bool hudFallbackAllowedToHide,
  required bool showDriverHudOverlay,
  required bool followLiveActive,
  required bool explicit2dFallback,
  DriverVisualOwnership? ownership,
  // NAV-3D-VEHICLE-CHOICE-3WAY-1: explicit vehicle presentation choice.
  DriverVehiclePresentationChoice? selectedVehiclePresentation,
}) {
  final resolvedOwnership = ownership ??
      resolveDriverVisualOwnership(
        followLiveActive: followLiveActive,
        showDriverHudOverlay: showDriverHudOverlay,
        hideHudFlagEnabled: hideHudFlagEnabled,
        driver3dVisualReady: driver3dVisualReady,
        explicit2dFallback: explicit2dFallback,
        selectedVehiclePresentation: selectedVehiclePresentation,
        presentation3dIntentActive: presentation3dActive,
      );
  final shouldHideHud = resolveNav3dHudShouldHide(
    hideHudFlagEnabled: hideHudFlagEnabled,
    driver3dVisualReady: driver3dVisualReady,
  );
  final actualHudVisible = resolvedOwnership.hudMounted;
  final mapbox2dVisible = resolveNav3dMapbox2dTaxiVisible(
    followLiveActive: followLiveActive,
    explicit2dFallback: explicit2dFallback,
    owner: resolvedOwnership.owner,
  );
  final reason = resolveNav3dHudRenderReason(
    followLiveActive: followLiveActive,
    showDriverHudOverlay: showDriverHudOverlay,
    hideHudFlagEnabled: hideHudFlagEnabled,
    driver3dVisualReady: driver3dVisualReady,
    explicit2dFallback: explicit2dFallback,
    shouldHideHud: shouldHideHud,
    actualHudVisible: actualHudVisible,
    owner: resolvedOwnership.owner,
  );
  return Nav3dHudRenderDecision(
    hideFlag: hideHudFlagEnabled,
    presentation3d: presentation3dActive,
    driver3dVisualReady: driver3dVisualReady,
    effectivelyActive: effectivelyActive,
    hudFallbackAllowedToHide: hudFallbackAllowedToHide,
    owner: resolvedOwnership.owner,
    shouldHideHud: shouldHideHud,
    actualHudVisible: actualHudVisible,
    mapbox2dVisible: mapbox2dVisible,
    visibleDriverVisualCount: resolvedOwnership.visibleDriverVisualCount,
    reason: reason,
  );
}

/// Bounded reason token for [Nav3dHudRenderDecision].
String resolveNav3dHudRenderReason({
  required bool followLiveActive,
  required bool showDriverHudOverlay,
  required bool hideHudFlagEnabled,
  required bool driver3dVisualReady,
  required bool explicit2dFallback,
  required bool shouldHideHud,
  required bool actualHudVisible,
  required DriverVisualOwner owner,
}) {
  if (!followLiveActive) {
    return 'not_follow_live';
  }
  if (!showDriverHudOverlay) {
    return 'hud_overlay_disabled';
  }
  if (explicit2dFallback) {
    return 'explicit_2d_fallback';
  }
  if (shouldHideHud) {
    return 'model3d_visual_ready';
  }
  if (actualHudVisible) {
    if (!hideHudFlagEnabled) {
      return 'hide_flag_disabled';
    }
    if (driver3dVisualReady) {
      return 'unexpected_hud_with_3d_ready';
    }
    return 'hud2d_fallback';
  }
  if (owner == DriverVisualOwner.mapbox2d) {
    return 'mapbox2d_owner';
  }
  if (owner == DriverVisualOwner.model3d && !driver3dVisualReady) {
    // NAV-3D-INSTANT-SWITCH-SCALE-AND-HEADING-POLISH-1: explicit 3D
    // selection suppressed both 2D visuals in the same interaction.
    return 'model3d_selected_pending';
  }
  return 'hud_hidden';
}

String? _lastNav3dHudRenderLogSignature;

/// NAV-3D-HUD-ACTUAL-VISIBILITY-FIX-2: bounded final widget-mount diagnostics.
void logNav3dHudRenderDecision(Nav3dHudRenderDecision decision) {
  if (decision.diagnosticSignature == _lastNav3dHudRenderLogSignature) {
    return;
  }
  _lastNav3dHudRenderLogSignature = decision.diagnosticSignature;
  debugPrint(
    '[NAV_3D_HUD_RENDER] hideFlag=${decision.hideFlag} '
    'presentation3d=${decision.presentation3d} '
    'driver3dVisualReady=${decision.driver3dVisualReady} '
    'effectivelyActive=${decision.effectivelyActive} '
    'hudFallbackAllowedToHide=${decision.hudFallbackAllowedToHide} '
    'owner=${decision.owner.name} '
    'actualHudVisible=${decision.actualHudVisible} '
    'reason=${decision.reason}',
  );
}

/// NAV-PRES-3K-E: whether another register attempt is allowed.

bool resolveDriverVehicleModelCanAttemptRegister({
  required bool registered,

  required bool registerInFlight,

  required DateTime? lastFailureAt,

  required DateTime now,

  int cooldownMs = kDriverVehicleModelRegisterRetryCooldownMs,
}) {
  if (registered || registerInFlight) return false;

  if (lastFailureAt == null) return true;

  return now.difference(lastFailureAt).inMilliseconds >= cooldownMs;
}

/// NAV-PRES-3K-E: choose a guaranteed-visible model anchor for debug only.

({double lon, double lat, String placementSource})
resolveDriverVehicleModelDebugPlacementCoordinate({
  required bool debugPlacementActive,

  required double visualLon,

  required double visualLat,

  required String visualSource,

  double? cameraCenterLon,

  double? cameraCenterLat,

  required bool visualOnScreen,
}) {
  if (!debugPlacementActive) {
    return (lon: visualLon, lat: visualLat, placementSource: visualSource);
  }

  if (cameraCenterLon != null &&
      cameraCenterLat != null &&
      cameraCenterLon.isFinite &&
      cameraCenterLat.isFinite) {
    return (
      lon: cameraCenterLon,

      lat: cameraCenterLat,

      placementSource: 'camera_center',
    );
  }

  if (visualOnScreen) {
    return (lon: visualLon, lat: visualLat, placementSource: visualSource);
  }

  return (
    lon: visualLon,

    lat: visualLat,

    placementSource: '${visualSource}_offscreen_fallback',
  );
}

/// NAV-PRES-3K-E: screen pixel inside viewport bounds (no PII).

bool resolveDriverVehicleScreenOnViewport({
  required double screenX,

  required double screenY,

  required double viewportWidth,

  required double viewportHeight,

  double marginPx = 0,
}) {
  if (viewportWidth <= 0 || viewportHeight <= 0) return false;

  return screenX >= marginPx &&
      screenY >= marginPx &&
      screenX <= viewportWidth - marginPx &&
      screenY <= viewportHeight - marginPx;
}

String formatDriverVehicleViewportForLog({
  required double width,

  required double height,
}) {
  return '${width.round()}x${height.round()}';
}

/// NAV-PRES-3K-E: lift model higher only while debug placement is active.

double resolveDriverVehicleModelAltitudeMeters({
  bool debugPlacementActive = false,
}) {
  if (debugPlacementActive) {
    return kDriverVehicleModelDebugAltitudeMeters;
  }

  return kDriverVehicleModelAltitudeMeters;
}

/// Normalize bearing to [0, 360) for model-rotation Z axis.

double normalizeDriverVehicleModelBearingDeg(double bearingDeg) {
  var bearing = bearingDeg % 360;

  if (bearing < 0) {
    bearing += 360;
  }

  return bearing;
}

/// NAV-PRES-3K-D: route bearing + heading offset, normalized.

double resolveDriverVehicleModelHeadingDeg({
  required double routeBearingDeg,

  double headingOffsetDeg = kDriverVehicleModelHeadingOffsetDeg,
}) {
  return normalizeDriverVehicleModelBearingDeg(
    routeBearingDeg + headingOffsetDeg,
  );
}

/// NAV-PRES-3K-H4: piecewise zoom scale.

double resolveDriverVehicleModelScaleFromZoom(double appliedZoom) {
  final points = kDriverVehicleModelScaleCalibrationPoints;

  if (points.isEmpty) {
    return kDriverVehicleModelScaleMax;
  }

  if (appliedZoom <= points.first.$1) {
    return points.first.$2;
  }

  if (appliedZoom >= points.last.$1) {
    return points.last.$2;
  }

  for (var i = 0; i < points.length - 1; i++) {
    final z0 = points[i].$1;

    final s0 = points[i].$2;

    final z1 = points[i + 1].$1;

    final s1 = points[i + 1].$2;

    if (appliedZoom >= z0 && appliedZoom <= z1) {
      final span = z1 - z0;

      if (span <= 0) {
        return s1;
      }

      final t = (appliedZoom - z0) / span;

      return s0 + (s1 - s0) * t;
    }
  }

  return points.last.$2;
}

/// NAV-PRES-3K-H4: adaptive uniform model scale from applied camera state.

List<double> resolveDriverVehicleModelScale({
  required double appliedZoom,

  required double appliedPitch,
}) {
  final scale = resolveDriverVehicleModelScaleFromZoom(
    appliedZoom,
  ).clamp(kDriverVehicleModelScaleMin, kDriverVehicleModelScaleMax);

  return [scale, scale, scale];
}

/// NAV-3D-INSTANT-SWITCH-SCALE-AND-HEADING-POLISH-1: screen-footprint scale.
///
/// One centralized zoom-aware resolver for both 3D presets. The target is a
/// projected on-screen footprint (px): at zoomed-out navigation views the 3D
/// vehicle starts near the 2D HUD taxi footprint, grows smoothly through mid
/// zoom, and is hard capped at street level.
const double kNav3dScaleFootprintLowPx = 94.0;

const double kNav3dScaleFootprintHighPx = 170.0;

const double kNav3dScaleFootprintLowZoom = 17.0;

const double kNav3dScaleFootprintHighZoom = 20.5;

/// Calibrated pixels→model-scale conversion base: combines Mercator
/// meters-per-pixel at navigation latitudes with the GLB base footprint so
/// that `scale = targetPx * base / 2^zoom` keeps mid-level continuity with
/// the previous known-good cockpit calibration (≈5.0 at zoom 19.1).
const double kNav3dScalePxToScaleBase = 19600.0;

/// Hard clamp bounds for the footprint scale (never unbounded linear growth).
const double kNav3dScaleHardMin = 0.9;

const double kNav3dScaleHardMax = 30.0;

/// Preset-specific footprint calibration multipliers (GLB files unchanged).
///
/// The classic GLB has a smaller authored bounding footprint than the Fluxidi
/// GLB. This 1.20 calibration restores equivalent perceived screen size while
/// preserving the shared smooth zoom curve and its hard min/max clamp.
const double kNav3dClassicFootprintMultiplier = 1.20;

double nav3dFootprintMultiplierForPreset(DriverVehicle3dPreset preset) {
  switch (preset) {
    case DriverVehicle3dPreset.fluxidiTaxi:
      return 1.0;
    case DriverVehicle3dPreset.classicFlyingTaxi:
      return kNav3dClassicFootprintMultiplier;
  }
}

/// Smoothstep target footprint (px) for [appliedZoom]: 2D-taxi footprint at
/// low zoom, gradual growth through mid zoom, capped street-level presence.
double resolveNav3dTargetFootprintPx(double appliedZoom) {
  final span = kNav3dScaleFootprintHighZoom - kNav3dScaleFootprintLowZoom;
  final t = span <= 0
      ? 1.0
      : ((appliedZoom - kNav3dScaleFootprintLowZoom) / span).clamp(0.0, 1.0);
  final smooth = t * t * (3 - 2 * t);
  return kNav3dScaleFootprintLowPx +
      (kNav3dScaleFootprintHighPx - kNav3dScaleFootprintLowPx) * smooth;
}

/// NAV-3D-INSTANT-SWITCH-SCALE-AND-HEADING-POLISH-1: resolved footprint scale.
class DriverVehicle3dScaleResolution {
  const DriverVehicle3dScaleResolution({
    required this.preset,
    required this.zoom,
    required this.viewLevel,
    required this.targetFootprintPx,
    required this.baseScale,
    required this.resolvedScale,
    required this.minScale,
    required this.maxScale,
  });

  final DriverVehicle3dPreset preset;
  final double zoom;
  final int? viewLevel;
  final double targetFootprintPx;
  final double baseScale;
  final double resolvedScale;
  final double minScale;
  final double maxScale;
}

String? _lastNav3dScaleLogSignature;

/// NAV-3D-INSTANT-SWITCH-SCALE-AND-HEADING-POLISH-1: bounded scale diagnostics.
void logNav3dScale(DriverVehicle3dScaleResolution resolution) {
  final signature =
      '${driverVehicle3dPresetLogLabel(resolution.preset)}|'
      '${resolution.zoom.toStringAsFixed(1)}|'
      '${resolution.viewLevel ?? 'na'}|'
      '${resolution.resolvedScale.toStringAsFixed(2)}';
  if (signature == _lastNav3dScaleLogSignature) return;
  _lastNav3dScaleLogSignature = signature;
  debugPrint(
    '[NAV_3D_SCALE] '
    'preset=${driverVehicle3dPresetLogLabel(resolution.preset)} '
    'zoom=${resolution.zoom.toStringAsFixed(2)} '
    'viewLevel=${resolution.viewLevel ?? 'na'} '
    'baseScale=${resolution.baseScale.toStringAsFixed(3)} '
    'resolvedScale=${resolution.resolvedScale.toStringAsFixed(3)} '
    'minScale=${resolution.minScale} '
    'maxScale=${resolution.maxScale}',
  );
}

/// Single centralized zoom-aware footprint scale resolver for both presets.
DriverVehicle3dScaleResolution resolveDriverVehicle3dFootprintScale({
  required double appliedZoom,
  required DriverVehicle3dPreset preset,
  int? viewLevel,
}) {
  final targetFootprintPx = resolveNav3dTargetFootprintPx(appliedZoom);
  final baseScale =
      targetFootprintPx * kNav3dScalePxToScaleBase / math.pow(2, appliedZoom);
  final calibrated = baseScale *
      nav3dFootprintMultiplierForPreset(preset) *
      resolveDriverVehicle3dModelSpec(preset).scaleMultiplier;
  final resolvedScale =
      calibrated.clamp(kNav3dScaleHardMin, kNav3dScaleHardMax);
  return DriverVehicle3dScaleResolution(
    preset: preset,
    zoom: appliedZoom,
    viewLevel: viewLevel,
    targetFootprintPx: targetFootprintPx,
    baseScale: baseScale,
    resolvedScale: resolvedScale,
    minScale: kNav3dScaleHardMin,
    maxScale: kNav3dScaleHardMax,
  );
}

/// NAV-PRES-3K-J: uniform model scale for the selected preset.
///
/// NAV-3D-INSTANT-SWITCH-SCALE-AND-HEADING-POLISH-1: now backed by the
/// centralized screen-footprint resolver (debug overrides preserved).
List<double> resolveDriverVehicleModelScaleForPreset({
  required double appliedZoom,

  required double appliedPitch,

  required DriverVehicle3dPreset preset,

  bool debugPlacementActive = false,
  double? debugProbeScale,
  int? viewLevel,
}) {
  if (debugProbeScale != null && debugProbeScale > 0) {
    return [debugProbeScale, debugProbeScale, debugProbeScale];
  }

  final debugScale = debugPlacementActive
      ? navigation3dVehicleDebugScaleOverride()
      : null;
  if (debugScale != null && debugScale > 0) {
    return [debugScale, debugScale, debugScale];
  }

  final resolution = resolveDriverVehicle3dFootprintScale(
    appliedZoom: appliedZoom,
    preset: preset,
    viewLevel: viewLevel,
  );
  logNav3dScale(resolution);
  final value = resolution.resolvedScale;
  return [value, value, value];
}

/// NAV-PRES-3K-J: altitude from preset spec (debug placement keeps debug lift).

double resolveDriverVehicleModelAltitudeMetersForPreset({
  required bool debugPlacementActive,

  required DriverVehicle3dPreset preset,
  double? debugProbeAltitude,
}) {
  if (debugProbeAltitude != null && debugProbeAltitude.isFinite) {
    return debugProbeAltitude;
  }
  final debugElevation = debugPlacementActive
      ? navigation3dVehicleDebugElevationOverrideMeters()
      : null;
  if (debugElevation != null) {
    return debugElevation;
  }
  if (debugPlacementActive) {
    return kDriverVehicleModelDebugAltitudeMeters;
  }

  return resolveDriverVehicle3dModelSpec(preset).altitudeMeters;
}

/// NAV-PRES-3K-J: model-translation using preset altitude.

List<double> driverVehicleModelTranslationForPreset({
  bool debugPlacementActive = false,

  required DriverVehicle3dPreset preset,
  double? debugProbeAltitude,
}) {
  return [
    0.0,

    0.0,

    resolveDriverVehicleModelAltitudeMetersForPreset(
      debugPlacementActive: debugPlacementActive,

      preset: preset,
      debugProbeAltitude: debugProbeAltitude,
    ),
  ];
}

/// NAV-3D-ORIENTATION-AND-PRODUCTION-HANDOFF-2: canonical orientation pipeline
/// result (raw bearing → normalized bearing → preset offset → final rotation).
class DriverVehicle3dOrientationResolution {
  const DriverVehicle3dOrientationResolution({
    required this.rawNavigationBearing,
    required this.normalizedBearingDeg,
    required this.presetOffsetDeg,
    required this.finalRotation,
  });

  final double rawNavigationBearing;
  final double normalizedBearingDeg;
  final double presetOffsetDeg;
  final List<double> finalRotation;
}

/// Single authoritative resolver for all 3D vehicle model rotations.
DriverVehicle3dOrientationResolution resolveDriverVehicle3dModelOrientation({
  required double rawNavigationBearing,
  required DriverVehicle3dPreset preset,
  double baseRotationXDeg = kDriverVehicleModelBaseRotationXDeg,
  double baseRotationYDeg = kDriverVehicleModelBaseRotationYDeg,
  bool debugPlacementActive = false,
}) {
  final spec = resolveDriverVehicle3dModelSpec(preset);
  final debugYaw = debugPlacementActive
      ? navigation3dVehicleDebugYawOffsetDeg()
      : null;
  final presetOffsetDeg = spec.headingOffsetDeg + (debugYaw ?? 0.0);
  final normalizedBearingDeg = normalizeDriverVehicleModelBearingDeg(
    rawNavigationBearing,
  );
  final finalRotation = resolveDriverVehicleModelFinalRotation(
    rawNavigationBearing,
    baseRotationXDeg: baseRotationXDeg,
    baseRotationYDeg: baseRotationYDeg,
    headingOffsetDeg: presetOffsetDeg,
  );
  return DriverVehicle3dOrientationResolution(
    rawNavigationBearing: rawNavigationBearing,
    normalizedBearingDeg: normalizedBearingDeg,
    presetOffsetDeg: presetOffsetDeg,
    finalRotation: finalRotation,
  );
}

String? _lastNav3dOrientationLogSignature;

/// NAV-3D-ORIENTATION-AND-PRODUCTION-HANDOFF-2: bounded orientation diagnostics.
void logNav3dOrientation({
  required String source,
  required DriverVehicle3dPreset preset,
  required double rawBearing,
  required double presetOffset,
  required List<double> finalRotation,
  required int styleGeneration,
  required int presetGeneration,
}) {
  final signature =
      '$source|${driverVehicle3dPresetLogLabel(preset)}|'
      '${rawBearing.toStringAsFixed(1)}|'
      '${presetOffset.toStringAsFixed(1)}|'
      '${formatDriverVehicleModelRotationForLog(finalRotation)}|'
      '$styleGeneration|$presetGeneration';
  if (signature == _lastNav3dOrientationLogSignature) return;
  _lastNav3dOrientationLogSignature = signature;
  debugPrint(
    '[NAV_3D_ORIENTATION] source=$source '
    'preset=${driverVehicle3dPresetLogLabel(preset)} '
    'rawBearing=${rawBearing.toStringAsFixed(1)} '
    'presetOffset=${presetOffset.toStringAsFixed(1)} '
    'finalRotation=${formatDriverVehicleModelRotationForLog(finalRotation)} '
    'styleGeneration=$styleGeneration '
    'presetGeneration=$presetGeneration',
  );
}

/// NAV-3D-INSTANT-SWITCH-SCALE-AND-HEADING-POLISH-1: canonical model heading.
///
/// Every pose request funnels through [resolveNav3dModelHeadingForPose] so
/// that exactly one canonical travel bearing controls model yaw:
///   1. trusted route-locked / snapped travel bearing while navigating,
///   2. reliable movement course bearing,
///   3. last stable valid heading.
/// Camera bearing never becomes vehicle heading: camera/zoom-scale updates
/// preserve the last stable heading instead of adopting the camera value.
class Nav3dModelHeadingResolution {
  const Nav3dModelHeadingResolution({
    required this.bearingDeg,
    required this.headingSource,
    required this.updatesStable,
    required this.reason,
  });

  /// Canonical travel bearing (pre preset-offset) to use for the pose.
  final double bearingDeg;

  /// route_snapped | movement_course | last_stable | none
  final String headingSource;

  /// True when this bearing may become the new last stable heading.
  final bool updatesStable;

  final String reason;
}

/// Camera/zoom-scale driven pose sources must never rewrite the heading.
bool nav3dPoseSourcePreservesHeading(String source) {
  return source.startsWith('camera_scale');
}

/// Route-locked / snapped / engine-derived sources are trusted travel
/// bearings and may change heading freely (including genuine reversals).
bool nav3dPoseSourceIsRouteTrusted(String source) {
  final s = source.toLowerCase();
  return s.contains('route') ||
      s.contains('snap') ||
      s.contains('engine') ||
      s.contains('nav_visual') ||
      s.contains('predict');
}

/// Shortest angular distance between two bearings in degrees [0, 180].
double nav3dHeadingAngularDeltaDeg(double a, double b) {
  final na = normalizeDriverVehicleModelBearingDeg(a);
  final nb = normalizeDriverVehicleModelBearingDeg(b);
  var delta = (na - nb).abs();
  if (delta > 180) delta = 360 - delta;
  return delta;
}

/// Rejects a suspicious instantaneous ~180° flip from an untrusted course
/// bearing on the same route segment (GPS noise), while trusted route/snap
/// updates stay free to reverse.
const double kNav3dHeadingCourseFlipRejectDeg = 150.0;

Nav3dModelHeadingResolution resolveNav3dModelHeadingForPose({
  required double requestedBearingDeg,
  required String source,
  double? lastStableBearingDeg,
}) {
  final hasStable =
      lastStableBearingDeg != null && lastStableBearingDeg.isFinite;
  final stable = hasStable
      ? normalizeDriverVehicleModelBearingDeg(lastStableBearingDeg)
      : null;
  if (nav3dPoseSourcePreservesHeading(source)) {
    if (stable != null) {
      return Nav3dModelHeadingResolution(
        bearingDeg: stable,
        headingSource: 'last_stable',
        updatesStable: false,
        reason: 'camera_scale_preserves_heading',
      );
    }
    // No stable heading yet: fall through and treat as a normal update.
  }
  if (!requestedBearingDeg.isFinite) {
    return Nav3dModelHeadingResolution(
      bearingDeg: stable ?? 0.0,
      headingSource: stable != null ? 'last_stable' : 'none',
      updatesStable: false,
      reason: 'invalid_bearing',
    );
  }
  final normalized = normalizeDriverVehicleModelBearingDeg(
    requestedBearingDeg,
  );
  final routeTrusted = nav3dPoseSourceIsRouteTrusted(source);
  if (!routeTrusted && stable != null) {
    final delta = nav3dHeadingAngularDeltaDeg(normalized, stable);
    if (delta >= kNav3dHeadingCourseFlipRejectDeg) {
      return Nav3dModelHeadingResolution(
        bearingDeg: stable,
        headingSource: 'last_stable',
        updatesStable: false,
        reason: 'course_flip_rejected',
      );
    }
  }
  return Nav3dModelHeadingResolution(
    bearingDeg: normalized,
    headingSource: routeTrusted ? 'route_snapped' : 'movement_course',
    updatesStable: true,
    reason: 'travel_update',
  );
}

String? _lastNav3dHeadingLogSignature;

/// NAV-3D-INSTANT-SWITCH-SCALE-AND-HEADING-POLISH-1: bounded heading trace.
void logNav3dHeading({
  required String source,
  required double rawBearing,
  required double stableBearing,
  required DriverVehicle3dPreset preset,
  required double presetOffset,
  required double finalYaw,
  required String reason,
}) {
  final signature =
      '$source|${rawBearing.toStringAsFixed(1)}|'
      '${stableBearing.toStringAsFixed(1)}|'
      '${driverVehicle3dPresetLogLabel(preset)}|$reason';
  if (signature == _lastNav3dHeadingLogSignature) return;
  _lastNav3dHeadingLogSignature = signature;
  debugPrint(
    '[NAV_3D_HEADING] source=$source '
    'rawBearing=${rawBearing.toStringAsFixed(1)} '
    'stableBearing=${stableBearing.toStringAsFixed(1)} '
    'preset=${driverVehicle3dPresetLogLabel(preset)} '
    'presetOffset=${presetOffset.toStringAsFixed(1)} '
    'finalYaw=${finalYaw.toStringAsFixed(1)} '
    'reason=$reason',
  );
}

/// Resolve + log before every native model-rotation write.
List<double> resolveDriverVehicleModelRotationForWrite({
  required double rawNavigationBearing,
  required DriverVehicle3dPreset preset,
  required String source,
  bool debugPlacementActive = false,
  int styleGeneration = -1,
  int presetGeneration = -1,
}) {
  final resolution = resolveDriverVehicle3dModelOrientation(
    rawNavigationBearing: rawNavigationBearing,
    preset: preset,
    debugPlacementActive: debugPlacementActive,
  );
  logNav3dOrientation(
    source: source,
    preset: preset,
    rawBearing: resolution.rawNavigationBearing,
    presetOffset: resolution.presetOffsetDeg,
    finalRotation: resolution.finalRotation,
    styleGeneration: styleGeneration,
    presetGeneration: presetGeneration,
  );
  return resolution.finalRotation;
}

/// NAV-PRES-3K-J: final rotation using preset heading offset.

List<double> resolveDriverVehicleModelFinalRotationForPreset(
  double routeBearingDeg, {

  required DriverVehicle3dPreset preset,

  double baseRotationXDeg = kDriverVehicleModelBaseRotationXDeg,

  double baseRotationYDeg = kDriverVehicleModelBaseRotationYDeg,

  bool debugPlacementActive = false,
}) {
  return resolveDriverVehicle3dModelOrientation(
    rawNavigationBearing: routeBearingDeg,
    preset: preset,
    baseRotationXDeg: baseRotationXDeg,
    baseRotationYDeg: baseRotationYDeg,
    debugPlacementActive: debugPlacementActive,
  ).finalRotation;
}

/// NAV-PRES-3K-D: Mapbox model-rotation [pitch X, roll Y, heading Z] in degrees.

List<double> resolveDriverVehicleModelFinalRotation(
  double routeBearingDeg, {

  double baseRotationXDeg = kDriverVehicleModelBaseRotationXDeg,

  double baseRotationYDeg = kDriverVehicleModelBaseRotationYDeg,

  double headingOffsetDeg = kDriverVehicleModelHeadingOffsetDeg,
}) {
  return [
    baseRotationXDeg,

    baseRotationYDeg,

    resolveDriverVehicleModelHeadingDeg(
      routeBearingDeg: routeBearingDeg,

      headingOffsetDeg: headingOffsetDeg,
    ),
  ];
}

/// Back-compat alias used by earlier NAV-PRES-3K-B tests/callers.

List<double> driverVehicleModelRotation(double bearingDeg) {
  return resolveDriverVehicleModelFinalRotation(bearingDeg);
}

/// NAV-PRES-3K-D/E: model-translation [longitudinal, latitudinal, altitude] meters.

List<double> driverVehicleModelTranslation({
  bool debugPlacementActive = false,
}) {
  return [
    0.0,

    0.0,

    resolveDriverVehicleModelAltitudeMeters(
      debugPlacementActive: debugPlacementActive,
    ),
  ];
}

/// NAV-PRES-3K-F: GeoJSON Point matching the official Mapbox Flutter example.
/// NAV-3D-REGRESSION-BISECT-LAST-WORKING-1: bare Point (not FeatureCollection).
String driverVehicleModelGeoJsonData({
  required double lon,
  required double lat,
}) {
  return json.encode(mb.Point(coordinates: mb.Position(lon, lat)));
}

/// NAV-3D-RENDER-VISIBILITY-PROOF-1: parsed GeoJSON source snapshot.
class Nav3dVehicleRenderSourceParse {
  const Nav3dVehicleRenderSourceParse({
    required this.sourceFeaturePresent,
    required this.sourceHasValidPosition,
    this.sourceModelId,
    this.sourceLon,
    this.sourceLat,
  });

  final bool sourceFeaturePresent;
  final bool sourceHasValidPosition;
  final String? sourceModelId;
  final double? sourceLon;
  final double? sourceLat;

  static const empty = Nav3dVehicleRenderSourceParse(
    sourceFeaturePresent: false,
    sourceHasValidPosition: false,
  );
}

Nav3dVehicleRenderSourceParse parseDriverVehicleModelSourceJson(String? raw) {
  if (raw == null || raw.trim().isEmpty) {
    return Nav3dVehicleRenderSourceParse.empty;
  }
  try {
    final decoded = json.decode(raw);
    if (decoded is! Map) {
      return Nav3dVehicleRenderSourceParse.empty;
    }
    Map<String, dynamic>? feature;
    if (decoded['type'] == 'FeatureCollection') {
      final features = decoded['features'];
      if (features is List && features.isNotEmpty && features.first is Map) {
        feature = Map<String, dynamic>.from(features.first as Map);
      }
    } else if (decoded['type'] == 'Feature') {
      feature = Map<String, dynamic>.from(decoded);
    } else if (decoded['type'] == 'Point') {
      feature = {
        'type': 'Feature',
        'geometry': decoded,
        'properties': <String, dynamic>{},
      };
    }
    if (feature == null) {
      return Nav3dVehicleRenderSourceParse.empty;
    }
    final geometry = feature['geometry'];
    if (geometry is! Map || geometry['type'] != 'Point') {
      return Nav3dVehicleRenderSourceParse(
        sourceFeaturePresent: true,
        sourceHasValidPosition: false,
      );
    }
    final coords = geometry['coordinates'];
    double? lon;
    double? lat;
    if (coords is List && coords.length >= 2) {
      lon = (coords[0] as num?)?.toDouble();
      lat = (coords[1] as num?)?.toDouble();
    }
    String? sourceModelId;
    final properties = feature['properties'];
    if (properties is Map) {
      final rawModelId = properties['model-id'] ?? properties['modelId'];
      if (rawModelId is String && rawModelId.trim().isNotEmpty) {
        sourceModelId = rawModelId.trim();
      }
    }
    final hasValidPosition = lon != null &&
        lat != null &&
        lon.isFinite &&
        lat.isFinite &&
        !(lon == 0 && lat == 0);
    return Nav3dVehicleRenderSourceParse(
      sourceFeaturePresent: true,
      sourceHasValidPosition: hasValidPosition,
      sourceModelId: sourceModelId,
      sourceLon: lon,
      sourceLat: lat,
    );
  } catch (_) {
    return Nav3dVehicleRenderSourceParse.empty;
  }
}

/// NAV-3D-RENDER-VISIBILITY-PROOF-1: style readback snapshot.
class Nav3dVehicleRenderReadback {
  const Nav3dVehicleRenderReadback({
    required this.layerExists,
    required this.sourceExists,
    required this.layerVisible,
    required this.sourceFeaturePresent,
    required this.sourceHasValidPosition,
    required this.modelIdBound,
    required this.sourceModelIdBound,
    this.layerModelId,
    this.sourceModelId,
    this.layerVisibility,
    this.sourceLon,
    this.sourceLat,
    this.layerScale,
    this.layerTranslation,
    this.layerRotation,
    this.minZoom,
    this.maxZoom,
    this.slot,
    this.modelOpacity,
    this.modelEmissiveStrength,
  });

  final bool layerExists;
  final bool sourceExists;
  final bool layerVisible;
  final bool sourceFeaturePresent;
  final bool sourceHasValidPosition;
  final bool modelIdBound;
  final bool sourceModelIdBound;
  final String? layerModelId;
  final String? sourceModelId;
  final String? layerVisibility;
  final double? sourceLon;
  final double? sourceLat;
  final List<double>? layerScale;
  final List<double>? layerTranslation;
  final List<double>? layerRotation;
  final double? minZoom;
  final double? maxZoom;
  final String? slot;
  final double? modelOpacity;
  final double? modelEmissiveStrength;

  static const empty = Nav3dVehicleRenderReadback(
    layerExists: false,
    sourceExists: false,
    layerVisible: false,
    sourceFeaturePresent: false,
    sourceHasValidPosition: false,
    modelIdBound: false,
    sourceModelIdBound: false,
  );
}

bool resolveNav3dVehicleLayerVisibilityVisible(String? visibility) {
  if (visibility == null || visibility.trim().isEmpty) return true;
  return visibility.trim().toLowerCase() != 'none';
}

bool resolveNav3dVehicleModelIdBound({
  required String? actualModelId,
  required String expectedModelId,
}) {
  if (actualModelId == null || actualModelId.trim().isEmpty) return false;
  return actualModelId.trim() == expectedModelId.trim();
}

bool resolveNav3dVehicleRenderCredibility({
  required Nav3dVehicleRenderReadback readback,
  required bool assetLoaded,
  required bool modelPoseApplied,
}) {
  if (!assetLoaded || !modelPoseApplied) return false;
  if (!readback.layerExists || !readback.sourceExists) return false;
  if (!readback.layerVisible) return false;
  if (!readback.modelIdBound) return false;
  if (!readback.sourceFeaturePresent) return false;
  if (!readback.sourceHasValidPosition) return false;
  return true;
}

double haversineDistanceMeters(
  double lon1,
  double lat1,
  double lon2,
  double lat2,
) {
  const earthRadiusM = 6371000.0;
  final dLat = (lat2 - lat1) * math.pi / 180.0;
  final dLon = (lon2 - lon1) * math.pi / 180.0;
  final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(lat1 * math.pi / 180.0) *
          math.cos(lat2 * math.pi / 180.0) *
          math.sin(dLon / 2) *
          math.sin(dLon / 2);
  final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  return earthRadiusM * c;
}

double? boundedPositionDeltaM({
  required double? fromLon,
  required double? fromLat,
  required double? toLon,
  required double? toLat,
}) {
  if (fromLon == null ||
      fromLat == null ||
      toLon == null ||
      toLat == null ||
      !fromLon.isFinite ||
      !fromLat.isFinite ||
      !toLon.isFinite ||
      !toLat.isFinite) {
    return null;
  }
  final delta = haversineDistanceMeters(fromLon, fromLat, toLon, toLat);
  return delta.isFinite ? delta : null;
}

List<double>? _parseStyleDoubleList(Object? value) {
  if (value is! List) return null;
  final parsed = <double>[];
  for (final item in value) {
    if (item is num) {
      parsed.add(item.toDouble());
    } else {
      return null;
    }
  }
  return parsed.isEmpty ? null : parsed;
}

double? _parseStyleDouble(Object? value) {
  if (value is num) return value.toDouble();
  return null;
}

String? _parseStyleString(Object? value) {
  if (value is String && value.trim().isNotEmpty) return value.trim();
  return null;
}

/// NAV-3D-RENDER-VISIBILITY-PROOF-1: debug-only scale/altitude probe sequence.
const List<double> kNav3dVehicleDebugScaleProbes = [5, 15, 50, 150];
const List<double> kNav3dVehicleDebugAltitudeProbes = [0.2, 2, 10];

class Nav3dVehicleDebugRenderProbeScheduler {
  int _index = 0;

  ({double scale, double altitude}) advance() {
    final scaleIdx = _index ~/ kNav3dVehicleDebugAltitudeProbes.length;
    var altIdx = _index % kNav3dVehicleDebugAltitudeProbes.length;
    var normalizedScaleIdx = scaleIdx;
    if (normalizedScaleIdx >= kNav3dVehicleDebugScaleProbes.length) {
      _index = 0;
      normalizedScaleIdx = 0;
      altIdx = 0;
    }
    final probe = (
      scale: kNav3dVehicleDebugScaleProbes[normalizedScaleIdx],
      altitude: kNav3dVehicleDebugAltitudeProbes[altIdx],
    );
    _index++;
    return probe;
  }

  @visibleForTesting
  void resetForTest() {
    _index = 0;
  }
}

String? _lastNav3dRenderProofSignature;

void logNav3dRenderProof({
  required String action,
  required String preset,
  required String modelId,
  required bool layerVisible,
  required bool sourceFeaturePresent,
  required bool modelIdBound,
  double? positionDeltaM,
  double? scale,
  double? altitude,
  double? zoom,
  double? minZoom,
  double? maxZoom,
  String? slot,
  required bool assetLoaded,
  String? reason,
}) {
  final signature =
      '$action|$preset|$modelId|$layerVisible|$sourceFeaturePresent|'
      '$modelIdBound|${positionDeltaM?.toStringAsFixed(1)}|'
      '${scale?.toStringAsFixed(2)}|${altitude?.toStringAsFixed(2)}|'
      '${zoom?.toStringAsFixed(1)}|$minZoom|$maxZoom|$slot|$assetLoaded|'
      '${reason ?? ''}';
  if (signature == _lastNav3dRenderProofSignature) return;
  _lastNav3dRenderProofSignature = signature;
  debugPrint(
    '[NAV_3D_RENDER_PROOF] action=$action preset=$preset modelId=$modelId '
    'layerVisible=$layerVisible sourceFeaturePresent=$sourceFeaturePresent '
    'modelIdBound=$modelIdBound'
    '${positionDeltaM != null ? ' positionDeltaM=${positionDeltaM.toStringAsFixed(1)}' : ''}'
    '${scale != null ? ' scale=${scale.toStringAsFixed(2)}' : ''}'
    '${altitude != null ? ' altitude=${altitude.toStringAsFixed(2)}' : ''}'
    '${zoom != null ? ' zoom=${zoom.toStringAsFixed(1)}' : ''}'
    '${minZoom != null ? ' minZoom=$minZoom' : ''}'
    '${maxZoom != null ? ' maxZoom=$maxZoom' : ''}'
    '${slot != null ? ' slot=$slot' : ''}'
    ' assetLoaded=$assetLoaded'
    '${reason != null ? ' reason=$reason' : ''}',
  );
}

/// NAV-PRES-3K-F: bounded error text for register/update failures.

String formatNavPres3dVehicleError(Object error) {
  if (error is PlatformException) {
    final code = error.code.trim();

    final message = (error.message ?? '').trim();

    final details = error.details?.toString().trim() ?? '';

    final buffer = StringBuffer('PlatformException');

    if (code.isNotEmpty) {
      buffer.write(' code=$code');
    }

    if (message.isNotEmpty) {
      buffer.write(' message=$message');
    }

    if (details.isNotEmpty) {
      buffer.write(' details=$details');
    }

    return buffer.toString();
  }

  return error.toString();
}

String formatDriverVehicleModelScaleForLog(List<double> scale) {
  if (scale.isEmpty) return 'empty';

  return scale.map((v) => v.toStringAsFixed(2)).join(',');
}

String formatDriverVehicleModelBaseRotForLog() {
  return '${kDriverVehicleModelBaseRotationXDeg.toStringAsFixed(1)},'
      '${kDriverVehicleModelBaseRotationYDeg.toStringAsFixed(1)}';
}

String formatDriverVehicleModelRotationForLog(List<double> rotation) {
  return rotation.map((v) => v.toStringAsFixed(1)).join(',');
}

/// Bounded non-PII diagnostics for the 3D vehicle model layer.

void logNavPres3dVehicle({
  required String action,

  required String result,

  String? reason,

  String? source,

  double? bearing,

  String? asset,

  String? modelIdMode,

  bool? modelActive,

  bool? hudVehicleHidden,

  bool? mapbox2dTaxiSuppressed,

  String? finalRotation,

  String? baseRot,

  double? headingOffset,

  double? altitude,

  bool? layerExists,

  bool? sourceExists,

  String? layerType,

  double? screenX,

  double? screenY,

  bool? onScreen,

  String? viewport,

  List<double>? scale,

  bool? debugPlacement,
}) {
  final signature = [
    action,

    result,

    reason ?? '',

    source ?? '',

    bearing?.round() ?? '',

    asset ?? '',

    modelIdMode ?? '',

    modelActive ?? '',

    hudVehicleHidden ?? '',

    mapbox2dTaxiSuppressed ?? '',

    finalRotation ?? '',

    baseRot ?? '',

    headingOffset?.toStringAsFixed(1) ?? '',

    altitude?.toStringAsFixed(2) ?? '',

    layerExists ?? '',

    sourceExists ?? '',

    layerType ?? '',

    screenX?.round() ?? '',

    screenY?.round() ?? '',

    onScreen ?? '',

    viewport ?? '',

    scale == null ? '' : formatDriverVehicleModelScaleForLog(scale),

    debugPlacement ?? '',
  ].join('|');

  if (signature == _lastNavPres3dVehicleLogSignature) return;

  _lastNavPres3dVehicleLogSignature = signature;

  final buffer = StringBuffer(
    '[NAV_PRES_3D_VEHICLE] action=$action result=$result',
  );

  if (modelActive != null) {
    buffer.write(' modelActive=$modelActive');
  }

  if (hudVehicleHidden != null) {
    buffer.write(' hudVehicleHidden=$hudVehicleHidden');
  }

  if (mapbox2dTaxiSuppressed != null) {
    buffer.write(' mapbox2dTaxiSuppressed=$mapbox2dTaxiSuppressed');
  }

  if (layerExists != null) {
    buffer.write(' layer=$layerExists');
  }

  if (sourceExists != null) {
    if (action == 'verify' || action == 'debug_style_dot_verify') {
      buffer.write(' source=$sourceExists');
    } else {
      buffer.write(' sourceExists=$sourceExists');
    }
  }

  if (layerType != null && layerType.isNotEmpty) {
    buffer.write(' type=$layerType');
  }

  if (screenX != null && screenX.isFinite) {
    buffer.write(' screenX=${screenX.round()}');
  }

  if (screenY != null && screenY.isFinite) {
    buffer.write(' screenY=${screenY.round()}');
  }

  if (onScreen != null) {
    buffer.write(' onScreen=$onScreen');
  }

  if (viewport != null && viewport.isNotEmpty) {
    buffer.write(' viewport=$viewport');
  }

  if (reason != null && reason.isNotEmpty) {
    buffer.write(' reason=$reason');
  }

  if (asset != null && asset.isNotEmpty) {
    buffer.write(' asset=$asset');
  }

  if (modelIdMode != null && modelIdMode.isNotEmpty) {
    buffer.write(' modelIdMode=$modelIdMode');
  }

  if (baseRot != null && baseRot.isNotEmpty) {
    buffer.write(' baseRot=$baseRot');
  }

  if (headingOffset != null && headingOffset.isFinite) {
    buffer.write(' headingOffset=${headingOffset.toStringAsFixed(1)}');
  }

  if (altitude != null && altitude.isFinite) {
    buffer.write(' altitude=${altitude.toStringAsFixed(2)}');
  }

  if (source != null && source.isNotEmpty && action != 'verify') {
    buffer.write(' source=$source');
  }

  if (bearing != null && bearing.isFinite) {
    buffer.write(' bearing=${bearing.round()}');
  }

  if (finalRotation != null && finalRotation.isNotEmpty) {
    buffer.write(' finalRotation=$finalRotation');
  }

  if ((action == 'update' || action == 'register') && scale != null) {
    buffer.write(' scale=${formatDriverVehicleModelScaleForLog(scale)}');
  }

  if (action == 'register' && debugPlacement != null) {
    buffer.write(' debugPlacement=$debugPlacement');
  }

  debugPrint(buffer.toString());
}

/// NAV-PRES-3K-J: bounded preset selection diagnostics (no lat/lng).

void logNavPres3dVehiclePresetSelected({
  required DriverVehicle3dPreset preset,

  required String assetUri,
}) {
  debugPrint(
    '[NAV_PRES_3D_VEHICLE] action=preset_selected '
    'preset=${driverVehicle3dPresetLogLabel(preset)} asset=$assetUri',
  );
}

/// NAV-PRES-3K-J: bounded preset register diagnostics.

void logNavPres3dVehiclePresetRegister({
  required DriverVehicle3dPreset preset,

  required String result,

  required String assetUri,
}) {
  debugPrint(
    '[NAV_PRES_3D_VEHICLE] action=preset_register '
    'preset=${driverVehicle3dPresetLogLabel(preset)} result=$result '
    'modelIdMode=$kDriverVehicleModelIdModeRegistered '
    'modelId=${resolveDriverVehicle3dStyleModelId(preset)} asset=$assetUri',
  );
}

/// NAV-ASSET-3D-SWAP-1: bounded vehicle swap diagnostics (no lat/lng).

void logNav3dVehicleSwap({
  required String phase,

  required DriverVehicle3dPreset preset,

  required int generation,

  String? modelId,

  int? durationMs,

  String? reason,
}) {
  final buffer = StringBuffer(
    '[NAV_3D_VEHICLE_SWAP] phase=$phase '
    'vehicle=${driverVehicle3dPresetLogLabel(preset)} generation=$generation',
  );

  if (modelId != null && modelId.isNotEmpty) {
    buffer.write(' modelId=$modelId');
  }

  if (durationMs != null) {
    buffer.write(' durationMs=$durationMs');
  }

  if (reason != null && reason.isNotEmpty) {
    buffer.write(' reason=$reason');
  }

  debugPrint(buffer.toString());
}

/// NAV-ASSET-3D-SYNC-1: preferred movement sync interval (10 Hz).

const int kDriverVehicleModelMovementPreferredIntervalMs = 100;

/// NAV-ASSET-3D-SYNC-1: minimum gap between movement updates (15 Hz cap).

const int kDriverVehicleModelMovementMinimumIntervalMs = 67;

/// NAV-ASSET-3D-SYNC-1: in-flight movement update timeout.

const int kDriverVehicleModelMovementTimeoutMs = 500;

/// NAV-ASSET-3D-SYNC-1: consecutive failures before 2D session fallback.

const int kDriverVehicleModelMovementMaxConsecutiveFailures = 3;

/// NAV-ASSET-3D-SYNC-1: optional registered-state health check cadence.

const int kDriverVehicleModelMovementHealthCheckIntervalMs = 1000;

/// NAV-ASSET-3D-SYNC-1: position delta below which native GeoJSON is skipped.

const double kDriverVehicleModelMovementPositionThresholdM = 0.4;

/// NAV-ASSET-3D-SYNC-1: bearing delta below which rotation write is skipped.

const double kDriverVehicleModelMovementBearingThresholdDeg = 1.5;

/// NAV-ASSET-3D-SYNC-1: scale delta below which model-scale write is skipped.

const double kDriverVehicleModelMovementScaleThreshold = 0.05;

/// NAV-ASSET-3D-SYNC-1: result of a bounded movement-only native update.

enum DriverVehicleModelMovementUpdateResult {
  applied,

  skippedUnchanged,

  notRegistered,

  staleMovement,

  failed,
}

/// NAV-3D-VEHICLE-VISIBILITY-FAILSAFE-1: movement outcome with pose-write detail.
class DriverVehicleModelMovementOutcome {
  const DriverVehicleModelMovementOutcome({
    required this.result,
    this.positionWritten = false,
    this.rotationWritten = false,
    this.scaleWritten = false,
    this.translationWritten = false,
  });

  final DriverVehicleModelMovementUpdateResult result;
  final bool positionWritten;
  final bool rotationWritten;
  final bool scaleWritten;
  final bool translationWritten;

  bool get anyPropertyWritten =>
      positionWritten || rotationWritten || scaleWritten || translationWritten;
}

/// NAV-ASSET-3D-SYNC-1: latest coalesced movement pose (no coordinates in logs).

class DriverVehicle3dMovementPose {
  const DriverVehicle3dMovementPose({
    required this.lon,
    required this.lat,
    required this.bearingDeg,
    required this.source,
    required this.appliedZoom,
    required this.appliedPitch,
    required this.preset,
    required this.movementGeneration,
  });

  final double lon;

  final double lat;

  final double bearingDeg;

  final String source;

  final double appliedZoom;

  final double appliedPitch;

  final DriverVehicle3dPreset preset;

  final int movementGeneration;
}

/// NAV-ASSET-3D-SYNC-1: cached last-applied movement values for skip logic.

class DriverVehicleModelAppliedMovementState {
  const DriverVehicleModelAppliedMovementState({
    this.lon,
    this.lat,
    this.bearingDeg,
    this.preset,
    this.scale,
    this.translation,
    this.rotation,
  });

  final double? lon;

  final double? lat;

  final double? bearingDeg;

  /// NAV-3D-ORIENTATION-AND-PRODUCTION-HANDOFF-2: preset used for last rotation.
  final DriverVehicle3dPreset? preset;

  final List<double>? scale;

  final List<double>? translation;

  final List<double>? rotation;

  DriverVehicleModelAppliedMovementState copyWith({
    double? lon,
    double? lat,
    double? bearingDeg,
    DriverVehicle3dPreset? preset,
    List<double>? scale,
    List<double>? translation,
    List<double>? rotation,
  }) {
    return DriverVehicleModelAppliedMovementState(
      lon: lon ?? this.lon,
      lat: lat ?? this.lat,
      bearingDeg: bearingDeg ?? this.bearingDeg,
      preset: preset ?? this.preset,
      scale: scale ?? this.scale,
      translation: translation ?? this.translation,
      rotation: rotation ?? this.rotation,
    );
  }
}

/// NAV-ASSET-3D-SYNC-1: approximate meters between two WGS84 points.

double driverVehicleModelMovementDistanceMeters({
  required double fromLat,
  required double fromLon,
  required double toLat,
  required double toLon,
}) {
  const earthRadiusM = 6371000.0;
  final lat1 = fromLat * (3.141592653589793 / 180.0);
  final lat2 = toLat * (3.141592653589793 / 180.0);
  final dLat = (toLat - fromLat) * (3.141592653589793 / 180.0);
  final dLon = (toLon - fromLon) * (3.141592653589793 / 180.0);
  final a =
      (math.sin(dLat / 2) * math.sin(dLat / 2)) +
      math.cos(lat1) *
          math.cos(lat2) *
          (math.sin(dLon / 2) * math.sin(dLon / 2));
  final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  return earthRadiusM * c;
}

/// NAV-ASSET-3D-SYNC-1: shortest signed bearing delta in degrees.

double driverVehicleModelMovementBearingDeltaDeg(double fromDeg, double toDeg) {
  var delta = (toDeg - fromDeg) % 360.0;
  if (delta > 180.0) delta -= 360.0;
  if (delta < -180.0) delta += 360.0;
  return delta.abs();
}

bool driverVehicleModelMovementListNear(
  List<double>? left,
  List<double>? right, {
  required double threshold,
}) {
  if (left == null || right == null) return false;
  if (left.length != right.length) return false;
  for (var i = 0; i < left.length; i++) {
    if ((left[i] - right[i]).abs() > threshold) return false;
  }
  return true;
}

/// NAV-ASSET-3D-SYNC-1: whether any native write is needed for this pose.

({
  bool positionChanged,
  bool rotationChanged,
  bool scaleChanged,
  bool translationChanged,
})
resolveDriverVehicleModelMovementWritePlan({
  required DriverVehicleModelAppliedMovementState? applied,
  required double lon,
  required double lat,
  required double bearingDeg,
  required DriverVehicle3dPreset preset,
  required List<double> scale,
  required List<double> translation,
  required List<double> rotation,
  bool force = false,
  double positionThresholdM = kDriverVehicleModelMovementPositionThresholdM,
  double bearingThresholdDeg = kDriverVehicleModelMovementBearingThresholdDeg,
  double scaleThreshold = kDriverVehicleModelMovementScaleThreshold,
}) {
  if (force || applied == null) {
    return (
      positionChanged: true,
      rotationChanged: true,
      scaleChanged: true,
      translationChanged: true,
    );
  }

  final positionChanged =
      applied.lon == null ||
      applied.lat == null ||
      driverVehicleModelMovementDistanceMeters(
            fromLat: applied.lat!,
            fromLon: applied.lon!,
            toLat: lat,
            toLon: lon,
          ) >=
          positionThresholdM;

  final rotationChanged =
      applied.preset != preset ||
      applied.bearingDeg == null ||
      driverVehicleModelMovementBearingDeltaDeg(
            applied.bearingDeg!,
            bearingDeg,
          ) >=
          bearingThresholdDeg ||
      !driverVehicleModelMovementListNear(
        applied.rotation,
        rotation,
        threshold: bearingThresholdDeg,
      );

  final scaleChanged = !driverVehicleModelMovementListNear(
    applied.scale,
    scale,
    threshold: scaleThreshold,
  );

  final translationChanged = !driverVehicleModelMovementListNear(
    applied.translation,
    translation,
    threshold: scaleThreshold,
  );

  return (
    positionChanged: positionChanged,
    rotationChanged: rotationChanged,
    scaleChanged: scaleChanged,
    translationChanged: translationChanged,
  );
}

bool driverVehicleModelMovementRequiresNativeUpdate({
  required DriverVehicleModelAppliedMovementState? applied,
  required double lon,
  required double lat,
  required double bearingDeg,
  required DriverVehicle3dPreset preset,
  required List<double> scale,
  required List<double> translation,
  required List<double> rotation,
  bool force = false,
}) {
  final plan = resolveDriverVehicleModelMovementWritePlan(
    applied: applied,
    lon: lon,
    lat: lat,
    bearingDeg: bearingDeg,
    preset: preset,
    scale: scale,
    translation: translation,
    rotation: rotation,
    force: force,
  );
  return plan.positionChanged ||
      plan.rotationChanged ||
      plan.scaleChanged ||
      plan.translationChanged;
}

String? _lastNav3dVehicleSyncLogSignature;

String? _lastNav3dFirstPoseLogSignature;

String? _lastNav3dFirstActivationLogSignature;

String? _lastNav3d2dSourceLogSignature;

/// NAV-3D-FIRST-ACTIVATION-AND-REAL-2D-OVERLAY-FIX-1: bounded first-activation
/// diagnostics across register → first pose → native write → confirm.
void logNav3dFirstActivation({
  required String event,
  required int styleGeneration,
  required int presetGeneration,
  required bool registered,
  required bool layerCreated,
  required bool posePending,
  required bool movementQueued,
  required bool movementInFlight,
  required int movementGeneration,
  required bool writeExecuted,
  required String reason,
}) {
  final signature =
      '$event|$styleGeneration|$presetGeneration|$registered|$layerCreated|'
      '$posePending|$movementQueued|$movementInFlight|$movementGeneration|'
      '$writeExecuted|$reason';
  if (signature == _lastNav3dFirstActivationLogSignature) return;
  _lastNav3dFirstActivationLogSignature = signature;
  debugPrint(
    '[NAV_3D_FIRST_ACTIVATION] event=$event '
    'styleGeneration=$styleGeneration presetGeneration=$presetGeneration '
    'registered=$registered layerCreated=$layerCreated posePending=$posePending '
    'movementQueued=$movementQueued movementInFlight=$movementInFlight '
    'movementGeneration=$movementGeneration writeExecuted=$writeExecuted '
    'reason=$reason',
  );
}

/// NAV-3D-FIRST-ACTIVATION-AND-REAL-2D-OVERLAY-FIX-1: final 2D taxi source trace.
void logNav3d2dSource({
  required bool hudMounted,
  required bool hudActualVisible,
  required bool mapboxMarkerExists,
  required double? mapboxMarkerOpacity,
  required bool mapbox2dVisible,
  required bool presentation3d,
  required bool effectivelyActive,
  required bool hudFallbackAllowedToHide,
  required bool hideHudFlag,
  required String reason,
}) {
  final opacityLabel = mapboxMarkerOpacity?.toStringAsFixed(2) ?? 'null';
  final signature =
      '$hudMounted|$hudActualVisible|$mapboxMarkerExists|$opacityLabel|'
      '$mapbox2dVisible|$presentation3d|$effectivelyActive|'
      '$hudFallbackAllowedToHide|$hideHudFlag|$reason';
  if (signature == _lastNav3d2dSourceLogSignature) return;
  _lastNav3d2dSourceLogSignature = signature;
  debugPrint(
    '[NAV_3D_2D_SOURCE] hudMounted=$hudMounted '
    'hudActualVisible=$hudActualVisible mapboxMarkerExists=$mapboxMarkerExists '
    'mapboxMarkerOpacity=$opacityLabel mapbox2dVisible=$mapbox2dVisible '
    'presentation3d=$presentation3d effectivelyActive=$effectivelyActive '
    'hudFallbackAllowedToHide=$hudFallbackAllowedToHide hideHudFlag=$hideHudFlag '
    'reason=$reason',
  );
}

/// Whether first-pose [skippedUnchanged] should still confirm 3D activation.
bool resolveNav3dFirstActivationConfirmsOnSkippedUnchanged({
  required bool firstPoseRequired,
}) {
  return firstPoseRequired;
}

/// NAV-3D-FIRST-POSE-ACTIVATION-1: bounded first-pose lifecycle diagnostics.
void logNav3dFirstPose({
  required String action,
  required String reason,
  required String preset,
  required int styleGeneration,
  required int presetGeneration,
  bool? inFlight,
  bool? pending,
  bool? hasPosition,
  bool? hasBearing,
  String? scale,
}) {
  final signature =
      '$action|$reason|$preset|$styleGeneration|$presetGeneration|'
      '${inFlight ?? ''}|${pending ?? ''}|${hasPosition ?? ''}|'
      '${hasBearing ?? ''}|${scale ?? ''}';
  if (signature == _lastNav3dFirstPoseLogSignature) return;
  _lastNav3dFirstPoseLogSignature = signature;
  debugPrint(
    '[NAV_3D_FIRST_POSE] action=$action reason=$reason preset=$preset '
    'styleGeneration=$styleGeneration presetGeneration=$presetGeneration'
    '${inFlight != null ? ' inFlight=$inFlight' : ''}'
    '${pending != null ? ' pending=$pending' : ''}'
    '${hasPosition != null ? ' hasPosition=$hasPosition' : ''}'
    '${hasBearing != null ? ' hasBearing=$hasBearing' : ''}'
    '${scale != null ? ' scale=$scale' : ''}',
  );
}

/// NAV-3D-FIRST-POSE-ACTIVATION-1: whether throttle may be bypassed.
bool resolveDriver3dVehicleFirstPoseBypassThrottle({
  required bool force,
  required bool firstPoseRequired,
}) {
  return force || firstPoseRequired;
}

/// NAV-ASSET-3D-SYNC-1: bounded movement sync diagnostics (no coordinates).

void logNav3dVehicleSync({
  required String phase,
  String? source,
  int? inFlightMs,
  int? consecutiveFailures,
  int? generation,
  DriverVehicle3dPreset? preset,
  bool? pending,
  String? reason,
}) {
  final signature = [
    phase,
    source ?? '',
    inFlightMs ?? '',
    consecutiveFailures ?? '',
    generation ?? '',
    preset?.name ?? '',
    pending ?? '',
    reason ?? '',
  ].join('|');
  if (signature == _lastNav3dVehicleSyncLogSignature) return;
  _lastNav3dVehicleSyncLogSignature = signature;

  final buffer = StringBuffer('[NAV_3D_VEHICLE_SYNC] phase=$phase');
  if (source != null && source.isNotEmpty) {
    buffer.write(' source=$source');
  }
  if (inFlightMs != null) {
    buffer.write(' inFlightMs=$inFlightMs');
  }
  if (consecutiveFailures != null) {
    buffer.write(' consecutiveFailures=$consecutiveFailures');
  }
  if (generation != null) {
    buffer.write(' generation=$generation');
  }
  if (preset != null) {
    buffer.write(' preset=${driverVehicle3dPresetLogLabel(preset)}');
  }
  if (pending != null) {
    buffer.write(' pending=$pending');
  }
  if (reason != null && reason.isNotEmpty) {
    buffer.write(' reason=$reason');
  }
  debugPrint(buffer.toString());
}

/// NAV-ASSET-3D-SYNC-1: coalesced, throttled movement sync lifecycle.

class NavVehicleModelSyncLifecycle {
  DriverVehicle3dMovementPose? _latestRequest;

  DriverVehicle3dMovementPose? _pendingRequest;

  bool _updateInFlight = false;

  DateTime? _lastNativeUpdateAt;

  DateTime? _updateStartedAt;

  int _consecutiveFailures = 0;

  bool _sessionFallback2d = false;

  bool _movementPaused = false;

  int _movementGeneration = 0;

  bool _firstPoseRequired = true;

  DateTime? _lastHealthCheckAt;

  bool get sessionFallback2d => _sessionFallback2d;

  bool get updateInFlight => _updateInFlight;

  bool get pendingUpdate => _pendingRequest != null;

  bool get firstPoseRequired => _firstPoseRequired;

  int get consecutiveFailures => _consecutiveFailures;

  int get movementGeneration => _movementGeneration;

  DriverVehicle3dMovementPose? get latestRequest => _latestRequest;

  DateTime? get updateStartedAt => _updateStartedAt;

  /// Returns `queued` or `coalesced` for diagnostics.
  String queueMovement(DriverVehicle3dMovementPose pose) {
    if (_sessionFallback2d || _movementPaused) return 'ignored';
    _latestRequest = pose;
    if (_updateInFlight) {
      _pendingRequest = pose;
      return 'coalesced';
    }
    return 'queued';
  }

  DriverVehicle3dMovementPose? consumeLatestRequest() {
    final pose = _latestRequest;
    _latestRequest = null;
    return pose;
  }

  void requeuePose(DriverVehicle3dMovementPose pose) {
    if (_sessionFallback2d || _movementPaused) return;
    _latestRequest = pose;
    if (_updateInFlight) {
      _pendingRequest = pose;
    }
  }

  void markFirstPoseRequired() {
    _firstPoseRequired = true;
  }

  void markFirstPoseSatisfied() {
    _firstPoseRequired = false;
  }

  bool shouldBypassThrottleForFirstPose() => _firstPoseRequired;

  void syncMovementGeneration(int generation) {
    _movementGeneration = generation;
  }

  bool beginMovementUpdate(DateTime now) {
    if (_sessionFallback2d || _movementPaused) return false;
    if (_updateInFlight) return false;
    _updateInFlight = true;
    _updateStartedAt = now;
    return true;
  }

  void cancelMovementUpdate() {
    _updateInFlight = false;
    _updateStartedAt = null;
  }

  int movementThrottleDelayMs(DateTime now, {required bool drainPending}) {
    final last = _lastNativeUpdateAt;
    if (last == null) return 0;
    final elapsed = now.difference(last).inMilliseconds;
    final minGap = drainPending
        ? kDriverVehicleModelMovementMinimumIntervalMs
        : kDriverVehicleModelMovementPreferredIntervalMs;
    if (elapsed >= minGap) return 0;
    return minGap - elapsed;
  }

  bool shouldThrottle(DateTime now, {required bool drainPending}) {
    return movementThrottleDelayMs(now, drainPending: drainPending) > 0;
  }

  /// Completes an update. Returns true when a coalesced follow-up should run.
  bool finishMovementUpdate({
    required bool applied,
    required DateTime now,
    bool timedOut = false,
    bool countFailure = false,
  }) {
    final started = _updateStartedAt;
    _updateInFlight = false;
    _updateStartedAt = null;

    if (timedOut || countFailure) {
      _consecutiveFailures += 1;
    } else if (applied) {
      _consecutiveFailures = 0;
      _lastNativeUpdateAt = now;
    }

    if (started != null &&
        now.difference(started).inMilliseconds >
            kDriverVehicleModelMovementTimeoutMs) {
      _consecutiveFailures = kDriverVehicleModelMovementMaxConsecutiveFailures;
    }

    final rerun = _pendingRequest != null;
    if (_pendingRequest != null) {
      _latestRequest = _pendingRequest;
      _pendingRequest = null;
    }

    return rerun;
  }

  bool shouldTriggerFallback({required DateTime now}) {
    if (_consecutiveFailures >=
        kDriverVehicleModelMovementMaxConsecutiveFailures) {
      return true;
    }
    final started = _updateStartedAt;
    if (started != null &&
        now.difference(started).inMilliseconds >
            kDriverVehicleModelMovementTimeoutMs) {
      return true;
    }
    return false;
  }

  int inFlightElapsedMs(DateTime now) {
    final started = _updateStartedAt;
    if (started == null) return 0;
    return now.difference(started).inMilliseconds;
  }

  void pauseForSwap() {
    _movementPaused = true;
    _pendingRequest = null;
    _latestRequest = null;
    _updateInFlight = false;
    _updateStartedAt = null;
  }

  void resumeAfterSwap({required int movementGeneration}) {
    _movementPaused = false;
    _movementGeneration = movementGeneration;
    _pendingRequest = null;
  }

  int bumpMovementGeneration() {
    _movementGeneration += 1;
    return _movementGeneration;
  }

  bool shouldIgnoreStaleMovement(int requestGeneration) {
    return requestGeneration != _movementGeneration;
  }

  void enableSessionFallback2d() {
    _sessionFallback2d = true;
    _movementPaused = true;
    _pendingRequest = null;
    _latestRequest = null;
    _updateInFlight = false;
    _updateStartedAt = null;
  }

  /// Clears movement sync state for style restore; session fallback persists.
  void clearMovementStateForStyleRestore({int movementGeneration = 0}) {
    _movementPaused = false;
    _consecutiveFailures = 0;
    _pendingRequest = null;
    _latestRequest = null;
    _updateInFlight = false;
    _updateStartedAt = null;
    _lastHealthCheckAt = null;
    _movementGeneration = movementGeneration;
    _firstPoseRequired = true;
  }

  /// NAV-ASSET-3D-MODE-GATE-1: pause and drop pending syncs when leaving 3D.
  void pauseForEligibilityLoss() {
    _movementPaused = true;
    _pendingRequest = null;
    _latestRequest = null;
    _updateInFlight = false;
    _updateStartedAt = null;
  }

  void resumeAfterEligibilityGain() {
    if (!_sessionFallback2d) {
      _movementPaused = false;
    }
  }

  /// Resets session fallback only for a genuinely new navigation session.
  void resetForNewNavigationSession() {
    _sessionFallback2d = false;
    clearMovementStateForStyleRestore(movementGeneration: 0);
    _lastNativeUpdateAt = null;
  }

  void resetForStyleRestore() {
    clearMovementStateForStyleRestore();
  }

  void reset() {
    resetForNewNavigationSession();
  }

  bool shouldRunHealthCheck(DateTime now) {
    final last = _lastHealthCheckAt;
    if (last == null ||
        now.difference(last).inMilliseconds >=
            kDriverVehicleModelMovementHealthCheckIntervalMs) {
      _lastHealthCheckAt = now;
      return true;
    }
    return false;
  }
}

/// NAV-3D-MOVEMENT-SCHEDULER-LIVELOCK-FIX-1: watchdog limit for consecutive
/// pump iterations without a new external request generation.
const int kNavVehicleModelPumpMaxStagnantIterations = 10;

/// NAV-3D-MOVEMENT-SCHEDULER-LIVELOCK-FIX-1: max pump logs per activation.
const int kNav3dMovementPumpMaxLogsPerActivation = 20;

int _nav3dMovementPumpLogCount = 0;
int _nav3dMovementPumpAbortLogCount = 0;

/// Resets the bounded pump log budget at the start of a new activation.
void resetNav3dMovementPumpLogBudget() {
  _nav3dMovementPumpLogCount = 0;
  _nav3dMovementPumpAbortLogCount = 0;
}

/// NAV-3D-MOVEMENT-SCHEDULER-LIVELOCK-FIX-1: bounded pump diagnostics.
/// Hard limit: [kNav3dMovementPumpMaxLogsPerActivation] logs per activation.
void logNav3dMovementPump({
  required String event,
  bool? queued,
  bool? running,
  bool? rerunRequested,
  bool? forceRequested,
  bool? firstPoseRequested,
  int? generation,
  int? presetGeneration,
  String? source,
  int? iteration,
}) {
  // abort_livelock must not be starved by the normal budget, but stays
  // bounded with its own small cap.
  if (event == 'abort_livelock') {
    if (_nav3dMovementPumpAbortLogCount >= 3) return;
    _nav3dMovementPumpAbortLogCount += 1;
  } else {
    if (_nav3dMovementPumpLogCount >= kNav3dMovementPumpMaxLogsPerActivation) {
      return;
    }
    _nav3dMovementPumpLogCount += 1;
  }
  final buffer = StringBuffer('[NAV_3D_MOVEMENT_PUMP] event=$event');
  if (queued != null) buffer.write(' queued=$queued');
  if (running != null) buffer.write(' running=$running');
  if (rerunRequested != null) buffer.write(' rerunRequested=$rerunRequested');
  if (forceRequested != null) buffer.write(' forceRequested=$forceRequested');
  if (firstPoseRequested != null) {
    buffer.write(' firstPoseRequested=$firstPoseRequested');
  }
  if (generation != null) buffer.write(' generation=$generation');
  if (presetGeneration != null) {
    buffer.write(' presetGeneration=$presetGeneration');
  }
  if (source != null && source.isNotEmpty) buffer.write(' source=$source');
  if (iteration != null) buffer.write(' iteration=$iteration');
  debugPrint(buffer.toString());
}

/// One movement write attempt performed by the pump host. Returns false when
/// the pump must stop (inactive, paused, session fallback, style gone).
typedef NavVehicleModelPumpAttempt =
    Future<bool> Function({required bool force, required int iteration});

/// NAV-3D-MOVEMENT-SCHEDULER-LIVELOCK-FIX-1: finite, non-recursive,
/// single-owner movement pump.
///
/// Replaces the cyclic schedule/kick/run microtask architecture that could
/// livelock the event loop. Invariants:
/// - [request] never runs a write synchronously and never recurses; it only
///   records the latest intent and starts at most one async pump.
/// - The pump loop never calls [request] and never schedules a microtask or
///   timer to re-enter itself; it loops only while [rerunRequested] was set
///   by a genuinely new request (or one bounded internal follow-up).
/// - At most one attempt (and therefore one native write) is in flight.
/// - Latest request wins; one follow-up iteration per newly arrived request.
/// - A watchdog aborts the pump if more than
///   [maxIterationsWithoutExternalRequest] consecutive iterations run without
///   a new external request generation.
class NavVehicleModelMovementPump {
  NavVehicleModelMovementPump({
    required NavVehicleModelPumpAttempt performAttempt,
    this.maxIterationsWithoutExternalRequest =
        kNavVehicleModelPumpMaxStagnantIterations,
    void Function(int iteration)? onAbortLivelock,
    void Function(int iterations)? onExit,
  }) : _performAttempt = performAttempt,
       _onAbortLivelock = onAbortLivelock,
       _onExit = onExit;

  final NavVehicleModelPumpAttempt _performAttempt;
  final void Function(int iteration)? _onAbortLivelock;
  final void Function(int iterations)? _onExit;
  final int maxIterationsWithoutExternalRequest;

  bool _running = false;
  bool _rerunRequested = false;
  bool _forceRequested = false;
  int _externalRequestGeneration = 0;
  int _lastRunIterations = 0;
  int _maxObservedIterations = 0;
  bool _abortedLivelock = false;

  bool get running => _running;
  bool get rerunRequested => _rerunRequested;
  bool get forceRequested => _forceRequested;
  int get externalRequestGeneration => _externalRequestGeneration;
  int get lastRunIterations => _lastRunIterations;
  int get maxObservedIterations => _maxObservedIterations;
  bool get abortedLivelock => _abortedLivelock;

  /// External entry point. The request payload itself lives in
  /// [NavVehicleModelSyncLifecycle] (latest wins); this only records intent
  /// and starts exactly one pump when idle.
  void request({bool force = false}) {
    _externalRequestGeneration += 1;
    _rerunRequested = true;
    _forceRequested = _forceRequested || force;
    if (_running) return;
    _running = true;
    unawaited(_run());
  }

  /// Bounded internal follow-up (e.g. stale-generation re-tag of the first
  /// pose). Does not bump the external generation, so the livelock watchdog
  /// still bounds it. No-op when the pump is not running.
  void requestInternalFollowUp() {
    if (!_running) return;
    _rerunRequested = true;
  }

  /// Clears request intent for a new session; a running pump exits on its
  /// next loop check because [rerunRequested] is cleared.
  void reset() {
    _rerunRequested = false;
    _forceRequested = false;
    _abortedLivelock = false;
  }

  Future<void> _run() async {
    var iteration = 0;
    var lastSeenGeneration = _externalRequestGeneration;
    var stagnantIterations = 0;
    try {
      while (_rerunRequested) {
        _rerunRequested = false;
        final force = _forceRequested;
        _forceRequested = false;
        iteration += 1;
        if (_externalRequestGeneration != lastSeenGeneration) {
          lastSeenGeneration = _externalRequestGeneration;
          stagnantIterations = 1;
        } else {
          stagnantIterations += 1;
        }
        if (stagnantIterations > maxIterationsWithoutExternalRequest) {
          _abortedLivelock = true;
          _rerunRequested = false;
          _onAbortLivelock?.call(iteration);
          break;
        }
        final keepPumping = await _performAttempt(
          force: force,
          iteration: iteration,
        );
        if (!keepPumping) break;
      }
    } finally {
      _lastRunIterations = iteration;
      if (iteration > _maxObservedIterations) {
        _maxObservedIterations = iteration;
      }
      _running = false;
      _onExit?.call(iteration);
    }
  }
}

/// NAV-PRES-3K-H: bounded scale diagnostics from applied camera state.

void logNavPres3dVehicleScale({
  required double appliedZoom,

  required double appliedPitch,

  required List<double> scale,

  DriverVehicle3dPreset preset = kDriverVehicle3dPresetDefault,

  double scaleMultiplier = 1.0,
}) {
  final scaleValue = scale.isNotEmpty ? scale.first : 0.0;

  final signature =
      '${driverVehicle3dPresetLogLabel(preset)}|'
      '${appliedZoom.toStringAsFixed(1)}|${appliedPitch.toStringAsFixed(1)}|'
      '${scaleValue.toStringAsFixed(2)}|${scaleMultiplier.toStringAsFixed(2)}';

  if (signature == _lastNavPres3dVehicleScaleLogSignature) return;

  _lastNavPres3dVehicleScaleLogSignature = signature;

  debugPrint(
    '[NAV_PRES_3D_VEHICLE] action=scale '
    'preset=${driverVehicle3dPresetLogLabel(preset)} '
    'appliedZoom=${appliedZoom.toStringAsFixed(1)} '
    'scale=${scaleValue.toStringAsFixed(2)} '
    'multiplier=${scaleMultiplier.toStringAsFixed(2)}',
  );
}

/// NAV-PRES-3K-I: bounded placement-mode diagnostics (no lat/lng).

void logNavPres3dVehiclePlacementMode({
  required bool debugPlacementActive,

  required String placementSource,
}) {
  final mode = resolveDriverVehicleModelPlacementMode(
    debugPlacementActive: debugPlacementActive,

    placementSource: placementSource,
  );

  final signature = '$debugPlacementActive|$mode|$placementSource';

  if (signature == _lastNavPres3dVehiclePlacementLogSignature) return;

  _lastNavPres3dVehiclePlacementLogSignature = signature;

  debugPrint(
    '[NAV_PRES_3D_VEHICLE] action=placement mode=$mode '
    'reason=${debugPlacementActive ? 'debug_placement' : 'product_render'}',
  );
}

/// NAV-PRES-3K-I: bounded debug-dot visibility diagnostics.

void logNavPres3dVehicleDebugDot({
  required bool visible,

  required String reason,
}) {
  final signature = '$visible|$reason';

  if (signature == _lastNavPres3dVehicleDebugDotLogSignature) return;

  _lastNavPres3dVehicleDebugDotLogSignature = signature;

  debugPrint(
    '[NAV_PRES_3D_VEHICLE] action=debug_dot visible=$visible reason=$reason',
  );
}

/// NAV-PRES-3K-E: screen placement diagnostics without lat/lng.

void logNavPres3dVehicleDebugPlacement({
  required String placementSource,

  required double screenX,

  required double screenY,

  required bool onScreen,

  required String viewport,
}) {
  logNavPres3dVehicle(
    action: 'debug_placement',

    result: 'ok',

    source: placementSource,

    screenX: screenX,

    screenY: screenY,

    onScreen: onScreen,

    viewport: viewport,
  );
}

/// NAV-PRES-3K-G: log when 3D vehicle intent is blocked by flat map style.

void logNavPres3dVehicleStyleGateBlocked({required String styleFamily}) {
  final signature = 'blocked|$styleFamily';

  if (signature == _lastNavPres3dVehicleStyleGateSignature) return;

  _lastNavPres3dVehicleStyleGateSignature = signature;

  logNavPres3dVehicle(
    action: 'style_gate',

    result: 'blocked',

    reason: 'is3dCandidate=false',

    layerType: styleFamily,
  );
}

/// NAV-PRES-3K-F: log active map style context during debug placement.

void logNavPres3dVehicleDebugStyleContext({
  required String activeStyleUri,

  required bool is3dCandidate,

  required String styleFamily,
}) {
  logNavPres3dVehicle(
    action: 'debug_style_context',

    result: 'ok',

    asset: activeStyleUri,

    layerType: styleFamily,

    reason: 'is3dCandidate=$is3dCandidate',
  );
}

/// NAV-PRES-3K-C: log resolved visible vehicle presentation state.

void logNavPres3dVehicleVisibleState({
  required bool modelActive,

  required bool hudVehicleHidden,

  required bool mapbox2dTaxiSuppressed,
}) {
  logNavPres3dVehicle(
    action: 'visible_state',

    result: 'ok',

    reason: 'visual_isolation',

    modelActive: modelActive,

    hudVehicleHidden: hudVehicleHidden,

    mapbox2dTaxiSuppressed: mapbox2dTaxiSuppressed,
  );
}

String? _lastNav3dVehicleGateLogSignature;

/// NAV-ASSET-3D-MODE-GATE-1: bounded eligibility diagnostics (no PII).
void logNav3dVehicleGate(Driver3dVehicleEligibility eligibility) {
  final signature =
      '${eligibility.eligible}|${eligibility.reason}|'
      '${eligibility.presentation}|${eligibility.styleFamily}|'
      '${eligibility.modelReady}|${eligibility.fallback2d}|'
      '${eligibility.selectorVisible}|${eligibility.hudTaxiHidden}';
  if (signature == _lastNav3dVehicleGateLogSignature) return;
  _lastNav3dVehicleGateLogSignature = signature;
  debugPrint(
    '[NAV_3D_VEHICLE_GATE] eligible=${eligibility.eligible} '
    'reason=${eligibility.reason} presentation=${eligibility.presentation} '
    'styleFamily=${eligibility.styleFamily} modelReady=${eligibility.modelReady} '
    'fallback2d=${eligibility.fallback2d} '
    'selectorVisible=${eligibility.selectorVisible} '
    'hudTaxiHidden=${eligibility.hudTaxiHidden}',
  );
}

/// NAV-PRES-3K-D: one-shot field-test hint after successful registration.

void logNavPres3dVehicleVisibilityHint({required String layerOrder}) {
  if (_loggedNavPres3dVehicleVisibilityHint) return;

  _loggedNavPres3dVehicleVisibilityHint = true;

  logNavPres3dVehicle(
    action: 'visibility_hint',

    result: 'ok',

    reason: 'scale_calibration',

    baseRot: formatDriverVehicleModelBaseRotForLog(),

    headingOffset: kDriverVehicleModelHeadingOffsetDeg,

    altitude: kDriverVehicleModelAltitudeMeters,

    finalRotation: formatDriverVehicleModelRotationForLog(
      resolveDriverVehicleModelFinalRotationForPreset(
        0,
        preset: kDriverVehicle3dPresetDefault,
      ),
    ),
  );

  debugPrint(
    '[NAV_PRES_3D_VEHICLE] action=visibility_hint layerOrder=$layerOrder',
  );
}

String? _lastNavPres3dVehicleLogSignature;

String? _lastNavPres3dVehicleScaleLogSignature;

String? _lastNavPres3dVehiclePlacementLogSignature;

String? _lastNavPres3dVehicleDebugDotLogSignature;

String? _lastNavPres3dVehicleStyleGateSignature;

bool _loggedNavPres3dVehicleVisibilityHint = false;

/// Best-effort Mapbox ModelLayer lifecycle for the driver taxi GLB.

class DriverVehicleModelLayer {
  bool _registered = false;

  bool _registerInFlight = false;

  bool _layerCreated = false;

  bool _sourceGeometryValid = false;

  DateTime? _lastRegisterFailureAt;

  DateTime? _lastStyleNotLoadedSkipAt;

  bool _debugStyleDotRegistered = false;

  bool _debugStyleDotRegisterInFlight = false;

  bool _lastDebugPlacementActive = false;

  DriverVehicle3dPreset? _registeredPreset;

  DriverVehicleModelAppliedMovementState? _appliedMovementState;

  DriverVehicle3dPreset? get registeredPreset => _registeredPreset;

  bool get isRegistered => _registered;

  bool get layerCreated => _layerCreated;

  bool get sourceGeometryValid => _sourceGeometryValid;

  DriverVehicleModelAppliedMovementState? get appliedMovementState =>
      _appliedMovementState;

  bool get registerInFlight => _registerInFlight;

  DateTime? get lastRegisterFailureAt => _lastRegisterFailureAt;

  DateTime? get lastStyleNotLoadedSkipAt => _lastStyleNotLoadedSkipAt;

  bool get isDebugStyleDotRegistered => _debugStyleDotRegistered;

  void resetRegistration() {
    _registered = false;

    _registerInFlight = false;

    _layerCreated = false;

    _sourceGeometryValid = false;

    _lastRegisterFailureAt = null;

    _lastStyleNotLoadedSkipAt = null;

    _debugStyleDotRegistered = false;

    _debugStyleDotRegisterInFlight = false;

    _lastDebugPlacementActive = false;

    _registeredPreset = null;

    _appliedMovementState = null;

    _loggedNavPres3dVehicleVisibilityHint = false;
  }

  void clearAppliedMovementState() {
    _appliedMovementState = null;
  }

  Future<bool> _isStyleLoaded(mb.StyleManager style) async {
    try {
      return await style.isStyleLoaded();
    } catch (_) {
      return false;
    }
  }

  Future<void> _moveLayerToTop(mb.StyleManager style, String layerId) async {
    try {
      await style.moveStyleLayer(layerId, null);
    } catch (_) {}
  }

  Future<String> _addModelLayerOnTop(
    mb.StyleManager style,
    mb.ModelLayer layer,
  ) async {
    await style.addLayer(layer);

    await _moveLayerToTop(style, kDriverVehicleModelLayerId);

    return 'style_top_moveStyleLayer';
  }

  Future<({bool layerExists, bool sourceExists, String layerType})>
  _verifyRegisteredGeometry(mb.StyleManager style) async {
    var layerExists = false;

    var sourceExists = false;

    var layerType = 'unknown';

    try {
      final layer = await style.getLayer(kDriverVehicleModelLayerId);

      layerExists = layer != null;

      if (layer != null) {
        layerType = layer.getType();
      }
    } catch (_) {}

    try {
      final source = await style.getSource(kDriverVehicleModelSourceId);

      sourceExists = source != null;
    } catch (_) {}

    return (
      layerExists: layerExists,
      sourceExists: sourceExists,
      layerType: layerType,
    );
  }

  Future<void> _verifyRegistered(mb.StyleManager style) async {
    final verified = await _verifyRegisteredGeometry(style);
    _layerCreated = verified.layerExists;
    _sourceGeometryValid = verified.sourceExists;

    logNavPres3dVehicle(
      action: 'verify',

      result: verified.layerExists && verified.sourceExists ? 'ok' : 'failed',

      layerExists: verified.layerExists,

      sourceExists: verified.sourceExists,

      layerType: verified.layerType,
    );
  }

  /// NAV-3D-RENDER-VISIBILITY-PROOF-1: read back layer/source binding state.
  Future<Nav3dVehicleRenderReadback> readRenderProof({
    required mb.StyleManager style,
    required DriverVehicle3dPreset preset,
  }) async {
    final expectedLayerModelId = resolveDriverVehicleModelLayerModelId(
      debugPlacementActive: false,
      preset: preset,
    );
    var layerExists = false;
    var sourceExists = false;
    String? layerModelId;
    String? layerVisibility;
    List<double>? layerScale;
    List<double>? layerTranslation;
    List<double>? layerRotation;
    double? minZoom;
    double? maxZoom;
    String? slot;
    double? modelOpacity;
    double? modelEmissiveStrength;

    try {
      final layer = await style.getLayer(kDriverVehicleModelLayerId);
      layerExists = layer != null;
      if (layer is mb.ModelLayer) {
        layerModelId = layer.modelId;
        layerScale = layer.modelScale == null
            ? null
            : List<double>.from(layer.modelScale!);
        layerTranslation = layer.modelTranslation == null
            ? null
            : List<double>.from(layer.modelTranslation!);
        layerRotation = layer.modelRotation == null
            ? null
            : List<double>.from(layer.modelRotation!);
        minZoom = layer.minZoom;
        maxZoom = layer.maxZoom;
        slot = layer.slot;
        modelOpacity = layer.modelOpacity;
        modelEmissiveStrength = layer.modelEmissiveStrength;
        layerVisibility = layer.visibility?.name
            .toLowerCase()
            .replaceAll('_', '-');
      }
    } catch (_) {}

    if (layerVisibility == null) {
      try {
        final visibilityProp = await style.getStyleLayerProperty(
          kDriverVehicleModelLayerId,
          'visibility',
        );
        layerVisibility = _parseStyleString(visibilityProp.value);
      } catch (_) {}
    }

    Nav3dVehicleRenderSourceParse sourceParse = Nav3dVehicleRenderSourceParse.empty;
    try {
      final source = await style.getSource(kDriverVehicleModelSourceId);
      sourceExists = source != null;
      final dataProp = await style.getStyleSourceProperty(
        kDriverVehicleModelSourceId,
        'data',
      );
      final rawData = dataProp.value?.toString();
      sourceParse = parseDriverVehicleModelSourceJson(rawData);
    } catch (_) {}

    final modelIdBound = resolveNav3dVehicleModelIdBound(
      actualModelId: layerModelId,
      expectedModelId: expectedLayerModelId,
    );

    return Nav3dVehicleRenderReadback(
      layerExists: layerExists,
      sourceExists: sourceExists,
      layerVisible: resolveNav3dVehicleLayerVisibilityVisible(layerVisibility),
      sourceFeaturePresent: sourceParse.sourceFeaturePresent,
      sourceHasValidPosition: sourceParse.sourceHasValidPosition,
      modelIdBound: modelIdBound,
      sourceModelIdBound: false,
      layerModelId: layerModelId,
      sourceModelId: sourceParse.sourceModelId,
      layerVisibility: layerVisibility,
      sourceLon: sourceParse.sourceLon,
      sourceLat: sourceParse.sourceLat,
      layerScale: layerScale,
      layerTranslation: layerTranslation,
      layerRotation: layerRotation,
      minZoom: minZoom,
      maxZoom: maxZoom,
      slot: slot,
      modelOpacity: modelOpacity,
      modelEmissiveStrength: modelEmissiveStrength,
    );
  }

  /// NAV-3D-VEHICLE-VISIBILITY-FAILSAFE-1: runtime activation check before HUD hide.
  Future<bool> verifyRuntimeActivation({
    required mb.StyleManager style,
    required DriverVehicle3dPreset preset,
    required bool assetLoaded,
    required bool modelPoseApplied,
  }) async {
    if (!_registered || !_layerCreated || !_sourceGeometryValid) {
      return false;
    }
    if (!assetLoaded || !modelPoseApplied) {
      return false;
    }
    final verified = await _verifyRegisteredGeometry(style);
    _layerCreated = verified.layerExists;
    _sourceGeometryValid = verified.sourceExists;
    if (!verified.layerExists || !verified.sourceExists) {
      return false;
    }
    final readback = await readRenderProof(style: style, preset: preset);
    return resolveNav3dVehicleRenderCredibility(
      readback: readback,
      assetLoaded: assetLoaded,
      modelPoseApplied: modelPoseApplied,
    );
  }

  Future<void> _verifyDebugStyleDot(mb.StyleManager style) async {
    var layerExists = false;

    var sourceExists = false;

    try {
      final layer = await style.getLayer(kDriverVehicleDebugStyleDotLayerId);

      layerExists = layer != null;
    } catch (_) {}

    try {
      final source = await style.getSource(kDriverVehicleDebugStyleDotSourceId);

      sourceExists = source != null;
    } catch (_) {}

    logNavPres3dVehicle(
      action: 'debug_style_dot_verify',

      result: layerExists && sourceExists ? 'ok' : 'failed',

      layerExists: layerExists,

      sourceExists: sourceExists,
    );
  }

  Future<bool> _styleAlreadyHasModelLayer(mb.StyleManager style) async {
    try {
      final layer = await style.getLayer(kDriverVehicleModelLayerId);

      if (layer != null) {
        await _verifyRegistered(style);

        return true;
      }
    } catch (_) {}

    return false;
  }

  Future<bool> _styleAlreadyHasDebugStyleDot(mb.StyleManager style) async {
    try {
      final layer = await style.getLayer(kDriverVehicleDebugStyleDotLayerId);

      if (layer != null) {
        await _verifyDebugStyleDot(style);

        return true;
      }
    } catch (_) {}

    return false;
  }

  Future<void> _teardownModelOnly(mb.StyleManager style) async {
    try {
      await style.removeStyleLayer(kDriverVehicleModelLayerId);
    } catch (_) {}

    try {
      await style.removeStyleSource(kDriverVehicleModelSourceId);
    } catch (_) {}

    for (final modelId in allDriverVehicle3dStyleModelIds()) {
      try {
        await style.removeStyleModel(modelId);
      } catch (_) {}
    }

    try {
      await style.removeStyleModel(kDriverVehicleModelId);
    } catch (_) {}

    _registered = false;

    _registeredPreset = null;

    _layerCreated = false;

    _sourceGeometryValid = false;

    _appliedMovementState = null;
  }

  Future<bool> _layerMatchesPreset(
    mb.StyleManager style,

    DriverVehicle3dPreset preset,
  ) async {
    try {
      final layer = await style.getLayer(kDriverVehicleModelLayerId);

      if (layer is! mb.ModelLayer) {
        return false;
      }

      return layer.modelId == resolveDriverVehicleModelLayerModelId(
        debugPlacementActive: false,
        preset: preset,
      );
    } catch (_) {
      return false;
    }
  }

  Future<bool> _ensureStyleModelRegistered(
    mb.StyleManager style,

    DriverVehicle3dPreset preset,
  ) async {
    final spec = resolveDriverVehicle3dModelSpec(preset);

    final styleModelId = resolveDriverVehicle3dStyleModelId(preset);

    try {
      await style.removeStyleModel(styleModelId);
    } catch (_) {}

    await style.addStyleModel(styleModelId, spec.assetUri);

    return true;
  }

  Future<void> teardownDebugStyleDot(mb.StyleManager style) async {
    try {
      await style.removeStyleLayer(kDriverVehicleDebugStyleDotLayerId);
    } catch (_) {}

    try {
      await style.removeStyleSource(kDriverVehicleDebugStyleDotSourceId);
    } catch (_) {}

    _debugStyleDotRegistered = false;

    _debugStyleDotRegisterInFlight = false;
  }

  Future<bool> _attemptRegisterModelLayer({
    required mb.StyleManager style,

    required DriverVehicle3dPreset preset,

    required bool debugPlacementActive,

    required double appliedZoom,

    required double appliedPitch,
  }) async {
    final spec = resolveDriverVehicle3dModelSpec(preset);

    final styleModelId = resolveDriverVehicle3dStyleModelId(preset);

    final modelIdMode = resolveDriverVehicleModelIdModeLabel(
      debugPlacementActive: debugPlacementActive,
    );

    final layerModelId = resolveDriverVehicleModelLayerModelId(
      debugPlacementActive: debugPlacementActive,

      preset: preset,
    );

    try {
      if (resolveDriverVehicleModelRequiresStyleModelRegistration(
        debugPlacementActive: debugPlacementActive,
      )) {
        await _ensureStyleModelRegistered(style, preset);
      }

      await style.addSource(
        mb.GeoJsonSource(
          id: kDriverVehicleModelSourceId,

          data: driverVehicleModelGeoJsonData(lon: 0, lat: 0),
        ),
      );

      final layer = mb.ModelLayer(
        id: kDriverVehicleModelLayerId,

        sourceId: kDriverVehicleModelSourceId,
      );

      layer.modelId = layerModelId;

      final modelScale = resolveDriverVehicleModelScaleForPreset(
        appliedZoom: appliedZoom,

        appliedPitch: appliedPitch,

        preset: preset,

        debugPlacementActive: debugPlacementActive,
      );

      layer.modelScale = modelScale;

      layer.modelRotation = resolveDriverVehicleModelRotationForWrite(
        rawNavigationBearing: 0,
        preset: preset,
        source: 'register',
        debugPlacementActive: debugPlacementActive,
      );

      layer.modelTranslation = driverVehicleModelTranslationForPreset(
        debugPlacementActive: debugPlacementActive,

        preset: preset,
      );

      layer.modelType = mb.ModelType.COMMON_3D;

      layer.modelElevationReference = mb.ModelElevationReference.GROUND;

      final layerOrder = await _addModelLayerOnTop(style, layer);

      _registered = resolveDriverVehicleModelRegisteredAfterFailure(
        registerSucceeded: true,
      );

      _lastRegisterFailureAt = null;

      logNavPres3dVehicle(
        action: 'register',

        result: 'ok',

        asset: spec.assetUri,

        modelIdMode: modelIdMode,

        baseRot: formatDriverVehicleModelBaseRotForLog(),

        headingOffset: spec.headingOffsetDeg,

        altitude: resolveDriverVehicleModelAltitudeMetersForPreset(
          debugPlacementActive: debugPlacementActive,

          preset: preset,
        ),

        finalRotation: formatDriverVehicleModelRotationForLog(
          resolveDriverVehicleModelFinalRotationForPreset(
            0,
            preset: preset,
            debugPlacementActive: debugPlacementActive,
          ),
        ),

        scale: modelScale,

        debugPlacement: debugPlacementActive,
      );

      logNavPres3dVehiclePresetRegister(
        preset: preset,

        result: 'ok',

        assetUri: spec.assetUri,
      );

      logNavPres3dVehicleScale(
        appliedZoom: appliedZoom,

        appliedPitch: appliedPitch,

        scale: modelScale,

        preset: preset,

        scaleMultiplier: spec.scaleMultiplier,
      );

      await _verifyRegistered(style);

      if (!_layerCreated || !_sourceGeometryValid) {
        await _teardownModelOnly(style);
        _registered = resolveDriverVehicleModelRegisteredAfterFailure(
          registerSucceeded: false,
        );
        _lastRegisterFailureAt = DateTime.now();
        logNavPres3dVehicle(
          action: 'register',
          result: 'failed',
          reason: 'layer_or_source_missing_after_verify',
          asset: spec.assetUri,
          modelIdMode: modelIdMode,
        );
        return false;
      }

      logNavPres3dVehicleVisibilityHint(layerOrder: layerOrder);

      return true;
    } catch (e) {
      await _teardownModelOnly(style);

      await teardownDebugStyleDot(style);

      _registered = resolveDriverVehicleModelRegisteredAfterFailure(
        registerSucceeded: false,
      );

      _lastRegisterFailureAt = DateTime.now();

      logNavPres3dVehicle(
        action: 'register',

        result: 'failed',

        reason: formatNavPres3dVehicleError(e),

        asset: spec.assetUri,

        modelIdMode: modelIdMode,

        baseRot: formatDriverVehicleModelBaseRotForLog(),

        headingOffset: spec.headingOffsetDeg,

        altitude: resolveDriverVehicleModelAltitudeMetersForPreset(
          debugPlacementActive: debugPlacementActive,

          preset: preset,
        ),
      );

      return false;
    }
  }

  Future<bool> _registerWithPresetOrFallback({
    required mb.StyleManager style,

    required DriverVehicle3dPreset requestedPreset,

    required bool debugPlacementActive,

    required double appliedZoom,

    required double appliedPitch,
  }) async {
    _registerInFlight = true;

    try {
      var effectivePreset = requestedPreset;

      var ok = await _attemptRegisterModelLayer(
        style: style,

        preset: effectivePreset,

        debugPlacementActive: debugPlacementActive,

        appliedZoom: appliedZoom,

        appliedPitch: appliedPitch,
      );

      logNavPres3dVehiclePresetRegister(
        preset: requestedPreset,

        result: ok ? 'ok' : 'failed',

        assetUri: resolveDriverVehicle3dModelSpec(requestedPreset).assetUri,
      );

      if (!ok && effectivePreset != DriverVehicle3dPreset.fluxidiTaxi) {
        await _teardownModelOnly(style);

        effectivePreset = DriverVehicle3dPreset.fluxidiTaxi;

        ok = await _attemptRegisterModelLayer(
          style: style,

          preset: effectivePreset,

          debugPlacementActive: debugPlacementActive,

          appliedZoom: appliedZoom,

          appliedPitch: appliedPitch,
        );

        logNavPres3dVehiclePresetRegister(
          preset: effectivePreset,

          result: ok ? 'ok' : 'failed',

          assetUri: resolveDriverVehicle3dModelSpec(effectivePreset).assetUri,
        );
      }

      if (ok) {
        _registeredPreset = effectivePreset;
      }

      return ok;
    } finally {
      _registerInFlight = false;
    }
  }

  Future<bool> swapVehiclePreset({
    required mb.StyleManager style,

    required DriverVehicle3dPreset preset,

    required int generation,

    required int Function() readCurrentGeneration,

    required double lon,

    required double lat,

    required double bearingDeg,

    required String source,

    bool debugPlacementActive = false,

    required double appliedZoom,

    required double appliedPitch,
    int styleGeneration = -1,
    int presetGeneration = -1,
  }) async {
    final startedAt = DateTime.now();

    final styleModelId = resolveDriverVehicle3dStyleModelId(preset);

    final spec = resolveDriverVehicle3dModelSpec(preset);

    if (shouldIgnoreStaleDriverVehicle3dSwap(
      requestGeneration: generation,

      currentGeneration: readCurrentGeneration(),
    )) {
      logNav3dVehicleSwap(
        phase: 'stale_ignored',

        preset: preset,

        generation: generation,

        modelId: styleModelId,

        reason: 'pre_teardown',
      );

      return false;
    }

    await _teardownModelOnly(style);

    _registerInFlight = false;

    _lastRegisterFailureAt = null;

    if (shouldIgnoreStaleDriverVehicle3dSwap(
      requestGeneration: generation,

      currentGeneration: readCurrentGeneration(),
    )) {
      logNav3dVehicleSwap(
        phase: 'stale_ignored',

        preset: preset,

        generation: generation,

        modelId: styleModelId,

        reason: 'post_teardown',
      );

      return false;
    }

    logNav3dVehicleSwap(
      phase: 'model_registered',

      preset: preset,

      generation: generation,

      modelId: styleModelId,
    );

    var effectivePreset = preset;

    var ok = await _attemptRegisterModelLayer(
      style: style,

      preset: effectivePreset,

      debugPlacementActive: debugPlacementActive,

      appliedZoom: appliedZoom,

      appliedPitch: appliedPitch,
    );

    if (shouldIgnoreStaleDriverVehicle3dSwap(
      requestGeneration: generation,

      currentGeneration: readCurrentGeneration(),
    )) {
      logNav3dVehicleSwap(
        phase: 'stale_ignored',

        preset: preset,

        generation: generation,

        modelId: styleModelId,

        reason: 'post_register',
      );

      return false;
    }

    if (!ok && effectivePreset != DriverVehicle3dPreset.fluxidiTaxi) {
      await _teardownModelOnly(style);

      effectivePreset = DriverVehicle3dPreset.fluxidiTaxi;

      ok = await _attemptRegisterModelLayer(
        style: style,

        preset: effectivePreset,

        debugPlacementActive: debugPlacementActive,

        appliedZoom: appliedZoom,

        appliedPitch: appliedPitch,
      );
    }

    if (shouldIgnoreStaleDriverVehicle3dSwap(
      requestGeneration: generation,

      currentGeneration: readCurrentGeneration(),
    )) {
      logNav3dVehicleSwap(
        phase: 'stale_ignored',

        preset: preset,

        generation: generation,

        modelId: resolveDriverVehicle3dStyleModelId(effectivePreset),

        reason: 'post_fallback_register',
      );

      return false;
    }

    if (!ok) {
      logNav3dVehicleSwap(
        phase: 'failed',

        preset: effectivePreset,

        generation: generation,

        modelId: resolveDriverVehicle3dStyleModelId(effectivePreset),

        reason: 'register_failed',

        durationMs: DateTime.now().difference(startedAt).inMilliseconds,
      );

      return false;
    }

    _registeredPreset = effectivePreset;

    logNav3dVehicleSwap(
      phase: 'layer_recreated',

      preset: effectivePreset,

      generation: generation,

      modelId: resolveDriverVehicle3dStyleModelId(effectivePreset),
    );

    final updated = await update(
      style: style,

      lon: lon,

      lat: lat,

      bearingDeg: bearingDeg,

      source: source,

      debugPlacementActive: debugPlacementActive,

      appliedZoom: appliedZoom,

      appliedPitch: appliedPitch,

      preset: effectivePreset,

      swapGeneration: generation,

      readCurrentGeneration: readCurrentGeneration,
      styleGeneration: styleGeneration,
      presetGeneration: presetGeneration,
    );

    if (shouldIgnoreStaleDriverVehicle3dSwap(
      requestGeneration: generation,

      currentGeneration: readCurrentGeneration(),
    )) {
      logNav3dVehicleSwap(
        phase: 'stale_ignored',

        preset: effectivePreset,

        generation: generation,

        modelId: resolveDriverVehicle3dStyleModelId(effectivePreset),

        reason: 'post_update',
      );

      return false;
    }

    if (!updated) {
      logNav3dVehicleSwap(
        phase: 'failed',

        preset: effectivePreset,

        generation: generation,

        modelId: resolveDriverVehicle3dStyleModelId(effectivePreset),

        reason: 'update_failed',

        durationMs: DateTime.now().difference(startedAt).inMilliseconds,
      );

      return false;
    }

    logNav3dVehicleSwap(
      phase: 'source_updated',

      preset: effectivePreset,

      generation: generation,

      modelId: resolveDriverVehicle3dStyleModelId(effectivePreset),
    );

    logNav3dVehicleSwap(
      phase: 'complete',

      preset: effectivePreset,

      generation: generation,

      modelId: resolveDriverVehicle3dStyleModelId(effectivePreset),

      durationMs: DateTime.now().difference(startedAt).inMilliseconds,
    );

    return true;
  }

  Future<bool> ensureRegistered(
    mb.StyleManager style, {

    bool styleReady = true,

    bool debugPlacementActive = false,

    required double appliedZoom,

    required double appliedPitch,

    DriverVehicle3dPreset preset = kDriverVehicle3dPresetDefault,
  }) async {
    _lastDebugPlacementActive = debugPlacementActive;

    if (_registered && _registeredPreset == preset) {
      if (await _layerMatchesPreset(style, preset)) {
        return true;
      }

      await _teardownModelOnly(style);
    }

    if (_registered && _registeredPreset != preset) {
      await _teardownModelOnly(style);
    }

    if (!styleReady) return false;

    if (_registerInFlight) return false;

    final now = DateTime.now();

    if (!resolveDriverVehicleModelCanAttemptRegister(
      registered: _registered,

      registerInFlight: _registerInFlight,

      lastFailureAt: _lastRegisterFailureAt,

      now: now,
    )) {
      return false;
    }

    final styleLoaded = await _isStyleLoaded(style);

    if (resolveDriverVehicleModelShouldSkipForStyleNotLoaded(
      styleLoaded: styleLoaded,

      lastStyleNotLoadedSkipAt: _lastStyleNotLoadedSkipAt,

      now: now,
    )) {
      _lastStyleNotLoadedSkipAt = now;

      logNavPres3dVehicle(
        action: 'register',

        result: 'skipped',

        reason: 'style_not_loaded',
      );

      return false;
    }

    if (!styleLoaded) {
      _lastStyleNotLoadedSkipAt = now;

      logNavPres3dVehicle(
        action: 'register',

        result: 'skipped',

        reason: 'style_not_loaded',
      );

      return false;
    }

    if (await _styleAlreadyHasModelLayer(style)) {
      if (await _layerMatchesPreset(style, preset)) {
        _registered = true;

        _registeredPreset = preset;

        _lastRegisterFailureAt = null;

        return true;
      }

      await _teardownModelOnly(style);
    }

    return _registerWithPresetOrFallback(
      style: style,

      requestedPreset: preset,

      debugPlacementActive: debugPlacementActive,

      appliedZoom: appliedZoom,

      appliedPitch: appliedPitch,
    );
  }

  Future<bool> ensureDebugStyleDotRegistered(
    mb.StyleManager style, {

    required double lon,

    required double lat,

    bool styleReady = true,
  }) async {
    if (_debugStyleDotRegistered) return true;

    if (!styleReady || _debugStyleDotRegisterInFlight) return false;

    final styleLoaded = await _isStyleLoaded(style);

    final now = DateTime.now();

    if (!styleLoaded) {
      if (resolveDriverVehicleModelShouldSkipForStyleNotLoaded(
        styleLoaded: false,

        lastStyleNotLoadedSkipAt: _lastStyleNotLoadedSkipAt,

        now: now,
      )) {
        return false;
      }

      _lastStyleNotLoadedSkipAt = now;

      return false;
    }

    if (await _styleAlreadyHasDebugStyleDot(style)) {
      _debugStyleDotRegistered = true;

      return true;
    }

    _debugStyleDotRegisterInFlight = true;

    final config = resolveDriverVehicleDebugStyleDotLayerConfig();

    try {
      await style.addSource(
        mb.GeoJsonSource(
          id: kDriverVehicleDebugStyleDotSourceId,

          data: driverVehicleModelGeoJsonData(lon: lon, lat: lat),
        ),
      );

      final circleLayer = mb.CircleLayer(
        id: kDriverVehicleDebugStyleDotLayerId,

        sourceId: kDriverVehicleDebugStyleDotSourceId,

        circleRadius: config.radius,

        circleColor: config.color,

        circleStrokeColor: config.strokeColor,

        circleStrokeWidth: config.strokeWidth,

        circleOpacity: 1.0,

        circleStrokeOpacity: 1.0,

        circlePitchAlignment: config.pitchAlignment,

        circlePitchScale: config.pitchScale,
      );

      await style.addLayer(circleLayer);

      await _moveLayerToTop(style, kDriverVehicleDebugStyleDotLayerId);

      _debugStyleDotRegistered = true;

      logNavPres3dVehicle(action: 'debug_style_dot_register', result: 'ok');

      await _verifyDebugStyleDot(style);

      return true;
    } catch (e) {
      await teardownDebugStyleDot(style);

      logNavPres3dVehicle(
        action: 'debug_style_dot_register',

        result: 'failed',

        reason: formatNavPres3dVehicleError(e),
      );

      return false;
    } finally {
      _debugStyleDotRegisterInFlight = false;
    }
  }

  Future<DriverVehicleModelMovementOutcome> updateMovementOnly({
    required mb.StyleManager style,

    required double lon,

    required double lat,

    required double bearingDeg,

    required String source,

    bool debugPlacementActive = false,

    required double appliedZoom,

    required double appliedPitch,

    DriverVehicle3dPreset preset = kDriverVehicle3dPresetDefault,

    int? movementGeneration,

    int Function()? readCurrentMovementGeneration,

    bool force = false,
    double? debugProbeScale,
    double? debugProbeAltitude,
    int styleGeneration = -1,
    int presetGeneration = -1,
  }) async {
    if (!_registered) {
      return const DriverVehicleModelMovementOutcome(
        result: DriverVehicleModelMovementUpdateResult.notRegistered,
      );
    }

    if (movementGeneration != null &&
        readCurrentMovementGeneration != null &&
        movementGeneration != readCurrentMovementGeneration()) {
      return const DriverVehicleModelMovementOutcome(
        result: DriverVehicleModelMovementUpdateResult.staleMovement,
      );
    }

    try {
      final spec = resolveDriverVehicle3dModelSpec(preset);

      final finalRotation = resolveDriverVehicleModelRotationForWrite(
        rawNavigationBearing: bearingDeg,
        preset: preset,
        source: source,
        debugPlacementActive: debugPlacementActive,
        styleGeneration: styleGeneration,
        presetGeneration: presetGeneration,
      );

      final translation = driverVehicleModelTranslationForPreset(
        debugPlacementActive: debugPlacementActive,

        preset: preset,
        debugProbeAltitude: debugProbeAltitude,
      );

      final modelScale = resolveDriverVehicleModelScaleForPreset(
        appliedZoom: appliedZoom,

        appliedPitch: appliedPitch,

        preset: preset,

        debugPlacementActive: debugPlacementActive,
        debugProbeScale: debugProbeScale,
      );

      final plan = resolveDriverVehicleModelMovementWritePlan(
        applied: _appliedMovementState,

        lon: lon,

        lat: lat,

        bearingDeg: bearingDeg,

        preset: preset,

        scale: modelScale,

        translation: translation,

        rotation: finalRotation,

        force: force,
      );

      if (!plan.positionChanged &&
          !plan.rotationChanged &&
          !plan.scaleChanged &&
          !plan.translationChanged) {
        return const DriverVehicleModelMovementOutcome(
          result: DriverVehicleModelMovementUpdateResult.skippedUnchanged,
        );
      }

      if (plan.positionChanged) {
        final geoJson = driverVehicleModelGeoJsonData(lon: lon, lat: lat);

        final sourceObj = await style.getSource(kDriverVehicleModelSourceId);

        if (sourceObj is mb.GeoJsonSource) {
          await sourceObj.updateGeoJSON(geoJson);
        } else {
          await style.setStyleSourceProperty(
            kDriverVehicleModelSourceId,

            'data',

            geoJson,
          );
        }
      }

      if (plan.rotationChanged) {
        await style.setStyleLayerProperty(
          kDriverVehicleModelLayerId,

          'model-rotation',

          finalRotation,
        );
      }

      if (plan.translationChanged) {
        await style.setStyleLayerProperty(
          kDriverVehicleModelLayerId,

          'model-translation',

          translation,
        );
      }

      if (plan.scaleChanged) {
        await style.setStyleLayerProperty(
          kDriverVehicleModelLayerId,

          'model-scale',

          modelScale,
        );

        logNavPres3dVehicleScale(
          appliedZoom: appliedZoom,

          appliedPitch: appliedPitch,

          scale: modelScale,

          preset: preset,

          scaleMultiplier: spec.scaleMultiplier,
        );
      }

      _appliedMovementState = DriverVehicleModelAppliedMovementState(
        lon: lon,

        lat: lat,

        bearingDeg: bearingDeg,

        preset: preset,

        scale: List<double>.from(modelScale),

        translation: List<double>.from(translation),

        rotation: List<double>.from(finalRotation),
      );

      logNavPres3dVehicle(
        action: 'movement_update',

        result: 'ok',

        source: source,

        bearing: bearingDeg,

        modelIdMode: resolveDriverVehicleModelIdModeLabel(
          debugPlacementActive: debugPlacementActive,
        ),

        finalRotation: formatDriverVehicleModelRotationForLog(finalRotation),

        altitude: resolveDriverVehicleModelAltitudeMetersForPreset(
          debugPlacementActive: debugPlacementActive,

          preset: preset,
        ),

        scale: modelScale,
      );

      return DriverVehicleModelMovementOutcome(
        result: DriverVehicleModelMovementUpdateResult.applied,
        positionWritten: plan.positionChanged,
        rotationWritten: plan.rotationChanged,
        scaleWritten: plan.scaleChanged,
        translationWritten: plan.translationChanged,
      );
    } catch (e) {
      logNavPres3dVehicle(
        action: 'movement_update',

        result: 'failed',

        reason: formatNavPres3dVehicleError(e),

        source: source,

        bearing: bearingDeg,
      );

      return const DriverVehicleModelMovementOutcome(
        result: DriverVehicleModelMovementUpdateResult.failed,
      );
    }
  }

  Future<bool> update({
    required mb.StyleManager style,

    required double lon,

    required double lat,

    required double bearingDeg,

    required String source,

    bool debugPlacementActive = false,

    required double appliedZoom,

    required double appliedPitch,

    DriverVehicle3dPreset preset = kDriverVehicle3dPresetDefault,

    int? swapGeneration,

    int Function()? readCurrentGeneration,
    int styleGeneration = -1,
    int presetGeneration = -1,
  }) async {
    if (!_registered) return false;

    if (swapGeneration != null &&
        readCurrentGeneration != null &&
        shouldIgnoreStaleDriverVehicle3dSwap(
          requestGeneration: swapGeneration,

          currentGeneration: readCurrentGeneration(),
        )) {
      return false;
    }

    try {
      final spec = resolveDriverVehicle3dModelSpec(preset);

      final geoJson = driverVehicleModelGeoJsonData(lon: lon, lat: lat);

      final sourceObj = await style.getSource(kDriverVehicleModelSourceId);

      if (sourceObj is mb.GeoJsonSource) {
        await sourceObj.updateGeoJSON(geoJson);
      } else {
        await style.setStyleSourceProperty(
          kDriverVehicleModelSourceId,

          'data',

          geoJson,
        );
      }

      final finalRotation = resolveDriverVehicleModelRotationForWrite(
        rawNavigationBearing: bearingDeg,
        preset: preset,
        source: source,
        debugPlacementActive: debugPlacementActive,
        styleGeneration: styleGeneration,
        presetGeneration: presetGeneration,
      );

      final altitude = resolveDriverVehicleModelAltitudeMetersForPreset(
        debugPlacementActive: debugPlacementActive,

        preset: preset,
      );

      final translation = driverVehicleModelTranslationForPreset(
        debugPlacementActive: debugPlacementActive,

        preset: preset,
      );

      final modelScale = resolveDriverVehicleModelScaleForPreset(
        appliedZoom: appliedZoom,

        appliedPitch: appliedPitch,

        preset: preset,

        debugPlacementActive: debugPlacementActive,
      );

      await style.setStyleLayerProperty(
        kDriverVehicleModelLayerId,

        'model-rotation',

        finalRotation,
      );

      await style.setStyleLayerProperty(
        kDriverVehicleModelLayerId,

        'model-translation',

        translation,
      );

      await style.setStyleLayerProperty(
        kDriverVehicleModelLayerId,

        'model-scale',

        modelScale,
      );

      logNavPres3dVehicleScale(
        appliedZoom: appliedZoom,

        appliedPitch: appliedPitch,

        scale: modelScale,

        preset: preset,

        scaleMultiplier: spec.scaleMultiplier,
      );

      logNavPres3dVehicle(
        action: 'update',

        result: 'ok',

        source: source,

        bearing: bearingDeg,

        modelIdMode: resolveDriverVehicleModelIdModeLabel(
          debugPlacementActive: debugPlacementActive,
        ),

        finalRotation: formatDriverVehicleModelRotationForLog(finalRotation),

        altitude: altitude,

        scale: modelScale,
      );

      _appliedMovementState = DriverVehicleModelAppliedMovementState(
        lon: lon,

        lat: lat,

        bearingDeg: bearingDeg,

        preset: preset,

        scale: List<double>.from(modelScale),

        translation: List<double>.from(translation),

        rotation: List<double>.from(finalRotation),
      );

      return true;
    } catch (e) {
      logNavPres3dVehicle(
        action: 'update',

        result: 'failed',

        reason: formatNavPres3dVehicleError(e),

        source: source,

        bearing: bearingDeg,

        finalRotation: formatDriverVehicleModelRotationForLog(
          resolveDriverVehicleModelRotationForWrite(
            rawNavigationBearing: bearingDeg,
            preset: preset,
            source: source,
            debugPlacementActive: debugPlacementActive,
            styleGeneration: styleGeneration,
            presetGeneration: presetGeneration,
          ),
        ),

        altitude: resolveDriverVehicleModelAltitudeMetersForPreset(
          debugPlacementActive: debugPlacementActive,

          preset: preset,
        ),
      );

      return false;
    }
  }

  Future<bool> updateDebugStyleDot({
    required mb.StyleManager style,

    required double lon,

    required double lat,

    double? screenX,

    double? screenY,

    bool? onScreen,
  }) async {
    if (!_debugStyleDotRegistered) return false;

    try {
      final geoJson = driverVehicleModelGeoJsonData(lon: lon, lat: lat);

      final sourceObj = await style.getSource(
        kDriverVehicleDebugStyleDotSourceId,
      );

      if (sourceObj is mb.GeoJsonSource) {
        await sourceObj.updateGeoJSON(geoJson);
      } else {
        await style.setStyleSourceProperty(
          kDriverVehicleDebugStyleDotSourceId,

          'data',

          geoJson,
        );
      }

      logNavPres3dVehicle(
        action: 'debug_style_dot_update',

        result: 'ok',

        screenX: screenX,

        screenY: screenY,

        onScreen: onScreen,
      );

      return true;
    } catch (e) {
      logNavPres3dVehicle(
        action: 'debug_style_dot_update',

        result: 'failed',

        reason: formatNavPres3dVehicleError(e),

        screenX: screenX,

        screenY: screenY,

        onScreen: onScreen,
      );

      return false;
    }
  }

  Future<void> teardown(mb.StyleManager style) async {
    try {
      await teardownDebugStyleDot(style);

      await _teardownModelOnly(style);

      logNavPres3dVehicle(action: 'teardown', result: 'ok');
    } catch (e) {
      _registered = false;

      _registerInFlight = false;

      _debugStyleDotRegistered = false;

      _debugStyleDotRegisterInFlight = false;

      logNavPres3dVehicle(
        action: 'teardown',

        result: 'failed',

        reason: formatNavPres3dVehicleError(e),
      );
    }
  }
}

/// Convenience for tests: default 3D vehicle flag is off.

bool navigation3dVehicleModelFlagDefaultOff() =>
    !kNavigation3dVehicleModelEnabled;

/// Convenience for tests: default hide-HUD flag is off.

bool navigation3dVehicleHideHudFlagDefaultOff() =>
    !kNavigation3dVehicleHideHudEnabled;

/// Convenience for tests: default debug-placement flag is off.

bool navigation3dVehicleDebugPlacementFlagDefaultOff() =>
    !kNavigation3dVehicleDebugPlacementEnabled;
