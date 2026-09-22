import 'dart:async';

import 'package:flutter/material.dart';
import 'package:fluxidi_customer_core/fluxidi_customer_core.dart';
import 'package:fluxidi_tracking/customer_theme_palette.dart';
import 'package:fluxidi_tracking/customer_theme_store.dart';

import 'package:fluxidi_tracking/app_config.dart';

import '../app/customer_app_config.dart';
import '../app/customer_labels.dart';
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
  bool _suppressDestinationListener = false;

  @override
  void initState() {
    super.initState();
    _addressClient =
        widget.addressClient ??
        FluxidiAddressSearchClient(token: widget.config.mapboxToken);
    _destinationCtrl.addListener(_onDestinationChanged);
    appLanguageNotifier.addListener(_onAppLanguageChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    appLanguageNotifier.removeListener(_onAppLanguageChanged);
    _destinationCtrl.removeListener(_onDestinationChanged);
    _destinationCtrl.dispose();
    _destinationFocus.dispose();
    super.dispose();
  }

  void _writeDestinationText(String text) {
    _suppressDestinationListener = true;
    _destinationCtrl.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    _suppressDestinationListener = false;
  }

  void _onAppLanguageChanged() {
    if (!mounted) return;
    _requestId += 1;
    if (_destination.isRouteReady) {
      final source = _destination.canonicalLabel.trim().isNotEmpty
          ? _destination.canonicalLabel
          : _destination.displayText;
      final localized = fluxidiLocalizeAddressLabel(
        source,
        currentLanguageCode,
      );
      if (localized == _destination.displayText &&
          localized == _destinationCtrl.text) {
        return;
      }
      setState(() {
        _destination = _destination.copyWith(displayText: localized);
        _writeDestinationText(localized);
      });
      return;
    }
    final raw = _destinationCtrl.text.trim();
    if (raw.length >= kFluxidiAddressMinQueryLength &&
        _destinationFocus.hasFocus) {
      unawaited(_search(raw));
    }
  }

  void _onDestinationChanged() {
    if (_suppressDestinationListener) return;
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
    final results = await _addressClient.search(
      query,
      language: currentLanguageCode,
    );
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
      _writeDestinationText(suggestion.label);
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
    return ValueListenableBuilder<CustomerThemeVariant>(
      valueListenable: customerThemeNotifier,
      builder: (context, variant, _) {
        return CustomerLanguageBuilder(
          builder: (context, _) {
        final palette = paletteForCustomerTheme(variant);
        return ColoredBox(
          color: palette.background,
          child: SafeArea(
            bottom: false,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final shortest = constraints.biggest.shortestSide;
                final isTablet = shortest >= 600;
                final isLandscape =
                    constraints.maxWidth > constraints.maxHeight;
                // Wide photo cards stacked on a phone and on a tablet in portrait;
                // two columns only on a tablet in landscape.
                final twoColumns = isTablet && isLandscape;
                final horizontal = twoColumns ? 28.0 : (isTablet ? 24.0 : 16.0);
                if (twoColumns) {
                  // constraints.maxHeight is already the shell body above the
                  // NavigationBar, minus the top SafeArea. Do not subtract the
                  // bar or the system inset again.
                  return _landscapeHome(
                    context: context,
                    palette: palette,
                    horizontal: horizontal,
                    viewportHeight: constraints.maxHeight,
                  );
                }
                if (isTablet) {
                  return _portraitTabletHome(
                    context: context,
                    palette: palette,
                    horizontal: horizontal,
                  );
                }
                return ListView(
                  padding: EdgeInsets.fromLTRB(horizontal, 8, horizontal, 16),
                  children: <Widget>[
                    Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 880),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: <Widget>[
                            ..._homeIntro(
                              context: context,
                              palette: palette,
                              isTablet: false,
                              twoColumns: false,
                            ),
                            const _ServiceGrid(
                              twoColumns: false,
                              cardHeight: 140,
                            ),
                            const SizedBox(height: 16),
                            _RegionRadarCard(palette: palette),
                          ],
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        );
          },
        );
      },
    );
  }

  List<Widget> _homeIntro({
    required BuildContext context,
    required CustomerThemePalette palette,
    required bool isTablet,
    required bool twoColumns,
  }) {
    return <Widget>[
      CustomerHeaderBar(config: widget.config),
      SizedBox(height: twoColumns ? 12 : (isTablet ? 20 : 16)),
      Text(
        CustomerText.whereTo.current,
        style:
            (isTablet
                    ? Theme.of(context).textTheme.headlineMedium
                    : Theme.of(context).textTheme.headlineSmall)
                ?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: palette.textPrimary,
                ),
      ),
      SizedBox(height: twoColumns ? 10 : 12),
      _DestinationField(
        controller: _destinationCtrl,
        focusNode: _destinationFocus,
        palette: palette,
        searching: _searching,
        canSearch: _addressClient.canSearch,
        noResults: _searched && _suggestions.isEmpty,
        suggestions: _suggestions,
        onPick: _pickSuggestion,
        sideBySideCta: twoColumns,
        onBookTaxi: _bookTaxi,
      ),
      SizedBox(height: twoColumns ? 14 : (isTablet ? 24 : 20)),
      Text(
        CustomerText.services.current,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w700,
          color: palette.textPrimary,
        ),
      ),
      const SizedBox(height: 10),
    ];
  }

  /// Tablet portrait at normal text: Region Radar stays fully above the nav.
  /// The gap above Radar shrinks first; leftover shortfall is shared across
  /// the four photo cards. Large text or a keyboard keeps a scrolling list.
  Widget _portraitTabletHome({
    required BuildContext context,
    required CustomerThemePalette palette,
    required double horizontal,
  }) {
    const bottomGap = 16.0;
    const radarGap = 10.0;
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    final largeText = MediaQuery.textScalerOf(context).scale(16) > 20;
    if (largeText || keyboard > 80) {
      return ListView(
        padding: EdgeInsets.fromLTRB(horizontal, 8, horizontal, bottomGap),
        children: <Widget>[
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 880),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  ..._homeIntro(
                    context: context,
                    palette: palette,
                    isTablet: true,
                    twoColumns: false,
                  ),
                  const _ServiceGrid(twoColumns: false, cardHeight: 200),
                  const SizedBox(height: radarGap),
                  _RegionRadarCard(palette: palette),
                ],
              ),
            ),
          ),
        ],
      );
    }
    return Padding(
      padding: EdgeInsets.fromLTRB(horizontal, 8, horizontal, bottomGap),
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 880),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              ..._homeIntro(
                context: context,
                palette: palette,
                isTablet: true,
                twoColumns: false,
              ),
              const Expanded(
                child: _ServiceGrid(
                  twoColumns: false,
                  expandColumn: true,
                  maxCardHeight: 200,
                  minCardHeight: 176,
                ),
              ),
              const SizedBox(height: radarGap),
              _RegionRadarCard(palette: palette),
            ],
          ),
        ),
      ),
    );
  }

  /// Tablet landscape: leftover body height goes into the two photo rows.
  /// Region Radar sits after them with a normal 16–24 px gap to the app bar.
  Widget _landscapeHome({
    required BuildContext context,
    required CustomerThemePalette palette,
    required double horizontal,
    required double viewportHeight,
  }) {
    const bottomGap = 20.0;
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    final largeText = MediaQuery.textScalerOf(context).scale(16) > 20;
    if (largeText || keyboard > 80) {
      return ListView(
        padding: EdgeInsets.fromLTRB(horizontal, 8, horizontal, bottomGap),
        children: <Widget>[
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1320),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  ..._homeIntro(
                    context: context,
                    palette: palette,
                    isTablet: true,
                    twoColumns: true,
                  ),
                  _ServiceGrid(
                    twoColumns: true,
                    cardHeight: _landscapeCardHeight(
                      viewportHeight: viewportHeight,
                      textScaler: MediaQuery.textScalerOf(context),
                      textTheme: Theme.of(context).textTheme,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _RegionRadarCard(palette: palette),
                ],
              ),
            ),
          ),
        ],
      );
    }
    return Padding(
      padding: EdgeInsets.fromLTRB(horizontal, 8, horizontal, bottomGap),
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1320),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              ..._homeIntro(
                context: context,
                palette: palette,
                isTablet: true,
                twoColumns: true,
              ),
              Expanded(
                child: _ServiceGrid(twoColumns: true, expandRows: true),
              ),
              const SizedBox(height: 12),
              _RegionRadarCard(palette: palette),
            ],
          ),
        ),
      ),
    );
  }

  /// Gives leftover shell-body height to the two photo rows.
  ///
  /// [viewportHeight] is already above the NavigationBar and after the top
  /// SafeArea. The 148 px ceiling that left a blank strip is gone; cards stop
  /// at 260 so a very tall window does not turn them into full-page banners.
  static double _landscapeCardHeight({
    required double viewportHeight,
    required TextScaler textScaler,
    required TextTheme textTheme,
  }) {
    if (!viewportHeight.isFinite) return 180;
    final title =
        textScaler.scale(textTheme.headlineMedium?.fontSize ?? 28) * 1.15;
    final services =
        textScaler.scale(textTheme.titleMedium?.fontSize ?? 16) * 1.25;
    final radarText =
        textScaler.scale(textTheme.titleMedium?.fontSize ?? 16) * 1.2 +
        2 +
        textScaler.scale(textTheme.bodySmall?.fontSize ?? 12) * 1.25;
    const header = 42.0;
    const dest = 56.0;
    const topPad = 8.0;
    const bottomGap = 20.0;
    final radar = 36 + (radarText < 28 ? 28.0 : radarText);
    final chrome =
        topPad +
        header +
        12 +
        title +
        10 +
        dest +
        14 +
        services +
        10 +
        12 +
        12 +
        radar +
        bottomGap +
        24;
    return ((viewportHeight - chrome) / 2).clamp(108.0, 220.0);
  }
}

