import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/navigation/nav_engine/nav_camera_policy.dart';
import 'package:fluxidi_tracking/navigation/nav_engine/nav_camera_view_mode.dart';

NavCameraPolicyInput _input({
  double? speedKmh = 30.0,
  double? routeConfidence = 80.0,
  bool offRouteLikely = false,
  bool routeDeviationLikely = false,
  bool reroutePending = false,
  bool hasReliableSnap = true,
  NavCameraViewMode viewMode = NavCameraViewMode.overview,
}) {
  return NavCameraPolicyInput(
    timestamp: DateTime(2026, 1, 1, 12),
    liveRideActive: true,
    cameraFollowMode: true,
    speedKmh: speedKmh,
    routeConfidence: routeConfidence,
    offRouteLikely: offRouteLikely,
    routeDeviationLikely: routeDeviationLikely,
    reroutePending: reroutePending,
    hasReliableSnap: hasReliableSnap,
    viewMode: viewMode,
  );
}

void main() {
  group('NAV-R15A NavCameraViewMode', () {
    test('default overview preserves legacy bearing weight at city speed', () {
      final out = DriverNavCameraPolicy().update(_input(speedKmh: 30.0));
      expect(out.bearingModeWeight, 1.0);
    });

    test('toggle cycles north up -> overview -> street view -> north up', () {
      expect(
        toggleNavCameraViewMode(NavCameraViewMode.northUp),
        NavCameraViewMode.overview,
      );
      expect(
        toggleNavCameraViewMode(NavCameraViewMode.overview),
        NavCameraViewMode.streetView,
      );
      expect(
        toggleNavCameraViewMode(NavCameraViewMode.streetView),
        NavCameraViewMode.northUp,
      );
    });

    test('north up keeps camera bearing fixed with zero route follow weight', () {
      final out = DriverNavCameraPolicy().update(
        _input(speedKmh: 40.0, viewMode: NavCameraViewMode.northUp),
      );
      expect(out.bearingModeWeight, 0.0);
      expect(northUpCameraBearingTarget(), 0.0);
      expect(navCameraViewModeUsesFixedNorthBearing(NavCameraViewMode.northUp), isTrue);
      expect(navCameraViewModeUsesFixedNorthBearing(NavCameraViewMode.overview), isFalse);
    });

    test('north up aligns using dedicated max step not route follow weight', () {
      final step = navCameraBearingMaxStepBase(
        viewMode: NavCameraViewMode.northUp,
        speedKmh: 25.0,
      );
      expect(step, northUpBearingAlignMaxStep(25.0));
      expect(step, greaterThan(0.0));
    });

    test('street view uses stronger bearing follow than overview', () {
      final overviewStep = navCameraBearingMaxStep(
        viewMode: NavCameraViewMode.overview,
        speedKmh: 25.0,
        bearingModeWeight: 1.0,
      );
      final street = DriverNavCameraPolicy().update(
        _input(speedKmh: 25.0, viewMode: NavCameraViewMode.streetView),
      );
      final streetStep = navCameraBearingMaxStep(
        viewMode: NavCameraViewMode.streetView,
        speedKmh: 25.0,
        bearingModeWeight: street.bearingModeWeight,
      );
      expect(streetStep, greaterThan(overviewStep));
      expect(street.bearingModeWeight, greaterThan(0.85));
    });

    test('low speed dampens street view rotation', () {
      final slow = streetViewBearingModeWeight(_input(speedKmh: 2.0));
      final city = streetViewBearingModeWeight(_input(speedKmh: 25.0));
      expect(slow, lessThan(0.25));
      expect(city, greaterThan(slow));
    });

    test('low confidence reduces street view bearing follow', () {
      final confident = streetViewBearingModeWeight(
        _input(speedKmh: 30.0, routeConfidence: 85.0),
      );
      final low = streetViewBearingModeWeight(
        _input(
          speedKmh: 30.0,
          routeConfidence: 40.0,
          hasReliableSnap: false,
        ),
      );
      expect(low, lessThan(confident));
      expect(low, lessThan(0.35));
    });

    test('off-route dampens street view bearing follow', () {
      final weight = streetViewBearingModeWeight(
        _input(speedKmh: 40.0, offRouteLikely: true, routeConfidence: 30.0),
      );
      expect(weight, lessThan(0.3));
    });

    test('street view bearing max step exceeds overview at highway speed', () {
      final overviewStep = navCameraBearingMaxStep(
        viewMode: NavCameraViewMode.overview,
        speedKmh: 60.0,
        bearingModeWeight: 1.0,
      );
      final streetStep = navCameraBearingMaxStep(
        viewMode: NavCameraViewMode.streetView,
        speedKmh: 60.0,
        bearingModeWeight: 1.0,
      );
      expect(streetStep, greaterThan(overviewStep));
    });

    test('street view padding anchors taxi lower than overview', () {
      final overview = navCameraViewPadding(
        mode: NavCameraViewMode.overview,
        isLandscape: false,
        safeTop: 40,
        safeBottom: 20,
      );
      final northUp = navCameraViewPadding(
        mode: NavCameraViewMode.northUp,
        isLandscape: false,
        safeTop: 40,
        safeBottom: 20,
      );
      final street = navCameraViewPadding(
        mode: NavCameraViewMode.streetView,
        isLandscape: false,
        safeTop: 40,
        safeBottom: 20,
      );
      expect(street.bottom, greaterThan(overview.bottom));
      expect(street.top, lessThan(overview.top));
      expect(northUp.bottom, overview.bottom);
      expect(northUp.top, overview.top);
    });

    test('overview mode output unchanged when not in street view', () {
      final policy = DriverNavCameraPolicy();
      final a = policy.update(_input(speedKmh: 50.0));
      policy.reset();
      final b = policy.update(
        _input(speedKmh: 50.0, viewMode: NavCameraViewMode.overview),
      );
      expect(a.bearingModeWeight, b.bearingModeWeight);
      expect(a.targetZoom, b.targetZoom);
    });

    test('north up does not apply street view zoom/tilt tuning', () {
      final policy = DriverNavCameraPolicy();
      final north = policy.update(
        _input(speedKmh: 30.0, viewMode: NavCameraViewMode.northUp),
      );
      policy.reset();
      final overview = policy.update(_input(speedKmh: 30.0));
      expect(north.zoom, overview.zoom);
      expect(north.tilt, overview.tilt);
      expect(north.reason, isNot(contains('street_view')));
    });
  });
}
