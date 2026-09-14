import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_config.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/company/company_customer_quote_labels.dart';
import 'package:fluxidi_tracking/company/company_rate_card_hint.dart';
import 'package:fluxidi_tracking/company/company_ride_options.dart';

void main() {
  test('company rates stay a reference and are not a fixed offer', () {
    final hint = buildCompanyRateCardHint(
      language: AppLanguage.nl,
      settings: businessSettingsNotifier.value,
      options: const CompanyRideOptions(service: 'airport'),
    );
    expect(
      hint.notes,
      contains(kCompanyCustomerQuoteRatesDisclaimer.of(AppLanguage.nl)),
    );
    expect(hint.notes.join(' ').contains('Vaste prijs gebruiken'), isTrue);
    expect(hint.notes.join(' ').contains('kilometertarieven'), isTrue);
    expect(hint.referenceLines.any((line) => line.contains('Starttarief')), isTrue);
    expect(hint.referenceLines.any((line) => line.contains('Per km')), isTrue);
  });
}