class _ServiceGrid extends StatelessWidget {
  const _ServiceGrid({
    required this.twoColumns,
    this.cardHeight,
    this.expandRows = false,
    this.expandColumn = false,
    this.maxCardHeight = 200,
    this.minCardHeight = 176,
  });

  final bool twoColumns;
  final double? cardHeight;
  final bool expandRows;
  final bool expandColumn;
  final double maxCardHeight;
  final double minCardHeight;

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
    return CustomerLanguageBuilder(
      builder: (context, language) {
    final cards = <Widget>[
      for (final service in _services)
        CustomerServiceCard(
          cardKey: Key('customer_home_service_${service.key}'),
          title: service.label.of(language),
          asset: service.asset,
          icon: service.icon,
          height: expandRows ? null : cardHeight,
          onTap: () => _open(context, service.key),
        ),
    ];

    if (!twoColumns) {
      if (expandColumn) {
        return LayoutBuilder(
          builder: (context, constraints) {
            const spacing = 12.0;
            final raw =
                (constraints.maxHeight - spacing * (cards.length - 1)) /
                cards.length;
            final height = raw.clamp(minCardHeight, maxCardHeight);
            if (raw < minCardHeight) {
              return ListView(
                children: _stackedCards(cards, height: minCardHeight),
              );
            }
            return Column(
              children: _stackedCards(cards, height: height),
            );
          },
        );
      }
      return Column(children: _stackedCards(cards, height: cardHeight));
    }

    final rows = <Widget>[
      for (var i = 0; i < cards.length; i += 2)
        Row(
          crossAxisAlignment: expandRows
              ? CrossAxisAlignment.stretch
              : CrossAxisAlignment.start,
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
    ];

    if (expandRows) {
      return Column(
        children: <Widget>[
          for (var i = 0; i < rows.length; i++) ...<Widget>[
            if (i > 0) const SizedBox(height: 12),
            Expanded(child: rows[i]),
          ],
        ],
      );
    }

    return Column(
      children: <Widget>[
        for (var i = 0; i < rows.length; i++) ...<Widget>[
          if (i > 0) const SizedBox(height: 12),
          rows[i],
        ],
      ],
    );
      },
    );
  }

