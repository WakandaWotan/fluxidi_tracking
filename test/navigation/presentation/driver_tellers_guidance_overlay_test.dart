// TELLERS-LIVE-NAV-INSTRUCTION-OVERLAY-1
//
// The Tellers live-navigation map must show the SAME authoritative maneuver
// instruction as the main navigation screen, and must never resolve one of its
// own. These tests pin the phase policy, the map-pane width/placement contract
// and the rendered result on tablet portrait and tablet landscape.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/navigation/driver_navigation_models.dart';
import 'package:fluxidi_tracking/navigation/presentation/driver_ride_meters.dart';
import 'package:fluxidi_tracking/navigation/presentation/driver_tellers_guidance.dart';
import 'package:fluxidi_tracking/navigation/presentation/maneuver_presentation.dart';
import 'package:fluxidi_tracking/navigation/presentation/nav_maneuver_sign.dart';
import 'package:fluxidi_tracking/navigation/presentation/navigation_driver_marker_choice.dart';
import 'package:fluxidi_tracking/widgets/driver_nav_banners.dart';

const Size kTabletPortrait = Size(834, 1194);
const Size kTabletLandscape = Size(1194, 834);
const Size kPhonePortrait = Size(390, 844);

String _tr({
  required String nl,
  required String en,
  required String fr,
  required String es,
}) => nl;

// ---------------------------------------------------------------------------
// Authoritative snapshots -> authoritative presentations.
// Every expectation below is derived from buildResponsiveManeuverPresentation,
// never from hand-written text, so a change in the main navigation wording
// moves both surfaces together.
// ---------------------------------------------------------------------------

NavInstructionSnapshot _snap({
  required double distance,
  required String primary,
  String secondary = '',
  String type = 'turn',
  String modifier = 'left',
  String roadName = '',
  String? exitNumber,
  String? roadRef,
  String? destinationText,
  bool isHighwayLike = false,
  NavInstructionSource source = NavInstructionSource.step,
}) {
  return NavInstructionSnapshot(
    distanceToManeuverMeters: distance,
    primaryText: primary,
    secondaryText: secondary,
    maneuverType: type,
    maneuverModifier: modifier,
    roadName: roadName,
    exitNumber: exitNumber,
    roadRef: roadRef,
    destinationText: destinationText,
    isHighwayLike: isHighwayLike,
    lanes: const <DriverNavLaneGuidance>[],
    source: source,
  );
}

final NavInstructionSnapshot kTurnLeftSnapshot = _snap(
  distance: 644,
  primary: 'Linksaf',
  roadName: 'N454',
  roadRef: 'N454',
);

final NavInstructionSnapshot kRoundaboutSnapshot = _snap(
  distance: 300,
  primary: 'De rotonde op',
  type: 'roundabout',
  modifier: 'right',
  roadName: 'Dorpsstraat',
  exitNumber: '2',
);

final NavInstructionSnapshot kArrivalSnapshot = _snap(
  distance: 20,
  primary: 'Bestemming bereikt',
  type: 'arrive',
  modifier: '',
  roadName: 'Kerkweg',
  exitNumber: '3',
);

final NavInstructionSnapshot kFallbackSnapshot = _snap(
  distance: 120,
  primary: 'Onbekende manoeuvre',
  type: 'flabbergast',
  modifier: 'sideways',
  source: NavInstructionSource.fallback,
);

final NavInstructionSnapshot kLongSnapshot = _snap(
  distance: 900,
  primary: 'Neem de afslag richting de ringweg en houd rechts aan',
  secondary: 'Rijksstraatweg-Noord richting Bedrijventerrein Zuidoost',
  roadName: 'Rijksstraatweg-Noord',
  destinationText: 'Bedrijventerrein Zuidoost',
);

ResponsiveManeuverPresentation _present(NavInstructionSnapshot s) =>
    buildResponsiveManeuverPresentation(snapshot: s, tr: _tr);

DriverTellersGuidanceView _instruction(
  NavInstructionSnapshot s, {
  int routeVersion = 1,
}) {
  return resolveDriverTellersGuidance(
    tellersActive: true,
    followCameraActive: true,
    liveRideActive: true,
    showInstructionBanner: true,
    navStepsLoading: false,
    isRerouting: false,
    snapshotIsLoadingSource: false,
    presentation: _present(s),
    loadingText: 'Route herberekenen…',
    routeVersion: routeVersion,
  );
}

// ---------------------------------------------------------------------------
// Widget harness.
// ---------------------------------------------------------------------------

