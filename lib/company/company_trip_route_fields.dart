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
import 'package:fluxidi_tracking/company/company_agenda_labels.dart';
import 'package:fluxidi_tracking/company/company_plan_airport_cards.dart';
import 'package:fluxidi_tracking/company/company_plan_ride_mode.dart';
import 'package:fluxidi_tracking/company/company_plan_when.dart';
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
    this.showRouteKindChips = true,
    this.showAirportDestinationCards = false,
    this.hideAddressKindChip = false,
    this.pickupLocal,
    this.whenNow = true,
    this.routeDurationMin,
    this.showFlightBlock = true,
    this.showGroundAddresses = true,
    this.betweenEndpoints,
    this.sectionTitle,
    this.onApplySuggestedPickup,
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
  final bool showRouteKindChips;
  final bool showAirportDestinationCards;
  final bool hideAddressKindChip;
  final DateTime? pickupLocal;
  final bool whenNow;
  final int? routeDurationMin;
  final bool showFlightBlock;
  final bool showGroundAddresses;
  final Widget? betweenEndpoints;
  final String? sectionTitle;
  final ValueChanged<DateTime>? onApplySuggestedPickup;

  @override
  State<CompanyTripRouteFields> createState() => _CompanyTripRouteFieldsState();
}

const Key kCompanyPlanAirportSummaryKey = Key('company_plan_airport_summary');

class _CompanyTripRouteFieldsState extends State<CompanyTripRouteFields> {
  late final TextEditingController _flight;
  bool _choseOtherAirport = false;

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
  bool get showRouteKindChips => widget.showRouteKindChips;
  bool get showAirportDestinationCards => widget.showAirportDestinationCards;
  bool get hideAddressKindChip => widget.hideAddressKindChip;
  DateTime? get pickupLocal => widget.pickupLocal;
  bool get whenNow => widget.whenNow;
  int? get routeDurationMin => widget.routeDurationMin;
  bool get showFlightBlock => widget.showFlightBlock;
  bool get showGroundAddresses => widget.showGroundAddresses;

  bool get _featuredAirportSelected =>
      showAirportDestinationCards &&
      companyPlanFeaturedAirportIataContains(rideOptions.airportIata);

  bool get _showAirportSearch {
    if (!companyTripRouteKindIsAirport(_kind)) return false;
    if (!showAirportDestinationCards) return true;
    return _choseOtherAirport;
  }

