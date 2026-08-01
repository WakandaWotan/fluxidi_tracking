import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:fluxidi_tracking/app_config.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/driver_theme_palette.dart';
import 'package:fluxidi_tracking/driver_theme_store.dart';

import 'driver_offline_maps_service.dart';
import 'nav_backend/driver_navigation_worker_client.dart';

// Future: OFFLINE-C2 download current visible map area from DriverHomePage.
// Future: OFFLINE-C3 airport presets (Zaventem, Charleroi, Schiphol).
// Future: OFFLINE-D active route cache / degraded mode when network is lost.

enum DriverOfflineMapPresetType { overview, detail }

/// Offline basemap download preset (tiles only — not full navigation).
class DriverOfflineMapPreset {
  final String slug;
  final String displayNameNl;
  final String displayNameEn;
  final String descriptionNl;
  final String descriptionEn;
  final Map<String, dynamic> geometry;
  final int minZoom;
  final int maxZoom;
  final DriverOfflineMapPresetType type;

  const DriverOfflineMapPreset({
    required this.slug,
    required this.displayNameNl,
    required this.displayNameEn,
    required this.descriptionNl,
    required this.descriptionEn,
    required this.geometry,
    required this.minZoom,
    required this.maxZoom,
    required this.type,
  });

  String localizedDisplayName(String Function({required String nl, required String en}) tr) {
    return tr(nl: displayNameNl, en: displayNameEn);
  }

  String localizedDescription(String Function({required String nl, required String en}) tr) {
    return tr(nl: descriptionNl, en: descriptionEn);
  }
}

Map<String, dynamic> driverOfflineMapBboxGeometry({
  required double westLon,
  required double southLat,
  required double eastLon,
  required double northLat,
}) {
  return <String, dynamic>{
    'type': 'Polygon',
    'coordinates': <List<List<double>>>[
      <List<double>>[
        <double>[westLon, southLat],
        <double>[eastLon, southLat],
        <double>[eastLon, northLat],
        <double>[westLon, northLat],
        <double>[westLon, southLat],
      ],
    ],
  };
}

/// Presets shown in the Offline kaarten UI.
List<DriverOfflineMapPreset> driverOfflineMapVisiblePresets() {
  return const <DriverOfflineMapPreset>[
    DriverOfflineMapPreset(
      slug: 'belgium_base',
      displayNameNl: 'België basiskaart',
      displayNameEn: 'Belgium base map',
      descriptionNl:
          'Overzichtskaart voor België. Beperkt detail, lager opslaggebruik.',
      descriptionEn:
          'Overview map for Belgium. Limited detail, lower storage use.',
      geometry: <String, dynamic>{
        'type': 'Polygon',
        'coordinates': <List<List<double>>>[
          <List<double>>[
            <double>[2.50, 49.45],
            <double>[6.45, 49.45],
            <double>[6.45, 51.55],
            <double>[2.50, 51.55],
            <double>[2.50, 49.45],
          ],
        ],
      },
      minZoom: 6,
      maxZoom: 10,
      type: DriverOfflineMapPresetType.overview,
    ),
    DriverOfflineMapPreset(
      slug: 'maarkedal_vlaamse_ardennen',
      displayNameNl: 'Maarkedal / Vlaamse Ardennen detail',
      displayNameEn: 'Maarkedal / Flemish Ardennes detail',
      descriptionNl:
          'Straatdetail voor Maarkedal, Oudenaarde, Ronse en omgeving.',
      descriptionEn:
          'Street detail for Maarkedal, Oudenaarde, Ronse and nearby area.',
      geometry: <String, dynamic>{
        'type': 'Polygon',
        'coordinates': <List<List<double>>>[
          <List<double>>[
            <double>[3.45, 50.70],
            <double>[3.85, 50.70],
            <double>[3.85, 50.90],
            <double>[3.45, 50.90],
            <double>[3.45, 50.70],
          ],
        ],
      },
      minZoom: 11,
      maxZoom: 16,
      type: DriverOfflineMapPresetType.detail,
    ),
  ];
}

