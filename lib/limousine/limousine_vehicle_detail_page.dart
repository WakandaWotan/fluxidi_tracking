import 'package:flutter/material.dart';

import '../app_config.dart';
import '../app_strings.dart';
import '../nearby/public_partner_market.dart';
import '../customer_theme_palette.dart';
import '../customer_theme_store.dart';
import 'limousine_adaptive_vehicle_photo.dart';
import 'limousine_brand_logo.dart';
import 'limousine_customer_discovery.dart';
import 'limousine_customer_discovery_labels.dart';
import 'limousine_customer_quote.dart';
import 'limousine_customer_quote_page.dart';
import 'limousine_offer_binding.dart';
import 'limousine_p2d4c1a_ux.dart';
import 'limousine_provider_showroom.dart';
import 'limousine_provider_showroom_labels.dart';
import 'limousine_public_copy.dart';
import 'limousine_public_showroom.dart';
import 'limousine_public_showroom_labels.dart';
import 'limousine_quote_inbox.dart';
import 'limousine_vehicle_public_copy.dart';

class LimousineVehicleDetailPage extends StatefulWidget {
  const LimousineVehicleDetailPage({
    super.key,
    required this.vehicle,
    required this.companyName,
    required this.partnerId,
    this.verifiedPartner = false,
    this.logoUrl = '',
    this.logoImage,
    this.quoteEnabled = kLimousineCustomerQuoteGateEnabled,
    this.manualQuoteEnabled = kLimousineCustomerManualQuoteGateEnabled,
    this.bookEnabled = kLimousineCustomerBookGateEnabled,
    this.onQuote,
    this.onBook,
    this.market = PublicPartnerMarket.limousine,
    this.photoSourceSizes,
    this.photoImages,
  });