Widget _harness({
  required Size size,
  required bool isTablet,
  required bool isLandscape,
  required DriverTellersGuidanceView guidance,
  bool showMarkerSelector = true,
  ValueChanged<DriverNavigationMarkerChoice>? onMarkerChoiceSelected,
  DriverNavigationMarkerChoice markerChoice = DriverNavigationMarkerChoice.car,
}) {
  return MediaQuery(
    data: MediaQueryData(size: size),
    child: MaterialApp(
      home: Scaffold(
        body: DriverRideMetersView(
          snapshot: const DriverRideMetersSnapshot(
            fareText: '€ 12.50',
            distanceTravelledText: '3.2 km',
            rideDurationText: '12:05',
            waitingTimeText: '00:00',
            statusText: 'Rit actief',
          ),
          onBackToNavigation: () {},
          isTablet: isTablet,
          isLandscape: isLandscape,
          showLiveWindow: true,
          showVehicleMarker: false,
          showMarkerSelector: showMarkerSelector,
          markerChoice: markerChoice,
          onMarkerChoiceSelected: onMarkerChoiceSelected ?? (_) {},
          guidance: guidance,
        ),
      ),
    ),
  );
}

Future<void> _pump(
  WidgetTester tester, {
  required Size size,
  required bool isTablet,
  required bool isLandscape,
  required DriverTellersGuidanceView guidance,
  bool showMarkerSelector = true,
  ValueChanged<DriverNavigationMarkerChoice>? onMarkerChoiceSelected,
  DriverNavigationMarkerChoice markerChoice = DriverNavigationMarkerChoice.car,
}) async {
  await tester.binding.setSurfaceSize(size);
  await tester.pumpWidget(
    _harness(
      size: size,
      isTablet: isTablet,
      isLandscape: isLandscape,
      guidance: guidance,
      showMarkerSelector: showMarkerSelector,
      onMarkerChoiceSelected: onMarkerChoiceSelected,
      markerChoice: markerChoice,
    ),
  );
  // Two frames so the Tellers geometry latch promotes a settled candidate.
  await tester.pump();
  await tester.pump();
}

final Finder kOverlay = find.byKey(
  const ValueKey<String>('driver_tellers_guidance'),
);
final Finder kBanner = find.byKey(
  const ValueKey<String>('nav_maneuver_banner'),
);
final Finder kSelector = find.byKey(
  const ValueKey<String>('driver_tellers_marker_selector'),
);
final Finder kLabel = find.byKey(
  const ValueKey<String>('driver_tellers_live_label'),
);
final Finder kLiveWindow = find.byKey(
  const ValueKey<String>('driver_tellers_live_window'),
);

DriverTellersLayoutGeometry _geometryFor(Size size, {required bool isTablet}) {
  return DriverTellersLayoutGeometry.resolve(
    viewportSize: size,
    safeTop: 0,
    safeBottom: 0,
    safeLeft: 0,
    safeRight: 0,
    isLandscape: size.width > size.height,
    isTablet: isTablet,
  );
}

