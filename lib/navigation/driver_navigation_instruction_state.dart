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

bool driverTextLooksLikeManeuverAction(String text) {
  final lower = text.trim().toLowerCase();
  if (lower.isEmpty) return false;
  const markers = <String>[
    'turn',
    'left',
    'right',
    'straight',
    'continue',
    'merge',
    'fork',
    'roundabout',
    'rotary',
    'uturn',
    'u-turn',
    'exit',
    'ramp',
    'depart',
    'arrive',
    'destination',
    'keep',
    'take the',
    'sla ',
    'links',
    'rechts',
    'rechtdoor',
    'neem',
    'afrit',
    'rotonde',
    'tournez',
    'continuez',
    'sortie',
    'gira',
    'sigue',
    'rotonda',
    'richting',
    'toward',
    'direction',
    'hacia',
    'vers ',
  ];
  for (final marker in markers) {
    if (lower.contains(marker)) return true;
  }
  return false;
}

bool driverTextLooksLikeRoadLabel(String text) {
  final t = text.trim();
  if (t.isEmpty || driverTextLooksLikeManeuverAction(t)) return false;
  if (RegExp(r'\b[ENA]\d+\b', caseSensitive: false).hasMatch(t)) return true;
  if (t.contains(' / ')) return true;
  return false;
}

bool _textLooksLikeRoadContext(String text, DriverNavStep step) {
  final t = text.trim();
  if (t.isEmpty || driverTextLooksLikeManeuverAction(t)) return false;
  final street = step.street.trim();
  final ref = (step.roadRef ?? '').trim();
  if (street.isNotEmpty && ref.isNotEmpty && t == '$street / $ref') {
    return true;
  }
  if (t.contains(' / ')) {
    return RegExp(r'\b[ENA]\d+\b', caseSensitive: false).hasMatch(t) ||
        (ref.isNotEmpty && t.contains(ref));
  }
  if (ref.isNotEmpty && t.contains(ref)) return true;
  return driverTextLooksLikeRoadLabel(t);
}

bool _labelsReferToSameRoad(String a, String b) {
  final left = a.trim().toLowerCase();
  final right = b.trim().toLowerCase();
  if (left.isEmpty || right.isEmpty) return false;
  if (left == right) return true;
  if (left.contains(right) || right.contains(left)) return true;
  final leftStreet = left.split(' / ').first.trim();
  final rightStreet = right.split(' / ').first.trim();
  if (leftStreet.isNotEmpty &&
      rightStreet.isNotEmpty &&
      (leftStreet == rightStreet ||
          leftStreet.contains(rightStreet) ||
          rightStreet.contains(leftStreet))) {
    return true;
  }
  return false;
}

String? _parseManeuverTargetFromInstruction(String instruction) {
  final text = instruction.trim();
  if (text.isEmpty) return null;
  final patterns = <RegExp>[
    RegExp(
      r'(?:turn|sla|tournez|gira|bear)\s+(?:\w+\s+){0,4}(?:onto|on|op|naar|toward|towards|richting|vers|hacia|sur)\s+(.+)$',
      caseSensitive: false,
    ),
    RegExp(
      r'(?:onto|on|op|naar|toward|towards|richting|vers|hacia)\s+(.+)$',
      caseSensitive: false,
    ),
  ];
  for (final pattern in patterns) {
    final match = pattern.firstMatch(text);
    if (match == null) continue;
    final candidate = match.group(1)?.trim();
    if (candidate != null &&
        candidate.isNotEmpty &&
        !driverTextLooksLikeManeuverAction(candidate)) {
      return candidate;
    }
  }
  return null;
}

String _augmentTargetLabelWithRef(String target, DriverNavStep step) {
  final label = target.trim();
  final ref = (step.roadRef ?? '').trim();
  if (label.isEmpty || ref.isEmpty) return label;
  if (label.toLowerCase().contains(ref.toLowerCase())) return label;
  final street = step.street.trim();
  if (street.isNotEmpty &&
      _labelsReferToSameRoad(label, street) &&
      _instructionMentionsTarget(step.instruction, label)) {
    return '$street / $ref';
  }
  return label;
}

