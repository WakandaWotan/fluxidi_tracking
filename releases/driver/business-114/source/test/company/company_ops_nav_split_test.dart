import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/company/company_agenda_http.dart';
import 'package:fluxidi_tracking/company/company_agenda_labels.dart';
import 'package:fluxidi_tracking/company/company_agenda_models.dart';
import 'package:fluxidi_tracking/company/company_agenda_calendar.dart';
import 'package:fluxidi_tracking/company/company_customer_labels.dart';
import 'package:fluxidi_tracking/company/company_customer_models.dart';
import 'package:fluxidi_tracking/company/company_customers_page.dart';
import 'package:fluxidi_tracking/company/company_customers_repository.dart';
import 'package:fluxidi_tracking/company/company_ops_workspace_page.dart';

class _FakeCustomersRepository extends CompanyCustomersRepository {
  _FakeCustomersRepository()
    : super(
        scopeQuery: const <String, String>{
          'tenant_id': 'demo_company_p0',
          'company_id': 'demo_company_p0',
        },
        headers: () async => const <String, String>{},
        listTransport:
            ({required path, required query, required headers}) async =>
                <String, dynamic>{'ok': true, 'items': <dynamic>[]},
        sendTransport:
            ({
              required method,
              required path,
              required query,
              required body,
              required headers,
              idempotencyKey,
            }) async => <String, dynamic>{'ok': true},
      );

  @override
  Future<CompanyCustomerListPage> list({
    String status = 'active',
    String query = '',
    String cursor = '',
  }) async {
    return CompanyCustomerListPage(
      items: <CompanyCustomerListItem>[
        CompanyCustomerListItem(
          customerId: 'cus_1',
          displayName: 'Ada Lovelace',
          companyName: '',
          phoneMasked: '***01',
          emailMasked: '*@demo.local',
          status: 'active',
          updatedAt: '2026-09-11T00:00:00.000Z',
        ),
      ],
      hasMore: false,
      nextCursor: null,
      totalCount: 1,
    );
  }

  @override
  Future<CompanyCustomer> getById(String customerId) async {
    return parseCompanyCustomer(<String, dynamic>{
      'customer_id': customerId,
      'display_name': 'Ada Lovelace',
      'status': 'active',
      'revision': 1,
      'email': 'ada@example.test',
    });
  }
}

class _FakeAgendaRepository extends CompanyAgendaRepository {
  _FakeAgendaRepository()
    : super(
        scopeResolver: () => const <String, String>{
          'tenant_id': 'demo_company_p0',
          'company_id': 'demo_company_p0',
        },
        listTransport: (_) async => const <CompanyAgendaRide>[],
        createTransport: ({required draft, required idempotencyKey}) async {
          throw const CompanyAgendaException('unused');
        },
      );
}

void main() {
  test('home Quick actions split planner and CRM destinations', () {
    final home = File(
      'lib/main_parts/business_home_page_state.dart',
    ).readAsStringSync();
    final planRide = home.indexOf("actionKey: 'plan_ride'");
    final planWrap = home.indexOf("'company_home_plan_ride'");
    final customers = home.indexOf("nl: 'Klantenbeheer'");
    expect(planRide, greaterThan(0));
    expect(planWrap, greaterThan(0));
    expect(customers, greaterThan(0));
    expect(
      home.substring(planRide, planRide + 900).contains('_openCompanyPlanRide'),
      isTrue,
    );
    expect(
      home.substring(planWrap, planWrap + 900).contains('_openCompanyPlanRide'),
      isTrue,
    );
    expect(
      home.substring(customers, customers + 500).contains('_openCompanyCustomers'),
      isTrue,
    );
    expect(
      home.substring(customers, customers + 500).contains('_openCompanyPlanRide'),
      isFalse,
    );
    expect(home.contains('CompanyBookingsOverviewPage()'), isTrue);
    expect(home.contains('_openBusinessBookingsOverview'), isTrue);
    expect(home.contains("'company_home_customers'"), isTrue);
    final customersOpen = home.indexOf('Future<void> _openCompanyCustomers');
    expect(customersOpen, greaterThan(0));
    expect(
      home
          .substring(customersOpen, customersOpen + 900)
          .contains('CompanyCustomersPage('),
      isTrue,
    );
    expect(
      home
          .substring(customersOpen, customersOpen + 900)
          .contains('CompanyOpsWorkspacePage('),
      isFalse,
    );
    final planOpen = home.indexOf('Future<void> _openCompanyPlanRide');
    expect(planOpen, greaterThan(0));
    final planFn = home.substring(planOpen, planOpen + 900);
    expect(planFn.contains('CompanyOpsWorkspacePage('), isTrue);
    expect(planFn.contains('plannerOnly: true'), isTrue);
    expect(planFn.contains('CompanyCustomersPage('), isFalse);
    final bookingsOpen = home.indexOf(
      'Future<void> _openBusinessBookingsOverview',
    );
    expect(bookingsOpen, greaterThan(0));
    expect(
      home
          .substring(bookingsOpen, bookingsOpen + 400)
          .contains('CompanyBookingsOverviewPage()'),
      isTrue,
    );
    expect(
      home
          .substring(bookingsOpen, bookingsOpen + 400)
          .contains('CompanyOpsWorkspacePage('),
      isFalse,
    );
  });

  testWidgets('planner workspace has no CRM list or dossier calendar', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: CompanyOpsWorkspacePage(
          plannerOnly: true,
          language: AppLanguage.nl,
          customersRepository: _FakeCustomersRepository(),
          agendaRepository: _FakeAgendaRepository(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(kCompanyOpsPlannerWorkspaceKey), findsOneWidget);
    expect(find.byKey(kCompanyAgendaPaneKey), findsOneWidget);
    expect(find.byKey(kCompanyCustomersSearchFieldKey), findsNothing);
    expect(find.byKey(kCompanyCustomersPageKey), findsNothing);
    expect(find.byType(CompanyAgendaCalendar), findsOneWidget);
    expect(find.text(kCompanyAgendaPlanRide.of(AppLanguage.nl)), findsWidgets);
    expect(find.text(kCompanyAgendaHint.of(AppLanguage.nl)), findsWidgets);
    expect(
      find.byKey(const Key('company_ops_planner_empty_start')),
      findsOneWidget,
    );
    expect(find.byKey(kCompanyAgendaToggleCustomersKey), findsNothing);
  });

  testWidgets('CRM page has no agenda, plan form or Rit plannen', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: CompanyCustomersPage(
          language: AppLanguage.nl,
          repository: _FakeCustomersRepository(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(kCompanyCustomersPageKey), findsOneWidget);
    expect(find.byKey(kCompanyCustomersSearchFieldKey), findsOneWidget);
    expect(find.byKey(kCompanyAgendaPaneKey), findsNothing);
    expect(find.byType(CompanyAgendaCalendar), findsNothing);
    expect(find.byKey(kCompanyAgendaRideFormKey), findsNothing);
    expect(find.byKey(kCompanyAgendaPlanRideKey), findsNothing);
    expect(find.text(kCompanyAgendaPlanRide.of(AppLanguage.nl)), findsNothing);
    expect(find.text(kCompanyCustomersTitle.of(AppLanguage.nl)), findsWidgets);
    expect(find.text(kCompanyCustomersAddLabel.of(AppLanguage.nl)), findsOneWidget);
    expect(find.byKey(kCompanyCustomersListKey), findsOneWidget);
  });
}
