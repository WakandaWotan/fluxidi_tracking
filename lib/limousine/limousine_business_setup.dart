// LIMOUSINE-MARKETPLACE-P2D4C1B — company setup contracts.
// Presentation and save orchestration only. Offers stay Map<String, dynamic>
// and validation stays in limousine_offers.dart. Vehicle classification stays
// VehicleProfile.serviceCategory / serviceClassId.

import 'package:flutter/foundation.dart';

import '../app_config.dart';
import '../app_strings.dart';
import 'limousine_offers.dart';
import 'limousine_p2d4c1a_ux.dart';

const Key kLimousineBusinessSetupPageKey = ValueKey<String>(
  'limousine_business_setup_page',
);
const Key kLimousineBusinessSetupOpenKey = ValueKey<String>(
  'limousine_business_setup_open',
);
const Key kLimousineBusinessSetupPhoneLayoutKey = ValueKey<String>(
  'limousine_business_setup_phone',
);
const Key kLimousineBusinessSetupTabletLayoutKey = ValueKey<String>(
  'limousine_business_setup_tablet',
);
const Key kLimousineBusinessSetupHeroKey = ValueKey<String>(
  'limousine_business_setup_hero',
);
const Key kLimousineBusinessSetupFooterKey = ValueKey<String>(
  'limousine_business_setup_footer',
);
const Key kLimousineBusinessSetupDraftSaveKey = ValueKey<String>(
  'limousine_business_setup_draft_save',
);
const Key kLimousineBusinessSetupPublishKey = ValueKey<String>(
  'limousine_business_setup_publish',
);
const Key kLimousineBusinessSetupTestBadgeKey = ValueKey<String>(
  'limousine_business_setup_test_badge',
);
const Key kLimousineBusinessSetupAdvancedKey = ValueKey<String>(
  'limousine_business_setup_advanced',
);
const Key kLimousineBusinessSetupPreviewKey = ValueKey<String>(
  'limousine_business_setup_preview',
);
const Key kLimousineBusinessSetupStatusKey = ValueKey<String>(
  'limousine_business_setup_status',
);
const Key kLimousineBusinessSetupErrorKey = ValueKey<String>(
  'limousine_business_setup_error',
);
const Key kLimousineBusinessSetupDirtyKey = ValueKey<String>(
  'limousine_business_setup_dirty',
);
const Key kLimousineBusinessSetupVehiclesKey = ValueKey<String>(
  'limousine_business_setup_vehicles',
);
const Key kLimousineBusinessSetupOffersKey = ValueKey<String>(
  'limousine_business_setup_offers',
);
const Key kLimousineBusinessSetupPublicKey = ValueKey<String>(
  'limousine_business_setup_public',
);
const Key kLimousineBusinessSetupReviewKey = ValueKey<String>(
  'limousine_business_setup_review',
);
const Key kLimousineBusinessSetupPublicTitleKey = ValueKey<String>(
  'limousine_business_setup_public_title',
);
const Key kLimousineBusinessSetupPublicDescriptionKey = ValueKey<String>(
  'limousine_business_setup_public_description',
);
const Key kLimousineBusinessSetupOtherLanguagesKey = ValueKey<String>(
  'limousine_business_setup_other_languages',
);
const Key kLimousineSimpleOfferEditorKey = ValueKey<String>(
  'limousine_simple_offer_editor',
);
const Key kLimousineSimpleOfferAmountKey = ValueKey<String>(
  'limousine_simple_offer_amount',
);
const Key kLimousineSimpleOfferEnabledKey = ValueKey<String>(
  'limousine_simple_offer_enabled',
);
const Key kLimousineSimpleOfferPublishedKey = ValueKey<String>(
  'limousine_simple_offer_published',
);
const Key kLimousineSimpleOfferNameKey = ValueKey<String>(
  'limousine_simple_offer_name',
);
const Key kLimousineSimpleOfferFirstHourKey = ValueKey<String>(
  'limousine_simple_offer_first_hour',
);

enum LimousineSimpleOfferMode { quote, fromPrice, fixed, hourly }

