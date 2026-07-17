import '../driver_navigation_formatters.dart';
import '../driver_navigation_models.dart';

/// NAV-SIGNAL-P1B: Mapbox banner ownership + trusted along-route stage activation.
///
/// Traversal step owns `bannerInstructions`. Described maneuver step owns
/// type/modifier/exit/icon. Activation uses remaining along-route meters to
/// [DriverBannerOwnership.distanceTargetStepIndex] only — never straight-line GPS.

enum NavBannerResolveTransition {
  none,
  stageAdvance,
  stepChange,
  routeChange,
  fallback,
}

enum NavBannerResolveSource { mapboxBanner, maneuverInstruction, generic }

/// Authoritative ownership for one Fluxidi upcoming-maneuver index.
class DriverBannerOwnership {
  final int traversalStepIndex;
  final int describedManeuverStepIndex;
  final int distanceTargetStepIndex;
  final bool isDepartureSpecialCase;
  final bool isFinalArrival;

  const DriverBannerOwnership({
    required this.traversalStepIndex,
    required this.describedManeuverStepIndex,
    required this.distanceTargetStepIndex,
    required this.isDepartureSpecialCase,
    required this.isFinalArrival,
  });
}

class DriverActiveBanner {
  final int traversalStepIndex;
  final int maneuverStepIndex;
  final int distanceTargetStepIndex;
  final bool isDepartureSpecialCase;
  final bool isFinalArrival;

  /// Original `bannerInstructions` index, or null when using fallback text.
  final int? bannerIndex;
  final int routeVersion;
  final double? distanceAlongGeometry;
  final String primaryText;
  final String secondaryText;
  final String? subText;
  final String maneuverType;
  final String maneuverModifier;
  final String roadName;
  final String? exitNumber;
  final String? destinationText;
  final String? roadRef;
  final bool isHighwayLike;
  final List<DriverNavLaneGuidance> lanes;
  final NavBannerResolveTransition transition;
  final NavBannerResolveSource source;
  final int bannerCount;
  final bool trustedProgress;

  const DriverActiveBanner({
    required this.traversalStepIndex,
    required this.maneuverStepIndex,
    required this.distanceTargetStepIndex,
    required this.isDepartureSpecialCase,
    required this.isFinalArrival,
    required this.bannerIndex,
    required this.routeVersion,
    required this.distanceAlongGeometry,
    required this.primaryText,
    required this.secondaryText,
    required this.maneuverType,
    required this.maneuverModifier,
    required this.roadName,
    required this.isHighwayLike,
    required this.lanes,
    required this.transition,
    required this.source,
    required this.bannerCount,
    required this.trustedProgress,
    this.subText,
    this.exitNumber,
    this.destinationText,
    this.roadRef,
  });

  bool get hasInstruction => primaryText.trim().isNotEmpty;

  bool get isMapboxStage =>
      source == NavBannerResolveSource.mapboxBanner && bannerIndex != null;
}

class DriverBannerResolveInput {
  final List<DriverNavStep> routeSteps;

  /// Fluxidi upcoming-maneuver index (`nextStepIndex`).
  final int upcomingManeuverStepIndex;

  /// Trusted remaining along-route meters to [DriverBannerOwnership.distanceTargetStepIndex].
  /// Null when matched route progress is unavailable — never use straight-line GPS.
  final double? bannerRemainingAlongRouteM;

  final int routeVersion;
  final DriverActiveBanner? previous;
  final bool destinationReached;
  final bool clearBanners;
  final DriverNavTranslate tr;

  const DriverBannerResolveInput({
    required this.routeSteps,
    required this.upcomingManeuverStepIndex,
    required this.bannerRemainingAlongRouteM,
    required this.routeVersion,
    required this.tr,
    this.previous,
    this.destinationReached = false,
    this.clearBanners = false,
  });
}

class _NormalizedBannerStage {
  final DriverNavBannerStage stage;
  final int stageRank;

  const _NormalizedBannerStage({required this.stage, required this.stageRank});
}

