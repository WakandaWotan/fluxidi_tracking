import 'dart:async';

import 'package:flutter/material.dart';

import '../app_config.dart';
import '../app_strings.dart';
import '../customer_theme_palette.dart';
import '../customer_theme_store.dart';
import '../airport/airport_catalog_repository.dart';
import 'limousine_accepted_booking_page.dart';
import 'limousine_accepted_booking_resume_ui.dart';
import 'limousine_accepted_booking_vault.dart';
import 'limousine_address_field.dart';
import 'limousine_address_lookup.dart';
import 'limousine_airport_transfer_fields.dart';
import 'limousine_current_location.dart';
import 'limousine_event_field.dart';
import 'limousine_event_lookup.dart';
import 'limousine_hotel_field.dart';
import 'limousine_hotel_lookup.dart';
import 'limousine_journey_scope.dart';
import 'limousine_offers.dart';
import 'limousine_transfer_endpoint.dart';
import 'limousine_customer_entry.dart';
import 'limousine_customer_quote.dart';
import 'limousine_customer_quote_api.dart';
import 'limousine_customer_quote_labels.dart';
import 'limousine_customer_status_page.dart';
import 'limousine_customer_wizard_chrome.dart';
import 'limousine_offer_binding.dart';
import 'limousine_p2d4c1a_ux.dart';
import 'limousine_provider_showroom.dart';
import 'limousine_p2d4c1c_journey.dart';
import 'limousine_quote_inbox.dart';
import 'limousine_unified_intent.dart';
import 'limousine_wizard_vehicle.dart';

class LimousineCustomerQuotePage extends StatefulWidget {
  const LimousineCustomerQuotePage({
    super.key,
    this.controller,
    this.gateway,
    this.entryEnabled,
    this.initialPublicPartnerId,
    this.initialOffer,
    this.initialVehicleId = '',
    this.initialVehicle,
    this.initialCompanyName = '',
    this.resumeRepository,
    this.placeLookup,
    this.hotelLookup,
    this.eventLookup,
    this.currentLocationPlatform,
  });

  final LimousineCustomerQuoteController? controller;
  final LimousineCustomerQuoteGateway? gateway;
  final LimousineAcceptedBookingResumeRepository? resumeRepository;
  final LimousinePlaceLookup? placeLookup;
  final LimousineHotelLookup? hotelLookup;
  final LimousineEventLookup? eventLookup;
  final LimousineCurrentLocationPlatform? currentLocationPlatform;
  final bool? entryEnabled;
  final String? initialPublicPartnerId;
  final LimousinePublishedOffer? initialOffer;
  final String initialVehicleId;
  final LimousineWizardVehicleOption? initialVehicle;
  final String initialCompanyName;

  @override
  State<LimousineCustomerQuotePage> createState() =>
      _LimousineCustomerQuotePageState();
}

