import '../driver_navigation_map_config.dart';
import '../driver_navigation_models.dart';
import 'nav_banner_resolver.dart';

/// NAV-SIGNAL-P2B: pure, deterministic lane-guidance resolution.
///
/// Never concatenates intersection lane groups. Never invents lanes.
/// At uncertainty, returns hidden guidance.

enum DriverLaneGuidanceSource { bannerComponent, intersection, none }

enum DriverLaneAvailability { unavailable, usable, preferred, unknown }

enum DriverLaneHiddenReason {
  none,
  featureDisabled,
  noActiveBannerStage,
  noLaneData,
  singleLane,
  noMeaningfulChoice,
  ambiguousIntersections,
  malformedData,
  excessiveLaneCount,
  allUnusable,
  ownershipMismatch,
  routeVersionMismatch,
  policySuppressed,
  destinationReached,
  clearBanners,
  contradictoryData,
}

class DriverResolvedLaneColumn {
  final List<String> directions;
  final String? activeDirection;
  final DriverLaneAvailability availability;
  final int sourceIndex;

  const DriverResolvedLaneColumn({
    required this.directions,
    required this.availability,
    required this.sourceIndex,
    this.activeDirection,
  });
}

class DriverResolvedLaneGuidance {
  final int routeVersion;
  final int traversalStepIndex;
  final int describedManeuverStepIndex;
  final int? bannerIndex;
  final DriverLaneGuidanceSource source;
  final int? sourceIntersectionIndex;
  final List<DriverResolvedLaneColumn> lanes;
  final bool visible;
  final DriverLaneHiddenReason hiddenReason;

  const DriverResolvedLaneGuidance({
    required this.routeVersion,
    required this.traversalStepIndex,
    required this.describedManeuverStepIndex,
    required this.bannerIndex,
    required this.source,
    required this.sourceIntersectionIndex,
    required this.lanes,
    required this.visible,
    required this.hiddenReason,
  });

  static const DriverResolvedLaneGuidance hiddenNone =
      DriverResolvedLaneGuidance(
        routeVersion: 0,
        traversalStepIndex: 0,
        describedManeuverStepIndex: 0,
        bannerIndex: null,
        source: DriverLaneGuidanceSource.none,
        sourceIntersectionIndex: null,
        lanes: <DriverResolvedLaneColumn>[],
        visible: false,
        hiddenReason: DriverLaneHiddenReason.noLaneData,
      );

  int get usableCount => lanes
      .where(
        (l) =>
            l.availability == DriverLaneAvailability.usable ||
            l.availability == DriverLaneAvailability.preferred,
      )
      .length;

  int get preferredCount => lanes
      .where((l) => l.availability == DriverLaneAvailability.preferred)
      .length;

  bool get isMapboxBannerSource =>
      source == DriverLaneGuidanceSource.bannerComponent && bannerIndex != null;
}

class DriverLaneResolveInput {
  final int routeVersion;
  final List<DriverNavStep> routeSteps;
  final DriverActiveBanner? activeBanner;
  final bool featureEnabledForEvaluation;
  final DriverResolvedLaneGuidance? previous;
  final bool destinationReached;
  final bool clearBanners;

  const DriverLaneResolveInput({
    required this.routeVersion,
    required this.routeSteps,
    required this.activeBanner,
    required this.featureEnabledForEvaluation,
    this.previous,
    this.destinationReached = false,
    this.clearBanners = false,
  });
}

const int kDriverLaneMaxVisibleCount = 8;

DriverResolvedLaneGuidance _hidden({
  required int routeVersion,
  required int traversal,
  required int maneuver,
  required DriverLaneHiddenReason reason,
  int? bannerIndex,
  DriverLaneGuidanceSource source = DriverLaneGuidanceSource.none,
  int? intersectionIndex,
  List<DriverResolvedLaneColumn> lanes = const <DriverResolvedLaneColumn>[],
}) {
  return DriverResolvedLaneGuidance(
    routeVersion: routeVersion,
    traversalStepIndex: traversal,
    describedManeuverStepIndex: maneuver,
    bannerIndex: bannerIndex,
    source: source,
    sourceIntersectionIndex: intersectionIndex,
    lanes: lanes,
    visible: false,
    hiddenReason: reason,
  );
}

