import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:fluxidi_tracking/app_config.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/driver_theme_palette.dart';
import 'package:fluxidi_tracking/driver_theme_store.dart';

import 'driver_offline_maps_service.dart';

/// Predefined Brussels demo polygon for OFFLINE-C.
///
/// Current visible-map bounds extraction is deferred to a follow-up (OFFLINE-C2)
/// to avoid risky DriverHomePage map coupling in this patch.
Map<String, dynamic> driverOfflineMapsBrusselsTestGeometry() {
  return <String, dynamic>{
    'type': 'Polygon',
    'coordinates': <List<List<double>>>[
      <List<double>>[
        <double>[4.30, 50.82],
        <double>[4.45, 50.82],
        <double>[4.45, 50.90],
        <double>[4.30, 50.90],
        <double>[4.30, 50.82],
      ],
    ],
  };
}

/// Chauffeur-facing offline basemap management (tiles only, not full navigation).
class DriverOfflineMapsPage extends StatefulWidget {
  const DriverOfflineMapsPage({super.key, this.themeListenable});

  final ValueListenable<DriverThemeVariant>? themeListenable;

  @override
  State<DriverOfflineMapsPage> createState() => _DriverOfflineMapsPageState();
}

class _DriverOfflineMapsPageState extends State<DriverOfflineMapsPage> {
  final DriverOfflineMapsService _service = DriverOfflineMapsService.shared;

