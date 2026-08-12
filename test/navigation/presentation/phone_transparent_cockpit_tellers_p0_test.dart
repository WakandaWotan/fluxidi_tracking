// Phone transparent cockpit / full-map Tellers P0.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/driver_theme_palette.dart';
import 'package:fluxidi_tracking/driver_theme_store.dart';
import 'package:fluxidi_tracking/navigation/external/external_navigation_pip_meter.dart';
import 'package:fluxidi_tracking/navigation/external/external_navigation_session.dart';
import 'package:fluxidi_tracking/navigation/nav_engine/nav_camera_view_mode.dart';
import 'package:fluxidi_tracking/navigation/presentation/driver_ride_meters.dart';
import 'package:fluxidi_tracking/navigation/presentation/driver_tellers_layout_geometry.dart';
import 'package:fluxidi_tracking/navigation/presentation/phone_cockpit_opacity.dart';
import 'package:fluxidi_tracking/widgets/cockpit_widget.dart';

String _read(String path) =>
    File(path).readAsStringSync().replaceAll('\r\n', '\n');

DriverRideMetersSnapshot _snap({
  String fare = '€ 0.00',
  String estimate = '€ 12.40',
  bool fixed = false,
}) {
  return DriverRideMetersSnapshot(
    fareText: fare,
    distanceTravelledText: '0.0 km',
    rideDurationText: '00:00:00',
    waitingTimeText: '00:00:00',
    statusText: 'Voorbereid',
    usesFixedPrice: fixed,
    estimatedRidePriceText: estimate,
  );
}

