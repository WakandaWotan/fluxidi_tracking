import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/driver_theme_palette.dart';
import 'package:fluxidi_tracking/driver_theme_store.dart';
import 'package:fluxidi_tracking/navigation/driver_navigation_models.dart';
import 'package:fluxidi_tracking/navigation/presentation/maneuver_presentation.dart';
import 'package:fluxidi_tracking/navigation/presentation/nav_maneuver_sign.dart';
import 'package:fluxidi_tracking/navigation/presentation/nav_sign_resolver.dart';
import 'package:fluxidi_tracking/widgets/driver_nav_banners.dart';

/// NAV-SIGNAGE-VISUAL-RELEASE-GATE: widget-level proof that the banner shows
/// exactly one sign, in exactly one language, and repaints on every change.

String _trNl({
  required String nl,
  required String en,
  required String fr,
  required String es,
}) => nl;

NavInstructionSnapshot _snap({
  required String type,
  String modifier = '',
  String? exitNumber,
  double distance = 300,
  String primary = 'Primary',
  String secondary = '',
  String roadName = 'Teststraat',
  NavInstructionSource source = NavInstructionSource.banner,
}) {
  return NavInstructionSnapshot(
    distanceToManeuverMeters: distance,
    primaryText: primary,
    secondaryText: secondary,
    maneuverType: type,
    maneuverModifier: modifier,
    roadName: roadName,
    exitNumber: exitNumber,
    isHighwayLike: false,
    lanes: const <DriverNavLaneGuidance>[],
    source: source,
  );
}

ResponsiveManeuverPresentation _present(
  NavInstructionSnapshot snap, {
  String languageCode = 'nl',
}) => buildResponsiveManeuverPresentation(
  snapshot: snap,
  tr: _trNl,
  languageCode: languageCode,
);

Widget _wrap(Widget child, {Size size = const Size(400, 800)}) {
  return MediaQuery(
    data: MediaQueryData(size: size),
    child: Directionality(
      textDirection: TextDirection.ltr,
      child: MaterialApp(
        home: Scaffold(
          body: Align(alignment: Alignment.topCenter, child: child),
        ),
      ),
    ),
  );
}

DriverTurnInstructionBanner _banner(ResponsiveManeuverPresentation p) {
  return DriverTurnInstructionBanner(
    compact: false,
    isTablet: false,
    isArrival: p.isArrival,
    isHighwayLike: p.isHighwayLike,
    distancePrefix: '',
    distanceText: p.distanceLabel,
    primaryText: p.primaryInstruction,
    secondaryText: p.secondaryInstruction,
    icon: driverManeuverVisualIconData(p.maneuverVisual),
    presentation: p,
  );
}

/// The asset path of the single sign currently on screen.
String _visibleSignPath(WidgetTester tester) {
  final signs = tester.widgetList<NavManeuverSign>(
    find.byType(NavManeuverSign),
  );
  expect(signs, hasLength(1), reason: 'exactly one sign must be visible');
  return signs.single.assetPath;
}

/// The asset path of every `Image` actually mounted, sign or not.
///
/// Signs are decode-capped, so the provider is a [ResizeImage] wrapping the
/// [AssetImage]; both shapes are unwrapped here.
List<String> _mountedImageAssets(WidgetTester tester) {
  return tester
      .widgetList<Image>(find.byType(Image))
      .map((image) {
        final provider = image.image;
        return provider is ResizeImage ? provider.imageProvider : provider;
      })
      .whereType<AssetImage>()
      .map((provider) => provider.assetName)
      .toList();
}

