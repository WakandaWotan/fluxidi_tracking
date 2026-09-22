import 'dart:async';

import 'package:flutter/material.dart';
import 'package:fluxidi_customer_core/fluxidi_customer_core.dart';
import 'package:fluxidi_tracking/app_config.dart';

import '../api/public_partner_api.dart';
import '../api/ride_quote_api.dart';
import '../app/customer_app_config.dart';
import '../widgets/customer_route_map.dart';
import '../widgets/ride_map_sheet_shell.dart';

/// What the customer currently sees for price and availability.
enum RidePriceState { incomplete, loading, quoted, noOffer, failed }

/// Prepare a ride for one public company and ask the server for a price.
///
/// This phase ends at the price and the availability offer. It never creates a
/// booking and never starts a payment.
class CustomerRidePrepareScreen extends StatefulWidget {
  const CustomerRidePrepareScreen({
    super.key,
    required this.api,
    required this.scope,
    this.profileVehicles = const <Map<String, dynamic>>[],
    this.config = kCustomerAppConfig,
    this.clock,
    this.addressSearch,
    this.routeGeometry,
  });

  final RideQuoteApi api;

  /// Public partner context, from the company the customer opened.
  final FluxidiPartnerScope scope;

  /// `profile.vehicles[]` of that company, used to name the offered vehicles.
  final List<Map<String, dynamic>> profileVehicles;

  final CustomerAppConfig config;
  final DateTime Function()? clock;

  /// Address lookup. Defaults to Mapbox geocoding with the configured token.
  final FluxidiAddressSearchClient? addressSearch;

  /// Route line source. Defaults to Mapbox Directions with the same token.
  final FluxidiRouteGeometryClient? routeGeometry;

  @override
  State<CustomerRidePrepareScreen> createState() =>
      _CustomerRidePrepareScreenState();
}

/// Which address field the customer is editing.
enum _RideEndpoint { from, to }

class _CustomerRidePrepareScreenState extends State<CustomerRidePrepareScreen> {
  final TextEditingController _fromCtrl = TextEditingController();
  final TextEditingController _toCtrl = TextEditingController();

  bool _whenNow = true;
  DateTime? _pickupLocal;
  int _passengers = 2;
  int _bags = 0;
  bool _businessRide = false;
  bool _returnEnabled = false;
  DateTime? _returnPickupLocal;

  RidePriceState _state = RidePriceState.incomplete;
  FluxidiQuoteResult? _quote;
  FluxidiAvailabilitySnapshot? _availability;
  String _failureText = '';
  bool _failureRetryable = true;

  /// Guards against a late answer overwriting a newer request.
  int _generation = 0;

  late final FluxidiAddressSearchClient _addressSearch;
  late final FluxidiRouteGeometryClient _routeGeometry;

  FluxidiAddressValue _from = const FluxidiAddressValue();
  FluxidiAddressValue _to = const FluxidiAddressValue();

  _RideEndpoint? _activeEndpoint;
  List<FluxidiAddressSuggestion> _suggestions =
      const <FluxidiAddressSuggestion>[];
  Timer? _suggestDebounce;
  int _suggestGeneration = 0;

  List<FluxidiLonLat> _routePoints = const <FluxidiLonLat>[];
  int _routeGenerationCounter = 0;
  EdgeInsets _mapInsets = EdgeInsets.zero;

  DateTime get _now => (widget.clock ?? DateTime.now)();

  bool get _hasMap => widget.config.hasMapboxToken || widget.routeGeometry != null;

  FluxidiLonLat? get _fromPoint => fluxidiLonLat(_from.lat, _from.lon);
  FluxidiLonLat? get _toPoint => fluxidiLonLat(_to.lat, _to.lon);

  FluxidiRideOptions get _options => FluxidiRideOptions(
    service: 'passenger',
    bags: _bags,
  );

  @override
  void initState() {
    super.initState();
    _addressSearch =
        widget.addressSearch ??
        FluxidiAddressSearchClient(token: widget.config.mapboxToken);
    _routeGeometry =
        widget.routeGeometry ??
        FluxidiRouteGeometryClient(token: widget.config.mapboxToken);
    appLanguageNotifier.addListener(_onAppLanguageChanged);
  }

