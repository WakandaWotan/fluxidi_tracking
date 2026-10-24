/// Real driving route between the ride endpoints.
///
/// Ported from golden commit 9df7e7b92ecc86a11184ee995e255da7b8f6fb68:
/// `lib/customer_booking/customer_booking_route_geometry.dart` —
/// `CustomerBookingRouteGeometry`, `CustomerBookingRouteGeometryClient`.
///
/// Uses the Mapbox Directions API with `geometries=geojson&overview=full`, the
/// same call the existing customer flow makes. A straight line is never drawn as
/// a substitute: without a route answer there is no line.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import 'lon_lat.dart';

typedef FluxidiRouteHttpGet = Future<http.Response> Function(Uri url);

class FluxidiRouteGeometry {
  const FluxidiRouteGeometry({
    required this.fingerprint,
    required this.points,
    this.distanceKm,
    this.durationMin,
  });

  final String fingerprint;

  /// Full route line as returned by the routing service.
  final List<FluxidiLonLat> points;

  final double? distanceKm;
  final int? durationMin;

  bool get hasLine => points.length >= 2;
}

class FluxidiRouteGeometryClient {
  FluxidiRouteGeometryClient({required this.token, this.httpGet});

  /// Mapbox access token. Never logged.
  final String token;

  final FluxidiRouteHttpGet? httpGet;

  final Map<String, FluxidiRouteGeometry> _cache =
      <String, FluxidiRouteGeometry>{};
  final Map<String, Future<FluxidiRouteGeometry>> _inflight =
      <String, Future<FluxidiRouteGeometry>>{};

  bool get canFetch => token.trim().isNotEmpty || httpGet != null;

  Future<FluxidiRouteGeometry> fetch({
    required FluxidiLonLat pickup,
    required FluxidiLonLat dropoff,
    List<FluxidiLonLat> stops = const <FluxidiLonLat>[],
  }) {
    final fingerprint = fluxidiRouteFingerprint(
      pickup: pickup,
      dropoff: dropoff,
      stops: stops,
    );
    final cached = _cache[fingerprint];
    if (cached != null) return Future<FluxidiRouteGeometry>.value(cached);
    final pending = _inflight[fingerprint];
    if (pending != null) return pending;
    final next = _load(
      fingerprint: fingerprint,
      pickup: pickup,
      dropoff: dropoff,
      stops: stops,
    );
    _inflight[fingerprint] = next;
    return next.whenComplete(() => _inflight.remove(fingerprint));
  }

  Future<FluxidiRouteGeometry> _load({
    required String fingerprint,
    required FluxidiLonLat pickup,
    required FluxidiLonLat dropoff,
    required List<FluxidiLonLat> stops,
  }) async {
    final access = token.trim();
    if (access.isEmpty && httpGet == null) {
      throw StateError('route_failed');
    }
    final coords = <String>[
      '${pickup.lon},${pickup.lat}',
      for (final stop in stops) '${stop.lon},${stop.lat}',
      '${dropoff.lon},${dropoff.lat}',
    ].join(';');
    final uri = Uri.parse(
      'https://api.mapbox.com/directions/v5/mapbox/driving/$coords'
      '?alternatives=false&geometries=geojson&overview=full'
      '&access_token=$access',
    );
    final res = httpGet != null
        ? await httpGet!(uri)
        : await http.get(uri).timeout(const Duration(seconds: 12));
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw StateError('route_failed');
    }
    final decoded = jsonDecode(res.body);
    if (decoded is! Map) throw StateError('route_failed');
    final routes = decoded['routes'];
    if (routes is! List || routes.isEmpty) throw StateError('route_failed');
    final route = routes.first;
    if (route is! Map) throw StateError('route_failed');
    final geometry = route['geometry'];
    final coordinates = geometry is Map ? geometry['coordinates'] : null;
    final points = <FluxidiLonLat>[];
    if (coordinates is List) {
      for (final raw in coordinates) {
        if (raw is! List || raw.length < 2) continue;
        final point = fluxidiLonLat(
          (raw[1] as num?)?.toDouble(),
          (raw[0] as num?)?.toDouble(),
        );
        if (point != null) points.add(point);
      }
    }
    if (points.length < 2) throw StateError('route_failed');
    final meters = (route['distance'] as num?)?.toDouble();
    final seconds = (route['duration'] as num?)?.toDouble();
    final result = FluxidiRouteGeometry(
      fingerprint: fingerprint,
      points: points,
      distanceKm: meters != null && meters > 0 ? meters / 1000 : null,
      durationMin: seconds != null && seconds > 0
          ? (seconds / 60).round().clamp(1, 24 * 60)
          : null,
    );
    _cache[fingerprint] = result;
    return result;
  }
}
