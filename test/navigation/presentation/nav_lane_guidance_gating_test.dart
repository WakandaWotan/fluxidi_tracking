// NAV-ROUNDABOUT-LANE-CLARITY-P0-2026-07-31
//
// Presentation contracts for the lane guidance strip visibility gate.
//
// Requirements:
//   * Show lanes side-by-side with valid/preferred lanes prominent, other
//     lanes dimmed — proven by existing tests + this file's smoke checks.
//   * NEVER show a lane strip when the source data is uncertain (every
//     lane has `valid == null` and `active == null`) — the driver must not
//     see a bar of neutral pills that suggests guidance the source data
//     never provided.
//   * Panel appears when at least one lane carries a concrete signal
//     (`valid` true/false or `active` true).
//   * Panel is removed when the caller passes an empty lane list (i.e.,
//     after the maneuver is passed and the resolver clears the row).
//
// These contracts are enforced BOTH at the pure helper level
// (`driverNavLanesForBannerDisplay` / `driverNavLanesHaveConfidence`) and
// at the widget level (`DriverNavLaneGuidanceStrip`).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/driver_theme_palette.dart';
import 'package:fluxidi_tracking/driver_theme_store.dart';
import 'package:fluxidi_tracking/navigation/driver_navigation_formatters.dart';
import 'package:fluxidi_tracking/navigation/driver_navigation_map_config.dart';
import 'package:fluxidi_tracking/navigation/driver_navigation_models.dart';
import 'package:fluxidi_tracking/navigation/presentation/maneuver_presentation.dart';
import 'package:fluxidi_tracking/navigation/presentation/navigation_lane_guidance_strip.dart';
import 'package:fluxidi_tracking/widgets/driver_nav_banners.dart';

Widget _wrap(Widget child, {Size size = const Size(400, 800)}) {
  return MediaQuery(
    data: MediaQueryData(size: size),
    child: Directionality(
      textDirection: TextDirection.ltr,
      child: MaterialApp(home: Scaffold(body: Center(child: child))),
    ),
  );
}

String _tr({
  required String nl,
  required String en,
  required String fr,
  required String es,
}) => nl;

NavInstructionSnapshot _snap({
  required List<DriverNavLaneGuidance> lanes,
  double distance = 250,
  String modifier = 'right',
  String primary = 'Turn right',
  String? roadRef = 'N454',
}) {
  return NavInstructionSnapshot(
    distanceToManeuverMeters: distance,
    primaryText: primary,
    secondaryText: '',
    maneuverType: 'turn',
    maneuverModifier: modifier,
    roadName: '',
    exitNumber: null,
    destinationText: null,
    roadRef: roadRef,
    isHighwayLike: false,
    lanes: lanes,
    source: NavInstructionSource.banner,
  );
}

DriverTurnInstructionBanner _banner(
  ResponsiveManeuverPresentation p,
  List<DriverNavLaneGuidance> lanes,
) {
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
    lanes: lanes,
    presentation: p,
  );
}