  @override
  void dispose() {
    _suggestDebounce?.cancel();
    appLanguageNotifier.removeListener(_onAppLanguageChanged);
    _fromCtrl.dispose();
    _toCtrl.dispose();
    super.dispose();
  }

  void _onAppLanguageChanged() {
    if (!mounted) return;
    _suggestGeneration += 1;
    final language = currentLanguageCode;
    FluxidiAddressValue localize(FluxidiAddressValue value) {
      if (!value.isRouteReady) return value;
      final source = value.canonicalLabel.trim().isNotEmpty
          ? value.canonicalLabel
          : value.displayText;
      return value.copyWith(
        displayText: fluxidiLocalizeAddressLabel(source, language),
      );
    }

    setState(() {
      _from = localize(_from);
      _to = localize(_to);
      if (_fromCtrl.text != _from.displayText) {
        _fromCtrl.text = _from.displayText;
      }
      if (_toCtrl.text != _to.displayText) {
        _toCtrl.text = _to.displayText;
      }
      _suggestions = const <FluxidiAddressSuggestion>[];
    });
  }

  /// Typed text keeps the ride usable without a lookup hit, but loses the
  /// coordinates a route needs until a suggestion is picked.
  void _onAddressTyped(_RideEndpoint endpoint, String raw) {
    final typed = fluxidiAddressFromTypedText(raw);
    setState(() {
      if (endpoint == _RideEndpoint.from) {
        _from = typed;
      } else {
        _to = typed;
      }
      _activeEndpoint = endpoint;
      _routePoints = const <FluxidiLonLat>[];
    });
    _invalidateQuote();
    _suggestDebounce?.cancel();
    _suggestDebounce = Timer(
      const Duration(milliseconds: 350),
      () => _searchSuggestions(raw),
    );
  }

  Future<void> _searchSuggestions(String raw) async {
    if (!_addressSearch.canSearch) return;
    final generation = ++_suggestGeneration;
    final found = await _addressSearch.search(
      raw,
      language: currentLanguageCode,
    );
    if (!mounted || generation != _suggestGeneration) return;
    setState(() => _suggestions = found);
  }

  void _selectSuggestion(FluxidiAddressSuggestion suggestion) {
    final endpoint = _activeEndpoint;
    if (endpoint == null) return;
    final value = suggestion.toAddressValue();
    setState(() {
      if (endpoint == _RideEndpoint.from) {
        _from = value;
        _fromCtrl.text = value.displayText;
      } else {
        _to = value;
        _toCtrl.text = value.displayText;
      }
      _suggestions = const <FluxidiAddressSuggestion>[];
      _activeEndpoint = null;
    });
    _invalidateQuote();
    unawaited(_refreshRoute());
  }

  /// Fetches the real driving line once both endpoints have coordinates.
  Future<void> _refreshRoute() async {
    final pickup = _fromPoint;
    final dropoff = _toPoint;
    if (pickup == null || dropoff == null) {
      if (_routePoints.isNotEmpty) {
        setState(() => _routePoints = const <FluxidiLonLat>[]);
      }
      return;
    }
    if (!_routeGeometry.canFetch) return;
    final generation = ++_routeGenerationCounter;
    try {
      final geometry = await _routeGeometry.fetch(
        pickup: pickup,
        dropoff: dropoff,
      );
      if (!mounted || generation != _routeGenerationCounter) return;
      setState(() => _routePoints = geometry.points);
    } catch (_) {
      if (!mounted || generation != _routeGenerationCounter) return;
      // No answer means no line; a straight line is never drawn instead.
      setState(() => _routePoints = const <FluxidiLonLat>[]);
    }
  }

