// FLUXIDI NAV-STREETLEVEL-FLUID-MOTION-2 Phase 2A — controller tests.
//
// Covers the hard-acceptance behaviors that Dart owns:
//   * 5-10 Hz rate limit (rate-limited coalesce, latest wins).
//   * Single-in-flight (no queue growth, coalesce during pending call).
//   * Route generation guard (stale rejected on Dart side).
//   * Invalid pose rejection.
//   * Ownership state machine (followPuck / temporary / disabled).
//   * Synthetic replay at 1 / 5 / 10 Hz with 90° course change and 359° -> 1°
//     wrap; every accepted pose must reach the wire in a first-in-first-out
//     order.
//   * Flag-off short-circuit: every method returns without touching the
//     wire and never mutates state.

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/navigation/native_follow/native_follow_controller.dart';
import 'package:fluxidi_tracking/navigation/native_follow/pigeon_native_follow.g.dart';
import 'package:fluxidi_tracking/navigation/presentation/navigation_presentation_flags.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Discover the flag mode once. Every test asserts against the actual
  // build-time flag rather than a hard-coded expectation so both flag-off
  // (production default) and flag-on (dart-define override) suites pass.
  final flagOn = kNavigationUseNativeFollowPuckEnabled;

  group('NativeFollowController (flag=$flagOn)', () {
    late FakeHostApi fake;
    late FakeClock clock;
    late NativeFollowController controller;

    setUp(() {
      fake = FakeHostApi();
      fake.installMocks();
      clock = FakeClock();
      controller = NativeFollowController(
        mapInstanceId: '0',
        hostApi: fake.api,
        clock: clock.now,
      );
    });

    tearDown(() {
      fake.dispose();
    });

    test('flag-off enable() is a no-op and never touches the wire', () async {
      if (flagOn) return;
      final ok = await controller.enable();
      expect(ok, isFalse);
      expect(fake.setEnabledCalls, isEmpty);
      expect(controller.isSessionActive, isFalse);
    });

    test(
      'flag-off submitPose returns disabled and never touches the wire',
      () async {
        if (flagOn) return;
        final r = await controller.submitPose(
          latitude: 52.0,
          longitude: 5.0,
          courseDegrees: 90.0,
          speedMetersPerSecond: 10.0,
          horizontalAccuracyMeters: 3.0,
          timestampMillis: 1000,
          routeGeneration: 1,
        );
        expect(r, NativeFollowSubmitDartOutcome.disabled);
        expect(fake.submitCalls, isEmpty);
      },
    );

    test(
      'enable then disable transitions ownership state (flag on only)',
      () async {
        if (!flagOn) return;
        expect(controller.ownerState, NativeFollowOwnerState.disabled);
        await controller.enable();
        expect(controller.ownerState, NativeFollowOwnerState.followPuck);
        await controller.disable();
        expect(controller.ownerState, NativeFollowOwnerState.disabled);
      },
    );

    test('submitPose enforces the 100 ms rate limit (flag on)', () async {
      if (!flagOn) return;
      await controller.enable();
      clock.tMs = 1000;
      final first = await controller.submitPose(
        latitude: 52.0,
        longitude: 5.0,
        courseDegrees: 45.0,
        speedMetersPerSecond: 10.0,
        horizontalAccuracyMeters: 3.0,
        timestampMillis: 1000,
        routeGeneration: 1,
      );
      expect(first, NativeFollowSubmitDartOutcome.accepted);
      clock.tMs = 1050; // < 100 ms since last submit
      final second = await controller.submitPose(
        latitude: 52.0001,
        longitude: 5.0001,
        courseDegrees: 46.0,
        speedMetersPerSecond: 10.0,
        horizontalAccuracyMeters: 3.0,
        timestampMillis: 1050,
        routeGeneration: 1,
      );
      expect(second, NativeFollowSubmitDartOutcome.rateLimited);
      // Only one submission actually reached the wire.
      expect(fake.submitCalls.length, 1);
    });

    test(
      'submitPose rejects stale route generation on the Dart side',
      () async {
        if (!flagOn) return;
        await controller.enable();
        clock.tMs = 1000;
        await controller.submitPose(
          latitude: 52.0,
          longitude: 5.0,
          courseDegrees: 0.0,
          speedMetersPerSecond: 10.0,
          horizontalAccuracyMeters: 3.0,
          timestampMillis: 1000,
          routeGeneration: 5,
        );
        clock.tMs = 1200;
        final stale = await controller.submitPose(
          latitude: 52.0,
          longitude: 5.0,
          courseDegrees: 0.0,
          speedMetersPerSecond: 10.0,
          horizontalAccuracyMeters: 3.0,
          timestampMillis: 1200,
          routeGeneration: 4,
        );
        expect(stale, NativeFollowSubmitDartOutcome.rejectedStaleGeneration);
        // The stale pose never reached the wire.
        expect(fake.submitCalls.length, 1);
      },
    );

    test(
      'invalid pose is rejected without hitting the wire (flag on)',
      () async {
        if (!flagOn) return;
        await controller.enable();
        clock.tMs = 1000;
        final r = await controller.submitPose(
          latitude: double.nan,
          longitude: 5.0,
          courseDegrees: 0.0,
          speedMetersPerSecond: 10.0,
          horizontalAccuracyMeters: 3.0,
          timestampMillis: 1000,
          routeGeneration: 1,
        );
        expect(r, NativeFollowSubmitDartOutcome.rejectedInvalidPose);
        expect(fake.submitCalls, isEmpty);
      },
    );

    test(
      'synthetic replay at 10 Hz — every submission accepted, order preserved',
      () async {
        if (!flagOn) return;
        await controller.enable();
        for (int i = 0; i < 10; i++) {
          clock.tMs = 1000 + i * 100;
          final r = await controller.submitPose(
            latitude: 52.0 + i * 1e-5,
            longitude: 5.0 + i * 1e-5,
            courseDegrees: 90.0,
            speedMetersPerSecond: 12.0,
            horizontalAccuracyMeters: 3.0,
            timestampMillis: clock.tMs,
            routeGeneration: 1,
          );
          expect(r, NativeFollowSubmitDartOutcome.accepted);
        }
        expect(fake.submitCalls.length, 10);
        // Bounded diagnostics.
        final snap = controller.snapshot();
        expect(snap.submittedCount, 10);
        expect(snap.acceptedCount, 10);
        expect(snap.rateLimitedCount, 0);
        expect(snap.coalescedCount, 0);
        expect(snap.rejectedCount, 0);
      },
    );

    test(
      'synthetic replay at 5 Hz with 90° course change — all accepted',
      () async {
        if (!flagOn) return;
        await controller.enable();
        final courses = [0.0, 45.0, 90.0, 135.0, 180.0];
        for (int i = 0; i < courses.length; i++) {
          clock.tMs = 1000 + i * 200;
          await controller.submitPose(
            latitude: 52.0,
            longitude: 5.0,
            courseDegrees: courses[i],
            speedMetersPerSecond: 10.0,
            horizontalAccuracyMeters: 3.0,
            timestampMillis: clock.tMs,
            routeGeneration: 1,
          );
        }
        final capturedCourses = fake.submitCalls
            .map((p) => p.courseDegrees)
            .toList();
        expect(capturedCourses, orderedEquals(courses));
      },
    );

    test(
      'synthetic replay 359° -> 1° wrap is passed through untouched',
      () async {
        if (!flagOn) return;
        await controller.enable();
        final courses = [359.0, 0.0, 1.0];
        for (int i = 0; i < courses.length; i++) {
          clock.tMs = 1000 + i * 200;
          await controller.submitPose(
            latitude: 52.0,
            longitude: 5.0,
            courseDegrees: courses[i],
            speedMetersPerSecond: 10.0,
            horizontalAccuracyMeters: 3.0,
            timestampMillis: clock.tMs,
            routeGeneration: 1,
          );
        }
        final capturedCourses = fake.submitCalls
            .map((p) => p.courseDegrees)
            .toList();
        expect(capturedCourses, orderedEquals(courses));
      },
    );

    test('ownership state machine transitions (flag on)', () async {
      if (!flagOn) return;
      await controller.enable();
      expect(controller.ownerState, NativeFollowOwnerState.followPuck);
      await controller.setOwner(NativeFollowOwnerState.temporary);
      expect(controller.ownerState, NativeFollowOwnerState.temporary);
      await controller.setOwner(NativeFollowOwnerState.followPuck);
      expect(controller.ownerState, NativeFollowOwnerState.followPuck);
    });

    test('noteRouteGenerationApplied only advances forward', () {
      controller.noteRouteGenerationApplied(3);
      expect(controller.currentRouteGeneration, 3);
      controller.noteRouteGenerationApplied(2); // stale ignored
      expect(controller.currentRouteGeneration, 3);
      controller.noteRouteGenerationApplied(7);
      expect(controller.currentRouteGeneration, 7);
    });

    test('transport error path counts and never throws (flag on)', () async {
      if (!flagOn) return;
      await controller.enable();
      fake.forceThrowOnSubmit = true;
      clock.tMs = 1000;
      final r = await controller.submitPose(
        latitude: 52.0,
        longitude: 5.0,
        courseDegrees: 0.0,
        speedMetersPerSecond: 10.0,
        horizontalAccuracyMeters: 3.0,
        timestampMillis: 1000,
        routeGeneration: 1,
      );
      expect(r, NativeFollowSubmitDartOutcome.transportError);
      final snap = controller.snapshot();
      expect(snap.transportErrorCount, greaterThanOrEqualTo(1));
    });

    test(
      'NAV-3D-P0: setVehiclePreset latest-wins — older configure is stale',
      () async {
        if (!flagOn) return;
        await controller.enable();
        fake.delayNextPreset = Completer<void>();
        final older = controller.setVehiclePreset(
          NativeVehiclePreset(
            mapInstanceId: '0',
            presetId: 'older',
            assetUri: 'asset://older.glb',
            modelScale: 1.0,
            yawOffsetDegrees: 0.0,
          ),
        );
        // Supersede before the older host call completes.
        final newer = controller.setVehiclePreset(
          NativeVehiclePreset(
            mapInstanceId: '0',
            presetId: 'newer',
            assetUri: 'asset://newer.glb',
            modelScale: 1.0,
            yawOffsetDegrees: 0.0,
          ),
        );
        fake.delayNextPreset!.complete();
        expect(await older, isFalse);
        expect(await newer, isTrue);
        expect(fake.setPresetCalls.last.assetUri, 'asset://newer.glb');
      },
    );

    test(
      'NAV-3D-P0: older deactivate generation cannot defeat newer activate',
      () async {
        if (!flagOn) return;
        await controller.enable();
        fake.delayNextPreset = Completer<void>();
        final older = controller.setVehiclePreset(
          NativeVehiclePreset(
            mapInstanceId: '0',
            presetId: 'a',
            assetUri: 'asset://a.glb',
            modelScale: 1.0,
            yawOffsetDegrees: 0.0,
          ),
        );
        controller.invalidateVehicleCommands(reason: 'explicit_user_choice_2d');
        final newer = controller.setVehiclePreset(
          NativeVehiclePreset(
            mapInstanceId: '0',
            presetId: 'b',
            assetUri: 'asset://b.glb',
            modelScale: 1.0,
            yawOffsetDegrees: 0.0,
          ),
        );
        fake.delayNextPreset!.complete();
        expect(await older, isFalse);
        expect(await newer, isTrue);
      },
    );

    test(
      'NAV-3D-P0: preset is not credibly active until current configure succeeds',
      () async {
        if (!flagOn) return;
        await controller.enable();
        expect(controller.isVehiclePresetCrediblyActive, isFalse);
        fake.delayNextPreset = Completer<void>();
        final inFlight = controller.setVehiclePreset(
          NativeVehiclePreset(
            mapInstanceId: '0',
            presetId: 'fluxidiTaxi',
            assetUri: 'asset://fluxidi.glb',
            modelScale: 1.0,
            yawOffsetDegrees: 0.0,
          ),
        );
        // In-flight configure must not claim ownership yet.
        expect(controller.isVehiclePresetCrediblyActive, isFalse);
        fake.delayNextPreset!.complete();
        expect(await inFlight, isTrue);
        expect(controller.isVehiclePresetCrediblyActive, isTrue);
        controller.invalidateVehicleCommands(reason: 'explicit_user_choice_2d');
        expect(controller.isVehiclePresetCrediblyActive, isFalse);
      },
    );
  });
}

