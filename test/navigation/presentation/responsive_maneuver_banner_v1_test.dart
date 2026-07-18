import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/driver_theme_store.dart';
import 'package:fluxidi_tracking/driver_theme_palette.dart';
import 'package:fluxidi_tracking/navigation/driver_navigation_models.dart';
import 'package:fluxidi_tracking/navigation/presentation/maneuver_presentation.dart';
import 'package:fluxidi_tracking/navigation/widgets/navigation_driver_tablet_portrait_nav_layout.dart';
import 'package:fluxidi_tracking/widgets/driver_nav_banners.dart';

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

NavInstructionSnapshot _snap({
  required double distance,
  String type = 'turn',
  String modifier = '',
  String primary = '',
  String secondary = '',
  String? subText,
  String roadName = '',
  String? roadRef,
  String? destination,
  String? exitNumber,
  bool isHighwayLike = false,
  NavInstructionSource source = NavInstructionSource.banner,
}) {
  return NavInstructionSnapshot(
    distanceToManeuverMeters: distance,
    primaryText: primary,
    secondaryText: secondary,
    subText: subText,
    maneuverType: type,
    maneuverModifier: modifier,
    roadName: roadName,
    exitNumber: exitNumber,
    destinationText: destination,
    roadRef: roadRef,
    isHighwayLike: isHighwayLike,
    lanes: const <DriverNavLaneGuidance>[],
    source: source,
  );
}

ResponsiveManeuverPresentation _build(NavInstructionSnapshot snap) {
  return buildResponsiveManeuverPresentation(snapshot: snap, tr: _trNl);
}

Widget _wrap(Widget child, {Size size = const Size(400, 800)}) {
  return MediaQuery(
    data: MediaQueryData(size: size),
    child: Directionality(
      textDirection: TextDirection.ltr,
      child: MaterialApp(
        home: Scaffold(body: Center(child: child)),
      ),
    ),
  );
}