bool driverNavStepIsTurnLike(DriverNavStep step) {
  final type = step.type.trim().toLowerCase();
  final modifier = step.modifier.trim().toLowerCase();
  if (type.contains('turn') ||
      type.contains('fork') ||
      type.contains('merge') ||
      type.contains('ramp')) {
    return true;
  }
  if (modifier.contains('left') ||
      modifier.contains('right') ||
      modifier.contains('uturn') ||
      modifier.contains('u-turn')) {
    return true;
  }
  return false;
}

/// Best-effort maneuver target label from banner secondary, instruction, or
/// destination. Does not invent names beyond parsed step data.
String? driverStepManeuverTargetLabel(DriverNavStep step) {
  final bannerSecondary = (step.banner?.secondaryText ?? '').trim();
  if (bannerSecondary.isNotEmpty &&
      !driverTextLooksLikeManeuverAction(bannerSecondary)) {
    return bannerSecondary;
  }
  final fromInstruction = _parseManeuverTargetFromInstruction(step.instruction);
  if (fromInstruction != null && fromInstruction.isNotEmpty) {
    return _augmentTargetLabelWithRef(fromInstruction, step);
  }
  final destination = (step.destinationText ?? '').trim();
  if (destination.isNotEmpty) return destination;
  return null;
}

String driverNavManeuverTargetSource(DriverNavStep step) {
  final bannerSecondary = (step.banner?.secondaryText ?? '').trim();
  if (bannerSecondary.isNotEmpty) return 'banner';
  if (_parseManeuverTargetFromInstruction(step.instruction) != null) {
    return 'instruction';
  }
  if ((step.destinationText ?? '').trim().isNotEmpty) return 'destination';
  return 'none';
}

bool _textLooksLikeStepTargetRoad(String text, DriverNavStep step) {
  final t = text.trim();
  if (t.isEmpty) return false;
  final maneuverTarget = driverStepManeuverTargetLabel(step);
  if (maneuverTarget != null && _labelsReferToSameRoad(t, maneuverTarget)) {
    return true;
  }
  if (_instructionMentionsTarget(step.instruction, t)) return true;
  final bannerSecondary = (step.banner?.secondaryText ?? '').trim();
  if (bannerSecondary.isNotEmpty && _labelsReferToSameRoad(t, bannerSecondary)) {
    return true;
  }
  final destination = (step.destinationText ?? '').trim();
  if (destination.isNotEmpty && _labelsReferToSameRoad(t, destination)) {
    return true;
  }
  return false;
}

String driverNavBannerPrimaryKind({
  required String primaryText,
  required DriverNavStep step,
}) {
  final primary = primaryText.trim();
  if (primary.isEmpty) return 'unknown';
  if (driverTextLooksLikeManeuverAction(primary)) return 'action';
  if (_textLooksLikeStepTargetRoad(primary, step)) return 'target';
  if (_textLooksLikeRoadContext(primary, step) ||
      driverTextLooksLikeRoadLabel(primary)) {
    return 'roadContext';
  }
  return 'unknown';
}

String _currentRoadContextLabel(DriverNavStep step, {String? exclude}) {
  final street = step.street.trim();
  final ref = (step.roadRef ?? '').trim();
  final label = street.isNotEmpty && ref.isNotEmpty
      ? '$street / $ref'
      : (street.isNotEmpty ? street : ref);
  if (label.isEmpty) return '';
  if (exclude != null && exclude.trim() == label) return '';
  return label;
}

String _dedupeSecondaryLine(String primary, String secondary) {
  final p = primary.trim();
  final s = secondary.trim();
  if (s.isEmpty || p == s) return '';
  if (p.toLowerCase().contains(s.toLowerCase())) return '';
  return s;
}

bool _instructionMentionsTarget(String instruction, String target) {
  final i = instruction.trim().toLowerCase();
  final t = target.trim().toLowerCase();
  if (i.isEmpty || t.isEmpty) return false;
  return i.contains(t);
}

