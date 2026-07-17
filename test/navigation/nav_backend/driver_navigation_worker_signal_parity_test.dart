import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/navigation/driver_navigation_models.dart';
import 'package:fluxidi_tracking/navigation/driver_navigation_route_parser.dart';
import 'package:fluxidi_tracking/navigation/nav_backend/driver_navigation_worker_client.dart';

/// Rich Mapbox-shaped step fixture used for both direct and worker legs.
Map<String, dynamic> _richStep({
  required List<dynamic> location,
  required String type,
  required String modifier,
  required String instruction,
  String name = 'Teststraat',
  String? ref,
  List<dynamic>? destinations,
  Object? exit,
  List<Map<String, dynamic>>? banners,
  List<Map<String, dynamic>>? intersections,
  String? drivingSide,
}) {
  return <String, dynamic>{
    'distance': 120.0,
    'duration': 15,
    'name': name,
    if (ref != null) 'ref': ref,
    if (destinations != null) 'destinations': destinations,
    if (drivingSide != null) 'driving_side': drivingSide,
    'maneuver': <String, dynamic>{
      'type': type,
      'modifier': modifier,
      'instruction': instruction,
      'location': location,
      if (exit != null) 'exit': exit,
      'bearing_before': 10,
      'bearing_after': 90,
    },
    if (banners != null) 'bannerInstructions': banners,
    if (intersections != null) 'intersections': intersections,
  };
}

Map<String, dynamic> _banner({
  required double distanceAlongGeometry,
  required Map<String, dynamic> primary,
  Map<String, dynamic>? secondary,
  Map<String, dynamic>? sub,
}) {
  return <String, dynamic>{
    'distanceAlongGeometry': distanceAlongGeometry,
    'primary': primary,
    if (secondary != null) 'secondary': secondary,
    if (sub != null) 'sub': sub,
  };
}

Map<String, dynamic> _component({
  required String text,
  String? type,
  String? imageBaseURL,
  String? abbr,
  int? abbrPriority,
  List<String>? directions,
  bool? active,
  String? activeDirection,
}) {
  return <String, dynamic>{
    'text': text,
    if (type != null) 'type': type,
    if (imageBaseURL != null) 'imageBaseURL': imageBaseURL,
    if (abbr != null) 'abbr': abbr,
    if (abbrPriority != null) 'abbr_priority': abbrPriority,
    if (directions != null) 'directions': directions,
    if (active != null) 'active': active,
    if (activeDirection != null) 'active_direction': activeDirection,
  };
}

List<Map<String, dynamic>> _richLegsFixture() {
  final stepTurn = _richStep(
    location: <dynamic>[4.40, 50.85],
    type: 'turn',
    modifier: 'right',
    instruction: 'Turn right onto Teststraat',
    ref: 'N5',
    destinations: <dynamic>['Brussel', 'Centrum'],
    drivingSide: 'right',
    banners: <Map<String, dynamic>>[
      _banner(
        distanceAlongGeometry: 500,
        primary: <String, dynamic>{
          'text': 'Teststraat',
          'components': <dynamic>[
            _component(
              text: 'N5',
              type: 'icon',
              imageBaseURL: 'https://example.invalid/shields/',
              abbr: 'N5',
              abbrPriority: 0,
            ),
            _component(text: 'Teststraat', type: 'text'),
          ],
        },
        secondary: <String, dynamic>{
          'text': 'Brussel',
          'components': <dynamic>[_component(text: 'Brussel', type: 'text')],
        },
        sub: <String, dynamic>{
          'text': '',
          'components': <dynamic>[
            _component(
              text: '',
              type: 'lane',
              directions: <String>['straight', 'right'],
              active: true,
              activeDirection: 'right',
            ),
            _component(
              text: '',
              type: 'lane',
              directions: <String>['left'],
              active: false,
            ),
          ],
        },
      ),
      _banner(
        distanceAlongGeometry: 80,
        primary: <String, dynamic>{
          'text': 'Turn right',
          'components': <dynamic>[_component(text: 'Turn right', type: 'text')],
        },
      ),
    ],
    intersections: <Map<String, dynamic>>[
      <String, dynamic>{
        'location': <dynamic>[4.401, 50.851],
        'bearings': <dynamic>[0, 90, 180],
        'entry': <dynamic>[true, true, false],
        'in': 0,
        'out': 1,
        'classes': <dynamic>['motorway'],
        'lanes': <dynamic>[
          <String, dynamic>{
            'indications': <dynamic>['straight', 'right'],
            'valid': true,
            'active': true,
            'valid_indication': 'right',
            'access': <String, dynamic>{
              'designated': <dynamic>['taxi'],
            },
          },
          <String, dynamic>{
            'indications': <dynamic>['left'],
            'valid': false,
            // active intentionally omitted (driving-traffic optional).
          },
        ],
      },
    ],
  );

  final stepRoundabout = _richStep(
    location: <dynamic>[4.41, 50.86],
    type: 'roundabout',
    modifier: 'right',
    instruction: 'At the roundabout, take the 2nd exit',
    exit: 2,
    banners: <Map<String, dynamic>>[
      _banner(
        distanceAlongGeometry: 200,
        primary: <String, dynamic>{
          'text': '2nd exit',
          'components': <dynamic>[_component(text: '2nd exit', type: 'text')],
        },
      ),
    ],
  );

  return <Map<String, dynamic>>[
    <String, dynamic>{
      'steps': <dynamic>[stepTurn, stepRoundabout],
    },
  ];
}

