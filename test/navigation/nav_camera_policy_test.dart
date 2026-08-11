import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/navigation/nav_engine/nav_camera_policy.dart';
import 'package:fluxidi_tracking/navigation/nav_engine/nav_camera_view_mode.dart';
import 'package:fluxidi_tracking/navigation/presentation/navigation_driver_cockpit_camera.dart';

NavCameraPolicyInput _input({
  bool liveRideActive = true,
  bool cameraFollowMode = true,
  bool manualRecenter = false,
  double? speedKmh,
  double? accuracyM = 8.0,
  double? routeConfidence = 80.0,
  bool offRouteLikely = false,
  bool routeDeviationLikely = false,
  bool oppositeDirectionLikely = false,
  bool backwardProgressLikely = false,
  bool reroutePending = false,
  double? distanceToManeuverM,
  bool nearManeuver = false,
  bool waitingMode = false,
  bool hasReliableSnap = true,
  NavCameraViewMode viewMode = NavCameraViewMode.overview,
}) {
  return NavCameraPolicyInput(
    timestamp: DateTime(2026, 1, 1, 12),
    liveRideActive: liveRideActive,
    cameraFollowMode: cameraFollowMode,
    manualRecenter: manualRecenter,
    speedKmh: speedKmh,
    accuracyM: accuracyM,
    routeConfidence: routeConfidence,
    offRouteLikely: offRouteLikely,
    routeDeviationLikely: routeDeviationLikely,
    oppositeDirectionLikely: oppositeDirectionLikely,
    backwardProgressLikely: backwardProgressLikely,
    reroutePending: reroutePending,
    distanceToManeuverM: distanceToManeuverM,
    nearManeuver: nearManeuver,
    waitingMode: waitingMode,
    hasReliableSnap: hasReliableSnap,
    viewMode: viewMode,
  );
}

