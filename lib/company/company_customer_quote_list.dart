// COMPANY-CUSTOMER-OPS-P0 — dossier list lines for company-issued quotes.

import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/company/company_customer_quote_labels.dart';
import 'package:fluxidi_tracking/company/company_customer_quote_models.dart';
import 'package:fluxidi_tracking/company/company_form_date_time.dart';

LocalizedText companyCustomerQuoteStateLabel(String state) {
  switch (state.trim()) {
    case 'draft':
      return kCompanyCustomerQuoteStateDraft;
    case 'sent':
      return kCompanyCustomerQuoteStateSent;
    case 'accepted':
      return kCompanyCustomerQuoteStateAccepted;
    default:
      return LocalizedText(nl: state, en: state, fr: state, es: state);
  }
}

String companyCustomerQuoteListTitle({
  required CompanyCustomerQuote quote,
  required AppLanguage language,
}) {
  final parts = <String>[
    companyCustomerQuoteStateLabel(quote.state).of(language),
  ];
  final rideAt = companyFormDateTimeFromIso(quote.startAt);
  if (rideAt != null) {
    parts.add(formatCompanyFormDate(rideAt, language));
  }
  final destination = quote.dropoff.trim();
  if (destination.isNotEmpty) parts.add(destination);
  if (quote.enteredAmountCents != null) {
    parts.add(
      formatQuoteEuros(quote.enteredAmountCents, currency: quote.currency),
    );
  }
  return parts.join(' · ');
}

String companyCustomerQuoteListSubtitle(CompanyCustomerQuote quote) {
  final pickup = quote.pickup.trim();
  final dropoff = quote.dropoff.trim();
  if (pickup.isEmpty && dropoff.isEmpty) return '';
  if (pickup.isEmpty) return dropoff;
  if (dropoff.isEmpty) return pickup;
  return '$pickup → $dropoff';
}
