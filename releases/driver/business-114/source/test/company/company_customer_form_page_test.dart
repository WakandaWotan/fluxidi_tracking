import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/company/company_customer_form_page.dart';
import 'package:fluxidi_tracking/company/company_customer_labels.dart';
import 'package:fluxidi_tracking/company/company_customers_repository.dart';

void main() {
  testWidgets('form suggests a display name and keeps a manual edit', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(size: Size(1440, 900)),
        child: MaterialApp(
          home: CompanyCustomerFormPage(
            language: AppLanguage.nl,
            repository: _FakeCustomersRepository(),
          ),
        ),
      ),
    );
    expect(
      find.textContaining(kCompanyCustomersDisplayName.of(AppLanguage.nl)),
      findsWidgets,
    );
    expect(find.byKey(kCompanyCustomerFormRequiredHintKey), findsOneWidget);
    expect(
      find.text(kCompanyCustomersContactRequired.of(AppLanguage.nl)),
      findsWidgets,
    );
    await tester.enterText(find.byKey(kCompanyCustomerFormFirstNameKey), 'Ada');
    await tester.enterText(find.byKey(kCompanyCustomerFormLastNameKey), 'Lovelace');
    await tester.pump();
    expect(
      tester.widget<TextField>(find.byKey(kCompanyCustomerFormNameKey)).controller!.text,
      'Ada Lovelace',
    );
    await tester.enterText(find.byKey(kCompanyCustomerFormNameKey), 'Ada L.');
    await tester.enterText(find.byKey(kCompanyCustomerFormFirstNameKey), 'Ada');
    await tester.enterText(find.byKey(kCompanyCustomerFormLastNameKey), 'Byron');
    await tester.pump();
    expect(
      tester.widget<TextField>(find.byKey(kCompanyCustomerFormNameKey)).controller!.text,
      'Ada L.',
    );
    expect(find.byKey(kCompanyCustomerFormLocaleKey), findsOneWidget);
    expect(find.byKey(kCompanyCustomerFormCallingCodeKey), findsOneWidget);
    final form = tester.getSize(find.byKey(kCompanyCustomerFormPageKey));
    expect(form.width, 1440);
    expect(
      tester.getSize(find.byKey(kCompanyCustomersSaveButtonKey)).width,
      lessThanOrEqualTo(720),
    );
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
        }) async => <String, dynamic>{'ok': true, 'items': <dynamic>[]},
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