  /// Any change to a priced input drops the previous answer and redraws, so the
  /// request button and the summary follow what the customer typed.
  void _invalidateQuote() {
    final hadAnswer =
        _quote != null ||
        _availability != null ||
        _state == RidePriceState.failed;
    setState(() {
      if (!hadAnswer) return;
      _generation += 1;
      _quote = null;
      _availability = null;
      _failureText = '';
      _state = RidePriceState.incomplete;
    });
  }

  FluxidiQuoteRequest? _buildRequest() {
    // With coordinates the request carries them, exactly like the existing
    // flow; typed-only input falls back to the text contract.
    final withCoordinates = buildFluxidiQuoteRequest(
      from: _from,
      to: _to,
      pickupLocal: _pickupLocal,
      options: _options,
      passengers: _passengers,
      returnEnabled: _returnEnabled,
      returnPickupLocal: _returnEnabled ? _returnPickupLocal : null,
      returnFrom: _returnEnabled ? _to : null,
      returnTo: _returnEnabled ? _from : null,
      whenNow: _whenNow,
    );
    if (withCoordinates != null) return withCoordinates;
    return buildFluxidiQuoteRequestFromText(
      from: _from,
      to: _to,
      pickupLocal: _pickupLocal,
      options: _options,
      passengers: _passengers,
      returnEnabled: _returnEnabled,
      returnPickupLocal: _returnEnabled ? _returnPickupLocal : null,
      returnFrom: _returnEnabled ? _to : null,
      returnTo: _returnEnabled ? _from : null,
      whenNow: _whenNow,
    );
  }

  bool get _canRequestPrice => _buildRequest() != null;

