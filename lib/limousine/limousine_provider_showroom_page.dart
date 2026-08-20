import 'package:flutter/material.dart';

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
import 'limousine_public_copy.dart';
import 'limousine_public_hero_overlay.dart';
import 'limousine_quote_inbox.dart';
import 'limousine_public_profile_page.dart';
import 'limousine_vehicle_detail_page.dart';
import 'limousine_vehicle_media.dart';

class LimousineProviderShowroomPage extends StatelessWidget {
  const LimousineProviderShowroomPage({
    super.key,
    required this.profile,
    required this.partnerId,
    this.companyNameFallback = '',
    this.distanceKm,
    this.discoveryCard,
    this.logoImage,
    this.onOpenVehicle,
    this.onOpenCompanyProfile,
    this.market = PublicPartnerMarket.limousine,
  });

  final Map<String, dynamic> profile;
  final String partnerId;
  final PublicPartnerMarket market;
  final String companyNameFallback;
  final double? distanceKm;
  final LimousineDiscoveryCard? discoveryCard;
  final ImageProvider? logoImage;
  final ValueChanged<LimousineShowroomVehicle>? onOpenVehicle;
  final VoidCallback? onOpenCompanyProfile;

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
            final data = buildLimousineProviderShowroomData(
              profile: profile,
              partnerIdFallback: partnerId,
              companyNameFallback: companyNameFallback,
              distanceKm: distanceKm,
              discoveryCard: discoveryCard,
              language: language,
            );
            final tablet = MediaQuery.sizeOf(context).shortestSide >= 600;
            return Scaffold(
              key: kLimousineProviderShowroomPageKey,
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
                          child: _catalog(
                            context,
                            tokens,
                            data,
                            tablet,
                            language,
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

  Widget _hero(
    BuildContext context,
    LimousineUxTokens tokens,
    LimousineProviderShowroomData data,
  ) {
    final identity = resolvePublicPartnerHeroIdentity(
      logoUrl: data.logoUrl,
      logoImage: logoImage,
      companyName: data.companyName,
      description: data.tagline.isNotEmpty ? data.tagline : data.description,
    );
    return Stack(
      children: [
        LimousineContainPhoto(
          key: kLimousineProviderShowroomHeroKey,
          imageUrl: data.heroPhotoUrl,
          background: tokens.surfaceAlt,
          gold: tokens.gold,
          minHeight: 240,
          aspectRatio: 16 / 8,
          borderRadius: 0,
          placeholderLabel: data.companyName,
          fit: data.heroIsExplicit ? BoxFit.cover : BoxFit.contain,
          alignment: data.heroAlignment,
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
            verified: data.verifiedPartner,
            distanceLabel: data.distanceKm == null
                ? ''
                : limousineDiscoveryDistanceLabel(
                    data.distanceKm!,
                    appLanguageNotifier.value,
                  ),
          ),
        ),
      ],
    );
  }

  Widget _catalog(
    BuildContext context,
    LimousineUxTokens tokens,
    LimousineProviderShowroomData data,
    bool tablet,
    AppLanguage language,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          kLimousineProviderShowroomTitle.of(language),
          style: TextStyle(
            color: tokens.onSurface,
            fontSize: 22,
            fontWeight: FontWeight.w700,
          ),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            key: kLimousineShowroomCompanyProfileCtaKey,
            onPressed: () => _openCompanyProfile(context),
            child: Text(kLimousineShowroomViewCompanyProfile.of(language)),
          ),
        ),
        const SizedBox(height: 8),
        if (data.vehicles.isEmpty)
          Container(
            key: kLimousineProviderShowroomEmptyKey,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: tokens.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: tokens.border),
            ),
            child: Text(
              kLimousineProviderShowroomEmpty.of(language),
              style: TextStyle(color: tokens.muted, height: 1.4),
            ),
          )
        else
          Column(
            key: kLimousineProviderShowroomCatalogKey,
            children: [
              for (final vehicle in data.vehicles) ...[
                _vehicleCard(context, tokens, data, vehicle, tablet, language),
                const SizedBox(height: 16),
              ],
            ],
          ),
      ],
    );
  }

  Widget _vehicleCard(
    BuildContext context,
    LimousineUxTokens tokens,
    LimousineProviderShowroomData data,
    LimousineShowroomVehicle vehicle,
    bool tablet,
    AppLanguage language,
  ) {
    final info = _vehicleInfo(context, tokens, data, vehicle, language);
    final photo = LimousineContainPhoto(
      imageUrl: vehicle.primaryPhotoUrl,
      background: tokens.surfaceAlt,
      gold: tokens.gold,
      minHeight: tablet ? 260 : 220,
      aspectRatio: tablet ? 16 / 10 : 16 / 9,
      placeholderLabel: vehicle.displayName.isEmpty
          ? data.companyName
          : vehicle.displayName,
    );
    final card = DecoratedBox(
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: tokens.border),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [tokens.surface, tokens.surfaceAlt.withOpacity(0.55)],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: tablet
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(flex: 11, child: photo),
                  const SizedBox(width: 16),
                  Expanded(flex: 9, child: info),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [photo, const SizedBox(height: 12), info],
              ),
      ),
    );
    return KeyedSubtree(
      key: limousineShowroomVehicleCardKey(vehicle.key),
      child: tablet ? IntrinsicHeight(child: card) : card,
    );
  }

  Widget _vehicleInfo(
    BuildContext context,
    LimousineUxTokens tokens,
    LimousineProviderShowroomData data,
    LimousineShowroomVehicle vehicle,
    AppLanguage language,
  ) {
    final title = vehicle.displayName.isEmpty
        ? limousineDiscoveryServiceClassLabel(vehicle.serviceClassId)
        : vehicle.displayName;
    final classLabel = limousineDiscoveryServiceClassLabel(
      vehicle.serviceClassId,
    );
    final offer = vehicle.primaryOffer;
    final arrangement = offer == null
        ? ''
        : localizedLimousineText(offer.title, languageCode: language.name);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title.isEmpty
                ? kLimousineProviderShowroomTitle.of(language)
                : title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: tokens.onSurface,
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (classLabel.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              classLabel,
              style: TextStyle(color: tokens.gold, fontSize: 13.5),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            [
              if (vehicle.passengerCapacity != null)
                '${vehicle.passengerCapacity} ${kLimousineDiscoveryPassengers.of(language)}',
              if (vehicle.luggageCapacity != null)
                '${vehicle.luggageCapacity} ${kLimousineDiscoveryLuggage.of(language)}',
              if (vehicle.color.isNotEmpty) vehicle.color,
              if (vehicle.length.isNotEmpty) vehicle.length,
            ].join(' · '),
            style: TextStyle(color: tokens.muted, height: 1.35),
          ),
          if (limousineMeaningfulComfortFeatures(
            vehicle.features,
            language: language,
          ).isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              limousineMeaningfulComfortBody(
                vehicle.features,
                language: language,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: tokens.muted, fontSize: 13),
            ),
          ],
          if (arrangement.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              arrangement,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: tokens.onSurface, fontSize: 13.5),
            ),
          ],
          const SizedBox(height: 10),
          Text(
            limousineShowroomVehiclePriceLabel(vehicle, language),
            style: TextStyle(
              color: tokens.gold,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              key: limousineShowroomMoreInfoCtaKey(vehicle.key),
              onPressed: () => _openDetail(context, data, vehicle),
              style: FilledButton.styleFrom(
                backgroundColor: tokens.gold,
                foregroundColor: const Color(0xFF1A1408),
              ),
              child: Text(kLimousineProviderShowroomMoreInfo.of(language)),
            ),
          ),
        ],
      ),
    );
  }

  void _openDetail(
    BuildContext context,
    LimousineProviderShowroomData data,
    LimousineShowroomVehicle vehicle,
  ) {
    final onOpen = onOpenVehicle;
    if (onOpen != null) {
      onOpen(vehicle);
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        settings: publicPartnerMarketRouteSettings(
          partnerId: data.partnerId,
          market: market,
        ),
        builder: (_) => LimousineVehicleDetailPage(
          vehicle: vehicle,
          companyName: data.companyName,
          partnerId: data.partnerId,
          verifiedPartner: data.verifiedPartner,
          logoUrl: data.logoUrl,
          logoImage: logoImage,
          market: market,
        ),
      ),
    );
  }

  void _openCompanyProfile(BuildContext context) {
    final onOpen = onOpenCompanyProfile;
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
        builder: (_) => LimousinePublicProfilePage(
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
