import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart' as geo;

import 'driver_navigation_formatters.dart';
import 'driver_navigation_geometry.dart';
import 'driver_navigation_map_config.dart';
import 'driver_navigation_models.dart';
import 'nav_engine/nav_banner_resolver.dart';
import 'nav_engine/nav_instruction_policy.dart';
import 'nav_engine/nav_lane_resolver.dart';
import 'nav_engine/nav_maneuver_owner.dart';
import 'nav_engine/nav_slight_fork_guidance.dart';

const double kDriverNavStepPassStraightLineMeters = 32.0;
const double kDriverNavStepPassRouteBufferMeters = 18.0;

/// NAV-R12-E2: when matched route progress falls this far behind the start
/// of an already-passed step, the forward-only step index is stale
/// (backtracking or a refreshed route) and is re-resolved from scratch.
const double kDriverNavStepBacktrackResetMeters = 40.0;

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

  /// NAV-R12-E2: true when the step index was re-resolved from route
  /// progress instead of only advancing forward.
  final bool reResolved;

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
    this.reResolved = false,
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
  var reResolved = false;

  // NAV-R12-E2: a stale index from a previous (longer) route never survives.
  if (resolvedStepIndex > routeSteps.length - 1 || resolvedStepIndex < 0) {
    resolvedStepIndex = 0;
    reResolved = true;
  }

  // NAV-R12-E2: forward-only advancement goes stale after backtracking or a
  // route refresh. When reliable matched progress is clearly behind the last
  // passed step, re-resolve the index from the start of the route.
  if (progressM != null && resolvedStepIndex > 0) {
    final lastPassed = routeSteps[resolvedStepIndex - 1];
    if (progressM <
        lastPassed.distanceAlongRouteM - kDriverNavStepBacktrackResetMeters) {
      resolvedStepIndex = 0;
      reResolved = true;
    }
  }

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
    reResolved: reResolved,
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
    'hou licht',
    'flauw',
    'keep slight',
    'keep left',
    'keep right',
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

/// Best-effort maneuver target from non-banner step metadata only.
///
/// NAV-SIGNAL-P1B: live ownership must not read `DriverNavStep.banner` (legacy
/// first-stage field may describe a different maneuver than the step index).
String? driverStepManeuverTargetLabel(DriverNavStep step) {
  final fromInstruction = _parseManeuverTargetFromInstruction(step.instruction);
  if (fromInstruction != null && fromInstruction.isNotEmpty) {
    return _augmentTargetLabelWithRef(fromInstruction, step);
  }
  final street = step.street.trim();
  if (street.isNotEmpty && !driverTextLooksLikeManeuverAction(street)) {
    return _augmentTargetLabelWithRef(street, step);
  }
  final ref = (step.roadRef ?? '').trim();
  if (ref.isNotEmpty) return ref;
  final destination = (step.destinationText ?? '').trim();
  if (destination.isNotEmpty) return destination;
  return null;
}

