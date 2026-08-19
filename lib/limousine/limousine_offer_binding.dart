// Vehicle-bound limousine offers. Branding, vehicle media and prices stay
// separate. Matching uses stable public vehicle IDs, never names or indexes.

import '../app_config.dart';
import '../app_strings.dart';
import 'limousine_customer_discovery.dart';
import 'limousine_customer_discovery_labels.dart';
import 'limousine_customer_quote.dart';
import 'limousine_offers.dart';
import 'limousine_provider_showroom_labels.dart';
import 'limousine_public_showroom_labels.dart';
import 'limousine_quote_inbox.dart';

enum LimousineOfferDisplayKind { quote, fromPrice, fixed, hourly, package }

class LimousineOfferScope {
  const LimousineOfferScope({
    this.appliesToAllSelected = false,
    this.vehicleIds = const <String>[],
    this.legacyUnbound = false,
    this.featured = false,
    this.sortOrder = 0,
  });

  final bool appliesToAllSelected;
  final List<String> vehicleIds;
  final bool legacyUnbound;
  final bool featured;
  final int sortOrder;
}

List<String> limousineNormalizeVehicleIds(Object? raw, {Object? single}) =>
    limousineNormalizeBoundVehicleIds(raw, single: single);

bool _boolOf(Object? raw, {bool fallback = false}) {
  if (raw is bool) return raw;
  final token = limousineOfferToken(raw);
  if (token == 'true' || token == '1' || token == 'yes' || token == 'on') {
    return true;
  }
  if (token == 'false' || token == '0' || token == 'no' || token == 'off') {
    return false;
  }
  return fallback;
}

bool _hasExplicitAllFlag(Map<String, dynamic> offer) {
  return offer.containsKey('applies_to_all_selected_vehicles') ||
      offer.containsKey('appliesToAllSelectedVehicles');
}

LimousineOfferScope limousineOfferScopeOf(Map<String, dynamic> offer) {
  final ids = limousineNormalizeVehicleIds(
    offer['vehicle_ids'] ?? offer['vehicleIds'],
    single: offer['vehicle_id'] ?? offer['vehicleId'],
  );
  final legacyUnbound = !_hasExplicitAllFlag(offer) && ids.isEmpty;
  final appliesToAll = _hasExplicitAllFlag(offer)
      ? _boolOf(
          offer['applies_to_all_selected_vehicles'] ??
              offer['appliesToAllSelectedVehicles'],
        )
      : ids.isEmpty;
  return LimousineOfferScope(
    appliesToAllSelected: appliesToAll,
    vehicleIds: ids,
    legacyUnbound: legacyUnbound,
    featured: _boolOf(offer['featured']),
    sortOrder:
        int.tryParse('${offer['sort_order'] ?? offer['sortOrder'] ?? 0}') ?? 0,
  );
}

LimousineOfferScope limousinePublishedOfferScope(
  LimousinePublishedOffer offer,
) {
  return limousineOfferScopeOf(offer.raw);
}

List<String> limousineSelectedLimousineIds(Iterable<VehicleProfile> vehicles) {
  return [
    for (final vehicle in vehicles)
      if (limousineOfferToken(vehicle.serviceCategory) == 'limousine' &&
          vehicle.id.trim().isNotEmpty)
        vehicle.id.trim(),
  ];
}

bool limousineVehicleIsPublishedLimousine(VehicleProfile vehicle) {
  return vehicle.isActive &&
      limousineOfferToken(vehicle.serviceCategory) == 'limousine' &&
      limousineOfferToken(vehicle.serviceClassId).isNotEmpty;
}

List<String> limousineOfferMissingLinkedIds({
  required Map<String, dynamic> offer,
  required Iterable<VehicleProfile> vehicles,
}) {
  final scope = limousineOfferScopeOf(offer);
  if (scope.appliesToAllSelected) return const <String>[];
  final known = <String>{for (final vehicle in vehicles) vehicle.id.trim()};
  return [
    for (final id in scope.vehicleIds)
      if (id.isNotEmpty && !known.contains(id)) id,
  ];
}

