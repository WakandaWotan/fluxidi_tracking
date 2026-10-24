import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:fluxidi_tracking/navigation/driver_offline_be_nl_catalog.dart';
import 'package:fluxidi_tracking/navigation/driver_offline_maps_europe_geocoder.dart';

class _Asset extends CachingAssetBundle {
  _Asset(this.body);
  final Object body;
  @override
  Future<ByteData> load(String key) async =>
      ByteData.sublistView(Uint8List.fromList(utf8.encode(jsonEncode(body))));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final catalog = jsonDecode(
    File('assets/fluxidi_maplibre/offline_areas.json').readAsStringSync(),
  );
  test('service-area centre supports BE/NL without provider or first-prefix guess',() async {
    for(final item in [('Gent','BE'),('9000','BE'),('Amsterdam','NL'),('1011','NL')]) {
      final point=await resolveBeNlAreaCenter(query:item.$1,countryCode:item.$2,assets:_Asset(catalog));
      expect(point,isNotNull);
    }
    expect(await resolveBeNlAreaCenter(query:'Gent',countryCode:'NL',assets:_Asset(catalog)),isNull);
    expect(await resolveBeNlAreaCenter(query:'Gente',countryCode:'BE',assets:_Asset(catalog)),isNull);
    expect(await resolveBeNlAreaCenter(query:'Teststraat 9',countryCode:'BE',assets:_Asset(catalog)),isNull);
  });
  for (final entry in [
    ('Gent', 'BE'),
    ('Bruxelles', 'BE'),
    ('Eupen', 'BE'),
    ('Amsterdam', 'NL'),
    ('Rotterdam', 'NL'),
    ('Utrecht', 'NL'),
    ('9700', 'BE'),
  ]) {
    test(
      'real bundled derived area ${entry.$1} without provider or address/access claim',
      () async {
        final results = await searchDriverOfflineBeNlAreas(
          query: entry.$1,
          assets: _Asset(catalog),
        );
        expect(results, isNotEmpty);
        expect(results.every((r) => r.countryCode == entry.$2), true);
        expect(
          results.every(
            (r) => r.mapboxFeatureId.startsWith('fluxidi:offline-area:'),
          ),
          true,
        );
        expect(results.every((r) => r.placeType == 'map-area'), true);
        expect(results.length, lessThanOrEqualTo(8));
      },
    );
  }
  test(
    'exact city precedes its postal regions and language changes only country label',
    () async {
      final a = await searchDriverOfflineBeNlAreas(
        query: 'Gent',
        assets: _Asset(catalog),
        languageCode: 'nl',
      );
      final b = await searchDriverOfflineBeNlAreas(
        query: 'Gent',
        assets: _Asset(catalog),
        languageCode: 'fr',
      );
      expect(a.first.primaryName, 'Gent');
      expect(a.first.mapboxFeatureId, b.first.mapboxFeatureId);
      expect(a.first.countryName, 'België');
      expect(b.first.countryName, 'Belgique');
    },
  );
  test(
    'no empty, too broad single character or unsupported foreign area request',
    () async {
      for (final query in ['', 'a', 'Paris', 'Berlin'])
        expect(
          await searchDriverOfflineBeNlAreas(
            query: query,
            assets: _Asset(catalog),
          ),
          isEmpty,
        );
    },
  );
  test('corrupt or falsely authoritative catalog fails closed', () async {
    for (final patch in [
      {'schema': 'wrong'},
      {'official_address_identity': true},
      {'road_access_proven': true},
      {'base_manifest_sha256': 'wrong'},
    ]) {
      await expectLater(
        searchDriverOfflineBeNlAreas(
          query: 'Gent',
          assets: _Asset({...catalog as Map, ...patch}),
        ),
        throwsStateError,
      );
    }
  });
  test(
    'existing geocoder entry point never calls supplied HTTP provider client',
    () async {
      var requests = 0;
      final client = MockClient((r) async {
        requests++;
        throw StateError('PROVIDER_FORBIDDEN');
      });
      final result = await searchDriverOfflineEuropePlaces(
        query: 'Gent',
        client: client,
        accessToken: 'unused',
      );
      expect(result, isNotEmpty);
      expect(requests, 0);
      client.close();
    },
  );
}
