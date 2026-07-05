class DriverLonLat {
  final double lon;
  final double lat;

  const DriverLonLat(this.lon, this.lat);
}

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

  bool get hasContent => indications.isNotEmpty;
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
  final DriverNavBannerInstruction? banner;
  final String? exitNumber;
  final String? destinationText;
  final String? roadRef;
  final String? drivingSide;
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
    this.exitNumber,
    this.destinationText,
    this.roadRef,
    this.drivingSide,
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

enum NavInstructionSource {
  banner,
  step,
  fallback,
  loading,
  none,
}

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
