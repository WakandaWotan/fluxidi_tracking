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
