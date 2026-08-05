import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/navigation/driver_navigation_models.dart';
import 'package:fluxidi_tracking/navigation/nav_engine/nav_slight_fork_guidance.dart';
import 'package:fluxidi_tracking/navigation/driver_navigation_instruction_state.dart';
import 'package:fluxidi_tracking/navigation/presentation/maneuver_presentation.dart';

DriverNavStep _step({
  String type = '',
  String modifier = '',
  List<DriverNavIntersection> intersections = const [],
  double along = 100,
  String instruction = '',
  String street = '',
}) {
  return DriverNavStep(
    lat: 50.85,
    lon: 3.61,
    instruction: instruction,
    street: street,
    type: type,
    modifier: modifier,
    distanceAlongRouteM: along,
    intersections: intersections,
  );
}

DriverNavIntersection _forkIx({
  required double inBearing,
  required double outBearing,
  required double otherBearing,
  int inIndex = 0,
  int outIndex = 1,
}) {
  return DriverNavIntersection(
    sourceIndex: 0,
    bearings: [inBearing, outBearing, otherBearing],
    entry: const [false, true, true],
    inIndex: inIndex,
    outIndex: outIndex,
  );
}

String _tr({
  required String nl,
  required String en,
  required String fr,
  required String es,
}) =>
    nl;