List<String> limousineOfferInactiveLinkedIds({
  required Map<String, dynamic> offer,
  required Iterable<VehicleProfile> vehicles,
}) {
  final scope = limousineOfferScopeOf(offer);
  if (scope.appliesToAllSelected) return const <String>[];
  final byId = <String, VehicleProfile>{
    for (final vehicle in vehicles) vehicle.id.trim(): vehicle,
  };
  return [
    for (final id in scope.vehicleIds)
      if (byId[id] == null || !limousineVehicleIsPublishedLimousine(byId[id]!))
        id,
  ];
}

bool limousineOfferAppliesToVehicleId({
  required Map<String, dynamic> offer,
  required String vehicleId,
  Iterable<String> selectedVehicleIds = const <String>[],
}) {
  final wanted = vehicleId.trim();
  if (wanted.isEmpty) return false;
  final scope = limousineOfferScopeOf(offer);
  // Explicit vehicle ids are authoritative, even when a projection copy still
  // carries applies_to_all_selected_vehicles from the original all-selected row.
  if (scope.vehicleIds.isNotEmpty) {
    return scope.vehicleIds.contains(wanted);
  }
  if (scope.appliesToAllSelected || scope.legacyUnbound) {
    if (selectedVehicleIds.isEmpty) return true;
    return selectedVehicleIds.contains(wanted);
  }
  return false;
}

bool limousinePublishedOfferAppliesToVehicle({
  required LimousinePublishedOffer offer,
  required String vehicleId,
  Iterable<String> selectedVehicleIds = const <String>[],
}) {
  return limousineOfferAppliesToVehicleId(
    offer: offer.raw,
    vehicleId: vehicleId,
    selectedVehicleIds: selectedVehicleIds,
  );
}

Map<String, dynamic> limousineWriteOfferScope(
  Map<String, dynamic> offer, {
  required bool appliesToAllSelected,
  required List<String> vehicleIds,
  bool? featured,
  int? sortOrder,
}) {
  final next = Map<String, dynamic>.from(offer);
  final ids = limousineNormalizeVehicleIds(vehicleIds);
  next['applies_to_all_selected_vehicles'] = appliesToAllSelected;
  next['vehicle_ids'] = appliesToAllSelected ? <String>[] : ids;
  next['vehicle_id'] = appliesToAllSelected || ids.isEmpty ? '' : ids.first;
  next['target_type'] = appliesToAllSelected
      ? LimousineOfferTarget.serviceClass
      : LimousineOfferTarget.vehicle;
  if (featured != null) next['featured'] = featured;
  if (sortOrder != null) next['sort_order'] = sortOrder;
  return next;
}

LimousineOfferDisplayKind limousineOfferDisplayKindOf(
  Map<String, dynamic> offer,
) {
  final hourly = offer['hourly'] is Map
      ? Map<String, dynamic>.from(offer['hourly'] as Map)
      : const <String, dynamic>{};
  final hourlyOn = _boolOf(hourly['enabled']);
  final packageAmount = limousineCentsOf(hourly['package_amount_cents']);
  final packageDuration = limousineMinutesOf(
    hourly['package_duration_minutes'],
  );
  if (hourlyOn &&
      ((packageAmount != null && packageAmount > 0) ||
          (packageDuration != null && packageDuration > 0))) {
    return LimousineOfferDisplayKind.package;
  }
  if (hourlyOn) return LimousineOfferDisplayKind.hourly;
  final presentation = limousineOfferToken(offer['price_presentation']);
  if (presentation == LimousinePricePresentation.fromPrice) {
    return LimousineOfferDisplayKind.fromPrice;
  }
  if (presentation == LimousinePricePresentation.exactFixed) {
    return LimousineOfferDisplayKind.fixed;
  }
  return LimousineOfferDisplayKind.quote;
}

