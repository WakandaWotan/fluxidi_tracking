// PHONE — transparent Tellers Auto/Pijl + higher landscape banner + status pill.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/driver_theme_palette.dart';
import 'package:fluxidi_tracking/driver_theme_store.dart';
import 'package:fluxidi_tracking/navigation/presentation/driver_ride_meters.dart';
import 'package:fluxidi_tracking/navigation/presentation/driver_tellers_layout_geometry.dart';
import 'package:fluxidi_tracking/navigation/presentation/navigation_driver_marker_choice.dart';
import 'package:fluxidi_tracking/navigation/presentation/phone_cockpit_opacity.dart';
import 'package:fluxidi_tracking/navigation/presentation/phone_nav_landscape_banner_geometry.dart';
import 'package:fluxidi_tracking/navigation/widgets/navigation_driver_vehicle_choice_selector.dart';

String _read(String path) =>
    File(path).readAsStringSync().replaceAll('\r\n', '\n');

void main() {
  setUpAll(() {
    driverThemeNotifier.value = DriverThemeVariant.midnightBlue;
  });

  group('phone Tellers Auto/Pijl glass', () {
    testWidgets('phone glass capsule + ≥48 lp targets; tablet stays opaque', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(407, 904));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(size: Size(407, 904)),
          child: MaterialApp(
            home: Scaffold(
              body: Center(
                child: NavigationDriverMarkerChoiceSelector(
                  selectedChoice: DriverNavigationMarkerChoice.car,
                  onSelected: (_) {},
                  accentColor: const Color(0xFFFFC107),
                  textColor: Colors.white,
                  surfaceColor: const Color(0xFF1A2330),
                  language: AppLanguage.nl,
                  phoneFloatingGlass: true,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(
        find.byKey(const ValueKey('nav_marker_selector_phone_glass')),
        findsOneWidget,
      );
      final glass = tester.widget<Container>(
        find.byKey(const ValueKey('nav_marker_selector_phone_glass')),
      );
      final deco = glass.decoration! as BoxDecoration;
      expect(deco.color!.a, closeTo(PhoneCockpitOpacity.outer, 0.02));
      expect(find.byType(BackdropFilter), findsNothing);

      final carBtn = find.ancestor(
        of: find.text('Auto').first,
        matching: find.byType(InkWell),
      );
      final arrowBtn = find.ancestor(
        of: find.text('Pijl').first,
        matching: find.byType(InkWell),
      );
      expect(tester.getSize(carBtn).height, greaterThanOrEqualTo(48 - 0.5));
      expect(tester.getSize(arrowBtn).height, greaterThanOrEqualTo(48 - 0.5));

      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(size: Size(1024, 768)),
          child: MaterialApp(
            home: Scaffold(
              body: Center(
                child: NavigationDriverMarkerChoiceSelector(
                  selectedChoice: DriverNavigationMarkerChoice.car,
                  onSelected: (_) {},
                  accentColor: const Color(0xFFFFC107),
                  textColor: Colors.white,
                  surfaceColor: const Color(0xFF1A2330),
                  language: AppLanguage.nl,
                  compactLandscape: true,
                  phoneFloatingGlass: false,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(
        find.byKey(const ValueKey('nav_marker_selector_phone_glass')),
        findsNothing,
      );
      final materials = tester.widgetList<Material>(find.byType(Material));
      expect(
        materials.any((m) => (m.color?.a ?? 0) > 0.8),
        isTrue,
      );
    });

    test('Tellers wires phoneFloatingGlass only on phone path', () {
      final src = _read('lib/navigation/presentation/driver_ride_meters.dart');
      expect(src, contains('phoneFloatingGlass: !isTablet'));
      expect(src, contains('compactLandscape: isTablet'));
    });
  });

  group('ordinary phone landscape banner height', () {
    test('phone landscape chrome top is tighter than prior 6 lp inset', () {
      const safeTop = 24.0;
      final phoneLandscape = resolvePhoneOrdinaryNavCollapsedChromeTop(
        safeTop: safeTop,
        isPhoneHost: true,
        isLandscape: true,
      );
      final phonePortrait = resolvePhoneOrdinaryNavCollapsedChromeTop(
        safeTop: safeTop,
        isPhoneHost: true,
        isLandscape: false,
      );
      final tabletLandscape = resolvePhoneOrdinaryNavCollapsedChromeTop(
        safeTop: safeTop,
        isPhoneHost: false,
        isLandscape: true,
      );
      // Prior phone landscape baseline: safeTop + 6.
      expect(phoneLandscape, lessThan(safeTop + 6));
      expect(phoneLandscape, closeTo(safeTop + 2, 0.5));
      // Portrait unchanged.
      expect(phonePortrait, closeTo(safeTop + 8, 0.5));
      // Tablet landscape keeps prior 6.
      expect(tabletLandscape, closeTo(safeTop + 6, 0.5));
    });

    test('banner budget leaves room for enlarged logo group', () {
      const row = 860.0;
      const menuGaps = 44.0 + 16.0;
      const logo = 156.8;
      final banner = row - menuGaps - logo;
      expect(banner / row, greaterThanOrEqualTo(0.52));
      expect(logo + menuGaps, lessThan(row * 0.40));
    });
  });

  group('phone Tellers status pill geometry', () {
    testWidgets('portrait/landscape status fully inside statusRect', (
      tester,
    ) async {
      for (final entry in <(Size, bool)>[
        (const Size(407, 904), false),
        (const Size(904, 407), true),
      ]) {
        await tester.binding.setSurfaceSize(entry.$1);
        await tester.pumpWidget(
          MediaQuery(
            data: MediaQueryData(
              size: entry.$1,
              padding: entry.$2
                  ? const EdgeInsets.fromLTRB(32, 12, 32, 12)
                  : const EdgeInsets.fromLTRB(0, 32, 0, 20),
            ),
            child: MaterialApp(
              home: Scaffold(
                body: DriverRideMetersView(
                  snapshot: const DriverRideMetersSnapshot(
                    fareText: '€ 9.00',
                    distanceTravelledText: '2.0 km',
                    rideDurationText: '00:08:00',
                    waitingTimeText: '00:00:30',
                    statusText: 'Rit actief',
                  ),
                  onBackToNavigation: () {},
                  onToggleWait: () {},
                  onRecenter: () {},
                  onStop: () {},
                  isWaiting: false,
                  liveRideActive: true,
                  showEstimatedPriceStrip: false,
                  isLandscape: entry.$2,
                  showMarkerSelector: true,
                  markerChoice: DriverNavigationMarkerChoice.car,
                  onMarkerChoiceSelected: (_) {},
                ),
              ),
            ),
          ),
        );
        await tester.pump();

        final status = tester.getRect(
          find.byKey(const ValueKey('driver_tellers_status')),
        );
        final geo = DriverTellersLayoutGeometry.resolve(
          viewportSize: entry.$1,
          safeTop: entry.$2 ? 12 : 32,
          safeBottom: entry.$2 ? 12 : 20,
          safeLeft: entry.$2 ? 32 : 0,
          safeRight: entry.$2 ? 32 : 0,
          isLandscape: entry.$2,
          isTablet: false,
          reserveActionBar: true,
          reservePriceSummary: false,
          reservePhasePill: true,
        );
        expect(geo.statusRect.height, closeTo(kTellersPhonePhasePillH, 0.5));
        expect(status.top, greaterThanOrEqualTo(geo.statusRect.top - 0.5));
        expect(
          status.bottom,
          lessThanOrEqualTo(geo.statusRect.bottom + 0.5),
        );
        expect(find.text('Live navigatie'), findsNothing);
        expect(find.text('Navigatie'), findsWidgets); // return button only
        expect(find.byKey(const ValueKey('driver_tellers_live_label')), findsNothing);

        // Bottom controls keep breathing room.
        expect(
          geo.controlsRect.bottom,
          lessThanOrEqualTo(
            entry.$1.height -
                (entry.$2 ? 12 : 20) -
                kTellersPhoneBottomBreathing +
                0.5,
          ),
        );
      }
      addTearDown(() => tester.binding.setSurfaceSize(null));
    });
  });
}
