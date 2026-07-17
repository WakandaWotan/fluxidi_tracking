import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/navigation/driver_navigation_instruction_state.dart';
import 'package:fluxidi_tracking/navigation/driver_navigation_models.dart';
import 'package:fluxidi_tracking/navigation/driver_navigation_route_parser.dart';
import 'package:fluxidi_tracking/navigation/nav_engine/nav_banner_resolver.dart';
import 'package:fluxidi_tracking/navigation/nav_engine/nav_instruction_policy.dart';
import 'package:fluxidi_tracking/navigation/nav_engine/nav_lane_resolver.dart';

String _tr({
  required String nl,
  required String en,
  required String fr,
  required String es,
}) => nl;

DriverNavLaneGuidance _lane({
  required List<String> indications,
  bool? valid,
  bool? active,
  String? validIndication,
}) {
  return DriverNavLaneGuidance(
    indications: indications,
    valid: valid,
    active: active,
    validIndication: validIndication,
  );
}

DriverNavIntersection _intersection({
  required int sourceIndex,
  required List<DriverNavLaneGuidance> lanes,
}) {
  return DriverNavIntersection(sourceIndex: sourceIndex, lanes: lanes);
}

DriverNavBannerComponent _laneComponent({
  required List<String> directions,
  bool? active,
  String? activeDirection,
  int sourceHint = 0,
}) {
  return DriverNavBannerComponent(
    type: 'lane',
    text: 'lane$sourceHint',
    directions: directions,
    active: active,
    activeDirection: activeDirection,
  );
}

DriverNavBannerView _view({
  String text = 'Turn',
  List<DriverNavBannerComponent> components =
      const <DriverNavBannerComponent>[],
}) {
  return DriverNavBannerView(text: text, components: components);
}

DriverNavBannerStage _stage({
  required int sourceIndex,
  required double distance,
  DriverNavBannerView? primary,
  DriverNavBannerView? secondary,
  DriverNavBannerView? sub,
}) {
  return DriverNavBannerStage(
    sourceIndex: sourceIndex,
    distanceAlongGeometry: distance,
    primary: primary ?? _view(text: 'Prepare'),
    secondary: secondary,
    sub: sub,
  );
}

DriverNavStep _step({
  String type = 'continue',
  String modifier = '',
  String instruction = 'Continue',
  double distanceAlongRouteM = 100,
  List<DriverNavIntersection> intersections = const <DriverNavIntersection>[],
  List<DriverNavBannerStage> banners = const <DriverNavBannerStage>[],
  String street = '',
  String? drivingSide,
}) {
  return DriverNavStep(
    lat: 50.85,
    lon: 4.35,
    instruction: instruction,
    street: street,
    type: type,
    modifier: modifier,
    distanceAlongRouteM: distanceAlongRouteM,
    intersections: intersections,
    bannerInstructions: banners,
    drivingSide: drivingSide,
  );
}

DriverActiveBanner _activeBanner({
  required int routeVersion,
  required int traversal,
  required int maneuver,
  int? bannerIndex,
  NavBannerResolveSource source = NavBannerResolveSource.mapboxBanner,
}) {
  return DriverActiveBanner(
    traversalStepIndex: traversal,
    maneuverStepIndex: maneuver,
    distanceTargetStepIndex: maneuver,
    isDepartureSpecialCase: traversal == 0 && maneuver == 1,
    isFinalArrival: false,
    bannerIndex: bannerIndex,
    routeVersion: routeVersion,
    distanceAlongGeometry: bannerIndex == null ? null : 300,
    primaryText: 'Turn',
    secondaryText: '',
    maneuverType: 'turn',
    maneuverModifier: 'right',
    roadName: '',
    isHighwayLike: false,
    lanes: const <DriverNavLaneGuidance>[],
    transition: NavBannerResolveTransition.none,
    source: source,
    bannerCount: bannerIndex == null ? 0 : 1,
    trustedProgress: true,
  );
}

DriverResolvedLaneGuidance _resolve({
  required List<DriverNavStep> steps,
  required DriverActiveBanner banner,
  bool featureEnabled = true,
  DriverResolvedLaneGuidance? previous,
  bool destinationReached = false,
  bool clearBanners = false,
  int? routeVersion,
}) {
  return resolveDriverLaneGuidance(
    DriverLaneResolveInput(
      routeVersion: routeVersion ?? banner.routeVersion,
      routeSteps: steps,
      activeBanner: banner,
      featureEnabledForEvaluation: featureEnabled,
      previous: previous,
      destinationReached: destinationReached,
      clearBanners: clearBanners,
    ),
  );
}

