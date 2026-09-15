// COMPANY-CUSTOMER-OPS-P0 — shared ride option fields for quote and agenda.

import 'package:flutter/material.dart';
import 'package:fluxidi_tracking/airport/airport_selector.dart';
import 'package:fluxidi_tracking/app_config.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/company/company_customer_quote_labels.dart';
import 'package:fluxidi_tracking/company/company_fixed_price_labels.dart';
import 'package:fluxidi_tracking/company/company_form_date_time.dart';
import 'package:fluxidi_tracking/company/company_ride_options.dart';

const Key kCompanyRideServiceKey = Key('company_ride_service');
const Key kCompanyRideTierKey = Key('company_ride_tier');
const Key kCompanyRideBagsKey = Key('company_ride_bags');
const Key kCompanyRideWaitKey = Key('company_ride_wait');
const Key kCompanyRideFlightKey = Key('company_ride_flight');
const Key kCompanyRideMeetAndGreetKey = Key('company_ride_meet_and_greet');
const Key kCompanyRideNameBoardKey = Key('company_ride_name_board');
const Key kCompanyRideExtraKey = Key('company_ride_extra');

class CompanyRideOptionsForm extends StatelessWidget {
  const CompanyRideOptionsForm({
    super.key,
    required this.language,
    required this.value,
    required this.onChanged,
    this.showReturnAirportFields = false,
    this.showAirportRouteFields = true,
    this.showTitle = true,
    this.showService = true,
    this.showTier = true,
    this.showBags = true,
    this.showWait = true,
    this.showMeetAndGreet,
  });

  final AppLanguage language;
  final CompanyRideOptions value;
  final ValueChanged<CompanyRideOptions> onChanged;
  final bool showReturnAirportFields;
  final bool showAirportRouteFields;
  final bool showTitle;
  final bool showService;
  final bool showTier;
  final bool showBags;
  final bool showWait;
  final bool? showMeetAndGreet;

