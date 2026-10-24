import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/navigation/presentation/navigation_driver_marker_choice.dart';
import 'package:fluxidi_tracking/navigation/presentation/navigation_streetlevel_marker_anchor.dart';
import 'package:fluxidi_tracking/navigation/widgets/navigation_driver_arrow_marker.dart';
import 'package:fluxidi_tracking/navigation/widgets/navigation_driver_hud_overlay.dart';
import 'package:fluxidi_tracking/widgets/cockpit_widget.dart';

void main() {
  group('NAV-VEHICLE-MODE-CAR-ARROW-1 marker choice model', () {
    test('the public choices are exactly Car and Arrow', () {
      expect(DriverNavigationMarkerChoice.values, <DriverNavigationMarkerChoice>[
        DriverNavigationMarkerChoice.car,
        DriverNavigationMarkerChoice.arrow,
      ]);
    });

    test('Car is the default choice', () {
      expect(
        kDriverNavigationMarkerChoiceDefault,
        DriverNavigationMarkerChoice.car,
      );
    });

    test('storage + log tokens are stable and never localized', () {
      expect(
        driverNavigationMarkerChoiceStorageValue(
          DriverNavigationMarkerChoice.car,
        ),
        'car',
      );
      expect(
        driverNavigationMarkerChoiceStorageValue(
          DriverNavigationMarkerChoice.arrow,
        ),
        'arrow',
      );
      expect(
        driverNavigationMarkerChoiceLogLabel(DriverNavigationMarkerChoice.car),
        'car',
      );
      expect(
        driverNavigationMarkerChoiceLogLabel(
          DriverNavigationMarkerChoice.arrow,
        ),
        'arrow',
      );
    });

    test('labels are localized NL / EN / FR / ES', () {
      expect(
        driverNavigationMarkerChoiceLabel(
          DriverNavigationMarkerChoice.car,
          AppLanguage.nl,
        ),
        'Auto',
      );
      expect(
        driverNavigationMarkerChoiceLabel(
          DriverNavigationMarkerChoice.arrow,
          AppLanguage.nl,
        ),
        'Pijl',
      );
      expect(
        driverNavigationMarkerChoiceLabel(
          DriverNavigationMarkerChoice.car,
          AppLanguage.en,
        ),
        'Car',
      );
      expect(
        driverNavigationMarkerChoiceLabel(
          DriverNavigationMarkerChoice.arrow,
          AppLanguage.en,
        ),
        'Arrow',
      );
      expect(
        driverNavigationMarkerChoiceLabel(
          DriverNavigationMarkerChoice.car,
          AppLanguage.fr,
        ),
        'Voiture',
      );
      expect(
        driverNavigationMarkerChoiceLabel(
          DriverNavigationMarkerChoice.arrow,
          AppLanguage.fr,
        ),
        'Flèche',
      );
      expect(
        driverNavigationMarkerChoiceLabel(
          DriverNavigationMarkerChoice.car,
          AppLanguage.es,
        ),
        'Coche',
      );
      expect(
        driverNavigationMarkerChoiceLabel(
          DriverNavigationMarkerChoice.arrow,
          AppLanguage.es,
        ),
        'Flecha',
      );
    });
  });

  group('NAV-VEHICLE-MODE-CAR-ARROW-1 legacy migration', () {
    test('car / arrow are restored as-is (no rewrite)', () {
      final car = resolveStoredNavigationMarkerChoice('car');
      expect(car.choice, DriverNavigationMarkerChoice.car);
      expect(car.source, DriverNavigationMarkerChoiceSource.restored);
      expect(car.wasStored, isTrue);
      expect(car.needsRewrite, isFalse);

      final arrow = resolveStoredNavigationMarkerChoice('arrow');
      expect(arrow.choice, DriverNavigationMarkerChoice.arrow);
      expect(arrow.source, DriverNavigationMarkerChoiceSource.restored);
    });

    test('legacy Fluxidi choice migrates to Car', () {
      for (final legacy in ['fluxidi', 'fluxidi3d', 'fluxidi_taxi', 'Fluxidi']) {
        final r = resolveStoredNavigationMarkerChoice(legacy);
        expect(r.choice, DriverNavigationMarkerChoice.car, reason: legacy);
        expect(
          r.source,
          DriverNavigationMarkerChoiceSource.legacyMigration,
          reason: legacy,
        );
        expect(r.needsRewrite, isTrue, reason: legacy);
      }
    });

    test('legacy Classic choice migrates to Car', () {
      for (final legacy in [
        'classic',
        'classic3d',
        'classic_taxi',
        'classic_flying_taxi',
      ]) {
        final r = resolveStoredNavigationMarkerChoice(legacy);
        expect(r.choice, DriverNavigationMarkerChoice.car, reason: legacy);
        expect(
          r.source,
          DriverNavigationMarkerChoiceSource.legacyMigration,
          reason: legacy,
        );
      }
    });

    test('unknown or empty values never yield an empty choice', () {
      for (final raw in <String?>[null, '', '   ', 'taxi2d', 'nonsense']) {
        final r = resolveStoredNavigationMarkerChoice(raw);
        expect(r.choice, DriverNavigationMarkerChoice.car, reason: '$raw');
      }
      // Empty/null is a fresh default, not a migration event.
      expect(
        resolveStoredNavigationMarkerChoice(null).source,
        DriverNavigationMarkerChoiceSource.restored,
      );
      expect(resolveStoredNavigationMarkerChoice(null).wasStored, isFalse);
    });
  });

  group('NAV-VEHICLE-MODE-CAR-ARROW-1 Street Level marker anchor', () {
    test('marker bottom sits 12–20 px above the KPI panel top (portrait)', () {
      final offset = resolveStreetLevelMarkerBottomOffset(
        isLandscape: false,
        hasSecondaryActions: false,
        secondaryActionRowHeight: 44,
        primaryToSecondaryGap: 4,
      );
      final gap = offset - kCockpitPortraitBasePanelHeight;
      expect(gap, greaterThanOrEqualTo(kStreetLevelMarkerGapAboveKpiMin));
      expect(gap, lessThanOrEqualTo(kStreetLevelMarkerGapAboveKpiMax));
    });

    test('anchor tracks the real KPI height (secondary actions raise it)', () {
      final without = resolveStreetLevelMarkerBottomOffset(
        isLandscape: false,
        hasSecondaryActions: false,
        secondaryActionRowHeight: 44,
        primaryToSecondaryGap: 4,
      );
      final withSecondary = resolveStreetLevelMarkerBottomOffset(
        isLandscape: false,
        hasSecondaryActions: true,
        secondaryActionRowHeight: 44,
        primaryToSecondaryGap: 4,
      );
      expect(withSecondary, greaterThan(without));
      expect(withSecondary - without, 44 + 4);
    });

    test('landscape uses the fixed KPI strip height', () {
      final offset = resolveStreetLevelMarkerBottomOffset(
        isLandscape: true,
        hasSecondaryActions: true,
        secondaryActionRowHeight: 44,
        primaryToSecondaryGap: 4,
      );
      final gap = offset - kCockpitLandscapePanelHeight;
      expect(gap, greaterThanOrEqualTo(kStreetLevelMarkerGapAboveKpiMin));
      expect(gap, lessThanOrEqualTo(kStreetLevelMarkerGapAboveKpiMax));
    });

    test('panel height mirrors the CockpitWidget layout constants', () {
      expect(
        streetLevelKpiPanelHeight(
          isLandscape: false,
          hasSecondaryActions: false,
          secondaryActionRowHeight: 44,
          primaryToSecondaryGap: 4,
        ),
        kCockpitPortraitBasePanelHeight,
      );
      expect(
        streetLevelKpiPanelHeight(
          isLandscape: true,
          hasSecondaryActions: false,
          secondaryActionRowHeight: 44,
          primaryToSecondaryGap: 4,
        ),
        kCockpitLandscapePanelHeight,
      );
    });

    testWidgets('CockpitWidget portrait height equals the shared constant', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: CockpitWidget(
                embedded: true,
                etaText: '04 min',
                kmText: '2.8 km',
                priceText: '€ 14.20',
                tripStarted: true,
                isWaiting: false,
                navActive: true,
                onNav: () {},
                onStart: () {},
                onStop: () {},
                onWait: () {},
                onGo: () {},
              ),
            ),
          ),
        ),
      );
      final size = tester.getSize(find.byType(CockpitWidget));
      expect(size.height, kCockpitPortraitBasePanelHeight);
    });
  });

  group('NAV-VEHICLE-MODE-CAR-ARROW-1 single marker render', () {
    testWidgets('Car choice renders the car HUD, not the arrow', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: NavigationDriverHudOverlay(
              markerChoice: DriverNavigationMarkerChoice.car,
            ),
          ),
        ),
      );
      expect(find.byType(NavigationDriverArrowMarker), findsNothing);
      expect(find.byType(Image), findsOneWidget);
    });

    testWidgets('Arrow choice renders the arrow marker, not the car image', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: NavigationDriverHudOverlay(
              markerChoice: DriverNavigationMarkerChoice.arrow,
            ),
          ),
        ),
      );
      expect(find.byType(NavigationDriverArrowMarker), findsOneWidget);
      expect(find.byType(Image), findsNothing);
    });

    testWidgets('switching Car ↔ Arrow keeps exactly one marker at all times', (
      WidgetTester tester,
    ) async {
      Widget hud(DriverNavigationMarkerChoice choice) => MaterialApp(
            home: Scaffold(
              body: NavigationDriverHudOverlay(markerChoice: choice),
            ),
          );

      await tester.pumpWidget(hud(DriverNavigationMarkerChoice.car));
      expect(find.byType(Image), findsOneWidget);
      expect(find.byType(NavigationDriverArrowMarker), findsNothing);

      await tester.pumpWidget(hud(DriverNavigationMarkerChoice.arrow));
      expect(find.byType(Image), findsNothing);
      expect(find.byType(NavigationDriverArrowMarker), findsOneWidget);

      await tester.pumpWidget(hud(DriverNavigationMarkerChoice.car));
      expect(find.byType(Image), findsOneWidget);
      expect(find.byType(NavigationDriverArrowMarker), findsNothing);
    });
  });
}
