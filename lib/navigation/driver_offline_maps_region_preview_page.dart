// OFFLINE-MAPS-DOWNLOADED-REGION-PREVIEW-P1
//
// Read-only Mapbox preview of an already-downloaded TileRegion.
// Does not start navigation, follow GPS, mutate rides, or download tiles.
//
// Offline truth: Mapbox TileStoreUsageMode.READ_ONLY checks local packs first
// but falls back to network individual tiles when the stack is connected. This
// page therefore disconnects OfflineSwitch while open (forceOfflineStack) so
// the field acceptance test cannot silently hydrate missing tiles. Outside the
// downloaded perimeter the map may show blank/missing tiles — that is correct.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:fluxidi_tracking/app_config.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/driver_theme_palette.dart';
import 'package:fluxidi_tracking/driver_theme_store.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mb;

import 'driver_offline_maps_preview_model.dart';
import 'driver_offline_maps_service.dart';
import 'nav_engine/nav_field_diagnostics.dart';

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

  /// Test seam: replaces the Mapbox [mb.MapWidget] with a deterministic stub.
  final Widget Function(
    BuildContext context,
    DriverOfflineMapPreviewTarget target,
  )? mapBuilder;

  /// When true (default), disconnects the Mapbox stack while this page is open
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
  mb.MapboxMap? _map;
  mb.PolylineAnnotationManager? _perimeterManager;
  int _styleIndex = 0;
  bool _outsideDownloadedArea = false;
  bool? _previousStackConnected;
  bool _stackArmed = false;

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
      case AppLanguage.de:
        return en;
    }
  }

  @override
  void initState() {
    super.initState();
    _target = widget.target ?? resolveDriverOfflineMapPreviewTarget(widget.region);
    if (widget.forceOfflineStack && widget.mapBuilder == null) {
      _armOfflineStack();
    }
    navFieldDiagnosticsPrinter(
      '[OFFLINE_MAPS][PREVIEW_OPEN] region_id=${widget.region.id} '
      'complete=${widget.region.isComplete} '
      'geometry_source=${_target?.geometrySource ?? 'none'} '
      'force_offline_stack=${widget.forceOfflineStack}',
    );
  }

  Future<void> _armOfflineStack() async {
    try {
      _previousStackConnected =
          await mb.OfflineSwitch.shared.isMapboxStackConnected;
      await mb.OfflineSwitch.shared.setMapboxStackConnected(false);
      _stackArmed = true;
      navFieldDiagnosticsPrinter(
        '[OFFLINE_MAPS][PREVIEW_STACK] connected=false '
        'previous=${_previousStackConnected ?? '-'}',
      );
    } catch (e) {
      navFieldDiagnosticsPrinter(
        '[OFFLINE_MAPS][PREVIEW_STACK] arm_failed type=${e.runtimeType}',
      );
    }
  }

  Future<void> _restoreOfflineStack() async {
    if (!_stackArmed) return;
    try {
      final restore = _previousStackConnected ?? true;
      await mb.OfflineSwitch.shared.setMapboxStackConnected(restore);
      navFieldDiagnosticsPrinter(
        '[OFFLINE_MAPS][PREVIEW_STACK] restored=$restore',
      );
    } catch (_) {
      // Best-effort restore — do not block pop.
    } finally {
      _stackArmed = false;
    }
  }

  @override
  void dispose() {
    // Fire-and-forget restore; dispose cannot await.
    unawaited(_restoreOfflineStack());
    navFieldDiagnosticsPrinter(
      '[OFFLINE_MAPS][PREVIEW_CLOSE] region_id=${widget.region.id}',
    );
    super.dispose();
  }

  Future<void> _onMapCreated(mb.MapboxMap map) async {
    _map = map;
    // Preview only: gestures on, no location component / follow.
    try {
      await map.location.updateSettings(
        mb.LocationComponentSettings(enabled: false),
      );
    } catch (_) {}
    try {
      await map.compass.updateSettings(mb.CompassSettings(enabled: false));
    } catch (_) {}
    try {
      await map.scaleBar.updateSettings(mb.ScaleBarSettings(enabled: false));
    } catch (_) {}
    await _fitCamera();
    await _drawPerimeter();
  }

  Future<void> _fitCamera() async {
    final target = _target;
    final map = _map;
    if (target == null || map == null) return;
    final bounds = driverOfflineMapPreviewBoundsFromGeometry(target.geometry);
    if (bounds != null) {
      try {
        final camera = await map.cameraForCoordinateBounds(
          mb.CoordinateBounds(
            southwest: mb.Point(
              coordinates: mb.Position(bounds.westLon, bounds.southLat),
            ),
            northeast: mb.Point(
              coordinates: mb.Position(bounds.eastLon, bounds.northLat),
            ),
            infiniteBounds: false,
          ),
          mb.MbxEdgeInsets(top: 72, left: 48, bottom: 72, right: 48),
          null,
          null,
          null,
          null,
        );
        await map.setCamera(camera);
        return;
      } catch (_) {
        // Fall through to center/zoom.
      }
    }
    await map.setCamera(
      mb.CameraOptions(
        center: mb.Point(
          coordinates: mb.Position(
            target.centerLongitude,
            target.centerLatitude,
          ),
        ),
        zoom: driverOfflineMapPreviewZoomForRadiusKm(target.radiusKm),
        pitch: 0,
        bearing: 0,
      ),
    );
  }

  Future<void> _drawPerimeter() async {
    final target = _target;
    final map = _map;
    if (target == null || map == null) return;
    final ring = driverOfflineMapPreviewPerimeterRing(target.geometry);
    if (ring.length < 2) return;
    try {
      _perimeterManager ??=
          await map.annotations.createPolylineAnnotationManager();
      await _perimeterManager!.create(
        mb.PolylineAnnotationOptions(
          geometry: mb.LineString(
            coordinates: [
              for (final p in ring) mb.Position(p[0], p[1]),
            ],
          ),
          lineColor: 0xFF2563EB,
          lineWidth: 2.5,
          lineOpacity: 0.85,
        ),
      );
    } catch (_) {
      // Perimeter is optional chrome — never fail the preview.
    }
  }

  Future<void> _onCameraChange(_) async {
    final target = _target;
    final map = _map;
    if (target == null || map == null || !mounted) return;
    final bounds = driverOfflineMapPreviewBoundsFromGeometry(target.geometry);
    if (bounds == null) return;
    try {
      final state = await map.getCameraState();
      final lon = state.center.coordinates.lng.toDouble();
      final lat = state.center.coordinates.lat.toDouble();
      final outside = !bounds.contains(latitude: lat, longitude: lon);
      if (outside != _outsideDownloadedArea && mounted) {
        setState(() => _outsideDownloadedArea = outside);
      }
    } catch (_) {}
  }

  Future<void> _toggleStyle() async {
    final target = _target;
    final map = _map;
    if (target == null || map == null || target.styleUris.length < 2) return;
    final next = (_styleIndex + 1) % target.styleUris.length;
    try {
      await map.loadStyleURI(target.styleUris[next]);
      _styleIndex = next;
      // Re-draw perimeter after style reload.
      _perimeterManager = null;
      await _drawPerimeter();
      if (mounted) setState(() {});
    } catch (_) {}
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
                          : mb.MapWidget(
                              key: Key(
                                'offline_region_preview_map_${target.regionId}_$_styleIndex',
                              ),
                              styleUri: styleUri,
                              textureView: true,
                              androidHostingMode:
                                  mb.AndroidPlatformViewHostingMode.HC,
                              cameraOptions: mb.CameraOptions(
                                center: mb.Point(
                                  coordinates: mb.Position(
                                    target.centerLongitude,
                                    target.centerLatitude,
                                  ),
                                ),
                                zoom: driverOfflineMapPreviewZoomForRadiusKm(
                                  target.radiusKm,
                                ),
                                pitch: 0,
                                bearing: 0,
                              ),
                              onMapCreated: _onMapCreated,
                              onCameraChangeListener: _onCameraChange,
                            ),
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