/// Hidden QA preset — not shown in the main UI.
@visibleForTesting
DriverOfflineMapPreset driverOfflineMapBrusselsTestPreset() {
  return DriverOfflineMapPreset(
    slug: 'brussels_test',
    displayNameNl: 'Brussel (test)',
    displayNameEn: 'Brussels (test)',
    descriptionNl: 'Interne testregio.',
    descriptionEn: 'Internal test region.',
    geometry: driverOfflineMapBboxGeometry(
      westLon: 4.30,
      southLat: 50.82,
      eastLon: 4.45,
      northLat: 50.90,
    ),
    minZoom: kDriverOfflineMapsDefaultMinZoom,
    maxZoom: kDriverOfflineMapsDefaultMaxZoom,
    type: DriverOfflineMapPresetType.detail,
  );
}

/// Chauffeur-facing offline basemap management (tiles only, not full navigation).
class DriverOfflineMapsPage extends StatefulWidget {
  const DriverOfflineMapsPage({
    super.key,
    this.themeListenable,
    this.routeCorridorMetadata,
  });

  final ValueListenable<DriverThemeVariant>? themeListenable;
  final NavigationWorkerOfflineCorridorMetadata? routeCorridorMetadata;

  @override
  State<DriverOfflineMapsPage> createState() => _DriverOfflineMapsPageState();
}

class _DriverOfflineMapsPageState extends State<DriverOfflineMapsPage> {
  final DriverOfflineMapsService _service = DriverOfflineMapsService.shared;

  List<DriverOfflineMapRegionInfo> _regions = const <DriverOfflineMapRegionInfo>[];
  bool _loadingList = true;
  bool _downloadInProgress = false;
  bool _estimateInProgress = false;
  DriverOfflineMapProgress? _downloadProgress;
  String? _inlineError;
  bool _wifiOnly = true;

  @override
  void initState() {
    super.initState();
    if (kDebugMode) {
      debugPrint('[OFFLINE_MAPS] ui=open');
    }
    _loadRegions();
  }

  String _tr({
    required String nl,
    required String en,
    String? fr,
    String? es,
  }) {
    switch (appConfig.currentLanguage) {
      case AppLanguage.fr:
        return fr ?? en;
      case AppLanguage.es:
        return es ?? en;
      case AppLanguage.nl:
        return nl;
      case AppLanguage.en:
        return en;
      case AppLanguage.de:
        return en;
    }
  }

  DriverOfflineMapRegionRequest _requestForPreset(DriverOfflineMapPreset preset) {
    return DriverOfflineMapRegionRequest(
      displayName: preset.localizedDisplayName(_tr),
      slug: preset.slug,
      geometry: preset.geometry,
      minZoom: preset.minZoom,
      maxZoom: preset.maxZoom,
      wifiOnly: _wifiOnly,
    );
  }

  Future<void> _loadRegions() async {
    setState(() {
      _loadingList = true;
      _inlineError = null;
    });
    try {
      await _service.ensureInitialized();
      final regions = await _service.listDownloadedRegions();
      if (!mounted) return;
      setState(() {
        _regions = regions;
        _loadingList = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadingList = false;
        _inlineError = _tr(
          nl: 'Kon gedownloade kaarttegels niet laden.',
          en: 'Could not load downloaded map tiles.',
        );
      });
    }
  }

  Future<void> _onPresetSelected(DriverOfflineMapPreset preset) async {
    if (_downloadInProgress || _estimateInProgress) return;
    if (kDebugMode) {
      debugPrint('[OFFLINE_MAPS] ui=preset_selected preset=${preset.slug}');
    }

    setState(() => _estimateInProgress = true);
    DriverOfflineMapEstimate? estimate;
    var estimateFailed = false;
    try {
      await _service.ensureInitialized();
      estimate = await _service.estimateRegion(_requestForPreset(preset));
      if (kDebugMode) {
        debugPrint('[OFFLINE_MAPS] ui=estimate_done preset=${preset.slug}');
      }
    } catch (_) {
      estimateFailed = true;
    } finally {
      if (mounted) setState(() => _estimateInProgress = false);
    }

    if (!mounted) return;
    final proceed = await _showDownloadConfirmDialog(
      preset: preset,
      estimate: estimate,
      estimateFailed: estimateFailed,
    );
    if (proceed == true && mounted) {
      await _startDownload(preset);
    }
  }