  Future<void> _requestPrice() async {
    final request = _buildRequest();
    if (request == null) {
      setState(() => _state = RidePriceState.incomplete);
      return;
    }
    final generation = ++_generation;
    setState(() {
      _state = RidePriceState.loading;
      _failureText = '';
      _quote = null;
      _availability = null;
    });

    try {
      final quote = await widget.api.quote(
        request: request,
        scope: widget.scope,
      );
      if (!mounted || generation != _generation) return;
      if (quote.fingerprint != request.fingerprint) return;

      final pickupUtc = _whenNow
          ? _now.toUtc()
          : fluxidiPickupUtc(_pickupLocal!);
      final availability = await widget.api.availability(
        partnerId: widget.scope.routingPartnerId,
        pickupUtc: pickupUtc,
        passengers: _passengers,
        durationMin: quote.durationMin ?? 30,
        returnDurationMin: _returnEnabled ? (quote.returnDurationMin ?? 0) : 0,
      );
      if (!mounted || generation != _generation) return;

      setState(() {
        _quote = quote;
        _availability = availability;
        _state = _resolveState(quote, availability);
      });
    } on FluxidiQuoteException catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _state = RidePriceState.failed;
        _failureRetryable = true;
        _failureText = _quoteErrorText(error.code);
      });
    } on PublicApiException catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _state = RidePriceState.failed;
        _failureRetryable = error.failure != PublicApiFailure.notConfigured;
        _failureText = error.failure == PublicApiFailure.notConfigured
            ? 'Deze build heeft geen basis-URL voor de publieke API.'
            : error.failure == PublicApiFailure.network
            ? 'De verbinding met de server is mislukt. Probeer het opnieuw.'
            : 'De server gaf een antwoord dat we niet konden lezen.';
      });
    }
  }

  static RidePriceState _resolveState(
    FluxidiQuoteResult quote,
    FluxidiAvailabilitySnapshot availability,
  ) {
    if (!quote.priceAvailable) return RidePriceState.noOffer;
    if (availability.loadFailed) return RidePriceState.quoted;
    if (!availability.hasAnyAvailable) return RidePriceState.noOffer;
    return RidePriceState.quoted;
  }

  static String _quoteErrorText(String code) {
    switch (code) {
      case 'route_failed':
      case 'route_required':
        return 'De route kon niet berekend worden. Controleer de adressen.';
      case 'calculator_off':
        return 'Dit bedrijf rekent prijzen niet automatisch.';
      default:
        return 'De prijs kon niet opgevraagd worden ($code).';
    }
  }

  List<FluxidiVehicleOffer> get _offers {
    final availability = _availability;
    if (availability == null) return const <FluxidiVehicleOffer>[];
    return buildFluxidiVehicleOffers(
      profileVehicles: widget.profileVehicles,
      availability: availability,
    );
  }

  Future<void> _pickPickupMoment() async {
    final base = _pickupLocal ?? _now.add(const Duration(hours: 1));
    final date = await showDatePicker(
      context: context,
      initialDate: base,
      firstDate: DateTime(_now.year, _now.month, _now.day),
      lastDate: DateTime(_now.year + 1, _now.month, _now.day),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(base),
    );
    if (time == null || !mounted) return;
    setState(() {
      _pickupLocal = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
      _whenNow = false;
    });
    _invalidateQuote();
  }

  Future<void> _pickReturnMoment() async {
    final base =
        _returnPickupLocal ??
        (_pickupLocal ?? _now).add(const Duration(hours: 3));
    final date = await showDatePicker(
      context: context,
      initialDate: base,
      firstDate: DateTime(_now.year, _now.month, _now.day),
      lastDate: DateTime(_now.year + 1, _now.month, _now.day),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(base),
    );
    if (time == null || !mounted) return;
    setState(() {
      _returnPickupLocal = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
    });
    _invalidateQuote();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Rit voorbereiden')),
      body: RideMapSheetShell(
        config: widget.config,
        onMapInsets: (insets) {
          if (insets == _mapInsets) return;
          setState(() => _mapInsets = insets);
        },
        map: _hasMap
            ? CustomerRouteMap(
                token: widget.config.mapboxToken,
                pickup: _fromPoint,
                dropoff: _toPoint,
                route: _routePoints,
                contentInsets: _mapInsets,
                config: widget.config,
              )
            : null,
        mapOverlay: _MapSummary(
          from: _fromCtrl.text,
          to: _toCtrl.text,
          companyName: widget.scope.companyName,
          config: widget.config,
        ),
        sheetBuilder: (context, scrollController) => ListView(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: <Widget>[
            _RideForm(
              fromCtrl: _fromCtrl,
              toCtrl: _toCtrl,
              onFromChanged: (value) =>
                  _onAddressTyped(_RideEndpoint.from, value),
              onToChanged: (value) => _onAddressTyped(_RideEndpoint.to, value),
              suggestions: _suggestions,
              activeEndpoint: _activeEndpoint,
              onSuggestionTap: _selectSuggestion,
              lookupAvailable: _addressSearch.canSearch,
              whenNow: _whenNow,
              pickupLocal: _pickupLocal,
              passengers: _passengers,
              bags: _bags,
              businessRide: _businessRide,
              returnEnabled: _returnEnabled,
              returnPickupLocal: _returnPickupLocal,
              config: widget.config,
              onWhenNow: (value) {
                setState(() => _whenNow = value);
                _invalidateQuote();
              },
              onPickPickup: _pickPickupMoment,
              onPassengers: (value) {
                setState(() => _passengers = value);
                _invalidateQuote();
              },
              onBags: (value) {
                setState(() => _bags = value);
                _invalidateQuote();
              },
              onBusinessRide: (value) => setState(() => _businessRide = value),
              onReturnEnabled: (value) {
                setState(() => _returnEnabled = value);
                _invalidateQuote();
              },
              onPickReturn: _pickReturnMoment,
            ),
            const SizedBox(height: 14),
            FilledButton(
              key: const Key('ride_request_price'),
              onPressed: _state == RidePriceState.loading || !_canRequestPrice
                  ? null
                  : _requestPrice,
              child: const Text('Prijs en beschikbaarheid opvragen'),
            ),
            const SizedBox(height: 16),
            _PriceSection(
              state: _state,
              quote: _quote,
              offers: _offers,
              passengers: _passengers,
              returnEnabled: _returnEnabled,
              failureText: _failureText,
              failureRetryable: _failureRetryable,
              onRetry: _requestPrice,
              config: widget.config,
              incompleteReason: _canRequestPrice
                  ? ''
                  : 'Vul een volledig ophaal- en bestemmingsadres in en kies '
                        'wanneer je wil vertrekken.',
            ),
          ],
        ),
      ),
    );
  }
}

