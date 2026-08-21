// LIMOUSINE-MARKETPLACE-P2B2 — company Limousine offers: pure model, validation
// and safe public projection. Mirrors
// workers/booking/modules/limousine_offers.mjs so the admin UI, the tests and
// the server agree on one contract.
//
// Offers are plain JSON maps (same pattern as the airport fixed-fare rules in
// Business settings). All money is integer minor units (cents).

import '../app_config.dart';
import '../app_strings.dart';
import 'limousine_dimensions.dart';

abstract final class LimousinePricePresentation {
  static const String exactFixed = 'exact_fixed';
  static const String fromPrice = 'from_price';
  static const String indicative = 'indicative';
  static const String quoteRequired = 'quote_required';
  static const String unavailable = 'unavailable';

  static const List<String> all = <String>[
    exactFixed,
    fromPrice,
    indicative,
    quoteRequired,
    unavailable,
  ];
}

abstract final class LimousineOfferTarget {
  static const String vehicle = 'vehicle';
  static const String serviceClass = 'service_class';

  static const List<String> all = <String>[vehicle, serviceClass];
}

abstract final class LimousineMobilisationMethod {
  static const String included = 'included';
  static const String fixedFee = 'fixed_fee';
  static const String distanceTime = 'distance_time';

  static const List<String> all = <String>[included, fixedFee, distanceTime];
}

abstract final class LimousineJourneyTypeId {
  static const String pointToPoint = 'point_to_point';
  static const String airportTransfer = 'airport_transfer';
  static const String hotelTransfer = 'hotel_transfer';
  static const String eventTransfer = 'event_transfer';
  static const String hourlyPackage = 'hourly_package';

  static const List<String> all = <String>[
    pointToPoint,
    airportTransfer,
    hotelTransfer,
    eventTransfer,
    hourlyPackage,
  ];
}

abstract final class LimousineOfferError {
  static const String missingOfferId = 'missing_offer_id';
  static const String unknownTarget = 'unknown_target';
  static const String unknownVehicle = 'unknown_vehicle';
  static const String inactiveVehicle = 'inactive_vehicle';
  static const String vehicleNotLimousine = 'vehicle_not_limousine';
  static const String unknownServiceClass = 'unknown_service_class';
  static const String missingCurrency = 'missing_currency';
  static const String currencyConflict = 'currency_conflict';
  static const String negativeAmount = 'negative_amount';
  static const String invalidPresentation = 'invalid_presentation';
  static const String missingDisplayAmount = 'missing_display_amount';
  static const String incompleteFixedRule = 'incomplete_fixed_rule';
  static const String duplicateRule = 'duplicate_rule';
  static const String hourlyMissingMinimumDuration =
      'hourly_missing_minimum_duration';
  static const String hourlyIncomplete = 'hourly_incomplete';
  static const String packageIncomplete = 'package_incomplete';
  static const String mobilisationIncomplete = 'mobilisation_incomplete';
  static const String mobilisationContradictory = 'mobilisation_contradictory';
  static const String publishedWithoutReadiness = 'published_without_readiness';
  static const String distanceTimeIncomplete = 'distance_time_incomplete';
  static const String missingJourneyTypes = 'missing_journey_types';
}

String limousineOfferToken(Object? raw) => (raw ?? '')
    .toString()
    .trim()
    .toLowerCase()
    .replaceAll(RegExp(r'[\s-]+'), '_');

List<String> limousineNormalizeBoundVehicleIds(Object? raw, {Object? single}) {
  final out = <String>[];
  final seen = <String>{};
  void add(Object? value) {
    final id = (value ?? '').toString().trim();
    if (id.isEmpty || id.length > 96 || !seen.add(id)) return;
    out.add(id);
  }

  if (raw is List) {
    for (final item in raw) {
      add(item);
    }
  }
  add(single);
  return out;
}

bool _boolOf(Object? raw, {bool fallback = false}) {
  if (raw is bool) return raw;
  final t = limousineOfferToken(raw);
  if (t == 'true' || t == '1' || t == 'yes' || t == 'on') return true;
  if (t == 'false' || t == '0' || t == 'no' || t == 'off') return false;
  return fallback;
}

/// Integer cents. Returns null when absent/invalid; negatives are preserved so
/// validation can reject them explicitly rather than silently clamping.
///
/// Stored whole numbers stay cents. Decimal / locale text (`250.00`, `250,00`)
/// is authored major-unit input and is converted to cents. Duration fields must
/// use [limousineMinutesOf] — never this helper.
int? limousineCentsOf(Object? raw) {
  if (raw == null) return null;
  if (raw is int) return raw;
  if (raw is num) return raw.truncate();
  final original = raw.toString().trim();
  if (original.isEmpty) return null;
  final asStoredInt = int.tryParse(original);
  if (asStoredInt != null) return asStoredInt;
  return limousineCentsFromMajorUnitText(original);
}

/// Editor / locale money text (`250`, `250.00`, `250,00`) → integer cents.
int? limousineCentsFromMajorUnitText(String raw) {
  final text = raw.trim().replaceAll(',', '.');
  if (text.isEmpty) return null;
  final value = double.tryParse(text);
  if (value == null) return null;
  return (value * 100).round();
}

String limousineMajorUnitTextFromCents(int? cents) =>
    cents == null ? '' : (cents / 100).toStringAsFixed(2);

/// Whole minutes. Accepts ints, `60.0`, and locale text (`60,0`) without
/// converting major units to cents.
int? limousineMinutesOf(Object? raw) {
  if (raw == null) return null;
  if (raw is int) return raw;
  if (raw is num) return raw.truncate();
  final text = raw.toString().trim().replaceAll(',', '.');
  if (text.isEmpty) return null;
  final asInt = int.tryParse(text);
  if (asInt != null) return asInt;
  final asDouble = double.tryParse(text);
  if (asDouble == null) return null;
  return asDouble.round();
}

int? _intOf(Object? raw) => limousineMinutesOf(raw);

final RegExp _kLimousinePublicSortOrderPattern = RegExp(r'^[1-9][0-9]*$');

class LimousinePublicSortOrderParse {
  const LimousinePublicSortOrderParse.automatic()
    : value = null,
      errorCode = null;
  const LimousinePublicSortOrderParse.explicit(this.value) : errorCode = null;
  const LimousinePublicSortOrderParse.invalid()
    : value = null,
      errorCode = 'sort_order_invalid';

  final int? value;
  final String? errorCode;
  bool get isValid => errorCode == null;
  bool get isAutomatic => isValid && value == null;
}

LimousinePublicSortOrderParse parseLimousinePublicSortOrderInput(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return const LimousinePublicSortOrderParse.automatic();
  if (!_kLimousinePublicSortOrderPattern.hasMatch(text)) {
    return const LimousinePublicSortOrderParse.invalid();
  }
  return LimousinePublicSortOrderParse.explicit(int.parse(text));
}