  Future<bool?> _showDownloadConfirmDialog({
    required DriverOfflineMapPreset preset,
    required DriverOfflineMapEstimate? estimate,
    required bool estimateFailed,
  }) {
    final estimateLines = <String>[];
    if (estimate != null) {
      estimateLines.add(
        _tr(
          nl:
              'Geschatte download: ${_formatBytes(estimate.transferSizeBytes)} · '
              'opslag: ${_formatBytes(estimate.storageSizeBytes)}',
          en:
              'Estimated download: ${_formatBytes(estimate.transferSizeBytes)} · '
              'storage: ${_formatBytes(estimate.storageSizeBytes)}',
        ),
      );
    } else if (estimateFailed) {
      estimateLines.add(
        _tr(
          nl: 'Grootte kon niet worden geschat. Download kan veel data gebruiken.',
          en: 'Could not estimate size. Download may use significant data.',
        ),
      );
    }

    return showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text(
            _tr(nl: 'Kaartgebied downloaden?', en: 'Download map area?'),
          ),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  preset.localizedDisplayName(_tr),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Text(preset.localizedDescription(_tr)),
                const SizedBox(height: 8),
                Text(
                  _tr(
                    nl: 'Zoom ${preset.minZoom}–${preset.maxZoom} · licht + donker kaartstijl',
                    en: 'Zoom ${preset.minZoom}–${preset.maxZoom} · light + dark map styles',
                  ),
                ),
                if (estimateLines.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(estimateLines.join('\n')),
                ],
                const SizedBox(height: 12),
                Text(
                  _tr(
                    nl:
                        'Gebruik bij voorkeur Wi‑Fi. Dit gebruikt opslag en mobiele data.\n\n'
                        'Dit houdt alleen de straatkaart zichtbaar bij zwak signaal. '
                        'Nieuwe routes en herberekenen hebben nog internet nodig.',
                    en:
                        'Wi‑Fi is recommended. This uses storage and mobile data.\n\n'
                        'This only keeps the street map visible when signal is weak. '
                        'New routes and recalculation still need internet.',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(_tr(nl: 'Annuleren', en: 'Cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(_tr(nl: 'Downloaden', en: 'Download')),
            ),
          ],
        );
      },
    );
  }

  Future<void> _startDownload(DriverOfflineMapPreset preset) async {
    if (_downloadInProgress) return;
    if (kDebugMode) {
      debugPrint('[OFFLINE_MAPS] ui=download_start preset=${preset.slug}');
    }

    setState(() {
      _downloadInProgress = true;
      _downloadProgress = null;
      _inlineError = null;
    });

    try {
      await _service.downloadRegion(
        _requestForPreset(preset),
        onProgress: (progress) {
          if (!mounted) return;
          setState(() => _downloadProgress = progress);
        },
      );
      if (!mounted) return;
      if (kDebugMode) {
        debugPrint('[OFFLINE_MAPS] ui=download_done preset=${preset.slug}');
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _tr(
              nl: 'Kaarttegels gedownload.',
              en: 'Map tiles downloaded.',
            ),
          ),
        ),
      );
      await _loadRegions();
    } catch (_) {
      if (!mounted) return;
      if (kDebugMode) {
        debugPrint('[OFFLINE_MAPS] ui=fail preset=${preset.slug}');
      }
      setState(() {
        _inlineError = _tr(
          nl: 'Download mislukt. Controleer internet en probeer opnieuw.',
          en: 'Download failed. Check your connection and try again.',
        );
      });
    } finally {
      if (mounted) {
        setState(() {
          _downloadInProgress = false;
          _downloadProgress = null;
        });
      }
    }
  }

  Future<void> _confirmAndDelete(DriverOfflineMapRegionInfo region) async {
    final proceed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text(_tr(nl: 'Regio verwijderen?', en: 'Delete region?')),
          content: Text(
            _tr(
              nl: '“${region.displayName}” van dit toestel verwijderen?',
              en: 'Remove “${region.displayName}” from this device?',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(_tr(nl: 'Annuleren', en: 'Cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(_tr(nl: 'Verwijderen', en: 'Delete')),
            ),
          ],
        );
      },
    );
    if (proceed != true || !mounted) return;

    try {
      await _service.deleteRegion(region.id);
      if (!mounted) return;
      if (kDebugMode) {
        debugPrint('[OFFLINE_MAPS] ui=delete_done');
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _tr(nl: 'Kaarttegels verwijderd.', en: 'Map tiles removed.'),
          ),
        ),
      );
      await _loadRegions();
    } catch (_) {
      if (!mounted) return;
      if (kDebugMode) {
        debugPrint('[OFFLINE_MAPS] ui=fail');
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _tr(
              nl: 'Verwijderen mislukt.',
              en: 'Could not delete region.',
            ),
          ),
        ),
      );
    }
  }

  String _phaseLabel(DriverOfflineMapProgressPhase phase) {
    switch (phase) {
      case DriverOfflineMapProgressPhase.stylePack:
        return _tr(nl: 'Kaartstijl', en: 'Style pack');
      case DriverOfflineMapProgressPhase.tileRegion:
        return _tr(nl: 'Kaarttegels', en: 'Map tiles');
      case DriverOfflineMapProgressPhase.estimate:
        return _tr(nl: 'Schatting', en: 'Estimate');
      case DriverOfflineMapProgressPhase.delete:
        return _tr(nl: 'Verwijderen', en: 'Delete');
    }
  }

  String _formatCreatedAt(DateTime? createdAt) {
    if (createdAt == null) return '—';
    final local = createdAt.toLocal();
    final y = local.year.toString().padLeft(4, '0');
    final m = local.month.toString().padLeft(2, '0');
    final d = local.day.toString().padLeft(2, '0');
    final h = local.hour.toString().padLeft(2, '0');
    final min = local.minute.toString().padLeft(2, '0');
    return '$y-$m-$d $h:$min';
  }

  Widget _buildRouteCorridorMetadataCard({
    required DriverThemePalette palette,
    required NavigationWorkerOfflineCorridorMetadata metadata,
  }) {
    final sizeRange =
        '${_formatBytes(metadata.estimatedSizeBytesMin)} - ${_formatBytes(metadata.estimatedSizeBytesMax)}';
    return _infoCard(
      palette: palette,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _tr(
              nl: 'Actieve route-corridor (voorbereiding)',
              en: 'Active route corridor (preparation)',
            ),
            style: TextStyle(
              color: palette.textPrimary,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _tr(
              nl:
                  'Geschat ${metadata.estimatedTileCountMin}-${metadata.estimatedTileCountMax} tegels · '
                  '$sizeRange · buffer ${metadata.corridorBufferMeters} m · '
                  'zoom ${metadata.zoomMin}-${metadata.zoomMax} · ${metadata.supportedStatus}',
              en:
                  'Estimated ${metadata.estimatedTileCountMin}-${metadata.estimatedTileCountMax} tiles · '
                  '$sizeRange · buffer ${metadata.corridorBufferMeters} m · '
                  'zoom ${metadata.zoomMin}-${metadata.zoomMax} · ${metadata.supportedStatus}',
            ),
            style: TextStyle(
              color: palette.textMuted,
              height: 1.35,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _tr(
              nl:
                  'Kaartweergave kan offline beschikbaar zijn. Routeberekening, '
                  'zoeken, verkeersinformatie en herberekenen vereisen momenteel internet.',
              en:
                  'Map display can be available offline. Route calculation, search, '
                  'traffic information and rerouting currently require internet.',
            ),
            style: TextStyle(
              color: palette.textMuted,
              fontSize: 12,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '—';
    final mb = bytes / (1024 * 1024);
    if (mb < 1) {
      return '${(bytes / 1024).toStringAsFixed(0)} KB';
    }
    if (mb >= 1024) {
      return '${(mb / 1024).toStringAsFixed(1)} GB';
    }
    return '${mb.toStringAsFixed(1)} MB';
  }

  /// NAV-MOBILE-DATA-MINIMAL-SAFE-RELEASE-P0-1 Part F: truthful status label.
  /// Distinguishes complete / completed-with-errors / incomplete / expired /
  /// unknown so the driver never sees a false "complete" claim over a region
  /// that failed resources or a StylePack that could not be verified.
  String _offlineRegionStatusText(
    DriverOfflineMapRegionInfo region, {
    required bool nl,
  }) {
    switch (region.completionStatus) {
      case DriverOfflineMapCompletionStatus.complete:
        return nl ? 'Volledig' : 'Complete';
      case DriverOfflineMapCompletionStatus.completedWithErrors:
        return nl
            ? 'Ontladen met fouten (niet volledig)'
            : 'Downloaded with errors (not complete)';
      case DriverOfflineMapCompletionStatus.incomplete:
        return nl ? 'Bezig / onvolledig' : 'In progress / incomplete';
      case DriverOfflineMapCompletionStatus.expiredOrStale:
        return nl
            ? 'Verlopen — vernieuwen aanbevolen'
            : 'Expired — refresh recommended';
      case DriverOfflineMapCompletionStatus.unknown:
        return nl ? 'Status onbekend' : 'Status unknown';
    }
  }

  /// NAV-MOBILE-DATA-MINIMAL-SAFE-RELEASE-P0-1 Part F: show which navigation
  /// styles the region actually covers. Standard/Satellite are only listed as
  /// offline when their StylePack was proven downloaded — never assumed.
  String _offlineStyleCoverageText(
    DriverOfflineMapRegionInfo region, {
    required bool nl,
  }) {
    if (region.styleUris.isEmpty) {
      return nl ? 'geen' : 'none';
    }
    final labels = region.styleUris.map(_offlineStyleLabel).toList();
    final verified = region.stylePacksVerified;
    final suffix = verified == true
        ? (nl ? ' (geverifieerd)' : ' (verified)')
        : verified == false
            ? (nl ? ' (niet volledig)' : ' (not complete)')
            : (nl ? ' (niet geverifieerd)' : ' (not verified)');
    return '${labels.join(', ')}$suffix';
  }

  String _offlineStyleLabel(String styleUri) {
    // navigation-day-v1 / navigation-night-v1 are the only styles the driver
    // service currently downloads. Return a short bounded label; never leak
    // the raw URI.
    final trimmed = styleUri.trim();
    if (trimmed.contains('navigation-day')) return 'Navigatie (dag)';
    if (trimmed.contains('navigation-night')) return 'Navigatie (nacht)';
    if (trimmed.contains('satellite')) return 'Satelliet';
    if (trimmed.contains('standard')) return 'Standaard';
    if (trimmed.contains('streets')) return 'Straten';
    final parts = trimmed.split('/');
    return parts.isNotEmpty ? parts.last : 'style';
  }

  Widget _infoCard({
    required DriverThemePalette palette,
    required Widget child,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: palette.border.withOpacity(0.55)),
      ),
      child: child,
    );
  }

  Widget _presetCard({
    required DriverThemePalette palette,
    required DriverOfflineMapPreset preset,
    required bool busy,
  }) {
    final isOverview = preset.type == DriverOfflineMapPresetType.overview;
    return _infoCard(
      palette: palette,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                isOverview ? Icons.map_outlined : Icons.location_city_outlined,
                color: palette.accent,
                size: 22,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      preset.localizedDisplayName(_tr),
                      style: TextStyle(
                        color: palette.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      preset.localizedDescription(_tr),
                      style: TextStyle(
                        color: palette.textMuted,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _tr(
                        nl: 'Zoom ${preset.minZoom}–${preset.maxZoom}',
                        en: 'Zoom ${preset.minZoom}–${preset.maxZoom}',
                      ),
                      style: TextStyle(
                        color: palette.textMuted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: busy ? null : () => _onPresetSelected(preset),
              icon: const Icon(Icons.download_rounded, size: 18),
              label: Text(_tr(nl: 'Downloaden', en: 'Download')),
              style: FilledButton.styleFrom(
                backgroundColor: palette.accent,
                foregroundColor:
                    palette.isDark ? palette.background : Colors.black,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppLanguage>(
      valueListenable: appLanguageNotifier,
      builder: (context, _, __) {
        return ValueListenableBuilder<DriverThemeVariant>(
          valueListenable: widget.themeListenable ?? driverThemeNotifier,
          builder: (context, themeVariant, _) {
            final palette = paletteForDriverTheme(themeVariant);
            final progress = _downloadProgress;
            final progressFraction = progress?.fraction;
            final presets = driverOfflineMapVisiblePresets();
            final busy = _downloadInProgress || _estimateInProgress;

            return Scaffold(
              backgroundColor: palette.background,
              appBar: AppBar(
                backgroundColor: palette.background,
                foregroundColor: palette.textPrimary,
                title: Text(
                  // P0-FIELD-REPAIR-1 (C): the screen downloads basemap tiles
                  // only. "Offline kaarten" read as full offline navigation.
                  _tr(nl: 'Offline kaarttegels', en: 'Offline map tiles'),
                  style: TextStyle(color: palette.textPrimary),
                ),
              ),
              body: Stack(
                children: [
                  RefreshIndicator(
                    color: palette.accent,
                    onRefresh: _loadRegions,
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                      children: [
                        // NAV-R9: honest scope — tile packs only; routing still needs network.
                        _infoCard(
                          palette: palette,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _tr(
                                  nl: 'Gedownloade kaarten',
                                  en: 'Downloaded maps',
                                ),
                                style: TextStyle(
                                  color: palette.textPrimary,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                _tr(
                                  nl:
                                      'Kaartweergave kan offline beschikbaar zijn. '
                                      'Routeberekening, zoeken, verkeersinformatie en herberekenen vereisen momenteel internet.',
                                  en:
                                      'Map display can be available offline. '
                                      'Route calculation, search, traffic information and rerouting currently require internet.',
                                ),
                                style: TextStyle(
                                  color: palette.textMuted,
                                  height: 1.35,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (widget.routeCorridorMetadata != null) ...[
                          const SizedBox(height: 12),
                          _buildRouteCorridorMetadataCard(
                            palette: palette,
                            metadata: widget.routeCorridorMetadata!,
                          ),
                        ],
                        const SizedBox(height: 12),
                        _infoCard(
                          palette: palette,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _tr(
                                  nl:
                                      'Download kaartgebieden voor zwak mobiel signaal.',
                                  en: 'Download map areas for weak mobile signal.',
                                ),
                                style: TextStyle(
                                  color: palette.textPrimary,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                _tr(
                                  nl:
                                      'Gedownloade kaarten houden de straatkaart zichtbaar bij zwak signaal. '
                                      'Nieuwe routes en herberekenen hebben nog internet nodig.',
                                  en:
                                      'Downloaded maps keep the street map visible when signal is weak. '
                                      'New routes and recalculation still need internet.',
                                ),
                                style: TextStyle(
                                  color: palette.textMuted,
                                  height: 1.35,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        _infoCard(
                          palette: palette,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    Icons.wifi_rounded,
                                    size: 18,
                                    color: palette.accent,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      _tr(
                                        nl:
                                            'Wi‑Fi aanbevolen voor grote downloads.',
                                        en:
                                            'Wi‑Fi recommended for large downloads.',
                                      ),
                                      style:
                                          TextStyle(color: palette.textMuted),
                                    ),
                                  ),
                                  Switch(
                                    value: _wifiOnly,
                                    activeThumbColor: palette.accent,
                                    onChanged: busy
                                        ? null
                                        : (v) => setState(() => _wifiOnly = v),
                                  ),
                                ],
                              ),
                              Text(
                                _tr(nl: 'Alleen Wi‑Fi', en: 'Wi‑Fi only'),
                                style: TextStyle(
                                  color: palette.textMuted,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _tr(nl: 'Kaartgebieden', en: 'Map areas'),
                          style: TextStyle(
                            color: palette.textPrimary,
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 10),
                        ...presets.map(
                          (preset) => Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _presetCard(
                              palette: palette,
                              preset: preset,
                              busy: busy,
                            ),
                          ),
                        ),
                        OutlinedButton.icon(
                          onPressed: _loadingList || busy ? null : _loadRegions,
                          icon: const Icon(Icons.refresh_rounded),
                          label: Text(_tr(nl: 'Vernieuwen', en: 'Refresh')),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: palette.accent,
                            side: BorderSide(color: palette.border),
                            minimumSize: const Size.fromHeight(44),
                          ),
                        ),
                        if (_downloadInProgress) ...[
                          const SizedBox(height: 16),
                          _infoCard(
                            palette: palette,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _tr(
                                    nl: 'Bezig met downloaden…',
                                    en: 'Downloading…',
                                  ),
                                  style: TextStyle(
                                    color: palette.textPrimary,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                if (progress != null) ...[
                                  const SizedBox(height: 8),
                                  Text(
                                    _phaseLabel(progress.phase),
                                    style:
                                        TextStyle(color: palette.textMuted),
                                  ),
                                  if (progressFraction != null) ...[
                                    const SizedBox(height: 8),
                                    LinearProgressIndicator(
                                      value: progressFraction,
                                      color: palette.accent,
                                      backgroundColor:
                                          palette.surfaceAlt.withOpacity(0.8),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      '${(progressFraction * 100).round()}%',
                                      style:
                                          TextStyle(color: palette.textMuted),
                                    ),
                                  ],
                                  if (progress.completedResourceCount !=
                                          null &&
                                      progress.requiredResourceCount !=
                                          null) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      '${progress.completedResourceCount} / ${progress.requiredResourceCount}',
                                      style: TextStyle(
                                        color: palette.textMuted,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ],
                              ],
                            ),
                          ),
                        ],
                        if (_inlineError != null) ...[
                          const SizedBox(height: 12),
                          Text(
                            _inlineError!,
                            style: TextStyle(color: palette.danger),
                          ),
                        ],
                        const SizedBox(height: 20),
                        Text(
                          _tr(
                            nl: 'Gedownloade regio’s',
                            en: 'Downloaded regions',
                          ),
                          style: TextStyle(
                            color: palette.textPrimary,
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 10),
                        if (_loadingList)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 24),
                            child: Center(
                              child: CircularProgressIndicator(
                                color: palette.accent,
                              ),
                            ),
                          )
                        else if (_regions.isEmpty)
                          _infoCard(
                            palette: palette,
                            child: Text(
                              _tr(
                                nl: 'Nog geen kaarttegels gedownload.',
                                en: 'No map tiles downloaded yet.',
                              ),
                              style: TextStyle(color: palette.textMuted),
                            ),
                          )
                        else
                          ..._regions.map((region) {
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: _infoCard(
                                palette: palette,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      region.displayName,
                                      style: TextStyle(
                                        color: palette.textPrimary,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      'Zoom ${region.minZoom}–${region.maxZoom}',
                                      style:
                                          TextStyle(color: palette.textMuted),
                                    ),
                                    Text(
                                      _tr(
                                        nl:
                                            'Aangemaakt: ${_formatCreatedAt(region.createdAt)}',
                                        en:
                                            'Created: ${_formatCreatedAt(region.createdAt)}',
                                      ),
                                      style:
                                          TextStyle(color: palette.textMuted),
                                    ),
                                    Text(
                                      _tr(
                                        nl:
                                            'Opslag: ${_formatBytes(region.completedResourceSize)} · '
                                            '${_offlineRegionStatusText(region, nl: true)}',
                                        en:
                                            'Storage: ${_formatBytes(region.completedResourceSize)} · '
                                            '${_offlineRegionStatusText(region, nl: false)}',
                                      ),
                                      style: TextStyle(
                                        color: palette.textMuted,
                                        fontSize: 12,
                                      ),
                                    ),
                                    if (region.styleUris.isNotEmpty)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 2),
                                        child: Text(
                                          _tr(
                                            nl:
                                                'Navigatiestijlen offline: '
                                                '${_offlineStyleCoverageText(region, nl: true)}',
                                            en:
                                                'Navigation styles offline: '
                                                '${_offlineStyleCoverageText(region, nl: false)}',
                                          ),
                                          style: TextStyle(
                                            color: palette.textMuted,
                                            fontSize: 11,
                                          ),
                                        ),
                                      ),
                                    const SizedBox(height: 10),
                                    Align(
                                      alignment: Alignment.centerRight,
                                      child: TextButton.icon(
                                        onPressed: busy
                                            ? null
                                            : () =>
                                                _confirmAndDelete(region),
                                        icon: Icon(
                                          Icons.delete_outline_rounded,
                                          color: palette.danger,
                                        ),
                                        label: Text(
                                          _tr(
                                            nl: 'Verwijderen',
                                            en: 'Delete',
                                          ),
                                          style:
                                              TextStyle(color: palette.danger),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }),
                      ],
                    ),
                  ),
                  if (_estimateInProgress)
                    ColoredBox(
                      color: Colors.black.withOpacity(0.25),
                      child: Center(
                        child: Card(
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                CircularProgressIndicator(color: palette.accent),
                                const SizedBox(height: 12),
                                Text(
                                  _tr(
                                    nl: 'Grootte schatten…',
                                    en: 'Estimating size…',
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