/// Pure ownership resolver — single source of truth for index mapping.
DriverBannerOwnership resolveDriverBannerOwnership({
  required int upcomingManeuverStepIndex,
  required int routeStepCount,
}) {
  if (routeStepCount <= 0) {
    return const DriverBannerOwnership(
      traversalStepIndex: 0,
      describedManeuverStepIndex: 0,
      distanceTargetStepIndex: 0,
      isDepartureSpecialCase: false,
      isFinalArrival: true,
    );
  }

  if (routeStepCount == 1) {
    return const DriverBannerOwnership(
      traversalStepIndex: 0,
      describedManeuverStepIndex: 0,
      distanceTargetStepIndex: 0,
      isDepartureSpecialCase: false,
      isFinalArrival: true,
    );
  }

  final upcoming = upcomingManeuverStepIndex.clamp(0, routeStepCount - 1);

  // A: departure — Fluxidi still on step 0, banners on 0 describe maneuver 1.
  if (upcoming == 0) {
    return const DriverBannerOwnership(
      traversalStepIndex: 0,
      describedManeuverStepIndex: 1,
      distanceTargetStepIndex: 1,
      isDepartureSpecialCase: true,
      isFinalArrival: false,
    );
  }

  // B / D: normal travel and final arrive (upcoming >= 1).
  final traversal = upcoming - 1;
  final described = upcoming;
  return DriverBannerOwnership(
    traversalStepIndex: traversal,
    describedManeuverStepIndex: described,
    distanceTargetStepIndex: described,
    isDepartureSpecialCase: false,
    isFinalArrival: described >= routeStepCount - 1,
  );
}

/// Trusted along-route remaining meters to the ownership distance target.
double? computeBannerRemainingAlongRouteM({
  required List<DriverNavStep> routeSteps,
  required DriverBannerOwnership ownership,
  required double? trustedRouteProgressM,
}) {
  if (trustedRouteProgressM == null || !trustedRouteProgressM.isFinite) {
    return null;
  }
  if (routeSteps.isEmpty) return null;
  final targetIndex = ownership.distanceTargetStepIndex.clamp(
    0,
    routeSteps.length - 1,
  );
  final targetAlong = routeSteps[targetIndex].distanceAlongRouteM;
  if (!targetAlong.isFinite) return null;
  return (targetAlong - trustedRouteProgressM)
      .clamp(0.0, double.infinity)
      .toDouble();
}

List<_NormalizedBannerStage> _normalizeBannerStagesForActivation(
  List<DriverNavBannerStage> stages,
) {
  if (stages.isEmpty) return const <_NormalizedBannerStage>[];
  final usable = <DriverNavBannerStage>[];
  for (final stage in stages) {
    final d = stage.distanceAlongGeometry;
    if (!d.isFinite || d < 0 || d.isInfinite) continue;
    if (!stage.hasUsablePrimary) continue;
    usable.add(stage);
  }
  if (usable.isEmpty) return const <_NormalizedBannerStage>[];
  final sorted = List<DriverNavBannerStage>.from(usable)
    ..sort((a, b) {
      final byDistance = b.distanceAlongGeometry.compareTo(
        a.distanceAlongGeometry,
      );
      if (byDistance != 0) return byDistance;
      return a.sourceIndex.compareTo(b.sourceIndex);
    });
  return <_NormalizedBannerStage>[
    for (var i = 0; i < sorted.length; i++)
      _NormalizedBannerStage(stage: sorted[i], stageRank: i),
  ];
}

int? _previousMapboxStageRank({
  required DriverActiveBanner? previous,
  required int routeVersion,
  required DriverBannerOwnership ownership,
  required List<_NormalizedBannerStage> normalized,
}) {
  if (previous == null || !previous.isMapboxStage) return null;
  if (previous.routeVersion != routeVersion) return null;
  if (previous.traversalStepIndex != ownership.traversalStepIndex) return null;
  if (previous.maneuverStepIndex != ownership.describedManeuverStepIndex) {
    return null;
  }
  final prevIndex = previous.bannerIndex;
  if (prevIndex == null) return null;
  for (final item in normalized) {
    if (item.stage.sourceIndex == prevIndex) return item.stageRank;
  }
  return null;
}

bool _previousOwnershipMatches(
  DriverActiveBanner previous,
  DriverBannerOwnership ownership,
  int routeVersion,
) {
  return previous.routeVersion == routeVersion &&
      previous.traversalStepIndex == ownership.traversalStepIndex &&
      previous.maneuverStepIndex == ownership.describedManeuverStepIndex;
}

