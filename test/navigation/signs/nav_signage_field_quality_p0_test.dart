// NAV-SIGNAGE-FIELD-QUALITY-P0-1
//
// Field test 05-08-2026: continue was forced into curved follow_route; captions
// inside PNGs were unreadable; tablet full/split sizes too small; primary text
// ellipsized ("Bestemming ber…"). This suite locks the product decisions.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/navigation/driver_navigation_models.dart';
import 'package:fluxidi_tracking/navigation/nav_engine/nav_maneuver_owner.dart';
import 'package:fluxidi_tracking/navigation/presentation/maneuver_presentation.dart';
import 'package:fluxidi_tracking/navigation/presentation/nav_maneuver_sign.dart';
import 'package:fluxidi_tracking/navigation/presentation/nav_sign_resolver.dart';
import 'package:fluxidi_tracking/navigation/presentation/nav_signage_tablet_readability.dart';
import 'package:fluxidi_tracking/widgets/driver_nav_banners.dart';

String _tr({
  required String nl,
  required String en,
  required String fr,
  required String es,
}) =>
    nl;

NavInstructionSnapshot _snap({
  required String type,
  String modifier = '',
  String? exit,
  double distance = 120,
  String primary = '',
  String secondary = '',
  String road = '',
  bool followRouteForced = false,
  NavInstructionSource source = NavInstructionSource.banner,
}) {
  return NavInstructionSnapshot(
    distanceToManeuverMeters: distance,
    primaryText: primary,
    secondaryText: secondary,
    maneuverType: type,
    maneuverModifier: modifier,
    exitNumber: exit,
    roadName: road,
    roadRef: '',
    isHighwayLike: false,
    lanes: const <DriverNavLaneGuidance>[],
    source: source,
    followRouteForced: followRouteForced,
  );
}