/// Stored/backend value. 0, negative, decimal and junk become automatic.
int? limousinePublicSortOrderOf(Object? raw) {
  if (raw == null) return null;
  if (raw is int) return raw >= 1 ? raw : null;
  if (raw is num) {
    if (raw != raw.roundToDouble() || raw < 1) return null;
    return raw.toInt();
  }
  final parsed = parseLimousinePublicSortOrderInput(raw.toString());
  return parsed.isValid ? parsed.value : null;
}

bool limousineOfferFlag(Object? raw, {bool fallback = false}) =>
    _boolOf(raw, fallback: fallback);

enum LimousineSimpleOfferMode { quote, fromPrice, fixed, hourly, package }

class LimousineHourlyHireValidation {
  const LimousineHourlyHireValidation({
    required this.firstHourCents,
    required this.additionalHourCents,
    required this.minimumDurationMinutes,
    required this.errors,
    required this.fieldErrors,
  });

  final int? firstHourCents;
  final int? additionalHourCents;
  final int? minimumDurationMinutes;
  final List<String> errors;
  final Map<String, String> fieldErrors;

  bool get isValid => errors.isEmpty;
}

class LimousinePackageHireValidation {
  const LimousinePackageHireValidation({
    required this.packageAmountCents,
    required this.packageDurationMinutes,
    required this.errors,
    required this.fieldErrors,
  });

  final int? packageAmountCents;
  final int? packageDurationMinutes;
  final List<String> errors;
  final Map<String, String> fieldErrors;

  bool get isValid => errors.isEmpty;
}

class LimousineSimpleOfferValidation {
  const LimousineSimpleOfferValidation({
    required this.mode,
    required this.configured,
    required this.errors,
    this.fieldErrors = const <String, String>{},
  });

  final LimousineSimpleOfferMode mode;
  final bool configured;
  final List<String> errors;
  final Map<String, String> fieldErrors;

  bool get isValid => configured && errors.isEmpty;
}

/// Canonical hourly-hire field check. Package leftovers are ignored here.
LimousineHourlyHireValidation limousineHourlyHireValidation(Object? hourlyRaw) {
  final hourly = _mapOf(hourlyRaw);
  final first = limousineCentsOf(hourly['first_hour_cents']);
  final additional = limousineCentsOf(hourly['additional_hour_cents']);
  final minimum = limousineMinutesOf(hourly['minimum_duration_minutes']);
  final errors = <String>{};
  final fields = <String, String>{};
  if (first == null || first <= 0) {
    fields['first_hour'] = LimousineOfferError.hourlyIncomplete;
    errors.add(LimousineOfferError.hourlyIncomplete);
  }
  if (additional == null || additional <= 0) {
    fields['additional_hour'] = LimousineOfferError.hourlyIncomplete;
    errors.add(LimousineOfferError.hourlyIncomplete);
  }
  if (minimum == null || minimum <= 0) {
    fields['min_duration'] = LimousineOfferError.hourlyMissingMinimumDuration;
    errors.add(LimousineOfferError.hourlyMissingMinimumDuration);
  }
  return LimousineHourlyHireValidation(
    firstHourCents: first,
    additionalHourCents: additional,
    minimumDurationMinutes: minimum,
    errors: errors.toList(growable: false),
    fieldErrors: fields,
  );
}

/// Package fields are required only when [required] is true.
LimousinePackageHireValidation limousinePackageHireValidation(
  Object? hourlyRaw, {
  required bool required,
}) {
  final hourly = _mapOf(hourlyRaw);
  final amount = limousineCentsOf(hourly['package_amount_cents']);
  final duration = limousineMinutesOf(hourly['package_duration_minutes']);
  final hasAmount = amount != null && amount > 0;
  final hasDuration = duration != null && duration > 0;
  if (!required || (hasAmount && hasDuration)) {
    return LimousinePackageHireValidation(
      packageAmountCents: amount,
      packageDurationMinutes: duration,
      errors: const <String>[],
      fieldErrors: const <String, String>{},
    );
  }
  return LimousinePackageHireValidation(
    packageAmountCents: amount,
    packageDurationMinutes: duration,
    errors: const <String>[LimousineOfferError.packageIncomplete],
    fieldErrors: <String, String>{
      if (!hasDuration)
        'package_duration': LimousineOfferError.packageIncomplete,
      if (!hasAmount) 'package_amount': LimousineOfferError.packageIncomplete,
    },
  );
}

LimousineSimpleOfferMode? limousineSimpleOfferModeOf(
  Map<String, dynamic> offer,
) {
  final hourlyOn = _boolOf(_mapOf(offer['hourly'])['enabled']);
  final presentation = limousineOfferToken(offer['price_presentation']);
  if (hourlyOn) {
    return presentation == LimousinePricePresentation.exactFixed
        ? LimousineSimpleOfferMode.package
        : LimousineSimpleOfferMode.hourly;
  }
  if (presentation == LimousinePricePresentation.quoteRequired) {
    return LimousineSimpleOfferMode.quote;
  }
  if (presentation == LimousinePricePresentation.fromPrice) {
    return LimousineSimpleOfferMode.fromPrice;
  }
  if (presentation == LimousinePricePresentation.exactFixed) {
    return LimousineSimpleOfferMode.fixed;
  }
  return null;
}

const Set<String> _kSimpleOfferSharedErrors = <String>{
  LimousineOfferError.missingOfferId,
  LimousineOfferError.unknownTarget,
  LimousineOfferError.unknownVehicle,
  LimousineOfferError.inactiveVehicle,
  LimousineOfferError.vehicleNotLimousine,
  LimousineOfferError.unknownServiceClass,
  LimousineOfferError.missingCurrency,
  LimousineOfferError.currencyConflict,
  LimousineOfferError.negativeAmount,
};

Set<String> _simpleOfferPricingErrors(LimousineSimpleOfferMode mode) {
  switch (mode) {
    case LimousineSimpleOfferMode.quote:
      return const <String>{};
    case LimousineSimpleOfferMode.fromPrice:
      return const <String>{LimousineOfferError.missingDisplayAmount};
    case LimousineSimpleOfferMode.fixed:
      return const <String>{LimousineOfferError.incompleteFixedRule};
    case LimousineSimpleOfferMode.hourly:
      return const <String>{
        LimousineOfferError.hourlyIncomplete,
        LimousineOfferError.hourlyMissingMinimumDuration,
      };
    case LimousineSimpleOfferMode.package:
      return const <String>{LimousineOfferError.packageIncomplete};
  }
}

