// LIMOUSINE-MARKETPLACE-P2D4C1F — customer marketplace discovery page.
// Loads recommended limousine companies without requiring a region or GPS.
// Opens the limousine provider showroom after a server-confirmed Limousine
// surface. Does not open the taxi partner profile, start the request wizard
// or call /book.

import 'dart:async';

import 'package:flutter/material.dart';

import '../app_config.dart';
import '../app_strings.dart';
import '../customer_theme_palette.dart';
import '../customer_theme_store.dart';
import 'limousine_address_field.dart';
import 'limousine_address_lookup.dart';
import 'limousine_current_location.dart';
import 'limousine_customer_discovery.dart';
import 'limousine_customer_discovery_api.dart';
import 'limousine_customer_discovery_labels.dart';
import 'limousine_p2d4c1a_ux.dart';
import 'limousine_provider_showroom_page.dart';
import 'limousine_service_capability.dart';
import 'limousine_vehicle_media.dart';

typedef LimousineDiscoveryOpenPartner =
    Future<void> Function(
      BuildContext context,
      LimousineDiscoveryCard card,
      Map<String, dynamic> profile,
    );

void openLimousineCustomerDiscovery(
  BuildContext context, {
  WidgetBuilder? customerHomeBuilder,
  LimousineDiscoveryGateway? gateway,
  LimousinePlaceLookup? placeLookup,
  LimousineCurrentLocationPlatform? currentLocationPlatform,
  LimousineDiscoveryOpenPartner? onOpenPartner,
  bool autoLoadRecommended = true,
}) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => LimousineCustomerDiscoveryPage(
        customerHomeBuilder: customerHomeBuilder,
        gateway: gateway,
        placeLookup: placeLookup,
        currentLocationPlatform: currentLocationPlatform,
        onOpenPartner: onOpenPartner,
        autoLoadRecommended: autoLoadRecommended,
      ),
    ),
  );
}

class LimousineCustomerDiscoveryPage extends StatefulWidget {
  const LimousineCustomerDiscoveryPage({
    super.key,
    this.customerHomeBuilder,
    this.gateway,
    this.controller,
    this.placeLookup,
    this.currentLocationPlatform,
    this.onOpenPartner,
    this.autoLoadRecommended = true,
  });

  final WidgetBuilder? customerHomeBuilder;
  final LimousineDiscoveryGateway? gateway;
  final LimousineDiscoveryController? controller;
  final LimousinePlaceLookup? placeLookup;
  final LimousineCurrentLocationPlatform? currentLocationPlatform;
  final LimousineDiscoveryOpenPartner? onOpenPartner;
  final bool autoLoadRecommended;

  @override
  State<LimousineCustomerDiscoveryPage> createState() =>
      _LimousineCustomerDiscoveryPageState();
}

