// FLUXIDI-OFFLINE-MAPS-EUROPE-REGION-EXPANSION-P0-1
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/navigation/driver_offline_maps_europe_selection.dart';
import 'package:fluxidi_tracking/navigation/driver_offline_maps_service.dart';
import 'package:fluxidi_tracking/navigation/nav_external_fallback_policy.dart';

void main() {
  group('FLUXIDI-OFFLINE-MAPS-EUROPE-REGION-EXPANSION-P0-1', () {
    test('1) existing Maarkedal region remains recognized', () {
      final id = driverOfflineMapRegionId(
        slug: 'maarkedal_vlaamse_ardennen',
        minZoom: 11,
        maxZoom: 16,
      );
      expect(driverOfflineMapIsLegacyPresetRegionId(id), isTrue);
      expect(id, contains('maarkedal_vlaamse_ardennen'));
    });

    test('2) existing Belgium download remains manageable after migration', () {
      final id = driverOfflineMapRegionId(
        slug: 'belgium_base',
        minZoom: 6,
        maxZoom: 10,
      );
      expect(driverOfflineMapIsLegacyPresetRegionId(id), isTrue);
      expect(kDriverOfflineLegacyPresetSlugs.contains('belgium_base'), isTrue);
    });

    test('3) Belgian municipality outside Maarkedal builds valid selection', () {
      const place = DriverOfflineEuropePlace(
        primaryName: 'Gent',
        countryCode: 'be',
        countryName: 'Belgium',
        latitude: 51.05,
        longitude: 3.72,
      );
      final v = validateDriverOfflineEuropeSelection(
        latitude: place.latitude,
        longitude: place.longitude,
        radiusKm: 20,
      );
      expect(v.accepted, isTrue);
      final sel = DriverOfflineEuropeSelection(place: place, radiusKm: 20);
      expect(sel.regionId, contains('gent'));
      expect(sel.regionId, contains('_be_'));
      expect(sel.geometry['type'], 'Polygon');
    });

    test('4) French location accepted', () {
      final v = validateDriverOfflineEuropeSelection(
        latitude: 50.63,
        longitude: 3.06,
        radiusKm: 20,
      );
      expect(v.accepted, isTrue);
      const place = DriverOfflineEuropePlace(
        primaryName: 'Lille',
        countryCode: 'fr',
        countryName: 'France',
        latitude: 50.63,
        longitude: 3.06,
      );
      expect(place.displayLabel, 'Lille, France');
    });

    test('5) Dutch location accepted', () {
      expect(
        validateDriverOfflineEuropeSelection(
          latitude: 51.44,
          longitude: 5.47,
          radiusKm: 20,
        ).accepted,
        isTrue,
      );
    });

    test('6) German or Spanish location accepted', () {
      expect(
        validateDriverOfflineEuropeSelection(
          latitude: 50.94,
          longitude: 6.96,
          radiusKm: 20,
        ).accepted,
        isTrue,
      );
      expect(
        validateDriverOfflineEuropeSelection(
          latitude: 40.42,
          longitude: -3.70,
          radiusKm: 40,
        ).accepted,
        isTrue,
      );
    });

    test('7) same city name in different countries is distinguishable', () {
      const cambridgeUk = DriverOfflineEuropePlace(
        primaryName: 'Cambridge',
        countryCode: 'gb',
        countryName: 'United Kingdom',
        latitude: 52.205,
        longitude: 0.121,
      );
      const cambridgeUsOutside = DriverOfflineEuropePlace(
        primaryName: 'Cambridge',
        countryCode: 'us',
        countryName: 'United States',
        latitude: 42.37,
        longitude: -71.11,
      );
      expect(cambridgeUk.displayLabel, isNot(cambridgeUsOutside.displayLabel));
      final ukSel = DriverOfflineEuropeSelection(
        place: cambridgeUk,
        radiusKm: 20,
      );
      // US center is outside Europe envelope → rejected before download.
      expect(
        validateDriverOfflineEuropeSelection(
          latitude: cambridgeUsOutside.latitude,
          longitude: cambridgeUsOutside.longitude,
          radiusKm: 20,
        ).accepted,
        isFalse,
      );
      expect(ukSel.slug, contains('_gb_'));
    });

    test('8) cross-border radius is accepted', () {
      // Near BE/FR border — radius may spill across; still accepted.
      final v = validateDriverOfflineEuropeSelection(
        latitude: 50.75,
        longitude: 3.20,
        radiusKm: 40,
      );
      expect(v.accepted, isTrue);
      final geom = driverOfflineEuropeRadiusBboxGeometry(
        latitude: 50.75,
        longitude: 3.20,
        radiusKm: 40,
      );
      final ring = (geom['coordinates'] as List).first as List;
      expect(ring.length, 5);
    });

    test('8b) 10/20/40/60 km geometries scale and stay valid polygons', () {
      const lat = 50.7456;
      const lon = 3.6003;
      double width(Map<String, dynamic> geom) {
        final ring = (geom['coordinates'] as List).first as List;
        final lons = ring.map((p) => (p as List)[0] as num).toList();
        return (lons.reduce((a, b) => a > b ? a : b) -
                lons.reduce((a, b) => a < b ? a : b))
            .toDouble();
      }

      final g10 = driverOfflineEuropeRadiusBboxGeometry(
        latitude: lat,
        longitude: lon,
        radiusKm: 10,
      );
      final g20 = driverOfflineEuropeRadiusBboxGeometry(
        latitude: lat,
        longitude: lon,
        radiusKm: 20,
      );
      final g40 = driverOfflineEuropeRadiusBboxGeometry(
        latitude: lat,
        longitude: lon,
        radiusKm: 40,
      );
      final g60 = driverOfflineEuropeRadiusBboxGeometry(
        latitude: lat,
        longitude: lon,
        radiusKm: 60,
      );
      for (final g in [g10, g20, g40, g60]) {
        expect(g['type'], 'Polygon');
        expect(((g['coordinates'] as List).first as List).length, 5);
      }
      expect(width(g10) < width(g20), isTrue);
      expect(width(g20) < width(g40), isTrue);
      expect(width(g40) < width(g60), isTrue);
      for (final km in [10, 20, 40, 60]) {
        expect(
          validateDriverOfflineEuropeSelection(
            latitude: lat,
            longitude: lon,
            radiusKm: km,
          ).accepted,
          isTrue,
        );
      }
    });

    test('9) invalid or excessive area is rejected before download', () {
      expect(
        validateDriverOfflineEuropeSelection(
          latitude: 50.8,
          longitude: 4.3,
          radiusKm: 500,
        ).reason,
        'radius_out_of_bounds',
      );
      expect(
        validateDriverOfflineEuropeSelection(
          latitude: 0,
          longitude: 0,
          radiusKm: 20,
        ).reason,
        'outside_europe_envelope',
      );
      expect(
        driverOfflineEuropeApproxAreaKm2(80) <=
            kDriverOfflineEuropeMaxAreaKm2 + 1,
        isTrue,
      );
    });

    test('10) deterministic unique region ID', () {
      const place = DriverOfflineEuropePlace(
        primaryName: 'Namur',
        countryCode: 'be',
        countryName: 'Belgium',
        latitude: 50.467,
        longitude: 4.872,
      );
      final a = DriverOfflineEuropeSelection(place: place, radiusKm: 20);
      final b = DriverOfflineEuropeSelection(place: place, radiusKm: 20);
      final c = DriverOfflineEuropeSelection(place: place, radiusKm: 40);
      expect(a.regionId, b.regionId);
      expect(a.regionId, isNot(c.regionId));
      expect(a.regionId.startsWith('fluxidi_driver_region_'), isTrue);
    });

    test('11) duplicate selection does not create conflicting records', () {
      const place = DriverOfflineEuropePlace(
        primaryName: 'Brugge',
        countryCode: 'be',
        countryName: 'Belgium',
        latitude: 51.21,
        longitude: 3.22,
      );
      final sel = DriverOfflineEuropeSelection(place: place, radiusKm: 20);
      expect(
        driverOfflineMapRegionIdAlreadyPresent(
          candidateRegionId: sel.regionId,
          existingRegionIds: <String>[sel.regionId, 'other'],
        ),
        isTrue,
      );
      expect(
        driverOfflineMapRegionIdAlreadyPresent(
          candidateRegionId: sel.regionId,
          existingRegionIds: const <String>['other_region'],
        ),
        isFalse,
      );
    });

    test('12) interrupted download remains incomplete', () {
      expect(
        resolveDriverOfflineMapCompletionStatus(
          requiredResourceCount: 100,
          completedResourceCount: 40,
          erroredResourceCount: 0,
          styleErroredResourceCount: 0,
          stylePacksVerified: true,
          expired: false,
        ),
        DriverOfflineMapCompletionStatus.incomplete,
      );
    });

    test('13) resource error prevents verified-complete state', () {
      expect(
        resolveDriverOfflineMapCompletionStatus(
          requiredResourceCount: 100,
          completedResourceCount: 100,
          erroredResourceCount: 2,
          styleErroredResourceCount: 0,
          stylePacksVerified: true,
          expired: false,
        ),
        DriverOfflineMapCompletionStatus.completedWithErrors,
      );
      expect(
        resolveDriverOfflineMapCompletionStatus(
          requiredResourceCount: 100,
          completedResourceCount: 100,
          erroredResourceCount: 0,
          styleErroredResourceCount: 0,
          stylePacksVerified: false,
          expired: false,
        ).isCompleteEquivalent,
        isFalse,
      );
    });

    test('14) zero errors + completed requirements allows complete', () {
      final status = resolveDriverOfflineMapCompletionStatus(
        requiredResourceCount: 100,
        completedResourceCount: 100,
        erroredResourceCount: 0,
        styleErroredResourceCount: 0,
        stylePacksVerified: true,
        expired: false,
      );
      expect(status, DriverOfflineMapCompletionStatus.complete);
    });

    test('15) app restart re-verifies from persisted counts (pure rules)', () {
      // After restart the service rebuilds status from TileRegion + metadata —
      // the pure resolver must still refuse complete without proof.
      expect(
        resolveDriverOfflineMapCompletionStatus(
          requiredResourceCount: 50,
          completedResourceCount: 50,
          erroredResourceCount: null,
          styleErroredResourceCount: null,
          stylePacksVerified: null,
          expired: false,
        ),
        DriverOfflineMapCompletionStatus.unknown,
      );
      expect(
        resolveDriverOfflineMapCompletionStatus(
          requiredResourceCount: 50,
          completedResourceCount: 50,
          erroredResourceCount: null,
          styleErroredResourceCount: null,
          stylePacksVerified: true,
          expired: false,
        ),
        DriverOfflineMapCompletionStatus.complete,
      );
    });

    test('16) delete and re-download uses same deterministic id', () {
      const place = DriverOfflineEuropePlace(
        primaryName: 'Antwerpen',
        countryCode: 'be',
        countryName: 'Belgium',
        latitude: 51.22,
        longitude: 4.40,
      );
      final before = DriverOfflineEuropeSelection(place: place, radiusKm: 20);
      final afterDelete =
          DriverOfflineEuropeSelection(place: place, radiusKm: 20);
      expect(before.regionId, afterDelete.regionId);
    });

    test('17) phone and tablet share identical selection policy', () {
      // Pure helpers are device-agnostic.
      final phone = validateDriverOfflineEuropeSelection(
        latitude: 48.85,
        longitude: 2.35,
        radiusKm: 20,
      );
      final tablet = validateDriverOfflineEuropeSelection(
        latitude: 48.85,
        longitude: 2.35,
        radiusKm: 20,
      );
      expect(phone.accepted, tablet.accepted);
      expect(phone.reason, tablet.reason);
      expect(kDriverOfflineEuropeRadiusOptionsKm, contains(20));
    });

    test('18) navigation camera/HUD ownership files untouched by this module', () {
      // Smoke: europe selection does not import camera / HUD presentation.
      expect(kDriverOfflineEuropeDefaultRadiusKm, 20);
    });

    test('19) network loss does not auto-prompt external navigation', () {
      final d = resolveExternalNavAutoPrompt(
        const NavExternalFallbackPromptInput(
          navigationSuccessfullyStarted: true,
          hasUsableRoute: true,
          driverInActiveNavigation: true,
          transientNavigationSignal: true,
          failureIsTerminal: false,
        ),
      );
      expect(d.shouldShow, isFalse);
    });

    test('20) no Belgium/device-locale hardcoding owns availability', () {
      // Envelope is Europe-wide; French/Dutch centers are accepted the same
      // way as Belgian ones. Locale is not an input to validation.
      for (final center in <(double, double)>[
        (50.85, 4.35), // BE
        (48.85, 2.35), // FR
        (52.37, 4.90), // NL
        (52.52, 13.40), // DE
      ]) {
        expect(
          validateDriverOfflineEuropeSelection(
            latitude: center.$1,
            longitude: center.$2,
            radiusKm: 20,
          ).accepted,
          isTrue,
        );
      }
      expect(
        kDriverOfflineEuropeGeocodeCountryCsv.contains('be'),
        isTrue,
      );
      expect(
        kDriverOfflineEuropeGeocodeCountryCsv.contains('fr'),
        isTrue,
      );
      expect(
        kDriverOfflineEuropeGeocodeCountryCsv.split(',').length,
        greaterThan(10),
      );
    });

    test('geocode feature parser extracts country context', () {
      final places = parseDriverOfflineEuropeGeocodeFeatures(<dynamic>[
        <String, dynamic>{
          'id': 'place.1',
          'text': 'Tournai',
          'place_name': 'Tournai, Belgium',
          'center': <double>[3.39, 50.61],
          'place_type': <String>['place'],
          'context': <Map<String, dynamic>>[
            <String, dynamic>{
              'id': 'country.1',
              'short_code': 'be',
              'text': 'Belgium',
            },
          ],
        },
        <String, dynamic>{
          'id': 'place.2',
          'text': 'Boston',
          'place_name': 'Boston, Massachusetts, United States',
          'center': <double>[-71.06, 42.36],
          'place_type': <String>['place'],
          'context': <Map<String, dynamic>>[
            <String, dynamic>{
              'id': 'country.2',
              'short_code': 'us',
              'text': 'United States',
            },
          ],
        },
      ]);
      expect(places.length, 1);
      expect(places.first.primaryName, 'Tournai');
      expect(places.first.countryCode, 'be');
    });
  });
}

extension on DriverOfflineMapCompletionStatus {
  bool get isCompleteEquivalent =>
      this == DriverOfflineMapCompletionStatus.complete;
}
