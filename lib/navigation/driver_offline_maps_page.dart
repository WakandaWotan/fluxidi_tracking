import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:fluxidi_tracking/app_config.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/driver_theme_palette.dart';
import 'package:fluxidi_tracking/driver_theme_store.dart';

import 'driver_offline_maps_download_feedback.dart';
import 'driver_offline_maps_estimate_format.dart';
import 'driver_offline_maps_europe_geocoder.dart';
import 'driver_offline_maps_europe_selection.dart';
import 'driver_offline_maps_service.dart';
import 'driver_offline_maps_tile_quota.dart';
import 'nav_backend/driver_navigation_worker_client.dart';

// Future: OFFLINE-C2 download current visible map area from DriverHomePage.
// Future: OFFLINE-C3 airport presets (Zaventem, Charleroi, Schiphol).
// Future: OFFLINE-D active route cache / degraded mode when network is lost.
// FLUXIDI-OFFLINE-MAPS-EUROPE-REGION-EXPANSION-P0-1: Europe search + radius.

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

/// Presets shown in the Offline kaarten UI (legacy shortcuts — Europe search
/// is the primary path).
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

/// Europe place lookup used by the offline page. Defaults to the Mapbox
/// geocoder; overridden only by tests so the selection flow stays deterministic.
typedef DriverOfflineEuropePlaceSearch =
    Future<List<DriverOfflineEuropePlace>> Function({
      required String query,
      String languageCode,
    });

/// Chauffeur-facing offline basemap management (tiles only, not full navigation).
class DriverOfflineMapsPage extends StatefulWidget {
  const DriverOfflineMapsPage({
    super.key,
    this.themeListenable,
    this.routeCorridorMetadata,
    this.service,
    this.mapboxConfigured,
    this.placeSearch,
    this.searchDebounce,
  });

  final ValueListenable<DriverThemeVariant>? themeListenable;
  final NavigationWorkerOfflineCorridorMetadata? routeCorridorMetadata;

  /// Defaults to [DriverOfflineMapsService.shared]; overridden only by tests.
  final DriverOfflineMapsDownloadPort? service;

  /// Defaults to whether a Mapbox token was compiled in.
  final bool? mapboxConfigured;

  /// Defaults to [searchDriverOfflineEuropePlaces]; overridden only by tests.
  final DriverOfflineEuropePlaceSearch? placeSearch;

  /// Debounce before a search runs. Overridden only by tests.
  final Duration? searchDebounce;

  @override
  State<DriverOfflineMapsPage> createState() => _DriverOfflineMapsPageState();
}

class _DriverOfflineMapsPageState extends State<DriverOfflineMapsPage> {
  late final DriverOfflineMapsDownloadPort _service =
      widget.service ?? DriverOfflineMapsService.shared;
  final TextEditingController _searchCtrl = TextEditingController();

  List<DriverOfflineMapRegionInfo> _regions = const <DriverOfflineMapRegionInfo>[];
  bool _loadingList = true;
  bool _downloadInProgress = false;
  bool _estimateInProgress = false;
  DriverOfflineMapProgress? _downloadProgress;
  String? _inlineError;
  bool _wifiOnly = true;

  List<DriverOfflineEuropePlace> _searchResults =
      const <DriverOfflineEuropePlace>[];
  bool _searchInProgress = false;
  String? _searchError;
  DriverOfflineEuropePlace? _selectedPlace;
  int _selectedRadiusKm = kDriverOfflineEuropeDefaultRadiusKm;
  Timer? _searchDebounce;
  DriverOfflineMapsTileCapacity? _tileCapacity;
  bool _selectionTooLarge = false;
  int? _suggestedRadiusKm;
  String? _quotaGuidance;

