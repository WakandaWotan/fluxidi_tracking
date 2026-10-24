// Phone tablet-parity pass (P0): logo, transparent banner, Tellers, PiP.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/driver_theme_palette.dart';
import 'package:fluxidi_tracking/driver_theme_store.dart';
import 'package:fluxidi_tracking/navigation/external/external_navigation_pip_meter.dart';
import 'package:fluxidi_tracking/navigation/external/external_navigation_session.dart';
import 'package:fluxidi_tracking/navigation/presentation/driver_ride_meters.dart';
import 'package:fluxidi_tracking/navigation/presentation/nav_signage_tablet_readability.dart';
import 'package:fluxidi_tracking/widgets/driver_nav_banners.dart';

String _read(String path) =>
    File(path).readAsStringSync().replaceAll('\r\n', '\n');

void main() {
  setUpAll(() {
    driverThemeNotifier.value = DriverThemeVariant.midnightBlue;
  });

  group('phone Navigatie logo', () {
    test('collapsed logo capsule has no opaque black fill', () {
      final src = _read('lib/main_parts/driver_home_page_state.dart');
      final start = src.indexOf('Widget _buildCollapsedNavLogoCapsule');
      expect(start, greaterThan(0));
      final end = src.indexOf('Widget _buildTabletNavBrandCard', start);
      final block = src.substring(start, end);
      expect(block, contains('nav_phone_free_logo'));
      expect(block, isNot(contains('Colors.black.withOpacity')));
      expect(block, isNot(contains('BoxDecoration(')));
    });
  });

  group('phone forPhoneParity banner', () {
    test('metrics enable transparent chrome', () {
      final m = NavSignageTabletReadabilityMetrics.forPhoneParity(
        isLandscape: false,
        availableBannerWidth: 360,
      );
      expect(m.useTransparentChrome, isTrue);
      expect(m.signSize, inInclusiveRange(72, 96));
      expect(m.bannerMinHeight, inInclusiveRange(96, 120));
      expect(m.primaryFontSize, inInclusiveRange(18, 22));
    });

    testWidgets('banner uses transparent decoration', (tester) async {
      const metrics = NavSignageTabletReadabilityMetrics(
        isLandscape: false,
        bannerMinHeight: 100,
        bannerMaxWidth: 360,
        bannerMinWidth: 260,
        signSize: 80,
        iconBoxSize: 86,
        distanceFontSize: 20,
        primaryFontSize: 20,
        secondaryFontSize: 18,
        horizontalPadding: 10,
        verticalPadding: 7,
        compassReserve: 0,
        signPlateInset: 3,
        useTransparentChrome: true,
      );
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(size: Size(390, 844)),
          child: MaterialApp(
            home: Scaffold(
              body: DriverTurnInstructionBanner(
                compact: false,
                isTablet: false,
                topRowLandscape: false,
                isArrival: false,
                isHighwayLike: false,
                distancePrefix: 'Over',
                distanceText: '200 m',
                primaryText: 'Rechtdoor',
                secondaryText: 'Hoofdstraat',
                icon: Icons.arrow_upward,
                tabletReadability: metrics,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      final container = tester.widget<Container>(
        find.descendant(
          of: find.byKey(const ValueKey<String>('nav_maneuver_banner')),
          matching: find.byType(Container),
        ).first,
      );
      final color = container.decoration is BoxDecoration
          ? (container.decoration! as BoxDecoration).color
          : null;
      expect(color, Colors.transparent);
    });
  });

  group('phone Tellers geometry parity', () {
    test('portrait priceSummaryRect non-zero; landscape left ~0.40', () {
      final portrait = DriverTellersLayoutGeometry.resolve(
        viewportSize: const Size(390, 844),
        safeTop: 47,
        safeBottom: 34,
        safeLeft: 0,
        safeRight: 0,
        isLandscape: false,
        isTablet: false,
      );
      expect(portrait.priceSummaryRect.height, inInclusiveRange(48, 56));

      final landscape = DriverTellersLayoutGeometry.resolve(
        viewportSize: const Size(844, 390),
        safeTop: 0,
        safeBottom: 0,
        safeLeft: 0,
        safeRight: 0,
        isLandscape: true,
        isTablet: false,
      );
      expect(
        landscape.landscapeLeftWidthFraction,
        closeTo(kTellersPhoneLandscapeLeftWidthFraction, 0.01),
      );
      expect(landscape.priceSummaryRect.height, inInclusiveRange(44, 52));
    });

    test('phone portrait tail margin targets 20–24 px band', () {
      final g = DriverTellersLayoutGeometry.resolve(
        viewportSize: const Size(390, 844),
        safeTop: 47,
        safeBottom: 34,
        safeLeft: 0,
        safeRight: 0,
        isLandscape: false,
        isTablet: false,
      );
      final tailMargin = g.liveWindowRect.bottom - g.vehicleTailGlobal.dy;
      expect(tailMargin, inInclusiveRange(20.0, 24.0));
    });
  });

  group('phone PiP metrics', () {
    test('model includes wait and ordered phone metrics', () {
      final m = buildExternalNavPipMeterModel(
        phase: ExternalNavPhase.activeRide,
        isStreetRide: true,
        isFixedPrice: false,
        language: AppLanguage.nl,
        liveFareText: '€ 12,00',
        kmText: '3.1 km',
        durationText: '00:07:00',
        waitText: '00:01:30',
      );
      expect(m.metrics, hasLength(4));
      expect(m.metrics[0].label, pipMeterPhoneFareLabel(AppLanguage.nl));
      expect(m.metrics[1].label, pipMeterRideDurationLabel(AppLanguage.nl));
      expect(m.metrics[2].label, pipMeterDistanceLabel(AppLanguage.nl));
      expect(m.metrics[3].label, pipMeterWaitingLabel(AppLanguage.nl));
      expect(m.metrics[3].value, '00:01:30');
    });

    test('phone PiP metric tier fallbacks', () {
      expect(resolvePhonePipMetricTier(80), 1);
      expect(resolvePhonePipMetricTier(100), 2);
      expect(resolvePhonePipMetricTier(120), 4);
      expect(resolvePhonePipMetricTier(180), 4);
    });
  });
}
