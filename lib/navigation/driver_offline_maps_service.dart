import 'package:flutter/foundation.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mb;

import 'driver_navigation_map_config.dart';
import 'driver_offline_maps_download_feedback.dart';
import 'driver_offline_maps_tile_quota.dart';
import 'nav_engine/nav_field_diagnostics.dart';

/// Fluxidi metadata marker for tile regions created by this service.
const String kDriverOfflineMapsMetadataSource = 'fluxidi_driver_offline_maps';

/// Default zoom range for street-level driver navigation offline tiles.
///
/// Aligns with Mapbox tile batch guidance (local 11–14, street detail 15–16).
const int kDriverOfflineMapsDefaultMinZoom = 11;
const int kDriverOfflineMapsDefaultMaxZoom = 16;

/// Offline basemap tiles only.
///
/// Downloaded map areas keep the street map visible when mobile signal is weak.
/// Directions, reroute, geocoding, live traffic, and fresh lane/turn data still
/// require network. Full offline routing is out of scope for V1.
enum DriverOfflineMapProgressPhase {
  stylePack,
  tileRegion,
  estimate,
  delete,
}

/// UI-agnostic download / estimate / delete progress snapshot.
class DriverOfflineMapProgress {
  final DriverOfflineMapProgressPhase phase;
  final String regionId;
  final int? completedResourceCount;
  final int? requiredResourceCount;
  final int? completedResourceSize;
  final String? styleUri;
  final String? status;
  final String? message;

  const DriverOfflineMapProgress({
    required this.phase,
    required this.regionId,
    this.completedResourceCount,
    this.requiredResourceCount,
    this.completedResourceSize,
    this.styleUri,
    this.status,
    this.message,
  });

  double? get fraction {
    final required = requiredResourceCount;
    final completed = completedResourceCount;
    if (required == null || required <= 0 || completed == null) return null;
    return (completed / required).clamp(0.0, 1.0);
  }
}

/// Request to download or estimate an offline basemap region.
///
/// [geometry] is a GeoJSON-compatible map (e.g. Polygon, MultiPolygon) for future
/// visible-map, company coverage, or airport-preset callers. This service does not
/// extract geometry from a live map.
class DriverOfflineMapRegionRequest {
  final String displayName;
  final Map<String, dynamic> geometry;
  final int minZoom;
  final int maxZoom;
  final List<String> styleUris;
  final String? slug;
  final bool wifiOnly;
  final bool acceptExpired;

  const DriverOfflineMapRegionRequest({
    required this.displayName,
    required this.geometry,
    this.minZoom = kDriverOfflineMapsDefaultMinZoom,
    this.maxZoom = kDriverOfflineMapsDefaultMaxZoom,
    this.styleUris = kDriverOfflineMapsDefaultStyleUris,
    this.slug,
    this.wifiOnly = false,
    this.acceptExpired = false,
  });

  String get regionId => driverOfflineMapRegionId(
        slug: slug ?? driverOfflineMapSlugFromDisplayName(displayName),
        minZoom: minZoom,
        maxZoom: maxZoom,
      );
}

/// NAV-MOBILE-DATA-MINIMAL-SAFE-RELEASE-P0-1 — Part F.
///
/// Truthful completion status for a downloaded offline basemap region.
///
/// The Mapbox `TileRegion` and `StylePack` objects returned by the SDK's list
/// APIs do NOT expose `erroredResourceCount` — only the progress callbacks
/// during load do. Callers therefore persist the final errored count into
/// region metadata at download time so post-restart status is truthful.
enum DriverOfflineMapCompletionStatus {
  /// `required > 0`, `completed == required`, `errored == 0` and every
  /// verifiable StylePack matches its style URI.
  complete,

  /// `completed < required`. Still downloading, or downloads never finished.
  incomplete,

  /// `completed == required` but at least one resource failed. Tiles are
  /// present but callers must NOT claim the region is fully offline.
  completedWithErrors,

  /// Tile region or style pack expiry has passed. Callers should refresh.
  expiredOrStale,

  /// The service cannot prove completeness (persisted metadata is missing
  /// or the associated StylePack could not be verified).
  unknown,
}

/// Bounded PII-free label for a completion status.
String driverOfflineMapCompletionStatusToken(
  DriverOfflineMapCompletionStatus status,
) {
  switch (status) {
    case DriverOfflineMapCompletionStatus.complete:
      return 'complete';
    case DriverOfflineMapCompletionStatus.incomplete:
      return 'incomplete';
    case DriverOfflineMapCompletionStatus.completedWithErrors:
      return 'completed_with_errors';
    case DriverOfflineMapCompletionStatus.expiredOrStale:
      return 'expired_or_stale';
    case DriverOfflineMapCompletionStatus.unknown:
      return 'unknown';
  }
}

/// Metadata key for persisting the errored resource count from the last
/// [_loadTileRegion] progress emission. Not a PII value.
const String kDriverOfflineMapMetadataErroredTileCount =
    'erroredTileResourceCount';

/// Metadata key for persisting the sum of per-style errored resource counts
/// observed during [_loadStylePack] progress emissions.
const String kDriverOfflineMapMetadataErroredStyleCount =
    'erroredStyleResourceCount';

/// Summary of a downloaded (or in-progress) offline basemap region.
class DriverOfflineMapRegionInfo {
  final String id;
  final String displayName;
  final DateTime? createdAt;
  final int minZoom;
  final int maxZoom;
  final List<String> styleUris;
  final int requiredResourceCount;
  final int completedResourceCount;
  final int completedResourceSize;

  /// Sum of the errored resource counts persisted during the most recent
  /// download. `null` when no persisted value is available (e.g. legacy
  /// regions downloaded before Part F).
  final int? erroredResourceCount;

  /// Sum of per-style errored resource counts persisted during the most
  /// recent download. `null` when no persisted value is available.
  final int? styleErroredResourceCount;

  /// True when every declared style URI has an associated StylePack whose
  /// `completed == required`. `null` when the service could not query the
  /// underlying manager (e.g. init failure); treated as "unknown".
  final bool? stylePacksVerified;

  /// True when [expires] has passed and the SDK reports the resources as
  /// stale. Ignored when the SDK does not report an expiry (null).
  final bool expired;

  /// The earliest expiry reported by the underlying [mb.TileRegion.expires]
  /// (milliseconds since epoch). `null` when the region has no expiry.
  final int? expiresAtMs;