Key limousineBusinessSetupVehiclePhotoKey(String vehicleId) =>
    ValueKey<String>('limousine_business_setup_vehicle_photo_$vehicleId');

Key limousineBusinessSetupOtherLangTitleKey(String lang) =>
    ValueKey<String>('limousine_business_setup_other_title_$lang');

Key limousineBusinessSetupSectionKey(LimousineBusinessSetupSection section) =>
    ValueKey<String>('limousine_business_setup_section_${section.name}');

Key limousineBusinessSetupVehicleKey(String vehicleId) =>
    ValueKey<String>('limousine_business_setup_vehicle_$vehicleId');

Key limousineBusinessSetupOfferCardKey(String presentation) =>
    ValueKey<String>('limousine_business_setup_offer_$presentation');

Key limousineBusinessSetupPublicLangKey(String lang) =>
    ValueKey<String>('limousine_business_setup_public_lang_$lang');

Key limousineBusinessSetupPreviewTabKey(LimousineBusinessSetupPreviewTab tab) =>
    ValueKey<String>('limousine_business_setup_preview_${tab.name}');

Key limousineBusinessSetupChecklistKey(String code) =>
    ValueKey<String>('limousine_business_setup_check_$code');

enum LimousineBusinessSetupSection { vehicles, offers, publicText, review }

enum LimousineBusinessSetupPreviewTab { taxi, airport, limousine }

enum LimousineVehiclePublicService { taxi, airport, limousine }

class LimousineVehicleServiceFlags {
  const LimousineVehicleServiceFlags({
    required this.taxi,
    required this.airport,
    required this.limousine,
  });

  final bool taxi;
  final bool airport;
  final bool limousine;

  bool get isLimousineOnly => limousine && !taxi && !airport;
  bool get isTaxiOnly => taxi && !limousine;
}

/// Committed fleet contract: `serviceCategory == limousine` is the only
/// limousine signal. Empty category is taxi. Airport is not a vehicle field
/// in the committed schema, so it is never inferred from brand or name.
LimousineVehicleServiceFlags limousineVehicleServiceFlags(
  VehicleProfile vehicle,
) {
  final limousine = limousineOfferToken(vehicle.serviceCategory) == 'limousine';
  return LimousineVehicleServiceFlags(
    taxi: !limousine,
    airport: false,
    limousine: limousine,
  );
}

bool limousineVehicleAppearsInTaxiPreview(VehicleProfile vehicle) =>
    limousineVehicleServiceFlags(vehicle).taxi;

bool limousineVehicleAppearsInLimousinePreview(VehicleProfile vehicle) =>
    limousineVehicleServiceFlags(vehicle).limousine;

List<VehicleProfile> limousineSetupTaxiVehicles(
  Iterable<VehicleProfile> vehicles,
) {
  return vehicles.where(limousineVehicleAppearsInTaxiPreview).toList();
}

List<VehicleProfile> limousineSetupLimousineVehicles(
  Iterable<VehicleProfile> vehicles,
) {
  return vehicles.where(limousineVehicleAppearsInLimousinePreview).toList();
}

class LimousineBusinessSetupChecklistItem {
  const LimousineBusinessSetupChecklistItem({
    required this.code,
    required this.section,
    required this.complete,
  });

  final String code;
  final LimousineBusinessSetupSection section;
  final bool complete;
}

class LimousineBusinessSetupReadiness {
  const LimousineBusinessSetupReadiness({
    required this.items,
    required this.progress,
  });

  final List<LimousineBusinessSetupChecklistItem> items;
  final double progress;

  bool get canPublish => items.every((item) => item.complete);
}

bool limousinePublicTextIsComplete({
  required Map<String, String> title,
  required Map<String, String> description,
}) {
  bool filled(Map<String, String> values) {
    final nl = (values['nl'] ?? '').trim();
    return nl.isNotEmpty ||
        values.values.any((value) => value.trim().isNotEmpty);
  }

  return filled(title) && filled(description);
}