String _genericFollowRoute(DriverNavTranslate tr) {
  return tr(
    nl: 'Volg de route',
    en: 'Follow the route',
    fr: 'Suivez l’itinéraire',
    es: 'Sigue la ruta',
  );
}

String _primaryFromManeuverStep(
  DriverNavStep maneuverStep,
  DriverNavTranslate tr,
) {
  final instruction = maneuverStep.instruction.trim();
  if (instruction.isNotEmpty) return instruction;
  final shortAction = driverShortNavAction(
    instruction,
    maneuverStep.type,
    maneuverStep.modifier,
    tr: tr,
  ).trim();
  if (shortAction.isNotEmpty) return shortAction;
  final street = maneuverStep.street.trim();
  if (street.isNotEmpty) return street;
  final ref = (maneuverStep.roadRef ?? '').trim();
  if (ref.isNotEmpty) return ref;
  final destination = (maneuverStep.destinationText ?? '').trim();
  if (destination.isNotEmpty) return destination;
  return _genericFollowRoute(tr);
}

DriverActiveBanner _fallbackBanner({
  required DriverBannerOwnership ownership,
  required DriverNavStep maneuverStep,
  required int routeVersion,
  required int bannerCount,
  required NavBannerResolveTransition transition,
  required DriverNavTranslate tr,
  required bool trustedProgress,
}) {
  final primary = _primaryFromManeuverStep(maneuverStep, tr);
  final secondary = maneuverStep.street.trim();
  final source = maneuverStep.instruction.trim().isNotEmpty
      ? NavBannerResolveSource.maneuverInstruction
      : NavBannerResolveSource.generic;
  return DriverActiveBanner(
    traversalStepIndex: ownership.traversalStepIndex,
    maneuverStepIndex: ownership.describedManeuverStepIndex,
    distanceTargetStepIndex: ownership.distanceTargetStepIndex,
    isDepartureSpecialCase: ownership.isDepartureSpecialCase,
    isFinalArrival:
        ownership.isFinalArrival || driverNavTypeIsArrival(maneuverStep.type),
    bannerIndex: null,
    routeVersion: routeVersion,
    distanceAlongGeometry: null,
    primaryText: primary,
    secondaryText: secondary == primary ? '' : secondary,
    subText: null,
    maneuverType: maneuverStep.type,
    maneuverModifier: maneuverStep.modifier,
    roadName: maneuverStep.street,
    exitNumber: (maneuverStep.exitNumber ?? '').trim().isEmpty
        ? null
        : maneuverStep.exitNumber!.trim(),
    destinationText: (maneuverStep.destinationText ?? '').trim().isEmpty
        ? null
        : maneuverStep.destinationText!.trim(),
    roadRef: (maneuverStep.roadRef ?? '').trim().isEmpty
        ? null
        : maneuverStep.roadRef!.trim(),
    isHighwayLike: isDriverHighwayLikeStep(maneuverStep),
    // NAV-SIGNAL-P2B: lane presentation is owned by nav_lane_resolver.
    lanes: const <DriverNavLaneGuidance>[],
    transition: transition,
    source: source,
    bannerCount: bannerCount,
    trustedProgress: trustedProgress,
  );
}

DriverActiveBanner _emptyBanner({
  required int routeVersion,
  required NavBannerResolveTransition transition,
}) {
  return DriverActiveBanner(
    traversalStepIndex: 0,
    maneuverStepIndex: 0,
    distanceTargetStepIndex: 0,
    isDepartureSpecialCase: false,
    isFinalArrival: true,
    bannerIndex: null,
    routeVersion: routeVersion,
    distanceAlongGeometry: null,
    primaryText: '',
    secondaryText: '',
    maneuverType: '',
    maneuverModifier: '',
    roadName: '',
    isHighwayLike: false,
    lanes: const <DriverNavLaneGuidance>[],
    transition: transition,
    source: NavBannerResolveSource.generic,
    bannerCount: 0,
    trustedProgress: false,
  );
}

