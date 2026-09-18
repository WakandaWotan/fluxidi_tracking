import 'package:flutter/material.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/company/company_plan_presence.dart';
import 'package:fluxidi_tracking/company/company_plan_vehicle_fallback.dart';
import 'package:fluxidi_tracking/company/company_plan_vehicle_type.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_assigned_driver.dart';
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
    this.proposedDriver,
    this.compact = false,
    this.customerFacing = false,
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
    CustomerBookingAssignedDriver? proposedDriver,
    bool compact = false,
    bool customerFacing = false,
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
      proposedDriver: proposedDriver,
      compact: compact,
      customerFacing: customerFacing,
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
  final CustomerBookingAssignedDriver? proposedDriver;
  final bool compact;
  final bool customerFacing;

  @override
  Widget build(BuildContext context) {
    final category = classifyCompanyPlanVehicleCategory(offer.vehicle) ??
        CompanyPlanVehicleCategory.sedan;
    final photo = customerBookingVehiclePhotoUrl(offer.vehicle);
    final title = customerBookingVehicleOfferTitle(
      offer: offer,
      language: language,
      customerFacing: customerFacing,
    );
    final capacity = customerBookingVehicleOfferCapacityLabel(
      offer: offer,
      language: language,
    );
    final fallback = companyPlanVehicleFallbackAsset(category);
    Widget photoBox({required double iconSize, BoxFit fit = BoxFit.cover}) {
      return ColoredBox(
        color: surfaceAlt,
        child: photo.isNotEmpty
            ? Image.network(
                photo,
                fit: fit,
                alignment: Alignment.center,
                filterQuality: FilterQuality.medium,
                errorBuilder: (_, __, ___) => Image.asset(
                  fallback,
                  fit: fit,
                  alignment: Alignment.center,
                  errorBuilder: (_, __, ___) => Icon(
                    Icons.directions_car_outlined,
                    color: titleColor,
                    size: iconSize,
                  ),
                ),
              )
            : Image.asset(
                fallback,
                fit: fit,
                alignment: Alignment.center,
                errorBuilder: (_, __, ___) => Icon(
                  Icons.directions_car_outlined,
                  color: titleColor,
                  size: iconSize,
                ),
              ),
      );
    }

    final driver = customerBookingVisibleDriver(
      proposed: proposedDriver,
      driver: offer.driver,
      vehicle: offer.vehicle,
    );
    final driverName = driver.firstName.trim();
    final showDriver = selected &&
        (driver.driverId.isNotEmpty || driverName.isNotEmpty);
    final heading = customerFacing && driverName.isNotEmpty ? driverName : title;
    final showUnavailable = !compact &&
        !offer.available &&
        !customerBookingVehicleReasonIsPending(offer.reason) &&
        !customerBookingVehicleReasonIsLoadFailed(offer.reason);

    Widget headingBlock({required double titleSize}) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            heading,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: titleColor,
              fontWeight: FontWeight.w800,
              fontSize: titleSize,
              height: 1.15,
            ),
          ),
          Text(
            capacity,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: mutedColor,
              fontWeight: FontWeight.w600,
              fontSize: 12,
              height: 1.15,
            ),
          ),
          if (showUnavailable) ...[
            const SizedBox(height: 4),
            Text(
              unavailableLabel ?? kCustomerBookingVehicleUnavailable.of(language),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: dangerColor,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      );
    }

    Widget driverAvatar(double size) {
      final photo = driver.photoUrl.trim();
      if (photo.isNotEmpty) {
        return ClipOval(
          child: Image.network(
            photo,
            width: size,
            height: size,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => CircleAvatar(
              radius: size / 2,
              backgroundColor: surfaceAlt,
              child: Icon(
                Icons.person_outline,
                size: size * 0.55,
                color: titleColor,
              ),
            ),
          ),
        );
      }
      return CircleAvatar(
        radius: size / 2,
        backgroundColor: surfaceAlt,
        child: Icon(
          Icons.person_outline,
          size: size * 0.55,
          color: titleColor,
        ),
      );
    }

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
          child: compact
              ? SizedBox(
                  height: 88,
                  child: Row(
                    children: [
                      SizedBox(
                        width: 128,
                        child: photoBox(
                          iconSize: 32,
                          fit: BoxFit.contain,
                        ),
                      ),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(8, 8, 6, 8),
                          child: Row(
                            children: [
                              if (showDriver) ...[
                                driverAvatar(40),
                                const SizedBox(width: 8),
                              ],
                              Expanded(
                                child: headingBlock(titleSize: 14),
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (selected)
                        Padding(
                          padding: const EdgeInsets.only(right: 10),
                          child: Icon(
                            Icons.check_circle,
                            color: selectedBorder,
                            size: 22,
                          ),
                        ),
                    ],
                  ),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AspectRatio(
                      aspectRatio: 16 / 10,
                      child: photoBox(iconSize: 48, fit: BoxFit.contain),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
                      child: showDriver
                          ? Row(
                              children: [
                                driverAvatar(36),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: headingBlock(titleSize: 13),
                                ),
                              ],
                            )
                          : headingBlock(titleSize: 13),
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
    this.bookableOnly = false,
  });

  final List<CustomerBookingVehicleOffer> offers;
  final AppLanguage language;
  final String? selectedVehicleId;
  final ValueChanged<CustomerBookingVehicleOffer> onSelected;
  final CustomerThemePalette? palette;
  final Key Function(String vehicleId)? cardKeyFor;
  final bool bookableOnly;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final columns = width >= 700 ? 2 : 1;
        const gap = 10.0;
        final cardWidth = columns == 1
            ? width
            : (width - gap * (columns - 1)) / columns;
        final visible = bookableOnly
            ? customerBookingBookableOffers(offers)
            : offers;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final offer in visible)
              SizedBox(
                width: cardWidth,
                child: palette == null
                    ? CustomerBookingVehiclePhotoCard(
                        offer: offer,
                        language: language,
                        selected: selectedVehicleId == offer.vehicleId,
                        compact: true,
                        customerFacing: true,
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
                        unavailableLabel: customerBookingVehicleOfferReasonLabel(
                          offer,
                          language,
                        ),
                        proposedDriver: selectedVehicleId == offer.vehicleId
                            ? customerBookingProposedDriverFromRecord(
                                offer.driver,
                              )
                            : null,
                      )
                    : CustomerBookingVehiclePhotoCard.palette(
                        offer: offer,
                        language: language,
                        selected: selectedVehicleId == offer.vehicleId,
                        onTap: offer.available
                            ? () => onSelected(offer)
                            : null,
                        palette: palette!,
                        compact: true,
                        customerFacing: true,
                        cardKey: cardKeyFor?.call(offer.vehicleId) ??
                            customerBookingVehicleKey(offer.vehicleId),
                        unavailableLabel: customerBookingVehicleOfferReasonLabel(
                          offer,
                          language,
                        ),
                        proposedDriver: selectedVehicleId == offer.vehicleId
                            ? customerBookingProposedDriverFromRecord(
                                offer.driver,
                              )
                            : null,
                      ),
              ),
          ],
        );
      },
    );
  }
}

String customerBookingVehicleOfferReasonLabel(
  CustomerBookingVehicleOffer offer,
  AppLanguage language,
) {
  final reason = offer.reason.trim();
  if (reason.isEmpty ||
      customerBookingVehicleReasonIsPending(reason) ||
      customerBookingVehicleReasonIsLoadFailed(reason)) {
    return '';
  }
  return companyPlanPresenceLabel(
    CompanyPlanPresence(
      tone: CompanyPlanPresenceTone.blocked,
      code: reason,
      icon: Icons.event_busy_outlined,
    ),
    language,
  );
}
