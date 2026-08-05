// NAV-MANEUVER-OWNER-REBASE-1
//
// Pure proofs for the single visible-maneuver owner: deterministic selection,
// distance-only activation windows, stale-write rejection and route-revision
// invalidation.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/navigation/driver_navigation_models.dart';
import 'package:fluxidi_tracking/navigation/nav_engine/nav_maneuver_owner.dart';

DriverNavStep _step({
  required String type,
  String modifier = '',
  String? exitNumber,
  String? drivingSide,
  double distanceAlongRouteM = 1000,
  double? bearingBefore,
  double? bearingAfter,
  List<DriverNavBannerStage> banners = const <DriverNavBannerStage>[],
}) {
  return DriverNavStep(
    lat: 50.85,
    lon: 4.35,
    instruction: 'instruction',
    street: 'Teststraat',
    type: type,
    modifier: modifier,
    distanceAlongRouteM: distanceAlongRouteM,
    exitNumber: exitNumber,
    drivingSide: drivingSide,
    bearingBefore: bearingBefore,
    bearingAfter: bearingAfter,
    bannerInstructions: banners,
  );
}

DriverNavBannerStage _stageWithDegrees(double? degrees) {
  return DriverNavBannerStage(
    sourceIndex: 0,
    distanceAlongGeometry: 200,
    primary: DriverNavBannerView(
      text: 'Take the 2nd exit',
      type: 'roundabout',
      modifier: 'right',
      degrees: degrees,
    ),
  );
}

NavVisibleManeuverOwner _resolve({
  required DriverNavStep step,
  required double distance,
  int describedStepIndex = 1,
  int traversalStepIndex = 0,
  int routeVersion = 1,
  int progressEpoch = 1,
  NavVisibleManeuverOwner? previous,
}) {
  return resolveNavVisibleManeuverOwner(
    describedStep: step,
    describedStepIndex: describedStepIndex,
    traversalStepIndex: traversalStepIndex,
    distanceToManeuverM: distance,
    routeVersion: routeVersion,
    progressEpoch: progressEpoch,
    previous: previous,
  );
}

