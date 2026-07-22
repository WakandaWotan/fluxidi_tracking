// NAV-PARKING-ARRIVAL-DEPARTURE-ROUTE-CLARITY-BANNER-TELLERS-2 / Commit 3
// Readability proofs: larger maneuver text/icon + logo, still overflow-safe and
// content-adaptive.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/driver_theme_palette.dart';
import 'package:fluxidi_tracking/driver_theme_store.dart';
import 'package:fluxidi_tracking/navigation/driver_navigation_models.dart';
import 'package:fluxidi_tracking/navigation/presentation/maneuver_presentation.dart';
import 'package:fluxidi_tracking/navigation/presentation/driver_nav_header_logo_metrics.dart';
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

Widget _wrap(
  Widget child, {
  Size size = const Size(400, 800),
  double textScale = 1.0,
}) {
  return MediaQuery(
    data: MediaQueryData(
      size: size,
      textScaler: TextScaler.linear(textScale),
    ),
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

double _primaryFontSize(WidgetTester tester, String contains) {
  final t = tester.widget<Text>(find.textContaining(contains).first);
  return t.style!.fontSize!;
}

double _iconGlyphSize(WidgetTester tester) {
  final icons = tester.widgetList<Icon>(find.byType(Icon)).toList();
  return icons.map((i) => i.size ?? 0).reduce((a, b) => a > b ? a : b);
}

void main() {
  setUpAll(() {
    driverThemeNotifier.value = DriverThemeVariant.midnightBlue;
  });

  group('NAV-PARKING-2 banner readability', () {
    testWidgets('short instruction: large primary text + icon, compact height',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final p = _build(_snap(distance: 250, modifier: 'left', primary: 'Turn left'));
      await tester.pumpWidget(_wrap(_banner(p), size: const Size(390, 844)));
      await tester.pump();
      // Driving-readable primary text and maneuver glyph.
      expect(_primaryFontSize(tester, 'linksaf'), greaterThanOrEqualTo(20));
      expect(_iconGlyphSize(tester), greaterThanOrEqualTo(30));
      // Still content-adaptive — no oversized band.
      expect(_bannerSize(tester).height, lessThanOrEqualTo(82));
      expect(tester.takeException(), isNull);
    });

    testWidgets('two-line instruction stays within two principal lines',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final p = _build(
        _snap(
          distance: 709,
          type: 'roundabout',
          primary: 'Take the 2nd exit',
          exitNumber: '2',
          roadRef: 'N425',
        ),
      );
      await tester.pumpWidget(_wrap(_banner(p), size: const Size(390, 844)));
      await tester.pump();
      final primary = tester.widget<Text>(find.textContaining('rotonde').first);
      expect(primary.maxLines, lessThanOrEqualTo(1));
      expect(_bannerSize(tester).height, lessThanOrEqualTo(120));
      expect(tester.takeException(), isNull);
    });

    testWidgets('long bilingual street name remains readable (ellipsis, 1 line)',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 780));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      const longRef =
          'Rijksweg N425 richting Koekamerstraat / Autoroute direction Centre-Ville Zonnestraat';
      final p = _build(
        _snap(distance: 250, modifier: 'left', primary: 'Turn left', roadRef: longRef),
      );
      await tester.pumpWidget(_wrap(_banner(p), size: const Size(360, 780)));
      await tester.pump();
      final secondary = tester.widget<Text>(find.textContaining('naar').first);
      expect(secondary.maxLines, 1);
      expect(secondary.overflow, TextOverflow.ellipsis);
      expect(_bannerSize(tester).height, lessThanOrEqualTo(120));
      expect(tester.takeException(), isNull);
    });

    testWidgets('all orientations: no overflow with larger text', (tester) async {
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
        (size: const Size(390, 844), banner: _banner(p)),
        (
          size: const Size(800, 380),
          banner: _banner(p, compact: true, topRowLandscape: true),
        ),
        (
          size: const Size(834, 1194),
          banner: _banner(p, isTablet: true, metrics: kDriverNavBannerPortraitTabletLayout),
        ),
        (
          size: const Size(1194, 834),
          banner: _banner(p, compact: true, isTablet: true, topRowLandscape: true),
        ),
      ];
      for (final c in cases) {
        await tester.binding.setSurfaceSize(c.size);
        await tester.pumpWidget(_wrap(c.banner, size: c.size));
        await tester.pump();
        expect(tester.takeException(), isNull, reason: 'overflow at ${c.size}');
        expect(_bannerSize(tester).height, lessThan(c.size.height * 0.30));
      }
      addTearDown(() => tester.binding.setSurfaceSize(null));
    });

    testWidgets('text scaling (1.3x) does not overflow', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final p = _build(
        _snap(
          distance: 709,
          type: 'roundabout',
          primary: 'Take the 2nd exit',
          exitNumber: '2',
          roadRef: 'N425',
        ),
      );
      await tester.pumpWidget(
        _wrap(_banner(p), size: const Size(390, 844), textScale: 1.3),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });

  group('NAV-PARKING-2 header logo metrics', () {
    test('regular + compact logo are enlarged and aspect-preserving box', () {
      final regular = driverNavHeaderLogoMetrics(compact: false);
      final compact = driverNavHeaderLogoMetrics(compact: true);
      // Larger than the previous 50 / 38 logo heights (Fluxidi + white-label
      // share these metrics; BoxFit.contain preserves aspect ratio).
      expect(regular.logoHeight, greaterThan(50));
      expect(compact.logoHeight, greaterThan(38));
      // Box always taller than the rendered logo so contain never clips.
      expect(regular.boxHeight, greaterThanOrEqualTo(regular.logoHeight));
      expect(compact.boxHeight, greaterThanOrEqualTo(compact.logoHeight));
      // Regular header logo is larger than the compact one.
      expect(regular.logoHeight, greaterThan(compact.logoHeight));
    });
  });
}
