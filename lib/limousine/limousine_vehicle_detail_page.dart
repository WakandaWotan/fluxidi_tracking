import 'package:flutter/material.dart';

import '../app_config.dart';
import '../app_strings.dart';
import '../customer_theme_palette.dart';
import '../customer_theme_store.dart';
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
import 'limousine_vehicle_media.dart';

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
  });

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
    final comfort = limousineMeaningfulComfortFeatures(
      vehicle.features,
      language: _lang,
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
        const SizedBox(height: 16),
        Text(
          key: kLimousineDetailVehicleTitleKey,
          title.isEmpty ? _t(kLimousineProviderShowroomTitle) : title,
          style: TextStyle(
            color: tokens.onSurface,
            fontSize: 28,
            fontWeight: FontWeight.w700,
            height: 1.15,
          ),
        ),
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
        if (comfort.isNotEmpty) ...[
          const SizedBox(height: 14),
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
              const SizedBox(height: 6),
              Text(
                comfort.join(' · '),
                style: TextStyle(color: tokens.muted, height: 1.4),
              ),
            ],
          ),
        ],
        const SizedBox(height: 22),
        _prices(tokens),
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

  Widget _prices(LimousineUxTokens tokens) {
    final offers = limousineSortPublishedOffers(widget.vehicle.offers);
    return Column(
      key: kLimousineDetailPricesSectionKey,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          _t(kLimousineDetailPricesHeading),
          style: TextStyle(
            color: tokens.onSurface,
            fontSize: 20,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 12),
        if (offers.isEmpty)
          Text(
            key: kLimousineDetailOfferPriceKey,
            kLimousineShowroomPriceOnRequest.of(_lang),
            style: TextStyle(
              color: tokens.gold,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          )
        else
          for (final offer in offers) ...[
            _offerCard(tokens, offer),
            const SizedBox(height: 12),
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
    final kindLabel = limousineOfferKindLabel(kind, _lang);
    final priceLabel = limousineFormatPublishedOfferPrice(offer, _lang);
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
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: tokens.border),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
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
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 6),
            ],
            if (title.isNotEmpty &&
                !generic &&
                !limousinePublicLabelsMatch(title, priceLabel)) ...[
              Text(
                title,
                style: TextStyle(
                  color: tokens.onSurface,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
            ],
            if (description.isNotEmpty && !generic) ...[
              Text(
                description,
                style: TextStyle(color: tokens.muted, height: 1.4),
              ),
              const SizedBox(height: 6),
            ],
            const SizedBox(height: 4),
            Text(
              key: kLimousineDetailOfferPriceKey,
              priceLabel,
              style: TextStyle(
                color: tokens.gold,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (kind == LimousineOfferDisplayKind.fromPrice) ...[
              const SizedBox(height: 6),
              Text(
                _t(kLimousineOfferFromPriceDisclaimer),
                style: TextStyle(color: tokens.muted, fontSize: 12.5),
              ),
            ],
            if (included.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                included,
                style: TextStyle(color: tokens.onSurface, height: 1.35),
              ),
            ],
            if (cta != LimousineShowroomCta.none) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
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
                    minimumSize: const Size.fromHeight(46),
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

  Widget _spec(LimousineUxTokens tokens, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: tokens.border),
      ),
      child: Text(
        text,
        style: TextStyle(color: tokens.onSurface, fontSize: 13.5),
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
