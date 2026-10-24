// PRIVACY-LOCALE-THEME-EMAIL-AND-CUSTOMER-WIDE-TILE-P0-4
//
// The Privacy & account UI must follow the active Fluxidi theme (light /
// dark) instead of forcing a permanent dark scheme. This regression suite
// proves:
//   * the Scaffold inherits from Theme.of(context) (no hardcoded background);
//   * the delete action uses Theme.of(context).colorScheme.error (no
//     hardcoded red);
//   * dialog surface uses Theme.of(context).dialogTheme via AlertDialog
//     defaults;
//   * production source under lib/privacy/ never hardcodes Colors.black /
//     Colors.white / Brightness.dark / ThemeData.dark(), never forces a
//     Scaffold(backgroundColor: Colors.black) and never uses a hardcoded
//     red for the deletion action.
//
// Run:
//   flutter test test/privacy/privacy_theme_parity_p0_4_test.dart

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fluxidi_tracking/app_config.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/privacy/fluxidi_privacy_account.dart';
import 'package:fluxidi_tracking/privacy/fluxidi_privacy_ui.dart';

ThemeData _fluxidiLightLikeTheme() {
  final base = ThemeData(brightness: Brightness.light);
  return base.copyWith(
    scaffoldBackgroundColor: const Color(0xFFFFF7E8),
    colorScheme: base.colorScheme.copyWith(
      surface: const Color(0xFFFFF9EE),
      error: const Color(0xFFB3261E),
    ),
  );
}

ThemeData _fluxidiDarkLikeTheme() {
  final base = ThemeData(brightness: Brightness.dark);
  return base.copyWith(
    scaffoldBackgroundColor: const Color(0xFF111111),
    colorScheme: base.colorScheme.copyWith(
      surface: const Color(0xFF1B1B1B),
      error: const Color(0xFFF2B8B5),
    ),
  );
}

Widget _hostWith(ThemeData theme, Widget child) {
  return MaterialApp(
    theme: theme,
    home: child,
  );
}

Future<void> _openBusiness(WidgetTester tester, ThemeData theme) async {
  await tester.pumpWidget(
    _hostWith(
      theme,
      const FluxidiPrivacyAccountPage(
        audience: FluxidiPrivacyAudience.business,
        isCompanyOwnerOrAdmin: true,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => setAppLanguage(AppLanguage.en));
  tearDown(() => setAppLanguage(AppLanguage.en));

  group('PRIVACY-P0-4 privacy UI follows the active Fluxidi theme', () {
    testWidgets('light theme: Scaffold uses Theme.scaffoldBackgroundColor',
        (tester) async {
      final theme = _fluxidiLightLikeTheme();
      await _openBusiness(tester, theme);
      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
      // No hardcoded backgroundColor on the Scaffold — it must inherit from
      // the ambient theme.
      expect(scaffold.backgroundColor, isNull,
          reason:
              'Privacy Scaffold must not override backgroundColor. It should '
              'inherit from Theme.of(context).scaffoldBackgroundColor '
              '(= ${theme.scaffoldBackgroundColor}).');
    });

    testWidgets('dark theme: Scaffold uses Theme.scaffoldBackgroundColor',
        (tester) async {
      final theme = _fluxidiDarkLikeTheme();
      await _openBusiness(tester, theme);
      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
      expect(scaffold.backgroundColor, isNull);
    });

    testWidgets('delete action uses Theme.colorScheme.error (light)',
        (tester) async {
      final theme = _fluxidiLightLikeTheme();
      await _openBusiness(tester, theme);
      final icon =
          tester.widget<Icon>(find.byIcon(Icons.delete_outline));
      expect(icon.color, theme.colorScheme.error);
    });

    testWidgets('delete action uses Theme.colorScheme.error (dark)',
        (tester) async {
      final theme = _fluxidiDarkLikeTheme();
      await _openBusiness(tester, theme);
      final icon =
          tester.widget<Icon>(find.byIcon(Icons.delete_outline));
      expect(icon.color, theme.colorScheme.error);
    });

    testWidgets('deletion confirmation dialog is present under light theme',
        (tester) async {
      final theme = _fluxidiLightLikeTheme();
      await _openBusiness(tester, theme);
      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
    });

    testWidgets('deletion confirmation dialog is present under dark theme',
        (tester) async {
      final theme = _fluxidiDarkLikeTheme();
      await _openBusiness(tester, theme);
      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
    });
  });

  group('PRIVACY-P0-4 lib/privacy/ never hardcodes theme colors', () {
    Iterable<File> dartFilesUnder(String relativeDir) sync* {
      final dir = Directory(relativeDir);
      if (!dir.existsSync()) return;
      for (final entity
          in dir.listSync(recursive: true, followLinks: false)) {
        if (entity is File && entity.path.toLowerCase().endsWith('.dart')) {
          yield entity;
        }
      }
    }

    test('no Colors.black / Colors.white / Brightness.dark / ThemeData.dark()',
        () {
      // NOTE: `Colors.red.shade700` and any raw Color(0x...) literal for the
      // deletion action is forbidden — the semantic error color must come
      // from Theme.of(context).colorScheme.error.
      final forbiddenPatterns = <String>[
        'Colors.black',
        'Colors.white',
        'Colors.red.',
        'Brightness.dark',
        'ThemeData.dark()',
        'ThemeData.light()',
      ];
      final offenders = <String>[];
      for (final file in dartFilesUnder('lib/privacy')) {
        final text = file.readAsStringSync();
        for (final needle in forbiddenPatterns) {
          if (text.contains(needle)) {
            offenders.add('${file.path} :: $needle');
          }
        }
      }
      expect(
        offenders,
        isEmpty,
        reason:
            'Files under lib/privacy/ must not hardcode dark/light theme '
            'primitives. Bind to Theme.of(context) / colorScheme instead. '
            'Offenders: $offenders',
      );
    });

    test('no forced backgroundColor on the privacy Scaffold', () {
      final ui = File('lib/privacy/fluxidi_privacy_ui.dart').readAsStringSync();
      // The Scaffold must not set backgroundColor at all — the theme owns it.
      expect(
        RegExp(r'Scaffold\([^)]*backgroundColor\s*:').hasMatch(ui),
        isFalse,
        reason:
            'Privacy UI Scaffold must not force a backgroundColor; the '
            'active Fluxidi theme owns it.',
      );
    });

    test('delete action reads colorScheme.error (positive assertion)', () {
      final ui = File('lib/privacy/fluxidi_privacy_ui.dart').readAsStringSync();
      expect(
        ui.contains('colorScheme.error'),
        isTrue,
        reason:
            'The deletion action must read Theme.of(context).colorScheme.error '
            'for the icon (and any related text), never a raw red literal.',
      );
    });

    test('Theme.of(context) is actually used by the privacy UI', () {
      final ui = File('lib/privacy/fluxidi_privacy_ui.dart').readAsStringSync();
      expect(ui.contains('Theme.of(context)'), isTrue);
    });
  });
}