void main() {
  // -------------------------------------------------------------------------
  // Phase policy (mirrors the main navigation screen's own gates).
  // -------------------------------------------------------------------------
  group('resolveDriverTellersGuidance', () {
    DriverTellersGuidanceView call({
      bool tellersActive = true,
      bool followCameraActive = true,
      bool liveRideActive = true,
      bool showInstructionBanner = true,
      bool navStepsLoading = false,
      bool isRerouting = false,
      bool snapshotIsLoadingSource = false,
      ResponsiveManeuverPresentation? presentation,
      int routeVersion = 1,
    }) {
      return resolveDriverTellersGuidance(
        tellersActive: tellersActive,
        followCameraActive: followCameraActive,
        liveRideActive: liveRideActive,
        showInstructionBanner: showInstructionBanner,
        navStepsLoading: navStepsLoading,
        isRerouting: isRerouting,
        snapshotIsLoadingSource: snapshotIsLoadingSource,
        presentation: presentation ?? _present(kTurnLeftSnapshot),
        loadingText: 'Route herberekenen…',
        routeVersion: routeVersion,
      );
    }

    test('an authoritative instruction is shown', () {
      final v = call();
      expect(v.phase, DriverTellersGuidancePhase.instruction);
      expect(v.presentation, isNotNull);
    });

    test('inactive navigation shows nothing at all', () {
      // Proof 16.
      expect(
        call(tellersActive: false).phase,
        DriverTellersGuidancePhase.hidden,
      );
      expect(
        call(followCameraActive: false).phase,
        DriverTellersGuidancePhase.hidden,
      );
      expect(
        call(liveRideActive: false).phase,
        DriverTellersGuidancePhase.hidden,
      );
    });

    test('reroute hides the stale maneuver and shows recalculation', () {
      // Proof 12. The driver page's own gate already returns false for an
      // in-flight reroute without accepted ownership; the loading phase then
      // wins, so the previous instruction cannot stay on the map.
      final v = call(showInstructionBanner: false, isRerouting: true);
      expect(v.phase, DriverTellersGuidancePhase.loading);
      expect(v.presentation, isNull);
      expect(v.loadingText, 'Route herberekenen…');
    });

    test('loading steps and a loading-source snapshot both show loading', () {
      expect(
        call(showInstructionBanner: false, navStepsLoading: true).phase,
        DriverTellersGuidancePhase.loading,
      );
      expect(
        call(showInstructionBanner: false, snapshotIsLoadingSource: true).phase,
        DriverTellersGuidancePhase.loading,
      );
    });

    test('no instruction and no loading yields no empty card', () {
      expect(
        call(showInstructionBanner: false).phase,
        DriverTellersGuidancePhase.hidden,
      );
    });

    test('an empty presentation never produces a card', () {
      const empty = ResponsiveManeuverPresentation(
        maneuverVisual: ManeuverVisual.followRoute,
        distanceLabel: '',
        primaryInstruction: '   ',
        secondaryInstruction: '',
        urgencyPhase: ManeuverUrgencyPhase.far,
        accessibilityLabel: '',
        isArrival: false,
        isHighwayLike: false,
      );
      expect(
        call(presentation: empty).phase,
        DriverTellersGuidancePhase.hidden,
      );
      expect(driverTellersGuidanceHasContent(null), isFalse);
      expect(driverTellersGuidanceHasContent(empty), isFalse);
    });

    test('the accepted route generation travels with the view', () {
      // Proof 11 (policy half): a new generation produces a new view rather
      // than mutating the old one.
      final a = call(routeVersion: 7);
      final b = call(routeVersion: 8);
      expect(a.routeVersion, 7);
      expect(b.routeVersion, 8);
      expect(identical(a, b), isFalse);
    });

    test('resolving twice from equal inputs is pure', () {
      // Proof 18 (policy half): entering or leaving Tellers only re-reads
      // state; it cannot mutate navigation ownership.
      final a = call();
      final b = call();
      expect(a.phase, b.phase);
      expect(identical(a.presentation, b.presentation), isFalse);
      expect(a.presentation!.primaryInstruction, b.presentation!.primaryInstruction);
    });
  });

  // -------------------------------------------------------------------------
  // Map-pane width and placement contract.
  // -------------------------------------------------------------------------
  group('resolveDriverTellersGuidanceLayout', () {
    test('tablet portrait max width sits inside 68-76% of the map pane', () {
      final g = _geometryFor(kTabletPortrait, isTablet: true);
      final layout = resolveDriverTellersGuidanceLayout(
        geometry: g,
        selectorVisible: true,
      );
      expect(layout.fits, isTrue);
      final fraction = layout.maxWidth / g.liveWindowRect.width;
      expect(fraction, greaterThanOrEqualTo(0.68));
      expect(fraction, lessThanOrEqualTo(0.76));
    });

    test('tablet landscape max width sits inside 65-76% of the map pane', () {
      final g = _geometryFor(kTabletLandscape, isTablet: true);
      final layout = resolveDriverTellersGuidanceLayout(
        geometry: g,
        selectorVisible: true,
      );
      expect(layout.fits, isTrue);
      final fraction = layout.maxWidth / g.liveWindowRect.width;
      expect(fraction, greaterThanOrEqualTo(0.65));
      expect(fraction, lessThanOrEqualTo(0.76));
    });

    test('landscape reserves the selector width deterministically', () {
      // Proof 7 (policy half): the reservation is computed, not accidental.
      final g = _geometryFor(kTabletLandscape, isTablet: true);
      final layout = resolveDriverTellersGuidanceLayout(
        geometry: g,
        selectorVisible: true,
      );
      final rightEdge = layout.left + layout.maxWidth;
      final selectorLeft =
          g.selectorRect.left - g.liveWindowRect.left;
      expect(
        rightEdge,
        lessThanOrEqualTo(selectorLeft - kDriverTellersGuidanceSelectorGap + 0.5),
      );
    });

    test('hiding the selector releases its reserved band', () {
      final g = _geometryFor(kTabletLandscape, isTablet: true);
      final withSelector = resolveDriverTellersGuidanceLayout(
        geometry: g,
        selectorVisible: true,
      );
      final without = resolveDriverTellersGuidanceLayout(
        geometry: g,
        selectorVisible: false,
      );
      // Top band always relaxes when the selector is gone.
      expect(without.top, lessThan(withSelector.top));
      // Reservation contract: with-selector width never exceeds usable-reserved.
      // (On wide map-first landscape the fraction cap may equal both widths.)
      final usable =
          g.liveWindowRect.width - (kDriverTellersGuidanceInset * 2);
      final reserved =
          g.selectorRect.width + kDriverTellersGuidanceSelectorGap;
      expect(
        withSelector.maxWidth,
        lessThanOrEqualTo(usable - reserved + 0.5),
      );
      expect(without.maxWidth, lessThanOrEqualTo(usable + 0.5));
      expect(without.maxWidth, greaterThanOrEqualTo(withSelector.maxWidth));
    });

    test('the card starts below the badge and selector band', () {
      for (final size in <Size>[kTabletPortrait, kTabletLandscape]) {
        final g = _geometryFor(size, isTablet: true);
        final layout = resolveDriverTellersGuidanceLayout(
          geometry: g,
          selectorVisible: true,
        );
        final labelBottom = g.labelRect.bottom - g.liveWindowRect.top;
        expect(layout.top, greaterThan(labelBottom));
        expect(
          layout.top,
          greaterThanOrEqualTo(
            8 + kDriverTellersSelectorPaintedHeight + kDriverTellersGuidanceTopGap,
          ),
        );
      }
    });

    test('a phone aperture is judged too small to carry the card', () {
      final g = _geometryFor(kPhonePortrait, isTablet: false);
      final layout = resolveDriverTellersGuidanceLayout(
        geometry: g,
        selectorVisible: true,
      );
      expect(layout.fits, isFalse);
    });

    test('a degenerate geometry never claims to fit', () {
      final g = _geometryFor(Size.zero, isTablet: true);
      final layout = resolveDriverTellersGuidanceLayout(
        geometry: g,
        selectorVisible: true,
      );
      expect(layout.fits, isFalse);
      expect(layout.maxWidth, 0);
    });
  });

  // -------------------------------------------------------------------------
  // Rendered overlay.
  // -------------------------------------------------------------------------
  group('Tellers guidance overlay', () {
    testWidgets('tablet portrait active navigation shows the instruction', (
      tester,
    ) async {
      // Proof 1.
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await _pump(
        tester,
        size: kTabletPortrait,
        isTablet: true,
        isLandscape: false,
        guidance: _instruction(kTurnLeftSnapshot),
      );
      final p = _present(kTurnLeftSnapshot);
      expect(kOverlay, findsOneWidget);
      expect(find.text(p.primaryInstruction), findsOneWidget);
    });

    testWidgets('tablet landscape active navigation shows the instruction', (
      tester,
    ) async {
      // Proof 2.
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await _pump(
        tester,
        size: kTabletLandscape,
        isTablet: true,
        isLandscape: true,
        guidance: _instruction(kTurnLeftSnapshot),
      );
      final p = _present(kTurnLeftSnapshot);
      expect(kOverlay, findsOneWidget);
      expect(find.text(p.primaryInstruction), findsOneWidget);
    });

    testWidgets('icon, distance, primary and secondary come from the '
        'authoritative presentation', (tester) async {
      // Proof 3.
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final p = _present(kTurnLeftSnapshot);
      await _pump(
        tester,
        size: kTabletPortrait,
        isTablet: true,
        isLandscape: false,
        guidance: _instruction(kTurnLeftSnapshot),
      );
      final banner = tester.widget<DriverTurnInstructionBanner>(
        find.byType(DriverTurnInstructionBanner),
      );
      // The very object the main navigation banner would render.
      expect(banner.presentation, isNotNull);
      expect(banner.presentation!.primaryInstruction, p.primaryInstruction);
      expect(banner.presentation!.secondaryInstruction, p.secondaryInstruction);
      expect(banner.presentation!.distanceLabel, p.distanceLabel);
      expect(banner.presentation!.maneuverVisual, p.maneuverVisual);
      expect(banner.icon, driverManeuverVisualIconData(p.maneuverVisual));
      // NAV-SIGNAGE-VISUAL-RELEASE-GATE: the painted glyph is now the sign
      // plate the resolver picked, not a Material icon.
      expect(find.byType(NavManeuverSign), findsOneWidget);
      expect(
        tester.widget<NavManeuverSign>(find.byType(NavManeuverSign)).assetPath,
        p.signAssetPath,
      );
      if (p.secondaryInstruction.trim().isNotEmpty) {
        expect(find.text(p.secondaryInstruction), findsOneWidget);
      }
    });

    testWidgets('roundabout exit number matches the main presentation', (
      tester,
    ) async {
      // Proof 14.
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final p = _present(kRoundaboutSnapshot);
      expect(p.roundaboutExitNumber, 2);
      await _pump(
        tester,
        size: kTabletPortrait,
        isTablet: true,
        isLandscape: false,
        guidance: _instruction(kRoundaboutSnapshot),
      );
      final banner = tester.widget<DriverTurnInstructionBanner>(
        find.byType(DriverTurnInstructionBanner),
      );
      expect(banner.presentation!.roundaboutExitNumber, 2);
      expect(find.text(p.primaryInstruction), findsOneWidget);
      expect(find.text(p.secondaryInstruction), findsOneWidget);
    });

    testWidgets('arrival shows the arrival presentation and drops stale '
        'context', (tester) async {
      // Proof 13.
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final p = _present(kArrivalSnapshot);
      expect(p.isArrival, isTrue);
      await _pump(
        tester,
        size: kTabletPortrait,
        isTablet: true,
        isLandscape: false,
        guidance: _instruction(kArrivalSnapshot),
      );
      final banner = tester.widget<DriverTurnInstructionBanner>(
        find.byType(DriverTurnInstructionBanner),
      );
      expect(banner.isArrival, isTrue);
      // The snapshot deliberately still carries a stale exit number and street
      // name; the arrival presentation must paint neither.
      expect(banner.presentation!.secondaryInstruction, isEmpty);
      expect(find.text('Kerkweg'), findsNothing);
      expect(find.textContaining('3e'), findsNothing);
      expect(find.textContaining('afslag'), findsNothing);
      expect(find.text(p.primaryInstruction), findsOneWidget);
      expect(
        tester.widget<NavManeuverSign>(find.byType(NavManeuverSign)).assetPath,
        p.signAssetPath,
      );
    });

    testWidgets('an unknown maneuver uses the same neutral fallback', (
      tester,
    ) async {
      // Proof 15.
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final p = _present(kFallbackSnapshot);
      await _pump(
        tester,
        size: kTabletPortrait,
        isTablet: true,
        isLandscape: false,
        guidance: _instruction(kFallbackSnapshot),
      );
      expect(find.text(p.primaryInstruction), findsOneWidget);
      final banner = tester.widget<DriverTurnInstructionBanner>(
        find.byType(DriverTurnInstructionBanner),
      );
      expect(banner.presentation!.maneuverVisual, p.maneuverVisual);
      expect(banner.icon, driverManeuverVisualIconData(p.maneuverVisual));
    });

    testWidgets('a short instruction stays compact', (tester) async {
      // Proof 5.
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final g = _geometryFor(kTabletPortrait, isTablet: true);
      final layout = resolveDriverTellersGuidanceLayout(
        geometry: g,
        selectorVisible: true,
      );
      await _pump(
        tester,
        size: kTabletPortrait,
        isTablet: true,
        isLandscape: false,
        guidance: _instruction(
          _snap(distance: 50, primary: 'Rechts', roadName: 'A'),
        ),
      );
      final width = tester.getSize(kBanner).width;
      expect(width, lessThan(layout.maxWidth));
      expect(width, greaterThan(0));
    });

    testWidgets('a long instruction respects the map-pane maximum', (
      tester,
    ) async {
      // Proof 6.
      addTearDown(() => tester.binding.setSurfaceSize(null));
      for (final entry in <(Size, bool)>[
        (kTabletPortrait, false),
        (kTabletLandscape, true),
      ]) {
        final g = _geometryFor(entry.$1, isTablet: true);
        final layout = resolveDriverTellersGuidanceLayout(
          geometry: g,
          selectorVisible: true,
        );
        await _pump(
          tester,
          size: entry.$1,
          isTablet: true,
          isLandscape: entry.$2,
          guidance: _instruction(kLongSnapshot),
        );
        final banner = tester.getRect(kBanner);
        expect(banner.width, lessThanOrEqualTo(layout.maxWidth + 0.5));
        // And it never escapes the live map aperture.
        final window = tester.getRect(kLiveWindow);
        expect(banner.left, greaterThanOrEqualTo(window.left - 0.5));
        expect(banner.right, lessThanOrEqualTo(window.right + 0.5));
        expect(banner.bottom, lessThanOrEqualTo(window.bottom + 0.5));
      }
    });

    testWidgets('the overlay never overlaps the Car/Arrow selector', (
      tester,
    ) async {
      // Proof 7.
      addTearDown(() => tester.binding.setSurfaceSize(null));
      for (final entry in <(Size, bool)>[
        (kTabletPortrait, false),
        (kTabletLandscape, true),
      ]) {
        await _pump(
          tester,
          size: entry.$1,
          isTablet: true,
          isLandscape: entry.$2,
          guidance: _instruction(kLongSnapshot),
        );
        final overlay = tester.getRect(kBanner);
        final selector = tester.getRect(kSelector);
        expect(
          overlay.overlaps(selector),
          isFalse,
          reason: 'overlay $overlay overlaps selector $selector',
        );
        // The painted selector must stay within the height the placement
        // policy assumes for it.
        expect(
          selector.height,
          lessThanOrEqualTo(kDriverTellersSelectorPaintedHeight),
        );
      }
    });

    testWidgets('the overlay never overlaps the Live navigation badge', (
      tester,
    ) async {
      // Proof 8.
      addTearDown(() => tester.binding.setSurfaceSize(null));
      for (final entry in <(Size, bool)>[
        (kTabletPortrait, false),
        (kTabletLandscape, true),
      ]) {
        await _pump(
          tester,
          size: entry.$1,
          isTablet: true,
          isLandscape: entry.$2,
          guidance: _instruction(kLongSnapshot),
        );
        final overlay = tester.getRect(kBanner);
        final label = tester.getRect(kLabel);
        expect(
          overlay.overlaps(label),
          isFalse,
          reason: 'overlay $overlay overlaps badge $label',
        );
        expect(overlay.top, greaterThanOrEqualTo(label.bottom));
        expect(
          label.height,
          lessThanOrEqualTo(kDriverTellersLabelPaintedHeight),
        );
      }
    });

    testWidgets('portrait to landscape adopts the landscape constraints', (
      tester,
    ) async {
      // Proof 9.
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await _pump(
        tester,
        size: kTabletPortrait,
        isTablet: true,
        isLandscape: false,
        guidance: _instruction(kLongSnapshot),
      );
      final portraitWidth = tester.getSize(kBanner).width;

      await _pump(
        tester,
        size: kTabletLandscape,
        isTablet: true,
        isLandscape: true,
        guidance: _instruction(kLongSnapshot),
      );
      final landscapeLayout = resolveDriverTellersGuidanceLayout(
        geometry: _geometryFor(kTabletLandscape, isTablet: true),
        selectorVisible: true,
      );
      final landscapeWidth = tester.getSize(kBanner).width;
      expect(landscapeWidth, lessThanOrEqualTo(landscapeLayout.maxWidth + 0.5));
      // The landscape map pane is narrower than the portrait one, so the card
      // must actually shrink rather than keep a stale portrait width.
      expect(landscapeWidth, lessThan(portraitWidth + 0.5));
      expect(kOverlay, findsOneWidget);
    });

    testWidgets('landscape to portrait stays stable', (tester) async {
      // Proof 10.
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await _pump(
        tester,
        size: kTabletLandscape,
        isTablet: true,
        isLandscape: true,
        guidance: _instruction(kLongSnapshot),
      );
      await _pump(
        tester,
        size: kTabletPortrait,
        isTablet: true,
        isLandscape: false,
        guidance: _instruction(kLongSnapshot),
      );
      final portraitLayout = resolveDriverTellersGuidanceLayout(
        geometry: _geometryFor(kTabletPortrait, isTablet: true),
        selectorVisible: true,
      );
      expect(kOverlay, findsOneWidget);
      final banner = tester.getRect(kBanner);
      expect(banner.width, lessThanOrEqualTo(portraitLayout.maxWidth + 0.5));
      final window = tester.getRect(kLiveWindow);
      expect(window.contains(banner.topLeft), isTrue);
      expect(tester.takeException(), isNull);
    });

    testWidgets('route replacement removes the previous instruction', (
      tester,
    ) async {
      // Proof 11.
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final oldP = _present(kTurnLeftSnapshot);
      await _pump(
        tester,
        size: kTabletPortrait,
        isTablet: true,
        isLandscape: false,
        guidance: _instruction(kTurnLeftSnapshot, routeVersion: 1),
      );
      expect(find.text(oldP.primaryInstruction), findsOneWidget);

      // The accepted route generation advances and clears the snapshot; the
      // driver page then hands Tellers a loading view for the new generation.
      await _pump(
        tester,
        size: kTabletPortrait,
        isTablet: true,
        isLandscape: false,
        guidance: const DriverTellersGuidanceView(
          phase: DriverTellersGuidancePhase.loading,
          loadingText: 'Route-instructies worden geladen…',
          routeVersion: 2,
        ),
      );
      expect(find.text(oldP.primaryInstruction), findsNothing);
      expect(find.byType(DriverTurnInstructionBanner), findsNothing);
      expect(find.text('Route-instructies worden geladen…'), findsOneWidget);

      final newP = _present(kRoundaboutSnapshot);
      await _pump(
        tester,
        size: kTabletPortrait,
        isTablet: true,
        isLandscape: false,
        guidance: _instruction(kRoundaboutSnapshot, routeVersion: 2),
      );
      expect(find.text(oldP.primaryInstruction), findsNothing);
      expect(find.text(newP.primaryInstruction), findsOneWidget);
    });

    testWidgets('reroute replaces the maneuver with the recalculation state', (
      tester,
    ) async {
      // Proof 12 (render half).
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final p = _present(kTurnLeftSnapshot);
      await _pump(
        tester,
        size: kTabletLandscape,
        isTablet: true,
        isLandscape: true,
        guidance: _instruction(kTurnLeftSnapshot),
      );
      expect(find.text(p.primaryInstruction), findsOneWidget);

      await _pump(
        tester,
        size: kTabletLandscape,
        isTablet: true,
        isLandscape: true,
        guidance: resolveDriverTellersGuidance(
          tellersActive: true,
          followCameraActive: true,
          liveRideActive: true,
          showInstructionBanner: false,
          navStepsLoading: false,
          isRerouting: true,
          snapshotIsLoadingSource: false,
          presentation: null,
          loadingText: 'Route herberekenen…',
          routeVersion: 1,
        ),
      );
      expect(find.text(p.primaryInstruction), findsNothing);
      expect(find.byType(DriverTurnInstructionBanner), findsNothing);
      expect(find.byType(DriverNavLoadingBanner), findsOneWidget);
      expect(find.text('Route herberekenen…'), findsOneWidget);
    });

    testWidgets('inactive navigation paints no overlay and no empty card', (
      tester,
    ) async {
      // Proof 16.
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await _pump(
        tester,
        size: kTabletPortrait,
        isTablet: true,
        isLandscape: false,
        guidance: const DriverTellersGuidanceView.hidden(),
      );
      expect(kOverlay, findsNothing);
      expect(find.byType(DriverTurnInstructionBanner), findsNothing);
      expect(find.byType(DriverNavLoadingBanner), findsNothing);
      // The live window itself is untouched.
      expect(kLiveWindow, findsOneWidget);
      expect(kLabel, findsOneWidget);
    });

    testWidgets('switching Car/Arrow does not alter the instruction', (
      tester,
    ) async {
      // Proof 17.
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final guidance = _instruction(kTurnLeftSnapshot);
      final p = _present(kTurnLeftSnapshot);
      var selected = DriverNavigationMarkerChoice.car;
      await _pump(
        tester,
        size: kTabletLandscape,
        isTablet: true,
        isLandscape: true,
        guidance: guidance,
        markerChoice: selected,
        onMarkerChoiceSelected: (c) => selected = c,
      );
      final before = tester.getRect(kBanner);
      expect(find.text(p.primaryInstruction), findsOneWidget);

      await _pump(
        tester,
        size: kTabletLandscape,
        isTablet: true,
        isLandscape: true,
        guidance: guidance,
        markerChoice: DriverNavigationMarkerChoice.arrow,
        onMarkerChoiceSelected: (c) => selected = c,
      );
      final after = tester.getRect(kBanner);
      expect(find.text(p.primaryInstruction), findsOneWidget);
      expect(after, before);
      final banner = tester.widget<DriverTurnInstructionBanner>(
        find.byType(DriverTurnInstructionBanner),
      );
      expect(identical(banner.presentation, guidance.presentation), isTrue);
    });

    testWidgets('a phone Tellers layout is left alone', (tester) async {
      // Phone safety: no overlay is forced onto a cramped aperture.
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await _pump(
        tester,
        size: kPhonePortrait,
        isTablet: false,
        isLandscape: false,
        guidance: _instruction(kTurnLeftSnapshot),
      );
      expect(kOverlay, findsNothing);
      expect(kLiveWindow, findsOneWidget);
      expect(kSelector, findsOneWidget);
    });

    testWidgets('a phone landscape aperture gets a compact overlay that '
        'stays clear of the controls', (tester) async {
      // Phone safety, permissive half: the overlay is allowed where it
      // genuinely fits, and even then only at a compact width.
      addTearDown(() => tester.binding.setSurfaceSize(null));
      const size = Size(844, 390);
      await _pump(
        tester,
        size: size,
        isTablet: false,
        isLandscape: true,
        guidance: _instruction(kLongSnapshot),
      );
      final g = _geometryFor(size, isTablet: false);
      final layout = resolveDriverTellersGuidanceLayout(
        geometry: g,
        selectorVisible: true,
      );
      expect(layout.fits, isTrue);
      expect(kOverlay, findsOneWidget);
      final banner = tester.getRect(kBanner);
      expect(banner.width, lessThanOrEqualTo(layout.maxWidth + 0.5));
      expect(banner.overlaps(tester.getRect(kSelector)), isFalse);
      expect(banner.overlaps(tester.getRect(kLabel)), isFalse);
      final window = tester.getRect(kLiveWindow);
      expect(banner.bottom, lessThanOrEqualTo(window.bottom + 0.5));
      expect(banner.right, lessThanOrEqualTo(window.right + 0.5));
    });

    testWidgets('the overlay adds no lane strip', (tester) async {
      // Lane guidance stays out of this commit; nothing may be fabricated.
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await _pump(
        tester,
        size: kTabletPortrait,
        isTablet: true,
        isLandscape: false,
        guidance: _instruction(kTurnLeftSnapshot),
      );
      final banner = tester.widget<DriverTurnInstructionBanner>(
        find.byType(DriverTurnInstructionBanner),
      );
      expect(banner.lanes, isEmpty);
    });
  });

  // -------------------------------------------------------------------------
  // Ownership guards: the Tellers surface must stay presentation-only.
  // -------------------------------------------------------------------------
  group('no duplicate navigation logic', () {
    /// Reads a source file with its `//` comments removed, so the guards below
    /// assert about real code rather than about prose describing it.
    String read(String path) {
      return File(path)
          .readAsLinesSync()
          .map((line) {
            final i = line.indexOf('//');
            return i < 0 ? line : line.substring(0, i);
          })
          .join('\n');
    }

    const tellersView = 'lib/navigation/presentation/driver_ride_meters.dart';
    const tellersPolicy =
        'lib/navigation/presentation/driver_tellers_guidance.dart';

    test('Tellers keeps no maneuver index and no route steps', () {
      // Proofs 4 and 19.
      const forbidden = <String>[
        '_nextStepIndex',
        'nextStepIndex',
        'routeSteps',
        'maneuverStepIndex',
        'routeCoords',
        'exitNumber',
        'buildDriverNavInstructionPresentation',
        'resolveDriverLaneGuidance',
        'resolveDriverManeuverVisual',
        'resolveDriverRoundaboutExitNumber',
        'DriverNavBannerResolve',
        'jsonDecode',
        'Directions',
      ];
      for (final path in <String>[tellersView, tellersPolicy]) {
        final src = read(path);
        for (final token in forbidden) {
          expect(
            src.contains(token),
            isFalse,
            reason: '$path must not reference $token',
          );
        }
      }
    });

    test('the policy owns no mutable navigation state', () {
      // Proof 18.
      final src = read(tellersPolicy);
      expect(src.contains('class '), isTrue);
      expect(src.contains('setState'), isFalse);
      expect(src.contains('Timer'), isFalse);
      expect(src.contains('static '), isFalse);
      // Pure functions only: no late/mutable module state.
      expect(RegExp(r'^(late|var) ', multiLine: true).hasMatch(src), isFalse);
    });

    test('the Tellers view renders the shared banner widgets', () {
      // The overlay must reuse the main navigation widgets, not a private copy.
      final src = read(tellersView);
      expect(src.contains('DriverTurnInstructionBanner('), isTrue);
      expect(src.contains('DriverNavLoadingBanner('), isTrue);
      expect(src.contains('driverManeuverVisualIconData('), isTrue);
    });
  });
}