  @override
  Widget build(BuildContext context) {
    final services = companyRideServiceOptions();
    final tiers = companyRideTierOptions();
    final extras = companyRideExtraOptions();
    final serviceValue = _selected(services, value.service);
    final tierValue = _selected(tiers, value.tier);
    final extraValue = () {
      final selected = _selected(extras, value.extra);
      if (selected.isNotEmpty) return selected;
      for (final option in extras) {
        if (option.id == 'none') return 'none';
      }
      return extras.isEmpty ? '' : extras.first.id;
    }();
    final showMeet = showMeetAndGreet ?? value.isAirport;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showTitle) ...[
          Text(
            kCompanyCustomerQuoteRideOptions.of(language),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 10),
        ],
        if (showService && services.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: DropdownButtonFormField<String>(
              key: kCompanyRideServiceKey,
              isExpanded: true,
              initialValue: serviceValue,
              decoration: InputDecoration(
                labelText: kCompanyCustomerQuoteService.of(language),
              ),
              items: [
                DropdownMenuItem<String>(
                  value: '',
                  child: Text(kCompanyCustomerQuoteNotChosen.of(language)),
                ),
                for (final option in services)
                  DropdownMenuItem<String>(
                    value: option.id,
                    child: Text(option.labelFor(language)),
                  ),
              ],
              onChanged: (next) => onChanged(value.copyWith(service: next ?? '')),
            ),
          ),
        if (showTier && tiers.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: DropdownButtonFormField<String>(
              key: kCompanyRideTierKey,
              isExpanded: true,
              initialValue: tierValue,
              decoration: InputDecoration(
                labelText: kCompanyCustomerQuoteTier.of(language),
              ),
              items: [
                DropdownMenuItem<String>(
                  value: '',
                  child: Text(kCompanyCustomerQuoteNotChosen.of(language)),
                ),
                for (final option in tiers)
                  DropdownMenuItem<String>(
                    value: option.id,
                    child: Text(option.labelFor(language)),
                  ),
              ],
              onChanged: (next) => onChanged(value.copyWith(tier: next ?? '')),
            ),
          ),
        if (showBags)
        Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Row(
            children: [
              Expanded(child: Text(kCompanyCustomerQuoteBags.of(language))),
              IconButton(
                key: kCompanyRideBagsKey,
                onPressed: value.bags > 0
                    ? () => onChanged(value.copyWith(bags: value.bags - 1))
                    : null,
                icon: const Icon(Icons.remove),
              ),
              Text('${value.bags}'),
              IconButton(
                onPressed: value.bags < 3
                    ? () => onChanged(value.copyWith(bags: value.bags + 1))
                    : null,
                icon: const Icon(Icons.add),
              ),
            ],
          ),
        ),
        if (showWait)
        Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: TextFormField(
            key: kCompanyRideWaitKey,
            initialValue: value.waitMin == 0 ? '' : '${value.waitMin}',
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: kCompanyCustomerQuoteWait.of(language),
            ),
            onChanged: (text) {
              final parsed = int.tryParse(text.trim()) ?? 0;
              onChanged(value.copyWith(waitMin: parsed.clamp(0, 240)));
            },
          ),
        ),
        if (value.isAirport && showAirportRouteFields) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: DropdownButtonFormField<String>(
              isExpanded: true,
              initialValue: value.airportDirection.isEmpty
                  ? ''
                  : value.airportDirection,
              decoration: InputDecoration(
                labelText: kCompanyCustomerQuoteAirportDirection.of(language),
              ),
              items: [
                DropdownMenuItem<String>(
                  value: '',
                  child: Text(kCompanyCustomerQuoteNotChosen.of(language)),
                ),
                DropdownMenuItem<String>(
                  value: 'from_airport',
                  child: Text(kCompanyCustomerQuoteFromAirport.of(language)),
                ),
                DropdownMenuItem<String>(
                  value: 'to_airport',
                  child: Text(kCompanyCustomerQuoteToAirport.of(language)),
                ),
              ],
              onChanged: (next) =>
                  onChanged(value.copyWith(airportDirection: next ?? '')),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: AirportCountryAirportSelector(
              language: language,
              countryCode: value.airportCountry.isEmpty
                  ? 'BE'
                  : value.airportCountry,
              airportIata: value.airportIata,
              onCountryChanged: (code) =>
                  onChanged(value.copyWith(airportCountry: code)),
              onAirportChanged: (airport) => onChanged(
                value.copyWith(
                  airportIata: airport.iata,
                  airportCountry: airport.countryCode,
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: TextFormField(
              key: kCompanyRideFlightKey,
              initialValue: value.flightNumber,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(
                labelText: kCompanyCustomerQuoteFlight.of(language),
              ),
              onChanged: (text) =>
                  onChanged(value.copyWith(flightNumber: text.trim())),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: CompanyDateTimeFields(
              fieldId: 'ride_flight',
              language: language,
              value: companyFormDateTimeFromIso(value.flightAt),
              dateLabel: value.airportDirection == 'from_airport'
                  ? kCompanyCustomerQuoteFlightAtInbound.of(language)
                  : kCompanyCustomerQuoteFlightAtOutbound.of(language),
              onChanged: (next) => onChanged(
                value.copyWith(
                  flightAt: next == null ? '' : companyFormIsoFromLocal(next),
                ),
              ),
            ),
          ),
          Text(
            kCompanyFixedPricesTimezone.of(language),
            softWrap: true,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          if (value.airportDirection == 'from_airport') ...[
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: value.pickupArrangement.isEmpty
                    ? 'scheduled'
                    : value.pickupArrangement,
                decoration: InputDecoration(
                  labelText: kCompanyCustomerQuotePickupArrangement.of(language),
                ),
                items: [
                  DropdownMenuItem(
                    value: 'scheduled',
                    child: Text(
                      kCompanyCustomerQuotePickupScheduled.of(language),
                    ),
                  ),
                  DropdownMenuItem(
                    value: 'after_landing',
                    child: Text(
                      kCompanyCustomerQuotePickupAfterLanding.of(language),
                    ),
                  ),
                ],
                onChanged: (next) => onChanged(
                  value.copyWith(pickupArrangement: next ?? 'scheduled'),
                ),
              ),
            ),
            if (value.pickupArrangement == 'after_landing')
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: TextFormField(
                  initialValue: value.pickupAfterMin == 0
                      ? ''
                      : '${value.pickupAfterMin}',
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText:
                        kCompanyCustomerQuotePickupAfterLanding.of(language),
                  ),
                  onChanged: (text) => onChanged(
                    value.copyWith(
                      pickupAfterMin: (int.tryParse(text.trim()) ?? 0).clamp(
                        0,
                        240,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ],
        if (showMeet) ...[
          SwitchListTile(
            key: kCompanyRideMeetAndGreetKey,
            contentPadding: EdgeInsets.zero,
            title: Text(kCompanyCustomerQuoteMeetAndGreet.of(language)),
            value: value.meetAndGreet,
            onChanged: (next) => onChanged(value.copyWith(meetAndGreet: next)),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: TextFormField(
              key: kCompanyRideNameBoardKey,
              initialValue: value.nameBoard,
              decoration: InputDecoration(
                labelText: kCompanyCustomerQuoteNameBoard.of(language),
              ),
              onChanged: (text) =>
                  onChanged(value.copyWith(nameBoard: text.trim())),
            ),
          ),
        ],
        if (showReturnAirportFields && value.isAirport) ...[
          const SizedBox(height: 8),
          Text(
            kCompanyCustomerQuoteReturnAirport.of(language),
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          AirportCountryAirportSelector(
            language: language,
            countryCode: value.airportCountry.isEmpty
                ? 'BE'
                : value.airportCountry,
            airportIata: value.returnAirportIata.isEmpty
                ? value.airportIata
                : value.returnAirportIata,
            onCountryChanged: (_) {},
            onAirportChanged: (airport) => onChanged(
              value.copyWith(returnAirportIata: airport.iata),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 14, bottom: 14),
            child: TextFormField(
              initialValue: value.returnFlightNumber,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(
                labelText: kCompanyCustomerQuoteFlight.of(language),
              ),
              onChanged: (text) =>
                  onChanged(value.copyWith(returnFlightNumber: text.trim())),
            ),
          ),
          CompanyDateTimeFields(
            fieldId: 'ride_return_flight',
            language: language,
            value: companyFormDateTimeFromIso(value.returnFlightAt),
            dateLabel: kCompanyCustomerQuoteFlightAtInbound.of(language),
            onChanged: (next) => onChanged(
              value.copyWith(
                returnFlightAt:
                    next == null ? '' : companyFormIsoFromLocal(next),
              ),
            ),
          ),
        ],
        if (extras.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: DropdownButtonFormField<String>(
              key: kCompanyRideExtraKey,
              isExpanded: true,
              initialValue: extraValue,
              decoration: InputDecoration(
                labelText: kCompanyCustomerQuoteExtra.of(language),
              ),
              items: [
                for (final option in extras)
                  DropdownMenuItem<String>(
                    value: option.id,
                    child: Text(option.labelFor(language)),
                  ),
              ],
              onChanged: (next) => onChanged(value.copyWith(extra: next ?? '')),
            ),
          ),
      ],
    );
  }

  String _selected(List<AppOption> options, String raw) {
    final id = raw.trim();
    if (id.isEmpty) return '';
    for (final option in options) {
      if (option.id == id) return id;
    }
    return '';
  }
}
