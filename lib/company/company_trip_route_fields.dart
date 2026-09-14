// COMPANY-CUSTOMER-OPS-P0 — shared route kind, address/airport fields and swap.

import 'package:flutter/material.dart';
import 'package:fluxidi_tracking/airport/airport_catalog_repository.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/company/company_address_field.dart';
import 'package:fluxidi_tracking/company/company_airport_search_field.dart';
import 'package:fluxidi_tracking/company/company_customer_models.dart';
import 'package:fluxidi_tracking/company/company_customer_quote_labels.dart';
import 'package:fluxidi_tracking/company/company_fixed_price_labels.dart';
import 'package:fluxidi_tracking/company/company_form_date_time.dart';
import 'package:fluxidi_tracking/company/company_ride_options.dart';
import 'package:fluxidi_tracking/company/company_ride_options_form.dart';
import 'package:fluxidi_tracking/company/company_trip_route.dart';
import 'package:fluxidi_tracking/limousine/limousine_address_field.dart';

class CompanyTripRouteFields extends StatefulWidget {
  const CompanyTripRouteFields({
    super.key,
    required this.language,
    required this.pickup,
    required this.dropoff,
    required this.rideOptions,
    required this.onRideOptionsChanged,
    this.savedAddresses = const <CompanyCustomerAddress>[],
    this.pickupInputKey,
    this.dropoffInputKey,
    this.pickupLabel,
    this.dropoffLabel,
    this.onRouteIdentityChanged,
    this.showReturnAirportFields = false,
  });

  final AppLanguage language;
  final LimousineAddressFieldController pickup;
  final LimousineAddressFieldController dropoff;
  final CompanyRideOptions rideOptions;
  final ValueChanged<CompanyRideOptions> onRideOptionsChanged;
  final List<CompanyCustomerAddress> savedAddresses;
  final Key? pickupInputKey;
  final Key? dropoffInputKey;
  final String? pickupLabel;
  final String? dropoffLabel;
  final VoidCallback? onRouteIdentityChanged;
  final bool showReturnAirportFields;

  @override
  State<CompanyTripRouteFields> createState() => _CompanyTripRouteFieldsState();
}

class _CompanyTripRouteFieldsState extends State<CompanyTripRouteFields> {
  late final TextEditingController _flight;

  CompanyRideOptions get rideOptions => widget.rideOptions;
  AppLanguage get language => widget.language;
  LimousineAddressFieldController get pickup => widget.pickup;
  LimousineAddressFieldController get dropoff => widget.dropoff;
  List<CompanyCustomerAddress> get savedAddresses => widget.savedAddresses;
  Key? get pickupInputKey => widget.pickupInputKey;
  Key? get dropoffInputKey => widget.dropoffInputKey;
  String? get pickupLabel => widget.pickupLabel;
  String? get dropoffLabel => widget.dropoffLabel;
  bool get showReturnAirportFields => widget.showReturnAirportFields;

  CompanyTripRouteKind get _kind => companyTripRouteKindOf(rideOptions);

  @override
  void initState() {
    super.initState();
    _flight = TextEditingController(text: rideOptions.flightNumber);
  }

