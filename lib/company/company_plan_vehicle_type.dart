// COMPANY-AGENDA-P0 — sedan/minivan are vehicle types, not ride modes.

import 'package:flutter/widgets.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/company/company_agenda_labels.dart';
import 'package:fluxidi_tracking/company/company_driver_agenda_style.dart';

enum CompanyPlanVehicleType { sedan, minivan }

enum CompanyPlanVehicleCategory {
  compact,
  sedan,
  breakWagon,
  suv,
  minivan,
  minibus,
  premium,
  wheelchair,
}

enum CompanyPlanVehicleBadge { electric, extraBags, childSeat, pets, premium, accessible }

const String kCompanyPlanVehicleTypeSedan = 'sedan';
const String kCompanyPlanVehicleTypeMinivan = 'minivan';

const int kCompanyPlanSedanMaxPassengers = 3;
const int kCompanyPlanMinivanTypicalPassengers = 7;
const int kCompanyPlanSedanMaxBags = 3;
const int kCompanyPlanMinivanTypicalBags = 7;

const Key kCompanyAgendaVehicleTypeSedanKey = Key(
  'company_agenda_vehicle_type_sedan',
);
const Key kCompanyAgendaVehicleTypeMinivanKey = Key(
  'company_agenda_vehicle_type_minivan',
);
const Key kCompanyAgendaAirportModeKey = Key('company_agenda_airport_mode');
const Key kCompanyAgendaRegularRideKey = Key('company_agenda_regular_ride');
const Key kCompanyAgendaReturnSummaryKey = Key('company_agenda_return_summary');
const Key kCompanyAgendaWaitPriceKey = Key('company_agenda_wait_price');
const Key kCompanyAgendaBagsPriceKey = Key('company_agenda_bags_price');

CompanyPlanVehicleType? parseCompanyPlanVehicleType(String? raw) {
  switch (raw?.trim().toLowerCase() ?? '') {
    case kCompanyPlanVehicleTypeSedan:
    case 'berline':
      return CompanyPlanVehicleType.sedan;
    case kCompanyPlanVehicleTypeMinivan:
    case 'van':
    case 'minibus':
      return CompanyPlanVehicleType.minivan;
    case 'airport':
    case 'airport_ride':
      return null;
    default:
      return null;
  }
}

String companyPlanVehicleTypeWire(CompanyPlanVehicleType type) {
  return switch (type) {
    CompanyPlanVehicleType.sedan => kCompanyPlanVehicleTypeSedan,
    CompanyPlanVehicleType.minivan => kCompanyPlanVehicleTypeMinivan,
  };
}

int companyPlanVehicleTypeMaxPassengers(CompanyPlanVehicleType type) {
  return switch (type) {
    CompanyPlanVehicleType.sedan => kCompanyPlanSedanMaxPassengers,
    CompanyPlanVehicleType.minivan => kCompanyPlanMinivanTypicalPassengers,
  };
}

int companyPlanVehicleTypeMaxBags(CompanyPlanVehicleType type) {
  return switch (type) {
    CompanyPlanVehicleType.sedan => kCompanyPlanSedanMaxBags,
    CompanyPlanVehicleType.minivan => kCompanyPlanMinivanTypicalBags,
  };
}

bool companyPlanVehicleTypeFitsCapacity({
  required CompanyPlanVehicleType type,
  required int passengers,
  required int bags,
}) {
  return passengers <= companyPlanVehicleTypeMaxPassengers(type) &&
      bags <= companyPlanVehicleTypeMaxBags(type);
}

CompanyPlanVehicleType? companyPlanSuggestedTypeForCapacity({
  required int passengers,
  required int bags,
  required Iterable<CompanyPlanVehicleType> available,
}) {
  for (final type in available) {
    if (companyPlanVehicleTypeFitsCapacity(
      type: type,
      passengers: passengers,
      bags: bags,
    )) {
      return type;
    }
  }
  return null;
}

String companyPlanVehicleTypeLabel(
  CompanyPlanVehicleType type,
  AppLanguage language,
) {
  return switch (type) {
    CompanyPlanVehicleType.sedan => kCompanyAgendaVehicleTypeSedan.of(language),
    CompanyPlanVehicleType.minivan => kCompanyAgendaVehicleTypeMinivan.of(
      language,
    ),
  };
}

