import 'dart:convert';
import 'package:fluxidi_tracking/company/company_plan_quote.dart';

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
    CompanyPlanQuoteResult? quote,
  }) {
    if (quote != null) {
      return Future<CustomerBookingRouteGeometry>.sync(() => fromServerQuote(quote:quote,pickup:pickup,dropoff:dropoff,stops:stops));
    }
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

  static CustomerBookingRouteGeometry fromServerQuote({required CompanyPlanQuoteResult quote,
    required FluxidiMapLonLat pickup,required FluxidiMapLonLat dropoff,List<FluxidiMapLonLat> stops=const []}) {
    final raw=quote.routePreview;
    Never invalid()=>throw StateError('owned_quote_route_unavailable');
    if(raw==null||raw['schema']!='fluxidi-quote-route-preview-v1'||raw['source']!='fluxidi-national'||
      !RegExp(r'^[a-f0-9]{64}$').hasMatch('${raw['graph_checksum']??''}')) invalid();
    final bound=raw['points'],expected=[pickup,...stops,dropoff];
    if(bound is! List||bound.length!=expected.length) invalid();
    for(var i=0;i<expected.length;i++) {
      final p=bound[i];
      if(p is! Map||p['lat'] is! num||p['lng'] is! num||
        !(p['lat'] as num).isFinite||!(p['lng'] as num).isFinite||
        ((p['lat'] as num).toDouble()-expected[i].lat).abs()>1e-7||
        ((p['lng'] as num).toDouble()-expected[i].lon).abs()>1e-7) invalid();
    }
    final geo=raw['geometry'];final coordinates=geo is Map?geo['coordinates']:null;
    if(geo is! Map||geo['type']!='LineString'||coordinates is! List||coordinates.length<2||coordinates.length>100000) invalid();
    final points=<FluxidiMapLonLat>[];
    for(final p in coordinates) {
      if(p is! List||p.length!=2||p[0] is! num||p[1] is! num) invalid();
      final point=customerBookingLonLat((p[1] as num).toDouble(),(p[0] as num).toDouble());
      if(point==null) invalid();points.add(point);
    }
    final meters=raw['distance_m'],seconds=raw['duration_s'];
    if(meters is! num||seconds is! num||!meters.isFinite||!seconds.isFinite||meters<0||seconds<0) invalid();
    if(quote.distanceKm!=null&&(quote.distanceKm!.toDouble()-meters/1000).abs()>0.051||
      quote.durationMin!=null&&quote.durationMin!=(seconds/60).round()) invalid();
    return CustomerBookingRouteGeometry(fingerprint:customerBookingRouteFingerprint(pickup:pickup,dropoff:dropoff,stops:stops),
      points:List.unmodifiable(points),distanceKm:meters/1000,durationMin:(seconds/60).round().clamp(1,24*60));
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
