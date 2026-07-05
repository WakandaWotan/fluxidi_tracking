import 'dart:math' as math;

import 'package:geolocator/geolocator.dart' as geo;

import 'driver_navigation_formatters.dart';
import 'driver_navigation_geometry.dart';
import 'driver_navigation_models.dart';

const double kDriverNavStepPassStraightLineMeters = 32.0;
const double kDriverNavStepPassRouteBufferMeters = 18.0;

class DriverNavInstructionUpdate {
  final int nextStepIndex;
  final String? instruction;
  final String? street;
  final double? distanceMeters;
  final String? type;
  final String? modifier;
  final bool shouldClear;
  final bool hasInstruction;
  final String progressSource;
  final double logDistanceMeters;

  const DriverNavInstructionUpdate({
    required this.nextStepIndex,
    required this.instruction,
    required this.street,
    required this.distanceMeters,
    required this.type,
    required this.modifier,
    required this.shouldClear,
    required this.hasInstruction,
    required this.progressSource,
    required this.logDistanceMeters,
  });
}

DriverNavInstructionUpdate computeDriverNextNavInstruction({
  required List<DriverNavStep> routeSteps,
  required int nextStepIndex,
  required double posLat,
  required double posLon,
  required DriverRouteSnap? lastRouteSnap,
  required List<DriverLonLat> routeCoords,
  required bool useMatchedVisual,
}) {
  if (routeSteps.isEmpty) {
    return DriverNavInstructionUpdate(
      nextStepIndex: nextStepIndex,
      instruction: null,
      street: null,
      distanceMeters: null,
      type: null,
      modifier: null,
      shouldClear: true,
      hasInstruction: false,
      progressSource: 'raw_fallback',
      logDistanceMeters: 0.0,
    );
  }

  final posPoint = DriverLonLat(posLon, posLat);
  final snap = lastRouteSnap ?? driverSnapToRouteOn(routeCoords, posPoint);
  final progressM = (useMatchedVisual && snap != null)
      ? snap.distanceAlongRouteM
      : null;
  final progressSource = progressM == null ? 'raw_fallback' : 'matched';
  var resolvedStepIndex = nextStepIndex;

  while (resolvedStepIndex < routeSteps.length - 1) {
    final current = routeSteps[resolvedStepIndex];
    final straightLineM = geo.Geolocator.distanceBetween(
      posLat,
      posLon,
      current.lat,
      current.lon,
    );
    final passedByRouteProgress =
        progressM != null &&
        progressM >=
            current.distanceAlongRouteM + kDriverNavStepPassRouteBufferMeters;
    if (straightLineM <= kDriverNavStepPassStraightLineMeters ||
        passedByRouteProgress) {
      resolvedStepIndex += 1;
    } else {
      break;
    }
  }

  final step = routeSteps[resolvedStepIndex];
  final distanceM = progressM == null
      ? geo.Geolocator.distanceBetween(posLat, posLon, step.lat, step.lon)
      : math.max(0.0, step.distanceAlongRouteM - progressM);

  return DriverNavInstructionUpdate(
    nextStepIndex: resolvedStepIndex,
    instruction: step.instruction,
    street: step.street,
    distanceMeters: distanceM,
    type: step.type,
    modifier: step.modifier,
    shouldClear: false,
    hasInstruction: true,
    progressSource: progressSource,
    logDistanceMeters: distanceM,
  );
}

String _snapshotSecondaryFromStep(DriverNavStep step) {
  final street = step.street.trim();
  if (street.isNotEmpty) return street;
  final ref = (step.roadRef ?? '').trim();
  if (ref.isNotEmpty) return ref;
  final destination = (step.destinationText ?? '').trim();
  if (destination.isNotEmpty) return destination;
  return '';
}

String? _trimmedOrNull(String? raw) {
  final text = (raw ?? '').trim();
  return text.isEmpty ? null : text;
}

NavInstructionSnapshot buildDriverNavInstructionSnapshot({
  required List<DriverNavStep> routeSteps,
  required int nextStepIndex,
  required double posLat,
  required double posLon,
  required DriverRouteSnap? lastRouteSnap,
  required List<DriverLonLat> routeCoords,
  required bool useMatchedVisual,
  required DriverNavTranslate tr,
  bool navStepsLoading = false,
}) {
  if (routeSteps.isEmpty) {
    return navStepsLoading
        ? NavInstructionSnapshot.loading
        : NavInstructionSnapshot.none;
  }

  final update = computeDriverNextNavInstruction(
    routeSteps: routeSteps,
    nextStepIndex: nextStepIndex,
    posLat: posLat,
    posLon: posLon,
    lastRouteSnap: lastRouteSnap,
    routeCoords: routeCoords,
    useMatchedVisual: useMatchedVisual,
  );

  if (update.shouldClear) {
    return navStepsLoading
        ? NavInstructionSnapshot.loading
        : NavInstructionSnapshot.none;
  }

  final step = routeSteps[update.nextStepIndex];
  final distanceM = update.distanceMeters ?? 0.0;
  final banner = step.banner;
  final bannerPrimary = (banner?.primaryText ?? '').trim();

  late final NavInstructionSource source;
  late final String primaryText;
  var secondaryText = '';
  String? subText;

  if (bannerPrimary.isNotEmpty) {
    source = NavInstructionSource.banner;
    primaryText = bannerPrimary;
    secondaryText = (banner?.secondaryText ?? '').trim();
    subText = _trimmedOrNull(banner?.subText);
  } else {
    final instruction = step.instruction.trim();
    final shortAction = driverShortNavAction(
      instruction,
      step.type,
      step.modifier,
      tr: tr,
    );
    if (instruction.isNotEmpty) {
      source = NavInstructionSource.step;
      primaryText = instruction;
    } else if (shortAction.trim().isNotEmpty) {
      source = NavInstructionSource.fallback;
      primaryText = shortAction.trim();
    } else {
      source = NavInstructionSource.fallback;
      primaryText = '';
    }
  }

  if (secondaryText.isEmpty) {
    secondaryText = _snapshotSecondaryFromStep(step);
  }

  return NavInstructionSnapshot(
    distanceToManeuverMeters: distanceM,
    primaryText: primaryText,
    secondaryText: secondaryText,
    subText: subText,
    maneuverType: step.type,
    maneuverModifier: step.modifier,
    roadName: step.street,
    exitNumber: _trimmedOrNull(step.exitNumber),
    destinationText: _trimmedOrNull(step.destinationText),
    roadRef: _trimmedOrNull(step.roadRef),
    isHighwayLike: isDriverHighwayLikeStep(step),
    lanes: step.lanes,
    source: source,
  );
}