Map<String, String> _simpleOfferFieldErrors({
  required LimousineSimpleOfferMode mode,
  required Map<String, dynamic> offer,
}) {
  final hourly = _mapOf(offer['hourly']);
  switch (mode) {
    case LimousineSimpleOfferMode.hourly:
      return limousineHourlyHireValidation(hourly).fieldErrors;
    case LimousineSimpleOfferMode.package:
      return limousinePackageHireValidation(hourly, required: true).fieldErrors;
    case LimousineSimpleOfferMode.fromPrice:
      final display = limousineCentsOf(offer['display_amount_cents']);
      if (display == null || display <= 0) {
        return const <String, String>{
          'amount': LimousineOfferError.missingDisplayAmount,
        };
      }
      return const <String, String>{};
    case LimousineSimpleOfferMode.fixed:
      final rules = _listOf(offer['fixed_rules']);
      final amount = limousineCentsOf(
        rules.isEmpty
            ? offer['display_amount_cents']
            : rules.first['amount_cents'],
      );
      if (amount == null || amount <= 0) {
        return const <String, String>{
          'amount': LimousineOfferError.incompleteFixedRule,
        };
      }
      return const <String, String>{};
    case LimousineSimpleOfferMode.quote:
      return const <String, String>{};
  }
}

/// One validation outcome per simple offer type. Shared by the card, editor,
/// publication check and public limousine projection.
LimousineSimpleOfferValidation limousineValidateSimpleOffer(
  Map<String, dynamic>? offer, {
  required LimousineSimpleOfferMode mode,
  List<VehicleProfile> vehicles = const <VehicleProfile>[],
  List<String> knownClassIds = const <String>[],
}) {
  if (offer == null) {
    return LimousineSimpleOfferValidation(
      mode: mode,
      configured: false,
      errors: const <String>[],
      fieldErrors: _simpleOfferFieldErrors(
        mode: mode,
        offer: <String, dynamic>{
          'hourly': <String, dynamic>{'enabled': true},
        },
      ),
    );
  }
  final contract = validateLimousineOffer(
    offer,
    vehicles: vehicles,
    knownClassIds: knownClassIds,
    readiness: true,
  );
  final keep = <String>{
    ..._kSimpleOfferSharedErrors,
    ..._simpleOfferPricingErrors(mode),
  };
  var errors = contract.errors.where(keep.contains).toList(growable: false);
  if (mode == LimousineSimpleOfferMode.hourly) {
    errors = limousineHourlyHireValidation(offer['hourly']).errors
        .followedBy(contract.errors.where(_kSimpleOfferSharedErrors.contains))
        .toSet()
        .toList(growable: false);
  } else if (mode == LimousineSimpleOfferMode.package) {
    errors = limousinePackageHireValidation(offer['hourly'], required: true)
        .errors
        .followedBy(contract.errors.where(_kSimpleOfferSharedErrors.contains))
        .toSet()
        .toList(growable: false);
  }
  return LimousineSimpleOfferValidation(
    mode: mode,
    configured: true,
    errors: errors,
    fieldErrors: _simpleOfferFieldErrors(mode: mode, offer: offer),
  );
}

String limousineCurrencyOf(Object? raw) {
  final c = (raw ?? '').toString().trim().toUpperCase();
  return RegExp(r'^[A-Z]{3}$').hasMatch(c) ? c : '';
}

Map<String, dynamic> _mapOf(Object? raw) {
  if (raw is Map<String, dynamic>) return raw;
  if (raw is Map) return raw.map((k, v) => MapEntry(k.toString(), v));
  return <String, dynamic>{};
}

List<Map<String, dynamic>> _listOf(Object? raw) {
  if (raw is! List) return const <Map<String, dynamic>>[];
  return raw.whereType<Map>().map(_mapOf).toList(growable: false);
}

/// A localized {nl,en,fr,es} block.
Map<String, String> limousineLocalizedOf(Object? raw) {
  final src = _mapOf(raw);
  return <String, String>{
    for (final lang in const ['nl', 'en', 'fr', 'es'])
      lang: (src[lang] ?? '').toString().trim(),
  };
}

String limousineLocalizedFor(Object? raw, AppLanguage language) {
  final map = limousineLocalizedOf(raw);
  switch (language) {
    case AppLanguage.nl:
      return map['nl'] ?? '';
    case AppLanguage.fr:
      return map['fr'] ?? '';
    case AppLanguage.es:
      return map['es'] ?? '';
    case AppLanguage.en:
    case AppLanguage.de:
      return map['en'] ?? '';
  }
}

bool _localizedIsEmpty(Object? raw) =>
    limousineLocalizedOf(raw).values.every((v) => v.trim().isEmpty);

class LimousineOfferValidation {
  const LimousineOfferValidation({required this.errors});

  final List<String> errors;

  bool get valid => errors.isEmpty;
}

bool _fixedRuleComplete(Map<String, dynamic> rule) {
  if ((rule['rule_id'] ?? '').toString().trim().isEmpty) return false;
  final journey = limousineOfferToken(rule['journey_type']);
  if (!LimousineJourneyTypeId.all.contains(journey)) return false;
  final amount = limousineCentsOf(rule['amount_cents']);
  if (amount == null || amount <= 0) return false;
  if (limousineCurrencyOf(rule['currency']).isEmpty) return false;
  if (journey == LimousineJourneyTypeId.airportTransfer &&
      (rule['airport_iata'] ?? '').toString().trim().isEmpty) {
    return false;
  }
  final zoneType = limousineOfferToken(rule['zone_type']);
  if (zoneType == 'radius') {
    final lat = double.tryParse('${rule['zone_center_lat']}');
    final lng = double.tryParse('${rule['zone_center_lng']}');
    final radius = double.tryParse('${rule['radius_km']}');
    if (lat == null || lng == null || radius == null || radius <= 0)
      return false;
  }
  if (zoneType == 'postcode' || zoneType == 'city' || zoneType == 'country') {
    if ((rule['zone_value'] ?? '').toString().trim().isEmpty) return false;
  }
  return true;
}

bool _distanceTimeComplete(Map<String, dynamic> dt) {
  if (!_boolOf(dt['enabled'])) return true;
  for (final key in const [
    'base_incl_vat_cents',
    'per_km_incl_vat_cents',
    'per_minute_incl_vat_cents',
    'minimum_incl_vat_cents',
  ]) {
    if (limousineCentsOf(dt[key]) == null) return false;
  }
  return limousineCurrencyOf(dt['currency']).isNotEmpty;
}