LimousineOfferDisplayKind limousinePublishedDisplayKind(
  LimousinePublishedOffer offer,
) {
  return limousineOfferDisplayKindOf(offer.raw);
}

int? _offerPublicAmountCents(Map<String, dynamic> offer) {
  final hourly = offer['hourly'] is Map
      ? Map<String, dynamic>.from(offer['hourly'] as Map)
      : const <String, dynamic>{};
  final packageAmount = limousineCentsOf(hourly['package_amount_cents']);
  if (packageAmount != null && packageAmount > 0) return packageAmount;
  final firstHour = limousineCentsOf(hourly['first_hour_cents']);
  if (firstHour != null && firstHour > 0) return firstHour;
  return limousineCentsOf(offer['display_amount_cents']);
}

List<LimousinePublishedOffer> limousineSortPublishedOffers(
  Iterable<LimousinePublishedOffer> offers,
) {
  final out = offers.toList();
  out.sort((a, b) {
    final sa = limousinePublishedOfferScope(a);
    final sb = limousinePublishedOfferScope(b);
    if (sa.featured != sb.featured) return sa.featured ? -1 : 1;
    if (sa.sortOrder != sb.sortOrder)
      return sa.sortOrder.compareTo(sb.sortOrder);
    return a.offerId.compareTo(b.offerId);
  });
  return out;
}

/// Collapse projection copies of the same catalog offer. First row in the
/// incoming order wins, so callers keep their sort (vehicle-first or
/// featured/sortOrder). Never deduplicates on visible price text.
List<LimousinePublishedOffer> limousineDeduplicatePublishedOffers(
  Iterable<LimousinePublishedOffer> offers,
) {
  final seen = <String>{};
  final out = <LimousinePublishedOffer>[];
  for (final offer in offers) {
    final id = offer.offerId.trim();
    if (id.isEmpty || !seen.add(id)) continue;
    out.add(offer);
  }
  return out;
}

LimousinePublishedOffer? limousineSelectSummaryOffer(
  Iterable<LimousinePublishedOffer> offers,
) {
  final list = limousineSortPublishedOffers(offers);
  if (list.isEmpty) return null;
  for (final offer in list) {
    if (limousinePublishedOfferScope(offer).featured) return offer;
  }
  LimousinePublishedOffer? lowestFrom;
  int? lowestFromCents;
  for (final offer in list) {
    if (limousinePublishedDisplayKind(offer) !=
        LimousineOfferDisplayKind.fromPrice) {
      continue;
    }
    final cents = offer.displayAmountCents;
    if (cents == null || cents <= 0) continue;
    if (lowestFromCents == null || cents < lowestFromCents) {
      lowestFrom = offer;
      lowestFromCents = cents;
    }
  }
  if (lowestFrom != null) return lowestFrom;
  for (final offer in list) {
    final kind = limousinePublishedDisplayKind(offer);
    if (kind == LimousineOfferDisplayKind.fixed ||
        kind == LimousineOfferDisplayKind.hourly ||
        kind == LimousineOfferDisplayKind.package) {
      if ((offer.displayAmountCents ?? 0) > 0 ||
          (limousineCentsOf(
                    offer.raw['hourly'] is Map
                        ? (offer.raw['hourly'] as Map)['package_amount_cents']
                        : null,
                  ) ??
                  0) >
              0) {
        return offer;
      }
    }
  }
  return list.first;
}

