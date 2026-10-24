// PRIVACY-LOCALE-THEME-EMAIL-AND-CUSTOMER-WIDE-TILE-P0-4
//
// Extended locale-parity coverage for the shared Privacy & account UI:
//   * driver surface renders in NL, FR, ES without losing its driver-only
//     active-trip location copy;
//   * live NL → FR switch re-renders an already-open page;
//   * live FR → ES switch re-renders an already-open confirmation dialog;
//   * no English fallback strings ever surface when FR/ES is selected.
//
// Run:
//   flutter test test/privacy/privacy_locale_parity_p0_4_test.dart

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fluxidi_tracking/app_config.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/privacy/fluxidi_privacy_account.dart';
import 'package:fluxidi_tracking/privacy/fluxidi_privacy_ui.dart';

Widget _host(Widget child) {
  return MaterialApp(
    // Force an EN system locale so the fix is proven to override the device
    // locale with the Fluxidi-selected language.
    locale: const Locale('en', 'US'),
    supportedLocales: const [
      Locale('en', 'US'),
      Locale('nl', 'NL'),
      Locale('fr', 'FR'),
      Locale('es', 'ES'),
    ],
    home: child,
  );
}

Future<void> _openDriver(WidgetTester tester) async {
  await tester.pumpWidget(
    _host(
      const FluxidiPrivacyAccountPage(
        audience: FluxidiPrivacyAudience.driver,
        sessionDriverId: 'D1',
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _openBusinessAdmin(WidgetTester tester) async {
  await tester.pumpWidget(
    _host(
      const FluxidiPrivacyAccountPage(
        audience: FluxidiPrivacyAudience.business,
        isCompanyOwnerOrAdmin: true,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => setAppLanguage(AppLanguage.nl));
  tearDown(() => setAppLanguage(AppLanguage.en));

  group('PRIVACY-P0-4 driver surface keeps driver-only copy across languages',
      () {
    testWidgets('NL driver shows driver active-trip location copy',
        (tester) async {
      setAppLanguage(AppLanguage.nl);
      await _openDriver(tester);
      // Driver page title, action labels, plus the driver-only block.
      expect(find.text('Mijn gegevens & privacy'), findsOneWidget);
      expect(find.text('Privacybeleid openen'), findsOneWidget);
      // Personal-driver deletion (never business copy).
      expect(
        find.text('Verwijdering account en gegevens aanvragen'),
        findsOneWidget,
      );
      expect(
        find.text('Verwijdering bedrijfsaccount aanvragen'),
        findsNothing,
      );
      // Driver-specific active-trip location block must be present in NL.
      expect(find.text('Locatie tijdens actieve ritten'), findsOneWidget);
    });

    testWidgets('FR driver shows French privacy + driver-only copy',
        (tester) async {
      setAppLanguage(AppLanguage.fr);
      await _openDriver(tester);
      expect(find.text('Mes données & confidentialité'), findsOneWidget);
      expect(
        find.text('Ouvrir la politique de confidentialité'),
        findsOneWidget,
      );
      expect(
        find.text('Demander la suppression du compte et des données'),
        findsOneWidget,
      );
      expect(
        find.text('Demander la suppression du compte d’entreprise'),
        findsNothing,
      );
      // Driver-specific active-trip location block must remain in FR.
      expect(
        find.text('Localisation pendant les courses actives'),
        findsOneWidget,
      );
    });

    testWidgets('ES driver shows Spanish privacy + driver-only copy',
        (tester) async {
      setAppLanguage(AppLanguage.es);
      await _openDriver(tester);
      expect(find.text('Mis datos y privacidad'), findsOneWidget);
      expect(find.text('Abrir la política de privacidad'), findsOneWidget);
      expect(
        find.text('Solicitar la eliminación de la cuenta y los datos'),
        findsOneWidget,
      );
      expect(
        find.text('Solicitar la eliminación de la cuenta de empresa'),
        findsNothing,
      );
      // Driver-specific active-trip location block must remain in ES.
      expect(
        find.text('Ubicación durante viajes activos'),
        findsOneWidget,
      );
    });
  });

  group('PRIVACY-P0-4 no English fallback under FR/ES on business surface',
      () {
    testWidgets('FR business page has no residual English strings',
        (tester) async {
      setAppLanguage(AppLanguage.fr);
      await _openBusinessAdmin(tester);
      const englishOnly = <String>[
        'Privacy & account',
        'Open privacy policy',
        'Request access or correction',
        'Request business account deletion',
        'Fallback: info@fluxidi.com',
      ];
      for (final label in englishOnly) {
        expect(find.text(label), findsNothing,
            reason: 'FR page must not surface English label "$label"');
      }
    });

    testWidgets('ES business page has no residual English strings',
        (tester) async {
      setAppLanguage(AppLanguage.es);
      await _openBusinessAdmin(tester);
      const englishOnly = <String>[
        'Privacy & account',
        'Open privacy policy',
        'Request access or correction',
        'Request business account deletion',
        'Fallback: info@fluxidi.com',
      ];
      for (final label in englishOnly) {
        expect(find.text(label), findsNothing,
            reason: 'ES page must not surface English label "$label"');
      }
    });
  });

  group('PRIVACY-P0-4 live language switch on an open page and dialog', () {
    testWidgets('NL → FR live switch re-renders the business page',
        (tester) async {
      setAppLanguage(AppLanguage.nl);
      await _openBusinessAdmin(tester);
      expect(find.text('Terugval: info@fluxidi.com'), findsOneWidget);

      setAppLanguage(AppLanguage.fr);
      await tester.pumpAndSettle();
      expect(
        find.text('Solution de secours : info@fluxidi.com'),
        findsOneWidget,
      );
      expect(find.text('Terugval: info@fluxidi.com'), findsNothing);
    });

    testWidgets('FR → ES live switch re-renders the open deletion dialog',
        (tester) async {
      setAppLanguage(AppLanguage.fr);
      await _openBusinessAdmin(tester);
      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pumpAndSettle();
      expect(find.text('Confirmer la demande de suppression'), findsOneWidget);

      setAppLanguage(AppLanguage.es);
      await tester.pumpAndSettle();
      expect(
        find.text('Confirmar la solicitud de eliminación'),
        findsOneWidget,
      );
      expect(
        find.text('Confirmer la demande de suppression'),
        findsNothing,
      );
    });
  });
}