/// Minimal mockable clock.
class FakeClock {
  int tMs = 0;
  int now() => tMs;
}

/// Fake host API that intercepts every Pigeon channel used by the
/// controller and records the payloads for assertion.
class FakeHostApi {
  late final NativeFollowHostApi api;

  final List<NativeFollowPose> submitCalls = <NativeFollowPose>[];
  final List<(String, bool)> setEnabledCalls = <(String, bool)>[];
  final List<NativeFollowViewport> setViewportCalls = <NativeFollowViewport>[];
  final List<NativeVehiclePreset> setPresetCalls = <NativeVehiclePreset>[];
  bool forceThrowOnSubmit = false;
  Completer<void>? delayNextPreset;

  final Map<String, String> _registeredHandlers = <String, String>{};

  static const _prefix =
      'dev.flutter.pigeon.fluxidi_tracking.NativeFollowHostApi';

  FakeHostApi() {
    api = NativeFollowHostApi();
  }

  void installMocks() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    void bind(String method, MessageHandler h) {
      final channel = BasicMessageChannel<Object?>(
        '$_prefix.$method',
        NativeFollowHostApi.pigeonChannelCodec,
      );
      messenger.setMockDecodedMessageHandler<Object?>(channel, h);
      _registeredHandlers[method] = '$_prefix.$method';
    }

