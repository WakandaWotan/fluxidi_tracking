import 'package:flutter/material.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/company/company_plan_vehicle_fallback.dart';
import 'package:fluxidi_tracking/company/company_plan_vehicle_type.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_company_vehicles.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_keys.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_labels.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_vehicle_offers.dart';
import 'package:fluxidi_tracking/customer_theme_palette.dart';

class CustomerBookingVehiclePhotoCard extends StatelessWidget {
  const CustomerBookingVehiclePhotoCard({
    super.key,
    required this.offer,
    required this.language,
    required this.selected,
    required this.onTap,
    required this.surface,
    required this.surfaceAlt,
    required this.border,
    required this.selectedBorder,
    required this.titleColor,
    required this.mutedColor,
    required this.dangerColor,
    this.cardKey,
    this.unavailableLabel,
  });

  factory CustomerBookingVehiclePhotoCard.palette({
    Key? key,
    required CustomerBookingVehicleOffer offer,
    required AppLanguage language,
    required bool selected,
    required VoidCallback? onTap,
    required CustomerThemePalette palette,
    Key? cardKey,
    String? unavailableLabel,
  }) {
    return CustomerBookingVehiclePhotoCard(
      key: key,
      offer: offer,
      language: language,
      selected: selected,
      onTap: onTap,
      surface: palette.surface,
      surfaceAlt: palette.surfaceAlt,
      border: palette.border,
      selectedBorder: palette.gold,
      titleColor: palette.textPrimary,
      mutedColor: palette.textMuted,
      dangerColor: palette.danger,
      cardKey: cardKey,
      unavailableLabel: unavailableLabel,
    );
  }

  final CustomerBookingVehicleOffer offer;
  final AppLanguage language;
  final bool selected;
  final VoidCallback? onTap;
  final Color surface;
  final Color surfaceAlt;
  final Color border;
  final Color selectedBorder;
  final Color titleColor;
  final Color mutedColor;
  final Color dangerColor;
  final Key? cardKey;
  final String? unavailableLabel;

  @override
  Widget build(BuildContext context) {
    final category = classifyCompanyPlanVehicleCategory(offer.vehicle) ??
        CompanyPlanVehicleCategory.sedan;
    final photo = customerBookingVehiclePhotoUrl(offer.vehicle);
    final title = customerBookingVehicleOfferTitle(
      offer: offer,
      language: language,
    );
    final capacity = customerBookingVehicleOfferCapacityLabel(
      offer: offer,
      language: language,
    );
    final fallback = companyPlanVehicleFallbackAsset(category);
    return Material(
      key: cardKey,
      color: surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: selected ? selectedBorder : border,
          width: selected ? 2.4 : 1.1,
        ),
      ),
      child: InkWell(
        onTap: offer.available ? onTap : null,
        child: Opacity(
          opacity: offer.available ? 1 : 0.55,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AspectRatio(
                aspectRatio: 16 / 10,
                child: ColoredBox(
                  color: surfaceAlt,
                  child: photo.isNotEmpty
                      ? Image.network(
                          photo,
                          fit: BoxFit.cover,
                          alignment: Alignment.center,
                          filterQuality: FilterQuality.medium,
                          errorBuilder: (_, __, ___) => Image.asset(
                            fallback,
                            fit: BoxFit.cover,
                            alignment: Alignment.center,
                            errorBuilder: (_, __, ___) => Icon(
                              Icons.directions_car_outlined,
                              color: titleColor,
                              size: 48,
                            ),
                          ),
                        )
                      : Image.asset(
                          fallback,
                          fit: BoxFit.cover,
                          alignment: Alignment.center,
                          errorBuilder: (_, __, ___) => Icon(
                            Icons.directions_car_outlined,
                            color: titleColor,
                            size: 48,
                          ),
                        ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: titleColor,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      capacity,
                      style: TextStyle(
                        color: mutedColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (!offer.available) ...[
                      const SizedBox(height: 4),
                      Text(
                        unavailableLabel ??
                            kCustomerBookingVehicleUnavailable.of(language),
                        style: TextStyle(
                          color: dangerColor,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class CustomerBookingVehiclePhotoCardGrid extends StatelessWidget {
  const CustomerBookingVehiclePhotoCardGrid({
    super.key,
    required this.offers,
    required this.language,
    required this.selectedVehicleId,
    required this.onSelected,
    this.palette,
    this.cardKeyFor,
  });

  final List<CustomerBookingVehicleOffer> offers;
  final AppLanguage language;
  final String? selectedVehicleId;
  final ValueChanged<CustomerBookingVehicleOffer> onSelected;
  final CustomerThemePalette? palette;
  final Key Function(String vehicleId)? cardKeyFor;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final columns = width >= 900
            ? 3
            : width >= 360
                ? 2
                : 1;
        const gap = 10.0;
        final cardWidth = columns == 1
            ? width
            : (width - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final offer in offers)
              SizedBox(
                width: cardWidth,
                child: palette == null
                    ? CustomerBookingVehiclePhotoCard(
                        offer: offer,
                        language: language,
                        selected: selectedVehicleId == offer.vehicleId,
                        onTap: offer.available
                            ? () => onSelected(offer)
                            : null,
                        surface: scheme.surface,
                        surfaceAlt: scheme.surfaceContainerHighest,
                        border: scheme.outline,
                        selectedBorder: scheme.primary,
                        titleColor: scheme.onSurface,
                        mutedColor: scheme.onSurfaceVariant,
                        dangerColor: scheme.error,
                        cardKey: cardKeyFor?.call(offer.vehicleId),
                      )
                    : CustomerBookingVehiclePhotoCard.palette(
                        offer: offer,
                        language: language,
                        selected: selectedVehicleId == offer.vehicleId,
                        onTap: offer.available
                            ? () => onSelected(offer)
                            : null,
                        palette: palette!,
                        cardKey: cardKeyFor?.call(offer.vehicleId) ??
                            customerBookingVehicleKey(offer.vehicleId),
                      ),
              ),
          ],
        );
      },
    );
  }
}
