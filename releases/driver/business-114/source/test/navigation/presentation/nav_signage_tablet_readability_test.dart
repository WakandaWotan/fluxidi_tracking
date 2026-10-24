// NAV-SIGNAGE-TABLET-READABILITY-1
//
// Tablet-only larger navigation signage. Phones must keep historic sizes and
// the below-logo portrait placement. Tablet portrait mounts the banner beside
// the logo on one top row.

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/driver_theme_palette.dart';
import 'package:fluxidi_tracking/driver_theme_store.dart';
import 'package:fluxidi_tracking/navigation/driver_navigation_models.dart';
import 'package:fluxidi_tracking/navigation/presentation/maneuver_presentation.dart';
import 'package:fluxidi_tracking/navigation/presentation/nav_maneuver_sign.dart';
import 'package:fluxidi_tracking/navigation/presentation/nav_sign_resolver.dart';
import 'package:fluxidi_tracking/navigation/presentation/nav_signage_tablet_readability.dart';
import 'package:fluxidi_tracking/widgets/driver_nav_banners.dart';

const String _reportDir =
    'test_reports/nav_signage_tablet_readability_20260805';

String _trNl({
  required String nl,
  required String en,
  required String fr,
  required String es,
}) => nl;

NavInstructionSnapshot _followRouteSnap() {
  // Field case: policy-neutral / withheld "Volg de route naar N454" must
  // resolve to the upright straight plate — not the curved follow_route glyph.
  return NavInstructionSnapshot(
    distanceToManeuverMeters: 643,
    primaryText: 'Volg de route',
    secondaryText: 'naar N454',
    maneuverType: 'continue',
    maneuverModifier: 'straight',
    roadName: 'N454',
    roadRef: 'N454',
    isHighwayLike: false,
    lanes: const <DriverNavLaneGuidance>[],
    source: NavInstructionSource.banner,
    followRouteForced: true,
  );
}

ResponsiveManeuverPresentation _presentation({bool useCaptionedSign = false}) {
  return buildResponsiveManeuverPresentation(
    snapshot: _followRouteSnap(),
    tr: _trNl,
    languageCode: 'nl',
    useCaptionedSign: useCaptionedSign,
  );
}

DriverTurnInstructionBanner _banner({
  required bool isTablet,
  required bool compact,
  required bool topRowLandscape,
  NavSignageTabletReadabilityMetrics? tabletReadability,
  bool useCaptionedSign = false,
}) {
  final p = _presentation(useCaptionedSign: useCaptionedSign);
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
    tabletReadability: tabletReadability,
  );
}

Widget _wrap({
  required Widget child,
  required Size size,
  Key? boundaryKey,
}) {
  return MediaQuery(
    data: MediaQueryData(size: size, devicePixelRatio: 1.0),
    child: Directionality(
      textDirection: TextDirection.ltr,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          backgroundColor: const Color(0xFF1A1A1A),
          body: Align(
            alignment: Alignment.topLeft,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: boundaryKey == null
                  ? child
                  : RepaintBoundary(key: boundaryKey, child: child),
            ),
          ),
        ),
      ),
    ),
  );
}

