// FLUXIDI NAV-STREETLEVEL-FLUID-MOTION-2 Phase 2A — Dart-side controller for
// the native FollowPuck bridge.
//
// Responsibilities:
//   1. Rate-limit outgoing pose submissions to a bounded 5-10 Hz range.
//   2. Enforce single-in-flight: only one Pigeon call outstanding at a time;
//      newer poses coalesce onto the pending slot. No queue growth ever.
//   3. Route generation guard: reject stale poses on the Dart side too,
//      independent of the native check.
//   4. Ownership state machine: FollowPuck / temporary / disabled.
//   5. Bounded diagnostic counters (submitted / accepted / coalesced /
//      rejected / providerInstall / providerUninstall) exposed for the
//      hard-acceptance assertions in tests + field diagnostics.
//
// This controller does NOT touch the Mapbox controller directly. It only
// speaks to the native side through the typed Pigeon `NativeFollowHostApi`.

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../presentation/navigation_presentation_flags.dart';
import 'pigeon_native_follow.g.dart';

/// Fixed lower / upper bounds for the outbound pose submission rate. The
/// active-navigation Android GPS settings target ~500 ms callbacks, so 5 Hz
/// is the practical floor and 10 Hz is the ceiling the platform channel can
/// sustain across a Flutter <-> Kotlin hop without contention.
const int kNativeFollowMinIntervalMs = 100; // 10 Hz
const int kNativeFollowMaxIntervalMs = 200; // 5 Hz

/// Discrete ownership latches for the follow camera pipeline. Mirrors the
/// Pigeon `NativeFollowOwner` enum but lives in idiomatic Dart so callers
/// do not import wire types.
enum NativeFollowOwnerState { followPuck, temporary, disabled }

/// One aggregated result of a single [NativeFollowController.submitPose]
/// call, decoupled from the Pigeon return type so tests can assert on
/// stable Dart values.
enum NativeFollowSubmitDartOutcome {
  accepted,
  rateLimited,
  coalescedInFlight,
  rejectedUnknownMap,
  rejectedStaleGeneration,
  rejectedInvalidPose,
  rejectedNotEnabled,
  disabled,
  transportError,
}

/// Snapshot of bounded diagnostic counters. Used by tests and by
/// hard-acceptance assertions on the device (zero passive Dart writes,
/// bounded coalesce count, etc.).
@immutable
class NativeFollowDartDiagnostics {
  const NativeFollowDartDiagnostics({
    required this.mapInstanceId,
    required this.owner,
    required this.submittedCount,
    required this.acceptedCount,
    required this.rateLimitedCount,
    required this.coalescedCount,
    required this.rejectedCount,
    required this.transportErrorCount,
    required this.currentRouteGeneration,
    required this.lastSubmitAtMs,
  });

  final String mapInstanceId;
  final NativeFollowOwnerState owner;
  final int submittedCount;
  final int acceptedCount;
  final int rateLimitedCount;
  final int coalescedCount;
  final int rejectedCount;
  final int transportErrorCount;
  final int currentRouteGeneration;
  final int? lastSubmitAtMs;
}

/// Minimal clock indirection so tests inject a deterministic time source.
typedef NativeFollowClock = int Function();

int _defaultClock() => DateTime.now().millisecondsSinceEpoch;

/// Controller managing all Dart-side interactions with the native FollowPuck
/// bridge for one map instance.
class NativeFollowController {
  NativeFollowController({
    required this.mapInstanceId,
    NativeFollowHostApi? hostApi,
    NativeFollowClock clock = _defaultClock,
    int minIntervalMs = kNativeFollowMinIntervalMs,
    int maxIntervalMs = kNativeFollowMaxIntervalMs,
  }) : _hostApi = hostApi ?? NativeFollowHostApi(),
       _clock = clock,
       _minIntervalMs = minIntervalMs,
       _maxIntervalMs = maxIntervalMs,
       assert(minIntervalMs > 0),
       assert(maxIntervalMs >= minIntervalMs);

  /// Plugin-owned map instance id — the same string
  /// `MapboxMapController.channelSuffix` uses on the Kotlin side.
  final String mapInstanceId;

  final NativeFollowHostApi _hostApi;
  final NativeFollowClock _clock;
  final int _minIntervalMs;
  final int _maxIntervalMs;

