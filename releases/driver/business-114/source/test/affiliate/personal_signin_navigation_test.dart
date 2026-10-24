import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/company_session_store.dart';
import 'package:fluxidi_tracking/customer_session_store.dart';
import 'package:fluxidi_tracking/customer_phone_recovery_page.dart';
import 'package:fluxidi_tracking/affiliate/affiliate_open.dart';
import 'package:fluxidi_tracking/affiliate/affiliate_page.dart';

void main() {
  testWidgets('real personal recovery new-account return never replaces company credential or home', (tester) async {
    appLanguageNotifier.value = AppLanguage.nl;
    await tester.runAsync(() => CustomerSessionStore.instance.clear());
    const company = ActiveCompanySession(companyId: 'company_fixture', role: 'companyAdmin',
      createdAt: '2026-10-04T00:00:00Z', lastUsedAt: '2026-10-04T00:00:00Z',
      companySessionToken: 'company_fixture_bearer');
    activeCompanySessionNotifier.value = company;
    addTearDown(() { activeCompanySessionNotifier.value = null; appLanguageNotifier.value = AppLanguage.en; });
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) => Scaffold(
      body: TextButton(key: const Key('company_home'), onPressed: () => openAffiliatePage(context),
        child: const Text('Company fixture home'))))));
    await tester.tap(find.byKey(const Key('company_home'))); await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('affiliate_signin'))); await tester.pumpAndSettle();
    expect(find.byType(CustomerPhoneRecoveryPage), findsOneWidget);
    await tester.ensureVisible(find.byKey(CustomerPhoneRecoveryPage.newCustomerKey));
    await tester.tap(find.byKey(CustomerPhoneRecoveryPage.newCustomerKey)); await tester.pumpAndSettle();
    expect(find.byType(AffiliatePage), findsOneWidget);
    expect(find.text('Maak eerst je persoonlijke account in de Klantenapp.'), findsOneWidget);
    expect(activeCompanySessionNotifier.value, same(company));
    expect(CustomerSessionStore.instance.peekCachedSession(), isNull);
    await tester.pageBack(); await tester.pumpAndSettle();
    expect(find.byKey(const Key('company_home')), findsOneWidget);
    expect(activeCompanySessionNotifier.value?.companySessionToken, 'company_fixture_bearer');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
