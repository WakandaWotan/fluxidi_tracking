class DriverLonLat {
  final double lon;
  final double lat;

  const DriverLonLat(this.lon, this.lat);
}

/// Legacy flattened banner texts (first usable stage). Kept for compatibility.
class DriverNavBannerInstruction {
  final String? primaryText;
  final String? secondaryText;
  final String? subText;

  const DriverNavBannerInstruction({
    this.primaryText,
    this.secondaryText,
    this.subText,
  });

  bool get hasContent =>
      (primaryText ?? '').isNotEmpty ||
      (secondaryText ?? '').isNotEmpty ||
      (subText ?? '').isNotEmpty;
}

/// One Mapbox banner component (text / icon / lane), order preserved.
class DriverNavBannerComponent {
  final String? type;
  final String text;
  final String? imageBaseURL;
  final String? abbr;
  final int? abbrPriority;
  final List<String> directions;
  final bool? active;
  final String? activeDirection;

  const DriverNavBannerComponent({
    this.type,
    this.text = '',
    this.imageBaseURL,
    this.abbr,
    this.abbrPriority,
    this.directions = const <String>[],
    this.active,
    this.activeDirection,
  });
}

/// Mapbox primary / secondary / sub view with optional component array.
class DriverNavBannerView {
  final String? text;
  final List<DriverNavBannerComponent> components;

  const DriverNavBannerView({
    this.text,
    this.components = const <DriverNavBannerComponent>[],
  });

  /// Displayable text: explicit text, else non-empty component texts joined.
  String get displayText {
    final direct = (text ?? '').trim();
    if (direct.isNotEmpty) return direct;
    final parts = <String>[];
    for (final component in components) {
      final part = component.text.trim();
      if (part.isNotEmpty) parts.add(part);
    }
    return parts.join(' ').trim();
  }

  bool get hasDisplayText => displayText.isNotEmpty;
}

/// One Mapbox `bannerInstructions[]` stage (authoritative rich representation).
class DriverNavBannerStage {
  /// Original index in the step's `bannerInstructions` array.
  final int sourceIndex;

  /// Mapbox `distanceAlongGeometry` (meters). Compared to remaining step
  /// distance for activation (Navigation SDK convention).
  final double distanceAlongGeometry;

  final DriverNavBannerView? primary;
  final DriverNavBannerView? secondary;
  final DriverNavBannerView? sub;

  const DriverNavBannerStage({
    required this.sourceIndex,
    required this.distanceAlongGeometry,
    this.primary,
    this.secondary,
    this.sub,
  });

  bool get hasUsablePrimary => primary?.hasDisplayText ?? false;

  DriverNavBannerInstruction get asLegacyInstruction =>
      DriverNavBannerInstruction(
        primaryText: primary?.displayText,
        secondaryText: secondary?.displayText,
        subText: sub?.displayText,
      );
}

/// One Mapbox intersection lane (raw source semantics).
class DriverNavLaneGuidance {
  final List<String> indications;
  final bool? valid;
  final bool? active;
  final String? validIndication;

  const DriverNavLaneGuidance({
    this.indications = const <String>[],
    this.valid,
    this.active,
    this.validIndication,
  });

  bool get hasContent =>
      indications.isNotEmpty ||
      valid != null ||
      active != null ||
      (validIndication ?? '').isNotEmpty;
}

/// One Mapbox `step.intersections[]` entry with its own lane group.
///
/// NAV-SIGNAL-P2B: intersection identity is preserved so lanes are never
/// concatenated across intersections.
class DriverNavIntersection {
  /// Original index in the step's `intersections` array.
  final int sourceIndex;
  final List<DriverNavLaneGuidance> lanes;
  final List<double> bearings;
  final List<bool> entry;
  final int? inIndex;
  final int? outIndex;
  final List<String> classes;

  const DriverNavIntersection({
    required this.sourceIndex,
    this.lanes = const <DriverNavLaneGuidance>[],
    this.bearings = const <double>[],
    this.entry = const <bool>[],
    this.inIndex,
    this.outIndex,
    this.classes = const <String>[],
  });

  bool get hasLanes => lanes.isNotEmpty;
}

class DriverNavStep {
  final double lat;
  final double lon;
  final String instruction;
  final String street;
  final String type;
  final String modifier;
  final double distanceAlongRouteM;
  final double? distanceM;
  final int? durationSec;

  /// Legacy: first usable banner stage texts (compatibility).
  final DriverNavBannerInstruction? banner;

  /// Authoritative ordered Mapbox banner stages for this traversal step.
  final List<DriverNavBannerStage> bannerInstructions;

  /// Authoritative ordered intersections for this step (lane groups).
  final List<DriverNavIntersection> intersections;

  final String? exitNumber;
  final String? destinationText;
  final String? roadRef;
  final String? drivingSide;

  /// Deprecated for live lane guidance. Always empty after P2B — use
  /// [intersections] and [DriverResolvedLaneGuidance] instead. Never a
  /// concatenated multi-intersection list.
  @Deprecated('Use intersections + nav_lane_resolver; never concat groups.')
  final List<DriverNavLaneGuidance> lanes;

  const DriverNavStep({
    required this.lat,
    required this.lon,
    required this.instruction,
    required this.street,
    required this.type,
    required this.modifier,
    required this.distanceAlongRouteM,
    this.distanceM,
    this.durationSec,
    this.banner,
    this.bannerInstructions = const <DriverNavBannerStage>[],
    this.intersections = const <DriverNavIntersection>[],
    this.exitNumber,
    this.destinationText,
    this.roadRef,
    this.drivingSide,
    @Deprecated('Use intersections + nav_lane_resolver; never concat groups.')
    this.lanes = const <DriverNavLaneGuidance>[],
  });
}

class DriverRouteSnap {
  final DriverLonLat point;
  final double distanceFromRouteM;
  final double distanceAlongRouteM;
  final int segmentIndex;
  final double segmentT;

  const DriverRouteSnap({
    required this.point,
    required this.distanceFromRouteM,
    required this.distanceAlongRouteM,
    required this.segmentIndex,
    required this.segmentT,
  });
}

enum NavInstructionSource { banner, step, fallback, loading, none }

class NavInstructionSnapshot {
  final double distanceToManeuverMeters;
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
  final NavInstructionSource source;

  const NavInstructionSnapshot({
    required this.distanceToManeuverMeters,
    required this.primaryText,
    required this.secondaryText,
    required this.maneuverType,
    required this.maneuverModifier,
    required this.roadName,
    required this.isHighwayLike,
    required this.lanes,
    required this.source,
    this.subText,
    this.exitNumber,
    this.destinationText,
    this.roadRef,
  });

  static const NavInstructionSnapshot none = NavInstructionSnapshot(
    distanceToManeuverMeters: 0,
    primaryText: '',
    secondaryText: '',
    maneuverType: '',
    maneuverModifier: '',
    roadName: '',
    isHighwayLike: false,
    lanes: <DriverNavLaneGuidance>[],
    source: NavInstructionSource.none,
  );

  static const NavInstructionSnapshot loading = NavInstructionSnapshot(
    distanceToManeuverMeters: 0,
    primaryText: '',
    secondaryText: '',
    maneuverType: '',
    maneuverModifier: '',
    roadName: '',
    isHighwayLike: false,
    lanes: <DriverNavLaneGuidance>[],
    source: NavInstructionSource.loading,
  );

  bool get hasInstruction =>
      source != NavInstructionSource.none &&
      source != NavInstructionSource.loading &&
      primaryText.trim().isNotEmpty;
}