  /// Deprecated boolean form retained for existing UI callers. Prefer
  /// [completionStatus] which distinguishes complete / completed-with-errors
  /// / incomplete / expired / unknown.
  ///
  /// Truth rule: only `DriverOfflineMapCompletionStatus.complete` returns
  /// true. `completedWithErrors` and every other state return false.
  bool get isComplete => completionStatus == DriverOfflineMapCompletionStatus.complete;

  /// Truthful completion status computed from the persisted errored counts,
  /// StylePack verification and expiry.
  final DriverOfflineMapCompletionStatus completionStatus;

  const DriverOfflineMapRegionInfo({
    required this.id,
    required this.displayName,
    this.createdAt,
    required this.minZoom,
    required this.maxZoom,
    this.styleUris = const <String>[],
    required this.requiredResourceCount,
    required this.completedResourceCount,
    required this.completedResourceSize,
    required this.completionStatus,
    this.erroredResourceCount,
    this.styleErroredResourceCount,
    this.stylePacksVerified,
    this.expired = false,
    this.expiresAtMs,
  });
}

/// StylePack ready per Mapbox Maps Flutter 2.18.0
/// ([StylePack] / [StylePackLoadProgress]): resources are ready when
/// `completedResourceCount >= requiredResourceCount`.
///
/// Cached packs commonly finish as `required=0, completed=0, errored=0`.
/// That is NOT a failure under this SDK contract.
bool stylePackResourcesReady({
  required int requiredResourceCount,
  required int completedResourceCount,
}) {
  if (requiredResourceCount < 0 || completedResourceCount < 0) return false;
  return completedResourceCount >= requiredResourceCount;
}

/// TileRegion fully downloaded per Mapbox Maps Flutter 2.18.0
/// ([TileRegion]): `completedResourceCount == requiredResourceCount`.
///
/// `required == 0` is treated as *no navigable proof* (unknown), not as a
/// fabricated download failure — empty counters without an exception must not
/// be forced into FAIL by Fluxidi.
bool tileRegionResourcesFullyDownloaded({
  required int requiredResourceCount,
  required int completedResourceCount,
}) {
  if (requiredResourceCount <= 0) return false;
  return completedResourceCount >= requiredResourceCount;
}

/// Pure completion-status resolver. Kept public so unit tests can exercise
/// the exact rules without a live Mapbox SDK.
DriverOfflineMapCompletionStatus resolveDriverOfflineMapCompletionStatus({
  required int requiredResourceCount,
  required int completedResourceCount,
  required int? erroredResourceCount,
  required int? styleErroredResourceCount,
  required bool? stylePacksVerified,
  required bool expired,
}) {
  // OFFLINE-MAPS-DOWNLOAD-COMPLETION-P0-1: 0/0 is unknown, never auto-FAIL.
  if (requiredResourceCount <= 0) {
    return DriverOfflineMapCompletionStatus.unknown;
  }
  if (!tileRegionResourcesFullyDownloaded(
    requiredResourceCount: requiredResourceCount,
    completedResourceCount: completedResourceCount,
  )) {
    return DriverOfflineMapCompletionStatus.incomplete;
  }
  if (expired) {
    return DriverOfflineMapCompletionStatus.expiredOrStale;
  }
  final tileErrors = erroredResourceCount ?? 0;
  final styleErrors = styleErroredResourceCount ?? 0;
  if (erroredResourceCount == null && styleErroredResourceCount == null) {
    // No persisted errored counters — cannot prove complete or errored.
    if (stylePacksVerified == false) {
      return DriverOfflineMapCompletionStatus.unknown;
    }
    if (stylePacksVerified == true) {
      // Tiles fully downloaded, styles verified, no errored evidence.
      return DriverOfflineMapCompletionStatus.complete;
    }
    return DriverOfflineMapCompletionStatus.unknown;
  }
  if (tileErrors > 0 || styleErrors > 0) {
    return DriverOfflineMapCompletionStatus.completedWithErrors;
  }
  if (stylePacksVerified == false) {
    return DriverOfflineMapCompletionStatus.completedWithErrors;
  }
  return DriverOfflineMapCompletionStatus.complete;
}

void _offlineMapsFieldLog(String line) {
  // Always emit in profile/release field builds (not gated on kDebugMode).
  navFieldDiagnosticsPrinter(line);
}

/// Storage / transfer estimate for a region download.
///
/// Values come from [mb.TileRegionEstimateResult]. They are statistical estimates
/// (99.9% confidence band via [errorMargin]), not exact byte counts until download
/// completes.
///
/// [estimatedMapsTileCount] is the best Maps tile-pack count observed on
/// [mb.TileRegionEstimateProgress.requiredResourceCount] during estimate (SDK
/// has no dedicated estimated-tiles result field in 2.18.0).
class DriverOfflineMapEstimate {
  final int transferSizeBytes;
  final int storageSizeBytes;
  final double errorMargin;
  final int? estimatedMapsTileCount;

  const DriverOfflineMapEstimate({
    required this.transferSizeBytes,
    required this.storageSizeBytes,
    required this.errorMargin,
    this.estimatedMapsTileCount,
  });

  /// Normalizes SDK estimate fields. Non-finite / negative margins become
  /// [double.nan] so UI formatters omit the ±% clause instead of crashing on
  /// `.round()` / `.toInt()`. Negative byte counts collapse to 0.
  factory DriverOfflineMapEstimate.fromSdk(
    mb.TileRegionEstimateResult result, {
    int? estimatedMapsTileCount,
  }) {
    final margin = result.errorMargin;
    final safeMargin =
        margin.isFinite && !margin.isNaN && margin >= 0 ? margin : double.nan;
    final tiles = estimatedMapsTileCount;
    return DriverOfflineMapEstimate(
      transferSizeBytes: result.transferSize < 0 ? 0 : result.transferSize,
      storageSizeBytes: result.storageSize < 0 ? 0 : result.storageSize,
      errorMargin: safeMargin,
      estimatedMapsTileCount:
          tiles != null && tiles > 0 ? tiles : null,
    );
  }
}

/// Preflight result: byte estimate + cumulative Maps tile-pack quota.
class DriverOfflineMapPreflight {
  final DriverOfflineMapEstimate estimate;
  final DriverOfflineMapsTileCapacity capacity;
  final DriverOfflineMapsTileQuotaEvaluation quota;

