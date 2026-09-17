// COMPANY-AGENDA-P0 — guided plan chrome. Same slots on Windows, tablet, phone.

import 'package:flutter/material.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/company/company_agenda_labels.dart';
import 'package:fluxidi_tracking/company/company_customer_ground.dart';
import 'package:fluxidi_tracking/company/company_customer_models.dart';
import 'package:fluxidi_tracking/company/company_plan_media.dart';
import 'package:fluxidi_tracking/company/company_plan_ride_layout.dart';
import 'package:fluxidi_tracking/company/company_plan_ride_mode.dart';
import 'package:fluxidi_tracking/company/company_plan_vehicle_type.dart';
import 'package:fluxidi_tracking/company/company_plan_vehicle_visual.dart';

const Key kCompanyAgendaPlanWhenNowKey = Key('company_agenda_plan_when_now');
const Key kCompanyAgendaPlanWhenLaterKey = Key('company_agenda_plan_when_later');
const Key kCompanyAgendaMoreOptionsKey = Key('company_agenda_more_options');
const Key kCompanyAgendaCapacityWarningKey = Key(
  'company_agenda_capacity_warning',
);
const Key kCompanyAgendaOccupancyKey = Key('company_agenda_occupancy');
Key companyAgendaVehicleOfferKey(String vehicleId) =>
    Key('company_agenda_vehicle_offer_${vehicleId.trim()}');
const Key kCompanyAgendaPlanCustomerFieldKey = Key(
  'company_agenda_plan_customer',
);
const Key kCompanyAgendaPlanCustomerAddKey = Key(
  'company_agenda_plan_customer_add',
);

enum CompanyPlanAudience { companyOps, customer }

class CompanyPlanRideForm extends StatelessWidget {
  const CompanyPlanRideForm({
    super.key,
    required this.language,
    required this.title,
    required this.whenNow,
    required this.onWhenNowChanged,
    required this.customer,
    required this.customers,
    required this.onCustomerSelected,
    required this.onAddCustomer,
    required this.vehicleType,
    required this.airportMode,
    required this.onVehicleTypeChanged,
    required this.onAirportModeChanged,
    required this.routeFields,
    required this.whenLaterFields,
    this.waypointFields,
    this.roundtripFields,
    this.roundtripChoiceFields,
    this.returnRouteFields,
    this.returnWhenFields,
    this.waitFields,
    this.flightFields,
    required this.passengers,
    required this.onPassengersChanged,
    required this.bags,
    required this.onBagsChanged,
    required this.quote,
    required this.proposedAssignment,
    required this.moreOptions,
    required this.primary,
    required this.secondary,
    required this.map,
    this.errorText,
    this.brand,
    this.audience = CompanyPlanAudience.companyOps,
    this.bookableCategories = const <CompanyPlanVehicleCategory>[
      CompanyPlanVehicleCategory.sedan,
      CompanyPlanVehicleCategory.minivan,
    ],
    this.vehicleVisuals = const CompanyPlanVehicleVisualContract(),
    this.categoryBadges = const <CompanyPlanVehicleCategory, List<CompanyPlanVehicleBadge>>{},
    this.unavailableReasons = const <CompanyPlanVehicleCategory, String>{},
    this.assignedCrew,
    this.unsuitableDrivers,
    this.selectedCategory,
    this.onCategoryChanged,
    this.capacityWarning,
    this.unsuitableCategories = const <CompanyPlanVehicleCategory>{},
    this.categoryPhotoUrls = const <CompanyPlanVehicleCategory, String>{},
    this.categoryPassengerCaps = const <CompanyPlanVehicleCategory, int>{},
    this.vehicleOfferCards,
  });