  bool _enabled = false;
  NativeFollowOwnerState _owner = NativeFollowOwnerState.disabled;
  int _currentRouteGeneration = 0;
  bool _submitInFlight = false;
  int? _lastSubmitAtMs;
  /// NAV-3D-P0: latest-wins generation for vehicle preset / deactivate commands.
  int _vehicleCommandGeneration = 0;
  bool _vehiclePresetAcknowledged = false;
  int? _acknowledgedVehicleCommandGeneration;

  int _submittedCount = 0;
  int _acceptedCount = 0;
  int _rateLimitedCount = 0;
  int _coalescedCount = 0;
  int _rejectedCount = 0;
  int _transportErrorCount = 0;

  /// Whether the controller has an active native-follow session (flag on
  /// AND the caller has called [enable]).
  bool get isSessionActive => kNavigationUseNativeFollowPuckEnabled && _enabled;

  /// NAV-3D-P0: true only when the latest configure generation succeeded and
  /// has not been superseded by a newer configure/deactivate.
  bool get isVehiclePresetCrediblyActive =>
      isSessionActive &&
      _vehiclePresetAcknowledged &&
      _acknowledgedVehicleCommandGeneration == _vehicleCommandGeneration;

  /// Dart-visible ownership state.
  NativeFollowOwnerState get ownerState => _owner;

  /// Most recent Dart-tracked route generation.
  int get currentRouteGeneration => _currentRouteGeneration;

  /// Enables the native-follow pipeline for this map. No-op when the
  /// [kNavigationUseNativeFollowPuckEnabled] build flag is false.
  Future<bool> enable() async {
    if (!kNavigationUseNativeFollowPuckEnabled) return false;
    if (_enabled) return true;
    try {
      await _hostApi.setNativeFollowEnabled(mapInstanceId, true);
    } catch (_) {
      _transportErrorCount += 1;
      return false;
    }
    _enabled = true;
    _owner = NativeFollowOwnerState.followPuck;
    return true;
  }

  Future<void> disable() async {
    if (!_enabled) {
      _owner = NativeFollowOwnerState.disabled;
      return;
    }
    invalidateVehicleCommands(reason: 'native_follow_disable');
    try {
      await _hostApi.setNativeFollowEnabled(mapInstanceId, false);
    } catch (_) {
      _transportErrorCount += 1;
    }
    _enabled = false;
    _owner = NativeFollowOwnerState.disabled;
    _clearVehiclePresetAcknowledgement();
  }

  /// Installs / hot-swaps the native LocationPuck3D preset.
  ///
  /// NAV-3D-P0-PERSISTENT-VEHICLE-OWNERSHIP-1: latest-wins — an older in-flight
  /// [setVehiclePreset] or [clearVehiclePreset] completion cannot overwrite a
  /// newer command. Acknowledgement is stored only for the current generation.
  Future<bool> setVehiclePreset(NativeVehiclePreset preset) async {
    if (!kNavigationUseNativeFollowPuckEnabled) return false;
    assert(preset.mapInstanceId == mapInstanceId);
    final generation = ++_vehicleCommandGeneration;
    // Starting a new configure immediately makes any prior ack non-current so
    // ownership cannot claim native3d while the command is still in flight.
    debugPrint(
      '[NAV_3D_NATIVE_COMMAND] generation=$generation command=configure '
      'preset=${preset.assetUri} result=started reason=set_vehicle_preset',
    );
    try {
      final ok = await _hostApi.setNativeVehiclePreset(preset);
      if (generation != _vehicleCommandGeneration) {
        debugPrint(
          '[NAV_3D_NATIVE_COMMAND] generation=$generation command=configure '
          'preset=${preset.assetUri} result=stale reason=superseded',
        );
        return false;
      }
      if (ok) {
        _vehiclePresetAcknowledged = true;
        _acknowledgedVehicleCommandGeneration = generation;
      } else {
        _clearVehiclePresetAcknowledgement();
      }
      debugPrint(
        '[NAV_3D_NATIVE_COMMAND] generation=$generation command=configure '
        'preset=${preset.assetUri} result=${ok ? 'success' : 'failed'} '
        'reason=${ok ? 'applied' : 'host_rejected'}',
      );
      return ok;
    } catch (_) {
      _transportErrorCount += 1;
      if (generation == _vehicleCommandGeneration) {
        _clearVehiclePresetAcknowledgement();
        debugPrint(
          '[NAV_3D_NATIVE_COMMAND] generation=$generation command=configure '
          'preset=${preset.assetUri} result=failed reason=transport_error',
        );
      }
      return false;
    }
  }

