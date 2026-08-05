// NAV-MANEUVER-OWNER-REBASE-1
//
// `step.driving_side` decides which way a U-turn points and which side an
// unlabelled ramp or motorway exit leaves on. These proofs cover right-hand
// traffic, left-hand traffic (UK, Ireland), a missing value, the formats the
// parser can hand over, and values nothing can make sense of.

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/navigation/driver_navigation_models.dart';
import 'package:fluxidi_tracking/navigation/presentation/maneuver_presentation.dart';
import 'package:fluxidi_tracking/navigation/presentation/nav_sign_resolver.dart';

String _tr({
  required String nl,
  required String en,
  required String fr,
  required String es,
}) => nl;

NavSignManeuver _sign({
  required String type,
  String modifier = '',
  String? drivingSide,
}) {
  return resolveNavSign(
    NavSignEvent(
      maneuverType: type,
      maneuverModifier: modifier,
      drivingSide: drivingSide,
    ),
  ).maneuver;
}

NavInstructionSnapshot _snapshot({
  required String type,
  String modifier = '',
  String? drivingSide,
  double distance = 120,
}) {
  return NavInstructionSnapshot(
    distanceToManeuverMeters: distance,
    primaryText: 'Instructie',
    secondaryText: '',
    maneuverType: type,
    maneuverModifier: modifier,
    roadName: 'Teststraat',
    isHighwayLike: false,
    lanes: const <DriverNavLaneGuidance>[],
    source: NavInstructionSource.step,
    drivingSide: drivingSide,
  );
}

