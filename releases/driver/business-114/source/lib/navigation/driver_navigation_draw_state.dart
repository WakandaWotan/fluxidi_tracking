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
  // NAV-PARKING-2 Commit 2: include a mid-geometry sample so a reroute that
  // reshapes the middle of the route (e.g. a different roundabout arm) while
  // keeping the same length + endpoints produces a DIFFERENT signature. The
  // old length+endpoints-only key could match within the draw debounce and
  // skip the replacement draw, leaving the previous blue path visible next to
  // the new one — a second authoritative-looking route around a roundabout.
  final mid = coords[coords.length ~/ 2];
  return '${coords.length}:'
      '${first.lon.toStringAsFixed(5)},${first.lat.toStringAsFixed(5)}>'
      '${mid.lon.toStringAsFixed(5)},${mid.lat.toStringAsFixed(5)}>'
      '${last.lon.toStringAsFixed(5)},${last.lat.toStringAsFixed(5)}';
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
