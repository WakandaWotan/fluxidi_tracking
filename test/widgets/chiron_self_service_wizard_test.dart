import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_config.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/chiron_company_connection_config.dart';
import 'package:fluxidi_tracking/widgets/chiron_friendly_diagnose_sheet.dart';
import 'package:fluxidi_tracking/widgets/chiron_self_service_wizard.dart';

void main() {
  testWidgets('wizard shows compact 3 steps and no 8-step wall', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChironSelfServiceWizard(
            status: const BackendChironConnectionStatus(
              ok: true,
              enabled: true,
              testCredentialsStored: true,
              lastConnectionStatus: 'test_passed',
              accTestSubmitActive: true,
              effectiveChironEnvironment: ChironConnectionEnvironment.test,
            ),
            language: AppLanguage.nl,
            textPrimary: Colors.black,
            textSecondary: Colors.black54,
            panelColor: Colors.white,
            borderColor: Colors.black12,
            accentColor: Colors.amber,
          ),
        ),
      ),
    );

    expect(find.text('Chiron instellen'), findsOneWidget);
    expect(find.text('Testverbinding'), findsOneWidget);
    expect(find.text('Acceptatietest'), findsOneWidget);
    expect(find.text('Productieverbinding'), findsOneWidget);
    expect(find.text('Open Chiron-testportaal'), findsOneWidget);
    expect(
      find.textContaining('Registreer uw bedrijf in de Chiron-testomgeving'),
      findsNothing,
    );
  });

  testWidgets('wizard includes DE strings', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChironSelfServiceWizard(
            status: null,
            language: AppLanguage.de,
            textPrimary: Colors.black,
            textSecondary: Colors.black54,
            panelColor: Colors.white,
            borderColor: Colors.black12,
            accentColor: Colors.amber,
          ),
        ),
      ),
    );
    expect(find.text('Chiron einrichten'), findsOneWidget);
    expect(find.text('Testverbindung'), findsOneWidget);
  });

  testWidgets('diagnose sheet opens with friendly lines and no secrets', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChironFriendlyDiagnoseSheet(
            language: AppLanguage.nl,
            status: const BackendChironConnectionStatus(
              ok: true,
              enabled: true,
              testCredentialsStored: true,
              lastConnectionStatus: 'test_passed',
              accTestSubmitActive: true,
            ),
            panelColor: Colors.white,
            cardColor: Colors.grey.shade100,
            borderColor: Colors.black12,
            textPrimary: Colors.black,
            textSecondary: Colors.black54,
            onOpenAdvanced: () {},
          ),
        ),
      ),
    );
    expect(find.text('Diagnose'), findsOneWidget);
    expect(find.text('ACC-testinzending'), findsOneWidget);
    expect(find.textContaining('client_secret'), findsNothing);
    expect(find.textContaining('Bearer '), findsNothing);
  });

  test('honest setup status never Complete for ACC-only', () {
    final label = chironHonestSetupStatusLabel(
      status: const BackendChironConnectionStatus(
        ok: true,
        enabled: true,
        testCredentialsStored: true,
        lastConnectionStatus: 'test_passed',
        testflowStatus: 'complete',
      ),
      language: AppLanguage.nl,
      enabled: true,
    );
    expect(label, 'Productie instellen');
    expect(label.toLowerCase().contains('compleet'), isFalse);
  });

  test('official portal URLs are correct', () {
    expect(
      kChironTestPortalUrl,
      'https://chiron-acc.vlaanderen.be/chiron/registratie/toegang',
    );
    expect(
      kChironProductionPortalUrl,
      'https://chiron.vlaanderen.be/chiron/registratie/toegang',
    );
  });
}