class _LimousineCustomerQuotePageState extends State<LimousineCustomerQuotePage>
    with WidgetsBindingObserver {
  late final LimousineCustomerQuoteController _controller;
  late final bool _ownsController;
  late final LimousinePlaceLookup _placeLookup;
  late final bool _ownsPlaceLookup;
  late final LimousineHotelLookup _hotelLookup;
  late final bool _ownsHotelLookup;
  late final LimousineHotelFieldController _hotelField;
  late final LimousineEventLookup _eventLookup;
  late final bool _ownsEventLookup;
  late final LimousineEventFieldController _eventField;
  late final LimousineAddressFieldController _pickup;
  late final LimousineAddressFieldController _destination;
  late final LimousineAddressFieldController _returnPickup;
  late final LimousineAddressFieldController _returnDestination;
  final _postcode = TextEditingController();
  final _note = TextEditingController();
  final _occasion = TextEditingController();
  final _duration = TextEditingController();
  final List<LimousineAddressFieldController> _stops =
      <LimousineAddressFieldController>[];
  LimousineReturnTripKind _returnKind = LimousineReturnTripKind.unset;
  LimousineOfferBrowseFilter _browseFilter = LimousineOfferBrowseFilter.all;
  final List<AirportCatalogAirport> _airports = publishedAirportCatalog();
  late String _airportCountryCode;
  AirportCatalogAirport? _selectedAirport;

  bool get _entryEnabled =>
      widget.entryEnabled ?? LimousineCustomerEntryContract.isVisible;

  AppLanguage get _lang => appLanguageNotifier.value;

  String _t(LocalizedText text) => text.of(_lang);

  void _returnToCustomerStart() {
    _controller.resetAfterConfirmedSubmit();
    if (!mounted) return;
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final existing = widget.controller;
    _ownsController = existing == null;
    _controller =
        existing ??
        LimousineCustomerQuoteController(
          gateway: widget.gateway ?? HttpLimousineCustomerQuoteGateway(),
          resumeRepository: widget.resumeRepository,
        );
    _controller.addListener(_onChanged);
    _ownsPlaceLookup = widget.placeLookup == null;
    _placeLookup = widget.placeLookup ?? LimousinePlaceLookup();
    _ownsHotelLookup = widget.hotelLookup == null;
    _hotelLookup = widget.hotelLookup ?? LimousineHotelLookup();
    _hotelField = LimousineHotelFieldController(lookup: _hotelLookup);
    _ownsEventLookup = widget.eventLookup == null;
    _eventLookup = widget.eventLookup ?? LimousineEventLookup();
    _eventField = LimousineEventFieldController(lookup: _eventLookup);
    _airportCountryCode = publishedAirportCountryCodes(_airports).first;
    _pickup = _createAddressField('pickup', listen: false);
    _pickup.currentLocation = LimousineCurrentLocationResolver(
      lookup: _placeLookup,
      platform:
          widget.currentLocationPlatform ??
          const LimousineCurrentLocationPlatform(),
    );
    _destination = _createAddressField('destination', listen: false);
    _returnPickup = _createAddressField('return_pickup', listen: false);
    _returnDestination = _createAddressField(
      'return_destination',
      listen: false,
    );
    if (widget.resumeRepository != null) {
      unawaited(_controller.detectSecureResume());
    }
    final initialOffer = widget.initialOffer;
    final initialPartner = (widget.initialPublicPartnerId ?? '').trim();
    if (initialOffer != null && initialPartner.isNotEmpty) {
      _controller.applyShowroomSelection(
        publicPartnerId: initialPartner,
        offer: initialOffer,
        companyName: widget.initialCompanyName,
        vehicleId: widget.initialVehicleId,
        vehicle: widget.initialVehicle,
      );
    }
    _pickup.seedText(_controller.draft.from);
    _destination.seedText(_controller.draft.to);
    for (var i = 0; i < _controller.draft.stops.length; i++) {
      _addStop(initialText: _controller.draft.stops[i], listen: false);
    }
    _note.text = _controller.draft.customerNote;
    _occasion.text = _controller.draft.occasion;
    if (_controller.draft.roundtrip &&
        _controller.draft.returnPickupIso.trim().isNotEmpty) {
      _returnKind = LimousineReturnTripKind.later;
    }
    _hotelField.addListener(_onHotelFieldChanged);
    _eventField.addListener(_onEventFieldChanged);
    _pickup.addListener(_onAddressChanged);
    _destination.addListener(_onAddressChanged);
    _returnPickup.addListener(_onAddressChanged);
    _returnDestination.addListener(_onAddressChanged);
    for (final stop in _stops) {
      stop.addListener(_onAddressChanged);
    }
  }

  LimousineAddressFieldController _createAddressField(
    String id, {
    bool listen = true,
  }) {
    final field = LimousineAddressFieldController(
      lookup: _placeLookup,
      fieldId: id,
      language: _lang.name,
    );
    if (listen) field.addListener(_onAddressChanged);
    return field;
  }

  void _addStop({String initialText = '', bool listen = true}) {
    if (_stops.length >= 8) return;
    final field = _createAddressField('stop_${_stops.length}', listen: listen);
    if (initialText.isNotEmpty) field.seedText(initialText);
    _stops.add(field);
  }

  void _removeStop(int index) {
    if (index < 0 || index >= _stops.length) return;
    final field = _stops.removeAt(index);
    field
      ..removeListener(_onAddressChanged)
      ..dispose();
    _onAddressChanged();
  }

  void _onAddressChanged() {
    _pickup.language = _lang.name;
    _destination.language = _lang.name;
    _returnPickup.language = _lang.name;
    _returnDestination.language = _lang.name;
    _hotelField.language = _lang.name;
    _eventField.language = _lang.name;
    final proximity = _pickup.value;
    if (proximity.lat != null && proximity.lon != null) {
      _hotelField.proximityLat = proximity.lat;
      _hotelField.proximityLng = proximity.lon;
      _eventField.proximityLat = proximity.lat;
      _eventField.proximityLng = proximity.lon;
    }
    for (final stop in _stops) {
      stop.language = _lang.name;
    }
    _controller.updateDraft(_syncedDraft());
    if (mounted) setState(() {});
  }

  void _onHotelFieldChanged() {
    _applyHotelIfSelected();
  }

  void _onEventFieldChanged() {
    _applyEventIfSelected();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _controller.resumePolling();
    } else {
      _controller.pausePolling();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.removeListener(_onChanged);
    _controller.stopPolling();
    if (_ownsController) _controller.dispose();
    _postcode.dispose();
    _pickup.dispose();
    _destination.dispose();
    _returnPickup.dispose();
    _returnDestination.dispose();
    _note.dispose();
    _occasion.dispose();
    _duration.dispose();
    for (final stop in _stops) {
      stop.dispose();
    }
    if (_ownsPlaceLookup) _placeLookup.dispose();
    _hotelField.dispose();
    if (_ownsHotelLookup) _hotelLookup.dispose();
    _eventField.dispose();
    if (_ownsEventLookup) _eventLookup.dispose();
    super.dispose();
  }

  CustomerThemePalette get _palette =>
      paletteForCustomerTheme(customerThemeNotifier.value);

  LimousineUxTokens get _tokens => LimousineUxTokens.fromCustomer(_palette);

  bool get _tablet =>
      limousineQuoteInboxIsTablet(MediaQuery.sizeOf(context).shortestSide);

  LimousineRequestWizardStep get _wizardStep =>
      limousineRequestWizardStepOf(_controller.step);

  LimousineReturnTripKind get _activeReturnKind =>
      _controller.draft.roundtrip ? _returnKind : LimousineReturnTripKind.unset;

  LimousineWizardVehicleMode get _vehicleMode => limousineWizardVehicleMode(
    providerOfferLocked: _controller.providerOfferLocked,
    offer: _controller.selectedOffer,
    lockedVehicleId: _controller.vehicleLocked
        ? _controller.draft.vehicleId
        : '',
  );

  List<LimousineRequestWizardStep> get _visibleSteps =>
      limousineVisibleWizardSteps(_vehicleMode);

  List<LimousineRequestStepGap> get _gaps {
    final gaps = limousineRequestWizardGaps(
      step: _wizardStep,
      draft: _syncedDraft(),
      offer: _controller.selectedOffer,
      hasProvider: _controller.selectedProvider != null,
      pickupAddress: _pickup.value,
      destinationAddress: _destination.value,
      stopAddresses: _stops.map((stop) => stop.value).toList(growable: false),
      returnPickupAddress: _returnPickup.value,
      returnDestinationAddress: _returnDestination.value,
      returnKind: _activeReturnKind,
      waitDurationSupported: _waitSupported,
      waitMinutes: limousinePublishedOfferWaitMinutes(_controller.selectedOffer),
    );
    if (_wizardStep == LimousineRequestWizardStep.provider &&
        _vehicleMode == LimousineWizardVehicleMode.choose &&
        _controller.draft.vehicleId.trim().isEmpty) {
      return <LimousineRequestStepGap>[
        ...gaps,
        const LimousineRequestStepGap('vehicle_required'),
      ];
    }
    return gaps;
  }

  bool get _canAdvance =>
      _gaps.isEmpty && !_controller.offerScopeChanged;

  bool get _needsDuration {
    if (_controller.draft.journeyType == 'hourly_package') return true;
    final offer = _controller.selectedOffer;
    if (offer == null) return false;
    final mode = limousinePublishedPricingModeOf(offer);
    return mode == LimousinePublishedPricingMode.hourly ||
        mode == LimousinePublishedPricingMode.package;
  }

  LimousineCustomerIntentKind get _intentKind =>
      limousineCustomerIntentKindOf(_controller.selectedOffer);

  bool get _isAirportJourney =>
      limousineOfferToken(_controller.draft.journeyType) == 'airport_transfer';

  bool get _isHotelJourney =>
      limousineOfferToken(_controller.draft.journeyType) == 'hotel_transfer';

  bool get _isEventJourney =>
      limousineOfferToken(_controller.draft.journeyType) == 'event_transfer';

  bool get _waitSupported =>
      !_isEventJourney &&
      limousinePublishedOfferSupportsReturnWait(_controller.selectedOffer);

  bool get _airportIsPickup =>
      _controller.draft.airportDirection == 'from_airport';

  bool get _hotelIsPickup => _controller.draft.hotelDirection == 'from_hotel';

  LimousineTransferEndpoint? get _addressEndpointFromPickup =>
      _pickup.isRouteReady ? limousineEndpointFromAddress(_pickup.value) : null;

  LimousineTransferEndpoint? get _addressEndpointFromDestination =>
      _destination.isRouteReady
      ? limousineEndpointFromAddress(_destination.value)
      : null;

  List<Widget> _journeyEndpointFields(LimousineUxTokens tokens) {
    if (_isAirportJourney) {
      return [
        LimousineAirportTransferPanel(
          language: _lang,
          tokens: tokens,
          direction: _controller.draft.airportDirection.isEmpty
              ? 'to_airport'
              : _controller.draft.airportDirection,
          countryCode: _airportCountryCode,
          airport: _selectedAirport,
          onDirectionChanged: _onAirportDirectionChanged,
          onCountryChanged: _onAirportCountryChanged,
          onAirportChanged: _onAirportSelected,
        ),
        const SizedBox(height: 12),
        if (_airportIsPickup)
          LimousineAddressField(
            controller: _destination,
            label: _t(kLimousineCustomerTo),
            tokens: tokens,
            language: _lang,
          )
        else
          LimousineAddressField(
            controller: _pickup,
            label: _t(kLimousineCustomerFrom),
            tokens: tokens,
            language: _lang,
            showCurrentLocation: true,
          ),
      ];
    }
    if (_isHotelJourney) {
      final toHotel = !_hotelIsPickup;
      return [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            LimousineDirectionChip(
              key: kLimousineHotelToDirectionKey,
              tokens: tokens,
              label: kLimousineHotelToDirection.of(_lang),
              selected: toHotel,
              onTap: () => _onHotelDirectionChanged('to_hotel'),
            ),
            LimousineDirectionChip(
              key: kLimousineHotelFromDirectionKey,
              tokens: tokens,
              label: kLimousineHotelFromDirection.of(_lang),
              selected: !toHotel,
              onTap: () => _onHotelDirectionChanged('from_hotel'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        LimousineHotelField(
          controller: _hotelField,
          label: kLimousineHotelFieldLabel.of(_lang),
          tokens: tokens,
          language: _lang,
        ),
        if (_hotelIsPickup)
          LimousineAddressField(
            controller: _destination,
            label: _t(kLimousineCustomerTo),
            tokens: tokens,
            language: _lang,
          )
        else
          LimousineAddressField(
            controller: _pickup,
            label: _t(kLimousineCustomerFrom),
            tokens: tokens,
            language: _lang,
            showCurrentLocation: true,
          ),
      ];
    }
    if (_isEventJourney) {
      return [
        LimousineAddressField(
          controller: _pickup,
          label: _t(kLimousineCustomerFrom),
          tokens: tokens,
          language: _lang,
          showCurrentLocation: true,
        ),
        LimousineEventField(
          controller: _eventField,
          tokens: tokens,
          language: _lang,
        ),
      ];
    }
    return [
      LimousineAddressField(
        controller: _pickup,
        label: _t(kLimousineCustomerFrom),
        tokens: tokens,
        language: _lang,
        showCurrentLocation: true,
      ),
      LimousineAddressField(
        controller: _destination,
        label: _t(kLimousineCustomerTo),
        tokens: tokens,
        language: _lang,
      ),
    ];
  }

  void _onJourneyTypeSelected(String type) {
    final token = limousineOfferToken(type);
    if (!limousineJourneyTypeAllowedByPublishedScope(
      journeyTypes: _controller.selectedOffer?.journeyTypes,
      journeyType: token,
    )) {
      return;
    }
    var next = _syncedDraft().copyWith(journeyType: token);
    if (token == 'airport_transfer') {
      next = next.copyWith(
        airportDirection: next.airportDirection.isEmpty
            ? 'to_airport'
            : next.airportDirection,
      );
      if (_selectedAirport != null) {
        _applyAirportToDraft(next, _selectedAirport!);
        return;
      }
    } else if (token == 'hotel_transfer') {
      next = next.copyWith(
        hotelDirection: next.hotelDirection.isEmpty
            ? 'to_hotel'
            : next.hotelDirection,
      );
    } else if (token == 'event_transfer') {
      next = next.copyWith(
        fromEndpoint: _addressEndpointFromPickup,
        toEndpoint: _eventField.selected,
        airportDirection: '',
        hotelDirection: '',
      );
    } else {
      next = next.copyWith(
        fromEndpoint: _addressEndpointFromPickup,
        toEndpoint: _addressEndpointFromDestination,
        airportDirection: '',
        hotelDirection: '',
      );
    }
    _controller.updateDraft(next);
    if (mounted) setState(() {});
  }

  void _onAirportDirectionChanged(String direction) {
    final airport = _selectedAirport;
    var next = _syncedDraft().copyWith(airportDirection: direction);
    if (airport != null) {
      _applyAirportToDraft(next, airport);
      return;
    }
    _controller.updateDraft(next);
    if (mounted) setState(() {});
  }

  void _onAirportCountryChanged(String countryCode) {
    final cleared = clearIncompatibleAirportOnCountryChange(
      current: _syncedDraft().itinerary,
      countryCode: countryCode,
      airports: _airports,
    );
    final stillValid = airportByIata(
      _selectedAirport?.iata ?? '',
      countryCode: countryCode,
      airports: _airports,
    );
    setState(() {
      _airportCountryCode = countryCode;
      _selectedAirport = stillValid;
    });
    _controller.updateDraft(
      _syncedDraft().copyWith(
        fromEndpoint: cleared.from,
        toEndpoint: cleared.to,
      ),
    );
  }

  void _onAirportSelected(AirportCatalogAirport airport) {
    setState(() {
      _airportCountryCode = airport.countryCode;
      _selectedAirport = airport;
    });
    _applyAirportToDraft(_syncedDraft(), airport);
  }

  void _applyAirportToDraft(
    LimousineQuoteCreateDraft draft,
    AirportCatalogAirport airport,
  ) {
    final direction = draft.airportDirection == 'from_airport'
        ? 'from_airport'
        : 'to_airport';
    final other = direction == 'to_airport'
        ? _addressEndpointFromPickup
        : _addressEndpointFromDestination;
    final next = applyAirportDirection(
      direction: direction,
      airport: airport,
      other: other,
      current: draft.itinerary,
    );
    _controller.updateDraft(
      draft.copyWith(
        from: next.from?.routeText ?? draft.from,
        to: next.to?.routeText ?? draft.to,
        fromEndpoint: next.from,
        toEndpoint: next.to,
        airportDirection: next.airportDirection,
      ),
    );
    if (mounted) setState(() {});
  }

  void _onHotelDirectionChanged(String direction) {
    _controller.updateDraft(_syncedDraft().copyWith(hotelDirection: direction));
    _applyHotelIfSelected();
  }

  void _applyHotelIfSelected() {
    final hotel = _hotelField.selected;
    if (hotel == null) {
      if (mounted) setState(() {});
      return;
    }
    final draft = _syncedDraft();
    final direction = draft.hotelDirection == 'from_hotel'
        ? 'from_hotel'
        : 'to_hotel';
    final other = direction == 'to_hotel'
        ? _addressEndpointFromPickup
        : _addressEndpointFromDestination;
    final next = applyHotelDirection(
      direction: direction,
      hotel: hotel,
      other: other,
      current: draft.itinerary,
    );
    _controller.updateDraft(
      draft.copyWith(
        from: next.from?.routeText ?? draft.from,
        to: next.to?.routeText ?? draft.to,
        fromEndpoint: next.from,
        toEndpoint: next.to,
        hotelDirection: next.hotelDirection,
      ),
    );
    if (mounted) setState(() {});
  }

  void _applyEventIfSelected() {
    final venue = _eventField.selected;
    if (venue == null) {
      if (mounted) setState(() {});
      return;
    }
    final draft = _syncedDraft();
    _controller.updateDraft(
      draft.copyWith(
        from: _addressEndpointFromPickup?.routeText ?? draft.from,
        to: venue.routeText,
        fromEndpoint: _addressEndpointFromPickup,
        toEndpoint: venue,
        airportDirection: '',
        hotelDirection: '',
      ),
    );
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (!_entryEnabled && widget.controller == null && widget.gateway == null) {
      return const SizedBox.shrink();
    }
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final tokens = _tokens;
    return Theme(
      data: limousineUxThemeData(tokens),
      child: Scaffold(
        key: kLimousineCustomerQuotePageKey,
        backgroundColor: tokens.background,
        appBar: AppBar(
          backgroundColor: tokens.surface,
          foregroundColor: tokens.onSurface,
          title: Text(_t(kLimousineCustomerPageTitle)),
        ),
        body: SafeArea(
          child: KeyedSubtree(
            key: _tablet
                ? kLimousineCustomerTabletLayoutKey
                : kLimousineCustomerPhoneLayoutKey,
            child: _pageBody(reduceMotion, tokens),
          ),
        ),
      ),
    );
  }

  Widget _pageBody(bool reduceMotion, LimousineUxTokens tokens) {
    final width = MediaQuery.sizeOf(context).width;
    final columnWidth = limousineRequestWizardContentWidth(width);
    final draftMode =
        _controller.phase != LimousineCustomerQuotePhase.unavailable &&
        _controller.request == null &&
        _controller.bookingRequestId.isEmpty &&
        !(_controller.restoredFromSecureResume && _controller.handoff != null);
    return Column(
      key: kLimousineRequestWizardKey,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              width: columnWidth,
              child: Column(
                children: [
                  LimousineWizardHero(
                    tokens: tokens,
                    title: _t(limousineRequestWizardHeroTitle(_wizardStep)),
                    subtitle: _t(limousineRequestWizardHeroBody(_wizardStep)),
                    compact: !_tablet || reduceMotion,
                  ),
                  const SizedBox(height: 12),
                  if (draftMode)
                    LimousineWizardStepper(
                      tokens: tokens,
                      language: _lang,
                      current: _wizardStep,
                      steps: _visibleSteps,
                      stepLabel: (step) =>
                          limousineVisibleWizardStepLabel(step, _vehicleMode),
                      onOpenPast: (step) {
                        if (!_visibleSteps.contains(step)) return;
                        _controller.goTo(limousineCustomerQuoteStepOf(step));
                      },
                    ),
                ],
              ),
            ),
          ),
        ),
        Expanded(
          child: Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              width: columnWidth,
              child: ListView(
                key: kLimousineRequestWizardScrollKey,
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                children: [
                  if (_controller.restoredFromSecureResume &&
                      _controller.handoff != null) ...[
                    LimousineAcceptedBookingContinueAction(
                      language: _lang,
                      onContinue: () => openLimousineAcceptedBookingReview(
                        context,
                        quoteController: _controller,
                        entryEnabled: _entryEnabled,
                      ),
                      onDiscard: () =>
                          unawaited(_controller.discardSecureResume()),
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (_controller.offerScopeChanged) ...[
                    LimousineOfferScopeChangedBanner(
                      tokens: tokens,
                      language: _lang,
                      onRefresh: _controller.refreshOfferScopeAfterUserAck,
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (_controller.safeError.isNotEmpty &&
                      _controller.safeError != 'unavailable' &&
                      _controller.safeError != 'offer_scope_changed' &&
                      _controller.request == null)
                    Padding(
                      key: kLimousineQuoteSubmitErrorKey,
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _t(limousineSubmitErrorLabel(_controller.safeError)),
                            style: TextStyle(
                              color: tokens.danger,
                              height: 1.35,
                            ),
                          ),
                          if (_controller.lastRequestId.isNotEmpty ||
                              _controller.lastHttpStatus > 0)
                            Padding(
                              key: kLimousineQuoteSubmitTraceKey,
                              padding: const EdgeInsets.only(top: 6),
                              child: Text(
                                [
                                  if (_controller.lastHttpStatus > 0)
                                    'HTTP ${_controller.lastHttpStatus}',
                                  if (_controller.lastSubmitErrorCode.isNotEmpty)
                                    _controller.lastSubmitErrorCode,
                                  if (_controller.lastErrorStage.isNotEmpty)
                                    _controller.lastErrorStage,
                                  if (_controller.lastRequestId.isNotEmpty)
                                    '${_t(kLimousineSubmitTechnicalRef)}: ${_controller.lastRequestId}',
                                ].join(' · '),
                                style: TextStyle(
                                  color: tokens.muted,
                                  fontSize: 12,
                                  height: 1.35,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  if (_controller.phase ==
                          LimousineCustomerQuotePhase.unavailable ||
                      _controller.safeError == 'unavailable')
                    LimousineCustomerUnavailableBanner(language: _lang)
                  else if (_controller.bookingRequestId.isNotEmpty)
                    Padding(
                      key: kLimousineQuoteSubmitConfirmationKey,
                      padding: const EdgeInsets.only(top: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _t(kLimousineBookingSubmittedTitle),
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 18,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(_t(kLimousineBookingSubmittedBody)),
                          const SizedBox(height: 10),
                          Text(
                            '${_t(kLimousineQuoteSubmittedReference)}: ${_controller.bookingRequestId}',
                            key: kLimousineQuoteSubmitReferenceKey,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 12),
                          FilledButton(
                            key: kLimousineQuoteSubmittedHomeKey,
                            onPressed: _returnToCustomerStart,
                            child: Text(_t(kLimousineQuoteSubmittedHome)),
                          ),
                        ],
                      ),
                    )
                  else if (_controller.request != null)
                    LimousineCustomerStatusView(
                      controller: _controller,
                      language: _lang,
                      palette: _palette,
                      onReturnToCustomerStart: _returnToCustomerStart,
                    )
                  else if (!(_controller.restoredFromSecureResume &&
                      _controller.handoff != null))
                    _stepCard(tokens),
                ],
              ),
            ),
          ),
        ),
        if (draftMode)
          LimousineWizardFooter(
            tokens: tokens,
            language: _lang,
            step: _wizardStep,
            canAdvance: _canAdvance,
            submitting: _controller.submitting,
            hint: _gaps.isEmpty
                ? ''
                : _t(limousineRequestGapLabel(_gaps.first.code)),
            onBack: _wizardStep == LimousineRequestWizardStep.journey
                ? null
                : _goBack,
            onNext: () => unawaited(_goNext()),
            maxWidth: columnWidth,
            allowSubmitWhenInvalid:
                _wizardStep == LimousineRequestWizardStep.review,
            primaryAction: _wizardStep == LimousineRequestWizardStep.review &&
                    _intentKind == LimousineCustomerIntentKind.bookingRequest
                ? kLimousineReviewSubmitBooking
                : limousineWizardPrimaryAction(_wizardStep, _vehicleMode),
          ),
      ],
    );
  }

  Widget _stepCard(LimousineUxTokens tokens) {
    return Card(
      key: kLimousineRequestWizardColumnKey,
      color: tokens.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: tokens.border),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: _draftSteps(),
        ),
      ),
    );
  }

  List<Widget> _draftSteps() {
    switch (_wizardStep) {
      case LimousineRequestWizardStep.journey:
        return _journeyStep();
      case LimousineRequestWizardStep.provider:
        return _providerStep();
      case LimousineRequestWizardStep.details:
        return _detailsStep();
      case LimousineRequestWizardStep.review:
        return _reviewStep();
    }
  }

  List<Widget> _journeyStep() {
    final tokens = _tokens;
    return [
      Text(
        _t(kLimousineJourneyRouteCardTitle),
        style: TextStyle(
          color: tokens.onSurface,
          fontWeight: FontWeight.w800,
          fontSize: 16,
        ),
      ),
      const SizedBox(height: 8),
      ..._journeyEndpointFields(tokens),
      Text(
        _t(kLimousineJourneyTypeCardTitle),
        style: TextStyle(color: tokens.onSurface, fontWeight: FontWeight.w800),
      ),
      const SizedBox(height: 8),
      LimousinePublishedJourneyTypeScope(
        tokens: tokens,
        language: _lang,
        selected: _controller.draft.journeyType,
        wide: _tablet,
        allowedTypes: _controller.publishedJourneyScopeForSelectedOffer(),
        onSelected: _onJourneyTypeSelected,
      ),
      const SizedBox(height: 12),
      LimousineDateTimeTile(
        key: kLimousineOutboundPickupTimeKey,
        tokens: tokens,
        label: _t(
          _isEventJourney
              ? kLimousineCustomerDesiredArrivalTime
              : kLimousineCustomerPickupTime,
        ),
        value: limousineCustomerFormatDateTime(
          _controller.draft.scheduledPickupIso,
          _lang,
        ),
        placeholder: _t(kLimousineChooseDateTime),
        onTap: () => _pickSchedule(returnTrip: false),
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(_t(kLimousineCustomerRoundtrip)),
        value: _controller.draft.roundtrip,
        onChanged: _setRoundtrip,
      ),
      if (_controller.draft.roundtrip) _returnCard(tokens),
      if (_needsDuration)
        _field(
          _t(kLimousineCustomerDuration),
          _duration,
          onChanged: (value) {
            _controller.updateDraft(
              _syncedDraft().copyWith(
                requestedDurationMinutes: int.tryParse(value.trim()),
              ),
            );
          },
        ),
      ..._stopFields(),
      Padding(
        padding: const EdgeInsets.only(top: 4, bottom: 8),
        child: Text(
          _t(kLimousineJourneySecureNote),
          style: TextStyle(color: tokens.muted, fontSize: 12.5),
        ),
      ),
    ];
  }

  Widget _returnCard(LimousineUxTokens tokens) {
    final later = _returnKind == LimousineReturnTripKind.later;
    final outbound = DateTime.tryParse(_controller.draft.scheduledPickupIso);
    final ret = DateTime.tryParse(_controller.draft.returnPickupIso);
    final orderError =
        later && outbound != null && ret != null && !ret.isAfter(outbound)
        ? _t(kLimousineGapReturnOrder)
        : null;
    return Container(
      key: kLimousineReturnCardKey,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: tokens.surfaceAlt,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: tokens.gold.withOpacity(0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            _t(kLimousineCustomerRoundtrip),
            style: TextStyle(
              color: tokens.onSurface,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${_returnPickup.value.routeText.isEmpty ? _destination.value.routeText : _returnPickup.value.routeText}  ·  ${_returnDestination.value.routeText.isEmpty ? _pickup.value.routeText : _returnDestination.value.routeText}',
            style: TextStyle(color: tokens.muted, height: 1.35),
          ),
          const SizedBox(height: 10),
          LimousineAddressField(
            controller: _returnPickup,
            label: _t(kLimousineCustomerReturnPickupAddress),
            tokens: tokens,
            language: _lang,
          ),
          LimousineAddressField(
            controller: _returnDestination,
            label: _t(kLimousineCustomerReturnDestinationAddress),
            tokens: tokens,
            language: _lang,
          ),
          Text(
            _t(kLimousineReturnWhen),
            style: TextStyle(
              color: tokens.onSurface,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          LimousineReturnModeCard(
            key: kLimousineReturnWaitModeKey,
            tokens: tokens,
            title: _t(kLimousineReturnWaitTitle),
            body: _t(kLimousineReturnWaitBody),
            selected: _returnKind == LimousineReturnTripKind.wait,
            enabled: _waitSupported && !_isEventJourney,
            onTap: _waitSupported && !_isEventJourney
                ? () {
                    setState(() {
                      _returnKind = LimousineReturnTripKind.wait;
                    });
                    _controller.updateDraft(_syncedDraft());
                  }
                : null,
            footer: _waitSupported
                ? null
                : Text(
                    _t(kLimousineReturnWaitUnavailable),
                    style: TextStyle(color: tokens.danger, fontSize: 12.5),
                  ),
          ),
          const SizedBox(height: 8),
          LimousineReturnModeCard(
            key: kLimousineReturnLaterModeKey,
            tokens: tokens,
            title: _t(kLimousineReturnLaterTitle),
            body: _t(kLimousineReturnLaterBody),
            selected: later,
            enabled: true,
            onTap: () {
              setState(() {
                _returnKind = LimousineReturnTripKind.later;
              });
              _controller.updateDraft(_syncedDraft());
            },
          ),
          if (later)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: LimousineDateTimeTile(
                key: kLimousineReturnPickupTimeKey,
                tokens: tokens,
                label: _t(kLimousineCustomerReturnTime),
                value: limousineCustomerFormatDateTime(
                  _controller.draft.returnPickupIso,
                  _lang,
                ),
                placeholder: _t(kLimousineChooseDateTime),
                error: orderError,
                onTap: () => _pickSchedule(returnTrip: true),
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              _t(kLimousineReturnPriceNote),
              style: TextStyle(color: tokens.muted, fontSize: 12.5),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _stopFields() {
    return [
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          key: kLimousineRequestAddStopKey,
          onPressed: _stops.length >= 8
              ? null
              : () {
                  setState(_addStop);
                },
          icon: const Icon(Icons.add),
          label: Text(_t(kLimousineCustomerAddStop)),
        ),
      ),
      for (var i = 0; i < _stops.length; i++)
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 18, right: 8),
              child: CircleAvatar(
                radius: 12,
                backgroundColor: _tokens.gold.withOpacity(0.18),
                child: Text(
                  '${i + 1}',
                  style: TextStyle(
                    color: _tokens.onSurface,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
            Expanded(
              child: LimousineAddressField(
                controller: _stops[i],
                label: '${_t(kLimousineCustomerStops)} ${i + 1}',
                tokens: _tokens,
                language: _lang,
              ),
            ),
            IconButton(
              key: limousineRequestRemoveStopKey(i),
              tooltip: _t(kLimousineRemoveStop),
              onPressed: () => _removeStop(i),
              icon: Icon(Icons.remove_circle_outline, color: _tokens.danger),
            ),
          ],
        ),
    ];
  }

  List<Widget> _providerStep() {
    final locked = _controller.providerOfferLocked;
    if (_vehicleMode == LimousineWizardVehicleMode.choose) {
      final offer = _controller.selectedOffer;
      final options = offer == null
          ? const <LimousineWizardVehicleOption>[]
          : limousineWizardVehicleOptions(offer);
      return [
        Column(
          key: kLimousineWizardVehicleListKey,
          children: [
            for (final option in options)
              _vehicleChoiceCard(option, offer!),
          ],
        ),
      ];
    }
    final offers = _filteredOffers();
    return [
      if (!locked) ...[
        _field(_t(kLimousineCustomerSearchHint), _postcode),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton(
              onPressed:
                  _controller.discovering ||
                      !limousineRequestWizardAllowsHttp(
                        step: LimousineRequestWizardStep.provider,
                        draft: _syncedDraft(),
                        offer: _controller.selectedOffer,
                        hasProvider: _controller.selectedProvider != null,
                        action: 'discover',
                        pickupAddress: _pickup.value,
                        destinationAddress: _destination.value,
                        stopAddresses: _stops
                            .map((stop) => stop.value)
                            .toList(growable: false),
                        returnPickupAddress: _returnPickup.value,
                        returnDestinationAddress: _returnDestination.value,
                        returnKind: _activeReturnKind,
                        waitDurationSupported: _waitSupported,
                        waitMinutes: limousinePublishedOfferWaitMinutes(
                          _controller.selectedOffer,
                        ),
                      )
                  ? null
                  : () => _controller.discover(postcode: _postcode.text),
              child: Text(_t(kLimousineCustomerSearchAction)),
            ),
            TextButton(
              onPressed: _controller.discovering
                  ? null
                  : () => _controller.discover(postcode: _postcode.text),
              child: Text(_t(kLimousineProviderRetry)),
            ),
            TextButton(
              onPressed: () =>
                  _controller.goTo(LimousineCustomerQuoteStep.journey),
              child: Text(_t(kLimousineProviderEditRoute)),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            FilterChip(
              key: kLimousineProviderExactFilterKey,
              label: Text(_t(kLimousineProviderExactVehicle)),
              selected:
                  _browseFilter == LimousineOfferBrowseFilter.exactVehicle,
              onSelected: (_) {
                setState(() {
                  _browseFilter =
                      _browseFilter == LimousineOfferBrowseFilter.exactVehicle
                      ? LimousineOfferBrowseFilter.all
                      : LimousineOfferBrowseFilter.exactVehicle;
                });
              },
            ),
            FilterChip(
              key: kLimousineProviderClassFilterKey,
              label: Text(_t(kLimousineProviderServiceClass)),
              selected:
                  _browseFilter == LimousineOfferBrowseFilter.serviceClass,
              onSelected: (_) {
                setState(() {
                  _browseFilter =
                      _browseFilter == LimousineOfferBrowseFilter.serviceClass
                      ? LimousineOfferBrowseFilter.all
                      : LimousineOfferBrowseFilter.serviceClass;
                });
              },
            ),
          ],
        ),
      ],
      if (_controller.discovering) const LinearProgressIndicator(),
      if (_controller.safeError == 'unavailable')
        LimousineCustomerUnavailableBanner(language: _lang)
      else if (!_controller.discovering &&
          _controller.lastDiscoveryCount == 0 &&
          _controller.lastDiscoveryService == 'limousine')
        Padding(
          key: kLimousineCustomerDiscoverEmptyKey,
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Text(_t(kLimousineProviderNoneNearby)),
        ),
      for (final provider in _controller.providers)
        if (_controller.selectedProvider?.provider.partnerId !=
            provider.partnerId)
          ListTile(
            leading: Icon(
              Icons.directions_car_filled_outlined,
              color: _tokens.onSurface,
            ),
            title: Text(provider.companyName),
            subtitle: Text(provider.serviceArea.take(3).join(' · ')),
            onTap: locked ? null : () => _controller.selectProvider(provider),
          ),
      if (_controller.selectedProvider != null && offers.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Text(_t(kLimousineProviderNoOffer)),
        ),
      for (final offer in offers)
        LimousineProviderOfferCard(
          tokens: _tokens,
          language: _lang,
          provider: _controller.selectedProvider!.provider,
          offer: offer,
          selected: _controller.selectedOffer?.offerId == offer.offerId,
          wide: _tablet,
          onSelect: locked ? () {} : () => _controller.selectOffer(offer),
        ),
    ];
  }

  List<LimousinePublishedOffer> _filteredOffers() {
    final detail = _controller.selectedProvider;
    if (detail == null) return const [];
    final ranked = limousineRankPublicOffers(detail.offers);
    switch (_browseFilter) {
      case LimousineOfferBrowseFilter.exactVehicle:
        return ranked.where((offer) => offer.isVehicleTargeted).toList();
      case LimousineOfferBrowseFilter.serviceClass:
        return ranked.where((offer) => !offer.isVehicleTargeted).toList();
      case LimousineOfferBrowseFilter.all:
        return ranked;
    }
  }

  List<Widget> _detailsStep() {
    final offer = _controller.selectedOffer;
    final extras = offer?.paidExtras ?? const <Map<String, dynamic>>[];
    return [
      if (offer != null)
        LimousineReviewSection(
          tokens: _tokens,
          title:
              _controller.selectedProvider?.provider.companyName ??
              _t(kLimousineReviewProvider),
          editLabel: _t(kLimousineExtrasChangeSelection),
          onEdit: () => _controller.goTo(
            limousineWizardSkipsVehicleStep(_vehicleMode)
                ? LimousineCustomerQuoteStep.journey
                : LimousineCustomerQuoteStep.providerOffer,
          ),
          child: Text(
            localizedLimousineText(offer.title, languageCode: _lang.name),
            style: TextStyle(color: _tokens.muted),
          ),
        ),
      _stepperField(
        _t(kLimousineCustomerPax),
        _controller.draft.pax ?? 1,
        (value) {
          _controller.updateDraft(_syncedDraft().copyWith(pax: value));
        },
        max: offer?.passengerCapacity,
      ),
      _stepperField(
        _t(kLimousineCustomerBags),
        _controller.draft.bags ?? 0,
        (value) {
          _controller.updateDraft(_syncedDraft().copyWith(bags: value));
        },
        max: offer?.luggageCapacity,
      ),
      if (extras.isEmpty)
        Padding(
          key: kLimousineExtrasEmptyKey,
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text(
            _t(kLimousineExtrasEmpty),
            style: TextStyle(color: _tokens.muted, height: 1.35),
          ),
        )
      else
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final extra in extras)
              LimousineExtraTile(
                tokens: _tokens,
                label: _extraLabel(extra),
                selected: _controller.draft.selectedExtraIds.contains(
                  _extraId(extra),
                ),
                onTap: () {
                  final id = _extraId(extra);
                  if (id.isEmpty) return;
                  final next = List<String>.from(
                    _controller.draft.selectedExtraIds,
                  );
                  if (next.contains(id)) {
                    next.remove(id);
                  } else {
                    next.add(id);
                  }
                  _controller.updateDraft(
                    _syncedDraft().copyWith(selectedExtraIds: next),
                  );
                },
              ),
          ],
        ),
      _field(
        _t(kLimousineCustomerOccasion),
        _occasion,
        onChanged: (value) {
          _controller.updateDraft(_syncedDraft().copyWith(occasion: value));
        },
      ),
      _field(
        _t(kLimousineCustomerNote),
        _note,
        maxLines: 3,
        onChanged: (value) {
          _controller.updateDraft(_syncedDraft().copyWith(customerNote: value));
        },
      ),
      Padding(
        padding: const EdgeInsets.only(top: 4, bottom: 8),
        child: Text(
          _t(kLimousineExtrasPriceAuthority),
          style: TextStyle(color: _tokens.muted, fontSize: 12.5),
        ),
      ),
    ];
  }

  List<Widget> _reviewStep() {
    final rows = buildLimousineRequestReviewRows(
      draft: _syncedDraft(),
      language: _lang,
      providerName: _controller.selectedProvider?.provider.companyName ?? '',
      offer: _controller.selectedOffer,
      returnPickupAddress: _returnPickup.value.routeText,
      returnDestinationAddress: _returnDestination.value.routeText,
      returnKind: _activeReturnKind,
    );
    return [
      Column(
        key: kLimousineRequestReviewSummaryKey,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LimousineReviewSection(
            tokens: _tokens,
            title: _t(kLimousineReviewRoute),
            editLabel: _t(kLimousineReviewEdit),
            onEdit: () => _controller.goTo(LimousineCustomerQuoteStep.journey),
            child: _reviewLines(rows, const [
              'route',
              'stops',
              'pickup',
              'return',
              'return_pickup_address',
              'return_destination_address',
            ]),
          ),
          LimousineReviewSection(
            tokens: _tokens,
            title: _t(kLimousineReviewProvider),
            editLabel: _t(kLimousineReviewEdit),
            onEdit: limousineWizardSkipsVehicleStep(_vehicleMode)
                ? null
                : () => _controller.goTo(
                    LimousineCustomerQuoteStep.providerOffer,
                  ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _reviewLines(rows, const ['provider', 'offer']),
                if (_controller.lockedVehicle != null ||
                    _controller.draft.vehicleId.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      _controller.lockedVehicle?.name.isNotEmpty == true
                          ? _controller.lockedVehicle!.name
                          : _controller.draft.vehicleId,
                      key: kLimousineReviewLockedVehicleKey,
                      style: TextStyle(
                        color: _tokens.onSurface,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          LimousineReviewSection(
            tokens: _tokens,
            title: _t(kLimousineReviewExtras),
            editLabel: _t(kLimousineReviewEdit),
            onEdit: () =>
                _controller.goTo(LimousineCustomerQuoteStep.detailsExtras),
            child: _reviewLines(rows, const [
              'pax',
              'bags',
              'duration',
              'extras',
              'occasion',
            ]),
          ),
          Container(
            key: kLimousineReviewQuoteStateKey,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: _tokens.surfaceAlt,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _tokens.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _t(
                    _intentKind == LimousineCustomerIntentKind.bookingRequest
                        ? kLimousineReviewBookingRequest
                        : kLimousineReviewQuoteOnRequest,
                  ),
                  style: TextStyle(
                    color: _tokens.onSurface,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _t(kLimousineReviewNoPayment),
                  style: TextStyle(color: _tokens.muted),
                ),
                Text(
                  _t(
                    _intentKind == LimousineCustomerIntentKind.bookingRequest
                        ? kLimousineReviewCompanyConfirms
                        : kLimousineReviewDecideLater,
                  ),
                  style: TextStyle(color: _tokens.muted),
                ),
                const SizedBox(height: 8),
                _reviewLines(rows, const [
                  'price_status',
                  'price_evidence',
                  'vat_terms',
                ]),
              ],
            ),
          ),
        ],
      ),
    ];
  }

  Widget _reviewLines(List<LimousineRequestReviewRow> rows, List<String> ids) {
    final selected = rows.where((row) => ids.contains(row.id));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final row in selected)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  row.label,
                  style: TextStyle(
                    color: _tokens.muted,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  row.value,
                  style: TextStyle(
                    color: _tokens.onSurface,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  void _goBack() {
    switch (_wizardStep) {
      case LimousineRequestWizardStep.provider:
        _controller.goTo(LimousineCustomerQuoteStep.journey);
        break;
      case LimousineRequestWizardStep.details:
        _controller.goTo(
          limousineWizardSkipsVehicleStep(_vehicleMode)
              ? LimousineCustomerQuoteStep.journey
              : LimousineCustomerQuoteStep.providerOffer,
        );
        break;
      case LimousineRequestWizardStep.review:
        _controller.goTo(LimousineCustomerQuoteStep.detailsExtras);
        break;
      case LimousineRequestWizardStep.journey:
        break;
    }
  }

  bool get _submitCtaAllowed {
    if (widget.controller != null || widget.gateway != null) return true;
    return _intentKind == LimousineCustomerIntentKind.bookingRequest
        ? limousineCustomerBookCtaEnabled()
        : limousineCustomerQuoteCtaEnabled();
  }

  Future<void> _goNext() async {
    _syncDraft();
    if (!_canAdvance) {
      _controller.markSubmitBlocked(
        _gaps.isEmpty ? 'invalid_request' : _gaps.first.code,
      );
      return;
    }
    switch (_wizardStep) {
      case LimousineRequestWizardStep.journey:
        _controller.goTo(
          limousineWizardSkipsVehicleStep(_vehicleMode)
              ? LimousineCustomerQuoteStep.detailsExtras
              : LimousineCustomerQuoteStep.providerOffer,
        );
        break;
      case LimousineRequestWizardStep.provider:
        _controller.goTo(LimousineCustomerQuoteStep.detailsExtras);
        break;
      case LimousineRequestWizardStep.details:
        _controller.goTo(LimousineCustomerQuoteStep.reviewRequest);
        break;
      case LimousineRequestWizardStep.review:
        if (!_submitCtaAllowed) {
          _controller.markSubmitBlocked('gate_off');
          return;
        }
        if (!limousineRequestWizardAllowsHttp(
          step: LimousineRequestWizardStep.review,
          draft: _syncedDraft(),
          offer: _controller.selectedOffer,
          hasProvider: _controller.selectedProvider != null,
          action: 'submit',
          pickupAddress: _pickup.value,
          destinationAddress: _destination.value,
          stopAddresses: _stops
              .map((stop) => stop.value)
              .toList(growable: false),
          returnPickupAddress: _returnPickup.value,
          returnDestinationAddress: _returnDestination.value,
          returnKind: _activeReturnKind,
          waitDurationSupported: _waitSupported,
          waitMinutes: limousinePublishedOfferWaitMinutes(
            _controller.selectedOffer,
          ),
        )) {
          _controller.markSubmitBlocked(
            _gaps.isEmpty ? 'invalid_request' : _gaps.first.code,
          );
          return;
        }
        final locale = switch (_lang) {
          AppLanguage.fr => 'fr',
          AppLanguage.es => 'es',
          AppLanguage.en => 'en',
          _ => 'nl',
        };
        _controller.updateDraft(_syncedDraft().copyWith(locale: locale));
        final ok = await _controller.submitRequest();
        if (ok) _controller.startPolling();
        break;
    }
  }

  Widget _vehicleChoiceCard(
    LimousineWizardVehicleOption option,
    LimousinePublishedOffer offer,
  ) {
    final selected = _controller.draft.vehicleId == option.vehicleId;
    final photo = option.photoUrl;
    final media = photo.isNotEmpty
        ? Image.network(
            photo,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => ColoredBox(
              color: _tokens.surfaceAlt,
              child: Icon(Icons.directions_car_filled, color: _tokens.gold),
            ),
          )
        : ColoredBox(
            color: _tokens.surfaceAlt,
            child: Icon(Icons.directions_car_filled, color: _tokens.gold),
          );
    final description = localizedLimousineText(
      option.publicDescription,
      languageCode: _lang.name,
    );
    final classLabel = option.classLabel(_lang);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        key: limousineWizardVehicleCardKey(option.vehicleId),
        color: _tokens.surface,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _controller.selectVehicle(option.vehicleId),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: selected ? _tokens.gold : _tokens.border,
                width: selected ? 1.6 : 1,
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: SizedBox(width: 132, height: 96, child: media),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        option.name,
                        style: TextStyle(
                          color: _tokens.onSurface,
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
                      if (classLabel.isNotEmpty)
                        Text(
                          classLabel,
                          style: TextStyle(color: _tokens.gold, height: 1.35),
                        ),
                      Wrap(
                        spacing: 10,
                        children: [
                          if (option.passengerCapacity != null)
                            Text(
                              '${_t(kLimousineWizardPassengers)} ${option.passengerCapacity}',
                              style: TextStyle(
                                color: _tokens.muted,
                                fontSize: 12,
                              ),
                            ),
                          if (option.luggageCapacity != null)
                            Text(
                              '${_t(kLimousineWizardLuggage)} ${option.luggageCapacity}',
                              style: TextStyle(
                                color: _tokens.muted,
                                fontSize: 12,
                              ),
                            ),
                        ],
                      ),
                      if (description.isNotEmpty)
                        Text(
                          description,
                          style: TextStyle(color: _tokens.muted, height: 1.35),
                        ),
                      Text(
                        limousineCustomerPresentationLabel(
                          option.pricePresentation.isEmpty
                              ? offer.pricePresentation
                              : option.pricePresentation,
                          _lang,
                        ),
                        style: TextStyle(
                          color: _tokens.onSurface,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _field(
    String label,
    TextEditingController controller, {
    int maxLines = 1,
    ValueChanged<String>? onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: controller,
        maxLines: maxLines,
        style: TextStyle(color: _tokens.onSurface),
        onChanged: onChanged,
        decoration: InputDecoration(
          labelText: label,
          hintStyle: TextStyle(color: _tokens.muted),
          filled: true,
          fillColor: _tokens.fieldFill,
        ),
      ),
    );
  }

  Widget _stepperField(
    String label,
    int value,
    ValueChanged<int> onChanged, {
    int? max,
  }) {
    final atMax = max != null && value >= max;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(label),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            onPressed: value <= 0 ? null : () => onChanged(value - 1),
            icon: const Icon(Icons.remove_circle_outline),
          ),
          Text('$value', style: TextStyle(color: _tokens.onSurface)),
          IconButton(
            onPressed: atMax ? null : () => onChanged(value + 1),
            icon: const Icon(Icons.add_circle_outline),
          ),
        ],
      ),
    );
  }

  LimousineQuoteCreateDraft _syncedDraft() {
    final onJourney = _wizardStep == LimousineRequestWizardStep.journey;
    final later =
        _controller.draft.roundtrip &&
        _returnKind == LimousineReturnTripKind.later;
    final fromEndpoint = _resolvedFromEndpoint();
    final toEndpoint = _resolvedToEndpoint();
    return _controller.draft.copyWith(
      from: fromEndpoint?.routeText.isNotEmpty == true
          ? fromEndpoint!.routeText
          : (_pickup.isRouteReady
                ? _pickup.value.routeText
                : (onJourney ? '' : _controller.draft.from)),
      to: toEndpoint?.routeText.isNotEmpty == true
          ? toEndpoint!.routeText
          : (_destination.isRouteReady
                ? _destination.value.routeText
                : (onJourney ? '' : _controller.draft.to)),
      fromEndpoint: fromEndpoint,
      toEndpoint: toEndpoint,
      returnPickupEndpoint: _returnPickup.isRouteReady
          ? (_controller.draft.returnPickupEndpoint ??
                limousineEndpointFromAddress(_returnPickup.value))
          : _controller.draft.returnPickupEndpoint,
      returnDestinationEndpoint: _returnDestination.isRouteReady
          ? (_controller.draft.returnDestinationEndpoint ??
                limousineEndpointFromAddress(_returnDestination.value))
          : _controller.draft.returnDestinationEndpoint,
      customerNote: _note.text,
      occasion: _occasion.text,
      stops: _stops
          .map((controller) => controller.value.routeText)
          .where((text) => text.isNotEmpty)
          .toList(growable: false),
      returnPickupIso: later ? _controller.draft.returnPickupIso : '',
    );
  }

  LimousineTransferEndpoint? _resolvedFromEndpoint() {
    if (_isAirportJourney && _airportIsPickup && _selectedAirport != null) {
      return limousineEndpointFromAirport(_selectedAirport!);
    }
    if (_isHotelJourney && _hotelIsPickup && _hotelField.selected != null) {
      return _hotelField.selected;
    }
    if (_pickup.isRouteReady) return limousineEndpointFromAddress(_pickup.value);
    return _controller.draft.fromEndpoint;
  }

  LimousineTransferEndpoint? _resolvedToEndpoint() {
    if (_isAirportJourney && !_airportIsPickup && _selectedAirport != null) {
      return limousineEndpointFromAirport(_selectedAirport!);
    }
    if (_isHotelJourney && !_hotelIsPickup && _hotelField.selected != null) {
      return _hotelField.selected;
    }
    if (_isEventJourney && _eventField.selected != null) {
      return _eventField.selected;
    }
    if (_destination.isRouteReady) {
      return limousineEndpointFromAddress(_destination.value);
    }
    return _controller.draft.toEndpoint;
  }

  void _syncDraft() {
    _controller.updateDraft(_syncedDraft());
  }

  void _setRoundtrip(bool value) {
    if (value) {
      if (_destination.isRouteReady) {
        _returnPickup.acceptCopy(_destination.value);
      } else if (_isEventJourney && _eventField.selected != null) {
        _returnPickup.acceptCopy(
          limousineAddressValueFromEndpoint(_eventField.selected!),
        );
      }
      if (_pickup.isRouteReady) {
        _returnDestination.acceptCopy(_pickup.value);
      }
      final fromEndpoint = _resolvedFromEndpoint();
      final toEndpoint = _resolvedToEndpoint();
      final reversed = fromEndpoint != null && toEndpoint != null
          ? reverseLimousineEndpoints(from: fromEndpoint, to: toEndpoint)
          : null;
      _returnKind = _isEventJourney
          ? LimousineReturnTripKind.later
          : LimousineReturnTripKind.unset;
      _controller.updateDraft(
        _syncedDraft().copyWith(
          roundtrip: true,
          returnPickupIso: '',
          returnPickupEndpoint: reversed?.from ?? toEndpoint,
          returnDestinationEndpoint: reversed?.to ?? fromEndpoint,
        ),
      );
    } else {
      _returnKind = LimousineReturnTripKind.unset;
      _returnPickup.clear();
      _returnDestination.clear();
      _controller.updateDraft(
        _syncedDraft().copyWith(roundtrip: false, returnPickupIso: ''),
      );
    }
    if (mounted) setState(() {});
  }

  Future<void> _pickSchedule({required bool returnTrip}) async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: now.add(const Duration(days: 1)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(now.add(const Duration(hours: 2))),
    );
    if (time == null) return;
    final iso = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    ).toUtc().toIso8601String();
    if (returnTrip) {
      _returnKind = LimousineReturnTripKind.later;
      _controller.updateDraft(_syncedDraft().copyWith(returnPickupIso: iso));
    } else {
      _controller.updateDraft(_syncedDraft().copyWith(scheduledPickupIso: iso));
    }
  }

  String _extraId(Map<String, dynamic> extra) =>
      (extra['extra_id'] ?? extra['extraId'] ?? '').toString().trim();

  String _extraLabel(Map<String, dynamic> extra) {
    return localizedLimousineText(
      extra['label'] is Map
          ? Map<String, String>.from(
              (extra['label'] as Map).map(
                (key, value) => MapEntry(key.toString(), '$value'),
              ),
            )
          : const <String, String>{},
      languageCode: _lang.name,
    );
  }
}