bool _identityMatches(
  DriverResolvedLaneGuidance previous,
  DriverActiveBanner banner,
  int routeVersion,
) {
  if (previous.routeVersion != routeVersion) return false;
  if (previous.traversalStepIndex != banner.traversalStepIndex) return false;
  if (previous.describedManeuverStepIndex != banner.maneuverStepIndex) {
    return false;
  }
  if (previous.source == DriverLaneGuidanceSource.bannerComponent) {
    return previous.bannerIndex == banner.bannerIndex;
  }
  if (previous.source == DriverLaneGuidanceSource.intersection) {
    return previous.sourceIntersectionIndex != null;
  }
  return false;
}

List<String> _normalizeDirections(List<String> raw) {
  final out = <String>[];
  for (final item in raw) {
    final t = item.trim().toLowerCase();
    if (t.isNotEmpty) out.add(t);
  }
  return out;
}

String _directionsKey(List<String> directions) =>
    _normalizeDirections(directions).join('|');

DriverLaneAvailability _intersectionAvailability({
  required bool? valid,
  required bool? active,
}) {
  if (valid == false && active == true) {
    // Contradiction handled by caller.
    return DriverLaneAvailability.unknown;
  }
  if (valid == false) return DriverLaneAvailability.unavailable;
  if (valid == true && active == true) {
    return DriverLaneAvailability.preferred;
  }
  if (valid == true) return DriverLaneAvailability.usable;
  // Missing valid → unknown (never preferred without proven usable).
  return DriverLaneAvailability.unknown;
}

/// Banner-component `active` proves usable-for-maneuver, not preference.
DriverLaneAvailability _bannerAvailability({required bool? active}) {
  if (active == true) return DriverLaneAvailability.usable;
  if (active == false) return DriverLaneAvailability.unavailable;
  return DriverLaneAvailability.unknown;
}

bool _hasMeaningfulChoice(List<DriverResolvedLaneColumn> lanes) {
  if (lanes.length < 2) return false;
  final keys = lanes.map((l) => _directionsKey(l.directions)).toSet();
  if (keys.length >= 2) return true;
  final statuses = lanes.map((l) => l.availability).toSet();
  if (statuses.length >= 2) return true;
  final hasUsable = lanes.any(
    (l) =>
        l.availability == DriverLaneAvailability.usable ||
        l.availability == DriverLaneAvailability.preferred,
  );
  final hasUnavailable = lanes.any(
    (l) => l.availability == DriverLaneAvailability.unavailable,
  );
  return hasUsable && hasUnavailable;
}

DriverLaneHiddenReason? _visibilityFailure(
  List<DriverResolvedLaneColumn> lanes,
) {
  if (lanes.isEmpty) return DriverLaneHiddenReason.noLaneData;
  if (lanes.length < 2) return DriverLaneHiddenReason.singleLane;
  if (lanes.length > kDriverLaneMaxVisibleCount) {
    return DriverLaneHiddenReason.excessiveLaneCount;
  }
  final allUnknown = lanes.every(
    (l) => l.availability == DriverLaneAvailability.unknown,
  );
  if (allUnknown) return DriverLaneHiddenReason.allUnusable;
  final allUnavailable = lanes.every(
    (l) => l.availability == DriverLaneAvailability.unavailable,
  );
  if (allUnavailable) return DriverLaneHiddenReason.allUnusable;
  final allEmptyDirections = lanes.every((l) => l.directions.isEmpty);
  if (allEmptyDirections) return DriverLaneHiddenReason.malformedData;
  final usableOrPreferred = lanes.any(
    (l) =>
        l.availability == DriverLaneAvailability.usable ||
        l.availability == DriverLaneAvailability.preferred,
  );
  if (!usableOrPreferred) return DriverLaneHiddenReason.allUnusable;
  if (!_hasMeaningfulChoice(lanes)) {
    return DriverLaneHiddenReason.noMeaningfulChoice;
  }
  return null;
}

