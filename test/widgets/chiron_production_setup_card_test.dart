import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_config.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/widgets/chiron_production_setup_card.dart';

Widget _host(Widget child) {
  return MaterialApp(
    home: Scaffold(body: SingleChildScrollView(child: child)),
  );
}

BackendChironConnectionStatus _status({
  String testflowStatus = 'not_started',
  bool productionCredentialsStored = false,
  String productionLastConnectionStatus = 'never_tested',
  bool productionSubmitActive = false,
}) {
  return BackendChironConnectionStatus(
    ok: true,
    enabled: true,
    testflowStatus: testflowStatus,
    productionCredentialsStored: productionCredentialsStored,
    productionLastConnectionStatus: productionLastConnectionStatus,
    productionSubmitActive: productionSubmitActive,
  );
}

void main() {
  testWidgets('locked before 5/5: concrete reason, no fields, portal disabled', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        ChironProductionSetupCard(
          status: _status(testflowStatus: 'in_progress'),
          language: AppLanguage.nl,
          onSave: (_, __) async {},
          onTestConnection: () async {},
          onActivate: () async {},
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey('chiron_production_block_locked')),
      findsOneWidget,
    );
    expect(find.textContaining('Voltooi eerst de acceptatietest'), findsOneWidget);
    expect(find.text('Productie Client ID'), findsNothing);
    expect(find.text('Productiegegevens opslaan'), findsNothing);
  });

  testWidgets('unlocked at 5/5: portal + fields + actions; activate gated', (
    tester,
  ) async {
    var saveCalls = 0;
    var testCalls = 0;
    var activateCalls = 0;

    await tester.pumpWidget(
      _host(
        ChironProductionSetupCard(
          status: _status(testflowStatus: 'complete'),
          language: AppLanguage.nl,
          onSave: (_, __) async {
            saveCalls += 1;
          },
          onTestConnection: () async {
            testCalls += 1;
          },
          onActivate: () async {
            activateCalls += 1;
          },
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey('chiron_production_block_unlocked')),
      findsOneWidget,
    );
    expect(find.text('Open Chiron-productieportaal'), findsOneWidget);
    expect(find.text('Productie Client ID'), findsOneWidget);
    expect(find.text('Productie Client Secret'), findsOneWidget);
    expect(find.text('Productiegegevens opslaan'), findsOneWidget);
    expect(find.text('Productieverbinding controleren'), findsOneWidget);
    expect(find.text('Productie activeren'), findsOneWidget);
    expect(find.textContaining('Voer eerst uw productiegegevens in'), findsOneWidget);

    await tester.tap(find.text('Productieverbinding controleren'));
    await tester.pump();
    expect(testCalls, 1);

    // Activate stays disabled until creds + OAuth passed.
    await tester.tap(find.text('Productie activeren'));
    await tester.pump();
    expect(activateCalls, 0);

    await tester.enterText(find.byType(TextField).first, 'prod-client');
    await tester.enterText(find.byType(TextField).at(1), 'prod-secret');
    await tester.tap(find.text('Productiegegevens opslaan'));
    await tester.pump();
    expect(saveCalls, 1);
  });

  testWidgets('double tap on save causes one request', (tester) async {
    var saveCalls = 0;
    await tester.pumpWidget(
      _host(
        ChironProductionSetupCard(
          status: _status(testflowStatus: 'complete'),
          language: AppLanguage.nl,
          onSave: (_, __) async {
            saveCalls += 1;
            await Future<void>.delayed(const Duration(milliseconds: 80));
          },
          onTestConnection: () async {},
          onActivate: () async {},
        ),
      ),
    );

    await tester.enterText(find.byType(TextField).first, 'prod-client');
    await tester.enterText(find.byType(TextField).at(1), 'prod-secret');
    await tester.tap(find.text('Productiegegevens opslaan'));
    await tester.tap(find.text('Productiegegevens opslaan'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    expect(saveCalls, 1);
  });

  testWidgets('activate enabled only when oauth passed', (tester) async {
    var activateCalls = 0;
    await tester.pumpWidget(
      _host(
        ChironProductionSetupCard(
          status: _status(
            testflowStatus: 'complete',
            productionCredentialsStored: true,
            productionLastConnectionStatus: 'test_passed',
          ),
          language: AppLanguage.nl,
          onSave: (_, __) async {},
          onTestConnection: () async {},
          onActivate: () async {
            activateCalls += 1;
          },
        ),
      ),
    );

    await tester.tap(find.text('Productie activeren'));
    await tester.pump();
    expect(activateCalls, 1);
  });
}