void main() {
  group('slight fork synthesis', () {
    test('1) real fork, route slightly left -> slight-left instruction', () {
      // Incoming travel ~0° (north). Out ~340° (-20°) = slight left.
      // Inbound arm bearing is reverse of travel (180).
      final step = _step(
        type: 'fork',
        intersections: [
          _forkIx(inBearing: 180, outBearing: 340, otherBearing: 40),
        ],
      );
      final g = resolveSlightForkGuidance(step: step);
      expect(g, isNotNull);
      expect(g!.side, SlightForkSide.left);
      expect(g.modifier, 'slight left');
      expect(g.primaryText(_tr), 'Hou licht links');
    });

    test('2) real fork, route slightly right -> slight-right instruction', () {
      final step = _step(
        type: 'fork',
        intersections: [
          _forkIx(inBearing: 180, outBearing: 20, otherBearing: 340),
        ],
      );
      final g = resolveSlightForkGuidance(step: step);
      expect(g, isNotNull);
      expect(g!.side, SlightForkSide.right);
      expect(g.modifier, 'slight right');
      expect(g.primaryText(_tr), 'Hou licht rechts');
    });

    test('3) curved road without alternative -> no synthetic instruction', () {
      final step = _step(type: 'continue', modifier: '');
      final coords = <DriverLonLat>[
        const DriverLonLat(3.60, 50.85),
        const DriverLonLat(3.601, 50.8505),
        const DriverLonLat(3.602, 50.8512),
        const DriverLonLat(3.6035, 50.852),
      ];
      final g = resolveSlightForkGuidance(
        step: step,
        routeCoords: coords,
      );
      expect(g, isNull);
    });

    test('4) official Mapbox turn -> official instruction wins', () {
      final step = _step(
        type: 'turn',
        modifier: 'left',
        intersections: [
          _forkIx(inBearing: 180, outBearing: 340, otherBearing: 40),
        ],
      );
      expect(resolveSlightForkGuidance(step: step), isNull);
      expect(
        hasOfficialDirectionalManeuver(type: 'turn', modifier: 'left'),
        isTrue,
      );
    });

    test('5) roundabout -> no synthetic fork instruction', () {
      final step = _step(
        type: 'roundabout',
        modifier: 'left',
        intersections: [
          _forkIx(inBearing: 180, outBearing: 20, otherBearing: 90),
        ],
      );
      expect(resolveSlightForkGuidance(step: step), isNull);
    });

    test('6) tiny bearing noise -> no instruction', () {
      final step = _step(
        type: 'fork',
        intersections: [
          _forkIx(inBearing: 180, outBearing: 5, otherBearing: 90),
        ],
      );
      expect(resolveSlightForkGuidance(step: step), isNull);
    });
  });

  group('action presentation during mapbox banner', () {
    test('7+8) action stays primary; target/street secondary', () {
      final step = _step(
        type: 'turn',
        modifier: 'left',
        street: 'Stationsstraat',
        instruction: 'Turn left onto Stationsstraat',
      );
      final normalized = normalizeDriverInstructionDisplayLines(
        rawPrimary: 'Turn left',
        rawSecondary: 'Stationsstraat',
        step: step,
      );
      expect(driverTextLooksLikeManeuverAction(normalized.primary), isTrue);
      expect(normalized.primary.toLowerCase(), contains('left'));
      expect(normalized.secondary.toLowerCase(), contains('stationsstraat'));
      expect(normalized.swapped, isFalse);
      expect(
        driverNavBannerPrimaryKind(
          primaryText: normalized.primary,
          step: step,
        ),
        'action',
      );
    });

    test('9) no banner flashing: action primary is stable across normalize', () {
      final step = _step(
        type: 'fork',
        modifier: 'slight right',
        street: 'N60',
      );
      final a = normalizeDriverInstructionDisplayLines(
        rawPrimary: 'Hou licht rechts',
        rawSecondary: 'N60',
        step: step,
      );
      final b = normalizeDriverInstructionDisplayLines(
        rawPrimary: a.primary,
        rawSecondary: a.secondary,
        step: step,
      );
      expect(a.primary, b.primary);
      expect(a.secondary, b.secondary);
    });

    test('slight-fork visual shows action wording (not follow-route) in far', () {
      final snap = NavInstructionSnapshot(
        distanceToManeuverMeters: 1200,
        primaryText: 'Hou licht links',
        secondaryText: 'N60',
        maneuverType: 'fork',
        maneuverModifier: 'slight left',
        roadName: 'N60',
        isHighwayLike: false,
        lanes: const [],
        source: NavInstructionSource.banner,
      );
      final presentation = buildResponsiveManeuverPresentation(
        snapshot: snap,
        tr: _tr,
      );
      expect(presentation.maneuverVisual, ManeuverVisual.slightLeft);
      expect(presentation.primaryInstruction.toLowerCase(), contains('licht'));
      expect(
        presentation.primaryInstruction.toLowerCase(),
        isNot(contains('volg de route')),
      );
      expect(presentation.secondaryInstruction.toLowerCase(), contains('n60'));
    });
  });

  group('route presentation coalesce', () {
    test('10) coalesces without stale writes', () {
      expect(
        decideNavRouteLineProgressWrite(
          capturedRenderEpoch: 3,
          currentRenderEpoch: 4,
          hasActiveLineAnnotations: true,
          forceRecreate: false,
          sameRouteVersion: true,
          progressDeltaM: 20,
          msSinceLastWrite: 500,
        ).kind,
        NavRouteLineProgressWriteKind.skip,
      );
      expect(
        decideNavRouteLineProgressWrite(
          capturedRenderEpoch: 4,
          currentRenderEpoch: 4,
          hasActiveLineAnnotations: true,
          forceRecreate: false,
          sameRouteVersion: true,
          progressDeltaM: 5,
          msSinceLastWrite: 100,
        ).kind,
        NavRouteLineProgressWriteKind.skip,
      );
      expect(
        decideNavRouteLineProgressWrite(
          capturedRenderEpoch: 4,
          currentRenderEpoch: 4,
          hasActiveLineAnnotations: true,
          forceRecreate: false,
          sameRouteVersion: true,
          progressDeltaM: 15,
          msSinceLastWrite: 400,
        ).kind,
        NavRouteLineProgressWriteKind.updateInPlace,
      );
      expect(
        decideNavRouteLineProgressWrite(
          capturedRenderEpoch: 4,
          currentRenderEpoch: 4,
          hasActiveLineAnnotations: false,
          forceRecreate: false,
          sameRouteVersion: true,
          progressDeltaM: 15,
          msSinceLastWrite: 400,
        ).kind,
        NavRouteLineProgressWriteKind.recreate,
      );
    });
  });
}
