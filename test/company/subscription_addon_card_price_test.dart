import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/company/subscription_addon_card_price.dart';

void main() {
  const beDriverUnit = 900;
  const beVehicleUnit = 1900;
  const beBase = 6900;
  // Server quote fixture — not a Flutter pricing constant.
  const beSaasVatRate = 0.21;

  group('inactive extra chauffeur shows catalog unit, not €0', () {
    test('zero quote unit falls back to catalog + quote vat_rate', () {
      final money = resolveAddonCardUnitMoney(
        catalogUnitExclCents: beDriverUnit,
        quoteUnitExclCents: 0,
        quoteUnitVatCents: 0,
        quoteUnitInclCents: 0,
        quoteVatRate: beSaasVatRate,
        taxTreatment: 'belgian_vat',
      );
      expect(money.exclCents, 900);
      expect(money.vatCents, 189);
      expect(money.inclCents, 1089);
    });

    test('null quote unit also uses catalog unit', () {
      final money = resolveAddonCardUnitMoney(
        catalogUnitExclCents: beDriverUnit,
        quoteVatRate: beSaasVatRate,
        taxTreatment: 'belgian_vat',
      );
      expect(money.exclCents, 900);
      expect(money.vatCents, 189);
      expect(money.inclCents, 1089);
    });
  });

  group('active quantity does not multiply the card unit', () {
    test('three active chauffeurs still show the per-unit price', () {
      const activeQty = 3;
      final money = resolveAddonCardUnitMoney(
        catalogUnitExclCents: beDriverUnit,
        quoteUnitExclCents: beDriverUnit,
        quoteUnitVatCents: 189,
        quoteUnitInclCents: 1089,
        quoteVatRate: beSaasVatRate,
        taxTreatment: 'belgian_vat',
      );
      expect(money.exclCents, isNot(beDriverUnit * activeQty));
      expect(money.exclCents, 900);
      expect(money.vatCents, 189);
      expect(money.inclCents, 1089);
    });
  });

  group('extra vehicle unit stays catalog/unit', () {
    test('Belgium extra vehicle is €19 / €3,99 / €22,99', () {
      final money = resolveAddonCardUnitMoney(
        catalogUnitExclCents: beVehicleUnit,
        quoteUnitExclCents: 1900,
        quoteUnitVatCents: 399,
        quoteUnitInclCents: 2299,
        quoteVatRate: beSaasVatRate,
        taxTreatment: 'belgian_vat',
      );
      expect(money.exclCents, 1900);
      expect(money.vatCents, 399);
      expect(money.inclCents, 2299);
    });

    test('two active vehicles do not multiply the card unit', () {
      final money = resolveAddonCardUnitMoney(
        catalogUnitExclCents: beVehicleUnit,
        quoteUnitExclCents: 1900,
        quoteUnitVatCents: 399,
        quoteUnitInclCents: 2299,
        quoteVatRate: beSaasVatRate,
        taxTreatment: 'belgian_vat',
      );
      expect(money.exclCents, isNot(3800));
      expect(money.exclCents, 1900);
    });
  });

  group('hero multiplies active quantity', () {
    test('FLX-00001 two vehicles and zero chauffeurs is €107 excl.', () {
      expect(
        subscriptionHeroRecurringExclCents(
          baseExclCents: beBase,
          extraVehicleUnitExclCents: beVehicleUnit,
          extraDriverUnitExclCents: beDriverUnit,
          extraVehicleActiveQuantity: 2,
          extraDriverActiveQuantity: 0,
        ),
        10700,
      );
    });

    test('one extra chauffeur is added only to the hero total', () {
      expect(
        subscriptionHeroRecurringExclCents(
          baseExclCents: beBase,
          extraVehicleUnitExclCents: beVehicleUnit,
          extraDriverUnitExclCents: beDriverUnit,
          extraVehicleActiveQuantity: 2,
          extraDriverActiveQuantity: 1,
        ),
        11600,
      );
      final card = resolveAddonCardUnitMoney(
        catalogUnitExclCents: beDriverUnit,
        quoteUnitExclCents: beDriverUnit,
        quoteUnitVatCents: 189,
        quoteUnitInclCents: 1089,
        quoteVatRate: beSaasVatRate,
        taxTreatment: 'belgian_vat',
      );
      expect(card.exclCents, 900);
    });
  });

  group('other markets keep their catalog and tax treatment', () {
    test('NL catalog extra driver is €7 excl. with quote vat_rate', () {
      final money = resolveAddonCardUnitMoney(
        catalogUnitExclCents: 700,
        quoteUnitExclCents: 0,
        quoteVatRate: 0.21,
        taxTreatment: 'belgian_vat',
      );
      expect(money.exclCents, 700);
      expect(money.vatCents, 147);
      expect(money.inclCents, 847);
    });

    test('helper and billing sources do not hardcode local 21% VAT', () {
      final helper = File(
        'lib/company/subscription_addon_card_price.dart',
      ).readAsStringSync();
      final billing = File(
        'lib/main_parts/company_subscription_billing_state.dart',
      ).readAsStringSync();
      expect(helper.contains('0.21'), isFalse);
      expect(billing.contains('0.21'), isFalse);
      expect(helper.contains('* 0.21'), isFalse);
      expect(billing.contains('startCompanySubscriptionAddonCheckout'), isTrue);
      expect(helper.contains('checkout'), isFalse);
      expect(helper.contains('Paid'), isFalse);
    });

    test('reverse charge shows catalog excl. and zero VAT', () {
      final money = resolveAddonCardUnitMoney(
        catalogUnitExclCents: 700,
        quoteUnitExclCents: 0,
        quoteUnitVatCents: 0,
        quoteUnitInclCents: 0,
        quoteVatRate: 0,
        taxTreatment: 'eu_reverse_charge',
      );
      expect(money.exclCents, 700);
      expect(money.vatCents, 0);
      expect(money.inclCents, 700);
    });
  });

  group('authoritative recurring monthly total (hero)', () {
    test('FLX-00001: €69 base + 2 × €19 vehicle = €107 recurring excl.', () {
      expect(
        resolveHeroRecurringExclCents(
          profileRecurringAmountCents: null,
          quoteRecurringExclVatCents: null,
          baseExclCents: beBase,
          extraVehicleUnitExclCents: beVehicleUnit,
          extraDriverUnitExclCents: beDriverUnit,
          extraVehicleActiveQuantity: 2,
          extraDriverActiveQuantity: 0,
        ),
        10700,
      );
    });

    test('€107 excl → €22,47 VAT → €129,47 incl at the quote vat_rate', () {
      const recurringExcl = 10700;
      final vat = vatCentsFromQuoteRate(recurringExcl, beSaasVatRate);
      expect(vat, 2247);
      expect(recurringExcl + vat!, 12947);
    });

    test('zero add-ons shows the €69 base', () {
      expect(
        resolveHeroRecurringExclCents(
          profileRecurringAmountCents: null,
          quoteRecurringExclVatCents: null,
          baseExclCents: beBase,
          extraVehicleUnitExclCents: beVehicleUnit,
          extraDriverUnitExclCents: beDriverUnit,
          extraVehicleActiveQuantity: 0,
          extraDriverActiveQuantity: 0,
        ),
        6900,
      );
    });

    test('server recurringAmountCents wins over a deviating local calc', () {
      // A local recomputation here would give 6900 + 1 × 1900 = 8800, but the
      // server recurring total is authoritative and must not be overridden.
      expect(
        resolveHeroRecurringExclCents(
          profileRecurringAmountCents: 10700,
          quoteRecurringExclVatCents: 9999,
          baseExclCents: beBase,
          extraVehicleUnitExclCents: beVehicleUnit,
          extraDriverUnitExclCents: beDriverUnit,
          extraVehicleActiveQuantity: 1,
          extraDriverActiveQuantity: 0,
        ),
        10700,
      );
    });

    test('safe fallback to quote then local when server value is missing', () {
      expect(
        resolveHeroRecurringExclCents(
          profileRecurringAmountCents: null,
          quoteRecurringExclVatCents: 10700,
          baseExclCents: beBase,
          extraVehicleUnitExclCents: beVehicleUnit,
          extraDriverUnitExclCents: beDriverUnit,
          extraVehicleActiveQuantity: 2,
          extraDriverActiveQuantity: 0,
        ),
        10700,
      );
      // A null or non-positive server value is treated as missing and the
      // computation falls through to the local base + add-ons total.
      expect(
        resolveHeroRecurringExclCents(
          profileRecurringAmountCents: 0,
          quoteRecurringExclVatCents: null,
          baseExclCents: beBase,
          extraVehicleUnitExclCents: beVehicleUnit,
          extraDriverUnitExclCents: beDriverUnit,
          extraVehicleActiveQuantity: 2,
          extraDriverActiveQuantity: 0,
        ),
        10700,
      );
    });
  });

  group('next-charge copy pends the date only, not the amount', () {
    test('every locale scopes the pending state to the date', () {
      const amountWords = <String>['bedrag', 'amount', 'montant', 'importe'];
      for (final lang in const <String>['nl', 'en', 'fr', 'es']) {
        final copy = subscriptionNextChargeDatePendingText(lang);
        final lower = copy.toLowerCase();
        final mentionsDate =
            lower.contains('datum') ||
            lower.contains('date') ||
            lower.contains('fecha');
        expect(
          mentionsDate,
          isTrue,
          reason: 'locale $lang must scope the pending state to the date',
        );
        for (final word in amountWords) {
          expect(
            lower.contains(word),
            isFalse,
            reason: 'locale $lang must not claim the amount is unknown',
          );
        }
      }
    });

    test('Dutch copy is the date-pending phrasing', () {
      expect(
        subscriptionNextChargeDatePendingText('nl'),
        'Afschrijfdatum nog niet gesynchroniseerd.',
      );
    });
  });
}