void main() {
  setUpAll(() {
    driverThemeNotifier.value = DriverThemeVariant.midnightBlue;
  });

  group('estimate phase policy', () {
    test('phone prepared shows; active/paused/completed hide', () {
      expect(
        resolveTellersEstimatedPriceStripVisible(
          isTablet: false,
          liveRideActive: false,
          ridePrepared: true,
          rideCompleted: false,
        ),
        isTrue,
      );
      expect(
        resolveTellersEstimatedPriceStripVisible(
          isTablet: false,
          liveRideActive: true,
          ridePrepared: true,
          rideCompleted: false,
        ),
        isFalse,
      );
      expect(
        resolveTellersEstimatedPriceStripVisible(
          isTablet: false,
          liveRideActive: true,
          ridePrepared: true,
          rideCompleted: false,
        ),
        isFalse,
      );
      expect(
        resolveTellersEstimatedPriceStripVisible(
          isTablet: false,
          liveRideActive: false,
          ridePrepared: false,
          rideCompleted: true,
        ),
        isFalse,
      );
    });

    test('tablet estimate strip always visible', () {
      expect(
        resolveTellersEstimatedPriceStripVisible(
          isTablet: true,
          liveRideActive: true,
          ridePrepared: false,
          rideCompleted: false,
        ),
        isTrue,
      );
    });

    testWidgets('phone pre-START paints price summary', (tester) async {
      await tester.binding.setSurfaceSize(const Size(407, 904));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(size: Size(407, 904)),
          child: MaterialApp(
            home: Scaffold(
              body: DriverRideMetersView(
                snapshot: _snap(),
                onBackToNavigation: () {},
                showEstimatedPriceStrip: true,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(
        find.byKey(const ValueKey('driver_tellers_price_summary')),
        findsOneWidget,
      );
    });

    testWidgets('phone active/paused hide price summary', (tester) async {
      await tester.binding.setSurfaceSize(const Size(407, 904));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(size: Size(407, 904)),
          child: MaterialApp(
            home: Scaffold(
              body: DriverRideMetersView(
                snapshot: _snap(fare: '€ 9.00'),
                onBackToNavigation: () {},
                onToggleWait: () {},
                onRecenter: () {},
                onStop: () {},
                isWaiting: true,
                showEstimatedPriceStrip: false,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(
        find.byKey(const ValueKey('driver_tellers_price_summary')),
        findsNothing,
      );
    });

    testWidgets('tablet still paints price summary while active', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1194, 834));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(size: Size(1194, 834)),
          child: MaterialApp(
            home: Scaffold(
              body: DriverRideMetersView(
                snapshot: _snap(fare: '€ 9.00'),
                onBackToNavigation: () {},
                isTablet: true,
                isLandscape: true,
                onToggleWait: () {},
                onRecenter: () {},
                onStop: () {},
                showEstimatedPriceStrip: true,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(
        find.byKey(const ValueKey('driver_tellers_price_summary')),
        findsOneWidget,
      );
    });
  });

  group('phone Tellers glass geometry', () {
    test('portrait/landscape: no overlap; price collapses when hidden', () {
      const vp = Size(407, 904);
      final prepared = DriverTellersLayoutGeometry.resolve(
        viewportSize: vp,
        safeTop: 32,
        safeBottom: 20,
        safeLeft: 0,
        safeRight: 0,
        isLandscape: false,
        isTablet: false,
        reserveActionBar: false,
        reservePriceSummary: true,
      );
      expect(prepared.priceSummaryRect.height, greaterThan(0));
      expect(
        prepared.metersPanelRect.overlaps(prepared.priceSummaryRect),
        isFalse,
      );

      final active = DriverTellersLayoutGeometry.resolve(
        viewportSize: vp,
        safeTop: 32,
        safeBottom: 20,
        safeLeft: 0,
        safeRight: 0,
        isLandscape: false,
        isTablet: false,
        reserveActionBar: true,
        reservePriceSummary: false,
      );
      expect(active.priceSummaryRect, Rect.zero);
      expect(active.controlsRect.height, greaterThanOrEqualTo(48));
      expect(active.liveWindowRect.height, greaterThan(120));
      expect(
        active.metersPanelRect.overlaps(active.controlsRect),
        isFalse,
      );

      final landscape = DriverTellersLayoutGeometry.resolve(
        viewportSize: const Size(904, 407),
        safeTop: 12,
        safeBottom: 12,
        safeLeft: 32,
        safeRight: 32,
        isLandscape: true,
        isTablet: false,
        reserveActionBar: true,
        reservePriceSummary: false,
      );
      expect(landscape.priceSummaryRect, Rect.zero);
      expect(
        landscape.metersPanelRect.overlaps(landscape.liveWindowRect),
        isFalse,
      );
      expect(
        landscape.metersPanelRect.width / (904 - 64),
        closeTo(kTellersPhoneLandscapeLeftWidthFraction, 0.02),
      );
    });

    test('camera padding tracks settled overlays; target preserved via padding', () {
      final geo = DriverTellersLayoutGeometry.resolve(
        viewportSize: const Size(407, 904),
        safeTop: 32,
        safeBottom: 20,
        safeLeft: 0,
        safeRight: 0,
        isLandscape: false,
        isTablet: false,
        reserveActionBar: true,
        reservePriceSummary: false,
      );
      final anchor = resolveTellersLiveWindowVehicleAnchor(
        liveWindowRect: geo.liveWindowRect,
        viewportSize: geo.viewportSize,
        isTablet: false,
        vehicleIconSize: geo.vehicleIconSize,
      );
      expect(anchor.cameraPadding.top, geo.cameraPadding.top);
      expect(anchor.cameraPadding.bottom, geo.cameraPadding.bottom);
      expect(anchor.cameraPadding.left, geo.cameraPadding.left);
      expect(anchor.cameraPadding.right, geo.cameraPadding.right);
      final tailMargin =
          geo.liveWindowRect.bottom - anchor.vehicleTailGlobal.dy;
      expect(tailMargin, inInclusiveRange(20, 24));
    });

    test('ordinary padding restored when Tellers inactive', () {
      const ordinary = NavCameraViewPadding(
        top: 10,
        left: 11,
        bottom: 120,
        right: 12,
      );
      final tellers = DriverTellersLayoutGeometry.resolve(
        viewportSize: const Size(407, 904),
        safeTop: 32,
        safeBottom: 20,
        safeLeft: 0,
        safeRight: 0,
        isLandscape: false,
        isTablet: false,
        reserveActionBar: true,
        reservePriceSummary: false,
      ).cameraPadding;
      expect(
        resolveTellersAwarePreviewCameraPadding(
          tellersActive: true,
          ordinaryCockpitPadding: ordinary,
          tellersLiveWindowPadding: tellers,
        ),
        tellers,
      );
      expect(
        resolveTellersAwarePreviewCameraPadding(
          tellersActive: false,
          ordinaryCockpitPadding: ordinary,
          tellersLiveWindowPadding: tellers,
        ),
        ordinary,
      );
    });

    testWidgets('phone meters panel uses glass alpha tokens', (tester) async {
      await tester.binding.setSurfaceSize(const Size(407, 904));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(size: Size(407, 904)),
          child: MaterialApp(
            home: Scaffold(
              body: DriverRideMetersView(
                snapshot: _snap(),
                onBackToNavigation: () {},
                showEstimatedPriceStrip: true,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      final panel = tester.widget<Container>(
        find.byKey(const ValueKey('driver_tellers_meters_panel')),
      );
      final deco = panel.decoration! as BoxDecoration;
      expect(deco.color!.a, lessThan(0.05));
      expect(find.byType(BackdropFilter), findsNothing);
      final meters = tester.getRect(
        find.byKey(const ValueKey('driver_tellers_meters_panel')),
      );
      // Immediately under SafeArea (+ 8–12 breathing), not mid-screen.
      expect(meters.top, lessThan(50));
      expect(meters.height, lessThanOrEqualTo(260));
    });
  });

  group('phone ordinary nav cockpit glass', () {
    testWidgets('transparent shell keeps primary actions', (tester) async {
      await tester.binding.setSurfaceSize(const Size(407, 904));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(size: Size(407, 904)),
          child: MaterialApp(
            home: Scaffold(
              body: CockpitWidget(
                etaText: '4 min',
                kmText: '1.2 km',
                priceText: '€ 8.00',
                tripStarted: true,
                isWaiting: false,
                navActive: true,
                onNav: () {},
                onStart: () {},
                onStop: () {},
                onWait: () {},
                onGo: () {},
                phoneFloatingGlass: true,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.byType(BackdropFilter), findsNothing);
      expect(find.byTooltip('Stop trip'), findsOneWidget);
      expect(find.byTooltip('Pause / wait'), findsOneWidget);
      expect(find.byTooltip('Navigation on'), findsOneWidget);
    });

    test('tablet path retains BackdropFilter in source', () {
      final src = _read('lib/widgets/cockpit_widget.dart');
      expect(src, contains('BackdropFilter'));
      expect(src, contains('phoneFloatingGlass'));
      expect(src, contains('PhoneCockpitOpacity.outer'));
    });
  });

  group('phone PiP title', () {
    test('model keeps destination title; phone UI drops duplicate headings', () {
      final model = buildExternalNavPipMeterModel(
        phase: ExternalNavPhase.activeRide,
        language: AppLanguage.en,
        isStreetRide: true,
        isFixedPrice: false,
        liveFareText: '€9.00',
        kmText: '2.0 km',
        durationText: '00:05:00',
        waitText: '00:00:10',
      );
      expect(model.title, 'To destination');
      expect(model.primaryLabel, 'Fare');
      expect(model.metrics.first.label, 'Fare');
      expect(model.metrics.length, greaterThanOrEqualTo(4));
      final src = _read('lib/navigation/external/external_navigation_pip_meter.dart');
      // Phone body no longer paints ride-state / destination titles.
      expect(src, contains('_PhonePipMeterBody'));
      expect(src, contains('PhonePipSurfaceOpacity'));
      expect(src, isNot(contains('pipMeterRideActiveTitle(model.language)')));
    });
  });

  group('opacity tokens', () {
    test('phone Navigatie + Tellers share near-clear glass family', () {
      expect(PhoneCockpitOpacity.outer, inInclusiveRange(0.0, 0.28));
      expect(PhoneTellersSurfaceOpacity.panel, lessThanOrEqualTo(0.08));
      expect(PhoneTellersSurfaceOpacity.kpiTile, inInclusiveRange(0.0, 0.22));
      expect(PhoneTellersSurfaceOpacity.actionHit, inInclusiveRange(0.25, 0.55));
      expect(PhoneTellersReadability.primaryStrokeWidth, greaterThanOrEqualTo(2.0));
    });

    test('phone phase pill only for active/paused/waiting', () {
      expect(
        resolveTellersPhasePillVisible(
          isTablet: false,
          liveRideActive: false,
          isWaiting: false,
        ),
        isFalse,
      );
      expect(
        resolveTellersPhasePillVisible(
          isTablet: false,
          liveRideActive: true,
          isWaiting: false,
        ),
        isTrue,
      );
      expect(
        resolveTellersPhasePillVisible(
          isTablet: false,
          liveRideActive: true,
          isWaiting: true,
        ),
        isTrue,
      );
      expect(
        resolveTellersPhasePillVisible(
          isTablet: true,
          liveRideActive: false,
          isWaiting: false,
        ),
        isTrue,
      );
    });

    test('phone portrait meters sit under SafeArea with compact height', () {
      final geo = DriverTellersLayoutGeometry.resolve(
        viewportSize: const Size(407, 904),
        safeTop: 32,
        safeBottom: 20,
        safeLeft: 0,
        safeRight: 0,
        isLandscape: false,
        isTablet: false,
        reserveActionBar: true,
        reservePriceSummary: false,
      );
      expect(geo.metersPanelRect.top, closeTo(32 + kTellersPhoneTopBreathing, 0.5));
      expect(geo.metersPanelRect.height, lessThanOrEqualTo(kTellersPhonePortraitMetersH + 1));
      expect(
        geo.controlsRect.bottom,
        closeTo(904 - 20 - kTellersPhoneBottomBreathing, 0.5),
      );
      expect(geo.liveWindowRect.top, greaterThan(geo.metersPanelRect.bottom));
      expect(geo.liveWindowRect.bottom, lessThanOrEqualTo(geo.controlsRect.top + 0.5));
      // No Live-navigation badge reservation on phone.
      expect(geo.labelRect, Rect.zero);
    });

    test('phone phase pill is in settled geometry below KPIs, never clipped', () {
      final without = DriverTellersLayoutGeometry.resolve(
        viewportSize: const Size(407, 904),
        safeTop: 32,
        safeBottom: 20,
        safeLeft: 0,
        safeRight: 0,
        isLandscape: false,
        isTablet: false,
        reserveActionBar: true,
        reservePriceSummary: false,
        reservePhasePill: false,
      );
      final withPill = DriverTellersLayoutGeometry.resolve(
        viewportSize: const Size(407, 904),
        safeTop: 32,
        safeBottom: 20,
        safeLeft: 0,
        safeRight: 0,
        isLandscape: false,
        isTablet: false,
        reserveActionBar: true,
        reservePriceSummary: false,
        reservePhasePill: true,
      );
      expect(without.statusRect, Rect.zero);
      expect(withPill.statusRect.height, closeTo(kTellersPhonePhasePillH, 0.5));
      expect(withPill.statusRect.top, greaterThanOrEqualTo(withPill.metersPanelRect.bottom));
      expect(withPill.metersPanelRect.overlaps(withPill.statusRect), isFalse);
      expect(withPill.liveWindowRect.top, greaterThanOrEqualTo(withPill.statusRect.bottom));
      // Post-KPI selector row is always reserved; phase pill shares that row
      // (does not add a second vertical band).
      expect(
        without.liveWindowRect.height,
        closeTo(withPill.liveWindowRect.height, 0.5),
      );
      expect(withPill.statusRect.overlaps(withPill.selectorRect), isFalse);
      expect(
        withPill.selectorRect.top,
        closeTo(
          withPill.metersPanelRect.bottom + kTellersPhonePostKpiGap,
          0.5,
        ),
      );
    });
  });
}