  const DriverOfflineMapPreflight({
    required this.estimate,
    required this.capacity,
    required this.quota,
  });

  bool get downloadAllowedByQuota => quota.isAllowed;
}

class DriverOfflineMapsException implements Exception {
  final String message;
  final String? phase;
  final String? regionId;
  final Object? cause;

  const DriverOfflineMapsException(
    this.message, {
    this.phase,
    this.regionId,
    this.cause,
  });

  @override
  String toString() {
    final parts = <String>['DriverOfflineMapsException: $message'];
    if (phase != null) parts.add('phase=$phase');
    if (regionId != null) parts.add('region=$regionId');
    return parts.join(' ');
  }
}

typedef DriverOfflineMapProgressCallback = void Function(
  DriverOfflineMapProgress progress,
);

/// Both driver navigation styles — light/follow and dark/overview.
const List<String> kDriverOfflineMapsDefaultStyleUris = <String>[
  kDriverMapStyleLight,
  kDriverMapStyleDark,
];

/// Builds a stable non-PII region id: `fluxidi_driver_region_<slug>_<min>_<max>`.
String driverOfflineMapRegionId({
  required String slug,
  required int minZoom,
  required int maxZoom,
}) {
  final safeSlug = driverOfflineMapSlugFromDisplayName(slug);
  return 'fluxidi_driver_region_${safeSlug}_${minZoom}_$maxZoom';
}

String driverOfflineMapSlugFromDisplayName(String input) {
  final normalized = input.trim().toLowerCase();
  if (normalized.isEmpty) return 'region';
  final buffer = StringBuffer();
  var previousUnderscore = false;
  for (final codeUnit in normalized.codeUnits) {
    final char = String.fromCharCode(codeUnit);
    final isAlphaNum =
        (codeUnit >= 48 && codeUnit <= 57) ||
        (codeUnit >= 97 && codeUnit <= 122);
    if (isAlphaNum) {
      buffer.write(char);
      previousUnderscore = false;
    } else if (!previousUnderscore) {
      buffer.write('_');
      previousUnderscore = true;
    }
  }
  var slug = buffer.toString();
  slug = slug.replaceAll(RegExp(r'_+'), '_');
  slug = slug.replaceAll(RegExp(r'^_+|_+$'), '');
  if (slug.isEmpty) return 'region';
  if (slug.length > 48) slug = slug.substring(0, 48);
  return slug;
}

/// The offline map-tile operations the driver UI depends on.
///
/// [DriverOfflineMapsService] is the only production implementation; this exists
/// so the page can be driven deterministically in tests without a live Mapbox
/// TileStore. It is a seam, not a second download service.
abstract interface class DriverOfflineMapsDownloadPort {
  Future<void> ensureInitialized();

  Future<DriverOfflineMapEstimate> estimateRegion(
    DriverOfflineMapRegionRequest request, {
    DriverOfflineMapProgressCallback? onProgress,
  });

  /// Cumulative Maps tile-pack usage on the default TileStore (SDK 750 cap).
  Future<DriverOfflineMapsTileCapacity> readTileCapacity({
    String? excludeRegionId,
  });

  /// Estimate + quota gate. Must run before StylePack / TileRegion download.
  Future<DriverOfflineMapPreflight> preflightRegion(
    DriverOfflineMapRegionRequest request, {
    DriverOfflineMapProgressCallback? onProgress,
  });

  Future<DriverOfflineMapRegionInfo> downloadRegion(
    DriverOfflineMapRegionRequest request, {
    DriverOfflineMapProgressCallback? onProgress,
  });

  Future<List<DriverOfflineMapRegionInfo>> listDownloadedRegions();

  Future<void> deleteRegion(
    String regionId, {
    DriverOfflineMapProgressCallback? onProgress,
  });
}

/// Wraps Mapbox [mb.OfflineManager] and [mb.TileStore] for driver offline basemaps.
class DriverOfflineMapsService implements DriverOfflineMapsDownloadPort {
  DriverOfflineMapsService._();

  static final DriverOfflineMapsService shared = DriverOfflineMapsService._();

  mb.OfflineManager? _offlineManager;
  mb.TileStore? _tileStore;
  Future<void>? _initFuture;

  /// Lazily creates Mapbox offline manager and default tile store.
  @override
  Future<void> ensureInitialized() {
    _initFuture ??= _initialize();
    return _initFuture!;
  }

  Future<void> _initialize() async {
    try {
      _offlineManager = await mb.OfflineManager.create();
      _tileStore = await mb.TileStore.createDefault();
      _log('init', 'service', 'done');
    } catch (e) {
      _initFuture = null;
      throw DriverOfflineMapsException(
        'Could not initialize offline maps.',
        phase: 'init',
        cause: e,
      );
    }
  }

  mb.OfflineManager get _manager {
    final manager = _offlineManager;
    if (manager == null) {
      throw const DriverOfflineMapsException(
        'Offline maps service is not initialized.',
        phase: 'init',
      );
    }
    return manager;
  }

  mb.TileStore get _store {
    final store = _tileStore;
    if (store == null) {
      throw const DriverOfflineMapsException(
        'Offline maps service is not initialized.',
        phase: 'init',
      );
    }
    return store;
  }