LimousineDiscoveryPrice limousineDiscoveryPriceFromOffers(
  Iterable<Map<String, dynamic>> offers,
) {
  final published = [
    for (final offer in offers)
      if (_boolOf(offer['published'], fallback: true) &&
          _boolOf(offer['enabled'], fallback: true) &&
          limousineOfferToken(offer['price_presentation']) !=
              LimousinePricePresentation.unavailable)
        offer,
  ];
  if (published.isEmpty) {
    return const LimousineDiscoveryPrice(
      kind: LimousineDiscoveryPriceKind.quoteRequired,
    );
  }
  Map<String, dynamic>? featured;
  for (final offer in published) {
    if (_boolOf(offer['featured'])) {
      featured = offer;
      break;
    }
  }
  Map<String, dynamic>? chosen = featured;
  if (chosen == null) {
    int? lowest;
    for (final offer in published) {
      if (limousineOfferDisplayKindOf(offer) !=
          LimousineOfferDisplayKind.fromPrice) {
        continue;
      }
      final cents = _offerPublicAmountCents(offer);
      if (cents == null || cents <= 0) continue;
      if (lowest == null || cents < lowest) {
        lowest = cents;
        chosen = offer;
      }
    }
  }
  if (chosen == null) {
    for (final offer in published) {
      final kind = limousineOfferDisplayKindOf(offer);
      if (kind == LimousineOfferDisplayKind.fixed ||
          kind == LimousineOfferDisplayKind.hourly ||
          kind == LimousineOfferDisplayKind.package) {
        chosen = offer;
        break;
      }
    }
  }
  final selected = chosen ?? published.first;
  final kind = limousineOfferDisplayKindOf(selected);
  final cents = _offerPublicAmountCents(selected);
  final currency = limousineCurrencyOf(selected['currency']);
  switch (kind) {
    case LimousineOfferDisplayKind.fromPrice:
      return LimousineDiscoveryPrice(
        kind: LimousineDiscoveryPriceKind.fromPrice,
        amountCents: cents,
        currency: currency,
      );
    case LimousineOfferDisplayKind.fixed:
    case LimousineOfferDisplayKind.hourly:
    case LimousineOfferDisplayKind.package:
      return LimousineDiscoveryPrice(
        kind: LimousineDiscoveryPriceKind.exactFixed,
        amountCents: cents,
        currency: currency,
      );
    case LimousineOfferDisplayKind.quote:
      return const LimousineDiscoveryPrice(
        kind: LimousineDiscoveryPriceKind.quoteRequired,
      );
  }
}

String _money(int cents, String currency) {
  final amount = (cents / 100).toStringAsFixed(cents % 100 == 0 ? 0 : 2);
  if (currency.toUpperCase() == 'EUR') return '€$amount';
  return '$amount ${currency.toUpperCase()}';
}

String limousineOfferKindLabel(
  LimousineOfferDisplayKind kind,
  AppLanguage language,
) {
  switch (kind) {
    case LimousineOfferDisplayKind.quote:
      return kLimousineShowroomPriceOnRequest.of(language);
    case LimousineOfferDisplayKind.fromPrice:
      return kLimousineDiscoveryFromPrice.of(language);
    case LimousineOfferDisplayKind.fixed:
      return kLimousineOfferFixedKind.of(language);
    case LimousineOfferDisplayKind.hourly:
      return kLimousineOfferHourlyKind.of(language);
    case LimousineOfferDisplayKind.package:
      return kLimousineOfferPackageKind.of(language);
  }
}