  @override
  void initState() {
    super.initState();
    if (kDebugMode) {
      debugPrint('[OFFLINE_MAPS] ui=open');
    }
    _loadRegions();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
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

  bool get _mapboxConfigured =>
      widget.mapboxConfigured ?? kMapboxToken.trim().isNotEmpty;

  /// Emits a PII-safe diagnostic line: no token, no raw exception, no address.
  void _logOfflineDiagnostic({
    required String phase,
    required String regionId,
    int? radiusKm,
    DriverOfflineMapFailureCategory? category,
    int? completedResourceCount,
    int? requiredResourceCount,
    int? erroredResourceCount,
    String completionState = '',
    bool? estimateAvailable,
    String estimateFinite = '',
    String marginFinite = '',
  }) {
    if (!kDebugMode) return;
    debugPrint(
      buildDriverOfflineMapDiagnostic(
        phase: phase,
        regionId: regionId,
        radiusKm: radiusKm,
        category: category,
        completedResourceCount: completedResourceCount,
        requiredResourceCount: requiredResourceCount,
        erroredResourceCount: erroredResourceCount,
        completionState: completionState,
        estimateAvailable: estimateAvailable,
        estimateFinite: estimateFinite,
        marginFinite: marginFinite,
      ),
    );
  }

  /// Single place that turns a failure category into visible driver feedback.
  void _showFailure(
    DriverOfflineMapFailureCategory category, {
    bool inline = true,
  }) {
    if (!mounted) return;
    final message = driverOfflineMapFailureMessage(
      category: category,
      language: appConfig.currentLanguage,
    );
    if (inline) {
      setState(() => _inlineError = message);
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
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

  void _onSearchChanged(String raw) {
    _searchDebounce?.cancel();
    final q = raw.trim();
    if (q.length < 2) {
      setState(() {
        _searchResults = const <DriverOfflineEuropePlace>[];
        _searchError = null;
        _searchInProgress = false;
        // Clearing the query clears the selection, so the radius controls can
        // never describe a place the driver can no longer see.
        _selectedPlace = null;
        _inlineError = null;
      });
      return;
    }
    _searchDebounce = Timer(
      widget.searchDebounce ?? const Duration(milliseconds: 450),
      () => unawaited(_runEuropeSearch(q)),
    );
  }

  Future<void> _runEuropeSearch(String query) async {
    if (!mounted) return;
    setState(() {
      _searchInProgress = true;
      _searchError = null;
    });
    final lang = switch (appConfig.currentLanguage) {
      AppLanguage.nl => 'nl',
      AppLanguage.fr => 'fr',
      AppLanguage.es => 'es',
      AppLanguage.de => 'de',
      AppLanguage.en => 'en',
    };
    final search = widget.placeSearch ?? searchDriverOfflineEuropePlaces;
    final results = await search(query: query, languageCode: lang);
    if (!mounted) return;
    final previous = _selectedPlace;
    final selectionStillListed = previous == null ||
        driverOfflineMapSelectionStillListed(
          selectedFeatureId: previous.mapboxFeatureId,
          selectedPrimaryName: previous.primaryName,
          resultFeatureIds: results.map((p) => p.mapboxFeatureId),
          resultPrimaryNames: results.map((p) => p.primaryName),
        );
    setState(() {
      _searchInProgress = false;
      _searchResults = results;
      if (!selectionStillListed) {
        _selectedPlace = null;
      }
      if (results.isEmpty) {
        _searchError = _tr(
          nl: 'Geen Europese plaats gevonden. Probeer stad, gemeente of postcode.',
          en: 'No European place found. Try a city, municipality or postcode.',
        );
      }
    });
  }

  Future<void> _onEuropeSelectionConfirmed() async {
    // A tap always ends in feedback: instruction, error, preview or progress.
    if (_downloadInProgress || _estimateInProgress) return;

    final place = _selectedPlace;
    if (place == null) {
      _logOfflineDiagnostic(
        phase: 'cta',
        regionId: '',
        radiusKm: _selectedRadiusKm,
        category: DriverOfflineMapFailureCategory.noSelection,
      );
      _showFailure(DriverOfflineMapFailureCategory.noSelection);
      return;
    }

    if (!_mapboxConfigured) {
      _logOfflineDiagnostic(
        phase: 'cta',
        regionId: '',
        radiusKm: _selectedRadiusKm,
        category: DriverOfflineMapFailureCategory.mapboxConfiguration,
      );
      _showFailure(DriverOfflineMapFailureCategory.mapboxConfiguration);
      return;
    }

    final validation = validateDriverOfflineEuropeSelection(
      latitude: place.latitude,
      longitude: place.longitude,
      radiusKm: _selectedRadiusKm,
    );
    if (!validation.accepted) {
      _logOfflineDiagnostic(
        phase: 'validate',
        regionId: '',
        radiusKm: _selectedRadiusKm,
        category: DriverOfflineMapFailureCategory.regionTooLarge,
      );
      _showFailure(DriverOfflineMapFailureCategory.regionTooLarge);
      return;
    }

    final selection = DriverOfflineEuropeSelection(
      place: place,
      radiusKm: _selectedRadiusKm,
    );
    final existingIds = _regions.map((r) => r.id);
    if (driverOfflineMapRegionIdAlreadyPresent(
      candidateRegionId: selection.regionId,
      existingRegionIds: existingIds,
    )) {
      _logOfflineDiagnostic(
        phase: 'duplicate',
        regionId: selection.regionId,
        radiusKm: _selectedRadiusKm,
        category: DriverOfflineMapFailureCategory.duplicateRegion,
      );
      _showFailure(
        DriverOfflineMapFailureCategory.duplicateRegion,
        inline: false,
      );
      return;
    }

    await _confirmAndDownloadRequest(
      radiusKm: _selectedRadiusKm,
      request: selection.toRegionRequest(wifiOnly: _wifiOnly),
      titleName: selection.displayName,
      detailLines: <String>[
        _tr(
          nl: 'Land: ${place.countryName} (${place.countryCode.toUpperCase()})',
          en: 'Country: ${place.countryName} (${place.countryCode.toUpperCase()})',
        ),
        _tr(
          nl: 'Straal: $_selectedRadiusKm km (grensoverschrijdend toegestaan)',
          en: 'Radius: $_selectedRadiusKm km (cross-border allowed)',
        ),
        _tr(
          nl:
              'Centrum: ${place.latitude.toStringAsFixed(3)}, '
              '${place.longitude.toStringAsFixed(3)}',
          en:
              'Center: ${place.latitude.toStringAsFixed(3)}, '
              '${place.longitude.toStringAsFixed(3)}',
        ),
        _tr(
          nl:
              'Zoom ${selection.minZoom}–${selection.maxZoom} · '
              'straal-begrenzing (geen exacte gemeentegrens)',
          en:
              'Zoom ${selection.minZoom}–${selection.maxZoom} · '
              'radius boundary (not an exact municipality polygon)',
        ),
      ],
      previewCenterLat: place.latitude,
      previewCenterLon: place.longitude,
      previewRadiusKm: _selectedRadiusKm,
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
      DriverOfflineMapsTileCapacity? capacity;
      try {
        capacity = await _service.readTileCapacity();
      } catch (_) {
        capacity = null;
      }
      if (!mounted) return;
      setState(() {
        _regions = regions;
        _tileCapacity = capacity;
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

  Future<int?> _findLargestValidRadiusKm({
    required DriverOfflineEuropePlace place,
    required int usedMapsTiles,
    required int limitMapsTiles,
    required int currentRadiusKm,
  }) async {
    final candidates = kDriverOfflineEuropeRadiusOptionsKm
        .where((km) => km < currentRadiusKm)
        .toList()
      ..sort((a, b) => b.compareTo(a));
    for (final km in candidates) {
      final selection = DriverOfflineEuropeSelection(
        place: place,
        radiusKm: km,
      );
      try {
        final estimate = await _service
            .estimateRegion(selection.toRegionRequest(wifiOnly: _wifiOnly))
            .timeout(kDriverOfflineMapEstimateTimeout);
        final evaluation = evaluateOfflineMapsTileQuota(
          usedMapsTiles: usedMapsTiles,
          requestedMapsTiles: estimate.estimatedMapsTileCount,
          limitMapsTiles: limitMapsTiles,
        );
        if (evaluation.isAllowed) return km;
      } catch (_) {
        // Keep scanning smaller radii; never silent-apply a fallback.
      }
    }
    return null;
  }

  Future<void> _onPresetSelected(DriverOfflineMapPreset preset) async {
    if (_downloadInProgress || _estimateInProgress) return;
    final request = _requestForPreset(preset);
    if (!_mapboxConfigured) {
      _logOfflineDiagnostic(
        phase: 'preset_selected',
        regionId: request.regionId,
        category: DriverOfflineMapFailureCategory.mapboxConfiguration,
      );
      _showFailure(DriverOfflineMapFailureCategory.mapboxConfiguration);
      return;
    }
    _logOfflineDiagnostic(
      phase: 'preset_selected',
      regionId: request.regionId,
    );
    await _confirmAndDownloadRequest(
      request: request,
      titleName: preset.localizedDisplayName(_tr),
      detailLines: <String>[
        preset.localizedDescription(_tr),
        _tr(
          nl: 'Zoom ${preset.minZoom}–${preset.maxZoom} · licht + donker kaartstijl',
          en: 'Zoom ${preset.minZoom}–${preset.maxZoom} · light + dark map styles',
        ),
      ],
    );
  }

  Future<void> _confirmAndDownloadRequest({
    required DriverOfflineMapRegionRequest request,
    required String titleName,
    required List<String> detailLines,
    int? radiusKm,
    double? previewCenterLat,
    double? previewCenterLon,
    int? previewRadiusKm,
  }) async {
    setState(() {
      _estimateInProgress = true;
      _inlineError = null;
      _selectionTooLarge = false;
      _suggestedRadiusKm = null;
      _quotaGuidance = null;
    });
    DriverOfflineMapPreflight? preflight;
    DriverOfflineMapFailureCategory? estimateFailure;
    // Both awaits are bounded. An unbounded platform call was the silent no-op:
    // the page stayed busy and the preview below was never reached.
    try {
      await _service.ensureInitialized().timeout(
        kDriverOfflineMapInitTimeout,
      );
    } catch (err) {
      estimateFailure = classifyDriverOfflineMapFailure(
        error: err,
        phase: 'init',
        mapboxConfigured: _mapboxConfigured,
        wifiOnlyRequested: _wifiOnly,
      );
    }
    if (estimateFailure == null) {
      try {
        // OFFLINE-MAPS-TILE-LIMIT-PREFLIGHT-P0-2: quota before StylePacks.
        preflight = await _service
            .preflightRegion(request)
            .timeout(kDriverOfflineMapEstimateTimeout);
      } catch (err) {
        estimateFailure = classifyDriverOfflineMapFailure(
          error: err,
          phase: 'estimate',
          mapboxConfigured: _mapboxConfigured,
          wifiOnlyRequested: _wifiOnly,
        );
      }
    }
    if (mounted) {
      setState(() {
        _estimateInProgress = false;
        if (preflight != null) {
          _tileCapacity = preflight.capacity;
        }
      });
    }
    if (estimateFailure != null) {
      _logOfflineDiagnostic(
        phase: 'estimate',
        regionId: request.regionId,
        radiusKm: radiusKm,
        category: estimateFailure,
      );
    }
    if (!mounted) return;

    // Configuration and connectivity failures would also fail the download, so
    // they surface immediately instead of leading into a doomed confirmation.
    if (estimateFailure == DriverOfflineMapFailureCategory.mapboxConfiguration ||
        estimateFailure == DriverOfflineMapFailureCategory.noInternet) {
      _showFailure(estimateFailure!);
      return;
    }

    final estimate = preflight?.estimate;
    final quota = preflight?.quota;
    final quotaBlocked = quota?.isBlocked == true;
    int? suggestedRadius;
    String? quotaGuidance;
    if (quotaBlocked &&
        preflight != null &&
        estimate?.estimatedMapsTileCount != null) {
      final place = _selectedPlace;
      if (place != null && radiusKm != null) {
        suggestedRadius = await _findLargestValidRadiusKm(
          place: place,
          usedMapsTiles: preflight.capacity.usedMapsTiles,
          limitMapsTiles: preflight.capacity.limitMapsTiles,
          currentRadiusKm: radiusKm,
        );
      }
      if (!mounted) return;
      final lang = appConfig.currentLanguage;
      if (suggestedRadius != null) {
        quotaGuidance = formatOfflineMapsTileQuotaBlockedMessage(
          language: lang,
          requestedMapsTiles: estimate!.estimatedMapsTileCount!,
          availableMapsTiles: preflight.capacity.availableMapsTiles,
          suggestedRadiusKm: suggestedRadius,
        );
      } else {
        quotaGuidance = offlineMapsNoValidRadiusMessage(lang);
      }
      setState(() {
        _selectionTooLarge = true;
        _suggestedRadiusKm = suggestedRadius;
        _quotaGuidance = quotaGuidance;
        _inlineError = driverOfflineMapFailureMessage(
          category: DriverOfflineMapFailureCategory.tileLimitExceeded,
          language: lang,
        );
      });
    }

    final proceed = await _showDownloadConfirmDialog(
      titleName: titleName,
      detailLines: detailLines,
      estimate: estimate,
      capacity: preflight?.capacity,
      quota: quota,
      quotaGuidance: quotaGuidance,
      downloadAllowed: !quotaBlocked,
      estimateFailed: estimateFailure != null,
      estimateFailureMessage: estimateFailure == null
          ? null
          : driverOfflineMapFailureMessage(
              category: estimateFailure,
              language: appConfig.currentLanguage,
            ),
      minZoom: request.minZoom,
      maxZoom: request.maxZoom,
      previewCenterLat: previewCenterLat,
      previewCenterLon: previewCenterLon,
      previewRadiusKm: previewRadiusKm,
      regionIdForDiag: request.regionId,
      radiusKmForDiag: radiusKm,
    );
    // Never start download when quota is proven over limit — no silent fallback.
    if (proceed == true && mounted && !quotaBlocked) {
      await _startDownloadRequest(request, radiusKm: radiusKm);
    }
  }

  Future<bool?> _showDownloadConfirmDialog({
    required String titleName,
    required List<String> detailLines,
    required DriverOfflineMapEstimate? estimate,
    required bool estimateFailed,
    required int minZoom,
    required int maxZoom,
    DriverOfflineMapsTileCapacity? capacity,
    DriverOfflineMapsTileQuotaEvaluation? quota,
    String? quotaGuidance,
    bool downloadAllowed = true,
    String? estimateFailureMessage,
    double? previewCenterLat,
    double? previewCenterLon,
    int? previewRadiusKm,
    String regionIdForDiag = '',
    int? radiusKmForDiag,
  }) async {
    // Bound every estimate-derived conversion before the dialog builds.
    // Field crash: non-finite TileRegionEstimateResult.errorMargin made
    // `.round()` throw "Infinity or NaN toInt".
    final estimateLines = <String>[];
    final lang = appConfig.currentLanguage;
    try {
      if (estimate != null) {
        _logOfflineDiagnostic(
          phase: 'confirm_estimate',
          regionId: regionIdForDiag,
          radiusKm: radiusKmForDiag,
          estimateAvailable: true,
          estimateFinite: offlineMapEstimateFiniteClassToken(
            classifyOfflineMapEstimateNumber(estimate.transferSizeBytes),
          ),
          marginFinite: offlineMapEstimateFiniteClassToken(
            classifyOfflineMapEstimateNumber(estimate.errorMargin),
          ),
          requiredResourceCount: estimate.estimatedMapsTileCount,
        );
        estimateLines.add(
          formatOfflineMapEstimateConfirmLine(
            language: lang,
            transferSizeBytes: estimate.transferSizeBytes,
            storageSizeBytes: estimate.storageSizeBytes,
            errorMargin: estimate.errorMargin,
          ),
        );
      } else if (estimateFailed) {
        _logOfflineDiagnostic(
          phase: 'confirm_estimate',
          regionId: regionIdForDiag,
          radiusKm: radiusKmForDiag,
          estimateAvailable: false,
          estimateFinite: 'missing',
          marginFinite: 'missing',
        );
        estimateLines.add(
          estimateFailureMessage ?? offlineMapEstimateUnavailableLabel(lang),
        );
      }
      if (capacity != null) {
        estimateLines.add(
          formatOfflineMapsTileQuotaSummaryLine(
            language: lang,
            requestedMapsTiles: estimate?.estimatedMapsTileCount,
            usedMapsTiles: capacity.usedMapsTiles,
            availableMapsTiles: capacity.availableMapsTiles,
            limitMapsTiles: capacity.limitMapsTiles,
          ),
        );
      }
      if (quotaGuidance != null && quotaGuidance.trim().isNotEmpty) {
        estimateLines.add(quotaGuidance.trim());
      } else if (quota?.isBlocked == true &&
          estimate?.estimatedMapsTileCount != null &&
          capacity != null) {
        estimateLines.add(
          formatOfflineMapsTileQuotaBlockedMessage(
            language: lang,
            requestedMapsTiles: estimate!.estimatedMapsTileCount!,
            availableMapsTiles: capacity.availableMapsTiles,
          ),
        );
      }
    } catch (_) {
      // Formatting must never suppress the dialog or leave buttons busy.
      if (mounted) {
        setState(() {
          _estimateInProgress = false;
          _downloadInProgress = false;
        });
      }
      _logOfflineDiagnostic(
        phase: 'confirm_estimate_format_error',
        regionId: regionIdForDiag,
        radiusKm: radiusKmForDiag,
        estimateAvailable: estimate != null,
        estimateFinite: 'error',
        marginFinite: 'error',
      );
      estimateLines
        ..clear()
        ..add(offlineMapEstimateUnavailableLabel(lang));
    }

    try {
      return await showDialog<bool>(
        context: context,
        builder: (ctx) {
          return AlertDialog(
            title: Text(
              downloadAllowed
                  ? _tr(nl: 'Kaartgebied downloaden?', en: 'Download map area?')
                  : _tr(
                      nl: 'Kaartgebied te groot',
                      en: 'Map area too large',
                    ),
            ),
            content: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    titleName,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  if (!downloadAllowed) ...[
                    const SizedBox(height: 6),
                    Text(
                      offlineMapsSelectionTooLargeLabel(lang),
                      key: const Key('offline_selection_too_large'),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ],
                  const SizedBox(height: 8),
                  for (final line in detailLines) ...[
                    Text(line),
                    const SizedBox(height: 4),
                  ],
                  Text(
                    _tr(
                      nl: 'Zoom $minZoom–$maxZoom · licht + donker kaartstijl',
                      en: 'Zoom $minZoom–$maxZoom · light + dark map styles',
                    ),
                  ),
                  if (previewCenterLat != null &&
                      previewCenterLon != null &&
                      previewRadiusKm != null) ...[
                    const SizedBox(height: 10),
                    SizedBox(
                      height: 120,
                      width: double.infinity,
                      child: CustomPaint(
                        painter: _OfflineRegionPreviewPainter(
                          radiusKm: previewRadiusKm,
                        ),
                        child: Center(
                          child: Text(
                            _tr(
                              nl: 'Voorbeeld · $previewRadiusKm km straal',
                              en: 'Preview · $previewRadiusKm km radius',
                            ),
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                  if (estimateLines.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    for (final line in estimateLines) ...[
                      Text(line),
                      const SizedBox(height: 6),
                    ],
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
                key: const Key('offline_confirm_download'),
                onPressed: downloadAllowed
                    ? () => Navigator.pop(ctx, true)
                    : null,
                child: Text(_tr(nl: 'Downloaden', en: 'Download')),
              ),
            ],
          );
        },
      );
    } catch (_) {
      if (mounted) {
        setState(() {
          _estimateInProgress = false;
          _downloadInProgress = false;
        });
        _showFailure(DriverOfflineMapFailureCategory.unknown);
      }
      return false;
    }
  }

  Future<void> _startDownloadRequest(
    DriverOfflineMapRegionRequest request, {
    int? radiusKm,
  }) async {
    // Single-flight: a second tap while a download runs is intentionally ignored
    // here, because the button already renders a downloading state.
    if (_downloadInProgress) return;

    setState(() {
      _downloadInProgress = true;
      _downloadProgress = null;
      _inlineError = null;
    });
    _logOfflineDiagnostic(
      phase: 'download_start',
      regionId: request.regionId,
      radiusKm: radiusKm,
    );

    DriverOfflineMapProgress? lastProgress;
    try {
      final info = await _service.downloadRegion(
        request,
        onProgress: (progress) {
          lastProgress = progress;
          if (!mounted) return;
          setState(() => _downloadProgress = progress);
        },
      );
      if (!mounted) return;
      _logOfflineDiagnostic(
        phase: 'download_done',
        regionId: request.regionId,
        radiusKm: radiusKm,
        completedResourceCount: info.completedResourceCount,
        requiredResourceCount: info.requiredResourceCount,
        erroredResourceCount: info.erroredResourceCount,
        completionState: driverOfflineMapCompletionStatusToken(
          info.completionStatus,
        ),
      );
      switch (info.completionStatus) {
        case DriverOfflineMapCompletionStatus.complete:
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                _tr(
                  nl: 'Kaartgebied gedownload. Status: Volledig.',
                  en: 'Map area downloaded. Status: Complete.',
                ),
              ),
            ),
          );
        case DriverOfflineMapCompletionStatus.completedWithErrors:
          // Resource errors must never read as a clean success.
          _showFailure(DriverOfflineMapFailureCategory.tileRegionResourceError);
        case DriverOfflineMapCompletionStatus.unknown:
          // OFFLINE-MAPS-DOWNLOAD-COMPLETION-P0-1: unknown counters (incl.
          // StylePack 0/0 without exception) are not "download mislukt".
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                _tr(
                  nl:
                      'Download afgerond. Status wordt geverifieerd — nog niet '
                      'als volledig gemarkeerd.',
                  en:
                      'Download finished. Status is being verified — not yet '
                      'marked complete.',
                ),
              ),
            ),
          );
        case DriverOfflineMapCompletionStatus.incomplete:
        case DriverOfflineMapCompletionStatus.expiredOrStale:
          _showFailure(DriverOfflineMapFailureCategory.tileRegionResourceError);
      }
      await _loadRegions();
    } catch (err) {
      if (!mounted) return;
      final category = classifyDriverOfflineMapFailure(
        error: err,
        phase: 'download',
        mapboxConfigured: _mapboxConfigured,
        wifiOnlyRequested: _wifiOnly,
      );
      _logOfflineDiagnostic(
        phase: 'download_fail',
        regionId: request.regionId,
        radiusKm: radiusKm,
        category: category,
        completedResourceCount: lastProgress?.completedResourceCount,
        requiredResourceCount: lastProgress?.requiredResourceCount,
        completionState: 'not_complete',
      );
      _showFailure(category);
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
    Key? key,
  }) {
    return Container(
      key: key,
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
              key: Key('offline_preset_download_${preset.slug}'),
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

  String _europeCtaLabel(DriverOfflineMapCtaState state) {
    switch (state) {
      case DriverOfflineMapCtaState.estimating:
        return _tr(
          nl: 'Voorbeeld voorbereiden…',
          en: 'Preparing preview…',
        );
      case DriverOfflineMapCtaState.downloading:
        return _tr(nl: 'Bezig met downloaden…', en: 'Downloading…');
      case DriverOfflineMapCtaState.needsSelection:
      case DriverOfflineMapCtaState.ready:
        return _tr(
          nl: 'Voorbeeld & downloaden',
          en: 'Preview & download',
        );
    }
  }

  /// Keeps the chosen place and country visible next to the radius controls,
  /// or states plainly that nothing is selected yet.
  Widget _selectedPlaceSummary({required DriverThemePalette palette}) {
    final place = _selectedPlace;
    if (place == null) {
      return Row(
        key: const Key('offline_europe_selection_empty'),
        children: [
          Icon(Icons.info_outline_rounded, size: 16, color: palette.textMuted),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              driverOfflineMapFailureMessage(
                category: DriverOfflineMapFailureCategory.noSelection,
                language: appConfig.currentLanguage,
              ),
              style: TextStyle(color: palette.textMuted, fontSize: 12),
            ),
          ),
        ],
      );
    }
    return Container(
      key: const Key('offline_europe_selection_summary'),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: palette.accent.withOpacity(0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: palette.accent.withOpacity(0.5)),
      ),
      child: Row(
        children: [
          Icon(Icons.place_rounded, size: 18, color: palette.accent),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _tr(
                    nl: 'Gekozen plaats',
                    en: 'Selected place',
                  ),
                  style: TextStyle(color: palette.textMuted, fontSize: 11),
                ),
                Text(
                  '${place.primaryName} · ${place.countryName}',
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  _tr(
                    nl: 'Straal $_selectedRadiusKm km',
                    en: 'Radius $_selectedRadiusKm km',
                  ),
                  style: TextStyle(color: palette.textMuted, fontSize: 12),
                ),
              ],
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
            final ctaState = resolveDriverOfflineMapCtaState(
              hasSelection: _selectedPlace != null,
              estimateInProgress: _estimateInProgress,
              downloadInProgress: _downloadInProgress,
            );

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
                          _tr(
                            nl: 'Europa — zoek jouw werkgebied',
                            en: 'Europe — search your operating area',
                          ),
                          style: TextStyle(
                            color: palette.textPrimary,
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _tr(
                            nl:
                                'Zoek een stad, gemeente of postcode in Europa. '
                                'Download gebruikt een begrensde straal (geen landdownload).',
                            en:
                                'Search a city, municipality or postcode in Europe. '
                                'Download uses a bounded radius (not a whole country).',
                          ),
                          style: TextStyle(
                            color: palette.textMuted,
                            height: 1.35,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          key: const Key('offline_europe_search_field'),
                          controller: _searchCtrl,
                          enabled: !busy,
                          onChanged: _onSearchChanged,
                          style: TextStyle(color: palette.textPrimary),
                          decoration: InputDecoration(
                            hintText: _tr(
                              nl: 'Bijv. Lille, Eindhoven, Köln, Madrid…',
                              en: 'e.g. Lille, Eindhoven, Köln, Madrid…',
                            ),
                            hintStyle: TextStyle(color: palette.textMuted),
                            prefixIcon: Icon(
                              Icons.search_rounded,
                              color: palette.accent,
                            ),
                            filled: true,
                            fillColor: palette.surface,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(color: palette.border),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(color: palette.border),
                            ),
                          ),
                        ),
                        if (_searchInProgress) ...[
                          const SizedBox(height: 10),
                          LinearProgressIndicator(color: palette.accent),
                        ],
                        if (_searchError != null && _searchResults.isEmpty) ...[
                          const SizedBox(height: 8),
                          Text(
                            _searchError!,
                            style: TextStyle(
                              color: palette.textMuted,
                              fontSize: 12,
                            ),
                          ),
                        ],
                        if (_searchResults.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          ..._searchResults.map((place) {
                            final selected = _selectedPlace?.mapboxFeatureId ==
                                    place.mapboxFeatureId &&
                                _selectedPlace?.primaryName == place.primaryName;
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: Material(
                                color: selected
                                    ? palette.accent.withOpacity(0.15)
                                    : palette.surface,
                                borderRadius: BorderRadius.circular(12),
                                child: ListTile(
                                  key: Key(
                                    'offline_europe_result_${place.primaryName}',
                                  ),
                                  enabled: !busy,
                                  selected: selected,
                                  title: Text(
                                    place.displayLabel,
                                    style: TextStyle(
                                      color: palette.textPrimary,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  subtitle: Text(
                                    '${place.latitude.toStringAsFixed(3)}, '
                                    '${place.longitude.toStringAsFixed(3)} · '
                                    '${place.placeType}',
                                    style: TextStyle(
                                      color: palette.textMuted,
                                      fontSize: 12,
                                    ),
                                  ),
                                  onTap: () {
                                    setState(() => _selectedPlace = place);
                                  },
                                ),
                              ),
                            );
                          }),
                        ],
                        // The selection summary, radius controls and CTA stay
                        // mounted with or without a selection: a hidden CTA and
                        // a CTA that silently returns are equally confusing.
                        const SizedBox(height: 10),
                        _selectedPlaceSummary(palette: palette),
                        const SizedBox(height: 10),
                        if (_tileCapacity != null) ...[
                          _infoCard(
                            key: const Key('offline_tile_capacity_card'),
                            palette: palette,
                            child: Text(
                              formatOfflineMapsTileQuotaSummaryLine(
                                language: appConfig.currentLanguage,
                                requestedMapsTiles: null,
                                usedMapsTiles: _tileCapacity!.usedMapsTiles,
                                availableMapsTiles:
                                    _tileCapacity!.availableMapsTiles,
                                limitMapsTiles: _tileCapacity!.limitMapsTiles,
                              ),
                              style: TextStyle(
                                color: palette.textPrimary,
                                fontSize: 13,
                                height: 1.35,
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                        ],
                        Text(
                          _tr(nl: 'Downloadstraal', en: 'Download radius'),
                          style: TextStyle(
                            color: palette.textPrimary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final km in kDriverOfflineEuropeRadiusOptionsKm)
                              ChoiceChip(
                                label: Text(
                                  _suggestedRadiusKm == km
                                      ? '$km km · ${_tr(nl: 'voorstel', en: 'suggested')}'
                                      : '$km km',
                                ),
                                selected: _selectedRadiusKm == km,
                                onSelected: busy
                                    ? null
                                    : (_) => setState(() {
                                          _selectedRadiusKm = km;
                                          _selectionTooLarge = false;
                                          _quotaGuidance = null;
                                          // Do not auto-change zoom; only clear
                                          // stale quota state for the new radius.
                                          if (_suggestedRadiusKm != null &&
                                              km == _suggestedRadiusKm) {
                                            _suggestedRadiusKm = null;
                                          }
                                        }),
                                selectedColor: palette.accent.withOpacity(0.35),
                                labelStyle: TextStyle(
                                  color: palette.textPrimary,
                                ),
                              ),
                          ],
                        ),
                        if (_selectionTooLarge) ...[
                          const SizedBox(height: 8),
                          Text(
                            offlineMapsSelectionTooLargeLabel(
                              appConfig.currentLanguage,
                            ),
                            key: const Key('offline_radius_too_large'),
                            style: TextStyle(
                              color: palette.textPrimary,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          if (_quotaGuidance != null) ...[
                            const SizedBox(height: 4),
                            Text(
                              _quotaGuidance!,
                              style: TextStyle(
                                color: palette.textMuted,
                                fontSize: 12,
                                height: 1.35,
                              ),
                            ),
                          ],
                        ],
                        const SizedBox(height: 10),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            key: const Key('offline_europe_cta'),
                            onPressed: driverOfflineMapCtaIsTappable(ctaState)
                                ? _onEuropeSelectionConfirmed
                                : null,
                            icon: ctaState == DriverOfflineMapCtaState.estimating
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.download_rounded, size: 18),
                            label: Text(_europeCtaLabel(ctaState)),
                            style: FilledButton.styleFrom(
                              backgroundColor: palette.accent,
                              foregroundColor: palette.isDark
                                  ? palette.background
                                  : Colors.black,
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          _tr(
                            nl: 'Snelkoppelingen (bestaand)',
                            en: 'Shortcuts (existing)',
                          ),
                          style: TextStyle(
                            color: palette.textPrimary,
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _tr(
                            nl:
                                'Bestaande België- / Maarkedal-regio’s blijven beschikbaar.',
                            en:
                                'Existing Belgium / Maarkedal regions remain available.',
                          ),
                          style: TextStyle(
                            color: palette.textMuted,
                            fontSize: 12,
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
                        // Estimating used to render nothing at all, which is
                        // what made a slow or stalled estimate look like a
                        // dead button.
                        if (_estimateInProgress) ...[
                          const SizedBox(height: 16),
                          _infoCard(
                            key: const Key('offline_preparing_card'),
                            palette: palette,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _tr(
                                    nl: 'Voorbeeld voorbereiden…',
                                    en: 'Preparing preview…',
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
                                        'Grootte van het kaartgebied wordt geschat.',
                                    en: 'Estimating the map area size.',
                                  ),
                                  style: TextStyle(
                                    color: palette.textMuted,
                                    fontSize: 12,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                LinearProgressIndicator(color: palette.accent),
                              ],
                            ),
                          ),
                        ],
                        if (_downloadInProgress) ...[
                          const SizedBox(height: 16),
                          _infoCard(
                            key: const Key('offline_download_progress_card'),
                            palette: palette,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  progressFraction == null
                                      ? _tr(
                                          nl: 'Kaartgebied downloaden…',
                                          en: 'Downloading map area…',
                                        )
                                      : _tr(
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
                                  const SizedBox(height: 8),
                                  LinearProgressIndicator(
                                    value: progressFraction,
                                    color: palette.accent,
                                    backgroundColor:
                                        palette.surfaceAlt.withOpacity(0.8),
                                  ),
                                  if (progressFraction != null) ...[
                                    const SizedBox(height: 6),
                                    Text(
                                      '${safeOfflineMapPercent(progressFraction) ?? '—'}%',
                                      style:
                                          TextStyle(color: palette.textMuted),
                                    ),
                                  ],
                                  if (progress.completedResourceCount !=
                                          null &&
                                      progress.requiredResourceCount !=
                                          null &&
                                      (progress.requiredResourceCount ?? 0) >
                                          0) ...[
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

/// Schematic preview of the selected radius (not live map tiles).
class _OfflineRegionPreviewPainter extends CustomPainter {
  _OfflineRegionPreviewPainter({required this.radiusKm});

  final int radiusKm;

  @override
  void paint(Canvas canvas, Size size) {
    final bg = Paint()..color = const Color(0xFF1B2436);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Offset.zero & size,
        const Radius.circular(10),
      ),
      bg,
    );
    final border = Paint()
      ..color = const Color(0xFF4C6FFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final maxR = math.min(size.width, size.height) * 0.42;
    final r = maxR * (radiusKm / kDriverOfflineEuropeMaxRadiusKm).clamp(0.2, 1.0);
    final c = Offset(size.width / 2, size.height / 2);
    canvas.drawCircle(c, r, border);
    canvas.drawCircle(
      c,
      3,
      Paint()..color = const Color(0xFFE8C57E),
    );
  }

  @override
  bool shouldRepaint(covariant _OfflineRegionPreviewPainter oldDelegate) =>
      oldDelegate.radiusKm != radiusKm;
}
