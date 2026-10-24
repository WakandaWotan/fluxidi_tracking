// OFFLINE-MAPS-DOWNLOADED-REGION-PREVIEW-P1
//
// Read-only MapLibre preview of an already-downloaded own region.
// Does not start navigation, follow GPS, mutate rides, or download tiles.
//
// Offline truth: the native renderer is switched offline before surface creation
// (forceOfflineStack) so
// the field acceptance test cannot silently hydrate missing tiles. Outside the
// downloaded perimeter the map may show blank/missing tiles — that is correct.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:fluxidi_tracking/driver_theme_palette.dart';
import 'package:fluxidi_tracking/driver_theme_store.dart';
import 'package:maplibre_gl/maplibre_gl.dart' as ml;
import '../maps/fluxidi_map_source_config.dart';

import 'driver_offline_maps_l10n.dart';
import 'driver_offline_maps_preview_model.dart';
import 'driver_offline_maps_service.dart';
import 'maplibre_offline_preview_lease.dart';

/// Offline-region map preview owner (UI only — TileStore remains the data owner).
class DriverOfflineMapRegionPreviewPage extends StatefulWidget {
  const DriverOfflineMapRegionPreviewPage({
    super.key,
    required this.region,
    this.themeListenable,
    this.target,
    this.mapBuilder,
    this.forceOfflineStack = true,
  });

  final DriverOfflineMapRegionInfo region;
  final ValueListenable<DriverThemeVariant>? themeListenable;

  /// When null, resolved via [resolveDriverOfflineMapPreviewTarget].
  final DriverOfflineMapPreviewTarget? target;

  /// Test seam: replaces the own native map with a deterministic stub.
  final Widget Function(
    BuildContext context,
    DriverOfflineMapPreviewTarget target,
  )? mapBuilder;

  /// When true (default), disconnects the MapLibre stack while this page is open
  /// so the acceptance test cannot silently pull network tiles. Restored on
  /// dispose. See product note in the field report about READ_ONLY fallback.
  final bool forceOfflineStack;

  @override
  State<DriverOfflineMapRegionPreviewPage> createState() =>
      _DriverOfflineMapRegionPreviewPageState();
}