  bool get _showFlightFields {
    if (!companyTripRouteKindIsAirport(_kind)) return false;
    if (!showAirportDestinationCards) return true;
    return _airport != null || rideOptions.airportIata.trim().isNotEmpty;
  }

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
    final airport = airportByIata(
      rideOptions.airportIata,
      countryCode: rideOptions.airportCountry.isEmpty
          ? null
          : rideOptions.airportCountry,
    );
    if (airport != null && companyTripRouteKindIsAirport(next)) {
      companyTripApplyAirportEndpoint(
        kind: next,
        airport: airport,
        applyPickup: widget.pickup.acceptCopy,
        applyDropoff: widget.dropoff.acceptCopy,
      );
      companyTripClearOppositeAirportEndpoint(
        kind: next,
        airport: airport,
        pickup: widget.pickup.value,
        dropoff: widget.dropoff.value,
        clearPickup: widget.pickup.clear,
        clearDropoff: widget.dropoff.clear,
      );
    }
    widget.onRouteIdentityChanged?.call();
  }

  void _clearAirportEndpoint() {
    if (_kind == CompanyTripRouteKind.fromAirport) {
      pickup.clear();
      return;
    }
    if (_kind == CompanyTripRouteKind.toAirport) {
      dropoff.clear();
    }
  }

  void _selectFeaturedAirport(String iata) {
    _choseOtherAirport = false;
    final record = companyPlanAirportCatalogRecord(iata);
    if (record != null) {
      _applyAirport(record);
      return;
    }
    _clearAirportEndpoint();
    widget.onRideOptionsChanged(
      rideOptions.copyWith(
        service: 'airport',
        airportIata: iata.trim().toUpperCase(),
        airportCountry: '',
        flightNumber: _flight.text.trim(),
      ),
    );
    widget.onRouteIdentityChanged?.call();
  }

  void _selectOtherAirport() {
    _choseOtherAirport = true;
    _clearAirportEndpoint();
    widget.onRideOptionsChanged(
      rideOptions.copyWith(
        service: 'airport',
        airportIata: '',
        airportCountry: '',
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
    _choseOtherAirport = !companyPlanFeaturedAirportIataContains(airport.iata);
    companyTripApplyAirportEndpoint(
      kind: _kind == CompanyTripRouteKind.address
          ? CompanyTripRouteKind.toAirport
          : _kind,
      airport: airport,
      applyPickup: widget.pickup.acceptCopy,
      applyDropoff: widget.dropoff.acceptCopy,
    );
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

  Widget _groundAddress({
    required LimousineAddressFieldController controller,
    required String? label,
    required Key? inputKey,
    required String fallbackLabel,
    bool isPickupField = false,
  }) {
    return CompanyAddressField(
      controller: controller,
      label: label ?? fallbackLabel,
      language: language,
      inputKey: inputKey,
      savedAddresses: savedAddresses,
      isPickupField: isPickupField,
    );
  }

  List<Widget> _flightBlock(BuildContext context, CompanyTripRouteKind kind) {
    if (!_showFlightFields) return const <Widget>[];
    final suggested = kind == CompanyTripRouteKind.toAirport
        ? companyPlanSuggestedToAirportPickup(
            flightAt: rideOptions.flightAt,
            durationMin: routeDurationMin,
            arrivalMarginMin: rideOptions.arrivalMarginMin,
          )
        : companyPlanSuggestedFromAirportPickup(
            flightAt: rideOptions.flightAt,
            pickupAfterMin: rideOptions.pickupAfterMin,
          );
    final latePickup = kind == CompanyTripRouteKind.toAirport &&
        companyPlanFlightDepartsBeforePickup(
          flightAt: rideOptions.flightAt,
          pickupLocal: pickupLocal,
          whenNow: whenNow,
        );
    return <Widget>[
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
        timeLabel: kind == CompanyTripRouteKind.fromAirport
            ? kCompanyCustomerQuoteFlightTimeInbound.of(language)
            : kCompanyCustomerQuoteFlightTimeOutbound.of(language),
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
      if (kind == CompanyTripRouteKind.toAirport) ...[
        const SizedBox(height: 16),
        TextFormField(
          key: const Key('company_plan_arrival_margin'),
          initialValue: '${rideOptions.arrivalMarginMin}',
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: kCompanyCustomerQuoteArrivalMargin.of(language),
          ),
          onChanged: (text) => widget.onRideOptionsChanged(
            rideOptions.copyWith(
              arrivalMarginMin: (int.tryParse(text.trim()) ??
                      kCompanyPlanDefaultAirportArrivalMarginMin)
                  .clamp(0, 180),
            ),
          ),
        ),
      ],
      if (suggested != null) ...[
        const SizedBox(height: 8),
        Text(
          kCompanyAgendaSuggestedPickup
              .of(language)
              .replaceAll('{time}', companyPlanFormatClock(suggested)),
          key: const Key('company_plan_suggested_pickup'),
          style: Theme.of(context).textTheme.bodySmall,
        ),
        if (widget.onApplySuggestedPickup != null)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              key: const Key('company_plan_apply_suggested_pickup'),
              onPressed: () => widget.onApplySuggestedPickup!(suggested),
              child: Text(
                kCompanyCustomerQuoteApplySuggestedPickup.of(language),
              ),
            ),
          ),
      ],
      if (latePickup) ...[
        const SizedBox(height: 8),
        Text(
          kCompanyAgendaFlightAfterPickup.of(language),
          key: const Key('company_plan_flight_after_pickup'),
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      ],
      if (kind == CompanyTripRouteKind.fromAirport) ...[
        const SizedBox(height: 8),
        Text(
          kCompanyAgendaLandingNotPickup.of(language),
          style: Theme.of(context).textTheme.bodySmall,
        ),
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
              child: Text(kCompanyCustomerQuotePickupScheduled.of(language)),
            ),
            DropdownMenuItem(
              value: 'after_landing',
              child: Text(kCompanyCustomerQuotePickupAfterLanding.of(language)),
            ),
          ],
          onChanged: (next) => widget.onRideOptionsChanged(
            rideOptions.copyWith(pickupArrangement: next ?? 'scheduled'),
          ),
        ),
        const SizedBox(height: 16),
        TextFormField(
          key: const Key('company_plan_pickup_after_min'),
          initialValue: rideOptions.pickupAfterMin == 0
              ? ''
              : '${rideOptions.pickupAfterMin}',
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: kCompanyCustomerQuotePickupAfterLanding.of(language),
          ),
          onChanged: (text) => widget.onRideOptionsChanged(
            rideOptions.copyWith(
              pickupAfterMin: (int.tryParse(text.trim()) ?? 0).clamp(0, 240),
            ),
          ),
        ),
      ],
    ];
  }

  @override
  Widget build(BuildContext context) {
    final kind = _kind;
    final airport = _airport;
    final compactAirport = showAirportDestinationCards &&
        companyTripRouteKindIsAirport(kind);
    final hideAirportEndpoint = companyTripRouteKindIsAirport(kind) &&
        rideOptions.airportIata.trim().isNotEmpty;
    final showPickupField = showGroundAddresses &&
        (kind == CompanyTripRouteKind.address ||
            kind == CompanyTripRouteKind.toAirport ||
            (kind == CompanyTripRouteKind.fromAirport &&
                !compactAirport &&
                !hideAirportEndpoint));
    final showDropoffField = showGroundAddresses &&
        (kind == CompanyTripRouteKind.address ||
            kind == CompanyTripRouteKind.fromAirport ||
            (kind == CompanyTripRouteKind.toAirport &&
                !compactAirport &&
                !hideAirportEndpoint));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if ((widget.sectionTitle ?? '').trim().isNotEmpty) ...[
          Text(
            widget.sectionTitle!.trim(),
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
        ],
        if (showRouteKindChips) ...[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (!hideAddressKindChip)
                ChoiceChip(
                  key: kCompanyTripRouteAddressKey,
                  label: Text(kCompanyTripRouteAddress.of(language)),
                  selected: kind == CompanyTripRouteKind.address,
                  onSelected: (_) => _setKind(CompanyTripRouteKind.address),
                ),
              ChoiceChip(
                key: kCompanyTripRouteToAirportKey,
                avatar: const Icon(kCompanyPlanAirportModeIcon, size: 16),
                label: Text(kCompanyCustomerQuoteToAirport.of(language)),
                selected: kind == CompanyTripRouteKind.toAirport,
                onSelected: (_) => _setKind(CompanyTripRouteKind.toAirport),
              ),
              ChoiceChip(
                key: kCompanyTripRouteFromAirportKey,
                avatar: const Icon(Icons.flight_land, size: 16),
                label: Text(
                  hideAddressKindChip
                      ? kCompanyAgendaFromAirport.of(language)
                      : kCompanyCustomerQuoteFromAirport.of(language),
                ),
                selected: kind == CompanyTripRouteKind.fromAirport,
                onSelected: (_) => _setKind(CompanyTripRouteKind.fromAirport),
              ),
            ],
          ),
          const SizedBox(height: 12),
        ],
        if (compactAirport) ...[
          CompanyPlanAirportDestinationCards(
            language: language,
            selectedIata: rideOptions.airportIata,
            onSelectedIata: _selectFeaturedAirport,
            onSelectedOther: _selectOtherAirport,
          ),
          const SizedBox(height: 12),
        ],
        if (_featuredAirportSelected && airport != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              '✈ ${airport.displayLabel}',
              key: kCompanyPlanAirportSummaryKey,
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
        if (_showAirportSearch) ...[
          CompanyAirportSearchField(
            language: language,
            selected: airport,
            onSelected: _applyAirport,
            label: showAirportDestinationCards
                ? kCompanyAgendaSearchOtherAirport.of(language)
                : null,
          ),
          const SizedBox(height: 12),
        ],
        if (showGroundAddresses) ...[
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
        ],
        if (showPickupField)
          _groundAddress(
            controller: pickup,
            label: pickupLabel,
            inputKey: pickupInputKey,
            fallbackLabel: kCompanyCustomerQuotePickup.of(language),
            isPickupField: true,
          ),
        if (showGroundAddresses && widget.betweenEndpoints != null) ...[
          const SizedBox(height: 4),
          widget.betweenEndpoints!,
        ],
        if (showPickupField && showDropoffField && widget.betweenEndpoints == null)
          const SizedBox(height: 16),
        if (showDropoffField)
          _groundAddress(
            controller: dropoff,
            label: dropoffLabel,
            inputKey: dropoffInputKey,
            fallbackLabel: kCompanyCustomerQuoteDropoff.of(language),
          ),
        if (showFlightBlock) ..._flightBlock(context, kind),
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
            onSelected: (next) => widget.onRideOptionsChanged(
              rideOptions.copyWith(returnAirportIata: next.iata),
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
