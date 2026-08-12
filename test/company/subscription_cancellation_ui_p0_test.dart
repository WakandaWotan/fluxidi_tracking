import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Source-contract tests for subscription cancel UX + SafeArea padding.
/// Does not call live APIs or mutate production tenants.
void main() {
  late String billingSource;
  late String appConfigSource;

  setUpAll(() {
    billingSource = File(
      'lib/main_parts/company_subscription_billing_state.dart',
    ).readAsStringSync();
    appConfigSource = File('lib/app_config.dart').readAsStringSync();
  });

  test('base cancel confirmation lists cascade consequences and founder warning', () {
    expect(billingSource.contains('_baseCancelConsequenceLines'), isTrue);
    expect(billingSource.contains('Founderprijs'), isTrue);
    expect(billingSource.contains('founder price'), isTrue);
    expect(billingSource.contains('tarif fondateur'), isTrue);
    expect(billingSource.contains('precio fundador'), isTrue);
    expect(billingSource.contains('extra voertuig'), isTrue);
    expect(billingSource.contains('PDF-pakket'), isTrue);
    expect(billingSource.contains('geen automatische verlenging'), isTrue);
  });

  test('separate vehicle and PDF cancellation actions are visible CTAs', () {
    expect(billingSource.contains('Eén extra voertuig opzeggen'), isTrue);
    expect(billingSource.contains('Cancel one extra vehicle'), isTrue);
    expect(billingSource.contains('Eén pakket van \$pdfs PDF'), isTrue);
    expect(billingSource.contains('Cancel one \$pdfs PDF bundle'), isTrue);
    expect(billingSource.contains('minimumSize: const Size.fromHeight(48)'), isTrue);
    expect(billingSource.contains('OutlinedButton.icon'), isTrue);
  });

  test('pending cancellation copy renders after schedule', () {
    expect(billingSource.contains('Opzegging gepland'), isTrue);
    expect(billingSource.contains('Cancellation scheduled'), isTrue);
    expect(billingSource.contains('Résiliation planifiée'), isTrue);
    expect(billingSource.contains('Cancelación programada'), isTrue);
  });

  test('SafeArea uses viewPadding bottom with extra scroll padding', () {
    expect(billingSource.contains('MediaQuery.viewPaddingOf(context).bottom'), isTrue);
    expect(billingSource.contains('24 + bottomSafeInset'), isTrue);
  });

  test('PDF active state does not dominate with activation CTA', () {
    expect(billingSource.contains('Actief: \$activeQty'), isTrue);
    expect(billingSource.contains('Nog een pakket van \$pdfs toevoegen'), isTrue);
  });

  test('client accepts provider_cancel_pending and HTTP 202', () {
    expect(appConfigSource.contains('providerCancelPending'), isTrue);
    expect(appConfigSource.contains('provider_cancel_pending'), isTrue);
    expect(appConfigSource.contains("res.statusCode != 200 && res.statusCode != 202"), isTrue);
  });

  test('entitlement PDF totals remain source-of-truth driven', () {
    expect(
      billingSource.contains(
        'catalog.includedPdfCreationsPerVehicleMonth *',
      ),
      isTrue,
    );
    expect(billingSource.contains('addonAllowance: profile.pdfMonthlyAllowance'), isTrue);
  });

  test('localization covers NL EN FR ES for cancel labels', () {
    for (final snippet in <String>[
      "nl: 'Abonnement opzeggen'",
      "en: 'Cancel subscription'",
      "fr: 'Résilier l\\'abonnement'",
      "es: 'Cancelar suscripción'",
      "nl: 'Eén extra voertuig opzeggen'",
      "en: 'Cancel one extra vehicle'",
      "fr: 'Résilier un véhicule supplémentaire'",
      "es: 'Cancelar un vehículo extra'",
    ]) {
      expect(billingSource.contains(snippet), isTrue, reason: snippet);
    }
  });
}
