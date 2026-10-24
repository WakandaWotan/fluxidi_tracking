// PRIVACY-CUSTOMER-WIRING-AUDIT-P0-1
//
// Verifies the CUSTOMER Privacy & account flow end-to-end against the
// contract:
//   * an entry point exists in the customer profile grid ("Mijn gegevens
//     & privacy");
//   * the page opens with audience = customer;
//   * the customer sees policy / access-correction / personal deletion /
//     fallback email;
//   * the customer never sees business-account deletion or owner/admin
//     copy;
//   * confirmation dialog identifies the request as a customer request;
//   * the canonical deletion URL keeps only the bounded `audience`
//     parameter;
//   * NL/EN/FR/ES follow the Fluxidi in-app language even when the device
//     Localizations locale is EN.
//
// Run:
//   flutter test test/privacy/privacy_customer_wiring_audit_p0_1_test.dart

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fluxidi_tracking/app_config.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/privacy/fluxidi_legal_urls.dart';
import 'package:fluxidi_tracking/privacy/fluxidi_privacy_account.dart';
import 'package:fluxidi_tracking/privacy/fluxidi_privacy_ui.dart';

Widget _host(Widget child) {
  // Force an EN system locale so language parity is proven to come from
  // the Fluxidi app-language notifier, not from Flutter's Localizations.
  return MaterialApp(
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

Future<void> _openCustomer(WidgetTester tester) async {
  await tester.pumpWidget(
    _host(
      const FluxidiPrivacyAccountPage(
        audience: FluxidiPrivacyAudience.customer,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    setAppLanguage(AppLanguage.nl);
  });
  tearDown(() {
    setAppLanguage(AppLanguage.en);
  });

  group('PRIVACY-CUSTOMER-WIRING-AUDIT-P0-1 entry point', () {
    test('customer_home_page.dart wires the customer privacy card to '
        'audience = customer', () {
      final source = File('lib/main_parts/customer_home_page.dart')
          .readAsStringSync();
      // PRIVACY-LOCALE-THEME-EMAIL-AND-CUSTOMER-WIDE-TILE-P0-4:
      // The entry moved out of the half-width grid tile into a full-width
      // "Mijn gegevens & account verwijderen" card below the grid.
      expect(source.contains('Mijn gegevens & account verwijderen'), isTrue);
      expect(source.contains('My data & delete account'), isTrue);
      expect(
        source.contains('Mes données & supprimer le compte'),
        isTrue,
      );
      expect(source.contains('Mis datos y eliminar la cuenta'), isTrue);
      expect(source.contains('openFluxidiPrivacyAccountPage'), isTrue);
      expect(source.contains('FluxidiPrivacyAudience.customer'), isTrue);
      // Owner/admin flag must never be raised on the customer surface.
      final customerTileIdx =
          source.indexOf('FluxidiPrivacyAudience.customer');
      final surroundingWindow =
          source.substring(customerTileIdx, customerTileIdx + 400);
      expect(surroundingWindow.contains('isCompanyOwnerOrAdmin'), isFalse,
          reason: 'Customer entry must not pass owner/admin authority.');
      expect(surroundingWindow.contains('sessionDriverId'), isFalse,
          reason: 'Customer entry must not pass a sessionDriverId.');
    });
  });

  group('PRIVACY-CUSTOMER-WIRING-AUDIT-P0-1 page content (customer)', () {
    testWidgets('NL customer sees personal deletion, never business copy',
        (tester) async {
      setAppLanguage(AppLanguage.nl);
      await _openCustomer(tester);

      // Title + labels in NL.
      expect(find.text('Mijn gegevens & privacy'), findsOneWidget);
      expect(find.text('Privacybeleid openen'), findsOneWidget);
      expect(find.text('Inzage of correctie aanvragen'), findsOneWidget);
      expect(
        find.text('Verwijdering account en gegevens aanvragen'),
        findsOneWidget,
      );
      expect(find.text('Terugval: info@fluxidi.com'), findsOneWidget);

      // Business-specific copy must be absent for the customer surface.
      const forbidden = <String>[
        'Verwijdering bedrijfsaccount aanvragen',
        'Request business account deletion',
        'Demander la suppression du compte d’entreprise',
        'Solicitar la eliminación de la cuenta de empresa',
        'Alleen de geverifieerde bedrijfseigenaar/admin kan een bedrijfsverwijdering starten.',
        'Only a verified company owner/admin may start a business deletion request.',
        'Seul un propriétaire/admin d’entreprise vérifié peut démarrer une suppression.',
        'Solo un propietario/admin verificado puede iniciar la eliminación empresarial.',
        'Privacy & account',
      ];
      for (final label in forbidden) {
        expect(
          find.text(label),
          findsNothing,
          reason: 'Customer surface must not render "$label"',
        );
      }
    });

    testWidgets('EN customer parity (forced EN system locale)',
        (tester) async {
      setAppLanguage(AppLanguage.en);
      await _openCustomer(tester);

      expect(find.text('My data & privacy'), findsOneWidget);
      expect(find.text('Open privacy policy'), findsOneWidget);
      expect(find.text('Request access or correction'), findsOneWidget);
      expect(find.text('Request account and data deletion'), findsOneWidget);
      expect(find.text('Fallback: info@fluxidi.com'), findsOneWidget);
      expect(find.text('Request business account deletion'), findsNothing);
    });

    testWidgets('FR customer parity', (tester) async {
      setAppLanguage(AppLanguage.fr);
      await _openCustomer(tester);

      expect(find.text('Mes données & confidentialité'), findsOneWidget);
      expect(
        find.text('Ouvrir la politique de confidentialité'),
        findsOneWidget,
      );
      expect(
        find.text('Demander l’accès ou la rectification'),
        findsOneWidget,
      );
      expect(
        find.text('Demander la suppression du compte et des données'),
        findsOneWidget,
      );
      expect(
        find.text('Solution de secours : info@fluxidi.com'),
        findsOneWidget,
      );
      expect(
        find.text('Demander la suppression du compte d’entreprise'),
        findsNothing,
      );
    });

    testWidgets('ES customer parity', (tester) async {
      setAppLanguage(AppLanguage.es);
      await _openCustomer(tester);

      expect(find.text('Mis datos y privacidad'), findsOneWidget);
      expect(find.text('Abrir la política de privacidad'), findsOneWidget);
      expect(find.text('Solicitar acceso o rectificación'), findsOneWidget);
      expect(
        find.text('Solicitar la eliminación de la cuenta y los datos'),
        findsOneWidget,
      );
      expect(find.text('Alternativa: info@fluxidi.com'), findsOneWidget);
      expect(
        find.text('Solicitar la eliminación de la cuenta de empresa'),
        findsNothing,
      );
    });

    testWidgets('driver-only active-trip location block is hidden for customer',
        (tester) async {
      setAppLanguage(AppLanguage.nl);
      await _openCustomer(tester);
      // Driver-only section title / body must not appear on the customer page.
      expect(find.text('Locatie tijdens actieve ritten'), findsNothing);
      expect(find.text('Location during active trips'), findsNothing);
    });
  });

  group('PRIVACY-CUSTOMER-WIRING-AUDIT-P0-1 confirmation dialog (customer)',
      () {
    testWidgets('NL dialog identifies request as customer, no owner/admin copy',
        (tester) async {
      setAppLanguage(AppLanguage.nl);
      await _openCustomer(tester);

      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pumpAndSettle();

      expect(find.text('Verwijderingsverzoek bevestigen'), findsOneWidget);
      // PRIVACY-LOCALE-THEME-EMAIL-AND-CUSTOMER-WIDE-TILE-P0-4:
      // The dialog now surfaces the audience with a localized display label,
      // never the machine keyword. NL customer → "klant".
      expect(
        find.textContaining('Dit verzoek betreft: klant'),
        findsOneWidget,
      );
      expect(find.text('Annuleren'), findsOneWidget);
      expect(find.text('Doorgaan'), findsOneWidget);

      // Retention text is generic (audit note): it must not present the
      // customer with company-specific language such as "bedrijfsaccount" or
      // "owner/admin" in the dialog body.
      const forbiddenInDialog = <String>[
        'bedrijfsaccount',
        'owner/admin',
        'company owner',
        'entreprise',
      ];
      for (final needle in forbiddenInDialog) {
        expect(
          find.textContaining(needle, findRichText: true),
          findsNothing,
          reason:
              'Customer confirmation dialog must not surface "$needle" copy',
        );
      }
    });

    testWidgets('FR dialog identifies request as customer',
        (tester) async {
      setAppLanguage(AppLanguage.fr);
      await _openCustomer(tester);

      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pumpAndSettle();

      expect(
        find.text('Confirmer la demande de suppression'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Cette demande concerne : le client'),
        findsOneWidget,
      );
      expect(find.text('Annuler'), findsOneWidget);
      expect(find.text('Continuer'), findsOneWidget);
    });
  });

  group('PRIVACY-CUSTOMER-WIRING-AUDIT-P0-1 canonical deletion URL', () {
    test('customer deletion URI is the canonical Shopify page with only '
        'the bounded audience parameter', () {
      final uri = buildFluxidiAccountDeletionRequestUri(
        audience: FluxidiPrivacyAudience.customer,
      );
      expect(
        uri.toString(),
        'https://fluxidi.com/pages/account-en-gegevens-verwijderen?audience=customer',
      );
      expect(uri.queryParameters.keys.toSet(), <String>{'audience'});
      expect(uri.queryParameters['audience'], 'customer');
      expect(isSafeFluxidiAccountDeletionUri(uri), isTrue);
      expect(kFluxidiAccountDeletionUrl,
          'https://fluxidi.com/pages/account-en-gegevens-verwijderen');
    });
  });

  group('PRIVACY-CUSTOMER-WIRING-AUDIT-P0-1 live language switch (customer)',
      () {
    testWidgets('changing Fluxidi language re-renders the open customer page',
        (tester) async {
      setAppLanguage(AppLanguage.nl);
      await _openCustomer(tester);
      expect(find.text('Mijn gegevens & privacy'), findsOneWidget);

      setAppLanguage(AppLanguage.fr);
      await tester.pumpAndSettle();
      expect(find.text('Mes données & confidentialité'), findsOneWidget);
      expect(find.text('Mijn gegevens & privacy'), findsNothing);
    });
  });
}