  final AppLanguage language;
  final String title;
  final bool whenNow;
  final ValueChanged<bool> onWhenNowChanged;
  final CompanyCustomer? customer;
  final List<CompanyCustomerListItem> customers;
  final ValueChanged<CompanyCustomerListItem> onCustomerSelected;
  final VoidCallback onAddCustomer;
  final CompanyPlanVehicleType vehicleType;
  final bool airportMode;
  final ValueChanged<CompanyPlanVehicleType> onVehicleTypeChanged;
  final ValueChanged<bool> onAirportModeChanged;
  final Widget routeFields;
  final Widget whenLaterFields;
  final Widget? waypointFields;
  final Widget? roundtripFields;
  final Widget? roundtripChoiceFields;
  final Widget? returnRouteFields;
  final Widget? returnWhenFields;
  final Widget? waitFields;
  final Widget? flightFields;
  final int passengers;
  final ValueChanged<int> onPassengersChanged;
  final int bags;
  final ValueChanged<int> onBagsChanged;
  final Widget quote;
  final Widget proposedAssignment;
  final List<Widget> moreOptions;
  final Widget primary;
  final Widget secondary;
  final Widget map;
  final String? errorText;
  final CompanyPlanCompanyBrand? brand;
  final CompanyPlanAudience audience;
  final List<CompanyPlanVehicleCategory> bookableCategories;
  final CompanyPlanVehicleVisualContract vehicleVisuals;
  final Map<CompanyPlanVehicleCategory, List<CompanyPlanVehicleBadge>>
      categoryBadges;
  final Map<CompanyPlanVehicleCategory, String> unavailableReasons;
  final Widget? assignedCrew;
  final Widget? unsuitableDrivers;
  final CompanyPlanVehicleCategory? selectedCategory;
  final ValueChanged<CompanyPlanVehicleCategory>? onCategoryChanged;
  final String? capacityWarning;
  final Set<CompanyPlanVehicleCategory> unsuitableCategories;
  final Map<CompanyPlanVehicleCategory, String> categoryPhotoUrls;
  final Map<CompanyPlanVehicleCategory, int> categoryPassengerCaps;
  final Widget? vehicleOfferCards;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final split =
            companyPlanRideLayoutFor(constraints) == CompanyPlanRideLayout.split;
        final mapHeight = companyPlanStackedMapHeight(constraints);
        final fields = _fields(context, stacked: !split);
        final actions = _actions();
        if (split) {
          return Column(
            children: [
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      flex: 5,
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(16, 16, 12, 120),
                        child: fields,
                      ),
                    ),
                    Expanded(
                      flex: 4,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(4, 16, 16, 16),
                        child: map,
                      ),
                    ),
                  ],
                ),
              ),
              actions,
            ],
          );
        }
        return Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    fields,
                    if (mapHeight > 0) ...[
                      const SizedBox(height: 16),
                      SizedBox(height: mapHeight, child: map),
                    ],
                  ],
                ),
              ),
            ),
            actions,
          ],
        );
      },
    );
  }

  Widget _fields(BuildContext context, {required bool stacked}) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (brand != null) ...[
          Row(
            children: [
              CompanyPlanBrandMark(brand: brand!),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  brand!.hasName ? brand!.companyName : title,
                  style: theme.textTheme.titleMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ] else
          Text(title, style: theme.textTheme.titleMedium),
        const SizedBox(height: 12),
        SegmentedButton<bool>(
          segments: [
            ButtonSegment<bool>(
              value: true,
              label: Text(
                key: kCompanyAgendaPlanWhenNowKey,
                kCompanyAgendaWhenNow.of(language),
              ),
              icon: const Icon(Icons.bolt_outlined),
            ),
            ButtonSegment<bool>(
              value: false,
              label: Text(
                key: kCompanyAgendaPlanWhenLaterKey,
                kCompanyAgendaWhenLater.of(language),
              ),
              icon: const Icon(Icons.schedule_outlined),
            ),
          ],
          selected: <bool>{whenNow},
          onSelectionChanged: (next) {
            if (next.isEmpty) return;
            onWhenNowChanged(next.first);
          },
          style: const ButtonStyle(visualDensity: VisualDensity.compact),
        ),
        if (!whenNow) ...[
          const SizedBox(height: 12),
          whenLaterFields,
        ],
        if (returnWhenFields != null) ...[
          const SizedBox(height: 8),
          returnWhenFields!,
        ],
        if (waitFields != null) ...[
          const SizedBox(height: 8),
          waitFields!,
        ],
        if (audience != CompanyPlanAudience.customer) ...[
          const SizedBox(height: 16),
          _CustomerField(
            language: language,
            customer: customer,
            customers: customers,
            onSelected: onCustomerSelected,
            onAdd: onAddCustomer,
          ),
        ],
        const SizedBox(height: 16),
        _ServiceModeChoice(
          language: language,
          airportMode: airportMode,
          onChanged: onAirportModeChanged,
        ),
        if (airportMode) ...[
          const SizedBox(height: 8),
          Text(
            kCompanyAgendaAirportNeedsVehicle.of(language),
            style: theme.textTheme.bodySmall,
          ),
        ],
        if (roundtripChoiceFields != null) ...[
          const SizedBox(height: 16),
          roundtripChoiceFields!,
        ],
        const SizedBox(height: 16),
        if (stacked && flightFields != null) ...[
          flightFields!,
          const SizedBox(height: 16),
        ],
        routeFields,
        if (waypointFields != null) ...[
          const SizedBox(height: 8),
          waypointFields!,
        ],
        if (returnRouteFields != null) ...[
          const SizedBox(height: 16),
          returnRouteFields!,
        ] else if (roundtripFields != null) ...[
          const SizedBox(height: 16),
          roundtripFields!,
        ],
        if (!stacked && flightFields != null) ...[
          const SizedBox(height: 16),
          flightFields!,
        ],
        const SizedBox(height: 16),
        Text(
          kCompanyAgendaVehicleType.of(language),
          style: theme.textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        if (vehicleOfferCards != null)
          vehicleOfferCards!
        else
          _TypeCards(
            language: language,
            vehicleType: vehicleType,
            onVehicleTypeChanged: onVehicleTypeChanged,
            categories: bookableCategories,
            visuals: vehicleVisuals,
            badges: categoryBadges,
            unavailableReasons: unavailableReasons,
            selectedCategory: selectedCategory,
            onCategoryChanged: onCategoryChanged,
            unsuitableCategories: unsuitableCategories,
            categoryPhotoUrls: categoryPhotoUrls,
            categoryPassengerCaps: categoryPassengerCaps,
          ),
        if (capacityWarning != null && capacityWarning!.trim().isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            capacityWarning!,
            key: kCompanyAgendaCapacityWarningKey,
            style: TextStyle(color: theme.colorScheme.error),
          ),
        ],
        const SizedBox(height: 16),
        _OccupancyRow(
          language: language,
          passengers: passengers,
          bags: bags,
          onPassengersChanged: onPassengersChanged,
          onBagsChanged: onBagsChanged,
        ),
        const SizedBox(height: 16),
        quote,
        if (audience == CompanyPlanAudience.customer) ...[
          if (assignedCrew != null) ...[
            const SizedBox(height: 16),
            assignedCrew!,
          ],
        ] else ...[
          const SizedBox(height: 16),
          Text(
            kCompanyAgendaProposedDriver.of(language),
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          proposedAssignment,
          if (unsuitableDrivers != null) ...[
            const SizedBox(height: 8),
            unsuitableDrivers!,
          ],
        ],
        const SizedBox(height: 8),
        Theme(
          data: theme.copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            key: kCompanyAgendaMoreOptionsKey,
            tilePadding: EdgeInsets.zero,
            childrenPadding: EdgeInsets.zero,
            title: Text(kCompanyAgendaMoreOptions.of(language)),
            children: [
              for (final child in moreOptions) ...[
                const SizedBox(height: 8),
                child,
              ],
            ],
          ),
        ),
        if (errorText != null && errorText!.trim().isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            errorText!,
            style: TextStyle(color: theme.colorScheme.error),
          ),
        ],
      ],
    );
  }

  Widget _actions() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [primary, const SizedBox(height: 8), secondary],
      ),
    );
  }
}

