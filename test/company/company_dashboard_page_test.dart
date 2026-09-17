import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/company/booking_list_page_repository.dart';
import 'package:fluxidi_tracking/company/company_booking_detail_page.dart';
import 'package:fluxidi_tracking/company/company_bookings_page.dart';
import 'package:fluxidi_tracking/company/company_customer_import_labels.dart';
import 'package:fluxidi_tracking/company/company_customer_labels.dart';
import 'package:fluxidi_tracking/company/company_agenda_http.dart';
import 'package:fluxidi_tracking/company/company_agenda_models.dart';
import 'package:fluxidi_tracking/company/company_customers_page.dart';
import 'package:fluxidi_tracking/company/company_customers_repository.dart';
import 'package:fluxidi_tracking/company/company_ops_workspace_page.dart';
import 'package:fluxidi_tracking/company/company_dashboard_layout.dart';
import 'package:fluxidi_tracking/company/company_dashboard_page.dart';
import 'package:fluxidi_tracking/company/company_dashboard_tiles.dart';
import 'package:fluxidi_tracking/company/company_dashboard_unavailable_page.dart';
import 'package:fluxidi_tracking/company/company_drivers_admin_page.dart';
import 'package:fluxidi_tracking/company/company_driver_schedule_page.dart';
import 'package:fluxidi_tracking/business_theme_store.dart';
import 'package:fluxidi_tracking/company/company_ops_identity.dart';
import 'package:fluxidi_tracking/company/company_customer_quote_page.dart';
import 'package:fluxidi_tracking/company/company_settings_page.dart';
import 'package:fluxidi_tracking/fluxidi_responsive.dart';

