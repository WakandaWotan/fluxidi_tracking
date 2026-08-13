// LIGHT-EMERALD-CHAUFFEUR-P0
//
// Source-contract pins for DriverThemeVariant.lightEmerald wiring:
// enum/palette, pubspec asset folder, lossless WebP allowlist, driver home
// asset slots, NL/EN/FR/ES selector copy, and COMPLETE DASHBOARD THEME POLISH
// P0 surface/nav/KPI/hero contracts. No PNG leftovers under Light Emerald
// Chauffeur in dart/pubspec/allowlist sources.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/driver_theme_palette.dart';

String _normalizeNewlines(String source) => source.replaceAll('\r\n', '\n');

String _driverHomeSource() => _normalizeNewlines(
  File('lib/main_parts/driver_home_page_state.dart').readAsStringSync(),
);

String _shellSource() => _normalizeNewlines(
  File('lib/main_parts/fluxidi_shell_widgets.dart').readAsStringSync(),
);

/// Extract `_buildPremiumDriverDashboard` body for LE polish contracts.
String _premiumDashboardRegion(String source) {
  final start = source.indexOf('Widget _buildPremiumDriverDashboard()');
  expect(start, greaterThanOrEqualTo(0));
  final end = source.indexOf(
    'Widget _buildStandaloneOperationalBlockPanel(',
    start,
  );
  expect(end, greaterThan(start));
  return source.substring(start, end);
}

String _summaryCardsRegion(String source) {
  final start = source.indexOf('Widget _buildDriverSummaryCards({');
  expect(start, greaterThanOrEqualTo(0));
  final end = source.indexOf('Widget _buildNextRideHeroCard({', start);
  expect(end, greaterThan(start));
  return source.substring(start, end);
}