List<DriverResolvedLaneColumn>? _columnsFromBannerView(
  DriverNavBannerView view,
) {
  final columns = <DriverResolvedLaneColumn>[];
  for (var i = 0; i < view.components.length; i++) {
    final component = view.components[i];
    final type = (component.type ?? '').trim().toLowerCase();
    if (type != 'lane') continue;
    final directions = _normalizeDirections(component.directions);
    var activeDirection = (component.activeDirection ?? '')
        .trim()
        .toLowerCase();
    if (activeDirection.isNotEmpty && !directions.contains(activeDirection)) {
      activeDirection = '';
    }
    columns.add(
      DriverResolvedLaneColumn(
        directions: directions,
        activeDirection: activeDirection.isEmpty ? null : activeDirection,
        availability: _bannerAvailability(active: component.active),
        sourceIndex: i,
      ),
    );
  }
  if (columns.isEmpty) return null;
  return columns;
}

List<DriverResolvedLaneColumn>? _bannerLaneColumns({
  required DriverNavStep traversalStep,
  required int bannerIndex,
}) {
  DriverNavBannerStage? stage;
  for (final candidate in traversalStep.bannerInstructions) {
    if (candidate.sourceIndex == bannerIndex) {
      stage = candidate;
      break;
    }
  }
  if (stage == null) return null;

  // Deterministic view priority: sub → primary → secondary. Never concat.
  for (final view in <DriverNavBannerView?>[
    stage.sub,
    stage.primary,
    stage.secondary,
  ]) {
    if (view == null) continue;
    final columns = _columnsFromBannerView(view);
    if (columns != null) return columns;
  }
  return null;
}

List<DriverResolvedLaneColumn>? _intersectionLaneColumns(
  DriverNavIntersection intersection,
) {
  if (!intersection.hasLanes) return null;
  final columns = <DriverResolvedLaneColumn>[];
  var contradictory = false;
  for (var i = 0; i < intersection.lanes.length; i++) {
    final lane = intersection.lanes[i];
    if (lane.valid == false && lane.active == true) {
      contradictory = true;
      break;
    }
    final directions = _normalizeDirections(lane.indications);
    var validIndication = (lane.validIndication ?? '').trim().toLowerCase();
    if (validIndication.isNotEmpty && !directions.contains(validIndication)) {
      validIndication = '';
    }
    columns.add(
      DriverResolvedLaneColumn(
        directions: directions,
        activeDirection: validIndication.isEmpty ? null : validIndication,
        availability: _intersectionAvailability(
          valid: lane.valid,
          active: lane.active,
        ),
        sourceIndex: i,
      ),
    );
  }
  if (contradictory) return null;
  if (columns.isEmpty) return null;
  return columns;
}

/// Map resolved columns to legacy snapshot/widget lane rows (display boundary).
List<DriverNavLaneGuidance> mapResolvedLanesForDisplay(
  DriverResolvedLaneGuidance guidance,
) {
  if (!guidance.visible) return const <DriverNavLaneGuidance>[];
  return <DriverNavLaneGuidance>[
    for (final column in guidance.lanes)
      DriverNavLaneGuidance(
        indications: column.directions,
        valid: switch (column.availability) {
          DriverLaneAvailability.unavailable => false,
          DriverLaneAvailability.usable => true,
          DriverLaneAvailability.preferred => true,
          DriverLaneAvailability.unknown => null,
        },
        active: column.availability == DriverLaneAvailability.preferred
            ? true
            : null,
        validIndication: column.activeDirection,
      ),
  ];
}