String companyPlanBagsLabel(AppLanguage language) {
  return language == AppLanguage.fr
      ? 'Bagages'
      : language == AppLanguage.es
      ? 'Equipaje'
      : language == AppLanguage.nl
      ? 'Bagage'
      : 'Baggage';
}

class _OccupancyRow extends StatelessWidget {
  const _OccupancyRow({
    required this.language,
    required this.passengers,
    required this.bags,
    required this.onPassengersChanged,
    required this.onBagsChanged,
  });

  final AppLanguage language;
  final int passengers;
  final int bags;
  final ValueChanged<int> onPassengersChanged;
  final ValueChanged<int> onBagsChanged;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      key: kCompanyAgendaOccupancyKey,
      container: true,
      label:
          '${kCompanyAgendaPassengers.of(language)} $passengers · ${companyPlanBagsLabel(language)} $bags',
      child: Row(
        children: [
          Expanded(
            child: _OccupancyStepper(
              icon: Icons.person_outline,
              value: passengers,
              min: 1,
              label: kCompanyAgendaPassengers.of(language),
              onChanged: onPassengersChanged,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _OccupancyStepper(
              icon: Icons.luggage_outlined,
              value: bags,
              min: 0,
              label: companyPlanBagsLabel(language),
              onChanged: onBagsChanged,
            ),
          ),
        ],
      ),
    );
  }
}

