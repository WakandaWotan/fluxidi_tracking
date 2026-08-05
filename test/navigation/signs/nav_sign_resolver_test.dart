import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/navigation/driver_navigation_models.dart';
import 'package:fluxidi_tracking/navigation/presentation/maneuver_presentation.dart';
import 'package:fluxidi_tracking/navigation/presentation/nav_sign_debug_catalog.dart';
import 'package:fluxidi_tracking/navigation/presentation/nav_sign_resolver.dart';

/// NAV-SIGNAGE-VISUAL-RELEASE-GATE: pure mapping proof for the sign resolver.
///
/// Every case below feeds the same field names the Mapbox route parser writes
/// into `DriverNavStep` (`maneuver.type`, `maneuver.modifier`, `maneuver.exit`,
/// `step.driving_side`), so nothing here depends on an invented event shape.
void main() {
  group('34 maneuver simulations: event -> maneuver id', () {
    for (final entry in kNavSignReferenceEntries) {
      test('${entry.inputLabel} -> ${entry.expected!.id}', () {
        final resolution = resolveNavSign(entry.event);
        expect(
          resolution.maneuver,
          entry.expected,
          reason:
              'input ${entry.event.diagnosticSignature} resolved to '
              '${resolution.maneuver.id}',
        );
      });
    }

    test('reference table covers all 34 signs exactly once', () {
      final covered = kNavSignReferenceEntries.map((e) => e.expected!).toSet();
      expect(covered.length, NavSignManeuver.values.length);
      expect(covered, containsAll(NavSignManeuver.values));
      expect(NavSignManeuver.values.length, 34);
    });

    test('every maneuver id is unique and snake_case', () {
      final ids = NavSignManeuver.values.map((m) => m.id).toList();
      expect(ids.toSet().length, ids.length);
      for (final id in ids) {
        expect(RegExp(r'^[a-z0-9_]+$').hasMatch(id), isTrue, reason: id);
      }
    });
  });

  group('roundabout exits are 1-based and never guessed', () {
    // Car enters at the bottom and travels anticlockwise in right-hand
    // traffic: exit 1 leaves right, 2 continues straight, 3 leaves left,
    // 4 turns back.
    const expectations = <String, NavSignManeuver>{
      '1': NavSignManeuver.roundaboutExit1,
      '2': NavSignManeuver.roundaboutExit2,
      '3': NavSignManeuver.roundaboutExit3,
      '4': NavSignManeuver.roundaboutExit4,
    };

    expectations.forEach((exit, expected) {
      test('exit $exit -> ${expected.id}', () {
        final resolution = resolveNavSign(
          NavSignEvent(maneuverType: 'roundabout', exitNumber: exit),
        );
        expect(resolution.maneuver, expected);
        expect(resolution.source, NavSignResolutionSource.roundaboutExit);
        expect(resolution.roundaboutExitNumber, int.parse(exit));
        expect(resolution.isFallback, isFalse);
      });
    });

    test('exit 1 is never shifted into the exit 2 sign (no zero-basing)', () {
      // A zero-based bug would show exit N+1 or N-1 artwork. Assert the whole
      // 1..4 band lines up ordinal-for-ordinal.
      for (var exit = 1; exit <= 4; exit++) {
        final resolution = resolveNavSign(
          NavSignEvent(maneuverType: 'roundabout', exitNumber: '$exit'),
        );
        expect(resolution.maneuver.id, 'roundabout_exit_$exit');
      }
    });

    test('exit 0 is bad data and must not become exit 1', () {
      final resolution = resolveNavSign(
        const NavSignEvent(maneuverType: 'roundabout', exitNumber: '0'),
      );
      expect(resolution.maneuver, NavSignManeuver.roundabout);
      expect(resolution.roundaboutExitNumber, isNull);
      expect(resolution.source, NavSignResolutionSource.roundaboutGeneric);
    });

    for (final bad in <String?>[null, '', '   ', '-1', '-3', 'abc', '2.5']) {
      test('untrusted exit ${bad ?? 'null'} -> generic roundabout', () {
        final resolution = resolveNavSign(
          NavSignEvent(maneuverType: 'roundabout', exitNumber: bad),
        );
        expect(resolution.maneuver, NavSignManeuver.roundabout);
        expect(resolution.roundaboutExitNumber, isNull);
      });
    }

    for (final undrawn in <String>['5', '6', '12']) {
      test('exit $undrawn has no artwork -> generic roundabout', () {
        final resolution = resolveNavSign(
          NavSignEvent(maneuverType: 'roundabout', exitNumber: undrawn),
        );
        expect(resolution.maneuver, NavSignManeuver.roundabout);
        // The ordinal is still trusted, so the wording can announce it.
        expect(resolution.roundaboutExitNumber, int.parse(undrawn));
      });
    }

    test('rotary and exit roundabout use the same roundabout family', () {
      for (final type in <String>[
        'rotary',
        'roundabout turn',
        'exit roundabout',
        'exit rotary',
      ]) {
        final resolution = resolveNavSign(
          NavSignEvent(maneuverType: type, exitNumber: '3'),
        );
        expect(
          resolution.maneuver,
          NavSignManeuver.roundaboutExit3,
          reason: type,
        );
      }
    });

    test('navSignRoundaboutExit matches the banner wording parser', () {
      for (final raw in <String?>[null, '', '0', '-2', 'x', '1', '4', '9']) {
        expect(
          navSignRoundaboutExit(raw),
          resolveDriverRoundaboutExitNumber(raw),
          reason: 'raw=$raw',
        );
      }
    });
  });

  group('T-junctions carry direction, not wording', () {
    test('end of road keeps the modifier direction', () {
      expect(
        resolveNavSign(
          const NavSignEvent(
            maneuverType: 'end of road',
            maneuverModifier: 'sharp left',
          ),
        ).maneuver,
        NavSignManeuver.tLeft,
      );
      expect(
        resolveNavSign(
          const NavSignEvent(
            maneuverType: 'end of road',
            maneuverModifier: 'slight right',
          ),
        ).maneuver,
        NavSignManeuver.tRight,
      );
    });

    test('end of road with a uturn modifier is a U-turn, not a T sign', () {
      expect(
        resolveNavSign(
          const NavSignEvent(
            maneuverType: 'end of road',
            maneuverModifier: 'uturn',
          ),
        ).maneuver,
        NavSignManeuver.uturnLeft,
      );
    });

    test('end of road without a modifier shows the junction only', () {
      final resolution = resolveNavSign(
        const NavSignEvent(maneuverType: 'end of road'),
      );
      expect(resolution.maneuver, NavSignManeuver.roadEnd);
      expect(resolution.source, NavSignResolutionSource.categoryFallback);
    });
  });

  group('driving side decides U-turns and unlabelled ramps', () {
    test('U-turn crosses oncoming traffic', () {
      expect(
        resolveNavSign(
          const NavSignEvent(maneuverType: 'turn', maneuverModifier: 'uturn'),
        ).maneuver,
        NavSignManeuver.uturnLeft,
        reason: 'right-hand traffic is the default',
      );
      expect(
        resolveNavSign(
          const NavSignEvent(
            maneuverType: 'turn',
            maneuverModifier: 'u-turn',
            drivingSide: 'LEFT',
          ),
        ).maneuver,
        NavSignManeuver.uturnRight,
      );
    });

    test('ramp without a modifier uses the near side of the carriageway', () {
      expect(
        resolveNavSign(const NavSignEvent(maneuverType: 'on ramp')).maneuver,
        NavSignManeuver.rampRight,
      );
      expect(
        resolveNavSign(
          const NavSignEvent(maneuverType: 'off ramp', drivingSide: 'left'),
        ).maneuver,
        NavSignManeuver.exitLeft,
      );
    });

    test('off ramp is an exit sign, on ramp is a ramp sign', () {
      expect(
        resolveNavSign(
          const NavSignEvent(
            maneuverType: 'off-ramp',
            maneuverModifier: 'slight right',
          ),
        ).maneuver,
        NavSignManeuver.exitRight,
      );
      expect(
        resolveNavSign(
          const NavSignEvent(
            maneuverType: 'on-ramp',
            maneuverModifier: 'slight left',
          ),
        ).maneuver,
        NavSignManeuver.rampLeft,
      );
    });
  });

  group('arrival and departure', () {
    test('arrive flips to reached inside the existing now band', () {
      expect(
        kNavSignDestinationReachedMeters,
        kDriverManeuverPhaseNearThresholdMeters,
      );
      expect(
        resolveNavSign(
          const NavSignEvent(
            maneuverType: 'arrive',
            distanceToManeuverMeters: kNavSignDestinationReachedMeters + 0.1,
          ),
        ).maneuver,
        NavSignManeuver.destinationAhead,
      );
      expect(
        resolveNavSign(
          const NavSignEvent(
            maneuverType: 'arrive',
            distanceToManeuverMeters: kNavSignDestinationReachedMeters,
          ),
        ).maneuver,
        NavSignManeuver.destinationReached,
      );
    });

    test('engine-confirmed arrival wins over distance', () {
      expect(
        resolveNavSign(
          const NavSignEvent(
            maneuverType: 'arrive',
            distanceToManeuverMeters: 400,
            arrivalConfirmed: true,
          ),
        ).maneuver,
        NavSignManeuver.destinationReached,
      );
    });

    test(
      'arrive without distance stays "ahead" rather than claiming arrival',
      () {
        expect(
          resolveNavSign(const NavSignEvent(maneuverType: 'arrive')).maneuver,
          NavSignManeuver.destinationAhead,
        );
        expect(
          resolveNavSign(
            const NavSignEvent(
              maneuverType: 'arrive',
              distanceToManeuverMeters: double.nan,
            ),
          ).maneuver,
          NavSignManeuver.destinationAhead,
        );
      },
    );

    test('depart ignores its modifier', () {
      for (final modifier in <String>['', 'left', 'right', 'straight']) {
        expect(
          resolveNavSign(
            NavSignEvent(maneuverType: 'depart', maneuverModifier: modifier),
          ).maneuver,
          NavSignManeuver.departure,
        );
      }
    });
  });

  group('unknown events never masquerade as a known maneuver', () {
    late List<String> logged;

    setUp(() {
      logged = <String>[];
      navSignDiagnosticSink = logged.add;
    });

    tearDown(() {
      navSignDiagnosticSink = debugPrint;
    });

    test('unrecognised type with no modifier falls back to follow_route', () {
      final resolution = resolveNavSign(
        const NavSignEvent(maneuverType: 'teleport'),
      );
      expect(resolution.maneuver, NavSignManeuver.followRoute);
      expect(resolution.source, NavSignResolutionSource.safeFallback);
      expect(resolution.isFallback, isTrue);
    });

    test('a neutral pipeline fallback never inherits a stale direction', () {
      final resolution = resolveNavSign(
        const NavSignEvent(
          maneuverType: 'turn',
          maneuverModifier: 'left',
          neutralFallback: true,
        ),
      );
      // Upright straight — not a premature left turn, not curved follow_route.
      expect(resolution.maneuver, NavSignManeuver.straight);
    });

    test('unrecognised type still honours a usable modifier', () {
      expect(
        resolveNavSign(
          const NavSignEvent(
            maneuverType: 'unmapped_engine_event',
            maneuverModifier: 'sharp right',
          ),
        ).maneuver,
        NavSignManeuver.sharpRight,
      );
    });

    test('fallbacks log type, modifier and exit and nothing else', () {
      resolveNavSign(
        const NavSignEvent(
          maneuverType: 'wormhole',
          maneuverModifier: '',
          exitNumber: '7',
        ),
      );
      expect(logged, hasLength(1));
      final line = logged.single;
      expect(line, contains('[NAV_SIGN_UNCLASSIFIED]'));
      expect(line, contains('type=wormhole'));
      expect(line, contains('modifier=-'));
      expect(line, contains('exit=7'));
      expect(line, contains('shown=follow_route'));
    });

    test('fully classified events log nothing', () {
      resolveNavSign(
        const NavSignEvent(maneuverType: 'turn', maneuverModifier: 'left'),
      );
      resolveNavSign(
        const NavSignEvent(maneuverType: 'roundabout', exitNumber: '2'),
      );
      expect(logged, isEmpty);
    });

    test('a diagnostic signature carries no road name or coordinates', () {
      const event = NavSignEvent(
        maneuverType: 'turn',
        maneuverModifier: 'left',
        exitNumber: '3',
      );
      expect(event.diagnosticSignature, 'type=turn modifier=left exit=3');
    });
  });

  group('language selection', () {
    test('the four shipped sets pass through unchanged', () {
      for (final code in kNavSignLanguageCodes) {
        expect(resolveNavSignLanguageCode(code), code);
      }
      expect(kNavSignLanguageCodes, <String>['nl', 'en', 'fr', 'es']);
    });

    test('region and case variants collapse to the base language', () {
      expect(resolveNavSignLanguageCode('nl_BE'), 'nl');
      expect(resolveNavSignLanguageCode('EN-GB'), 'en');
      expect(resolveNavSignLanguageCode('FR'), 'fr');
      expect(resolveNavSignLanguageCode(' es '), 'es');
    });

    test('unsupported locales fall back to nl', () {
      for (final code in <String?>[null, '', '  ', 'de', 'pt', 'it', 'zz']) {
        expect(resolveNavSignLanguageCode(code), 'nl', reason: '$code');
      }
      expect(kNavSignFallbackLanguageCode, 'nl');
    });

    test('asset paths follow png/<language>/<maneuver_id>.png', () {
      expect(
        navSignAssetPath(
          languageCode: 'fr',
          maneuver: NavSignManeuver.roundaboutExit2,
        ),
        'assets/fluxidi_navigation_signs_v3/png/fr/roundabout_exit_2.png',
      );
      expect(
        navSignAssetPath(
          languageCode: 'de',
          maneuver: NavSignManeuver.turnLeft,
        ),
        'assets/fluxidi_navigation_signs_v3/png/nl/turn_left.png',
      );
    });

    test('the full path set is 34 x 4 with no duplicates', () {
      final paths = navSignAllAssetPaths();
      expect(paths, hasLength(136));
      expect(paths.toSet(), hasLength(136));
    });
  });

  group('presentation carries the resolved sign', () {
    NavInstructionSnapshot snap({
      required String type,
      String modifier = '',
      String? exitNumber,
      double distance = 300,
    }) {
      return NavInstructionSnapshot(
        distanceToManeuverMeters: distance,
        primaryText: 'Primary',
        secondaryText: 'Secondary',
        maneuverType: type,
        maneuverModifier: modifier,
        roadName: 'Teststraat',
        exitNumber: exitNumber,
        isHighwayLike: false,
        lanes: const <DriverNavLaneGuidance>[],
        source: NavInstructionSource.banner,
      );
    }

    String tr({
      required String nl,
      required String en,
      required String fr,
      required String es,
    }) => nl;

    test('sign, language and path travel on the presentation model', () {
      final presentation = buildResponsiveManeuverPresentation(
        snapshot: snap(type: 'roundabout', exitNumber: '3'),
        tr: tr,
        languageCode: 'fr',
      );
      expect(presentation.signManeuver, NavSignManeuver.roundaboutExit3);
      expect(presentation.signLanguageCode, 'fr');
      expect(
        presentation.signAssetPath,
        'assets/fluxidi_navigation_signs_v3/png/fr/roundabout_exit_3.png',
      );
      expect(presentation.roundaboutExitNumber, 3);
    });

    test('an unsupported presentation language falls back to nl', () {
      final presentation = buildResponsiveManeuverPresentation(
        snapshot: snap(type: 'turn', modifier: 'left'),
        tr: tr,
        languageCode: 'de',
      );
      expect(presentation.signLanguageCode, 'nl');
      expect(presentation.signManeuver, NavSignManeuver.turnLeft);
    });

    test('driving side reaches the resolver through the presentation', () {
      final presentation = buildResponsiveManeuverPresentation(
        snapshot: snap(type: 'turn', modifier: 'uturn'),
        tr: tr,
        languageCode: 'en',
        drivingSide: 'left',
      );
      expect(presentation.signManeuver, NavSignManeuver.uturnRight);
    });
  });
}
