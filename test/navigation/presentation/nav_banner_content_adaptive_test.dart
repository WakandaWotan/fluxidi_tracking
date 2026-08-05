// NAV-PRESENTATION-COMPACT-BANNER-LANES-TELLERS-1 / Commit 1
// Layout proofs for content-adaptive maneuver banner.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/driver_theme_palette.dart';
import 'package:fluxidi_tracking/driver_theme_store.dart';
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

NavInstructionSnapshot _snap({
  required double distance,
  String type = 'turn',
  String modifier = '',
  String primary = '',
  String secondary = '',
  String roadName = '',
  String? roadRef,
  String? exitNumber,
}) {
  return NavInstructionSnapshot(
    distanceToManeuverMeters: distance,
    primaryText: primary,
    secondaryText: secondary,
    maneuverType: type,
    maneuverModifier: modifier,
    roadName: roadName,
    exitNumber: exitNumber,
    roadRef: roadRef,
    isHighwayLike: false,
    lanes: const <DriverNavLaneGuidance>[],
    source: NavInstructionSource.banner,
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
        home: Scaffold(
          body: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: size.width - 24),
              child: child,
            ),
          ),
        ),
      ),
    ),
  );
}

DriverTurnInstructionBanner _banner(
  ResponsiveManeuverPresentation p, {
  bool compact = false,
  bool isTablet = false,
  bool topRowLandscape = false,
  DriverNavBannerPortraitTabletLayout? metrics,
}) {
  return DriverTurnInstructionBanner(
    compact: compact,
    isTablet: isTablet,
    topRowLandscape: topRowLandscape,
    isArrival: p.isArrival,
    isHighwayLike: p.isHighwayLike,
    distancePrefix: '',
    distanceText: p.distanceLabel,
    primaryText: p.primaryInstruction,
    secondaryText: p.secondaryInstruction,
    icon: driverManeuverVisualIconData(p.maneuverVisual),
    presentation: p,
    portraitTabletMetrics: metrics,
  );
}

Size _bannerSize(WidgetTester tester) {
  final finder = find.byKey(const ValueKey<String>('nav_maneuver_banner'));
  expect(finder, findsOneWidget);
  return tester.getSize(finder);
}

