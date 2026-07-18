// FLUXIDI NAV-STREETLEVEL-FLUID-MOTION-2 Phase 2A — shared vehicle calibration
// source for the native FollowPuck bridge.
//
// This file is the SINGLE Dart-side authority for the constants used to
// install a Mapbox `LocationPuck3D` on the native side. It delegates to
// `resolveDriverVehicle3dModelSpec` in
// `lib/navigation/presentation/navigation_driver_vehicle_model_layer.dart`
// so the exact same `assetUri`, `scaleMultiplier`, `headingOffsetDeg`, and
// preset identity are used by the custom Dart ModelLayer path and by the
// native `LocationPuck3D` — no duplicated calibration table.

import 'package:flutter/foundation.dart' show visibleForTesting;

import '../presentation/navigation_driver_vehicle_model_layer.dart';
import 'pigeon_native_follow.g.dart';

/// Base model scale multiplier applied when the shared calibration source
/// converts a [DriverVehicle3dModelSpec] into a native
/// `LocationPuck3D` modelScale. The GLB assets ship at unit-meter scale;
/// this factor accounts for Mapbox's meter-based model rendering.
///
/// Kept as a named constant so a future device-driven adjustment lives in
/// exactly one place.
@visibleForTesting
const double kNativeFollowBaseModelScale = 1.0;

/// Builds a Pigeon-ready [NativeVehiclePreset] for the exact map instance
/// [mapInstanceId] using the shared driver vehicle 3D preset resolver.
///
/// Returns `null` when no 3D preset is active (`preset == null`); callers
/// should treat this as "the native puck should stay uninstalled".
NativeVehiclePreset? buildNativeVehiclePreset({
  required String mapInstanceId,
  required DriverVehicle3dPreset? preset,
}) {
  if (preset == null) return null;
  final spec = resolveDriverVehicle3dModelSpec(preset);
  return NativeVehiclePreset(
    mapInstanceId: mapInstanceId,
    presetId: _presetIdOf(preset),
    assetUri: spec.assetUri,
    modelScale: kNativeFollowBaseModelScale * spec.scaleMultiplier,
    yawOffsetDegrees: spec.headingOffsetDeg,
  );
}

/// Stable identity string per preset. Not user-visible; used by the native
/// side to short-circuit redundant puck reinstalls when the preset did not
/// actually change.
String _presetIdOf(DriverVehicle3dPreset preset) {
  switch (preset) {
    case DriverVehicle3dPreset.fluxidiTaxi:
      return 'fluxidiTaxi';
    case DriverVehicle3dPreset.classicFlyingTaxi:
      return 'classicFlyingTaxi';
  }
}