NavigationWorkerRouteResult _workerResult({
  List<Map<String, dynamic>>? legs,
  List<Map<String, dynamic>>? maneuvers,
}) {
  return NavigationWorkerRouteResult(
    distanceMeters: 1200,
    durationSeconds: 180,
    coords: const <DriverLonLat>[
      DriverLonLat(4.40, 50.85),
      DriverLonLat(4.41, 50.86),
    ],
    maneuvers: maneuvers ?? const <Map<String, dynamic>>[],
    legs: legs ?? const <Map<String, dynamic>>[],
    cache: 'miss',
  );
}

DriverRouteParseResult _parseShape(Map<String, dynamic> shape) {
  return parseDriverDirectionsResponse(
    response: shape,
    localizeInstruction: (raw) => raw,
    distanceAlongRouteForCoords: (_, __) => 0,
  );
}

void main() {
  group('NAV-SIGNAL-P0A-WORKER-PARITY-1', () {
    test('A) worker route conversion preserves rich signaling fields', () {
      final result = _workerResult(legs: _richLegsFixture());
      final shape = result.toMapboxDirectionsShape();
      final legs = (shape['routes'] as List).first['legs'] as List;
      final steps = (legs.first as Map)['steps'] as List;
      final step0 = steps[0] as Map<String, dynamic>;

      expect(result.hasPreservedLegs, isTrue);
      expect(step0['ref'], 'N5');
      expect(step0['destinations'], isA<List>());
      expect((step0['maneuver'] as Map)['exit'], isNull);
      expect(step0['bannerInstructions'], isA<List>());
      final banners = step0['bannerInstructions'] as List;
      expect(banners.length, 2);
      expect(banners[0]['distanceAlongGeometry'], 500);
      expect(banners[1]['distanceAlongGeometry'], 80);

      final lanes =
          ((step0['intersections'] as List).first as Map)['lanes'] as List;
      expect(lanes.length, 2);
      expect(lanes[0]['valid'], isTrue);
      expect(lanes[0]['active'], isTrue);
      expect(lanes[0]['valid_indication'], 'right');
      expect((lanes[0]['access'] as Map)['designated'], contains('taxi'));

      // Components must not be flattened away.
      final primary = banners[0]['primary'] as Map;
      expect(primary['components'], isA<List>());
      expect((primary['components'] as List).length, 2);
      expect(
        ((primary['components'] as List)[0] as Map)['imageBaseURL'],
        'https://example.invalid/shields/',
      );
    });

    test('B) worker reroute conversion preserves the same fields', () {
      // Same reshape path for route and reroute — legs are endpoint-agnostic.
      final result = _workerResult(legs: _richLegsFixture());
      final shape = result.toMapboxDirectionsShape();
      final summary = summarizeNavSignalResponse(
        source: 'worker_reroute',
        mapboxShape: shape,
      );
      expect(summary.source, 'worker_reroute');
      expect(summary.steps, 2);
      expect(summary.banners, 3); // 2 on turn + 1 on roundabout
      expect(summary.laneGroups, 1);
      expect(summary.refs, 1);
      expect(summary.destinations, 1);
      expect(summary.roundaboutExits, 1);
      expect(summary.logLine, contains('[NAV_SIGNAL_RESPONSE]'));
      expect(summary.logLine, isNot(contains('Teststraat')));
      expect(summary.logLine, isNot(contains('Brussel')));
    });

    test('C) optional lane active / valid_indication may be absent', () {
      final legs = <Map<String, dynamic>>[
        <String, dynamic>{
          'steps': <dynamic>[
            _richStep(
              location: <dynamic>[4.40, 50.85],
              type: 'turn',
              modifier: 'left',
              instruction: 'Turn left',
              intersections: <Map<String, dynamic>>[
                <String, dynamic>{
                  'lanes': <dynamic>[
                    <String, dynamic>{
                      'indications': <dynamic>['left'],
                      'valid': true,
                      // no active, no valid_indication
                    },
                  ],
                },
              ],
            ),
          ],
        },
      ];
      final shape = _workerResult(legs: legs).toMapboxDirectionsShape();
      final parsed = _parseShape(shape);
      expect(parsed.navSteps, isNotEmpty);
      expect(parsed.stepsWithLaneGuidanceCount, 1);
      final lane = parsed.navSteps.first.lanes.first;
      expect(lane.valid, isTrue);
      expect(lane.active, isNull);
      expect(lane.validIndication, isNull);
    });

    test('D) multiple bannerInstructions keep original order', () {
      final shape = _workerResult(
        legs: _richLegsFixture(),
      ).toMapboxDirectionsShape();
      final step0 =
          ((((shape['routes'] as List).first as Map)['legs'] as List).first
                  as Map)['steps']
              as List;
      final banners = (step0[0] as Map)['bannerInstructions'] as List;
      expect(banners[0]['distanceAlongGeometry'], 500);
      expect(banners[1]['distanceAlongGeometry'], 80);
    });

    test('E) banner primary/secondary/sub component arrays preserved', () {
      final shape = _workerResult(
        legs: _richLegsFixture(),
      ).toMapboxDirectionsShape();
      final step0 =
          ((((shape['routes'] as List).first as Map)['legs'] as List).first
                  as Map)['steps']
              as List;
      final banner0 =
          ((step0[0] as Map)['bannerInstructions'] as List)[0] as Map;
      expect((banner0['primary'] as Map)['components'], isA<List>());
      expect((banner0['secondary'] as Map)['components'], isA<List>());
      expect((banner0['sub'] as Map)['components'], isA<List>());
      final subLane = ((banner0['sub'] as Map)['components'] as List)[0] as Map;
      expect(subLane['active_direction'], 'right');
      expect(subLane['directions'], contains('right'));
    });

    test('F) direct and worker-shaped fixtures parse equivalent signaling', () {
      final legs = _richLegsFixture();
      final directShape = <String, dynamic>{
        'routes': [
          {
            'distance': 1200,
            'duration': 180,
            'geometry': {
              'type': 'LineString',
              'coordinates': [
                [4.40, 50.85],
                [4.41, 50.86],
              ],
            },
            'legs': legs,
          },
        ],
      };
      final workerShape = _workerResult(legs: legs).toMapboxDirectionsShape();

      final directParsed = _parseShape(directShape);
      final workerParsed = _parseShape(workerShape);

      expect(workerParsed.navSteps.length, directParsed.navSteps.length);
      expect(
        workerParsed.stepsWithBannerCount,
        directParsed.stepsWithBannerCount,
      );
      expect(
        workerParsed.stepsWithLaneGuidanceCount,
        directParsed.stepsWithLaneGuidanceCount,
      );
      expect(
        workerParsed.navSteps[0].roadRef,
        directParsed.navSteps[0].roadRef,
      );
      expect(
        workerParsed.navSteps[0].destinationText,
        directParsed.navSteps[0].destinationText,
      );
      expect(
        workerParsed.navSteps[0].lanes.length,
        directParsed.navSteps[0].lanes.length,
      );
      expect(
        workerParsed.navSteps[1].exitNumber,
        directParsed.navSteps[1].exitNumber,
      );
      // Current parser keeps first banner text only — both paths agree.
      expect(
        workerParsed.navSteps[0].banner?.primaryText,
        directParsed.navSteps[0].banner?.primaryText,
      );
    });

    test('G) older minimal worker maneuvers remain backward-compatible', () {
      final result = _workerResult(
        maneuvers: <Map<String, dynamic>>[
          <String, dynamic>{
            'type': 'turn',
            'modifier': 'right',
            'instruction': 'Turn right',
            'location': <String, dynamic>{'lng': 4.40, 'lat': 50.85},
            'distance_m': 100,
            'duration_s': 12,
          },
        ],
      );
      expect(result.hasPreservedLegs, isFalse);
      final shape = result.toMapboxDirectionsShape();
      final parsed = _parseShape(shape);
      expect(parsed.navSteps.length, 1);
      expect(parsed.navSteps.first.type, 'turn');
      expect(parsed.navSteps.first.modifier, 'right');
      expect(parsed.stepsWithBannerCount, 0);
      expect(parsed.stepsWithLaneGuidanceCount, 0);
    });

    test('roundabout exit is preserved on worker legs for parser', () {
      final shape = _workerResult(
        legs: _richLegsFixture(),
      ).toMapboxDirectionsShape();
      final parsed = _parseShape(shape);
      expect(parsed.navSteps[1].exitNumber, '2');
      expect(parsed.navSteps[1].type, 'roundabout');
    });
  });
}