  /// NAV-3D-P0: bump the vehicle-command generation so any in-flight configure
  /// is treated as stale (used when navigation stops or user selects 2D).
  void invalidateVehicleCommands({required String reason}) {
    final generation = ++_vehicleCommandGeneration;
    _clearVehiclePresetAcknowledgement();
    debugPrint(
      '[NAV_3D_NATIVE_COMMAND] generation=$generation command=deactivate '
      'preset=none result=started reason=$reason',
    );
  }

  void _clearVehiclePresetAcknowledgement() {
    _vehiclePresetAcknowledged = false;
    _acknowledgedVehicleCommandGeneration = null;
  }

  Future<bool> setViewport(NativeFollowViewport viewport) async {
    if (!kNavigationUseNativeFollowPuckEnabled) return false;
    assert(viewport.mapInstanceId == mapInstanceId);
    try {
      return await _hostApi.setNativeFollowViewport(viewport);
    } catch (_) {
      _transportErrorCount += 1;
      return false;
    }
  }

  Future<bool> setOwner(NativeFollowOwnerState newOwner) async {
    if (!kNavigationUseNativeFollowPuckEnabled) return false;
    if (_owner == newOwner) return true;
    final wire = _toWireOwner(newOwner);
    try {
      await _hostApi.setNativeFollowOwner(mapInstanceId, wire);
    } catch (_) {
      _transportErrorCount += 1;
      return false;
    }
    _owner = newOwner;
    return true;
  }

  Future<bool> transitionToFollowPuck() async {
    if (!kNavigationUseNativeFollowPuckEnabled) return false;
    try {
      final ok = await _hostApi.transitionToFollowPuck(mapInstanceId);
      if (ok) _owner = NativeFollowOwnerState.followPuck;
      return ok;
    } catch (_) {
      _transportErrorCount += 1;
      return false;
    }
  }

  /// Advances the Dart-tracked route generation. Called by the driver page
  /// on every successful reroute so subsequent poses carry the new
  /// generation.
  void noteRouteGenerationApplied(int newGeneration) {
    if (newGeneration > _currentRouteGeneration) {
      _currentRouteGeneration = newGeneration;
    }
  }

  /// Submits one pose to the native side. Returns the aggregated Dart
  /// outcome. This method is non-throwing.
  Future<NativeFollowSubmitDartOutcome> submitPose({
    required double latitude,
    required double longitude,
    required double courseDegrees,
    required double speedMetersPerSecond,
    required double horizontalAccuracyMeters,
    required int timestampMillis,
    required int routeGeneration,
  }) async {
    if (!kNavigationUseNativeFollowPuckEnabled) {
      return NativeFollowSubmitDartOutcome.disabled;
    }
    if (!_enabled) {
      _rejectedCount += 1;
      return NativeFollowSubmitDartOutcome.rejectedNotEnabled;
    }
    _submittedCount += 1;
    if (!_isPoseValid(
      latitude,
      longitude,
      courseDegrees,
      horizontalAccuracyMeters,
      timestampMillis,
    )) {
      _rejectedCount += 1;
      return NativeFollowSubmitDartOutcome.rejectedInvalidPose;
    }
    if (routeGeneration < _currentRouteGeneration) {
      _rejectedCount += 1;
      return NativeFollowSubmitDartOutcome.rejectedStaleGeneration;
    }
    if (routeGeneration > _currentRouteGeneration) {
      _currentRouteGeneration = routeGeneration;
    }
    final nowMs = _clock();
    if (_lastSubmitAtMs != null && nowMs - _lastSubmitAtMs! < _minIntervalMs) {
      _rateLimitedCount += 1;
      return NativeFollowSubmitDartOutcome.rateLimited;
    }
    if (_submitInFlight) {
      // Latest-wins coalesce — no queue, no retry, next tick submits the
      // freshest pose the caller provides.
      _coalescedCount += 1;
      return NativeFollowSubmitDartOutcome.coalescedInFlight;
    }
    _submitInFlight = true;
    _lastSubmitAtMs = nowMs;
    NativeFollowSubmitDartOutcome outcome;
    try {
      final wire = await _hostApi.submitNavigationPose(
        NativeFollowPose(
          mapInstanceId: mapInstanceId,
          latitude: latitude,
          longitude: longitude,
          courseDegrees: courseDegrees,
          speedMetersPerSecond: speedMetersPerSecond,
          horizontalAccuracyMeters: horizontalAccuracyMeters,
          timestampMillis: timestampMillis,
          routeGeneration: routeGeneration,
        ),
      );
      outcome = _fromWireSubmit(wire);
    } catch (_) {
      _transportErrorCount += 1;
      outcome = NativeFollowSubmitDartOutcome.transportError;
    } finally {
      _submitInFlight = false;
    }
    if (outcome == NativeFollowSubmitDartOutcome.accepted) {
      _acceptedCount += 1;
    } else if (outcome != NativeFollowSubmitDartOutcome.rateLimited &&
        outcome != NativeFollowSubmitDartOutcome.coalescedInFlight) {
      _rejectedCount += 1;
    }
    return outcome;
  }

