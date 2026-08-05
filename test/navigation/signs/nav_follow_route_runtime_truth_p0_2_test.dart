// NAV-FOLLOW-ROUTE-RUNTIME-TRUTH-P0-2
//
// Field proof 05-08-2026 ~16:39: "Volg de route naar N454" still painted the
// curved follow_route plate because followRouteForced / policy-neutral mapped
// to neutralFallback → follow_route.png. Ordinary continue guidance must prove
// canonical_id=straight and asset basename=straight.png at runtime.

import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/navigation/driver_navigation_models.dart';
import 'package:fluxidi_tracking/navigation/nav_engine/nav_maneuver_owner.dart';
import 'package:fluxidi_tracking/navigation/presentation/maneuver_presentation.dart';
import 'package:fluxidi_tracking/navigation/presentation/nav_maneuver_sign.dart';
import 'package:fluxidi_tracking/navigation/presentation/nav_sign_resolver.dart';
import 'package:fluxidi_tracking/navigation/presentation/nav_signage_tablet_readability.dart';
import 'package:fluxidi_tracking/widgets/driver_nav_banners.dart';

String _tr({
  required String nl,
  required String en,
  required String fr,
  required String es,
}) =>
    nl;

NavSignRuntimeTruth _truth({
  required String type,
  String modifier = '',
  bool followRouteForced = false,
  String primaryText = 'Volg de route',
  String roadRef = 'N454',
}) {
  return proveNavSignRuntimeTruth(
    type: type,
    modifier: modifier,
    followRouteForced: followRouteForced,
    primaryText: primaryText,
    secondaryText: 'naar $roadRef',
    roadName: roadRef,
    roadRef: roadRef,
    tr: _tr,
    languageCode: 'nl',
  );
}

String _sha256(String relativePath) {
  final bytes = File(relativePath).readAsBytesSync();
  return sha256.convert(bytes).toString();
}

