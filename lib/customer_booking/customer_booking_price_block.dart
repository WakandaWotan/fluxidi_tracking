import 'package:flutter/material.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/company/company_plan_quote.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_keys.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_labels.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_quote_wire.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_submit.dart';

const LocalizedText kCustomerBookingTotalInclVat = LocalizedText(
  nl: 'Totaal incl. btw',
  en: 'Total incl. VAT',
  fr: 'Total TTC',
  es: 'Total IVA incl.',
);

const LocalizedText kCustomerBookingTotalExVat = LocalizedText(
  nl: 'Excl. btw',
  en: 'Excl. VAT',
  fr: 'Hors TVA',
  es: 'Sin IVA',
);

const LocalizedText kCustomerBookingPriceDetails = LocalizedText(
  nl: 'Prijsdetails',
  en: 'Price details',
  fr: 'Détail du prix',
  es: 'Detalle del precio',
);

const LocalizedText kCustomerBookingPriceCalculating = LocalizedText(
  nl: 'Prijs wordt berekend…',
  en: 'Calculating price…',
  fr: 'Calcul du prix…',
  es: 'Calculando el precio…',
);

const LocalizedText kCustomerBookingRouteReadyPricePending = LocalizedText(
  nl: 'Route bekend. De prijs wordt nog berekend.',
  en: 'Route ready. Price is still being calculated.',
  fr: 'Itinéraire prêt. Le prix est encore en cours de calcul.',
  es: 'Ruta lista. El precio se está calculando.',
);

const LocalizedText kCustomerBookingPriceRetry = LocalizedText(
  nl: 'Prijs opnieuw berekenen',
  en: 'Recalculate price',
  fr: 'Recalculer le prix',
  es: 'Recalcular el precio',
);

num? customerBookingQuoteExVat(CompanyPlanQuoteResult quote) {
  if (quote.priceExVat != null) return quote.priceExVat;
  final breakdown = quote.breakdown;
  if (breakdown?.totalEx != null) return breakdown!.totalEx;
  return null;
}

num? customerBookingQuoteInclVat(CompanyPlanQuoteResult quote) {
  return quote.displayTotalPrice ?? quote.priceInclVat;
}

class CustomerBookingPriceBlock extends StatelessWidget {
  const CustomerBookingPriceBlock({
    super.key,
    required this.language,
    required this.loading,
    required this.quote,
    required this.error,
    required this.onRetry,
    this.arrivalText = '',
  });

  final AppLanguage language;
  final bool loading;
  final CompanyPlanQuoteResult? quote;
  final String? error;
  final VoidCallback onRetry;
  final String arrivalText;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (loading) {
      return Text(
        kCustomerBookingPriceCalculating.of(language),
        key: kCustomerBookingQuoteStatusKey,
      );
    }
    if (error != null && error!.trim().isNotEmpty) {
      final needCompany = error == kCustomerBookingIssueNeedCompany;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            customerBookingQuoteErrorText(error, language),
            key: kCustomerBookingQuoteStatusKey,
            style: TextStyle(color: theme.colorScheme.error),
          ),
          if (!needCompany) ...[
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: onRetry,
              child: Text(kCustomerBookingPriceRetry.of(language)),
            ),
          ],
        ],
      );
    }
    final result = quote;
    if (result == null) return const SizedBox.shrink();
    if (customerBookingQuotePriceFailed(result) ||
        (!result.priceAvailable &&
            !customerBookingQuoteIsOnRequest(result) &&
            result.hasRoute)) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            result.hasRoute
                ? kCustomerBookingRouteReadyPricePending.of(language)
                : kCustomerBookingPriceFailed.of(language),
            key: kCustomerBookingQuoteStatusKey,
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: onRetry,
            child: Text(kCustomerBookingPriceRetry.of(language)),
          ),
        ],
      );
    }
    if (customerBookingQuoteIsOnRequest(result)) {
      return Text(
        kCustomerBookingPriceOnRequest.of(language),
        key: kCustomerBookingPriceKey,
        style: theme.textTheme.titleMedium,
      );
    }
    final incl = customerBookingQuoteInclVat(result);
    final excl = customerBookingQuoteExVat(result);
    if (incl == null) return const SizedBox.shrink();
    final details = <String>[
      if (result.outboundPriceInclVat != null &&
          result.returnPriceInclVat != null) ...[
        '${kCustomerBookingPriceOutbound.of(language)} · ${formatCompanyPlanQuoteMoney(result.outboundPriceInclVat!, result.currency)}',
        '${kCustomerBookingPriceReturn.of(language)} · ${formatCompanyPlanQuoteMoney(result.returnPriceInclVat!, result.currency)}',
      ],
      if (result.breakdown != null)
        ...formatCompanyPlanQuoteBreakdownLines(
          result.breakdown!,
          language: language,
          currency: result.currency,
        ),
      if (result.returnBreakdown != null)
        ...formatCompanyPlanQuoteBreakdownLines(
          result.returnBreakdown!,
          language: language,
          currency: result.currency,
        ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          kCustomerBookingTotalInclVat.of(language),
          style: theme.textTheme.labelLarge,
        ),
        Text(
          formatCompanyPlanQuoteMoney(incl, result.currency),
          key: kCustomerBookingPriceKey,
          style: theme.textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        if (excl != null) ...[
          const SizedBox(height: 4),
          Text(
            kCustomerBookingTotalExVat.of(language),
            style: theme.textTheme.labelMedium,
          ),
          Text(
            formatCompanyPlanQuoteMoney(excl, result.currency),
            style: theme.textTheme.titleMedium,
          ),
        ],
        if (arrivalText.trim().isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(arrivalText, style: theme.textTheme.bodyMedium),
        ],
        if (details.isNotEmpty)
          Theme(
            data: theme.copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: Text(kCustomerBookingPriceDetails.of(language)),
              children: [
                for (final line in details)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(line),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}