String limousineFormatPublishedOfferPrice(
  LimousinePublishedOffer offer,
  AppLanguage language,
) {
  final kind = limousinePublishedDisplayKind(offer);
  final hourly = offer.raw['hourly'] is Map
      ? Map<String, dynamic>.from(offer.raw['hourly'] as Map)
      : const <String, dynamic>{};
  final currency = offer.currency.trim().isEmpty ? 'EUR' : offer.currency;
  final packageAmount = limousineCentsOf(hourly['package_amount_cents']);
  final packageMinutes = limousineMinutesOf(hourly['package_duration_minutes']);
  final firstHour = limousineCentsOf(hourly['first_hour_cents']);
  final minMinutes = limousineMinutesOf(hourly['minimum_duration_minutes']);
  switch (kind) {
    case LimousineOfferDisplayKind.quote:
      return kLimousineShowroomPriceOnRequest.of(language);
    case LimousineOfferDisplayKind.fromPrice:
      final cents = offer.displayAmountCents;
      if (cents == null || cents <= 0) {
        return kLimousineShowroomPriceOnRequest.of(language);
      }
      return '${kLimousineDiscoveryFromPrice.of(language)} ${_money(cents, currency)}';
    case LimousineOfferDisplayKind.hourly:
      final cents = firstHour ?? offer.displayAmountCents;
      if (cents == null || cents <= 0) {
        return kLimousineShowroomPriceOnRequest.of(language);
      }
      final parts = <String>[
        '${_money(cents, currency)} ${kLimousineOfferPerHour.of(language)}',
      ];
      if (minMinutes != null && minMinutes > 0) {
        final hours = (minMinutes / 60).ceil();
        parts.add('${kLimousineOfferMinimumHours.of(language)} $hours');
      }
      return parts.join(' · ');
    case LimousineOfferDisplayKind.package:
      final title = localizedLimousineText(
        offer.title,
        languageCode: language.name,
      );
      final parts = <String>[
        if (title.isNotEmpty) title,
        if (packageMinutes != null && packageMinutes > 0)
          '${(packageMinutes / 60).toStringAsFixed(packageMinutes % 60 == 0 ? 0 : 1)} ${kLimousineOfferHoursUnit.of(language)}',
        if (packageAmount != null && packageAmount > 0)
          _money(packageAmount, currency)
        else if ((offer.displayAmountCents ?? 0) > 0)
          _money(offer.displayAmountCents!, currency)
        else
          kLimousineShowroomPriceOnRequest.of(language),
      ];
      return parts.join(' · ');
    case LimousineOfferDisplayKind.fixed:
      final cents = offer.displayAmountCents;
      if (cents == null || cents <= 0) {
        return kLimousineShowroomPriceOnRequest.of(language);
      }
      return _money(cents, currency);
  }
}

/// Amount only — used on detail cards so "Vanaf" is not repeated in the value.
String limousineFormatPublishedOfferAmount(
  LimousinePublishedOffer offer,
  AppLanguage language,
) {
  final kind = limousinePublishedDisplayKind(offer);
  if (kind == LimousineOfferDisplayKind.quote) {
    return kLimousineShowroomPriceOnRequest.of(language);
  }
  final currency = offer.currency.trim().isEmpty ? 'EUR' : offer.currency;
  final hourly = offer.raw['hourly'] is Map
      ? Map<String, dynamic>.from(offer.raw['hourly'] as Map)
      : const <String, dynamic>{};
  final cents = kind == LimousineOfferDisplayKind.hourly
      ? (limousineCentsOf(hourly['first_hour_cents']) ??
            offer.displayAmountCents)
      : kind == LimousineOfferDisplayKind.package
      ? (limousineCentsOf(hourly['package_amount_cents']) ??
            offer.displayAmountCents)
      : offer.displayAmountCents;
  if (cents == null || cents <= 0) {
    return kLimousineShowroomPriceOnRequest.of(language);
  }
  return _money(cents, currency);
}

String limousineDetailOfferKindLabel(
  LimousineOfferDisplayKind kind,
  AppLanguage language,
) {
  if (kind == LimousineOfferDisplayKind.fromPrice) {
    return kLimousineOfferFromPriceKind.of(language);
  }
  return limousineOfferKindLabel(kind, language);
}

String limousineShowroomOffersExtraLabel(int extraCount, AppLanguage language) {
  if (extraCount <= 0) return '';
  return '+ $extraCount ${kLimousineOfferExtraArrangements.of(language)}';
}

String limousineIncludedServicesLabel(
  LimousinePublishedOffer offer,
  AppLanguage language,
) {
  final labels = <String>[];
  for (final item in offer.includedServices) {
    final text = localizedLimousineText(
      item['label'],
      languageCode: language.name,
    );
    if (text.isNotEmpty) labels.add(text);
  }
  return labels.join(' · ');
}