/// Authoritative offer validation. Fails closed on every rule in the P2B2
/// contract. `vehicles` are the company's authoritative vehicles.
LimousineOfferValidation validateLimousineOffer(
  Map<String, dynamic> offer, {
  List<VehicleProfile> vehicles = const <VehicleProfile>[],
  List<String> knownClassIds = const <String>[],
  bool readiness = false,
}) {
  final errors = <String>{};

  final offerId = (offer['offer_id'] ?? '').toString().trim();
  if (offerId.isEmpty) errors.add(LimousineOfferError.missingOfferId);

  final targetType = limousineOfferToken(offer['target_type']);
  if (!LimousineOfferTarget.all.contains(targetType)) {
    errors.add(LimousineOfferError.unknownTarget);
  }

  final presentation = limousineOfferToken(offer['price_presentation']);
  if (!LimousinePricePresentation.all.contains(presentation)) {
    errors.add(LimousineOfferError.invalidPresentation);
  }

  final currency = limousineCurrencyOf(offer['currency']);
  if (currency.isEmpty) errors.add(LimousineOfferError.missingCurrency);

  final classIds = knownClassIds.map(limousineOfferToken).toSet();

  final boundIds = <String>[
    ...limousineNormalizeBoundVehicleIds(
      offer['vehicle_ids'] ?? offer['vehicleIds'],
      single: offer['vehicle_id'] ?? offer['vehicleId'],
    ),
  ];
  final appliesToAll =
      offer.containsKey('applies_to_all_selected_vehicles') ||
          offer.containsKey('appliesToAllSelectedVehicles')
      ? _boolOf(
          offer['applies_to_all_selected_vehicles'] ??
              offer['appliesToAllSelectedVehicles'],
        )
      : boundIds.isEmpty;
  if (appliesToAll) {
    final classId = limousineOfferToken(offer['service_class_id']);
    if (classId.isNotEmpty && !classIds.contains(classId)) {
      errors.add(LimousineOfferError.unknownServiceClass);
    }
  } else if (targetType == LimousineOfferTarget.vehicle ||
      boundIds.isNotEmpty) {
    final records = <VehicleProfile>[
      for (final id in boundIds)
        for (final vehicle in vehicles)
          if (vehicle.id == id) vehicle,
    ];
    final validRecords = records
        .where((vehicle) {
          if (!vehicle.isActive) return false;
          if (limousineOfferToken(vehicle.serviceCategory) != 'limousine') {
            return false;
          }
          final vehicleClass = limousineOfferToken(vehicle.serviceClassId);
          return vehicleClass.isNotEmpty &&
              !isForbiddenClassInferenceToken(vehicleClass);
        })
        .toList(growable: false);
    if (boundIds.isEmpty || records.isEmpty) {
      errors.add(LimousineOfferError.unknownVehicle);
    } else if (validRecords.isEmpty) {
      final vehicle = records.first;
      if (!vehicle.isActive) errors.add(LimousineOfferError.inactiveVehicle);
      if (limousineOfferToken(vehicle.serviceCategory) != 'limousine') {
        errors.add(LimousineOfferError.vehicleNotLimousine);
      }
      final vehicleClass = limousineOfferToken(vehicle.serviceClassId);
      if (vehicleClass.isEmpty ||
          isForbiddenClassInferenceToken(vehicleClass)) {
        errors.add(LimousineOfferError.unknownServiceClass);
      }
    }
  } else if (targetType == LimousineOfferTarget.serviceClass) {
    if (!classIds.contains(limousineOfferToken(offer['service_class_id']))) {
      errors.add(LimousineOfferError.unknownServiceClass);
    }
  }

  final fixedRules = _listOf(offer['fixed_rules']);
  final hourly = _mapOf(offer['hourly']);
  final distanceTime = _mapOf(offer['distance_time']);
  final mobilisation = _mapOf(offer['mobilisation']);
  final paidExtras = _listOf(offer['paid_extras']);

  // Negative amounts anywhere fail closed.
  final amounts = <int?>[
    limousineCentsOf(offer['display_amount_cents']),
    ...fixedRules.map((r) => limousineCentsOf(r['amount_cents'])),
    limousineCentsOf(hourly['first_hour_cents']),
    limousineCentsOf(hourly['additional_hour_cents']),
    limousineCentsOf(hourly['package_amount_cents']),
    limousineCentsOf(hourly['excess_hour_cents']),
    limousineCentsOf(distanceTime['base_incl_vat_cents']),
    limousineCentsOf(distanceTime['per_km_incl_vat_cents']),
    limousineCentsOf(distanceTime['per_minute_incl_vat_cents']),
    limousineCentsOf(distanceTime['minimum_incl_vat_cents']),
    limousineCentsOf(mobilisation['fee_cents']),
    ...paidExtras.map((e) => limousineCentsOf(e['amount_cents'])),
  ];
  if (amounts.any((a) => a != null && a < 0)) {
    errors.add(LimousineOfferError.negativeAmount);
  }

  // One currency across every priced element.
  final currencies = <String>{
    if (currency.isNotEmpty) currency,
    for (final r in fixedRules)
      if (limousineCurrencyOf(r['currency']).isNotEmpty)
        limousineCurrencyOf(r['currency']),
    if (limousineCurrencyOf(hourly['currency']).isNotEmpty)
      limousineCurrencyOf(hourly['currency']),
    if (limousineCurrencyOf(distanceTime['currency']).isNotEmpty)
      limousineCurrencyOf(distanceTime['currency']),
    if (limousineCurrencyOf(mobilisation['currency']).isNotEmpty)
      limousineCurrencyOf(mobilisation['currency']),
    for (final e in paidExtras)
      if (limousineCurrencyOf(e['currency']).isNotEmpty)
        limousineCurrencyOf(e['currency']),
  };
  if (currencies.length > 1) errors.add(LimousineOfferError.currencyConflict);

  // exact_fixed must be able to resolve from complete data.
  if (presentation == LimousinePricePresentation.exactFixed) {
    final enabledRules = fixedRules
        .where((r) => _boolOf(r['enabled']))
        .toList(growable: false);
    final hourlyOn = _boolOf(hourly['enabled']);
    final dtOn = _boolOf(distanceTime['enabled']);
    if (enabledRules.isNotEmpty && !enabledRules.every(_fixedRuleComplete)) {
      errors.add(LimousineOfferError.incompleteFixedRule);
    }
    if (enabledRules.isEmpty && !hourlyOn && !dtOn) {
      errors.add(LimousineOfferError.incompleteFixedRule);
    }
  }

  // Marketing presentations need a display amount.
  if (presentation == LimousinePricePresentation.fromPrice ||
      presentation == LimousinePricePresentation.indicative) {
    final display = limousineCentsOf(offer['display_amount_cents']);
    if (display == null || display <= 0) {
      errors.add(LimousineOfferError.missingDisplayAmount);
    }
  }

  final ruleIds = fixedRules
      .map((r) => (r['rule_id'] ?? '').toString().trim())
      .where((id) => id.isNotEmpty)
      .toList(growable: false);
  if (ruleIds.toSet().length != ruleIds.length) {
    errors.add(LimousineOfferError.duplicateRule);
  }

  // Hourly hire. Package leftovers stay optional unless a package amount or
  // duration is actually being authored (half-filled package only).
  if (_boolOf(hourly['enabled'])) {
    errors.addAll(limousineHourlyHireValidation(hourly).errors);
    final packageAmount = limousineCentsOf(hourly['package_amount_cents']);
    final packageDuration = limousineMinutesOf(
      hourly['package_duration_minutes'],
    );
    final hasAmount = packageAmount != null;
    final hasDuration = packageDuration != null && packageDuration > 0;
    if (hasAmount != hasDuration) {
      errors.add(LimousineOfferError.packageIncomplete);
    }
  }

  if (!_distanceTimeComplete(distanceTime)) {
    errors.add(LimousineOfferError.distanceTimeIncomplete);
  }

  // Mobilisation.
  if (mobilisation.isNotEmpty) {
    final method = limousineOfferToken(mobilisation['method']);
    final charged =
        _boolOf(mobilisation['outbound_charged']) ||
        _boolOf(mobilisation['return_charged']);
    if (!LimousineMobilisationMethod.all.contains(method)) {
      errors.add(LimousineOfferError.mobilisationIncomplete);
    } else if (charged && method == LimousineMobilisationMethod.included) {
      errors.add(LimousineOfferError.mobilisationContradictory);
    } else if (charged && method == LimousineMobilisationMethod.fixedFee) {
      final fee = limousineCentsOf(mobilisation['fee_cents']);
      if (fee == null ||
          fee <= 0 ||
          limousineCurrencyOf(mobilisation['currency']).isEmpty) {
        errors.add(LimousineOfferError.mobilisationIncomplete);
      }
    } else if (charged && method == LimousineMobilisationMethod.distanceTime) {
      if (!_boolOf(distanceTime['enabled']) ||
          !_distanceTimeComplete(distanceTime)) {
        errors.add(LimousineOfferError.mobilisationIncomplete);
      }
    }
  }

  if (_boolOf(offer['published']) && !readiness) {
    errors.add(LimousineOfferError.publishedWithoutReadiness);
  }

  return LimousineOfferValidation(errors: errors.toList(growable: false));
}

