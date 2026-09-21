import 'dart:async';

import 'package:flutter/material.dart';
import 'package:fluxidi_customer_core/fluxidi_customer_core.dart';
import 'package:fluxidi_tracking/customer_theme_palette.dart';

import '../app/customer_app_config.dart';
import '../app/customer_labels.dart';
import '../app/customer_theme.dart';
import '../bridge/customer_flows.dart';
import '../widgets/customer_header_bar.dart';
import '../widgets/customer_service_card.dart';

/// Start page of the customer app.
///
/// A real screen rather than a background photo with a carousel on top: the
/// header, one destination field that carries its coordinates into the booking
/// flow, the four service cards and Region Radar.
class CustomerHomeScreen extends StatefulWidget {
  const CustomerHomeScreen({
    super.key,
    this.config = kCustomerAppConfig,
    this.addressClient,
  });

  final CustomerAppConfig config;

  /// Injected in tests so the destination field can be exercised without
  /// calling the address provider.
  final FluxidiAddressSearchClient? addressClient;

  @override
  State<CustomerHomeScreen> createState() => _CustomerHomeScreenState();
}

class _CustomerHomeScreenState extends State<CustomerHomeScreen> {
  final TextEditingController _destinationCtrl = TextEditingController();
  final FocusNode _destinationFocus = FocusNode();

  late final FluxidiAddressSearchClient _addressClient;
  Timer? _debounce;
  int _requestId = 0;
  bool _searching = false;
  bool _searched = false;
  List<FluxidiAddressSuggestion> _suggestions =
      const <FluxidiAddressSuggestion>[];
  FluxidiAddressValue _destination = const FluxidiAddressValue();

