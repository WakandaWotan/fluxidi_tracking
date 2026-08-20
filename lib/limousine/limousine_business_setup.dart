// LIMOUSINE-MARKETPLACE-P2D4C1B — company setup contracts.
// Presentation and save orchestration only. Offers stay Map<String, dynamic>
// and validation stays in limousine_offers.dart. Vehicle classification stays
// VehicleProfile.serviceCategory / serviceClassId.

import 'package:flutter/foundation.dart';

import '../app_config.dart';
import '../app_strings.dart';
import 'limousine_hero_contract.dart';
import 'limousine_offer_binding.dart';
import 'limousine_profile_identity.dart';
import 'limousine_offers.dart';
import 'limousine_p2d4c1a_ux.dart';

export 'limousine_offers.dart' show LimousineSimpleOfferMode;

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
const Key kLimousineBusinessSetupPreviewFleetKey = ValueKey<String>(
  'limousine_business_setup_preview_fleet',
);
const Key kLimousineBusinessSetupPreviewPriceKey = ValueKey<String>(
  'limousine_business_setup_preview_price',
);
const Key kLimousineBusinessSetupLeaveDialogKey = ValueKey<String>(
  'limousine_business_setup_leave_dialog',
);
const Key kLimousineBusinessSetupLeaveSaveKey = ValueKey<String>(
  'limousine_business_setup_leave_save',
);
const Key kLimousineBusinessSetupLeaveDiscardKey = ValueKey<String>(
  'limousine_business_setup_leave_discard',
);
const Key kLimousineBusinessSetupLeaveCancelKey = ValueKey<String>(
  'limousine_business_setup_leave_cancel',
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
const Key kLimousineSimpleOfferExtraHourKey = ValueKey<String>(
  'limousine_simple_offer_extra_hour',
);
const Key kLimousineSimpleOfferMinDurationKey = ValueKey<String>(
  'limousine_simple_offer_min_duration',
);
const double kLimousineBusinessSetupOfferValidityDotSize = 12;
const double kLimousineBusinessSetupStickyFooterReserve = 96;

const Key kLimousineBusinessSetupCoverPickGalleryKey = ValueKey<String>(
  'limousine_business_setup_cover_pick_gallery',
);
const Key kLimousineBusinessSetupCoverUploadHelpKey = ValueKey<String>(
  'limousine_business_setup_cover_upload_help',
);
const Key kLimousineBusinessSetupCoverGalleryHelpKey = ValueKey<String>(
  'limousine_business_setup_cover_gallery_help',
);
const Key kLimousineBusinessSetupLogoStatusKey = ValueKey<String>(
  'limousine_business_setup_logo_status',
);
const Key kLimousineBusinessSetupLogoActionsKey = ValueKey<String>(
  'limousine_business_setup_logo_actions',
);
const Key kLimousineBusinessSetupMediaStatusKey = ValueKey<String>(
  'limousine_business_setup_media_status',
);
const Key kLimousineBusinessSetupMediaErrorKey = ValueKey<String>(
  'limousine_business_setup_media_error',
);

const Key kLimousineBusinessSetupCoverKey = ValueKey<String>(
  'limousine_business_setup_cover',
);
const Key kLimousineBusinessSetupCoverFallbackKey = ValueKey<String>(
  'limousine_business_setup_cover_fallback',
);
const Key kLimousineBusinessSetupCoverUploadKey = ValueKey<String>(
  'limousine_business_setup_cover_upload',
);
const Key kLimousineBusinessSetupCoverPreviewKey = ValueKey<String>(
  'limousine_business_setup_cover_preview',
);
const Key kLimousineBusinessSetupCoverUploadingKey = ValueKey<String>(
  'limousine_business_setup_cover_uploading',
);
const Key kLimousineBusinessSetupCoverGalleryDialogKey = ValueKey<String>(
  'limousine_business_setup_cover_gallery_dialog',
);
const Key kLimousineBusinessSetupCoverGalleryCancelKey = ValueKey<String>(
  'limousine_business_setup_cover_gallery_cancel',
);
const Key kLimousineBusinessSetupCoverGalleryUseKey = ValueKey<String>(
  'limousine_business_setup_cover_gallery_use',
);

Key limousineBusinessSetupCoverFocusKey(String alignment) => ValueKey<String>(
  'limousine_business_setup_cover_focus_$alignment',
);

Key limousineBusinessSetupCoverGalleryItemKey(String mediaId) =>
    ValueKey<String>('limousine_business_setup_cover_gallery_item_$mediaId');
const Key kLimousineBusinessSetupLogoKey = ValueKey<String>(
  'limousine_business_setup_logo',
);
const Key kLimousineBusinessSetupLogoPickKey = ValueKey<String>(
  'limousine_business_setup_logo_pick',
);
const Key kLimousineBusinessSetupLogoReplaceKey = ValueKey<String>(
  'limousine_business_setup_logo_replace',
);
const Key kLimousineBusinessSetupLogoClearKey = ValueKey<String>(
  'limousine_business_setup_logo_clear',
);
const Key kLimousineBusinessSetupLogoPreviewKey = ValueKey<String>(
  'limousine_business_setup_logo_preview',
);
const Key kLimousineBusinessSetupLogoUploadingKey = ValueKey<String>(
  'limousine_business_setup_logo_uploading',
);
const Key kLimousineBusinessSetupLogoMediaStatusKey = ValueKey<String>(
  'limousine_business_setup_logo_media_status',
);
const Key kLimousineBusinessSetupLogoMediaErrorKey = ValueKey<String>(
  'limousine_business_setup_logo_media_error',
);
const Key kLimousineSimpleOfferScopeAllKey = ValueKey<String>(
  'limousine_simple_offer_scope_all',
);
const Key kLimousineSimpleOfferFeaturedKey = ValueKey<String>(
  'limousine_simple_offer_featured',
);
const Key kLimousineSimpleOfferVehiclePickerKey = ValueKey<String>(
  'limousine_simple_offer_vehicle_picker',
);
const Key kLimousineSimpleOfferMissingVehicleKey = ValueKey<String>(
  'limousine_simple_offer_missing_vehicle',
);

Key limousineSimpleOfferVehicleTileKey(String vehicleId) =>
    ValueKey<String>('limousine_simple_offer_vehicle_$vehicleId');

Key limousineBusinessSetupVehiclePhotoKey(String vehicleId) =>
    ValueKey<String>('limousine_business_setup_vehicle_photo_$vehicleId');

Key limousineBusinessSetupOtherLangTitleKey(String lang) =>
    ValueKey<String>('limousine_business_setup_other_title_$lang');

Key limousineBusinessSetupSectionKey(LimousineBusinessSetupSection section) =>
    ValueKey<String>('limousine_business_setup_section_${section.name}');

Key limousineBusinessSetupVehicleKey(String vehicleId) =>
    ValueKey<String>('limousine_business_setup_vehicle_$vehicleId');

Key limousineBusinessSetupManagePhotosKey(String vehicleId) =>
    ValueKey<String>('limousine_business_setup_manage_photos_$vehicleId');

Key limousineBusinessSetupOfferCardKey(String presentation) =>
    ValueKey<String>('limousine_business_setup_offer_$presentation');

Key limousineBusinessSetupOfferValidityKey(
  String presentation, {
  required bool valid,
}) => ValueKey<String>(
  'limousine_business_setup_offer_validity_${presentation}_${valid ? 'valid' : 'incomplete'}',
);

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

  /// Publish may run on a valid unpublished offer. 100% / Compleet waits for
  /// a published offer via [live_status].
  bool get canPublish => items
      .where((item) => item.code != 'live_status')
      .every((item) => item.complete);

  bool get isFullyComplete => items.every((item) => item.complete);
}

