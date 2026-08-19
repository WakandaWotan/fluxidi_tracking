// Shared public-copy helpers for limousine cards and vehicle detail.
// Rendering only: never rewrite stored company or offer payloads.

import '../app_strings.dart';
import 'limousine_provider_showroom_labels.dart';

bool limousinePublicLabelsMatch(String left, String right) {
  return left.trim().toLowerCase() == right.trim().toLowerCase();
}

bool limousineShouldShowOfferKindEyebrow(String kindLabel, String priceLabel) {
  if (kindLabel.trim().isEmpty) return false;
  return !limousinePublicLabelsMatch(kindLabel, priceLabel);
}

List<String> limousineMeaningfulComfortFeatures(
  Iterable<String> features, {
  AppLanguage? language,
}) {
  final titles =
      <String>{
            kLimousineShowroomComfort.nl,
            kLimousineShowroomComfort.en,
            kLimousineShowroomComfort.fr,
            kLimousineShowroomComfort.es,
            if (kLimousineShowroomComfort.de != null)
              kLimousineShowroomComfort.de!,
            if (language != null) kLimousineShowroomComfort.of(language),
          }
          .map((value) => value.trim().toLowerCase())
          .where((value) => value.isNotEmpty);
  final blocked = titles.toSet();
  return [
    for (final feature in features)
      if (feature.trim().isNotEmpty &&
          !blocked.contains(feature.trim().toLowerCase()))
        feature.trim(),
  ];
}

String limousineMeaningfulComfortBody(
  Iterable<String> features, {
  AppLanguage? language,
}) {
  return limousineMeaningfulComfortFeatures(
    features,
    language: language,
  ).join(' · ');
}
