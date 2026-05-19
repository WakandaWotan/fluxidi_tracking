import 'driver_navigation_models.dart';

String driverPinsDrawSignature({
  required DriverLonLat pickup,
  required DriverLonLat dropoff,
}) {
  return '${pickup.lon.toStringAsFixed(5)},${pickup.lat.toStringAsFixed(5)}|${dropoff.lon.toStringAsFixed(5)},${dropoff.lat.toStringAsFixed(5)}';
}

String driverRouteDrawSignature(List<DriverLonLat> coords) {
  final first = coords.first;
  final last = coords.last;
  return '${coords.length}:${first.lon.toStringAsFixed(5)},${first.lat.toStringAsFixed(5)}>${last.lon.toStringAsFixed(5)},${last.lat.toStringAsFixed(5)}';
}

bool driverShouldSkipDraw({
  required String signature,
  required String? lastSignature,
  required DateTime? lastDrawAt,
  required Duration debounce,
  bool force = false,
  DateTime? now,
}) {
  if (force) return false;
  if (signature != lastSignature) return false;
  if (lastDrawAt == null) return false;
  final referenceNow = now ?? DateTime.now();
  return referenceNow.difference(lastDrawAt) < debounce;
}
