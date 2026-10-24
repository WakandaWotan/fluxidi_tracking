import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:maplibre_gl/maplibre_gl.dart' as ml;
import '../maps/fluxidi_map_source_config.dart';
import 'driver_offline_maps_service.dart';
import 'driver_offline_maps_preview_model.dart';
import 'driver_offline_maps_tile_quota.dart';

const kFluxidiOfflineSource = 'fluxidi_driver_offline_maplibre_v1';
const kFluxidiOfflineResourceLimit = 50000;
const _release = 'be-nl-20261013-rectangle-v1';

/// Own native SDK storage only. Existing Mapbox TileStore packs are never
/// adopted, listed as complete, deleted, or passed to a MapLibre surface.
class DriverMapLibreOfflineMapsService
    implements DriverOfflineMapsDownloadPort {
  DriverMapLibreOfflineMapsService();
  static final shared = DriverMapLibreOfflineMapsService();
  static const _channel = MethodChannel('fluxidi/offline_maps');
  bool _initialized = false, _downloading = false;
  String? _activeKey;
  DriverOfflineMapProgressCallback? _progress;

  @override
  Future<void> ensureInitialized() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      throw const DriverOfflineMapsException(
        'Own offline downloads require Android.',
        phase: 'init',
      );
    }
    if (_initialized) return;
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'progress' || call.arguments is! Map) return;
      final value = call.arguments as Map;
      if (value['logical_key'] != _activeKey) return;
      _progress?.call(
        DriverOfflineMapProgress(
          phase: DriverOfflineMapProgressPhase.tileRegion,
          regionId: _activeKey!,
          completedResourceCount: (value['completed'] as num?)?.toInt(),
          requiredResourceCount: (value['required'] as num?)?.toInt(),
          completedResourceSize: (value['bytes'] as num?)?.toInt(),
        ),
      );
    });
    _initialized = true;
  }

  Map<String, dynamic> _definition(DriverOfflineMapRegionRequest request) {
    final bounds = driverOfflineMapPreviewBoundsFromGeometry(request.geometry);
    if (bounds == null ||
        bounds.westLon < 2 ||
        bounds.eastLon > 7.8 ||
        bounds.southLat < 49.1 ||
        bounds.northLat > 54 ||
        request.minZoom < 0 ||
        request.maxZoom > 16 ||
        request.minZoom > request.maxZoom) {
      throw const DriverOfflineMapsException(
        'The region falls outside the published BE/NL map coverage.',
        phase: 'configuration',
      );
    }
    return {
      'west': bounds.westLon,
      'south': bounds.southLat,
      'east': bounds.eastLon,
      'north': bounds.northLat,
      'minZoom': request.minZoom,
      'maxZoom': request.maxZoom,
    };
  }

  List<String> _styles(DriverOfflineMapRegionRequest request) {
    final base = fluxidiMapAssetBase(
      const String.fromEnvironment(
        'FLUXIDI_MAP_ASSET_BASE_URL',
        defaultValue: '',
      ),
    );
    final styles = <String>{};
    for (final style in request.styleUris) {
      if (![
        'fluxidi-maplibre://light',
        'fluxidi-maplibre://dark',
      ].contains(style)) {
        throw const DriverOfflineMapsException(
          'Own offline map style required.',
          phase: 'configuration',
        );
      }
      styles.add(
        '$base/data/full/style-${style.endsWith('dark') ? 'dark' : 'light'}.json',
      );
    }
    if (styles.isEmpty || styles.length > 2)
      throw const DriverOfflineMapsException(
        'Own map styles missing.',
        phase: 'configuration',
      );
    return styles.toList();
  }

  Future<List<ml.OfflineRegion>> _ownRegions() async {
    await ensureInitialized();
    return (await ml.getListOfRegions())
        .where((r) => r.metadata['source'] == kFluxidiOfflineSource)
        .toList();
  }

  @override
  Future<DriverOfflineMapEstimate> estimateRegion(
    DriverOfflineMapRegionRequest request, {
    DriverOfflineMapProgressCallback? onProgress,
  }) async {
    _definition(request);
    _styles(request);
    // The native MapLibre API has no transfer-size estimator. Preserve the
    // existing explicit "estimate unavailable" confirmation; zero is not an
    // invented download size and old Mapbox pack counts cannot be reused.
    throw const DriverOfflineMapsException(
      'Size estimate unavailable for this own map download.',
      phase: 'estimate',
    );
  }

  @override
  Future<DriverOfflineMapsTileCapacity> readTileCapacity({
    String? excludeRegionId,
  }) async {
    var used = 0;
    for (final region in await _ownRegions()) {
      if (region.metadata['region_id'] == excludeRegionId) continue;
      final status = await ml.getOfflineRegionStatus(region.id);
      used += status.completedResourceCount > status.requiredResourceCount
          ? status.completedResourceCount
          : status.requiredResourceCount;
    }
    return DriverOfflineMapsTileCapacity(
      usedMapsTiles: used,
      limitMapsTiles: kFluxidiOfflineResourceLimit,
    );
  }

  @override
  Future<DriverOfflineMapPreflight> preflightRegion(
    DriverOfflineMapRegionRequest request, {
    DriverOfflineMapProgressCallback? onProgress,
  }) async {
    await ensureInitialized();
    await readTileCapacity(excludeRegionId: request.regionId);
    // Let the existing UI display unavailable estimation before explicit
    // confirmation. Native resource and Wi-Fi checks still precede downloads.
    await estimateRegion(request, onProgress: onProgress);
    throw const DriverOfflineMapsException(
      'Size estimate unavailable.',
      phase: 'estimate',
    );
  }

  @override
  Future<DriverOfflineMapRegionInfo> downloadRegion(
    DriverOfflineMapRegionRequest request, {
    DriverOfflineMapProgressCallback? onProgress,
  }) async {
    if (_downloading)
      throw const DriverOfflineMapsException(
        'An offline download is already active.',
        phase: 'download',
      );
    _downloading = true;
    _progress = onProgress;
    try {
      final definition = _definition(request), styles = _styles(request);
      await ensureInitialized();
      final capacity = await readTileCapacity(
        excludeRegionId: request.regionId,
      );
      var remaining = capacity.availableMapsTiles;
      final groupKey = sha256
          .convert(
            utf8.encode(jsonEncode([request.regionId, definition, styles])),
          )
          .toString();
      for (final style in styles) {
        if (remaining <= 0)
          throw const DriverOfflineMapsException(
            'Offline map resource limit reached.',
            phase: 'quota',
          );
        final key = sha256
            .convert(utf8.encode(jsonEncode([groupKey, style])))
            .toString();
        _activeKey = key;
        final metadata = {
          'source': kFluxidiOfflineSource,
          'logical_key': key,
          'group_key': groupKey,
          'map_release': _release,
          'region_id': request.regionId,
          'displayName': request.displayName.trim(),
          'createdAt': DateTime.now().toUtc().toIso8601String(),
          'styleUris': styles,
          'geometry': request.geometry,
          'minZoom': request.minZoom,
          'maxZoom': request.maxZoom,
        };
        final result = await _channel
            .invokeMapMethod<String, dynamic>('download', {
              ...definition,
              'style': style,
              'logical_key': key,
              'wifiOnly': request.wifiOnly,
              'remainingResources': remaining,
              'metadata': metadata,
            });
        if (result?['complete'] != true || result?['id'] is! num)
          throw const DriverOfflineMapsException(
            'Offline completion not confirmed.',
            phase: 'download',
          );
        final status = await ml.getOfflineRegionStatus(
          (result!['id'] as num).toInt(),
        );
        if (!status.isComplete ||
            status.requiredResourceCount <= 0 ||
            status.completedResourceCount < status.requiredResourceCount) {
          throw const DriverOfflineMapsException(
            'Offline resources are incomplete.',
            phase: 'verify',
          );
        }
        remaining -= status.completedResourceCount;
      }
      final regions = await listDownloadedRegions();
      final result = regions.where((r) => r.id == request.regionId).firstOrNull;
      if (result == null || !result.isComplete)
        throw const DriverOfflineMapsException(
          'Both own map styles must be verified.',
          phase: 'verify',
        );
      return result;
    } finally {
      _activeKey = null;
      _progress = null;
      _downloading = false;
    }
  }

  @override
  Future<List<DriverOfflineMapRegionInfo>> listDownloadedRegions() async {
    final groups = <String, List<ml.OfflineRegion>>{};
    for (final region in await _ownRegions()) {
      final id = region.metadata['region_id'];
      if (id is! String || id.isEmpty) continue;
      groups.putIfAbsent(id, () => []).add(region);
    }
    final results = <DriverOfflineMapRegionInfo>[];
    for (final entry in groups.entries) {
      final rows = entry.value, meta = rows.last.metadata;
      final group = meta['group_key'];
      final same = rows.where((r) => r.metadata['group_key'] == group).toList();
      final expected =
          (meta['styleUris'] as List?)?.whereType<String>().toList() ??
          <String>[];
      var required = 0, completed = 0, bytes = 0;
      var complete =
          expected.isNotEmpty &&
          expected.every(
            (style) => same.any((r) => r.definition.mapStyleUrl == style),
          );
      for (final region in same) {
        final status = await ml.getOfflineRegionStatus(region.id);
        required += status.requiredResourceCount;
        completed += status.completedResourceCount;
        bytes += status.completedResourceSize;
        complete =
            complete &&
            status.isComplete &&
            status.requiredResourceCount > 0 &&
            status.completedResourceCount >= status.requiredResourceCount;
      }
      final expired = meta['map_release'] != _release;
      results.add(
        DriverOfflineMapRegionInfo(
          id: entry.key,
          displayName: meta['displayName'] as String? ?? entry.key,
          createdAt: DateTime.tryParse(meta['createdAt'] as String? ?? ''),
          minZoom: (meta['minZoom'] as num?)?.toInt() ?? 0,
          maxZoom: (meta['maxZoom'] as num?)?.toInt() ?? 0,
          styleUris: expected,
          requiredResourceCount: required,
          completedResourceCount: completed,
          completedResourceSize: bytes,
          completionStatus: expired
              ? DriverOfflineMapCompletionStatus.expiredOrStale
              : complete
              ? DriverOfflineMapCompletionStatus.complete
              : DriverOfflineMapCompletionStatus.incomplete,
          // Exact current native status is the proof, rather than legacy style
          // error counters. No inferred road, route, or offline-navigation proof.
          stylePacksVerified: complete,
          expired: expired,
          geometry: meta['geometry'] is Map
              ? Map<String, dynamic>.from(meta['geometry'] as Map)
              : null,
        ),
      );
    }
    return results;
  }

  @override
  Future<void> deleteRegion(
    String regionId, {
    DriverOfflineMapProgressCallback? onProgress,
  }) async {
    if (_downloading)
      throw const DriverOfflineMapsException(
        'Wait for the active offline download.',
        phase: 'delete',
      );
    for (final region in await _ownRegions()) {
      if (region.metadata['region_id'] == regionId)
        await ml.deleteOfflineRegion(region.id);
    }
  }
}