class _MapSummary extends StatelessWidget {
  const _MapSummary({
    required this.from,
    required this.to,
    required this.companyName,
    required this.config,
  });

  final String from;
  final String to;
  final String companyName;
  final CustomerAppConfig config;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.end,
        children: <Widget>[
          if (companyName.isNotEmpty)
            Text(
              companyName,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          const SizedBox(height: 6),
          Text(
            from.trim().isEmpty ? 'Ophaaladres nog niet ingevuld' : from.trim(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: config.brand.textSoft,
            ),
          ),
          Text(
            to.trim().isEmpty ? 'Bestemming nog niet ingevuld' : to.trim(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: config.brand.textSoft,
            ),
          ),
        ],
      ),
    );
  }
}

class _RideForm extends StatelessWidget {
  const _RideForm({
    required this.fromCtrl,
    required this.toCtrl,
    required this.onFromChanged,
    required this.onToChanged,
    required this.suggestions,
    required this.activeEndpoint,
    required this.onSuggestionTap,
    required this.lookupAvailable,
    required this.whenNow,
    required this.pickupLocal,
    required this.passengers,
    required this.bags,
    required this.businessRide,
    required this.returnEnabled,
    required this.returnPickupLocal,
    required this.config,
    required this.onWhenNow,
    required this.onPickPickup,
    required this.onPassengers,
    required this.onBags,
    required this.onBusinessRide,
    required this.onReturnEnabled,
    required this.onPickReturn,
  });

