// COMPANY-CUSTOMER-OPS-P0 — quote VAT display from existing settings logic.
// pricingVatRate is a fraction (0.06) or already in percent points. Never invent
// a rate such as 21% when the configured rate is missing.

import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/company/company_customer_quote_labels.dart';
import 'package:fluxidi_tracking/company/company_customer_quote_models.dart';

double? companyQuoteVatRatePercent(double? raw) {
  if (raw == null || !raw.isFinite || raw < 0) return null;
  final pct = raw <= 1 ? raw * 100 : raw;
  if (pct <= 0 || pct > 100) return null;
  return pct;
}

class CompanyQuoteVatBreakdown {
  const CompanyQuoteVatBreakdown({
    required this.treatment,
    this.enteredCents,
    this.vatRatePercent,
    this.exclCents,
    this.vatCents,
    this.inclCents,
    this.rateMissing = false,
  });

  final String treatment;
  final int? enteredCents;
  final double? vatRatePercent;
  final int? exclCents;
  final int? vatCents;
  final int? inclCents;
  final bool rateMissing;

  bool get hasComputedTotals =>
      !rateMissing && exclCents != null && vatCents != null && inclCents != null;
}

CompanyQuoteVatBreakdown computeCompanyQuoteVatBreakdown({
  required int? enteredCents,
  required String treatment,
  double? vatRateRaw,
}) {
  final code = treatment.trim().toLowerCase();
  if (enteredCents == null) {
    return CompanyQuoteVatBreakdown(treatment: code);
  }
  if (code == 'none' || code == 'zero') {
    return CompanyQuoteVatBreakdown(
      treatment: code,
      enteredCents: enteredCents,
      vatRatePercent: code == 'zero' ? 0 : null,
      exclCents: enteredCents,
      vatCents: 0,
      inclCents: enteredCents,
    );
  }
  final pct = companyQuoteVatRatePercent(vatRateRaw);
  if (pct == null) {
    return CompanyQuoteVatBreakdown(
      treatment: code.isEmpty ? 'incl' : code,
      enteredCents: enteredCents,
      rateMissing: true,
    );
  }
  if (code == 'excl') {
    final vatCents = (enteredCents * pct / 100).round();
    return CompanyQuoteVatBreakdown(
      treatment: code,
      enteredCents: enteredCents,
      vatRatePercent: pct,
      exclCents: enteredCents,
      vatCents: vatCents,
      inclCents: enteredCents + vatCents,
    );
  }
  final exclCents = (enteredCents * 100 / (100 + pct)).round();
  return CompanyQuoteVatBreakdown(
    treatment: code.isEmpty ? 'incl' : code,
    enteredCents: enteredCents,
    vatRatePercent: pct,
    exclCents: exclCents,
    vatCents: enteredCents - exclCents,
    inclCents: enteredCents,
  );
}

String _formatVatPercent(double pct) {
  if (pct == pct.roundToDouble()) return pct.toStringAsFixed(0);
  return pct.toStringAsFixed(2);
}

List<String> companyQuoteVatBreakdownLines({
  required CompanyQuoteVatBreakdown breakdown,
  required AppLanguage language,
  required String currency,
}) {
  final code = currency.trim().isEmpty ? 'EUR' : currency.trim().toUpperCase();
  final lines = <String>[
    formatQuoteEuros(breakdown.enteredCents, currency: code),
  ];
  if (breakdown.rateMissing) {
    lines.add(kCompanyCustomerQuoteVatRateMissing.of(language));
    return lines;
  }
  if (breakdown.vatRatePercent != null && breakdown.vatRatePercent! > 0) {
    lines.add(
      '${kCompanyCustomerQuoteVatPercent.of(language)} ${_formatVatPercent(breakdown.vatRatePercent!)}%',
    );
  }
  if (!breakdown.hasComputedTotals) return lines;
  if (breakdown.treatment == 'excl') {
    lines.add(
      '${kCompanyCustomerQuoteVatAmount.of(language)} ${formatQuoteEuros(breakdown.vatCents, currency: code)}',
    );
    lines.add(
      '${kCompanyCustomerQuoteTotalIncl.of(language)} ${formatQuoteEuros(breakdown.inclCents, currency: code)}',
    );
  } else if (breakdown.treatment == 'incl') {
    lines.add(
      '${kCompanyCustomerQuoteAmountExcl.of(language)} ${formatQuoteEuros(breakdown.exclCents, currency: code)}',
    );
    lines.add(
      '${kCompanyCustomerQuoteVatAmount.of(language)} ${formatQuoteEuros(breakdown.vatCents, currency: code)}',
    );
  }
  return lines;
}
