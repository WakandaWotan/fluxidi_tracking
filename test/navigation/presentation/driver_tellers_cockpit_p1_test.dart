// TABLET-TELLERS-COCKPIT-P1
//
// Tablet Tellers presentation: dense KPI row, map-first geometry, theme tokens,
// fixed-price SoT parity between KPI and bottom summary. Phone path unchanged.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/driver_theme_palette.dart';
import 'package:fluxidi_tracking/driver_theme_store.dart';
import 'package:fluxidi_tracking/main_parts/planned_ride_price_presentation.dart';
import 'package:fluxidi_tracking/navigation/presentation/driver_ride_meters.dart';
import 'package:fluxidi_tracking/navigation/presentation/driver_tellers_guidance.dart';
import 'package:fluxidi_tracking/navigation/presentation/maneuver_presentation.dart';

void main() {
  group('tablet Tellers cockpit geometry', () {
    test('portrait reserves KPI chrome; map gets remainder (no overlap)', () {
      final g = DriverTellersLayoutGeometry.resolve(
        viewportSize: const Size(800, 1280),
        safeTop: 24,
        safeBottom: 16,
        safeLeft: 0,
        safeRight: 0,
        isLandscape: false,
        isTablet: true,
      );
      final topMin = driverTellersTabletCockpitTopMinHeight(
        contentWidth: g.metersPanelRect.width,
        isLandscape: false,
      );
      expect(g.metersPanelRect.height, greaterThanOrEqualTo(topMin - 0.5));
      expect(g.liveWindowRect.height, greaterThan(g.metersPanelRect.height));
      expect(g.priceSummaryRect.height, greaterThan(0));
      expect(g.metersPanelRect.bottom, lessThanOrEqualTo(g.liveWindowRect.top));
      expect(g.liveWindowRect.bottom, lessThanOrEqualTo(g.controlsRect.top));
      expect(g.controlsRect.bottom, lessThanOrEqualTo(g.priceSummaryRect.top));
      expect(g.metersPanelRect.overlaps(g.liveWindowRect), isFalse);
      expect(g.liveWindowRect.overlaps(g.priceSummaryRect), isFalse);
    });

    test('landscape stays tablet vertical cockpit (host identity)', () {
      final g = DriverTellersLayoutGeometry.resolve(
        viewportSize: const Size(1280, 800),
        safeTop: 0,
        safeBottom: 0,
        safeLeft: 0,
        safeRight: 0,
        isLandscape: true,
        isTablet: true,
      );
      expect(g.isTablet, isTrue);
      expect(g.liveWindowRect.height, greaterThan(g.metersPanelRect.height));
      expect(g.priceSummaryRect.height, greaterThan(0));
      // Not the phone left-strip layout.
      expect(g.liveWindowRect.left, closeTo(g.metersPanelRect.left, 0.5));
      // Map must never invade footer (old max(160) overlap bug).
      expect(g.liveWindowRect.overlaps(g.controlsRect), isFalse);
      expect(g.liveWindowRect.overlaps(g.priceSummaryRect), isFalse);
    });

    test('without action bar, no empty controls band under the map', () {
      final g = DriverTellersLayoutGeometry.resolve(
        viewportSize: const Size(800, 1280),
        safeTop: 24,
        safeBottom: 16,
        safeLeft: 0,
        safeRight: 0,
        isLandscape: false,
        isTablet: true,
        reserveActionBar: false,
      );
      expect(g.controlsRect, Rect.zero);
      expect(g.liveWindowRect.bottom, lessThanOrEqualTo(g.priceSummaryRect.top));
    });

    test('narrow split pane still tablet; KPI wrap gate uses window width', () {
      expect(driverTellersTabletFourAcrossKpis(800), isTrue);
      expect(driverTellersTabletFourAcrossKpis(520), isFalse);
      final g = DriverTellersLayoutGeometry.resolve(
        viewportSize: const Size(420, 900),
        safeTop: 0,
        safeBottom: 0,
        safeLeft: 0,
        safeRight: 0,
        isLandscape: false,
        isTablet: true,
      );
      expect(g.isTablet, isTrue);
      expect(g.priceSummaryRect.height, greaterThan(0));
    });

    test('phone portrait has no price summary band', () {
      final g = DriverTellersLayoutGeometry.resolve(
        viewportSize: const Size(390, 844),
        safeTop: 47,
        safeBottom: 34,
        safeLeft: 0,
        safeRight: 0,
        isLandscape: false,
        isTablet: false,
      );
      expect(g.priceSummaryRect, Rect.zero);
    });
  });

  group('fixed-price SoT on Tellers surface', () {
    test('planned €48 stays locked vs live meter drift', () {
      final locked = resolveDriverCockpitFarePresentation(
        hasActiveBooking: true,
        isStreetOrDirectBooking: false,
        fixedBookingPriceEur: 48,
        liveMeterPreviewEur: 52.3,
        language: AppLanguage.nl,
      );
      expect(locked.usesFixedPrice, isTrue);
      expect(locked.amountText, '€ 48.00');
      expect(locked.tellersLabel, driverTellersFixedPriceLabel(AppLanguage.nl));

      final drifted = resolveDriverCockpitFarePresentation(
        hasActiveBooking: true,
        isStreetOrDirectBooking: false,
        fixedBookingPriceEur: 48,
        liveMeterPreviewEur: 61.05,
        language: AppLanguage.nl,
      );
      expect(drifted.amountText, '€ 48.00');
      expect(drifted.amountText, isNot(contains('61')));
    });

    test('street ride uses Tarief + live meter', () {
      final fare = resolveDriverCockpitFarePresentation(
        hasActiveBooking: false,
        isStreetOrDirectBooking: true,
        fixedBookingPriceEur: null,
        liveMeterPreviewEur: 12.4,
        language: AppLanguage.en,
      );
      expect(fare.usesFixedPrice, isFalse);
      expect(fare.amountText, '€ 12.40');
      expect(fare.tellersLabel, driverTellersFareLabel(AppLanguage.en));
    });

    test('fixed-price labels localize NL/EN/FR/ES', () {
      expect(driverTellersFixedPriceLabel(AppLanguage.nl), 'Vaste prijs');
      expect(driverTellersFixedPriceLabel(AppLanguage.en), 'Fixed price');
      expect(driverTellersFixedPriceLabel(AppLanguage.fr), 'Prix fixe');
      expect(driverTellersFixedPriceLabel(AppLanguage.es), 'Precio fijo');
      expect(
        driverTellersFixedRidePriceLabel(AppLanguage.nl),
        'Vaste ritprijs',
      );
      expect(
        driverTellersEstimatedRidePriceLabel(AppLanguage.nl),
        'Geschatte ritprijs',
      );
    });
  });

  group('DriverRideMetersView tablet cockpit widgets', () {
    setUp(() {
      driverThemeNotifier.value = DriverThemeVariant.midnightBlue;
    });

    Widget harness({
      required DriverRideMetersSnapshot snapshot,
      Size size = const Size(800, 1280),
      bool isTablet = true,
      bool isLandscape = false,
      Widget? brandLogo,
      DriverTellersGuidanceView guidance =
          const DriverTellersGuidanceView.hidden(),
      DriverThemeVariant? theme,
      bool withActions = false,
    }) {
      if (theme != null) driverThemeNotifier.value = theme;
      return MediaQuery(
        data: MediaQueryData(size: size),
        child: MaterialApp(
          home: Scaffold(
            body: DriverRideMetersView(
              snapshot: snapshot,
              onBackToNavigation: () {},
              isTablet: isTablet,
              isLandscape: isLandscape,
              brandLogo: brandLogo,
              guidance: guidance,
              showMarkerSelector: false,
              onStop: withActions ? () {} : null,
              onToggleWait: withActions ? () {} : null,
              onRecenter: withActions ? () {} : null,
            ),
          ),
        ),
      );
    }

    const snapBase = DriverRideMetersSnapshot(
      fareText: '€ 12.50',
      fareLabel: 'Tarief',
      usesFixedPrice: false,
      distanceTravelledText: '3.2 km',
      rideDurationText: '12:05',
      waitingTimeText: '01:10',
      statusText: 'Rit actief',
    );

    testWidgets('street ride: Tarief KPI + estimated summary + large map', (
      tester,
    ) async {
      const snap = DriverRideMetersSnapshot(
        fareText: '€ 3.20',
        fareLabel: 'Tarief',
        usesFixedPrice: false,
        estimatedRidePriceText: '€ 17.20',
        estimatedRidePriceNote: 'Incl. btw • Definitieve prijs bij STOP',
        distanceTravelledText: '3.2 km',
        rideDurationText: '12:05',
        waitingTimeText: '01:10',
        statusText: 'Rit actief',
      );
      await tester.pumpWidget(
        harness(
          snapshot: snap,
          brandLogo: const FlutterLogo(key: ValueKey('logo_a')),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('teller_fare')), findsOneWidget);
      expect(find.text('Tarief'), findsWidgets);
      expect(find.text('€ 3.20'), findsOneWidget); // live Tarief only
      expect(find.text('€ 17.20'), findsOneWidget); // authoritative estimate
      expect(
        find.byKey(const ValueKey('driver_tellers_price_summary')),
        findsOneWidget,
      );
      expect(find.text('Geschatte ritprijs'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('driver_tellers_live_window')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('driver_tellers_tablet_branded_header')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('driver_tellers_kpi_row_4')), findsOneWidget);
    });

    testWidgets('fixed-price: KPI and summary both €48; meter drift ignored', (
      tester,
    ) async {
      const snap = DriverRideMetersSnapshot(
        fareText: '€ 48.00',
        fareLabel: 'Vaste prijs',
        usesFixedPrice: true,
        estimatedRidePriceText: '€ 48.00',
        distanceTravelledText: '5.0 km',
        rideDurationText: '20:00',
        waitingTimeText: '00:00',
        statusText: 'Rit actief',
      );
      await tester.pumpWidget(
        harness(
          snapshot: snap,
          brandLogo: const FlutterLogo(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Vaste prijs'), findsOneWidget);
      expect(find.text('Vaste ritprijs'), findsOneWidget);
      expect(find.text('€ 48.00'), findsNWidgets(2));
      expect(find.textContaining('52'), findsNothing);
    });

    testWidgets('narrow tablet pane wraps KPIs 2x2 without phone fallback', (
      tester,
    ) async {
      const snap = DriverRideMetersSnapshot(
        fareText: '€ 5.00',
        fareLabel: 'Tarief',
        distanceTravelledText: '1.0 km',
        rideDurationText: '05:00',
        waitingTimeText: '00:00',
        statusText: 'Rit actief',
      );
      await tester.pumpWidget(
        harness(
          snapshot: snap,
          size: const Size(480, 900),
          brandLogo: const FlutterLogo(),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('driver_tellers_kpi_wrap_2x2')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('driver_tellers_kpi_row_4')), findsNothing);
      // Still tablet chrome (price summary + branded header).
      expect(
        find.byKey(const ValueKey('driver_tellers_price_summary')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('driver_tellers_tablet_branded_header')),
        findsOneWidget,
      );
    });

    testWidgets('phone path has no tablet price summary / brand header', (
      tester,
    ) async {
      const snap = DriverRideMetersSnapshot(
        fareText: '€ 9.00',
        fareLabel: 'Tarief',
        distanceTravelledText: '2.0 km',
        rideDurationText: '08:00',
        waitingTimeText: '00:00',
        statusText: 'Rit actief',
      );
      await tester.pumpWidget(
        harness(
          snapshot: snap,
          size: const Size(390, 844),
          isTablet: false,
          brandLogo: const FlutterLogo(),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('driver_tellers_price_summary')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('driver_tellers_tablet_branded_header')),
        findsNothing,
      );
      expect(find.byKey(const ValueKey('driver_tellers_status')), findsOneWidget);
    });

    testWidgets('theme tokens change surface while layout keys stay', (
      tester,
    ) async {
      const snap = DriverRideMetersSnapshot(
        fareText: '€ 10.00',
        fareLabel: 'Tarief',
        distanceTravelledText: '1.0 km',
        rideDurationText: '04:00',
        waitingTimeText: '00:00',
        statusText: 'Rit actief',
      );
      // Driver Tellers chrome resolves from DriverThemeVariant palettes
      // (company image presets are branding artwork, not this surface).
      final themes = <DriverThemeVariant>[
        DriverThemeVariant.nightGold,
        DriverThemeVariant.midnightBlue,
        DriverThemeVariant.highContrast,
      ];
      Color? previousAccent;
      for (final theme in themes) {
        await tester.pumpWidget(
          harness(
            snapshot: snap,
            theme: theme,
            brandLogo: const FlutterLogo(),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('driver_tellers_live_window')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('driver_tellers_price_summary')),
          findsOneWidget,
        );
        final accent = paletteForDriverTheme(theme).accent;
        if (previousAccent != null) {
          expect(accent, isNot(previousAccent));
        }
        previousAccent = accent;
      }
    });

    testWidgets('brand logo slot swaps A → B without stale A', (tester) async {
      const snap = DriverRideMetersSnapshot(
        fareText: '€ 10.00',
        fareLabel: 'Tarief',
        distanceTravelledText: '1.0 km',
        rideDurationText: '04:00',
        waitingTimeText: '00:00',
        statusText: 'Rit actief',
      );
      await tester.pumpWidget(
        harness(
          snapshot: snap,
          brandLogo: const Text('LOGO_A', key: ValueKey('logo_a')),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('logo_a')), findsOneWidget);

      await tester.pumpWidget(
        harness(
          snapshot: snap,
          brandLogo: const Text('LOGO_B', key: ValueKey('logo_b')),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('logo_a')), findsNothing);
      expect(find.byKey(const ValueKey('logo_b')), findsOneWidget);
      expect(find.text('LOGO_B'), findsOneWidget);
    });

    testWidgets('tablet branded header owns guidance (no live-map duplicate)', (
      tester,
    ) async {
      const guidance = DriverTellersGuidanceView(
        phase: DriverTellersGuidancePhase.instruction,
        presentation: ResponsiveManeuverPresentation(
          distanceLabel: '200 m',
          primaryInstruction: 'Sla rechtsaf',
          secondaryInstruction: 'Hoofdstraat',
          maneuverVisual: ManeuverVisual.right,
          urgencyPhase: ManeuverUrgencyPhase.approaching,
          accessibilityLabel: 'Sla rechtsaf',
          isArrival: false,
          isHighwayLike: false,
        ),
      );
      await tester.pumpWidget(
        harness(
          snapshot: snapBase,
          brandLogo: const FlutterLogo(),
          guidance: guidance,
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('driver_tellers_tablet_maneuver_slot')),
        findsOneWidget,
      );
      expect(find.textContaining('Sla rechtsaf'), findsOneWidget);
      // Live-window guidance key must not appear when header owns it.
      expect(
        find.byKey(const ValueKey('driver_tellers_guidance')),
        findsNothing,
      );
    });

    testWidgets('portrait: all cockpit regions visible with readable KPIs', (
      tester,
    ) async {
      const guidance = DriverTellersGuidanceView(
        phase: DriverTellersGuidancePhase.instruction,
        presentation: ResponsiveManeuverPresentation(
          distanceLabel: '200 m',
          primaryInstruction: 'Sla rechtsaf',
          secondaryInstruction: 'Hoofdstraat',
          maneuverVisual: ManeuverVisual.right,
          urgencyPhase: ManeuverUrgencyPhase.approaching,
          accessibilityLabel: 'Sla rechtsaf',
          isArrival: false,
          isHighwayLike: false,
        ),
      );
      await tester.binding.setSurfaceSize(const Size(800, 1280));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        harness(
          snapshot: snapBase,
          brandLogo: const Text('LOGO'),
          guidance: guidance,
          withActions: true,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('LOGO'), findsOneWidget);
      expect(find.textContaining('Sla rechtsaf'), findsOneWidget);
      expect(find.text('Tellers'), findsOneWidget);
      expect(find.text('Navigatie'), findsOneWidget);
      expect(find.text('Tarief'), findsWidgets);
      expect(find.text('Afstand'), findsOneWidget);
      expect(find.text('Ritduur'), findsOneWidget);
      expect(find.text('Wachttijd'), findsOneWidget);
      expect(find.text('€ 12.50'), findsWidgets);
      expect(find.text('3.2 km'), findsOneWidget);
      expect(find.text('12:05'), findsOneWidget);
      expect(find.text('01:10'), findsOneWidget);

      final kpiBand = tester.getRect(
        find.byKey(const ValueKey('driver_tellers_kpi_band')),
      );
      expect(kpiBand.height, greaterThanOrEqualTo(72));

      final live = tester.getRect(
        find.byKey(const ValueKey('driver_tellers_live_window')),
      );
      final meters = tester.getRect(
        find.byKey(const ValueKey('driver_tellers_meters_panel')),
      );
      final price = tester.getRect(
        find.byKey(const ValueKey('driver_tellers_price_summary')),
      );
      expect(live.height, greaterThan(meters.height));
      expect(live.bottom, lessThanOrEqualTo(price.top + 0.5));
      expect(live.overlaps(meters), isFalse);
      expect(tester.takeException(), isNull);
    });

    testWidgets('landscape: no overlap/clip; KPIs + maneuver + price visible', (
      tester,
    ) async {
      const guidance = DriverTellersGuidanceView(
        phase: DriverTellersGuidancePhase.instruction,
        presentation: ResponsiveManeuverPresentation(
          distanceLabel: '120 m',
          primaryInstruction: 'Rechtdoor',
          secondaryInstruction: 'N454',
          maneuverVisual: ManeuverVisual.straight,
          urgencyPhase: ManeuverUrgencyPhase.approaching,
          accessibilityLabel: 'Rechtdoor',
          isArrival: false,
          isHighwayLike: false,
        ),
      );
      await tester.binding.setSurfaceSize(const Size(1280, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        harness(
          snapshot: snapBase,
          size: const Size(1280, 800),
          isLandscape: true,
          brandLogo: const Text('LOGO'),
          guidance: guidance,
          withActions: true,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Tellers'), findsOneWidget);
      expect(find.text('Navigatie'), findsOneWidget);
      expect(find.textContaining('Rechtdoor'), findsOneWidget);
      expect(find.byKey(const ValueKey('driver_tellers_kpi_row_4')), findsOneWidget);

      final live = tester.getRect(
        find.byKey(const ValueKey('driver_tellers_live_window')),
      );
      final meters = tester.getRect(
        find.byKey(const ValueKey('driver_tellers_meters_panel')),
      );
      final price = tester.getRect(
        find.byKey(const ValueKey('driver_tellers_price_summary')),
      );
      final kpi = tester.getRect(
        find.byKey(const ValueKey('driver_tellers_kpi_band')),
      );
      expect(kpi.height, greaterThanOrEqualTo(72));
      expect(live.top, greaterThanOrEqualTo(meters.bottom - 0.5));
      expect(live.bottom, lessThanOrEqualTo(price.top + 0.5));
      expect(live.overlaps(meters), isFalse);
      expect(live.overlaps(price), isFalse);
      expect(tester.takeException(), isNull);
    });

    testWidgets('no action bar → no empty controls band under map', (
      tester,
    ) async {
      await tester.pumpWidget(
        harness(snapshot: snapBase, brandLogo: const FlutterLogo()),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('driver_tellers_controls_panel')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('driver_tellers_price_summary')),
        findsOneWidget,
      );
    });

    testWidgets('hidden guidance keeps maneuver placeholder chrome', (
      tester,
    ) async {
      await tester.pumpWidget(
        harness(snapshot: snapBase, brandLogo: const FlutterLogo()),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('driver_tellers_tablet_maneuver_placeholder')),
        findsOneWidget,
      );
      expect(find.text('Live navigatie'), findsWidgets);
    });
  });
}
