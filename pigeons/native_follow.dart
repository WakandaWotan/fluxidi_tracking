// FLUXIDI NAV-STREETLEVEL-FLUID-MOTION-2 Phase 2A — Pigeon HostApi definition.
//
// Typed Dart <-> Android bridge for feeding Fluxidi's route-snapped /
// predicted pose to a custom Mapbox `LocationProvider` on the native
// MapView so `FollowPuckViewportState` + `LocationPuck3D` can own continuous
// camera + puck rendering without any Dart-side `setCamera` / `easeTo` /
// `flyTo` calls during passive follow.
//
// Regenerate with:
//   dart run pigeon --input pigeons/native_follow.dart
//
// Outputs are checked in:
//   lib/navigation/native_follow/pigeon_native_follow.g.dart
//   android/app/src/main/kotlin/com/fluxidi/tracking/nativefollow/PigeonNativeFollow.g.kt

import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/navigation/native_follow/pigeon_native_follow.g.dart',
    dartOptions: DartOptions(),
    kotlinOut:
        'android/app/src/main/kotlin/com/fluxidi/tracking/nativefollow/PigeonNativeFollow.g.kt',
    kotlinOptions: KotlinOptions(package: 'com.fluxidi.tracking.nativefollow'),
    dartPackageName: 'fluxidi_tracking',
  ),
)
/// Discrete outcomes for a single `submitNavigationPose` call.
///
/// The Dart controller uses [NativeFollowSubmitOutcome] to update the
/// bounded `submitted / accepted / coalesced / rejected` diagnostic
/// counters. No coordinates cross the wire in either direction beyond the
/// pose itself.
enum NativeFollowSubmitOutcome {
  /// Pose was accepted by the custom `LocationProvider` and forwarded to the
  /// Mapbox location component (and via `FollowPuck` to the camera).
  accepted,

  /// A newer pose was in-flight or already latched; the pose was dropped
  /// intentionally as a latest-wins coalesce (not a failure).
  coalesced,

  /// `mapInstanceId` is not currently registered in the MapView registry.
  rejectedUnknownMap,

  /// The pose's `routeGeneration` is older than the currently-latched
  /// generation.
  rejectedStaleGeneration,

  /// The pose failed a non-negotiable validity check (NaN, out-of-range lat/
  /// lon, negative accuracy, non-finite timestamp).
  rejectedInvalidPose,

  /// Native follow is disabled for this `mapInstanceId`.
  rejectedNotEnabled,
}

/// Discrete high-level lifecycle transitions of the native custom
/// `LocationProvider` for one map instance.
enum NativeFollowProviderLifecycle {
  /// A custom provider was installed on the exact MapView associated with
  /// [mapInstanceId] and the map's location component now consumes Fluxidi
  /// poses.
  installed,

  /// A custom provider was uninstalled (either by explicit
  /// `setNativeFollowEnabled(false)` or by MapView disposal) and the stock
  /// Mapbox provider was restored.
  uninstalled,

  /// The MapView for [mapInstanceId] disappeared from the registry (weak
  /// reference died or `dispose()` fired). The provider is torn down.
  mapDisposed,
}

/// One authoritative pose from Fluxidi's navigation engine (route-snapped
/// display point + smoothed course + measured speed + accuracy). Only bounded
/// scalars cross the wire; no coordinate strings, no route geometry.
class NativeFollowPose {
  NativeFollowPose({
    required this.mapInstanceId,
    required this.latitude,
    required this.longitude,
    required this.courseDegrees,
    required this.speedMetersPerSecond,
    required this.horizontalAccuracyMeters,
    required this.timestampMillis,
    required this.routeGeneration,
  });

  /// Plugin-owned map instance id (the same string mapbox_maps_flutter's
  /// `channelSuffix` uses internally).
  final String mapInstanceId;
  final double latitude;
  final double longitude;
  final double courseDegrees;
  final double speedMetersPerSecond;
  final double horizontalAccuracyMeters;
  final int timestampMillis;
  final int routeGeneration;
}

/// Viewport-shape target: zoom + pitch, plus optional edge insets when the
/// native `FollowPuckViewportState` supports padding (Mapbox 11.x does).
class NativeFollowViewport {
  NativeFollowViewport({
    required this.mapInstanceId,
    required this.zoom,
    required this.pitch,
    this.paddingTop,
    this.paddingBottom,
    this.paddingLeft,
    this.paddingRight,
  });

