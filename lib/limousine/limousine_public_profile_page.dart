import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_config.dart';
import '../app_strings.dart';
import '../customer_theme_palette.dart';
import '../customer_theme_store.dart';
import '../nearby/public_partner_identity.dart';
import '../nearby/public_partner_market.dart';
import 'limousine_customer_discovery.dart';
import 'limousine_customer_discovery_labels.dart';
import 'limousine_p2d4c1a_ux.dart';
import 'limousine_provider_showroom.dart';
import 'limousine_provider_showroom_labels.dart';
import 'limousine_provider_showroom_page.dart';
import 'limousine_public_hero_overlay.dart';
import 'limousine_public_profile.dart';
import 'limousine_vehicle_media.dart';

class LimousinePublicProfilePage extends StatelessWidget {
  const LimousinePublicProfilePage({
    super.key,
    required this.profile,
    required this.partnerId,
    this.companyNameFallback = '',
    this.distanceKm,
    this.discoveryCard,
    this.logoImage,
    this.onOpenShowroom,
    this.market = PublicPartnerMarket.limousine,
  });

  final Map<String, dynamic> profile;
  final String partnerId;
  final String companyNameFallback;
  final PublicPartnerMarket market;
  final ImageProvider? logoImage;
  final double? distanceKm;
  final LimousineDiscoveryCard? discoveryCard;
  final VoidCallback? onOpenShowroom;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppLanguage>(
      valueListenable: appLanguageNotifier,
      builder: (context, language, _) {
        return ValueListenableBuilder<CustomerThemeVariant>(
          valueListenable: customerThemeNotifier,
          builder: (context, variant, _) {
            final tokens = LimousineUxTokens.fromCustomer(
              paletteForCustomerTheme(variant),
            );
            final data = buildLimousinePublicProfileData(
              profile: profile,
              partnerIdFallback: partnerId,
              companyNameFallback: companyNameFallback,
              distanceKm: distanceKm,
              discoveryCard: discoveryCard,
              language: language,
            );
            final tablet = MediaQuery.sizeOf(context).shortestSide >= 600;
            return Scaffold(
              key: kLimousinePublicProfilePageKey,
              backgroundColor: tokens.background,
              body: CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(child: _hero(context, tokens, data)),
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(
                      tablet ? 28 : 16,
                      20,
                      tablet ? 28 : 16,
                      32,
                    ),
                    sliver: SliverToBoxAdapter(
                      child: Align(
                        alignment: Alignment.topCenter,
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: tablet ? 1280 : 720,
                          ),
                          child: _body(context, tokens, data, tablet, language),
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

  Widget _hero(
    BuildContext context,
    LimousineUxTokens tokens,
    LimousinePublicProfileData data,
  ) {
    final showroom = data.showroom;
    final identity = resolvePublicPartnerHeroIdentity(
      logoUrl: showroom.logoUrl,
      logoImage: logoImage,
      companyName: showroom.companyName,
      description: showroom.tagline.isNotEmpty
          ? showroom.tagline
          : showroom.description,
    );
    return Stack(
      children: [
        LimousineContainPhoto(
          key: kLimousinePublicProfileHeroKey,
          imageUrl: showroom.heroPhotoUrl,
          background: tokens.surfaceAlt,
          gold: tokens.gold,
          minHeight: 260,
          aspectRatio: 16 / 8,
          borderRadius: 0,
          placeholderLabel: '',
          fit: showroom.heroIsExplicit ? BoxFit.cover : BoxFit.contain,
          alignment: showroom.heroAlignment,
        ),
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withOpacity(0.08),
                  Colors.transparent,
                  tokens.heroScrim.withOpacity(0.55),
                ],
                stops: const <double>[0, 0.42, 1],
              ),
            ),
          ),
        ),
        SafeArea(
          bottom: false,
          child: Align(
            alignment: Alignment.topLeft,
            child: IconButton(
              color: tokens.onHero,
              onPressed: () => Navigator.of(context).maybePop(),
              icon: const Icon(Icons.arrow_back),
            ),
          ),
        ),
        Positioned.fill(
          child: LimousinePublicHeroOverlay(
            identity: identity,
            tokens: tokens,
            includeTopSafeArea: true,
            verified: showroom.verifiedPartner,
          ),
        ),
      ],
    );
  }

  Widget _body(
    BuildContext context,
    LimousineUxTokens tokens,
    LimousinePublicProfileData data,
    bool tablet,
    AppLanguage language,
  ) {
    final showroom = data.showroom;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (data.hasPublicRating) ...[
          Text(
            '${data.ratingAverage!.toStringAsFixed(1)} · ${data.ratingCount} ${kLimousinePublicProfileReviews.of(language)}',
            style: TextStyle(
              color: tokens.gold,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
        ],
        if (data.serviceRegion.isNotEmpty || showroom.distanceKm != null)
          Text(
            [
              if (data.serviceRegion.isNotEmpty)
                '${kLimousinePublicProfileRegion.of(language)}: ${data.serviceRegion}',
              if (showroom.distanceKm != null)
                limousineDiscoveryDistanceLabel(showroom.distanceKm!, language),
            ].join(' · '),
            style: TextStyle(color: tokens.muted, height: 1.4),
          ),
        if (showroom.tagline.isNotEmpty) ...[
          const SizedBox(height: 14),
          Text(
            showroom.tagline,
            style: TextStyle(
              color: tokens.onSurface,
              fontSize: 17,
              fontWeight: FontWeight.w600,
              height: 1.35,
            ),
          ),
        ],
        if (showroom.description.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(
            showroom.description,
            style: TextStyle(
              color: tokens.onSurface,
              height: 1.45,
              fontSize: 15,
            ),
          ),
        ],
        if (data.hasPublicContact) ...[
          const SizedBox(height: 22),
          Text(
            kLimousinePublicProfileContact.of(language),
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
            runSpacing: 10,
            children: [
              if (data.websiteUrl.isNotEmpty)
                _contactChip(
                  tokens,
                  kLimousinePublicProfileWebsite.of(language),
                  data.websiteUrl,
                  () => _openUri(Uri.parse(data.websiteUrl)),
                ),
              if (data.publicPhone.isNotEmpty)
                _contactChip(
                  tokens,
                  kLimousinePublicProfilePhone.of(language),
                  data.publicPhone,
                  () => _openUri(Uri(scheme: 'tel', path: data.publicPhone)),
                ),
              if (data.bookingEmail.isNotEmpty)
                _contactChip(
                  tokens,
                  kLimousinePublicProfileEmail.of(language),
                  data.bookingEmail,
                  () =>
                      _openUri(Uri(scheme: 'mailto', path: data.bookingEmail)),
                ),
            ],
          ),
        ],
        const SizedBox(height: 26),
        Text(
          kLimousinePublicProfileFleet.of(language),
          style: TextStyle(
            color: tokens.onSurface,
            fontSize: 22,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 14),
        if (showroom.vehicles.isEmpty)
          Text(
            kLimousineProviderShowroomEmpty.of(language),
            style: TextStyle(color: tokens.muted, height: 1.4),
          )
        else
          Column(
            key: kLimousinePublicProfileFleetKey,
            children: [
              for (final vehicle in showroom.vehicles.take(3)) ...[
                _previewCard(tokens, vehicle, tablet, language),
                const SizedBox(height: 14),
              ],
            ],
          ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            key: kLimousinePublicProfileOffersCtaKey,
            onPressed: () => _openShowroom(context),
            style: FilledButton.styleFrom(
              backgroundColor: tokens.gold,
              foregroundColor: const Color(0xFF1A1408),
              minimumSize: const Size.fromHeight(48),
            ),
            child: Text(kLimousineDiscoveryViewOffers.of(language)),
          ),
        ),
      ],
    );
  }

  Widget _previewCard(
    LimousineUxTokens tokens,
    LimousineShowroomVehicle vehicle,
    bool tablet,
    AppLanguage language,
  ) {
    final title = vehicle.displayName.isEmpty
        ? limousineDiscoveryServiceClassLabel(vehicle.serviceClassId)
        : vehicle.displayName;
    final photo = LimousineContainPhoto(
      imageUrl: vehicle.primaryPhotoUrl,
      background: tokens.surfaceAlt,
      gold: tokens.gold,
      minHeight: tablet ? 220 : 200,
      aspectRatio: tablet ? 16 / 10 : 16 / 9,
      placeholderLabel: title,
    );
    final info = Padding(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: tokens.onSurface,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            [
              if (vehicle.serviceClassId.isNotEmpty)
                limousineDiscoveryServiceClassLabel(vehicle.serviceClassId),
              if (vehicle.passengerCapacity != null)
                '${vehicle.passengerCapacity} ${kLimousineDiscoveryPassengers.of(language)}',
              if (vehicle.luggageCapacity != null)
                '${vehicle.luggageCapacity} ${kLimousineDiscoveryLuggage.of(language)}',
            ].join(' · '),
            style: TextStyle(color: tokens.muted, height: 1.35),
          ),
        ],
      ),
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: tokens.border),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [tokens.surface, tokens.surfaceAlt.withOpacity(0.5)],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: tablet
            ? IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(flex: 11, child: photo),
                    const SizedBox(width: 14),
                    Expanded(flex: 9, child: info),
                  ],
                ),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [photo, const SizedBox(height: 10), info],
              ),
      ),
    );
  }

  Widget _contactChip(
    LimousineUxTokens tokens,
    String label,
    String value,
    VoidCallback onPressed,
  ) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: tokens.onSurface,
        side: BorderSide(color: tokens.border),
      ),
      child: Text('$label: $value'),
    );
  }

  Future<void> _openUri(Uri uri) async {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  void _openShowroom(BuildContext context) {
    final onOpen = onOpenShowroom;
    if (onOpen != null) {
      onOpen();
      return;
    }
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        settings: publicPartnerMarketRouteSettings(
          partnerId: partnerId,
          market: market,
        ),
        builder: (_) => LimousineProviderShowroomPage(
          partnerId: partnerId,
          companyNameFallback: companyNameFallback,
          profile: profile,
          distanceKm: distanceKm,
          discoveryCard: discoveryCard,
          market: market,
        ),
      ),
    );
  }
}
