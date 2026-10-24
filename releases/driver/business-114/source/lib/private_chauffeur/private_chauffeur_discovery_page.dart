import 'package:fluxidi_tracking/customer_booking/official_address_lookup.dart';
// Privéchauffeur company search. Reuses the limousine place field and the
// public company card, then stops on a held selection. It does not open the
// limousine showroom, the taxi booking flow, or POST /book.

import 'dart:async';

import 'package:flutter/material.dart';

import '../app_strings.dart';
import '../customer_theme_palette.dart';
import '../customer_theme_store.dart';
import '../limousine/limousine_address_field.dart';
import '../limousine/limousine_address_lookup.dart';
import '../limousine/limousine_current_location.dart';
import '../limousine/limousine_customer_discovery.dart';
import '../limousine/limousine_p2d4c1a_ux.dart';
import '../limousine/limousine_public_company_card.dart';
import 'private_chauffeur_assets.dart';
import 'private_chauffeur_capability.dart';
import 'private_chauffeur_discovery_api.dart';
import 'private_chauffeur_labels.dart';
import 'private_chauffeur_selection_page.dart';

const Key kPrivateChauffeurDiscoveryPageKey = ValueKey<String>(
  'private_chauffeur_discovery_page',
);
const Key kPrivateChauffeurSearchActionKey = ValueKey<String>(
  'private_chauffeur_search',
);
const Key kPrivateChauffeurEmptyKey = ValueKey<String>(
  'private_chauffeur_empty',
);
const Key kPrivateChauffeurNeedPlaceKey = ValueKey<String>(
  'private_chauffeur_need_place',
);
const Key kPrivateChauffeurNetworkKey = ValueKey<String>(
  'private_chauffeur_network',
);
const Key kPrivateChauffeurUnavailableKey = ValueKey<String>(
  'private_chauffeur_unavailable',
);

Key privateChauffeurChooseKey(String partnerId) =>
    ValueKey<String>('private_chauffeur_choose_$partnerId');

void openPrivateChauffeurDiscovery(
  BuildContext context, {
  PrivateChauffeurDiscoveryGateway? gateway,
  LimousinePlaceLookup? placeLookup,
  LimousineCurrentLocationPlatform? currentLocationPlatform,
}) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => PrivateChauffeurDiscoveryPage(
        gateway: gateway,
        placeLookup: placeLookup,
        currentLocationPlatform: currentLocationPlatform,
      ),
    ),
  );
}

class PrivateChauffeurDiscoveryPage extends StatefulWidget {
  const PrivateChauffeurDiscoveryPage({
    super.key,
    this.gateway,
    this.controller,
    this.placeLookup,
    this.currentLocationPlatform,
  });

  final PrivateChauffeurDiscoveryGateway? gateway;
  final PrivateChauffeurDiscoveryController? controller;
  final LimousinePlaceLookup? placeLookup;
  final LimousineCurrentLocationPlatform? currentLocationPlatform;

  @override
  State<PrivateChauffeurDiscoveryPage> createState() =>
      _PrivateChauffeurDiscoveryPageState();
}

