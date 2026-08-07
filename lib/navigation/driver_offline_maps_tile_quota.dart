// OFFLINE-MAPS-TILE-LIMIT-PREFLIGHT-P0-2
//
// Mapbox Maps Flutter 2.18.0 TileStore contract (tile_store.dart):
// "By default, users may download up to 750 tile packs for offline use across
// all regions. If the limit is hit, any loadRegion call will fail until excess
// regions are deleted."
//
// Pure quota math — no Mapbox imports, no I/O. Resource counts come from
// TileRegion.requiredResourceCount / estimate progress requiredResourceCount.

import 'package:fluxidi_tracking/app_strings.dart';

/// Default Mapbox Maps offline tile-pack cap for the default TileStore.
///
/// Documented on [TileStore.loadTileRegion] in mapbox_maps_flutter 2.18.0.
const int kMapboxOfflineMapsTilePackLimit = 750;

/// Snapshot of Maps tile-pack capacity on the default TileStore.
class DriverOfflineMapsTileCapacity {
  final int usedMapsTiles;
  final int limitMapsTiles;

  const DriverOfflineMapsTileCapacity({
    required this.usedMapsTiles,
    this.limitMapsTiles = kMapboxOfflineMapsTilePackLimit,
  });

  int get availableMapsTiles {
    final left = limitMapsTiles - usedMapsTiles;
    return left < 0 ? 0 : left;
  }

  bool get isAtOrOverLimit => usedMapsTiles >= limitMapsTiles;
}

/// Outcome of comparing a requested region against remaining capacity.
enum DriverOfflineMapsTileQuotaDecision {
  /// requested <= available (including exact equality).
  allowed,

  /// requested > available.
  blocked,

  /// Estimate did not yield a usable tile count — caller must not pretend
  /// the selection fits; download may still be blocked by policy.
  unknown,
}

class DriverOfflineMapsTileQuotaEvaluation {
  final DriverOfflineMapsTileQuotaDecision decision;
  final int usedMapsTiles;
  final int availableMapsTiles;
  final int limitMapsTiles;
  final int? requestedMapsTiles;
  final int? projectedTotalMapsTiles;

  const DriverOfflineMapsTileQuotaEvaluation({
    required this.decision,
    required this.usedMapsTiles,
    required this.availableMapsTiles,
    required this.limitMapsTiles,
    this.requestedMapsTiles,
    this.projectedTotalMapsTiles,
  });

  bool get isAllowed => decision == DriverOfflineMapsTileQuotaDecision.allowed;
  bool get isBlocked => decision == DriverOfflineMapsTileQuotaDecision.blocked;
}

/// Sums Maps tile packs already held by existing TileRegions.
///
/// [regionTileCounts] maps regionId → requiredResourceCount (or completed when
/// that is the only proven count). Estimate phantom ids (`*__estimate`) and
/// non-positive counts are ignored. When [excludeRegionId] is set (replace /
/// re-download of the same id), that region's current count is omitted so it
/// is not double-counted against the new estimate.
int sumOfflineMapsTileUsage({
  required Map<String, int> regionTileCounts,
  String? excludeRegionId,
}) {
  var total = 0;
  final exclude = excludeRegionId?.trim() ?? '';
  regionTileCounts.forEach((id, count) {
    final regionId = id.trim();
    if (regionId.isEmpty || regionId.endsWith('__estimate')) return;
    if (exclude.isNotEmpty && regionId == exclude) return;
    if (count <= 0) return;
    total += count;
  });
  return total;
}

DriverOfflineMapsTileCapacity buildOfflineMapsTileCapacity({
  required Map<String, int> regionTileCounts,
  String? excludeRegionId,
  int limitMapsTiles = kMapboxOfflineMapsTilePackLimit,
}) {
  final used = sumOfflineMapsTileUsage(
    regionTileCounts: regionTileCounts,
    excludeRegionId: excludeRegionId,
  );
  return DriverOfflineMapsTileCapacity(
    usedMapsTiles: used,
    limitMapsTiles: limitMapsTiles < 0 ? 0 : limitMapsTiles,
  );
}

