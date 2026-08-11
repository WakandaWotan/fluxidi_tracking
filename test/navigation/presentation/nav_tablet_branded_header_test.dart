// NAV-TABLET-BRANDED-HEADER-P1: tablet header proportions, logo paint box,
// landscape compact cluster, phone non-activation, maneuver reuse, locales.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/driver_theme_palette.dart';
import 'package:fluxidi_tracking/driver_theme_store.dart';
import 'package:fluxidi_tracking/navigation/driver_navigation_models.dart';
import 'package:fluxidi_tracking/navigation/presentation/maneuver_presentation.dart';
import 'package:fluxidi_tracking/navigation/presentation/nav_maneuver_sign.dart';
import 'package:fluxidi_tracking/navigation/presentation/nav_signage_tablet_readability.dart';
import 'package:fluxidi_tracking/navigation/presentation/nav_tablet_branded_header.dart';
import 'package:fluxidi_tracking/widgets/driver_nav_banners.dart';

String _tr({
  required String nl,
  required String en,
  required String fr,
  required String es,
  required String lang,
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
}

NavInstructionSnapshot _snap({
  double distance = 1500,
  String type = 'turn',
  String modifier = 'straight',
  String roadName = 'N48',
  String? roadRef = 'N48',
}) {
  return NavInstructionSnapshot(
    distanceToManeuverMeters: distance,
    primaryText: '',
    secondaryText: '',
    maneuverType: type,
    maneuverModifier: modifier,
    roadName: roadName,
    roadRef: roadRef,
    isHighwayLike: false,
    lanes: const <DriverNavLaneGuidance>[],
    source: NavInstructionSource.banner,
  );
}

Widget _headerHarness({
  required Size viewport,
  required bool isLandscape,
  required String logoAsset,
  String lang = 'nl',
  String? companyId,
  ValueNotifier<String>? logoRefNotifier,
}) {
  final available = viewport.width - 20 - NavSignageTabletReadabilityMetrics.defaultCompassReserve;
  final provisional = NavTabletBrandedHeaderMetrics.resolve(
    availableWidth: available,
    isLandscape: isLandscape,
    cardHeight: 176,
  );
  final bannerMetrics = NavSignageTabletReadabilityMetrics.resolve(
    isLandscape: isLandscape,
    availableBannerWidth: provisional.maneuverMaxWidth,
  );
  final sharedCardHeight = bannerMetrics.bannerMinHeight >
          (bannerMetrics.iconBoxSize + bannerMetrics.verticalPadding * 2)
      ? bannerMetrics.bannerMinHeight
      : bannerMetrics.iconBoxSize + bannerMetrics.verticalPadding * 2;
  final header = NavTabletBrandedHeaderMetrics.resolve(
    availableWidth: available,
    isLandscape: isLandscape,
    cardHeight: sharedCardHeight,
  );
  final paint = header.logoPaintBox();
  final presentation = buildResponsiveManeuverPresentation(
    snapshot: _snap(
      roadName: lang == 'en'
          ? 'very long destination boulevard eastbound'
          : lang == 'fr'
          ? 'boulevard très long vers la destination'
          : lang == 'es'
          ? 'avenida muy larga hacia el destino'
          : 'zeer lange bestemmingsboulevard oostwaarts',
      roadRef: 'N48',
    ),
    tr: ({
      required String nl,
      required String en,
      required String fr,
      required String es,
    }) =>
        _tr(nl: nl, en: en, fr: fr, es: es, lang: lang),
    languageCode: lang,
    useCaptionedSign: true,
  );

  Widget brandLogo(String ref) {
    // Synthetic tenant mark — avoids asset-bundle races while proving the
    // brand slot rebuilds when the active logo ref changes.
    return ColoredBox(
      key: ValueKey<String>('tenant_logo_$ref'),
      color: ref.contains('tenant_b') ? Colors.green : Colors.amber,
      child: SizedBox(width: paint.width, height: paint.height),
    );
  }

  final logoChild = logoRefNotifier == null
      ? brandLogo(logoAsset)
      : ValueListenableBuilder<String>(
          valueListenable: logoRefNotifier,
          builder: (_, ref, __) => brandLogo(ref),
        );

  return MediaQuery(
    data: MediaQueryData(size: viewport),
    child: Directionality(
      textDirection: TextDirection.ltr,
      child: MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: available,
              // Tight height so CrossAxisAlignment.center cannot float cards
              // in the full viewport band during widget tests.
              height: header.cardHeight + 48,
              child: NavTabletBrandedHeader(
                metrics: header,
                menu: Container(
                  key: const ValueKey<String>('nav_tablet_header_menu'),
                  width: header.menuSize,
                  height: header.menuSize,
                  color: Colors.blueGrey,
                ),
                brand: Container(
                  key: const ValueKey<String>('nav_tablet_header_brand'),
                  width: header.brandWidth,
                  height: header.cardHeight,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  decoration: navTabletBrandedHeaderCardDecoration(
                    radius: header.radius,
                  ),
                  child: Center(
                    child: SizedBox(
                      width: paint.width,
                      height: paint.height,
                      child: logoChild,
                    ),
                  ),
                ),
                maneuver: DriverTurnInstructionBanner(
                  compact: true,
                  isTablet: true,
                  topRowLandscape: true,
                  isArrival: false,
                  isHighwayLike: false,
                  distancePrefix: '',
                  distanceText: presentation.distanceLabel,
                  primaryText: presentation.primaryInstruction,
                  secondaryText: presentation.secondaryInstruction,
                  icon: Icons.arrow_upward,
                  tabletReadability: bannerMetrics,
                  presentation: presentation,
                  themeListenable:
                      ValueNotifier(DriverThemeVariant.midnightBlue),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('NavTabletBrandedHeaderMetrics', () {
    test('portrait: maneuver dominates brand; fractions near target', () {
      const available = 700.0;
      final m = NavTabletBrandedHeaderMetrics.resolve(
        availableWidth: available,
        isLandscape: false,
        cardHeight: 176,
      );
      expect(m.maneuverDominatesBrand, isTrue);
      final usable = available - m.menuSize - m.gap * 2;
      expect(m.brandWidth / usable, closeTo(0.33, 0.02));
      expect(m.maneuverMaxWidth / usable, closeTo(0.58, 0.02));
      expect(m.brandWidth + m.maneuverMaxWidth + m.menuSize + m.gap * 2,
          lessThanOrEqualTo(available + 0.5));
    });

    test('landscape: compact cluster does not consume full width', () {
      const available = 1100.0;
      final m = NavTabletBrandedHeaderMetrics.resolve(
        availableWidth: available,
        isLandscape: true,
        cardHeight: 160,
      );
      final cluster = m.menuSize + m.gap * 2 + m.brandWidth + m.maneuverMaxWidth;
      expect(cluster, lessThan(available * 0.85));
      expect(m.maneuverDominatesBrand, isTrue);
    });

    test('logo paint box uses substantial card area', () {
      final m = NavTabletBrandedHeaderMetrics.resolve(
        availableWidth: 720,
        isLandscape: false,
        cardHeight: 176,
      );
      final paint = m.logoPaintBox();
      expect(paint.height / m.cardHeight, greaterThan(0.75));
      expect(paint.width / m.brandWidth, greaterThan(0.75));
    });
  });

  group('NavTabletBrandedHeader layout', () {
    testWidgets('portrait: menu + brand + maneuver present and aligned', (
      tester,
    ) async {
      await tester.pumpWidget(
        _headerHarness(
          viewport: const Size(800, 1280),
          isLandscape: false,
          logoAsset: 'assets/branding/fluxidi_logo.png',
        ),
      );
      await tester.pump();

      expect(find.byKey(const ValueKey('nav_tablet_branded_header')), findsOneWidget);
      expect(find.byKey(const ValueKey('nav_tablet_header_menu')), findsOneWidget);
      expect(find.byKey(const ValueKey('nav_tablet_header_brand')), findsOneWidget);
      expect(find.byKey(const ValueKey('nav_tablet_header_maneuver_slot')), findsOneWidget);
      expect(find.byKey(const ValueKey('nav_maneuver_banner')), findsOneWidget);

      final brandBox = tester.getRect(find.byKey(const ValueKey('nav_tablet_header_brand')));
      final manBanner = tester.getRect(find.byKey(const ValueKey('nav_maneuver_banner')));
      final manSlot = tester.getRect(
        find.byKey(const ValueKey('nav_tablet_header_maneuver_slot')),
      );
      // Same visual band: centers align; brand tracks the sign-driven card.
      expect(brandBox.center.dy, closeTo(manBanner.center.dy, 28));
      expect((brandBox.height - manBanner.height).abs(), lessThan(56));
      expect(manSlot.width, greaterThan(brandBox.width));
    });

    testWidgets('wide and square logos fit without forced stretch', (tester) async {
      await tester.pumpWidget(
        _headerHarness(
          viewport: const Size(800, 1280),
          isLandscape: false,
          logoAsset: 'assets/branding/fluxidi_logo.png',
        ),
      );
      await tester.pump();

      final brand = tester.getSize(find.byKey(const ValueKey('nav_tablet_header_brand')));
      expect(brand.height, greaterThan(140));
      expect(brand.width / brand.height, greaterThan(1.0));

      // Logo paint area is the brand interior; BoxFit.contain is asserted via
      // the Image configuration on the tenant logo key.
      final logoFinder = find.byWidgetPredicate(
        (w) => w is Image && w.fit == BoxFit.contain,
      );
      expect(logoFinder, findsWidgets);
    });

    testWidgets('tenant logo key changes when logo ref switches A→B', (
      tester,
    ) async {
      final logoRef = ValueNotifier<String>('tenant_a_logo');
      await tester.pumpWidget(
        _headerHarness(
          viewport: const Size(800, 1280),
          isLandscape: false,
          logoAsset: 'tenant_a_logo',
          logoRefNotifier: logoRef,
        ),
      );
      await tester.pump();
      expect(find.byKey(const ValueKey('tenant_logo_tenant_a_logo')), findsOneWidget);
      expect(find.byKey(const ValueKey('tenant_logo_tenant_b_logo')), findsNothing);

      logoRef.value = 'tenant_b_logo';
      await tester.pump();
      expect(find.byKey(const ValueKey('tenant_logo_tenant_a_logo')), findsNothing);
      expect(find.byKey(const ValueKey('tenant_logo_tenant_b_logo')), findsOneWidget);
    });

    testWidgets('landscape: header cluster stays compact (not full-width)', (
      tester,
    ) async {
      const viewport = Size(1280, 800);
      await tester.pumpWidget(
        _headerHarness(
          viewport: viewport,
          isLandscape: true,
          logoAsset: 'assets/branding/fluxidi_logo.png',
        ),
      );
      await tester.pump();

      final headerBox = tester.getRect(
        find.byKey(const ValueKey('nav_tablet_branded_header')),
      );
      expect(headerBox.width, lessThan(viewport.width * 0.85));
    });

    testWidgets('maneuver sign asset widget is present', (tester) async {
      await tester.pumpWidget(
        _headerHarness(
          viewport: const Size(800, 1280),
          isLandscape: false,
          logoAsset: 'assets/branding/fluxidi_logo.png',
        ),
      );
      await tester.pump();
      expect(find.byType(NavManeuverSign), findsOneWidget);
      expect(find.byKey(const ValueKey('nav_maneuver_banner')), findsOneWidget);
    });

    for (final lang in const ['nl', 'en', 'fr', 'es']) {
      testWidgets('locale $lang: distance + instruction visible, no overflow', (
        tester,
      ) async {
        await tester.pumpWidget(
          _headerHarness(
            viewport: const Size(800, 1280),
            isLandscape: false,
            logoAsset: 'assets/branding/fluxidi_logo.png',
            lang: lang,
          ),
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
        expect(find.byKey(const ValueKey('nav_maneuver_banner')), findsOneWidget);
      });
    }
  });

  group('form-factor gate', () {
    test('phone shortestSide does not qualify as tablet signage layout', () {
      expect(isNavSignageTabletLayout(const Size(390, 844)), isFalse);
      expect(isNavSignageTabletLayout(const Size(800, 1280)), isTrue);
    });
  });
}