class _PrivateChauffeurDiscoveryPageState
    extends State<PrivateChauffeurDiscoveryPage> {
  late final PrivateChauffeurDiscoveryController _controller;
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
        PrivateChauffeurDiscoveryController(
          gateway: widget.gateway ?? HttpPrivateChauffeurDiscoveryGateway(),
        );
    _ownsPlaceLookup = widget.placeLookup == null;
    _placeLookup = widget.placeLookup ?? OfficialAddressLookup(operatorSession: false);
    _location = LimousineCurrentLocationResolver(
      lookup: _placeLookup,
      platform: widget.currentLocationPlatform,
    );
    _place = LimousineAddressFieldController(
      lookup: _placeLookup,
      fieldId: 'private_chauffeur',
      language: _lang.name,
      currentLocation: _location,
    );
    _place.addListener(_onPlaceChanged);
    _controller.addListener(_onControllerChanged);
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

  Future<void> _choose(LimousineDiscoveryCard card) async {
    final profile = await _controller.confirmProfile(card);
    if (!mounted || profile == null) return;
    final name = privateChauffeurCompanyName(profile);
    final selection = PrivateChauffeurSelection(
      publicPartnerId: privateChauffeurPartnerId(profile),
      companyName: name.isEmpty ? card.companyName : name,
      serviceCode: kPrivateChauffeurServiceCode,
    );
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => PrivateChauffeurSelectionPage(selection: selection),
      ),
    );
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
            final size = MediaQuery.sizeOf(context);
            final banner = privateChauffeurBannerAsset(
              width: size.width,
              shortestSide: size.shortestSide,
            );
            return Scaffold(
              key: kPrivateChauffeurDiscoveryPageKey,
              backgroundColor: tokens.background,
              body: CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(child: _hero(tokens, banner)),
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(
                      size.shortestSide >= 600 ? 28 : 16,
                      20,
                      size.shortestSide >= 600 ? 28 : 16,
                      28,
                    ),
                    sliver: SliverToBoxAdapter(
                      child: Align(
                        alignment: Alignment.topCenter,
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: size.shortestSide >= 600 ? 960 : 720,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                _t(kPrivateChauffeurTitle),
                                style: TextStyle(
                                  color: tokens.onSurface,
                                  fontSize: 28,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                _t(kPrivateChauffeurDiscoverySubtitle),
                                style: TextStyle(
                                  color: tokens.muted,
                                  height: 1.4,
                                ),
                              ),
                              const SizedBox(height: 16),
                              LimousineAddressField(
                                controller: _place,
                                label: _t(kPrivateChauffeurSearchLabel),
                                tokens: tokens,
                                language: _lang,
                                showCurrentLocation: true,
                                inputKey: const Key('private_chauffeur_place'),
                              ),
                              const SizedBox(height: 8),
                              Align(
                                alignment: Alignment.centerRight,
                                child: FilledButton(
                                  key: kPrivateChauffeurSearchActionKey,
                                  onPressed: _controller.isSearching
                                      ? null
                                      : _searchFromField,
                                  style: FilledButton.styleFrom(
                                    backgroundColor: tokens.gold,
                                    foregroundColor: const Color(0xFF1A1408),
                                  ),
                                  child: Text(
                                    _t(kPrivateChauffeurSearchAction),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 20),
                              _body(tokens),
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
        );
      },
    );
  }

  Widget _hero(LimousineUxTokens tokens, String banner) {
    return SizedBox(
      height: 220,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            banner,
            fit: BoxFit.cover,
            alignment: const Alignment(0.25, 0),
            errorBuilder: (_, __, ___) => ColoredBox(color: tokens.surfaceAlt),
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: <Color>[Color(0x66000000), Color(0xCC000000)],
              ),
            ),
          ),
          SafeArea(
            child: Align(
              alignment: Alignment.topLeft,
              child: IconButton(
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.arrow_back, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _body(LimousineUxTokens tokens) {
    switch (_controller.phase) {
      case PrivateChauffeurDiscoveryPhase.idle:
      case PrivateChauffeurDiscoveryPhase.needPlace:
        return _note(
          key: kPrivateChauffeurNeedPlaceKey,
          tokens: tokens,
          text: _t(kPrivateChauffeurNeedPlace),
        );
      case PrivateChauffeurDiscoveryPhase.loading:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Column(
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 12),
              Text(
                _t(kPrivateChauffeurLoading),
                style: TextStyle(color: tokens.muted),
              ),
            ],
          ),
        );
      case PrivateChauffeurDiscoveryPhase.network:
        return _note(
          key: kPrivateChauffeurNetworkKey,
          tokens: tokens,
          text: _t(kPrivateChauffeurNetwork),
        );
      case PrivateChauffeurDiscoveryPhase.empty:
        return _note(
          key: kPrivateChauffeurEmptyKey,
          tokens: tokens,
          title: _t(kPrivateChauffeurEmptyTitle),
          text: _t(kPrivateChauffeurEmptyBody),
        );
      case PrivateChauffeurDiscoveryPhase.ready:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_controller.unavailablePartnerId.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _note(
                  key: kPrivateChauffeurUnavailableKey,
                  tokens: tokens,
                  text: _t(kPrivateChauffeurUnavailable),
                ),
              ),
            for (final card in _controller.cards) ...[
              LimousinePublicCompanyCard(
                card: card,
                tokens: tokens,
                language: _lang,
                horizontal: MediaQuery.sizeOf(context).shortestSide >= 600,
                showActions: false,
              ),
              const SizedBox(height: 8),
              FilledButton(
                key: privateChauffeurChooseKey(card.publicPartnerId),
                onPressed: _controller.openingProfile
                    ? null
                    : () => _choose(card),
                style: FilledButton.styleFrom(
                  backgroundColor: tokens.gold,
                  foregroundColor: const Color(0xFF1A1408),
                  minimumSize: const Size.fromHeight(46),
                ),
                child: Text(_t(kPrivateChauffeurChoose)),
              ),
              const SizedBox(height: 16),
            ],
          ],
        );
    }
  }

  Widget _note({
    required Key key,
    required LimousineUxTokens tokens,
    required String text,
    String? title,
  }) {
    return Container(
      key: key,
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: tokens.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null) ...[
            Text(
              title,
              style: TextStyle(
                color: tokens.onSurface,
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
          ],
          Text(
            text,
            style: TextStyle(color: tokens.muted, height: 1.45, fontSize: 15),
          ),
        ],
      ),
    );
  }
}
