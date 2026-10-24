import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/navigation/presentation/navigation_driver_vehicle_model_layer.dart';

DriverVisualOwnership ownershipFor({
  required DriverVehiclePresentationChoice choice,
  bool followLiveActive = true,
  bool showDriverHudOverlay = true,
  bool hideHudFlagEnabled = true,
  bool driver3dVisualReady = false,
  bool sessionFallback2d = false,
  bool presentation3dIntentActive = true,
}) {
  return resolveDriverVisualOwnership(
    followLiveActive: followLiveActive,
    showDriverHudOverlay: showDriverHudOverlay,
    hideHudFlagEnabled: hideHudFlagEnabled,
    driver3dVisualReady: driver3dVisualReady,
    explicit2dFallback: sessionFallback2d,
    selectedVehiclePresentation: choice,
    runtimeFallbackState: resolveDriverVehicleRuntimeFallbackState(
      selectedVehiclePresentation: choice,
      sessionFallback2d: sessionFallback2d,
    ),
    presentation3dIntentActive: presentation3dIntentActive,
  );
}

void main() {
  group('NAV-3D-INSTANT-SWITCH (Part A) immediate ownership', () {
    test('1. 2D -> Fluxidi tap: 2D remains until activation confirmed', () {
      // Before the tap: normal 2D ownership.
      final before = ownershipFor(
        choice: DriverVehiclePresentationChoice.taxi2d,
      );
      expect(before.owner, DriverVisualOwner.hud2d);

      // After the tap: selection alone must not blank the vehicle.
      final after = ownershipFor(
        choice: DriverVehiclePresentationChoice.fluxidi3d,
        driver3dVisualReady: false,
      );
      expect(after.owner, DriverVisualOwner.hud2d);
      expect(after.hudMounted, isTrue);
      expect(after.mapbox2dVisible, isFalse);
      expect(after.reason, 'hud2d_fallback');
    });

    test('2. 2D -> Classic tap: same safe handoff (2D until confirmed)', () {
      final after = ownershipFor(
        choice: DriverVehiclePresentationChoice.classic3d,
        driver3dVisualReady: false,
      );
      expect(after.owner, DriverVisualOwner.hud2d);
      expect(after.hudMounted, isTrue);
      expect(after.mapbox2dVisible, isFalse);
    });

    test('3. 3D -> 2D tap: immediate 2D owner even while model reports ready',
        () {
      final after = ownershipFor(
        choice: DriverVehiclePresentationChoice.taxi2d,
        driver3dVisualReady: true,
      );
      expect(after.owner, DriverVisualOwner.hud2d);
      expect(after.hudMounted, isTrue);
      expect(after.model3dActivePresentation, isFalse);

      final hudDisabled = ownershipFor(
        choice: DriverVehiclePresentationChoice.taxi2d,
        driver3dVisualReady: true,
        showDriverHudOverlay: false,
      );
      expect(hudDisabled.owner, DriverVisualOwner.mapbox2d);
    });

    test('4. zoom change after vehicle switch: ownership unchanged', () {
      // The ownership scope has no zoom/camera input: repeated evaluation
      // with identical scope inputs is the zoom-invariance guarantee.
      final owners = List.generate(
        5,
        (_) => ownershipFor(
          choice: DriverVehiclePresentationChoice.fluxidi3d,
          driver3dVisualReady: true,
        ).owner,
      );
      expect(owners.toSet(), {DriverVisualOwner.model3d});
    });

    test('failed 3D activation falls back to a temporary 2D owner', () {
      final fallback = ownershipFor(
        choice: DriverVehiclePresentationChoice.fluxidi3d,
        sessionFallback2d: true,
      );
      expect(fallback.owner, DriverVisualOwner.hud2d);
      expect(fallback.reason, 'temporary_2d_fallback');
    });

    test('legacy callers (no explicit choice) keep visual-ready gating', () {
      final legacy = resolveDriverVisualOwnership(
        followLiveActive: true,
        showDriverHudOverlay: true,
        hideHudFlagEnabled: true,
        driver3dVisualReady: false,
        explicit2dFallback: false,
      );
      expect(legacy.owner, DriverVisualOwner.hud2d);
    });
  });

  group('NAV-3D-SCALE (Part B) screen-footprint scale curve', () {
    test('5. low zoom: 3D footprint matches the 2D taxi target footprint', () {
      for (final zoom in [15.0, 16.0, 16.5, 17.0]) {
        expect(
          resolveNav3dTargetFootprintPx(zoom),
          kNav3dScaleFootprintLowPx,
          reason: 'zoom=$zoom',
        );
      }
      // The resolved model scale realizes that footprint (bigger physical
      // scale at lower zoom, not smaller).
      final z165 = resolveDriverVehicle3dFootprintScale(
        appliedZoom: 16.5,
        preset: DriverVehicle3dPreset.fluxidiTaxi,
      );
      final z191 = resolveDriverVehicle3dFootprintScale(
        appliedZoom: 19.1,
        preset: DriverVehicle3dPreset.fluxidiTaxi,
      );
      expect(z165.resolvedScale, greaterThan(z191.resolvedScale));
      expect(z165.targetFootprintPx, kNav3dScaleFootprintLowPx);
    });

    test('6. street level: footprint and scale are hard capped', () {
      for (final zoom in [20.5, 21.0, 21.6, 22.0]) {
        final resolution = resolveDriverVehicle3dFootprintScale(
          appliedZoom: zoom,
          preset: DriverVehicle3dPreset.fluxidiTaxi,
        );
        expect(
          resolution.targetFootprintPx,
          kNav3dScaleFootprintHighPx,
          reason: 'zoom=$zoom',
        );
        expect(
          resolution.resolvedScale,
          inInclusiveRange(kNav3dScaleHardMin, kNav3dScaleHardMax),
          reason: 'zoom=$zoom',
        );
      }
      // Street level is smaller than the previous unbounded look (was 2.75
      // at zoom 21.0): capped cockpit presence, no giant vehicle.
      final street = resolveDriverVehicle3dFootprintScale(
        appliedZoom: 21.0,
        preset: DriverVehicle3dPreset.fluxidiTaxi,
      );
      expect(street.resolvedScale, lessThan(2.0));
    });

    test('smooth clamped curve: monotonic footprint, no abrupt jumps', () {
      double? previousPx;
      double? previousScale;
      for (var zoom = 15.0; zoom <= 22.0; zoom += 0.05) {
        final px = resolveNav3dTargetFootprintPx(zoom);
        final scale = resolveDriverVehicle3dFootprintScale(
          appliedZoom: zoom,
          preset: DriverVehicle3dPreset.fluxidiTaxi,
        ).resolvedScale;
        if (previousPx != null) {
          // Projected footprint grows monotonically with zoom.
          expect(px, greaterThanOrEqualTo(previousPx), reason: 'zoom=$zoom');
          // No sudden jump: bounded relative step per 0.05 zoom.
          expect(
            (px - previousPx).abs() / previousPx,
            lessThan(0.03),
            reason: 'footprint jump at zoom=$zoom',
          );
        }
        if (previousScale != null && scale != previousScale) {
          expect(
            (scale - previousScale).abs() / previousScale,
            lessThan(0.06),
            reason: 'scale jump at zoom=$zoom',
          );
        }
        previousPx = px;
        previousScale = scale;
      }
    });

    test('physical scale never grows with zoom (no giant street vehicle)', () {
      double? previous;
      for (var zoom = 15.0; zoom <= 22.0; zoom += 0.1) {
        final scale = resolveDriverVehicle3dFootprintScale(
          appliedZoom: zoom,
          preset: DriverVehicle3dPreset.classicFlyingTaxi,
        ).resolvedScale;
        if (previous != null) {
          expect(scale, lessThanOrEqualTo(previous + 1e-9), reason: 'z=$zoom');
        }
        previous = scale;
      }
    });

    test('mid-zoom keeps continuity with previous cockpit calibration', () {
      final mid = resolveDriverVehicle3dFootprintScale(
        appliedZoom: 19.1,
        preset: DriverVehicle3dPreset.fluxidiTaxi,
      );
      expect(mid.resolvedScale, closeTo(5.0, 0.15));
    });

    test('both presets are independently calibrated', () {
      for (final preset in DriverVehicle3dPreset.values) {
        final resolution = resolveDriverVehicle3dFootprintScale(
          appliedZoom: 18.7,
          preset: preset,
        );
        expect(resolution.preset, preset);
        final expected = (resolution.baseScale *
                nav3dFootprintMultiplierForPreset(preset) *
                resolveDriverVehicle3dModelSpec(preset).scaleMultiplier)
            .clamp(kNav3dScaleHardMin, kNav3dScaleHardMax);
        expect(resolution.resolvedScale, closeTo(expected, 1e-9));
      }
    });

    test('Classic calibration compensates its smaller GLB footprint', () {
      for (final zoom in [16.5, 18.7, 20.5, 21.6]) {
        final fluxidi = resolveDriverVehicle3dFootprintScale(
          appliedZoom: zoom,
          preset: DriverVehicle3dPreset.fluxidiTaxi,
        );
        final classic = resolveDriverVehicle3dFootprintScale(
          appliedZoom: zoom,
          preset: DriverVehicle3dPreset.classicFlyingTaxi,
        );
        // 1.20 is the measured authored-footprint compensation. The common
        // target curve and max clamp remain unchanged, so it cannot create
        // street-level runaway growth.
        if (fluxidi.resolvedScale > kNav3dScaleHardMin) {
          expect(
            classic.resolvedScale / fluxidi.resolvedScale,
            closeTo(kNav3dClassicFootprintMultiplier, 0.0001),
            reason: 'zoom=$zoom',
          );
        } else {
          // At the highest zoom both presets intentionally converge on the
          // existing hard minimum rather than allowing Classic to grow.
          expect(classic.resolvedScale, kNav3dScaleHardMin);
        }
        expect(
          classic.resolvedScale,
          inInclusiveRange(kNav3dScaleHardMin, kNav3dScaleHardMax),
          reason: 'zoom=$zoom',
        );
      }
    });

    test('preset scale entry point returns the centralized footprint value',
        () {
      final direct = resolveDriverVehicle3dFootprintScale(
        appliedZoom: 20.0,
        preset: DriverVehicle3dPreset.classicFlyingTaxi,
      ).resolvedScale;
      final viaPreset = resolveDriverVehicleModelScaleForPreset(
        appliedZoom: 20.0,
        appliedPitch: 80.0,
        preset: DriverVehicle3dPreset.classicFlyingTaxi,
      );
      expect(viaPreset, [direct, direct, direct]);
    });
  });

  group('NAV-3D-HEADING (Part C) canonical heading source of truth', () {
    test('7. View +/- (camera-scale) alone never changes heading', () {
      final resolution = resolveNav3dModelHeadingForPose(
        requestedBearingDeg: 275.0, // camera bearing at street level
        source: 'camera_scale_cockpit_adjust',
        lastStableBearingDeg: 90.0,
      );
      expect(resolution.bearingDeg, 90.0);
      expect(resolution.headingSource, 'last_stable');
      expect(resolution.updatesStable, isFalse);
      expect(resolution.reason, 'camera_scale_preserves_heading');
    });

    test('camera bearing never becomes vehicle heading on zoom updates', () {
      for (final source in [
        'camera_scale_gps',
        'camera_scale_cockpit_adjust',
        'camera_scale_style_switch',
      ]) {
        final resolution = resolveNav3dModelHeadingForPose(
          requestedBearingDeg: 33.0,
          source: source,
          lastStableBearingDeg: 180.0,
        );
        expect(resolution.bearingDeg, 180.0, reason: source);
        expect(resolution.updatesStable, isFalse, reason: source);
      }
    });

    test('8. route bearing change updates heading smoothly', () {
      final first = resolveNav3dModelHeadingForPose(
        requestedBearingDeg: 90.0,
        source: 'route_snap',
        lastStableBearingDeg: null,
      );
      expect(first.bearingDeg, 90.0);
      expect(first.headingSource, 'route_snapped');
      expect(first.updatesStable, isTrue);

      final next = resolveNav3dModelHeadingForPose(
        requestedBearingDeg: 105.0,
        source: 'route_snap',
        lastStableBearingDeg: first.bearingDeg,
      );
      expect(next.bearingDeg, 105.0);
      expect(next.updatesStable, isTrue);
      expect(next.reason, 'travel_update');
    });

    test('no 180-degree course flip on the same route segment', () {
      final flipped = resolveNav3dModelHeadingForPose(
        requestedBearingDeg: 271.0, // ~180 off the stable 90
        source: 'last_pos',
        lastStableBearingDeg: 90.0,
      );
      expect(flipped.bearingDeg, 90.0);
      expect(flipped.reason, 'course_flip_rejected');
      expect(flipped.updatesStable, isFalse);

      // A trusted route-snapped reversal stays allowed (genuine U-turn).
      final routeReversal = resolveNav3dModelHeadingForPose(
        requestedBearingDeg: 271.0,
        source: 'route_snap',
        lastStableBearingDeg: 90.0,
      );
      expect(routeReversal.bearingDeg, 271.0);
      expect(routeReversal.updatesStable, isTrue);
    });

    test('9. preset swap keeps travel direction, only preset offset differs',
        () {
      const travelBearing = 90.0;
      final fluxidi = resolveDriverVehicle3dModelOrientation(
        rawNavigationBearing: travelBearing,
        preset: DriverVehicle3dPreset.fluxidiTaxi,
      );
      final classic = resolveDriverVehicle3dModelOrientation(
        rawNavigationBearing: travelBearing,
        preset: DriverVehicle3dPreset.classicFlyingTaxi,
      );
      expect(fluxidi.normalizedBearingDeg, classic.normalizedBearingDeg);
      expect(fluxidi.presetOffsetDeg, 0.0);
      expect(classic.presetOffsetDeg, 180.0);
      expect(
        nav3dHeadingAngularDeltaDeg(
          fluxidi.finalRotation[2],
          classic.finalRotation[2],
        ),
        closeTo(180.0, 1e-9),
      );
    });

    test('10. style restore preserves the latest stable bearing', () {
      // Restore first pose replays the last stable travel bearing.
      final replay = resolveNav3dModelHeadingForPose(
        requestedBearingDeg: 132.0,
        source: 'first_pose_style_restore_snapshot',
        lastStableBearingDeg: 132.0,
      );
      expect(replay.bearingDeg, 132.0);

      // If restore has no usable bearing, the stable one is kept.
      final invalid = resolveNav3dModelHeadingForPose(
        requestedBearingDeg: double.nan,
        source: 'first_pose_style_restore_snapshot',
        lastStableBearingDeg: 132.0,
      );
      expect(invalid.bearingDeg, 132.0);
      expect(invalid.headingSource, 'last_stable');
      expect(invalid.reason, 'invalid_bearing');
    });

    test('bearing normalization stays in [0, 360)', () {
      final negative = resolveNav3dModelHeadingForPose(
        requestedBearingDeg: -45.0,
        source: 'route_snap',
        lastStableBearingDeg: null,
      );
      expect(negative.bearingDeg, 315.0);
    });
  });

  group('NAV-3D-OWNERSHIP (Part D) single owner during every switch', () {
    test('11. visibleDriverVisualCount == 1 across all switch states', () {
      for (final choice in DriverVehiclePresentationChoice.values) {
        for (final intent in [false, true]) {
          for (final ready in [false, true]) {
            for (final fallback in [false, true]) {
              for (final hud in [false, true]) {
                final ownership = ownershipFor(
                  choice: choice,
                  presentation3dIntentActive: intent,
                  driver3dVisualReady: ready,
                  sessionFallback2d: fallback,
                  showDriverHudOverlay: hud,
                );
                expect(
                  ownership.visibleDriverVisualCount,
                  1,
                  reason:
                      'choice=$choice intent=$intent ready=$ready '
                      'fallback=$fallback hud=$hud',
                );
                // Never two visuals: HUD mount, Mapbox marker and 3D
                // presentation are mutually exclusive derivations.
                final visuals = [
                  ownership.hudMounted,
                  ownership.mapbox2dVisible,
                  ownership.model3dActivePresentation,
                ].where((v) => v).length;
                expect(visuals, lessThanOrEqualTo(1));
              }
            }
          }
        }
      }
    });
  });
}
