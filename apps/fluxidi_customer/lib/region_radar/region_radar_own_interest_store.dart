import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:fluxidi_tracking/business/regional_demand_consistency.dart';
import 'package:fluxidi_tracking/fluxidi_runtime_env.dart';
import 'package:path_provider/path_provider.dart';

import 'region_radar_map_interest.dart';

/// Remembers which region this device successfully registered, so the own
/// mark can return without a public identity API.
///
/// The radar GET cannot say “this visitor already registered here”. The
/// worker only dedupes on a contact key and never returns names or emails.
class RegionRadarOwnInterestStore {
  RegionRadarOwnInterestStore() : _memoryOnly = false;

  RegionRadarOwnInterestStore.memory([Iterable<String>? seed])
    : _memoryOnly = true {
    _keys.addAll(seed ?? const <String>[]);
    _loaded = true;
  }

  static const _stateDirName = 'customer_state';
  static const _fileName = 'customer_region_radar_own_v1.json';

  final Set<String> _keys = <String>{};
  final bool _memoryOnly;
  bool _loaded = false;

  Future<File> _file() async {
    final base = await getApplicationDocumentsDirectory();
    final root = Directory(
      '${base.path}${Platform.pathSeparator}'
      '${fluxidiRuntimeStateDirName(_stateDirName)}',
    );
    if (!await root.exists()) {
      await root.create(recursive: true);
    }
    return File('${root.path}${Platform.pathSeparator}$_fileName');
  }

  Future<void> ensureLoaded() async {
    if (_loaded) return;
    if (_memoryOnly) {
      _loaded = true;
      return;
    }
    try {
      final file = await _file();
      if (await file.exists()) {
        final decoded = jsonDecode(await file.readAsString());
        if (decoded is Map && decoded['regions'] is List) {
          for (final item in decoded['regions'] as List<dynamic>) {
            final key = item.toString().trim();
            if (key.contains('|')) _keys.add(key);
          }
        }
      }
    } catch (error) {
      debugPrint('[REGION_RADAR][OWN_LOAD_ERROR] $error');
    }
    _loaded = true;
  }

  Future<bool> contains({
    required String country,
    required String postcode,
  }) async {
    await ensureLoaded();
    final key = _normalizedKey(country: country, postcode: postcode);
    if (key == null) return false;
    return _keys.contains(key);
  }

  Future<void> remember({
    required String country,
    required String postcode,
  }) async {
    await ensureLoaded();
    final key = _normalizedKey(country: country, postcode: postcode);
    if (key == null || _keys.contains(key)) return;
    _keys.add(key);
    if (_memoryOnly) return;
    try {
      final file = await _file();
      await file.writeAsString(
        jsonEncode(<String, dynamic>{
          'regions': _keys.toList(growable: false),
          'updatedAt': DateTime.now().toUtc().toIso8601String(),
        }),
        flush: true,
      );
    } catch (error) {
      debugPrint('[REGION_RADAR][OWN_SAVE_ERROR] $error');
    }
  }

  String? _normalizedKey({
    required String country,
    required String postcode,
  }) {
    final normalizedCountry = parseDemandRadarCountryCode(country);
    final normalizedPostcode = normalizeDemandRadarPostcode(postcode);
    if (normalizedCountry.isEmpty || normalizedPostcode.isEmpty) return null;
    return regionRadarOwnKey(
      country: normalizedCountry,
      postcode: normalizedPostcode,
    );
  }
}
