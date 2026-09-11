import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/company/company_customer_import_labels.dart';
import 'package:fluxidi_tracking/company/company_customer_labels.dart';
import 'package:fluxidi_tracking/company/company_customers_page.dart';
import 'package:fluxidi_tracking/company/company_customers_repository.dart';
import 'package:fluxidi_tracking/company/company_dashboard_layout.dart';
import 'package:fluxidi_tracking/company/company_dashboard_page.dart';
import 'package:fluxidi_tracking/company/company_dashboard_unavailable_page.dart';
import 'package:fluxidi_tracking/company/company_ops_identity.dart';
import 'package:fluxidi_tracking/fluxidi_responsive.dart';

void main() {
  setUp(() {
    companyOpsContextGeneration = 0;
    companyOpsLocalSessionNotifier.value = null;
    companyOpsIdentityNotifier.value = CompanyOpsIdentity.empty;
    appLanguageNotifier.value = AppLanguage.nl;
  });

  test('wide Windows uses a compact header and four gold tiles', () {
    expect(companyDashboardIsDesktopWide(1440), isTrue);
    expect(companyDashboardIsDesktopWide(800), isFalse);
    expect(
      companyDashboardGoldTileColumns(
        screenClass: FluxidiScreenClass.desktop,
        isTabletLandscape: true,
      ),
      4,
    );
    expect(
      companyDashboardGoldTileColumns(
        screenClass: FluxidiScreenClass.tablet,
        isTabletLandscape: true,
      ),
      3,
    );
    expect(
      companyDashboardGoldTileColumns(
        screenClass: FluxidiScreenClass.phone,
        isTabletLandscape: false,
      ),
      2,
    );
    expect(
      companyDashboardHeaderHeight(
        isTabletLandscape: true,
        useTabletVisualMode: true,
        isDesktopWide: true,
      ),
      kCompanyDashboardDesktopHeaderHeight,
    );
    expect(
      companyDashboardHeaderHeight(
        isTabletLandscape: true,
        useTabletVisualMode: true,
      ),
      156,
    );
  });

  test('delayed identity from the previous company is ignored', () {
    beginCompanyOpsContextClear();
    companyOpsLocalSessionNotifier.value = const CompanyOpsLocalSession(
      companyId: 'demo_company_p1',
      sessionToken: 'tok-b',
    );
    final stale = identityFromBusinessProfile(
      generation: 0,
      companyId: 'demo_company_p0',
      profile: <String, dynamic>{
        'companyName': 'Fluxidi Demo Cars',
        'publicLogoUrl': 'http://127.0.0.1:8788/local/media/demo_company_p0/logo.png',
      },
    );
    expect(
      shouldApplyCompanyOpsIdentity(
        generation: stale.generation,
        companyId: stale.companyId,
        session: companyOpsLocalSessionNotifier.value,
      ),
      isFalse,
    );
    expect(stale.logo.isCompanyOwned, isTrue);
    expect(stale.logo.ref.contains('demo_company_p0'), isTrue);
  });

  test('import country copy names numbers without a country code', () {
    expect(
      kCompanyCustomerImportDefaultCountry.of(AppLanguage.nl),
      'Land voor telefoonnummers zonder landcode',
    );
  });

  testWidgets('dashboard opens Klantenbeheer and blocked tiles stay honest', (
    tester,
  ) async {
    final repo = _FakeCustomersRepository();
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(size: Size(1440, 900)),
        child: MaterialApp(
          home: CompanyDashboardPage(
            language: AppLanguage.nl,
            directory: () async => const <CompanyOpsDirectoryEntry>[
              CompanyOpsDirectoryEntry(
                companyId: 'demo_company_p0',
                sessionToken: 'tok-a',
                companyName: 'Fluxidi Demo Cars',
                publicLogoUrl:
                    'http://127.0.0.1:8788/local/media/demo_company_p0/logo.png',
              ),
              CompanyOpsDirectoryEntry(
                companyId: 'demo_company_p1',
                sessionToken: 'tok-b',
                companyName: 'Nocturne Limousines',
                publicLogoUrl:
                    'http://127.0.0.1:8788/local/media/demo_company_p1/logo.png',
              ),
            ],
            identityLoader: () async => <String, dynamic>{
              'companyName':
                  companyOpsLocalSessionNotifier.value?.companyId ==
                      'demo_company_p1'
                  ? 'Nocturne Limousines'
                  : 'Fluxidi Demo Cars',
              'publicLogoUrl':
                  'http://127.0.0.1:8788/local/media/${companyOpsLocalSessionNotifier.value?.companyId}/logo.png',
            },
            onOpenCustomers: (context, identity) {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => CompanyCustomersPage(
                    language: AppLanguage.nl,
                    issuerName: identity.companyName,
                    repository: repo,
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(kCompanyDashboardPageKey), findsOneWidget);
    expect(find.byKey(kCompanyDashboardNameKey), findsOneWidget);
    expect(find.text('Fluxidi Demo Cars'), findsWidgets);
    expect(tester.getSize(find.byKey(kCompanyDashboardHeaderKey)).height, 96);

    await tester.tap(find.byKey(const Key('brand_signature_action_settings')));
    await tester.pumpAndSettle();
    expect(find.byKey(kCompanyDashboardUnavailablePageKey), findsOneWidget);
    expect(
      find.byKey(kCompanyDashboardUnavailableBlockerKey),
      findsOneWidget,
    );
    expect(
      find.textContaining('BusinessSettingsPage'),
      findsOneWidget,
    );
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.ensureVisible(
      find.byKey(const Key('brand_signature_action_ai_dispatch')),
    );
    await tester.tap(find.byKey(const Key('brand_signature_action_ai_dispatch')));
    await tester.pumpAndSettle();
    expect(find.byKey(kCompanyCustomersPageKey), findsOneWidget);
    expect(find.text(kCompanyCustomersTitle.of(AppLanguage.nl)), findsWidgets);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byKey(kCompanyDashboardPageKey), findsOneWidget);

    await tester.tap(find.byKey(kCompanyDashboardSwitchKey));
    await tester.pumpAndSettle();
    expect(find.byKey(kCompanyDashboardPickerKey), findsOneWidget);
    await tester.tap(find.byKey(const Key('company_dashboard_pick_demo_company_p1')));
    await tester.pumpAndSettle();
    expect(find.text('Nocturne Limousines'), findsWidgets);
    expect(find.text('Fluxidi Demo Cars'), findsNothing);
  });
}

class _FakeCustomersRepository extends CompanyCustomersRepository {
  _FakeCustomersRepository()
    : super(
        scopeQuery: const <String, String>{
          'tenant_id': 'TA',
          'company_id': 'CA',
        },
        headers: () async => const <String, String>{},
        listTransport: ({
          required path,
          required query,
          required headers,
        }) async => <String, dynamic>{
          'ok': true,
          'items': <dynamic>[],
        },
        sendTransport: ({
          required method,
          required path,
          required query,
          required body,
          required headers,
          idempotencyKey,
        }) async => <String, dynamic>{'ok': true},
      );
}