String companyPlanVehicleTypeCapacityLabel(
  CompanyPlanVehicleType type,
  AppLanguage language,
) {
  final max = companyPlanVehicleTypeMaxPassengers(type);
  return language == AppLanguage.fr
      ? '1–$max pers.'
      : language == AppLanguage.es
      ? '1–$max pers.'
      : language == AppLanguage.nl
      ? '1–$max pers.'
      : '1–$max pax';
}

CompanyPlanVehicleType companyPlanVehicleTypeForPassengers(int passengers) {
  return passengers > kCompanyPlanSedanMaxPassengers
      ? CompanyPlanVehicleType.minivan
      : CompanyPlanVehicleType.sedan;
}

String _vehicleTypeToken(Map<String, dynamic> raw) {
  const keys = <String>[
    'vehicle_type',
    'vehicleType',
    'type',
    'class',
    'vehicle_class',
    'vehicleClass',
    'service_class',
    'serviceClass',
    'tier',
    'vehicle_name',
    'vehicleName',
    'brand_model',
    'brandModel',
    'label',
  ];
  final parts = <String>[];
  for (final key in keys) {
    final text = raw[key]?.toString().trim().toLowerCase() ?? '';
    if (text.isNotEmpty) parts.add(text);
  }
  return parts.join(' ');
}

bool companyPlanVehicleLooksLikeSedan(Map<String, dynamic> raw) {
  final token = _vehicleTypeToken(raw);
  if (token.contains('minivan') ||
      token.contains('minibus') ||
      token.contains('van') ||
      token.contains('vito') ||
      token.contains('transporter') ||
      token.contains('class v')) {
    return false;
  }
  if (token.contains('sedan') ||
      token.contains('berline') ||
      token.contains('saloon')) {
    return true;
  }
  final capacity = companyAgendaVehicleCapacity(raw);
  return capacity > 0 && capacity <= kCompanyPlanSedanMaxPassengers;
}

bool companyPlanVehicleLooksLikeMinivan(Map<String, dynamic> raw) {
  final token = _vehicleTypeToken(raw);
  if (token.contains('minivan') ||
      token.contains('minibus') ||
      token.contains('van') ||
      token.contains('vito') ||
      token.contains('transporter')) {
    return true;
  }
  if (companyPlanVehicleLooksLikeSedan(raw)) return false;
  final capacity = companyAgendaVehicleCapacity(raw);
  return capacity > kCompanyPlanSedanMaxPassengers;
}

bool companyPlanVehicleMatchesType(
  Map<String, dynamic> raw,
  CompanyPlanVehicleType type,
) {
  return switch (type) {
    CompanyPlanVehicleType.sedan => companyPlanVehicleLooksLikeSedan(raw),
    CompanyPlanVehicleType.minivan => companyPlanVehicleLooksLikeMinivan(raw),
  };
}

String companyPlanVehicleCategoryWire(CompanyPlanVehicleCategory category) {
  return switch (category) {
    CompanyPlanVehicleCategory.compact => 'compact',
    CompanyPlanVehicleCategory.sedan => kCompanyPlanVehicleTypeSedan,
    CompanyPlanVehicleCategory.breakWagon => 'break',
    CompanyPlanVehicleCategory.suv => 'suv',
    CompanyPlanVehicleCategory.minivan => kCompanyPlanVehicleTypeMinivan,
    CompanyPlanVehicleCategory.minibus => 'minibus',
    CompanyPlanVehicleCategory.premium => 'premium',
    CompanyPlanVehicleCategory.wheelchair => 'wheelchair',
  };
}

CompanyPlanVehicleType companyPlanVehicleTypeForCategory(
  CompanyPlanVehicleCategory category,
) {
  return switch (category) {
    CompanyPlanVehicleCategory.compact ||
    CompanyPlanVehicleCategory.sedan ||
    CompanyPlanVehicleCategory.breakWagon ||
    CompanyPlanVehicleCategory.premium =>
      CompanyPlanVehicleType.sedan,
    CompanyPlanVehicleCategory.suv ||
    CompanyPlanVehicleCategory.minivan ||
    CompanyPlanVehicleCategory.minibus ||
    CompanyPlanVehicleCategory.wheelchair =>
      CompanyPlanVehicleType.minivan,
  };
}

