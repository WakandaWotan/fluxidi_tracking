import 'package:flutter/foundation.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mb;

import 'driver_navigation_map_config.dart';

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
  final bool isComplete;

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
    required this.isComplete,
  });
}

/// Storage / transfer estimate for a region download.
///
/// Values come from [mb.TileRegionEstimateResult]. They are statistical estimates
/// (99.9% confidence band via [errorMargin]), not exact byte counts until download
/// completes.
class DriverOfflineMapEstimate {
  final int transferSizeBytes;
  final int storageSizeBytes;
  final double errorMargin;

  const DriverOfflineMapEstimate({
    required this.transferSizeBytes,
    required this.storageSizeBytes,
    required this.errorMargin,
  });

  factory DriverOfflineMapEstimate.fromSdk(mb.TileRegionEstimateResult result) {
    return DriverOfflineMapEstimate(
      transferSizeBytes: result.transferSize,
      storageSizeBytes: result.storageSize,
      errorMargin: result.errorMargin,
    );
  }
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

/// Wraps Mapbox [mb.OfflineManager] and [mb.TileStore] for driver offline basemaps.
class DriverOfflineMapsService {
  DriverOfflineMapsService._();

  static final DriverOfflineMapsService shared = DriverOfflineMapsService._();

  mb.OfflineManager? _offlineManager;
  mb.TileStore? _tileStore;
  Future<void>? _initFuture;

  /// Lazily creates Mapbox offline manager and default tile store.
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
      final result = await _store.estimateTileRegion(
        regionId,
        loadOptions,
        mb.TileRegionEstimateOptions(
          errorMargin: 0.15,
          preciseEstimationTimeout: 5,
          timeout: 30,
        ),
        onProgress == null
            ? null
            : (mb.TileRegionEstimateProgress progress) {
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
      _emitProgress(
        onProgress,
        DriverOfflineMapProgress(
          phase: DriverOfflineMapProgressPhase.estimate,
          regionId: regionId,
          status: 'done',
          message: 'estimate_complete',
        ),
      );
      return DriverOfflineMapEstimate.fromSdk(result);
    } catch (e) {
      _log('estimate', regionId, 'fail');
      throw DriverOfflineMapsException(
        'Could not estimate offline map region.',
        phase: 'estimate',
        regionId: regionId,
        cause: e,
      );
    }
  }

  /// Downloads style packs and tile region for [request].
  ///
  /// Loads one style pack per entry in [DriverOfflineMapRegionRequest.styleUris],
  /// then loads a single tile region with matching descriptors.
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

    try {
      for (final styleUri in styleUris) {
        await _loadStylePack(
          styleUri: styleUri,
          regionId: regionId,
          acceptExpired: request.acceptExpired,
          onProgress: onProgress,
        );
      }

      final tileRegion = await _loadTileRegion(
        request: request,
        styleUris: styleUris,
        onProgress: onProgress,
      );
      _log('download', regionId, 'done');
      final info = await _regionInfoFromTileRegion(tileRegion);
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
  Future<List<DriverOfflineMapRegionInfo>> listDownloadedRegions() async {
    await ensureInitialized();
    try {
      final regions = await _store.allTileRegions();
      final out = <DriverOfflineMapRegionInfo>[];
      for (final region in regions) {
        if (!_isFluxidiManagedRegionId(region.id)) continue;
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

  Future<void> _loadStylePack({
    required String styleUri,
    required String regionId,
    required bool acceptExpired,
    DriverOfflineMapProgressCallback? onProgress,
  }) async {
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
    await _manager.loadStylePack(
      styleUri,
      options,
      (mb.StylePackLoadProgress progress) {
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
  }

  Future<mb.TileRegion> _loadTileRegion({
    required DriverOfflineMapRegionRequest request,
    required List<String> styleUris,
    DriverOfflineMapProgressCallback? onProgress,
  }) async {
    final regionId = request.regionId;
    _emitProgress(
      onProgress,
      DriverOfflineMapProgress(
        phase: DriverOfflineMapProgressPhase.tileRegion,
        regionId: regionId,
        status: 'start',
      ),
    );
    final loadOptions = _buildTileRegionLoadOptions(request, styleUris: styleUris);
    return _store.loadTileRegion(
      regionId,
      loadOptions,
      (mb.TileRegionLoadProgress progress) {
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
  }

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
      isComplete:
          region.requiredResourceCount > 0 &&
          region.completedResourceCount >= region.requiredResourceCount,
    );
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
    if (!kDebugMode) return;
    debugPrint('[OFFLINE_MAPS] phase=$phase region=$regionId status=$status');
  }
}