/// An exact vehicle offer overrides a service-class offer when both match.
Map<String, dynamic>? selectLimousineOfferForRequest(
  List<Map<String, dynamic>> offers, {
  String vehicleId = '',
  String serviceClassId = '',
  String journeyType = '',
}) {
  final enabled = offers
      .where((o) => _boolOf(o['enabled']))
      .toList(growable: false);
  final wantedJourney = limousineOfferToken(journeyType);
  bool journeyOk(Map<String, dynamic> offer) {
    final types =
        (offer['journey_types'] as List?)
            ?.map(limousineOfferToken)
            .where(LimousineJourneyTypeId.all.contains)
            .toList(growable: false) ??
        const <String>[];
    if (wantedJourney.isEmpty) return true;
    if (!LimousineJourneyTypeId.all.contains(wantedJourney)) return false;
    // Explicit legacy rule: missing published scope uses the full catalog.
    if (types.isEmpty) return true;
    return types.contains(wantedJourney);
  }

  final wantedVehicle = vehicleId.trim();
  if (wantedVehicle.isNotEmpty) {
    for (final o in enabled) {
      if (limousineOfferToken(o['target_type']) ==
              LimousineOfferTarget.vehicle &&
          (o['vehicle_id'] ?? '').toString().trim() == wantedVehicle &&
          journeyOk(o)) {
        return o;
      }
    }
  }
  final wantedClass = limousineOfferToken(serviceClassId);
  if (wantedClass.isNotEmpty) {
    for (final o in enabled) {
      if (limousineOfferToken(o['target_type']) ==
              LimousineOfferTarget.serviceClass &&
          limousineOfferToken(o['service_class_id']) == wantedClass &&
          journeyOk(o)) {
        return o;
      }
    }
  }
  return null;
}

/// PRICING MODE vs PRESENTATION are independent axes.
///
/// `pricing mode` = HOW a total is computed (fixed journey, hourly/package,
/// limousine distance-time, manual). `price presentation` = WHAT the customer
/// is shown. An `exact_fixed` presentation may therefore be produced by an
/// hourly/package or distance/time calculation, not only by a fixed journey.
abstract final class LimousineOfferPricingMode {
  static const String fixed = 'fixed';
  static const String package = 'package';
  static const String distanceTime = 'distance_time';
  static const String manual = 'manual';

  static const List<String> all = <String>[
    fixed,
    package,
    distanceTime,
    manual,
  ];
}

List<String> limousineOfferSupportedPricingModes(Map<String, dynamic> offer) {
  final modes = <String>[];
  final fixedRules = _listOf(offer['fixed_rules']);
  if (fixedRules.any((r) => _boolOf(r['enabled']))) {
    modes.add(LimousineOfferPricingMode.fixed);
  }
  if (_boolOf(_mapOf(offer['hourly'])['enabled'])) {
    modes.add(LimousineOfferPricingMode.package);
  }
  if (_boolOf(_mapOf(offer['distance_time'])['enabled'])) {
    modes.add(LimousineOfferPricingMode.distanceTime);
  }
  if (modes.isEmpty) modes.add(LimousineOfferPricingMode.manual);
  return modes;
}

/// Fields that must never leave the authoritative vehicle record.
const List<String> kLimousinePrivateVehicleFields = <String>[
  'license_plate',
  'vin',
  'vehicle_registration_number',
  'exploitation_license_number',
  'assigned_driver',
  'driver_id',
  'notes',
  'base_address',
];

/// Customer-safe vehicle block resolved from the AUTHORITATIVE fleet record.
/// Returns null when the vehicle is missing, inactive or not an explicitly
/// classified limousine (fail closed). Plate, VIN, licences, driver data and
/// private notes are never emitted.
Map<String, dynamic>? buildSafePublicLimousineVehicle(VehicleProfile? vehicle) {
  if (vehicle == null) return null;
  if (!vehicle.isActive) return null;
  if (limousineOfferToken(vehicle.serviceCategory) != 'limousine') return null;
  final classId = limousineOfferToken(vehicle.serviceClassId);
  if (classId.isEmpty) return null;
  final photo = (vehicle.publicPhotoUrl ?? '').trim();
  final safePhoto = photo.toLowerCase().startsWith('https://') ? photo : '';
  return <String, dynamic>{
    'vehicle_id': vehicle.id.trim(),
    'service_class_id': classId,
    if (vehicle.passengerCapacity > 0)
      'passenger_capacity': vehicle.passengerCapacity,
    if (vehicle.luggageCapacity > 0)
      'luggage_capacity': vehicle.luggageCapacity,
    if (vehicle.color.trim().isNotEmpty) 'color': vehicle.color.trim(),
    if (safePhoto.isNotEmpty) 'photo_url': safePhoto,
  };
}

/// Only an "exact" presentation may become a resolved, bookable total — but it
/// may be produced by ANY pricing mode. `from_price` and `indicative` are
/// marketing and must never enter a snapshot.
bool limousineOfferCanResolvePrice(Map<String, dynamic> offer) =>
    limousineOfferToken(offer['price_presentation']) ==
    LimousinePricePresentation.exactFixed;

