// Per-vehicle commercial copy for the limousine catalog only.
// Authoritative key is the fleet vehicle id. This never writes taxi notes,
// VehicleProfile fields, or administrative vehicle-management notes.
//
// Schema v1 (additive, backward-compatible):
//   limousine_vehicle_public_copy: { "<vehicle_id>": {nl,en,fr,es,de} }
//   published_limousine_vehicle_public_copy: same shape, publish snapshot

import 'package:flutter/foundation.dart';

import '../app_strings.dart';
import 'limousine_quote_inbox.dart';
import 'limousine_service_capability.dart';

const int kLimousineVehiclePublicCopySchemaVersion = 1;
const int kLimousineVehiclePublicDescriptionMaxChars = 600;

const String kLimousineVehiclePublicCopyKey = 'limousine_vehicle_public_copy';
const String kLimousinePublishedVehiclePublicCopyKey =
    'published_limousine_vehicle_public_copy';
const String kLimousineVehiclePublicCopySchemaKey =
    'limousine_vehicle_public_copy_schema';

const List<String> kLimousinePublicCopyLanguages = <String>[
  'nl',
  'en',
  'fr',
  'es',
  'de',
];

const Key kLimousineDetailAboutSectionKey = ValueKey<String>(
  'limousine_vehicle_detail_about',
);
const Key kLimousineDetailAboutBodyKey = ValueKey<String>(
  'limousine_vehicle_detail_about_body',
);
const Key kLimousineVehiclePublicCopyDialogKey = ValueKey<String>(
  'limousine_vehicle_public_copy_dialog',
);
const Key kLimousineVehiclePublicCopyFieldKey = ValueKey<String>(
  'limousine_vehicle_public_copy_field',
);
const Key kLimousineVehiclePublicCopySaveKey = ValueKey<String>(
  'limousine_vehicle_public_copy_save',
);
const Key kLimousineVehiclePublicCopyCancelKey = ValueKey<String>(
  'limousine_vehicle_public_copy_cancel',
);
const Key kLimousineVehiclePublicCopyOtherLanguagesKey = ValueKey<String>(
  'limousine_vehicle_public_copy_other_languages',
);

Key limousineBusinessSetupEditPublicDetailsKey(String vehicleId) =>
    ValueKey<String>(
      'limousine_business_setup_edit_public_details_$vehicleId',
    );

Key limousineVehiclePublicCopyLangFieldKey(String lang) =>
    ValueKey<String>('limousine_vehicle_public_copy_lang_$lang');

Map<String, String> limousinePublicCopyLocalizedOf(Object? raw) {
  final src = raw is Map
      ? raw.map((key, value) => MapEntry(key.toString(), value))
      : const <String, dynamic>{};
  return <String, String>{
    for (final lang in kLimousinePublicCopyLanguages)
      lang: (src[lang] ?? '').toString().trim(),
  };
}

bool limousinePublicCopyHasText(Map<String, String> values) {
  return values.values.any((value) => value.trim().isNotEmpty);
}

Map<String, String> limousineClampPublicCopy(Map<String, String> values) {
  return <String, String>{
    for (final lang in kLimousinePublicCopyLanguages)
      lang: _clamp((values[lang] ?? '').trim()),
  };
}

String _clamp(String value) {
  if (value.length <= kLimousineVehiclePublicDescriptionMaxChars) return value;
  return value.substring(0, kLimousineVehiclePublicDescriptionMaxChars);
}

Map<String, Map<String, String>> limousineVehiclePublicCopyById(Object? raw) {
  if (raw is! Map) return <String, Map<String, String>>{};
  final out = <String, Map<String, String>>{};
  raw.forEach((key, value) {
    final id = key.toString().trim();
    if (id.isEmpty) return;
    final localized = limousineClampPublicCopy(
      limousinePublicCopyLocalizedOf(value),
    );
    if (!limousinePublicCopyHasText(localized)) return;
    out[id] = localized;
  });
  return out;
}

Map<String, dynamic> limousineEncodeVehiclePublicCopy(
  Map<String, Map<String, String>> copy,
) {
  final out = <String, dynamic>{};
  copy.forEach((id, localized) {
    final clamped = limousineClampPublicCopy(localized);
    if (!limousinePublicCopyHasText(clamped)) return;
    out[id] = clamped;
  });
  return out;
}

Map<String, Map<String, String>> limousineCloneVehiclePublicCopy(
  Map<String, Map<String, String>> copy,
) {
  return <String, Map<String, String>>{
    for (final entry in copy.entries)
      entry.key: Map<String, String>.from(entry.value),
  };
}

/// Working-copy vs published per-vehicle catalog copy.
/// Draft save keeps [published] unchanged so live vehicle pages do not pick
/// up unpublished descriptions.
Map<String, dynamic> limousineVehiclePublicCopyPayload({
  required bool publish,
  required Map<String, Map<String, String>> working,
  required Map<String, Map<String, String>> published,
}) {
  return <String, dynamic>{
    kLimousineVehiclePublicCopySchemaKey: kLimousineVehiclePublicCopySchemaVersion,
    kLimousineVehiclePublicCopyKey: limousineEncodeVehiclePublicCopy(working),
    kLimousinePublishedVehiclePublicCopyKey: limousineEncodeVehiclePublicCopy(
      publish ? working : published,
    ),
  };
}

Map<String, Map<String, String>> limousinePublishedVehiclePublicCopyOf(
  Map<String, dynamic> profile,
) {
  final nested = asStringKeyedMap(profile['limousine'] ?? profile['pricing']);
  final source = nested.isEmpty
      ? profile
      : <String, dynamic>{...profile, ...nested};
  final hasPublished =
      source.containsKey(kLimousinePublishedVehiclePublicCopyKey) ||
      source.containsKey('publishedLimousineVehiclePublicCopy');
  final published = limousineVehiclePublicCopyById(
    source[kLimousinePublishedVehiclePublicCopyKey] ??
        source['publishedLimousineVehiclePublicCopy'],
  );
  if (published.isNotEmpty || hasPublished) return published;
  return limousineVehiclePublicCopyById(
    source[kLimousineVehiclePublicCopyKey] ??
        source['limousineVehiclePublicCopy'],
  );
}

Map<String, String> limousineVehiclePublicDescriptionMap({
  required Map<String, dynamic> vehicle,
  required Map<String, Map<String, String>> catalog,
  required String vehicleId,
}) {
  final fromCatalog = catalog[vehicleId.trim()];
  if (fromCatalog != null && limousinePublicCopyHasText(fromCatalog)) {
    return fromCatalog;
  }
  return limousinePublicCopyLocalizedOf(
    vehicle['public_description'] ??
        vehicle['publicDescription'] ??
        vehicle['limousine_public_description'] ??
        vehicle['limousinePublicDescription'],
  );
}

String limousineResolvePublicCopyText(
  Map<String, String> localized,
  AppLanguage language,
) {
  return localizedLimousineText(localized, languageCode: language.name);
}

bool limousinePublicCopyTouchesPrivateVehicleFields(
  Map<String, dynamic> payload,
) {
  return payload.containsKey('notes') ||
      payload.containsKey('internal_notes') ||
      payload.containsKey('license_plate') ||
      payload.containsKey('vin');
}
