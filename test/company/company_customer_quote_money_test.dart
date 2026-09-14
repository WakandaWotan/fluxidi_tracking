import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/company/company_customer_quote_labels.dart';
import 'package:fluxidi_tracking/company/company_customer_quote_money.dart';
import 'package:fluxidi_tracking/company/company_ride_options.dart';

void main() {
  test('excl 110 at 6 percent shows vat and total', () {
    final breakdown = computeCompanyQuoteVatBreakdown(
      enteredCents: 11000,
      treatment: 'excl',
      vatRateRaw: 0.06,
    );
    expect(breakdown.vatRatePercent, 6);
    expect(breakdown.vatCents, 660);
    expect(breakdown.inclCents, 11660);
    expect(breakdown.rateMissing, isFalse);
    final lines = companyQuoteVatBreakdownLines(
      breakdown: breakdown,
      language: AppLanguage.nl,
      currency: 'EUR',
    );
    expect(lines.join('\n'), contains('Btw 6%'));
    expect(lines.join('\n'), contains('EUR 6.60'));
    expect(lines.join('\n'), contains('Totaal incl. btw EUR 116.60'));
    expect(lines.join('\n').contains('21'), isFalse);
  });

  test('missing rate stays explicit and does not invent 21 percent', () {
    final breakdown = computeCompanyQuoteVatBreakdown(
      enteredCents: 11000,
      treatment: 'excl',
      vatRateRaw: 0,
    );
    expect(breakdown.rateMissing, isTrue);
    expect(breakdown.inclCents, isNull);
    expect(companyQuoteVatRatePercent(0), isNull);
    expect(companyQuoteVatRatePercent(null), isNull);
    final lines = companyQuoteVatBreakdownLines(
      breakdown: breakdown,
      language: AppLanguage.nl,
      currency: 'EUR',
    );
    expect(lines, contains(kCompanyCustomerQuoteVatRateMissing.of(AppLanguage.nl)));
    expect(lines.join('\n').contains('21'), isFalse);
    expect(lines.join('\n').contains('116.60'), isFalse);
  });

  test('ride option summary uses translated labels', () {
    const options = CompanyRideOptions(
      service: 'business',
      tier: 'premium',
      extra: 'worktable',
    );
    final summary = formatCompanyRideOptionsSummary(
      options,
      language: AppLanguage.nl,
    );
    expect(summary, 'Zakelijk · Premium · Werktafel (laptop)');
    expect(summary.contains('business'), isFalse);
    expect(summary.contains('worktable'), isFalse);
  });
}