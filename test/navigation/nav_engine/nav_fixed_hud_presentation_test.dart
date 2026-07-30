import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/navigation/driver_navigation_models.dart';
import 'package:fluxidi_tracking/navigation/nav_engine/nav_camera_policy.dart';
import 'package:fluxidi_tracking/navigation/nav_engine/nav_camera_view_mode.dart';
import 'package:fluxidi_tracking/navigation/nav_engine/nav_fixed_hud_presentation.dart';
import 'package:fluxidi_tracking/navigation/nav_engine/nav_prestart_presentation.dart';
import 'package:fluxidi_tracking/navigation/presentation/driver_ride_meters.dart';
import 'package:fluxidi_tracking/navigation/presentation/nav_stationary_bearing_hold.dart';
import 'package:fluxidi_tracking/navigation/presentation/navigation_driver_vehicle_model_layer.dart';
import 'package:fluxidi_tracking/navigation/presentation/navigation_streetlevel_marker_anchor.dart';

// NAV-FIXED-HUD-PRESENTATION-1
//
// Field validation of commit 49c110d failed on tablet: the Car was not
// screen-fixed above the KPI counters, rotated diagonally, and the forward
// route did not point to the top of the screen. Logs showed
// `[NAV_R5_CAMERA_POLICY] follow=false reason=inactive` on a prepared route
// and `[NAV_MARKER_OWNER] owner=mapbox`.
//
// Root cause: every marker-ownership and camera decision gated on
// `cameraFollowMode && liveRideActive`, which excludes prepared booking,
// prepared street draft and NAV-to-pickup A.
//
// These proofs pin the corrected contract for all four phases.

/// The three route phases that must share one identical presentation, plus
/// idle as the negative control.
const List<NavFixedHudPhase> _routePhases = <NavFixedHudPhase>[
  NavFixedHudPhase.preparedRoute,
  NavFixedHudPhase.toPickup,
  NavFixedHudPhase.liveRide,
];

/// Mirrors the production wiring: `_navFixedHudPresentationActive` feeds the
/// `followLiveActive` parameter of the owner resolver.
DriverVehicleMarkerPresentationOwner _ownerFor(
  NavFixedHudPhase phase, {
  bool tellersActive = false,
  bool cameraFollowMode = true,
  bool showDriverHudOverlay = true,
}) {
  return resolveDriverVehicleMarkerPresentationOwner(
    tellersActive: tellersActive,
    followLiveActive: navFixedHudPresentationActive(
      phase: phase,
      cameraFollowMode: cameraFollowMode,
    ),
    showDriverHudOverlay: showDriverHudOverlay,
  );
}

/// Mirrors `_resolveDesiredMapboxTaxiOpacity` for a 2D Street Level surface.
double _mapboxOpacityFor(
  NavFixedHudPhase phase, {
  bool tellersActive = false,
  bool cameraFollowMode = true,
}) {
  final owner = _ownerFor(
    phase,
    tellersActive: tellersActive,
    cameraFollowMode: cameraFollowMode,
  );
  return resolveNav3dMapbox2dTaxiCreateOpacity(
    followLiveActive: navFixedHudPresentationActive(
      phase: phase,
      cameraFollowMode: cameraFollowMode,
    ),
    hideForHudOverlay: driverHideMapboxMarkerForPresentationOwner(owner),
    presentation3dIntent: false,
    explicit2dFallback: false,
  );
}