void main() {
  setUpAll(() {
    driverThemeNotifier.value = DriverThemeVariant.midnightBlue;
  });

  group('NavManeuverSign loads one plate', () {
    testWidgets('renders the resolved asset at a bounded decode size', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const MediaQuery(
            data: MediaQueryData(devicePixelRatio: 3),
            child: NavManeuverSign(
              maneuver: NavSignManeuver.roundaboutExit2,
              languageCode: 'fr',
              size: 60,
            ),
          ),
        ),
      );
      final image = tester.widget<Image>(find.byType(Image));
      final provider = image.image as ResizeImage;
      expect(provider.width, 180);
      expect(provider.height, 180);
      expect(
        (provider.imageProvider as AssetImage).assetName,
        'assets/fluxidi_navigation_signs_v3/png/fr/roundabout_exit_2.png',
      );
    });

    testWidgets('an unsupported language falls back to nl, never to two', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const NavManeuverSign(
            maneuver: NavSignManeuver.turnLeft,
            languageCode: 'de',
            size: 60,
          ),
        ),
      );
      final sign = tester.widget<NavManeuverSign>(find.byType(NavManeuverSign));
      expect(sign.resolvedLanguageCode, 'nl');
      expect(_mountedImageAssets(tester), <String>[
        'assets/fluxidi_navigation_signs_v3/png/nl/turn_left.png',
      ]);
    });

    testWidgets('real bytes decode for a sign in every language', (
      tester,
    ) async {
      for (final language in kNavSignLanguageCodes) {
        await tester.pumpWidget(
          _wrap(
            NavManeuverSign(
              maneuver: NavSignManeuver.roundaboutExit3,
              languageCode: language,
              size: 96,
            ),
          ),
        );
        final element = tester.element(find.byType(NavManeuverSign));
        await tester.runAsync(() async {
          await precacheImage(
            AssetImage(
              navSignAssetPath(
                languageCode: language,
                maneuver: NavSignManeuver.roundaboutExit3,
              ),
            ),
            element,
          );
        });
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: language);
      }
    });
  });

  group('language is switched cleanly mid-session', () {
    testWidgets('switching language swaps the plate and drops the old one', (
      tester,
    ) async {
      final snapshot = _snap(type: 'turn', modifier: 'left');
      await tester.pumpWidget(
        _wrap(_banner(_present(snapshot, languageCode: 'nl'))),
      );
      expect(
        _visibleSignPath(tester),
        'assets/fluxidi_navigation_signs_v3/png/nl/turn_left.png',
      );

      for (final language in <String>['en', 'fr', 'es', 'nl']) {
        await tester.pumpWidget(
          _wrap(_banner(_present(snapshot, languageCode: language))),
        );
        await tester.pump();
        final mounted = _mountedImageAssets(tester);
        expect(mounted, <String>[
          'assets/fluxidi_navigation_signs_v3/png/$language/turn_left.png',
        ], reason: 'only the $language plate may be mounted');
      }
    });

    testWidgets('no two language variants are ever mounted together', (
      tester,
    ) async {
      final snapshot = _snap(type: 'roundabout', exitNumber: '2');
      for (final language in kNavSignLanguageCodes) {
        await tester.pumpWidget(
          _wrap(_banner(_present(snapshot, languageCode: language))),
        );
        await tester.pump();
        final languagesOnScreen = _mountedImageAssets(
          tester,
        ).map((path) => path.split('/')[3]).toSet();
        expect(languagesOnScreen, <String>{language});
      }
    });
  });

  group('runtime transitions', () {
    testWidgets('a full instruction sequence never shows a stale plate', (
      tester,
    ) async {
      final sequence = <(String, NavInstructionSnapshot, NavSignManeuver)>[
        (
          'departure',
          _snap(type: 'depart', distance: 900),
          NavSignManeuver.departure,
        ),
        (
          'follow_route',
          _snap(type: 'unmapped_engine_event', distance: 800),
          NavSignManeuver.followRoute,
        ),
        (
          'slight_right',
          _snap(type: 'turn', modifier: 'slight right', distance: 600),
          NavSignManeuver.slightRight,
        ),
        (
          'roundabout_exit_2',
          _snap(type: 'roundabout', exitNumber: '2', distance: 400),
          NavSignManeuver.roundaboutExit2,
        ),
        (
          'keep_left',
          _snap(type: 'continue', modifier: 'slight left', distance: 300),
          NavSignManeuver.keepLeft,
        ),
        (
          'exit_right',
          _snap(type: 'off ramp', modifier: 'right', distance: 200),
          NavSignManeuver.exitRight,
        ),
        (
          'destination_ahead',
          _snap(type: 'arrive', distance: 180),
          NavSignManeuver.destinationAhead,
        ),
        (
          'destination_reached',
          _snap(type: 'arrive', distance: 5),
          NavSignManeuver.destinationReached,
        ),
      ];

      String? previousPath;
      for (final (label, snapshot, expected) in sequence) {
        await tester.pumpWidget(_wrap(_banner(_present(snapshot))));
        await tester.pump();
        final path = _visibleSignPath(tester);
        expect(
          path,
          'assets/fluxidi_navigation_signs_v3/png/nl/${expected.id}.png',
          reason: 'step $label',
        );
        expect(
          _mountedImageAssets(tester),
          <String>[path],
          reason: 'step $label left an old plate mounted',
        );
        if (previousPath != null) {
          expect(path, isNot(previousPath), reason: 'step $label');
        }
        previousPath = path;
      }
    });

    testWidgets('rapid back-to-back instructions land on the last one', (
      tester,
    ) async {
      final rapid = <NavInstructionSnapshot>[
        _snap(type: 'turn', modifier: 'left'),
        _snap(type: 'turn', modifier: 'right'),
        _snap(type: 'roundabout', exitNumber: '4'),
        _snap(type: 'turn', modifier: 'sharp left'),
      ];
      for (final snapshot in rapid) {
        await tester.pumpWidget(_wrap(_banner(_present(snapshot))));
        // Deliberately no settle: the next instruction arrives on the very
        // next frame.
      }
      await tester.pump();
      expect(
        _visibleSignPath(tester),
        'assets/fluxidi_navigation_signs_v3/png/nl/sharp_left.png',
      );
      expect(_mountedImageAssets(tester), hasLength(1));
    });

    testWidgets('changing only the exit number repaints the sign', (
      tester,
    ) async {
      for (var exit = 1; exit <= 4; exit++) {
        await tester.pumpWidget(
          _wrap(
            _banner(_present(_snap(type: 'roundabout', exitNumber: '$exit'))),
          ),
        );
        await tester.pump();
        expect(
          _visibleSignPath(tester),
          'assets/fluxidi_navigation_signs_v3/png/nl/roundabout_exit_$exit.png',
        );
      }
    });

    testWidgets('changing only the modifier repaints the sign', (tester) async {
      const modifiers = <String, String>{
        'left': 'turn_left',
        'right': 'turn_right',
        'sharp left': 'sharp_left',
        'slight right': 'slight_right',
      };
      for (final entry in modifiers.entries) {
        await tester.pumpWidget(
          _wrap(_banner(_present(_snap(type: 'turn', modifier: entry.key)))),
        );
        await tester.pump();
        expect(
          _visibleSignPath(tester),
          'assets/fluxidi_navigation_signs_v3/png/nl/${entry.value}.png',
        );
      }
    });

    testWidgets('rerouting falls back to follow_route, not a wrong turn', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(_banner(_present(_snap(type: 'turn', modifier: 'left')))),
      );
      expect(
        _visibleSignPath(tester),
        'assets/fluxidi_navigation_signs_v3/png/nl/turn_left.png',
      );
      // A neutral pipeline fallback still carries the previous type/modifier.
      await tester.pumpWidget(
        _wrap(
          _banner(
            _present(
              _snap(
                type: 'turn',
                modifier: 'left',
                source: NavInstructionSource.fallback,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(
        _visibleSignPath(tester),
        'assets/fluxidi_navigation_signs_v3/png/nl/follow_route.png',
      );
    });

    testWidgets('the plate and the written instruction stay in sync', (
      tester,
    ) async {
      final presentation = _present(
        _snap(type: 'roundabout', exitNumber: '2', distance: 400),
      );
      await tester.pumpWidget(_wrap(_banner(presentation)));
      await tester.pump();
      expect(
        _visibleSignPath(tester),
        'assets/fluxidi_navigation_signs_v3/png/nl/roundabout_exit_2.png',
      );
      expect(presentation.roundaboutExitNumber, 2);
      expect(find.textContaining('2de afslag'), findsOneWidget);
    });

    testWidgets('an untrusted exit shows the generic plate and no ordinal', (
      tester,
    ) async {
      final presentation = _present(
        _snap(type: 'roundabout', exitNumber: '0', distance: 400),
      );
      await tester.pumpWidget(_wrap(_banner(presentation)));
      await tester.pump();
      expect(
        _visibleSignPath(tester),
        'assets/fluxidi_navigation_signs_v3/png/nl/roundabout.png',
      );
      expect(presentation.roundaboutExitNumber, isNull);
      expect(find.textContaining('afslag'), findsNothing);
    });
  });

  group('banner integration', () {
    testWidgets('a presentation-driven banner shows a sign, not a glyph', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(_banner(_present(_snap(type: 'turn', modifier: 'right')))),
      );
      expect(find.byType(NavManeuverSign), findsOneWidget);
      expect(find.byIcon(Icons.turn_right_rounded), findsNothing);
    });

    testWidgets('a legacy banner without a presentation keeps its glyph', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const DriverTurnInstructionBanner(
            compact: false,
            isTablet: false,
            isArrival: false,
            isHighwayLike: false,
            distancePrefix: 'Over',
            distanceText: '400 m',
            primaryText: 'Sla linksaf',
            secondaryText: '',
            icon: Icons.turn_left_rounded,
          ),
        ),
      );
      expect(find.byType(NavManeuverSign), findsNothing);
      expect(find.byIcon(Icons.turn_left_rounded), findsOneWidget);
    });
  });
}
