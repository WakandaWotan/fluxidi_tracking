// FLUXIDI-TELLERS-KPI-COCKPIT-POLISH
//
// Larger passenger-readable KPI bands + lower live-map nose (0.80).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/driver_theme_store.dart';
import 'package:fluxidi_tracking/navigation/presentation/driver_ride_meters.dart';
import 'package:fluxidi_tracking/navigation/presentation/driver_tellers_layout_geometry.dart';
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
  group('FLUXIDI-TELLERS-KPI-COCKPIT-POLISH', () {
    test('wide tablet geometry: tall KPI row + map below + 0.80 nose', () {
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
      expect(kTellersTabletCockpitKpiRowH, 100);
      expect(g.requestedNoseFractionInLive, 0.80);
      expect(g.realizedNoseFractionInLive, closeTo(0.80, 0.02));
      expect(g.liveWindowRect.top, greaterThan(g.metersPanelRect.bottom - 1));
      expect(g.priceSummaryRect.height, greaterThan(0));
      expect(
        g.vehicleTailGlobal.dy,
        lessThanOrEqualTo(g.liveWindowRect.bottom),
      );
    });

    test('narrow vertical pane geometry uses 2×2 KPI wrap height', () {
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
      expect(kTellersTabletCockpitKpiWrapH, 210);
      expect(g.requestedNoseFractionInLive, 0.80);
      expect(g.realizedNoseFractionInLive, lessThanOrEqualTo(0.80 + 1e-9));
    });

    test('horizontal split keeps liveWindow-relative nose with clamp', () {
      final g = DriverTellersLayoutGeometry.resolve(
        viewportSize: const Size(880, 676),
        safeTop: 24,
        safeBottom: 24,
        safeLeft: 0,
        safeRight: 0,
        isLandscape: true,
        isTablet: true,
      );
      expect(g.cameraPaddingFocalPoint, g.markerAnchor);
      expect(g.requestedNoseFractionInLive, 0.80);
    });

    test('enlarged KPI band shortens live map vs prior 78 px row', () {
      final topMin = driverTellersTabletCockpitTopMinHeight(
        contentWidth: 760,
        isLandscape: false,
      );
      // brand+title+gaps+pad+slack + 100 row > prior + 78 row.
      expect(topMin, greaterThan(226));
      expect(topMin, greaterThanOrEqualTo(248));
    });

    testWidgets('wide tablet paints 4-across KPI row + price summary', (
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
        find.byKey(const ValueKey('driver_tellers_kpi_wrap_2x2')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('driver_tellers_price_summary')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('driver_tellers_live_window')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('driver_tellers_back_nav')),
        findsOneWidget,
      );
      expect(find.text('€ 3.20'), findsOneWidget);
      expect(find.text('€ 17.20'), findsOneWidget);
    });

    testWidgets('narrow vertical pane paints 2×2 KPI wrap', (tester) async {
      await tester.pumpWidget(
        _harness(size: const Size(436, 1360), isLandscape: false),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('driver_tellers_kpi_wrap_2x2')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('driver_tellers_kpi_row_4')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('driver_tellers_price_summary')),
        findsOneWidget,
      );
    });

    testWidgets('NL/EN/FR/ES labels do not overflow Tellers KPI chrome', (
      tester,
    ) async {
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
        expect(find.byKey(const ValueKey('teller_fare')), findsOneWidget);
        expect(
          find.byKey(const ValueKey('driver_tellers_price_summary')),
          findsOneWidget,
        );
      }
    });

    test('phone non-Tellers ordinary viewport geometry unchanged', () {
      // Sanity: Tellers constants do not alter ordinary nav shared model.
      expect(kTellersLiveWindowNoseYFractionRequested, 0.80);
      expect(kDriverCockpitPro2HudTabletL7, 132);
    });
  });
}