bool limousineOfferAmountIsSnapshotEligible(Map<String, dynamic> offer) =>
    limousineOfferCanResolvePrice(offer);

bool _limousineOfferMayPublishForDisplay(
  Map<String, dynamic> offer, {
  required List<VehicleProfile> vehicles,
  required List<String> knownClassIds,
  required bool readiness,
}) {
  final validation = validateLimousineOffer(
    offer,
    vehicles: vehicles,
    knownClassIds: knownClassIds,
    readiness: readiness,
  );
  final mode = limousineSimpleOfferModeOf(offer);
  if (mode != null) {
    return limousineValidateSimpleOffer(
      offer,
      mode: mode,
      vehicles: vehicles,
      knownClassIds: knownClassIds,
    ).isValid;
  }
  if (validation.valid) return true;
  const displayOnly = <String>{
    LimousineOfferError.incompleteFixedRule,
    LimousineOfferError.hourlyIncomplete,
    LimousineOfferError.hourlyMissingMinimumDuration,
    LimousineOfferError.packageIncomplete,
    LimousineOfferError.missingJourneyTypes,
  };
  if (validation.errors.any((code) => !displayOnly.contains(code))) {
    return false;
  }
  final display = limousineCentsOf(offer['display_amount_cents']);
  if (validation.errors.contains(LimousineOfferError.incompleteFixedRule) &&
      (display == null || display <= 0)) {
    return false;
  }
  final hourlyErrors = validation.errors
      .where(
        (code) =>
            code != LimousineOfferError.incompleteFixedRule &&
            code != LimousineOfferError.missingJourneyTypes,
      )
      .toList(growable: false);
  if (hourlyErrors.isEmpty) return true;
  final hourly = _mapOf(offer['hourly']);
  final packageAmount = limousineCentsOf(hourly['package_amount_cents']);
  final packageDuration = limousineMinutesOf(
    hourly['package_duration_minutes'],
  );
  return packageAmount != null &&
      packageAmount > 0 &&
      packageDuration != null &&
      packageDuration > 0;
}

/// Customer-safe projection. Never exposes the private operating-base address,
/// unpublished rules, internal costs or raw pricing records.
List<Map<String, dynamic>> buildSafePublicLimousineOffers(
  List<Map<String, dynamic>> offers, {
  bool eligible = false,
  List<VehicleProfile> vehicles = const <VehicleProfile>[],
  List<String> knownClassIds = const <String>[],
  bool readiness = false,
}) {
  if (!eligible) return const <Map<String, dynamic>>[];
  final out = <Map<String, dynamic>>[];
  for (final offer in offers) {
    if (!_boolOf(offer['enabled'])) continue;
    if (!_boolOf(offer['published'])) continue;
    if (!_limousineOfferMayPublishForDisplay(
      offer,
      vehicles: vehicles,
      knownClassIds: knownClassIds,
      readiness: readiness,
    )) {
      continue;
    }
    final presentation = limousineOfferToken(offer['price_presentation']);
    if (presentation == LimousinePricePresentation.unavailable) continue;

    // Authoritative vehicle join: an exact-vehicle offer publishes only when the
    // fleet record still resolves to an active, classified limousine.
    Map<String, dynamic>? safeVehicle;
    final boundIds = limousineNormalizeBoundVehicleIds(
      offer['vehicle_ids'] ?? offer['vehicleIds'],
      single: offer['vehicle_id'] ?? offer['vehicleId'],
    );
    final appliesToAll =
        offer.containsKey('applies_to_all_selected_vehicles') ||
            offer.containsKey('appliesToAllSelectedVehicles')
        ? _boolOf(
            offer['applies_to_all_selected_vehicles'] ??
                offer['appliesToAllSelectedVehicles'],
          )
        : boundIds.isEmpty;
    final publicVehicleIds = <String>[];
    if (!appliesToAll &&
        (boundIds.isNotEmpty ||
            limousineOfferToken(offer['target_type']) ==
                LimousineOfferTarget.vehicle)) {
      for (final vehicleId in boundIds) {
        VehicleProfile? record;
        for (final vehicle in vehicles) {
          if (vehicle.id == vehicleId) {
            record = vehicle;
            break;
          }
        }
        final safe = buildSafePublicLimousineVehicle(record);
        if (safe == null) continue;
        publicVehicleIds.add(safe['vehicle_id'].toString());
        safeVehicle ??= safe;
      }
      if (publicVehicleIds.isEmpty) continue;
    }

    final display = limousineCentsOf(offer['display_amount_cents']);
    final showsAmount =
        presentation != LimousinePricePresentation.quoteRequired &&
        display != null &&
        display > 0;

    final mobilisation = _mapOf(offer['mobilisation']);
    final charged =
        _boolOf(mobilisation['outbound_charged']) ||
        _boolOf(mobilisation['return_charged']);

    final hourly = _mapOf(offer['hourly']);
    out.add(<String, dynamic>{
      'offer_id': (offer['offer_id'] ?? '').toString(),
      'target_type': limousineOfferToken(offer['target_type']),
      'applies_to_all_selected_vehicles': appliesToAll,
      'featured': _boolOf(offer['featured']),
      'sort_order': limousinePublicSortOrderOf(
        offer['sort_order'] ?? offer['sortOrder'],
      ),
      if (publicVehicleIds.isNotEmpty) ...{
        'vehicle_ids': publicVehicleIds,
        'vehicle_id': publicVehicleIds.first,
      },
      if (safeVehicle != null) ...{
        'vehicle': safeVehicle,
        'vehicle_id': safeVehicle['vehicle_id'],
      },
      'service_class_id': safeVehicle != null
          ? safeVehicle['service_class_id']
          : limousineOfferToken(offer['service_class_id']),
      'title': limousineLocalizedOf(offer['title']),
      'description': limousineLocalizedOf(offer['description']),
      if (!_localizedIsEmpty(offer['important_information']))
        'important_information': limousineLocalizedOf(
          offer['important_information'],
        ),
      'pricing_modes': limousineOfferSupportedPricingModes(offer),
      'price_presentation': presentation,
      if (showsAmount) 'display_amount_cents': display,
      'currency': limousineCurrencyOf(offer['currency']),
      'journey_types':
          (offer['journey_types'] as List?)
              ?.map(limousineOfferToken)
              .where((t) => t.isNotEmpty)
              .toList(growable: false) ??
          const <String>[],
      if (_boolOf(hourly['enabled']))
        'hourly': <String, dynamic>{
          'first_hour_cents': hourly['first_hour_cents'],
          'additional_hour_cents': hourly['additional_hour_cents'],
          'minimum_duration_minutes': hourly['minimum_duration_minutes'],
          if (hourly['included_hours'] != null)
            'included_hours': hourly['included_hours'],
          if (hourly['package_duration_minutes'] != null)
            'package_duration_minutes': hourly['package_duration_minutes'],
          if (hourly['package_amount_cents'] != null)
            'package_amount_cents': hourly['package_amount_cents'],
        },
      'included_services': _listOf(offer['included_services'])
          .where((s) => _boolOf(s['active'], fallback: true))
          .where((s) => !_localizedIsEmpty(s['label']))
          .map(
            (s) => <String, dynamic>{
              'item_id': (s['item_id'] ?? '').toString(),
              'label': limousineLocalizedOf(s['label']),
            },
          )
          .toList(growable: false),
      'paid_extras': _listOf(offer['paid_extras'])
          .where((e) => _boolOf(e['active'], fallback: true))
          .where((e) => _boolOf(e['public'], fallback: true))
          .where((e) => !_localizedIsEmpty(e['label']))
          .map((e) {
            final quoteRequired = _boolOf(e['quote_required']);
            final amount = limousineCentsOf(e['amount_cents']);
            return <String, dynamic>{
              'extra_id': (e['extra_id'] ?? '').toString(),
              'label': limousineLocalizedOf(e['label']),
              'quote_required': quoteRequired,
              if (!quoteRequired && amount != null) 'amount_cents': amount,
              'currency': limousineCurrencyOf(e['currency']),
            };
          })
          .toList(growable: false),
      // Safe statement only — the private operating-base address is excluded.
      'mobilisation': <String, dynamic>{
        'included':
            !charged &&
            limousineOfferToken(mobilisation['method']) ==
                LimousineMobilisationMethod.included,
        'charged_separately': charged,
        'disclosure': limousineLocalizedOf(mobilisation['disclosure']),
      },
      'source_revision': _intOf(offer['source_revision']) ?? 0,
    });
  }
  if (out.length < 2) return out;
  final indexed = <({int index, Map<String, dynamic> offer})>[
    for (var i = 0; i < out.length; i++) (index: i, offer: out[i]),
  ];
  indexed.sort((a, b) {
    final orderA = limousinePublicSortOrderOf(
      a.offer['sort_order'] ?? a.offer['sortOrder'],
    );
    final orderB = limousinePublicSortOrderOf(
      b.offer['sort_order'] ?? b.offer['sortOrder'],
    );
    final explicitA = orderA != null;
    final explicitB = orderB != null;
    if (explicitA != explicitB) return explicitA ? -1 : 1;
    if (explicitA && explicitB && orderA != orderB) {
      return orderA.compareTo(orderB);
    }
    return a.index.compareTo(b.index);
  });
  return [for (final item in indexed) item.offer];
}

