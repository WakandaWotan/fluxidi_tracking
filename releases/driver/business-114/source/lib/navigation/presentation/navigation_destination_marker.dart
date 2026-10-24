import '../driver_navigation_models.dart';

/// NAV-PRES-3L: resolved coordinate for the active navigation destination marker.
class NavigationDestinationMarkerCoordinate {
  const NavigationDestinationMarkerCoordinate({
    required this.lat,
    required this.lon,
    required this.source,
  });

  final double lat;
  final double lon;

  /// `route_end` or `dropoff`.
  final String source;
}

bool isTrustedNavigationLonLat(DriverLonLat? point) {
  if (point == null) return false;
  if (!point.lat.isFinite || !point.lon.isFinite) return false;
  if (point.lat.abs() > 90 || point.lon.abs() > 180) return false;
  if (point.lat == 0 && point.lon == 0) return false;
  return true;
}

/// NAV-PRES-3L: chooses the destination marker coordinate for active navigation.
///
/// Priority:
/// 1. final coordinate of active route geometry
/// 2. trusted dropoff/destination coordinate
/// 3. null when neither is safe
NavigationDestinationMarkerCoordinate?
resolveNavigationDestinationMarkerCoordinate({
  required List<DriverLonLat> routeCoords,
  DriverLonLat? trustedDropoff,
}) {
  if (routeCoords.isNotEmpty) {
    final last = routeCoords.last;
    if (isTrustedNavigationLonLat(last)) {
      return NavigationDestinationMarkerCoordinate(
        lat: last.lat,
        lon: last.lon,
        source: 'route_end',
      );
    }
  }
  if (isTrustedNavigationLonLat(trustedDropoff)) {
    return NavigationDestinationMarkerCoordinate(
      lat: trustedDropoff!.lat,
      lon: trustedDropoff.lon,
      source: 'dropoff',
    );
  }
  return null;
}

String navigationDestinationMarkerSignature(
  NavigationDestinationMarkerCoordinate coordinate,
) {
  return '${coordinate.source}|'
      '${coordinate.lat.toStringAsFixed(5)}|'
      '${coordinate.lon.toStringAsFixed(5)}';
}