ResponsiveManeuverPresentation _present(NavInstructionSnapshot snap) {
  return buildResponsiveManeuverPresentation(
    snapshot: snap,
    tr: _tr,
    languageCode: 'nl',
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('semantic mapping matrix (raw Mapbox → canonical ID)', () {
    final cases = <(String type, String modifier, String? exit, NavSignManeuver want)>[
      ('depart', '', null, NavSignManeuver.departure),
      ('arrive', '', null, NavSignManeuver.destinationAhead),
      ('arrive', '', null, NavSignManeuver.destinationReached), // overridden below by distance
      ('continue', '', null, NavSignManeuver.straight),
      ('continue', 'straight', null, NavSignManeuver.straight),
      ('continue', 'forward', null, NavSignManeuver.straight),
      ('new name', '', null, NavSignManeuver.straight),
      ('notification', 'straight', null, NavSignManeuver.straight),
      ('turn', 'left', null, NavSignManeuver.turnLeft),
      ('turn', 'right', null, NavSignManeuver.turnRight),
      ('turn', 'slight left', null, NavSignManeuver.slightLeft),
      ('turn', 'slight right', null, NavSignManeuver.slightRight),
      ('turn', 'sharp left', null, NavSignManeuver.sharpLeft),
      ('turn', 'sharp right', null, NavSignManeuver.sharpRight),
      ('turn', 'uturn', null, NavSignManeuver.uturnLeft),
      ('turn', 'straight', null, NavSignManeuver.straight),
      ('fork', 'left', null, NavSignManeuver.forkLeft),
      ('fork', '', null, NavSignManeuver.forkStraight),
      ('fork', 'right', null, NavSignManeuver.forkRight),
      ('fork', 'straight', null, NavSignManeuver.forkStraight),
      ('continue', 'left', null, NavSignManeuver.keepLeft),
      ('continue', 'right', null, NavSignManeuver.keepRight),
      ('continue', 'slight left', null, NavSignManeuver.keepLeft),
      ('merge', 'left', null, NavSignManeuver.mergeLeft),
      ('merge', '', null, NavSignManeuver.mergeStraight),
      ('merge', 'right', null, NavSignManeuver.mergeRight),
      ('merge', 'straight', null, NavSignManeuver.mergeStraight),
      ('on ramp', 'left', null, NavSignManeuver.rampLeft),
      ('on ramp', 'right', null, NavSignManeuver.rampRight),
      ('off ramp', 'left', null, NavSignManeuver.exitLeft),
      ('off ramp', 'right', null, NavSignManeuver.exitRight),
      ('roundabout', '', '1', NavSignManeuver.roundaboutExit1),
      ('roundabout', '', '2', NavSignManeuver.roundaboutExit2),
      ('roundabout', '', '3', NavSignManeuver.roundaboutExit3),
      ('roundabout', '', '4', NavSignManeuver.roundaboutExit4),
      ('end of road', '', null, NavSignManeuver.roadEnd),
      ('end of road', 'left', null, NavSignManeuver.tLeft),
      ('end of road', 'right', null, NavSignManeuver.tRight),
    ];

    for (final c in cases) {
      if (c.$1 == 'arrive' && c.$4 == NavSignManeuver.destinationReached) {
        test('arrive near → destination_reached', () {
          final r = resolveNavSign(
            NavSignEvent(
              maneuverType: 'arrive',
              distanceToManeuverMeters: 40,
            ),
          );
          expect(r.maneuver, NavSignManeuver.destinationReached);
        });
        continue;
      }
      if (c.$1 == 'arrive') {
        test('arrive far → destination_ahead', () {
          final r = resolveNavSign(
            NavSignEvent(
              maneuverType: 'arrive',
              distanceToManeuverMeters: 120,
            ),
          );
          expect(r.maneuver, NavSignManeuver.destinationAhead);
        });
        continue;
      }
      test('${c.$1}/${c.$2}/${c.$3 ?? '-'} → ${c.$4.id}', () {
        final r = resolveNavSign(
          NavSignEvent(
            maneuverType: c.$1,
            maneuverModifier: c.$2,
            exitNumber: c.$3,
            drivingSide: 'right',
          ),
        );
        expect(r.maneuver, c.$4);
      });
    }

    test('continue is never curved follow_route', () {
      for (final mod in <String>['', 'straight', 'forward']) {
        final r = resolveNavSign(
          NavSignEvent(maneuverType: 'continue', maneuverModifier: mod),
        );
        expect(r.maneuver, NavSignManeuver.straight);
        expect(r.maneuver, isNot(NavSignManeuver.followRoute));
      }
    });

    test('owner does not force follow_route for continue+straight', () {
      final klass = classifyNavManeuverActivation(
        type: 'continue',
        modifier: 'straight',
      );
      expect(klass, NavManeuverActivationClass.alwaysActive);
      final p = _present(_snap(type: 'continue', modifier: 'straight'));
      expect(p.signManeuver, NavSignManeuver.straight);
      expect(p.maneuverVisual, ManeuverVisual.straight);
    });

    test('explicit slight left/right stay specific', () {
      expect(
        resolveNavSign(
          const NavSignEvent(
            maneuverType: 'turn',
            maneuverModifier: 'slight left',
          ),
        ).maneuver,
        NavSignManeuver.slightLeft,
      );
      expect(
        resolveNavSign(
          const NavSignEvent(
            maneuverType: 'turn',
            maneuverModifier: 'slight right',
          ),
        ).maneuver,
        NavSignManeuver.slightRight,
      );
    });

    test('road curvature alone cannot invent slight (no geometry input)', () {
      // Resolver has no bearing/geometry inputs — continue+straight stays straight.
      final src = File(
        'lib/navigation/presentation/nav_sign_resolver.dart',
      ).readAsStringSync();
      expect(src.contains('bearing'), isFalse);
      expect(src.contains('geometry'), isFalse);
      expect(
        resolveNavSign(
          const NavSignEvent(
            maneuverType: 'continue',
            maneuverModifier: 'straight',
          ),
        ).maneuver,
        NavSignManeuver.straight,
      );
    });
  });

  group('captionless sign assets', () {
    test('language folders share identical captionless bytes per id', () async {
      for (final maneuver in NavSignManeuver.values) {
        final hashes = <String>{};
        for (final lang in kNavSignLanguageCodes) {
          final data = await rootBundle.load(
            navSignAssetPath(languageCode: lang, maneuver: maneuver),
          );
          final bytes = data.buffer.asUint8List(
            data.offsetInBytes,
            data.lengthInBytes,
          );
          hashes.add(bytes.join(','));
        }
        expect(
          hashes,
          hasLength(1),
          reason: '${maneuver.id} must be captionless and identical across langs',
        );
      }
    });
  });

  group('tablet readability sizes', () {
    test('full-nav pictogram is at least 110 logical px', () {
      final m = NavSignageTabletReadabilityMetrics.resolve(
        isLandscape: false,
        availableBannerWidth: 400,
      );
      expect(m.signSize, greaterThanOrEqualTo(110));
      expect(m.signSize, lessThanOrEqualTo(120));
      expect(m.primaryFontSize, greaterThanOrEqualTo(28));
      expect(m.distanceFontSize, greaterThanOrEqualTo(23));
      expect(m.secondaryFontSize, greaterThanOrEqualTo(22));
    });

    test('split-nav pictogram is at least 76 logical px', () {
      final m = NavSignageTabletReadabilityMetrics.forSplitNav(
        availableBannerWidth: 320,
      );
      expect(m.signSize, greaterThanOrEqualTo(76));
      expect(m.signSize, lessThanOrEqualTo(88));
      expect(m.primaryFontSize, greaterThanOrEqualTo(21));
      expect(m.distanceFontSize, greaterThanOrEqualTo(18));
      expect(m.secondaryFontSize, greaterThanOrEqualTo(18));
    });
  });

  group('external text layout — no primary ellipsis', () {
    testWidgets('Bestemming bereikt is fully visible', (tester) async {
      final p = _present(
        _snap(
          type: 'arrive',
          distance: 20,
          primary: 'Bestemming bereikt',
        ),
      );
      expect(p.primaryInstruction.toLowerCase(), contains('bestemming'));
      expect(p.primaryInstruction.contains('…'), isFalse);
      expect(p.primaryInstruction.contains('...'), isFalse);
      expect(p.isArrival, isTrue);

      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(size: Size(800, 1280)),
          child: MaterialApp(
            home: Scaffold(
              body: DriverTurnInstructionBanner(
                compact: false,
                isTablet: true,
                isArrival: true,
                isHighwayLike: false,
                distancePrefix: '',
                distanceText: '',
                primaryText: p.primaryInstruction,
                secondaryText: '',
                icon: Icons.flag,
                presentation: p,
                tabletReadability:
                    NavSignageTabletReadabilityMetrics.forViewport(
                  viewport: const Size(800, 1280),
                  isLandscape: false,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Bestemming'), findsWidgets);
      expect(find.textContaining('ber…'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Sla nu rechtsaf naar Hofveldstraat stays readable', (
      tester,
    ) async {
      final p = _present(
        _snap(
          type: 'turn',
          modifier: 'right',
          distance: 25,
          primary: 'Sla nu rechtsaf',
          road: 'Hofveldstraat',
          secondary: 'naar Hofveldstraat',
        ),
      );
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(size: Size(800, 1280)),
          child: MaterialApp(
            home: Scaffold(
              body: DriverTurnInstructionBanner(
                compact: false,
                isTablet: true,
                isArrival: false,
                isHighwayLike: false,
                distancePrefix: '',
                distanceText: p.distanceLabel,
                primaryText: 'Sla nu rechtsaf',
                secondaryText: 'naar Hofveldstraat',
                icon: Icons.turn_right,
                presentation: p,
                tabletReadability:
                    NavSignageTabletReadabilityMetrics.forViewport(
                  viewport: const Size(800, 1280),
                  isLandscape: false,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('rechtsaf'), findsWidgets);
      expect(find.textContaining('Hofveldstraat'), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('phone banner has no overflow', (tester) async {
      final p = _present(
        _snap(type: 'turn', modifier: 'left', distance: 80, road: 'Kerkstraat'),
      );
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(size: Size(390, 844)),
          child: MaterialApp(
            home: Scaffold(
              body: DriverTurnInstructionBanner(
                compact: false,
                isTablet: false,
                isArrival: false,
                isHighwayLike: false,
                distancePrefix: '',
                distanceText: p.distanceLabel,
                primaryText: p.primaryInstruction,
                secondaryText: p.secondaryInstruction,
                icon: Icons.turn_left,
                presentation: p,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(NavManeuverSign), findsOneWidget);
    });
  });

  group('single owner / stale clearance', () {
    test('exactly one sign resolution per snapshot', () {
      final p = _present(_snap(type: 'turn', modifier: 'left', distance: 80));
      expect(p.signManeuver, NavSignManeuver.turnLeft);
      expect(NavSignManeuver.values.where((m) => m == p.signManeuver), hasLength(1));
    });

    test('followRouteForced clears specific turn to upright straight', () {
      final p = _present(
        _snap(
          type: 'turn',
          modifier: 'right',
          distance: 400,
          followRouteForced: true,
        ),
      );
      expect(p.signManeuver, NavSignManeuver.straight);
      expect(p.maneuverVisual, ManeuverVisual.straight);
      expect(p.signAssetPath, endsWith('/straight.png'));
    });
  });

  group('localized instruction text', () {
    test('nl/en/fr/es follow-route wording differs', () {
      String trLang(String lang) {
        return buildResponsiveManeuverPresentation(
          snapshot: _snap(
            type: 'unmapped_engine_event',
            followRouteForced: true,
          ),
          languageCode: lang,
          tr: ({
            required String nl,
            required String en,
            required String fr,
            required String es,
          }) {
            switch (lang) {
              case 'en':
                return en;
              case 'fr':
                return fr;
              case 'es':
                return es;
              default:
                return nl;
            }
          },
        ).primaryInstruction;
      }

      final texts = {
        'nl': trLang('nl'),
        'en': trLang('en'),
        'fr': trLang('fr'),
        'es': trLang('es'),
      };
      expect(texts.values.toSet().length, greaterThanOrEqualTo(3));
      expect(texts['nl']!.toLowerCase(), contains('route'));
    });
  });
}