  @override
  void didUpdateWidget(covariant CompanyTripRouteFields oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.rideOptions.flightNumber != rideOptions.flightNumber &&
        _flight.text != rideOptions.flightNumber) {
      _flight.text = rideOptions.flightNumber;
    }
  }

  @override
  void dispose() {
    _flight.dispose();
    super.dispose();
  }

  AirportCatalogAirport? get _airport {
    if (rideOptions.airportIata.trim().isEmpty) return null;
    return airportByIata(
      rideOptions.airportIata,
      countryCode: rideOptions.airportCountry.isEmpty
          ? null
          : rideOptions.airportCountry,
    );
  }

  void _setKind(CompanyTripRouteKind next) {
    if (next == _kind) return;
    widget.onRideOptionsChanged(
      companyTripRouteOptionsForKind(current: rideOptions, kind: next).copyWith(
        airportIata: rideOptions.airportIata,
        airportCountry: rideOptions.airportCountry,
        flightNumber: _flight.text.trim(),
      ),
    );
    widget.onRouteIdentityChanged?.call();
  }

  void _swap() {
    final origin = widget.pickup.value;
    widget.pickup.acceptCopy(widget.dropoff.value);
    widget.dropoff.acceptCopy(origin);
    if (_kind != CompanyTripRouteKind.address) {
      widget.onRideOptionsChanged(
        companyTripRouteOptionsAfterSwap(
          current: rideOptions.copyWith(flightNumber: _flight.text.trim()),
        ),
      );
    }
    widget.onRouteIdentityChanged?.call();
  }

  void _applyAirport(AirportCatalogAirport airport) {
    final value = companyAirportAddressValue(airport);
    if (_kind == CompanyTripRouteKind.fromAirport) {
      widget.pickup.acceptCopy(value);
    } else {
      widget.dropoff.acceptCopy(value);
    }
    widget.onRideOptionsChanged(
      rideOptions.copyWith(
        service: 'airport',
        airportIata: airport.iata,
        airportCountry: airport.countryCode,
        flightNumber: _flight.text.trim(),
      ),
    );
    widget.onRouteIdentityChanged?.call();
  }

  @override
  Widget build(BuildContext context) {
    final kind = _kind;
    final airport = _airport;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ChoiceChip(
              key: kCompanyTripRouteAddressKey,
              label: Text(kCompanyTripRouteAddress.of(language)),
              selected: kind == CompanyTripRouteKind.address,
              onSelected: (_) => _setKind(CompanyTripRouteKind.address),
            ),
            ChoiceChip(
              key: kCompanyTripRouteToAirportKey,
              label: Text(kCompanyCustomerQuoteToAirport.of(language)),
              selected: kind == CompanyTripRouteKind.toAirport,
              onSelected: (_) => _setKind(CompanyTripRouteKind.toAirport),
            ),
            ChoiceChip(
              key: kCompanyTripRouteFromAirportKey,
              label: Text(kCompanyCustomerQuoteFromAirport.of(language)),
              selected: kind == CompanyTripRouteKind.fromAirport,
              onSelected: (_) => _setKind(CompanyTripRouteKind.fromAirport),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            key: kCompanyTripRouteSwapKey,
            onPressed: _swap,
            icon: const Icon(Icons.swap_vert),
            label: Text(kCompanyTripRouteSwap.of(language)),
          ),
        ),
        const SizedBox(height: 8),
        if (kind != CompanyTripRouteKind.fromAirport)
          CompanyAddressField(
            controller: pickup,
            label: pickupLabel ?? kCompanyCustomerQuotePickup.of(language),
            language: language,
            inputKey: pickupInputKey,
            savedAddresses: savedAddresses,
          ),
        if (kind != CompanyTripRouteKind.address) ...[
          if (kind == CompanyTripRouteKind.fromAirport) ...[
            CompanyAirportSearchField(
              language: language,
              selected: airport,
              onSelected: _applyAirport,
            ),
            const SizedBox(height: 16),
            CompanyAddressField(
              controller: dropoff,
              label: dropoffLabel ?? kCompanyCustomerQuoteDropoff.of(language),
              language: language,
              inputKey: dropoffInputKey,
              savedAddresses: savedAddresses,
            ),
          ] else ...[
            const SizedBox(height: 16),
            CompanyAirportSearchField(
              language: language,
              selected: airport,
              onSelected: _applyAirport,
            ),
          ],
          const SizedBox(height: 16),
          TextField(
            key: kCompanyRideFlightKey,
            controller: _flight,
            textCapitalization: TextCapitalization.characters,
            scrollPadding: const EdgeInsets.fromLTRB(20, 20, 20, 220),
            decoration: InputDecoration(
              labelText: kCompanyCustomerQuoteFlight.of(language),
            ),
            onChanged: (text) => widget.onRideOptionsChanged(
              rideOptions.copyWith(flightNumber: text.trim()),
            ),
          ),
          const SizedBox(height: 16),
          CompanyDateTimeFields(
            fieldId: 'ride_flight',
            language: language,
            value: companyFormDateTimeFromIso(rideOptions.flightAt),
            dateLabel: kind == CompanyTripRouteKind.fromAirport
                ? kCompanyCustomerQuoteFlightAtInbound.of(language)
                : kCompanyCustomerQuoteFlightAtOutbound.of(language),
            onChanged: (next) => widget.onRideOptionsChanged(
              rideOptions.copyWith(
                flightAt: next == null ? '' : companyFormIsoFromLocal(next),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            kCompanyFixedPricesTimezone.of(language),
            softWrap: true,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (kind == CompanyTripRouteKind.fromAirport) ...[
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              isExpanded: true,
              initialValue: rideOptions.pickupArrangement.isEmpty
                  ? 'scheduled'
                  : rideOptions.pickupArrangement,
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
              onChanged: (next) => widget.onRideOptionsChanged(
                rideOptions.copyWith(pickupArrangement: next ?? 'scheduled'),
              ),
            ),
            if (rideOptions.pickupArrangement == 'after_landing') ...[
              const SizedBox(height: 16),
              TextFormField(
                initialValue: rideOptions.pickupAfterMin == 0
                    ? ''
                    : '${rideOptions.pickupAfterMin}',
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: kCompanyCustomerQuotePickupAfterLanding.of(
                    language,
                  ),
                ),
                onChanged: (text) => widget.onRideOptionsChanged(
                  rideOptions.copyWith(
                    pickupAfterMin: (int.tryParse(text.trim()) ?? 0).clamp(
                      0,
                      240,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ] else ...[
          const SizedBox(height: 16),
          CompanyAddressField(
            controller: dropoff,
            label: dropoffLabel ?? kCompanyCustomerQuoteDropoff.of(language),
            language: language,
            inputKey: dropoffInputKey,
            savedAddresses: savedAddresses,
          ),
        ],
        if (showReturnAirportFields &&
            companyTripRouteKindIsAirport(kind)) ...[
          const SizedBox(height: 20),
          Text(
            kCompanyCustomerQuoteReturnAirport.of(language),
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          CompanyAirportSearchField(
            fieldKey: const Key('company_airport_search_return'),
            language: language,
            selected: airportByIata(
              rideOptions.returnAirportIata.isEmpty
                  ? rideOptions.airportIata
                  : rideOptions.returnAirportIata,
            ),
            onSelected: (airport) => widget.onRideOptionsChanged(
              rideOptions.copyWith(returnAirportIata: airport.iata),
            ),
          ),
          const SizedBox(height: 16),
          TextFormField(
            initialValue: rideOptions.returnFlightNumber,
            textCapitalization: TextCapitalization.characters,
            decoration: InputDecoration(
              labelText: kCompanyCustomerQuoteFlight.of(language),
            ),
            onChanged: (text) => widget.onRideOptionsChanged(
              rideOptions.copyWith(returnFlightNumber: text.trim()),
            ),
          ),
          const SizedBox(height: 16),
          CompanyDateTimeFields(
            fieldId: 'ride_return_flight',
            language: language,
            value: companyFormDateTimeFromIso(rideOptions.returnFlightAt),
            dateLabel: kCompanyCustomerQuoteFlightAtInbound.of(language),
            onChanged: (next) => widget.onRideOptionsChanged(
              rideOptions.copyWith(
                returnFlightAt:
                    next == null ? '' : companyFormIsoFromLocal(next),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
