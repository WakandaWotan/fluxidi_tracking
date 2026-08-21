// Published offer journey-type scope for the existing limousine wizard.
// Working/draft edits never participate here; only the published snapshot does.

import 'limousine_offers.dart';

/// Explicit legacy rule: a published offer without `journey_types` uses the
/// full catalog. This is never used when an explicit published scope exists.
List<String> limousineLegacyUnscopedJourneyTypes() =>
    List<String>.from(LimousineJourneyTypeId.all);

List<String> limousineNormalizePublishedJourneyTypes(Object? raw) {
  if (raw is! Iterable) return const <String>[];
  final out = <String>[];
  final seen = <String>{};
  for (final item in raw) {
    final token = limousineOfferToken(item);
    if (!LimousineJourneyTypeId.all.contains(token)) continue;
    if (seen.add(token)) out.add(token);
  }
  return out;
}

bool limousineHasExplicitPublishedJourneyScope(Object? raw) =>
    limousineNormalizePublishedJourneyTypes(raw).isNotEmpty;

/// Customer-visible allowed types for one published offer.
/// Explicit published values win. Empty/missing uses the named legacy rule.
List<String> limousinePublishedJourneyScopeOf(Object? raw) {
  final explicit = limousineNormalizePublishedJourneyTypes(raw);
  if (explicit.isNotEmpty) return explicit;
  return limousineLegacyUnscopedJourneyTypes();
}

bool limousineJourneyTypeAllowedByPublishedScope({
  required Object? journeyTypes,
  required String journeyType,
}) {
  final wanted = limousineOfferToken(journeyType);
  if (wanted.isEmpty || !LimousineJourneyTypeId.all.contains(wanted)) {
    return false;
  }
  return limousinePublishedJourneyScopeOf(journeyTypes).contains(wanted);
}

String limousineResolveJourneyTypeInPublishedScope({
  required Object? journeyTypes,
  String current = '',
  bool preferHourlyPackage = false,
}) {
  final allowed = limousinePublishedJourneyScopeOf(journeyTypes);
  final wanted = limousineOfferToken(current);
  if (wanted.isNotEmpty && allowed.contains(wanted)) return wanted;
  if (preferHourlyPackage &&
      allowed.contains(LimousineJourneyTypeId.hourlyPackage)) {
    return LimousineJourneyTypeId.hourlyPackage;
  }
  return allowed.first;
}

/// Editors seed a concrete type when the working draft has none. Legacy
/// published snapshots without `journey_types` stay valid and use the named
/// catalog fallback on the customer side.
String limousineSeedDefaultJourneyType({bool hourlyOrPackage = false}) {
  if (hourlyOrPackage) return LimousineJourneyTypeId.hourlyPackage;
  return LimousineJourneyTypeId.pointToPoint;
}

Set<String> limousineSeedEditorJourneyTypes({
  required Object? current,
  bool hourlyOrPackage = false,
}) {
  final existing = limousineNormalizePublishedJourneyTypes(current);
  if (existing.isNotEmpty) return existing.toSet();
  return <String>{limousineSeedDefaultJourneyType(hourlyOrPackage: hourlyOrPackage)};
}

bool limousinePublishedJourneyScopeChanged({
  required Object? previousJourneyTypes,
  required Object? nextJourneyTypes,
  String previousOfferId = '',
  String nextOfferId = '',
  int previousSourceRevision = 0,
  int nextSourceRevision = 0,
}) {
  if (previousOfferId.trim().isNotEmpty &&
      nextOfferId.trim().isNotEmpty &&
      previousOfferId.trim() != nextOfferId.trim()) {
    return true;
  }
  if (previousSourceRevision > 0 &&
      nextSourceRevision > 0 &&
      previousSourceRevision != nextSourceRevision) {
    return true;
  }
  final previous = limousineNormalizePublishedJourneyTypes(previousJourneyTypes);
  final next = limousineNormalizePublishedJourneyTypes(nextJourneyTypes);
  if (previous.length != next.length) return true;
  return !previous.every(next.contains);
}
