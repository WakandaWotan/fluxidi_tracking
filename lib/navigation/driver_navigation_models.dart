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
