import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/navigation/driver_navigation_map_config.dart';
import 'package:fluxidi_tracking/navigation/presentation/navigation_driver_vehicle_model_layer.dart';
import 'package:fluxidi_tracking/navigation/presentation/navigation_presentation_mode.dart';

/// NAV-3D-MAPBOX-2D-MARKER-ISOLATION-FIX-1: harness that mirrors the exact
/// creation-time / apply / pending-opacity contract enforced by
/// `_DriverHomePageState` for the native Mapbox `_driverMarker`.
///
/// Every marker create, recreate, upgrade, self-heal, retry-restore, visual
/// and zoom-sync path in the host state class delegates to
/// [resolveNav3dMapbox2dTaxiCreateOpacity] via a single accessor that also
/// writes the authoritative desired value into a pending field. The harness
/// reproduces that flow so the invariants can be exercised without booting
/// Mapbox or the full driver screen.
class _MarkerIsolationHarness {
  _MarkerIsolationHarness({
    this.followLiveActive = true,
    this.hideForHudOverlay = false,
    this.presentation3dIntent = true,
    this.explicit2dFallback = false,
  });

  bool followLiveActive;
  bool hideForHudOverlay;
  bool presentation3dIntent;
  bool explicit2dFallback;

  double pendingOpacity = 1.0;
  bool markerExists = false;
  double? markerOpacity;
  int createCount = 0;
  int applyCount = 0;
  int applySkipped = 0;
  int applyPending = 0;
  final List<double> createdOpacities = <double>[];
  final List<double> appliedOpacities = <double>[];
  final List<String> events = <String>[];

  double resolveDesiredOpacity({required String source}) {
    final opacity = resolveNav3dMapbox2dTaxiCreateOpacity(
      followLiveActive: followLiveActive,
      hideForHudOverlay: hideForHudOverlay,
      presentation3dIntent: presentation3dIntent,
      explicit2dFallback: explicit2dFallback,
    );
    pendingOpacity = opacity;
    events.add('resolve:$source:${opacity.toStringAsFixed(2)}');
    return opacity;
  }

  /// Simulate marker creation. Opacity is always snapped from the
  /// authoritative resolver (the recreated marker cannot be born visible if
  /// pending desired says hidden).
  void createMarker({required String source}) {
    final opacity = resolveDesiredOpacity(source: source);
    markerExists = true;
    markerOpacity = opacity;
    createCount += 1;
    createdOpacities.add(opacity);
    events.add('create:$source:${opacity.toStringAsFixed(2)}');
  }

  /// Simulate marker recreation (delete + create in place).
  void recreateMarker({required String source}) {
    markerExists = false;
    markerOpacity = null;
    createMarker(source: source);
  }

  /// Simulate the null-marker window during a style swap.
  void destroyMarker() {
    markerExists = false;
    markerOpacity = null;
    events.add('destroy');
  }

  /// Mirrors `_applyMapboxTaxiMarkerPresentationOpacity`: retains the pending
  /// desired opacity when the marker is null; applies otherwise.
  void applyDesiredOpacity({required String source}) {
    final opacity = resolveDesiredOpacity(source: source);
    if (!markerExists) {
      applyPending += 1;
      events.add('pending:$source:${opacity.toStringAsFixed(2)}');
      return;
    }
    final current = markerOpacity ?? 1.0;
    if ((current - opacity).abs() < 0.001) {
      applySkipped += 1;
      events.add('skipped:$source:${opacity.toStringAsFixed(2)}');
      return;
    }
    markerOpacity = opacity;
    applyCount += 1;
    appliedOpacities.add(opacity);
    events.add('apply:$source:${opacity.toStringAsFixed(2)}');
  }

  /// Mirrors `_syncDriverMarkerIconSizeForZoom`: before native update, the
  /// Dart-side opacity is rebased on pending desired so a stale 1.0 cannot
  /// be re-pushed during active 3D isolation.
  void syncZoomIconSize() {
    if (!markerExists) return;
    final opacity = resolveDesiredOpacity(source: 'zoom_sync');
    if ((markerOpacity ?? 1.0 - opacity).abs() >= 0.001 &&
        markerOpacity != opacity) {
      markerOpacity = opacity;
      applyCount += 1;
      appliedOpacities.add(opacity);
      events.add('zoom_sync:${opacity.toStringAsFixed(2)}');
    }
  }
}

