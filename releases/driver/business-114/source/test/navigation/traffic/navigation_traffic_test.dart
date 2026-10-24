import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/navigation/driver_navigation_models.dart';
import 'package:fluxidi_tracking/navigation/driver_navigation_route_parser.dart';
import 'package:fluxidi_tracking/navigation/nav_backend/driver_navigation_worker_client.dart';
import 'package:fluxidi_tracking/navigation/nav_backend/driver_route_apply.dart';
import 'package:fluxidi_tracking/navigation/nav_engine/nav_reroute_apply_progress.dart';
import 'package:fluxidi_tracking/navigation/traffic/navigation_traffic_banner.dart';
import 'package:fluxidi_tracking/navigation/traffic/navigation_traffic_controller.dart';
import 'package:fluxidi_tracking/navigation/traffic/navigation_traffic_model.dart';
import 'package:fluxidi_tracking/navigation/traffic/navigation_traffic_route_adapter.dart';
import 'traffic_fixtures.dart';

NavigationTrafficController installed(Map<String, dynamic>? wire) {
  final controller = NavigationTrafficController();
  addTearDown(controller.dispose);
  controller.install(
    geometry: trafficRoute,
    snapshot: decodeFixture(wire),
    now: trafficNow,
  );
  controller.updateProgress(0, trusted: true, now: trafficNow);
  return controller;
}