void main() {
  group('NAV-SIGNAL-P2B parser intersection groups', () {
    test('12: A(1)+B(2)+C(2) stays three groups, never five flat', () {
      final parsed = parseDriverDirectionsResponse(
        response: <String, dynamic>{
          'routes': <dynamic>[
            <String, dynamic>{
              'distance': 1000,
              'duration': 100,
              'geometry': <String, dynamic>{
                'coordinates': <dynamic>[
                  <dynamic>[4.35, 50.85],
                  <dynamic>[4.36, 50.86],
                ],
              },
              'legs': <dynamic>[
                <String, dynamic>{
                  'steps': <dynamic>[
                    <String, dynamic>{
                      'name': 'Road',
                      'distance': 500,
                      'maneuver': <String, dynamic>{
                        'location': <dynamic>[4.35, 50.85],
                        'type': 'turn',
                        'modifier': 'right',
                        'instruction': 'Turn right',
                      },
                      'intersections': <dynamic>[
                        <String, dynamic>{
                          'lanes': <dynamic>[
                            <String, dynamic>{
                              'indications': <dynamic>['straight'],
                              'valid': true,
                            },
                          ],
                        },
                        <String, dynamic>{
                          'lanes': <dynamic>[
                            <String, dynamic>{
                              'indications': <dynamic>['left'],
                              'valid': false,
                            },
                            <String, dynamic>{
                              'indications': <dynamic>['right'],
                              'valid': true,
                            },
                          ],
                        },
                        <String, dynamic>{
                          'lanes': <dynamic>[
                            <String, dynamic>{
                              'indications': <dynamic>['straight'],
                              'valid': true,
                            },
                            <String, dynamic>{
                              'indications': <dynamic>['right'],
                              'valid': true,
                              'active': true,
                            },
                          ],
                        },
                      ],
                    },
                  ],
                },
              ],
            },
          ],
        },
        localizeInstruction: (raw) => raw,
        distanceAlongRouteForCoords: (_, __) => 0,
      );
      final step = parsed.navSteps.first;
      expect(step.intersections.length, 3);
      expect(step.intersections.map((i) => i.lanes.length).toList(), <int>[
        1,
        2,
        2,
      ]);
      // Legacy flat field must not concatenate.
      // ignore: deprecated_member_use_from_same_package
      expect(step.lanes, isEmpty);
    });
  });

  group('NAV-SIGNAL-P2B lane resolver', () {
    test('1: ordinary single lane → hidden', () {
      final steps = <DriverNavStep>[
        _step(
          intersections: <DriverNavIntersection>[
            _intersection(
              sourceIndex: 0,
              lanes: <DriverNavLaneGuidance>[
                _lane(indications: <String>['straight'], valid: true),
              ],
            ),
          ],
        ),
        _step(type: 'turn', modifier: 'right', instruction: 'Turn right'),
      ];
      final g = _resolve(
        steps: steps,
        banner: _activeBanner(
          routeVersion: 1,
          traversal: 0,
          maneuver: 1,
          bannerIndex: null,
          source: NavBannerResolveSource.maneuverInstruction,
        ),
      );
      expect(g.visible, isFalse);
      expect(g.hiddenReason, DriverLaneHiddenReason.singleLane);
    });

    test('2: one lane with indication → hidden', () {
      final steps = <DriverNavStep>[
        _step(
          intersections: <DriverNavIntersection>[
            _intersection(
              sourceIndex: 0,
              lanes: <DriverNavLaneGuidance>[
                _lane(indications: <String>['right'], valid: true),
              ],
            ),
          ],
        ),
        _step(type: 'turn', modifier: 'right'),
      ];
      final g = _resolve(
        steps: steps,
        banner: _activeBanner(
          routeVersion: 1,
          traversal: 0,
          maneuver: 1,
          source: NavBannerResolveSource.generic,
        ),
      );
      expect(g.visible, isFalse);
      expect(g.lanes.length, lessThan(2));
    });

    test('3: two-lane intersection, one valid → visible', () {
      final steps = <DriverNavStep>[
        _step(
          intersections: <DriverNavIntersection>[
            _intersection(
              sourceIndex: 0,
              lanes: <DriverNavLaneGuidance>[
                _lane(indications: <String>['straight'], valid: false),
                _lane(indications: <String>['right'], valid: true),
              ],
            ),
          ],
        ),
        _step(type: 'turn', modifier: 'right'),
      ];
      final g = _resolve(
        steps: steps,
        banner: _activeBanner(
          routeVersion: 1,
          traversal: 0,
          maneuver: 1,
          source: NavBannerResolveSource.maneuverInstruction,
        ),
      );
      expect(g.visible, isTrue);
      expect(g.source, DriverLaneGuidanceSource.intersection);
      expect(g.lanes.length, 2);
      expect(g.lanes[0].availability, DriverLaneAvailability.unavailable);
      expect(g.lanes[1].availability, DriverLaneAvailability.usable);
    });

    test('4: two usable lanes with different directions → visible', () {
      final steps = <DriverNavStep>[
        _step(
          intersections: <DriverNavIntersection>[
            _intersection(
              sourceIndex: 0,
              lanes: <DriverNavLaneGuidance>[
                _lane(indications: <String>['straight'], valid: true),
                _lane(indications: <String>['right'], valid: true),
              ],
            ),
          ],
        ),
        _step(type: 'turn', modifier: 'right'),
      ];
      final g = _resolve(
        steps: steps,
        banner: _activeBanner(
          routeVersion: 1,
          traversal: 0,
          maneuver: 1,
          source: NavBannerResolveSource.maneuverInstruction,
        ),
      );
      expect(g.visible, isTrue);
      expect(g.lanes.length, 2);
    });

    test('5: preferred active among valid lanes', () {
      final steps = <DriverNavStep>[
        _step(
          intersections: <DriverNavIntersection>[
            _intersection(
              sourceIndex: 0,
              lanes: <DriverNavLaneGuidance>[
                _lane(indications: <String>['left'], valid: true),
                _lane(indications: <String>['left'], valid: true, active: true),
              ],
            ),
          ],
        ),
        _step(type: 'turn', modifier: 'left'),
      ];
      final g = _resolve(
        steps: steps,
        banner: _activeBanner(
          routeVersion: 1,
          traversal: 0,
          maneuver: 1,
          source: NavBannerResolveSource.maneuverInstruction,
        ),
      );
      expect(g.visible, isTrue);
      expect(g.lanes[1].availability, DriverLaneAvailability.preferred);
      expect(g.preferredCount, 1);
    });

    test('6: intersection active missing but valid present', () {
      final steps = <DriverNavStep>[
        _step(
          intersections: <DriverNavIntersection>[
            _intersection(
              sourceIndex: 0,
              lanes: <DriverNavLaneGuidance>[
                _lane(indications: <String>['straight'], valid: false),
                _lane(indications: <String>['right'], valid: true),
              ],
            ),
          ],
        ),
        _step(type: 'turn', modifier: 'right'),
      ];
      final g = _resolve(
        steps: steps,
        banner: _activeBanner(
          routeVersion: 1,
          traversal: 0,
          maneuver: 1,
          source: NavBannerResolveSource.maneuverInstruction,
        ),
      );
      expect(g.visible, isTrue);
      expect(g.lanes[1].availability, DriverLaneAvailability.usable);
    });

    test('7: intersection valid missing → unknown', () {
      final steps = <DriverNavStep>[
        _step(
          intersections: <DriverNavIntersection>[
            _intersection(
              sourceIndex: 0,
              lanes: <DriverNavLaneGuidance>[
                _lane(indications: <String>['straight']),
                _lane(indications: <String>['right']),
              ],
            ),
          ],
        ),
        _step(type: 'turn', modifier: 'right'),
      ];
      final g = _resolve(
        steps: steps,
        banner: _activeBanner(
          routeVersion: 1,
          traversal: 0,
          maneuver: 1,
          source: NavBannerResolveSource.maneuverInstruction,
        ),
      );
      expect(
        g.lanes.every((l) => l.availability == DriverLaneAvailability.unknown),
        isTrue,
      );
      expect(g.visible, isFalse);
      expect(g.hiddenReason, DriverLaneHiddenReason.allUnusable);
    });

    test('8: all lanes invalid → hidden', () {
      final steps = <DriverNavStep>[
        _step(
          intersections: <DriverNavIntersection>[
            _intersection(
              sourceIndex: 0,
              lanes: <DriverNavLaneGuidance>[
                _lane(indications: <String>['left'], valid: false),
                _lane(indications: <String>['right'], valid: false),
              ],
            ),
          ],
        ),
        _step(type: 'turn', modifier: 'right'),
      ];
      final g = _resolve(
        steps: steps,
        banner: _activeBanner(
          routeVersion: 1,
          traversal: 0,
          maneuver: 1,
          source: NavBannerResolveSource.maneuverInstruction,
        ),
      );
      expect(g.visible, isFalse);
      expect(g.hiddenReason, DriverLaneHiddenReason.allUnusable);
    });

    test('9: empty indications → hidden', () {
      final steps = <DriverNavStep>[
        _step(
          intersections: <DriverNavIntersection>[
            _intersection(
              sourceIndex: 0,
              lanes: <DriverNavLaneGuidance>[
                _lane(indications: const <String>[], valid: true),
                _lane(indications: const <String>[], valid: true),
              ],
            ),
          ],
        ),
        _step(type: 'turn', modifier: 'right'),
      ];
      final g = _resolve(
        steps: steps,
        banner: _activeBanner(
          routeVersion: 1,
          traversal: 0,
          maneuver: 1,
          source: NavBannerResolveSource.maneuverInstruction,
        ),
      );
      expect(g.visible, isFalse);
      expect(g.hiddenReason, DriverLaneHiddenReason.malformedData);
    });

    test('10: five genuine lanes from one group → exactly five', () {
      final lanes = <DriverNavLaneGuidance>[
        for (var i = 0; i < 5; i++)
          _lane(
            indications: <String>[i == 4 ? 'right' : 'straight'],
            valid: i >= 3,
          ),
      ];
      final steps = <DriverNavStep>[
        _step(
          intersections: <DriverNavIntersection>[
            _intersection(sourceIndex: 0, lanes: lanes),
          ],
        ),
        _step(type: 'turn', modifier: 'right'),
      ];
      final g = _resolve(
        steps: steps,
        banner: _activeBanner(
          routeVersion: 1,
          traversal: 0,
          maneuver: 1,
          source: NavBannerResolveSource.maneuverInstruction,
        ),
      );
      expect(g.visible, isTrue);
      expect(g.lanes.length, 5);
    });

    test('11: A(1)+B(2)+C(2) → never merged; ambiguous hidden', () {
      final steps = <DriverNavStep>[
        _step(
          intersections: <DriverNavIntersection>[
            _intersection(
              sourceIndex: 0,
              lanes: <DriverNavLaneGuidance>[
                _lane(indications: <String>['straight'], valid: true),
              ],
            ),
            _intersection(
              sourceIndex: 1,
              lanes: <DriverNavLaneGuidance>[
                _lane(indications: <String>['left'], valid: false),
                _lane(indications: <String>['right'], valid: true),
              ],
            ),
            _intersection(
              sourceIndex: 2,
              lanes: <DriverNavLaneGuidance>[
                _lane(indications: <String>['straight'], valid: true),
                _lane(indications: <String>['right'], valid: true),
              ],
            ),
          ],
        ),
        _step(type: 'turn', modifier: 'right'),
      ];
      final g = _resolve(
        steps: steps,
        banner: _activeBanner(
          routeVersion: 1,
          traversal: 0,
          maneuver: 1,
          source: NavBannerResolveSource.maneuverInstruction,
        ),
      );
      expect(g.visible, isFalse);
      expect(g.hiddenReason, DriverLaneHiddenReason.ambiguousIntersections);
      expect(g.lanes.length, isNot(5));
    });

    test('13: banner components override ambiguous intersections', () {
      final banners = <DriverNavBannerStage>[
        _stage(
          sourceIndex: 0,
          distance: 300,
          primary: _view(
            text: 'Keep right',
            components: <DriverNavBannerComponent>[
              _laneComponent(directions: <String>['straight'], active: false),
              _laneComponent(
                directions: <String>['right'],
                active: true,
                activeDirection: 'right',
              ),
            ],
          ),
        ),
      ];
      final steps = <DriverNavStep>[
        _step(
          banners: banners,
          intersections: <DriverNavIntersection>[
            _intersection(
              sourceIndex: 0,
              lanes: <DriverNavLaneGuidance>[
                _lane(indications: <String>['straight'], valid: true),
              ],
            ),
            _intersection(
              sourceIndex: 1,
              lanes: <DriverNavLaneGuidance>[
                _lane(indications: <String>['left'], valid: true),
                _lane(indications: <String>['right'], valid: true),
              ],
            ),
          ],
        ),
        _step(type: 'turn', modifier: 'right'),
      ];
      final g = _resolve(
        steps: steps,
        banner: _activeBanner(
          routeVersion: 1,
          traversal: 0,
          maneuver: 1,
          bannerIndex: 0,
        ),
      );
      expect(g.visible, isTrue);
      expect(g.source, DriverLaneGuidanceSource.bannerComponent);
      expect(g.lanes.length, 2);
    });

    test('14: banner uses sub before primary before secondary', () {
      final banners = <DriverNavBannerStage>[
        _stage(
          sourceIndex: 0,
          distance: 200,
          primary: _view(
            text: 'Primary',
            components: <DriverNavBannerComponent>[
              _laneComponent(directions: <String>['left'], active: true),
              _laneComponent(directions: <String>['straight'], active: false),
            ],
          ),
          secondary: _view(
            text: 'Secondary',
            components: <DriverNavBannerComponent>[
              _laneComponent(directions: <String>['right'], active: true),
              _laneComponent(directions: <String>['straight'], active: false),
            ],
          ),
          sub: _view(
            text: 'Sub',
            components: <DriverNavBannerComponent>[
              _laneComponent(directions: <String>['straight'], active: false),
              _laneComponent(
                directions: <String>['slight right'],
                active: true,
                activeDirection: 'slight right',
              ),
            ],
          ),
        ),
      ];
      final steps = <DriverNavStep>[
        _step(banners: banners),
        _step(type: 'turn', modifier: 'right'),
      ];
      final g = _resolve(
        steps: steps,
        banner: _activeBanner(
          routeVersion: 1,
          traversal: 0,
          maneuver: 1,
          bannerIndex: 0,
        ),
      );
      expect(g.visible, isTrue);
      expect(g.lanes[1].directions, <String>['slight right']);
    });

    test('15: banner lanes not concatenated across views', () {
      final banners = <DriverNavBannerStage>[
        _stage(
          sourceIndex: 0,
          distance: 200,
          primary: _view(
            text: 'Primary',
            components: <DriverNavBannerComponent>[
              _laneComponent(directions: <String>['left'], active: true),
              _laneComponent(directions: <String>['straight'], active: false),
            ],
          ),
          secondary: _view(
            text: 'Secondary',
            components: <DriverNavBannerComponent>[
              _laneComponent(directions: <String>['right'], active: true),
              _laneComponent(directions: <String>['uturn'], active: false),
            ],
          ),
        ),
      ];
      final steps = <DriverNavStep>[
        _step(banners: banners),
        _step(type: 'turn', modifier: 'left'),
      ];
      final g = _resolve(
        steps: steps,
        banner: _activeBanner(
          routeVersion: 1,
          traversal: 0,
          maneuver: 1,
          bannerIndex: 0,
        ),
      );
      expect(g.lanes.length, 2);
      expect(g.lanes.any((l) => l.directions.contains('right')), isFalse);
    });

    test('16: banner-stage change replaces lane group atomically', () {
      final banners = <DriverNavBannerStage>[
        _stage(
          sourceIndex: 0,
          distance: 800,
          primary: _view(
            text: 'Far',
            components: <DriverNavBannerComponent>[
              _laneComponent(directions: <String>['straight'], active: true),
              _laneComponent(directions: <String>['right'], active: false),
            ],
          ),
        ),
        _stage(
          sourceIndex: 1,
          distance: 70,
          primary: _view(
            text: 'Near',
            components: <DriverNavBannerComponent>[
              _laneComponent(directions: <String>['left'], active: false),
              _laneComponent(directions: <String>['right'], active: true),
              _laneComponent(directions: <String>['straight'], active: false),
            ],
          ),
        ),
      ];
      final steps = <DriverNavStep>[
        _step(banners: banners),
        _step(type: 'turn', modifier: 'right'),
      ];
      final far = _resolve(
        steps: steps,
        banner: _activeBanner(
          routeVersion: 1,
          traversal: 0,
          maneuver: 1,
          bannerIndex: 0,
        ),
      );
      expect(far.lanes.length, 2);
      final near = _resolve(
        steps: steps,
        banner: _activeBanner(
          routeVersion: 1,
          traversal: 0,
          maneuver: 1,
          bannerIndex: 1,
        ),
        previous: far,
      );
      expect(near.lanes.length, 3);
      expect(near.bannerIndex, 1);
    });

    test('17: route version N→N+1 invalidates lanes', () {
      final steps = <DriverNavStep>[
        _step(
          intersections: <DriverNavIntersection>[
            _intersection(
              sourceIndex: 0,
              lanes: <DriverNavLaneGuidance>[
                _lane(indications: <String>['straight'], valid: false),
                _lane(indications: <String>['right'], valid: true),
              ],
            ),
          ],
        ),
        _step(type: 'turn', modifier: 'right'),
      ];
      final previous = _resolve(
        steps: steps,
        banner: _activeBanner(
          routeVersion: 3,
          traversal: 0,
          maneuver: 1,
          source: NavBannerResolveSource.maneuverInstruction,
        ),
      );
      expect(previous.visible, isTrue);
      final next = _resolve(
        steps: steps,
        banner: _activeBanner(
          routeVersion: 4,
          traversal: 0,
          maneuver: 1,
          source: NavBannerResolveSource.maneuverInstruction,
        ),
        previous: previous,
        routeVersion: 4,
      );
      // New version can resolve again, but identity is not preserved from N.
      expect(next.routeVersion, 4);
      expect(next.visible, isTrue);
      final mismatch = _resolve(
        steps: steps,
        banner: _activeBanner(
          routeVersion: 3,
          traversal: 0,
          maneuver: 1,
          source: NavBannerResolveSource.maneuverInstruction,
        ),
        previous: previous,
        routeVersion: 4,
      );
      expect(
        mismatch.hiddenReason,
        DriverLaneHiddenReason.routeVersionMismatch,
      );
    });

    test('18: step advancement invalidates previous ownership', () {
      final steps = <DriverNavStep>[
        _step(
          banners: <DriverNavBannerStage>[
            _stage(
              sourceIndex: 0,
              distance: 100,
              primary: _view(
                components: <DriverNavBannerComponent>[
                  _laneComponent(directions: <String>['left'], active: false),
                  _laneComponent(directions: <String>['right'], active: true),
                ],
              ),
            ),
          ],
        ),
        _step(type: 'continue', instruction: 'Continue'),
        _step(type: 'arrive', instruction: 'Arrive'),
      ];
      final previous = _resolve(
        steps: steps,
        banner: _activeBanner(
          routeVersion: 1,
          traversal: 0,
          maneuver: 1,
          bannerIndex: 0,
        ),
      );
      expect(previous.visible, isTrue);
      final next = _resolve(
        steps: steps,
        banner: _activeBanner(
          routeVersion: 1,
          traversal: 1,
          maneuver: 2,
          source: NavBannerResolveSource.maneuverInstruction,
        ),
        previous: previous,
      );
      expect(next.traversalStepIndex, 1);
      expect(next.visible, isFalse);
    });

    test('19: temporary null-progress identity does not import other step', () {
      final steps = <DriverNavStep>[
        _step(
          banners: <DriverNavBannerStage>[
            _stage(
              sourceIndex: 0,
              distance: 200,
              primary: _view(
                components: <DriverNavBannerComponent>[
                  _laneComponent(
                    directions: <String>['straight'],
                    active: false,
                  ),
                  _laneComponent(directions: <String>['right'], active: true),
                ],
              ),
            ),
          ],
        ),
        _step(
          type: 'turn',
          modifier: 'right',
          intersections: <DriverNavIntersection>[
            _intersection(
              sourceIndex: 0,
              lanes: <DriverNavLaneGuidance>[
                _lane(indications: <String>['left'], valid: true),
                _lane(indications: <String>['uturn'], valid: true),
              ],
            ),
          ],
        ),
      ];
      final previous = _resolve(
        steps: steps,
        banner: _activeBanner(
          routeVersion: 1,
          traversal: 0,
          maneuver: 1,
          bannerIndex: 0,
        ),
      );
      expect(previous.source, DriverLaneGuidanceSource.bannerComponent);
      final held = _resolve(
        steps: steps,
        banner: _activeBanner(
          routeVersion: 1,
          traversal: 0,
          maneuver: 1,
          bannerIndex: 0,
        ),
        previous: previous,
      );
      expect(held.source, DriverLaneGuidanceSource.bannerComponent);
      expect(held.lanes.length, 2);
      expect(held.lanes.any((l) => l.directions.contains('uturn')), isFalse);
    });

    test('20: rejected package same version leaves identity unchanged', () {
      final steps = <DriverNavStep>[
        _step(
          intersections: <DriverNavIntersection>[
            _intersection(
              sourceIndex: 0,
              lanes: <DriverNavLaneGuidance>[
                _lane(indications: <String>['straight'], valid: false),
                _lane(indications: <String>['right'], valid: true),
              ],
            ),
          ],
        ),
        _step(type: 'turn', modifier: 'right'),
      ];
      final previous = _resolve(
        steps: steps,
        banner: _activeBanner(
          routeVersion: 2,
          traversal: 0,
          maneuver: 1,
          source: NavBannerResolveSource.maneuverInstruction,
        ),
      );
      final same = _resolve(
        steps: steps,
        banner: _activeBanner(
          routeVersion: 2,
          traversal: 0,
          maneuver: 1,
          source: NavBannerResolveSource.maneuverInstruction,
        ),
        previous: previous,
      );
      expect(same.routeVersion, 2);
      expect(same.visible, previous.visible);
      expect(same.lanes.length, previous.lanes.length);
    });

    test('21: destination reached hides lanes', () {
      final steps = <DriverNavStep>[
        _step(
          intersections: <DriverNavIntersection>[
            _intersection(
              sourceIndex: 0,
              lanes: <DriverNavLaneGuidance>[
                _lane(indications: <String>['straight'], valid: false),
                _lane(indications: <String>['right'], valid: true),
              ],
            ),
          ],
        ),
        _step(type: 'arrive'),
      ];
      final g = _resolve(
        steps: steps,
        banner: _activeBanner(
          routeVersion: 1,
          traversal: 0,
          maneuver: 1,
          source: NavBannerResolveSource.maneuverInstruction,
        ),
        destinationReached: true,
      );
      expect(g.visible, isFalse);
      expect(g.hiddenReason, DriverLaneHiddenReason.destinationReached);
    });

    test('22: left-to-right source order preserved', () {
      final steps = <DriverNavStep>[
        _step(
          intersections: <DriverNavIntersection>[
            _intersection(
              sourceIndex: 0,
              lanes: <DriverNavLaneGuidance>[
                _lane(indications: <String>['left'], valid: true),
                _lane(indications: <String>['straight'], valid: false),
                _lane(indications: <String>['right'], valid: true),
              ],
            ),
          ],
        ),
        _step(type: 'turn', modifier: 'left'),
      ];
      final g = _resolve(
        steps: steps,
        banner: _activeBanner(
          routeVersion: 1,
          traversal: 0,
          maneuver: 1,
          source: NavBannerResolveSource.maneuverInstruction,
        ),
      );
      expect(g.lanes.map((l) => l.directions.first).toList(), <String>[
        'left',
        'straight',
        'right',
      ]);
    });

    test('23: left-hand driving does not reverse order', () {
      final steps = <DriverNavStep>[
        _step(
          drivingSide: 'left',
          intersections: <DriverNavIntersection>[
            _intersection(
              sourceIndex: 0,
              lanes: <DriverNavLaneGuidance>[
                _lane(indications: <String>['left'], valid: true),
                _lane(indications: <String>['right'], valid: false),
              ],
            ),
          ],
        ),
        _step(type: 'turn', modifier: 'left', drivingSide: 'left'),
      ];
      final g = _resolve(
        steps: steps,
        banner: _activeBanner(
          routeVersion: 1,
          traversal: 0,
          maneuver: 1,
          source: NavBannerResolveSource.maneuverInstruction,
        ),
      );
      expect(g.lanes.first.directions.first, 'left');
      expect(g.lanes.last.directions.first, 'right');
    });

    test('24: roundabout without trustworthy lane data → hidden', () {
      final steps = <DriverNavStep>[
        _step(type: 'continue'),
        _step(type: 'roundabout', modifier: 'right', instruction: 'Exit 2'),
      ];
      final g = _resolve(
        steps: steps,
        banner: _activeBanner(
          routeVersion: 1,
          traversal: 0,
          maneuver: 1,
          source: NavBannerResolveSource.maneuverInstruction,
        ),
      );
      expect(g.visible, isFalse);
    });

    test('25: fork/ramp with trustworthy banner lanes → visible', () {
      final steps = <DriverNavStep>[
        _step(
          banners: <DriverNavBannerStage>[
            _stage(
              sourceIndex: 0,
              distance: 150,
              primary: _view(
                text: 'Keep left',
                components: <DriverNavBannerComponent>[
                  _laneComponent(directions: <String>['left'], active: true),
                  _laneComponent(
                    directions: <String>['straight'],
                    active: false,
                  ),
                ],
              ),
            ),
          ],
        ),
        _step(type: 'on ramp', modifier: 'left'),
      ];
      final g = _resolve(
        steps: steps,
        banner: _activeBanner(
          routeVersion: 1,
          traversal: 0,
          maneuver: 1,
          bannerIndex: 0,
        ),
      );
      expect(g.visible, isTrue);
      expect(g.source, DriverLaneGuidanceSource.bannerComponent);
    });

    test('26: malformed lane data → hidden', () {
      final steps = <DriverNavStep>[
        _step(
          intersections: <DriverNavIntersection>[
            _intersection(
              sourceIndex: 0,
              lanes: <DriverNavLaneGuidance>[
                _lane(indications: const <String>[], valid: true),
                _lane(indications: const <String>[], valid: false),
              ],
            ),
          ],
        ),
        _step(type: 'turn', modifier: 'right'),
      ];
      final g = _resolve(
        steps: steps,
        banner: _activeBanner(
          routeVersion: 1,
          traversal: 0,
          maneuver: 1,
          source: NavBannerResolveSource.maneuverInstruction,
        ),
      );
      expect(g.visible, isFalse);
    });

    test('27: more than eight lanes → hidden', () {
      final lanes = <DriverNavLaneGuidance>[
        for (var i = 0; i < 9; i++)
          _lane(
            indications: <String>[i.isEven ? 'straight' : 'right'],
            valid: i.isOdd,
          ),
      ];
      final steps = <DriverNavStep>[
        _step(
          intersections: <DriverNavIntersection>[
            _intersection(sourceIndex: 0, lanes: lanes),
          ],
        ),
        _step(type: 'turn', modifier: 'right'),
      ];
      final g = _resolve(
        steps: steps,
        banner: _activeBanner(
          routeVersion: 1,
          traversal: 0,
          maneuver: 1,
          source: NavBannerResolveSource.maneuverInstruction,
        ),
      );
      expect(g.visible, isFalse);
      expect(g.hiddenReason, DriverLaneHiddenReason.excessiveLaneCount);
    });

    test('28: two identical lanes, no meaningful difference → hidden', () {
      final steps = <DriverNavStep>[
        _step(
          intersections: <DriverNavIntersection>[
            _intersection(
              sourceIndex: 0,
              lanes: <DriverNavLaneGuidance>[
                _lane(indications: <String>['straight'], valid: true),
                _lane(indications: <String>['straight'], valid: true),
              ],
            ),
          ],
        ),
        _step(type: 'continue'),
      ];
      final g = _resolve(
        steps: steps,
        banner: _activeBanner(
          routeVersion: 1,
          traversal: 0,
          maneuver: 1,
          source: NavBannerResolveSource.maneuverInstruction,
        ),
      );
      expect(g.visible, isFalse);
      expect(g.hiddenReason, DriverLaneHiddenReason.noMeaningfulChoice);
    });

    test('29: active=true + valid=false contradiction → hidden', () {
      final steps = <DriverNavStep>[
        _step(
          intersections: <DriverNavIntersection>[
            _intersection(
              sourceIndex: 0,
              lanes: <DriverNavLaneGuidance>[
                _lane(indications: <String>['straight'], valid: true),
                _lane(
                  indications: <String>['right'],
                  valid: false,
                  active: true,
                ),
              ],
            ),
          ],
        ),
        _step(type: 'turn', modifier: 'right'),
      ];
      final g = _resolve(
        steps: steps,
        banner: _activeBanner(
          routeVersion: 1,
          traversal: 0,
          maneuver: 1,
          source: NavBannerResolveSource.maneuverInstruction,
        ),
      );
      expect(g.visible, isFalse);
      expect(g.hiddenReason, DriverLaneHiddenReason.contradictoryData);
    });

    test('30: feature flag false → no visible lane row', () {
      final steps = <DriverNavStep>[
        _step(
          intersections: <DriverNavIntersection>[
            _intersection(
              sourceIndex: 0,
              lanes: <DriverNavLaneGuidance>[
                _lane(indications: <String>['straight'], valid: false),
                _lane(indications: <String>['right'], valid: true),
              ],
            ),
          ],
        ),
        _step(type: 'turn', modifier: 'right'),
      ];
      final g = _resolve(
        steps: steps,
        banner: _activeBanner(
          routeVersion: 1,
          traversal: 0,
          maneuver: 1,
          source: NavBannerResolveSource.maneuverInstruction,
        ),
        featureEnabled: false,
      );
      expect(g.visible, isFalse);
      expect(g.hiddenReason, DriverLaneHiddenReason.featureDisabled);
      expect(mapResolvedLanesForDisplay(g), isEmpty);
    });

    test('34: no active banner stage + multiple intersections → hidden', () {
      final steps = <DriverNavStep>[
        _step(
          intersections: <DriverNavIntersection>[
            _intersection(
              sourceIndex: 0,
              lanes: <DriverNavLaneGuidance>[
                _lane(indications: <String>['straight'], valid: true),
              ],
            ),
            _intersection(
              sourceIndex: 1,
              lanes: <DriverNavLaneGuidance>[
                _lane(indications: <String>['left'], valid: true),
                _lane(indications: <String>['right'], valid: true),
              ],
            ),
          ],
        ),
        _step(type: 'turn', modifier: 'right'),
      ];
      final g = _resolve(
        steps: steps,
        banner: _activeBanner(
          routeVersion: 1,
          traversal: 0,
          maneuver: 1,
          source: NavBannerResolveSource.maneuverInstruction,
        ),
      );
      expect(g.visible, isFalse);
      expect(g.hiddenReason, DriverLaneHiddenReason.ambiguousIntersections);
    });

    test('35: departure uses traversal step 0, not maneuver step 1 lanes', () {
      final steps = <DriverNavStep>[
        _step(
          type: 'depart',
          banners: <DriverNavBannerStage>[
            _stage(
              sourceIndex: 0,
              distance: 400,
              primary: _view(
                text: 'Keep right',
                components: <DriverNavBannerComponent>[
                  _laneComponent(
                    directions: <String>['straight'],
                    active: false,
                  ),
                  _laneComponent(directions: <String>['right'], active: true),
                ],
              ),
            ),
          ],
          intersections: <DriverNavIntersection>[
            _intersection(
              sourceIndex: 0,
              lanes: <DriverNavLaneGuidance>[
                _lane(indications: <String>['straight'], valid: false),
                _lane(indications: <String>['right'], valid: true),
              ],
            ),
          ],
        ),
        _step(
          type: 'turn',
          modifier: 'right',
          distanceAlongRouteM: 600,
          intersections: <DriverNavIntersection>[
            _intersection(
              sourceIndex: 0,
              lanes: <DriverNavLaneGuidance>[
                _lane(indications: <String>['uturn'], valid: true),
                _lane(indications: <String>['left'], valid: true),
              ],
            ),
          ],
        ),
      ];
      final g = _resolve(
        steps: steps,
        banner: _activeBanner(
          routeVersion: 1,
          traversal: 0,
          maneuver: 1,
          bannerIndex: 0,
        ),
      );
      expect(g.traversalStepIndex, 0);
      expect(g.describedManeuverStepIndex, 1);
      expect(g.visible, isTrue);
      expect(g.source, DriverLaneGuidanceSource.bannerComponent);
      expect(g.lanes.any((l) => l.directions.contains('uturn')), isFalse);
    });

    test('diagnostics omit instruction text and coordinates', () {
      final steps = <DriverNavStep>[
        _step(
          intersections: <DriverNavIntersection>[
            _intersection(
              sourceIndex: 0,
              lanes: <DriverNavLaneGuidance>[
                _lane(indications: <String>['straight'], valid: false),
                _lane(indications: <String>['right'], valid: true),
              ],
            ),
          ],
        ),
        _step(type: 'turn', modifier: 'right', street: 'Teststraat'),
      ];
      final g = _resolve(
        steps: steps,
        banner: _activeBanner(
          routeVersion: 1,
          traversal: 0,
          maneuver: 1,
          source: NavBannerResolveSource.maneuverInstruction,
        ),
      );
      final line = formatNavLaneResolveDiag(g);
      expect(line, contains('[NAV_LANE_RESOLVE]'));
      expect(line, contains('source=intersection'));
      expect(line, isNot(contains('Teststraat')));
      expect(line, isNot(contains('50.85')));
    });
  });

  group('NAV-SIGNAL-P2B policy lane preserve', () {
    String trLocal({
      required String nl,
      required String en,
      required String fr,
      required String es,
    }) => en;

    const snapWithLanes = NavInstructionSnapshot(
      distanceToManeuverMeters: 120,
      primaryText: 'Turn right',
      secondaryText: '',
      maneuverType: 'turn',
      maneuverModifier: 'right',
      roadName: '',
      isHighwayLike: false,
      lanes: <DriverNavLaneGuidance>[
        DriverNavLaneGuidance(indications: <String>['straight'], valid: false),
        DriverNavLaneGuidance(indications: <String>['right'], valid: true),
      ],
      source: NavInstructionSource.banner,
    );

    test('31: policy disabled → lanes cleared', () {
      final out = applyDriverNavInstructionPolicyFilter(
        snapshot: snapWithLanes,
        policy: DriverNavInstructionPolicy(),
        liveRideActive: true,
        trustRouteSnap: true,
        trustInstruction: true,
        offRouteLikely: false,
        forwardProgress: true,
        predictionActive: false,
        routeConfidence: 90,
        tr: trLocal,
        laneGuidanceEnabled: false,
      );
      expect(out.lanes, isEmpty);
    });

    test('32: policy enabled + permitted instruction → lanes preserved', () {
      final out = applyDriverNavInstructionPolicyFilter(
        snapshot: snapWithLanes,
        policy: DriverNavInstructionPolicy(),
        liveRideActive: true,
        trustRouteSnap: true,
        trustInstruction: true,
        offRouteLikely: false,
        forwardProgress: true,
        predictionActive: false,
        routeConfidence: 90,
        tr: trLocal,
        laneGuidanceEnabled: true,
      );
      expect(out.primaryText, 'Turn right');
      expect(out.lanes.length, 2);
    });

    test('33: policy neutral fallback → lanes cleared', () {
      final out = applyDriverNavInstructionPolicyFilter(
        snapshot: snapWithLanes,
        policy: DriverNavInstructionPolicy(),
        liveRideActive: true,
        trustRouteSnap: true,
        trustInstruction: true,
        offRouteLikely: true,
        routeDeviationLikely: true,
        forwardProgress: true,
        predictionActive: false,
        routeConfidence: 20,
        tr: trLocal,
        laneGuidanceEnabled: true,
      );
      expect(out.lanes, isEmpty);
      expect(out.primaryText, isNot('Turn right'));
    });
  });
}