String limousineBusinessSetupPrimaryLangCode(AppLanguage language) {
  switch (language) {
    case AppLanguage.en:
      return 'en';
    case AppLanguage.fr:
      return 'fr';
    case AppLanguage.es:
      return 'es';
    case AppLanguage.nl:
    case AppLanguage.de:
      return 'nl';
  }
}

String limousineBusinessSetupTextFallback(
  Object? raw,
  AppLanguage language, {
  String? primaryLang,
}) {
  final direct = limousineLocalizedFor(raw, language).trim();
  if (direct.isNotEmpty) return direct;
  final map = limousineLocalizedOf(raw);
  final primary =
      map[primaryLang ?? limousineBusinessSetupPrimaryLangCode(language)] ?? '';
  if (primary.trim().isNotEmpty) return primary.trim();
  return map.values.firstWhere(
    (value) => value.trim().isNotEmpty,
    orElse: () => '',
  );
}

bool limousineOfferIsValidPublished(
  Map<String, dynamic> offer, {
  List<VehicleProfile> vehicles = const <VehicleProfile>[],
  List<String> knownClassIds = const <String>[],
}) {
  if (offer['enabled'] == false) return false;
  if (offer['published'] != true) return false;
  return validateLimousineOffer(
    offer,
    vehicles: vehicles,
    knownClassIds: knownClassIds,
    readiness: true,
  ).errors.isEmpty;
}

bool limousineOffersPricingSectionIsComplete({
  required bool sectionEnabled,
  required List<Map<String, dynamic>> offers,
  List<VehicleProfile> vehicles = const <VehicleProfile>[],
  List<String> knownClassIds = const <String>[],
}) {
  if (!sectionEnabled) return false;
  return offers.any(
    (offer) => limousineOfferIsValidPublished(
      offer,
      vehicles: vehicles,
      knownClassIds: knownClassIds,
    ),
  );
}

bool limousineVehicleHasSafePublicPhoto(VehicleProfile vehicle) {
  return vehicle.isActive &&
      limousineVehicleAppearsInLimousinePreview(vehicle) &&
      vehicle.primaryPhotoRef.trim().isNotEmpty;
}

LimousineBusinessSetupReadiness limousineBusinessSetupReadiness({
  required List<VehicleProfile> vehicles,
  required List<Map<String, dynamic>> offers,
  required Map<String, String> publicTitle,
  required Map<String, String> publicDescription,
  List<String> knownClassIds = const <String>[],
  bool entryEnabled = false,
  bool sectionEnabled = false,
}) {
  final limousineVehicles = limousineSetupLimousineVehicles(vehicles);
  final hasLimousineVehicle = limousineVehicles.any(
    (vehicle) => vehicle.isActive,
  );
  final hasUsableOffer = offers.any((offer) {
    if (offer['enabled'] == false) return false;
    return validateLimousineOffer(
      offer,
      vehicles: vehicles,
      knownClassIds: knownClassIds,
      readiness: true,
    ).errors.isEmpty;
  });
  final hasPublicText = limousinePublicTextIsComplete(
    title: publicTitle,
    description: publicDescription,
  );
  final hasPublicPhoto = limousineVehicles.any(
    limousineVehicleHasSafePublicPhoto,
  );
  final items = <LimousineBusinessSetupChecklistItem>[
    LimousineBusinessSetupChecklistItem(
      code: 'vehicles',
      section: LimousineBusinessSetupSection.vehicles,
      complete: hasLimousineVehicle,
    ),
    LimousineBusinessSetupChecklistItem(
      code: 'offers',
      section: LimousineBusinessSetupSection.offers,
      complete: hasUsableOffer,
    ),
    LimousineBusinessSetupChecklistItem(
      code: 'public_text',
      section: LimousineBusinessSetupSection.publicText,
      complete: hasPublicText,
    ),
    LimousineBusinessSetupChecklistItem(
      code: 'public_photo',
      section: LimousineBusinessSetupSection.vehicles,
      complete: hasPublicPhoto,
    ),
    LimousineBusinessSetupChecklistItem(
      code: 'live_status',
      section: LimousineBusinessSetupSection.review,
      complete: entryEnabled && sectionEnabled,
    ),
  ];
  final done = items.where((item) => item.complete).length;
  return LimousineBusinessSetupReadiness(
    items: items,
    progress: items.isEmpty ? 0 : done / items.length,
  );
}

