import 'limousine_service_capability.dart';

/// Durable public-service selection for the partner profile toggle.
class PublicServiceSelection {
  const PublicServiceSelection({
    required this.ids,
    required this.configured,
    this.sourceRevision = 0,
  });

  final List<String> ids;
  final bool configured;
  final int sourceRevision;

  bool get limousineEnabled =>
      ids.map(normalizePublicServiceToken).contains(kLimousinePublicServiceId);

  PublicServiceSelection copyWith({
    List<String>? ids,
    bool? configured,
    int? sourceRevision,
  }) {
    return PublicServiceSelection(
      ids: ids ?? this.ids,
      configured: configured ?? this.configured,
      sourceRevision: sourceRevision ?? this.sourceRevision,
    );
  }
}

final Set<String> kPublicServiceCatalog = <String>{
  'taxi_vvb',
  'airport_transfer',
  'business_rides',
  'event_mobility',
  'hotel_bnb_pickup',
  'online_payments',
  kLimousinePublicServiceId,
};

List<String> sanitizePublicServiceIds(Iterable<String> values) {
  final out = <String>[];
  final seen = <String>{};
  for (final raw in values) {
    final token = normalizePublicServiceToken(raw);
    if (token.isEmpty || !kPublicServiceCatalog.contains(token)) continue;
    if (!seen.add(token)) continue;
    out.add(token);
  }
  return List<String>.unmodifiable(out);
}

/// Publish payload: a checked Limousine chip must survive even when the
/// configured flag was lost. Legacy calculator mapping never invents limousine.
List<String> mappedPublicServiceIdsForPublish({
  required bool configured,
  required Iterable<String> selected,
  required Iterable<String> legacyFallback,
}) {
  final explicit = sanitizePublicServiceIds(selected);
  if (configured || explicit.contains(kLimousinePublicServiceId)) {
    return explicit;
  }
  return sanitizePublicServiceIds(legacyFallback);
}

/// Server empty/unconfigured must not wipe a local explicit selection.
PublicServiceSelection mergePublicServiceSelection({
  required PublicServiceSelection local,
  required PublicServiceSelection server,
  bool serverFieldPresent = true,
}) {
  if (isStalePublicServiceRevision(
    existingRevision: local.sourceRevision,
    incomingRevision: server.sourceRevision,
  )) {
    return local;
  }
  final serverIds = sanitizePublicServiceIds(server.ids);
  final localIds = sanitizePublicServiceIds(local.ids);
  if (server.configured) {
    return PublicServiceSelection(
      ids: serverIds,
      configured: true,
      sourceRevision: server.sourceRevision > 0
          ? server.sourceRevision
          : local.sourceRevision,
    );
  }
  if (!serverFieldPresent || serverIds.isEmpty) {
    if (local.configured || localIds.contains(kLimousinePublicServiceId)) {
      return PublicServiceSelection(
        ids: localIds,
        configured: true,
        sourceRevision: local.sourceRevision,
      );
    }
  }
  if (serverIds.isNotEmpty) {
    return PublicServiceSelection(
      ids: serverIds,
      configured: server.configured || local.configured,
      sourceRevision: server.sourceRevision,
    );
  }
  return PublicServiceSelection(
    ids: localIds,
    configured: local.configured,
    sourceRevision: local.sourceRevision,
  );
}

bool isStalePublicServiceRevision({
  required int existingRevision,
  required int incomingRevision,
}) {
  if (existingRevision <= 0 || incomingRevision <= 0) return false;
  return incomingRevision < existingRevision;
}

PublicServiceSelection applyPublishedPartnerServices({
  required PublicServiceSelection current,
  required Iterable<String> publishedServices,
}) {
  final published = sanitizePublicServiceIds(publishedServices);
  if (!published.contains(kLimousinePublicServiceId)) return current;
  if (current.limousineEnabled && current.configured) return current;
  final ids = <String>{...current.ids, ...published}.toList(growable: false);
  return PublicServiceSelection(
    ids: sanitizePublicServiceIds(ids),
    configured: true,
    sourceRevision: current.sourceRevision,
  );
}

bool limousineBusinessSettingsCardIsComplete({
  required bool publicServiceEnabled,
  required bool sectionEnabled,
  required bool hasEligibleVehicle,
  required bool hasPublishedOffer,
  required bool hasPublicText,
  required bool hasSafePublicMedia,
}) {
  if (!publicServiceEnabled) return false;
  return sectionEnabled &&
      hasEligibleVehicle &&
      hasPublishedOffer &&
      hasPublicText &&
      hasSafePublicMedia;
}

bool limousineBusinessSettingsCardIsOptional({
  required bool publicServiceEnabled,
  required bool sectionEnabled,
}) {
  return !publicServiceEnabled && !sectionEnabled;
}
