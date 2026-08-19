import 'package:flutter/material.dart';

import '../app_config.dart';
import '../app_strings.dart';
import '../customer_theme_palette.dart';
import '../customer_theme_store.dart';
import 'limousine_customer_discovery.dart';
import 'limousine_customer_discovery_labels.dart';
import 'limousine_customer_quote.dart';
import 'limousine_customer_quote_page.dart';
import 'limousine_p2d4c1a_ux.dart';
import 'limousine_provider_showroom.dart';
import 'limousine_provider_showroom_labels.dart';
import 'limousine_public_showroom.dart';
import 'limousine_public_showroom_labels.dart';
import 'limousine_quote_inbox.dart';
import 'limousine_vehicle_media.dart';

class LimousineVehicleDetailPage extends StatefulWidget {
  const LimousineVehicleDetailPage({
    super.key,
    required this.vehicle,
    required this.companyName,
    required this.partnerId,
    this.verifiedPartner = false,
    this.quoteEnabled = kLimousineCustomerQuoteGateEnabled,
    this.manualQuoteEnabled = kLimousineCustomerManualQuoteGateEnabled,
    this.bookEnabled = kLimousineCustomerBookGateEnabled,
    this.onQuote,
    this.onBook,
  });

  final LimousineShowroomVehicle vehicle;
  final String companyName;
  final String partnerId;
  final bool verifiedPartner;
  final bool quoteEnabled;
  final bool manualQuoteEnabled;
  final bool bookEnabled;
  final ValueChanged<LimousinePublishedOffer>? onQuote;
  final ValueChanged<LimousinePublishedOffer>? onBook;

  @override
  State<LimousineVehicleDetailPage> createState() =>
      _LimousineVehicleDetailPageState();
}