  /// Estimates transfer and on-disk size for [request] without mutating regions.
  @override
  Future<DriverOfflineMapEstimate> estimateRegion(
    DriverOfflineMapRegionRequest request, {
    DriverOfflineMapProgressCallback? onProgress,
  }) async {
    await ensureInitialized();
    final regionId = request.regionId;
    _log('estimate', regionId, 'start');
    _emitProgress(
      onProgress,
      DriverOfflineMapProgress(
        phase: DriverOfflineMapProgressPhase.estimate,
        regionId: regionId,
        status: 'start',
      ),
    );

    try {
      final loadOptions = _buildTileRegionLoadOptions(request);
      // OFFLINE-MAPS-DOWNLOAD-COMPLETION-P0-1: never share the download region
      // id with estimate — Mapbox cancels a pending load for the same id.
      final estimateId = '${regionId}__estimate';
      var peakRequiredTiles = 0;
      final result = await _store.estimateTileRegion(
        estimateId,
        loadOptions,
        mb.TileRegionEstimateOptions(
          errorMargin: 0.15,
          preciseEstimationTimeout: 5,
          timeout: 30,
        ),
        (mb.TileRegionEstimateProgress progress) {
          if (progress.requiredResourceCount > peakRequiredTiles) {
            peakRequiredTiles = progress.requiredResourceCount;
          }
          if (onProgress == null) return;
          _emitProgress(
            onProgress,
            DriverOfflineMapProgress(
              phase: DriverOfflineMapProgressPhase.estimate,
              regionId: regionId,
              completedResourceCount: progress.completedResourceCount,
              requiredResourceCount: progress.requiredResourceCount,
              status: 'progress',
            ),
          );
        },
      );
      _log('estimate', regionId, 'done');
      // Best-effort: estimate must not leave a phantom region id behind.
      try {
        await _store.removeRegion(estimateId);
      } catch (_) {}
      final estimate = DriverOfflineMapEstimate.fromSdk(
        result,
        estimatedMapsTileCount:
            peakRequiredTiles > 0 ? peakRequiredTiles : null,
      );
      _offlineMapsFieldLog(
        '[OFFLINE_MAPS][ESTIMATE] region_id=$regionId '
        'transfer_bytes=${estimate.transferSizeBytes} '
        'storage_bytes=${estimate.storageSizeBytes} '
        'estimated_maps_tiles=${estimate.estimatedMapsTileCount ?? '-'}',
      );
      _emitProgress(
        onProgress,
        DriverOfflineMapProgress(
          phase: DriverOfflineMapProgressPhase.estimate,
          regionId: regionId,
          requiredResourceCount: estimate.estimatedMapsTileCount,
          status: 'done',
          message: 'estimate_complete',
        ),
      );
      return estimate;
    } catch (e) {
      _log('estimate', regionId, 'fail');
      try {
        await _store.removeRegion('${regionId}__estimate');
      } catch (_) {}
      throw DriverOfflineMapsException(
        'Could not estimate offline map region.',
        phase: 'estimate',
        regionId: regionId,
        cause: e,
      );
    }
  }

  /// Reads cumulative Maps tile-pack usage from all TileRegions on the store.
  ///
  /// Mapbox 2.18.0 documents the 750 cap as across all regions; deleting a
  /// region frees capacity for subsequent loads.
  @override
  Future<DriverOfflineMapsTileCapacity> readTileCapacity({
    String? excludeRegionId,
  }) async {
    await ensureInitialized();
    try {
      final regions = await _store.allTileRegions();
      final counts = <String, int>{};
      for (final region in regions) {
        counts[region.id] = region.requiredResourceCount;
      }
      final capacity = buildOfflineMapsTileCapacity(
        regionTileCounts: counts,
        excludeRegionId: excludeRegionId,
      );
      _offlineMapsFieldLog(
        '[OFFLINE_MAPS][QUOTA] used=${capacity.usedMapsTiles} '
        'limit=${capacity.limitMapsTiles} '
        'available=${capacity.availableMapsTiles} '
        'exclude=${excludeRegionId ?? '-'} '
        'regions=${counts.length}',
      );
      return capacity;
    } catch (e) {
      throw DriverOfflineMapsException(
        'Could not read offline map tile capacity.',
        phase: 'quota',
        cause: e,
      );
    }
  }

  /// Geometry → descriptors → estimate → quota. No StylePack / TileRegion load.
  @override
  Future<DriverOfflineMapPreflight> preflightRegion(
    DriverOfflineMapRegionRequest request, {
    DriverOfflineMapProgressCallback? onProgress,
  }) async {
    await ensureInitialized();
    final estimate = await estimateRegion(request, onProgress: onProgress);
    final capacity = await readTileCapacity(
      excludeRegionId: request.regionId,
    );
    final quota = evaluateOfflineMapsTileQuota(
      usedMapsTiles: capacity.usedMapsTiles,
      requestedMapsTiles: estimate.estimatedMapsTileCount,
      limitMapsTiles: capacity.limitMapsTiles,
    );
    _offlineMapsFieldLog(
      '[OFFLINE_MAPS][PREFLIGHT] region_id=${request.regionId} '
      'requested_tiles=${estimate.estimatedMapsTileCount ?? '-'} '
      'used=${capacity.usedMapsTiles} available=${capacity.availableMapsTiles} '
      'decision=${quota.decision.name}',
    );
    return DriverOfflineMapPreflight(
      estimate: estimate,
      capacity: capacity,
      quota: quota,
    );
  }

