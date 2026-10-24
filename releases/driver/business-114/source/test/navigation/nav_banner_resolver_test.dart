import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/navigation/driver_navigation_instruction_state.dart';
import 'package:fluxidi_tracking/navigation/driver_navigation_models.dart';
import 'package:fluxidi_tracking/navigation/driver_navigation_route_parser.dart';
import 'package:fluxidi_tracking/navigation/nav_engine/nav_banner_resolver.dart';

String _tr({
  required String nl,
  required String en,
  required String fr,
  required String es,
}) => nl;

DriverNavBannerView _view(
  String text, {
  List<DriverNavBannerComponent>? components,
}) {
  return DriverNavBannerView(
    text: text,
    components:
        components ??
        <DriverNavBannerComponent>[
          DriverNavBannerComponent(text: text, type: 'text'),
        ],
  );
}

DriverNavBannerStage _stage({
  required int sourceIndex,
  required double distance,
  required String primary,
  String? secondary,
  String? sub,
}) {
  return DriverNavBannerStage(
    sourceIndex: sourceIndex,
    distanceAlongGeometry: distance,
    primary: _view(primary),
    secondary: secondary == null ? null : _view(secondary),
    sub: sub == null ? null : _view(sub),
  );
}

DriverNavStep _step({
  required String type,
  required String modifier,
  required String instruction,
  double distanceAlongRouteM = 100,
  List<DriverNavBannerStage> banners = const <DriverNavBannerStage>[],
  String street = '',
  String? exitNumber,
  String? destinationText,
  String? roadRef,
  DriverNavBannerInstruction? legacyBanner,
}) {
  return DriverNavStep(
    lat: 50.85,
    lon: 4.35,
    instruction: instruction,
    street: street,
    type: type,
    modifier: modifier,
    distanceAlongRouteM: distanceAlongRouteM,
    distanceM: 1000,
    banner:
        legacyBanner ??
        (banners.isEmpty ? null : banners.first.asLegacyInstruction),
    bannerInstructions: banners,
    exitNumber: exitNumber,
    destinationText: destinationText,
    roadRef: roadRef,
  );
}

DriverActiveBanner _resolve({
  required List<DriverNavStep> steps,
  required int upcoming,
  double? remaining,
  int routeVersion = 1,
  DriverActiveBanner? previous,
  bool destinationReached = false,
  bool clearBanners = false,
}) {
  return resolveDriverActiveBanner(
    DriverBannerResolveInput(
      routeSteps: steps,
      upcomingManeuverStepIndex: upcoming,
      bannerRemainingAlongRouteM: remaining,
      routeVersion: routeVersion,
      previous: previous,
      destinationReached: destinationReached,
      clearBanners: clearBanners,
      tr: _tr,
    ),
  );
}

