/// Raw navigation signals fed into [DriverNavEngine].
class NavEngineInput {
  final DateTime timestamp;
  final double rawLatitude;
  final double rawLongitude;
  final double? snappedLatitude;
  final double? snappedLongitude;
  final bool hasReliableSnap;
  final double? rawHeading;
  final double? routeBearing;
  final double? speedKmh;
  final double? accuracyM;
  final bool cameraFollowMode;
  final bool liveRideActive;
  final double? movementBearing;
  final bool offRouteLikely;
  final bool trustBearing;
  final double? routeConfidence;

  // NAV-R12-C: route-deviation signals so bearing selection can demote the
  // route bearing the moment the route stops matching real movement.
  final bool routeDeviationLikely;
  final bool oppositeDirectionLikely;
  final bool backwardProgressLikely;
  final double? headingDeltaDeg;
  final bool forwardProgress;

  const NavEngineInput({
    required this.timestamp,
    required this.rawLatitude,
    required this.rawLongitude,
    this.snappedLatitude,
    this.snappedLongitude,
    this.hasReliableSnap = false,
    this.rawHeading,
    this.routeBearing,
    this.speedKmh,
    this.accuracyM,
    this.cameraFollowMode = false,
    this.liveRideActive = false,
    this.movementBearing,
    this.offRouteLikely = false,
    this.trustBearing = true,
    this.routeConfidence,
    this.routeDeviationLikely = false,
    this.oppositeDirectionLikely = false,
    this.backwardProgressLikely = false,
    this.headingDeltaDeg,
    this.forwardProgress = true,
  });
}
