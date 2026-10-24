// FLUXIDI-TELLERS-KPI-COCKPIT-POLISH (decisive scale + ~0.89 nose / 22 px tail)

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/driver_theme_store.dart';
import 'package:fluxidi_tracking/navigation/presentation/driver_ride_meters.dart';
import 'package:fluxidi_tracking/navigation/presentation/driver_viewport_anchor_geometry.dart';
import 'package:fluxidi_tracking/navigation/presentation/navigation_driver_cockpit_camera.dart';

const _snap = DriverRideMetersSnapshot(
  fareText: '€ 3.20',
  fareLabel: 'Tarief',
  usesFixedPrice: false,
  estimatedRidePriceText: '€ 17.20',
  estimatedRidePriceNote: 'Incl. btw • Definitieve prijs bij STOP',
  distanceTravelledText: '0.0 km',
  rideDurationText: '00:00',
  waitingTimeText: '00:00',
  statusText: 'Rit actief',
);

Widget _harness({
  required Size size,
  required bool isLandscape,
  AppLanguage language = AppLanguage.nl,
}) {
  return MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(size: size),
      child: Scaffold(
        body: Localizations(
          locale: Locale(language.name),
          delegates: const <LocalizationsDelegate<dynamic>>[
            DefaultWidgetsLocalizations.delegate,
            DefaultMaterialLocalizations.delegate,
          ],
          child: DriverRideMetersView(
            snapshot: _snap,
            themeListenable: driverThemeNotifier,
            isTablet: true,
            isLandscape: isLandscape,
            isWaiting: false,
            showLiveWindow: true,
            showVehicleMarker: false,
            markerLanguage: language,
            brandLogo: const FlutterLogo(),
            onBackToNavigation: () {},
          ),
        ),
      ),
    ),
  );
}

