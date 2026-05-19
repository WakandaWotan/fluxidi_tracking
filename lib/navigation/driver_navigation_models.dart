class DriverLonLat {
  final double lon;
  final double lat;

  const DriverLonLat(this.lon, this.lat);
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