void main() {
  test(
    'reroute trim origin keeps bound traffic ahead and passed events removed',
    () {
      final controller = NavigationTrafficController();
      addTearDown(controller.dispose);
      final applied = navRerouteSelectApplyProgress(
        routeCoords: [
          for (final p in trafficRoute)
            NavRerouteApplyLatLon(lat: p.lat, lon: p.lon),
        ],
        vehicleLat: 51.2,
        vehicleLon: 4.406,
        vehicleCourseDeg: 90,
      );
      expect(applied.accepted, isTrue);
      controller.install(
        geometry: trafficRoute,
        now: trafficNow,
        progressOriginMeters: applied.distanceAlongRouteM!,
        snapshot: decodeFixture(
          trafficWire(
            segments: [
              trafficSegment(
                start: 0,
                end: 1,
                traffic: 'closed',
                event: 'closure',
              ),
              trafficSegment(start: 1, end: 2),
              trafficSegment(start: 2, end: 3, traffic: 'light'),
            ],
          ),
        ),
      );
      final spans = controller.spansAt(trafficNow);
      expect(spans.map((s) => s.id), ['1:2', '2:3']);
      expect(spans.first.coordinates.first.lon, closeTo(4.406, .00001));
      controller.updateProgress(0, trusted: true, now: trafficNow);
      expect(controller.alert.value!.event, NavigationTrafficEvent.congestion);
      expect(controller.alert.value!.delaySeconds, isNull);
      controller.updateProgress(200, trusted: true, now: trafficNow);
      expect(controller.spansAt(trafficNow).single.id, '2:3');
      expect(controller.alert.value!.traffic, NavigationTrafficClass.light);
      expect(controller.alert.value!.distanceMeters, 0);
      expect(
        controller.progressMeters,
        closeTo(applied.distanceAlongRouteM! + 200, .01),
      );
      controller.updateProgress(null, trusted: false, now: trafficNow);
      expect(controller.spansAt(trafficNow).single.id, '2:3');
    },
  );
  test('unknown reroute progress origin discards optional traffic only', () {
    final controller = NavigationTrafficController();
    addTearDown(controller.dispose);
    controller.install(
      geometry: trafficRoute,
      snapshot: decodeFixture(trafficWire()),
      now: trafficNow,
      progressOriginMeters: double.nan,
    );
    expect(
      controller.stateAt(trafficNow),
      NavigationTrafficSourceState.unbound,
    );
    expect(controller.spansAt(trafficNow), isEmpty);
  });
  test(
    'segment total delay is omitted after entering it; no app ETA projection',
    () {
      final controller = installed(trafficWire());
      controller.updateProgress(400, trusted: true, now: trafficNow);
      expect(controller.alert.value, isNotNull);
      expect(
        navigationTrafficAlertText(controller.alert.value!, 'nl'),
        isNot(contains('min')),
      );
    },
  );
  test(
    'A no traffic preserves route availability and has zero overlays/alerts',
    () {
      final controller = installed(null);
      expect(
        controller.stateAt(trafficNow),
        NavigationTrafficSourceState.unavailable,
      );
      expect(controller.spansAt(trafficNow), isEmpty);
      expect(controller.alert.value, isNull);
      expect(controller.nextExpiry(trafficNow), isNull);
    },
  );
  for (final item in [
    ('B normal', 'normal', 0xFF2B6CB0),
    ('C light', 'light', 0xFFF59E0B),
    ('D heavy', 'heavy', 0xFFDC2626),
    ('reliable severe', 'severe', 0xFF991B1B),
  ]) {
    test(
      '${item.$1} uses the supplied normalized class, confidence, delay and speed',
      () {
        final controller = installed(
          trafficWire(segments: [trafficSegment(traffic: item.$2)]),
        );
        expect(controller.spansAt(trafficNow).single.color, item.$3);
        final segment = decodeFixture(trafficWire()).segments.single;
        expect(segment.delaySeconds, 240);
        expect(segment.speedKmh, 8);
        expect(segment.confidence, .95);
        expect(controller.alert.value == null, item.$2 == 'normal');
      },
    );
  }
  test(
    'E closure is distinct and F roadworks appears without changing ETA',
    () {
      final closure = installed(
        trafficWire(
          segments: [trafficSegment(traffic: 'closed', event: 'closure')],
        ),
      );
      expect(closure.spansAt(trafficNow).single.color, 0xFF7C2D52);
      expect(
        navigationTrafficAlertText(closure.alert.value!, 'nl'),
        contains('Weg afgesloten'),
      );
      final works = installed(
        trafficWire(
          segments: [trafficSegment(traffic: 'light', event: 'roadworks')],
        ),
      );
      expect(
        navigationTrafficAlertText(works.alert.value!, 'nl'),
        startsWith('Werken ·'),
      );
    },
  );
  for (final state in ['STALE', 'UNAVAILABLE', 'UNBOUND']) {
    test('G/H/I $state keeps normal presentation', () {
      final controller = installed(trafficWire(state: state));
      expect(controller.stateAt(trafficNow).name.toUpperCase(), state);
      expect(controller.spansAt(trafficNow), isEmpty);
      expect(controller.alert.value, isNull);
      expect(controller.nextExpiry(trafficNow), isNull);
    });
  }
  test(
    'J passed segments disappear, clipping progresses and GPS gaps do not revive them',
    () {
      final controller = installed(trafficWire());
      controller.updateProgress(400, trusted: true, now: trafficNow);
      expect(
        controller.spansAt(trafficNow).single.coordinates.first.lon,
        greaterThan(4.404),
      );
      controller.updateProgress(600, trusted: true, now: trafficNow);
      expect(controller.spansAt(trafficNow), isEmpty);
      expect(controller.alert.value, isNull);
      controller.updateProgress(0, trusted: false, now: trafficNow);
      expect(controller.spansAt(trafficNow), isEmpty);
      controller.updateProgress(0, trusted: true, now: trafficNow);
      expect(controller.spansAt(trafficNow), isEmpty);
    },
  );
  test(
    'K new accepted route replaces closure; visual layer cannot initiate rerouting',
    () {
      final controller = installed(
        trafficWire(
          segments: [trafficSegment(traffic: 'closed', event: 'closure')],
        ),
      );
      expect(controller.alert.value, isNotNull);
      controller.install(
        geometry: trafficRoute,
        snapshot: const NavigationTrafficSnapshot.unavailable(),
        now: trafficNow,
      );
      expect(controller.alert.value, isNull);
      expect(controller.spansAt(trafficNow), isEmpty);
    },
  );
  test('L offline expiry removes claims without a GPS update or request', () {
    final controller = installed(trafficWire());
    final expired = trafficNow.add(const Duration(minutes: 2));
    controller.expire(expired);
    expect(controller.stateAt(expired), NavigationTrafficSourceState.stale);
    expect(controller.alert.value, isNull);
    expect(controller.spansAt(expired), isEmpty);
    expect(controller.nextExpiry(expired), isNull);
  });
  test(
    'confidence distinguishes visual evidence and alerts without upgrading low data',
    () {
      final low = installed(
        trafficWire(segments: [trafficSegment(confidence: .79)]),
      );
      expect(low.spansAt(trafficNow), isEmpty);
      expect(low.alert.value, isNull);
      final medium = installed(
        trafficWire(segments: [trafficSegment(confidence: .82)]),
      );
      expect(medium.spansAt(trafficNow), hasLength(1));
      expect(medium.alert.value, isNull);
    },
  );
  test(
    'one alert prioritizes closure, then incident, then heavy, then light',
    () {
      final controller = installed(
        trafficWire(
          segments: [
            trafficSegment(start: 0, end: 1, traffic: 'light'),
            trafficSegment(start: 1, end: 2, traffic: 'heavy'),
            trafficSegment(
              start: 2,
              end: 3,
              traffic: 'closed',
              event: 'closure',
            ),
          ],
        ),
      );
      expect(controller.alert.value!.event, NavigationTrafficEvent.closure);
      final incident = installed(
        trafficWire(
          segments: [
            trafficSegment(start: 0, end: 1, traffic: 'heavy'),
            trafficSegment(
              start: 1,
              end: 2,
              traffic: 'light',
              event: 'incident',
            ),
          ],
        ),
      );
      expect(incident.alert.value!.event, NavigationTrafficEvent.incident);
    },
  );
  test(
    'missing delay has no invented duration and normal traffic has no alert',
    () {
      final controller = installed(
        trafficWire(segments: [trafficSegment(delay: null, speed: null)]),
      );
      expect(
        navigationTrafficAlertText(controller.alert.value!, 'nl'),
        isNot(contains('min')),
      );
    },
  );
  test(
    'individual stale segment drops while other fresh evidence survives',
    () {
      final wire = trafficWire(
        segments: [
          trafficSegment(start: 0, end: 1),
          trafficSegment(start: 1, end: 2, traffic: 'light'),
        ],
      );
      (wire['segments'] as List).first['validUntil'] = trafficNow
          .add(const Duration(seconds: 10))
          .millisecondsSinceEpoch;
      final controller = installed(wire);
      final later = trafficNow.add(const Duration(seconds: 10));
      expect(controller.nextExpiry(trafficNow), later);
      controller.expire(later);
      expect(
        controller.spansAt(later).single.traffic,
        NavigationTrafficClass.light,
      );
    },
  );
  test('provider validity cannot renew the maximum observation age', () {
    final snapshot = decodeFixture(
      trafficWire(validUntil: trafficNow.add(const Duration(hours: 1))),
      now: trafficNow.add(const Duration(minutes: 3)),
    );
    expect(snapshot.state, NavigationTrafficSourceState.stale);
  });
  test(
    'full directed geometry binding rejects same endpoints with a changed interior',
    () {
      final changed = [...trafficRoute];
      changed[1] = const DriverLonLat(4.4041, 51.2);
      expect(
        decodeFixture(trafficWire(), geometry: changed).state,
        NavigationTrafficSourceState.unbound,
      );
      expect(
        decodeFixture(
          trafficWire(),
          geometry: trafficRoute.reversed.toList(),
        ).state,
        NavigationTrafficSourceState.unbound,
      );
    },
  );
  final invalid = <String, void Function(Map<String, dynamic>)>{
    'graph IDs mistaken for geometry': (v) {
      v['binding'] = 'graph-edge-ids';
    },
    'unapproved rights': (v) {
      v['rights'] = 'unknown';
    },
    'private fleet data without authenticated scope': (v) {
      v['scope'] = 'company-fleet';
    },
    'wrong schema': (v) {
      v['schema'] = 'fluxidi-operational-routing-v1';
    },
    'missing observation': (v) {
      v.remove('observedAt');
    },
    'future observation': (v) {
      v['observedAt'] = trafficNow
          .add(const Duration(seconds: 1))
          .millisecondsSinceEpoch;
    },
    'fractional index': (v) {
      v['segments'][0]['startGeometryIndex'] = 1.5;
    },
    'out of bounds': (v) {
      v['segments'][0]['endGeometryIndex'] = 90;
    },
    'unknown class': (v) {
      v['segments'][0]['trafficClass'] = 'unknown';
    },
    'unknown event': (v) {
      v['segments'][0]['eventType'] = 'unknown';
    },
    'closure contradiction': (v) {
      v['segments'][0]['eventType'] = 'closure';
    },
    'NaN confidence': (v) {
      v['segments'][0]['confidence'] = double.nan;
    },
    'negative delay': (v) {
      v['segments'][0]['delaySeconds'] = -1;
    },
    'overlapping evidence': (v) {
      v['segments'].add(trafficSegment());
    },
    'unbounded segment count': (v) {
      v['segments'] = List.generate(257, (_) => trafficSegment());
    },
  };
  for (final entry in invalid.entries) {
    test('unsafe ${entry.key} is UNBOUND and does not throw', () {
      final wire = trafficWire();
      entry.value(wire);
      expect(decodeFixture(wire).state, NavigationTrafficSourceState.unbound);
    });
  }
  test(
    'ambiguous authorities and raw congestion without freshness remain unused',
    () {
      final response = trafficResponse(trafficWire());
      response['routes'][0]['legs'][0]['traffic_visuals'] = trafficWire();
      expect(
        decodeNavigationTraffic(
          response: response,
          geometry: trafficRoute,
          now: trafficNow,
        ).state,
        NavigationTrafficSourceState.unbound,
      );
      final noFreshness = trafficResponse(null);
      noFreshness['routes'][0]['legs'][0]['annotation'] = {
        'congestion': ['heavy', 'heavy', 'heavy'],
      };
      expect(
        decodeNavigationTraffic(
          response: noFreshness,
          geometry: trafficRoute,
          now: trafficNow,
        ).state,
        NavigationTrafficSourceState.unavailable,
      );
    },
  );
  test(
    'actual preserved-leg transport carries optional traffic while route fields and ETA are unchanged',
    () {
      final original = NavigationWorkerRouteResult(
        distanceMeters: 835,
        durationSeconds: 300,
        coords: trafficRoute,
        maneuvers: const [],
        legs: [
          {'traffic_visuals': trafficWire(), 'steps': []},
        ],
        cache: 'hit',
      );
      final response = original.toMapboxDirectionsShape();
      final parsed = parseDriverDirectionsResponse(
        response: response,
        localizeInstruction: (s) => s,
        distanceAlongRouteForCoords: (_, __) => 0,
      );
      final baseline = prepareDriverRoutePackage(
        parsed: parsed,
        source: DriverRouteResponseSource.worker,
      );
      final enhanced =
          prepareNavigationTrafficRoutePackage(
                parsed: bindNavigationTrafficParseResult(
                  parsed: parsed,
                  response: response,
                  now: trafficNow,
                ),
                source: DriverRouteResponseSource.worker,
              )
              as NavigationTrafficPreparedRoute;
      expect(enhanced.traffic.state, NavigationTrafficSourceState.available);
      expect(enhanced.coords, baseline.coords);
      expect(enhanced.navSteps, baseline.navSteps);
      expect(enhanced.durationSeconds, baseline.durationSeconds);
      expect(enhanced.geometryFingerprint, baseline.geometryFingerprint);
      expect(enhanced.distanceMeters, baseline.distanceMeters);
      expect(enhanced.source, baseline.source);
    },
  );
  test(
    'unknown current response yields identical route package with UNAVAILABLE traffic',
    () {
      final parsed = const DriverRouteParseResult(
        coords: trafficRoute,
        distanceMeters: 835,
        durationSeconds: 300,
        navSteps: [],
      );
      final result =
          prepareNavigationTrafficRoutePackage(
                parsed: parsed,
                source: DriverRouteResponseSource.mapboxDirect,
              )
              as NavigationTrafficPreparedRoute;
      expect(result.durationSeconds, 300);
      expect(result.coords, trafficRoute);
      expect(result.traffic.state, NavigationTrafficSourceState.unavailable);
    },
  );
}