bool limousineBusinessSetupDraftSaveAllowed({
  required bool dirty,
  required bool saving,
}) {
  return dirty && !saving;
}

bool limousineBusinessSetupPublishAllowed({
  required bool saving,
  required LimousineBusinessSetupReadiness readiness,
}) {
  return !saving && readiness.canPublish;
}

String? limousineBusinessSetupFieldSection(String errorCode) {
  switch (errorCode) {
    case LimousineOfferError.hourlyIncomplete:
    case LimousineOfferError.hourlyMissingMinimumDuration:
    case LimousineOfferError.packageIncomplete:
      return 'hourly';
    case LimousineOfferError.missingDisplayAmount:
    case LimousineOfferError.invalidPresentation:
    case LimousineOfferError.incompleteFixedRule:
      return 'offers';
    case LimousineOfferError.distanceTimeIncomplete:
    case LimousineOfferError.mobilisationIncomplete:
    case LimousineOfferError.mobilisationContradictory:
      return 'advanced';
    case LimousineOfferError.vehicleNotLimousine:
    case LimousineOfferError.unknownVehicle:
    case LimousineOfferError.inactiveVehicle:
    case LimousineOfferError.unknownServiceClass:
      return 'vehicles';
    default:
      return 'offers';
  }
}

List<String> limousineBusinessSetupOfferErrors(
  Map<String, dynamic> offer, {
  List<VehicleProfile> vehicles = const <VehicleProfile>[],
  List<String> knownClassIds = const <String>[],
  bool readiness = true,
}) {
  return validateLimousineOffer(
    offer,
    vehicles: vehicles,
    knownClassIds: knownClassIds,
    readiness: readiness,
  ).errors;
}

Map<String, dynamic> limousinePrepareDraftOffer(Map<String, dynamic> offer) {
  final copy = Map<String, dynamic>.from(offer);
  final errors = validateLimousineOffer(copy, readiness: true).errors;
  if (errors.isNotEmpty) {
    copy['published'] = false;
  }
  return copy;
}

List<Map<String, dynamic>> limousinePrepareDraftOffers(
  Iterable<Map<String, dynamic>> offers,
) {
  return offers.map(limousinePrepareDraftOffer).toList(growable: false);
}

List<Map<String, dynamic>> limousinePreparePublishOffers(
  Iterable<Map<String, dynamic>> offers, {
  List<VehicleProfile> vehicles = const <VehicleProfile>[],
  List<String> knownClassIds = const <String>[],
}) {
  return offers
      .map((offer) {
        final copy = Map<String, dynamic>.from(offer);
        final errors = validateLimousineOffer(
          copy,
          vehicles: vehicles,
          knownClassIds: knownClassIds,
          readiness: true,
        ).errors;
        copy['published'] = errors.isEmpty && copy['enabled'] != false;
        return copy;
      })
      .toList(growable: false);
}

bool limousineOfferIsSimpleCard(Map<String, dynamic> offer) {
  final presentation = limousineOfferToken(offer['price_presentation']);
  return presentation == LimousinePricePresentation.quoteRequired ||
      presentation == LimousinePricePresentation.fromPrice ||
      presentation == LimousinePricePresentation.exactFixed ||
      (_mapEnabled(offer['hourly']));
}

bool _mapEnabled(Object? raw) {
  if (raw is Map) return raw['enabled'] == true;
  return false;
}

class LimousineSimpleOfferDraft {
  const LimousineSimpleOfferDraft({
    required this.mode,
    required this.enabled,
    this.published = false,
    this.amountCents,
    this.currency = 'EUR',
    this.targetType = LimousineOfferTarget.serviceClass,
    this.vehicleId = '',
    this.serviceClassId = '',
    this.journeyTypes = const <String>[],
    this.primaryLang = 'nl',
    this.title = '',
    this.terms = '',
    this.pickupLabel = '',
    this.dropoffLabel = '',
    this.firstHourCents,
    this.additionalHourCents,
    this.minimumDurationMinutes,
    this.packageDurationMinutes,
    this.packageAmountCents,
    this.includedHours,
  });