  final TextEditingController fromCtrl;
  final TextEditingController toCtrl;
  final ValueChanged<String> onFromChanged;
  final ValueChanged<String> onToChanged;
  final List<FluxidiAddressSuggestion> suggestions;
  final _RideEndpoint? activeEndpoint;
  final ValueChanged<FluxidiAddressSuggestion> onSuggestionTap;
  final bool lookupAvailable;
  final bool whenNow;
  final DateTime? pickupLocal;
  final int passengers;
  final int bags;
  final bool businessRide;
  final bool returnEnabled;
  final DateTime? returnPickupLocal;
  final CustomerAppConfig config;
  final ValueChanged<bool> onWhenNow;
  final VoidCallback onPickPickup;
  final ValueChanged<int> onPassengers;
  final ValueChanged<int> onBags;
  final ValueChanged<bool> onBusinessRide;
  final ValueChanged<bool> onReturnEnabled;
  final VoidCallback onPickReturn;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        TextField(
          key: const Key('ride_from_field'),
          controller: fromCtrl,
          textInputAction: TextInputAction.next,
          onChanged: onFromChanged,
          decoration: const InputDecoration(
            labelText: 'Ophaaladres',
            hintText: 'Straat en nummer, postcode gemeente',
            border: OutlineInputBorder(),
          ),
        ),
        if (activeEndpoint == _RideEndpoint.from) _suggestionList(context),
        const SizedBox(height: 10),
        TextField(
          key: const Key('ride_to_field'),
          controller: toCtrl,
          onChanged: onToChanged,
          decoration: const InputDecoration(
            labelText: 'Bestemming',
            hintText: 'Straat en nummer, postcode gemeente',
            border: OutlineInputBorder(),
          ),
        ),
        if (activeEndpoint == _RideEndpoint.to) _suggestionList(context),
        if (!lookupAvailable)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'Adressuggesties en kaart zijn niet beschikbaar in deze build.',
              key: const Key('ride_lookup_unavailable'),
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: config.brand.textSoft),
            ),
          ),
        const SizedBox(height: 14),
        SegmentedButton<bool>(
          key: const Key('ride_when_toggle'),
          segments: const <ButtonSegment<bool>>[
            ButtonSegment<bool>(value: true, label: Text('Nu')),
            ButtonSegment<bool>(value: false, label: Text('Later')),
          ],
          selected: <bool>{whenNow},
          onSelectionChanged: (selection) => onWhenNow(selection.first),
        ),
        if (!whenNow) ...<Widget>[
          const SizedBox(height: 10),
          OutlinedButton.icon(
            key: const Key('ride_pick_pickup'),
            onPressed: onPickPickup,
            icon: const Icon(Icons.schedule_outlined),
            label: Text(
              pickupLocal == null
                  ? 'Kies datum en tijd'
                  : _formatMoment(pickupLocal!),
            ),
          ),
        ],
        const SizedBox(height: 14),
        _Stepper(
          key: const Key('ride_passengers'),
          label: 'Passagiers',
          value: passengers,
          min: 1,
          max: 8,
          onChanged: onPassengers,
          config: config,
        ),
        _Stepper(
          key: const Key('ride_bags'),
          label: 'Bagage',
          value: bags,
          min: 0,
          max: 8,
          onChanged: onBags,
          config: config,
        ),
        SwitchListTile(
          key: const Key('ride_return_toggle'),
          contentPadding: EdgeInsets.zero,
          title: const Text('Retourrit'),
          value: returnEnabled,
          onChanged: onReturnEnabled,
        ),
        if (returnEnabled)
          OutlinedButton.icon(
            key: const Key('ride_pick_return'),
            onPressed: onPickReturn,
            icon: const Icon(Icons.schedule_outlined),
            label: Text(
              returnPickupLocal == null
                  ? 'Kies terugrit datum en tijd'
                  : _formatMoment(returnPickupLocal!),
            ),
          ),
        SwitchListTile(
          key: const Key('ride_business_toggle'),
          contentPadding: EdgeInsets.zero,
          title: const Text('Zakelijke rit'),
          subtitle: Text(
            'Facturatiegegevens volgen bij het boeken; dit verandert de prijs '
            'niet.',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: config.brand.textSoft),
          ),
          value: businessRide,
          onChanged: onBusinessRide,
        ),
      ],
    );
  }

  Widget _suggestionList(BuildContext context) {
    if (suggestions.isEmpty) return const SizedBox.shrink();
    return Container(
      key: const Key('ride_address_suggestions'),
      margin: const EdgeInsets.only(top: 6),
      decoration: BoxDecoration(
        color: config.brand.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        children: <Widget>[
          for (final suggestion in suggestions)
            ListTile(
              key: Key('ride_suggestion_${suggestion.placeId ?? suggestion.label}'),
              dense: true,
              leading: Icon(
                suggestion.isStreetLevel
                    ? Icons.location_on_outlined
                    : Icons.place_outlined,
                size: 18,
              ),
              title: Text(
                suggestion.label,
                maxLines: 2,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              onTap: suggestion.hasCoordinates
                  ? () => onSuggestionTap(suggestion)
                  : null,
            ),
        ],
      ),
    );
  }

  static String _formatMoment(DateTime value) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(value.day)}/${two(value.month)}/${value.year} '
        '${two(value.hour)}:${two(value.minute)}';
  }
}

class _Stepper extends StatelessWidget {
  const _Stepper({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    required this.config,
  });

  final String label;
  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;
  final CustomerAppConfig config;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Expanded(child: Text(label)),
        IconButton(
          onPressed: value > min ? () => onChanged(value - 1) : null,
          icon: const Icon(Icons.remove_circle_outline),
        ),
        Text('$value', style: Theme.of(context).textTheme.titleMedium),
        IconButton(
          onPressed: value < max ? () => onChanged(value + 1) : null,
          icon: const Icon(Icons.add_circle_outline),
        ),
      ],
    );
  }
}

class _PriceSection extends StatelessWidget {
  const _PriceSection({
    required this.state,
    required this.quote,
    required this.offers,
    required this.passengers,
    required this.returnEnabled,
    required this.failureText,
    required this.failureRetryable,
    required this.onRetry,
    required this.config,
    required this.incompleteReason,
  });

