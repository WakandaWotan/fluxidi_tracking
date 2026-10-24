/// Smoothed navigation output consumed by marker/camera UI.
class NavEngineOutput {
  final DateTime timestamp;
  final double displayLatitude;
  final double displayLongitude;
  final double bearing;
  final String markerSource;
  final bool shouldAnimateMarker;
  final bool cameraFollowMode;
  final String cameraReason;
  final double? speedKmh;
  final double? accuracyM;

  const NavEngineOutput({
    required this.timestamp,
    required this.displayLatitude,
    required this.displayLongitude,
    required this.bearing,
    required this.markerSource,
    required this.shouldAnimateMarker,
    required this.cameraFollowMode,
    required this.cameraReason,
    this.speedKmh,
    this.accuracyM,
  });
}