/// Mapbox banner primary is sometimes the current road/ref; secondary is the
/// target road. Normalize so the banner foregrounds the target road.
({String primary, String secondary, bool swapped}) normalizeDriverInstructionDisplayLines({
  required String rawPrimary,
  required String rawSecondary,
  required DriverNavStep step,
}) {
  var primary = rawPrimary.trim();
  var secondary = rawSecondary.trim();

  if (primary.isEmpty && secondary.isNotEmpty) {
    primary = secondary;
    secondary = '';
  }

  if (secondary.isNotEmpty && !driverTextLooksLikeManeuverAction(secondary)) {
    final primaryIsTarget = _textLooksLikeStepTargetRoad(primary, step);
    final secondaryIsTarget = _textLooksLikeStepTargetRoad(secondary, step);
    final primaryIsRoadLabel =
        driverTextLooksLikeRoadLabel(primary) ||
        _textLooksLikeRoadContext(primary, step);
    final secondaryIsRoadLabel = driverTextLooksLikeRoadLabel(secondary);

    // Both lines are road labels: keep target road dominant.
    if (secondaryIsTarget && !primaryIsTarget && primaryIsRoadLabel) {
      return (
        primary: secondary,
        secondary: _dedupeSecondaryLine(secondary, primary),
        swapped: true,
      );
    }
    final maneuverTarget = driverStepManeuverTargetLabel(step);
    if (maneuverTarget != null &&
        _labelsReferToSameRoad(primary, maneuverTarget) &&
        !secondaryIsTarget) {
      return (
        primary: primary,
        secondary: _dedupeSecondaryLine(primary, secondary),
        swapped: false,
      );
    }
    if (primaryIsTarget && !secondaryIsTarget) {
      return (
        primary: primary,
        secondary: _dedupeSecondaryLine(primary, secondary),
        swapped: false,
      );
    }
    if (primaryIsRoadLabel &&
        secondaryIsRoadLabel &&
        secondaryIsTarget &&
        !primaryIsTarget) {
      return (
        primary: secondary,
        secondary: _dedupeSecondaryLine(secondary, primary),
        swapped: true,
      );
    }

    // Legacy Mapbox swap: primary is current road context, secondary is target.
    if (_textLooksLikeRoadContext(primary, step) &&
        !driverTextLooksLikeManeuverAction(secondary)) {
      return (
        primary: secondary,
        secondary: _dedupeSecondaryLine(secondary, primary),
        swapped: true,
      );
    }
    if (driverTextLooksLikeManeuverAction(primary) &&
        !driverTextLooksLikeManeuverAction(secondary) &&
        !_instructionMentionsTarget(primary, secondary)) {
      final target = secondary;
      final context = _currentRoadContextLabel(step, exclude: target);
      return (
        primary: target,
        secondary: _dedupeSecondaryLine(target, context),
        swapped: true,
      );
    }
  }

  final maneuverTarget = driverStepManeuverTargetLabel(step);
  if (maneuverTarget != null &&
      !_labelsReferToSameRoad(primary, maneuverTarget) &&
      driverNavStepIsTurnLike(step)) {
    if (driverTextLooksLikeRoadLabel(primary) ||
        driverTextLooksLikeManeuverAction(primary) ||
        _textLooksLikeRoadContext(primary, step)) {
      final demoted = secondary.isNotEmpty ? secondary : primary;
      if (!_labelsReferToSameRoad(demoted, maneuverTarget)) {
        return (
          primary: maneuverTarget,
          secondary: _dedupeSecondaryLine(maneuverTarget, demoted),
          swapped: true,
        );
      }
    }
  }

  return (
    primary: primary,
    secondary: _dedupeSecondaryLine(primary, secondary),
    swapped: false,
  );
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
  late final String rawPrimary;
  var rawSecondary = '';

  if (bannerPrimary.isNotEmpty) {
    source = NavInstructionSource.banner;
    rawPrimary = bannerPrimary;
    rawSecondary = (banner?.secondaryText ?? '').trim();
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
      rawPrimary = instruction;
      rawSecondary = step.street.trim();
    } else if (shortAction.trim().isNotEmpty) {
      source = NavInstructionSource.fallback;
      rawPrimary = shortAction.trim();
      rawSecondary = step.street.trim();
    } else {
      source = NavInstructionSource.fallback;
      rawPrimary = '';
      rawSecondary = step.street.trim();
    }
  }

  final normalized = normalizeDriverInstructionDisplayLines(
    rawPrimary: rawPrimary,
    rawSecondary: rawSecondary,
    step: step,
  );
  var primaryText = normalized.primary;
  var secondaryText = normalized.secondary;
  final subText = _trimmedOrNull(banner?.subText);

  if (primaryText.isEmpty) {
    final fallbackInstruction = step.instruction.trim();
    final fallbackAction = driverShortNavAction(
      fallbackInstruction,
      step.type,
      step.modifier,
      tr: tr,
    );
    primaryText = fallbackAction.isNotEmpty
        ? fallbackAction
        : _snapshotSecondaryFromStep(step);
    secondaryText = '';
  } else if (secondaryText.isEmpty) {
    final maneuverTarget = driverStepManeuverTargetLabel(step);
    if (maneuverTarget != null &&
        _labelsReferToSameRoad(primaryText, maneuverTarget)) {
      final rawBannerPrimary = (banner?.primaryText ?? '').trim();
      if (rawBannerPrimary.isNotEmpty &&
          !_labelsReferToSameRoad(rawBannerPrimary, primaryText)) {
        secondaryText = _dedupeSecondaryLine(primaryText, rawBannerPrimary);
      }
    }
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

/// Re-apply banner/step display normalization at render time.
NavInstructionSnapshot applyDriverNavInstructionDisplayLines({
  required NavInstructionSnapshot snapshot,
  required DriverNavStep step,
}) {
  final banner = step.banner;
  final bannerPrimary = (banner?.primaryText ?? '').trim();
  late final String rawPrimary;
  late final String rawSecondary;
  if (bannerPrimary.isNotEmpty) {
    rawPrimary = bannerPrimary;
    rawSecondary = (banner?.secondaryText ?? '').trim();
  } else if (step.instruction.trim().isNotEmpty) {
    rawPrimary = step.instruction.trim();
    rawSecondary = step.street.trim();
  } else {
    rawPrimary = snapshot.primaryText.trim();
    rawSecondary = snapshot.secondaryText.trim();
  }

  final normalized = normalizeDriverInstructionDisplayLines(
    rawPrimary: rawPrimary,
    rawSecondary: rawSecondary,
    step: step,
  );
  var primaryText = normalized.primary;
  var secondaryText = normalized.secondary;
  if (primaryText.isEmpty) {
    return snapshot;
  }
  if (secondaryText.isEmpty) {
    final maneuverTarget = driverStepManeuverTargetLabel(step);
    if (maneuverTarget != null &&
        _labelsReferToSameRoad(primaryText, maneuverTarget)) {
      final rawBannerPrimary = bannerPrimary;
      if (rawBannerPrimary.isNotEmpty &&
          !_labelsReferToSameRoad(rawBannerPrimary, primaryText)) {
        secondaryText = _dedupeSecondaryLine(primaryText, rawBannerPrimary);
      }
    }
  }
  if (primaryText == snapshot.primaryText.trim() &&
      secondaryText == snapshot.secondaryText.trim()) {
    return snapshot;
  }
  return NavInstructionSnapshot(
    distanceToManeuverMeters: snapshot.distanceToManeuverMeters,
    primaryText: primaryText,
    secondaryText: secondaryText,
    subText: snapshot.subText,
    maneuverType: snapshot.maneuverType,
    maneuverModifier: snapshot.maneuverModifier,
    roadName: snapshot.roadName,
    exitNumber: snapshot.exitNumber,
    destinationText: snapshot.destinationText,
    roadRef: snapshot.roadRef,
    isHighwayLike: snapshot.isHighwayLike,
    lanes: snapshot.lanes,
    source: snapshot.source,
  );
}