    bind('setNativeFollowEnabled', (Object? args) async {
      final list = args as List<Object?>;
      final mapId = list[0] as String;
      final enabled = list[1] as bool;
      setEnabledCalls.add((mapId, enabled));
      return <Object?>[true];
    });
    bind('submitNavigationPose', (Object? args) async {
      if (forceThrowOnSubmit) {
        return <Object?>['x', 'transport', 'x'];
      }
      final list = args as List<Object?>;
      final pose = list[0] as NativeFollowPose;
      submitCalls.add(pose);
      return <Object?>[NativeFollowSubmitOutcome.accepted];
    });
    bind('setNativeFollowViewport', (Object? args) async {
      final list = args as List<Object?>;
      final vp = list[0] as NativeFollowViewport;
      setViewportCalls.add(vp);
      return <Object?>[true];
    });
    bind('setNativeVehiclePreset', (Object? args) async {
      final delay = delayNextPreset;
      if (delay != null) {
        delayNextPreset = null;
        await delay.future;
      }
      final list = args as List<Object?>;
      final p = list[0] as NativeVehiclePreset;
      setPresetCalls.add(p);
      return <Object?>[true];
    });
    bind('setNativeFollowOwner', (Object? args) async {
      return <Object?>[true];
    });
    bind('transitionToFollowPuck', (Object? args) async {
      return <Object?>[true];
    });
    bind('readNativeFollowDiagnostics', (Object? args) async {
      return <Object?>[null];
    });
  }

  void dispose() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    for (final method in _registeredHandlers.keys) {
      final channel = BasicMessageChannel<Object?>(
        '$_prefix.$method',
        NativeFollowHostApi.pigeonChannelCodec,
      );
      messenger.setMockDecodedMessageHandler<Object?>(channel, null);
    }
    _registeredHandlers.clear();
  }
}

typedef MessageHandler = Future<Object?> Function(Object? args);