void main() {
  group('activation constants', () {
    test('the two windows are the only distances that decide activation', () {
      expect(kNavManeuverComplexActivationMeters, 300.0);
      expect(kNavManeuverOrdinaryActivationMeters, 200.0);
      expect(
        navManeuverActivationThresholdM(NavManeuverActivationClass.complex),
        300.0,
      );
      expect(
        navManeuverActivationThresholdM(NavManeuverActivationClass.ordinary),
        200.0,
      );
      expect(
        navManeuverActivationThresholdM(NavManeuverActivationClass.followOnly),
        0.0,
      );
      expect(
        navManeuverActivationThresholdM(
          NavManeuverActivationClass.alwaysActive,
        ),
        double.infinity,
      );
    });

    test('no magic numbers: the owner never spells a window out again', () {
      final src = File(
        'lib/navigation/nav_engine/nav_maneuver_owner.dart',
      ).readAsStringSync();
      final constantLines = src
          .split('\n')
          .where((l) => l.contains('300.0') || l.contains('200.0'))
          .toList();
      expect(
        constantLines.length,
        2,
        reason: 'Only the two const declarations may carry the raw values.',
      );
      for (final line in constantLines) {
        expect(line.trimLeft(), startsWith('const double kNavManeuver'));
      }
    });
  });

  group('maneuver classification', () {
    test('roundabouts, ramps, forks and merges are complex', () {
      for (final type in <String>[
        'roundabout',
        'exit roundabout',
        'rotary',
        'exit rotary',
        'on ramp',
        'off ramp',
        'ramp',
        'fork',
        'merge',
      ]) {
        expect(
          classifyNavManeuverActivation(type: type, modifier: 'right'),
          NavManeuverActivationClass.complex,
          reason: '$type must get the 300 m window',
        );
      }
    });

    test('turns and T-junctions are ordinary', () {
      for (final type in <String>['turn', 'end of road']) {
        expect(
          classifyNavManeuverActivation(type: type, modifier: 'left'),
          NavManeuverActivationClass.ordinary,
        );
      }
      // A directional modifier is enough, whatever the type is called.
      expect(
        classifyNavManeuverActivation(type: 'notification', modifier: 'uturn'),
        NavManeuverActivationClass.ordinary,
      );
    });

    test('route endpoints are always owned, plain guidance never is', () {
      expect(
        classifyNavManeuverActivation(type: 'arrive', modifier: ''),
        NavManeuverActivationClass.alwaysActive,
      );
      expect(
        classifyNavManeuverActivation(type: 'depart', modifier: ''),
        NavManeuverActivationClass.alwaysActive,
      );
      for (final type in <String>['continue', 'new name', 'notification', '']) {
        expect(
          classifyNavManeuverActivation(type: type, modifier: 'straight'),
          NavManeuverActivationClass.followOnly,
          reason: '$type describes no maneuver to sign',
        );
      }
    });
  });

  group('activation windows', () {
    test('an ordinary turn activates at 200 m and not a metre earlier', () {
      final turn = _step(type: 'turn', modifier: 'left');
      expect(_resolve(step: turn, distance: 201).isActive, isFalse);
      expect(_resolve(step: turn, distance: 200).isActive, isTrue);
      expect(_resolve(step: turn, distance: 1).isActive, isTrue);
      expect(_resolve(step: turn, distance: 300).showFollowRoute, isTrue);
    });

    test('a complex junction activates at 300 m', () {
      final roundabout = _step(type: 'roundabout', exitNumber: '2');
      expect(_resolve(step: roundabout, distance: 301).isActive, isFalse);
      expect(_resolve(step: roundabout, distance: 300).isActive, isTrue);
      expect(_resolve(step: roundabout, distance: 250).isActive, isTrue);
    });

    test('follow-only guidance never activates, at any distance', () {
      final cont = _step(type: 'continue', modifier: 'straight');
      for (final d in <double>[0, 1, 50, 200, 300, 5000]) {
        expect(_resolve(step: cont, distance: d).isActive, isFalse);
      }
    });

    test('arrival and departure are owned regardless of distance', () {
      expect(
        _resolve(step: _step(type: 'arrive'), distance: 8000).isActive,
        isTrue,
      );
      expect(
        _resolve(step: _step(type: 'depart'), distance: 8000).isActive,
        isTrue,
      );
    });

    test('an unusable distance never activates a junction', () {
      final turn = _step(type: 'turn', modifier: 'left');
      expect(_resolve(step: turn, distance: double.nan).isActive, isFalse);
      expect(_resolve(step: turn, distance: double.infinity).isActive, isFalse);
    });

    test('activation takes no speed input at all', () {
      final src = File(
        'lib/navigation/nav_engine/nav_maneuver_owner.dart',
      ).readAsStringSync();
      for (final token in <String>[
        'speedKmh',
        'speedMps',
        'driverSpeed',
        'currentSpeed',
        'velocity',
      ]) {
        expect(
          src.contains(token),
          isFalse,
          reason: 'Timing must never read $token.',
        );
      }
    });
  });

  group('maneuver identity', () {
    test('identity separates route, step, type, modifier and exit', () {
      String id({
        int routeVersion = 1,
        int step = 3,
        String type = 'roundabout',
        String modifier = 'right',
        String? exit = '2',
      }) => navManeuverIdentity(
        routeVersion: routeVersion,
        describedStepIndex: step,
        type: type,
        modifier: modifier,
        exitNumber: exit,
      );

      final base = id();
      expect(id(), base, reason: 'identity must be deterministic');
      expect(id(routeVersion: 2), isNot(base));
      expect(id(step: 4), isNot(base));
      expect(id(type: 'turn'), isNot(base));
      expect(id(modifier: 'left'), isNot(base));
      expect(id(exit: '3'), isNot(base));
      expect(id(exit: null), isNot(base));
    });

    test('identity ignores casing and padding of type and modifier', () {
      expect(
        navManeuverIdentity(
          routeVersion: 1,
          describedStepIndex: 0,
          type: ' Roundabout ',
          modifier: ' RIGHT ',
        ),
        navManeuverIdentity(
          routeVersion: 1,
          describedStepIndex: 0,
          type: 'roundabout',
          modifier: 'right',
        ),
      );
    });
  });

  group('one owner, deterministic selection', () {
    test('the same inputs always yield the same owner', () {
      final step = _step(type: 'turn', modifier: 'left');
      final a = _resolve(step: step, distance: 150);
      final b = _resolve(step: step, distance: 150);
      expect(a.maneuverIdentity, b.maneuverIdentity);
      expect(a.isActive, b.isActive);
      expect(a.activationClass, b.activationClass);
      expect(a.describedStepIndex, b.describedStepIndex);
    });

    test('the reason names why the owner changed', () {
      final turn = _step(type: 'turn', modifier: 'left');
      final first = _resolve(step: turn, distance: 180, progressEpoch: 1);
      expect(first.ownerChangeReason, 'initial');

      final tick = _resolve(
        step: turn,
        distance: 120,
        progressEpoch: 2,
        previous: first,
      );
      expect(tick.ownerChangeReason, 'progress_tick');
      expect(tick.maneuverIdentity, first.maneuverIdentity);

      final nextStep = _resolve(
        step: _step(type: 'roundabout', exitNumber: '2'),
        distance: 280,
        describedStepIndex: 2,
        progressEpoch: 3,
        previous: tick,
      );
      expect(nextStep.ownerChangeReason, 'step_change');
      expect(nextStep.maneuverIdentity, isNot(tick.maneuverIdentity));
    });

    test('only the exit number changing is a new maneuver identity', () {
      final before = _resolve(
        step: _step(type: 'roundabout', exitNumber: '2'),
        distance: 250,
        progressEpoch: 1,
      );
      final after = _resolve(
        step: _step(type: 'roundabout', exitNumber: '3'),
        distance: 250,
        progressEpoch: 2,
        previous: before,
      );
      expect(after.ownerChangeReason, 'maneuver_identity_change');
      expect(after.exitNumber, '3');
      expect(after.staleWriteRejected, isFalse);
    });

    test('only the modifier changing is a new maneuver identity', () {
      final before = _resolve(
        step: _step(type: 'turn', modifier: 'left'),
        distance: 150,
        progressEpoch: 1,
      );
      final after = _resolve(
        step: _step(type: 'turn', modifier: 'right'),
        distance: 150,
        progressEpoch: 2,
        previous: before,
      );
      expect(after.ownerChangeReason, 'maneuver_identity_change');
      expect(after.maneuverModifier, 'right');
    });
  });

  group('stale-owner rejection', () {
    test('a write from a replaced route is refused', () {
      final current = _resolve(
        step: _step(type: 'roundabout', exitNumber: '2'),
        distance: 250,
        routeVersion: 7,
        progressEpoch: 10,
      );
      final late = _resolve(
        step: _step(type: 'turn', modifier: 'left'),
        distance: 100,
        routeVersion: 6,
        progressEpoch: 11,
        previous: current,
      );
      expect(late.staleWriteRejected, isTrue);
      expect(late.ownerChangeReason, 'stale_write_rejected');
      expect(late.maneuverIdentity, current.maneuverIdentity);
      expect(late.routeVersion, 7);
    });

    test('an out-of-order progress tick is refused', () {
      final current = _resolve(
        step: _step(type: 'turn', modifier: 'left'),
        distance: 150,
        progressEpoch: 20,
      );
      final late = _resolve(
        step: _step(type: 'turn', modifier: 'right'),
        distance: 40,
        progressEpoch: 19,
        previous: current,
      );
      expect(late.staleWriteRejected, isTrue);
      expect(late.maneuverModifier, 'left');
    });

    test('a maneuver may not walk backwards inside one tick', () {
      final current = _resolve(
        step: _step(type: 'turn', modifier: 'left'),
        distance: 150,
        describedStepIndex: 4,
        progressEpoch: 5,
      );
      final backwards = _resolve(
        step: _step(type: 'turn', modifier: 'right'),
        distance: 150,
        describedStepIndex: 3,
        progressEpoch: 5,
        previous: current,
      );
      expect(backwards.staleWriteRejected, isTrue);
      expect(backwards.describedStepIndex, 4);
    });

    test('a newer route always wins, even on an older epoch', () {
      final current = _resolve(
        step: _step(type: 'turn', modifier: 'left'),
        distance: 150,
        routeVersion: 3,
        progressEpoch: 90,
      );
      final rerouted = _resolve(
        step: _step(type: 'roundabout', exitNumber: '1'),
        distance: 250,
        routeVersion: 4,
        progressEpoch: 1,
        previous: current,
      );
      expect(rerouted.staleWriteRejected, isFalse);
      expect(rerouted.ownerChangeReason, 'route_version_change');
      expect(rerouted.routeVersion, 4);
    });

    test('the first tick is never stale', () {
      expect(
        navManeuverOwnerTickIsStale(
          candidateRouteVersion: 0,
          candidateProgressEpoch: 0,
          candidateDescribedStepIndex: 0,
          active: null,
        ),
        isFalse,
      );
    });
  });

  group('route revision invalidation', () {
    test('a maneuver from the replaced route can never come back', () {
      final oldStep = _step(type: 'turn', modifier: 'left');
      final onOldRoute = _resolve(
        step: oldStep,
        distance: 150,
        routeVersion: 1,
        progressEpoch: 5,
      );

      final onNewRoute = _resolve(
        step: _step(type: 'roundabout', exitNumber: '3'),
        distance: 280,
        routeVersion: 2,
        progressEpoch: 6,
        previous: onOldRoute,
      );
      expect(onNewRoute.maneuverIdentity, isNot(onOldRoute.maneuverIdentity));

      // Replaying the exact old step on the new route is still a new identity,
      // because the route version is part of it.
      final replayed = _resolve(
        step: oldStep,
        distance: 150,
        routeVersion: 2,
        progressEpoch: 7,
        previous: onNewRoute,
      );
      expect(replayed.maneuverIdentity, isNot(onOldRoute.maneuverIdentity));
    });
  });

  group('roundabout phase and guidance data', () {
    test('phase follows remaining distance while the owner is active', () {
      final roundabout = _step(type: 'roundabout', exitNumber: '2');
      expect(
        _resolve(step: roundabout, distance: 400).roundaboutPhase,
        NavRoundaboutOwnerPhase.none,
      );
      expect(
        _resolve(step: roundabout, distance: 280).roundaboutPhase,
        NavRoundaboutOwnerPhase.approach,
      );
      expect(
        _resolve(step: roundabout, distance: 20).roundaboutPhase,
        NavRoundaboutOwnerPhase.circulating,
      );
      expect(
        _resolve(
          step: _step(type: 'turn', modifier: 'left'),
          distance: 20,
        ).roundaboutPhase,
        NavRoundaboutOwnerPhase.none,
      );
    });

    test('banner degrees are read, never invented', () {
      expect(
        navManeuverBannerDegrees(
          _step(type: 'roundabout', banners: [_stageWithDegrees(120)]),
        ),
        120,
      );
      expect(
        navManeuverBannerDegrees(
          _step(type: 'roundabout', banners: [_stageWithDegrees(null)]),
        ),
        isNull,
      );
      expect(
        navManeuverBannerDegrees(
          _step(
            type: 'roundabout',
            bearingBefore: 10,
            bearingAfter: 190,
          ),
        ),
        isNull,
        reason: 'bearings are not banner degrees',
      );
    });

    test('the bearing delta is a separate, signed quantity', () {
      expect(
        navManeuverBearingDeltaDegrees(
          _step(type: 'turn', bearingBefore: 350, bearingAfter: 20),
        ),
        30,
      );
      expect(
        navManeuverBearingDeltaDegrees(
          _step(type: 'turn', bearingBefore: 20, bearingAfter: 350),
        ),
        -30,
      );
      expect(
        navManeuverBearingDeltaDegrees(_step(type: 'turn', bearingBefore: 20)),
        isNull,
      );
    });

    test('guidance fields travel with the owner', () {
      final owner = _resolve(
        step: _step(
          type: 'roundabout',
          modifier: 'right',
          exitNumber: ' 2 ',
          drivingSide: 'left',
          bearingBefore: 90,
          bearingAfter: 270,
          banners: [_stageWithDegrees(180)],
        ),
        distance: 250,
      );
      expect(owner.exitNumber, '2');
      expect(owner.drivingSide, 'left');
      expect(owner.bearingBefore, 90);
      expect(owner.bearingAfter, 270);
      expect(owner.bannerDegrees, 180);
    });

    test('a blank exit number never becomes an ordinal', () {
      expect(
        _resolve(
          step: _step(type: 'roundabout', exitNumber: '   '),
          distance: 250,
        ).exitNumber,
        isNull,
      );
    });
  });

  group('diagnostics', () {
    test('the owner log carries no coordinates or free text', () {
      final line = formatNavManeuverOwnerDiag(
        _resolve(
          step: _step(type: 'roundabout', exitNumber: '2', drivingSide: 'left'),
          distance: 250,
        ),
      );
      expect(line, startsWith('[NAV_MANEUVER_OWNER]'));
      expect(line, contains('active=true'));
      expect(line, contains('thresholdM=300'));
      expect(line, isNot(contains('50.85')));
      expect(line, isNot(contains('Teststraat')));
    });

    test('an always-active owner reports its window as such', () {
      final line = formatNavManeuverOwnerDiag(
        _resolve(step: _step(type: 'arrive'), distance: 4000),
      );
      expect(line, contains('thresholdM=always'));
    });
  });
}