/// Pure quota gate. Exact equality is allowed (requested == available).
DriverOfflineMapsTileQuotaEvaluation evaluateOfflineMapsTileQuota({
  required int usedMapsTiles,
  required int? requestedMapsTiles,
  int limitMapsTiles = kMapboxOfflineMapsTilePackLimit,
}) {
  final used = usedMapsTiles < 0 ? 0 : usedMapsTiles;
  final limit = limitMapsTiles < 0 ? 0 : limitMapsTiles;
  final available = (limit - used) < 0 ? 0 : (limit - used);

  if (requestedMapsTiles == null || requestedMapsTiles < 0) {
    return DriverOfflineMapsTileQuotaEvaluation(
      decision: DriverOfflineMapsTileQuotaDecision.unknown,
      usedMapsTiles: used,
      availableMapsTiles: available,
      limitMapsTiles: limit,
      requestedMapsTiles: requestedMapsTiles,
    );
  }

  final requested = requestedMapsTiles;
  final projected = used + requested;
  if (requested <= available) {
    return DriverOfflineMapsTileQuotaEvaluation(
      decision: DriverOfflineMapsTileQuotaDecision.allowed,
      usedMapsTiles: used,
      availableMapsTiles: available,
      limitMapsTiles: limit,
      requestedMapsTiles: requested,
      projectedTotalMapsTiles: projected,
    );
  }
  return DriverOfflineMapsTileQuotaEvaluation(
    decision: DriverOfflineMapsTileQuotaDecision.blocked,
    usedMapsTiles: used,
    availableMapsTiles: available,
    limitMapsTiles: limit,
    requestedMapsTiles: requested,
    projectedTotalMapsTiles: projected,
  );
}

/// Largest radius (from [radiusOptionsKm] descending) whose estimate fits.
///
/// Returns null when none fit. Never silently picks a radius — callers must
/// surface the suggestion to the user.
int? suggestLargestValidOfflineMapsRadiusKm({
  required List<int> radiusOptionsKm,
  required int Function(int radiusKm) estimatedTilesForRadiusKm,
  required int usedMapsTiles,
  int limitMapsTiles = kMapboxOfflineMapsTilePackLimit,
}) {
  final sorted = radiusOptionsKm.toSet().toList()
    ..sort((a, b) => b.compareTo(a));
  for (final km in sorted) {
    if (km <= 0) continue;
    final tiles = estimatedTilesForRadiusKm(km);
    if (tiles < 0) continue;
    final evaluation = evaluateOfflineMapsTileQuota(
      usedMapsTiles: usedMapsTiles,
      requestedMapsTiles: tiles,
      limitMapsTiles: limitMapsTiles,
    );
    if (evaluation.isAllowed) return km;
  }
  return null;
}

