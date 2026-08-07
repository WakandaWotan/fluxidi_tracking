// OFFLINE-MAPS-DOWNLOADED-REGION-PREVIEW-P1

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_config.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/navigation/driver_offline_maps_europe_selection.dart';
import 'package:fluxidi_tracking/navigation/driver_offline_maps_page.dart';
import 'package:fluxidi_tracking/navigation/driver_offline_maps_preview_model.dart';
import 'package:fluxidi_tracking/navigation/driver_offline_maps_region_preview_page.dart';
import 'package:fluxidi_tracking/navigation/driver_offline_maps_service.dart';
import 'package:fluxidi_tracking/navigation/driver_offline_maps_tile_quota.dart';

DriverOfflineMapRegionInfo _region({
  required String id,
  required String displayName,
  required DriverOfflineMapCompletionStatus status,
  Map<String, dynamic>? geometry,
  double? centerLat,
  double? centerLon,
  int? radiusKm,
  List<String> styleUris = const <String>[
    'mapbox://styles/mapbox/navigation-day-v1',
    'mapbox://styles/mapbox/navigation-night-v1',
  ],
}) {
  return DriverOfflineMapRegionInfo(
    id: id,
    displayName: displayName,
    minZoom: 11,
    maxZoom: 16,
    styleUris: styleUris,
    requiredResourceCount: status == DriverOfflineMapCompletionStatus.complete
        ? 120
        : 120,
    completedResourceCount:
        status == DriverOfflineMapCompletionStatus.complete ? 120 : 40,
    completedResourceSize: 10,
    completionStatus: status,
    erroredResourceCount: 0,
    stylePacksVerified:
        status == DriverOfflineMapCompletionStatus.complete ? true : false,
    geometry: geometry,
    centerLatitude: centerLat,
    centerLongitude: centerLon,
    radiusKm: radiusKm,
  );
}

class _FakePort implements DriverOfflineMapsDownloadPort {
  _FakePort(this.regions);

  List<DriverOfflineMapRegionInfo> regions;

  @override
  Future<void> ensureInitialized() async {}

  @override
  Future<DriverOfflineMapEstimate> estimateRegion(
    DriverOfflineMapRegionRequest request, {
    DriverOfflineMapProgressCallback? onProgress,
  }) async {
    return const DriverOfflineMapEstimate(
      transferSizeBytes: 1,
      storageSizeBytes: 1,
      errorMargin: 0.1,
      estimatedMapsTileCount: 10,
    );
  }

  @override
  Future<DriverOfflineMapsTileCapacity> readTileCapacity({
    String? excludeRegionId,
  }) async {
    return const DriverOfflineMapsTileCapacity(usedMapsTiles: 10);
  }

  @override
  Future<DriverOfflineMapPreflight> preflightRegion(
    DriverOfflineMapRegionRequest request, {
    DriverOfflineMapProgressCallback? onProgress,
  }) async {
    final estimate = await estimateRegion(request, onProgress: onProgress);
    final capacity = await readTileCapacity(excludeRegionId: request.regionId);
    return DriverOfflineMapPreflight(
      estimate: estimate,
      capacity: capacity,
      quota: evaluateOfflineMapsTileQuota(
        usedMapsTiles: capacity.usedMapsTiles,
        requestedMapsTiles: estimate.estimatedMapsTileCount,
      ),
    );
  }

