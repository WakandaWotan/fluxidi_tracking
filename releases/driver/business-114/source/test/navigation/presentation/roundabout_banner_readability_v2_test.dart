// NAV-ROUNDABOUT-LANE-CLARITY-P0-2026-07-31
//
// Presentation contracts for the roundabout banner readability changes:
//
//  1. "Neem de Nde afslag" is the PRIMARY instruction when the ordinal is
//     known (never demoted to secondary in the actionable phases).
//  2. Destination road name is the SECONDARY line (may controllably
//     ellipsize on a single line).
//  3. Primary instruction is NEVER ellipsized (`TextOverflow.visible`) so
//     the ordinal is always fully visible, even on narrow phones.
//  4. Distance chip never truncates (`TextOverflow.visible`,
//     `softWrap: false`).
//  5. NAV-SIGNAGE-VISUAL-RELEASE-GATE: the exit-specific sign plate replaces
//     the generic roundabout plate when the ordinal is known.
//  6. Long secondary road names are ellipsized on ONE line.
//  7. Left- and right-oriented approach modifiers do NOT alter the primary
//     ordinal text (only the icon orientation may differ).
//  8. Missing exit ordinal falls back to the approach copy — never invents
//     an ordinal.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/driver_theme_store.dart';
import 'package:fluxidi_tracking/driver_theme_palette.dart';
import 'package:fluxidi_tracking/navigation/driver_navigation_models.dart';
import 'package:fluxidi_tracking/navigation/presentation/maneuver_presentation.dart';
import 'package:fluxidi_tracking/navigation/presentation/nav_maneuver_sign.dart';
import 'package:fluxidi_tracking/navigation/presentation/nav_sign_resolver.dart';
import 'package:fluxidi_tracking/widgets/driver_nav_banners.dart';

String _trNl({
  required String nl,
  required String en,
  required String fr,
  required String es,
}) => nl;

NavInstructionSnapshot _snap({
  required double distance,
  String type = 'roundabout',
  String modifier = '',
  String primary = '',
  String secondary = '',
  String roadName = '',
  String? roadRef,
  String? destination,
  String? exitNumber,
  bool isHighwayLike = false,
  NavInstructionSource source = NavInstructionSource.banner,
}) {
  return NavInstructionSnapshot(
    distanceToManeuverMeters: distance,
    primaryText: primary,
    secondaryText: secondary,
    maneuverType: type,
    maneuverModifier: modifier,
    roadName: roadName,
    exitNumber: exitNumber,
    destinationText: destination,
    roadRef: roadRef,
    isHighwayLike: isHighwayLike,
    lanes: const <DriverNavLaneGuidance>[],
    source: source,
  );
}

ResponsiveManeuverPresentation _present(NavInstructionSnapshot snap) =>
    buildResponsiveManeuverPresentation(snapshot: snap, tr: _trNl);

Widget _wrap(Widget child, {Size size = const Size(400, 800)}) {
  return MediaQuery(
    data: MediaQueryData(size: size),
    child: Directionality(
      textDirection: TextDirection.ltr,
      child: MaterialApp(
        home: Scaffold(
          body: Align(alignment: Alignment.topCenter, child: child),
        ),
      ),
    ),
  );
}

DriverTurnInstructionBanner _banner(
  ResponsiveManeuverPresentation p, {
  bool compact = false,
  bool isTablet = false,
  bool topRowLandscape = false,
}) {
  return DriverTurnInstructionBanner(
    compact: compact,
    isTablet: isTablet,
    topRowLandscape: topRowLandscape,
    isArrival: p.isArrival,
    isHighwayLike: p.isHighwayLike,
    distancePrefix: '',
    distanceText: p.distanceLabel,
    primaryText: p.primaryInstruction,
    secondaryText: p.secondaryInstruction,
    icon: driverManeuverVisualIconData(p.maneuverVisual),
    presentation: p,
  );
}

Text _findPrimary(WidgetTester tester) {
  final finder = find.textContaining('afslag');
  expect(finder, findsOneWidget);
  return tester.widget<Text>(finder);
}

