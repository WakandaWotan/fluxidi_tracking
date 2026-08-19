import 'package:flutter/material.dart';

import '../app_config.dart';
import '../app_strings.dart';
import '../customer_theme_palette.dart';
import '../customer_theme_store.dart';
import 'limousine_customer_discovery.dart';
import 'limousine_customer_discovery_labels.dart';
import 'limousine_p2d4c1a_ux.dart';
import 'limousine_provider_showroom.dart';
import 'limousine_provider_showroom_labels.dart';
import 'limousine_quote_inbox.dart';
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
    this.onOpenVehicle,
  });

  final Map<String, dynamic> profile;
  final String partnerId;
  final String companyNameFallback;
  final double? distanceKm;
  final LimousineDiscoveryCard? discoveryCard;
  final ValueChanged<LimousineShowroomVehicle>? onOpenVehicle;

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
                          child: _catalog(context, tokens, data, tablet, language),
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
        ),
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withOpacity(0.12),
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
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                IconButton(
                  color: tokens.onHero,
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: const Icon(Icons.arrow_back),
                ),
                const SizedBox(height: 28),
                Row(
                  children: [
                    if (data.logoUrl.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(right: 12),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Image.network(
                            data.logoUrl,
                            width: 48,
                            height: 48,
                            fit: BoxFit.contain,
                            errorBuilder: (_, __, ___) =>
                                const SizedBox.shrink(),
                          ),
                        ),
                      ),
                    Expanded(
                      child: Text(
                        data.companyName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: tokens.onHero,
                          fontSize: 26,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (data.verifiedPartner)
                      Icon(
                        Icons.verified,
                        color: tokens.gold,
                        semanticLabel: kLimousineDiscoveryVerified.of(
                          appLanguageNotifier.value,
                        ),
                      ),
                  ],
                ),
                if (data.distanceKm != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    limousineDiscoveryDistanceLabel(
                      data.distanceKm!,
                      appLanguageNotifier.value,
                    ),
                    style: TextStyle(
                      color: tokens.onHero.withOpacity(0.86),
                      fontSize: 13.5,
                    ),
                  ),
                ],
                if (data.tagline.isNotEmpty || data.description.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    data.tagline.isNotEmpty ? data.tagline : data.description,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: tokens.onHero.withOpacity(0.88),
                      height: 1.35,
                    ),
                  ),
                ],
              ],
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
        const SizedBox(height: 16),
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
                _vehicleCard(
                  context,
                  tokens,
                  data,
                  vehicle,
                  tablet,
                  language,
                ),
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
      child: tablet
          ? IntrinsicHeight(child: card)
          : card,
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
            Text(classLabel, style: TextStyle(color: tokens.gold, fontSize: 13.5)),
          ],
          const SizedBox(height: 8),
          Text(
            [
              if (vehicle.passengerCapacity != null)
                '${vehicle.passengerCapacity} ${kLimousineDiscoveryPassengers.of(language)}',
              if (vehicle.luggageCapacity != null)
                '${vehicle.luggageCapacity} ${kLimousineDiscoveryLuggage.of(language)}',
              if (vehicle.color.isNotEmpty) vehicle.color,
            ].join(' · '),
            style: TextStyle(color: tokens.muted, height: 1.35),
          ),
          if (vehicle.features.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              vehicle.features.join(' · '),
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
          if (vehicle.offers.length > 1) ...[
            const SizedBox(height: 8),
            Text(
              kLimousineShowroomOffersHeading.of(language),
              style: TextStyle(
                color: tokens.muted,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
            for (final extra in vehicle.offers.skip(1).take(3))
              Text(
                localizedLimousineText(extra.title, languageCode: language.name),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: tokens.muted, fontSize: 13),
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
        builder: (_) => LimousineVehicleDetailPage(
          vehicle: vehicle,
          companyName: data.companyName,
          partnerId: data.partnerId,
          verifiedPartner: data.verifiedPartner,
        ),
      ),
    );
  }
}