/// Working-copy vs published visiting-card fields for step 3.
/// Draft save keeps [published*] unchanged so the live marketplace card
/// does not pick up unpublished title/photo/description.
Map<String, dynamic> limousinePublicDisplayPayload({
  required bool publish,
  required Map<String, String> title,
  required Map<String, String> description,
  required Map<String, dynamic> hero,
  required Map<String, String> publishedTitle,
  required Map<String, String> publishedDescription,
  required Map<String, dynamic> publishedHero,
  Map<String, dynamic> logo = const <String, dynamic>{},
  Map<String, dynamic> publishedLogo = const <String, dynamic>{},
  Iterable<String> taxiHeroUrls = const <String>[],
}) {
  final safeHero = limousineSanitizeProfileCoverMap(
    hero,
    taxiHeroUrls: taxiHeroUrls,
  );
  final safePublished = limousineSanitizeProfileCoverMap(
    publishedHero,
    taxiHeroUrls: taxiHeroUrls,
  );
  final safeLogo = limousineSanitizeProfileLogoMap(logo);
  final safePublishedLogo = limousineSanitizeProfileLogoMap(publishedLogo);
  final snapshot = publish ? safeHero : safePublished;
  final logoSnapshot = publish ? safeLogo : safePublishedLogo;
  final publishedTitleSnapshot = publish ? title : publishedTitle;
  final publishedDescriptionSnapshot = publish
      ? description
      : publishedDescription;
  final publishedCard = <String, dynamic>{
    'public_title': publishedTitleSnapshot,
    'public_description': publishedDescriptionSnapshot,
    'cover': snapshot,
    'logo': logoSnapshot,
  };
  final workingCard = <String, dynamic>{
    'public_title': title,
    'public_description': description,
    'cover': safeHero,
    'logo': safeLogo,
  };
  return <String, dynamic>{
    'public_title': title,
    'public_description': description,
    kLimousineProfileCoverKey: safeHero,
    'limousine_hero': safeHero,
    kLimousineProfileLogoKey: safeLogo,
    'limousine_logo': safeLogo,
    kLimousineVisitingCardKey: workingCard,
    'published_public_title': publishedTitleSnapshot,
    'published_public_description': publishedDescriptionSnapshot,
    kLimousinePublishedProfileCoverKey: snapshot,
    'published_limousine_hero': snapshot,
    kLimousinePublishedProfileLogoKey: logoSnapshot,
    'published_limousine_logo': logoSnapshot,
    kLimousinePublishedVisitingCardKey: publishedCard,
    kLimousineProfileCoverSchemaKey: kLimousineProfileCoverSchemaVersion,
    kLimousineProfileLogoSchemaKey: kLimousineProfileLogoSchemaVersion,
  };
}

