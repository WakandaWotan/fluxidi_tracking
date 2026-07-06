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
  });
}