String driverNavManeuverTargetSource(DriverNavStep step) {
  if (_parseManeuverTargetFromInstruction(step.instruction) != null) {
    return 'instruction';
  }
  if (step.street.trim().isNotEmpty) return 'name';
  if ((step.roadRef ?? '').trim().isNotEmpty) return 'ref';
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
  final street = step.street.trim();
  if (street.isNotEmpty && _labelsReferToSameRoad(t, street)) {
    return true;
  }
  final ref = (step.roadRef ?? '').trim();
  if (ref.isNotEmpty && _labelsReferToSameRoad(t, ref)) {
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
({String primary, String secondary, bool swapped})
normalizeDriverInstructionDisplayLines({
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
    // Never demote a maneuver action line — left/right must stay primary.
    if (_textLooksLikeRoadContext(primary, step) &&
        !driverTextLooksLikeManeuverAction(primary) &&
        !driverTextLooksLikeManeuverAction(secondary)) {
      return (
        primary: secondary,
        secondary: _dedupeSecondaryLine(secondary, primary),
        swapped: true,
      );
    }
    // PART B: when primary is already a directional action, keep it as the
    // foreground and treat the street/target as secondary. Do not promote
    // primaryKind=target over a known left/right action.
    if (driverTextLooksLikeManeuverAction(primary) &&
        !driverTextLooksLikeManeuverAction(secondary)) {
      return (
        primary: primary,
        secondary: _dedupeSecondaryLine(primary, secondary),
        swapped: false,
      );
    }
  }

  final maneuverTarget = driverStepManeuverTargetLabel(step);
  // Only promote the target road when primary is NOT already an action.
  if (maneuverTarget != null &&
      !_labelsReferToSameRoad(primary, maneuverTarget) &&
      driverNavStepIsTurnLike(step) &&
      !driverTextLooksLikeManeuverAction(primary)) {
    if (driverTextLooksLikeRoadLabel(primary) ||
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

/// NAV-SIGNAL-P1B: resolve banner ownership + snapshot together.
///
/// [displayDistanceToUpcomingManeuverM] may use approximate GPS distance for
/// UI. [bannerRemainingAlongRouteM] is trusted along-route remaining to the
/// ownership distance target only (null when progress is unavailable).
({
  NavInstructionSnapshot snapshot,
  DriverActiveBanner? activeBanner,
  DriverResolvedLaneGuidance laneGuidance,
  NavVisibleManeuverOwner? maneuverOwner,
  double? bannerRemainingAlongRouteM,
  double displayDistanceToUpcomingManeuverM,
})
buildDriverNavInstructionPresentation({
  required List<DriverNavStep> routeSteps,
  required int nextStepIndex,
  required double posLat,
  required double posLon,
  required DriverRouteSnap? lastRouteSnap,
  required List<DriverLonLat> routeCoords,
  required bool useMatchedVisual,
  required DriverNavTranslate tr,
  int routeVersion = 0,
  DriverActiveBanner? previousActiveBanner,
  DriverResolvedLaneGuidance? previousLaneGuidance,
  // NAV-MANEUVER-OWNER-REBASE-1: the previous owner and a monotonic tick are
  // what let a delayed write be recognised and refused.
  NavVisibleManeuverOwner? previousManeuverOwner,
  int progressEpoch = 0,
  bool navStepsLoading = false,
  bool? laneGuidanceEnabledForEvaluation,
  // NAV-PARKING-2 Commit 1: when bounded destination-proximity arrival is
  // authoritative, the maneuver banner + lane strip are cleared so road
  // guidance toward surrounding public-road segments is no longer presented.
  bool destinationReached = false,
}) {
  if (routeSteps.isEmpty) {
    final empty = navStepsLoading
        ? NavInstructionSnapshot.loading
        : NavInstructionSnapshot.none;
    return (
      snapshot: empty,
      activeBanner: null,
      laneGuidance: DriverResolvedLaneGuidance.hiddenNone,
      maneuverOwner: null,
      bannerRemainingAlongRouteM: null,
      displayDistanceToUpcomingManeuverM: 0.0,
    );
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
    final empty = navStepsLoading
        ? NavInstructionSnapshot.loading
        : NavInstructionSnapshot.none;
    return (
      snapshot: empty,
      activeBanner: null,
      laneGuidance: resolveDriverLaneGuidance(
        DriverLaneResolveInput(
          routeVersion: routeVersion,
          routeSteps: routeSteps,
          activeBanner: null,
          featureEnabledForEvaluation:
              laneGuidanceEnabledForEvaluation ??
              driverNavLaneGuidanceFeatureEnabled,
          previous: previousLaneGuidance,
          clearBanners: true,
          destinationReached: destinationReached,
        ),
      ),
      maneuverOwner: null,
      bannerRemainingAlongRouteM: null,
      displayDistanceToUpcomingManeuverM: 0.0,
    );
  }

  final displayDistanceM = update.distanceMeters ?? 0.0;
  final ownership = resolveDriverBannerOwnership(
    upcomingManeuverStepIndex: update.nextStepIndex,
    routeStepCount: routeSteps.length,
  );
  final posPoint = DriverLonLat(posLon, posLat);
  final snap = lastRouteSnap ?? driverSnapToRouteOn(routeCoords, posPoint);
  final trustedProgressM = (useMatchedVisual && snap != null)
      ? snap.distanceAlongRouteM
      : null;
  final bannerRemainingAlongRouteM = computeBannerRemainingAlongRouteM(
    routeSteps: routeSteps,
    ownership: ownership,
    trustedRouteProgressM: trustedProgressM,
  );

  final active = resolveDriverActiveBanner(
    DriverBannerResolveInput(
      routeSteps: routeSteps,
      upcomingManeuverStepIndex: update.nextStepIndex,
      bannerRemainingAlongRouteM: bannerRemainingAlongRouteM,
      routeVersion: routeVersion,
      previous: previousActiveBanner,
      tr: tr,
      destinationReached: destinationReached,
    ),
  );

  final laneGuidance = resolveDriverLaneGuidance(
    DriverLaneResolveInput(
      routeVersion: routeVersion,
      routeSteps: routeSteps,
      activeBanner: active,
      featureEnabledForEvaluation:
          laneGuidanceEnabledForEvaluation ??
          driverNavLaneGuidanceFeatureEnabled,
      previous: previousLaneGuidance,
      destinationReached: destinationReached,
    ),
  );

  final maneuverStep = routeSteps[active.maneuverStepIndex];
  final rawPrimary = active.primaryText.trim();
  final rawSecondary = active.secondaryText.trim();
  final normalized = normalizeDriverInstructionDisplayLines(
    rawPrimary: rawPrimary,
    rawSecondary: rawSecondary,
    step: maneuverStep,
  );
  var primaryText = normalized.primary;
  var secondaryText = normalized.secondary;
  final subText = _trimmedOrNull(active.subText);
  var maneuverType = active.maneuverType;
  var maneuverModifier = active.maneuverModifier;

  // PART A: synthesize slight left/right when Mapbox omits a usable modifier
  // at a genuine fork. Official Mapbox directions always win.
  final slightFork = resolveSlightForkGuidance(
    step: maneuverStep,
    routeCoords: routeCoords,
  );
  if (slightFork != null) {
    maneuverModifier = slightFork.modifier;
    if (maneuverType.trim().isEmpty ||
        maneuverType.trim().toLowerCase() == 'notification' ||
        maneuverType.trim().toLowerCase() == 'new name' ||
        maneuverType.trim().toLowerCase() == 'continue') {
      maneuverType = 'fork';
    }
    if (!driverTextLooksLikeManeuverAction(primaryText)) {
      final action = slightFork.primaryText(tr);
      final previousPrimary = primaryText;
      primaryText = action;
      if (secondaryText.isEmpty && previousPrimary.isNotEmpty) {
        secondaryText = previousPrimary;
      }
    }
  }

  if (primaryText.isEmpty) {
    primaryText = _primaryFromManeuverStep(maneuverStep, tr);
    secondaryText = '';
  } else if (secondaryText.isEmpty) {
    final maneuverTarget = driverStepManeuverTargetLabel(maneuverStep);
    if (maneuverTarget != null &&
        _labelsReferToSameRoad(primaryText, maneuverTarget)) {
      if (rawPrimary.isNotEmpty &&
          !_labelsReferToSameRoad(rawPrimary, primaryText)) {
        secondaryText = _dedupeSecondaryLine(primaryText, rawPrimary);
      }
    }
  }

  final source = switch (active.source) {
    NavBannerResolveSource.mapboxBanner => NavInstructionSource.banner,
    NavBannerResolveSource.maneuverInstruction => NavInstructionSource.step,
    NavBannerResolveSource.generic => NavInstructionSource.fallback,
  };

  // NAV-MANEUVER-OWNER-REBASE-1: activation runs on trusted along-route
  // remaining when it exists, and on the display distance otherwise. Both are
  // pure distances — vehicle speed reaches neither.
  final owner = resolveNavVisibleManeuverOwner(
    describedStep: maneuverStep,
    describedStepIndex: active.maneuverStepIndex,
    traversalStepIndex: active.traversalStepIndex,
    distanceToManeuverM: bannerRemainingAlongRouteM ?? displayDistanceM,
    routeVersion: routeVersion,
    progressEpoch: progressEpoch,
    previous: previousManeuverOwner,
  );

  final snapshot = NavInstructionSnapshot(
    distanceToManeuverMeters: displayDistanceM,
    primaryText: primaryText,
    secondaryText: secondaryText,
    subText: subText,
    maneuverType: maneuverType,
    maneuverModifier: maneuverModifier,
    roadName: active.roadName,
    exitNumber: active.exitNumber,
    destinationText: active.destinationText,
    roadRef: active.roadRef,
    isHighwayLike: active.isHighwayLike,
    // Snapshot lanes come only from resolved guidance — never flat step.lanes.
    lanes: mapResolvedLanesForDisplay(laneGuidance),
    source: source,
    // Guidance fields travel with the maneuver the owner settled on, so the
    // sign and the wording can never describe different steps.
    drivingSide: maneuverStep.drivingSide,
    bearingBefore: maneuverStep.bearingBefore,
    bearingAfter: maneuverStep.bearingAfter,
    bannerDegrees: navManeuverBannerDegrees(maneuverStep),
    followRouteForced: owner.showFollowRoute,
    arrivalConfirmed: destinationReached,
  );
  return (
    snapshot: snapshot,
    activeBanner: active,
    laneGuidance: laneGuidance,
    maneuverOwner: owner,
    bannerRemainingAlongRouteM: bannerRemainingAlongRouteM,
    displayDistanceToUpcomingManeuverM: displayDistanceM,
  );
}

String _primaryFromManeuverStep(DriverNavStep step, DriverNavTranslate tr) {
  final instruction = step.instruction.trim();
  if (instruction.isNotEmpty) return instruction;
  final fallbackAction = driverShortNavAction(
    instruction,
    step.type,
    step.modifier,
    tr: tr,
  ).trim();
  if (fallbackAction.isNotEmpty) return fallbackAction;
  final fromStep = _snapshotSecondaryFromStep(step);
  if (fromStep.isNotEmpty) return fromStep;
  return tr(
    nl: 'Volg de route',
    en: 'Follow the route',
    fr: 'Suivez l’itinéraire',
    es: 'Sigue la ruta',
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
  int routeVersion = 0,
  DriverActiveBanner? previousActiveBanner,
  bool navStepsLoading = false,
}) {
  return buildDriverNavInstructionPresentation(
    routeSteps: routeSteps,
    nextStepIndex: nextStepIndex,
    posLat: posLat,
    posLon: posLon,
    lastRouteSnap: lastRouteSnap,
    routeCoords: routeCoords,
    useMatchedVisual: useMatchedVisual,
    tr: tr,
    routeVersion: routeVersion,
    previousActiveBanner: previousActiveBanner,
    navStepsLoading: navStepsLoading,
  ).snapshot;
}

/// Re-apply display normalization at render time.
///
/// NAV-SIGNAL-P1B: once a snapshot carries resolved primary/secondary/source/
/// maneuver identity, live display uses those values only. Never re-reads
/// legacy `DriverNavStep.banner`.
NavInstructionSnapshot applyDriverNavInstructionDisplayLines({
  required NavInstructionSnapshot snapshot,
  required DriverNavStep step,
}) {
  final snapshotPrimary = snapshot.primaryText.trim();
  final snapshotSecondary = snapshot.secondaryText.trim();

  late final String rawPrimary;
  late final String rawSecondary;
  if (snapshotPrimary.isNotEmpty || snapshotSecondary.isNotEmpty) {
    rawPrimary = snapshotPrimary;
    rawSecondary = snapshotSecondary;
  } else if (step.instruction.trim().isNotEmpty) {
    // Unresolved / empty snapshot only: non-banner step metadata.
    rawPrimary = step.instruction.trim();
    rawSecondary = step.street.trim();
  } else {
    return snapshot;
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
      if (snapshotPrimary.isNotEmpty &&
          !_labelsReferToSameRoad(snapshotPrimary, primaryText)) {
        secondaryText = _dedupeSecondaryLine(primaryText, snapshotPrimary);
      }
    }
  }
  if (primaryText == snapshotPrimary && secondaryText == snapshotSecondary) {
    return snapshot;
  }
  // Only the display lines change here; maneuver identity, guidance fields and
  // ownership state stay exactly as the owner resolved them.
  return snapshot.copyWith(
    primaryText: primaryText,
    secondaryText: secondaryText,
  );
}

/// True when Mapbox step type/modifier explicitly indicates a U-turn.
bool driverNavManeuverExplicitlyIndicatesUturn(String type, String modifier) {
  final t = type.trim().toLowerCase();
  final m = modifier.trim().toLowerCase();
  if (m.contains('uturn') || m.contains('u-turn')) return true;
  if (t.contains('uturn') || t.contains('u-turn')) return true;
  if (t == 'end of road' &&
      (m.contains('uturn') ||
          m.contains('u-turn') ||
          m.contains('left') ||
          m.contains('right') ||
          m.isEmpty)) {
    return true;
  }
  return false;
}

/// Text-only U-turn / turn-around detection for defensive filtering.
bool driverNavInstructionTextLooksLikeUturn(String text) {
  final lower = text.trim().toLowerCase();
  if (lower.isEmpty) return false;
  const markers = <String>[
    'u-turn',
    'uturn',
    'u turn',
    'turn around',
    'turn-around',
    'keer om',
    'keer terug',
    'omkeren',
    'demi-tour',
    'demi tour',
    'faire demi-tour',
    'giro en u',
    'media vuelta',
  ];
  for (final marker in markers) {
    if (lower.contains(marker)) return true;
  }
  return false;
}

/// NAV-R8 instruction policy filter — deterministic maneuver display safety.
///
/// NAV-SIGNAL-P2B: never rebuilds lane ownership. Preserves already-resolved
/// snapshot lanes only when the instruction is allowed and lane guidance is
/// enabled for evaluation.
NavInstructionSnapshot applyDriverNavInstructionPolicyFilter({
  required NavInstructionSnapshot snapshot,
  required DriverNavInstructionPolicy policy,
  required bool liveRideActive,
  required bool trustRouteSnap,
  required bool trustInstruction,
  required bool offRouteLikely,
  bool routeDeviationLikely = false,
  bool oppositeDirectionLikely = false,
  bool backwardProgressLikely = false,
  bool reroutePending = false,
  bool strongMismatchSuspected = false,
  required bool forwardProgress,
  required bool predictionActive,
  double? routeConfidence,
  double? instructionConfidenceScore,
  double? speedKmh,
  required DriverNavTranslate tr,
  bool? laneGuidanceEnabled,
}) {
  if (!snapshot.hasInstruction) return snapshot;

  final primary = snapshot.primaryText.trim();
  final secondary = snapshot.secondaryText.trim();
  final rawInstruction = primary.isNotEmpty ? primary : secondary;
  final lanesEnabled =
      laneGuidanceEnabled ?? driverNavLaneGuidanceFeatureEnabled;

  final policyOutput = policy.update(
    NavInstructionPolicyInput(
      timestamp: DateTime.now(),
      liveRideActive: liveRideActive,
      rawInstructionText: rawInstruction,
      maneuverType: snapshot.maneuverType,
      maneuverModifier: snapshot.maneuverModifier,
      distanceToManeuverM: snapshot.distanceToManeuverMeters,
      routeConfidence: routeConfidence,
      instructionConfidenceScore: instructionConfidenceScore,
      trustInstruction: trustInstruction,
      trustRouteSnap: trustRouteSnap,
      offRouteLikely: offRouteLikely,
      routeDeviationLikely: routeDeviationLikely,
      oppositeDirectionLikely: oppositeDirectionLikely,
      backwardProgressLikely: backwardProgressLikely,
      reroutePending: reroutePending,
      strongMismatchSuspected: strongMismatchSuspected,
      forwardProgress: forwardProgress,
      predictionActive: predictionActive,
      speedKmh: speedKmh,
    ),
  );

  final displayText = navInstructionPolicyLocalizedText(
    policy: policyOutput,
    originalText: rawInstruction,
    tr: tr,
  );

  if (kDebugMode) {
    debugPrint(
      '[NAV_R8_INSTRUCTION_POLICY] '
      'original=${navInstructionPolicyLogSnippet(rawInstruction)} '
      'displayed=${navInstructionPolicyLogSnippet(displayText)} '
      'reason=${policyOutput.reason}',
    );
  }

  // Preserve resolver-owned lanes only; never rebuild ownership here.
  // Requires master flag + policy showLaneGuidance + non-neutral instruction.
  final preservedLanes =
      policyOutput.showOriginalInstruction &&
          policyOutput.showLaneGuidance &&
          lanesEnabled &&
          snapshot.lanes.isNotEmpty
      ? snapshot.lanes
      : const <DriverNavLaneGuidance>[];

  if (policyOutput.showOriginalInstruction) {
    return snapshot.copyWith(lanes: preservedLanes);
  }

  return snapshot.copyWith(
    primaryText: displayText,
    secondaryText: '',
    maneuverType: policyOutput.isNeutralFallback
        ? 'continue'
        : snapshot.maneuverType,
    maneuverModifier: policyOutput.isNeutralFallback
        ? 'straight'
        : snapshot.maneuverModifier,
    lanes: const <DriverNavLaneGuidance>[],
    // A neutral policy fallback describes no maneuver at all, so the sign layer
    // must not keep showing the maneuver the owner had settled on.
    followRouteForced: policyOutput.isNeutralFallback
        ? true
        : snapshot.followRouteForced,
  );
}

/// NAV-R1 backward-compatible wrapper — delegates to NAV-R8 policy.
///
/// [routeSnappedReliable] maps to R8 [trustRouteSnap].
NavInstructionSnapshot applyDriverNavR1InstructionSafetyFilter({
  required NavInstructionSnapshot snapshot,
  required bool routeSnappedReliable,
  double? routeProgressConfidence,
  bool routeOffRouteLikely = false,
  bool? trustInstruction,
  double? instructionConfidenceScore,
  required DriverNavTranslate tr,
  DriverNavInstructionPolicy? policy,
  bool liveRideActive = true,
  bool forwardProgress = true,
  bool predictionActive = false,
  double? speedKmh,
}) {
  final engine = policy ?? DriverNavInstructionPolicy();
  return applyDriverNavInstructionPolicyFilter(
    snapshot: snapshot,
    policy: engine,
    liveRideActive: liveRideActive,
    trustRouteSnap: routeSnappedReliable,
    trustInstruction: trustInstruction ?? true,
    offRouteLikely: routeOffRouteLikely,
    forwardProgress: forwardProgress,
    predictionActive: predictionActive,
    routeConfidence: routeProgressConfidence,
    instructionConfidenceScore: instructionConfidenceScore,
    speedKmh: speedKmh,
    tr: tr,
  );
}