bool limousineLocalizedMapHasText(Map<String, String> values) {
  return values.values.any((value) => value.trim().isNotEmpty);
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
  return limousineBusinessSetupOfferErrors(
    offer,
    vehicles: vehicles,
    knownClassIds: knownClassIds,
  ).isEmpty;
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
  final hasValidOffer = offers.any((offer) {
    if (offer['enabled'] == false) return false;
    return limousineBusinessSetupOfferErrors(
      offer,
      vehicles: vehicles,
      knownClassIds: knownClassIds,
    ).isEmpty;
  });
  final hasPublishedOffer = offers.any(
    (offer) => limousineOfferIsValidPublished(
      offer,
      vehicles: vehicles,
      knownClassIds: knownClassIds,
    ),
  );
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
      complete: hasValidOffer,
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
      complete:
          sectionEnabled &&
          hasLimousineVehicle &&
          hasPublishedOffer &&
          hasPublicText &&
          hasPublicPhoto,
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
  LimousineSimpleOfferMode? mode,
  List<VehicleProfile> vehicles = const <VehicleProfile>[],
  List<String> knownClassIds = const <String>[],
  bool readiness = true,
}) {
  final resolved = mode ?? limousineSimpleOfferModeOf(offer);
  if (resolved != null) {
    return limousineValidateSimpleOffer(
      offer,
      mode: resolved,
      vehicles: vehicles,
      knownClassIds: knownClassIds,
    ).errors;
  }
  return validateLimousineOffer(
    offer,
    vehicles: vehicles,
    knownClassIds: knownClassIds,
    readiness: readiness,
  ).errors;
}

