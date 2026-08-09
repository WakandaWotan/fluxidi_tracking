// TABLET-LOCALIZED-NAV-SIGNAGE-1 / NAV-SIGNS-BLACK-CONTOUR-V3 pickup

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/navigation/driver_navigation_models.dart';
import 'package:fluxidi_tracking/navigation/presentation/maneuver_presentation.dart';
import 'package:fluxidi_tracking/navigation/presentation/nav_sign_resolver.dart';
import 'package:fluxidi_tracking/navigation/presentation/nav_signage_tablet_readability.dart';

String _tr({
  required String nl,
  required String en,
  required String fr,
  required String es,
}) =>
    nl;

NavInstructionSnapshot _snap({
  required String type,
  String modifier = '',
  double distance = 191,
  String road = 'Hofveldstraat',
}) {
  return NavInstructionSnapshot(
    distanceToManeuverMeters: distance,
    primaryText: '',
    secondaryText: '',
    maneuverType: type,
    maneuverModifier: modifier,
    roadName: road,
    roadRef: '',
    isHighwayLike: false,
    lanes: const <DriverNavLaneGuidance>[],
    source: NavInstructionSource.banner,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('runtime HUD uses BLACK-CONTOUR-V3 png/ family', () {
    test('1) straight resolves to png/nl — never png_captioned', () {
      for (final captionedFlag in <bool>[true, false]) {
        final path = navSignAssetPath(
          languageCode: 'nl',
          maneuver: NavSignManeuver.straight,
          useCaptioned: captionedFlag,
        );
        expect(
          path,
          'assets/fluxidi_navigation_signs_v3/png/nl/straight.png',
        );
        expect(path, isNot(contains('png_captioned')));
        expect(File(path).existsSync(), isTrue);
      }
    });

    test('2) NL/EN/FR/ES share the same png/ source family', () {
      for (final lang in kNavSignLanguageCodes) {
        final path = navSignAssetPath(
          languageCode: lang,
          maneuver: NavSignManeuver.straight,
          useCaptioned: true,
        );
        expect(path, startsWith('$kNavSignAssetRoot/$lang/'));
        expect(path, endsWith('/straight.png'));
        expect(path, isNot(contains('png_captioned')));
        expect(File(path).existsSync(), isTrue);
      }
    });

    test('3) legacy png_captioned remains on disk but is not the HUD path', () {
      final legacy = navSignLegacyCaptionedAssetPaths().firstWhere(
        (p) => p.endsWith('/nl/straight.png'),
      );
      expect(legacy, contains('png_captioned/nl/straight.png'));
      expect(File(legacy).existsSync(), isTrue);
      final runtime = navSignAssetPath(
        languageCode: 'nl',
        maneuver: NavSignManeuver.straight,
        useCaptioned: true,
      );
      expect(runtime, isNot(equals(legacy)));
      expect(
        File(runtime).readAsBytesSync(),
        isNot(equals(File(legacy).readAsBytesSync())),
      );
    });

    test('4) FR/ES language directories stay under png/', () {
      expect(
        navSignAssetPath(
          languageCode: 'fr',
          maneuver: NavSignManeuver.turnRight,
          useCaptioned: true,
        ),
        'assets/fluxidi_navigation_signs_v3/png/fr/turn_right.png',
      );
      expect(
        navSignAssetPath(
          languageCode: 'es',
          maneuver: NavSignManeuver.turnLeft,
          useCaptioned: true,
        ),
        'assets/fluxidi_navigation_signs_v3/png/es/turn_left.png',
      );
    });
  });

  group('tablet sizes', () {
    test('5) full-nav plate at least 160', () {
      final m = NavSignageTabletReadabilityMetrics.resolve(
        isLandscape: false,
        availableBannerWidth: 560,
      );
      expect(m.signSize, greaterThanOrEqualTo(160));
      expect(m.signSize, lessThanOrEqualTo(180));
    });

    test('6) split plate at least 120', () {
      final m = NavSignageTabletReadabilityMetrics.forSplitNav(
        availableBannerWidth: 360,
      );
      expect(m.signSize, greaterThanOrEqualTo(120));
      expect(m.signSize, lessThanOrEqualTo(140));
    });
  });

  group('tablet presentation copy (caption on plate)', () {
    test('7/8) tablet flag suppresses external maneuver verb; asset is png/',
        () {
      final p = buildResponsiveManeuverPresentation(
        snapshot: _snap(type: 'turn', modifier: 'right', distance: 191),
        tr: _tr,
        languageCode: 'nl',
        useCaptionedSign: true,
      );
      expect(p.signCaptioned, isTrue);
      expect(p.signAssetPath, 'assets/fluxidi_navigation_signs_v3/png/nl/turn_right.png');
      expect(p.signAssetPath, isNot(contains('png_captioned')));
      expect(p.primaryInstruction, isEmpty);
      expect(p.distanceLabel, isNotEmpty);
      expect(p.secondaryInstruction.toLowerCase(), contains('hofveldstraat'));
      expect(p.primaryInstruction.toLowerCase(), isNot(contains('rechts')));
    });

    test('9) phone stays on png/ with external primary', () {
      final p = buildResponsiveManeuverPresentation(
        snapshot: _snap(type: 'turn', modifier: 'right', distance: 191),
        tr: _tr,
        languageCode: 'nl',
        useCaptionedSign: false,
      );
      expect(p.signCaptioned, isFalse);
      expect(p.signAssetPath, contains('/png/nl/turn_right.png'));
      expect(p.signAssetPath, isNot(contains('png_captioned')));
      expect(p.primaryInstruction.trim(), isNotEmpty);
    });

    test('10) all 34 IDs resolve in four languages under png/', () {
      for (final lang in kNavSignLanguageCodes) {
        for (final maneuver in NavSignManeuver.values) {
          final path = navSignAssetPath(
            languageCode: lang,
            maneuver: maneuver,
            useCaptioned: true,
          );
          expect(File(path).existsSync(), isTrue, reason: path);
          expect(path, startsWith('$kNavSignAssetRoot/$lang/'));
        }
      }
      expect(NavSignManeuver.values.length, 34);
    });
  });

  test('tablet form-factor gate remains shortestSide 600', () {
    expect(isNavSignageTabletLayout(const Size(1024, 768)), isTrue);
    expect(isNavSignageTabletLayout(const Size(390, 844)), isFalse);
  });
}