class _OccupancyStepper extends StatelessWidget {
  const _OccupancyStepper({
    required this.icon,
    required this.value,
    required this.min,
    required this.label,
    required this.onChanged,
  });

  final IconData icon;
  final int value;
  final int min;
  final String label;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.outline.withValues(alpha: 0.35)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Row(
          children: [
            Icon(icon, semanticLabel: label),
            IconButton(
              onPressed: value > min ? () => onChanged(value - 1) : null,
              icon: const Icon(Icons.remove),
            ),
            Expanded(
              child: Text(
                '$value',
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium,
              ),
            ),
            IconButton(
              onPressed: () => onChanged(value + 1),
              icon: const Icon(Icons.add),
            ),
          ],
        ),
      ),
    );
  }
}

class _ServiceModeChoice extends StatelessWidget {
  const _ServiceModeChoice({
    required this.language,
    required this.airportMode,
    required this.onChanged,
  });

  final AppLanguage language;
  final bool airportMode;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<bool>(
      segments: [
        ButtonSegment<bool>(
          value: false,
          label: Text(
            key: kCompanyAgendaRegularRideKey,
            kCompanyAgendaRegularRide.of(language),
          ),
        ),
        ButtonSegment<bool>(
          value: true,
          label: Text(
            key: kCompanyAgendaAirportModeKey,
            kCompanyAgendaAirportMode.of(language),
          ),
          icon: const Icon(kCompanyPlanAirportModeIcon, size: 16),
        ),
      ],
      selected: <bool>{airportMode},
      onSelectionChanged: (next) {
        if (next.isEmpty) return;
        onChanged(next.first);
      },
      style: const ButtonStyle(visualDensity: VisualDensity.compact),
      showSelectedIcon: false,
    );
  }
}

class _TypeCards extends StatelessWidget {
  const _TypeCards({
    required this.language,
    required this.vehicleType,
    required this.onVehicleTypeChanged,
    required this.categories,
    required this.visuals,
    required this.badges,
    this.unavailableReasons = const <CompanyPlanVehicleCategory, String>{},
    this.selectedCategory,
    this.onCategoryChanged,
    this.unsuitableCategories = const <CompanyPlanVehicleCategory>{},
    this.categoryPhotoUrls = const <CompanyPlanVehicleCategory, String>{},
    this.categoryPassengerCaps = const <CompanyPlanVehicleCategory, int>{},
  });

  final AppLanguage language;
  final CompanyPlanVehicleType vehicleType;
  final ValueChanged<CompanyPlanVehicleType> onVehicleTypeChanged;
  final List<CompanyPlanVehicleCategory> categories;
  final CompanyPlanVehicleVisualContract visuals;
  final Map<CompanyPlanVehicleCategory, List<CompanyPlanVehicleBadge>> badges;
  final Map<CompanyPlanVehicleCategory, String> unavailableReasons;
  final CompanyPlanVehicleCategory? selectedCategory;
  final ValueChanged<CompanyPlanVehicleCategory>? onCategoryChanged;
  final Set<CompanyPlanVehicleCategory> unsuitableCategories;
  final Map<CompanyPlanVehicleCategory, String> categoryPhotoUrls;
  final Map<CompanyPlanVehicleCategory, int> categoryPassengerCaps;