void main() {
  setUpAll(() {
    driverThemeNotifier.value = DriverThemeVariant.midnightBlue;
  });

  group('NAV-PRESENTATION-COMPACT-BANNER content adaptive', () {
    testWidgets('one-line content stays compact (phone portrait)', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final p = _build(
        _snap(
          distance: 250,
          modifier: 'left',
          primary: 'Turn left',
          // no roadRef → no secondary
        ),
      );
      expect(p.secondaryInstruction.trim(), isEmpty);

      await tester.pumpWidget(
        _wrap(_banner(p), size: const Size(390, 844)),
      );
      await tester.pump();

      final size = _bannerSize(tester);
      expect(size.height, lessThanOrEqualTo(78),
          reason: 'Short one-line instruction must not reserve a tall band');
      expect(tester.takeException(), isNull);
    });

    testWidgets('two-line content expands only as needed', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final oneLine = _build(
        _snap(distance: 250, modifier: 'left', primary: 'Turn left'),
      );
      await tester.pumpWidget(
        _wrap(_banner(oneLine), size: const Size(390, 844)),
      );
      await tester.pump();
      final h1 = _bannerSize(tester).height;

      final twoLine = _build(
        _snap(
          distance: 709,
          type: 'roundabout',
          primary: 'Take the 2nd exit',
          exitNumber: '2',
          roadRef: 'N425',
        ),
      );
      await tester.pumpWidget(
        _wrap(_banner(twoLine), size: const Size(390, 844)),
      );
      await tester.pump();
      final h2 = _bannerSize(tester).height;

      // NAV-ROUNDABOUT-LANE-CLARITY-P0-2026-07-31: primary = ordinal, and
      // the destination road (roadRef) is the secondary. The word
      // "rotonde" no longer appears in either line because "Neem de N-de
      // afslag" (+ "naar N425") is a stronger, glanceable pair.
      expect(find.textContaining('afslag'), findsOneWidget);
      expect(find.textContaining('N425'), findsOneWidget);
      expect(h2, greaterThanOrEqualTo(h1));
      // NAV-ROUNDABOUT-LANE-CLARITY-P0-2026-07-31: the roundabout banner
      // now carries THREE deliberate elements (distance chip + ordinal
      // primary + destination secondary) instead of the pre-P0 two, so
      // the vertical delta is a few px larger than the old 40 px ceiling.
      // The empty-band guard is what matters — 55 px is still a compact
      // three-row card, never a large empty band.
      expect(h2 - h1, lessThanOrEqualTo(55),
          reason: 'Second line may grow, but must not leave a large empty band');
      expect(h2, lessThanOrEqualTo(115));
    });

    testWidgets('missing subtitle collapses (zero reserved line)', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final withSub = _build(
        _snap(
          distance: 250,
          modifier: 'left',
          primary: 'Turn left',
          roadRef: 'N425',
        ),
      );
      final withoutSub = _build(
        _snap(distance: 250, modifier: 'left', primary: 'Turn left'),
      );

      await tester.pumpWidget(
        _wrap(_banner(withSub), size: const Size(390, 844)),
      );
      await tester.pump();
      final withH = _bannerSize(tester).height;
      expect(find.text('naar N425'), findsOneWidget);

      await tester.pumpWidget(
        _wrap(_banner(withoutSub), size: const Size(390, 844)),
      );
      await tester.pump();
      final withoutH = _bannerSize(tester).height;
      expect(find.textContaining('naar'), findsNothing);
      // Subtitle absence must not leave a reserved empty text line. Height may
      // stay icon-bounded, but must never grow when subtitle is removed.
      expect(withoutH, lessThanOrEqualTo(withH));
      expect(withoutH, lessThanOrEqualTo(78));
    });

    testWidgets('long road name stays within two principal lines', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(360, 780));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      const longRef =
          'Very Very Very Long Road Reference That Should Ellipsize In Any Reasonable Layout Without Expanding The Banner Vertically Forever';
      final p = _build(
        _snap(
          distance: 250,
          modifier: 'left',
          primary: 'Turn left',
          roadRef: longRef,
        ),
      );
      await tester.pumpWidget(
        _wrap(_banner(p), size: const Size(360, 780)),
      );
      await tester.pump();

      final secondary = tester.widget<Text>(find.textContaining('naar'));
      expect(secondary.maxLines, 1);
      expect(secondary.overflow, TextOverflow.ellipsis);

      final primaryFinder = find.textContaining('linksaf');
      expect(primaryFinder, findsOneWidget);
      final primary = tester.widget<Text>(primaryFinder);
      expect(primary.maxLines, lessThanOrEqualTo(1));

      expect(_bannerSize(tester).height, lessThanOrEqualTo(110));
      expect(tester.takeException(), isNull);
    });

    testWidgets('complexity warning absent consumes no banner space', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final p = _build(
        _snap(distance: 250, modifier: 'left', primary: 'Turn left'),
      );
      // Banner alone — no caution wrap. Height must equal banner-only height.
      await tester.pumpWidget(
        _wrap(_banner(p), size: const Size(390, 844)),
      );
      await tester.pump();
      final alone = _bannerSize(tester).height;

      await tester.pumpWidget(
        _wrap(
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _banner(p),
              // Caution absent → zero-height placeholder proves collapse.
              const SizedBox.shrink(),
            ],
          ),
          size: const Size(390, 844),
        ),
      );
      await tester.pump();
      expect(_bannerSize(tester).height, alone);
      expect(find.byType(DriverNavComplexityCautionBanner), findsNothing);
    });

    testWidgets('phone portrait / tablet / landscape have no overflow', (
      tester,
    ) async {
      final p = _build(
        _snap(
          distance: 709,
          type: 'roundabout',
          primary: 'Take the 2nd exit',
          exitNumber: '2',
          roadRef: 'N425',
        ),
      );

      final cases = <({Size size, Widget banner})>[
        (
          size: const Size(390, 844),
          banner: _banner(p),
        ),
        (
          size: const Size(800, 380),
          banner: _banner(p, compact: true, topRowLandscape: true),
        ),
        (
          size: const Size(834, 1194),
          banner: _banner(
            p,
            isTablet: true,
            metrics: kDriverNavBannerPortraitTabletLayout,
          ),
        ),
        (
          size: const Size(1194, 834),
          banner: _banner(
            p,
            compact: true,
            isTablet: true,
            topRowLandscape: true,
          ),
        ),
      ];

      for (final c in cases) {
        await tester.binding.setSurfaceSize(c.size);
        await tester.pumpWidget(_wrap(c.banner, size: c.size));
        await tester.pump();
        expect(
          tester.takeException(),
          isNull,
          reason: 'overflow at ${c.size}',
        );
        expect(_bannerSize(tester).height, lessThan(c.size.height * 0.28));
      }
      addTearDown(() => tester.binding.setSurfaceSize(null));
    });
  });
}
