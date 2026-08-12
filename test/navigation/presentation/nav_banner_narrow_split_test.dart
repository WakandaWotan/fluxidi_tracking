// FLUXIDI-NARROW-SPLIT-BANNER-P0
//
// Vertical-split tablet panes must use LayoutBuilder / available-width
// compact metrics — not the full 160–180 px tablet plate — so distance,
// road and action labels stay inside the card.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/driver_theme_palette.dart';
import 'package:fluxidi_tracking/navigation/driver_navigation_models.dart';
import 'package:fluxidi_tracking/navigation/presentation/maneuver_presentation.dart';
import 'package:fluxidi_tracking/navigation/presentation/nav_signage_tablet_readability.dart';
import 'package:fluxidi_tracking/navigation/presentation/nav_tablet_branded_header.dart';
import 'package:fluxidi_tracking/widgets/driver_nav_banners.dart';

String _tr({
  required String nl,
  required String en,
  required String fr,
  required String es,
}) =>
    nl;

ResponsiveManeuverPresentation _presentation({
  required String primary,
  required String secondary,
  double distanceM = 643,
}) {
  return buildResponsiveManeuverPresentation(
    snapshot: NavInstructionSnapshot(
      distanceToManeuverMeters: distanceM,
      primaryText: primary,
      secondaryText: secondary,
      maneuverType: 'continue',
      maneuverModifier: 'straight',
      roadName: secondary,
      roadRef: 'N454',
      isHighwayLike: false,
      lanes: const <DriverNavLaneGuidance>[],
      source: NavInstructionSource.banner,
      followRouteForced: false,
    ),
    tr: _tr,
    languageCode: 'nl',
    useCaptionedSign: false,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('NavSignageTabletReadabilityMetrics narrow pane', () {
    test('vertical-split maneuver column (~186) is narrow, not full tablet', () {
      final header = NavTabletBrandedHeaderMetrics.resolve(
        availableWidth: 436,
        isLandscape: false,
        cardHeight: 120,
      );
      expect(header.maneuverMaxWidth, lessThan(360));
      final m = NavSignageTabletReadabilityMetrics.resolve(
        isLandscape: false,
        availableBannerWidth: header.maneuverMaxWidth,
      );
      expect(m.isNarrowPane, isTrue);
      expect(m.signSize, lessThanOrEqualTo(72));
      expect(m.signSize, greaterThanOrEqualTo(52));
      expect(m.primaryFontSize, lessThanOrEqualTo(18));
      expect(
        m.bannerMaxWidth,
        lessThanOrEqualTo(header.maneuverMaxWidth + 0.5),
      );
    });

    test('fullscreen tablet available width keeps large plate', () {
      final m = NavSignageTabletReadabilityMetrics.resolve(
        isLandscape: false,
        availableBannerWidth: 480,
      );
      expect(m.isNarrowPane, isFalse);
      expect(m.signSize, greaterThanOrEqualTo(160));
    });

    test('horizontal split landscape stays non-narrow even if zone < 360', () {
      final header = NavTabletBrandedHeaderMetrics.resolve(
        availableWidth: 880 - 20,
        isLandscape: true,
        cardHeight: 160,
      );
      final m = NavSignageTabletReadabilityMetrics.resolve(
        isLandscape: true,
        availableBannerWidth: header.maneuverMaxWidth,
      );
      expect(m.isNarrowPane, isFalse);
      expect(m.signSize, greaterThanOrEqualTo(160));
    });
  });

  group('DriverTurnInstructionBanner narrow layout', () {
    Widget harness({
      required Size viewport,
      required NavSignageTabletReadabilityMetrics metrics,
      required ResponsiveManeuverPresentation presentation,
    }) {
      return MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(size: viewport),
          child: Scaffold(
            body: Center(
              child: SizedBox(
                width: metrics.bannerMaxWidth,
                child: DriverTurnInstructionBanner(
                  compact: false,
                  isTablet: true,
                  topRowLandscape: true,
                  isArrival: presentation.isArrival,
                  isHighwayLike: presentation.isHighwayLike,
                  distancePrefix: '',
                  distanceText: presentation.distanceLabel,
                  primaryText: presentation.primaryInstruction,
                  secondaryText: presentation.secondaryInstruction,
                  icon: driverManeuverVisualIconData(
                    presentation.maneuverVisual,
                  ),
                  tabletReadability: metrics,
                  themeListenable:
                      ValueNotifier(DriverThemeVariant.nightGold),
                  presentation: presentation,
                ),
              ),
            ),
          ),
        ),
      );
    }

    Future<void> pumpNarrow(
      WidgetTester tester, {
      required String primary,
      required String secondary,
    }) async {
      const viewport = Size(436, 1360);
      final header = NavTabletBrandedHeaderMetrics.resolve(
        availableWidth: viewport.width,
        isLandscape: false,
        cardHeight: 120,
      );
      final metrics = NavSignageTabletReadabilityMetrics.resolve(
        isLandscape: false,
        availableBannerWidth: header.maneuverMaxWidth,
      );
      await tester.pumpWidget(
        harness(
          viewport: viewport,
          metrics: metrics,
          presentation: _presentation(primary: primary, secondary: secondary),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('narrow vertical pane: no overflow; texts present', (
      tester,
    ) async {
      final errors = <FlutterErrorDetails>[];
      final old = FlutterError.onError;
      FlutterError.onError = (details) {
        if (details.exceptionAsString().contains('overflowed')) {
          errors.add(details);
        }
        old?.call(details);
      };
      addTearDown(() => FlutterError.onError = old);

      await pumpNarrow(
        tester,
        primary: 'Rechtdoor',
        secondary: 'naar N454',
      );

      expect(find.byKey(const ValueKey<String>('nav_maneuver_banner')), findsOneWidget);
      expect(errors, isEmpty);
      expect(tester.takeException(), isNull);
    });

    testWidgets('long NL/EN/FR/ES labels stay inside narrow card', (
      tester,
    ) async {
      for (final label in const [
        'Rechtdoor aanhouden',
        'Continue straight ahead',
        'Continuer tout droit',
        'Continuar todo recto',
      ]) {
        await pumpNarrow(
          tester,
          primary: label,
          secondary: 'N454 / Ringlaan',
        );
        expect(
          find.byKey(const ValueKey<String>('nav_maneuver_banner')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      }
    });

    testWidgets('fullscreen tablet metrics still use large sign', (
      tester,
    ) async {
      final metrics = NavSignageTabletReadabilityMetrics.resolve(
        isLandscape: false,
        availableBannerWidth: 500,
      );
      expect(metrics.isNarrowPane, isFalse);
      expect(metrics.signSize, greaterThanOrEqualTo(160));
      await tester.pumpWidget(
        harness(
          viewport: const Size(800, 1280),
          metrics: metrics,
          presentation: _presentation(
            primary: 'Rechtdoor',
            secondary: 'naar N454',
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('horizontal split wide pane unchanged (non-narrow)', (
      tester,
    ) async {
      const viewport = Size(880, 676);
      final header = NavTabletBrandedHeaderMetrics.resolve(
        availableWidth: viewport.width - 20,
        isLandscape: true,
        cardHeight: 160,
      );
      final metrics = NavSignageTabletReadabilityMetrics.resolve(
        isLandscape: true,
        availableBannerWidth: header.maneuverMaxWidth,
      );
      expect(metrics.isNarrowPane, isFalse);
      await tester.pumpWidget(
        harness(
          viewport: viewport,
          metrics: metrics,
          presentation: _presentation(
            primary: 'Rechtdoor',
            secondary: 'naar N454',
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });
}
