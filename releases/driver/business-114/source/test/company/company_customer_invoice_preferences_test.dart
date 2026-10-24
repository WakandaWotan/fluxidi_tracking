import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/company/company_customer_form_page.dart';
import 'package:fluxidi_tracking/company/company_customers_repository.dart';
import 'package:fluxidi_tracking/company/company_customer_models.dart';

void main() {
  testWidgets('unrelated customer edit preserves existing monthly choice', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final existing = parseCompanyCustomer({
      'customer_id': 'cus_1',
      'tenant_id': 'T',
      'company_id': 'C',
      'display_name': 'Fixture',
      'email': 'fixture@example.test',
      'status': 'active',
      'revision': 1,
      'preferences': {'version': 2, 'invoice_frequency': 'monthly'},
    });
    CompanyCustomerWrite? saved;
    final repository = _CaptureRepository((write) => saved = write, existing);
    await tester.pumpWidget(
      MaterialApp(
        home: CompanyCustomerFormPage(
          repository: repository,
          existing: existing,
          language: AppLanguage.nl,
        ),
      ),
    );
    await tester.enterText(
      find.byKey(kCompanyCustomerFormNameKey),
      'Edited fixture',
    );
    await tester.tap(find.byKey(kCompanyCustomersSaveButtonKey));
    await tester.pumpAndSettle();
    expect(saved!.preferences.invoiceFrequency, 'monthly');
    expect(saved!.preferences.version, 2);
  });

  testWidgets(
    'monthly selector is hidden by default and selects monthly when flag enabled',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1440, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final customer = parseCompanyCustomer({
        'customer_id': 'cus_1',
        'display_name': 'Fixture',
        'email': 'fixture@example.test',
        'status': 'active',
        'revision': 1,
      });
      CompanyCustomerWrite? saved;
      await tester.pumpWidget(
        MaterialApp(
          home: CompanyCustomerFormPage(
            repository: _CaptureRepository((write) => saved = write, customer),
            existing: customer,
            language: AppLanguage.nl,
          ),
        ),
      );
      final selector = find.byKey(
        const Key('company_customer_invoice_frequency'),
      );
      if (const bool.fromEnvironment('COMPANY_MONTHLY_INVOICING_UI')) {
        await tester.ensureVisible(selector);
        await tester.tap(selector);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Maandfactuur').last);
        await tester.pumpAndSettle();
      } else {
        expect(selector, findsNothing);
      }
      await tester.tap(find.byKey(kCompanyCustomersSaveButtonKey));
      await tester.pumpAndSettle();
      expect(
        saved!.preferences.invoiceFrequency,
        const bool.fromEnvironment('COMPANY_MONTHLY_INVOICING_UI')
            ? 'monthly'
            : 'per_ride',
      );
    },
  );
  test('legacy preference shape stays per ride and unchanged', () {
    final preferences = parseCompanyCustomerPreferences({
      'version': 1,
      'preferred_locale': 'nl',
    });
    expect(preferences.invoiceFrequency, 'per_ride');
    expect(preferences.toJson(), {'version': 1, 'preferred_locale': 'nl'});
    expect(parseCompanyCustomerPreferences(null).invoiceFrequency, 'per_ride');
  });
  test('monthly choice survives model roundtrip without changing locale', () {
    final preferences = parseCompanyCustomerPreferences({
      'version': 2,
      'preferred_locale': 'fr',
      'invoice_frequency': 'monthly',
    });
    expect(preferences.invoiceFrequency, 'monthly');
    expect(
      parseCompanyCustomerPreferences(preferences.toJson()).invoiceFrequency,
      'monthly',
    );
    expect(preferences.version, 2);
    expect(preferences.preferredLocale, 'fr');
  });
  test('unknown invoice frequency is not silently accepted', () {
    for (final value in ['weekly', '', true, 1]) {
      expect(
        () => parseCompanyCustomerPreferences({'invoice_frequency': value}),
        throwsA(isA<CompanyCustomerException>()),
      );
    }
  });
}

class _CaptureRepository extends CompanyCustomersRepository {
  _CaptureRepository(this.capture, this.customer)
    : super(
        listTransport:
            ({required path, required query, required headers}) async => {},
        sendTransport:
            ({
              required method,
              required path,
              required query,
              required body,
              required headers,
              idempotencyKey,
            }) async => {},
      );
  final void Function(CompanyCustomerWrite) capture;
  final CompanyCustomer customer;
  @override
  Future<CompanyCustomer> update(
    String customerId,
    CompanyCustomerWrite write, {
    required int revision,
  }) async {
    capture(write);
    return customer;
  }
}