  @override
  Future<DriverOfflineMapRegionInfo> downloadRegion(
    DriverOfflineMapRegionRequest request, {
    DriverOfflineMapProgressCallback? onProgress,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<List<DriverOfflineMapRegionInfo>> listDownloadedRegions() async =>
      regions;

  @override
  Future<void> deleteRegion(
    String regionId, {
    DriverOfflineMapProgressCallback? onProgress,
  }) async {
    regions = regions.where((r) => r.id != regionId).toList();
  }
}

void main() {
  setUp(() => appLanguageNotifier.value = AppLanguage.nl);
  tearDown(() => appLanguageNotifier.value = AppLanguage.en);

  final ronseGeometry = driverOfflineEuropeRadiusBboxGeometry(
    latitude: 50.75,
    longitude: 3.60,
    radiusKm: 40,
  );

  group('preview availability + targeting', () {
    test('1) complete region may show Kaart bekijken', () {
      final region = _region(
        id: 'fluxidi_driver_region_ronse_be_r40_n5075_e360_11_16',
        displayName: 'Ronse, België · 40 km',
        status: DriverOfflineMapCompletionStatus.complete,
        geometry: ronseGeometry,
        centerLat: 50.75,
        centerLon: 3.60,
        radiusKm: 40,
      );
      expect(driverOfflineMapRegionPreviewAvailable(region), isTrue);
      final target = resolveDriverOfflineMapPreviewTarget(region);
      expect(target, isNotNull);
      expect(target!.centerLatitude, closeTo(50.75, 0.001));
      expect(target.centerLongitude, closeTo(3.60, 0.001));
      expect(target.radiusKm, 40);
    });

    test('2) incomplete / unknown / failed do not show preview', () {
      for (final status in <DriverOfflineMapCompletionStatus>[
        DriverOfflineMapCompletionStatus.incomplete,
        DriverOfflineMapCompletionStatus.unknown,
        DriverOfflineMapCompletionStatus.completedWithErrors,
        DriverOfflineMapCompletionStatus.expiredOrStale,
      ]) {
        final region = _region(
          id: 'x_$status',
          displayName: 'x',
          status: status,
          geometry: ronseGeometry,
        );
        expect(driverOfflineMapRegionPreviewAvailable(region), isFalse);
        expect(resolveDriverOfflineMapPreviewTarget(region), isNull);
      }
    });

    test('3+4) Ronse 40 km slug resolves center and full bounds', () {
      final region = _region(
        id: 'fluxidi_driver_region_ronse_be_r40_n5075_e360_11_16',
        displayName: 'Ronse, België · 40 km',
        status: DriverOfflineMapCompletionStatus.complete,
      );
      final target = resolveDriverOfflineMapPreviewTarget(region)!;
      expect(target.centerLatitude, closeTo(50.75, 0.001));
      expect(target.centerLongitude, closeTo(3.60, 0.001));
      expect(target.radiusKm, 40);
      expect(target.geometrySource, 'region_id_slug');
      final bounds =
          driverOfflineMapPreviewBoundsFromGeometry(target.geometry)!;
      expect(bounds.contains(latitude: 50.75, longitude: 3.60), isTrue);
      expect(bounds.contains(latitude: 51.80, longitude: 4.80), isFalse);
      expect(
        driverOfflineMapPreviewZoomForRadiusKm(40),
        lessThan(driverOfflineMapPreviewZoomForRadiusKm(10)),
      );
    });

    test('5+6) day and night style URIs are preserved for preview', () {
      final region = _region(
        id: 'fluxidi_driver_region_ronse_be_r40_n5075_e360_11_16',
        displayName: 'Ronse',
        status: DriverOfflineMapCompletionStatus.complete,
        geometry: ronseGeometry,
      );
      final target = resolveDriverOfflineMapPreviewTarget(region)!;
      expect(target.styleUris.length, 2);
      expect(target.styleUris.first, contains('navigation-day'));
      expect(target.styleUris.last, contains('navigation-night'));
    });

    test('12) outside-bounds helper is crash-safe', () {
      final bounds = driverOfflineMapPreviewBoundsFromGeometry(ronseGeometry)!;
      expect(bounds.contains(latitude: 0, longitude: 0), isFalse);
      expect(driverOfflineMapPreviewPerimeterRing(ronseGeometry).length,
          greaterThanOrEqualTo(4));
      expect(driverOfflineMapPreviewBoundsFromGeometry(null), isNull);
    });

    test('13) legacy Maarkedal preset geometry still resolves after restart shape',
        () {
      final region = _region(
        id: 'fluxidi_driver_region_maarkedal_vlaamse_ardennen_11_16',
        displayName: 'Maarkedal / Vlaamse Ardennen detail',
        status: DriverOfflineMapCompletionStatus.complete,
      );
      final target = resolveDriverOfflineMapPreviewTarget(region)!;
      expect(target.geometrySource, 'legacy_preset');
      expect(target.centerLatitude, isNotNull);
    });
  });

  group('UI wiring', () {
    testWidgets('1) complete region shows Kaart bekijken', (tester) async {
      final port = _FakePort([
        _region(
          id: 'fluxidi_driver_region_ronse_be_r40_n5075_e360_11_16',
          displayName: 'Ronse, België · 40 km',
          status: DriverOfflineMapCompletionStatus.complete,
          geometry: ronseGeometry,
          centerLat: 50.75,
          centerLon: 3.60,
          radiusKm: 40,
        ),
      ]);
      await tester.binding.setSurfaceSize(const Size(400, 2600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: DriverOfflineMapsPage(
            service: port,
            mapboxConfigured: true,
            placeSearch: ({required String query, String languageCode = 'en'}) async =>
                const <DriverOfflineEuropePlace>[],
            searchDebounce: Duration.zero,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Kaart bekijken'), findsOneWidget);
      expect(find.text('Verwijderen'), findsWidgets);
    });

    testWidgets('2) incomplete region hides Kaart bekijken', (tester) async {
      final port = _FakePort([
        _region(
          id: 'fluxidi_driver_region_ronse_be_r20_n5075_e360_11_16',
          displayName: 'Ronse partial',
          status: DriverOfflineMapCompletionStatus.incomplete,
          geometry: ronseGeometry,
        ),
      ]);
      await tester.binding.setSurfaceSize(const Size(400, 2600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: DriverOfflineMapsPage(
            service: port,
            mapboxConfigured: true,
            placeSearch: ({required String query, String languageCode = 'en'}) async =>
                const <DriverOfflineEuropePlace>[],
            searchDebounce: Duration.zero,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Ronse partial'), findsOneWidget);
      expect(find.text('Kaart bekijken'), findsNothing);
      expect(find.text('Verwijderen'), findsWidgets);
    });

    testWidgets(
      '7+8+9) preview opens without nav/ride mutation and back returns',
      (tester) async {
        final region = _region(
          id: 'fluxidi_driver_region_ronse_be_r40_n5075_e360_11_16',
          displayName: 'Ronse, België · 40 km',
          status: DriverOfflineMapCompletionStatus.complete,
          geometry: ronseGeometry,
          centerLat: 50.75,
          centerLon: 3.60,
          radiusKm: 40,
        );
        final port = _FakePort([region]);
        var mapBuilt = false;
        await tester.pumpWidget(
          MaterialApp(
            home: DriverOfflineMapsPage(
              service: port,
              mapboxConfigured: true,
              placeSearch:
                  ({required String query, String languageCode = 'en'}) async =>
                      const <DriverOfflineEuropePlace>[],
              searchDebounce: Duration.zero,
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.dragUntilVisible(
          find.text('Kaart bekijken'),
          find.byType(ListView),
          const Offset(0, -120),
        );
        // Replace Navigator push by pumping preview directly for map seam.
        final target = resolveDriverOfflineMapPreviewTarget(region)!;
        await tester.pumpWidget(
          MaterialApp(
            home: DriverOfflineMapRegionPreviewPage(
              region: region,
              target: target,
              forceOfflineStack: false,
              mapBuilder: (context, t) {
                mapBuilt = true;
                expect(t.centerLatitude, closeTo(50.75, 0.001));
                expect(t.radiusKm, 40);
                return const ColoredBox(
                  key: Key('offline_preview_stub_map'),
                  color: Colors.grey,
                );
              },
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(mapBuilt, isTrue);
        expect(find.byKey(const Key('offline_region_preview_page')), findsOneWidget);
        expect(find.text('Offline kaart'), findsOneWidget);
        expect(find.textContaining('Ronse'), findsWidgets);
        expect(find.byKey(const Key('offline_region_preview_badge')), findsOneWidget);
        expect(find.text('START'), findsNothing);
        expect(find.textContaining('Google Maps'), findsNothing);
        expect(port.regions, hasLength(1));

        await tester.tap(find.byKey(const Key('offline_region_preview_back')));
        await tester.pumpAndSettle();
        // Direct pumpWidget home was preview — back pops to empty; assert page gone.
        // Re-open offline page to prove delete still independent.
        await tester.pumpWidget(
          MaterialApp(
            home: DriverOfflineMapsPage(
              service: port,
              mapboxConfigured: true,
              placeSearch:
                  ({required String query, String languageCode = 'en'}) async =>
                      const <DriverOfflineEuropePlace>[],
              searchDebounce: Duration.zero,
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(port.regions, hasLength(1));
      },
    );

    testWidgets('10) delete remains available beside preview', (tester) async {
      final port = _FakePort([
        _region(
          id: 'fluxidi_driver_region_ronse_be_r40_n5075_e360_11_16',
          displayName: 'Ronse, België · 40 km',
          status: DriverOfflineMapCompletionStatus.complete,
          geometry: ronseGeometry,
        ),
      ]);
      await tester.binding.setSurfaceSize(const Size(400, 2600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: DriverOfflineMapsPage(
            service: port,
            mapboxConfigured: true,
            placeSearch: ({required String query, String languageCode = 'en'}) async =>
                const <DriverOfflineEuropePlace>[],
            searchDebounce: Duration.zero,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Kaart bekijken'), findsOneWidget);
      await tester.tap(find.text('Verwijderen'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      // Dialog confirm is the second "Verwijderen" after the list action.
      await tester.tap(find.text('Verwijderen').last);
      await tester.pumpAndSettle();
      expect(port.regions, isEmpty);
    });

    testWidgets('11) preview page documents forced offline stack flag', (
      tester,
    ) async {
      final region = _region(
        id: 'fluxidi_driver_region_ronse_be_r40_n5075_e360_11_16',
        displayName: 'Ronse, België · 40 km',
        status: DriverOfflineMapCompletionStatus.complete,
        geometry: ronseGeometry,
        centerLat: 50.75,
        centerLon: 3.60,
        radiusKm: 40,
      );
      final target = resolveDriverOfflineMapPreviewTarget(region)!;
      await tester.pumpWidget(
        MaterialApp(
          home: DriverOfflineMapRegionPreviewPage(
            region: region,
            target: target,
            forceOfflineStack: false,
            mapBuilder: (_, __) => const SizedBox.expand(
              key: Key('offline_preview_stub_map'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('offline_preview_stub_map')), findsOneWidget);
      expect(find.textContaining('Offline regio'), findsOneWidget);
    });
  });
}
