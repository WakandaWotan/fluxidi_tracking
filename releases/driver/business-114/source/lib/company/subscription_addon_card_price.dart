/// Catalog/unit-price presentation for monthly add-on cards.
///
/// The active-count chip stays quantity-based. The card price is always the
/// recurring unit, never `activeQuantity × unit`. Tax amounts come from the
/// server quote's unit fields or from that quote's `vat_rate` / treatment —
/// never from a local hardcoded Belgian 21% constant.
library;

class AddonCardUnitMoney {
  const AddonCardUnitMoney({
    required this.exclCents,
    required this.vatCents,
    required this.inclCents,
  });

  final int exclCents;
  final int vatCents;
  final int inclCents;
}

/// Same rounding the booking Worker uses: `Math.round(excl * vatRate)`.
int? vatCentsFromQuoteRate(int exclCents, double? vatRate) {
  if (exclCents < 0) return null;
  if (vatRate == null || !vatRate.isFinite || vatRate < 0) return null;
  return (exclCents * vatRate).round();
}

/// Resolves the per-unit add-on card money.
///
/// [quoteUnitExclCents] is used only when it is a positive catalog/unit
/// amount. Zero/null (inactive extra chauffeur, missing lock) falls back to
/// [catalogUnitExclCents] plus the quote's tax treatment / `vat_rate`.
AddonCardUnitMoney resolveAddonCardUnitMoney({
  required int catalogUnitExclCents,
  int? quoteUnitExclCents,
  int? quoteUnitVatCents,
  int? quoteUnitInclCents,
  double? quoteVatRate,
  String taxTreatment = '',
}) {
  final reverse = taxTreatment == 'eu_reverse_charge';
  final useQuoteUnit = quoteUnitExclCents != null && quoteUnitExclCents > 0;
  final excl = useQuoteUnit ? quoteUnitExclCents : catalogUnitExclCents;

  if (reverse) {
    return AddonCardUnitMoney(exclCents: excl, vatCents: 0, inclCents: excl);
  }

  if (useQuoteUnit &&
      quoteUnitVatCents != null &&
      quoteUnitInclCents != null &&
      quoteUnitExclCents + quoteUnitVatCents == quoteUnitInclCents) {
    return AddonCardUnitMoney(
      exclCents: quoteUnitExclCents,
      vatCents: quoteUnitVatCents,
      inclCents: quoteUnitInclCents,
    );
  }

  final vat = vatCentsFromQuoteRate(excl, quoteVatRate) ?? 0;
  return AddonCardUnitMoney(
    exclCents: excl,
    vatCents: vat,
    inclCents: excl + vat,
  );
}

/// Hero recurring excl. is quantity-based. The add-on *card* is not.
int subscriptionHeroRecurringExclCents({
  required int baseExclCents,
  required int extraVehicleUnitExclCents,
  required int extraDriverUnitExclCents,
  required int extraVehicleActiveQuantity,
  required int extraDriverActiveQuantity,
}) {
  return baseExclCents +
      extraVehicleActiveQuantity * extraVehicleUnitExclCents +
      extraDriverActiveQuantity * extraDriverUnitExclCents;
}

/// Authoritative recurring monthly total (excl. VAT) for the subscription hero.
///
/// Precedence, server-authoritative first:
///   1. the server profile `recurringAmountCents` — the consolidated base plus
///      the active recurring add-ons the backend actually bills;
///   2. the display quote `recurringExclVatCents`;
///   3. the local base plus active recurring add-ons computation.
///
/// A positive server value always wins, even when a local recomputation would
/// differ, so the hero can never understate the amount that is really billed.
/// A null or non-positive server value falls through safely to the next source.
int resolveHeroRecurringExclCents({
  int? profileRecurringAmountCents,
  int? quoteRecurringExclVatCents,
  required int baseExclCents,
  required int extraVehicleUnitExclCents,
  required int extraDriverUnitExclCents,
  required int extraVehicleActiveQuantity,
  required int extraDriverActiveQuantity,
}) {
  if (profileRecurringAmountCents != null && profileRecurringAmountCents > 0) {
    return profileRecurringAmountCents;
  }
  if (quoteRecurringExclVatCents != null && quoteRecurringExclVatCents > 0) {
    return quoteRecurringExclVatCents;
  }
  return subscriptionHeroRecurringExclCents(
    baseExclCents: baseExclCents,
    extraVehicleUnitExclCents: extraVehicleUnitExclCents,
    extraDriverUnitExclCents: extraDriverUnitExclCents,
    extraVehicleActiveQuantity: extraVehicleActiveQuantity,
    extraDriverActiveQuantity: extraDriverActiveQuantity,
  );
}

/// Next-charge line for the hero when the recurring amount is already known but
/// the exact next charge date has not yet been synchronized from the provider.
///
/// It only states that the date is pending — never that the amount is unknown —
/// and it never invents a provider charge date.
String subscriptionNextChargeDatePendingText(String languageCode) {
  switch (languageCode) {
    case 'en':
      return 'Next charge date not yet synchronized.';
    case 'fr':
      return 'Date du prochain prélèvement pas encore synchronisée.';
    case 'es':
      return 'Fecha del próximo cargo aún no sincronizada.';
    case 'nl':
    default:
      return 'Afschrijfdatum nog niet gesynchroniseerd.';
  }
}
