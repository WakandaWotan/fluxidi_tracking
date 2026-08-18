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

LimousineBusinessSetupReadiness limousineBusinessSetupReadiness({
  required List<VehicleProfile> vehicles,
  required List<Map<String, dynamic>> offers,
  required Map<String, String> publicTitle,
  required Map<String, String> publicDescription,
  List<String> knownClassIds = const <String>[],
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
  bool readiness = false,
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
