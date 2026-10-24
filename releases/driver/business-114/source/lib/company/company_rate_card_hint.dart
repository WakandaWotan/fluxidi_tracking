// COMPANY-CUSTOMER-OPS-P0 — internal company rates, never a quote price.

import 'package:flutter/material.dart';
import 'package:fluxidi_tracking/app_config.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/company/company_customer_quote_labels.dart';
import 'package:fluxidi_tracking/company/company_ride_options.dart';

const Key kCompanyInternalRatesToggleKey = Key('company_internal_rates_toggle');
const Key kCompanyInternalRatesPanelKey = Key('company_internal_rates_panel');

class CompanyRateCardHint {
  const CompanyRateCardHint({
    required this.referenceLines,
    required this.notes,
  });

  final List<String> referenceLines;
  final List<String> notes;

  bool get hasUsableRates => referenceLines.isNotEmpty;
}

CompanyRateCardHint buildCompanyRateCardHint({
  required AppLanguage language,
  required BusinessSettingsState settings,
  required CompanyRideOptions options,
}) {
  final currency = settings.defaultCurrency.trim().isEmpty
      ? 'EUR'
      : settings.defaultCurrency.trim().toUpperCase();
  final vatMode = settings.pricingVatMode.trim().isEmpty
      ? 'incl'
      : settings.pricingVatMode.trim();
  final reference = <String>[
    _moneyLine(
      language,
      nl: 'Starttarief',
      en: 'Base fare',
      fr: 'Prise en charge',
      es: 'Tarifa base',
      amount: settings.pricingBaseFare,
      currency: currency,
    ),
    _moneyLine(
      language,
      nl: 'Per km',
      en: 'Per km',
      fr: 'Par km',
      es: 'Por km',
      amount: settings.pricingPerKm,
      currency: currency,
    ),
    _moneyLine(
      language,
      nl: 'Per minuut',
      en: 'Per minute',
      fr: 'Par minute',
      es: 'Por minuto',
      amount: settings.pricingPerMinute,
      currency: currency,
    ),
    _moneyLine(
      language,
      nl: 'Minimum',
      en: 'Minimum',
      fr: 'Minimum',
      es: 'Mínimo',
      amount: settings.pricingMinimumFare,
      currency: currency,
    ),
    _moneyLine(
      language,
      nl: 'Wachten per minuut',
      en: 'Waiting per minute',
      fr: 'Attente par minute',
      es: 'Espera por minuto',
      amount: settings.pricingWaitPerMinute,
      currency: currency,
    ),
    _moneyLine(
      language,
      nl: 'Bagage per stuk',
      en: 'Bags each',
      fr: 'Bagages pièce',
      es: 'Equipaje cada uno',
      amount: settings.pricingBagFeeEach,
      currency: currency,
    ),
    _plain(
      language,
      nl: 'Btw $vatMode · ${settings.pricingVatRate.toStringAsFixed(0)}%',
      en: 'VAT $vatMode · ${settings.pricingVatRate.toStringAsFixed(0)}%',
      fr: 'TVA $vatMode · ${settings.pricingVatRate.toStringAsFixed(0)}%',
      es: 'IVA $vatMode · ${settings.pricingVatRate.toStringAsFixed(0)}%',
    ),
  ];
  if (options.tier == 'comfort' && settings.pricingTierFeeComfort > 0) {
    reference.add(
      _moneyLine(
        language,
        nl: 'Comforttoeslag',
        en: 'Comfort fee',
        fr: 'Supplément confort',
        es: 'Suplemento comfort',
        amount: settings.pricingTierFeeComfort,
        currency: currency,
      ),
    );
  }
  if (options.tier == 'private' && settings.pricingTierFeePrivate > 0) {
    reference.add(
      _moneyLine(
        language,
        nl: 'Privatetoeslag',
        en: 'Private fee',
        fr: 'Supplément private',
        es: 'Suplemento private',
        amount: settings.pricingTierFeePrivate,
        currency: currency,
      ),
    );
  }
  if (options.tier == 'premium' && settings.pricingTierFeePremium > 0) {
    reference.add(
      _moneyLine(
        language,
        nl: 'Premiumtoeslag',
        en: 'Premium fee',
        fr: 'Supplément premium',
        es: 'Suplemento premium',
        amount: settings.pricingTierFeePremium,
        currency: currency,
      ),
    );
  }

  final notes = <String>[
    kCompanyCustomerQuoteRatesDisclaimer.of(language),
  ];
  if (options.isAirport) {
    notes.add(
      _plain(
        language,
        nl: 'Dit zijn geen vaste luchthavenprijzen. Een toekomstige keuze ‘Vaste prijs gebruiken’ moet een ingestelde aanbieding selecteren, niet deze kilometertarieven.',
        en: 'These are not airport fixed fares. A future “Use fixed price” choice must pick a configured offer, not these per-km rates.',
        fr: 'Ce ne sont pas des tarifs aéroport fixes. Un futur « Utiliser un prix fixe » devra choisir une offre configurée, pas ces tarifs au km.',
        es: 'Estas no son tarifas fijas de aeropuerto. Una futura «Usar precio fijo» debe elegir una oferta configurada, no estas tarifas por km.',
      ),
    );
  }
  if (settings.pricingBaseFare <= 0 &&
      settings.pricingPerKm <= 0 &&
      settings.pricingMinimumFare <= 0) {
    notes.add(
      _plain(
        language,
        nl: 'Er is nog geen bruikbaar bedrijfstarief ingesteld.',
        en: 'No usable company rate is configured yet.',
        fr: 'Aucun tarif entreprise utilisable n’est encore configuré.',
        es: 'Aún no hay una tarifa de empresa usable.',
      ),
    );
  }

  return CompanyRateCardHint(
    referenceLines: reference,
    notes: notes,
  );
}

class CompanyInternalRatesPanel extends StatelessWidget {
  const CompanyInternalRatesPanel({
    super.key,
    required this.language,
    required this.options,
  });

  final AppLanguage language;
  final CompanyRideOptions options;

  @override
  Widget build(BuildContext context) {
    final hint = buildCompanyRateCardHint(
      language: language,
      settings: businessSettingsNotifier.value,
      options: options,
    );
    return ExpansionTile(
      key: kCompanyInternalRatesToggleKey,
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(bottom: 8),
      title: Text(kCompanyCustomerQuoteViewRates.of(language)),
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: Column(
            key: kCompanyInternalRatesPanelKey,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final line in hint.notes)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(line, softWrap: true),
                ),
              for (final line in hint.referenceLines)
                Text(line, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      ],
    );
  }
}

String _moneyLine(
  AppLanguage language, {
  required String nl,
  required String en,
  required String fr,
  required String es,
  required double amount,
  required String currency,
}) {
  return '${_plain(language, nl: nl, en: en, fr: fr, es: es)}: $currency ${amount.toStringAsFixed(2)}';
}

String _plain(
  AppLanguage language, {
  required String nl,
  required String en,
  required String fr,
  required String es,
}) {
  switch (language) {
    case AppLanguage.nl:
      return nl;
    case AppLanguage.fr:
      return fr;
    case AppLanguage.es:
      return es;
    case AppLanguage.en:
    case AppLanguage.de:
      return en;
  }
}