  final PublicPartnerMarket market;
  final LimousineShowroomVehicle vehicle;
  final String companyName;
  final String partnerId;
  final bool verifiedPartner;
  final String logoUrl;
  final ImageProvider? logoImage;
  final bool quoteEnabled;
  final bool manualQuoteEnabled;
  final bool bookEnabled;
  final ValueChanged<LimousinePublishedOffer>? onQuote;
  final ValueChanged<LimousinePublishedOffer>? onBook;
  final Map<String, Size>? photoSourceSizes;
  final List<ImageProvider>? photoImages;

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
            return KeyedSubtree(
              key: publicPartnerProfilePageKey(widget.market),
              child: Scaffold(
                key: kLimousineVehicleDetailPageKey,
                backgroundColor: tokens.background,
                body: Column(
                  children: [
                    Expanded(
                      child: CustomScrollView(
                        slivers: [
                          SliverToBoxAdapter(child: _hero(tokens)),
                          SliverPadding(
                            padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
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
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Size? _sourceSizeFor(String url) => widget.photoSourceSizes?[url];

  ImageProvider? _imageFor(int index) {
    final images = widget.photoImages;
    if (images == null || index < 0 || index >= images.length) return null;
    return images[index];
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
              _adaptivePage(
                tokens,
                photos: photos,
              )
            else
              _slide(
                tokens,
                url: widget.vehicle.primaryPhotoUrl,
                index: 0,
                onTap: photos.isEmpty
                    ? null
                    : () => _openFullscreen(photos, 0),
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
                  key: limousineDetailGalleryThumbKey(index),
                  onTap: () {
                    _gallery.animateToPage(
                      index,
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOut,
                    );
                    _openFullscreen(photos, index);
                  },
                  child: Semantics(
                    button: true,
                    selected: selected,
                    label: widget.vehicle.displayName,
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
                        child: SizedBox(
                          width: 88,
                          height: 56,
                          child: _thumbImage(tokens, photos[index], index),
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

  Widget _adaptivePage(
    LimousineUxTokens tokens, {
    required List<String> photos,
  }) {
    final currentUrl = photos[_page.clamp(0, photos.length - 1)];
    final height = limousineAdaptiveHeroHeight(
      viewport: MediaQuery.sizeOf(context),
      sourceSize: _sourceSizeFor(currentUrl) ?? const Size(16, 9),
    );
    return SizedBox(
      key: kLimousineDetailGalleryKey,
      height: height,
      child: PageView.builder(
        controller: _gallery,
        itemCount: photos.length,
        onPageChanged: (index) => setState(() => _page = index),
        itemBuilder: (_, index) => _slide(
          tokens,
          url: photos[index],
          index: index,
          fillParent: true,
          onTap: () => _openFullscreen(photos, index),
        ),
      ),
    );
  }

  Widget _slide(
    LimousineUxTokens tokens, {
    required String url,
    required int index,
    VoidCallback? onTap,
    bool fillParent = false,
  }) {
    return LimousineAdaptiveVehiclePhoto(
      imageUrl: url,
      image: _imageFor(index),
      sourceSize: _sourceSizeFor(url),
      fillParent: fillParent,
      background: tokens.surfaceAlt,
      gold: tokens.gold,
      placeholderLabel: widget.vehicle.displayName,
      semanticLabel: widget.vehicle.displayName,
      onTap: onTap,
    );
  }

  Widget _thumbImage(LimousineUxTokens tokens, String url, int index) {
    final image = _imageFor(index);
    if (image != null) {
      return Image(image: image, width: 88, height: 56, fit: BoxFit.contain);
    }
    return Image.network(
      url,
      width: 88,
      height: 56,
      fit: BoxFit.contain,
      errorBuilder: (_, __, ___) => SizedBox(
        width: 88,
        height: 56,
        child: ColoredBox(color: tokens.surfaceAlt),
      ),
    );
  }

  void _openFullscreen(List<String> photos, int index) {
    if (photos.isEmpty) return;
    setState(() => _page = index);
    if (_gallery.hasClients && _gallery.page?.round() != index) {
      _gallery.jumpToPage(index);
    }
    openLimousineVehiclePhotoViewer(
      context: context,
      photos: photos,
      initialIndex: index,
      semanticLabel: widget.vehicle.displayName,
      images: widget.photoImages,
    );
  }

  Widget _body(LimousineUxTokens tokens) {
    final vehicle = widget.vehicle;
    final title = vehicle.displayName.isEmpty
        ? limousineDiscoveryServiceClassLabel(vehicle.serviceClassId)
        : vehicle.displayName;
    final comfort = limousineMeaningfulComfortFeatures(
      vehicle.features,
      language: _lang,
    );
    final about = limousineResolvePublicCopyText(
      vehicle.publicDescription,
      _lang,
    );
    final classLabel = limousineServiceClassLabel(
      vehicle.serviceClassId,
      _lang,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: LimousineCompanyIdentity(
                logoUrl: widget.logoUrl,
                companyName: widget.companyName,
                tokens: tokens,
                logoImage: widget.logoImage,
                surface: LimousineCompanyIdentitySurface.vehicleDetail,
              ),
            ),
            if (widget.verifiedPartner)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Icon(
                  Icons.verified,
                  color: tokens.gold,
                  size: 18,
                  semanticLabel: kLimousineDiscoveryVerified.of(_lang),
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          key: kLimousineDetailVehicleTitleKey,
          title.isEmpty ? _t(kLimousineProviderShowroomTitle) : title,
          style: TextStyle(
            color: tokens.onSurface,
            fontSize: 24,
            fontWeight: FontWeight.w700,
            height: 1.15,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            if (classLabel.isNotEmpty) _specChip(tokens, label: classLabel),
            if (vehicle.passengerCapacity != null)
              _specChip(
                tokens,
                icon: Icons.person_outline,
                label: '${vehicle.passengerCapacity}',
              ),
            if (vehicle.luggageCapacity != null)
              _specChip(
                tokens,
                icon: Icons.work_outline,
                label: '${vehicle.luggageCapacity}',
              ),
          ],
        ),
        if (comfort.isNotEmpty) ...[
          const SizedBox(height: 12),
          Column(
            key: kLimousineDetailComfortSectionKey,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _t(kLimousineShowroomComfort),
                style: TextStyle(
                  color: tokens.onSurface,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                comfort.join(' · '),
                style: TextStyle(color: tokens.muted, height: 1.35),
              ),
            ],
          ),
        ],
        if (about.isNotEmpty) ...[
          const SizedBox(height: 16),
          Column(
            key: kLimousineDetailAboutSectionKey,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _t(kLimousineDetailAboutHeading),
                style: TextStyle(
                  color: tokens.gold,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.4,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                key: kLimousineDetailAboutBodyKey,
                about,
                style: TextStyle(
                  color: tokens.onSurface,
                  height: 1.45,
                  fontSize: 15,
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 18),
        _prices(tokens),
        if (_gateMessage.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            key: kLimousineDetailGateOffBannerKey,
            _gateMessage,
            style: TextStyle(color: tokens.muted, height: 1.4),
          ),
        ],
      ],
    );
  }

  Widget _prices(LimousineUxTokens tokens) {
    final offers = limousineDeduplicatePublishedOffers(widget.vehicle.offers);
    return Column(
      key: kLimousineDetailPricesSectionKey,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          _t(kLimousineDetailPricesHeading),
          style: TextStyle(
            color: tokens.onSurface,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 10),
        if (offers.isEmpty)
          Text(
            key: kLimousineDetailOfferPriceKey,
            kLimousineShowroomPriceOnRequest.of(_lang),
            style: TextStyle(
              color: tokens.gold,
              fontSize: 17,
              fontWeight: FontWeight.w700,
            ),
          )
        else
          for (final offer in offers) ...[
            _offerCard(tokens, offer),
            const SizedBox(height: 10),
          ],
      ],
    );
  }

  Widget _offerCard(LimousineUxTokens tokens, LimousinePublishedOffer offer) {
    final kind = limousinePublishedDisplayKind(offer);
    final title = localizedLimousineText(offer.title, languageCode: _lang.name);
    final description = localizedLimousineText(
      offer.description,
      languageCode: _lang.name,
    );
    final included = limousineIncludedServicesLabel(offer, _lang);
    final generic =
        title.trim().toLowerCase() == 'limousine' ||
        description.trim().toLowerCase() ==
            'limousine / arrangementen / limousine';
    final kindLabel = limousineDetailOfferKindLabel(kind, _lang);
    final priceLabel = kind == LimousineOfferDisplayKind.fromPrice
        ? limousineFormatPublishedOfferAmount(offer, _lang)
        : limousineFormatPublishedOfferPrice(offer, _lang);
    final showKindEyebrow = limousineShouldShowOfferKindEyebrow(
      kindLabel,
      priceLabel,
    );
    final cta = limousineDetailCtaFor(offer);
    final isBook = cta == LimousineShowroomCta.book;
    final summaryId = widget.vehicle.primaryOffer?.offerId ?? '';
    final isSummary = offer.offerId == summaryId;
    return DecoratedBox(
      key: limousineDetailOfferCardKey(offer.offerId),
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: tokens.border),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (showKindEyebrow) ...[
              Text(
                key: kLimousineDetailOfferKindEyebrowKey,
                kindLabel,
                style: TextStyle(
                  color: tokens.gold,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 2),
            ],
            if (title.isNotEmpty &&
                !generic &&
                !limousinePublicLabelsMatch(title, priceLabel)) ...[
              Text(
                title,
                style: TextStyle(
                  color: tokens.onSurface,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
            ],
            if (description.isNotEmpty && !generic) ...[
              Text(
                description,
                style: TextStyle(color: tokens.muted, height: 1.35, fontSize: 13),
              ),
              const SizedBox(height: 4),
            ],
            Text(
              key: kLimousineDetailOfferPriceKey,
              priceLabel,
              style: TextStyle(
                color: tokens.gold,
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (kind == LimousineOfferDisplayKind.fromPrice) ...[
              const SizedBox(height: 4),
              Text(
                _t(kLimousineOfferFromPriceDisclaimer),
                style: TextStyle(color: tokens.muted, fontSize: 11.5, height: 1.3),
              ),
            ],
            if (included.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                included,
                style: TextStyle(color: tokens.onSurface, height: 1.3, fontSize: 13),
              ),
            ],
            if (cta != LimousineShowroomCta.none) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton(
                  key: isSummary
                      ? (isBook
                            ? kLimousineDetailBookCtaKey
                            : kLimousineDetailQuoteCtaKey)
                      : ValueKey<String>(
                          'limousine_vehicle_detail_cta_${offer.offerId}',
                        ),
                  onPressed: (isBook ? _bookOn : _quotesOn)
                      ? () => _handleCta(offer, isBook)
                      : null,
                  style: FilledButton.styleFrom(
                    backgroundColor: tokens.gold,
                    foregroundColor: const Color(0xFF1A1408),
                    disabledBackgroundColor: tokens.gold.withOpacity(0.28),
                    disabledForegroundColor: tokens.muted,
                    minimumSize: const Size(88, 44),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                  ),
                  child: Text(
                    isBook
                        ? (_bookOn
                              ? _t(kLimousineDetailBookCta)
                              : _t(kLimousineDetailBookComingSoon))
                        : (_quotesOn
                              ? _t(kLimousineDetailQuoteCta)
                              : _t(kLimousineDetailQuoteComingSoon)),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _specChip(
    LimousineUxTokens tokens, {
    IconData? icon,
    required String label,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: tokens.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: tokens.muted),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(color: tokens.onSurface, fontSize: 13),
          ),
        ],
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
        entryEnabled: _quotesOn,
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
      entryEnabled: _quotesOn,
    );
  }
}
