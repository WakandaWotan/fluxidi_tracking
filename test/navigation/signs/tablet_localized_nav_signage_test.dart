// TABLET-LOCALIZED-NAV-SIGNAGE-1

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

  group('captioned asset source (a4d7aed restore)', () {
    test('1) tablet NL uses captioned NL straight', () {
      final path = navSignAssetPath(
        languageCode: 'nl',
        maneuver: NavSignManeuver.straight,
        useCaptioned: true,
      );
      expect(path, contains('png_captioned/nl/straight.png'));
      expect(File(path).existsSync(), isTrue);
      final phone = navSignAssetPath(
        languageCode: 'nl',
        maneuver: NavSignManeuver.straight,
        useCaptioned: false,
      );
      expect(
        File(path).readAsBytesSync(),
        isNot(equals(File(phone).readAsBytesSync())),
      );
    });

    test('2) tablet EN uses captioned EN straight', () {
      final nl = File(
        navSignAssetPath(
          languageCode: 'nl',
          maneuver: NavSignManeuver.straight,
          useCaptioned: true,
        ),
      ).readAsBytesSync();
      final en = File(
        navSignAssetPath(
          languageCode: 'en',
          maneuver: NavSignManeuver.straight,
          useCaptioned: true,
        ),
      ).readAsBytesSync();
      expect(nl, isNot(equals(en)));
    });

    test('3) tablet FR uses captioned FR right', () {
      final fr = navSignAssetPath(
        languageCode: 'fr',
        maneuver: NavSignManeuver.turnRight,
        useCaptioned: true,
      );
      expect(fr, contains('png_captioned/fr/turn_right.png'));
      expect(File(fr).existsSync(), isTrue);
    });

    test('4) tablet ES uses captioned ES left', () {
      final es = navSignAssetPath(
        languageCode: 'es',
        maneuver: NavSignManeuver.turnLeft,
        useCaptioned: true,
      );
      expect(es, contains('png_captioned/es/turn_left.png'));
      expect(File(es).existsSync(), isTrue);
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

  group('captioned presentation copy', () {
    test('7/8) captioned tablet does not duplicate maneuver caption externally',
        () {
      final p = buildResponsiveManeuverPresentation(
        snapshot: _snap(type: 'turn', modifier: 'right', distance: 191),
        tr: _tr,
        languageCode: 'nl',
        useCaptionedSign: true,
      );
      expect(p.signCaptioned, isTrue);
      expect(p.signAssetPath, contains('png_captioned/nl/turn_right.png'));
      expect(p.primaryInstruction, isEmpty);
      expect(p.distanceLabel, isNotEmpty);
      expect(p.secondaryInstruction.toLowerCase(), contains('hofveldstraat'));
      expect(p.primaryInstruction.toLowerCase(), isNot(contains('rechts')));
    });

    test('9) phone stays captionless with external primary', () {
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

    test('10) all 34 IDs resolve in four languages (captioned + phone)', () {
      for (final lang in kNavSignLanguageCodes) {
        for (final maneuver in NavSignManeuver.values) {
          final captioned = navSignAssetPath(
            languageCode: lang,
            maneuver: maneuver,
            useCaptioned: true,
          );
          final phone = navSignAssetPath(
            languageCode: lang,
            maneuver: maneuver,
            useCaptioned: false,
          );
          expect(File(captioned).existsSync(), isTrue, reason: captioned);
          expect(File(phone).existsSync(), isTrue, reason: phone);
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