void main() {
  // Force deterministic theme (dark palette variant is background-only; text
  // rules do not depend on it).
  setUpAll(() {
    driverThemeNotifier.value = DriverThemeVariant.midnightBlue;
  });

  group('NAV-RESPONSIVE-MANEUVER-BANNER-V1 urgency phases', () {
    test('far / approaching / near / now thresholds are exact', () {
      expect(
        resolveDriverManeuverUrgencyPhase(50_000),
        ManeuverUrgencyPhase.far,
      );
      expect(resolveDriverManeuverUrgencyPhase(1500), ManeuverUrgencyPhase.far);
      expect(resolveDriverManeuverUrgencyPhase(1001), ManeuverUrgencyPhase.far);
      expect(
        resolveDriverManeuverUrgencyPhase(1000),
        ManeuverUrgencyPhase.approaching,
      );
      expect(
        resolveDriverManeuverUrgencyPhase(201),
        ManeuverUrgencyPhase.approaching,
      );
      expect(resolveDriverManeuverUrgencyPhase(200), ManeuverUrgencyPhase.near);
      expect(resolveDriverManeuverUrgencyPhase(51), ManeuverUrgencyPhase.near);
      expect(resolveDriverManeuverUrgencyPhase(50), ManeuverUrgencyPhase.now);
      expect(resolveDriverManeuverUrgencyPhase(0), ManeuverUrgencyPhase.now);
      expect(
        resolveDriverManeuverUrgencyPhase(double.nan),
        ManeuverUrgencyPhase.now,
      );
    });

    test('constants document the deterministic V1 thresholds', () {
      expect(kDriverManeuverPhaseFarThresholdMeters, 1000.0);
      expect(kDriverManeuverPhaseApproachingThresholdMeters, 200.0);
      expect(kDriverManeuverPhaseNearThresholdMeters, 50.0);
    });
  });

  group('NAV-RESPONSIVE-MANEUVER-BANNER-V1 turn wording', () {
    test(
      '1. far left turn -> "Volg de route" with standalone distance chip',
      () {
        final p = _build(
          _snap(
            distance: 50_000,
            modifier: 'left',
            primary: 'Turn left onto N454',
            roadRef: 'N454',
          ),
        );
        expect(p.maneuverVisual, ManeuverVisual.left);
        expect(p.urgencyPhase, ManeuverUrgencyPhase.far);
        expect(p.primaryInstruction, 'Volg de route');
        expect(p.distanceLabel, '50,0 km');
        expect(p.secondaryInstruction, 'naar N454');
      },
    );

    test('2. approaching left turn -> "Over 1 km linksaf" / "naar N454"', () {
      final p = _build(
        _snap(
          distance: 1000,
          modifier: 'left',
          primary: 'Turn left onto N454',
          roadRef: 'N454',
        ),
      );
      expect(p.maneuverVisual, ManeuverVisual.left);
      expect(p.urgencyPhase, ManeuverUrgencyPhase.approaching);
      expect(p.primaryInstruction, 'Over 1,0 km linksaf');
      expect(p.distanceLabel, '');
      expect(p.secondaryInstruction, 'naar N454');
    });

    test('3. near right turn -> "Over 150 m rechtsaf" / "naar N454"', () {
      final p = _build(
        _snap(
          distance: 150,
          modifier: 'right',
          primary: 'Turn right onto N454',
          roadRef: 'N454',
        ),
      );
      expect(p.maneuverVisual, ManeuverVisual.right);
      expect(p.urgencyPhase, ManeuverUrgencyPhase.near);
      expect(p.primaryInstruction, 'Over 150 m rechtsaf');
      expect(p.distanceLabel, '');
      expect(p.secondaryInstruction, 'naar N454');
    });

    test(
      'example: 250 m right in approaching phase reads "Over 250 m rechtsaf"',
      () {
        final p = _build(
          _snap(
            distance: 250,
            modifier: 'right',
            primary: 'Turn right onto N454',
            roadRef: 'N454',
          ),
        );
        expect(p.urgencyPhase, ManeuverUrgencyPhase.approaching);
        expect(p.primaryInstruction, 'Over 250 m rechtsaf');
        expect(p.secondaryInstruction, 'naar N454');
      },
    );

    test('4. now left -> "Sla nu linksaf"', () {
      final p = _build(
        _snap(
          distance: 40,
          modifier: 'left',
          primary: 'Turn left',
          roadRef: 'N454',
        ),
      );
      expect(p.maneuverVisual, ManeuverVisual.left);
      expect(p.urgencyPhase, ManeuverUrgencyPhase.now);
      expect(p.primaryInstruction, 'Sla nu linksaf');
      expect(p.distanceLabel, '');
      expect(p.secondaryInstruction, 'naar N454');
    });

    test('slight and sharp variants produce clearly distinct wording', () {
      final slight = _build(_snap(distance: 250, modifier: 'slight left'));
      final sharp = _build(_snap(distance: 250, modifier: 'sharp right'));
      expect(slight.primaryInstruction, contains('flauw linksaf'));
      expect(sharp.primaryInstruction, contains('scherp rechtsaf'));
      expect(slight.maneuverVisual, ManeuverVisual.slightLeft);
      expect(sharp.maneuverVisual, ManeuverVisual.sharpRight);
    });
  });

  group('NAV-RESPONSIVE-MANEUVER-BANNER-V1 roundabout wording', () {
    NavInstructionSnapshot round(double d, {String? exit}) => _snap(
      distance: d,
      type: 'roundabout',
      modifier: '',
      primary: 'Take the 2nd exit',
      exitNumber: exit,
    );

    test('5. exit 1 -> "Neem de 1ste afslag"', () {
      final p = _build(round(400, exit: '1'));
      expect(p.maneuverVisual, ManeuverVisual.roundabout);
      expect(p.roundaboutExitNumber, 1);
      expect(p.primaryInstruction, 'Over 400 m de rotonde op');
      expect(p.secondaryInstruction, 'Neem de 1ste afslag');
    });

    test('6. exit 2 -> "Neem de 2de afslag"', () {
      final p = _build(round(400, exit: '2'));
      expect(p.roundaboutExitNumber, 2);
      expect(p.primaryInstruction, 'Over 400 m de rotonde op');
      expect(p.secondaryInstruction, 'Neem de 2de afslag');
    });

    test('7. exit 3 -> "Neem de 3de afslag"', () {
      final p = _build(round(400, exit: '3'));
      expect(p.roundaboutExitNumber, 3);
      expect(p.secondaryInstruction, 'Neem de 3de afslag');
      // 4+ ordinals stay in the same shape.
      expect(driverRoundaboutExitOrdinalDutch(4), '4de');
      expect(driverRoundaboutExitOrdinalDutch(5), '5de');
      expect(driverRoundaboutExitOrdinalDutch(11), '11de');
    });

    test('8. now roundabout phase -> "Op de rotonde"', () {
      final p = _build(round(40, exit: '2'));
      expect(p.urgencyPhase, ManeuverUrgencyPhase.now);
      expect(p.primaryInstruction, 'Op de rotonde');
      expect(p.distanceLabel, '');
      expect(p.secondaryInstruction, 'Neem de 2de afslag');
    });

    test('null exitNumber never invents an ordinal', () {
      final p = _build(round(400, exit: null));
      expect(p.roundaboutExitNumber, isNull);
      expect(p.primaryInstruction, 'Over 400 m de rotonde op');
      expect(p.secondaryInstruction, isNot(contains('afslag')));
    });

    test('English/Spanish/French ordinals match the language contract', () {
      expect(driverRoundaboutExitOrdinal(1, _trEn), '1st');
      expect(driverRoundaboutExitOrdinal(2, _trEn), '2nd');
      expect(driverRoundaboutExitOrdinal(3, _trEn), '3rd');
      expect(driverRoundaboutExitOrdinal(11, _trEn), '11th');
      expect(driverRoundaboutExitOrdinal(22, _trEn), '22nd');
    });
  });

  group('NAV-RESPONSIVE-MANEUVER-BANNER-V1 fallback safety', () {
    test(
      '9. unknown maneuver keeps the raw snapshot text and follow-route visual',
      () {
        final p = _build(
          _snap(
            distance: 300,
            type: 'random-mapbox-string',
            modifier: '',
            primary: 'Continue on service road',
            secondary: 'Toward parking',
            source: NavInstructionSource.step,
          ),
        );
        expect(p.maneuverVisual, ManeuverVisual.followRoute);
        expect(p.primaryInstruction, 'Continue on service road');
        expect(p.distanceLabel, '300 m');
      },
    );

    test(
      'policy neutral fallback becomes "Volg de route" regardless of raw text',
      () {
        final p = _build(
          _snap(
            distance: 8000,
            type: '',
            primary: 'Stale banner',
            source: NavInstructionSource.fallback,
            roadRef: 'A12',
          ),
        );
        expect(p.primaryInstruction, 'Volg de route');
        expect(p.distanceLabel, '8,0 km');
        expect(p.secondaryInstruction, 'naar A12');
      },
    );
  });

  group('NAV-RESPONSIVE-MANEUVER-BANNER-V1 responsive layout', () {
    testWidgets('10. phone portrait: icon + primary + secondary all visible', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(400, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final p = _build(
        _snap(
          distance: 250,
          modifier: 'left',
          primary: 'Turn left onto N454',
          roadRef: 'N454',
        ),
      );
      await tester.pumpWidget(
        _wrap(
          DriverTurnInstructionBanner(
            compact: false,
            isTablet: false,
            isArrival: false,
            isHighwayLike: false,
            distancePrefix: '',
            distanceText: p.distanceLabel,
            primaryText: p.primaryInstruction,
            secondaryText: p.secondaryInstruction,
            icon: driverManeuverVisualIconData(p.maneuverVisual),
            presentation: p,
          ),
        ),
      );
      await tester.pump();

      expect(find.byIcon(Icons.turn_left_rounded), findsOneWidget);
      expect(find.text('Over 250 m linksaf'), findsOneWidget);
      expect(find.text('naar N454'), findsOneWidget);
    });

    testWidgets(
      '11. phone landscape: compact 2-line layout keeps roundabout exit visible',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(800, 380));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final p = _build(
          _snap(
            distance: 400,
            type: 'roundabout',
            modifier: '',
            primary: 'Take the 2nd exit',
            exitNumber: '2',
          ),
        );
        await tester.pumpWidget(
          _wrap(
            DriverTurnInstructionBanner(
              compact: true,
              isTablet: false,
              topRowLandscape: true,
              isArrival: false,
              isHighwayLike: false,
              distancePrefix: '',
              distanceText: p.distanceLabel,
              primaryText: p.primaryInstruction,
              secondaryText: p.secondaryInstruction,
              icon: driverManeuverVisualIconData(p.maneuverVisual),
              presentation: p,
            ),
            size: const Size(800, 380),
          ),
        );
        await tester.pump();

        expect(find.byIcon(Icons.roundabout_right_rounded), findsOneWidget);
        expect(find.text('Over 400 m de rotonde op'), findsOneWidget);
        expect(
          find.text('Neem de 2de afslag'),
          findsOneWidget,
          reason: 'Roundabout exit line must survive landscape compression.',
        );
      },
    );

    testWidgets(
      '12. tablet portrait: presentation drives new wording while tablet metrics remain',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(834, 1194));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final p = _build(
          _snap(
            distance: 250,
            modifier: 'right',
            primary: 'Turn right onto N454',
            roadRef: 'N454',
          ),
        );
        const metrics = kDriverNavBannerPortraitTabletLayout;
        await tester.pumpWidget(
          _wrap(
            DriverTurnInstructionBanner(
              compact: false,
              isTablet: true,
              isArrival: false,
              isHighwayLike: false,
              distancePrefix: '',
              distanceText: p.distanceLabel,
              primaryText: p.primaryInstruction,
              secondaryText: p.secondaryInstruction,
              icon: driverManeuverVisualIconData(p.maneuverVisual),
              presentation: p,
              portraitTabletMetrics: metrics,
            ),
            size: const Size(834, 1194),
          ),
        );
        await tester.pump();

        expect(find.text('Over 250 m rechtsaf'), findsOneWidget);
        expect(find.text('naar N454'), findsOneWidget);
        expect(find.byIcon(Icons.turn_right_rounded), findsOneWidget);
      },
    );

    testWidgets(
      '13. long road name: primary maneuver line stays intact, secondary ellipsizes',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(380, 780));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        const longRef =
            'Very Very Very Long Road Reference That Should Ellipsize In Any Reasonable Layout';
        final p = _build(
          _snap(
            distance: 250,
            modifier: 'left',
            primary: 'Turn left',
            roadRef: longRef,
          ),
        );
        await tester.pumpWidget(
          _wrap(
            DriverTurnInstructionBanner(
              compact: false,
              isTablet: false,
              isArrival: false,
              isHighwayLike: false,
              distancePrefix: '',
              distanceText: p.distanceLabel,
              primaryText: p.primaryInstruction,
              secondaryText: p.secondaryInstruction,
              icon: driverManeuverVisualIconData(p.maneuverVisual),
              presentation: p,
            ),
            size: const Size(380, 780),
          ),
        );
        await tester.pump();

        expect(find.byIcon(Icons.turn_left_rounded), findsOneWidget);
        expect(find.text('Over 250 m linksaf'), findsOneWidget);
        final secondaryFinder = find.textContaining('naar');
        expect(secondaryFinder, findsOneWidget);
        final secondaryWidget = tester.widget<Text>(secondaryFinder);
        expect(secondaryWidget.overflow, TextOverflow.ellipsis);
        expect(secondaryWidget.maxLines, 1);
      },
    );
  });

  group('NAV-RESPONSIVE-MANEUVER-BANNER-V1 accessibility', () {
    test(
      'roundabout accessibility label describes distance + maneuver + exit',
      () {
        final p = _build(
          _snap(distance: 400, type: 'roundabout', exitNumber: '2'),
        );
        expect(
          p.accessibilityLabel,
          'Over 400 m de rotonde op. Neem de 2de afslag.',
        );
      },
    );

    test('now-phase left accessibility label mentions destination', () {
      final p = _build(_snap(distance: 30, modifier: 'left', roadRef: 'N454'));
      expect(p.accessibilityLabel, 'Sla nu linksaf. naar N454.');
    });
  });

  group('NAV-RESPONSIVE-MANEUVER-BANNER-V1 arrival', () {
    test('arrival is stable across every distance', () {
      for (final d in [3000.0, 800.0, 120.0, 20.0, 0.0]) {
        final p = _build(_snap(distance: d, type: 'arrive'));
        expect(p.isArrival, isTrue, reason: 'd=$d');
        expect(p.maneuverVisual, ManeuverVisual.arrive);
        expect(p.primaryInstruction, 'Bestemming bereikt');
        expect(p.distanceLabel, '', reason: 'd=$d');
      }
    });
  });
}