void main() {
  group('NAV-SIGNAL-P1B banner ownership', () {
    final threeBannerStep = _step(
      type: 'depart',
      modifier: '',
      instruction: 'Depart',
      distanceAlongRouteM: 15,
      banners: <DriverNavBannerStage>[
        _stage(sourceIndex: 0, distance: 800, primary: 'Prepare right'),
        _stage(sourceIndex: 1, distance: 300, primary: 'Approach right'),
        _stage(sourceIndex: 2, distance: 70, primary: 'Turn right now'),
      ],
    );
    final turnStep = _step(
      type: 'turn',
      modifier: 'right',
      instruction: 'Turn right onto Teststraat',
      street: 'Teststraat',
      distanceAlongRouteM: 600,
    );
    final steps = <DriverNavStep>[threeBannerStep, turnStep];

    test('1: departure ownership uses banners 0, maneuver 1, distance 1', () {
      final ownership = resolveDriverBannerOwnership(
        upcomingManeuverStepIndex: 0,
        routeStepCount: 2,
      );
      expect(ownership.traversalStepIndex, 0);
      expect(ownership.describedManeuverStepIndex, 1);
      expect(ownership.distanceTargetStepIndex, 1);
      expect(ownership.isDepartureSpecialCase, isTrue);

      final remaining = computeBannerRemainingAlongRouteM(
        routeSteps: steps,
        ownership: ownership,
        trustedRouteProgressM: 0,
      );
      expect(remaining, 600);

      final active = _resolve(steps: steps, upcoming: 0, remaining: remaining);
      expect(active.traversalStepIndex, 0);
      expect(active.maneuverStepIndex, 1);
      expect(active.distanceTargetStepIndex, 1);
      expect(active.isDepartureSpecialCase, isTrue);
      expect(active.maneuverType, 'turn');
      expect(active.maneuverModifier, 'right');
      // 600m <= 800m → prepare stage only (not 300/70).
      expect(active.source, NavBannerResolveSource.mapboxBanner);
      expect(active.bannerIndex, 0);
      expect(active.primaryText, 'Prepare right');
    });

    test('2: departure 15m to depart but ~585m to turn — no 70/300 stages', () {
      final ownership = resolveDriverBannerOwnership(
        upcomingManeuverStepIndex: 0,
        routeStepCount: 2,
      );
      // Progress near depart point; remaining to turn still ~585m.
      final remaining = computeBannerRemainingAlongRouteM(
        routeSteps: steps,
        ownership: ownership,
        trustedRouteProgressM: 15,
      );
      expect(remaining, 585);
      final active = _resolve(steps: steps, upcoming: 0, remaining: remaining);
      // Old bug used ~15m to depart and activated 70m. Distance-to-turn must not.
      expect(active.bannerIndex, 0);
      expect(active.primaryText, 'Prepare right');
      expect(active.bannerIndex, isNot(1));
      expect(active.bannerIndex, isNot(2));
    });

    test('3: departure crossing first 800m threshold activates stage 0', () {
      final active = _resolve(steps: steps, upcoming: 0, remaining: 750);
      expect(active.source, NavBannerResolveSource.mapboxBanner);
      expect(active.bannerIndex, 0);
      expect(active.primaryText, 'Prepare right');
      expect(active.maneuverType, 'turn');
      expect(active.maneuverModifier, 'right');
    });

    test('4: upcoming N>=1 → traversal N-1, maneuver N, distance N', () {
      final ownership = resolveDriverBannerOwnership(
        upcomingManeuverStepIndex: 1,
        routeStepCount: 2,
      );
      expect(ownership.traversalStepIndex, 0);
      expect(ownership.describedManeuverStepIndex, 1);
      expect(ownership.distanceTargetStepIndex, 1);
      expect(ownership.isDepartureSpecialCase, isFalse);

      final active = _resolve(steps: steps, upcoming: 1, remaining: 250);
      expect(active.traversalStepIndex, 0);
      expect(active.maneuverStepIndex, 1);
      expect(active.distanceTargetStepIndex, 1);
      expect(active.bannerIndex, 1);
      expect(active.primaryText, 'Approach right');
    });

    test('5: one-step route — no OOB, safe fallback', () {
      final only = <DriverNavStep>[
        _step(
          type: 'arrive',
          modifier: '',
          instruction: 'You have arrived',
          distanceAlongRouteM: 40,
          banners: <DriverNavBannerStage>[
            _stage(sourceIndex: 0, distance: 100, primary: 'Destination'),
          ],
        ),
      ];
      final ownership = resolveDriverBannerOwnership(
        upcomingManeuverStepIndex: 0,
        routeStepCount: 1,
      );
      expect(ownership.traversalStepIndex, 0);
      expect(ownership.describedManeuverStepIndex, 0);
      expect(ownership.distanceTargetStepIndex, 0);
      expect(ownership.isDepartureSpecialCase, isFalse);
      expect(ownership.isFinalArrival, isTrue);

      final active = _resolve(steps: only, upcoming: 0, remaining: 40);
      expect(active.maneuverType, 'arrive');
      expect(active.maneuverStepIndex, 0);
      expect(active.primaryText, 'Destination');
    });

    test('6: remaining before largest threshold → no Mapbox stage', () {
      final far = _resolve(steps: steps, upcoming: 1, remaining: 1000);
      expect(far.bannerIndex, isNull);
      expect(far.source, isNot(NavBannerResolveSource.mapboxBanner));
      expect(far.primaryText.trim().isNotEmpty, isTrue);
    });

    test('7: multi-threshold jump selects most specific stage', () {
      final previous = _resolve(steps: steps, upcoming: 1, remaining: 750);
      expect(previous.bannerIndex, 0);
      final jumped = _resolve(
        steps: steps,
        upcoming: 1,
        remaining: 40,
        previous: previous,
      );
      expect(jumped.bannerIndex, 2);
      expect(jumped.primaryText, 'Turn right now');
      expect(jumped.transition, NavBannerResolveTransition.stageAdvance);
    });

    test('8: duplicate threshold uses source-order tie-break', () {
      final dup = _step(
        type: 'continue',
        modifier: '',
        instruction: 'Continue',
        banners: <DriverNavBannerStage>[
          _stage(sourceIndex: 0, distance: 300, primary: 'First at 300'),
          _stage(sourceIndex: 1, distance: 300, primary: 'Second at 300'),
        ],
      );
      final route = <DriverNavStep>[dup, turnStep];
      final active = _resolve(steps: route, upcoming: 1, remaining: 250);
      // Sorted by distance desc then sourceIndex asc; same distance → lower
      // sourceIndex is earlier rank; most-specific eligible still prefers
      // higher rank among eligible — both eligible, higher rank wins (source 1).
      expect(active.bannerIndex, 1);
      expect(active.primaryText, 'Second at 300');
    });

    test('9: negative distance rejected', () {
      final route = <DriverNavStep>[
        _step(
          type: 'continue',
          modifier: '',
          instruction: 'Continue',
          banners: <DriverNavBannerStage>[
            _stage(sourceIndex: 0, distance: -10, primary: 'Bad'),
            _stage(sourceIndex: 1, distance: 200, primary: 'Good'),
          ],
        ),
        turnStep,
      ];
      final active = _resolve(steps: route, upcoming: 1, remaining: 100);
      expect(active.primaryText, 'Good');
      expect(active.bannerIndex, 1);
    });

    test('10: NaN distance rejected', () {
      final route = <DriverNavStep>[
        _step(
          type: 'continue',
          modifier: '',
          instruction: 'Continue',
          banners: <DriverNavBannerStage>[
            DriverNavBannerStage(
              sourceIndex: 0,
              distanceAlongGeometry: double.nan,
              primary: _view('NaN'),
            ),
            _stage(sourceIndex: 1, distance: 200, primary: 'Good'),
          ],
        ),
        turnStep,
      ];
      final active = _resolve(steps: route, upcoming: 1, remaining: 100);
      expect(active.primaryText, 'Good');
    });

    test('11: infinite distance rejected', () {
      final route = <DriverNavStep>[
        _step(
          type: 'continue',
          modifier: '',
          instruction: 'Continue',
          banners: <DriverNavBannerStage>[
            _stage(sourceIndex: 0, distance: double.infinity, primary: 'Inf'),
            _stage(sourceIndex: 1, distance: 200, primary: 'Good'),
          ],
        ),
        turnStep,
      ];
      final active = _resolve(steps: route, upcoming: 1, remaining: 100);
      expect(active.primaryText, 'Good');
    });

    test('12: null trusted progress — no new Mapbox stage', () {
      final active = _resolve(steps: steps, upcoming: 0, remaining: null);
      expect(active.bannerIndex, isNull);
      expect(active.source, isNot(NavBannerResolveSource.mapboxBanner));
      expect(active.trustedProgress, isFalse);
      expect(active.maneuverType, 'turn');
    });

    test('13: temporary null progress keeps valid Mapbox stage', () {
      final previous = _resolve(steps: steps, upcoming: 1, remaining: 250);
      expect(previous.bannerIndex, 1);
      final held = _resolve(
        steps: steps,
        upcoming: 1,
        remaining: null,
        previous: previous,
      );
      expect(held.bannerIndex, 1);
      expect(held.primaryText, 'Approach right');
      expect(held.transition, NavBannerResolveTransition.none);
      expect(held.trustedProgress, isFalse);
    });

    test('14: legacy DriverNavStep.banner cannot override resolver text', () {
      final maneuver = _step(
        type: 'turn',
        modifier: 'right',
        instruction: 'Turn right onto Teststraat',
        street: 'Teststraat',
        distanceAlongRouteM: 600,
        legacyBanner: const DriverNavBannerInstruction(
          primaryText: 'LEGACY OVERRIDE',
          secondaryText: 'Wrong road',
        ),
      );
      final route = <DriverNavStep>[threeBannerStep, maneuver];
      final active = _resolve(steps: route, upcoming: 0, remaining: 250);
      expect(active.primaryText, 'Approach right');
      expect(active.primaryText, isNot('LEGACY OVERRIDE'));

      final snap = NavInstructionSnapshot(
        distanceToManeuverMeters: 250,
        primaryText: active.primaryText,
        secondaryText: active.secondaryText,
        subText: active.subText,
        maneuverType: active.maneuverType,
        maneuverModifier: active.maneuverModifier,
        roadName: active.roadName,
        exitNumber: active.exitNumber,
        destinationText: active.destinationText,
        roadRef: active.roadRef,
        isHighwayLike: active.isHighwayLike,
        lanes: active.lanes,
        source: NavInstructionSource.banner,
      );
      final display = applyDriverNavInstructionDisplayLines(
        snapshot: snap,
        step: maneuver,
      );
      expect(display.primaryText, isNot(contains('LEGACY')));
      expect(display.maneuverModifier, 'right');
    });

    test(
      '15: policy cannot combine banner text with another step modifier',
      () {
        final uturn = _step(
          type: 'turn',
          modifier: 'uturn',
          instruction: 'Make a U-turn',
          distanceAlongRouteM: 2000,
        );
        final route = <DriverNavStep>[threeBannerStep, turnStep, uturn];
        final active = _resolve(steps: route, upcoming: 1, remaining: 40);
        expect(active.primaryText, 'Turn right now');
        expect(active.maneuverModifier, 'right');
        expect(active.maneuverModifier.toLowerCase(), isNot(contains('uturn')));
      },
    );

    test('16: pre-threshold fallback does not block later stage 0', () {
      final fallback = _resolve(steps: steps, upcoming: 1, remaining: 1000);
      expect(fallback.bannerIndex, isNull);
      final later = _resolve(
        steps: steps,
        upcoming: 1,
        remaining: 750,
        previous: fallback,
      );
      expect(later.bannerIndex, 0);
      expect(later.primaryText, 'Prepare right');
    });

    test('17: rejected/stale route version leaves active banner unchanged', () {
      final previous = _resolve(
        steps: steps,
        upcoming: 1,
        remaining: 50,
        routeVersion: 3,
      );
      // Same routeVersion (rejected package did not bump content version).
      final same = _resolve(
        steps: steps,
        upcoming: 1,
        remaining: 50,
        routeVersion: 3,
        previous: previous,
      );
      expect(same.routeVersion, 3);
      expect(same.bannerIndex, previous.bannerIndex);
      expect(same.primaryText, previous.primaryText);
      expect(same.transition, NavBannerResolveTransition.none);
    });

    test('18: accepted reroute invalidates old route-version identity', () {
      final n = _resolve(
        steps: steps,
        upcoming: 1,
        remaining: 50,
        routeVersion: 3,
      );
      final n1 = _resolve(
        steps: steps,
        upcoming: 1,
        remaining: 900,
        routeVersion: 4,
        previous: n,
      );
      expect(n1.routeVersion, 4);
      expect(n1.transition, NavBannerResolveTransition.routeChange);
      // 900m pre-threshold on new version → fallback, not stale stage.
      expect(n1.bannerIndex, isNull);
      expect(n1.source, isNot(NavBannerResolveSource.mapboxBanner));
    });

    test('19: destination reached clears pending banner', () {
      final previous = _resolve(steps: steps, upcoming: 1, remaining: 200);
      final done = _resolve(
        steps: steps,
        upcoming: 1,
        remaining: 200,
        previous: previous,
        destinationReached: true,
      );
      expect(done.hasInstruction, isFalse);
      expect(done.bannerIndex, isNull);
      expect(done.transition, NavBannerResolveTransition.routeChange);
    });

    test('GPS fluctuation does not regress Mapbox stage', () {
      final mid = _resolve(steps: steps, upcoming: 1, remaining: 250);
      expect(mid.bannerIndex, 1);
      final fluctuated = _resolve(
        steps: steps,
        upcoming: 1,
        remaining: 320,
        previous: mid,
      );
      expect(fluctuated.bannerIndex, 1);
      expect(fluctuated.primaryText, 'Approach right');
    });

    test('step change resets stage ownership', () {
      final previous = _resolve(steps: steps, upcoming: 1, remaining: 50);
      final nextTraversal = _step(
        type: 'continue',
        modifier: '',
        instruction: 'Continue',
        banners: <DriverNavBannerStage>[
          _stage(sourceIndex: 0, distance: 400, primary: 'Next prepare'),
        ],
      );
      final arrive = _step(
        type: 'arrive',
        modifier: '',
        instruction: 'You have arrived',
        distanceAlongRouteM: 2000,
      );
      final route = <DriverNavStep>[threeBannerStep, nextTraversal, arrive];
      final next = _resolve(
        steps: route,
        upcoming: 2,
        remaining: 350,
        previous: previous,
      );
      expect(next.traversalStepIndex, 1);
      expect(next.maneuverStepIndex, 2);
      expect(next.transition, NavBannerResolveTransition.stepChange);
      expect(next.primaryText, 'Next prepare');
    });

    test('missing banners fall back to maneuver instruction', () {
      final route = <DriverNavStep>[
        _step(type: 'continue', modifier: '', instruction: 'Continue on N5'),
        _step(
          type: 'turn',
          modifier: 'left',
          instruction: 'Turn left onto Kerkstraat',
          street: 'Kerkstraat',
        ),
      ];
      final active = _resolve(steps: route, upcoming: 1, remaining: 120);
      expect(active.source, NavBannerResolveSource.maneuverInstruction);
      expect(active.primaryText, 'Turn left onto Kerkstraat');
      expect(active.maneuverModifier, 'left');
      expect(active.bannerIndex, isNull);
    });

    test('primary secondary sub preserved on active stage', () {
      final route = <DriverNavStep>[
        _step(
          type: 'continue',
          modifier: '',
          instruction: 'Continue',
          banners: <DriverNavBannerStage>[
            _stage(
              sourceIndex: 0,
              distance: 200,
              primary: 'Exit 5',
              secondary: 'Brussel',
              sub: 'Keep right',
            ),
          ],
        ),
        turnStep,
      ];
      final active = _resolve(steps: route, upcoming: 1, remaining: 100);
      expect(active.primaryText, 'Exit 5');
      expect(active.secondaryText, 'Brussel');
      expect(active.subText, 'Keep right');
    });

    test('diagnostics omit instruction text and include ownership fields', () {
      final active = _resolve(steps: steps, upcoming: 0, remaining: 750);
      final line = formatNavBannerResolveDiag(
        banner: active,
        upcomingIndex: 0,
        remainingAlongRouteM: 750,
      );
      expect(line, contains('[NAV_BANNER_RESOLVE]'));
      expect(line, contains('upcomingIndex=0'));
      expect(line, contains('traversalStep=0'));
      expect(line, contains('maneuverStep=1'));
      expect(line, contains('distanceTargetStep=1'));
      expect(line, contains('departureSpecialCase=true'));
      expect(line, contains('trustedProgress=true'));
      expect(line, contains('remainingAlongRouteM=750'));
      expect(line, contains('source=mapbox_banner'));
      expect(line, isNot(contains('Prepare right')));
      expect(line, isNot(contains('Teststraat')));
    });

    test('trusted remaining uses distance target, not depart step', () {
      final ownership = resolveDriverBannerOwnership(
        upcomingManeuverStepIndex: 0,
        routeStepCount: 2,
      );
      expect(
        computeBannerRemainingAlongRouteM(
          routeSteps: steps,
          ownership: ownership,
          trustedRouteProgressM: 100,
        ),
        500,
      );
      expect(
        computeBannerRemainingAlongRouteM(
          routeSteps: steps,
          ownership: ownership,
          trustedRouteProgressM: null,
        ),
        isNull,
      );
    });

    test('clear banners suppresses previous stage identity', () {
      final previous = _resolve(steps: steps, upcoming: 1, remaining: 50);
      final cleared = _resolve(
        steps: steps,
        upcoming: 1,
        remaining: 50,
        previous: previous,
        clearBanners: true,
      );
      expect(cleared.hasInstruction, isFalse);
      expect(cleared.bannerIndex, isNull);
    });
  });

  group('NAV-SIGNAL-P1B presentation + legacy bypass', () {
    test('activation seed must not mix depart type with next-turn banner', () {
      // Models the post-accept home-state seed: empty until first resolve.
      const seededType = '';
      const seededInstruction = '';
      expect(seededType, isEmpty);
      expect(seededInstruction, isEmpty);

      final depart = _step(
        type: 'depart',
        modifier: '',
        instruction: 'Head north',
        distanceAlongRouteM: 15,
        banners: <DriverNavBannerStage>[
          _stage(sourceIndex: 0, distance: 800, primary: 'Turn right onto N5'),
        ],
      );
      final turn = _step(
        type: 'turn',
        modifier: 'right',
        instruction: 'Turn right onto N5',
        street: 'N5',
        distanceAlongRouteM: 600,
      );
      final active = _resolve(
        steps: <DriverNavStep>[depart, turn],
        upcoming: 0,
        remaining: 750,
      );
      expect(active.maneuverType, 'turn');
      expect(active.maneuverType, isNot('depart'));
      expect(active.primaryText, 'Turn right onto N5');
    });

    test('legacy banner on maneuver step ignored by display lines', () {
      final step = _step(
        type: 'turn',
        modifier: 'left',
        instruction: 'Turn left onto Markt',
        street: 'Markt',
        legacyBanner: const DriverNavBannerInstruction(
          primaryText: 'FROM_LEGACY_BANNER',
          secondaryText: 'ShouldNotWin',
        ),
      );
      const snap = NavInstructionSnapshot(
        distanceToManeuverMeters: 80,
        primaryText: 'Resolved primary',
        secondaryText: 'Resolved secondary',
        maneuverType: 'turn',
        maneuverModifier: 'left',
        roadName: 'Markt',
        isHighwayLike: false,
        lanes: <DriverNavLaneGuidance>[],
        source: NavInstructionSource.banner,
      );
      final display = applyDriverNavInstructionDisplayLines(
        snapshot: snap,
        step: step,
      );
      expect(display.primaryText, isNot(contains('FROM_LEGACY')));
      expect(display.maneuverModifier, 'left');
      expect(driverStepManeuverTargetLabel(step), 'Markt');
      expect(driverNavManeuverTargetSource(step), isNot('banner'));
    });
  });

  group('NAV-SIGNAL-P1 banner parser', () {
    test('malformed banner item skipped without rejecting route', () {
      final parsed = parseDriverDirectionsResponse(
        response: <String, dynamic>{
          'routes': <dynamic>[
            <String, dynamic>{
              'distance': 1000,
              'duration': 120,
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
                      'name': 'Teststraat',
                      'distance': 500,
                      'duration': 60,
                      'maneuver': <String, dynamic>{
                        'location': <dynamic>[4.35, 50.85],
                        'type': 'turn',
                        'modifier': 'right',
                        'instruction': 'Turn right',
                      },
                      'bannerInstructions': <dynamic>[
                        'not-a-map',
                        <String, dynamic>{
                          'primary': <String, dynamic>{'text': 'Bad'},
                        },
                        <String, dynamic>{
                          'distanceAlongGeometry': 120,
                          'primary': <String, dynamic>{
                            'text': 'Good',
                            'components': <dynamic>[
                              <String, dynamic>{'text': 'Good', 'type': 'text'},
                            ],
                          },
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
      expect(parsed.navSteps, isNotEmpty);
      expect(parsed.navSteps.first.bannerInstructions.length, 1);
      expect(
        parsed.navSteps.first.bannerInstructions.first.primary?.displayText,
        'Good',
      );
    });

    test('multiple components remain ordered', () {
      final parsed = parseDriverDirectionsResponse(
        response: <String, dynamic>{
          'routes': <dynamic>[
            <String, dynamic>{
              'distance': 800,
              'duration': 90,
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
                      'name': 'N5',
                      'distance': 400,
                      'maneuver': <String, dynamic>{
                        'location': <dynamic>[4.35, 50.85],
                        'type': 'turn',
                        'modifier': 'right',
                        'instruction': 'Turn right',
                      },
                      'bannerInstructions': <dynamic>[
                        <String, dynamic>{
                          'distanceAlongGeometry': 200,
                          'primary': <String, dynamic>{
                            'text': 'N5 Teststraat',
                            'components': <dynamic>[
                              <String, dynamic>{
                                'text': 'N5',
                                'type': 'icon',
                                'imageBaseURL':
                                    'https://example.invalid/shields/',
                                'abbr': 'N5',
                                'abbr_priority': 0,
                              },
                              <String, dynamic>{
                                'text': 'Teststraat',
                                'type': 'text',
                              },
                            ],
                          },
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
      final components =
          parsed.navSteps.first.bannerInstructions.first.primary!.components;
      expect(components.length, 2);
      expect(components[0].type, 'icon');
      expect(components[0].text, 'N5');
      expect(components[1].type, 'text');
      expect(parsed.navSteps.first.banner?.primaryText, 'N5 Teststraat');
    });

    test('all banner stages preserved in order', () {
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
                      'distance': 900,
                      'maneuver': <String, dynamic>{
                        'location': <dynamic>[4.35, 50.85],
                        'type': 'turn',
                        'modifier': 'right',
                        'instruction': 'Turn right',
                      },
                      'bannerInstructions': <dynamic>[
                        <String, dynamic>{
                          'distanceAlongGeometry': 800,
                          'primary': <String, dynamic>{'text': 'A'},
                        },
                        <String, dynamic>{
                          'distanceAlongGeometry': 300,
                          'primary': <String, dynamic>{'text': 'B'},
                        },
                        <String, dynamic>{
                          'distanceAlongGeometry': 70,
                          'primary': <String, dynamic>{'text': 'C'},
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
      final stages = parsed.navSteps.first.bannerInstructions;
      expect(stages.map((s) => s.sourceIndex).toList(), <int>[0, 1, 2]);
      expect(stages.map((s) => s.distanceAlongGeometry).toList(), <double>[
        800,
        300,
        70,
      ]);
    });
  });
}