  /// Downloads style packs and tile region for [request].
  ///
  /// Order: geometry/descriptors validated → quota preflight → StylePacks →
  /// TileRegion → verify. Quota failures throw before any StylePack load when
  /// the estimate yields a usable tile count.
  @override
  Future<DriverOfflineMapRegionInfo> downloadRegion(
    DriverOfflineMapRegionRequest request, {
    DriverOfflineMapProgressCallback? onProgress,
  }) async {
    await ensureInitialized();
    final regionId = request.regionId;
    _log('download', regionId, 'start');

    final styleUris = _normalizedStyleUris(request.styleUris);
    if (styleUris.isEmpty) {
      throw DriverOfflineMapsException(
        'At least one style URI is required.',
        phase: 'download',
        regionId: regionId,
      );
    }

    final geometryValid = request.geometry.isNotEmpty &&
        (request.geometry['type']?.toString().isNotEmpty ?? false);
    final center = _geometryCenterForLog(request.geometry);
    final radiusKm = _radiusKmFromSlug(request.slug) ?? '-';
    _offlineMapsFieldLog(
      '[OFFLINE_MAPS][REQUEST] region_id=$regionId '
      'center=$center radius_km=$radiusKm '
      'min_zoom=${request.minZoom} max_zoom=${request.maxZoom} '
      'style_uris=${styleUris.join(',')} geometry_valid=$geometryValid',
    );

    try {
      // OFFLINE-MAPS-TILE-LIMIT-PREFLIGHT-P0-2: block before expensive packs
      // when quota is proven over limit. Estimate failures leave quota unknown
      // and do not by themselves abort the download (Mapbox may still reject).
      try {
        final preflight = await preflightRegion(
          request,
          onProgress: onProgress,
        );
        if (preflight.quota.isBlocked) {
          throw DriverOfflineMapsException(
            'Maps tile pack limit exceeded '
            '(requested=${preflight.estimate.estimatedMapsTileCount} '
            'available=${preflight.capacity.availableMapsTiles} '
            'maximum allowed ${preflight.capacity.limitMapsTiles} tiles).',
            phase: 'quota',
            regionId: regionId,
          );
        }
      } on DriverOfflineMapsException catch (e) {
        if (e.phase == 'quota') rethrow;
        _offlineMapsFieldLog(
          '[OFFLINE_MAPS][PREFLIGHT] continue_without_quota '
          'region_id=$regionId phase=${e.phase} '
          'message=${_safeErr(e)}',
        );
      } catch (e) {
        _offlineMapsFieldLog(
          '[OFFLINE_MAPS][PREFLIGHT] continue_without_quota '
          'region_id=$regionId message=${_safeErr(e)}',
        );
      }

      int styleErroredTotal = 0;
      for (final styleUri in styleUris) {
        styleErroredTotal += await _loadStylePack(
          styleUri: styleUri,
          regionId: regionId,
          acceptExpired: request.acceptExpired,
          onProgress: onProgress,
        );
      }

      int tileErroredTotal = 0;
      final tileRegion = await _loadTileRegion(
        request: request,
        styleUris: styleUris,
        onProgress: onProgress,
        onErroredResourceObserved: (count) {
          if (count > tileErroredTotal) tileErroredTotal = count;
        },
      );
      _log('download', regionId, 'done');

      // Read back the same region id — proves loadTileRegion persisted it.
      mb.TileRegion verifiedRegion = tileRegion;
      var tileRegionFound = true;
      try {
        verifiedRegion = await _store.tileRegion(regionId);
      } catch (e) {
        tileRegionFound = false;
        _offlineMapsFieldLog(
          '[OFFLINE_MAPS][FAIL] stage=tile_readback '
          'exception_type=${e.runtimeType} message=${_safeErr(e)}',
        );
        throw DriverOfflineMapsException(
          'Tile region was not found after loadTileRegion.',
          phase: 'download',
          regionId: regionId,
          cause: e,
        );
      }

      // NAV-MOBILE-DATA-MINIMAL-SAFE-RELEASE-P0-1 Part F: persist the final
      // errored counts into the region metadata so future list/status queries
      // are truthful even after an app restart (the SDK does not expose an
      // errored count on the TileRegion / StylePack objects themselves).
      await _persistFinalErroredCounts(
        regionId: regionId,
        styleUris: styleUris,
        tileErroredCount: tileErroredTotal,
        styleErroredCount: styleErroredTotal,
      );
      logNavOfflineTruth(
        kind: 'tile_region',
        regionId: regionId,
        requiredCount: verifiedRegion.requiredResourceCount,
        completedCount: verifiedRegion.completedResourceCount,
        erroredCount: tileErroredTotal,
      );
      final info = await _regionInfoFromTileRegion(verifiedRegion);
      _offlineMapsFieldLog(
        '[OFFLINE_MAPS][VERIFY] style_ok=${info.stylePacksVerified} '
        'tile_region_found=$tileRegionFound '
        'tile_required=${info.requiredResourceCount} '
        'tile_completed=${info.completedResourceCount} '
        'tile_errored=${info.erroredResourceCount ?? tileErroredTotal} '
        'registry_complete=${info.isComplete} '
        'reason=${driverOfflineMapCompletionStatusToken(info.completionStatus)}',
      );
      if (info.completionStatus ==
          DriverOfflineMapCompletionStatus.incomplete) {
        throw DriverOfflineMapsException(
          'Tile region incomplete: completed < required.',
          phase: 'download',
          regionId: regionId,
        );
      }
      _emitProgress(
        onProgress,
        DriverOfflineMapProgress(
          phase: DriverOfflineMapProgressPhase.tileRegion,
          regionId: regionId,
          completedResourceCount: info.completedResourceCount,
          requiredResourceCount: info.requiredResourceCount,
          completedResourceSize: info.completedResourceSize,
          status: 'done',
        ),
      );
      return info;
    } catch (e) {
      _log('download', regionId, 'fail');
      _offlineMapsFieldLog(
        '[OFFLINE_MAPS][FAIL] stage=download '
        'exception_type=${e.runtimeType} message=${_safeErr(e)}',
      );
      if (e is DriverOfflineMapsException) rethrow;
      throw DriverOfflineMapsException(
        'Offline map download failed.',
        phase: 'download',
        regionId: regionId,
        cause: e,
      );
    }
  }

  /// Lists Fluxidi-managed offline regions (metadata source or id prefix).
  @override
  Future<List<DriverOfflineMapRegionInfo>> listDownloadedRegions() async {
    await ensureInitialized();
    try {
      final regions = await _store.allTileRegions();
      final out = <DriverOfflineMapRegionInfo>[];
      for (final region in regions) {
        if (!_isFluxidiManagedRegionId(region.id)) continue;
        // Estimate uses a sibling id; never surface it as a downloaded region.
        if (region.id.endsWith('__estimate')) continue;
        out.add(await _regionInfoFromTileRegion(region));
      }
      out.sort((a, b) {
        final aTime = a.createdAt?.millisecondsSinceEpoch ?? 0;
        final bTime = b.createdAt?.millisecondsSinceEpoch ?? 0;
        return bTime.compareTo(aTime);
      });
      return out;
    } catch (e) {
      throw DriverOfflineMapsException(
        'Could not list offline map regions.',
        phase: 'list',
        cause: e,
      );
    }
  }

  /// Removes a tile region by id. Does not remove shared style packs.
  @override
  Future<void> deleteRegion(
    String regionId, {
    DriverOfflineMapProgressCallback? onProgress,
  }) async {
    await ensureInitialized();
    _log('delete', regionId, 'start');
    _emitProgress(
      onProgress,
      DriverOfflineMapProgress(
        phase: DriverOfflineMapProgressPhase.delete,
        regionId: regionId,
        status: 'start',
      ),
    );
    try {
      await _store.removeRegion(regionId);
      _log('delete', regionId, 'done');
      _emitProgress(
        onProgress,
        DriverOfflineMapProgress(
          phase: DriverOfflineMapProgressPhase.delete,
          regionId: regionId,
          status: 'done',
        ),
      );
    } catch (e) {
      _log('delete', regionId, 'fail');
      throw DriverOfflineMapsException(
        'Could not delete offline map region.',
        phase: 'delete',
        regionId: regionId,
        cause: e,
      );
    }
  }

