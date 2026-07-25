// NAV-END-OF-ROAD-MANEUVER-CORRECTNESS-P0-1
//
// Field-proven defect: `type == 'end of road'` was unconditionally mapped to
// `ManeuverVisual.uTurn` / `Icons.u_turn_left_rounded` in BOTH the active
// presentation resolver and the legacy defensive icon resolver, so ordinary
// left / right turns at an end-of-road junction rendered a false 180° arrow.
//
// This suite pins the new modifier-aware mapping and proves that:
//   * end-of-road resolution reads the modifier;
//   * missing/unknown modifier at an end-of-road step falls back to the
//     neutral follow-route/straight icon, never a false U-turn;
//   * ordinary turn/uturn resolution is preserved for all left/right/slight/
//     sharp/uturn variants;
//   * roundabout / rotary ownership and localized ordinals (NL/EN/FR/ES) are
//     preserved unchanged;
//   * Portuguese roundabout ordinal + sentence are produced deterministically
//     by dedicated pure helpers (see maneuver_presentation.dart).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/navigation/driver_navigation_formatters.dart';
import 'package:fluxidi_tracking/navigation/driver_navigation_models.dart';
import 'package:fluxidi_tracking/navigation/presentation/maneuver_presentation.dart';

String _trNl({
  required String nl,
  required String en,
  required String fr,
  required String es,
}) => nl;

String _trEn({
  required String nl,
  required String en,
  required String fr,
  required String es,
}) => en;

String _trFr({
  required String nl,
  required String en,
  required String fr,
  required String es,
}) => fr;

String _trEs({
  required String nl,
  required String en,
  required String fr,
  required String es,
}) => es;

NavInstructionSnapshot _snap({
  String type = 'turn',
  String modifier = '',
  String primary = '',
  String secondary = '',
  String? exitNumber,
  double distance = 300,
  NavInstructionSource source = NavInstructionSource.banner,
}) {
  return NavInstructionSnapshot(
    distanceToManeuverMeters: distance,
    primaryText: primary,
    secondaryText: secondary,
    maneuverType: type,
    maneuverModifier: modifier,
    roadName: '',
    exitNumber: exitNumber,
    isHighwayLike: false,
    lanes: const <DriverNavLaneGuidance>[],
    source: source,
  );
}