  NativeFollowDartDiagnostics snapshot() => NativeFollowDartDiagnostics(
    mapInstanceId: mapInstanceId,
    owner: _owner,
    submittedCount: _submittedCount,
    acceptedCount: _acceptedCount,
    rateLimitedCount: _rateLimitedCount,
    coalescedCount: _coalescedCount,
    rejectedCount: _rejectedCount,
    transportErrorCount: _transportErrorCount,
    currentRouteGeneration: _currentRouteGeneration,
    lastSubmitAtMs: _lastSubmitAtMs,
  );

  @visibleForTesting
  void resetForTest() {
    _enabled = false;
    _owner = NativeFollowOwnerState.disabled;
    _currentRouteGeneration = 0;
    _submitInFlight = false;
    _lastSubmitAtMs = null;
    _submittedCount = 0;
    _acceptedCount = 0;
    _rateLimitedCount = 0;
    _coalescedCount = 0;
    _rejectedCount = 0;
    _transportErrorCount = 0;
  }

  static bool _isPoseValid(
    double latitude,
    double longitude,
    double courseDegrees,
    double horizontalAccuracyMeters,
    int timestampMillis,
  ) {
    if (latitude.isNaN || longitude.isNaN) return false;
    if (latitude < -90.0 || latitude > 90.0) return false;
    if (longitude < -180.0 || longitude > 180.0) return false;
    if (courseDegrees.isNaN || !courseDegrees.isFinite) return false;
    if (horizontalAccuracyMeters.isNaN || horizontalAccuracyMeters < 0.0) {
      return false;
    }
    if (timestampMillis <= 0) return false;
    return true;
  }

  static NativeFollowSubmitDartOutcome _fromWireSubmit(
    NativeFollowSubmitOutcome wire,
  ) {
    switch (wire) {
      case NativeFollowSubmitOutcome.accepted:
        return NativeFollowSubmitDartOutcome.accepted;
      case NativeFollowSubmitOutcome.coalesced:
        return NativeFollowSubmitDartOutcome.coalescedInFlight;
      case NativeFollowSubmitOutcome.rejectedUnknownMap:
        return NativeFollowSubmitDartOutcome.rejectedUnknownMap;
      case NativeFollowSubmitOutcome.rejectedStaleGeneration:
        return NativeFollowSubmitDartOutcome.rejectedStaleGeneration;
      case NativeFollowSubmitOutcome.rejectedInvalidPose:
        return NativeFollowSubmitDartOutcome.rejectedInvalidPose;
      case NativeFollowSubmitOutcome.rejectedNotEnabled:
        return NativeFollowSubmitDartOutcome.rejectedNotEnabled;
    }
  }

  static NativeFollowOwner _toWireOwner(NativeFollowOwnerState s) {
    switch (s) {
      case NativeFollowOwnerState.followPuck:
        return NativeFollowOwner.followPuck;
      case NativeFollowOwnerState.temporary:
        return NativeFollowOwner.temporary;
      case NativeFollowOwnerState.disabled:
        return NativeFollowOwner.disabled;
    }
  }
}