/// Monotonic guard: an older revision may never overwrite newer configuration.
bool limousineOffersRevisionAccepts({
  required int currentRevision,
  required int incomingRevision,
}) => incomingRevision > currentRevision;

// ---------------------------------------------------------------------------
// Localized labels (NL/EN/FR/ES)
// ---------------------------------------------------------------------------

const Map<String, LocalizedText> kLimousinePresentationLabels =
    <String, LocalizedText>{
      LimousinePricePresentation.exactFixed: LocalizedText(
        nl: 'Exacte boekbare prijs',
        en: 'Exact bookable price',
        fr: 'Prix exact réservable',
        es: 'Precio exacto reservable',
      ),
      LimousinePricePresentation.fromPrice: LocalizedText(
        nl: 'Vanafprijs',
        en: 'Price from',
        fr: 'Prix à partir de',
        es: 'Precio desde',
      ),
      LimousinePricePresentation.indicative: LocalizedText(
        nl: 'Indicatieve prijs',
        en: 'Indicative price',
        fr: 'Prix indicatif',
        es: 'Precio indicativo',
      ),
      LimousinePricePresentation.quoteRequired: LocalizedText(
        nl: 'Offerte op aanvraag',
        en: 'Quote required',
        fr: 'Devis requis',
        es: 'Presupuesto requerido',
      ),
      LimousinePricePresentation.unavailable: LocalizedText(
        nl: 'Niet beschikbaar',
        en: 'Unavailable',
        fr: 'Indisponible',
        es: 'No disponible',
      ),
    };

const Map<String, LocalizedText> kLimousineJourneyTypeLabels =
    <String, LocalizedText>{
      LimousineJourneyTypeId.pointToPoint: LocalizedText(
        nl: 'Van punt naar punt',
        en: 'Point to point',
        fr: 'Point à point',
        es: 'Punto a punto',
      ),
      LimousineJourneyTypeId.airportTransfer: LocalizedText(
        nl: 'Luchthaventransfer',
        en: 'Airport transfer',
        fr: 'Transfert aéroport',
        es: 'Traslado aeropuerto',
      ),
      LimousineJourneyTypeId.hotelTransfer: LocalizedText(
        nl: 'Hoteltransfer',
        en: 'Hotel transfer',
        fr: 'Transfert hôtel',
        es: 'Traslado hotel',
      ),
      LimousineJourneyTypeId.eventTransfer: LocalizedText(
        nl: 'Eventtransfer',
        en: 'Event transfer',
        fr: 'Transfert événement',
        es: 'Traslado evento',
      ),
      LimousineJourneyTypeId.hourlyPackage: LocalizedText(
        nl: 'Uurhuur / pakket',
        en: 'Hourly hire / package',
        fr: 'Location horaire / forfait',
        es: 'Alquiler por horas / paquete',
      ),
    };

const Map<String, LocalizedText> kLimousineMobilisationLabels =
    <String, LocalizedText>{
      LimousineMobilisationMethod.included: LocalizedText(
        nl: 'Voorrijden inbegrepen',
        en: 'Mobilisation included',
        fr: 'Acheminement inclus',
        es: 'Movilización incluida',
      ),
      LimousineMobilisationMethod.fixedFee: LocalizedText(
        nl: 'Vaste voorrijkost',
        en: 'Fixed mobilisation fee',
        fr: 'Frais d’acheminement fixes',
        es: 'Tarifa fija de movilización',
      ),
      LimousineMobilisationMethod.distanceTime: LocalizedText(
        nl: 'Voorrijden per afstand/tijd',
        en: 'Mobilisation by distance/time',
        fr: 'Acheminement selon distance/temps',
        es: 'Movilización por distancia/tiempo',
      ),
    };