void main() {
  test('web tiles keep bookings and settings reachable and cockpit blocked', () {
    CompanyDashboardTileSpec tile(String key) =>
        kCompanyDashboardTiles.firstWhere((item) => item.actionKey == key);
    expect(tile('settings').webFit, CompanyDashboardTileWebFit.available);
    expect(tile('planning').webFit, CompanyDashboardTileWebFit.available);
    expect(tile('vehicles').webFit, CompanyDashboardTileWebFit.available);
    expect(tile('customers').webFit, CompanyDashboardTileWebFit.available);
    expect(tile('payments').webFit, CompanyDashboardTileWebFit.available);
    expect(tile('booking_link').webFit, CompanyDashboardTileWebFit.available);
    expect(tile('drivers').webFit, CompanyDashboardTileWebFit.blocked);
    expect(tile('chiron').webFit, CompanyDashboardTileWebFit.blocked);
    expect(tile('demand_radar').webFit, CompanyDashboardTileWebFit.blocked);
  });

  setUp(() {
    resetBusinessThemePersistenceLatchForTest();
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
            bookingsPageLoader: ({cursor = '', forceRefresh = false}) async {
              return const BookingListPageResult(
                scopeKey: 's',
                cacheKey: 's|',
                contract: BookingListContractKind.legacy,
                items: <Map<String, dynamic>>[
                  <String, dynamic>{
                    'booking_id': 'cqb_ae3b84ee25e4f6505adc0b076192d394',
                    'customer_name': 'Ada Lovelace',
                    'from': 'Brussel-Zuid',
                    'to': 'Antwerpen-Centraal',
                    'status': 'PENDING',
                    'quote_id': 'cqq_711fd5c7c0095f21764a542d8b55b846',
                  },
                ],
                count: 1,
                hasMore: false,
              );
            },
            bookingDetailLoader: (bookingId) async => <String, dynamic>{
              'ok': true,
              'status': 'PENDING',
              'record': <String, dynamic>{
                'booking_id': bookingId,
                'customer_name': 'Ada Lovelace',
                'from': 'Brussel-Zuid',
                'to': 'Antwerpen-Centraal',
                'quote_id': 'cqq_711fd5c7c0095f21764a542d8b55b846',
              },
            },
            driversLoader: () async => const <Map<String, dynamic>>[],
            vehiclesLoader: () async => const <Map<String, dynamic>>[],
            settingsProfileLoader: () async => <String, dynamic>{
              'companyName': 'Fluxidi Demo Cars',
              'phone': '+3227110000',
              'email': 'ops@demo.local',
              'country': 'BE',
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

    await tester.tap(find.byKey(const Key('brand_signature_action_chiron')));
    await tester.pumpAndSettle();
    expect(find.byKey(kCompanyDashboardUnavailablePageKey), findsOneWidget);
    expect(
      find.byKey(kCompanyDashboardUnavailableBlockerKey),
      findsOneWidget,
    );
    expect(
      find.textContaining('ChironComplianceDashboardPage'),
      findsOneWidget,
    );
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.ensureVisible(
      find.byKey(const Key('brand_signature_action_planning')),
    );
    await tester.tap(find.byKey(const Key('brand_signature_action_planning')));
    await tester.pumpAndSettle();
    expect(find.byKey(kCompanyBookingsPageKey), findsOneWidget);
    expect(find.textContaining('Ada Lovelace'), findsWidgets);
    await tester.tap(find.text('Brussel-Zuid → Antwerpen-Centraal'));
    await tester.pumpAndSettle();
    expect(find.byKey(kCompanyBookingDetailPageKey), findsOneWidget);
    // Approved split: a booking opened from Boekingen is not a quote
    // dossier. There is no quote-return hint; system back must land on
    // the bookings list, not Rit plannen and not an offerte page.
    expect(find.byKey(kCompanyAgendaBackToQuoteHintKey), findsNothing);
    expect(find.textContaining('Terug gaat naar de offerte'), findsNothing);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byKey(kCompanyBookingsPageKey), findsOneWidget);
    expect(find.textContaining('Ada Lovelace'), findsWidgets);
    expect(find.byKey(kCompanyOpsWorkspacePageKey), findsNothing);
    expect(find.byKey(kCompanyCustomerQuotePageKey), findsNothing);
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.ensureVisible(
      find.byKey(const Key('brand_signature_action_settings')),
    );
    await tester.tap(find.byKey(const Key('brand_signature_action_settings')));
    await tester.pumpAndSettle();
    expect(find.byKey(kCompanySettingsPageKey), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.ensureVisible(
      find.byKey(const Key('brand_signature_action_ai_dispatch')),
    );
    await tester.tap(find.byKey(const Key('brand_signature_action_ai_dispatch')));
    await tester.pumpAndSettle();
    expect(find.byKey(kCompanyCustomersPageKey), findsOneWidget);
    expect(find.byKey(kCompanyOpsWorkspacePageKey), findsNothing);
    expect(find.byKey(kCompanyCustomersSearchFieldKey), findsOneWidget);
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

  testWidgets(
    'dashboard Chauffeurs opens that driver’s Uurrooster',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(size: Size(390, 844)),
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
              ],
              identityLoader: () async => <String, dynamic>{
                'companyName': 'Fluxidi Demo Cars',
              },
              driversLoader: () async => <Map<String, dynamic>>[
                <String, dynamic>{
                  'driver_id': 'drv_karel',
                  'display_name': 'Karel Peeters',
                  'phone': '+32470000011',
                  'is_active': true,
                },
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const Key('brand_signature_action_customers')),
      );
      await tester.tap(find.byKey(const Key('brand_signature_action_customers')));
      await tester.pumpAndSettle();
      expect(find.byKey(kCompanyDriversAdminPageKey), findsOneWidget);
      expect(find.textContaining('Karel Peeters'), findsWidgets);
      await tester.tap(find.byKey(companyDriverScheduleActionKey('drv_karel')));
      await tester.pumpAndSettle();
      expect(find.byKey(kCompanyDriverSchedulePageKey), findsOneWidget);
      expect(find.textContaining('Karel Peeters'), findsWidgets);
      expect(find.byKey(kCompanyDriverScheduleSaveUnavailableKey), findsOneWidget);
    },
  );
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