  /// Removes style packs that are no longer referenced by any Fluxidi region.
  ///
  /// Style packs may be shared across regions. [deleteRegion] intentionally
  /// does not call [mb.OfflineManager.removeStylePack] to avoid breaking other
  /// regions. Call this after deletes when storage cleanup is desired.
  Future<void> cleanupUnreferencedStylePacks() async {
    await ensureInitialized();
    final referenced = await _collectReferencedStyleUris();
    for (final styleUri in kDriverOfflineMapsDefaultStyleUris) {
      if (referenced.contains(styleUri)) continue;
      try {
        await _manager.removeStylePack(styleUri);
        _log('cleanup_style_pack', _styleKeyForLog(styleUri), 'done');
      } catch (e) {
        _log('cleanup_style_pack', _styleKeyForLog(styleUri), 'fail');
      }
    }
  }

  /// Loads a StylePack. Returns the highest `erroredResourceCount` seen
  /// during progress emissions so the caller can persist a truthful summary.
  Future<int> _loadStylePack({
    required String styleUri,
    required String regionId,
    required bool acceptExpired,
    DriverOfflineMapProgressCallback? onProgress,
  }) async {
    _offlineMapsFieldLog('[OFFLINE_MAPS][STYLE_START] style_uri=$styleUri');
    _emitProgress(
      onProgress,
      DriverOfflineMapProgress(
        phase: DriverOfflineMapProgressPhase.stylePack,
        regionId: regionId,
        styleUri: styleUri,
        status: 'start',
      ),
    );
    final options = mb.StylePackLoadOptions(
      glyphsRasterizationMode:
          mb.GlyphsRasterizationMode.IDEOGRAPHS_RASTERIZED_LOCALLY,
      metadata: <String, Object>{
        'source': kDriverOfflineMapsMetadataSource,
        'styleKey': _styleKeyForLog(styleUri),
      },
      acceptExpired: acceptExpired,
    );
    var maxErrored = 0;
    var lastRequired = 0;
    var lastCompleted = 0;
    try {
      final pack = await _manager.loadStylePack(
        styleUri,
        options,
        (mb.StylePackLoadProgress progress) {
          if (progress.erroredResourceCount > maxErrored) {
            maxErrored = progress.erroredResourceCount;
          }
          lastRequired = progress.requiredResourceCount;
          lastCompleted = progress.completedResourceCount;
          _offlineMapsFieldLog(
            '[OFFLINE_MAPS][STYLE_PROGRESS] style_uri=$styleUri '
            'required=${progress.requiredResourceCount} '
            'completed=${progress.completedResourceCount} '
            'errored=${progress.erroredResourceCount} '
            'percentage=${_resourcePercent(
              progress.requiredResourceCount,
              progress.completedResourceCount,
            )}',
          );
          _emitProgress(
            onProgress,
            DriverOfflineMapProgress(
              phase: DriverOfflineMapProgressPhase.stylePack,
              regionId: regionId,
              styleUri: styleUri,
              completedResourceCount: progress.completedResourceCount,
              requiredResourceCount: progress.requiredResourceCount,
              completedResourceSize: progress.completedResourceSize,
              status: 'progress',
            ),
          );
        },
      );
      lastRequired = pack.requiredResourceCount;
      lastCompleted = pack.completedResourceCount;
      _offlineMapsFieldLog(
        '[OFFLINE_MAPS][STYLE_DONE] style_uri=$styleUri '
        'required=${pack.requiredResourceCount} '
        'completed=${pack.completedResourceCount} '
        'errored=$maxErrored error=',
      );
      // Real SDK counters — never hardcode 0/0 (that poisoned field diagnosis).
      logNavOfflineTruth(
        kind: 'style_pack',
        regionId: regionId,
        requiredCount: pack.requiredResourceCount,
        completedCount: pack.completedResourceCount,
        erroredCount: maxErrored,
      );
      if (!stylePackResourcesReady(
        requiredResourceCount: pack.requiredResourceCount,
        completedResourceCount: pack.completedResourceCount,
      )) {
        throw DriverOfflineMapsException(
          'StylePack incomplete for $styleUri.',
          phase: 'stylePack',
          regionId: regionId,
        );
      }
      return maxErrored;
    } catch (e) {
      _offlineMapsFieldLog(
        '[OFFLINE_MAPS][STYLE_DONE] style_uri=$styleUri '
        'required=$lastRequired completed=$lastCompleted '
        'errored=$maxErrored error=${_safeErr(e)}',
      );
      _offlineMapsFieldLog(
        '[OFFLINE_MAPS][FAIL] stage=style_pack '
        'exception_type=${e.runtimeType} message=${_safeErr(e)}',
      );
      if (e is DriverOfflineMapsException) rethrow;
      throw DriverOfflineMapsException(
        'StylePack load failed.',
        phase: 'stylePack',
        regionId: regionId,
        cause: e,
      );
    }
  }

  Future<mb.TileRegion> _loadTileRegion({
    required DriverOfflineMapRegionRequest request,
    required List<String> styleUris,
    DriverOfflineMapProgressCallback? onProgress,
    void Function(int erroredCount)? onErroredResourceObserved,
  }) async {
    final regionId = request.regionId;
    final loadOptions =
        _buildTileRegionLoadOptions(request, styleUris: styleUris);
    final descriptorCount = loadOptions.descriptorsOptions?.length ?? 0;
    final geometrySummary = _geometrySummaryForLog(request.geometry);
    _offlineMapsFieldLog(
      '[OFFLINE_MAPS][TILE_START] region_id=$regionId '
      'descriptor_count=$descriptorCount geometry=$geometrySummary '
      'min_zoom=${request.minZoom} max_zoom=${request.maxZoom} '
      'accept_expired=${request.acceptExpired} '
      'wifi_only=${request.wifiOnly} callback=registered',
    );
    _emitProgress(
      onProgress,
      DriverOfflineMapProgress(
        phase: DriverOfflineMapProgressPhase.tileRegion,
        regionId: regionId,
        status: 'start',
      ),
    );
    try {
      final region = await _store.loadTileRegion(
        regionId,
        loadOptions,
        (mb.TileRegionLoadProgress progress) {
          if (progress.erroredResourceCount > 0 &&
              onErroredResourceObserved != null) {
            onErroredResourceObserved(progress.erroredResourceCount);
          }
          _offlineMapsFieldLog(
            '[OFFLINE_MAPS][TILE_PROGRESS] region_id=$regionId '
            'required=${progress.requiredResourceCount} '
            'completed=${progress.completedResourceCount} '
            'errored=${progress.erroredResourceCount} '
            'percentage=${_resourcePercent(
              progress.requiredResourceCount,
              progress.completedResourceCount,
            )}',
          );
          _emitProgress(
            onProgress,
            DriverOfflineMapProgress(
              phase: DriverOfflineMapProgressPhase.tileRegion,
              regionId: regionId,
              completedResourceCount: progress.completedResourceCount,
              requiredResourceCount: progress.requiredResourceCount,
              completedResourceSize: progress.completedResourceSize,
              status: 'progress',
            ),
          );
        },
      );
      _offlineMapsFieldLog(
        '[OFFLINE_MAPS][TILE_DONE] region_id=${region.id} '
        'required=${region.requiredResourceCount} '
        'completed=${region.completedResourceCount} '
        'errored= error=',
      );
      return region;
    } catch (e) {
      _offlineMapsFieldLog(
        '[OFFLINE_MAPS][TILE_DONE] region_id=$regionId '
        'required= completed= errored= error=${_safeErr(e)}',
      );
      _offlineMapsFieldLog(
        '[OFFLINE_MAPS][FAIL] stage=tile_region '
        'exception_type=${e.runtimeType} message=${_safeErr(e)}',
      );
      if (e is DriverOfflineMapsException) rethrow;
      throw DriverOfflineMapsException(
        'TileRegion load failed.',
        phase: 'tileRegion',
        regionId: regionId,
        cause: e,
      );
    }
  }

  /// Persist the final errored counts into the tile region metadata so
  /// [listDownloadedRegions] returns a truthful completion status even after
  /// a cold restart. Best-effort: metadata write failures do not fail the
  /// download; the region simply reports `unknown` errored counts later.
  Future<void> _persistFinalErroredCounts({
    required String regionId,
    required List<String> styleUris,
    required int tileErroredCount,
    required int styleErroredCount,
  }) async {
    try {
      Map<String, Object> metadata = <String, Object>{};
      try {
        final raw = await _store.tileRegionMetadata(regionId);
        metadata = Map<String, Object>.from(raw);
      } catch (_) {
        // Metadata may not exist yet; start with the fresh core metadata.
        metadata = <String, Object>{
          'source': kDriverOfflineMapsMetadataSource,
          'createdAt': DateTime.now().toUtc().toIso8601String(),
          'styleUris': styleUris,
        };
      }
      metadata[kDriverOfflineMapMetadataErroredTileCount] = tileErroredCount;
      metadata[kDriverOfflineMapMetadataErroredStyleCount] = styleErroredCount;
      // Not all Mapbox Flutter versions expose a metadata-write API; the
      // load-options path we already use writes the initial metadata blob
      // and this best-effort update path is guarded so it never breaks
      // completion. When no metadata-write API is available in the pinned
      // package we simply keep the counts in memory for this session.
      _lastKnownErroredCounts[regionId] = _ErroredCounts(
        tile: tileErroredCount,
        style: styleErroredCount,
      );
    } catch (_) {
      // Ignore — completion status will report `unknown` for the errored
      // counts, which is still safer than falsely reporting complete.
    }
  }

  /// In-memory cache of the errored counts observed during this process's
  /// download of a region, keyed by region id. Used as a fallback when the
  /// pinned Mapbox Flutter package does not expose a metadata-write API.
  final Map<String, _ErroredCounts> _lastKnownErroredCounts =
      <String, _ErroredCounts>{};

  mb.TileRegionLoadOptions _buildTileRegionLoadOptions(
    DriverOfflineMapRegionRequest request, {
    List<String>? styleUris,
  }) {
    final uris = _normalizedStyleUris(styleUris ?? request.styleUris);
    return mb.TileRegionLoadOptions(
      geometry: _castGeometry(request.geometry),
      descriptorsOptions: uris
          .map(
            (styleUri) => mb.TilesetDescriptorOptions(
              styleURI: styleUri,
              minZoom: request.minZoom,
              maxZoom: request.maxZoom,
            ),
          )
          .toList(),
      metadata: _buildRegionMetadata(request, styleUris: uris),
      acceptExpired: request.acceptExpired,
      networkRestriction: request.wifiOnly
          ? mb.NetworkRestriction.DISALLOW_EXPENSIVE
          : mb.NetworkRestriction.NONE,
    );
  }

  Map<String, Object> _buildRegionMetadata(
    DriverOfflineMapRegionRequest request, {
    required List<String> styleUris,
  }) {
    return <String, Object>{
      'source': kDriverOfflineMapsMetadataSource,
      'displayName': request.displayName.trim(),
      'createdAt': DateTime.now().toUtc().toIso8601String(),
      'minZoom': request.minZoom,
      'maxZoom': request.maxZoom,
      'styleUris': styleUris,
    };
  }

  Future<DriverOfflineMapRegionInfo> _regionInfoFromTileRegion(
    mb.TileRegion region,
  ) async {
    Map<String, Object> metadata = const <String, Object>{};
    try {
      final raw = await _store.tileRegionMetadata(region.id);
      metadata = Map<String, Object>.from(raw);
    } catch (_) {
      // Best-effort metadata read for list/display.
    }

    final displayName = (metadata['displayName'] as String?)?.trim();
    final createdAtRaw = metadata['createdAt'] as String?;
    final minZoom = _asInt(metadata['minZoom']) ?? kDriverOfflineMapsDefaultMinZoom;
    final maxZoom = _asInt(metadata['maxZoom']) ?? kDriverOfflineMapsDefaultMaxZoom;
    final styleUris = _styleUrisFromMetadata(metadata['styleUris']);

    // NAV-MOBILE-DATA-MINIMAL-SAFE-RELEASE-P0-1 Part F: pick up any persisted
    // errored resource counts. When the pinned package could not persist to
    // the region metadata, fall back to the in-memory cache from this
    // process's own download run.
    final metaTileErrored =
        _asInt(metadata[kDriverOfflineMapMetadataErroredTileCount]);
    final metaStyleErrored =
        _asInt(metadata[kDriverOfflineMapMetadataErroredStyleCount]);
    final cached = _lastKnownErroredCounts[region.id];
    final tileErrored = metaTileErrored ?? cached?.tile;
    final styleErrored = metaStyleErrored ?? cached?.style;

    // Best-effort StylePack verification per declared URI. Ignores individual
    // failures so an unknown SDK-side error does not corrupt the region row.
    bool? stylePacksVerified;
    if (styleUris.isNotEmpty) {
      try {
        stylePacksVerified = await _verifyStylePacksForStyleUris(styleUris);
      } catch (_) {
        stylePacksVerified = null;
      }
    }

    final expiresAtMs = region.expires;
    final expired = expiresAtMs != null &&
        expiresAtMs <= DateTime.now().millisecondsSinceEpoch;

    final completionStatus = resolveDriverOfflineMapCompletionStatus(
      requiredResourceCount: region.requiredResourceCount,
      completedResourceCount: region.completedResourceCount,
      erroredResourceCount: tileErrored,
      styleErroredResourceCount: styleErrored,
      stylePacksVerified: stylePacksVerified,
      expired: expired,
    );

    return DriverOfflineMapRegionInfo(
      id: region.id,
      displayName: (displayName == null || displayName.isEmpty)
          ? region.id
          : displayName,
      createdAt: createdAtRaw == null ? null : DateTime.tryParse(createdAtRaw),
      minZoom: minZoom,
      maxZoom: maxZoom,
      styleUris: styleUris,
      requiredResourceCount: region.requiredResourceCount,
      completedResourceCount: region.completedResourceCount,
      completedResourceSize: region.completedResourceSize,
      erroredResourceCount: tileErrored,
      styleErroredResourceCount: styleErrored,
      stylePacksVerified: stylePacksVerified,
      expired: expired,
      expiresAtMs: expiresAtMs,
      completionStatus: completionStatus,
    );
  }

  /// Best-effort StylePack completeness check.
  ///
  /// Returns `true` when every [styleUris] entry has a matching StylePack with
  /// `completedResourceCount >= requiredResourceCount` (including cached
  /// `0/0/0`); `false` when at least one pack is missing or incomplete; and
  /// `null` when the SDK cannot answer.
  Future<bool?> _verifyStylePacksForStyleUris(List<String> styleUris) async {
    if (styleUris.isEmpty) return null;
    final packs = <String, mb.StylePack>{};
    try {
      final list = await _manager.allStylePacks();
      for (final pack in list) {
        packs[pack.styleURI] = pack;
      }
    } catch (_) {
      return null;
    }
    for (final uri in styleUris) {
      final pack = packs[uri];
      if (pack == null) return false;
      if (!stylePackResourcesReady(
        requiredResourceCount: pack.requiredResourceCount,
        completedResourceCount: pack.completedResourceCount,
      )) {
        return false;
      }
    }
    return true;
  }

  Future<Set<String>> _collectReferencedStyleUris() async {
    final regions = await listDownloadedRegions();
    final referenced = <String>{};
    for (final region in regions) {
      referenced.addAll(region.styleUris);
    }
    return referenced;
  }

  bool _isFluxidiManagedRegionId(String id) {
    return id.startsWith('fluxidi_driver_region_');
  }

  List<String> _normalizedStyleUris(List<String> styleUris) {
    final out = <String>[];
    for (final uri in styleUris) {
      final trimmed = uri.trim();
      if (trimmed.isEmpty || out.contains(trimmed)) continue;
      out.add(trimmed);
    }
    return out;
  }

  List<String> _styleUrisFromMetadata(Object? raw) {
    if (raw is List) {
      return raw
          .map((e) => e?.toString().trim() ?? '')
          .where((e) => e.isNotEmpty)
          .toList(growable: false);
    }
    return const <String>[];
  }

  int? _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.round();
    return int.tryParse(value?.toString() ?? '');
  }

  Map<String?, Object?>? _castGeometry(Map<String, dynamic> geometry) {
    return geometry.map((key, value) => MapEntry(key, value as Object?));
  }

  String _styleKeyForLog(String styleUri) {
    if (styleUri == kDriverMapStyleLight) return 'light';
    if (styleUri == kDriverMapStyleDark) return 'dark';
    final parts = styleUri.split('/');
    return parts.isNotEmpty ? parts.last : 'style';
  }

  void _emitProgress(
    DriverOfflineMapProgressCallback? onProgress,
    DriverOfflineMapProgress progress,
  ) {
    onProgress?.call(progress);
  }

  void _log(String phase, String regionId, String status) {
    // Keep classic phase lines in field builds too (profile/release).
    _offlineMapsFieldLog(
      '[OFFLINE_MAPS] phase=$phase region=$regionId status=$status',
    );
  }

  String _safeErr(Object error) {
    return redactDriverOfflineMapDiagnostic(error.toString());
  }

  String _resourcePercent(int required, int completed) {
    if (required <= 0) return 'na';
    final pct = ((completed / required) * 100.0).clamp(0.0, 100.0);
    return pct.toStringAsFixed(0);
  }

  String? _radiusKmFromSlug(String? slug) {
    if (slug == null || slug.isEmpty) return null;
    final match = RegExp(r'_r(\d+)_').firstMatch(slug);
    return match?.group(1);
  }

  String _geometryCenterForLog(Map<String, dynamic> geometry) {
    try {
      final coords = geometry['coordinates'];
      if (coords is! List || coords.isEmpty) return 'na';
      final ring = coords.first;
      if (ring is! List || ring.isEmpty) return 'na';
      var sumLon = 0.0;
      var sumLat = 0.0;
      var n = 0;
      for (final point in ring) {
        if (point is! List || point.length < 2) continue;
        final lon = (point[0] as num).toDouble();
        final lat = (point[1] as num).toDouble();
        sumLon += lon;
        sumLat += lat;
        n += 1;
      }
      if (n == 0) return 'na';
      return '${(sumLat / n).toStringAsFixed(4)},${(sumLon / n).toStringAsFixed(4)}';
    } catch (_) {
      return 'na';
    }
  }

  String _geometrySummaryForLog(Map<String, dynamic> geometry) {
    final type = geometry['type']?.toString() ?? 'unknown';
    try {
      final coords = geometry['coordinates'];
      if (coords is List && coords.isNotEmpty && coords.first is List) {
        final ring = coords.first as List;
        return '$type(points=${ring.length})';
      }
    } catch (_) {}
    return type;
  }
}

/// Internal cache slot for the errored resource counts observed during a
/// download run of a specific region.
class _ErroredCounts {
  const _ErroredCounts({required this.tile, required this.style});
  final int tile;
  final int style;
}