bool _tokenHas(String token, List<String> needles) {
  for (final needle in needles) {
    if (token.contains(needle)) return true;
  }
  return false;
}

CompanyPlanVehicleCategory? classifyCompanyPlanVehicleCategory(
  Map<String, dynamic> raw,
) {
  final token = _vehicleTypeToken(raw);
  if (_tokenHas(token, const [
    'wheelchair',
    'rolstoel',
    'accessible',
    'wav',
  ])) {
    return CompanyPlanVehicleCategory.wheelchair;
  }
  if (_tokenHas(token, const ['minibus', 'sprinter', 'coach'])) {
    return CompanyPlanVehicleCategory.minibus;
  }
  if (_tokenHas(token, const ['suv', 'crossover', 'gle', 'x5', 'q7', 'cayenne'])) {
    return CompanyPlanVehicleCategory.suv;
  }
  if (_tokenHas(token, const ['break', 'station', 'estate', 'touring', 'avant'])) {
    return CompanyPlanVehicleCategory.breakWagon;
  }
  if (_tokenHas(token, const [
    'compact',
    'hatch',
    'golf',
    'polo',
    'fiesta',
  ])) {
    return CompanyPlanVehicleCategory.compact;
  }
  final tier = (raw['tier'] ??
          raw['tierId'] ??
          raw['service_class'] ??
          raw['serviceClass'] ??
          raw['service_category'] ??
          raw['serviceCategory'] ??
          '')
      .toString()
      .toLowerCase();
  if (_tokenHas(token, const [
        'limousine',
        's-klasse',
        's klasse',
        'ghost',
        'phantom',
        'maybach',
      ]) ||
      _tokenHas(tier, const ['premium', 'limousine', 'private'])) {
    return CompanyPlanVehicleCategory.premium;
  }
  if (companyPlanVehicleLooksLikeMinivan(raw)) {
    return CompanyPlanVehicleCategory.minivan;
  }
  if (companyPlanVehicleLooksLikeSedan(raw)) {
    return CompanyPlanVehicleCategory.sedan;
  }
  return null;
}

String companyPlanVehicleCategoryLabel(
  CompanyPlanVehicleCategory category,
  AppLanguage language,
) {
  return switch (category) {
    CompanyPlanVehicleCategory.compact =>
      kCompanyAgendaVehicleCategoryCompact.of(language),
    CompanyPlanVehicleCategory.sedan => companyPlanVehicleTypeLabel(
      CompanyPlanVehicleType.sedan,
      language,
    ),
    CompanyPlanVehicleCategory.breakWagon =>
      kCompanyAgendaVehicleCategoryBreak.of(language),
    CompanyPlanVehicleCategory.suv =>
      kCompanyAgendaVehicleCategorySuv.of(language),
    CompanyPlanVehicleCategory.minivan => companyPlanVehicleTypeLabel(
      CompanyPlanVehicleType.minivan,
      language,
    ),
    CompanyPlanVehicleCategory.minibus =>
      kCompanyAgendaVehicleCategoryMinibus.of(language),
    CompanyPlanVehicleCategory.premium =>
      kCompanyAgendaVehicleCategoryPremium.of(language),
    CompanyPlanVehicleCategory.wheelchair =>
      kCompanyAgendaVehicleCategoryWheelchair.of(language),
  };
}

List<CompanyPlanVehicleBadge> companyPlanVehicleBadges(
  Map<String, dynamic> raw,
) {
  final token = _vehicleTypeToken(raw);
  final extras = <String>[
    token,
    ...(raw['extras'] is List
        ? [for (final item in raw['extras'] as List) item.toString()]
        : const <String>[]),
    ...(raw['features'] is List
        ? [for (final item in raw['features'] as List) item.toString()]
        : const <String>[]),
    ...(raw['amenities'] is List
        ? [for (final item in raw['amenities'] as List) item.toString()]
        : const <String>[]),
  ].join(' ').toLowerCase();
  final bags = raw['luggage_capacity'] ?? raw['luggageCapacity'];
  final bagCount = bags is num ? bags.round() : int.tryParse(bags?.toString() ?? '') ?? 0;
  return [
    if (_tokenHas(extras, const ['electric', 'elektr', 'tesla', 'e-tron', 'ev ']))
      CompanyPlanVehicleBadge.electric,
    if (bagCount >= 4 || _tokenHas(extras, const ['extra bag', 'extra_luggage']))
      CompanyPlanVehicleBadge.extraBags,
    if (_tokenHas(extras, const ['child', 'kinderstoel', 'baby_seat']))
      CompanyPlanVehicleBadge.childSeat,
    if (_tokenHas(extras, const ['pet', 'huisdier']))
      CompanyPlanVehicleBadge.pets,
    if (_tokenHas(extras, const ['premium', 'limousine']))
      CompanyPlanVehicleBadge.premium,
    if (_tokenHas(extras, const ['wheelchair', 'rolstoel', 'accessible']))
      CompanyPlanVehicleBadge.accessible,
  ];
}