  final RidePriceState state;
  final FluxidiQuoteResult? quote;
  final List<FluxidiVehicleOffer> offers;
  final int passengers;
  final bool returnEnabled;
  final String failureText;
  final bool failureRetryable;
  final VoidCallback onRetry;
  final CustomerAppConfig config;
  final String incompleteReason;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    switch (state) {
      case RidePriceState.incomplete:
        return Text(
          incompleteReason.isEmpty
              ? 'Vraag de prijs op wanneer je gegevens kloppen.'
              : incompleteReason,
          key: const Key('ride_price_incomplete'),
          style: theme.textTheme.bodySmall?.copyWith(
            color: config.brand.textSoft,
          ),
        );
      case RidePriceState.loading:
        return const Padding(
          key: Key('ride_price_loading'),
          padding: EdgeInsets.symmetric(vertical: 24),
          child: Center(child: CircularProgressIndicator()),
        );
      case RidePriceState.failed:
        return Column(
          key: const Key('ride_price_failed'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'Prijs opvragen lukt niet',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              failureText,
              style: theme.textTheme.bodySmall?.copyWith(
                color: config.brand.textSoft,
              ),
            ),
            if (failureRetryable) ...<Widget>[
              const SizedBox(height: 12),
              OutlinedButton(
                key: const Key('ride_price_retry'),
                onPressed: onRetry,
                child: const Text('Opnieuw proberen'),
              ),
            ],
          ],
        );
      case RidePriceState.noOffer:
        return Column(
          key: const Key('ride_price_no_offer'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'Geen aanbod voor deze rit',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _noOfferReason(quote),
              style: theme.textTheme.bodySmall?.copyWith(
                color: config.brand.textSoft,
              ),
            ),
          ],
        );
      case RidePriceState.quoted:
        return _QuoteCard(
          quote: quote!,
          offers: offers,
          passengers: passengers,
          returnEnabled: returnEnabled,
          config: config,
        );
    }
  }

  static String _noOfferReason(FluxidiQuoteResult? quote) {
    if (quote == null) return 'Er is geen aanbod ontvangen.';
    if (quote.calculatorOff) {
      return 'Dit bedrijf rekent prijzen niet automatisch. Vraag een prijs aan '
          'het bedrijf zelf.';
    }
    if (quote.requestQuoteRequired) {
      return 'Dit bedrijf maakt voor deze rit een prijs op maat.';
    }
    if (!quote.priceAvailable) {
      return 'Het bedrijf gaf geen prijs voor deze rit.';
    }
    return 'Er is voor dit moment geen voertuig beschikbaar.';
  }
}

class _QuoteCard extends StatelessWidget {
  const _QuoteCard({
    required this.quote,
    required this.offers,
    required this.passengers,
    required this.returnEnabled,
    required this.config,
  });

  final FluxidiQuoteResult quote;
  final List<FluxidiVehicleOffer> offers;
  final int passengers;
  final bool returnEnabled;
  final CustomerAppConfig config;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total = quote.displayTotalPrice;
    final driftWarning = !quote.totalCheck.consistent;