class _LimousineCustomerDiscoveryPageState
    extends State<LimousineCustomerDiscoveryPage> {
  late final LimousineDiscoveryController _controller;
  late final bool _ownsController;
  late final LimousinePlaceLookup _placeLookup;
  late final bool _ownsPlaceLookup;
  late final LimousineAddressFieldController _place;
  late final LimousineCurrentLocationResolver _location;
  String _lastAutoSearch = '';

  AppLanguage get _lang => appLanguageNotifier.value;

  String _t(LocalizedText text) => text.of(_lang);

  @override
  void initState() {
    super.initState();
    _ownsController = widget.controller == null;
    _controller =
        widget.controller ??
        LimousineDiscoveryController(
          gateway: widget.gateway ?? HttpLimousineDiscoveryGateway(),
        );
    _ownsPlaceLookup = widget.placeLookup == null;
    _placeLookup = widget.placeLookup ?? LimousinePlaceLookup();
    _location = LimousineCurrentLocationResolver(
      lookup: _placeLookup,
      platform: widget.currentLocationPlatform,
    );
    _place = LimousineAddressFieldController(
      lookup: _placeLookup,
      fieldId: kLimousineDiscoveryFieldId,
      language: _lang.name,
      currentLocation: _location,
    );
    _place.addListener(_onPlaceChanged);
    _controller.addListener(_onControllerChanged);
    if (widget.autoLoadRecommended) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (_controller.phase != LimousineDiscoveryPhase.idle) return;
        unawaited(_controller.search(const LimousineDiscoveryQuery()));
      });
    }
  }

  @override
  void dispose() {
    _place.removeListener(_onPlaceChanged);
    _controller.removeListener(_onControllerChanged);
    _place.dispose();
    if (_ownsController) _controller.dispose();
    if (_ownsPlaceLookup) _placeLookup.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    if (mounted) setState(() {});
  }

  void _onPlaceChanged() {
    _place.language = _lang.name;
    final value = _place.value;
    if (value.acceptance != LimousineAddressAcceptance.selected) return;
    final token = '${value.canonicalLabel}|${value.lat}|${value.lon}';
    if (token == _lastAutoSearch) return;
    _lastAutoSearch = token;
    unawaited(_searchFromField());
  }

  LimousineDiscoveryQuery? _queryFromField() {
    final value = _place.value;
    return limousineDiscoveryQueryFromAddress(
      displayText: value.displayText.isNotEmpty
          ? value.displayText
          : _place.textController.text,
      lat: value.lat,
      lon: value.lon,
      explicitCurrentLocation: value.fromCurrentLocation,
    );
  }

  Future<void> _searchFromField() {
    return _controller.search(_queryFromField());
  }

  void _searchAnotherRegion() {
    _lastAutoSearch = '';
    _place.clear();
    _controller.searchAnotherRegion();
  }

  Future<void> _openPartner(LimousineDiscoveryCard card) async {
    final profile = await _controller.openConfirmedPublicProfile(card);
    if (!mounted || profile == null) return;
    final open = widget.onOpenPartner ?? _pushShowroom;
    await open(context, card, profile);
  }

  Future<void> _pushShowroom(
    BuildContext context,
    LimousineDiscoveryCard card,
    Map<String, dynamic> profile,
  ) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => LimousineProviderShowroomPage(
          partnerId: card.publicPartnerId,
          companyNameFallback: card.companyName,
          profile: profile,
          distanceKm: card.distanceKm,
          discoveryCard: card,
        ),
      ),
    );
  }

  Key _layoutKey() {
    final size = MediaQuery.sizeOf(context);
    final tablet = size.shortestSide >= 600;
    if (!tablet) return kLimousineDiscoveryPhoneLayoutKey;
    if (size.width > size.height) {
      return kLimousineDiscoveryTabletLandscapeLayoutKey;
    }
    return kLimousineDiscoveryTabletPortraitLayoutKey;
  }

  int _cardColumns(int cardCount) {
    final size = MediaQuery.sizeOf(context);
    if (size.shortestSide < 600) return 1;
    if (cardCount <= 2) return 1;
    if (size.width >= 1100) return 2;
    return 1;
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppLanguage>(
      valueListenable: appLanguageNotifier,
      builder: (context, _, __) {
        return ValueListenableBuilder<CustomerThemeVariant>(
          valueListenable: customerThemeNotifier,
          builder: (context, variant, _) {
            final palette = paletteForCustomerTheme(variant);
            final tokens = LimousineUxTokens.fromCustomer(palette);
            return Scaffold(
              key: kLimousineCustomerDiscoveryPageKey,
              backgroundColor: tokens.background,
              body: LayoutBuilder(
                builder: (context, constraints) {
                  return KeyedSubtree(
                    key: _layoutKey(),
                    child: CustomScrollView(
                      slivers: [
                        SliverToBoxAdapter(child: _hero(tokens, constraints)),
                        SliverPadding(
                          padding: EdgeInsets.fromLTRB(
                            MediaQuery.sizeOf(context).shortestSide >= 600
                                ? 28
                                : 16,
                            20,
                            MediaQuery.sizeOf(context).shortestSide >= 600
                                ? 28
                                : 16,
                            28,
                          ),
                          sliver: SliverToBoxAdapter(
                            child: Align(
                              alignment: Alignment.topCenter,
                              child: ConstrainedBox(
                                constraints: BoxConstraints(
                                  maxWidth:
                                      MediaQuery.sizeOf(context).shortestSide >=
                                          600
                                      ? 1280
                                      : 720,
                                ),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    LimousineAddressField(
                                      controller: _place,
                                      label: _t(kLimousineDiscoverySearchLabel),
                                      tokens: tokens,
                                      language: _lang,
                                      showCurrentLocation: true,
                                    ),
                                    const SizedBox(height: 8),
                                    Align(
                                      alignment: Alignment.centerRight,
                                      child: FilledButton(
                                        key: kLimousineDiscoverySearchActionKey,
                                        onPressed: _controller.isSearching
                                            ? null
                                            : _searchFromField,
                                        style: FilledButton.styleFrom(
                                          backgroundColor: tokens.gold,
                                          foregroundColor: tokens.isDark
                                              ? const Color(0xFF1A1408)
                                              : const Color(0xFF1A1408),
                                        ),
                                        child: Text(
                                          _t(kLimousineDiscoverySearchAction),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 20),
                                    _listingChrome(tokens),
                                    _body(tokens, constraints),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            );
          },
        );
      },
    );
  }

  Widget _hero(LimousineUxTokens tokens, BoxConstraints constraints) {
    final minHeight = constraints.maxWidth >= 900
        ? 280.0
        : constraints.maxWidth >= 600
        ? 240.0
        : 220.0;
    return ConstrainedBox(
      key: kLimousineDiscoveryHeroKey,
      constraints: BoxConstraints(minHeight: minHeight),
      child: Stack(
        children: [
          Positioned.fill(
            child: Image.asset(
              kLimousineMarketplaceHeroAsset,
              fit: BoxFit.cover,
              alignment: const Alignment(0.45, 0.0),
              errorBuilder: (_, __, ___) =>
                  ColoredBox(color: tokens.surfaceAlt),
            ),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    tokens.heroScrim.withOpacity(0.18),
                    tokens.heroScrim.withOpacity(0.78),
                  ],
                ),
              ),
            ),
          ),
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  IconButton(
                    tooltip: MaterialLocalizations.of(
                      context,
                    ).backButtonTooltip,
                    color: tokens.onHero,
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.arrow_back),
                  ),
                  const SizedBox(height: 24),
                  Padding(
                    padding: const EdgeInsets.only(left: 12),
                    child: Text(
                      _t(kLimousineDiscoveryTitle),
                      key: kLimousineDiscoveryTitleKey,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: tokens.onHero,
                        fontSize: 28,
                        height: 1.15,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.4,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.only(left: 12, right: 8),
                    child: Text(
                      _t(kLimousineDiscoverySubtitle),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: tokens.onHero.withOpacity(0.88),
                        fontSize: 14.5,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  bool get _showsRecommendedHeading {
    final query = _controller.lastQuery;
    if (query == null || !query.isUnscoped) return false;
    switch (_controller.phase) {
      case LimousineDiscoveryPhase.loading:
      case LimousineDiscoveryPhase.ready:
      case LimousineDiscoveryPhase.empty:
        return true;
      case LimousineDiscoveryPhase.idle:
      case LimousineDiscoveryPhase.gatesOff:
      case LimousineDiscoveryPhase.needPlace:
      case LimousineDiscoveryPhase.network:
        return false;
    }
  }

  Widget _listingChrome(LimousineUxTokens tokens) {
    final showRecommended = _showsRecommendedHeading;
    final showTestEnvironment =
        _controller.showsTestEnvironment &&
        _controller.phase == LimousineDiscoveryPhase.ready;
    if (!showRecommended && !showTestEnvironment) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showRecommended)
            Text(
              _t(kLimousineDiscoveryRecommended),
              key: kLimousineDiscoveryRecommendedKey,
              style: TextStyle(
                color: tokens.onSurface,
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
          if (showTestEnvironment) ...[
            if (showRecommended) const SizedBox(height: 6),
            Text(
              _t(kLimousineDiscoveryGatesOffTitle),
              key: kLimousineDiscoveryTestEnvironmentKey,
              style: TextStyle(
                color: tokens.gold,
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _body(LimousineUxTokens tokens, BoxConstraints constraints) {
    if (_controller.openingProfile) {
      return Padding(
        key: kLimousineDiscoveryOpeningKey,
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator(color: tokens.gold)),
      );
    }
    switch (_controller.phase) {
      case LimousineDiscoveryPhase.loading:
        if (_controller.cards.isEmpty) {
          return _status(
            key: kLimousineDiscoveryLoadingKey,
            tokens: tokens,
            title: _t(kLimousineDiscoveryLoading),
            busy: true,
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _status(
              key: kLimousineDiscoveryLoadingKey,
              tokens: tokens,
              title: _t(kLimousineDiscoveryLoading),
              busy: true,
            ),
            _cards(tokens, constraints),
          ],
        );
      case LimousineDiscoveryPhase.needPlace:
        return _status(tokens: tokens, title: _t(kLimousineDiscoveryNeedPlace));
      case LimousineDiscoveryPhase.network:
        return _status(tokens: tokens, title: _t(kLimousineDiscoveryNetwork));
      case LimousineDiscoveryPhase.gatesOff:
        return _emptyState(
          key: kLimousineDiscoveryGatesOffKey,
          tokens: tokens,
          title: _t(kLimousineDiscoveryGatesOffTitle),
          body: _t(kLimousineDiscoveryGatesOffBody),
        );
      case LimousineDiscoveryPhase.empty:
        return _emptyState(
          key: kLimousineDiscoveryEmptyKey,
          tokens: tokens,
          title: _t(kLimousineDiscoveryEmptyTitle),
          body: _t(kLimousineDiscoveryEmptyBody),
        );
      case LimousineDiscoveryPhase.ready:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_controller.profileUnavailablePartnerId.isNotEmpty)
              Padding(
                key: kLimousineDiscoveryProfileUnavailableKey,
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  _t(kLimousineDiscoveryProfileUnavailable),
                  style: TextStyle(color: tokens.danger, height: 1.35),
                ),
              ),
            _cards(tokens, constraints),
          ],
        );
      case LimousineDiscoveryPhase.idle:
        if (_controller.profileUnavailablePartnerId.isNotEmpty) {
          return Text(
            key: kLimousineDiscoveryProfileUnavailableKey,
            _t(kLimousineDiscoveryProfileUnavailable),
            style: TextStyle(color: tokens.danger, height: 1.35),
          );
        }
        return const SizedBox.shrink();
    }
  }

  Widget _status({
    Key? key,
    required LimousineUxTokens tokens,
    required String title,
    bool busy = false,
  }) {
    return Padding(
      key: key,
      padding: const EdgeInsets.symmetric(vertical: 28),
      child: Column(
        children: [
          if (busy) ...[
            CircularProgressIndicator(color: tokens.gold),
            const SizedBox(height: 16),
          ],
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(color: tokens.muted, height: 1.4, fontSize: 15),
          ),
        ],
      ),
    );
  }

  Widget _emptyState({
    required Key key,
    required LimousineUxTokens tokens,
    required String title,
    required String body,
  }) {
    return Container(
      key: key,
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: tokens.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: tokens.onSurface,
              fontSize: 20,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            body,
            style: TextStyle(color: tokens.muted, height: 1.45, fontSize: 14.5),
          ),
          const SizedBox(height: 16),
          TextButton(
            key: kLimousineDiscoverySearchOtherRegionKey,
            onPressed: _searchAnotherRegion,
            child: Text(_t(kLimousineDiscoverySearchOtherRegion)),
          ),
        ],
      ),
    );
  }

  Widget _cards(LimousineUxTokens tokens, BoxConstraints constraints) {
    final cards = _controller.cards;
    final columns = _cardColumns(cards.length);
    final tablet = MediaQuery.sizeOf(context).shortestSide >= 600;
    if (columns == 1) {
      return Column(
        key: kLimousineDiscoveryCardListKey,
        children: [
          for (final card in cards) ...[
            _ProviderCard(
              card: card,
              tokens: tokens,
              language: _lang,
              horizontal: tablet,
              onOpen: () => _openPartner(card),
            ),
            const SizedBox(height: 16),
          ],
        ],
      );
    }
    return KeyedSubtree(
      key: kLimousineDiscoveryCardListKey,
      child: Wrap(
        spacing: 16,
        runSpacing: 16,
        children: [
          for (final card in cards)
            SizedBox(
              width: (constraints.maxWidth - 16) / columns,
              child: _ProviderCard(
                card: card,
                tokens: tokens,
                language: _lang,
                horizontal: true,
                onOpen: () => _openPartner(card),
              ),
            ),
        ],
      ),
    );
  }
}

class _ProviderCard extends StatelessWidget {
  const _ProviderCard({
    required this.card,
    required this.tokens,
    required this.language,
    required this.horizontal,
    required this.onOpen,
  });

  final LimousineDiscoveryCard card;
  final LimousineUxTokens tokens;
  final AppLanguage language;
  final bool horizontal;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final info = _info();
    final photo = LimousineContainPhoto(
      imageUrl: card.coverImageUrl,
      background: tokens.surfaceAlt,
      gold: tokens.gold,
      minHeight: horizontal ? 240 : kLimousineVehiclePhotoMinHeight,
      aspectRatio: horizontal ? 16 / 10 : 16 / 9,
      placeholderLabel: card.companyName,
    );
    final body = horizontal
        ? IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(flex: 11, child: photo),
                const SizedBox(width: 16),
                Expanded(flex: 9, child: info),
              ],
            ),
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [photo, const SizedBox(height: 12), info],
          );
    return Material(
      key: limousineDiscoveryCardKey(card.publicPartnerId),
      color: tokens.surface,
      elevation: 0,
      borderRadius: BorderRadius.circular(22),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: tokens.border),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [tokens.surface, tokens.surfaceAlt.withOpacity(0.5)],
          ),
        ),
        child: Padding(padding: const EdgeInsets.all(12), child: body),
      ),
    );
  }

  Widget _info() {
    final price = limousineDiscoveryPriceLabel(card.price, language);
    final vehicleLabels = <String>[
      for (final vehicle in card.vehicles)
        [
          if (vehicle.serviceClassId.isNotEmpty)
            limousineDiscoveryServiceClassLabel(vehicle.serviceClassId),
          if (vehicle.passengerCapacity != null)
            '${vehicle.passengerCapacity} ${kLimousineDiscoveryPassengers.of(language)}',
          if (vehicle.luggageCapacity != null)
            '${vehicle.luggageCapacity} ${kLimousineDiscoveryLuggage.of(language)}',
        ].where((part) => part.isNotEmpty).join(' · '),
    ].where((part) => part.isNotEmpty).toList(growable: false);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  card.companyName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: tokens.onSurface,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (card.verifiedPartner)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Icon(
                    Icons.verified,
                    color: tokens.gold,
                    size: 20,
                    semanticLabel: kLimousineDiscoveryVerified.of(language),
                  ),
                ),
            ],
          ),
          if (card.publicCity.isNotEmpty || card.distanceKm != null) ...[
            const SizedBox(height: 4),
            Text(
              [
                if (card.publicCity.isNotEmpty) card.publicCity,
                if (card.distanceKm != null)
                  limousineDiscoveryDistanceLabel(card.distanceKm!, language),
              ].join(' · '),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: tokens.muted, fontSize: 13.5),
            ),
          ],
          if (vehicleLabels.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              vehicleLabels.join('\n'),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: tokens.muted, fontSize: 13.5, height: 1.35),
            ),
          ],
          if (price.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              price,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: tokens.gold,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              key: limousineDiscoveryViewLimousinesCtaKey(card.publicPartnerId),
              onPressed: onOpen,
              style: FilledButton.styleFrom(
                backgroundColor: tokens.gold,
                foregroundColor: const Color(0xFF1A1408),
                minimumSize: const Size.fromHeight(46),
              ),
              child: Text(kLimousineDiscoveryViewLimousines.of(language)),
            ),
          ),
        ],
      ),
    );
  }
}