  final LimousineSimpleOfferMode mode;
  final bool enabled;
  final bool published;
  final int? amountCents;
  final String currency;
  final String targetType;
  final String vehicleId;
  final String serviceClassId;
  final List<String> journeyTypes;
  final String primaryLang;
  final String title;
  final String terms;
  final String pickupLabel;
  final String dropoffLabel;
  final int? firstHourCents;
  final int? additionalHourCents;
  final int? minimumDurationMinutes;
  final int? packageDurationMinutes;
  final int? packageAmountCents;
  final int? includedHours;
}

String limousineSimpleOfferPresentation(LimousineSimpleOfferMode mode) {
  switch (mode) {
    case LimousineSimpleOfferMode.quote:
      return LimousinePricePresentation.quoteRequired;
    case LimousineSimpleOfferMode.fromPrice:
      return LimousinePricePresentation.fromPrice;
    case LimousineSimpleOfferMode.fixed:
      return LimousinePricePresentation.exactFixed;
    case LimousineSimpleOfferMode.hourly:
      return LimousinePricePresentation.fromPrice;
  }
}

Map<String, dynamic> limousineApplySimpleOfferEdits(
  Map<String, dynamic> offer,
  LimousineSimpleOfferDraft draft,
) {
  final next = Map<String, dynamic>.from(offer);
  final presentation = limousineSimpleOfferPresentation(draft.mode);
  next['enabled'] = draft.enabled;
  next['published'] = draft.published;
  next['price_presentation'] = presentation;
  next['currency'] = draft.currency;
  next['target_type'] = draft.targetType;
  next['vehicle_id'] = draft.targetType == LimousineOfferTarget.vehicle
      ? draft.vehicleId
      : '';
  next['service_class_id'] =
      draft.targetType == LimousineOfferTarget.serviceClass
      ? draft.serviceClassId
      : (next['service_class_id'] ?? '');
  next['journey_types'] = List<String>.from(draft.journeyTypes);
  if (draft.mode != LimousineSimpleOfferMode.quote) {
    next['display_amount_cents'] = draft.amountCents;
  }
  final title = limousineLocalizedOf(next['title']);
  final description = limousineLocalizedOf(next['description']);
  if (draft.title.trim().isNotEmpty) {
    title[draft.primaryLang] = draft.title.trim();
  }
  if (draft.terms.trim().isNotEmpty) {
    description[draft.primaryLang] = draft.terms.trim();
  }
  next['title'] = title;
  next['description'] = description;
  if (draft.pickupLabel.trim().isNotEmpty ||
      draft.dropoffLabel.trim().isNotEmpty) {
    next['pickup_label'] = draft.pickupLabel.trim();
    next['dropoff_label'] = draft.dropoffLabel.trim();
  }
  if (draft.mode == LimousineSimpleOfferMode.fixed &&
      draft.amountCents != null) {
    final rules = <Map<String, dynamic>>[
      ...((next['fixed_rules'] as List?) ?? const <dynamic>[])
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item)),
    ];
    if (rules.isEmpty) {
      rules.add(<String, dynamic>{
        'rule_id': 'rule_${next['offer_id'] ?? 'fixed'}',
        'enabled': true,
        'journey_type': draft.journeyTypes.isEmpty
            ? LimousineJourneyTypeId.pointToPoint
            : draft.journeyTypes.first,
        'zone_type': 'none',
        'currency': draft.currency,
      });
    }
    rules[0]['enabled'] = true;
    rules[0]['amount_cents'] = draft.amountCents;
    rules[0]['currency'] = draft.currency;
    if (draft.pickupLabel.trim().isNotEmpty) {
      rules[0]['pickup_label'] = draft.pickupLabel.trim();
    }
    if (draft.dropoffLabel.trim().isNotEmpty) {
      rules[0]['dropoff_label'] = draft.dropoffLabel.trim();
    }
    next['fixed_rules'] = rules;
  }
  final hourly = <String, dynamic>{
    ...((next['hourly'] is Map)
        ? Map<String, dynamic>.from(next['hourly'] as Map)
        : <String, dynamic>{}),
    'enabled': draft.mode == LimousineSimpleOfferMode.hourly,
    'currency': draft.currency,
  };
  if (draft.mode == LimousineSimpleOfferMode.hourly) {
    hourly['first_hour_cents'] = draft.firstHourCents;
    hourly['additional_hour_cents'] = draft.additionalHourCents;
    hourly['minimum_duration_minutes'] = draft.minimumDurationMinutes;
    hourly['package_duration_minutes'] =
        draft.packageDurationMinutes ??
        (draft.includedHours == null ? null : draft.includedHours! * 60);
    hourly['package_amount_cents'] = draft.packageAmountCents;
    if (draft.includedHours != null) {
      hourly['included_hours'] = draft.includedHours;
    }
    next['display_amount_cents'] = draft.firstHourCents ?? draft.amountCents;
  }
  next['hourly'] = hourly;
  return next;
}