class _DriverOfflineMapRegionPreviewPageState
    extends State<DriverOfflineMapRegionPreviewPage> {
  DriverOfflineMapPreviewTarget? _target;
  ml.MapLibreMapController? _map;
  ml.Line? _perimeter;
  bool _offlineReady = false;
  String? _offlineFailure;
  int _styleGeneration = 0;
  int _styleIndex = 0;
  bool _outsideDownloadedArea = false;
  final Object _offlineOwner = Object();

  String _tr({
    required String nl,
    required String en,
    String? fr,
    String? es,
  }) {
    return resolveOfflineMapsUiText(nl: nl, en: en, fr: fr, es: es);
  }

  @override
  void initState() {
    super.initState();
    _target = widget.target ?? resolveDriverOfflineMapPreviewTarget(widget.region);
    _offlineReady = !widget.forceOfflineStack || widget.mapBuilder != null;
    if (!_offlineReady) {
      _armOfflineStack();
    }
    debugPrint(
      '[OFFLINE_MAPS][PREVIEW_OPEN] region_id=${widget.region.id} '
      'complete=${widget.region.isComplete} '
      'geometry_source=${_target?.geometrySource ?? 'none'} '
      'force_offline_stack=${widget.forceOfflineStack}',
    );
  }

  Future<void> _armOfflineStack() async {
    try {
      await MapLibreOfflinePreviewLease.shared.acquire(_offlineOwner);
      if (!mounted) {
        await _restoreOfflineStack();
        return;
      }
      setState(() => _offlineReady = true);
    } catch (_) {
      if (mounted) setState(() => _offlineFailure = 'Offline kaart niet beschikbaar.');
    }
  }

  Future<void> _restoreOfflineStack() async {
    try { await MapLibreOfflinePreviewLease.shared.release(_offlineOwner); } catch (_) {}
  }

  @override
  void dispose() {
    ++_styleGeneration;
    unawaited(_restoreOfflineStack());
    super.dispose();
  }

  String _ownStyle(String value) {
    final dark = value.contains('dark') || value.contains('night');
    final base = fluxidiMapAssetBase(const String.fromEnvironment('FLUXIDI_MAP_ASSET_BASE_URL', defaultValue: ''));
    return '$base/data/full/style-${dark ? 'dark' : 'light'}.json';
  }

  Future<void> _fitCamera() async {
    final target = _target, map = _map;
    if (target == null || map == null || !mounted) return;
    final bounds = driverOfflineMapPreviewBoundsFromGeometry(target.geometry);
    if (bounds != null) {
      await map.moveCamera(ml.CameraUpdate.newLatLngBounds(
        ml.LatLngBounds(southwest: ml.LatLng(bounds.southLat, bounds.westLon),
          northeast: ml.LatLng(bounds.northLat, bounds.eastLon)), left:48, right:48, top:72, bottom:72));
    } else {
      await map.moveCamera(ml.CameraUpdate.newCameraPosition(ml.CameraPosition(
        target:ml.LatLng(target.centerLatitude,target.centerLongitude),
        zoom:driverOfflineMapPreviewZoomForRadiusKm(target.radiusKm))));
    }
  }

  Future<void> _onStyleLoaded() async {
    final target = _target, map = _map, generation = _styleGeneration;
    if (target == null || map == null || !mounted) return;
    _perimeter = null;
    try {
      await _fitCamera();
      if (!mounted || generation != _styleGeneration || !identical(map,_map)) return;
      final ring = driverOfflineMapPreviewPerimeterRing(target.geometry);
      if (ring.length < 2) return;
      final line = await map.addLine(ml.LineOptions(
        geometry: [for(final p in ring) ml.LatLng(p[1],p[0])],
        lineColor:'#2563EB',lineWidth:2.5,lineOpacity:0.85));
      if (!mounted || generation != _styleGeneration || !identical(map,_map)) {
        try { await map.removeLine(line); } catch (_) {}
      } else { _perimeter = line; }
    } catch (_) { /* Perimeter failure never invents downloaded coverage. */ }
  }

  void _onCameraChange() {
    final target = _target, center = _map?.cameraPosition?.target;
    if (target == null || center == null || !mounted) return;
    final bounds = driverOfflineMapPreviewBoundsFromGeometry(target.geometry);
    if (bounds == null) return;
    final outside = !bounds.contains(latitude:center.latitude,longitude:center.longitude);
    if (outside != _outsideDownloadedArea) setState(() => _outsideDownloadedArea = outside);
  }

  void _toggleStyle() {
    final target = _target;
    if (target == null || target.styleUris.length < 2) return;
    ++_styleGeneration;
    setState(() => _styleIndex = (_styleIndex + 1) % target.styleUris.length);
  }

  Widget _ownOfflineMap(String styleUri, DriverOfflineMapPreviewTarget target) {
    // Do not create a surface until native offline mode is armed. Otherwise
    // its first style/tile loads could silently hydrate a partial offline pack.
    if (!_offlineReady) return Center(child: _offlineFailure == null
      ? const CircularProgressIndicator() : Text(_offlineFailure!));
    return ml.MapLibreMap(
      styleString:_ownStyle(styleUri),
      initialCameraPosition:ml.CameraPosition(target:ml.LatLng(target.centerLatitude,target.centerLongitude),
        zoom:driverOfflineMapPreviewZoomForRadiusKm(target.radiusKm)),
      onMapCreated:(map) { _map = map; },onStyleLoadedCallback:_onStyleLoaded,
      trackCameraPosition:true,onCameraIdle:_onCameraChange,
      myLocationEnabled:false,compassEnabled:false,tiltGesturesEnabled:false);
  }

  @override
  Widget build(BuildContext context) {
    final listenable = widget.themeListenable ?? driverThemeNotifier;
    return ValueListenableBuilder<DriverThemeVariant>(
      valueListenable: listenable,
      builder: (context, variant, _) {
        final palette = paletteForDriverTheme(variant);
        final target = _target;
        final styleUri = (target == null || target.styleUris.isEmpty)
            ? kDriverOfflineMapsDefaultStyleUris.first
            : target.styleUris[
                _styleIndex.clamp(0, target.styleUris.length - 1)];
        return Scaffold(
          key: const Key('offline_region_preview_page'),
          backgroundColor: palette.background,
          appBar: AppBar(
            backgroundColor: palette.background,
            foregroundColor: palette.textPrimary,
            leading: IconButton(
              key: const Key('offline_region_preview_back'),
              icon: const Icon(Icons.arrow_back_rounded),
              onPressed: () => Navigator.of(context).maybePop(),
              tooltip: _tr(nl: 'Terug', en: 'Back'),
            ),
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _tr(nl: 'Offline kaart', en: 'Offline map'),
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontWeight: FontWeight.w800,
                    fontSize: 17,
                  ),
                ),
                Text(
                  target?.displayName ?? widget.region.displayName,
                  style: TextStyle(
                    color: palette.textMuted,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            actions: [
              if (target != null && target.styleUris.length > 1)
                TextButton(
                  key: const Key('offline_region_preview_style_toggle'),
                  onPressed: _toggleStyle,
                  child: Text(
                    _styleIndex == 0
                        ? _tr(nl: 'Nacht', en: 'Night')
                        : _tr(nl: 'Dag', en: 'Day'),
                  ),
                ),
            ],
          ),
          body: target == null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      _tr(
                        nl:
                            'Deze regio heeft geen bruikbare geometrie voor een '
                            'voorbeeld.',
                        en:
                            'This region has no usable geometry for a preview.',
                      ),
                      textAlign: TextAlign.center,
                      style: TextStyle(color: palette.textMuted),
                    ),
                  ),
                )
              : Stack(
                  children: [
                    Positioned.fill(
                      child: widget.mapBuilder != null
                          ? widget.mapBuilder!(context, target)
                          : _ownOfflineMap(styleUri, target),
                    ),
                    Positioned(
                      top: 12,
                      left: 12,
                      child: Container(
                        key: const Key('offline_region_preview_badge'),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: palette.isDark
                              ? Colors.black.withOpacity(0.55)
                              : palette.background.withOpacity(0.88),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: palette.accent.withOpacity(0.35),
                          ),
                        ),
                        child: Text(
                          _tr(
                            nl: 'Offline regio · Volledig',
                            en: 'Offline region · Complete',
                          ),
                          style: TextStyle(
                            color: palette.textPrimary,
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
                    if (_outsideDownloadedArea)
                      Positioned(
                        left: 12,
                        right: 12,
                        bottom: 24,
                        child: Material(
                          key: const Key('offline_region_preview_outside'),
                          color: palette.isDark
                              ? Colors.black.withOpacity(0.72)
                              : palette.background.withOpacity(0.92),
                          borderRadius: BorderRadius.circular(12),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 10,
                            ),
                            child: Text(
                              _tr(
                                nl: 'Buiten gedownload kaartgebied',
                                en: 'Outside the downloaded map area',
                              ),
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: palette.textPrimary,
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
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
  }
}
