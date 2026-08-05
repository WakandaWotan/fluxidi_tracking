// NAV-MANEUVER-OWNER-REBASE-1
//
// End-to-end proofs through the production instruction pipeline: guidance
// fields survive from route step to snapshot to sign, the activation windows
// really gate what the driver sees, and a reroute never lets an old maneuver
// return.

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/navigation/driver_navigation_instruction_state.dart';
import 'package:fluxidi_tracking/navigation/driver_navigation_models.dart';
import 'package:fluxidi_tracking/navigation/nav_engine/nav_banner_resolver.dart';
import 'package:fluxidi_tracking/navigation/nav_engine/nav_lane_resolver.dart';
import 'package:fluxidi_tracking/navigation/nav_engine/nav_maneuver_owner.dart';
import 'package:fluxidi_tracking/navigation/presentation/maneuver_presentation.dart';
import 'package:fluxidi_tracking/navigation/presentation/nav_sign_resolver.dart';

String _tr({
  required String nl,
  required String en,
  required String fr,
  required String es,
}) => nl;

const List<DriverLonLat> _routeCoords = <DriverLonLat>[
  DriverLonLat(4.35, 50.85),
  DriverLonLat(4.36, 50.86),
];

DriverNavStep _step({
  required String type,
  required double along,
  String modifier = '',
  String instruction = 'Ga verder',
  String? exitNumber,
  String? drivingSide,
  double? bearingBefore,
  double? bearingAfter,
  List<DriverNavBannerStage> banners = const <DriverNavBannerStage>[],
}) {
  return DriverNavStep(
    lat: 50.85,
    lon: 4.35,
    instruction: instruction,
    street: 'Teststraat',
    type: type,
    modifier: modifier,
    distanceAlongRouteM: along,
    exitNumber: exitNumber,
    drivingSide: drivingSide,
    bearingBefore: bearingBefore,
    bearingAfter: bearingAfter,
    bannerInstructions: banners,
  );
}

/// depart at 0, the maneuver under test at 1000, arrival at 2000.
List<DriverNavStep> _routeWith(DriverNavStep maneuver) => <DriverNavStep>[
  _step(type: 'depart', along: 0, instruction: 'Vertrek'),
  maneuver,
  _step(type: 'arrive', along: 2000, instruction: 'Bestemming'),
];

typedef _Run = ({
  NavInstructionSnapshot snapshot,
  DriverActiveBanner? activeBanner,
  DriverResolvedLaneGuidance laneGuidance,
  NavVisibleManeuverOwner? maneuverOwner,
  double? bannerRemainingAlongRouteM,
  double displayDistanceToUpcomingManeuverM,
});

_Run _run({
  required List<DriverNavStep> steps,
  required double progressM,
  int nextStepIndex = 0,
  int routeVersion = 1,
  int progressEpoch = 1,
  NavVisibleManeuverOwner? previousOwner,
  DriverActiveBanner? previousBanner,
  bool destinationReached = false,
}) {
  return buildDriverNavInstructionPresentation(
    routeSteps: steps,
    nextStepIndex: nextStepIndex,
    // Far from every step coordinate, so only matched route progress can
    // advance the step index.
    posLat: 50.0,
    posLon: 4.0,
    lastRouteSnap: DriverRouteSnap(
      point: const DriverLonLat(4.35, 50.85),
      distanceFromRouteM: 1.0,
      distanceAlongRouteM: progressM,
      segmentIndex: 0,
      segmentT: 0.5,
    ),
    routeCoords: _routeCoords,
    useMatchedVisual: true,
    tr: _tr,
    routeVersion: routeVersion,
    previousActiveBanner: previousBanner,
    previousManeuverOwner: previousOwner,
    progressEpoch: progressEpoch,
    destinationReached: destinationReached,
  );
}

/// Remaining distance to the maneuver at 1000 m along the route.
_Run _atDistance(DriverNavStep maneuver, double remaining) =>
    _run(steps: _routeWith(maneuver), progressM: 1000 - remaining);

NavSignManeuver _signOf(NavInstructionSnapshot snapshot) =>
    buildResponsiveManeuverPresentation(
      snapshot: snapshot,
      tr: _tr,
      languageCode: 'nl',
    ).signManeuver;