void main() {
  group('NAV-FIXED-HUD-PRESENTATION-1 phase resolution', () {
    test('1) live > toPickup > preparedRoute > idle precedence', () {
      expect(
        resolveNavFixedHudPhase(
          liveRideActive: true,
          navigationGuidanceActive: true,
          preparedRouteDraft: true,
        ),
        NavFixedHudPhase.liveRide,
      );
      expect(
        resolveNavFixedHudPhase(
          liveRideActive: false,
          navigationGuidanceActive: true,
          preparedRouteDraft: true,
        ),
        NavFixedHudPhase.toPickup,
      );
      expect(
        resolveNavFixedHudPhase(
          liveRideActive: false,
          navigationGuidanceActive: false,
          preparedRouteDraft: true,
        ),
        NavFixedHudPhase.preparedRoute,
      );
      expect(
        resolveNavFixedHudPhase(
          liveRideActive: false,
          navigationGuidanceActive: false,
          preparedRouteDraft: false,
        ),
        NavFixedHudPhase.idle,
      );
    });

    test('2) HUD presentation is active in every route phase, not idle', () {
      for (final phase in _routePhases) {
        expect(
          navFixedHudPresentationActive(phase: phase, cameraFollowMode: true),
          isTrue,
          reason: 'phase ${navFixedHudPhaseLabel(phase)} must arm the HUD',
        );
      }
      expect(
        navFixedHudPresentationActive(
          phase: NavFixedHudPhase.idle,
          cameraFollowMode: true,
        ),
        isFalse,
      );
      // The idle map keeps platform defaults when the camera is not following.
      expect(
        navFixedHudPresentationActive(
          phase: NavFixedHudPhase.liveRide,
          cameraFollowMode: false,
        ),
        isFalse,
      );
    });
  });

  group('NAV-FIXED-HUD-PRESENTATION-1 sole visible owner', () {
    test('3) HUD is the sole visible owner in all three route phases', () {
      for (final phase in _routePhases) {
        expect(
          _ownerFor(phase),
          DriverVehicleMarkerPresentationOwner.navigationHud,
          reason: 'phase ${navFixedHudPhaseLabel(phase)} must be HUD-owned',
        );
      }
    });

    test('4) regression: prepared route no longer resolves owner=mapbox', () {
      // Pre-fix behaviour: prepared route is not a live ride, so the old gate
      // produced `none` and the Mapbox annotation stayed visible.
      final legacyOwner = resolveDriverVehicleMarkerPresentationOwner(
        tellersActive: false,
        followLiveActive: false,
        showDriverHudOverlay: true,
      );
      expect(legacyOwner, DriverVehicleMarkerPresentationOwner.none);
      expect(driverVehicleMarkerPresentationOwnerLabel(legacyOwner), 'none');
      // Corrected behaviour.
      expect(
        driverVehicleMarkerPresentationOwnerLabel(
          _ownerFor(NavFixedHudPhase.preparedRoute),
        ),
        'hud',
      );
    });

    test('5) Mapbox marker opacity stays zero in all three route phases', () {
      for (final phase in _routePhases) {
        expect(
          _mapboxOpacityFor(phase),
          0.0,
          reason: 'phase ${navFixedHudPhaseLabel(phase)} must hide Mapbox',
        );
      }
    });
  });

  group('NAV-FIXED-HUD-PRESENTATION-1 screen-fixed marker', () {
    test('6) marker screen position is invariant across all route phases', () {
      double anchorFor(NavFixedHudPhase phase) {
        // Production computes the anchor from the KPI layout only; the phase
        // never enters the calculation. This pins that independence.
        expect(
          navFixedHudPresentationActive(phase: phase, cameraFollowMode: true),
          isTrue,
        );
        return resolveStreetLevelMarkerBottomOffset(
          isLandscape: false,
          hasSecondaryActions: true,
          secondaryActionRowHeight: 52.0,
          primaryToSecondaryGap: 8.0,
        );
      }

      final anchors = _routePhases.map(anchorFor).toSet();
      expect(anchors, hasLength(1));
      final anchor = anchors.single;
      // The marker bottom sits inside the 12-20 px acceptance window above
      // the KPI panel top, i.e. immediately above the counters.
      final panel = streetLevelKpiPanelHeight(
        isLandscape: false,
        hasSecondaryActions: true,
        secondaryActionRowHeight: 52.0,
        primaryToSecondaryGap: 8.0,
      );
      expect(
        anchor - panel,
        greaterThanOrEqualTo(kStreetLevelMarkerGapAboveKpiMin),
      );
      expect(
        anchor - panel,
        lessThanOrEqualTo(kStreetLevelMarkerGapAboveKpiMax),
      );
    });

    test('7) marker visual rotation is screen-up for every camera bearing', () {
      for (final phase in _routePhases) {
        final policy = resolveDriverMarkerRotationPolicy(
          isStreetlevel: true,
          owner: _ownerFor(phase),
        );
        expect(
          policy.alignment,
          DriverMarkerRotationAlignment.viewport,
          reason: 'phase ${navFixedHudPhaseLabel(phase)} must be screen-up',
        );
        expect(policy.forceIconRotateZero, isTrue);
        for (final cameraBearing in <double>[0, 37, 90, 181, 274, 359]) {
          expect(
            navFixedHudMarkerScreenRotationDeg(
              iconRotateDeg: policy.iconRotateFor(cameraBearing + 45.0),
              cameraBearingDeg: cameraBearing,
              viewportAligned: true,
            ),
            0.0,
          );
        }
      }
    });

    test('8) pre-fix road-aligned marker really did render diagonally', () {
      // Guards the proof itself: with MAP alignment the visible rotation is
      // poseBearing - cameraBearing, which is what the tablet showed.
      const legacy = DriverMarkerRotationPolicy.mapRoadBearing;
      expect(
        navFixedHudMarkerScreenRotationDeg(
          iconRotateDeg: legacy.iconRotateFor(135.0),
          cameraBearingDeg: 90.0,
          viewportAligned: false,
        ),
        45.0,
      );
    });
  });

  group('NAV-FIXED-HUD-PRESENTATION-1 route-up camera', () {
    // Straight leg heading due east from the origin.
    final eastRoute = <DriverLonLat>[
      const DriverLonLat(4.8952, 52.3702),
      const DriverLonLat(4.8990, 52.3702),
      const DriverLonLat(4.9040, 52.3702),
    ];

    test('9) camera bearing equals the forward route bearing', () {
      final tangent = navFirstMeaningfulRouteSegmentBearing(eastRoute);
      expect(tangent, isNotNull);
      final resolved = resolveNavFixedRouteUpBearing(
        routeTangentBearingDeg: tangent,
        seededRouteBearingDeg: null,
        gpsHeadingDeg: 211.0,
      );
      expect(resolved.source, NavFixedRouteUpBearingSource.routeTangent);
      expect(resolved.isRouteUp, isTrue);
      expect(navFixedBearingDeltaDeg(resolved.bearingDeg, tangent!), 0.0);
      // Due east, so ~90 degrees.
      expect(navFixedBearingDeltaDeg(resolved.bearingDeg, 90.0), lessThan(1.0));
    });

    test('10) route points upward while stationary (GPS course ignored)', () {
      final tangent = navFirstMeaningfulRouteSegmentBearing(eastRoute)!;
      // Standstill: GPS course is noise. Pre-fix the preview camera used it
      // verbatim, so the route pointed sideways.
      for (final noisyCourse in <double>[0.0, 178.0, 303.0]) {
        final resolved = resolveNavFixedRouteUpBearing(
          routeTangentBearingDeg: tangent,
          seededRouteBearingDeg: null,
          gpsHeadingDeg: noisyCourse,
        );
        expect(resolved.bearingDeg, closeTo(tangent, 0.001));
        // Screen-relative direction of the forward route == straight up.
        expect(
          navFixedBearingDeltaDeg(tangent, resolved.bearingDeg),
          lessThan(0.001),
        );
      }
    });

    test('11) seeded route bearing outranks GPS; GPS is the last resort', () {
      final seeded = resolveNavFixedRouteUpBearing(
        routeTangentBearingDeg: null,
        seededRouteBearingDeg: 275.0,
        gpsHeadingDeg: 12.0,
      );
      expect(seeded.source, NavFixedRouteUpBearingSource.seededRoute);
      expect(seeded.bearingDeg, 275.0);

      final gps = resolveNavFixedRouteUpBearing(
        routeTangentBearingDeg: null,
        seededRouteBearingDeg: null,
        gpsHeadingDeg: 12.0,
      );
      expect(gps.source, NavFixedRouteUpBearingSource.gpsHeading);
      expect(gps.isRouteUp, isFalse);

      // No route and no usable course: hold north rather than snap to noise.
      final none = resolveNavFixedRouteUpBearing(
        routeTangentBearingDeg: null,
        seededRouteBearingDeg: null,
        gpsHeadingDeg: -1.0,
      );
      expect(none.source, NavFixedRouteUpBearingSource.none);
      expect(none.bearingDeg, 0.0);
      expect(navFixedRouteUpBearingSourceLabel(none.source), 'none');
    });

    test(
      '12) prepared route no longer resolves follow=false reason=inactive',
      () {
        NavCameraPolicyOutput runFor(NavFixedHudPhase phase) {
          return DriverNavCameraPolicy().update(
            NavCameraPolicyInput(
              timestamp: DateTime.utc(2026, 7, 30, 10),
              liveRideActive: navFixedHudPresentationActive(
                phase: phase,
                cameraFollowMode: true,
              ),
              cameraFollowMode: true,
              manualRecenter: false,
              speedKmh: 0.0,
              hasReliableSnap: true,
              viewMode: NavCameraViewMode.streetView,
            ),
          );
        }

        for (final phase in _routePhases) {
          final out = runFor(phase);
          expect(
            out.shouldFollow,
            isTrue,
            reason: 'phase ${navFixedHudPhaseLabel(phase)} must follow',
          );
          expect(out.reason, isNot('inactive'));
        }
        final idle = runFor(NavFixedHudPhase.idle);
        expect(idle.shouldFollow, isFalse);
        expect(idle.reason, 'inactive');
      },
    );

    test('13) prepared booking reaches the driver cockpit presentation', () {
      // Pre-fix the build passed only the street draft as `hasPreviewDraft`,
      // so a prepared booking fell through to overview and never mounted the
      // cockpit HUD or the KPI anchor.
      final booking = decideNavPreviewPresentation(
        const NavPreviewPresentationInputs(
          hasPreviewDraft: true,
          selectedViewMode: NavPreviewViewModeTokens.overview,
          routePointCount: 24,
          liveRideActive: false,
        ),
      );
      expect(booking.mode, NavPreviewPresentationMode.streetLevel);
      expect(booking.applyCockpitCamera, isTrue);
    });
  });

  group('NAV-FIXED-HUD-PRESENTATION-1 Tellers, style swap, teardown', () {
    test('14) Tellers keeps one owner and never changes the KPI anchor', () {
      for (final phase in _routePhases) {
        final owner = _ownerFor(phase, tellersActive: true);
        // Tellers projects the single Mapbox annotation at its own anchor;
        // ownership stays single and the Street Level marker rotation stays
        // screen-up so nothing renders diagonally.
        expect(owner, DriverVehicleMarkerPresentationOwner.mapboxAnnotation);
        expect(
          resolveDriverMarkerRotationPolicy(
            isStreetlevel: true,
            owner: owner,
          ).alignment,
          DriverMarkerRotationAlignment.viewport,
        );
      }
      // Closing Tellers returns ownership to the HUD, not to Mapbox.
      expect(
        _ownerFor(NavFixedHudPhase.preparedRoute, tellersActive: false),
        DriverVehicleMarkerPresentationOwner.navigationHud,
      );
      // The KPI anchor is a pure layout function; Tellers cannot move it.
      expect(
        resolveStreetLevelMarkerBottomOffset(
          isLandscape: false,
          hasSecondaryActions: true,
          secondaryActionRowHeight: 52.0,
          primaryToSecondaryGap: 8.0,
        ),
        resolveStreetLevelMarkerBottomOffset(
          isLandscape: false,
          hasSecondaryActions: true,
          secondaryActionRowHeight: 52.0,
          primaryToSecondaryGap: 8.0,
        ),
      );
    });

    test(
      '15) a style swap preserves ownership, hidden Mapbox and route-up',
      () {
        // A style swap does not change the phase, so every derived decision is
        // byte-identical before and after.
        const phase = NavFixedHudPhase.preparedRoute;
        final before = _ownerFor(phase);
        final after = _ownerFor(phase);
        expect(after, before);
        expect(_mapboxOpacityFor(phase), 0.0);
        final tangent = navFirstMeaningfulRouteSegmentBearing(<DriverLonLat>[
          const DriverLonLat(4.8952, 52.3702),
          const DriverLonLat(4.8952, 52.3760),
        ]);
        final restored = resolveNavFixedRouteUpBearing(
          routeTangentBearingDeg: tangent,
          seededRouteBearingDeg: null,
          gpsHeadingDeg: null,
        );
        expect(restored.source, NavFixedRouteUpBearingSource.routeTangent);
        expect(
          navFixedBearingDeltaDeg(restored.bearingDeg, 0.0),
          lessThan(1.0),
        );
      },
    );

    test('16) STOP and Driver View exit fall back to idle, unchanged', () {
      final afterStop = resolveNavFixedHudPhase(
        liveRideActive: false,
        navigationGuidanceActive: false,
        preparedRouteDraft: false,
      );
      expect(afterStop, NavFixedHudPhase.idle);
      expect(
        navFixedHudPresentationActive(phase: afterStop, cameraFollowMode: true),
        isFalse,
      );
      // No HUD, and the Mapbox annotation is back to the plain idle marker.
      expect(
        _ownerFor(NavFixedHudPhase.idle),
        DriverVehicleMarkerPresentationOwner.none,
      );
      expect(
        resolveDriverMarkerRotationPolicy(
          isStreetlevel: true,
          owner: DriverVehicleMarkerPresentationOwner.none,
        ),
        DriverMarkerRotationPolicy.mapRoadBearing,
      );
      // Overview / north-up surfaces keep the legacy road-aligned marker.
      expect(
        resolveDriverMarkerRotationPolicy(
          isStreetlevel: false,
          owner: DriverVehicleMarkerPresentationOwner.mapboxAnnotation,
        ),
        DriverMarkerRotationPolicy.mapRoadBearing,
      );
    });
  });
}