Widget _bannerFor(
  ResponsiveManeuverPresentation p, {
  required Size size,
  required bool isTablet,
  required bool compact,
  bool topRowLandscape = false,
  NavSignageTabletReadabilityMetrics? tabletReadability,
}) {
  return MediaQuery(
    data: MediaQueryData(size: size, devicePixelRatio: 1.0),
    child: Directionality(
      textDirection: TextDirection.ltr,
      child: MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: DriverTurnInstructionBanner(
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
              tabletReadability: tabletReadability,
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  group('runtime truth: continue → straight', () {
    test('1. continue + empty modifier → straight ID + straight.png', () {
      final t = _truth(type: 'continue', modifier: '');
      expect(t.canonicalId, 'straight');
      expect(t.assetBasename, 'straight.png');
      expect(t.assetPath, endsWith('/straight.png'));
      expect(t.maneuverVisual, ManeuverVisual.straight);
      expect(t.assetPath, isNot(contains('follow_route')));
    });

    test('2. continue + straight modifier → straight ID + straight.png', () {
      final t = _truth(type: 'continue', modifier: 'straight');
      expect(t.canonicalId, 'straight');
      expect(t.assetBasename, 'straight.png');
    });

    test('3. instruction "Volg de route" does not force follow_route', () {
      final t = _truth(
        type: 'continue',
        modifier: 'straight',
        primaryText: 'Volg de route',
        followRouteForced: false,
      );
      expect(t.canonicalId, 'straight');
      expect(t.assetBasename, 'straight.png');
    });

    test('4. geometric curvature / bearings do not force follow_route', () {
      // Presentation never reads bearings for sign classification.
      final snap = NavInstructionSnapshot(
        distanceToManeuverMeters: 643,
        primaryText: 'Volg de route',
        secondaryText: 'naar N454',
        maneuverType: 'continue',
        maneuverModifier: 'straight',
        roadName: 'N454',
        roadRef: 'N454',
        bearingBefore: 10,
        bearingAfter: 95, // large bend — must stay straight
        isHighwayLike: false,
        lanes: const <DriverNavLaneGuidance>[],
        source: NavInstructionSource.banner,
      );
      final p = buildResponsiveManeuverPresentation(
        snapshot: snap,
        tr: _tr,
        languageCode: 'nl',
      );
      expect(p.signManeuver, NavSignManeuver.straight);
      expect(p.maneuverVisual, isNot(ManeuverVisual.slightLeft));
      expect(p.maneuverVisual, isNot(ManeuverVisual.slightRight));
      expect(p.signAssetPath, endsWith('/straight.png'));
    });

    test('5. stale/cached follow_route is replaced by new continue step', () {
      final stale = _truth(
        type: 'unmapped_engine_event',
        modifier: '',
      );
      expect(stale.canonicalId, 'follow_route');

      final next = _truth(type: 'continue', modifier: 'straight');
      expect(next.canonicalId, 'straight');
      expect(next.assetBasename, 'straight.png');
      expect(next.canonicalId, isNot(stale.canonicalId));
    });

    test('policy-neutral / followRouteForced continue still uses straight.png',
        () {
      final t = _truth(
        type: 'continue',
        modifier: 'straight',
        followRouteForced: true,
        primaryText: 'Volg de route',
      );
      expect(t.neutralFallback, isTrue);
      expect(t.canonicalId, 'straight');
      expect(t.assetBasename, 'straight.png');
      expect(t.maneuverVisual, ManeuverVisual.straight);
    });

    test('owner classifies continue as alwaysActive (not followOnly)', () {
      expect(
        classifyNavManeuverActivation(type: 'continue', modifier: 'straight'),
        NavManeuverActivationClass.alwaysActive,
      );
      expect(
        classifyNavManeuverActivation(type: 'continue', modifier: ''),
        NavManeuverActivationClass.alwaysActive,
      );
    });
  });

  group('surfaces: full-nav / split / pre-start', () {
    test('6. full-nav presentation uses straight.png', () {
      final p = buildResponsiveManeuverPresentation(
        snapshot: NavInstructionSnapshot(
          distanceToManeuverMeters: 643,
          primaryText: 'Volg de route',
          secondaryText: 'naar N454',
          maneuverType: 'continue',
          maneuverModifier: 'straight',
          roadName: 'N454',
          roadRef: 'N454',
          isHighwayLike: false,
          lanes: const <DriverNavLaneGuidance>[],
          source: NavInstructionSource.banner,
        ),
        tr: _tr,
        languageCode: 'nl',
      );
      expect(p.signAssetPath, endsWith('/straight.png'));
    });

    test('7. Tellers-split presentation uses straight.png', () {
      final p = buildResponsiveManeuverPresentation(
        snapshot: NavInstructionSnapshot(
          distanceToManeuverMeters: 643,
          primaryText: 'Volg de route',
          secondaryText: 'naar N454',
          maneuverType: 'continue',
          maneuverModifier: '',
          roadName: 'N454',
          roadRef: 'N454',
          isHighwayLike: false,
          lanes: const <DriverNavLaneGuidance>[],
          source: NavInstructionSource.banner,
        ),
        tr: _tr,
        languageCode: 'nl',
      );
      final split = NavSignageTabletReadabilityMetrics.forSplitNav(
        availableBannerWidth: 320,
      );
      expect(split.isSplitNav, isTrue);
      expect(p.signManeuver, NavSignManeuver.straight);
      expect(p.signAssetPath, endsWith('/straight.png'));
    });

    test('8. pre-start (followRouteForced) uses straight.png', () {
      final t = _truth(
        type: 'turn',
        modifier: 'right',
        followRouteForced: true,
      );
      expect(t.canonicalId, 'straight');
      expect(t.assetBasename, 'straight.png');
    });
  });

  group('asset truth', () {
    test('9. straight.png and follow_route.png differ (all languages)', () {
      for (final lang in const ['nl', 'en', 'fr', 'es']) {
        final straight =
            _sha256('assets/fluxidi_navigation_signs_v3/png/$lang/straight.png');
        final follow = _sha256(
          'assets/fluxidi_navigation_signs_v3/png/$lang/follow_route.png',
        );
        expect(straight, isNot(follow), reason: '$lang hashes must differ');
        expect(straight, hasLength(64));
        expect(follow, hasLength(64));
      }
      // Languages share identical captionless plates.
      final nl = _sha256('assets/fluxidi_navigation_signs_v3/png/nl/straight.png');
      for (final lang in const ['en', 'fr', 'es']) {
        expect(
          _sha256('assets/fluxidi_navigation_signs_v3/png/$lang/straight.png'),
          nl,
        );
      }
    });

    test('resolver never returns follow_route.png for continue', () {
      for (final mod in const ['', 'straight', 'forward']) {
        final r = resolveNavSign(
          NavSignEvent(maneuverType: 'continue', maneuverModifier: mod),
        );
        expect(r.maneuver, NavSignManeuver.straight);
        expect(
          navSignAssetPath(languageCode: 'nl', maneuver: r.maneuver),
          isNot(contains('follow_route')),
        );
      }
      final forced = resolveNavSign(
        const NavSignEvent(
          maneuverType: 'continue',
          maneuverModifier: 'straight',
          neutralFallback: true,
        ),
      );
      expect(forced.maneuver, NavSignManeuver.straight);
    });
  });

  group('tablet portrait text + landscape/phone', () {
    testWidgets('10-12. tablet portrait shows full Volg de route + naar N454',
        (tester) async {
      const size = Size(800, 1280);
      final p = buildResponsiveManeuverPresentation(
        snapshot: NavInstructionSnapshot(
          distanceToManeuverMeters: 643,
          primaryText: 'Volg de route',
          secondaryText: 'naar N454',
          maneuverType: 'continue',
          maneuverModifier: 'straight',
          roadName: 'N454',
          roadRef: 'N454',
          isHighwayLike: false,
          lanes: const <DriverNavLaneGuidance>[],
          source: NavInstructionSource.banner,
          followRouteForced: true,
        ),
        tr: _tr,
        languageCode: 'nl',
      );
      final metrics = NavSignageTabletReadabilityMetrics.forViewport(
        viewport: size,
        isLandscape: false,
      );
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        _bannerFor(
          p,
          size: size,
          isTablet: true,
          compact: false,
          tabletReadability: metrics,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Volg de route'), findsOneWidget);
      expect(find.textContaining('Volg de…'), findsNothing);
      expect(find.textContaining('Volg de...'), findsNothing);
      expect(find.textContaining('N454'), findsOneWidget);

      final sign = tester.widget<NavManeuverSign>(find.byType(NavManeuverSign));
      expect(sign.maneuver, NavSignManeuver.straight);
      expect(sign.assetPath, endsWith('/straight.png'));

      final primary = tester.widget<Text>(find.text('Volg de route'));
      expect(primary.overflow, isNot(TextOverflow.ellipsis));
    });

    testWidgets('13. tablet landscape stays green with straight plate',
        (tester) async {
      const size = Size(1194, 834);
      final p = buildResponsiveManeuverPresentation(
        snapshot: NavInstructionSnapshot(
          distanceToManeuverMeters: 643,
          primaryText: 'Volg de route',
          secondaryText: 'naar N454',
          maneuverType: 'continue',
          maneuverModifier: '',
          roadName: 'N454',
          roadRef: 'N454',
          isHighwayLike: false,
          lanes: const <DriverNavLaneGuidance>[],
          source: NavInstructionSource.banner,
          followRouteForced: true,
        ),
        tr: _tr,
        languageCode: 'nl',
      );
      final metrics = NavSignageTabletReadabilityMetrics.forViewport(
        viewport: size,
        isLandscape: true,
      );
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        _bannerFor(
          p,
          size: size,
          isTablet: true,
          compact: true,
          topRowLandscape: true,
          tabletReadability: metrics,
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Volg de route'), findsOneWidget);
      final sign = tester.widget<NavManeuverSign>(find.byType(NavManeuverSign));
      expect(sign.assetPath, endsWith('/straight.png'));
    });

    testWidgets('14. phone has no overflow', (tester) async {
      const size = Size(390, 844);
      final p = buildResponsiveManeuverPresentation(
        snapshot: NavInstructionSnapshot(
          distanceToManeuverMeters: 191,
          primaryText: 'Volg de route',
          secondaryText: 'naar N454',
          maneuverType: 'continue',
          maneuverModifier: 'straight',
          roadName: 'N454',
          roadRef: 'N454',
          isHighwayLike: false,
          lanes: const <DriverNavLaneGuidance>[],
          source: NavInstructionSource.banner,
          followRouteForced: true,
        ),
        tr: _tr,
        languageCode: 'nl',
      );
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        _bannerFor(p, size: size, isTablet: false, compact: false),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(NavManeuverSign), findsOneWidget);
    });
  });
}
