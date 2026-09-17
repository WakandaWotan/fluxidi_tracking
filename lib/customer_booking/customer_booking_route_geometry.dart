import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:fluxidi_tracking/app_config.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_route_camera.dart';
import 'package:fluxidi_tracking/maps/fluxidi_static_route_preview.dart';

typedef CustomerBookingRouteHttpGet = Future<http.Response> Function(Uri url);

class CustomerBookingRouteGeometry {
  const CustomerBookingRouteGeometry({
    required this.fingerprint,
    required this.points,
    this.distanceKm,
    this.durationMin,
  });

  final String fingerprint;
  final List<FluxidiMapLonLat> points;
  final double? distanceKm;
  final int? durationMin;

  bool get hasLine => points.length >= 2;
}

class CustomerBookingRouteGeometryClient {
  CustomerBookingRouteGeometryClient({
    this.token = kMapboxToken,
    this.httpGet,
  });

  final String token;
  final CustomerBookingRouteHttpGet? httpGet;

  bool get canFetch => token.trim().isNotEmpty || httpGet != null;

  final Map<String, CustomerBookingRouteGeometry> _cache =
      <String, CustomerBookingRouteGeometry>{};
  final Map<String, Future<CustomerBookingRouteGeometry>> _inflight =
      <String, Future<CustomerBookingRouteGeometry>>{};

  Future<CustomerBookingRouteGeometry> fetch({
    required FluxidiMapLonLat pickup,
    required FluxidiMapLonLat dropoff,
    List<FluxidiMapLonLat> stops = const <FluxidiMapLonLat>[],
  }) {
    final fingerprint = customerBookingRouteFingerprint(
      pickup: pickup,
      dropoff: dropoff,
      stops: stops,
    );
    final cached = _cache[fingerprint];
    if (cached != null) return Future<CustomerBookingRouteGeometry>.value(cached);
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

  Future<CustomerBookingRouteGeometry> _load({
    required String fingerprint,
    required FluxidiMapLonLat pickup,
    required FluxidiMapLonLat dropoff,
    required List<FluxidiMapLonLat> stops,
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
    final points = <FluxidiMapLonLat>[];
    if (coordinates is List) {
      for (final raw in coordinates) {
        if (raw is! List || raw.length < 2) continue;
        final lon = (raw[0] as num?)?.toDouble();
        final lat = (raw[1] as num?)?.toDouble();
        final point = customerBookingLonLat(lat, lon);
        if (point != null) points.add(point);
      }
    }
    if (points.length < 2) throw StateError('route_failed');
    final meters = (route['distance'] as num?)?.toDouble();
    final seconds = (route['duration'] as num?)?.toDouble();
    final result = CustomerBookingRouteGeometry(
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