  final String mapInstanceId;
  final double zoom;
  final double pitch;
  final double? paddingTop;
  final double? paddingBottom;
  final double? paddingLeft;
  final double? paddingRight;
}

/// One-time vehicle preset install for the native `LocationPuck3D`. Reuses
/// the shared Fluxidi calibration source; no calibration constants are
/// re-declared on the Kotlin side.
class NativeVehiclePreset {
  NativeVehiclePreset({
    required this.mapInstanceId,
    required this.presetId,
    required this.assetUri,
    required this.modelScale,
    required this.yawOffsetDegrees,
  });

  final String mapInstanceId;
  final String presetId;
  final String assetUri;
  final double modelScale;
  final double yawOffsetDegrees;
}

/// Latched follow-owner intent for one map instance.
enum NativeFollowOwner {
  /// FollowPuck owns the camera and the vehicle puck.
  followPuck,

  /// A temporary explicit owner is active (manual view +/-, recenter,
  /// overview, style_restore). The bridge does not touch the viewport while
  /// this state is latched; Dart is expected to restore `followPuck` after
  /// the temporary action completes.
  temporary,

  /// Native follow is disabled for this map.
  disabled,
}

/// Instantaneous diagnostics for one map's native-follow session.
class NativeFollowDiagnostics {
  NativeFollowDiagnostics({
    required this.mapInstanceId,
    required this.owner,
    required this.acceptedPoseCount,
    required this.coalescedPoseCount,
    required this.rejectedPoseCount,
    required this.viewportTransitionCount,
    required this.providerInstallCount,
    required this.providerUninstallCount,
    required this.currentRouteGeneration,
    required this.puckReady,
  });

  final String mapInstanceId;
  final NativeFollowOwner owner;
  final int acceptedPoseCount;
  final int coalescedPoseCount;
  final int rejectedPoseCount;
  final int viewportTransitionCount;
  final int providerInstallCount;
  final int providerUninstallCount;
  final int currentRouteGeneration;
  final bool puckReady;
}

@HostApi()
abstract class NativeFollowHostApi {
  /// Enables / disables the native-follow pipeline for one map instance.
  ///
  /// Returns `true` if the requested state is achievable on the current
  /// registration (i.e. the MapView exists and is in a valid lifecycle).
  /// Returns `false` if the map id is unknown; in that case the request is
  /// remembered and applied on the next `onMapViewRegistered` for the same
  /// id, so start-up race conditions do not silently drop the request.
  @async
  bool setNativeFollowEnabled(String mapInstanceId, bool enabled);

  /// Submits one route-snapped / predicted pose to the custom Mapbox
  /// `LocationProvider`. Callers must rate-limit to 5-10 Hz.
  @async
  NativeFollowSubmitOutcome submitNavigationPose(NativeFollowPose pose);

  /// Updates the current `FollowPuckViewportState` zoom + pitch (+ optional
  /// padding). No-op when native follow is disabled for [mapInstanceId].
  @async
  bool setNativeFollowViewport(NativeFollowViewport viewport);

  /// Installs / hot-swaps the `LocationPuck3D` GLB + calibration for one
  /// map. Called once per active preset change from Dart; no-op if the
  /// preset is byte-identical to the currently-installed one.
  @async
  bool setNativeVehiclePreset(NativeVehiclePreset preset);

  /// Latches a temporary owner (view +/-, recenter, overview, style_restore).
  /// While `temporary` is set, the native bridge does not fight the Dart
  /// camera writer; Dart is responsible for calling
  /// `setNativeFollowOwner(mapInstanceId, followPuck)` to return.
  @async
  bool setNativeFollowOwner(String mapInstanceId, NativeFollowOwner owner);

  /// Requests a viewport transition back to `FollowPuckViewportState` using
  /// `DefaultViewportTransition`. Returns `true` when the transition is
  /// scheduled; `false` when the target is already active or the map is
  /// disabled / unknown.
  @async
  bool transitionToFollowPuck(String mapInstanceId);

  /// Snapshot of the bounded diagnostic counters for [mapInstanceId].
  /// Returns `null` when the map is not registered.
  @async
  NativeFollowDiagnostics? readNativeFollowDiagnostics(String mapInstanceId);
}
