// FLUXIDI-OFFLINE-MAPS-EUROPE-REGION-EXPANSION-P0-1
//
// Thin Mapbox Geocoding v5 client for Europe offline-region search.
// Reuses the project access token ([kMapboxToken]) — no new provider/secrets.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../app_config.dart';
import 'driver_offline_maps_europe_selection.dart';

/// Searches European places for offline basemap selection.
Future<List<DriverOfflineEuropePlace>> searchDriverOfflineEuropePlaces({
  required String query,
  String languageCode = 'en',
  http.Client? client,
  String? accessToken,
}) async {
  final q = query.trim();
  if (q.isEmpty) return const <DriverOfflineEuropePlace>[];

  final token = (accessToken ?? kMapboxToken).trim();
  if (token.isEmpty) {
    if (kDebugMode) {
      debugPrint('[OFFLINE_MAPS] geocode=skip reason=missing_token');
    }
    return const <DriverOfflineEuropePlace>[];
  }

  final lang = languageCode.trim().isEmpty ? 'en' : languageCode.trim();
  final uri = Uri.parse(
    'https://api.mapbox.com/geocoding/v5/mapbox.places/'
    '${Uri.encodeComponent(q)}.json'
    '?access_token=${Uri.encodeComponent(token)}'
    '&autocomplete=true'
    '&types=place,locality,postcode,neighborhood,district'
    '&country=$kDriverOfflineEuropeGeocodeCountryCsv'
    '&language=${Uri.encodeComponent(lang)}'
    '&limit=8'
    '&bbox=$kDriverOfflineEuropeWestLon,'
    '$kDriverOfflineEuropeSouthLat,'
    '$kDriverOfflineEuropeEastLon,'
    '$kDriverOfflineEuropeNorthLat',
  );

  final httpClient = client ?? http.Client();
  final owned = client == null;
  try {
    final res = await httpClient.get(uri).timeout(const Duration(seconds: 8));
    if (res.statusCode != 200) {
      if (kDebugMode) {
        debugPrint('[OFFLINE_MAPS] geocode=fail status=${res.statusCode}');
      }
      return const <DriverOfflineEuropePlace>[];
    }
    final data = jsonDecode(res.body);
    if (data is! Map) return const <DriverOfflineEuropePlace>[];
    final features = data['features'];
    if (features is! List) return const <DriverOfflineEuropePlace>[];
    return parseDriverOfflineEuropeGeocodeFeatures(features);
  } on SocketException {
    if (kDebugMode) debugPrint('[OFFLINE_MAPS] geocode=fail reason=network');
    return const <DriverOfflineEuropePlace>[];
  } on TimeoutException {
    if (kDebugMode) debugPrint('[OFFLINE_MAPS] geocode=fail reason=timeout');
    return const <DriverOfflineEuropePlace>[];
  } on FormatException {
    if (kDebugMode) debugPrint('[OFFLINE_MAPS] geocode=fail reason=format');
    return const <DriverOfflineEuropePlace>[];
  } catch (_) {
    if (kDebugMode) debugPrint('[OFFLINE_MAPS] geocode=fail reason=unexpected');
    return const <DriverOfflineEuropePlace>[];
  } finally {
    if (owned) httpClient.close();
  }
}