void main() {
  setUpAll(() {
    driverThemeNotifier.value = DriverThemeVariant.midnightBlue;
  });

  group('roundabout banner: primary = exit ordinal, never ellipsized', () {
    for (final exit in const [1, 2, 3, 4]) {
      test('exit $exit → primary is the ordinal line', () {
        final p = _present(_snap(distance: 400, exitNumber: '$exit'));
        expect(p.primaryInstruction, contains('afslag'));
        expect(p.roundaboutExitNumber, exit);
      });
    }

    testWidgets('primary ordinal is visible and has TextOverflow.visible', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(400, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final p = _present(
        _snap(distance: 400, exitNumber: '2', roadRef: 'N454'),
      );
      await tester.pumpWidget(_wrap(_banner(p)));
      await tester.pump();
      final primary = _findPrimary(tester);
      expect(primary.overflow, TextOverflow.visible);
      expect(primary.maxLines, greaterThanOrEqualTo(2));
    });

    testWidgets('primary ordinal stays visible on narrow phone width', (
      tester,
    ) async {
      const narrow = Size(320, 700);
      await tester.binding.setSurfaceSize(narrow);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final p = _present(_snap(distance: 400, exitNumber: '4'));
      await tester.pumpWidget(_wrap(_banner(p), size: narrow));
      await tester.pump();
      expect(find.text('Neem de 4de afslag'), findsOneWidget);
      final primary = _findPrimary(tester);
      expect(primary.overflow, TextOverflow.visible);
      expect(tester.takeException(), isNull);
    });
  });

  group('roundabout banner: distance chip never truncates', () {
    testWidgets('distance chip uses TextOverflow.visible (not ellipsis)', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(400, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final p = _present(
        _snap(distance: 780, exitNumber: '2', roadRef: 'N425'),
      );
      await tester.pumpWidget(_wrap(_banner(p)));
      await tester.pump();
      // Distance chip is one of the Text widgets — locate by content.
      final chip = find.text('780 m');
      expect(chip, findsOneWidget);
      final txt = tester.widget<Text>(chip);
      expect(txt.overflow, TextOverflow.visible);
      expect(txt.softWrap, isFalse);
    });
  });

  group('roundabout banner: exit-specific sign', () {
    testWidgets(
      'known exit → the exit-specific plate replaces the generic one',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(400, 800));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final p = _present(_snap(distance: 400, exitNumber: '2'));
        await tester.pumpWidget(_wrap(_banner(p)));
        await tester.pump();
        final sign = tester.widget<NavManeuverSign>(
          find.byType(NavManeuverSign),
        );
        expect(sign.maneuver, NavSignManeuver.roundaboutExit2);
      },
    );

    testWidgets(
      'missing exit → generic roundabout plate (never invent an ordinal)',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(400, 800));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final p = _present(_snap(distance: 400, exitNumber: null));
        await tester.pumpWidget(_wrap(_banner(p)));
        await tester.pump();
        final sign = tester.widget<NavManeuverSign>(
          find.byType(NavManeuverSign),
        );
        expect(sign.maneuver, NavSignManeuver.roundabout);
        expect(p.roundaboutExitNumber, isNull);
      },
    );
  });

  group('roundabout banner: secondary road name is controllably truncated', () {
    testWidgets('long roadRef ellipsizes on one line as secondary', (
      tester,
    ) async {
      const longRef =
          'Very Very Very Long Road Reference That Should Ellipsize On The '
          'Secondary Line Of A Narrow Phone Banner';
      await tester.binding.setSurfaceSize(const Size(360, 780));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final p = _present(
        _snap(distance: 400, exitNumber: '2', roadRef: longRef),
      );
      await tester.pumpWidget(_wrap(_banner(p), size: const Size(360, 780)));
      await tester.pump();
      final secondaryFinder = find.textContaining('naar');
      expect(secondaryFinder, findsOneWidget);
      final secondary = tester.widget<Text>(secondaryFinder);
      expect(secondary.maxLines, 1);
      expect(secondary.overflow, TextOverflow.ellipsis);
      // Primary is still the ordinal and must NOT be ellipsized.
      final primary = _findPrimary(tester);
      expect(primary.overflow, TextOverflow.visible);
    });
  });

  group('roundabout banner: left/right orientation does not alter ordinal', () {
    test('modifier=left keeps ordinal wording intact', () {
      final p = _present(
        _snap(distance: 400, exitNumber: '2', modifier: 'left'),
      );
      expect(p.primaryInstruction, 'Neem de 2de afslag');
    });

    test('modifier=right keeps ordinal wording intact', () {
      final p = _present(
        _snap(distance: 400, exitNumber: '2', modifier: 'right'),
      );
      expect(p.primaryInstruction, 'Neem de 2de afslag');
    });
  });

  group(
    'roundabout banner: missing exit → approach fallback (no invention)',
    () {
      test('null exit → primary is "Over 400 m de rotonde op"', () {
        final p = _present(_snap(distance: 400, exitNumber: null));
        expect(p.roundaboutExitNumber, isNull);
        expect(p.primaryInstruction, 'Over 400 m de rotonde op');
        expect(p.secondaryInstruction, isNot(contains('afslag')));
      });
    },
  );
}