/// Mirrors `_attemptTaxiMarkerRestore` single-flight + bounded rerun contract.
class _RestoreSingleFlightHarness {
  _RestoreSingleFlightHarness({this.failFirstCreate = false});

  final bool failFirstCreate;

  bool markerExists = false;
  bool restoreInFlight = false;
  bool rerunRequested = false;
  int createCount = 0;
  int createAttempts = 0;
  int maxConcurrentCreates = 0;
  int _inFlightCreates = 0;
  bool _firstCreateFailed = false;

  Future<bool> attemptRestore() async {
    if (markerExists) return true;
    if (restoreInFlight) {
      rerunRequested = true;
      return false;
    }
    restoreInFlight = true;
    try {
      var success = await _createOnce();
      if (!success && rerunRequested && !markerExists) {
        rerunRequested = false;
        success = await _createOnce();
      }
      return success;
    } finally {
      restoreInFlight = false;
      rerunRequested = false;
    }
  }

  Future<bool> _createOnce() async {
    createAttempts += 1;
    _inFlightCreates += 1;
    maxConcurrentCreates = math.max(maxConcurrentCreates, _inFlightCreates);
    await Future<void>.delayed(Duration.zero);
    try {
      if (failFirstCreate && !_firstCreateFailed) {
        _firstCreateFailed = true;
        return false;
      }
      markerExists = true;
      createCount += 1;
      return true;
    } finally {
      _inFlightCreates -= 1;
    }
  }
}

class _FakeStaleManager {
  _FakeStaleManager({this.removeThrows = false});

  final bool removeThrows;
  final List<String> cleanupCalls = <String>[];

  Future<void> removeAnnotationManager() async {
    cleanupCalls.add('removeAnnotationManager');
    if (removeThrows) throw StateError('remove failed');
  }

  Future<void> deleteAll() async {
    cleanupCalls.add('deleteAll');
  }
}

/// Mirrors `_resetDriverMarkerOnNativeError` best-effort cleanup contract.
class _ResetCleanupHarness {
  _ResetCleanupHarness({this.removeThrows = false});

  final bool removeThrows;

  _FakeStaleManager? manager;
  _FakeStaleManager? _staleManagerRef;
  Object? marker;
  Future<void>? pendingCleanup;
  List<String> get staleManagerCleanupCalls =>
      _staleManagerRef?.cleanupCalls ?? const <String>[];

  void resetOnNativeError() {
    final staleManager = manager;
    manager = null;
    marker = null;
    if (staleManager != null) {
      _staleManagerRef = staleManager;
      pendingCleanup = () async {
        try {
          await staleManager.removeAnnotationManager();
        } catch (_) {
          try {
            await staleManager.deleteAll();
          } catch (_) {}
        }
      }();
    }
  }

  void seedManager() {
    manager = _FakeStaleManager(removeThrows: removeThrows);
    _staleManagerRef = manager;
    marker = Object();
  }
}