String companyPlanVehicleBadgeLabel(
  CompanyPlanVehicleBadge badge,
  AppLanguage language,
) {
  return switch (badge) {
    CompanyPlanVehicleBadge.electric => kCompanyAgendaBadgeElectric.of(language),
    CompanyPlanVehicleBadge.extraBags => kCompanyAgendaBadgeBags.of(language),
    CompanyPlanVehicleBadge.childSeat =>
      kCompanyAgendaBadgeChildSeat.of(language),
    CompanyPlanVehicleBadge.pets => kCompanyAgendaBadgePets.of(language),
    CompanyPlanVehicleBadge.premium => kCompanyAgendaBadgePremium.of(language),
    CompanyPlanVehicleBadge.accessible =>
      kCompanyAgendaBadgeAccessible.of(language),
  };
}

List<CompanyPlanVehicleCategory> companyPlanBookableCategories({
  required List<Map<String, dynamic>> vehicles,
  required int passengers,
  bool customerFacing = false,
}) {
  final found = <CompanyPlanVehicleCategory>{};
  for (final vehicle in vehicles) {
    if (!companyAgendaVehicleIsActive(vehicle)) continue;
    if (companyAgendaVehicleId(vehicle).isEmpty) continue;
    if (customerFacing &&
        !companyAgendaVehicleIsSuitable(vehicle, passengers: passengers)) {
      continue;
    }
    final category = classifyCompanyPlanVehicleCategory(vehicle);
    if (category != null) found.add(category);
  }
  return CompanyPlanVehicleCategory.values
      .where(found.contains)
      .toList(growable: false);
}

String? companyPlanCategoryUnavailableReason({
  required CompanyPlanVehicleCategory category,
  required List<Map<String, dynamic>> vehicles,
  required int passengers,
  required AppLanguage language,
}) {
  final typed = companyPlanVehiclesForCategory(
    vehicles: vehicles,
    category: category,
    passengers: 1,
  );
  if (typed.isEmpty) return kCompanyAgendaTypeUnavailable.of(language);
  final fitting = typed.where(
    (vehicle) => companyAgendaVehicleFitsPassengers(vehicle, passengers),
  );
  if (fitting.isEmpty) return kCompanyAgendaCapacityShort.of(language);
  return null;
}

List<Map<String, dynamic>> companyPlanVehiclesForCategory({
  required List<Map<String, dynamic>> vehicles,
  required CompanyPlanVehicleCategory category,
  required int passengers,
}) {
  final exact = [
    for (final vehicle in vehicles)
      if (companyAgendaVehicleIsSuitable(vehicle, passengers: passengers) &&
          classifyCompanyPlanVehicleCategory(vehicle) == category)
        vehicle,
  ];
  if (exact.isNotEmpty) return exact;
  return companyPlanVehiclesForType(
    vehicles: vehicles,
    type: companyPlanVehicleTypeForCategory(category),
    passengers: passengers,
  );
}

List<Map<String, dynamic>> companyPlanVehiclesForType({
  required List<Map<String, dynamic>> vehicles,
  required CompanyPlanVehicleType type,
  required int passengers,
}) {
  final typed = [
    for (final vehicle in vehicles)
      if (companyAgendaVehicleIsSuitable(vehicle, passengers: passengers) &&
          companyPlanVehicleMatchesType(vehicle, type))
        vehicle,
  ];
  if (typed.isNotEmpty) return typed;
  return [
    for (final vehicle in vehicles)
      if (companyAgendaVehicleIsSuitable(vehicle, passengers: passengers))
        vehicle,
  ];
}