String _nextRideRegion(String source) {
  final start = source.indexOf('Widget _buildNextRideHeroCard({');
  expect(start, greaterThanOrEqualTo(0));
  final end = source.indexOf('Widget _buildDriverQuickActionsGrid({', start);
  expect(end, greaterThan(start));
  return source.substring(start, end);
}

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
    final source = _driverHomeSource();
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
    final source = _driverHomeSource();
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

  group('COMPLETE DASHBOARD THEME POLISH P0 source contracts', () {
    test('ColoredBox / scaffold / bottom nav use LE background helpers', () {
      final source = _driverHomeSource();
      final dash = _premiumDashboardRegion(source);

      expect(dash, contains('isLightEmerald'));
      expect(dash, contains('_lightEmeraldBackground()'));
      expect(dash, contains('_lightEmeraldSurfaceGradient(soft: true)'));
      expect(dash, contains('_lightEmeraldBorderColor(0.28)'));

      // Scaffold + under-dashboard cover gate LE mint background.
      expect(
        source,
        contains(
          'driverThemeNotifier.value == DriverThemeVariant.lightEmerald',
        ),
      );
      expect(source, contains('? _lightEmeraldBackground()'));
      expect(source, contains(': kFluxidiBlack'));
      expect(
        source,
        contains('_lightEmeraldBackground().withOpacity(0.985)'),
      );
      expect(source, contains('const Color(0xFF040404).withOpacity(0.985)'));
    });

    test('bottom nav LE branch precedes Night Gold 0xFF101113', () {
      final dash = _premiumDashboardRegion(_driverHomeSource());
      final bottomNavStart = dash.indexOf(
        "margin: const EdgeInsets.fromLTRB(10, 0, 10, 8)",
      );
      expect(bottomNavStart, greaterThanOrEqualTo(0));
      final bottomNav = dash.substring(bottomNavStart);
      final leNav = bottomNav.indexOf(
        'isLightEmerald\n'
        '                  ? Container(',
      );
      final nightNav = bottomNav.indexOf('color: const Color(0xFF101113)');
      expect(leNav, greaterThanOrEqualTo(0));
      expect(nightNav, greaterThan(leNav));
      expect(
        bottomNav.substring(leNav, nightNav),
        contains('_lightEmeraldSurfaceGradient(soft: true)'),
      );
      expect(dash, contains('_middayGoldMetallicGradient()'));
      expect(dash, contains('const Color(0xFF050505)'));
    });

    test('navItem LE decoration avoids gold metallic + gold wash', () {
      final dash = _premiumDashboardRegion(_driverHomeSource());
      expect(dash, contains('_lightEmeraldSelectedSurfaceGradient()'));
      expect(dash, contains('(isMiddayGold || isLightEmerald)'));
      expect(
        dash,
        contains(
          'decoration: (isMiddayGold || isLightEmerald)\n'
          '                    ? null',
        ),
      );
      // Night Gold active path retained after LE arm.
      expect(dash, contains('_middayGoldMetallicGradient()'));
    });

    test('Completed KPI LE path does not use 0xFF4C9BFF', () {
      final cards = _summaryCardsRegion(_driverHomeSource());
      final completedIdx = cards.indexOf("en: 'Completed'");
      expect(completedIdx, greaterThanOrEqualTo(0));
      // Accent for Completed is declared just above the label block.
      final accentWindow = cards.substring(
        cards.lastIndexOf('accentColor:', completedIdx - 180),
        completedIdx,
      );
      expect(accentWindow, contains('isLightEmerald'));
      expect(accentWindow, contains('? const Color(0xFF0F766E)'));
      // Non-LE fallthrough still keeps the prior blue completed accent.
      expect(accentWindow, contains(': const Color(0xFF4C9BFF)'));
      // LE true-arm itself must not select the blue token.
      final leArm = accentWindow.split(': const Color(0xFF4C9BFF)').first;
      expect(leArm, contains('0xFF0F766E'));
      expect(leArm, isNot(contains('0xFF4C9BFF')));
    });

    test('Hero LE scrim does not use black@0.56 as the LE path', () {
      final dash = _premiumDashboardRegion(_driverHomeSource());
      expect(dash, contains('0xFF0F3D2E'));
      expect(dash, contains('.withOpacity(0.34)'));
      // Non-LE tablet portrait still uses the classic black@0.56 path.
      expect(dash, contains('Colors.black.withOpacity(0.56)'));
      // LE branch must not assign black@0.56 inside its ternary arm.
      final leScrim = RegExp(
        r'colors: isLightEmerald\s*\?\s*\[[^\]]+\]',
        multiLine: true,
      );
      for (final match in leScrim.allMatches(dash)) {
        expect(match.group(0), isNot(contains('0.56')));
        expect(match.group(0), isNot(contains('Colors.black')));
      }
    });

    test('next-ride CTAs wire LE button styles; handlers preserved', () {
      final next = _nextRideRegion(_driverHomeSource());
      expect(next, contains('_lightEmeraldGhostButtonStyle()'));
      expect(next, contains('_lightEmeraldStartButtonStyle()'));
      expect(next, contains('_lightEmeraldSurfaceGradient()'));
      // Visibility / callback contracts unchanged.
      expect(next, contains('if (nextRide == null)'));
      expect(next, contains('_openDirectRideEntry'));
      expect(next, contains('_goToRide(nextRide)'));
      expect(next, contains('_openNavigation()'));
      expect(next, contains("_refreshBookings(force: true, trigger: 'list_manual')"));
    });

    test('FluxidiFrame LE fill uses light emerald background', () {
      final shell = _shellSource();
      expect(
        shell,
        contains('chauffeurShellTheme == DriverThemeVariant.lightEmerald'),
      );
      expect(
        shell,
        contains(
          'paletteForDriverTheme(\n'
          '                        DriverThemeVariant.lightEmerald,\n'
          '                      ).background',
        ),
      );
      // Other themes still keep black fills via frameFill fallback.
      expect(shell, contains('kFluxidiBlack'));
    });
  });
}
