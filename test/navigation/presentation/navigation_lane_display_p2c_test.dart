import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/driver_theme_palette.dart';
import 'package:fluxidi_tracking/navigation/driver_navigation_formatters.dart';
import 'package:fluxidi_tracking/navigation/driver_navigation_map_config.dart';
import 'package:fluxidi_tracking/navigation/driver_navigation_models.dart';
import 'package:fluxidi_tracking/widgets/driver_nav_banners.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    home: Scaffold(
      body: ColoredBox(color: Colors.black, child: child),
    ),
  );
}

DriverTurnInstructionBanner _banner(List<DriverNavLaneGuidance> lanes) {
  return DriverTurnInstructionBanner(
    compact: false,
    isTablet: false,
    isArrival: false,
    isHighwayLike: false,
    distancePrefix: '',
    distanceText: '120 m',
    primaryText: 'Turn right',
    secondaryText: '',
    icon: Icons.turn_right_rounded,
    lanes: lanes,
    maneuverModifier: 'right',
    themeListenable: ValueNotifier<DriverThemeVariant>(
      DriverThemeVariant.nightGold,
    ),
  );
}

Finder _laneColumn(int index) => find.byKey(ValueKey('nav_lane_column_$index'));

void main() {
  tearDown(() {
    debugDriverNavLaneGuidanceOverride = null;
  });

  group('NAV-SIGNAL-P2C lane display contract', () {
    testWidgets('9: five resolved lanes render exactly five columns', (
      tester,
    ) async {
      debugDriverNavLaneGuidanceOverride = true;
      final lanes = <DriverNavLaneGuidance>[
        for (var i = 0; i < 5; i++)
          DriverNavLaneGuidance(
            indications: <String>[i == 4 ? 'right' : 'straight'],
            valid: i >= 3,
            active: i == 4 ? true : null,
          ),
      ];
      await tester.pumpWidget(_wrap(_banner(lanes)));
      await tester.pump();
      expect(_laneColumn(0), findsOneWidget);
      expect(_laneColumn(1), findsOneWidget);
      expect(_laneColumn(2), findsOneWidget);
      expect(_laneColumn(3), findsOneWidget);
      expect(_laneColumn(4), findsOneWidget);
      expect(_laneColumn(5), findsNothing);
    });

    testWidgets('10: four resolved lanes render exactly four columns', (
      tester,
    ) async {
      debugDriverNavLaneGuidanceOverride = true;
      final lanes = <DriverNavLaneGuidance>[
        const DriverNavLaneGuidance(
          indications: <String>['straight'],
          valid: false,
        ),
        const DriverNavLaneGuidance(
          indications: <String>['straight'],
          valid: true,
        ),
        const DriverNavLaneGuidance(
          indications: <String>['right'],
          valid: true,
        ),
        const DriverNavLaneGuidance(
          indications: <String>['right'],
          valid: true,
          active: true,
        ),
      ];
      await tester.pumpWidget(_wrap(_banner(lanes)));
      await tester.pump();
      expect(_laneColumn(0), findsOneWidget);
      expect(_laneColumn(3), findsOneWidget);
      expect(_laneColumn(4), findsNothing);
    });

    testWidgets('11: three resolved lanes render exactly three columns', (
      tester,
    ) async {
      debugDriverNavLaneGuidanceOverride = true;
      final lanes = <DriverNavLaneGuidance>[
        const DriverNavLaneGuidance(
          indications: <String>['left'],
          valid: false,
        ),
        const DriverNavLaneGuidance(
          indications: <String>['straight'],
          valid: true,
        ),
        const DriverNavLaneGuidance(
          indications: <String>['right'],
          valid: true,
          active: true,
        ),
      ];
      await tester.pumpWidget(_wrap(_banner(lanes)));
      await tester.pump();
      expect(_laneColumn(0), findsOneWidget);
      expect(_laneColumn(1), findsOneWidget);
      expect(_laneColumn(2), findsOneWidget);
      expect(_laneColumn(3), findsNothing);
    });

    testWidgets('12/14: empty indication does not remove a resolved column', (
      tester,
    ) async {
      debugDriverNavLaneGuidanceOverride = true;
      final lanes = <DriverNavLaneGuidance>[
        const DriverNavLaneGuidance(indications: <String>[], valid: false),
        const DriverNavLaneGuidance(
          indications: <String>['right'],
          valid: true,
          active: true,
        ),
      ];
      await tester.pumpWidget(_wrap(_banner(lanes)));
      await tester.pump();
      expect(_laneColumn(0), findsOneWidget);
      expect(_laneColumn(1), findsOneWidget);
      // Neutral glyph for empty indication (not shrink / not invented arrow).
      expect(find.text('·'), findsWidgets);
      expect(find.text('→'), findsOneWidget);
    });

    testWidgets('13: unsupported indication does not invent a known arrow', (
      tester,
    ) async {
      debugDriverNavLaneGuidanceOverride = true;
      final lanes = <DriverNavLaneGuidance>[
        const DriverNavLaneGuidance(
          indications: <String>['warp-drive'],
          valid: true,
        ),
        const DriverNavLaneGuidance(
          indications: <String>['left'],
          valid: false,
        ),
      ];
      await tester.pumpWidget(_wrap(_banner(lanes)));
      await tester.pump();
      expect(_laneColumn(0), findsOneWidget);
      expect(_laneColumn(1), findsOneWidget);
      expect(find.text('·'), findsOneWidget);
      expect(find.text('←'), findsOneWidget);
      expect(find.text('→'), findsNothing);
      expect(find.text('↑'), findsNothing);
    });

    testWidgets('6/7: preferred styling differs from usable and unavailable', (
      tester,
    ) async {
      debugDriverNavLaneGuidanceOverride = true;
      final lanes = <DriverNavLaneGuidance>[
        const DriverNavLaneGuidance(
          indications: <String>['straight'],
          valid: false,
        ),
        const DriverNavLaneGuidance(
          indications: <String>['straight'],
          valid: true,
        ),
        const DriverNavLaneGuidance(
          indications: <String>['right'],
          valid: true,
          active: true,
        ),
      ];
      await tester.pumpWidget(_wrap(_banner(lanes)));
      await tester.pump();

      final unavailable = tester.widget<Container>(
        find
            .descendant(of: _laneColumn(0), matching: find.byType(Container))
            .first,
      );
      final usable = tester.widget<Container>(
        find
            .descendant(of: _laneColumn(1), matching: find.byType(Container))
            .first,
      );
      final preferred = tester.widget<Container>(
        find
            .descendant(of: _laneColumn(2), matching: find.byType(Container))
            .first,
      );

      final unavailableBorder =
          (unavailable.decoration! as BoxDecoration).border!.top.width;
      final usableBorder =
          (usable.decoration! as BoxDecoration).border!.top.width;
      final preferredBorder =
          (preferred.decoration! as BoxDecoration).border!.top.width;

      expect(preferredBorder, greaterThan(usableBorder));
      expect(usableBorder, greaterThan(unavailableBorder));
      expect(
        driverLaneDisplayKind(lanes[0]),
        DriverLaneDisplayKind.unavailable,
      );
      expect(driverLaneDisplayKind(lanes[1]), DriverLaneDisplayKind.usable);
      expect(driverLaneDisplayKind(lanes[2]), DriverLaneDisplayKind.preferred);
    });

    testWidgets('15: source order remains left-to-right', (tester) async {
      debugDriverNavLaneGuidanceOverride = true;
      final lanes = <DriverNavLaneGuidance>[
        const DriverNavLaneGuidance(
          indications: <String>['left'],
          valid: false,
        ),
        const DriverNavLaneGuidance(
          indications: <String>['straight'],
          valid: true,
        ),
        const DriverNavLaneGuidance(
          indications: <String>['right'],
          valid: true,
          active: true,
        ),
      ];
      await tester.pumpWidget(_wrap(_banner(lanes)));
      await tester.pump();
      final left = tester.getTopLeft(_laneColumn(0));
      final mid = tester.getTopLeft(_laneColumn(1));
      final right = tester.getTopLeft(_laneColumn(2));
      expect(left.dx, lessThan(mid.dx));
      expect(mid.dx, lessThan(right.dx));
    });

    testWidgets('16: master flag false → zero displayed columns', (
      tester,
    ) async {
      debugDriverNavLaneGuidanceOverride = false;
      final lanes = <DriverNavLaneGuidance>[
        const DriverNavLaneGuidance(
          indications: <String>['straight'],
          valid: false,
        ),
        const DriverNavLaneGuidance(
          indications: <String>['right'],
          valid: true,
          active: true,
        ),
      ];
      await tester.pumpWidget(_wrap(_banner(lanes)));
      await tester.pump();
      expect(_laneColumn(0), findsNothing);
      expect(_laneColumn(1), findsNothing);
    });
  });
}