class _LimousineVehicleDetailPageState
    extends State<LimousineVehicleDetailPage> {
  final PageController _gallery = PageController();
  int _page = 0;
  String _gateMessage = '';

  AppLanguage get _lang => appLanguageNotifier.value;

  String _t(LocalizedText text) => text.of(_lang);

  bool get _quotesOn => limousineCustomerQuoteCtaEnabled(
    quoteGate: widget.quoteEnabled,
    manualQuoteGate: widget.manualQuoteEnabled,
  );

  bool get _bookOn =>
      limousineCustomerBookCtaEnabled(bookGate: widget.bookEnabled);

  @override
  void dispose() {
    _gallery.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppLanguage>(
      valueListenable: appLanguageNotifier,
      builder: (context, _, __) {
        return ValueListenableBuilder<CustomerThemeVariant>(
          valueListenable: customerThemeNotifier,
          builder: (context, variant, _) {
            final tokens = LimousineUxTokens.fromCustomer(
              paletteForCustomerTheme(variant),
            );
            return Scaffold(
              key: kLimousineVehicleDetailPageKey,
              backgroundColor: tokens.background,
              body: Column(
                children: [
                  Expanded(
                    child: CustomScrollView(
                      slivers: [
                        SliverToBoxAdapter(child: _hero(tokens)),
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
                          sliver: SliverToBoxAdapter(
                            child: Align(
                              alignment: Alignment.topCenter,
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: 880,
                                ),
                                child: _body(tokens),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  _ctaBar(tokens),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _hero(LimousineUxTokens tokens) {
    final photos = widget.vehicle.photoUrls;
    final tablet = MediaQuery.sizeOf(context).shortestSide >= 600;
    final multi = photos.length > 1;
    return Column(
      children: [
        Stack(
          children: [
            if (multi)
              SizedBox(
                key: kLimousineDetailGalleryKey,
                height: tablet ? 360 : 320,
                child: PageView.builder(
                  controller: _gallery,
                  itemCount: photos.length,
                  onPageChanged: (index) => setState(() => _page = index),
                  itemBuilder: (_, index) => GestureDetector(
                    onTap: () => _openFullscreen(tokens, photos, index),
                    child: LimousineContainPhoto(
                      imageUrl: photos[index],
                      background: tokens.surfaceAlt,
                      gold: tokens.gold,
                      minHeight: tablet ? 320 : 280,
                      aspectRatio: 16 / 9,
                      borderRadius: 0,
                      placeholderLabel: widget.vehicle.displayName,
                    ),
                  ),
                ),
              )
            else
              GestureDetector(
                onTap: photos.isEmpty
                    ? null
                    : () => _openFullscreen(tokens, photos, 0),
                child: LimousineContainPhoto(
                  imageUrl: widget.vehicle.primaryPhotoUrl,
                  background: tokens.surfaceAlt,
                  gold: tokens.gold,
                  minHeight: tablet ? 320 : 280,
                  aspectRatio: 16 / 9,
                  borderRadius: 0,
                  placeholderLabel: widget.vehicle.displayName,
                ),
              ),
            SafeArea(
              child: IconButton(
                color: tokens.onHero,
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.arrow_back),
              ),
            ),
            if (multi && tablet) ...[
              Positioned(
                left: 8,
                top: 0,
                bottom: 0,
                child: Center(
                  child: IconButton(
                    key: kLimousineDetailGalleryPrevKey,
                    color: tokens.onHero,
                    onPressed: _page == 0
                        ? null
                        : () => _gallery.animateToPage(
                            _page - 1,
                            duration: const Duration(milliseconds: 220),
                            curve: Curves.easeOut,
                          ),
                    icon: const Icon(Icons.chevron_left),
                  ),
                ),
              ),
              Positioned(
                right: 8,
                top: 0,
                bottom: 0,
                child: Center(
                  child: IconButton(
                    key: kLimousineDetailGalleryNextKey,
                    color: tokens.onHero,
                    onPressed: _page >= photos.length - 1
                        ? null
                        : () => _gallery.animateToPage(
                            _page + 1,
                            duration: const Duration(milliseconds: 220),
                            curve: Curves.easeOut,
                          ),
                    icon: const Icon(Icons.chevron_right),
                  ),
                ),
              ),
            ],
            if (multi)
              Positioned(
                left: 0,
                right: 0,
                bottom: 12,
                child: Column(
                  children: [
                    Text(
                      key: kLimousineDetailGalleryCounterKey,
                      '${_page + 1} / ${photos.length}',
                      style: TextStyle(
                        color: tokens.onHero,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        for (var i = 0; i < photos.length; i++)
                          Container(
                            width: 8,
                            height: 8,
                            margin: const EdgeInsets.symmetric(horizontal: 3),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: i == _page
                                  ? tokens.gold
                                  : tokens.onHero.withOpacity(0.35),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
          ],
        ),
        if (multi)
          SizedBox(
            key: kLimousineDetailGalleryThumbsKey,
            height: 72,
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              scrollDirection: Axis.horizontal,
              itemCount: photos.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, index) {
                final selected = index == _page;
                return GestureDetector(
                  onTap: () => _gallery.animateToPage(
                    index,
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOut,
                  ),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: selected ? tokens.gold : tokens.border,
                        width: selected ? 2 : 1,
                      ),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(9),
                      child: Image.network(
                        photos[index],
                        width: 88,
                        height: 56,
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => SizedBox(
                          width: 88,
                          height: 56,
                          child: ColoredBox(color: tokens.surfaceAlt),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }

  void _openFullscreen(
    LimousineUxTokens tokens,
    List<String> photos,
    int index,
  ) {
    if (photos.isEmpty) return;
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return Dialog(
          backgroundColor: Colors.black,
          insetPadding: const EdgeInsets.all(12),
          child: Stack(
            children: [
              LimousineContainPhoto(
                imageUrl: photos[index],
                background: Colors.black,
                gold: tokens.gold,
                minHeight: 280,
                aspectRatio: 16 / 9,
                borderRadius: 12,
                placeholderLabel: widget.vehicle.displayName,
              ),
              Positioned(
                top: 4,
                right: 4,
                child: IconButton(
                  color: Colors.white,
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  icon: const Icon(Icons.close),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _body(LimousineUxTokens tokens) {
    final vehicle = widget.vehicle;
    final title = vehicle.displayName.isEmpty
        ? limousineDiscoveryServiceClassLabel(vehicle.serviceClassId)
        : vehicle.displayName;
    final offer = vehicle.primaryOffer;
    final description = offer == null
        ? ''
        : localizedLimousineText(offer.description, languageCode: _lang.name);
    final arrangement = offer == null
        ? ''
        : localizedLimousineText(offer.title, languageCode: _lang.name);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title.isEmpty ? _t(kLimousineProviderShowroomTitle) : title,
          style: TextStyle(
            color: tokens.onSurface,
            fontSize: 28,
            fontWeight: FontWeight.w700,
            height: 1.15,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 10,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              widget.companyName,
              style: TextStyle(color: tokens.muted, fontSize: 15),
            ),
            if (widget.verifiedPartner)
              Icon(
                Icons.verified,
                color: tokens.gold,
                size: 18,
                semanticLabel: kLimousineDiscoveryVerified.of(_lang),
              ),
          ],
        ),
        if (description.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(
            description,
            style: TextStyle(color: tokens.onSurface, height: 1.45, fontSize: 15.5),
          ),
        ],
        const SizedBox(height: 22),
        Text(
          _t(kLimousineDetailSpecs),
          style: TextStyle(
            color: tokens.gold,
            fontSize: 13,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.4,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 8,
          children: [
            if (vehicle.serviceClassId.isNotEmpty)
              _spec(
                tokens,
                '${_t(kLimousineDetailClass)}: ${limousineDiscoveryServiceClassLabel(vehicle.serviceClassId)}',
              ),
            if (vehicle.passengerCapacity != null)
              _spec(
                tokens,
                '${_t(kLimousineShowroomPassengers)}: ${vehicle.passengerCapacity}',
              ),
            if (vehicle.luggageCapacity != null)
              _spec(
                tokens,
                '${_t(kLimousineShowroomLuggage)}: ${vehicle.luggageCapacity}',
              ),
            if (vehicle.color.isNotEmpty)
              _spec(
                tokens,
                '${_t(kLimousineShowroomColour)}: ${vehicle.color}',
              ),
            if (vehicle.length.isNotEmpty)
              _spec(
                tokens,
                '${_t(kLimousineShowroomLength)}: ${vehicle.length}',
              ),
          ],
        ),
        if (vehicle.features.isNotEmpty) ...[
          const SizedBox(height: 14),
          Text(
            _t(kLimousineShowroomComfort),
            style: TextStyle(
              color: tokens.onSurface,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            vehicle.features.join(' · '),
            style: TextStyle(color: tokens.muted, height: 1.4),
          ),
        ],
        if (arrangement.isNotEmpty) ...[
          const SizedBox(height: 18),
          Text(
            _t(kLimousineShowroomOffersHeading),
            style: TextStyle(
              color: tokens.onSurface,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(arrangement, style: TextStyle(color: tokens.muted)),
        ],
        const SizedBox(height: 18),
        Text(
          limousineShowroomVehiclePriceLabel(vehicle, _lang),
          style: TextStyle(
            color: tokens.gold,
            fontSize: 20,
            fontWeight: FontWeight.w700,
          ),
        ),
        if (_gateMessage.isNotEmpty) ...[
          const SizedBox(height: 14),
          Text(
            key: kLimousineDetailGateOffBannerKey,
            _gateMessage,
            style: TextStyle(color: tokens.muted, height: 1.4),
          ),
        ],
      ],
    );
  }

  Widget _spec(LimousineUxTokens tokens, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: tokens.border),
      ),
      child: Text(text, style: TextStyle(color: tokens.onSurface, fontSize: 13.5)),
    );
  }

  Widget _ctaBar(LimousineUxTokens tokens) {
    final offer = widget.vehicle.primaryOffer;
    final cta = limousineDetailCtaFor(offer);
    if (cta == LimousineShowroomCta.none || offer == null) {
      return const SizedBox.shrink();
    }
    final isBook = cta == LimousineShowroomCta.book;
    return Material(
      color: tokens.surface,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton(
              key: isBook ? kLimousineDetailBookCtaKey : kLimousineDetailQuoteCtaKey,
              onPressed: () => _handleCta(offer, isBook),
              style: FilledButton.styleFrom(
                backgroundColor: tokens.gold,
                foregroundColor: const Color(0xFF1A1408),
                minimumSize: const Size.fromHeight(48),
              ),
              child: Text(
                isBook ? _t(kLimousineDetailBookCta) : _t(kLimousineDetailQuoteCta),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _handleCta(LimousinePublishedOffer offer, bool isBook) {
    if (isBook) {
      if (!_bookOn) {
        setState(() => _gateMessage = _t(kLimousineDetailBookingsInactive));
        return;
      }
      final onBook = widget.onBook;
      if (onBook != null) {
        onBook(offer);
        return;
      }
      openLimousineCustomerQuoteFlow(
        context,
        publicPartnerId: widget.partnerId,
        offer: offer,
        companyName: widget.companyName,
        entryEnabled: true,
      );
      return;
    }
    if (!_quotesOn) {
      setState(() => _gateMessage = _t(kLimousineDetailQuotesInactive));
      return;
    }
    final onQuote = widget.onQuote;
    if (onQuote != null) {
      onQuote(offer);
      return;
    }
    openLimousineCustomerQuoteFlow(
      context,
      publicPartnerId: widget.partnerId,
      offer: offer,
      companyName: widget.companyName,
      entryEnabled: true,
    );
  }
}
