import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/fluxidi_responsive.dart';
import 'package:fluxidi_tracking/navigation/presentation/navigation_driver_marker_choice.dart';
import 'package:fluxidi_tracking/navigation/widgets/navigation_driver_cockpit_camera_controls.dart';
import 'package:fluxidi_tracking/navigation/widgets/navigation_driver_cockpit_camera_controls_layout.dart';
import 'package:fluxidi_tracking/navigation/widgets/navigation_driver_compact_nav_controls_layout.dart';
import 'package:fluxidi_tracking/navigation/widgets/navigation_driver_phone_map_controls.dart';
import 'package:fluxidi_tracking/navigation/widgets/navigation_driver_vehicle_choice_selector.dart';
import 'package:fluxidi_tracking/widgets/cockpit_widget.dart';

const _accent = Color(0xFFD4AF37);
const _text = Colors.white;
const _surface = Color(0xFF14171C);

Widget _wrap(Widget child) {
  return MaterialApp(
    home: Scaffold(body: Center(child: child)),
  );
}

void main() {
  group('NAV-MOBILE-COMPACT-CONTROLS-UNIFY-LANDSCAPE-1 form factor', () {
    test('portrait and landscape phone share the phone form factor', () {
      expect(
        FluxidiBreakpoints.classifyDeviceSize(const Size(400, 800)),
        FluxidiScreenClass.phone,
      );
      expect(
        FluxidiBreakpoints.classifyDeviceSize(const Size(800, 400)),
        FluxidiScreenClass.phone,
      );
    });

    test('tablet remains tablet in both orientations', () {
      expect(
        FluxidiBreakpoints.classifyDeviceSize(const Size(800, 1200)),
        FluxidiScreenClass.tablet,
      );
      expect(
        FluxidiBreakpoints.classifyDeviceSize(const Size(1200, 800)),
        FluxidiScreenClass.tablet,
      );
    });
  });

  group('NAV-MOBILE-COMPACT-CONTROLS phone zoom buttons (Part B)', () {
    testWidgets('3/4. only + and − are visible, no panel, no text at all', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          NavigationDriverPhoneZoomControls(
            onPlus: () {},
            onMinus: () {},
            accentColor: _accent,
            textColor: _text,
            surfaceColor: _surface,
          ),
        ),
      );
      expect(find.byIcon(Icons.add), findsOneWidget);
      expect(find.byIcon(Icons.remove), findsOneWidget);
      // 5. No "View X/13", no Z/P/A debug values — no text nodes exist.
      expect(find.byType(Text), findsNothing);
      // No enclosing large panel widget around both buttons.
      expect(find.byType(NavigationDriverCockpitCameraControls), findsNothing);
    });

    testWidgets('8. existing +/- callbacks fire unchanged', (
      WidgetTester tester,
    ) async {
      var plus = 0;
      var minus = 0;
      await tester.pumpWidget(
        _wrap(
          NavigationDriverPhoneZoomControls(
            onPlus: () => plus++,
            onMinus: () => minus++,
            accentColor: _accent,
            textColor: _text,
            surfaceColor: _surface,
          ),
        ),
      );
      await tester.tap(find.byIcon(Icons.add));
      await tester.tap(find.byIcon(Icons.remove));
      await tester.tap(find.byIcon(Icons.remove));
      expect(plus, 1);
      expect(minus, 2);
    });

    testWidgets('buttons meet the 44-48 px practical touch target', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          NavigationDriverPhoneZoomControls(
            onPlus: () {},
            onMinus: () {},
            accentColor: _accent,
            textColor: _text,
            surfaceColor: _surface,
          ),
        ),
      );
      final plusSize = tester.getSize(
        find.ancestor(
          of: find.byIcon(Icons.add),
          matching: find.byType(InkWell),
        ),
      );
      expect(plusSize.width, greaterThanOrEqualTo(44));
      expect(plusSize.height, greaterThanOrEqualTo(44));
      // Clear spacing between + and −.
      final plusRect = tester.getRect(find.byIcon(Icons.add));
      final minusRect = tester.getRect(find.byIcon(Icons.remove));
      expect(minusRect.top - plusRect.bottom, greaterThan(0));
    });
  });

  group('NAV-VEHICLE-MODE-CAR-ARROW-1 phone marker icon (Part A/G)', () {
    testWidgets('1/2. compact icon only — no permanent marker text/selector', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          NavigationDriverMarkerCompactButton(
            selectedChoice: DriverNavigationMarkerChoice.car,
            onSelected: (_) {},
            accentColor: _accent,
            textColor: _text,
            surfaceColor: _surface,
            language: AppLanguage.nl,
          ),
        ),
      );
      expect(find.byIcon(Icons.local_taxi), findsOneWidget);
      expect(find.text('Auto'), findsNothing);
      expect(find.text('Pijl'), findsNothing);
      expect(find.text('Fluxidi'), findsNothing);
      expect(find.text('Classic'), findsNothing);
      final size = tester.getSize(
        find.byType(NavigationDriverMarkerCompactButton),
      );
      expect(size.width, greaterThanOrEqualTo(44));
      expect(size.height, greaterThanOrEqualTo(44));
    });

    testWidgets('6. tap opens popup with Auto / Pijl, active marked',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        _wrap(
          NavigationDriverMarkerCompactButton(
            selectedChoice: DriverNavigationMarkerChoice.arrow,
            onSelected: (_) {},
            accentColor: _accent,
            textColor: _text,
            surfaceColor: _surface,
            language: AppLanguage.nl,
          ),
        ),
      );
      await tester.tap(find.byIcon(Icons.navigation));
      await tester.pumpAndSettle();
      expect(find.text('Auto'), findsOneWidget);
      expect(find.text('Pijl'), findsOneWidget);
      expect(find.text('Fluxidi'), findsNothing);
      expect(find.text('Classic'), findsNothing);
      // Active choice clearly indicated.
      expect(find.byIcon(Icons.check_circle), findsOneWidget);
      final checkRect = tester.getRect(find.byIcon(Icons.check_circle));
      final arrowRect = tester.getRect(find.text('Pijl'));
      expect((checkRect.center.dy - arrowRect.center.dy).abs(), lessThan(2));
    });

    testWidgets('7. selection calls the marker-choice callback', (
      WidgetTester tester,
    ) async {
      final selections = <DriverNavigationMarkerChoice>[];
      await tester.pumpWidget(
        _wrap(
          NavigationDriverMarkerCompactButton(
            selectedChoice: DriverNavigationMarkerChoice.car,
            onSelected: selections.add,
            accentColor: _accent,
            textColor: _text,
            surfaceColor: _surface,
            language: AppLanguage.nl,
          ),
        ),
      );
      await tester.tap(find.byIcon(Icons.local_taxi));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pijl'));
      await tester.pumpAndSettle();
      expect(selections, [DriverNavigationMarkerChoice.arrow]);
    });

    testWidgets('12. popup opens above the button, away from ride controls', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      const bottomStripHeight = 150.0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                Positioned(
                  left: 14,
                  bottom: 168,
                  child: NavigationDriverMarkerCompactButton(
                    selectedChoice: DriverNavigationMarkerChoice.car,
                    onSelected: (_) {},
                    accentColor: _accent,
                    textColor: _text,
                    surfaceColor: _surface,
                    language: AppLanguage.nl,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.tap(find.byIcon(Icons.local_taxi));
      await tester.pumpAndSettle();
      final screenHeight = tester.view.physicalSize.height;
      for (final label in ['Auto', 'Pijl']) {
        final rect = tester.getRect(find.text(label));
        // Every popup item stays above the bottom ride strip zone.
        expect(
          rect.bottom,
          lessThan(screenHeight - bottomStripHeight),
          reason: label,
        );
        // And inside screen bounds.
        expect(rect.top, greaterThanOrEqualTo(0), reason: label);
        expect(rect.left, greaterThanOrEqualTo(0), reason: label);
      }
    });

    testWidgets('14. popup stays inside bounds on a narrow phone', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                Positioned(
                  left: 14,
                  bottom: 168,
                  child: NavigationDriverMarkerCompactButton(
                    selectedChoice: DriverNavigationMarkerChoice.arrow,
                    onSelected: (_) {},
                    accentColor: _accent,
                    textColor: _text,
                    surfaceColor: _surface,
                    language: AppLanguage.nl,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.tap(find.byIcon(Icons.navigation));
      await tester.pumpAndSettle();
      final width = tester.view.physicalSize.width;
      final height = tester.view.physicalSize.height;
      for (final label in ['Auto', 'Pijl']) {
        final rect = tester.getRect(find.text(label));
        expect(rect.left, greaterThanOrEqualTo(0), reason: label);
        expect(rect.right, lessThanOrEqualTo(width), reason: label);
        expect(rect.top, greaterThanOrEqualTo(0), reason: label);
        expect(rect.bottom, lessThanOrEqualTo(height), reason: label);
      }
    });
  });

  group('NAV-MOBILE-COMPACT-CONTROLS placement (Parts D/E/H)', () {
    test('portrait: vehicle icon left of the map-control zone, not stacked', () {
      final zoom = resolveDriverCockpitCameraControlsLayout(
        screenHeight: 800,
        safeTop: 40,
        safeBottom: 20,
        safeRight: 0,
        isLandscape: false,
        panelHeight: driverPhoneZoomControlsSize().height,
        panelWidth: driverPhoneZoomControlsSize().width,
      );
      final vehicle = resolveDriverPhoneVehicleButtonPlacement(
        screenHeight: 800,
        safeTop: 40,
        safeBottom: 20,
        safeLeft: 0,
        isLandscape: false,
        zoomControlsBottom: zoom.bottom,
      );
      // Left side, mirroring the right-side zoom zone (not stacked above it).
      expect(vehicle.left, kDriverPhoneMapControlsEdgeMargin);
      expect(vehicle.bottom, zoom.bottom);
      expect(vehicle.reason, 'portrait_left_of_map_zone');
      // 13. Zoom zone itself sits well above the bottom ride strip: the
      // portrait anchor keeps 168 px above the safe bottom.
      expect(zoom.bottom, greaterThanOrEqualTo(20 + 150));
    });

    test('landscape: vehicle icon mid-left, clear of banner and bottom strip',
        () {
      const screenHeight = 400.0;
      final vehicle = resolveDriverPhoneVehicleButtonPlacement(
        screenHeight: screenHeight,
        safeTop: 24,
        safeBottom: 0,
        safeLeft: 44,
        isLandscape: true,
        zoomControlsBottom: 100,
        navBannerReserve: kDriverCockpitControlsLandscapeBannerReserve,
      );
      expect(vehicle.left, 44 + kDriverPhoneMapControlsEdgeMargin);
      // Vertically centered: clear of top banner and bottom controls.
      final top = screenHeight - vehicle.bottom - kDriverPhoneMapControlButtonSize;
      expect(
        top,
        greaterThanOrEqualTo(
          24 +
              kDriverPhoneMapControlsEdgeMargin +
              kDriverCockpitControlsLandscapeBannerReserve -
              0.001,
        ),
      );
      expect(vehicle.bottom, greaterThan(0));
    });

    test('14. narrow/short phone: placements clamp inside safe bounds', () {
      const screenHeight = 320.0;
      final vehicle = resolveDriverPhoneVehicleButtonPlacement(
        screenHeight: screenHeight,
        safeTop: 24,
        safeBottom: 16,
        safeLeft: 0,
        isLandscape: false,
        zoomControlsBottom: 400, // would be off-screen without clamping
      );
      expect(vehicle.clamped, isTrue);
      final top = screenHeight - vehicle.bottom - kDriverPhoneMapControlButtonSize;
      expect(top, greaterThanOrEqualTo(24 + kDriverPhoneMapControlsEdgeMargin - 0.001));
      expect(vehicle.bottom, greaterThanOrEqualTo(16));

      final zoom = resolveDriverCockpitCameraControlsLayout(
        screenHeight: screenHeight,
        safeTop: 24,
        safeBottom: 16,
        safeRight: 0,
        isLandscape: false,
        panelHeight: driverPhoneZoomControlsSize().height,
        panelWidth: driverPhoneZoomControlsSize().width,
      );
      expect(zoom.panelTop, greaterThanOrEqualTo(24));
      expect(
        zoom.panelTop + driverPhoneZoomControlsSize().height,
        lessThanOrEqualTo(screenHeight - 16),
      );
    });

    test('bottom strip reserve keeps the vehicle icon above ride controls', () {
      final vehicle = resolveDriverPhoneVehicleButtonPlacement(
        screenHeight: 800,
        safeTop: 40,
        safeBottom: 20,
        safeLeft: 0,
        isLandscape: false,
        zoomControlsBottom: 30, // hypothetical low anchor
        bottomStripReserve: 150,
      );
      expect(vehicle.clamped, isTrue);
      expect(
        vehicle.bottom,
        greaterThanOrEqualTo(20 + 150 + kDriverPhoneMapControlsEdgeMargin),
      );
    });

    test('phone zoom stack footprint is compact', () {
      final size = driverPhoneZoomControlsSize();
      expect(size.width, kDriverPhoneMapControlButtonSize);
      expect(
        size.height,
        kDriverPhoneMapControlButtonSize * 2 + kDriverPhoneZoomButtonsGap,
      );
      // Far smaller than the previous labeled panel in portrait.
      final oldPanel = estimateDriverCockpitCameraControlsPanelSize(
        buttonSize: 40,
        hasLevelLabel: true,
        hasDebugSubLabel: true,
        compactLandscape: false,
      );
      expect(size.height, lessThan(oldPanel.height));
      expect(size.width, lessThanOrEqualTo(oldPanel.width));
    });
  });

  group('NAV-MOBILE-COMPACT-CONTROLS tablet unchanged (Part F)', () {
    testWidgets('15/16. tablet View panel keeps level and debug labels', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          NavigationDriverCockpitCameraControls(
            onPlus: () {},
            onMinus: () {},
            accentColor: _accent,
            textColor: _text,
            surfaceColor: _surface,
            levelLabel: 'View 7/13',
            debugSubLabel: 'Z19.1 P78 A0.70',
          ),
        ),
      );
      expect(find.text('View 7/13'), findsOneWidget);
      expect(find.text('Z19.1 P78 A0.70'), findsOneWidget);
    });

    testWidgets('tablet keeps a direct marker selector (Auto/Pijl only)', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          NavigationDriverMarkerChoiceSelector(
            selectedChoice: DriverNavigationMarkerChoice.arrow,
            onSelected: (_) {},
            accentColor: _accent,
            textColor: _text,
            surfaceColor: _surface,
            language: AppLanguage.nl,
          ),
        ),
      );
      expect(find.text('Auto'), findsOneWidget);
      expect(find.text('Pijl'), findsOneWidget);
      expect(find.text('Fluxidi'), findsNothing);
      expect(find.text('Classic'), findsNothing);
    });

    test('tablet View panel size estimate is unchanged', () {
      final size = estimateDriverCockpitCameraControlsPanelSize(
        buttonSize: 40,
        hasLevelLabel: true,
        hasDebugSubLabel: true,
        compactLandscape: false,
      );
      expect(size.width, 48);
      expect(size.height, 8 + 40 + (6 + 10 + 8 + 4) + 40 + 8);
    });
  });

  group('NAV-MOBILE-3D-SELECTOR-SCALE-AND-BOTTOM-PRIORITY-1 action priority',
      () {
    test('phone portrait and landscape omit diagnostics but preserve Waze priority',
        () {
      for (final orientation in [
        Orientation.portrait,
        Orientation.landscape,
      ]) {
        final layout = resolveDriverCompactNavControlsLayout(
          screenClass: FluxidiScreenClass.phone,
          orientation: orientation,
        );
        final policy = resolveDriverCockpitSecondaryActionPolicy(
          isTablet: layout.isTablet,
          diagnosticsEnabled: true,
        );
        expect(policy.showDiagnosticsInBottomStrip, isFalse);
        expect(policy.prioritizeExternalNavigation, isTrue);
        expect(layout.minTouchTarget, greaterThanOrEqualTo(44));
      }
    });

    // NAV-TELLERS-POSE-ANCHOR-AND-DIAGNOSTICS-UI-1: the visible diagnostics/log
    // button is removed everywhere, so the policy must never surface it — not
    // even on tablet, and regardless of the requested diagnosticsEnabled flag.
    test('tablet never surfaces the diagnostics button on any orientation', () {
      for (final orientation in [
        Orientation.portrait,
        Orientation.landscape,
      ]) {
        final layout = resolveDriverCompactNavControlsLayout(
          screenClass: FluxidiScreenClass.tablet,
          orientation: orientation,
        );
        for (final diagnosticsEnabled in [true, false]) {
          final policy = resolveDriverCockpitSecondaryActionPolicy(
            isTablet: layout.isTablet,
            diagnosticsEnabled: diagnosticsEnabled,
          );
          expect(policy.showDiagnosticsInBottomStrip, isFalse);
          expect(policy.prioritizeExternalNavigation, isTrue);
        }
      }
    });

    testWidgets('phone landscape collapsed state prioritizes KPIs and safe ride controls',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(480, 320);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: CockpitWidget(
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
                landscapeKpiPriority: true,
                secondaryActions: const <Widget>[
                  Icon(Icons.more_horiz),
                ],
              ),
            ),
          ),
        ),
      );
      // KPIs stay direct and readable; stop/end and pause remain direct.
      expect(find.text('ETA'), findsOneWidget);
      expect(find.text('KM'), findsOneWidget);
      expect(find.text('€'), findsOneWidget);
      expect(find.text('04 min'), findsOneWidget);
      expect(find.byIcon(Icons.stop_circle_outlined), findsOneWidget);
      expect(find.byIcon(Icons.pause), findsOneWidget);
      // Follow/navigation and every other utility leave the direct strip.
      expect(find.byIcon(Icons.navigation), findsNothing);
      expect(find.byIcon(Icons.more_horiz), findsOneWidget);
      // All remaining direct controls are within the narrow landscape viewport.
      for (final finder in [
        find.byIcon(Icons.stop_circle_outlined),
        find.byIcon(Icons.pause),
        find.byIcon(Icons.more_horiz),
      ]) {
        final rect = tester.getRect(finder);
        expect(rect.left, greaterThanOrEqualTo(0));
        expect(rect.right, lessThanOrEqualTo(480));
      }
    });
  });
}