  Key _categoryKey(CompanyPlanVehicleCategory category) {
    return switch (category) {
      CompanyPlanVehicleCategory.sedan => kCompanyAgendaVehicleTypeSedanKey,
      CompanyPlanVehicleCategory.minivan => kCompanyAgendaVehicleTypeMinivanKey,
      _ => Key('company_agenda_vehicle_category_${category.name}'),
    };
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final gap = 8.0;
        final tablet = constraints.maxWidth >= 520;
        final cardWidth = constraints.maxWidth >= 900
            ? (constraints.maxWidth - gap * 2) / 3
            : (constraints.maxWidth - gap) / 2;
        final vehicleVisualHeight = tablet ? 72.0 : 56.0;
        final cards = <Widget>[
          for (final category in categories)
            SizedBox(
              width: cardWidth,
              child: _ChoiceCard(
                cardKey: _categoryKey(category),
                selected: (selectedCategory ??
                        (vehicleType == CompanyPlanVehicleType.minivan
                            ? CompanyPlanVehicleCategory.minivan
                            : CompanyPlanVehicleCategory.sedan)) ==
                    category,
                visual: CompanyPlanVehicleVisual(
                  type: companyPlanVehicleTypeForCategory(category),
                  category: category,
                  semanticLabel: companyPlanVehicleCategoryLabel(
                    category,
                    language,
                  ),
                  contract: visuals,
                  vehiclePhotoUrl: categoryPhotoUrls[category],
                  height: vehicleVisualHeight,
                ),
                title: companyPlanVehicleCategoryLabel(category, language),
                subtitle: [
                  () {
                    final cap = categoryPassengerCaps[category];
                    if (cap == null || cap <= 0) {
                      return companyPlanVehicleTypeCapacityLabel(
                        companyPlanVehicleTypeForCategory(category),
                        language,
                      );
                    }
                    return language == AppLanguage.nl ||
                            language == AppLanguage.fr ||
                            language == AppLanguage.es
                        ? '1–$cap pers.'
                        : '1–$cap pax';
                  }(),
                  for (final badge in badges[category] ?? const <CompanyPlanVehicleBadge>[])
                    companyPlanVehicleBadgeLabel(badge, language),
                  if ((unavailableReasons[category] ?? '').isNotEmpty)
                    unavailableReasons[category]!,
                ].join(' · '),
                minHeight: tablet ? 88 : 72,
                unsuitable: unsuitableCategories.contains(category),
                onTap: () {
                  (onCategoryChanged ??
                          (next) => onVehicleTypeChanged(
                            companyPlanVehicleTypeForCategory(next),
                          ))
                      .call(category);
                },
              ),
            ),
        ];
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: cards,
        );
      },
    );
  }
}

class _ChoiceCard extends StatelessWidget {
  const _ChoiceCard({
    required this.cardKey,
    required this.selected,
    required this.visual,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.titleIcon,
    this.minHeight = 72,
    this.unsuitable = false,
  });

  final Key cardKey;
  final bool selected;
  final Widget visual;
  final IconData? titleIcon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final double minHeight;
  final bool unsuitable;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Material(
      key: cardKey,
      color: selected
          ? scheme.primaryContainer
          : scheme.surfaceContainerHighest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: unsuitable
              ? scheme.error
              : selected
                  ? scheme.primary
                  : scheme.outline.withValues(alpha: 0.35),
          width: selected || unsuitable ? 1.6 : 1,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: minHeight),
          child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 12, 10, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              visual,
              const SizedBox(height: 8),
              Row(
                children: [
                  if (titleIcon != null) ...[
                    Icon(titleIcon, size: 16),
                    const SizedBox(width: 6),
                  ],
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
          ),
        ),
      ),
    );
  }
}

class _CustomerField extends StatelessWidget {
  const _CustomerField({
    required this.language,
    required this.customer,
    required this.customers,
    required this.onSelected,
    required this.onAdd,
  });

  final AppLanguage language;
  final CompanyCustomer? customer;
  final List<CompanyCustomerListItem> customers;
  final ValueChanged<CompanyCustomerListItem> onSelected;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Autocomplete<CompanyCustomerListItem>(
      key: ValueKey<String>(customer?.customerId ?? 'none'),
      initialValue: TextEditingValue(text: customer?.displayName ?? ''),
      displayStringForOption: (item) => item.displayName,
      optionsBuilder: (value) {
        final needle = value.text.trim().toLowerCase();
        if (needle.isEmpty) return customers.take(40);
        return customers.where(
          (item) => companyCustomerListItemMatches(item, needle),
        );
      },
      onSelected: onSelected,
      fieldViewBuilder: (context, controller, focus, onSubmitted) {
        return TextField(
          key: kCompanyAgendaPlanCustomerFieldKey,
          controller: controller,
          focusNode: focus,
          onSubmitted: (_) => onSubmitted(),
          decoration: InputDecoration(
            labelText: kCompanyAgendaCustomer.of(language),
            hintText: kCompanyAgendaCustomerSearch.of(language),
            suffixIcon: IconButton(
              key: kCompanyAgendaPlanCustomerAddKey,
              tooltip: kCompanyAgendaCustomerAdd.of(language),
              onPressed: onAdd,
              icon: const Icon(Icons.person_add_alt_1_outlined),
            ),
          ),
        );
      },
    );
  }
}