/// Pure deterministic lane resolver.
DriverResolvedLaneGuidance resolveDriverLaneGuidance(
  DriverLaneResolveInput input,
) {
  if (input.destinationReached) {
    return _hidden(
      routeVersion: input.routeVersion,
      traversal: 0,
      maneuver: 0,
      reason: DriverLaneHiddenReason.destinationReached,
    );
  }
  if (input.clearBanners || input.routeSteps.isEmpty) {
    return _hidden(
      routeVersion: input.routeVersion,
      traversal: 0,
      maneuver: 0,
      reason: DriverLaneHiddenReason.clearBanners,
    );
  }

  final banner = input.activeBanner;
  if (banner == null) {
    return _hidden(
      routeVersion: input.routeVersion,
      traversal: 0,
      maneuver: 0,
      reason: DriverLaneHiddenReason.noLaneData,
    );
  }

  final traversal = banner.traversalStepIndex;
  final maneuver = banner.maneuverStepIndex;
  if (traversal < 0 ||
      traversal >= input.routeSteps.length ||
      maneuver < 0 ||
      maneuver >= input.routeSteps.length) {
    return _hidden(
      routeVersion: input.routeVersion,
      traversal: traversal.clamp(0, 0),
      maneuver: maneuver.clamp(0, 0),
      reason: DriverLaneHiddenReason.ownershipMismatch,
      bannerIndex: banner.bannerIndex,
    );
  }

  if (banner.routeVersion != input.routeVersion) {
    return _hidden(
      routeVersion: input.routeVersion,
      traversal: traversal,
      maneuver: maneuver,
      reason: DriverLaneHiddenReason.routeVersionMismatch,
      bannerIndex: banner.bannerIndex,
    );
  }

  if (!input.featureEnabledForEvaluation) {
    // Still allow previous visible identity preservation checks? No — feature
    // off always hides for live evaluation. Tests inject true explicitly.
    return _hidden(
      routeVersion: input.routeVersion,
      traversal: traversal,
      maneuver: maneuver,
      reason: DriverLaneHiddenReason.featureDisabled,
      bannerIndex: banner.bannerIndex,
    );
  }

  final traversalStep = input.routeSteps[traversal];

  // 1) Active Mapbox banner-stage lane components.
  if (banner.isMapboxStage && banner.bannerIndex != null) {
    final columns = _bannerLaneColumns(
      traversalStep: traversalStep,
      bannerIndex: banner.bannerIndex!,
    );
    if (columns != null) {
      final failure = _visibilityFailure(columns);
      if (failure == null) {
        return DriverResolvedLaneGuidance(
          routeVersion: input.routeVersion,
          traversalStepIndex: traversal,
          describedManeuverStepIndex: maneuver,
          bannerIndex: banner.bannerIndex,
          source: DriverLaneGuidanceSource.bannerComponent,
          sourceIntersectionIndex: null,
          lanes: columns,
          visible: true,
          hiddenReason: DriverLaneHiddenReason.none,
        );
      }
      return _hidden(
        routeVersion: input.routeVersion,
        traversal: traversal,
        maneuver: maneuver,
        reason: failure,
        bannerIndex: banner.bannerIndex,
        source: DriverLaneGuidanceSource.bannerComponent,
        lanes: columns,
      );
    }
  }

  // 2) Conservative intersection fallback: exactly one non-empty group.
  final groups = traversalStep.intersections
      .where((i) => i.hasLanes)
      .toList(growable: false);
  if (groups.length >= 2) {
    return _hidden(
      routeVersion: input.routeVersion,
      traversal: traversal,
      maneuver: maneuver,
      reason: DriverLaneHiddenReason.ambiguousIntersections,
      bannerIndex: banner.bannerIndex,
    );
  }
  if (groups.length == 1) {
    final columns = _intersectionLaneColumns(groups.first);
    if (columns == null) {
      return _hidden(
        routeVersion: input.routeVersion,
        traversal: traversal,
        maneuver: maneuver,
        reason: DriverLaneHiddenReason.contradictoryData,
        bannerIndex: banner.bannerIndex,
        source: DriverLaneGuidanceSource.intersection,
        intersectionIndex: groups.first.sourceIndex,
      );
    }
    final failure = _visibilityFailure(columns);
    if (failure == null) {
      return DriverResolvedLaneGuidance(
        routeVersion: input.routeVersion,
        traversalStepIndex: traversal,
        describedManeuverStepIndex: maneuver,
        bannerIndex: banner.bannerIndex,
        source: DriverLaneGuidanceSource.intersection,
        sourceIntersectionIndex: groups.first.sourceIndex,
        lanes: columns,
        visible: true,
        hiddenReason: DriverLaneHiddenReason.none,
      );
    }
    return _hidden(
      routeVersion: input.routeVersion,
      traversal: traversal,
      maneuver: maneuver,
      reason: failure,
      bannerIndex: banner.bannerIndex,
      source: DriverLaneGuidanceSource.intersection,
      intersectionIndex: groups.first.sourceIndex,
      lanes: columns,
    );
  }

  // No banner stage lanes and no single intersection group.
  if (!banner.isMapboxStage) {
    return _hidden(
      routeVersion: input.routeVersion,
      traversal: traversal,
      maneuver: maneuver,
      reason: DriverLaneHiddenReason.noActiveBannerStage,
      bannerIndex: banner.bannerIndex,
    );
  }

  // Preserve previous visible guidance only when full identity still matches.
  final previous = input.previous;
  if (previous != null &&
      previous.visible &&
      _identityMatches(previous, banner, input.routeVersion)) {
    return previous;
  }

  return _hidden(
    routeVersion: input.routeVersion,
    traversal: traversal,
    maneuver: maneuver,
    reason: DriverLaneHiddenReason.noLaneData,
    bannerIndex: banner.bannerIndex,
  );
}

