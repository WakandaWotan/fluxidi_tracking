// RELEASE-P0-CHIRON-STATE-MACHINE-2026-07-31
//
// Widget tests for the split Chiron environment status labels + gated
// production block. Locks the UI contract: three status lines
// (ACC-testinzending / Productie-inzending / Huidige Chiron-omgeving) with
// active/inactive chips backed by the new backend fields, plus a
// lock/unlock switch on the production block driven by testflow_status.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fluxidi_tracking/app_config.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/chiron_company_connection_config.dart';
import 'package:fluxidi_tracking/widgets/chiron_environment_status_labels.dart';

BackendChironConnectionStatus _status({
  bool accTestSubmitActive = false,
  bool productionSubmitActive = false,
  String effectiveEnv = ChironConnectionEnvironment.test,
  String testflowStatus = 'not_started',
}) {
  return BackendChironConnectionStatus(
    ok: true,
    enabled: true,
    environment: ChironConnectionEnvironment.test,
    testCredentialsStored: true,
    lastConnectionStatus: 'test_passed',
    effectiveChironEnvironment: effectiveEnv,
    accTestSubmitActive: accTestSubmitActive,
    productionSubmitActive: productionSubmitActive,
    testflowStatus: testflowStatus,
  );
}

Widget _host(Widget child, {AppLanguage language = AppLanguage.nl}) {
  return MaterialApp(
    home: Scaffold(
      body: Padding(padding: const EdgeInsets.all(12), child: child),
    ),
  );
}

void main() {
  testWidgets(
    'labels: 0/5 test env → ACC actief, Productie inactief, omgeving Test/ACC',
    (tester) async {
      await tester.pumpWidget(
        _host(
          ChironEnvironmentStatusLabels(
            status: _status(accTestSubmitActive: true),
            language: AppLanguage.nl,
          ),
        ),
      );

      expect(find.text('ACC-testinzending'), findsOneWidget);
      expect(find.text('Productie-inzending'), findsOneWidget);
      expect(find.text('Huidige Chiron-omgeving'), findsOneWidget);
      // ACC active, Productie inactive — one 'actief', one 'inactief'.
      expect(find.text('actief'), findsOneWidget);
      expect(find.text('inactief'), findsOneWidget);
      expect(find.text('Test/ACC'), findsOneWidget);
    },
  );

  testWidgets('labels: production active → shows Productie, ACC inactief', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        ChironEnvironmentStatusLabels(
          status: _status(
            productionSubmitActive: true,
            effectiveEnv: ChironConnectionEnvironment.production,
          ),
          language: AppLanguage.nl,
        ),
      ),
    );

    expect(find.text('Productie'), findsOneWidget);
    // ACC inactive + Productie active → one 'actief', one 'inactief'.
    expect(find.text('actief'), findsOneWidget);
    expect(find.text('inactief'), findsOneWidget);
  });

  testWidgets('labels: null status → all inactief, default omgeving Test/ACC', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        ChironEnvironmentStatusLabels(status: null, language: AppLanguage.nl),
      ),
    );

    // Both submissions inactive.
    expect(find.text('inactief'), findsNWidgets(2));
    expect(find.text('actief'), findsNothing);
    expect(find.text('Test/ACC'), findsOneWidget);
  });

  testWidgets('labels: English translation surface', (tester) async {
    await tester.pumpWidget(
      _host(
        ChironEnvironmentStatusLabels(
          status: _status(accTestSubmitActive: true),
          language: AppLanguage.en,
        ),
      ),
    );

    expect(find.text('ACC test submission'), findsOneWidget);
    expect(find.text('Production submission'), findsOneWidget);
    expect(find.text('Current Chiron environment'), findsOneWidget);
    expect(find.text('active'), findsOneWidget);
    expect(find.text('inactive'), findsOneWidget);
  });

  testWidgets(
    'production block LOCKED before 5/5 → shows lock icon + explanatory text, no action chips',
    (tester) async {
      await tester.pumpWidget(
        _host(
          ChironProductionBlockGated(
            status: _status(testflowStatus: 'in_progress'),
            testflowStatus: 'in_progress',
            language: AppLanguage.nl,
          ),
        ),
      );

      expect(
        find.byKey(const ValueKey('chiron_production_block_locked')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('chiron_production_block_unlocked')),
        findsNothing,
      );
      expect(find.byIcon(Icons.lock_outline), findsOneWidget);
      expect(find.textContaining('Vergrendeld'), findsOneWidget);
      // Action chips must NOT render in the locked state.
      expect(find.textContaining('Productiegegevens opslaan'), findsNothing);
      expect(find.textContaining('Productie activeren'), findsNothing);
    },
  );

  testWidgets(
    'production block UNLOCKED at complete → shows official link + three action chips',
    (tester) async {
      await tester.pumpWidget(
        _host(
          ChironProductionBlockGated(
            status: _status(testflowStatus: 'complete'),
            testflowStatus: 'complete',
            language: AppLanguage.nl,
          ),
        ),
      );

      expect(
        find.byKey(const ValueKey('chiron_production_block_unlocked')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('chiron_production_block_locked')),
        findsNothing,
      );
      expect(
        find.text('https://chiron.vlaanderen.be/chiron/registratie/toegang'),
        findsOneWidget,
      );
      expect(find.text('Productiegegevens opslaan'), findsOneWidget);
      expect(find.text('Productieverbinding controleren'), findsOneWidget);
      expect(find.text('Productie activeren'), findsOneWidget);
    },
  );

  testWidgets(
    'DTO parses effective_chiron_environment + acc_test_submit_active + testflow_status from JSON',
    (tester) async {
      final parsed = BackendChironConnectionStatus.fromJson(<String, dynamic>{
        'ok': true,
        'enabled': true,
        'environment': 'test',
        'effective_chiron_environment': 'test',
        'acc_test_submit_active': true,
        'production_submit_active': false,
        'production_last_connection_status': 'never_tested',
        'testflow_status': 'in_progress',
      });
      expect(
        parsed.effectiveChironEnvironment,
        ChironConnectionEnvironment.test,
      );
      expect(parsed.accTestSubmitActive, true);
      expect(parsed.productionSubmitActive, false);
      expect(parsed.productionLastConnectionStatus, 'never_tested');
      expect(parsed.testflowStatus, 'in_progress');
    },
  );

  testWidgets('DTO parses production active shape', (tester) async {
    final parsed = BackendChironConnectionStatus.fromJson(<String, dynamic>{
      'ok': true,
      'enabled': true,
      'environment': 'production',
      'production_enabled': true,
      'production_credentials_stored': true,
      'production_last_connection_status': 'test_passed',
      'effective_chiron_environment': 'production',
      'acc_test_submit_active': false,
      'production_submit_active': true,
      'testflow_status': 'complete',
    });
    expect(
      parsed.effectiveChironEnvironment,
      ChironConnectionEnvironment.production,
    );
    expect(parsed.accTestSubmitActive, false);
    expect(parsed.productionSubmitActive, true);
    expect(parsed.productionLastConnectionStatus, 'test_passed');
    expect(parsed.testflowStatus, 'complete');
  });
}