void main() {
  const bias = DriverNavCameraPolicy.nonStreetViewOverviewZoomBias;

  group('NAV-R12-H dynamic zoom: speed bands', () {
    test('city speed keeps a close zoom (biased overview)', () {
      final out = DriverNavCameraPolicy().update(_input(speedKmh: 15.0));
      expect(out.shouldFollow, isTrue);
      expect(out.zoomReason, 'speed');
      expect(out.targetZoom, inInclusiveRange(16.05, 16.55));
    });

    test('NAV-R13: ~30 km/h gives a moderate overview', () {
      final out = DriverNavCameraPolicy().update(_input(speedKmh: 30.0));
      expect(out.targetZoom, inInclusiveRange(14.95, 15.35));
    });

    test('NAV-R13: ~50 km/h shows a top-down overview', () {
      final out = DriverNavCameraPolicy().update(_input(speedKmh: 50.0));
      expect(out.targetZoom, inInclusiveRange(14.35, 14.65));
    });

    test('fast driving widens further', () {
      final out = DriverNavCameraPolicy().update(_input(speedKmh: 80.0));
      expect(out.targetZoom, inInclusiveRange(13.55, 14.15));
    });

    test('highway speed shows the most road ahead', () {
      final out = DriverNavCameraPolicy().update(_input(speedKmh: 110.0));
      expect(out.targetZoom, inInclusiveRange(13.05, 13.75));
      expect(out.zoom, inInclusiveRange(13.05, 13.75));
    });

    test('speed zoom is monotonically non-increasing with speed', () {
      var previous = double.infinity;
      for (var speed = 0.0; speed <= 130.0; speed += 1.0) {
        final zoom = DriverNavCameraPolicy.speedZoomFor(speed);
        expect(
          zoom,
          lessThanOrEqualTo(previous + 0.3001),
          reason: 'speed $speed km/h',
        );
        if (speed > 3.0) previous = zoom;
      }
    });

    test('stopped/crawling holds the previous zoom (no jitter)', () {
      final policy = DriverNavCameraPolicy();
      final moving = policy.update(_input(speedKmh: 40.0));
      final stopped = policy.update(_input(speedKmh: 1.0));
      expect(stopped.targetZoom, moving.zoom);
      expect(stopped.zoom, moving.zoom);
    });

    test('missing speed falls back to holding zoom', () {
      final out = DriverNavCameraPolicy().update(_input(speedKmh: null));
      expect(out.zoomReason, 'fallback');
      expect(out.targetZoom, closeTo(16.5 + bias, 1e-9));
    });
  });

  group('NAV-R12-H dynamic zoom: maneuver proximity', () {
    test('very close maneuver (<=80 m) zooms in at city speed', () {
      final out = DriverNavCameraPolicy().update(
        _input(speedKmh: 40.0, nearManeuver: true, distanceToManeuverM: 60.0),
      );
      expect(out.zoomReason, 'maneuver');
      expect(out.targetZoom, closeTo(16.6 + bias, 1e-9));
    });

    test('near maneuver (<=120 m) zooms in moderately', () {
      final out = DriverNavCameraPolicy().update(
        _input(speedKmh: 40.0, nearManeuver: true, distanceToManeuverM: 100.0),
      );
      expect(out.zoomReason, 'maneuver');
      expect(out.targetZoom, closeTo(16.0 + bias, 1e-9));
    });

    test('NAV-R13: a maneuver beyond 120 m keeps the speed overview', () {
      final out = DriverNavCameraPolicy().update(
        _input(speedKmh: 50.0, nearManeuver: true, distanceToManeuverM: 200.0),
      );
      expect(out.zoomReason, 'speed');
      expect(
        out.targetZoom,
        closeTo(DriverNavCameraPolicy.speedZoomFor(50.0) + bias, 1e-9),
      );
    });

    test('high speed keeps a wider view even close to the maneuver', () {
      final out = DriverNavCameraPolicy().update(
        _input(speedKmh: 90.0, nearManeuver: true, distanceToManeuverM: 60.0),
      );
      expect(out.targetZoom, closeTo(15.8 + bias, 1e-9));
    });

    test('after the maneuver passes, zoom returns to the speed band', () {
      final policy = DriverNavCameraPolicy();
      policy.update(
        _input(speedKmh: 40.0, nearManeuver: true, distanceToManeuverM: 60.0),
      );
      // Maneuver passed: several updates ramp back toward the speed zoom.
      NavCameraPolicyOutput? out;
      for (var i = 0; i < 10; i++) {
        out = policy.update(_input(speedKmh: 40.0));
      }
      expect(out!.zoomReason, 'speed');
      expect(
        out.zoom,
        closeTo(DriverNavCameraPolicy.speedZoomFor(40.0) + bias, 0.01),
      );
    });
  });

  group('NAV-R12-H dynamic zoom: route adaptation context', () {
    for (final flag in const <String>[
      'routeDeviationLikely',
      'oppositeDirectionLikely',
      'backwardProgressLikely',
      'reroutePending',
    ]) {
      test('$flag prevents an overly tight zoom', () {
        final out = DriverNavCameraPolicy().update(
          _input(
            speedKmh: 12.0,
            routeDeviationLikely: flag == 'routeDeviationLikely',
            oppositeDirectionLikely: flag == 'oppositeDirectionLikely',
            backwardProgressLikely: flag == 'backwardProgressLikely',
            reroutePending: flag == 'reroutePending',
          ),
        );
        expect(out.zoomReason, 'adaptation');
        expect(
          out.targetZoom,
          lessThanOrEqualTo(DriverNavCameraPolicy.adaptationMaxZoom),
        );
      });
    }

    test('stopped with an excellent fix may stay close during adaptation', () {
      final out = DriverNavCameraPolicy().update(
        _input(speedKmh: 1.0, accuracyM: 5.0, routeDeviationLikely: true),
      );
      expect(out.zoomReason, 'speed');
      expect(
        out.targetZoom,
        closeTo(DriverNavCameraPolicy.stoppedZoom + bias, 1e-9),
      );
    });

    test('adaptation also softens tilt for context', () {
      final out = DriverNavCameraPolicy().update(
        _input(speedKmh: 20.0, reroutePending: true),
      );
      expect(out.zoomReason, 'adaptation');
      expect(out.tilt, lessThanOrEqualTo(52.0));
    });
  });

  group('NAV-R12-H dynamic zoom: smoothing and manual safety', () {
    test('max-step smoothing prevents large zoom jumps', () {
      final policy = DriverNavCameraPolicy();
      final city = policy.update(_input(speedKmh: 10.0));
      final highway = policy.update(_input(speedKmh: 110.0));
      expect(
        city.zoom - highway.zoom,
        lessThanOrEqualTo(DriverNavCameraPolicy.maxZoomStepPerUpdate + 1e-9),
      );
      // Keeps ramping toward the wide highway zoom on later updates.
      var last = highway;
      for (var i = 0; i < 20; i++) {
        final next = policy.update(_input(speedKmh: 110.0));
        expect(next.zoom, lessThanOrEqualTo(last.zoom + 1e-9));
        last = next;
      }
      expect(last.zoom, closeTo(last.targetZoom, 0.01));
    });

    test('manual/not-follow mode never forces auto-zoom', () {
      final policy = DriverNavCameraPolicy();
      final following = policy.update(_input(speedKmh: 10.0));
      final manual = policy.update(_input(cameraFollowMode: false));
      expect(manual.shouldFollow, isFalse);
      expect(manual.zoomReason, 'manual_hold');
      // Holds the last applied zoom instead of steering somewhere new.
      expect(manual.zoom, closeTo(following.zoom, 1e-9));
    });

    test('zoom always stays within the allowed range', () {
      final policy = DriverNavCameraPolicy();
      for (final speed in const <double>[0, 5, 20, 50, 80, 120, 200]) {
        final out = policy.update(_input(speedKmh: speed));
        expect(out.zoom, inInclusiveRange(13.0, 18.5));
      }
    });

    test('NAV-R13: tilt never exceeds 58° in any follow context', () {
      for (final speed in const <double>[0, 5, 20, 50, 80, 120]) {
        for (final distance in const <double?>[null, 60.0, 100.0, 500.0]) {
          final out = DriverNavCameraPolicy().update(
            _input(
              speedKmh: speed,
              nearManeuver: distance != null,
              distanceToManeuverM: distance,
            ),
          );
          expect(
            out.tilt,
            lessThanOrEqualTo(DriverNavCameraPolicy.maxTiltDeg),
            reason: 'speed=$speed maneuverDistance=$distance',
          );
        }
      }
    });
  });

  group('NAV-NON3D-CAMERA-OVERVIEW-P0 isolation', () {
    test('1) 3D Pro2 streetlevel L7 constants remain exact', () {
      expect(kDriverCockpitPro2PhoneZoomL7, 19.1);
      expect(kDriverCockpitPro2PhonePitchL7, 77.0);
      expect(kDriverCockpitPro2CompactZoomL7, 18.4);
      expect(kDriverCockpitPro2CompactPitchL7, 75.0);
      expect(
        driverCockpitViewLevelTargetZoom(
          isTablet: false,
          isLandscape: false,
          level: 7,
        ),
        19.1,
      );
      expect(
        driverCockpitViewLevelTargetPitch(
          isTablet: false,
          isLandscape: false,
          level: 7,
        ),
        77.0,
      );
      expect(
        driverCockpitViewLevelTargetZoom(
          isTablet: true,
          isLandscape: false,
          level: 7,
        ),
        18.4,
      );
      expect(
        driverCockpitViewLevelTargetPitch(
          isTablet: true,
          isLandscape: false,
          level: 7,
        ),
        75.0,
      );
    });

    test('2) overview receives the raised overview zoom bias', () {
      final overview = DriverNavCameraPolicy().update(
        _input(speedKmh: 40.0, viewMode: NavCameraViewMode.overview),
      );
      final expected =
          DriverNavCameraPolicy.speedZoomFor(40.0) + bias;
      expect(overview.targetZoom, closeTo(expected, 1e-9));
      expect(bias, lessThan(0));
    });

    test('3) northUp receives the same overview bias as overview', () {
      final north = DriverNavCameraPolicy().update(
        _input(speedKmh: 40.0, viewMode: NavCameraViewMode.northUp),
      );
      final overview = DriverNavCameraPolicy().update(
        _input(speedKmh: 40.0, viewMode: NavCameraViewMode.overview),
      );
      expect(north.targetZoom, closeTo(overview.targetZoom, 1e-9));
    });

    test('4) streetView policy zoom is NOT biased (3D seed preserved)', () {
      final street = DriverNavCameraPolicy().update(
        _input(speedKmh: 40.0, viewMode: NavCameraViewMode.streetView),
      );
      // streetViewCameraTuning adds +0.35 to applied zoom, but targetZoom
      // before tuning must match the unbiased speed band.
      expect(
        street.targetZoom,
        closeTo(DriverNavCameraPolicy.speedZoomFor(40.0), 1e-9),
      );
      expect(
        street.targetZoom,
        isNot(
          closeTo(
            DriverNavCameraPolicy.speedZoomFor(40.0) + bias,
            1e-9,
          ),
        ),
      );
    });

    test('5) switching overview ↔ streetView restores mode-specific zoom', () {
      final policy = DriverNavCameraPolicy();
      // Warm overview.
      for (var i = 0; i < 8; i++) {
        policy.update(
          _input(speedKmh: 40.0, viewMode: NavCameraViewMode.overview),
        );
      }
      final overview = policy.update(
        _input(speedKmh: 40.0, viewMode: NavCameraViewMode.overview),
      );
      expect(
        overview.targetZoom,
        closeTo(DriverNavCameraPolicy.speedZoomFor(40.0) + bias, 1e-9),
      );

      // Switch to streetView: target loses bias immediately.
      final street = policy.update(
        _input(speedKmh: 40.0, viewMode: NavCameraViewMode.streetView),
      );
      expect(
        street.targetZoom,
        closeTo(DriverNavCameraPolicy.speedZoomFor(40.0), 1e-9),
      );

      // Back to overview: bias returns.
      for (var i = 0; i < 8; i++) {
        policy.update(
          _input(speedKmh: 40.0, viewMode: NavCameraViewMode.overview),
        );
      }
      final back = policy.update(
        _input(speedKmh: 40.0, viewMode: NavCameraViewMode.overview),
      );
      expect(
        back.targetZoom,
        closeTo(DriverNavCameraPolicy.speedZoomFor(40.0) + bias, 1e-9),
      );
    });

    test('6) reroute adaptation on overview stays biased, not Pro2', () {
      final out = DriverNavCameraPolicy().update(
        _input(
          speedKmh: 12.0,
          reroutePending: true,
          viewMode: NavCameraViewMode.overview,
        ),
      );
      expect(out.zoomReason, 'adaptation');
      expect(
        out.targetZoom,
        closeTo(
          DriverNavCameraPolicy.adaptationMaxZoom + bias,
          1e-9,
        ),
      );
      // Must never jump to cockpit L7 zooms.
      expect(out.targetZoom, lessThan(17.0));
      expect(out.targetZoom, isNot(closeTo(kDriverCockpitPro2PhoneZoomL7, 0.5)));
      expect(
        out.targetZoom,
        isNot(closeTo(kDriverCockpitPro2CompactZoomL7, 0.5)),
      );
    });

    test('7) phone/tablet Pro2 L7 remain distinct and above overview', () {
      final overview = DriverNavCameraPolicy().update(
        _input(speedKmh: 0.0, viewMode: NavCameraViewMode.overview),
      );
      expect(overview.targetZoom, lessThan(kDriverCockpitPro2CompactZoomL7));
      expect(kDriverCockpitPro2PhoneZoomL7, greaterThan(kDriverCockpitPro2CompactZoomL7));
    });
  });
}