/// NL/EN capacity + selection copy for the confirm / selector UI.
String formatOfflineMapsTileQuotaBlockedMessage({
  required AppLanguage language,
  required int requestedMapsTiles,
  required int availableMapsTiles,
  int? suggestedRadiusKm,
}) {
  switch (language) {
    case AppLanguage.nl:
      final base =
          'Deze regio heeft ongeveer $requestedMapsTiles kaarttegels nodig. '
          'Nog beschikbaar: $availableMapsTiles. '
          'Kies een kleinere straal of minder detail.';
      if (suggestedRadiusKm != null && suggestedRadiusKm > 0) {
        return '$base\n\nVoorstel: $suggestedRadiusKm km past wel.';
      }
      return base;
    case AppLanguage.fr:
      final base =
          'Cette région nécessite environ $requestedMapsTiles tuiles. '
          'Disponible : $availableMapsTiles. '
          'Choisissez un rayon plus petit ou moins de détail.';
      if (suggestedRadiusKm != null && suggestedRadiusKm > 0) {
        return '$base\n\nSuggestion : $suggestedRadiusKm km convient.';
      }
      return base;
    case AppLanguage.es:
      final base =
          'Esta región necesita unas $requestedMapsTiles teselas. '
          'Disponibles: $availableMapsTiles. '
          'Elige un radio menor o menos detalle.';
      if (suggestedRadiusKm != null && suggestedRadiusKm > 0) {
        return '$base\n\nSugerencia: $suggestedRadiusKm km sí cabe.';
      }
      return base;
    case AppLanguage.de:
      final base =
          'Diese Region braucht etwa $requestedMapsTiles Kacheln. '
          'Noch verfügbar: $availableMapsTiles. '
          'Wählen Sie einen kleineren Radius oder weniger Detail.';
      if (suggestedRadiusKm != null && suggestedRadiusKm > 0) {
        return '$base\n\nVorschlag: $suggestedRadiusKm km passt.';
      }
      return base;
    case AppLanguage.en:
      final base =
          'This region needs about $requestedMapsTiles map tiles. '
          'Still available: $availableMapsTiles. '
          'Choose a smaller radius or less detail.';
      if (suggestedRadiusKm != null && suggestedRadiusKm > 0) {
        return '$base\n\nSuggestion: $suggestedRadiusKm km fits.';
      }
      return base;
  }
}

String formatOfflineMapsTileQuotaSummaryLine({
  required AppLanguage language,
  required int? requestedMapsTiles,
  required int usedMapsTiles,
  required int availableMapsTiles,
  required int limitMapsTiles,
}) {
  final requestedLabel =
      requestedMapsTiles == null ? '—' : '$requestedMapsTiles';
  switch (language) {
    case AppLanguage.nl:
      return 'Kaarttegels: ongeveer $requestedLabel nodig · '
          'gebruikt $usedMapsTiles / $limitMapsTiles · '
          'nog $availableMapsTiles beschikbaar';
    case AppLanguage.fr:
      return 'Tuiles : environ $requestedLabel nécessaires · '
          'utilisées $usedMapsTiles / $limitMapsTiles · '
          'encore $availableMapsTiles disponibles';
    case AppLanguage.es:
      return 'Teselas: unas $requestedLabel necesarias · '
          'usadas $usedMapsTiles / $limitMapsTiles · '
          'quedan $availableMapsTiles';
    case AppLanguage.de:
      return 'Kacheln: etwa $requestedLabel nötig · '
          'genutzt $usedMapsTiles / $limitMapsTiles · '
          'noch $availableMapsTiles verfügbar';
    case AppLanguage.en:
      return 'Map tiles: about $requestedLabel needed · '
          'used $usedMapsTiles / $limitMapsTiles · '
          '$availableMapsTiles still available';
  }
}

String offlineMapsSelectionTooLargeLabel(AppLanguage language) {
  switch (language) {
    case AppLanguage.nl:
      return 'Te groot';
    case AppLanguage.fr:
      return 'Trop grand';
    case AppLanguage.es:
      return 'Demasiado grande';
    case AppLanguage.de:
      return 'Zu groß';
    case AppLanguage.en:
      return 'Too large';
  }
}

String offlineMapsNoValidRadiusMessage(AppLanguage language) {
  switch (language) {
    case AppLanguage.nl:
      return 'Geen beschikbare downloadstraal past binnen de offline '
          'kaartcapaciteit. Verwijder eerst een bestaande regio of kies '
          'minder detail.';
    case AppLanguage.fr:
      return 'Aucun rayon disponible ne tient dans la capacité hors ligne. '
          'Supprimez d’abord une région ou choisissez moins de détail.';
    case AppLanguage.es:
      return 'Ningún radio disponible cabe en la capacidad offline. '
          'Elimina primero una región o elige menos detalle.';
    case AppLanguage.de:
      return 'Kein verfügbarer Radius passt in die Offline-Kapazität. '
          'Löschen Sie zuerst eine Region oder wählen Sie weniger Detail.';
    case AppLanguage.en:
      return 'No available download radius fits the offline map capacity. '
          'Delete an existing region first or choose less detail.';
  }
}