void main() {
  setUpAll(() {
    driverThemeNotifier.value = DriverThemeVariant.midnightBlue;
  });

  tearDown(() {
    debugDriverNavLaneGuidanceOverride = null;
  });

  group('driverNavLanesHaveConfidence', () {
    test('empty list is not confident', () {
      expect(driverNavLanesHaveConfidence(const <DriverNavLaneGuidance>[]),
          isFalse);
    });

    test('all lanes with valid=null AND active=null are not confident', () {
      final lanes = const <DriverNavLaneGuidance>[
        DriverNavLaneGuidance(indications: <String>['left']),
        DriverNavLaneGuidance(indications: <String>['straight']),
        DriverNavLaneGuidance(indications: <String>['right']),
      ];
      expect(driverNavLanesHaveConfidence(lanes), isFalse);
    });

    test('at least one lane with valid=true is confident', () {
      final lanes = const <DriverNavLaneGuidance>[
        DriverNavLaneGuidance(indications: <String>['left']),
        DriverNavLaneGuidance(indications: <String>['right'], valid: true),
      ];
      expect(driverNavLanesHaveConfidence(lanes), isTrue);
    });

    test('at least one lane with valid=false is confident', () {
      final lanes = const <DriverNavLaneGuidance>[
        DriverNavLaneGuidance(indications: <String>['left'], valid: false),
        DriverNavLaneGuidance(indications: <String>['right']),
      ];
      expect(driverNavLanesHaveConfidence(lanes), isTrue);
    });

    test('at least one lane with active=true is confident', () {
      final lanes = const <DriverNavLaneGuidance>[
        DriverNavLaneGuidance(indications: <String>['left']),
        DriverNavLaneGuidance(
          indications: <String>['right'],
          active: true,
        ),
      ];
      expect(driverNavLanesHaveConfidence(lanes), isTrue);
    });
  });

  group('driverNavLanesForBannerDisplay: uncertainty gate', () {
    test('all-unknown lanes produce empty display list (never misleading)',
        () {
      final lanes = const <DriverNavLaneGuidance>[
        DriverNavLaneGuidance(indications: <String>['left']),
        DriverNavLaneGuidance(indications: <String>['straight']),
      ];
      final shown =
          driverNavLanesForBannerDisplay(lanes, featureEnabled: true);
      expect(shown, isEmpty);
    });

    test('some concrete lanes → full list passes through unchanged', () {
      final lanes = const <DriverNavLaneGuidance>[
        DriverNavLaneGuidance(indications: <String>['left'], valid: false),
        DriverNavLaneGuidance(
          indications: <String>['right'],
          valid: true,
          active: true,
        ),
      ];
      final shown =
          driverNavLanesForBannerDisplay(lanes, featureEnabled: true);
      expect(shown.length, 2);
    });
  });

  group('DriverNavLaneGuidanceStrip: visibility contract', () {
    testWidgets('empty lane list renders nothing', (tester) async {
      await tester.pumpWidget(
        _wrap(
          DriverNavLaneGuidanceStrip(
            lanes: const <DriverNavLaneGuidance>[],
            palette: paletteForDriverTheme(DriverThemeVariant.midnightBlue),
            metrics: DriverNavLaneStripMetrics.phone,
          ),
        ),
      );
      await tester.pump();
      expect(find.byKey(const ValueKey<String>('nav_lane_guidance_strip')),
          findsNothing);
    });

    testWidgets('three lanes with only right recommended → strip visible', (
      tester,
    ) async {
      debugDriverNavLaneGuidanceOverride = true;
      final lanes = const <DriverNavLaneGuidance>[
        DriverNavLaneGuidance(indications: <String>['left'], valid: false),
        DriverNavLaneGuidance(indications: <String>['straight'], valid: false),
        DriverNavLaneGuidance(
          indications: <String>['right'],
          valid: true,
          active: true,
        ),
      ];
      final p = buildResponsiveManeuverPresentation(
        snapshot: _snap(lanes: lanes),
        tr: _tr,
      );
      await tester.pumpWidget(_wrap(_banner(p, lanes)));
      await tester.pump();
      expect(find.byKey(const ValueKey<String>('nav_lane_guidance_strip')),
          findsOneWidget);
      // Three lane columns, right pill is the preferred (accent border).
      expect(
        find.byKey(const ValueKey<String>('nav_lane_column_0')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('nav_lane_column_2')),
        findsOneWidget,
      );
    });

    testWidgets('two valid lanes both visible side by side', (tester) async {
      debugDriverNavLaneGuidanceOverride = true;
      final lanes = const <DriverNavLaneGuidance>[
        DriverNavLaneGuidance(
          indications: <String>['left'],
          valid: true,
          active: true,
        ),
        DriverNavLaneGuidance(
          indications: <String>['straight'],
          valid: true,
          active: true,
        ),
      ];
      final p = buildResponsiveManeuverPresentation(
        snapshot: _snap(lanes: lanes, modifier: 'left', primary: 'Turn left'),
        tr: _tr,
      );
      await tester.pumpWidget(_wrap(_banner(p, lanes)));
      await tester.pump();
      expect(find.byKey(const ValueKey<String>('nav_lane_guidance_strip')),
          findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('nav_lane_column_0')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('nav_lane_column_1')),
        findsOneWidget,
      );
    });

    testWidgets(
      'all-unknown lane data → NO strip (avoid misleading panel)',
      (tester) async {
        debugDriverNavLaneGuidanceOverride = true;
        final lanes = const <DriverNavLaneGuidance>[
          DriverNavLaneGuidance(indications: <String>['left']),
          DriverNavLaneGuidance(indications: <String>['straight']),
          DriverNavLaneGuidance(indications: <String>['right']),
        ];
        final p = buildResponsiveManeuverPresentation(
          snapshot: _snap(lanes: lanes),
          tr: _tr,
        );
        await tester.pumpWidget(_wrap(_banner(p, lanes)));
        await tester.pump();
        expect(
          find.byKey(const ValueKey<String>('nav_lane_guidance_strip')),
          findsNothing,
          reason:
              'Lane strip must be hidden when no lane carries valid/active '
              'confidence — otherwise the driver sees a bar of neutral pills '
              'that suggests guidance the source data never provided.',
        );
      },
    );

    testWidgets(
      'panel disappears after maneuver: empty lane list clears the strip',
      (tester) async {
        debugDriverNavLaneGuidanceOverride = true;
        final lanesBefore = const <DriverNavLaneGuidance>[
          DriverNavLaneGuidance(
            indications: <String>['right'],
            valid: true,
            active: true,
          ),
          DriverNavLaneGuidance(indications: <String>['left'], valid: false),
        ];
        final pBefore = buildResponsiveManeuverPresentation(
          snapshot: _snap(lanes: lanesBefore),
          tr: _tr,
        );
        await tester.pumpWidget(_wrap(_banner(pBefore, lanesBefore)));
        await tester.pump();
        expect(find.byKey(const ValueKey<String>('nav_lane_guidance_strip')),
            findsOneWidget);
        // Simulate having passed the maneuver — resolver clears the list.
        final pAfter = buildResponsiveManeuverPresentation(
          snapshot: _snap(lanes: const <DriverNavLaneGuidance>[]),
          tr: _tr,
        );
        await tester.pumpWidget(_wrap(_banner(pAfter, const [])));
        await tester.pump();
        expect(find.byKey(const ValueKey<String>('nav_lane_guidance_strip')),
            findsNothing);
      },
    );
  });
}
