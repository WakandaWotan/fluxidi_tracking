import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/navigation/nav_engine/nav_camera_policy.dart';

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
  );
}

void main() {
  group('NAV-R12-H dynamic zoom: speed bands', () {
    test('city speed keeps a close zoom (16.5–17.0)', () {
      final out = DriverNavCameraPolicy().update(_input(speedKmh: 15.0));
      expect(out.shouldFollow, isTrue);
      expect(out.zoomReason, 'speed');
      expect(out.targetZoom, inInclusiveRange(16.5, 17.0));
    });

    test('medium speed widens the view (15.2–16.2)', () {
      final out = DriverNavCameraPolicy().update(_input(speedKmh: 45.0));
      expect(out.targetZoom, inInclusiveRange(15.2, 16.2));
    });

    test('fast driving widens further (14.2–15.0)', () {
      final out = DriverNavCameraPolicy().update(_input(speedKmh: 80.0));
      expect(out.targetZoom, inInclusiveRange(14.2, 15.0));
    });

    test('highway speed shows the most road ahead (13.5–14.2)', () {
      final out = DriverNavCameraPolicy().update(_input(speedKmh: 110.0));
      expect(out.targetZoom, inInclusiveRange(13.5, 14.2));
      expect(out.zoom, inInclusiveRange(13.5, 14.2));
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
      expect(out.targetZoom, 16.5);
    });
  });

  group('NAV-R12-H dynamic zoom: maneuver proximity', () {
    test('very close maneuver zooms in toward 17.0 at city speed', () {
      final out = DriverNavCameraPolicy().update(
        _input(speedKmh: 40.0, nearManeuver: true, distanceToManeuverM: 60.0),
      );
      expect(out.zoomReason, 'maneuver');
      expect(out.targetZoom, 17.0);
    });

    test('near maneuver zooms in moderately', () {
      final out = DriverNavCameraPolicy().update(
        _input(speedKmh: 40.0, nearManeuver: true, distanceToManeuverM: 200.0),
      );
      expect(out.zoomReason, 'maneuver');
      expect(out.targetZoom, 16.4);
    });

    test('high speed keeps a wider view even close to the maneuver', () {
      final out = DriverNavCameraPolicy().update(
        _input(speedKmh: 90.0, nearManeuver: true, distanceToManeuverM: 60.0),
      );
      expect(out.targetZoom, 16.2);
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
      expect(out.zoom, closeTo(DriverNavCameraPolicy.speedZoomFor(40.0), 0.01));
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
      expect(out.targetZoom, DriverNavCameraPolicy.stoppedZoom);
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
  });
}