String formatNavLaneResolveDiag(
  DriverResolvedLaneGuidance guidance, {
  bool? featureEnabled,
  bool? policyAllowed,
  int? displayCount,
}) {
  final bannerPart = guidance.bannerIndex == null
      ? 'bannerIndex=none'
      : 'bannerIndex=${guidance.bannerIndex}';
  final sourcePart = switch (guidance.source) {
    DriverLaneGuidanceSource.bannerComponent => 'banner_component',
    DriverLaneGuidanceSource.intersection => 'intersection',
    DriverLaneGuidanceSource.none => 'none',
  };
  final intersectionPart = guidance.sourceIntersectionIndex == null
      ? 'intersectionIndex=none'
      : 'intersectionIndex=${guidance.sourceIntersectionIndex}';
  final feature = featureEnabled ?? driverNavLaneGuidanceFeatureEnabled;
  final policyPart = policyAllowed == null
      ? 'policyAllowed=n/a'
      : 'policyAllowed=$policyAllowed';
  final displayPart = displayCount == null
      ? 'displayCount=n/a'
      : 'displayCount=$displayCount';
  return '[NAV_LANE_RESOLVE] '
      'routeVersion=${guidance.routeVersion} '
      'traversalStep=${guidance.traversalStepIndex} '
      'maneuverStep=${guidance.describedManeuverStepIndex} '
      '$bannerPart '
      'source=$sourcePart '
      '$intersectionPart '
      'laneCount=${guidance.lanes.length} '
      'resolvedCount=${guidance.lanes.length} '
      'usableCount=${guidance.usableCount} '
      'preferredCount=${guidance.preferredCount} '
      'visible=${guidance.visible} '
      'featureEnabled=$feature '
      '$policyPart '
      '$displayPart '
      'reason=${_reasonToken(guidance.hiddenReason)}';
}

String _reasonToken(DriverLaneHiddenReason reason) {
  switch (reason) {
    case DriverLaneHiddenReason.none:
      return 'none';
    case DriverLaneHiddenReason.featureDisabled:
      return 'feature_disabled';
    case DriverLaneHiddenReason.noActiveBannerStage:
      return 'no_active_banner_stage';
    case DriverLaneHiddenReason.noLaneData:
      return 'no_lane_data';
    case DriverLaneHiddenReason.singleLane:
      return 'single_lane';
    case DriverLaneHiddenReason.noMeaningfulChoice:
      return 'no_meaningful_choice';
    case DriverLaneHiddenReason.ambiguousIntersections:
      return 'ambiguous_intersections';
    case DriverLaneHiddenReason.malformedData:
      return 'malformed_data';
    case DriverLaneHiddenReason.excessiveLaneCount:
      return 'excessive_lane_count';
    case DriverLaneHiddenReason.allUnusable:
      return 'all_unusable';
    case DriverLaneHiddenReason.ownershipMismatch:
      return 'ownership_mismatch';
    case DriverLaneHiddenReason.routeVersionMismatch:
      return 'route_version_mismatch';
    case DriverLaneHiddenReason.policySuppressed:
      return 'policy_suppressed';
    case DriverLaneHiddenReason.destinationReached:
      return 'destination_reached';
    case DriverLaneHiddenReason.clearBanners:
      return 'clear_banners';
    case DriverLaneHiddenReason.contradictoryData:
      return 'contradictory_data';
  }
}