    return Column(
      key: const Key('ride_price_quoted'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'Prijs van het bedrijf',
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        if (driftWarning)
          Padding(
            key: const Key('ride_price_total_drift'),
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'Het totaal van het bedrijf klopt niet met de losse ritten. '
              'Vraag het bedrijf om bevestiging.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          )
        else if (total != null)
          Text(
            _money(total, quote.currency),
            key: const Key('ride_price_total'),
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
        const SizedBox(height: 4),
        Text(
          quote.priceVat != null || quote.priceExVat != null
              ? 'Inclusief btw'
              : 'Prijs zoals het bedrijf die opgeeft',
          style: theme.textTheme.bodySmall?.copyWith(
            color: config.brand.textSoft,
          ),
        ),
        if (quote.priceExVat != null)
          Text(
            'Excl. btw ${_money(quote.priceExVat!, quote.currency)}'
            '${quote.priceVat != null ? ' · btw ${_money(quote.priceVat!, quote.currency)}' : ''}',
            key: const Key('ride_price_vat_split'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: config.brand.textSoft,
            ),
          ),
        if (quote.isFixedPrice)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'Vaste prijs van het bedrijf',
              key: const Key('ride_price_fixed'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: config.brand.textSoft,
              ),
            ),
          ),
        const SizedBox(height: 10),
        _MetricRow(
          distanceKm: quote.distanceKm,
          durationMin: quote.durationMin,
          config: config,
        ),
        if (returnEnabled)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Column(
              key: const Key('ride_price_return_legs'),
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                if (quote.outboundPriceInclVat != null)
                  Text(
                    'Heenrit ${_money(quote.outboundPriceInclVat!, quote.currency)}',
                    style: theme.textTheme.bodySmall,
                  ),
                if (quote.returnPriceInclVat != null)
                  Text(
                    'Terugrit ${_money(quote.returnPriceInclVat!, quote.currency)}',
                    style: theme.textTheme.bodySmall,
                  ),
                if (quote.hasReturnRoute)
                  Text(
                    'Terugrit ${quote.returnDistanceKm} km · '
                    '${quote.returnDurationMin} min',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: config.brand.textSoft,
                    ),
                  ),
              ],
            ),
          ),
        const SizedBox(height: 16),
        Text(
          'Beschikbare voertuigen',
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        if (offers.isEmpty)
          Text(
            'Het bedrijf gaf geen voertuiglijst voor dit moment.',
            key: const Key('ride_offers_empty'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: config.brand.textSoft,
            ),
          )
        else
          for (final offer in offers)
            _OfferTile(offer: offer, passengers: passengers, config: config),
        const SizedBox(height: 18),
        Container(
          key: const Key('ride_not_a_booking'),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: config.brand.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'Dit is nog geen boeking',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Je hebt een prijsopgave van het bedrijf. Boeken en betalen '
                'worden in een volgende fase aangesloten.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: config.brand.textSoft,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  static String _money(num amount, String currency) {
    final symbol = currency.toUpperCase() == 'EUR' ? '€' : '$currency ';
    return '$symbol${amount.toStringAsFixed(2).replaceAll('.', ',')}';
  }
}

class _MetricRow extends StatelessWidget {
  const _MetricRow({
    required this.distanceKm,
    required this.durationMin,
    required this.config,
  });

  final num? distanceKm;
  final int? durationMin;
  final CustomerAppConfig config;

  @override
  Widget build(BuildContext context) {
    final parts = <String>[
      if (distanceKm != null) '$distanceKm km',
      if (durationMin != null) '$durationMin min',
    ];
    if (parts.isEmpty) return const SizedBox.shrink();
    return Text(
      parts.join(' · '),
      key: const Key('ride_price_metrics'),
      style: Theme.of(
        context,
      ).textTheme.bodyMedium?.copyWith(color: config.brand.textSoft),
    );
  }
}

class _OfferTile extends StatelessWidget {
  const _OfferTile({
    required this.offer,
    required this.passengers,
    required this.config,
  });

  final FluxidiVehicleOffer offer;
  final int passengers;
  final CustomerAppConfig config;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subtitleParts = <String>[
      if (offer.passengerSeats != null) '${offer.passengerSeats} plaatsen',
      if (!offer.available && offer.reason.isNotEmpty) offer.reason,
      if (offer.hasDriverDetails) offer.driverDisplayName,
    ];
    return ListTile(
      key: Key('ride_offer_${offer.vehicleId}'),
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        offer.available ? Icons.directions_car_outlined : Icons.block_outlined,
        color: offer.available
            ? theme.colorScheme.primary
            : config.brand.textSoft,
      ),
      title: Text(offer.name.isEmpty ? offer.vehicleId : offer.name),
      subtitle: Text(
        subtitleParts.isEmpty
            ? (offer.available ? 'Beschikbaar' : 'Niet beschikbaar')
            : subtitleParts.join(' · '),
        style: theme.textTheme.bodySmall?.copyWith(color: config.brand.textSoft),
      ),
      trailing: offer.tooSmallFor(passengers)
          ? Text(
              'Te klein',
              key: Key('ride_offer_too_small_${offer.vehicleId}'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            )
          : null,
    );
  }
}