void main() {
  group('FLUXIDI-TELLERS-KPI-FINAL-POLISH', () {
    test(
      'tablet KPI tokens are materially larger than prior 100/28/13 baseline',
      () {
        expect(kTellersTabletCockpitKpiRowH, 128);
        expect(kTellersTabletCockpitKpiWrapH, 270);
        final wide = TellersTabletKpiMetrics.resolve(
          availableWidth: 760,
          isLandscape: false,
        );
        expect(wide.fourAcross, isTrue);
        expect(wide.valueFontSize, 45);
        expect(wide.labelFontSize, 18);
        expect(wide.minHeight, 118);
        expect(wide.valueFontSize, greaterThan(32)); // prior compact portrait
        expect(wide.labelFontSize, greaterThan(15));
        final land = TellersTabletKpiMetrics.resolve(
          availableWidth: 1100,
          isLandscape: true,
        );
        expect(land.valueFontSize, 39);
        expect(land.labelFontSize, 16);
      },
    );

    test('narrow pane metrics clamp but stay larger than old compact', () {
      final narrow = TellersTabletKpiMetrics.resolve(
        availableWidth: 400,
        isLandscape: false,
      );
      expect(narrow.fourAcross, isFalse);
      expect(narrow.valueFontSize, greaterThanOrEqualTo(34));
      expect(narrow.labelFontSize, greaterThanOrEqualTo(14));
    });

    test('wide tablet: KPI chrome grows; nose ~0.89; tail margin 20–24', () {
      final g = DriverTellersLayoutGeometry.resolve(
        viewportSize: const Size(800, 1280),
        safeTop: 24,
        safeBottom: 24,
        safeLeft: 0,
        safeRight: 0,
        isLandscape: false,
        isTablet: true,
      );
      expect(
        driverTellersTabletFourAcrossKpis(g.metersPanelRect.width),
        isTrue,
      );
      expect(g.requestedNoseFractionInLive, closeTo(0.89, 0.011));
      final tailMargin = g.liveWindowRect.bottom - g.vehicleTailGlobal.dy;
      expect(
        tailMargin,
        greaterThanOrEqualTo(kTellersLiveWindowVehicleBottomMarginMinPx - 0.5),
      );
      expect(
        tailMargin,
        lessThanOrEqualTo(kTellersLiveWindowVehicleBottomMarginMaxPx + 0.5),
      );
      expect(g.cameraPaddingFocalPoint, g.vehicleCenterGlobal);
      expect(g.priceSummaryRect.height, greaterThan(0));
      expect(g.vehicleIconSize, 132);
    });

    test('fullscreen landscape keeps lower live-window vehicle', () {
      final g = DriverTellersLayoutGeometry.resolve(
        viewportSize: const Size(1280, 800),
        safeTop: 24,
        safeBottom: 24,
        safeLeft: 0,
        safeRight: 0,
        isLandscape: true,
        isTablet: true,
      );
      expect(g.requestedNoseFractionInLive, closeTo(0.89, 0.011));
      final tailMargin = g.liveWindowRect.bottom - g.vehicleTailGlobal.dy;
      expect(tailMargin, closeTo(kTellersLiveWindowVehicleBottomMarginPx, 1.0));
      expect(g.markerAnchor.dy, greaterThan(g.liveWindowRect.center.dy));
    });

    test('vertical split host tablet: 2×2 band + safe clamp', () {
      final g = DriverTellersLayoutGeometry.resolve(
        viewportSize: const Size(436, 1360),
        safeTop: 24,
        safeBottom: 24,
        safeLeft: 0,
        safeRight: 0,
        isLandscape: false,
        isTablet: true,
      );
      expect(
        driverTellersTabletFourAcrossKpis(g.metersPanelRect.width),
        isFalse,
      );
      expect(kTellersTabletCockpitKpiWrapH, 270);
      expect(g.vehicleIconSize, 132);
      final tailMargin = g.liveWindowRect.bottom - g.vehicleTailGlobal.dy;
      expect(tailMargin, greaterThanOrEqualTo(20 - 0.5));
    });

    test('horizontal split recomputes from liveWindowRect', () {
      final g = DriverTellersLayoutGeometry.resolve(
        viewportSize: const Size(880, 676),
        safeTop: 24,
        safeBottom: 24,
        safeLeft: 0,
        safeRight: 0,
        isLandscape: true,
        isTablet: true,
      );
      expect(g.cameraPaddingFocalPoint, g.vehicleCenterGlobal);
      expect(
        g.markerAnchor.dy,
        closeTo(
          g.liveWindowRect.top +
              g.liveWindowRect.height * g.realizedNoseFractionInLive,
          0.5,
        ),
      );
    });

    test('ordinary Navigatie geometry unchanged by Tellers tokens', () {
      final nav = resolveDriverViewportAnchorGeometry(
        hostIsTablet: true,
        viewportWidth: 800,
        viewportHeight: 1280,
        layoutBottomHudHeightPx: 188,
        safeTop: 24,
        safeBottom: 24,
      );
      expect(nav.vehicleIconSize, kDriverCockpitPro2HudTabletL7);
      expect(nav.isAligned(), isTrue);
      expect(kTellersLiveWindowNoseYFractionRequested, closeTo(0.89, 0.011));
    });

    testWidgets('wide tablet: 4-across + estimate strip visible', (
      tester,
    ) async {
      await tester.pumpWidget(
        _harness(size: const Size(800, 1280), isLandscape: false),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('driver_tellers_kpi_row_4')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('driver_tellers_price_summary')),
        findsOneWidget,
      );
      expect(find.text('€ 3.20'), findsOneWidget);
      expect(find.text('€ 17.20'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('narrow vertical: 2×2 without overflow', (tester) async {
      await tester.pumpWidget(
        _harness(size: const Size(436, 1360), isLandscape: false),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('driver_tellers_kpi_wrap_2x2')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('driver_tellers_price_summary')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('NL/EN/FR/ES labels do not overflow', (tester) async {
      for (final lang in const [
        AppLanguage.nl,
        AppLanguage.en,
        AppLanguage.fr,
        AppLanguage.es,
      ]) {
        await tester.pumpWidget(
          _harness(
            size: const Size(800, 1280),
            isLandscape: false,
            language: lang,
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
    });
  });
}