void main() {
  setUp(() {
    resetNav3dMapbox2dLogBudget();
    debugPrint = (String? message, {int? wrapWidth}) {};
  });

  tearDown(() {
    debugPrint = debugPrintThrottled;
    resetNav3dMapbox2dLogBudget();
  });

  group('NAV-3D-MAPBOX-2D-MARKER-ISOLATION-FIX-1 pure creation-time opacity', () {
    test(
      'follow-live + 3D intent + no explicit 2D fallback => opacity=0.0',
      () {
        final opacity = resolveNav3dMapbox2dTaxiCreateOpacity(
          followLiveActive: true,
          hideForHudOverlay: false,
          presentation3dIntent: true,
          explicit2dFallback: false,
        );
        expect(opacity, 0.0);
      },
    );

    test('not follow-live => opacity=1.0 regardless of 3D intent', () {
      final opacity = resolveNav3dMapbox2dTaxiCreateOpacity(
        followLiveActive: false,
        hideForHudOverlay: false,
        presentation3dIntent: true,
        explicit2dFallback: false,
      );
      expect(opacity, 1.0);
    });

    test('explicit 2D fallback (HUD disabled) => opacity=1.0 even in 3D intent',
        () {
      final opacity = resolveNav3dMapbox2dTaxiCreateOpacity(
        followLiveActive: true,
        hideForHudOverlay: false,
        presentation3dIntent: true,
        explicit2dFallback: true,
      );
      expect(opacity, 1.0);
    });

    test('no 3D intent + HUD disabled => opacity=1.0 (default 2D visible)', () {
      final opacity = resolveNav3dMapbox2dTaxiCreateOpacity(
        followLiveActive: true,
        hideForHudOverlay: false,
        presentation3dIntent: false,
        explicit2dFallback: false,
      );
      expect(opacity, 1.0);
    });
  });

  group(
      'NAV-3D-YELLOW-TAXI-FINAL-VISIBILITY-FIX-1 hideForHudOverlay precedence',
      () {
    test('1. HUD active in normal 2D follow => Mapbox marker opacity=0.0', () {
      final opacity = resolveNav3dMapbox2dTaxiCreateOpacity(
        followLiveActive: true,
        hideForHudOverlay: true,
        presentation3dIntent: false,
        explicit2dFallback: false,
      );
      expect(opacity, 0.0);
    });

    test(
      '2. HUD active + explicit 2D fallback => marker still hidden '
      '(HUD owns the driver visual)',
      () {
        final opacity = resolveNav3dMapbox2dTaxiCreateOpacity(
          followLiveActive: true,
          hideForHudOverlay: true,
          presentation3dIntent: false,
          explicit2dFallback: true,
        );
        expect(opacity, 0.0);
      },
    );

    test('3. HUD disabled + normal 2D => Mapbox marker opacity=1.0', () {
      final opacity = resolveNav3dMapbox2dTaxiCreateOpacity(
        followLiveActive: true,
        hideForHudOverlay: false,
        presentation3dIntent: false,
        explicit2dFallback: false,
      );
      expect(opacity, 1.0);
    });

    test('not follow-live outranks HUD ownership (idle map shows marker)', () {
      final opacity = resolveNav3dMapbox2dTaxiCreateOpacity(
        followLiveActive: false,
        hideForHudOverlay: true,
        presentation3dIntent: false,
        explicit2dFallback: false,
      );
      expect(opacity, 1.0);
    });

    test('HUD active holds through 3D transition / swap / self-heal sources',
        () {
      final harness = _MarkerIsolationHarness(
        hideForHudOverlay: true,
        presentation3dIntent: true,
      );
      harness.createMarker(source: 'create');
      harness.recreateMarker(source: 'preset_change');
      harness.destroyMarker();
      harness.createMarker(source: 'restore');
      harness.destroyMarker();
      harness.createMarker(source: 'self_heal');
      harness.recreateMarker(source: 'asset_upgrade');
      expect(harness.createdOpacities, everyElement(0.0));
      // Even leaving 3D intent, HUD ownership keeps the marker hidden.
      harness.presentation3dIntent = false;
      harness.applyDesiredOpacity(source: 'presentation_change');
      expect(harness.markerOpacity, 0.0);
    });
  });

  group('NAV-3D-MAPBOX-2D-MARKER-ISOLATION-FIX-1 presentation3dIntent', () {
    bool intentWith({
      bool vehicleModelFlagEnabled = true,
      bool cockpitSceneEnabled = true,
      bool useDriverCockpitCamera = true,
      NavigationPresentationMode presentationMode =
          NavigationPresentationMode.driver,
      bool liveNavigationActive = true,
      bool followCamera = true,
      bool cockpitSceneActive = true,
      bool sessionFallback2d = false,
      DriverCockpitMapVisualStyle? cockpitVisualStyle =
          DriverCockpitMapVisualStyle.standard3d,
      String? activeStyleUri = kDriverMapStyleStandard,
    }) {
      return resolveNav3dPresentation3dIntent(
        vehicleModelFlagEnabled: vehicleModelFlagEnabled,
        cockpitSceneEnabled: cockpitSceneEnabled,
        useDriverCockpitCamera: useDriverCockpitCamera,
        presentationMode: presentationMode,
        liveNavigationActive: liveNavigationActive,
        followCamera: followCamera,
        cockpitSceneActive: cockpitSceneActive,
        sessionFallback2d: sessionFallback2d,
        cockpitVisualStyle: cockpitVisualStyle,
        activeStyleUri: activeStyleUri,
      );
    }

    test('all gates true => intent=true (no activation state required)', () {
      expect(intentWith(), isTrue);
    });

    test('sessionFallback2d flips intent to false', () {
      expect(intentWith(sessionFallback2d: true), isFalse);
    });

    test('non-driver presentation flips intent to false', () {
      expect(
        intentWith(presentationMode: NavigationPresentationMode.overview),
        isFalse,
      );
    });

    test('non-3D style URI flips intent to false', () {
      expect(intentWith(activeStyleUri: kDriverMapStyleNavStreetLight), isFalse);
    });

    test('vehicle model flag disabled flips intent to false', () {
      expect(intentWith(vehicleModelFlagEnabled: false), isFalse);
    });

    test('cockpit camera off flips intent to false', () {
      expect(intentWith(useDriverCockpitCamera: false), isFalse);
    });

    test('not live navigation flips intent to false', () {
      expect(intentWith(liveNavigationActive: false), isFalse);
    });
  });

  group('NAV-3D-MAPBOX-2D-MARKER-ISOLATION-FIX-1 marker lifecycle harness', () {
    test(
      '1. 3D intent + activation not yet confirmed => marker create opacity=0.0',
      () {
        final harness = _MarkerIsolationHarness(
          followLiveActive: true,
          presentation3dIntent: true,
          explicit2dFallback: false,
        );
        harness.createMarker(source: 'create');
        expect(harness.markerOpacity, 0.0);
        expect(harness.createdOpacities.last, 0.0);
      },
    );

    test('2. 3D presentation confirmed => marker opacity=0.0', () {
      final harness = _MarkerIsolationHarness();
      harness.createMarker(source: 'create');
      harness.applyDesiredOpacity(source: 'activation_change');
      expect(harness.markerOpacity, 0.0);
    });

    test(
      '3. preset swap in 3D => recreated marker opacity=0.0 (no visible window)',
      () {
        final harness = _MarkerIsolationHarness();
        harness.createMarker(source: 'create');
        expect(harness.markerOpacity, 0.0);
        harness.recreateMarker(source: 'preset_change');
        expect(harness.markerOpacity, 0.0);
        expect(harness.createdOpacities, everyElement(0.0));
      },
    );

    test(
      '4. style restore while staying in 3D => recreated marker opacity=0.0',
      () {
        final harness = _MarkerIsolationHarness();
        harness.createMarker(source: 'create');
        harness.destroyMarker();
        harness.createMarker(source: 'restore');
        expect(harness.markerOpacity, 0.0);
        expect(harness.createdOpacities, everyElement(0.0));
      },
    );

    test('5. self-heal in 3D => recreated marker opacity=0.0', () {
      final harness = _MarkerIsolationHarness();
      harness.createMarker(source: 'create');
      harness.destroyMarker();
      harness.createMarker(source: 'self_heal');
      expect(harness.markerOpacity, 0.0);
      expect(harness.createdOpacities.last, 0.0);
    });

    test('6. asset upgrade in 3D => recreated marker opacity=0.0', () {
      final harness = _MarkerIsolationHarness();
      harness.createMarker(source: 'create');
      // Asset upgrade path deletes and recreates in place with a fresh
      // opacity snapshot; the snapshot must be 0.0 in intended 3D mode.
      harness.recreateMarker(source: 'asset_upgrade');
      expect(harness.markerOpacity, 0.0);
    });

    test(
      '7. desired hide applied while marker==null => pending retained, '
      'next create uses 0.0',
      () {
        final harness = _MarkerIsolationHarness();
        // Enter 3D intent while marker is not yet created — this is the
        // exact window where the previous implementation dropped the hide.
        expect(harness.markerExists, isFalse);
        harness.applyDesiredOpacity(source: 'activation_change');
        expect(harness.applyPending, 1);
        expect(harness.pendingOpacity, 0.0);
        // Later, a style restore creates the marker. The pending desired
        // opacity must be honoured.
        harness.createMarker(source: 'restore');
        expect(harness.markerOpacity, 0.0);
      },
    );

    test(
      '8. zoom/icon-size update cannot push stale opacity=1.0 during 3D',
      () {
        final harness = _MarkerIsolationHarness();
        harness.createMarker(source: 'create');
        // Externally seed a stale 1.0 to model what pre-fix code could
        // leave on the Dart-side marker after a style-restore recreation
        // that read a mid-transition decision.
        harness.markerOpacity = 1.0;
        harness.syncZoomIconSize();
        expect(harness.markerOpacity, 0.0);
        expect(harness.appliedOpacities.last, 0.0);
      },
    );

    test('9. leave 3D presentation => Mapbox marker may return to 1.0', () {
      final harness = _MarkerIsolationHarness();
      harness.createMarker(source: 'create');
      expect(harness.markerOpacity, 0.0);
      harness.presentation3dIntent = false;
      harness.applyDesiredOpacity(source: 'presentation_change');
      expect(harness.markerOpacity, 1.0);
    });

    test('10. explicit session 2D fallback => Mapbox marker visible', () {
      final harness = _MarkerIsolationHarness();
      harness.createMarker(source: 'create');
      expect(harness.markerOpacity, 0.0);
      harness.explicit2dFallback = true;
      harness.applyDesiredOpacity(source: 'session_fallback');
      expect(harness.markerOpacity, 1.0);
    });
  });

  group('NAV-3D-YELLOW-TAXI-FINAL-VISIBILITY-FIX-1 visual owner invariants',
      () {
    // Mirrors the production wiring: HUD mount comes from
    // resolveNav3dHudRenderDecision, marker opacity from
    // resolveNav3dMapbox2dTaxiCreateOpacity with hideForHudOverlay.
    ({bool hudVisible, double markerOpacity}) ownersFor({
      required bool driver3dVisualReady,
      required bool hudOverlayEnabled,
      bool explicit2dFallback = false,
      bool presentation3dIntent = false,
    }) {
      final decision = resolveNav3dHudRenderDecision(
        hideHudFlagEnabled: true,
        presentation3dActive: presentation3dIntent,
        driver3dVisualReady: driver3dVisualReady,
        effectivelyActive: driver3dVisualReady,
        hudFallbackAllowedToHide: driver3dVisualReady,
        showDriverHudOverlay: hudOverlayEnabled,
        followLiveActive: true,
        explicit2dFallback: explicit2dFallback,
      );
      final markerOpacity = resolveNav3dMapbox2dTaxiCreateOpacity(
        followLiveActive: true,
        hideForHudOverlay: decision.owner == DriverVisualOwner.hud2d,
        presentation3dIntent: presentation3dIntent,
        explicit2dFallback: explicit2dFallback,
      );
      return (
        hudVisible: decision.actualHudVisible,
        markerOpacity: markerOpacity,
      );
    }

    test(
      '4. 3D intent before visual-ready => HUD visible, '
      'Mapbox marker hidden',
      () {
        final owners = ownersFor(
          driver3dVisualReady: false,
          hudOverlayEnabled: true,
          presentation3dIntent: true,
        );
        expect(owners.hudVisible, isTrue);
        expect(owners.markerOpacity, 0.0);
      },
    );

    test(
      '10. full 2D invariant: exactly one driver visual owner (HUD) '
      'when HUD overlay active',
      () {
        final owners = ownersFor(
          driver3dVisualReady: false,
          hudOverlayEnabled: true,
          presentation3dIntent: false,
        );
        expect(owners.hudVisible, isTrue);
        expect(owners.markerOpacity, 0.0);
      },
    );

    test(
      '11. full 3D invariant after visual-ready: exactly one owner, '
      'the 3D model (HUD hidden, marker hidden)',
      () {
        final owners = ownersFor(
          driver3dVisualReady: true,
          hudOverlayEnabled: true,
          presentation3dIntent: true,
        );
        expect(owners.hudVisible, isFalse);
        expect(owners.markerOpacity, 0.0);
      },
    );

    test('HUD overlay disabled: marker owns the 2D visual', () {
      final owners = ownersFor(
        driver3dVisualReady: false,
        hudOverlayEnabled: false,
        presentation3dIntent: false,
      );
      expect(owners.hudVisible, isFalse);
      expect(owners.markerOpacity, 1.0);
    });
  });

  group(
      'NAV-3D-YELLOW-TAXI-FINAL-VISIBILITY-FIX-1 activation confirm retry',
      () {
    test('bounded delays are one controlled 180 ms retry then fallback', () {
      expect(kNav3dActivationConfirmRetryDelaysMs, [180]);
      final lifecycle = Nav3dActivationConfirmRetryLifecycle();
      expect(
        lifecycle.nextDelay(styleGeneration: 1, presetGeneration: 1),
        const Duration(milliseconds: 180),
      );
      expect(
        lifecycle.nextDelay(styleGeneration: 1, presetGeneration: 1),
        isNull,
      );
    });

    test(
      '5. verification succeeds on retry => HUD hides, Mapbox stays hidden',
      () {
        final lifecycle = Nav3dActivationConfirmRetryLifecycle();
        var confirmed = false;
        var verifyResults = <bool>[false, true];
        var verifyIndex = 0;

        // Simulated confirm attempt: verify fails once, then succeeds.
        bool attemptConfirm() {
          final verified = verifyResults[verifyIndex++];
          if (verified) confirmed = true;
          return verified;
        }

        // First attempt fails => a retry is granted from the budget.
        expect(attemptConfirm(), isFalse);
        final delay = lifecycle.nextDelay(
          styleGeneration: 2,
          presetGeneration: 1,
        );
        expect(delay, isNotNull);
        // Retry fires (generations unchanged) and succeeds.
        expect(
          nav3dActivationConfirmRetryStillValid(
            scheduledStyleGeneration: 2,
            scheduledPresetGeneration: 1,
            currentStyleGeneration: 2,
            currentPresetGeneration: 1,
            activationConfirmed: confirmed,
            eligible: true,
            presentation3dIntent: true,
            layerCreated: true,
            sourceGeometryValid: true,
            sessionFallback2d: false,
          ),
          isTrue,
        );
        expect(attemptConfirm(), isTrue);
        expect(confirmed, isTrue);
        // Confirmed 3D => existing HUD gate hides, marker stays hidden.
        final decision = resolveNav3dHudRenderDecision(
          hideHudFlagEnabled: true,
          presentation3dActive: true,
          driver3dVisualReady: true,
          effectivelyActive: true,
          hudFallbackAllowedToHide: true,
          showDriverHudOverlay: true,
          followLiveActive: true,
          explicit2dFallback: false,
        );
        expect(decision.actualHudVisible, isFalse);
        expect(
          resolveNav3dMapbox2dTaxiCreateOpacity(
            followLiveActive: true,
            hideForHudOverlay: true,
            presentation3dIntent: true,
            explicit2dFallback: false,
          ),
          0.0,
        );
      },
    );

    test(
      '6. verification fails all bounded retries => budget exhausted once, '
      'HUD remains visible, no infinite retry',
      () {
        final lifecycle = Nav3dActivationConfirmRetryLifecycle();
        var granted = 0;
        while (lifecycle.nextDelay(styleGeneration: 3, presetGeneration: 2) !=
            null) {
          granted += 1;
          expect(granted, lessThanOrEqualTo(1));
        }
        expect(granted, 1);
        // Budget stays exhausted for the same generation pair.
        expect(
          lifecycle.nextDelay(styleGeneration: 3, presetGeneration: 2),
          isNull,
        );
        // Single bounded failure diagnostic.
        expect(lifecycle.markExhaustedOnce(), isTrue);
        expect(lifecycle.markExhaustedOnce(), isFalse);
        // HUD fallback remains the visible owner while unconfirmed.
        final decision = resolveNav3dHudRenderDecision(
          hideHudFlagEnabled: true,
          presentation3dActive: true,
          driver3dVisualReady: false,
          effectivelyActive: false,
          hudFallbackAllowedToHide: false,
          showDriverHudOverlay: true,
          followLiveActive: true,
          explicit2dFallback: false,
        );
        expect(decision.actualHudVisible, isTrue);
      },
    );

    test('7. generation change cancels old retry and refreshes the budget',
        () {
      // A scheduled retry from an old generation must be dropped.
      expect(
        nav3dActivationConfirmRetryStillValid(
          scheduledStyleGeneration: 3,
          scheduledPresetGeneration: 2,
          currentStyleGeneration: 4,
          currentPresetGeneration: 2,
          activationConfirmed: false,
          eligible: true,
          presentation3dIntent: true,
          layerCreated: true,
          sourceGeometryValid: true,
          sessionFallback2d: false,
        ),
        isFalse,
      );
      expect(
        nav3dActivationConfirmRetryStillValid(
          scheduledStyleGeneration: 3,
          scheduledPresetGeneration: 2,
          currentStyleGeneration: 3,
          currentPresetGeneration: 3,
          activationConfirmed: false,
          eligible: true,
          presentation3dIntent: true,
          layerCreated: true,
          sourceGeometryValid: true,
          sessionFallback2d: false,
        ),
        isFalse,
      );
      // Exhaust the old generation, then a new generation gets a fresh
      // budget.
      final lifecycle = Nav3dActivationConfirmRetryLifecycle();
      expect(
        lifecycle.nextDelay(styleGeneration: 3, presetGeneration: 2),
        isNotNull,
      );
      expect(
        lifecycle.nextDelay(styleGeneration: 3, presetGeneration: 2),
        isNull,
      );
      expect(
        lifecycle.nextDelay(styleGeneration: 4, presetGeneration: 2),
        const Duration(milliseconds: 180),
      );
    });

    test('retry dropped on eligibility loss, intent loss, layer/source gone, '
        'session fallback, or already confirmed', () {
      bool valid({
        bool activationConfirmed = false,
        bool eligible = true,
        bool presentation3dIntent = true,
        bool layerCreated = true,
        bool sourceGeometryValid = true,
        bool sessionFallback2d = false,
      }) {
        return nav3dActivationConfirmRetryStillValid(
          scheduledStyleGeneration: 1,
          scheduledPresetGeneration: 1,
          currentStyleGeneration: 1,
          currentPresetGeneration: 1,
          activationConfirmed: activationConfirmed,
          eligible: eligible,
          presentation3dIntent: presentation3dIntent,
          layerCreated: layerCreated,
          sourceGeometryValid: sourceGeometryValid,
          sessionFallback2d: sessionFallback2d,
        );
      }

      expect(valid(), isTrue);
      expect(valid(activationConfirmed: true), isFalse);
      expect(valid(eligible: false), isFalse);
      expect(valid(presentation3dIntent: false), isFalse);
      expect(valid(layerCreated: false), isFalse);
      expect(valid(sourceGeometryValid: false), isFalse);
      expect(valid(sessionFallback2d: true), isFalse);
    });
  });

  group('NAV-3D-YELLOW-TAXI-FINAL-VISIBILITY-FIX-1 restore single-flight', () {
    test('8. concurrent restore requests => at most one create in flight',
        () async {
      final harness = _RestoreSingleFlightHarness();
      final results = await Future.wait(<Future<bool>>[
        harness.attemptRestore(),
        harness.attemptRestore(),
        harness.attemptRestore(),
      ]);
      expect(harness.maxConcurrentCreates, 1);
      expect(harness.createCount, 1);
      expect(harness.markerExists, isTrue);
      // Owner completed; deferred callers reported false (their existing
      // retry timers re-check later and find the marker present).
      expect(results.where((r) => r).length, 1);
      expect(harness.rerunRequested, isFalse);
    });

    test('failed in-flight create honours one bounded rerun for a deferred '
        'request', () async {
      final harness = _RestoreSingleFlightHarness(
        failFirstCreate: true,
      );
      final results = await Future.wait(<Future<bool>>[
        harness.attemptRestore(),
        harness.attemptRestore(),
      ]);
      // Owner attempt failed, deferred request marked rerun, owner ran
      // exactly one rerun which succeeded — never concurrently.
      expect(harness.maxConcurrentCreates, 1);
      expect(harness.createAttempts, 2);
      expect(harness.markerExists, isTrue);
      expect(results.contains(true), isTrue);
    });
  });

  group('NAV-3D-YELLOW-TAXI-FINAL-VISIBILITY-FIX-1 native-error reset', () {
    test('9. best-effort cleanup of the stale manager before references are '
        'nulled', () async {
      final harness = _ResetCleanupHarness();
      harness.seedManager();
      harness.resetOnNativeError();
      expect(harness.manager, isNull);
      expect(harness.marker, isNull);
      await harness.pendingCleanup;
      expect(harness.staleManagerCleanupCalls, ['removeAnnotationManager']);
    });

    test('cleanup failure falls back to deleteAll and never throws', () async {
      final harness = _ResetCleanupHarness(removeThrows: true);
      harness.seedManager();
      harness.resetOnNativeError();
      await harness.pendingCleanup;
      expect(
        harness.staleManagerCleanupCalls,
        ['removeAnnotationManager', 'deleteAll'],
      );
      expect(harness.manager, isNull);
    });
  });

  group('NAV-3D-MAPBOX-2D-MARKER-ISOLATION-FIX-1 bounded diagnostics', () {
    test('log budget caps repeated events', () {
      final lines = <String>[];
      void capture(String? message, {int? wrapWidth}) {
        if (message != null && message.startsWith('[NAV_3D_MAPBOX_2D]')) {
          lines.add(message);
        }
      }

      debugPrint = capture;
      resetNav3dMapbox2dLogBudget();
      for (var i = 0; i < kNav3dMapbox2dMaxLogsPerActivation * 3; i++) {
        logNav3dMapbox2d(
          event: 'apply',
          presentation3dIntent: true,
          explicit2dFallback: false,
          desiredOpacity: 0.0,
          pendingOpacity: 0.0,
          markerExists: true,
          appliedOpacity: 0.0,
          source: 'unique_$i',
        );
      }
      expect(lines.length, lessThanOrEqualTo(kNav3dMapbox2dMaxLogsPerActivation));
    });

    test('log budget resets on reset call', () {
      final lines = <String>[];
      debugPrint = (String? message, {int? wrapWidth}) {
        if (message != null && message.startsWith('[NAV_3D_MAPBOX_2D]')) {
          lines.add(message);
        }
      };
      resetNav3dMapbox2dLogBudget();
      for (var i = 0; i < kNav3dMapbox2dMaxLogsPerActivation; i++) {
        logNav3dMapbox2d(
          event: 'apply',
          presentation3dIntent: true,
          explicit2dFallback: false,
          desiredOpacity: 0.0,
          pendingOpacity: 0.0,
          markerExists: true,
          appliedOpacity: 0.0,
          source: 'session1_$i',
        );
      }
      final firstCount = lines.length;
      resetNav3dMapbox2dLogBudget();
      logNav3dMapbox2d(
        event: 'apply',
        presentation3dIntent: true,
        explicit2dFallback: false,
        desiredOpacity: 0.0,
        pendingOpacity: 0.0,
        markerExists: true,
        appliedOpacity: 0.0,
        source: 'session2_first',
      );
      expect(lines.length, greaterThan(firstCount));
    });
  });
}
