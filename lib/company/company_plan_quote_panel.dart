import 'package:flutter/material.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/company/company_agenda_labels.dart';
import 'package:fluxidi_tracking/company/company_plan_quote.dart';

class CompanyPlanQuotePanel extends StatelessWidget {
  const CompanyPlanQuotePanel({
    super.key,
    required this.language,
    required this.loading,
    required this.result,
    required this.error,
    required this.onRetry,
  });

  final AppLanguage language;
  final bool loading;
  final CompanyPlanQuoteResult? result;
  final String? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (loading) {
      return Text(
        kCompanyAgendaRouteCalculating.of(language),
        key: kCompanyPlanQuoteStatusKey,
      );
    }
    if (error != null && error!.trim().isNotEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            companyPlanQuoteErrorText(error, language),
            key: kCompanyPlanQuoteStatusKey,
            style: TextStyle(color: theme.colorScheme.error),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            key: kCompanyPlanQuoteRetryKey,
            onPressed: onRetry,
            child: Text(kCompanyAgendaRouteRetry.of(language)),
          ),
        ],
      );
    }
    final quote = result;
    if (quote == null || !quote.hasRoute) {
      return const SizedBox.shrink();
    }
    final route = formatCompanyPlanQuoteRoute(quote, language);
    final price = formatCompanyPlanQuotePrice(quote, language);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              route,
              key: kCompanyPlanQuoteStatusKey,
              style: theme.textTheme.titleMedium,
            ),
            if (price.isNotEmpty) ...[
              Text(' · ', style: theme.textTheme.titleMedium),
              Text(
                price,
                key: kCompanyPlanQuotePriceKey,
                style: theme.textTheme.titleMedium,
              ),
            ],
          ],
        ),
        if (!quote.priceAvailable)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              kCompanyAgendaQuoteUnavailable.of(language),
              key: kCompanyPlanQuotePriceKey,
              style: TextStyle(color: theme.colorScheme.error),
            ),
          ),
      ],
    );
  }
}