void openLimousineCustomerQuoteFlow(
  BuildContext context, {
  String? publicPartnerId,
  LimousinePublishedOffer? offer,
  String companyName = '',
  String vehicleId = '',
  LimousineWizardVehicleOption? vehicle,
  bool? entryEnabled,
  bool? quoteEnabled,
  bool? manualQuoteEnabled,
  bool? bookEnabled,
}) {
  final intent = limousineCustomerIntentKindOf(offer);
  final allowed = intent == LimousineCustomerIntentKind.bookingRequest
      ? limousineCustomerBookCtaEnabled(
          bookGate: bookEnabled ?? kLimousineCustomerBookGateEnabled,
        )
      : limousineCustomerQuoteCtaEnabled(
          quoteGate: quoteEnabled ?? kLimousineCustomerQuoteGateEnabled,
          manualQuoteGate:
              manualQuoteEnabled ?? kLimousineCustomerManualQuoteGateEnabled,
        );
  if (!allowed) return;
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => LimousineCustomerQuotePage(
        entryEnabled: entryEnabled ?? true,
        initialPublicPartnerId: publicPartnerId,
        initialOffer: offer,
        initialVehicleId: vehicleId,
        initialVehicle: vehicle,
        initialCompanyName: companyName,
        resumeRepository: LimousineAcceptedBookingResumeRepository(),
      ),
    ),
  );
}
