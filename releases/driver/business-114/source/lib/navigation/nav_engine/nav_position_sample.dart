/// A single lat/lon sample with timestamp for motion smoothing.
class NavPositionSample {
  final double latitude;
  final double longitude;
  final DateTime timestamp;

  const NavPositionSample({
    required this.latitude,
    required this.longitude,
    required this.timestamp,
  });
}