/// Pure deterministic banner resolver.
DriverActiveBanner resolveDriverActiveBanner(DriverBannerResolveInput input) {
  final steps = input.routeSteps;
  if (steps.isEmpty || input.clearBanners || input.destinationReached) {
    return _emptyBanner(
      routeVersion: input.routeVersion,
      transition: input.destinationReached || input.clearBanners
          ? NavBannerResolveTransition.routeChange
          : NavBannerResolveTransition.none,
    );
  }

  final ownership = resolveDriverBannerOwnership(
    upcomingManeuverStepIndex: input.upcomingManeuverStepIndex,
    routeStepCount: steps.length,
  );
  final traversalStep = steps[ownership.traversalStepIndex];
  final maneuverStep = steps[ownership.describedManeuverStepIndex];
  final stages = traversalStep.bannerInstructions;
  final remainingRaw = input.bannerRemainingAlongRouteM;
  var transition = NavBannerResolveTransition.none;
  final previous = input.previous;
  if (previous != null && previous.routeVersion != input.routeVersion) {
    transition = NavBannerResolveTransition.routeChange;
  } else if (previous != null &&
      (previous.traversalStepIndex != ownership.traversalStepIndex ||
          previous.maneuverStepIndex != ownership.describedManeuverStepIndex)) {
    transition = NavBannerResolveTransition.stepChange;
  }

  // Unknown progress: never activate/advance/regress via approximate distance.
  if (remainingRaw == null || !remainingRaw.isFinite) {
    if (previous != null &&
        previous.isMapboxStage &&
        _previousOwnershipMatches(previous, ownership, input.routeVersion) &&
        transition == NavBannerResolveTransition.none) {
      return DriverActiveBanner(
        traversalStepIndex: previous.traversalStepIndex,
        maneuverStepIndex: previous.maneuverStepIndex,
        distanceTargetStepIndex: previous.distanceTargetStepIndex,
        isDepartureSpecialCase: previous.isDepartureSpecialCase,
        isFinalArrival: previous.isFinalArrival,
        bannerIndex: previous.bannerIndex,
        routeVersion: previous.routeVersion,
        distanceAlongGeometry: previous.distanceAlongGeometry,
        primaryText: previous.primaryText,
        secondaryText: previous.secondaryText,
        subText: previous.subText,
        maneuverType: previous.maneuverType,
        maneuverModifier: previous.maneuverModifier,
        roadName: previous.roadName,
        exitNumber: previous.exitNumber,
        destinationText: previous.destinationText,
        roadRef: previous.roadRef,
        isHighwayLike: previous.isHighwayLike,
        lanes: const <DriverNavLaneGuidance>[],
        transition: NavBannerResolveTransition.none,
        source: NavBannerResolveSource.mapboxBanner,
        bannerCount: previous.bannerCount,
        trustedProgress: false,
      );
    }
    return _fallbackBanner(
      ownership: ownership,
      maneuverStep: maneuverStep,
      routeVersion: input.routeVersion,
      bannerCount: stages.length,
      transition: transition == NavBannerResolveTransition.none
          ? NavBannerResolveTransition.fallback
          : transition,
      tr: input.tr,
      trustedProgress: false,
    );
  }

  final remaining = remainingRaw;
  final normalized = _normalizeBannerStagesForActivation(stages);
  if (normalized.isEmpty) {
    return _fallbackBanner(
      ownership: ownership,
      maneuverStep: maneuverStep,
      routeVersion: input.routeVersion,
      bannerCount: 0,
      transition: transition == NavBannerResolveTransition.none
          ? NavBannerResolveTransition.fallback
          : transition,
      tr: input.tr,
      trustedProgress: true,
    );
  }

  // Eligible only when remaining <= trigger. No pre-threshold Mapbox stage.
  _NormalizedBannerStage? selected;
  for (final item in normalized) {
    if (remaining <= item.stage.distanceAlongGeometry) {
      if (selected == null || item.stageRank > selected.stageRank) {
        selected = item;
      }
    }
  }

  if (selected == null) {
    // Before first threshold: fallback, no Mapbox stage identity.
    return _fallbackBanner(
      ownership: ownership,
      maneuverStep: maneuverStep,
      routeVersion: input.routeVersion,
      bannerCount: stages.length,
      transition: transition == NavBannerResolveTransition.none
          ? NavBannerResolveTransition.fallback
          : transition,
      tr: input.tr,
      trustedProgress: true,
    );
  }

  final previousRank = _previousMapboxStageRank(
    previous: previous,
    routeVersion: input.routeVersion,
    ownership: ownership,
    normalized: normalized,
  );
  if (previousRank != null && selected.stageRank < previousRank) {
    selected = normalized[previousRank];
  } else if (previousRank != null &&
      selected.stageRank > previousRank &&
      transition == NavBannerResolveTransition.none) {
    transition = NavBannerResolveTransition.stageAdvance;
  }

  final stage = selected.stage;
  final primary = (stage.primary?.displayText ?? '').trim();
  if (primary.isEmpty) {
    return _fallbackBanner(
      ownership: ownership,
      maneuverStep: maneuverStep,
      routeVersion: input.routeVersion,
      bannerCount: stages.length,
      transition: NavBannerResolveTransition.fallback,
      tr: input.tr,
      trustedProgress: true,
    );
  }

  final secondary = (stage.secondary?.displayText ?? '').trim();
  final sub = (stage.sub?.displayText ?? '').trim();

  return DriverActiveBanner(
    traversalStepIndex: ownership.traversalStepIndex,
    maneuverStepIndex: ownership.describedManeuverStepIndex,
    distanceTargetStepIndex: ownership.distanceTargetStepIndex,
    isDepartureSpecialCase: ownership.isDepartureSpecialCase,
    isFinalArrival:
        ownership.isFinalArrival || driverNavTypeIsArrival(maneuverStep.type),
    bannerIndex: stage.sourceIndex,
    routeVersion: input.routeVersion,
    distanceAlongGeometry: stage.distanceAlongGeometry,
    primaryText: primary,
    secondaryText: secondary == primary ? '' : secondary,
    subText: sub.isEmpty ? null : sub,
    maneuverType: maneuverStep.type,
    maneuverModifier: maneuverStep.modifier,
    roadName: maneuverStep.street,
    exitNumber: (maneuverStep.exitNumber ?? '').trim().isEmpty
        ? null
        : maneuverStep.exitNumber!.trim(),
    destinationText: (maneuverStep.destinationText ?? '').trim().isEmpty
        ? null
        : maneuverStep.destinationText!.trim(),
    roadRef: (maneuverStep.roadRef ?? '').trim().isEmpty
        ? null
        : maneuverStep.roadRef!.trim(),
    isHighwayLike: isDriverHighwayLikeStep(maneuverStep),
    // NAV-SIGNAL-P2B: lane presentation is owned by nav_lane_resolver.
    lanes: const <DriverNavLaneGuidance>[],
    transition: transition,
    source: NavBannerResolveSource.mapboxBanner,
    bannerCount: stages.length,
    trustedProgress: true,
  );
}

