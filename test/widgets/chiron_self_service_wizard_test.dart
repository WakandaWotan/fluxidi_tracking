import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_config.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/chiron_company_connection_config.dart';
import 'package:fluxidi_tracking/widgets/chiron_acceptance_step_card.dart';
import 'package:fluxidi_tracking/widgets/chiron_friendly_diagnose_sheet.dart';
import 'package:fluxidi_tracking/widgets/chiron_production_setup_card.dart';
import 'package:fluxidi_tracking/widgets/chiron_self_service_wizard.dart';
import 'package:fluxidi_tracking/widgets/chiron_test_setup_card.dart';

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

  testWidgets('full three-step cards: fields, portals, blocking reason', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: Column(
              children: [
                ChironTestSetupCard(
                  status: const BackendChironConnectionStatus(
                    ok: true,
                    enabled: true,
                  ),
                  language: AppLanguage.nl,
                  onSave: (_, __) async {},
                  onTestConnection: () async {},
                  onClear: () async {},
                ),
                ChironAcceptanceStepCard(
                  status: const BackendChironConnectionStatus(
                    ok: true,
                    enabled: true,
                    testflowStatus: 'complete',
                    testDepartureSentCount: 5,
                    testArrivalSentCount: 5,
                    testRidesCompletedCount: 5,
                    testMessagesSentCount: 10,
                  ),
                  language: AppLanguage.nl,
                  onReset: () {},
                ),
                ChironProductionSetupCard(
                  status: const BackendChironConnectionStatus(
                    ok: true,
                    enabled: true,
                    testflowStatus: 'in_progress',
                  ),
                  language: AppLanguage.nl,
                  onSave: (_, __) async {},
                  onTestConnection: () async {},
                  onActivate: () async {},
                ),
              ],
            ),
          ),
        ),
      ),
    );

    expect(find.text('Test Client ID'), findsOneWidget);
    expect(find.text('Test Client Secret'), findsOneWidget);
    expect(find.text('Open Chiron-testportaal'), findsOneWidget);
    expect(find.textContaining('Acceptatietest geslaagd'), findsOneWidget);
    expect(
      find.textContaining('blijft uw ritten naar de Chiron-testomgeving'),
      findsOneWidget,
    );
    expect(find.textContaining('Voltooi eerst de acceptatietest'), findsOneWidget);
    expect(find.text('Productie Client ID'), findsNothing);
  });

  for (final lang in AppLanguage.values) {
    testWidgets('five-language surface includes ${lang.name}', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChironSelfServiceWizard(
              status: null,
              language: lang,
              textPrimary: Colors.black,
              textSecondary: Colors.black54,
              panelColor: Colors.white,
              borderColor: Colors.black12,
              accentColor: Colors.amber,
            ),
          ),
        ),
      );
      expect(find.byKey(const ValueKey('chiron_self_service_wizard')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('diagnose opens immediately; refresh error stays in open panel', (
    tester,
  ) async {
    var refreshCalls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChironFriendlyDiagnoseSheet(
            language: AppLanguage.nl,
            initialStatus: const BackendChironConnectionStatus(
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
            refreshStatus: () async {
              refreshCalls += 1;
              await Future<void>.delayed(const Duration(milliseconds: 40));
              throw const BackendChironConnectionApiException(
                error: 'network_error',
                statusCode: 503,
              );
            },
          ),
        ),
      ),
    );

    // Panel content visible before refresh completes.
    expect(find.text('Diagnose'), findsOneWidget);
    expect(find.text('ACC-testinzending'), findsOneWidget);
    await tester.pump();
    expect(find.textContaining('Diagnose wordt uitgevoerd'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byKey(const ValueKey('chiron_diagnose_error')), findsOneWidget);
    expect(find.text('Diagnose'), findsOneWidget);
    expect(find.textContaining('client_secret'), findsNothing);
    expect(find.textContaining('Bearer '), findsNothing);
    expect(refreshCalls, 1);
  });

  testWidgets('diagnose refresh runs once on open (no double request)', (
    tester,
  ) async {
    var refreshCalls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChironFriendlyDiagnoseSheet(
            language: AppLanguage.nl,
            initialStatus: const BackendChironConnectionStatus(ok: true),
            panelColor: Colors.white,
            cardColor: Colors.white,
            borderColor: Colors.black12,
            textPrimary: Colors.black,
            textSecondary: Colors.black54,
            onOpenAdvanced: () {},
            refreshStatus: () async {
              refreshCalls += 1;
              await Future<void>.delayed(const Duration(milliseconds: 80));
              return const BackendChironConnectionStatus(
                ok: true,
                enabled: true,
                testCredentialsStored: true,
              );
            },
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.byKey(const ValueKey('chiron_friendly_diagnose_sheet')), findsOneWidget);
    expect(refreshCalls, 1);
    await tester.pump(const Duration(milliseconds: 100));
    expect(refreshCalls, 1);
  });

  testWidgets('phone layout: no overflow at 390x844', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ChironSelfServiceWizard(
              status: null,
              language: AppLanguage.nl,
              textPrimary: Colors.black,
              textSecondary: Colors.black54,
              panelColor: Colors.white,
              borderColor: Colors.black12,
              accentColor: Colors.amber,
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('tablet layout: no overflow at 1024x768', (tester) async {
    tester.view.physicalSize = const Size(1024, 768);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChironSelfServiceWizard(
            status: null,
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
    expect(tester.takeException(), isNull);
  });

  testWidgets('large text scaling remains usable', (tester) async {
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(1.6)),
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ChironAcceptanceStepCard(
                status: const BackendChironConnectionStatus(
                  ok: true,
                  testflowStatus: 'complete',
                  testMessagesSentCount: 10,
                  testDepartureSentCount: 5,
                  testArrivalSentCount: 5,
                  testRidesCompletedCount: 5,
                ),
                language: AppLanguage.nl,
                onReset: () {},
              ),
            ),
          ),
        ),
      ),
    );
    expect(find.textContaining('Acceptatietest geslaagd'), findsOneWidget);
    expect(tester.takeException(), isNull);
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
