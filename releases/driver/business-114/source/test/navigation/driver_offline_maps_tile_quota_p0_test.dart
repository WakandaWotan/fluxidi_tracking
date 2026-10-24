// OFFLINE-MAPS-TILE-LIMIT-PREFLIGHT-P0-2
//
// Pure quota math + failure classification for the Mapbox 750 Maps tile-pack
// cap (cumulative across TileRegions on the default TileStore).

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/navigation/driver_offline_maps_download_feedback.dart';
import 'package:fluxidi_tracking/navigation/driver_offline_maps_tile_quota.dart';

void main() {
  group('Mapbox 750 tile-pack quota math', () {
    test('1) request below available quota is allowed', () {
      final evaluation = evaluateOfflineMapsTileQuota(
        usedMapsTiles: 200,
        requestedMapsTiles: 400,
      );
      expect(evaluation.isAllowed, isTrue);
      expect(evaluation.availableMapsTiles, 550);
      expect(evaluation.projectedTotalMapsTiles, 600);
    });

    test('2) request exactly at available quota is allowed', () {
      final evaluation = evaluateOfflineMapsTileQuota(
        usedMapsTiles: 250,
        requestedMapsTiles: 500,
      );
      expect(evaluation.isAllowed, isTrue);
      expect(evaluation.availableMapsTiles, 500);
      expect(evaluation.projectedTotalMapsTiles, 750);
    });

    test('3) request above available quota is blocked', () {
      final evaluation = evaluateOfflineMapsTileQuota(
        usedMapsTiles: 300,
        requestedMapsTiles: 500,
      );
      expect(evaluation.isBlocked, isTrue);
      expect(evaluation.availableMapsTiles, 450);
      expect(evaluation.projectedTotalMapsTiles, 800);
    });

    test('4) existing regions count toward capacity (cumulative contract)', () {
      final capacity = buildOfflineMapsTileCapacity(
        regionTileCounts: <String, int>{
          'fluxidi_driver_region_maarkedal_vlaamse_ardennen_11_16': 340,
          'fluxidi_driver_region_belgium_base_6_10': 80,
          'other__estimate': 999,
        },
      );
      expect(capacity.usedMapsTiles, 420);
      expect(capacity.availableMapsTiles, 330);
      expect(capacity.limitMapsTiles, kMapboxOfflineMapsTilePackLimit);
    });

    test('5) deleting a region refreshes capacity (exclude / omit)', () {
      final before = buildOfflineMapsTileCapacity(
        regionTileCounts: <String, int>{
          'a': 400,
          'b': 200,
        },
      );
      expect(before.usedMapsTiles, 600);
      final afterDelete = buildOfflineMapsTileCapacity(
        regionTileCounts: <String, int>{
          'b': 200,
        },
      );
      expect(afterDelete.usedMapsTiles, 200);
      expect(afterDelete.availableMapsTiles, 550);
      final replaceSameId = buildOfflineMapsTileCapacity(
        regionTileCounts: <String, int>{
          'a': 400,
          'b': 200,
        },
        excludeRegionId: 'a',
      );
      expect(replaceSameId.usedMapsTiles, 200);
    });

    test('6) 60 km too large suggests largest smaller valid radius', () {
      final suggested = suggestLargestValidOfflineMapsRadiusKm(
        radiusOptionsKm: const <int>[10, 20, 40, 60],
        usedMapsTiles: 300,
        estimatedTilesForRadiusKm: (km) {
          switch (km) {
            case 60:
              return 720; // 300+720=1020 field-shaped overage
            case 40:
              return 480; // still over 450 available
            case 20:
              return 220; // fits
            case 10:
              return 90;
            default:
              return -1;
          }
        },
      );
      expect(suggested, 20);
    });

    test('7) 40 km valid is selectable when it fits', () {
      final evaluation = evaluateOfflineMapsTileQuota(
        usedMapsTiles: 200,
        requestedMapsTiles: 400,
      );
      expect(evaluation.isAllowed, isTrue);
      final suggested = suggestLargestValidOfflineMapsRadiusKm(
        radiusOptionsKm: const <int>[10, 20, 40, 60],
        usedMapsTiles: 200,
        estimatedTilesForRadiusKm: (km) => km == 40 ? 400 : 900,
      );
      expect(suggested, 40);
    });

    test('8) 20 km valid when larger radii do not fit', () {
      final suggested = suggestLargestValidOfflineMapsRadiusKm(
        radiusOptionsKm: const <int>[10, 20, 40, 60],
        usedMapsTiles: 500,
        estimatedTilesForRadiusKm: (km) {
          switch (km) {
            case 60:
              return 600;
            case 40:
              return 400;
            case 20:
              return 200;
            case 10:
              return 80;
            default:
              return -1;
          }
        },
      );
      expect(suggested, 20);
    });

    test('9) no available radius yields null suggestion', () {
      final suggested = suggestLargestValidOfflineMapsRadiusKm(
        radiusOptionsKm: const <int>[10, 20, 40, 60],
        usedMapsTiles: 700,
        estimatedTilesForRadiusKm: (_) => 100,
      );
      expect(suggested, isNull);
      expect(
        offlineMapsNoValidRadiusMessage(AppLanguage.nl),
        contains('Geen beschikbare downloadstraal'),
      );
    });

    test('15) suggestion never silently mutates the selected radius list', () {
      const options = <int>[10, 20, 40, 60];
      final suggested = suggestLargestValidOfflineMapsRadiusKm(
        radiusOptionsKm: options,
        usedMapsTiles: 0,
        estimatedTilesForRadiusKm: (km) => km <= 20 ? 100 : 900,
      );
      expect(suggested, 20);
      expect(options, <int>[10, 20, 40, 60]);
    });
  });

  group('tile_limit_exceeded classification', () {
    test('11) Mapbox 750-limit exception maps to tile_limit_exceeded', () {
      const field =
          'The tile region can\'t be loaded because it would increase '
          'the number of Maps tiles to 1020, which is beyond the maximum '
          'allowed 750 tiles.';
      expect(
        classifyDriverOfflineMapFailure(error: field, phase: 'tileRegion'),
        DriverOfflineMapFailureCategory.tileLimitExceeded,
      );
      expect(
        driverOfflineMapFailureCategoryToken(
          DriverOfflineMapFailureCategory.tileLimitExceeded,
        ),
        'tile_limit_exceeded',
      );
      expect(
        classifyDriverOfflineMapFailure(
          error:
              'DriverOfflineMapsException: Maps tile pack limit exceeded '
              '(maximum allowed 750 tiles). phase=quota',
          phase: 'download',
        ),
        DriverOfflineMapFailureCategory.tileLimitExceeded,
      );
    });

    test('NL capacity copy is actionable and non-technical', () {
      final message = driverOfflineMapFailureMessage(
        category: DriverOfflineMapFailureCategory.tileLimitExceeded,
        language: AppLanguage.nl,
      );
      expect(message, contains('offline'));
      expect(message, contains('downloadstraal'));
      expect(message.toLowerCase(), isNot(contains('mapbox')));
      expect(message.toLowerCase(), isNot(contains('exception')));
      final blocked = formatOfflineMapsTileQuotaBlockedMessage(
        language: AppLanguage.nl,
        requestedMapsTiles: 680,
        availableMapsTiles: 540,
        suggestedRadiusKm: 40,
      );
      expect(blocked, contains('680'));
      expect(blocked, contains('540'));
      expect(blocked, contains('40 km'));
    });
  });
}