void main() {
  group('activation windows reach production', () {
    test('an ordinary turn is withheld above 200 m and shown at 200 m', () {
      final turn = _step(
        type: 'turn',
        modifier: 'left',
        along: 1000,
        instruction: 'Sla linksaf',
      );

      final tooFar = _atDistance(turn, 250);
      expect(tooFar.maneuverOwner!.activationClass,
          NavManeuverActivationClass.ordinary);
      expect(tooFar.maneuverOwner!.isActive, isFalse);
      expect(tooFar.snapshot.followRouteForced, isTrue);
      expect(_signOf(tooFar.snapshot), NavSignManeuver.followRoute);

      final inWindow = _atDistance(turn, 200);
      expect(inWindow.maneuverOwner!.isActive, isTrue);
      expect(inWindow.snapshot.followRouteForced, isFalse);
      expect(_signOf(inWindow.snapshot), NavSignManeuver.turnLeft);
    });

    test('a roundabout is withheld above 300 m and shown at 300 m', () {
      final roundabout = _step(
        type: 'roundabout',
        along: 1000,
        exitNumber: '2',
        instruction: 'Neem de 2de afslag',
      );

      final tooFar = _atDistance(roundabout, 350);
      expect(tooFar.maneuverOwner!.activationClass,
          NavManeuverActivationClass.complex);
      expect(tooFar.snapshot.followRouteForced, isTrue);
      expect(_signOf(tooFar.snapshot), NavSignManeuver.followRoute);

      final inWindow = _atDistance(roundabout, 300);
      expect(inWindow.snapshot.followRouteForced, isFalse);
      expect(_signOf(inWindow.snapshot), NavSignManeuver.roundaboutExit2);
    });

    test('a motorway exit gets the complex window, not the ordinary one', () {
      final offRamp = _step(
        type: 'off ramp',
        modifier: 'right',
        along: 1000,
        instruction: 'Neem de afrit',
      );
      expect(_atDistance(offRamp, 300).snapshot.followRouteForced, isFalse);
      expect(_atDistance(offRamp, 301).snapshot.followRouteForced, isTrue);
      expect(_signOf(_atDistance(offRamp, 300).snapshot),
          NavSignManeuver.exitRight);
    });

    test('the withheld banner still reads as plain follow-route', () {
      final turn = _step(
        type: 'turn',
        modifier: 'right',
        along: 1000,
        instruction: 'Sla rechtsaf',
      );
      final p = buildResponsiveManeuverPresentation(
        snapshot: _atDistance(turn, 400).snapshot,
        tr: _tr,
        languageCode: 'nl',
      );
      expect(p.primaryInstruction, 'Volg de route');
      expect(p.maneuverVisual, ManeuverVisual.followRoute);
      expect(p.signManeuver, NavSignManeuver.followRoute);
    });

    test('arrival is owned far outside any junction window', () {
      final run = _run(
        steps: _routeWith(
          _step(type: 'turn', modifier: 'left', along: 1000),
        ),
        progressM: 1100,
      );
      expect(run.maneuverOwner!.maneuverType, 'arrive');
      expect(run.maneuverOwner!.activationClass,
          NavManeuverActivationClass.alwaysActive);
      expect(run.snapshot.followRouteForced, isFalse);
    });

    test('timing does not depend on vehicle speed', () {
      final turn = _step(
        type: 'turn',
        modifier: 'left',
        along: 1000,
        instruction: 'Sla linksaf',
      );
      final base = _atDistance(turn, 150).snapshot;

      NavInstructionSnapshot filtered(double speedKmh) =>
          applyDriverNavR1InstructionSafetyFilter(
            snapshot: base,
            routeSnappedReliable: true,
            tr: _tr,
            speedKmh: speedKmh,
          );

      final standingStill = filtered(0);
      final motorway = filtered(130);
      expect(standingStill.followRouteForced, motorway.followRouteForced);
      expect(standingStill.maneuverType, motorway.maneuverType);
      expect(standingStill.maneuverModifier, motorway.maneuverModifier);
      expect(_signOf(standingStill), _signOf(motorway));
    });
  });

  group('consecutive maneuvers', () {
    _Run advance(List<DriverNavStep> steps, double progressM, _Run? previous) =>
        _run(
          steps: steps,
          progressM: progressM,
          nextStepIndex: previous?.maneuverOwner?.traversalStepIndex ?? 0,
          progressEpoch: (previous?.maneuverOwner?.progressEpoch ?? 0) + 1,
          previousOwner: previous?.maneuverOwner,
          previousBanner: previous?.activeBanner,
        );

    test('a turn followed by a roundabout hands over exactly once', () {
      final steps = <DriverNavStep>[
        _step(type: 'depart', along: 0, instruction: 'Vertrek'),
        _step(
          type: 'turn',
          modifier: 'left',
          along: 1000,
          instruction: 'Sla linksaf',
        ),
        _step(
          type: 'roundabout',
          along: 1400,
          exitNumber: '3',
          instruction: 'Neem de 3de afslag',
        ),
        _step(type: 'arrive', along: 2000, instruction: 'Bestemming'),
      ];

      final far = advance(steps, 700, null); // 300 m to the turn
      expect(far.snapshot.followRouteForced, isTrue);

      final atTurn = advance(steps, 900, far); // 100 m to the turn
      expect(atTurn.maneuverOwner!.maneuverType, 'turn');
      expect(atTurn.snapshot.followRouteForced, isFalse);
      expect(_signOf(atTurn.snapshot), NavSignManeuver.turnLeft);

      // Past the turn: the roundabout owns the banner, 250 m ahead.
      final atRoundabout = advance(steps, 1150, atTurn);
      expect(atRoundabout.maneuverOwner!.maneuverType, 'roundabout');
      expect(atRoundabout.maneuverOwner!.ownerChangeReason, 'step_change');
      expect(atRoundabout.snapshot.followRouteForced, isFalse);
      expect(_signOf(atRoundabout.snapshot), NavSignManeuver.roundaboutExit3);
    });

    test('a roundabout followed by a motorway exit', () {
      final steps = <DriverNavStep>[
        _step(type: 'depart', along: 0, instruction: 'Vertrek'),
        _step(
          type: 'roundabout',
          along: 1000,
          exitNumber: '1',
          instruction: 'Neem de 1ste afslag',
        ),
        _step(
          type: 'off ramp',
          modifier: 'right',
          along: 1300,
          instruction: 'Neem de afrit',
        ),
        _step(type: 'arrive', along: 2000, instruction: 'Bestemming'),
      ];

      final onRoundabout = advance(steps, 980, null);
      expect(_signOf(onRoundabout.snapshot), NavSignManeuver.roundaboutExit1);
      expect(onRoundabout.maneuverOwner!.roundaboutPhase,
          NavRoundaboutOwnerPhase.circulating);

      final onExit = advance(steps, 1050, onRoundabout);
      expect(onExit.maneuverOwner!.maneuverType, 'off ramp');
      expect(_signOf(onExit.snapshot), NavSignManeuver.exitRight);
    });

    test('a fork followed by a second fork uses the complex window twice', () {
      final steps = <DriverNavStep>[
        _step(type: 'depart', along: 0, instruction: 'Vertrek'),
        _step(
          type: 'fork',
          modifier: 'left',
          along: 1000,
          instruction: 'Hou links aan',
        ),
        _step(
          type: 'fork',
          modifier: 'slight right',
          along: 1250,
          instruction: 'Hou licht rechts aan',
        ),
        _step(type: 'arrive', along: 2000, instruction: 'Bestemming'),
      ];

      final onFork = advance(steps, 750, null); // 250 m: inside 300 m
      expect(onFork.maneuverOwner!.activationClass,
          NavManeuverActivationClass.complex);
      expect(_signOf(onFork.snapshot), NavSignManeuver.forkLeft);

      final onSecondFork = advance(steps, 1020, onFork);
      expect(onSecondFork.maneuverOwner!.maneuverType, 'fork');
      expect(_signOf(onSecondFork.snapshot), NavSignManeuver.forkRight);
    });

    test('a fork followed by a keep hands over to the ordinary window', () {
      final steps = <DriverNavStep>[
        _step(type: 'depart', along: 0, instruction: 'Vertrek'),
        _step(
          type: 'fork',
          modifier: 'left',
          along: 1000,
          instruction: 'Hou links aan',
        ),
        _step(
          type: 'continue',
          modifier: 'slight left',
          along: 1300,
          instruction: 'Blijf links',
        ),
        _step(type: 'arrive', along: 2000, instruction: 'Bestemming'),
      ];

      final onFork = advance(steps, 750, null);
      expect(onFork.maneuverOwner!.activationClass,
          NavManeuverActivationClass.complex);
      expect(_signOf(onFork.snapshot), NavSignManeuver.forkLeft);

      // 250 m before the keep: still outside the ordinary 200 m window.
      final beforeKeep = advance(steps, 1050, onFork);
      expect(beforeKeep.maneuverOwner!.maneuverType, 'continue');
      expect(beforeKeep.snapshot.followRouteForced, isTrue);
      expect(_signOf(beforeKeep.snapshot), NavSignManeuver.followRoute);

      final onKeep = advance(steps, 1150, beforeKeep);
      expect(onKeep.maneuverOwner!.activationClass,
          NavManeuverActivationClass.ordinary);
      expect(onKeep.snapshot.followRouteForced, isFalse);
      expect(_signOf(onKeep.snapshot), NavSignManeuver.keepLeft);
    });

    test('two maneuvers within 100 m never share the banner', () {
      final steps = <DriverNavStep>[
        _step(type: 'depart', along: 0, instruction: 'Vertrek'),
        _step(
          type: 'turn',
          modifier: 'right',
          along: 1000,
          instruction: 'Sla rechtsaf',
        ),
        _step(
          type: 'turn',
          modifier: 'left',
          along: 1080,
          instruction: 'Sla linksaf',
        ),
        _step(type: 'arrive', along: 2000, instruction: 'Bestemming'),
      ];

      final first = advance(steps, 950, null);
      expect(first.maneuverOwner!.describedStepIndex, 1);
      expect(_signOf(first.snapshot), NavSignManeuver.turnRight);

      final second = advance(steps, 1030, first);
      expect(second.maneuverOwner!.describedStepIndex, 2);
      expect(second.maneuverOwner!.maneuverIdentity,
          isNot(first.maneuverOwner!.maneuverIdentity));
      expect(_signOf(second.snapshot), NavSignManeuver.turnLeft);
    });
  });

  group('reroute', () {
    final oldSteps = _routeWith(
      _step(
        type: 'turn',
        modifier: 'left',
        along: 1000,
        instruction: 'Sla linksaf',
      ),
    );
    final newSteps = _routeWith(
      _step(
        type: 'roundabout',
        along: 1000,
        exitNumber: '4',
        instruction: 'Neem de 4de afslag',
      ),
    );

    test('a new route version replaces the owner and the sign', () {
      final before = _run(
        steps: oldSteps,
        progressM: 850,
        routeVersion: 1,
        progressEpoch: 5,
      );
      expect(_signOf(before.snapshot), NavSignManeuver.turnLeft);

      final after = _run(
        steps: newSteps,
        progressM: 850,
        routeVersion: 2,
        progressEpoch: 6,
        previousOwner: before.maneuverOwner,
        previousBanner: before.activeBanner,
      );
      expect(after.maneuverOwner!.ownerChangeReason, 'route_version_change');
      expect(after.maneuverOwner!.maneuverIdentity,
          isNot(before.maneuverOwner!.maneuverIdentity));
      expect(_signOf(after.snapshot), NavSignManeuver.roundaboutExit4);
    });

    test('a late write from the replaced route is refused', () {
      final onNewRoute = _run(
        steps: newSteps,
        progressM: 850,
        routeVersion: 2,
        progressEpoch: 6,
      );

      final lateWrite = _run(
        steps: oldSteps,
        progressM: 850,
        routeVersion: 1,
        progressEpoch: 7,
        previousOwner: onNewRoute.maneuverOwner,
      );
      expect(lateWrite.maneuverOwner!.staleWriteRejected, isTrue);
      expect(lateWrite.maneuverOwner!.routeVersion, 2);
      expect(lateWrite.maneuverOwner!.maneuverIdentity,
          onNewRoute.maneuverOwner!.maneuverIdentity);
    });

    test('a reroute inside an active window does not resurrect the old sign',
        () {
      final active = _run(
        steps: oldSteps,
        progressM: 950, // 50 m: the left turn is firmly active
        routeVersion: 1,
        progressEpoch: 9,
      );
      expect(active.snapshot.followRouteForced, isFalse);

      final rerouted = _run(
        steps: newSteps,
        progressM: 600, // 400 m on the new route: nothing to show yet
        routeVersion: 2,
        progressEpoch: 10,
        previousOwner: active.maneuverOwner,
        previousBanner: active.activeBanner,
      );
      expect(rerouted.snapshot.followRouteForced, isTrue);
      expect(_signOf(rerouted.snapshot), NavSignManeuver.followRoute);
      expect(_signOf(rerouted.snapshot), isNot(NavSignManeuver.turnLeft));
    });
  });

  group('guidance fields survive the pipeline', () {
    test('driving side, bearings and banner degrees reach the snapshot', () {
      final run = _atDistance(
        _step(
          type: 'roundabout',
          along: 1000,
          exitNumber: '2',
          drivingSide: 'left',
          bearingBefore: 90,
          bearingAfter: 270,
          instruction: 'Neem de 2de afslag',
          banners: <DriverNavBannerStage>[
            const DriverNavBannerStage(
              sourceIndex: 0,
              distanceAlongGeometry: 200,
              primary: DriverNavBannerView(
                text: 'Neem de 2de afslag',
                type: 'roundabout',
                modifier: 'right',
                degrees: 180,
              ),
            ),
          ],
        ),
        250,
      );
      expect(run.snapshot.drivingSide, 'left');
      expect(run.snapshot.bearingBefore, 90);
      expect(run.snapshot.bearingAfter, 270);
      expect(run.snapshot.bannerDegrees, 180);
      expect(run.snapshot.exitNumber, '2');
    });

    test('a step without guidance data carries nulls, never guesses', () {
      final run = _atDistance(
        _step(
          type: 'turn',
          modifier: 'left',
          along: 1000,
          instruction: 'Sla linksaf',
        ),
        150,
      );
      expect(run.snapshot.drivingSide, isNull);
      expect(run.snapshot.bearingBefore, isNull);
      expect(run.snapshot.bearingAfter, isNull);
      expect(run.snapshot.bannerDegrees, isNull);
    });

    test('confirmed arrival is carried explicitly', () {
      final run = _run(
        steps: _routeWith(
          _step(type: 'turn', modifier: 'left', along: 1000),
        ),
        progressM: 1990,
        destinationReached: true,
      );
      expect(run.snapshot.arrivalConfirmed, isTrue);
    });

    test('rewriting the display lines keeps every guidance field', () {
      final maneuver = _step(
        type: 'turn',
        modifier: 'left',
        along: 1000,
        drivingSide: 'left',
        bearingBefore: 10,
        bearingAfter: 100,
        instruction: 'Sla linksaf naar N454',
      );
      final snapshot = _atDistance(maneuver, 150).snapshot;
      final rewritten = applyDriverNavInstructionDisplayLines(
        snapshot: snapshot,
        step: maneuver,
      );
      expect(rewritten.drivingSide, 'left');
      expect(rewritten.bearingBefore, 10);
      expect(rewritten.bearingAfter, 100);
      expect(rewritten.followRouteForced, snapshot.followRouteForced);
    });
  });

  group('fallback safety', () {
    final turn = _step(
      type: 'turn',
      modifier: 'left',
      along: 1000,
      instruction: 'Sla linksaf',
    );

    test('a valid instruction is not displaced by the follow-route gate', () {
      final active = _atDistance(turn, 120).snapshot;
      expect(active.followRouteForced, isFalse);
      expect(active.maneuverType, 'turn');
      expect(_signOf(active), NavSignManeuver.turnLeft);
    });

    test('a neutral policy fallback withholds the maneuver sign', () {
      final active = _atDistance(turn, 120).snapshot;
      final neutral = applyDriverNavR1InstructionSafetyFilter(
        snapshot: active,
        routeSnappedReliable: false,
        routeOffRouteLikely: true,
        trustInstruction: false,
        tr: _tr,
      );
      if (neutral.maneuverType == 'continue') {
        expect(neutral.followRouteForced, isTrue);
        expect(_signOf(neutral), NavSignManeuver.followRoute);
      } else {
        expect(neutral.followRouteForced, active.followRouteForced);
      }
    });

    test('a fallback is followed cleanly by the next real instruction', () {
      final withheld = _atDistance(turn, 400).snapshot;
      expect(_signOf(withheld), NavSignManeuver.followRoute);

      final shown = _atDistance(turn, 180).snapshot;
      expect(_signOf(shown), NavSignManeuver.turnLeft);
      expect(shown.followRouteForced, isFalse);
    });
  });
}