/// Simulated collapsed top row: menu → logo → banner → free space → compass.
Widget _tabletTopRowHarness({
  required Size size,
  required bool isLandscape,
  required Key boundaryKey,
}) {
  const compassReserve =
      NavSignageTabletReadabilityMetrics.defaultCompassReserve;
  return MediaQuery(
    data: MediaQueryData(size: size, devicePixelRatio: 1.0),
    child: Directionality(
      textDirection: TextDirection.ltr,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          backgroundColor: const Color(0xFF1A1A1A),
          body: RepaintBoundary(
            key: boundaryKey,
            child: SizedBox(
              width: size.width,
              height: 220,
              child: Stack(
                children: [
                  Positioned(
                    top: 8,
                    left: 10,
                    right: compassReserve,
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        // constraints already exclude the compass reserve.
                        final resolved =
                            NavSignageTabletReadabilityMetrics.resolve(
                          isLandscape: isLandscape,
                          availableBannerWidth:
                              constraints.maxWidth - 44 - 118 - 16,
                        );
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Container(
                              key: const ValueKey<String>('harness_menu'),
                              width: 44,
                              height: 44,
                              color: Colors.black54,
                              child: const Icon(
                                Icons.menu,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              key: const ValueKey<String>('harness_logo'),
                              width: 118,
                              height: 44,
                              alignment: Alignment.center,
                              color: Colors.black45,
                              child: const Text(
                                'FLUXIDI',
                                style: TextStyle(
                                  color: Color(0xFFFFD36A),
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Align(
                                alignment: AlignmentDirectional.centerStart,
                                child: _banner(
                                  isTablet: true,
                                  compact: true,
                                  topRowLandscape: true,
                                  tabletReadability: resolved,
                                  useCaptionedSign: true,
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                  Positioned(
                    key: const ValueKey<String>('harness_compass'),
                    top: 8,
                    right: 12,
                    child: Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.black54,
                        border: Border.all(color: Colors.white54),
                      ),
                      child: const Icon(
                        Icons.explore,
                        color: Colors.white70,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

double _signSize(WidgetTester tester) {
  final signs = tester.widgetList<NavManeuverSign>(find.byType(NavManeuverSign));
  expect(signs, isNotEmpty);
  return signs.first.size;
}

Size _bannerSize(WidgetTester tester) {
  final finder = find.byKey(const ValueKey<String>('nav_maneuver_banner'));
  expect(finder, findsOneWidget);
  return tester.getSize(finder);
}

double _primaryFont(WidgetTester tester) {
  final texts = tester.widgetList<Text>(find.byType(Text)).toList();
  final primary = texts
      .where((t) => (t.data ?? '').contains('Volg') || (t.data ?? '').contains('route'))
      .map((t) => t.style?.fontSize ?? 0)
      .fold<double>(0, (a, b) => a > b ? a : b);
  expect(primary, greaterThan(0));
  return primary;
}

Future<void> _primeFollowRoute(WidgetTester tester, BuildContext context) async {
  final path = navSignAssetPath(
    languageCode: 'nl',
    maneuver: NavSignManeuver.straight,
  );
  await tester.runAsync(() async {
    final data = await rootBundle.load(path);
    expect(data.lengthInBytes, greaterThan(0));
    final decode = navSignDecodeEdge(size: 100, devicePixelRatio: 1.0);
    await precacheImage(
      ResizeImage(AssetImage(path), width: decode, height: decode),
      context,
    );
  });
}

Future<void> _writeBoundaryPng(
  WidgetTester tester,
  Key boundaryKey,
  String filename,
) async {
  final boundary = tester.renderObject(find.byKey(boundaryKey))
      as RenderRepaintBoundary;
  final image = await tester.runAsync(
    () => boundary.toImage(pixelRatio: 1.5),
  );
  final bytes = await tester.runAsync(
    () => image!.toByteData(format: ui.ImageByteFormat.png),
  );
  Directory(_reportDir).createSync(recursive: true);
  File('$_reportDir/$filename').writeAsBytesSync(bytes!.buffer.asUint8List());
}

void main() {
  setUpAll(() {
    driverThemeNotifier.value = DriverThemeVariant.midnightBlue;
    Directory(_reportDir).createSync(recursive: true);
  });

  group('NAV-SIGNAGE-TABLET-READABILITY-1 phone regression', () {
    testWidgets('phone portrait keeps historic smaller signage', (tester) async {
      const size = Size(390, 844);
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      expect(isNavSignageTabletLayout(size), isFalse);

      await tester.pumpWidget(
        _wrap(
          size: size,
          child: _banner(
            isTablet: false,
            compact: false,
            topRowLandscape: false,
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.byType(NavManeuverSign), findsOneWidget);
      expect(_signSize(tester), lessThan(110));
      expect(_primaryFont(tester), lessThan(28));
      expect(_bannerSize(tester).height, lessThan(112));
    });

    testWidgets('phone landscape keeps historic top-row sizes', (tester) async {
      const size = Size(844, 390);
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      expect(isNavSignageTabletLayout(size), isFalse);

      await tester.pumpWidget(
        _wrap(
          size: size,
          child: _banner(
            isTablet: false,
            compact: true,
            topRowLandscape: true,
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.byType(NavManeuverSign), findsOneWidget);
      expect(_signSize(tester), lessThan(110));
      expect(_primaryFont(tester), lessThan(28));
    });
  });

  group('NAV-SIGNAGE-TABLET-READABILITY-1 tablet enlargement', () {
    testWidgets('tablet portrait: banner beside logo, larger plate + text', (
      tester,
    ) async {
      const size = Size(834, 1194);
      const boundaryKey = ValueKey<String>('tablet_portrait_boundary');
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      expect(isNavSignageTabletLayout(size), isTrue);

      await tester.pumpWidget(
        _tabletTopRowHarness(
          size: size,
          isLandscape: false,
          boundaryKey: boundaryKey,
        ),
      );
      await tester.pump();
      final ctx = tester.element(find.byType(NavManeuverSign));
      await _primeFollowRoute(tester, ctx);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(NavManeuverSign), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('harness_logo')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('harness_menu')), findsOneWidget);

      final sign = _signSize(tester);
      expect(sign, greaterThanOrEqualTo(160));
      expect(sign, lessThanOrEqualTo(180));

      final bannerRect = tester.getRect(
        find.byKey(const ValueKey<String>('nav_maneuver_banner')),
      );
      final logoRect = tester.getRect(
        find.byKey(const ValueKey<String>('harness_logo')),
      );
      final compassRect = tester.getRect(
        find.byKey(const ValueKey<String>('harness_compass')),
      );
      // Beside logo (same row): banner left edge after logo right edge.
      expect(bannerRect.left, greaterThanOrEqualTo(logoRect.right - 0.5));
      expect(
        (bannerRect.top - logoRect.top).abs(),
        lessThan(120),
        reason: 'banner must share the logo row in tablet portrait',
      );
      // No overlap with the compass stand-in.
      expect(bannerRect.right, lessThanOrEqualTo(compassRect.left + 0.5));

      final signWidget = tester.widget<NavManeuverSign>(
        find.byType(NavManeuverSign),
      );
      expect(signWidget.maneuver, NavSignManeuver.straight);
      expect(signWidget.resolvedLanguageCode, 'nl');
      expect(
        signWidget.assetPath,
        'assets/fluxidi_navigation_signs_v3/png/nl/straight.png',
      );
      // Captioned plate owns the maneuver verb; external copy is distance + road.
      expect(find.text('Volg de route'), findsNothing);
      // Outlined map text paints stroke+fill Text widgets.
      expect(find.textContaining('N454'), findsAtLeastNWidgets(1));
      expect(find.textContaining('643'), findsAtLeastNWidgets(1));

      await _writeBoundaryPng(
        tester,
        boundaryKey,
        'tablet_portrait_follow_route_643_N454.png',
      );
    });

    testWidgets('tablet landscape: beside logo, larger than phone', (
      tester,
    ) async {
      const size = Size(1194, 834);
      const boundaryKey = ValueKey<String>('tablet_landscape_boundary');
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        _tabletTopRowHarness(
          size: size,
          isLandscape: true,
          boundaryKey: boundaryKey,
        ),
      );
      await tester.pump();
      final ctx = tester.element(find.byType(NavManeuverSign));
      await _primeFollowRoute(tester, ctx);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(NavManeuverSign), findsOneWidget);

      final tabletSign = _signSize(tester);
      expect(tabletSign, greaterThanOrEqualTo(160));
      expect(
        _bannerSize(tester).height,
        greaterThanOrEqualTo(
          NavSignageTabletReadabilityMetrics.landscapeBannerHeightMin - 1,
        ),
      );

      // Phone landscape baseline is clearly smaller.
      await tester.pumpWidget(
        _wrap(
          size: const Size(844, 390),
          child: _banner(
            isTablet: false,
            compact: true,
            topRowLandscape: true,
          ),
        ),
      );
      await tester.pump();
      final phoneSign = _signSize(tester);
      expect(tabletSign, greaterThan(phoneSign + 40));

      await tester.pumpWidget(
        _tabletTopRowHarness(
          size: size,
          isLandscape: true,
          boundaryKey: boundaryKey,
        ),
      );
      await tester.pump();
      await _primeFollowRoute(
        tester,
        tester.element(find.byType(NavManeuverSign)),
      );
      await tester.pumpAndSettle();
      await _writeBoundaryPng(
        tester,
        boundaryKey,
        'tablet_landscape_follow_route_643_N454.png',
      );
    });

    test('metrics clamp on narrow available width without overflow contract', () {
      final narrow = NavSignageTabletReadabilityMetrics.resolve(
        isLandscape: false,
        availableBannerWidth: 300,
      );
      // FLUXIDI-NARROW-SPLIT-BANNER-P0: below the pane threshold the wide
      // tablet plate is replaced by compact narrow metrics.
      expect(narrow.isNarrowPane, isTrue);
      expect(narrow.bannerMaxWidth, lessThanOrEqualTo(300));
      expect(narrow.bannerMinWidth, lessThanOrEqualTo(narrow.bannerMaxWidth));
      expect(narrow.signSize, greaterThanOrEqualTo(52));
      expect(narrow.signSize, lessThanOrEqualTo(72));
      final split = NavSignageTabletReadabilityMetrics.forSplitNav(
        availableBannerWidth: 320,
      );
      expect(split.signSize, greaterThanOrEqualTo(120));
      expect(split.signSize, lessThanOrEqualTo(140));
      expect(split.primaryFontSize, greaterThanOrEqualTo(22));
    });

    test('instruction presentation stays straight / N454 / 643 m', () {
      final p = _presentation(useCaptionedSign: true);
      expect(p.signManeuver, NavSignManeuver.straight);
      expect(
        p.signAssetPath,
        'assets/fluxidi_navigation_signs_v3/png/nl/straight.png',
      );
      expect(p.signAssetPath, isNot(contains('png_captioned')));
      expect(p.distanceLabel, contains('643'));
      expect(p.secondaryInstruction.toLowerCase(), contains('n454'));
      expect(p.primaryInstruction, isEmpty);
    });
  });
}