LimousineSimpleOfferValidation limousineBusinessSetupOfferValidation(
  Map<String, dynamic>? offer, {
  required LimousineSimpleOfferMode mode,
  List<VehicleProfile> vehicles = const <VehicleProfile>[],
  List<String> knownClassIds = const <String>[],
}) {
  return limousineValidateSimpleOffer(
    offer,
    mode: mode,
    vehicles: vehicles,
    knownClassIds: knownClassIds,
  );
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
        final errors = limousineBusinessSetupOfferErrors(
          copy,
          vehicles: vehicles,
          knownClassIds: knownClassIds,
          readiness: true,
        );
        copy['published'] = errors.isEmpty && copy['enabled'] != false;
        return limousineStampOfferLineage(copy);
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
    this.appliesToAllSelected = true,
    this.vehicleIds = const <String>[],
    this.featured = false,
    this.sortOrder = 0,
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
  final bool appliesToAllSelected;
  final List<String> vehicleIds;
  final bool featured;
  final int sortOrder;
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
    case LimousineSimpleOfferMode.package:
      return LimousinePricePresentation.exactFixed;
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
  final scoped = limousineWriteOfferScope(
    next,
    appliesToAllSelected: draft.appliesToAllSelected,
    vehicleIds: draft.appliesToAllSelected
        ? const <String>[]
        : List<String>.from(draft.vehicleIds),
    featured: draft.featured,
    sortOrder: draft.sortOrder,
  );
  next.addAll(scoped);
  if (draft.appliesToAllSelected && draft.serviceClassId.isNotEmpty) {
    next['service_class_id'] = draft.serviceClassId;
  } else if (!draft.appliesToAllSelected) {
    next['service_class_id'] = next['service_class_id'] ?? draft.serviceClassId;
  }
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
    'enabled':
        draft.mode == LimousineSimpleOfferMode.hourly ||
        draft.mode == LimousineSimpleOfferMode.package,
    'currency': draft.currency,
  };
  if (draft.mode == LimousineSimpleOfferMode.hourly) {
    hourly['first_hour_cents'] = draft.firstHourCents;
    hourly['additional_hour_cents'] = draft.additionalHourCents;
    hourly['minimum_duration_minutes'] = draft.minimumDurationMinutes;
    next['display_amount_cents'] = draft.firstHourCents ?? draft.amountCents;
  } else if (draft.mode == LimousineSimpleOfferMode.package) {
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
    next['display_amount_cents'] =
        draft.packageAmountCents ?? draft.amountCents;
    if (draft.packageAmountCents == null || draft.packageAmountCents! <= 0) {
      next['price_presentation'] = LimousinePricePresentation.quoteRequired;
    }
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

bool limousinePricingSaveIsStaleConflict(Object error) {
  final text = error.toString().toLowerCase();
  return text.contains('stale_source_revision') ||
      (text.contains('409') && text.contains('stale'));
}

bool limousinePricingPublishConfirmedVisible(Map<String, dynamic> data) {
  if (data['visibility_ok'] == true) return true;
  final projected =
      int.tryParse('${data['public_projected_offer_count'] ?? ''}') ?? 0;
  return data['discovery_listable'] == true && projected > 0;
}

int limousinePricingResponseRevision(
  Map<String, dynamic> data, {
  int fallback = 0,
}) {
  final section = data['limousine'] is Map
      ? Map<String, dynamic>.from(data['limousine'] as Map)
      : const <String, dynamic>{};
  return int.tryParse('${data['source_revision'] ?? ''}') ??
      int.tryParse('${section['source_revision'] ?? ''}') ??
      fallback;
}

String limousineBusinessSetupFriendlyStatus({
  required bool gatesOff,
  required AppLanguage language,
  String? raw,
}) {
  if (gatesOff || (raw != null && limousineLooksLikeRawException(raw))) {
    return kLimousineBusinessSetupTransactionsOff.of(language);
  }
  return (raw ?? '').trim();
}

double limousineBusinessSetupContentWidth(double viewportWidth) {
  if (viewportWidth >= 700) {
    return viewportWidth < 880 ? viewportWidth : 880;
  }
  return viewportWidth;
}
