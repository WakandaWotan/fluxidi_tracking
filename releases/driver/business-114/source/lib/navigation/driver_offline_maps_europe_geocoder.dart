// Compatibility entry point for the existing offline selection UI.
// BE/NL area search uses only bundled own data; no provider request or token.
import 'package:http/http.dart' as http;
import 'driver_offline_maps_europe_selection.dart';
import 'driver_offline_be_nl_catalog.dart';

Future<List<DriverOfflineEuropePlace>> searchDriverOfflineEuropePlaces({
  required String query, String languageCode = 'en', http.Client? client, String? accessToken,
}) => searchDriverOfflineBeNlAreas(query: query, languageCode: languageCode);