Map<String, dynamic> limousineSimpleOfferDraft({
  required String presentation,
  required String currency,
  String serviceClassId = '',
  int? displayAmountCents,
  bool hourlyEnabled = false,
  Map<String, String>? title,
  Map<String, String>? description,
  int? nowMs,
}) {
  final id = 'offer_${nowMs ?? DateTime.now().millisecondsSinceEpoch}';
  return <String, dynamic>{
    'offer_id': id,
    'enabled': true,
    'published': false,
    'target_type': LimousineOfferTarget.serviceClass,
    'service_class_id': serviceClassId,
    'price_presentation': presentation,
    'currency': currency,
    'journey_types': <String>[],
    'title': <String, String>{
      'nl': title?['nl'] ?? '',
      'en': title?['en'] ?? '',
      'fr': title?['fr'] ?? '',
      'es': title?['es'] ?? '',
    },
    'description': <String, String>{
      'nl': description?['nl'] ?? '',
      'en': description?['en'] ?? '',
      'fr': description?['fr'] ?? '',
      'es': description?['es'] ?? '',
    },
    'display_amount_cents': displayAmountCents,
    'hourly': <String, dynamic>{'enabled': hourlyEnabled, 'currency': currency},
    'distance_time': <String, dynamic>{'enabled': false, 'currency': currency},
  };
}

List<Map<String, dynamic>> limousineSafeSetupPreviewOffers({
  required List<Map<String, dynamic>> offers,
  required List<VehicleProfile> vehicles,
  required List<String> knownClassIds,
  required bool sectionEnabled,
}) {
  return buildSafePublicLimousineOffers(
    offers,
    eligible: sectionEnabled,
    vehicles: vehicles,
    knownClassIds: knownClassIds,
    readiness: sectionEnabled,
  );
}

bool limousinePreviewContainsUnpublished(
  List<Map<String, dynamic>> preview,
  List<Map<String, dynamic>> source,
) {
  final publishedIds = source
      .where((offer) => offer['published'] == true && offer['enabled'] != false)
      .map((offer) => (offer['offer_id'] ?? '').toString())
      .where((id) => id.isNotEmpty)
      .toSet();
  for (final offer in preview) {
    final id = (offer['offer_id'] ?? '').toString();
    if (id.isNotEmpty && !publishedIds.contains(id)) return true;
  }
  return false;
}

String limousineBusinessSetupFriendlyStatus({
  required bool gatesOff,
  required AppLanguage language,
  String? raw,
}) {
  if (gatesOff || (raw != null && limousineLooksLikeRawException(raw))) {
    return kLimousineGatesOffFriendly.of(language);
  }
  return (raw ?? '').trim();
}

double limousineBusinessSetupContentWidth(double viewportWidth) {
  if (viewportWidth >= 700) {
    return viewportWidth < 880 ? viewportWidth : 880;
  }
  return viewportWidth;
}