void main() {
  group('NAV-END-OF-ROAD-MANEUVER-CORRECTNESS ordinary turn mapping', () {
    test('1. turn + left → ManeuverVisual.left / turn_left_rounded', () {
      final v = resolveDriverManeuverVisual(_snap(modifier: 'left'));
      expect(v, ManeuverVisual.left);
      expect(driverManeuverVisualIconData(v), Icons.turn_left_rounded);
      expect(
        driverManeuverIconData('turn', 'left', 'Turn left'),
        Icons.turn_left_rounded,
      );
    });

    test('2. turn + right → ManeuverVisual.right / turn_right_rounded', () {
      final v = resolveDriverManeuverVisual(_snap(modifier: 'right'));
      expect(v, ManeuverVisual.right);
      expect(driverManeuverVisualIconData(v), Icons.turn_right_rounded);
      expect(
        driverManeuverIconData('turn', 'right', 'Turn right'),
        Icons.turn_right_rounded,
      );
    });

    test('3. turn + slight left → slight-left icon', () {
      final v = resolveDriverManeuverVisual(_snap(modifier: 'slight left'));
      expect(v, ManeuverVisual.slightLeft);
      expect(driverManeuverVisualIconData(v), Icons.turn_slight_left_rounded);
      expect(
        driverManeuverIconData('turn', 'slight left', 'Slight left'),
        Icons.turn_slight_left_rounded,
      );
    });

    test('4. turn + slight right → slight-right icon', () {
      final v = resolveDriverManeuverVisual(_snap(modifier: 'slight right'));
      expect(v, ManeuverVisual.slightRight);
      expect(driverManeuverVisualIconData(v), Icons.turn_slight_right_rounded);
      expect(
        driverManeuverIconData('turn', 'slight right', 'Slight right'),
        Icons.turn_slight_right_rounded,
      );
    });

    test('5. turn + sharp left → sharp-left icon', () {
      final v = resolveDriverManeuverVisual(_snap(modifier: 'sharp left'));
      expect(v, ManeuverVisual.sharpLeft);
      expect(driverManeuverVisualIconData(v), Icons.turn_sharp_left_rounded);
      expect(
        driverManeuverIconData('turn', 'sharp left', 'Sharp left'),
        Icons.turn_sharp_left_rounded,
      );
    });

    test('6. turn + sharp right → sharp-right icon', () {
      final v = resolveDriverManeuverVisual(_snap(modifier: 'sharp right'));
      expect(v, ManeuverVisual.sharpRight);
      expect(driverManeuverVisualIconData(v), Icons.turn_sharp_right_rounded);
      expect(
        driverManeuverIconData('turn', 'sharp right', 'Sharp right'),
        Icons.turn_sharp_right_rounded,
      );
    });

    test('7. turn + uturn → U-turn icon', () {
      final v = resolveDriverManeuverVisual(_snap(modifier: 'uturn'));
      expect(v, ManeuverVisual.uTurn);
      expect(driverManeuverVisualIconData(v), Icons.u_turn_left_rounded);
      expect(
        driverManeuverIconData('turn', 'uturn', 'Make a U-turn'),
        Icons.u_turn_left_rounded,
      );
    });
  });

  group('NAV-END-OF-ROAD-MANEUVER-CORRECTNESS end-of-road mapping', () {
    test('8. end of road + left → left icon, never U-turn', () {
      final v = resolveDriverManeuverVisual(
        _snap(type: 'end of road', modifier: 'left'),
      );
      expect(v, ManeuverVisual.left);
      expect(driverManeuverVisualIconData(v), Icons.turn_left_rounded);
      expect(driverManeuverVisualIconData(v), isNot(Icons.u_turn_left_rounded));
      expect(
        driverManeuverIconData('end of road', 'left', 'Turn left'),
        Icons.turn_left_rounded,
      );
      expect(
        driverManeuverIconData('end of road', 'left', 'Turn left'),
        isNot(Icons.u_turn_left_rounded),
      );
    });

    test('9. end of road + right → right icon, never U-turn', () {
      final v = resolveDriverManeuverVisual(
        _snap(type: 'end of road', modifier: 'right'),
      );
      expect(v, ManeuverVisual.right);
      expect(driverManeuverVisualIconData(v), Icons.turn_right_rounded);
      expect(driverManeuverVisualIconData(v), isNot(Icons.u_turn_left_rounded));
      expect(
        driverManeuverIconData('end of road', 'right', 'Turn right'),
        Icons.turn_right_rounded,
      );
    });

    test('10. end of road + slight left → slight-left icon', () {
      final v = resolveDriverManeuverVisual(
        _snap(type: 'end of road', modifier: 'slight left'),
      );
      expect(v, ManeuverVisual.slightLeft);
      expect(driverManeuverVisualIconData(v), Icons.turn_slight_left_rounded);
      expect(
        driverManeuverIconData('end of road', 'slight left', 'Slight left'),
        Icons.turn_slight_left_rounded,
      );
    });

    test('11. end of road + slight right → slight-right icon', () {
      final v = resolveDriverManeuverVisual(
        _snap(type: 'end of road', modifier: 'slight right'),
      );
      expect(v, ManeuverVisual.slightRight);
      expect(driverManeuverVisualIconData(v), Icons.turn_slight_right_rounded);
      expect(
        driverManeuverIconData('end of road', 'slight right', 'Slight right'),
        Icons.turn_slight_right_rounded,
      );
    });

    test('12. end of road + sharp left → sharp-left icon', () {
      final v = resolveDriverManeuverVisual(
        _snap(type: 'end of road', modifier: 'sharp left'),
      );
      expect(v, ManeuverVisual.sharpLeft);
      expect(driverManeuverVisualIconData(v), Icons.turn_sharp_left_rounded);
      expect(
        driverManeuverIconData('end of road', 'sharp left', 'Sharp left'),
        Icons.turn_sharp_left_rounded,
      );
    });

    test('13. end of road + sharp right → sharp-right icon', () {
      final v = resolveDriverManeuverVisual(
        _snap(type: 'end of road', modifier: 'sharp right'),
      );
      expect(v, ManeuverVisual.sharpRight);
      expect(driverManeuverVisualIconData(v), Icons.turn_sharp_right_rounded);
      expect(
        driverManeuverIconData('end of road', 'sharp right', 'Sharp right'),
        Icons.turn_sharp_right_rounded,
      );
    });

    test('14. end of road + uturn → U-turn icon (legitimate)', () {
      final v = resolveDriverManeuverVisual(
        _snap(type: 'end of road', modifier: 'uturn'),
      );
      expect(v, ManeuverVisual.uTurn);
      expect(driverManeuverVisualIconData(v), Icons.u_turn_left_rounded);
      expect(
        driverManeuverIconData('end of road', 'uturn', 'Make a U-turn'),
        Icons.u_turn_left_rounded,
      );
    });

    test('15. end of road + empty modifier → followRoute, never U-turn', () {
      final v = resolveDriverManeuverVisual(
        _snap(type: 'end of road', modifier: '', primary: '', secondary: ''),
      );
      expect(v, ManeuverVisual.followRoute);
      expect(driverManeuverVisualIconData(v), Icons.straight_rounded);
      expect(driverManeuverVisualIconData(v), isNot(Icons.u_turn_left_rounded));
      // Legacy resolver must agree.
      final legacy = driverManeuverIconData('end of road', '', '');
      expect(legacy, isNot(Icons.u_turn_left_rounded));
      expect(legacy, Icons.straight_rounded);
    });

    test('16. end of road + unknown modifier → followRoute, never U-turn', () {
      final v = resolveDriverManeuverVisual(
        _snap(
          type: 'end of road',
          modifier: 'some-future-mapbox-modifier',
          primary: '',
        ),
      );
      expect(v, ManeuverVisual.followRoute);
      expect(driverManeuverVisualIconData(v), isNot(Icons.u_turn_left_rounded));
      // Legacy fallback icon must also stay neutral.
      final legacy = driverManeuverIconData(
        'end of road',
        'some-future-mapbox-modifier',
        '',
      );
      expect(legacy, isNot(Icons.u_turn_left_rounded));
    });

    test(
      'end of road + missing modifier + accidental "u-turn" in instruction '
      'text remains a safe followRoute (no U-turn upgrade from hints)',
      () {
        final v = resolveDriverManeuverVisual(
          _snap(
            type: 'end of road',
            modifier: '',
            primary: 'Reach the end of Main Street',
            secondary: '',
          ),
        );
        // No modifier + no true U-turn in the text → neutral.
        expect(v, ManeuverVisual.followRoute);
        expect(
          driverManeuverVisualIconData(v),
          isNot(Icons.u_turn_left_rounded),
        );
        // Legacy `combined` fallback must NOT upgrade an end-of-road step to
        // U-turn based on text hints — only an explicit modifier may.
        final legacy = driverManeuverIconData(
          'end of road',
          '',
          'proceed to the u-turn area',
        );
        expect(legacy, isNot(Icons.u_turn_left_rounded));
      },
    );
  });

  group('NAV-END-OF-ROAD-MANEUVER-CORRECTNESS unknown data fallback', () {
    test('17. empty type + empty modifier → followRoute', () {
      final v = resolveDriverManeuverVisual(_snap(type: '', modifier: ''));
      expect(v, ManeuverVisual.followRoute);
      expect(driverManeuverVisualIconData(v), Icons.straight_rounded);
      expect(driverManeuverIconData('', '', ''), Icons.straight_rounded);
    });

    test('18. unknown type + empty modifier → followRoute', () {
      final v = resolveDriverManeuverVisual(
        _snap(type: 'random-mapbox-string', modifier: ''),
      );
      expect(v, ManeuverVisual.followRoute);
      expect(driverManeuverVisualIconData(v), Icons.straight_rounded);
      expect(
        driverManeuverIconData('random-mapbox-string', '', ''),
        Icons.straight_rounded,
      );
    });

    test('19. unknown type + unknown modifier → followRoute', () {
      final v = resolveDriverManeuverVisual(
        _snap(type: 'random-mapbox-string', modifier: 'weird-modifier'),
      );
      expect(v, ManeuverVisual.followRoute);
      expect(driverManeuverVisualIconData(v), Icons.straight_rounded);
    });

    test(
      '20. transitioning unknown-data → known left never yields U-turn '
      'in any intermediate resolve',
      () {
        // Simulate two consecutive resolutions during a step advance: the
        // stale snapshot (unknown) and the fresh snapshot (turn + left). The
        // policy contract is: neither is a U-turn.
        final stale = resolveDriverManeuverVisual(
          _snap(type: '', modifier: '', primary: ''),
        );
        final fresh = resolveDriverManeuverVisual(
          _snap(type: 'turn', modifier: 'left'),
        );
        expect(stale, isNot(ManeuverVisual.uTurn));
        expect(fresh, ManeuverVisual.left);
        // The icon path never produces a U-turn asset either.
        expect(
          driverManeuverVisualIconData(stale),
          isNot(Icons.u_turn_left_rounded),
        );
        expect(
          driverManeuverVisualIconData(fresh),
          isNot(Icons.u_turn_left_rounded),
        );
      },
    );

    test(
      '21. legacy driverManeuverIconData produces the same safe mappings',
      () {
        // Ordinary turns:
        expect(
          driverManeuverIconData('turn', 'left', 'Turn left'),
          Icons.turn_left_rounded,
        );
        expect(
          driverManeuverIconData('turn', 'right', 'Turn right'),
          Icons.turn_right_rounded,
        );
        expect(
          driverManeuverIconData('turn', 'uturn', 'Make a U-turn'),
          Icons.u_turn_left_rounded,
        );
        // End-of-road:
        expect(
          driverManeuverIconData('end of road', 'left', ''),
          Icons.turn_left_rounded,
        );
        expect(
          driverManeuverIconData('end of road', 'right', ''),
          Icons.turn_right_rounded,
        );
        expect(
          driverManeuverIconData('end of road', '', ''),
          Icons.straight_rounded,
        );
        // Roundabout / arrival / depart:
        expect(
          driverManeuverIconData('roundabout', '', ''),
          Icons.roundabout_right_rounded,
        );
        expect(
          driverManeuverIconData('rotary', '', ''),
          Icons.roundabout_right_rounded,
        );
        expect(driverManeuverIconData('arrive', '', ''), Icons.flag_rounded);
        expect(
          driverManeuverIconData('depart', '', ''),
          Icons.navigation_rounded,
        );
      },
    );
  });

  group('NAV-END-OF-ROAD-MANEUVER-CORRECTNESS roundabout preservation', () {
    test('22. roundabout remains a dedicated roundabout visual', () {
      final v = resolveDriverManeuverVisual(
        _snap(type: 'roundabout', modifier: 'right'),
      );
      expect(v, ManeuverVisual.roundabout);
      expect(driverManeuverVisualIconData(v), Icons.roundabout_right_rounded);
    });

    test('23. rotary remains a dedicated roundabout visual', () {
      final v = resolveDriverManeuverVisual(
        _snap(type: 'rotary', modifier: 'right'),
      );
      expect(v, ManeuverVisual.roundabout);
      expect(driverManeuverVisualIconData(v), Icons.roundabout_right_rounded);
    });

    test('24. roundabout exit 1/2/3 remains correct in NL/EN/FR/ES', () {
      expect(driverRoundaboutExitOrdinal(1, _trNl), '1ste');
      expect(driverRoundaboutExitOrdinal(2, _trNl), '2de');
      expect(driverRoundaboutExitOrdinal(3, _trNl), '3de');

      expect(driverRoundaboutExitOrdinal(1, _trEn), '1st');
      expect(driverRoundaboutExitOrdinal(2, _trEn), '2nd');
      expect(driverRoundaboutExitOrdinal(3, _trEn), '3rd');
      expect(driverRoundaboutExitOrdinal(11, _trEn), '11th');

      expect(driverRoundaboutExitOrdinal(1, _trFr), '1re');
      expect(driverRoundaboutExitOrdinal(2, _trFr), '2e');
      expect(driverRoundaboutExitOrdinal(3, _trFr), '3e');

      expect(driverRoundaboutExitOrdinal(1, _trEs), '1ª');
      expect(driverRoundaboutExitOrdinal(2, _trEs), '2ª');
      expect(driverRoundaboutExitOrdinal(3, _trEs), '3ª');
    });

    test(
      '25. Portuguese roundabout exit 1/2/3/later use PT ordinal + sentence',
      () {
        // Feminine ordinal (matches noun `saída`).
        expect(driverRoundaboutExitOrdinalPortuguese(1), '1.ª');
        expect(driverRoundaboutExitOrdinalPortuguese(2), '2.ª');
        expect(driverRoundaboutExitOrdinalPortuguese(3), '3.ª');
        expect(driverRoundaboutExitOrdinalPortuguese(4), '4.ª');
        expect(driverRoundaboutExitOrdinalPortuguese(11), '11.ª');
        expect(driverRoundaboutExitOrdinalPortuguese(21), '21.ª');
        // Never fall back to English form for pt.
        expect(driverRoundaboutExitOrdinalPortuguese(1), isNot('1st'));
        expect(driverRoundaboutExitOrdinalPortuguese(2), isNot('2nd'));

        // Sentence form used on the second line of the roundabout banner.
        expect(driverRoundaboutExitLinePortuguese(1), 'Pegue a 1.ª saída');
        expect(driverRoundaboutExitLinePortuguese(2), 'Pegue a 2.ª saída');
        expect(driverRoundaboutExitLinePortuguese(3), 'Pegue a 3.ª saída');
        expect(driverRoundaboutExitLinePortuguese(11), 'Pegue a 11.ª saída');
      },
    );

    test('26. missing roundabout exit invents no ordinal', () {
      expect(resolveDriverRoundaboutExitNumber(null), isNull);
      expect(resolveDriverRoundaboutExitNumber(''), isNull);
      expect(resolveDriverRoundaboutExitNumber(' '), isNull);
      expect(resolveDriverRoundaboutExitNumber('0'), isNull);
      expect(resolveDriverRoundaboutExitNumber('-1'), isNull);
      expect(resolveDriverRoundaboutExitNumber('abc'), isNull);
      expect(resolveDriverRoundaboutExitNumber('2'), 2);
    });

    test(
      '27. arrival/merge/fork/ramp/depart mappings remain green after this '
      'commit',
      () {
        expect(
          resolveDriverManeuverVisual(_snap(type: 'arrive')),
          ManeuverVisual.arrive,
        );
        expect(
          resolveDriverManeuverVisual(_snap(type: 'merge')),
          ManeuverVisual.merge,
        );
        expect(
          resolveDriverManeuverVisual(_snap(type: 'fork')),
          ManeuverVisual.fork,
        );
        expect(
          resolveDriverManeuverVisual(_snap(type: 'off ramp')),
          ManeuverVisual.offRamp,
        );
        expect(
          resolveDriverManeuverVisual(_snap(type: 'on ramp')),
          ManeuverVisual.onRamp,
        );
        expect(
          resolveDriverManeuverVisual(_snap(type: 'depart')),
          ManeuverVisual.depart,
        );

        // Icon visuals match.
        expect(
          driverManeuverVisualIconData(ManeuverVisual.arrive),
          Icons.flag_rounded,
        );
        expect(
          driverManeuverVisualIconData(ManeuverVisual.merge),
          Icons.merge_rounded,
        );
        expect(
          driverManeuverVisualIconData(ManeuverVisual.fork),
          Icons.fork_right_rounded,
        );
        expect(
          driverManeuverVisualIconData(ManeuverVisual.offRamp),
          Icons.call_split_rounded,
        );
        expect(
          driverManeuverVisualIconData(ManeuverVisual.onRamp),
          Icons.alt_route_rounded,
        );
        expect(
          driverManeuverVisualIconData(ManeuverVisual.depart),
          Icons.navigation_rounded,
        );
      },
    );
  });
}
