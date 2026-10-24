import 'dart:convert';
import 'package:flutter/services.dart';
import 'driver_offline_maps_europe_selection.dart';

const _catalogPath = 'assets/fluxidi_maplibre/offline_areas.json';
Future<List<Map<String, dynamic>>>? _catalog;
String _fold(String value) {
  const source = 'àáâäãåèéêëìíîïòóôöõùúûüýÿçñæœĳß';
  const target = [
    'a',
    'a',
    'a',
    'a',
    'a',
    'a',
    'e',
    'e',
    'e',
    'e',
    'i',
    'i',
    'i',
    'i',
    'o',
    'o',
    'o',
    'o',
    'o',
    'u',
    'u',
    'u',
    'u',
    'y',
    'y',
    'c',
    'n',
    'ae',
    'oe',
    'ij',
    'ss',
  ];
  final text = StringBuffer();
  for (final char in value.toLowerCase().split('')) {
    final index = source.indexOf(char);
    text.write(index < 0 ? char : target[index]);
  }
  return text.toString().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();
}

Future<List<Map<String, dynamic>>> _load(AssetBundle bundle) async {
  final text = await bundle.loadString(_catalogPath);
  if (utf8.encode(text).length > 5000000)
    throw StateError('offline_catalog_size');
  final value = jsonDecode(text);
  if (value is! Map ||
      value['schema'] != 'fluxidi-official-derived-offline-areas-v1' ||
      value['base_manifest_sha256'] !=
          'fef5ebdcdd9a2909c45cdffe74ef1ba1bbe97db7a3d54b4af9ab23b2ffc69015' ||
      value['official_address_identity'] != false ||
      value['road_access_proven'] != false ||
      value['rows'] is! List) {
    throw StateError('offline_catalog_contract');
  }
  return (value['rows'] as List)
      .map((r) {
        if (r is! Map ||
            !['BE', 'NL'].contains(r['country']) ||
            r['name'] is! String ||
            r['search'] is! String ||
            r['id'] is! String ||
            !(r['id'] as String).startsWith('fluxidi:offline-area:') ||
            r['latitude'] is! num ||
            r['longitude'] is! num ||
            !(r['latitude'] as num).isFinite ||
            !(r['longitude'] as num).isFinite ||
            (r['latitude'] as num) < 49.1 ||
            (r['latitude'] as num) > 54 ||
            (r['longitude'] as num) < 2 ||
            (r['longitude'] as num) > 7.8)
          throw StateError('offline_catalog_row');
        return {
          ...Map<String, dynamic>.from(r),
          '_name_key': _fold(r['name']),
          '_tokens': _fold(
            '${r['search']} ${r['country']} ${_country(r['country'], 'nl')} ${_country(r['country'], 'en')} ${_country(r['country'], 'fr')} ${_country(r['country'], 'de')} ${_country(r['country'], 'es')}',
          ).split(' ').toSet().toList(),
        };
      })
      .toList(growable: false);
}

String _country(String code, String language) {
  const be = {
    'nl': 'België',
    'en': 'Belgium',
    'fr': 'Belgique',
    'de': 'Belgien',
    'es': 'Bélgica',
  };
  const nl = {
    'nl': 'Nederland',
    'en': 'Netherlands',
    'fr': 'Pays-Bas',
    'de': 'Niederlande',
    'es': 'Países Bajos',
  };
  return (code == 'BE' ? be : nl)[language] ??
      (code == 'BE' ? 'Belgium' : 'Netherlands');
}

/// Local area selection only. These derived mean positions are not official
/// address points, navigation anchors, road access evidence, or booking inputs.
Future<List<DriverOfflineEuropePlace>> searchDriverOfflineBeNlAreas({
  required String query,
  String languageCode = 'en',
  AssetBundle? assets,
}) async {
  final q = _fold(query);
  if (q.length < 2) return [];
  final rows = assets != null
      ? await _load(assets)
      : await (_catalog ??= _load(rootBundle));
  final words = q.split(' ').where((s) => s.isNotEmpty).toList();
  final matches = rows.where((r) {
    final text = r['_tokens'] as List<String>;
    return words.every((word) => text.any((t) => t.startsWith(word)));
  }).toList();
  int rank(Map<String, dynamic> r) {
    final n = r['_name_key'] as String;
    return n == q
        ? 0
        : n.startsWith(q)
        ? 1
        : 2;
  }

  matches.sort((a, b) {
    final score = rank(a).compareTo(rank(b));
    return score != 0
        ? score
        : (a['name'] as String).compareTo(b['name'] as String);
  });
  return matches
      .take(8)
      .map(
        (r) => DriverOfflineEuropePlace(
          primaryName: r['name'],
          countryCode: r['country'],
          countryName: _country(r['country'], languageCode),
          latitude: (r['latitude'] as num).toDouble(),
          longitude: (r['longitude'] as num).toDouble(),
          // Legacy internal field name only; the value is explicitly an own area ID.
          mapboxFeatureId: r['id'],
          placeType: 'map-area',
        ),
      )
      .toList(growable: false);
}

/// Approximate map/service-area centre only. Exact name/postal matching avoids
/// picking the first autocomplete result in another country or municipality.
/// This value must never be used as an address, route or vehicle pickup point.
Future<({double latitude,double longitude})?> resolveBeNlAreaCenter({
  required String query,
  required String countryCode,
  AssetBundle? assets,
}) async {
  if (!['BE','NL'].contains(countryCode)) return null;
  final q = _fold(query);
  if (q.length < 3) return null;
  final rows = assets != null ? await _load(assets) : await (_catalog ??= _load(rootBundle));
  final exact = rows.where((r) => r['country'] == countryCode && r['_name_key'] == q).toList();
  final matches = exact.isNotEmpty ? exact : RegExp(r'^\d{4}$').hasMatch(q)
      ? rows.where((r) => r['country'] == countryCode && (r['search'] as String).split(' ').first == q).toList()
      : <Map<String,dynamic>>[];
  if (matches.length != 1) return null;
  return (latitude:(matches.single['latitude'] as num).toDouble(),longitude:(matches.single['longitude'] as num).toDouble());
}
