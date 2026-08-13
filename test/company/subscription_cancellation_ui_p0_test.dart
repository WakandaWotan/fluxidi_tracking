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
    expect(billingSource.contains('Vervallen nooit'), isTrue);
    expect(billingSource.contains('geen automatische verlenging'), isTrue);
    expect(
      billingSource.contains('PDF-pakket(ten) eindigen op'),
      isFalse,
    );
  });

  test('vehicle cancel CTA remains; PDF cancel CTA removed', () {
    expect(billingSource.contains('Eén extra voertuig opzeggen'), isTrue);
    expect(billingSource.contains('Cancel one extra vehicle'), isTrue);
    expect(billingSource.contains('Eén pakket van \$pdfs PDF'), isFalse);
    expect(billingSource.contains('Cancel one \$pdfs PDF bundle'), isFalse);
    expect(billingSource.contains('_pdfBundleCancellationControls'), isFalse);
    expect(billingSource.contains('_confirmAndCancelOnePdfBundle'), isFalse);
    expect(billingSource.contains('minimumSize: const Size.fromHeight(48)'), isTrue);
    expect(billingSource.contains('OutlinedButton.icon'), isTrue);
  });

  test('scheduled cancellation shows undo copy and nothing-charged-today', () {
    expect(billingSource.contains('Opgezegd — actief t/m'), isTrue);
    expect(billingSource.contains('Cancelled — active until'), isTrue);
    expect(billingSource.contains('Opzegging ongedaan maken'), isTrue);
    expect(billingSource.contains('Undo cancellation'), isTrue);
    expect(billingSource.contains('Vandaag wordt niets aangerekend'), isTrue);
    expect(billingSource.contains('Nothing is charged today'), isTrue);
    expect(billingSource.contains('undoCancelCompanySubscription'), isTrue);
  });

  test('trial marketing hidden when subscription is paid active', () {
    expect(billingSource.contains('if (!isPaidActive)'), isTrue);
    expect(billingSource.contains('2 weken gratis proefperiode'), isTrue);
    expect(billingSource.contains('Proefperiode start/einde'), isTrue);
  });

  test('SafeArea uses viewPadding bottom with extra scroll padding', () {
    expect(billingSource.contains('MediaQuery.viewPaddingOf(context).bottom'), isTrue);
    expect(billingSource.contains('24 + bottomSafeInset'), isTrue);
  });

  test('PDF section shows included and purchased credits separately', () {
    expect(billingSource.contains('_buildPdfCreditsSection'), isTrue);
    expect(billingSource.contains('Inbegrepen deze maand'), isTrue);
    expect(billingSource.contains('Aangekochte PDF-credits'), isTrue);
    expect(billingSource.contains('purchasedPdfCredits'), isTrue);
    expect(billingSource.contains('Nieuwe maandbundel op'), isTrue);
  });

  test('client accepts provider_cancel_pending, undo routes, and HTTP 202', () {
    expect(appConfigSource.contains('providerCancelPending'), isTrue);
    expect(appConfigSource.contains('provider_cancel_pending'), isTrue);
    expect(appConfigSource.contains('undoCancelCompanySubscription'), isTrue);
    expect(appConfigSource.contains('undoCancelOneExtraVehicleAddon'), isTrue);
    expect(appConfigSource.contains('undoCancelOneExtraDriverAddon'), isTrue);
    expect(appConfigSource.contains("res.statusCode != 200 && res.statusCode != 202"), isTrue);
    expect(appConfigSource.contains('AddonCheckoutProration'), isTrue);
    expect(appConfigSource.contains('pdfPurchasedCreditsRemaining'), isTrue);
    expect(appConfigSource.contains('recurringAmountCents'), isTrue);
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