const Map<String, LocalizedText>
kLimousineOfferErrorLabels = <String, LocalizedText>{
  LimousineOfferError.missingOfferId: LocalizedText(
    nl: 'Aanbod-ID ontbreekt.',
    en: 'Offer ID is missing.',
    fr: 'L’identifiant de l’offre est manquant.',
    es: 'Falta el ID de la oferta.',
  ),
  LimousineOfferError.unknownTarget: LocalizedText(
    nl: 'Kies een voertuig of een serviceklasse.',
    en: 'Choose a vehicle or a service class.',
    fr: 'Choisissez un véhicule ou une classe de service.',
    es: 'Elige un vehículo o una clase de servicio.',
  ),
  LimousineOfferError.unknownVehicle: LocalizedText(
    nl: 'Het gekozen voertuig bestaat niet.',
    en: 'The selected vehicle does not exist.',
    fr: 'Le véhicule sélectionné n’existe pas.',
    es: 'El vehículo seleccionado no existe.',
  ),
  LimousineOfferError.inactiveVehicle: LocalizedText(
    nl: 'Het gekozen voertuig is niet actief.',
    en: 'The selected vehicle is not active.',
    fr: 'Le véhicule sélectionné n’est pas actif.',
    es: 'El vehículo seleccionado no está activo.',
  ),
  LimousineOfferError.vehicleNotLimousine: LocalizedText(
    nl: 'Het voertuig is niet als limousine geconfigureerd.',
    en: 'The vehicle is not configured as a limousine.',
    fr: 'Le véhicule n’est pas configuré comme limousine.',
    es: 'El vehículo no está configurado como limusina.',
  ),
  LimousineOfferError.unknownServiceClass: LocalizedText(
    nl: 'Onbekende of inactieve limousineklasse.',
    en: 'Unknown or inactive limousine class.',
    fr: 'Classe de limousine inconnue ou inactive.',
    es: 'Clase de limusina desconocida o inactiva.',
  ),
  LimousineOfferError.missingCurrency: LocalizedText(
    nl: 'Valuta ontbreekt.',
    en: 'Currency is missing.',
    fr: 'La devise est manquante.',
    es: 'Falta la moneda.',
  ),
  LimousineOfferError.currencyConflict: LocalizedText(
    nl: 'Tegenstrijdige valuta in dit aanbod.',
    en: 'Conflicting currencies in this offer.',
    fr: 'Devises contradictoires dans cette offre.',
    es: 'Monedas contradictorias en esta oferta.',
  ),
  LimousineOfferError.negativeAmount: LocalizedText(
    nl: 'Bedragen mogen niet negatief zijn.',
    en: 'Amounts cannot be negative.',
    fr: 'Les montants ne peuvent pas être négatifs.',
    es: 'Los importes no pueden ser negativos.',
  ),
  LimousineOfferError.invalidPresentation: LocalizedText(
    nl: 'Kies hoe de prijs wordt getoond.',
    en: 'Choose how the price is presented.',
    fr: 'Choisissez la présentation du prix.',
    es: 'Elige cómo se muestra el precio.',
  ),
  LimousineOfferError.missingDisplayAmount: LocalizedText(
    nl: 'Een vanaf- of indicatieve prijs vereist een bedrag.',
    en: 'A from/indicative price requires an amount.',
    fr: 'Un prix à partir de/indicatif exige un montant.',
    es: 'Un precio desde/indicativo requiere un importe.',
  ),
  LimousineOfferError.incompleteFixedRule: LocalizedText(
    nl: 'Een exacte prijs vereist volledige tariefgegevens.',
    en: 'An exact price requires complete rule data.',
    fr: 'Un prix exact exige des données de règle complètes.',
    es: 'Un precio exacto requiere datos de regla completos.',
  ),
  LimousineOfferError.duplicateRule: LocalizedText(
    nl: 'Dubbele of dubbelzinnige tariefregels.',
    en: 'Duplicate or ambiguous rules.',
    fr: 'Règles en double ou ambiguës.',
    es: 'Reglas duplicadas o ambiguas.',
  ),
  LimousineOfferError.hourlyMissingMinimumDuration: LocalizedText(
    nl: 'Uurhuur vereist een minimumduur.',
    en: 'Hourly hire requires a minimum duration.',
    fr: 'La location horaire exige une durée minimale.',
    es: 'El alquiler por horas requiere una duración mínima.',
  ),
  LimousineOfferError.hourlyIncomplete: LocalizedText(
    nl: 'Vul het eerste uur en het bijkomende uur in.',
    en: 'Enter the first-hour and additional-hour price.',
    fr: 'Saisissez le prix de la première heure et des heures suivantes.',
    es: 'Introduce el precio de la primera hora y de las horas adicionales.',
  ),
  LimousineOfferError.packageIncomplete: LocalizedText(
    nl: 'Een pakket vereist zowel duur als bedrag.',
    en: 'A package requires both a duration and an amount.',
    fr: 'Un forfait exige une durée et un montant.',
    es: 'Un paquete requiere duración e importe.',
  ),
  LimousineOfferError.mobilisationIncomplete: LocalizedText(
    nl: 'Voorrijkosten zijn onvolledig geconfigureerd.',
    en: 'Mobilisation charging is incompletely configured.',
    fr: 'Les frais d’acheminement sont incomplets.',
    es: 'El cobro de movilización está incompleto.',
  ),
  LimousineOfferError.mobilisationContradictory: LocalizedText(
    nl: 'Voorrijden is inbegrepen én aangerekend.',
    en: 'Mobilisation is both included and charged.',
    fr: 'L’acheminement est à la fois inclus et facturé.',
    es: 'La movilización está incluida y cobrada a la vez.',
  ),
  LimousineOfferError.publishedWithoutReadiness: LocalizedText(
    nl: 'Publiceren kan niet: je limousinestatus is niet gereed.',
    en: 'Cannot publish: your limousine readiness is not met.',
    fr: 'Publication impossible : votre statut limousine n’est pas prêt.',
    es: 'No se puede publicar: tu estado de limusina no está listo.',
  ),
  LimousineOfferError.distanceTimeIncomplete: LocalizedText(
    nl: 'Afstand/tijd-tarief is onvolledig.',
    en: 'Distance/time pricing is incomplete.',
    fr: 'La tarification distance/temps est incomplète.',
    es: 'La tarificación distancia/tiempo está incompleta.',
  ),
  LimousineOfferError.missingJourneyTypes: LocalizedText(
    nl: 'Kies minstens één toepasselijk trajecttype.',
    en: 'Choose at least one applicable journey type.',
    fr: 'Choisissez au moins un type de trajet applicable.',
    es: 'Elija al menos un tipo de trayecto aplicable.',
  ),
};

String limousineOfferErrorLabel(String code, AppLanguage language) {
  final text = kLimousineOfferErrorLabels[code];
  if (text == null) return code;
  return text.of(language);
}

String limousinePresentationLabel(String code, AppLanguage language) =>
    kLimousinePresentationLabels[code]?.of(language) ?? code;

String limousineJourneyTypeLabel(String code, AppLanguage language) =>
    kLimousineJourneyTypeLabels[code]?.of(language) ?? code;

String limousineMobilisationLabel(String code, AppLanguage language) =>
    kLimousineMobilisationLabels[code]?.of(language) ?? code;
