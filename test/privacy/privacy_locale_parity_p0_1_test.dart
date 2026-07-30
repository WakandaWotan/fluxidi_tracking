// PRIVACY-LOCALE-PARITY-P0-1
//
// The Privacy & account UI must bind to Fluxidi's own `appLanguageNotifier`
// (the single source of truth used everywhere else in the shell), so an NL
// app renders in NL on any device system locale. Previously it read
// `Localizations.maybeLocaleOf(context)` and defaulted to English on many
// phones despite NL being selected in the app.
//
// Run:
//   flutter test test/privacy/privacy_locale_parity_p0_1_test.dart

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fluxidi_tracking/app_config.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/privacy/fluxidi_privacy_account.dart';
import 'package:fluxidi_tracking/privacy/fluxidi_privacy_ui.dart';

Widget _host(Widget child, {Locale? systemLocale}) {
  return MaterialApp(
    // Force an EN system locale so the fix is proven to override the device
    // locale with the Fluxidi-selected language.
    locale: systemLocale ?? const Locale('en', 'US'),
    supportedLocales: const [
      Locale('en', 'US'),
      Locale('nl', 'NL'),
      Locale('fr', 'FR'),
      Locale('es', 'ES'),
    ],
    home: child,
  );
}

Future<void> _openBusinessAsAdmin(WidgetTester tester,
    {Locale? systemLocale}) async {
  await tester.pumpWidget(
    _host(
      const FluxidiPrivacyAccountPage(
        audience: FluxidiPrivacyAudience.business,
        isCompanyOwnerOrAdmin: true,
      ),
      systemLocale: systemLocale,
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _openDeletionDialog(WidgetTester tester) async {
  final deleteTile = find.byIcon(Icons.delete_outline);
  expect(deleteTile, findsOneWidget);
  await tester.tap(deleteTile);
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    setAppLanguage(AppLanguage.nl);
  });
  tearDown(() {
    setAppLanguage(AppLanguage.en);
  });

  group('PRIVACY-LOCALE-PARITY-P0-1 wiring proof', () {
    test('privacy UI source imports app_config and reads appLanguageNotifier',
        () {
      final source = File('lib/privacy/fluxidi_privacy_ui.dart')
          .readAsStringSync();
      expect(source.contains("import '../app_config.dart';"), isTrue);
      expect(source.contains('appLanguageNotifier'), isTrue);
      expect(source.contains('currentLanguageCode'), isTrue);
      // Must NOT depend on Flutter's Localizations widget locale anymore.
      expect(
        source.contains('Localizations.maybeLocaleOf'),
        isFalse,
        reason: 'Privacy UI must not read the device Localizations locale.',
      );
    });

    test('currentLanguageCode reflects appLanguageNotifier', () {
      setAppLanguage(AppLanguage.nl);
      expect(currentLanguageCode, 'nl');
      setAppLanguage(AppLanguage.en);
      expect(currentLanguageCode, 'en');
      setAppLanguage(AppLanguage.fr);
      expect(currentLanguageCode, 'fr');
      setAppLanguage(AppLanguage.es);
      expect(currentLanguageCode, 'es');
    });
  });

  group('PRIVACY-LOCALE-PARITY-P0-1 page renders in Fluxidi-selected language',
      () {
    testWidgets('NL renders in Dutch even on an EN device', (tester) async {
      setAppLanguage(AppLanguage.nl);
      await _openBusinessAsAdmin(tester);

      // Title and every action label must be NL, not EN.
      expect(find.text('Privacy & account'), findsOneWidget);
      expect(find.text('Privacybeleid openen'), findsOneWidget);
      expect(find.text('Inzage of correctie aanvragen'), findsOneWidget);
      expect(
        find.text('Verwijdering bedrijfsaccount aanvragen'),
        findsOneWidget,
      );
      expect(find.text('Terugval: info@fluxidi.com'), findsOneWidget);

      // Regression guard: no English fallback strings must appear.
      expect(find.text('Open privacy policy'), findsNothing);
      expect(find.text('Request access or correction'), findsNothing);
      expect(find.text('Request business account deletion'), findsNothing);
    });

    testWidgets('EN renders in English', (tester) async {
      setAppLanguage(AppLanguage.en);
      await _openBusinessAsAdmin(tester);

      expect(find.text('Privacy & account'), findsOneWidget);
      expect(find.text('Open privacy policy'), findsOneWidget);
      expect(find.text('Request access or correction'), findsOneWidget);
      expect(find.text('Request business account deletion'), findsOneWidget);
      expect(find.text('Fallback: info@fluxidi.com'), findsOneWidget);

      expect(find.text('Privacybeleid openen'), findsNothing);
    });

    testWidgets('FR renders in French', (tester) async {
      setAppLanguage(AppLanguage.fr);
      await _openBusinessAsAdmin(tester);

      expect(find.text('Confidentialité & compte'), findsOneWidget);
      expect(
        find.text('Ouvrir la politique de confidentialité'),
        findsOneWidget,
      );
      expect(
        find.text('Demander l’accès ou la rectification'),
        findsOneWidget,
      );
      expect(
        find.text('Demander la suppression du compte d’entreprise'),
        findsOneWidget,
      );
      expect(
        find.text('Solution de secours : info@fluxidi.com'),
        findsOneWidget,
      );

      expect(find.text('Open privacy policy'), findsNothing);
    });

    testWidgets('ES renders in Spanish', (tester) async {
      setAppLanguage(AppLanguage.es);
      await _openBusinessAsAdmin(tester);

      expect(find.text('Privacidad y cuenta'), findsOneWidget);
      expect(find.text('Abrir la política de privacidad'), findsOneWidget);
      expect(find.text('Solicitar acceso o rectificación'), findsOneWidget);
      expect(
        find.text('Solicitar la eliminación de la cuenta de empresa'),
        findsOneWidget,
      );
      expect(find.text('Alternativa: info@fluxidi.com'), findsOneWidget);

      expect(find.text('Open privacy policy'), findsNothing);
    });
  });

  group('PRIVACY-LOCALE-PARITY-P0-1 confirmation dialog is localized', () {
    testWidgets('NL dialog title, buttons and copy are Dutch', (tester) async {
      setAppLanguage(AppLanguage.nl);
      await _openBusinessAsAdmin(tester);
      await _openDeletionDialog(tester);

      expect(find.text('Verwijderingsverzoek bevestigen'), findsOneWidget);
      expect(find.text('Annuleren'), findsOneWidget);
      expect(find.text('Doorgaan'), findsOneWidget);
      expect(
        find.textContaining('U wordt doorgestuurd naar de openbare'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Uitloggen'),
        findsOneWidget,
        reason: 'NL retention explanation must be shown',
      );

      // Regression guard for the reported bug.
      expect(find.text('Confirm deletion request'), findsNothing);
      expect(find.text('Cancel'), findsNothing);
      expect(find.text('Continue'), findsNothing);
    });

    testWidgets('EN dialog title and buttons are English', (tester) async {
      setAppLanguage(AppLanguage.en);
      await _openBusinessAsAdmin(tester);
      await _openDeletionDialog(tester);

      expect(find.text('Confirm deletion request'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Continue'), findsOneWidget);
    });

    testWidgets('FR dialog title and buttons are French', (tester) async {
      setAppLanguage(AppLanguage.fr);
      await _openBusinessAsAdmin(tester);
      await _openDeletionDialog(tester);

      expect(find.text('Confirmer la demande de suppression'), findsOneWidget);
      expect(find.text('Annuler'), findsOneWidget);
      expect(find.text('Continuer'), findsOneWidget);
    });

    testWidgets('ES dialog title and buttons are Spanish', (tester) async {
      setAppLanguage(AppLanguage.es);
      await _openBusinessAsAdmin(tester);
      await _openDeletionDialog(tester);

      expect(
        find.text('Confirmar la solicitud de eliminación'),
        findsOneWidget,
      );
      expect(find.text('Cancelar'), findsOneWidget);
      expect(find.text('Continuar'), findsOneWidget);
    });
  });

  group('PRIVACY-LOCALE-PARITY-P0-1 live language switch', () {
    testWidgets('switching Fluxidi language re-renders the open page',
        (tester) async {
      setAppLanguage(AppLanguage.nl);
      await _openBusinessAsAdmin(tester);
      expect(find.text('Privacybeleid openen'), findsOneWidget);

      setAppLanguage(AppLanguage.fr);
      await tester.pumpAndSettle();
      expect(
        find.text('Ouvrir la politique de confidentialité'),
        findsOneWidget,
      );
      expect(find.text('Privacybeleid openen'), findsNothing);
    });
  });
}