String formatNavBannerResolveDiag({
  required DriverActiveBanner banner,
  required int upcomingIndex,
  required double? remainingAlongRouteM,
}) {
  final remainingPart = remainingAlongRouteM == null
      ? 'remainingAlongRouteM=unknown'
      : 'remainingAlongRouteM=${remainingAlongRouteM.toStringAsFixed(0)}';
  final bannerIndexPart = banner.bannerIndex == null
      ? 'bannerIndex=none'
      : 'bannerIndex=${banner.bannerIndex}';
  return '[NAV_BANNER_RESOLVE] '
      'routeVersion=${banner.routeVersion} '
      'upcomingIndex=$upcomingIndex '
      'traversalStep=${banner.traversalStepIndex} '
      'maneuverStep=${banner.maneuverStepIndex} '
      'distanceTargetStep=${banner.distanceTargetStepIndex} '
      'departureSpecialCase=${banner.isDepartureSpecialCase} '
      'trustedProgress=${banner.trustedProgress} '
      '$remainingPart '
      '$bannerIndexPart '
      'transition=${_transitionToken(banner.transition)} '
      'source=${_sourceToken(banner.source)}';
}

String _transitionToken(NavBannerResolveTransition transition) {
  switch (transition) {
    case NavBannerResolveTransition.none:
      return 'none';
    case NavBannerResolveTransition.stageAdvance:
      return 'stage_advance';
    case NavBannerResolveTransition.stepChange:
      return 'step_change';
    case NavBannerResolveTransition.routeChange:
      return 'route_change';
    case NavBannerResolveTransition.fallback:
      return 'fallback';
  }
}

String _sourceToken(NavBannerResolveSource source) {
  switch (source) {
    case NavBannerResolveSource.mapboxBanner:
      return 'mapbox_banner';
    case NavBannerResolveSource.maneuverInstruction:
      return 'maneuver_instruction';
    case NavBannerResolveSource.generic:
      return 'generic';
  }
}
