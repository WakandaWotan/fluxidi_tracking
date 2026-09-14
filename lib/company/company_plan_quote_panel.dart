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
            error!,
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          formatCompanyPlanQuoteRoute(quote, language),
          key: kCompanyPlanQuoteStatusKey,
          style: theme.textTheme.titleMedium,
        ),
        if (quote.priceAvailable) ...[
          const SizedBox(height: 6),
          Text(
            formatCompanyPlanQuotePrice(quote, language),
            key: kCompanyPlanQuotePriceKey,
          ),
        ],
      ],
    );
  }
}
