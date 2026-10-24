import '../driver_navigation_route_parser.dart';
import '../nav_backend/driver_route_apply.dart';
import 'navigation_traffic_model.dart';
import 'navigation_route_warning_controller.dart';

class NavigationTrafficParsedRoute extends DriverRouteParseResult {
  NavigationTrafficParsedRoute(
    DriverRouteParseResult parsed,
    this.traffic, [
    this.warningBinding,
  ]) : super(
         coords: parsed.coords,
         distanceMeters: parsed.distanceMeters,
         durationSeconds: parsed.durationSeconds,
         navSteps: parsed.navSteps,
         stepsWithBannerCount: parsed.stepsWithBannerCount,
         stepsWithLaneGuidanceCount: parsed.stepsWithLaneGuidanceCount,
       );
  final NavigationTrafficSnapshot traffic;
  final NavigationRouteWarningBinding? warningBinding;
}

class NavigationTrafficPreparedRoute extends DriverPreparedRoutePackage {
  NavigationTrafficPreparedRoute(
    DriverPreparedRoutePackage package,
    this.traffic, [
    this.warningBinding,
  ]) : super(
         coords: package.coords,
         navSteps: package.navSteps,
         distanceMeters: package.distanceMeters,
         durationSeconds: package.durationSeconds,
         source: package.source,
         geometryFingerprint: package.geometryFingerprint,
         stepsWithBannerCount: package.stepsWithBannerCount,
         stepsWithLaneGuidanceCount: package.stepsWithLaneGuidanceCount,
       );
  final NavigationTrafficSnapshot traffic;
  final NavigationRouteWarningBinding? warningBinding;
}

DriverRouteParseResult bindNavigationTrafficParseResult({
  required DriverRouteParseResult parsed,
  required Map<String, dynamic> response,
  DateTime? now,
  NavigationRouteWarningBinding? warningBinding,
}) => NavigationTrafficParsedRoute(
  parsed,
  decodeNavigationTraffic(
    response: response,
    geometry: parsed.coords,
    now: now ?? DateTime.now(),
  ),
  warningBinding,
);

DriverPreparedRoutePackage prepareNavigationTrafficRoutePackage({
  required DriverRouteParseResult parsed,
  required DriverRouteResponseSource source,
}) => NavigationTrafficPreparedRoute(
  prepareDriverRoutePackage(parsed: parsed, source: source),
  parsed is NavigationTrafficParsedRoute
      ? parsed.traffic
      : const NavigationTrafficSnapshot.unavailable(),
  parsed is NavigationTrafficParsedRoute &&
          (source == DriverRouteResponseSource.worker ||
              source == DriverRouteResponseSource.workerReroute)
      ? parsed.warningBinding
      : null,
);
