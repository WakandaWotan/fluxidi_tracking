import 'package:fluxidi_tracking/navigation/driver_navigation_models.dart';
import 'package:fluxidi_tracking/navigation/traffic/navigation_traffic_model.dart';

final trafficNow = DateTime.utc(2026, 10, 11, 10);
const trafficRoute = [
  DriverLonLat(4.4, 51.2),
  DriverLonLat(4.404, 51.2),
  DriverLonLat(4.408, 51.2),
  DriverLonLat(4.412, 51.2),
];

Map<String, dynamic> trafficSegment({
  int start = 1,
  int end = 2,
  String traffic = 'heavy',
  String event = 'congestion',
  double confidence = .95,
  double? delay = 240,
  double? speed = 8,
}) => {
  'startGeometryIndex': start,
  'endGeometryIndex': end,
  'trafficClass': traffic,
  'eventType': event,
  'confidence': confidence,
  if (delay != null) 'delaySeconds': delay,
  if (speed != null) 'speedKmh': speed,
};

Map<String, dynamic> trafficWire({
  List<Map<String, dynamic>>? segments,
  String state = 'AVAILABLE',
  List<DriverLonLat> geometry = trafficRoute,
  DateTime? observedAt,
  DateTime? validUntil,
}) => {
  'schema': 'fluxidi-navigation-traffic-visuals-v1',
  'sourceState': state,
  'binding': 'exact-directed-route-geometry',
  'rights': 'usable',
  'scope': 'public-road',
  'routeGeometrySha256': navigationTrafficGeometryFingerprint(geometry),
  'revision': 'fixture-1',
  'observedAt': (observedAt ?? trafficNow).millisecondsSinceEpoch,
  'validUntil': (validUntil ?? trafficNow.add(const Duration(minutes: 2)))
      .millisecondsSinceEpoch,
  'segments': segments ?? [trafficSegment()],
};

Map<String, dynamic> trafficResponse(
  Map<String, dynamic>? traffic, {
  bool inLeg = false,
}) => {
  'routes': [
    {
      'distance': 835.0,
      'duration': 300,
      'geometry': {
        'type': 'LineString',
        'coordinates': [
          for (final p in trafficRoute) [p.lon, p.lat],
        ],
      },
      if (traffic != null && !inLeg) 'traffic_visuals': traffic,
      'legs': [
        {if (traffic != null && inLeg) 'traffic_visuals': traffic, 'steps': []},
      ],
    },
  ],
};

NavigationTrafficSnapshot decodeFixture(
  Map<String, dynamic>? wire, {
  DateTime? now,
  List<DriverLonLat> geometry = trafficRoute,
}) => decodeNavigationTraffic(
  response: trafficResponse(wire),
  geometry: geometry,
  now: now ?? trafficNow,
);
