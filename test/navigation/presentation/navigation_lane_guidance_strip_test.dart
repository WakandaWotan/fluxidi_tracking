// NAV-PRESENTATION-COMPACT-BANNER-LANES-TELLERS-1 / Commit 2

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/driver_theme_palette.dart';
import 'package:fluxidi_tracking/navigation/driver_navigation_map_config.dart';
import 'package:fluxidi_tracking/navigation/driver_navigation_models.dart';
import 'package:fluxidi_tracking/navigation/presentation/navigation_lane_guidance_strip.dart';
import 'package:fluxidi_tracking/widgets/driver_nav_banners.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    home: Scaffold(
      body: ColoredBox(color: Colors.black, child: child),
    ),
  );
}

DriverThemePalette get _palette =>
    paletteForDriverTheme(DriverThemeVariant.nightGold);

Finder _col(int i) => find.byKey(ValueKey('nav_lane_column_$i'));

void main() {
  tearDown(() {
    debugDriverNavLaneGuidanceOverride = null;
  });

  group('driverLaneCombinedArrowGlyph', () {
    test('multiple indications stay one glyph string', () {
      const lane = DriverNavLaneGuidance(
        indications: <String>['straight', 'right'],
        valid: true,
        active: true,
      );
      final glyph = driverLaneCombinedArrowGlyph(lane, maneuverModifier: 'right');
      expect(glyph, contains('→'));
      expect(glyph, contains('↑'));
      expect(glyph.length, greaterThan(1));
    });

    test('single indication remains one arrow', () {
      const lane = DriverNavLaneGuidance(
        indications: <String>['left'],
        valid: true,
      );
      expect(driverLaneCombinedArrowGlyph(lane), '←');
    });
  });

  group('DriverNavLaneGuidanceStrip', () {
    testWidgets('empty lane data renders no strip', (tester) async {
      await tester.pumpWidget(
        _wrap(
          DriverNavLaneGuidanceStrip(
            lanes: const <DriverNavLaneGuidance>[],
            palette: _palette,
            metrics: DriverNavLaneStripMetrics.phone,
          ),
        ),
      );
      await tester.pump();
      expect(find.byKey(const ValueKey('nav_lane_guidance_strip')), findsNothing);
      expect(_col(0), findsNothing);
    });

    testWidgets('preserves Mapbox left-to-right order and exact count', (
      tester,
    ) async {
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
          indications: <String>['straight', 'right'],
          valid: true,
          active: true,
        ),
        const DriverNavLaneGuidance(
          indications: <String>['right'],
          valid: false,
        ),
        const DriverNavLaneGuidance(
          indications: <String>['right'],
          valid: true,
        ),
      ];
      await tester.pumpWidget(
        _wrap(
          DriverNavLaneGuidanceStrip(
            lanes: lanes,
            palette: _palette,
            metrics: DriverNavLaneStripMetrics.tablet,
            maneuverModifier: 'right',
          ),
        ),
      );
      await tester.pump();

      expect(find.byKey(const ValueKey('nav_lane_guidance_strip')), findsOneWidget);
      for (var i = 0; i < 5; i++) {
        expect(_col(i), findsOneWidget);
      }
      expect(_col(5), findsNothing);

      final left = tester.getTopLeft(_col(0));
      final mid = tester.getTopLeft(_col(2));
      final right = tester.getTopLeft(_col(4));
      expect(left.dx, lessThan(mid.dx));
      expect(mid.dx, lessThan(right.dx));
    });

    testWidgets('recommended lanes are visually distinct from subdued', (
      tester,
    ) async {
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
      await tester.pumpWidget(
        _wrap(
          DriverNavLaneGuidanceStrip(
            lanes: lanes,
            palette: _palette,
            metrics: DriverNavLaneStripMetrics.phone,
            maneuverModifier: 'right',
          ),
        ),
      );
      await tester.pump();

      final unavailable = tester.widget<Container>(
        find.descendant(of: _col(0), matching: find.byType(Container)).first,
      );
      final preferred = tester.widget<Container>(
        find.descendant(of: _col(1), matching: find.byType(Container)).first,
      );
      final uBorder =
          (unavailable.decoration! as BoxDecoration).border!.top.width;
      final pBorder =
          (preferred.decoration! as BoxDecoration).border!.top.width;
      expect(pBorder, greaterThan(uBorder));
      expect(pBorder, greaterThanOrEqualTo(2.0));
    });

    testWidgets('multiple indications remain one physical lane column', (
      tester,
    ) async {
      final lanes = <DriverNavLaneGuidance>[
        const DriverNavLaneGuidance(
          indications: <String>['straight', 'right'],
          valid: true,
          active: true,
        ),
      ];
      await tester.pumpWidget(
        _wrap(
          DriverNavLaneGuidanceStrip(
            lanes: lanes,
            palette: _palette,
            metrics: DriverNavLaneStripMetrics.phone,
            maneuverModifier: 'right',
          ),
        ),
      );
      await tester.pump();
      expect(_col(0), findsOneWidget);
      expect(_col(1), findsNothing);
      // Combined glyph rendered inside the single column.
      expect(find.textContaining('→'), findsOneWidget);
    });

    testWidgets(
      'secondary maneuver preview Icons cannot enter the lane strip',
      (tester) async {
        // The strip API accepts only DriverNavLaneGuidance — proving type
        // safety: IconData / maneuver preview widgets are not a valid input.
        await tester.pumpWidget(
          _wrap(
            DriverNavLaneGuidanceStrip(
              lanes: const <DriverNavLaneGuidance>[
                DriverNavLaneGuidance(
                  indications: <String>['right'],
                  valid: true,
                  active: true,
                ),
              ],
              palette: _palette,
              metrics: DriverNavLaneStripMetrics.phone,
            ),
          ),
        );
        await tester.pump();
        expect(find.byType(Icon), findsNothing);
        expect(find.byIcon(Icons.turn_right_rounded), findsNothing);
        expect(find.byIcon(Icons.turn_left_rounded), findsNothing);
        expect(find.text('→'), findsOneWidget);
      },
    );

    testWidgets('tablet metrics are larger than phone mini-icon era', (
      tester,
    ) async {
      expect(
        DriverNavLaneStripMetrics.tablet.arrowFontSize,
        greaterThan(20),
      );
      expect(
        DriverNavLaneStripMetrics.tablet.rowHeight,
        greaterThan(40),
      );
      expect(
        DriverNavLaneStripMetrics.phone.arrowFontSize,
        greaterThan(16),
      );
    });
  });

  group('banner integration — empty lanes consume zero height', () {
    testWidgets('gated-off lanes leave no strip under the banner', (
      tester,
    ) async {
      debugDriverNavLaneGuidanceOverride = false;
      await tester.pumpWidget(
        _wrap(
          DriverTurnInstructionBanner(
            compact: false,
            isTablet: false,
            isArrival: false,
            isHighwayLike: false,
            distancePrefix: '',
            distanceText: '120 m',
            primaryText: 'Turn right',
            secondaryText: '',
            icon: Icons.turn_right_rounded,
            lanes: const <DriverNavLaneGuidance>[
              DriverNavLaneGuidance(
                indications: <String>['right'],
                valid: true,
                active: true,
              ),
            ],
            themeListenable: ValueNotifier(DriverThemeVariant.nightGold),
          ),
        ),
      );
      await tester.pump();
      expect(find.byKey(const ValueKey('nav_lane_guidance_strip')), findsNothing);
      expect(_col(0), findsNothing);
    });
  });
}