void main() {
  group('driving side normalisation', () {
    test('the values Mapbox emits are read exactly', () {
      expect(driverNavDrivesOnLeft('left'), isTrue);
      expect(driverNavDrivesOnLeft('right'), isFalse);
    });

    test('casing and padding never change the answer', () {
      for (final raw in <String>['LEFT', ' Left ', 'lEfT', '  left']) {
        expect(driverNavDrivesOnLeft(raw), isTrue, reason: raw);
      }
      for (final raw in <String>['RIGHT', ' Right ', 'rIgHt']) {
        expect(driverNavDrivesOnLeft(raw), isFalse, reason: raw);
      }
    });

    test('a left-hand suffix still means left-hand traffic', () {
      expect(driverNavDrivesOnLeft('left-hand'), isTrue);
      expect(driverNavDrivesOnLeft('LEFT_HAND'), isTrue);
    });

    test('a missing or nonsensical value falls back to right-hand traffic', () {
      for (final raw in <String?>[
        null,
        '',
        '   ',
        'middle',
        'unknown',
        'l',
        'links',
        '0',
      ]) {
        expect(
          driverNavDrivesOnLeft(raw),
          isFalse,
          reason: 'unrecognised "$raw" must not flip the traffic side',
        );
      }
    });
  });

  group('U-turns cross oncoming traffic', () {
    test('right-hand traffic turns back to the left', () {
      expect(
        _sign(type: 'turn', modifier: 'uturn', drivingSide: 'right'),
        NavSignManeuver.uturnLeft,
      );
    });

    test('left-hand traffic turns back to the right', () {
      expect(
        _sign(type: 'turn', modifier: 'uturn', drivingSide: 'left'),
        NavSignManeuver.uturnRight,
      );
    });

    test('without a driving side the right-hand variant is used', () {
      expect(
        _sign(type: 'turn', modifier: 'uturn'),
        NavSignManeuver.uturnLeft,
      );
    });

    test('an unknown driving side never crashes and stays right-hand', () {
      for (final raw in <String>['', '   ', 'centre', 'both', '¯\\_(ツ)_/¯']) {
        expect(
          _sign(type: 'turn', modifier: 'uturn', drivingSide: raw),
          NavSignManeuver.uturnLeft,
          reason: raw,
        );
      }
    });

    test('an end-of-road U-turn honours the driving side too', () {
      expect(
        _sign(type: 'end of road', modifier: 'uturn', drivingSide: 'left'),
        NavSignManeuver.uturnRight,
      );
      expect(
        _sign(type: 'end of road', modifier: 'uturn', drivingSide: 'right'),
        NavSignManeuver.uturnLeft,
      );
    });
  });

  group('unlabelled ramps and exits sit on the near side', () {
    test('right-hand traffic joins and leaves on the right', () {
      expect(
        _sign(type: 'on ramp', drivingSide: 'right'),
        NavSignManeuver.rampRight,
      );
      expect(
        _sign(type: 'off ramp', drivingSide: 'right'),
        NavSignManeuver.exitRight,
      );
    });

    test('left-hand traffic joins and leaves on the left', () {
      expect(
        _sign(type: 'on ramp', drivingSide: 'left'),
        NavSignManeuver.rampLeft,
      );
      expect(
        _sign(type: 'off ramp', drivingSide: 'left'),
        NavSignManeuver.exitLeft,
      );
    });

    test('a missing driving side keeps the right-hand default', () {
      expect(_sign(type: 'on ramp'), NavSignManeuver.rampRight);
      expect(_sign(type: 'off ramp'), NavSignManeuver.exitRight);
    });

    test('an explicit modifier outranks the driving side', () {
      expect(
        _sign(type: 'off ramp', modifier: 'left', drivingSide: 'right'),
        NavSignManeuver.exitLeft,
      );
      expect(
        _sign(type: 'off ramp', modifier: 'right', drivingSide: 'left'),
        NavSignManeuver.exitRight,
      );
      expect(
        _sign(type: 'on ramp', modifier: 'slight left', drivingSide: 'right'),
        NavSignManeuver.rampLeft,
      );
    });
  });

  group('driving side reaches the sign from the snapshot', () {
    test('a UK U-turn resolves without any explicit argument', () {
      final event = NavSignEvent.fromSnapshot(
        _snapshot(type: 'turn', modifier: 'uturn', drivingSide: 'left'),
      );
      expect(event.drivingSide, 'left');
      expect(resolveNavSign(event).maneuver, NavSignManeuver.uturnRight);
    });

    test('a continental U-turn resolves the other way', () {
      final event = NavSignEvent.fromSnapshot(
        _snapshot(type: 'turn', modifier: 'uturn', drivingSide: 'right'),
      );
      expect(resolveNavSign(event).maneuver, NavSignManeuver.uturnLeft);
    });

    test('an explicit argument still overrides the snapshot', () {
      final event = NavSignEvent.fromSnapshot(
        _snapshot(type: 'turn', modifier: 'uturn', drivingSide: 'left'),
        drivingSide: 'right',
      );
      expect(resolveNavSign(event).maneuver, NavSignManeuver.uturnLeft);
    });

    test('the banner presentation picks the side up on its own', () {
      final uk = buildResponsiveManeuverPresentation(
        snapshot: _snapshot(
          type: 'turn',
          modifier: 'uturn',
          drivingSide: 'left',
        ),
        tr: _tr,
        languageCode: 'en',
      );
      expect(uk.signManeuver, NavSignManeuver.uturnRight);
      expect(uk.signAssetPath, endsWith('/en/uturn_right.png'));

      final be = buildResponsiveManeuverPresentation(
        snapshot: _snapshot(
          type: 'turn',
          modifier: 'uturn',
          drivingSide: 'right',
        ),
        tr: _tr,
        languageCode: 'nl',
      );
      expect(be.signManeuver, NavSignManeuver.uturnLeft);
      expect(be.signAssetPath, endsWith('/nl/uturn_left.png'));
    });

    test('an unlabelled Irish exit leaves on the left', () {
      final p = buildResponsiveManeuverPresentation(
        snapshot: _snapshot(type: 'off ramp', drivingSide: 'left'),
        tr: _tr,
        languageCode: 'en',
      );
      expect(p.signManeuver, NavSignManeuver.exitLeft);
    });

    test('a snapshot without a driving side is safe, never blank', () {
      final p = buildResponsiveManeuverPresentation(
        snapshot: _snapshot(type: 'on ramp'),
        tr: _tr,
        languageCode: 'nl',
      );
      expect(p.signManeuver, NavSignManeuver.rampRight);
    });
  });

  group('follow-route and fallback safety', () {
    test('a withheld maneuver resolves to straight, not to its turn', () {
      final snapshot = _snapshot(
        type: 'turn',
        modifier: 'left',
        distance: 400,
      ).copyWith(followRouteForced: true);
      final resolution = resolveNavSign(NavSignEvent.fromSnapshot(snapshot));
      expect(resolution.maneuver, NavSignManeuver.straight);
      expect(resolution.source, NavSignResolutionSource.safeFallback);
    });

    test('a valid instruction is never displaced while it is active', () {
      final snapshot = _snapshot(type: 'turn', modifier: 'left');
      expect(
        resolveNavSign(NavSignEvent.fromSnapshot(snapshot)).maneuver,
        NavSignManeuver.turnLeft,
      );
    });

    test('an unknown event with a usable modifier keeps the direction', () {
      final resolution = resolveNavSign(
        NavSignEvent.fromSnapshot(
          _snapshot(type: 'unmapped_engine_event', modifier: 'slight right'),
        ),
      );
      expect(resolution.maneuver, NavSignManeuver.slightRight);
      expect(resolution.source, NavSignResolutionSource.classified);
    });

    test('a completely unknown event falls back to follow-route', () {
      final resolution = resolveNavSign(
        NavSignEvent.fromSnapshot(_snapshot(type: '', modifier: '')),
      );
      expect(resolution.maneuver, NavSignManeuver.followRoute);
      expect(resolution.source, NavSignResolutionSource.safeFallback);
    });
  });
}
