// LIGHT-EMERALD-CHAUFFEUR-P0
//
// Source-contract pins for DriverThemeVariant.lightEmerald wiring:
// enum/palette, pubspec asset folder, lossless WebP allowlist, driver home
// asset slots, and NL/EN/FR/ES selector copy. No PNG leftovers under
// Light Emerald Chauffeur in dart/pubspec/allowlist sources.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/driver_theme_palette.dart';

void main() {
  test('lightEmerald enum + light palette contract', () {
    expect(DriverThemeVariant.values, contains(DriverThemeVariant.lightEmerald));
    final palette = paletteForDriverTheme(DriverThemeVariant.lightEmerald);
    expect(palette.isDark, isFalse);
    expect(palette.accent, const Color(0xFF1F8A65));
    expect(palette.background, const Color(0xFFEEF5F2));
    expect(palette.textPrimary, const Color(0xFF143028));
  });

  test('pubspec declares Light Emerald Chauffeur assets folder', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(pubspec, contains('assets/Light Emerald Chauffeur/'));
  });

  test('allowlist contains all 8 Light Emerald chauffeur WebPs', () {
    const expected = <String>[
      'assets/Light Emerald Chauffeur/driver_documents_light_emerald.webp',
      'assets/Light Emerald Chauffeur/driver_fare_calculator_light_emerald.webp',
      'assets/Light Emerald Chauffeur/driver_history_light_emerald.webp',
      'assets/Light Emerald Chauffeur/driver_home_header_light_emerald.webp',
      'assets/Light Emerald Chauffeur/driver_my_rides_light_emerald.webp',
      'assets/Light Emerald Chauffeur/driver_navigation_light_emerald.webp',
      'assets/Light Emerald Chauffeur/driver_receipts_light_emerald.webp',
      'assets/Light Emerald Chauffeur/driver_street_ride_light_emerald.webp',
    ];
    final allowlist = File('test/assets/lossless_webp_allowlist.json');
    final paths =
        (jsonDecode(allowlist.readAsStringSync()) as List).cast<String>();
    for (final path in expected) {
      expect(paths, contains(path), reason: path);
    }
  });

  test('driver_home_page_state wires lightEmeraldAsset + 8 asset paths', () {
    final source = File(
      'lib/main_parts/driver_home_page_state.dart',
    ).readAsStringSync();
    expect(source, contains('lightEmeraldAsset'));
    const expected = <String>[
      'assets/Light Emerald Chauffeur/driver_home_header_light_emerald.webp',
      'assets/Light Emerald Chauffeur/driver_navigation_light_emerald.webp',
      'assets/Light Emerald Chauffeur/driver_street_ride_light_emerald.webp',
      'assets/Light Emerald Chauffeur/driver_fare_calculator_light_emerald.webp',
      'assets/Light Emerald Chauffeur/driver_my_rides_light_emerald.webp',
      'assets/Light Emerald Chauffeur/driver_history_light_emerald.webp',
      'assets/Light Emerald Chauffeur/driver_receipts_light_emerald.webp',
      'assets/Light Emerald Chauffeur/driver_documents_light_emerald.webp',
    ];
    for (final path in expected) {
      expect(source, contains(path), reason: path);
    }
  });

  test('theme selector labels/subtitles include Light Emerald NL/EN/FR/ES', () {
    final source = File(
      'lib/main_parts/driver_home_page_state.dart',
    ).readAsStringSync();
    final start = source.indexOf(
      'Future<void> _showDriverAppThemeSelectorSheet()',
    );
    expect(start, greaterThanOrEqualTo(0));
    final end = source.indexOf('\n  Widget _driverLanguagePill()', start);
    expect(end, greaterThan(start));
    final region = source.substring(start, end);

    expect(region, contains("nl: 'Light Emerald'"));
    expect(region, contains("en: 'Light Emerald'"));
    expect(region, contains("fr: 'Light Emerald'"));
    expect(region, contains("es: 'Light Emerald'"));
    expect(region, contains("nl: 'Licht mint met smaragdgroene accenten'"));
    expect(region, contains("en: 'Light mint with emerald accents'"));
    expect(region, contains("fr: 'Menthe claire avec accents emeraude'"));
    expect(region, contains("es: 'Menta clara con acentos esmeralda'"));
  });

  test('no Light Emerald Chauffeur PNG refs in dart/pubspec/allowlist', () {
    final selfPath = File(
      'test/driver_theme/light_emerald_chauffeur_p0_test.dart',
    ).absolute.path;
    final files = <File>[
      File('pubspec.yaml'),
      File('test/assets/lossless_webp_allowlist.json'),
      ...Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart')),
      ...Directory('test')
          .listSync(recursive: true)
          .whereType<File>()
          .where(
            (f) =>
                (f.path.endsWith('.dart') || f.path.endsWith('.json')) &&
                f.absolute.path != selfPath,
          ),
    ];
    // Avoid embedding the banned filename literal in this assertion source.
    final bannedSuffix = '.png';
    final pngPattern = RegExp(
      r'Light Emerald Chauffeur[\\/][^\n"]+' + bannedSuffix,
      caseSensitive: false,
    );
    for (final file in files) {
      final content = file.readAsStringSync();
      expect(
        pngPattern.hasMatch(content),
        isFalse,
        reason: 'PNG reference in ${file.path}',
      );
    }
  });
}