  @override
  void initState() {
    super.initState();
    _addressClient = widget.addressClient ??
        FluxidiAddressSearchClient(token: widget.config.mapboxToken);
    _destinationCtrl.addListener(_onDestinationChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _destinationCtrl.removeListener(_onDestinationChanged);
    _destinationCtrl.dispose();
    _destinationFocus.dispose();
    super.dispose();
  }

  void _onDestinationChanged() {
    final raw = _destinationCtrl.text;
    // Typing after a pick drops the picked coordinates on purpose: the ride may
    // never quote on a label the customer has since edited.
    _destination = fluxidiAddressFromTypedText(raw);
    _debounce?.cancel();
    if (!_addressClient.canSearch) {
      setState(() {});
      return;
    }
    if (raw.trim().length < kFluxidiAddressMinQueryLength) {
      setState(() {
        _suggestions = const <FluxidiAddressSuggestion>[];
        _searched = false;
        _searching = false;
      });
      return;
    }
    setState(() => _searching = true);
    _debounce = Timer(const Duration(milliseconds: 320), () {
      unawaited(_search(raw));
    });
  }

  Future<void> _search(String query) async {
    final requestId = ++_requestId;
    final results = await _addressClient.search(query);
    if (!mounted || requestId != _requestId) return;
    setState(() {
      _suggestions = results;
      _searching = false;
      _searched = true;
    });
  }

  void _pickSuggestion(FluxidiAddressSuggestion suggestion) {
    setState(() {
      _destination = suggestion.toAddressValue();
      _destinationCtrl.value = TextEditingValue(
        text: suggestion.label,
        selection: TextSelection.collapsed(offset: suggestion.label.length),
      );
      _suggestions = const <FluxidiAddressSuggestion>[];
      _searched = false;
    });
    _destinationFocus.unfocus();
  }

  Future<void> _bookTaxi() async {
    final destination = _destination;
    if (!destination.isRouteReady) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(CustomerText.noDestinationYet.current)),
      );
      return;
    }
    await openTaxiFlow(
      context,
      destination: CustomerFlowPlace(
        address: destination.routeText,
        latitude: destination.lat,
        longitude: destination.lon,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = activeCustomerPalette();
    return Scaffold(
      backgroundColor: palette.background,
      body: SafeArea(
        bottom: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            // Phone stacks the service cards; a tablet shows two columns in
            // both portrait and landscape.
            final twoColumns = width >= 600;
            final horizontal = width >= 600 ? 24.0 : 16.0;
            return ListView(
              padding: EdgeInsets.fromLTRB(horizontal, 8, horizontal, 24),
              children: <Widget>[
                CustomerHeaderBar(config: widget.config),
                const SizedBox(height: 20),
                Text(
                  CustomerText.whereTo.current,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: palette.textPrimary,
                      ),
                ),
                const SizedBox(height: 12),
                _DestinationField(
                  controller: _destinationCtrl,
                  focusNode: _destinationFocus,
                  palette: palette,
                  searching: _searching,
                  canSearch: _addressClient.canSearch,
                  noResults: _searched && _suggestions.isEmpty,
                  suggestions: _suggestions,
                  onPick: _pickSuggestion,
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 52,
                  child: FilledButton.icon(
                    key: const Key('customer_home_book_taxi'),
                    onPressed: _bookTaxi,
                    icon: const Icon(Icons.local_taxi_outlined),
                    label: Text(CustomerText.bookTaxi.current),
                  ),
                ),
                const SizedBox(height: 28),
                Text(
                  CustomerText.services.current,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: palette.textPrimary,
                      ),
                ),
                const SizedBox(height: 12),
                _ServiceGrid(twoColumns: twoColumns),
                const SizedBox(height: 20),
                _RegionRadarCard(palette: palette),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ServiceGrid extends StatelessWidget {
  const _ServiceGrid({required this.twoColumns});

  final bool twoColumns;

  static const List<_Service> _services = <_Service>[
    _Service(
      key: 'airport',
      label: CustomerText.airportRides,
      asset: 'assets/fluxidi/customer_home_airport_banner.webp',
      icon: Icons.flight_takeoff_outlined,
    ),
    _Service(
      key: 'hotels',
      label: CustomerText.hotelsAndBnb,
      asset: 'assets/fluxidi/customer_home_hotel_bb_banner.webp',
      icon: Icons.hotel_outlined,
    ),
    _Service(
      key: 'events',
      label: CustomerText.events,
      asset: 'assets/fluxidi/customer_home_events_banner.webp',
      icon: Icons.celebration_outlined,
    ),
    _Service(
      key: 'limousine',
      label: CustomerText.limousine,
      asset: 'assets/fluxidi/customer_home_limousine_banner.webp',
      icon: Icons.airport_shuttle_outlined,
    ),
  ];

  void _open(BuildContext context, String key) {
    switch (key) {
      case 'airport':
        unawaited(openAirportFlow(context));
      case 'hotels':
        unawaited(openHotelsFlow(context));
      case 'events':
        unawaited(openEventsFlow(context));
      case 'limousine':
        openLimousineFlow(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cards = <Widget>[
      for (final service in _services)
        CustomerServiceCard(
          cardKey: Key('customer_home_service_${service.key}'),
          title: service.label.current,
          asset: service.asset,
          icon: service.icon,
          onTap: () => _open(context, service.key),
        ),
    ];

    if (!twoColumns) {
      return Column(
        children: <Widget>[
          for (final card in cards)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: card,
            ),
        ],
      );
    }

    return Column(
      children: <Widget>[
        for (var i = 0; i < cards.length; i += 2)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              children: <Widget>[
                Expanded(child: cards[i]),
                const SizedBox(width: 12),
                Expanded(
                  child: i + 1 < cards.length
                      ? cards[i + 1]
                      : const SizedBox.shrink(),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

@immutable
class _Service {
  const _Service({
    required this.key,
    required this.label,
    required this.asset,
    required this.icon,
  });

  final String key;
  final CustomerLabel label;
  final String asset;
  final IconData icon;
}

class _DestinationField extends StatelessWidget {
  const _DestinationField({
    required this.controller,
    required this.focusNode,
    required this.palette,
    required this.searching,
    required this.canSearch,
    required this.noResults,
    required this.suggestions,
    required this.onPick,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final CustomerThemePalette palette;
  final bool searching;
  final bool canSearch;
  final bool noResults;
  final List<FluxidiAddressSuggestion> suggestions;
  final ValueChanged<FluxidiAddressSuggestion> onPick;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        TextField(
          key: const Key('customer_home_destination'),
          controller: controller,
          focusNode: focusNode,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: CustomerText.destinationHint.current,
            prefixIcon: const Icon(Icons.place_outlined),
            suffixIcon: searching
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : (controller.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: controller.clear,
                      )),
          ),
        ),
        if (!canSearch)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              CustomerText.noMapboxToken.current,
              style: theme.textTheme.bodySmall?.copyWith(
                color: palette.textMuted,
              ),
            ),
          ),
        if (suggestions.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 8),
            decoration: BoxDecoration(
              color: palette.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: palette.border),
            ),
            child: Column(
              children: <Widget>[
                for (final suggestion in suggestions)
                  ListTile(
                    key: Key('customer_home_suggestion_${suggestion.label}'),
                    dense: true,
                    leading: Icon(
                      Icons.location_on_outlined,
                      color: palette.textMuted,
                    ),
                    title: Text(
                      suggestion.label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: palette.textPrimary),
                    ),
                    onTap: () => onPick(suggestion),
                  ),
              ],
            ),
          ),
        if (suggestions.isEmpty && noResults)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              CustomerText.noAddressFound.current,
              style: theme.textTheme.bodySmall?.copyWith(
                color: palette.textMuted,
              ),
            ),
          ),
      ],
    );
  }
}

class _RegionRadarCard extends StatelessWidget {
  const _RegionRadarCard({required this.palette});

  final CustomerThemePalette palette;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: palette.surfaceAlt,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        key: const Key('customer_home_region_radar'),
        borderRadius: BorderRadius.circular(16),
        onTap: () => unawaited(openRegionRadar(context)),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: palette.border),
          ),
          child: Row(
            children: <Widget>[
              Icon(Icons.radar_outlined, color: palette.gold, size: 28),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      CustomerText.regionRadar.current,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: palette.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      CustomerText.regionRadarSubtitle.current,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: palette.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: palette.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}