  List<DriverOfflineMapRegionInfo> _regions = const <DriverOfflineMapRegionInfo>[];
  bool _loadingList = true;
  bool _downloadInProgress = false;
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
    }
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
          nl: 'Kon offline kaarten niet laden.',
          en: 'Could not load offline maps.',
        );
      });
    }
  }

  Future<void> _confirmAndDownload() async {
    if (_downloadInProgress) return;

    final proceed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text(
            _tr(
              nl: 'Kaartgebied downloaden?',
              en: 'Download map area?',
            ),
          ),
          content: Text(
            _tr(
              nl:
                  'Dit downloadt een testregio rond Brussel (licht + donker kaartstijl, zoom 11–16). '
                  'Gebruik bij voorkeur Wi‑Fi. Dit gebruikt opslag en mobiele data.\n\n'
                  'Dit houdt alleen de straatkaart zichtbaar bij zwak signaal. '
                  'Nieuwe routes en herberekenen hebben nog internet nodig.',
              en:
                  'This downloads a test region around Brussels (light + dark map styles, zoom 11–16). '
                  'Wi‑Fi is recommended. This uses storage and mobile data.\n\n'
                  'This only keeps the street map visible when signal is weak. '
                  'New routes and recalculation still need internet.',
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
    if (proceed != true || !mounted) return;
    await _startDownload();
  }

  Future<void> _startDownload() async {
    if (_downloadInProgress) return;
    if (kDebugMode) {
      debugPrint('[OFFLINE_MAPS] ui=download_start');
    }

    setState(() {
      _downloadInProgress = true;
      _downloadProgress = null;
      _inlineError = null;
    });

    final request = DriverOfflineMapRegionRequest(
      displayName: _tr(
        nl: 'Brussel (test)',
        en: 'Brussels (test)',
      ),
      slug: 'brussels_test',
      geometry: driverOfflineMapsBrusselsTestGeometry(),
      wifiOnly: _wifiOnly,
    );

    try {
      await _service.downloadRegion(
        request,
        onProgress: (progress) {
          if (!mounted) return;
          setState(() => _downloadProgress = progress);
        },
      );
      if (!mounted) return;
      if (kDebugMode) {
        debugPrint('[OFFLINE_MAPS] ui=download_done');
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _tr(
              nl: 'Offline kaart gedownload.',
              en: 'Offline map downloaded.',
            ),
          ),
        ),
      );
      await _loadRegions();
    } catch (_) {
      if (!mounted) return;
      if (kDebugMode) {
        debugPrint('[OFFLINE_MAPS] ui=fail');
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
            _tr(nl: 'Offline kaart verwijderd.', en: 'Offline map removed.'),
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

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '—';
    final mb = bytes / (1024 * 1024);
    if (mb < 1) {
      return '${(bytes / 1024).toStringAsFixed(0)} KB';
    }
    return '${mb.toStringAsFixed(1)} MB';
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

            return Scaffold(
              backgroundColor: palette.background,
              appBar: AppBar(
                backgroundColor: palette.background,
                foregroundColor: palette.textPrimary,
                title: Text(
                  _tr(nl: 'Offline kaarten', en: 'Offline maps'),
                  style: TextStyle(color: palette.textPrimary),
                ),
              ),
              body: RefreshIndicator(
                color: palette.accent,
                onRefresh: _loadRegions,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                  children: [
                    _infoCard(
                      palette: palette,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _tr(
                              nl: 'Download kaartgebieden voor zwak mobiel signaal.',
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
                                    nl: 'Wi‑Fi aanbevolen voor grote downloads.',
                                    en: 'Wi‑Fi recommended for large downloads.',
                                  ),
                                  style: TextStyle(color: palette.textMuted),
                                ),
                              ),
                              Switch(
                                value: _wifiOnly,
                                activeThumbColor: palette.accent,
                                onChanged: _downloadInProgress
                                    ? null
                                    : (v) => setState(() => _wifiOnly = v),
                              ),
                            ],
                          ),
                          Text(
                            _tr(
                              nl: 'Alleen Wi‑Fi',
                              en: 'Wi‑Fi only',
                            ),
                            style: TextStyle(
                              color: palette.textMuted,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed:
                          _downloadInProgress ? null : _confirmAndDownload,
                      icon: const Icon(Icons.download_rounded),
                      label: Text(
                        _tr(
                          nl: 'Download kaartgebied (test Brussel)',
                          en: 'Download map area (Brussels test)',
                        ),
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor: palette.accent,
                        foregroundColor: palette.isDark
                            ? palette.background
                            : Colors.black,
                        minimumSize: const Size.fromHeight(48),
                      ),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: _loadingList ? null : _loadRegions,
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
                              _tr(nl: 'Bezig met downloaden…', en: 'Downloading…'),
                              style: TextStyle(
                                color: palette.textPrimary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            if (progress != null) ...[
                              const SizedBox(height: 8),
                              Text(
                                _phaseLabel(progress.phase),
                                style: TextStyle(color: palette.textMuted),
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
                                  style: TextStyle(color: palette.textMuted),
                                ),
                              ],
                              if (progress.completedResourceCount != null &&
                                  progress.requiredResourceCount != null) ...[
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
                      _tr(nl: 'Gedownloade regio’s', en: 'Downloaded regions'),
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
                          child: CircularProgressIndicator(color: palette.accent),
                        ),
                      )
                    else if (_regions.isEmpty)
                      _infoCard(
                        palette: palette,
                        child: Text(
                          _tr(
                            nl: 'Nog geen offline kaarten gedownload.',
                            en: 'No offline maps downloaded yet.',
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
                                  style: TextStyle(color: palette.textMuted),
                                ),
                                Text(
                                  _tr(
                                    nl: 'Aangemaakt: ${_formatCreatedAt(region.createdAt)}',
                                    en: 'Created: ${_formatCreatedAt(region.createdAt)}',
                                  ),
                                  style: TextStyle(color: palette.textMuted),
                                ),
                                Text(
                                  _tr(
                                    nl:
                                        'Opslag: ${_formatBytes(region.completedResourceSize)} · '
                                        '${region.isComplete ? 'Volledig' : 'Bezig/onvolledig'}',
                                    en:
                                        'Storage: ${_formatBytes(region.completedResourceSize)} · '
                                        '${region.isComplete ? 'Complete' : 'In progress/incomplete'}',
                                  ),
                                  style: TextStyle(
                                    color: palette.textMuted,
                                    fontSize: 12,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: TextButton.icon(
                                    onPressed: _downloadInProgress
                                        ? null
                                        : () => _confirmAndDelete(region),
                                    icon: Icon(
                                      Icons.delete_outline_rounded,
                                      color: palette.danger,
                                    ),
                                    label: Text(
                                      _tr(nl: 'Verwijderen', en: 'Delete'),
                                      style: TextStyle(color: palette.danger),
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
            );
          },
        );
      },
    );
  }
}
