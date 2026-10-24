// RELEASE-P0 — route-level proofs for the actual Chiron Compliance page.
//
// These tests pump [ChironComplianceDashboardPage] (the widget opened from
// Business home → Chiron Compliance), not isolated wizard helpers alone.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_config.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/chiron_company_connection_config.dart';
import 'package:fluxidi_tracking/chiron_compliance_dashboard_page.dart';
import 'package:fluxidi_tracking/company_session_store.dart';
import 'package:fluxidi_tracking/widgets/chiron_friendly_diagnose_sheet.dart';
import 'package:fluxidi_tracking/widgets/chiron_self_service_wizard.dart';

Finder _pageScrollable() => find.byType(Scrollable).first;

Future<void> _reveal(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    300,
    scrollable: _pageScrollable(),
  );
  await tester.ensureVisible(finder);
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    appLanguageNotifier.value = AppLanguage.nl;
    final now = DateTime.now().toUtc().toIso8601String();
    activeCompanySessionNotifier.value = ActiveCompanySession(
      companyId: 'co_route_test',
      role: 'companyAdmin',
      createdAt: now,
      lastUsedAt: now,
      companySessionToken: 'cst_route_test',
      companySessionExpiresAtUtc:
          DateTime.now().toUtc().add(const Duration(hours: 2)).toIso8601String(),
    );
    companyProfileNotifier.value = CompanyProfile(
      companyId: 'co_route_test',
      companyName: 'Route Test Co',
      ownerName: 'Owner',
      email: 'owner@example.test',
      phone: '+3200',
      vatNumber: '',
      addressLine: '',
      postalCode: '',
      city: '',
      countryCode: 'BE',
      companyEmail: '',
      supportEmail: '',
      billingEmail: '',
      bookingEmail: '',
      notificationEmail: '',
      createdAt: now,
      updatedAt: now,
      isActive: true,
    );
    backendChironConnectionStatusNotifier.value =
        const BackendChironConnectionStatus(
          ok: true,
          enabled: true,
          testCredentialsStored: false,
          lastConnectionStatus: 'never_tested',
          accTestSubmitActive: true,
          productionSubmitActive: false,
          effectiveChironEnvironment: ChironConnectionEnvironment.test,
        );
  });

  tearDown(() {
    backendChironConnectionStatusNotifier.value = null;
    activeCompanySessionNotifier.value = null;
    companyProfileNotifier.value = null;
  });

  Future<void> pumpDashboard(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(home: ChironComplianceDashboardPage()),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  testWidgets('routed page shows compact 3-step wizard; no 8-step wall', (
    tester,
  ) async {
    await pumpDashboard(tester);

    expect(
      find.byKey(const ValueKey('chiron_compliance_overview_wizard')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('chiron_self_service_wizard')), findsOneWidget);
    expect(find.text('Testverbinding'), findsWidgets);
    expect(find.text('Acceptatietest'), findsWidgets);
    expect(find.text('Productieverbinding'), findsWidgets);

    await _reveal(tester, find.text('Open Chiron-testportaal').first);
    expect(find.text('Open Chiron-testportaal'), findsWidgets);
    expect(find.text('Open Chiron-productieportaal'), findsWidgets);

    await _reveal(tester, find.text('Test Client ID'));
    expect(find.text('Test Client ID'), findsOneWidget);
    expect(find.text('Test Client Secret'), findsOneWidget);

    expect(find.text('Chiron aansluiten met Fluxidi'), findsNothing);
    expect(find.text('Connect Chiron with Fluxidi'), findsNothing);
    expect(
      find.textContaining('Registreer uw bedrijf in de Chiron-testomgeving'),
      findsNothing,
    );
    expect(find.textContaining('Official submission'), findsNothing);
    expect(find.textContaining('Officiële doorgifte'), findsNothing);
  });

  testWidgets('routed page exposes separate production credential labels', (
    tester,
  ) async {
    backendChironConnectionStatusNotifier.value =
        const BackendChironConnectionStatus(
          ok: true,
          enabled: true,
          testCredentialsStored: true,
          lastConnectionStatus: 'test_passed',
          testflowStatus: 'complete',
          testDepartureSentCount: 5,
          testArrivalSentCount: 5,
          testRidesCompletedCount: 5,
          testMessagesSentCount: 10,
          accTestSubmitActive: true,
          productionSubmitActive: false,
          effectiveChironEnvironment: ChironConnectionEnvironment.test,
        );
    await pumpDashboard(tester);
    await _reveal(tester, find.text('Productie Client ID'));
    expect(find.text('Productie Client ID'), findsOneWidget);
    expect(find.text('Productie Client Secret'), findsOneWidget);
  });

  testWidgets('portal URL constants match official Chiron portals', (_) async {
    expect(
      kChironTestPortalUrl,
      'https://chiron-acc.vlaanderen.be/chiron/registratie/toegang',
    );
    expect(
      kChironProductionPortalUrl,
      'https://chiron.vlaanderen.be/chiron/registratie/toegang',
    );
  });

  testWidgets('reset on routed page opens professional opaque dialog', (
    tester,
  ) async {
    backendChironConnectionStatusNotifier.value =
        const BackendChironConnectionStatus(
          ok: true,
          enabled: true,
          testCredentialsStored: true,
          lastConnectionStatus: 'test_passed',
          testflowStatus: 'in_progress',
          testDepartureSentCount: 1,
          testArrivalSentCount: 1,
          accTestSubmitActive: true,
        );
    await pumpDashboard(tester);
    final reset = find.byKey(const ValueKey('chiron_reset_testflow_button'));
    await _reveal(tester, reset);
    final button = tester.widget<OutlinedButton>(reset);
    expect(button.onPressed, isNotNull);
    final future = Future<void>.sync(button.onPressed!);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    // Prefer Dialog finders — generic dialog type params confuse byType.
    expect(find.byType(Dialog), findsOneWidget);
    expect(find.textContaining('Chiron-testflow resetten'), findsWidgets);
    final dialog = tester.widget<Dialog>(find.byType(Dialog));
    expect(dialog.backgroundColor, isNotNull);
    // Close to avoid leaking the dialog Future across tests.
    final cancel = find.text('Annuleren');
    if (cancel.evaluate().isNotEmpty) {
      await tester.tap(cancel);
      await tester.pump();
    }
    await future;
  });

  testWidgets('diagnose opens on first tap; slow refresh needs no second tap', (
    tester,
  ) async {
    await pumpDashboard(tester);
    final diagnose = find.byKey(const ValueKey('chiron_diagnose_button'));
    await _reveal(tester, diagnose);
    await tester.tap(diagnose);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    // Sheet content visible after a single tap (cached status first).
    expect(find.byType(ChironFriendlyDiagnoseSheet), findsOneWidget);
    expect(find.text('ACC-testinzending'), findsWidgets);
    expect(find.text('Diagnose'), findsWidgets);
  });

  testWidgets('honest next-step never contradicts stored+passed credentials', (
    tester,
  ) async {
    backendChironConnectionStatusNotifier.value =
        const BackendChironConnectionStatus(
          ok: true,
          enabled: true,
          testCredentialsStored: true,
          lastConnectionStatus: 'test_passed',
          testflowStatus: 'in_progress',
          accTestSubmitActive: true,
        );
    final next = chironHonestNextStepLabel(
      status: backendChironConnectionStatusNotifier.value,
      language: AppLanguage.nl,
      enabled: true,
    );
    expect(next.toLowerCase(), isNot(contains('testgegevens toevoegen')));
    expect(next.toLowerCase(), isNot(contains('add test credentials')));
  });

  for (final lang in AppLanguage.values) {
    testWidgets('routed page pumps without overflow for ${lang.name}', (
      tester,
    ) async {
      appLanguageNotifier.value = lang;
      await pumpDashboard(tester);
      expect(tester.takeException(), isNull);

      tester.view.physicalSize = const Size(390, 844);
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  }
}
