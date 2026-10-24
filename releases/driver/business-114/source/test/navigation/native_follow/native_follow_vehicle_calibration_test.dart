// FLUXIDI NAV-STREETLEVEL-FLUID-MOTION-2 Phase 2A — shared calibration tests.

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/navigation/native_follow/native_follow_vehicle_calibration.dart';
import 'package:fluxidi_tracking/navigation/presentation/navigation_driver_vehicle_model_layer.dart';

void main() {
  group('buildNativeVehiclePreset', () {
    test('returns null when preset is null', () {
      final result = buildNativeVehiclePreset(mapInstanceId: '0', preset: null);
      expect(result, isNull);
    });

    test('produces a Pigeon-ready preset from the fluxidiTaxi shared spec', () {
      final result = buildNativeVehiclePreset(
        mapInstanceId: '42',
        preset: DriverVehicle3dPreset.fluxidiTaxi,
      );
      expect(result, isNotNull);
      expect(result!.mapInstanceId, '42');
      expect(result.presetId, 'fluxidiTaxi');
      expect(result.assetUri, kDriverVehicleModelAssetUri);
      expect(result.modelScale, kNativeFollowBaseModelScale * 1.0);
      expect(result.yawOffsetDegrees, 0.0);
    });

    test('produces a Pigeon-ready preset from the classicFlyingTaxi spec', () {
      final result = buildNativeVehiclePreset(
        mapInstanceId: '0',
        preset: DriverVehicle3dPreset.classicFlyingTaxi,
      );
      expect(result, isNotNull);
      expect(result!.presetId, 'classicFlyingTaxi');
      expect(result.assetUri, kDriverVehicleClassicFlyingTaxiAssetUri);
      expect(result.yawOffsetDegrees, 180.0);
    });

    test('preset id and asset uri are stable per preset value', () {
      final a = buildNativeVehiclePreset(
        mapInstanceId: '0',
        preset: DriverVehicle3dPreset.fluxidiTaxi,
      )!;
      final b = buildNativeVehiclePreset(
        mapInstanceId: '0',
        preset: DriverVehicle3dPreset.fluxidiTaxi,
      )!;
      expect(a.presetId, b.presetId);
      expect(a.assetUri, b.assetUri);
      expect(a.modelScale, b.modelScale);
      expect(a.yawOffsetDegrees, b.yawOffsetDegrees);
    });
  });
}