  List<Widget> _stackedCards(List<Widget> cards, {double? height}) {
    return <Widget>[
      for (var i = 0; i < cards.length; i++) ...<Widget>[
        if (i > 0) const SizedBox(height: 12),
        if (height != null) SizedBox(height: height, child: cards[i]) else cards[i],
      ],
    ];
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
    required this.sideBySideCta,
    required this.onBookTaxi,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final CustomerThemePalette palette;
  final bool searching;
  final bool canSearch;
  final bool noResults;
  final List<FluxidiAddressSuggestion> suggestions;
  final ValueChanged<FluxidiAddressSuggestion> onPick;
  final bool sideBySideCta;
  final VoidCallback onBookTaxi;

  @override
  Widget build(BuildContext context) {
    final field = _addressField();
    final button = SizedBox(
      height: 56,
      child: FilledButton.icon(
        key: const Key('customer_home_book_taxi'),
        onPressed: onBookTaxi,
        icon: const Icon(Icons.local_taxi_outlined),
        label: Text(CustomerText.bookTaxi.current),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (sideBySideCta)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(child: field),
              const SizedBox(width: 12),
              SizedBox(width: 236, child: button),
            ],
          )
        else ...<Widget>[field, const SizedBox(height: 12), button],
        if (!canSearch)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              CustomerText.noMapboxToken.current,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: palette.textMuted),
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
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: palette.textMuted),
            ),
          ),
      ],
    );
  }

  Widget _addressField() {
    return TextField(
      key: const Key('customer_home_destination'),
      controller: controller,
      focusNode: focusNode,
      textInputAction: TextInputAction.search,
      style: TextStyle(color: palette.textPrimary, fontWeight: FontWeight.w600),
      cursorColor: palette.gold,
      decoration: InputDecoration(
        hintText: CustomerText.destinationHint.current,
        hintStyle: TextStyle(color: palette.textMuted),
        filled: true,
        fillColor: palette.surface,
        prefixIcon: Icon(Icons.place_outlined, color: palette.textMuted),
        suffixIcon: searching
            ? Padding(
                padding: const EdgeInsets.all(12),
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: palette.gold,
                  ),
                ),
              )
            : (controller.text.isEmpty
                  ? null
                  : IconButton(
                      icon: Icon(Icons.close, color: palette.textMuted),
                      onPressed: controller.clear,
                    )),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(28),
          borderSide: BorderSide(color: palette.border, width: 1.2),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(28),
          borderSide: BorderSide(color: palette.gold, width: 1.6),
        ),
      ),
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
