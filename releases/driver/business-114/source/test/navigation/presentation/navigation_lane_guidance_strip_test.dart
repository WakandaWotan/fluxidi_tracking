// NAV-PRESENTATION-COMPACT-BANNER-LANES-TELLERS-1 / Commit 2
// Extended by NAV-LANE-GUIDANCE-RELEASE-ENABLE-AND-READABILITY-1.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/driver_theme_palette.dart';
import 'package:fluxidi_tracking/navigation/driver_navigation_formatters.dart';
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

  // ==========================================================================
  // NAV-LANE-GUIDANCE-RELEASE-ENABLE-AND-READABILITY-1
  // ==========================================================================

  group('NAV-LANE-GUIDANCE-RELEASE-ENABLE feature default', () {
    test('1: unspecified compile-time env → master gate defaults enabled', () {
      // No dart-define, no debug override → release-default must be true.
      debugDriverNavLaneGuidanceOverride = null;
      expect(kDriverNavLaneGuidanceEnabled, isTrue);
      expect(driverNavLaneGuidanceFeatureEnabled, isTrue);
    });

    test('2: explicit debug override false disables the gate', () {
      debugDriverNavLaneGuidanceOverride = false;
      expect(driverNavLaneGuidanceFeatureEnabled, isFalse);
    });

    test('2b: explicit debug override true keeps the gate enabled', () {
      debugDriverNavLaneGuidanceOverride = true;
      expect(driverNavLaneGuidanceFeatureEnabled, isTrue);
    });

    testWidgets('3: master gate false still hides lanes in banner', (
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
                indications: <String>['left'],
                valid: false,
              ),
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
      expect(
        find.byKey(const ValueKey('nav_lane_guidance_strip')),
        findsNothing,
      );
    });

    testWidgets('7: no fixed count — one lane resolver output → one cell', (
      tester,
    ) async {
      // The strip must not pad, duplicate or fabricate lanes. Feeding a
      // single-lane list yields exactly one cell (this is the widget-level
      // contract; the resolver additionally hides single-lane cases).
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
            maneuverModifier: 'right',
          ),
        ),
      );
      await tester.pump();
      expect(_col(0), findsOneWidget);
      expect(_col(1), findsNothing);
    });
  });

  group('NAV-LANE-GUIDANCE-RELEASE readability metric floors', () {
    test('8: phone portrait metrics meet readable floor', () {
      const m = DriverNavLaneStripMetrics.phone;
      expect(m.rowHeight, greaterThanOrEqualTo(54));
      expect(m.rowHeight, lessThanOrEqualTo(58));
      expect(m.pillMinWidth, greaterThanOrEqualTo(48));
      expect(m.pillMinWidth, lessThanOrEqualTo(52));
      expect(m.arrowFontSize, greaterThanOrEqualTo(29));
      expect(m.arrowFontSize, lessThanOrEqualTo(32));
      expect(m.compact, isFalse);
    });

    test('9: phone landscape metrics meet readable floor', () {
      const m = DriverNavLaneStripMetrics.phoneLandscape;
      expect(m.rowHeight, greaterThanOrEqualTo(42));
      expect(m.rowHeight, lessThanOrEqualTo(46));
      expect(m.pillMinWidth, greaterThanOrEqualTo(38));
      expect(m.pillMinWidth, lessThanOrEqualTo(42));
      expect(m.arrowFontSize, greaterThanOrEqualTo(23));
      expect(m.arrowFontSize, lessThanOrEqualTo(26));
    });

    test('10: tablet portrait metrics meet readable floor', () {
      const m = DriverNavLaneStripMetrics.tablet;
      expect(m.rowHeight, greaterThanOrEqualTo(62));
      expect(m.rowHeight, lessThanOrEqualTo(68));
      expect(m.pillMinWidth, greaterThanOrEqualTo(56));
      expect(m.pillMinWidth, lessThanOrEqualTo(62));
      expect(m.arrowFontSize, greaterThanOrEqualTo(34));
      expect(m.arrowFontSize, lessThanOrEqualTo(38));
      expect(m.compact, isFalse);
    });

    test('11: tablet landscape metrics meet readable floor', () {
      const m = DriverNavLaneStripMetrics.tabletLandscape;
      expect(m.rowHeight, greaterThanOrEqualTo(48));
      expect(m.rowHeight, lessThanOrEqualTo(54));
      expect(m.pillMinWidth, greaterThanOrEqualTo(44));
      expect(m.pillMinWidth, lessThanOrEqualTo(50));
      expect(m.arrowFontSize, greaterThanOrEqualTo(27));
      expect(m.arrowFontSize, lessThanOrEqualTo(31));
    });

    test('non-compact metrics are strictly larger than landscape floors', () {
      expect(
        DriverNavLaneStripMetrics.phone.rowHeight,
        greaterThan(DriverNavLaneStripMetrics.phoneLandscape.rowHeight),
      );
      expect(
        DriverNavLaneStripMetrics.tablet.rowHeight,
        greaterThan(DriverNavLaneStripMetrics.tabletLandscape.rowHeight),
      );
      expect(
        DriverNavLaneStripMetrics.phone.arrowFontSize,
        greaterThan(DriverNavLaneStripMetrics.phoneLandscape.arrowFontSize),
      );
      expect(
        DriverNavLaneStripMetrics.tablet.arrowFontSize,
        greaterThan(DriverNavLaneStripMetrics.tabletLandscape.arrowFontSize),
      );
    });
  });

  group('NAV-LANE-GUIDANCE-RELEASE availability styling', () {
    Container containerOf(WidgetTester tester, int col) {
      return tester.widget<Container>(
        find.descendant(of: _col(col), matching: find.byType(Container)).first,
      );
    }

    double borderWidth(Container c) =>
        (c.decoration! as BoxDecoration).border!.top.width;
    List<BoxShadow>? shadowsOf(Container c) =>
        (c.decoration! as BoxDecoration).boxShadow;

    testWidgets(
      '12: preferred lane is visually stronger than usable lane',
      (tester) async {
        final lanes = <DriverNavLaneGuidance>[
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
        final usable = containerOf(tester, 0);
        final preferred = containerOf(tester, 1);
        expect(borderWidth(preferred), greaterThan(borderWidth(usable)));
        expect(borderWidth(preferred), greaterThanOrEqualTo(3.0));
        // Preferred pill also carries a subtle glow that usable lacks.
        expect((shadowsOf(preferred) ?? const <BoxShadow>[]).isNotEmpty, isTrue);
        expect(shadowsOf(usable) ?? const <BoxShadow>[], isEmpty);
      },
    );

    testWidgets('13: unavailable lane cannot look preferred', (tester) async {
      final lanes = <DriverNavLaneGuidance>[
        const DriverNavLaneGuidance(
          indications: <String>['left'],
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
      final unavailable = containerOf(tester, 0);
      final preferred = containerOf(tester, 1);
      expect(borderWidth(unavailable), lessThan(borderWidth(preferred)));
      expect(shadowsOf(unavailable) ?? const <BoxShadow>[], isEmpty);
    });

    testWidgets('14: unknown lane uses neutral styling (no glow, thin border)',
        (tester) async {
      // Missing valid + missing active → DriverLaneDisplayKind.unknown.
      final lanes = <DriverNavLaneGuidance>[
        const DriverNavLaneGuidance(indications: <String>['straight']),
      ];
      await tester.pumpWidget(
        _wrap(
          DriverNavLaneGuidanceStrip(
            lanes: lanes,
            palette: _palette,
            metrics: DriverNavLaneStripMetrics.phone,
          ),
        ),
      );
      await tester.pump();
      final unknown = containerOf(tester, 0);
      expect(borderWidth(unknown), lessThan(3.0));
      expect(shadowsOf(unknown) ?? const <BoxShadow>[], isEmpty);
    });
  });

  group('NAV-LANE-GUIDANCE-RELEASE layout overflow', () {
    List<DriverNavLaneGuidance> makeLanes(int count) => <DriverNavLaneGuidance>[
          for (var i = 0; i < count; i++)
            DriverNavLaneGuidance(
              indications: const <String>['straight'],
              valid: i == count - 1,
              active: i == count - 1 ? true : null,
            ),
        ];

    testWidgets('15: three-lane mixed state renders exactly three cells', (
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
          ),
        ),
      );
      await tester.pump();
      expect(_col(0), findsOneWidget);
      expect(_col(1), findsOneWidget);
      expect(_col(2), findsOneWidget);
      expect(_col(3), findsNothing);
    });

    testWidgets('17: six lanes render without overflow at phone portrait', (
      tester,
    ) async {
      // Constrain to a typical phone-portrait width.
      tester.view.physicalSize = const Size(380 * 3, 780 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      await tester.pumpWidget(
        _wrap(
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: DriverNavLaneGuidanceStrip(
              lanes: makeLanes(6),
              palette: _palette,
              metrics: DriverNavLaneStripMetrics.phone,
            ),
          ),
        ),
      );
      await tester.pump();
      for (var i = 0; i < 6; i++) {
        expect(_col(i), findsOneWidget);
      }
      final overflowError = tester.takeException();
      expect(overflowError, isNull);
    });

    testWidgets('18: eight lanes remain usable through horizontal scroll', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          SizedBox(
            width: 380,
            child: DriverNavLaneGuidanceStrip(
              lanes: makeLanes(8),
              palette: _palette,
              metrics: DriverNavLaneStripMetrics.phone,
            ),
          ),
        ),
      );
      await tester.pump();
      // First cell is attached.
      expect(_col(0), findsOneWidget);
      // Scrollable physics must be enabled for > 6 lanes so drivers can
      // reveal any far-right lane if the visible width is not enough.
      final listView = tester.widget<ListView>(find.byType(ListView));
      expect(listView.physics, isA<BouncingScrollPhysics>());
      // Reveal the far-right lane via ListView's own Scrollable, then
      // assert the tail cell is present in the widget tree.
      await tester.scrollUntilVisible(
        _col(7),
        56,
        scrollable: find.byType(Scrollable).first,
      );
      expect(_col(7), findsOneWidget);
    });
  });

  group('NAV-LANE-GUIDANCE-RELEASE accessibility', () {
    test('20: semantic label includes recommended/usable/unavailable state', () {
      const preferred = DriverNavLaneGuidance(
        indications: <String>['right'],
        valid: true,
        active: true,
      );
      const usable = DriverNavLaneGuidance(
        indications: <String>['straight'],
        valid: true,
      );
      const unavailable = DriverNavLaneGuidance(
        indications: <String>['left'],
        valid: false,
      );
      const unknown = DriverNavLaneGuidance(
        indications: <String>['straight'],
      );
      expect(
        driverLaneSemanticLabel(preferred),
        startsWith('Preferred lane'),
      );
      expect(driverLaneSemanticLabel(usable), startsWith('Usable lane'));
      expect(
        driverLaneSemanticLabel(unavailable),
        startsWith('Unavailable lane'),
      );
      expect(driverLaneSemanticLabel(unknown), startsWith('Lane'));
      // Semantic label additionally names the indication so recommended
      // versus non-recommended state is announced (not color-only).
      expect(
        driverLaneSemanticLabel(preferred, maneuverModifier: 'right'),
        contains('right'),
      );
      expect(driverLaneSemanticLabel(usable), contains('straight'));
      expect(driverLaneSemanticLabel(unavailable), contains('left'));
    });
  });

  group('NAV-LANE-GUIDANCE-RELEASE integration', () {
    testWidgets(
      '21: complexity caution stacked below banner does not overlap lane strip',
      (tester) async {
        final banner = DriverTurnInstructionBanner(
          compact: false,
          isTablet: false,
          isArrival: false,
          isHighwayLike: false,
          distancePrefix: 'In',
          distanceText: '120 m',
          primaryText: 'Turn right',
          secondaryText: '',
          icon: Icons.turn_right_rounded,
          lanes: const <DriverNavLaneGuidance>[
            DriverNavLaneGuidance(
              indications: <String>['straight'],
              valid: true,
            ),
            DriverNavLaneGuidance(
              indications: <String>['right'],
              valid: true,
              active: true,
            ),
          ],
          maneuverModifier: 'right',
          themeListenable: ValueNotifier(DriverThemeVariant.nightGold),
        );
        final caution = DriverNavComplexityCautionBanner(
          compact: false,
          isTablet: false,
          topRowLandscape: false,
          title: 'Complex road situation',
          body: 'Follow road signs and lane markings.',
          themeListenable: ValueNotifier(DriverThemeVariant.nightGold),
        );
        await tester.pumpWidget(
          _wrap(
            SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  banner,
                  const SizedBox(height: 6),
                  caution,
                ],
              ),
            ),
          ),
        );
        await tester.pump();
        expect(
          find.byKey(const ValueKey('nav_lane_guidance_strip')),
          findsOneWidget,
        );
        final laneRect = tester.getRect(
          find.byKey(const ValueKey('nav_lane_guidance_strip')),
        );
        final cautionRect = tester.getRect(
          find.byType(DriverNavComplexityCautionBanner),
        );
        // Vertical bounds must not intersect.
        expect(laneRect.bottom, lessThanOrEqualTo(cautionRect.top));
      },
    );
  });
}
