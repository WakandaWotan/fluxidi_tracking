import 'dart:convert';
import 'package:http/http.dart' as http;
import '../app_config.dart';
import '../customer_session_store.dart';
import '../company_session_store.dart';
import '../driver_session_store.dart';
import '../limousine/limousine_address_lookup.dart';

String officialAddressNotice(String language, {bool verification = false}) {
  if (verification)
    return switch (language) {
      'en' => 'This address could not be verified. Search again.',
      'fr' =>
        'Cette adresse n’a pas pu être vérifiée. Recherchez-la à nouveau.',
      'de' => 'Diese Adresse konnte nicht bestätigt werden. Suche erneut.',
      'es' => 'No se pudo verificar esta dirección. Búscala de nuevo.',
      _ => 'Dit adres kon niet worden bevestigd. Zoek het opnieuw.',
    };
  return switch (language) {
    'en' =>
      'Address search is unavailable or needs a more complete address. Please try again.',
    'fr' =>
      'Recherche indisponible ou adresse trop incomplète. Réessayez avec une adresse complète.',
    'de' =>
      'Adresssuche nicht verfügbar oder Adresse unvollständig. Bitte erneut versuchen.',
    'es' =>
      'La búsqueda no está disponible o la dirección está incompleta. Inténtalo de nuevo.',
    _ =>
      'Adres zoeken is nu niet beschikbaar of vereist een vollediger adres. Probeer opnieuw.',
  };
}

/// The sealed official BE/NL HTTP contract. No geocoder/provider fallback,
/// postcode/radius matcher, completed-result cache or booking side effect.
class OfficialAddressLookup extends LimousinePlaceLookup {
  OfficialAddressLookup({
    String? baseUrl,
    bool operatorSession = true,
    bool driverSession = false,
    http.Client? client,
    Future<String> Function()? tokenLoader,
    int Function()? sessionRevision,
  }) : assert(!driverSession || operatorSession),
       _base = Uri.parse(baseUrl ?? kBookingBaseUrl),
       _http = client ?? http.Client(),
       _tokenLoader =
           tokenLoader ??
           (() async {
             if (!operatorSession)
               return (await CustomerSessionStore.instance.loadValidSession())
                       ?.customerSessionToken ??
                   '';
             if (driverSession) {
               final driver =
                   activeDriverSessionNotifier.value ??
                   await DriverSessionStore.instance.load();
               return (driver?.driverSessionToken ?? '').trim();
             }
             final company =
                 activeCompanySessionNotifier.value ??
                 await CompanySessionStore.instance.loadSession();
             return (company?.companySessionToken ?? '').trim();
           }),
       _revision =
           sessionRevision ??
           (() => operatorSession
               ? driverSession
                     ? Object.hash(
                         activeDriverSessionNotifier.value?.tenantId,
                         activeDriverSessionNotifier.value?.companyId,
                         activeDriverSessionNotifier.value?.driverId,
                         activeDriverSessionNotifier.value?.driverSessionToken,
                       )
                     : Object.hash(
                         activeCompanySessionNotifier.value?.companyId,
                         activeCompanySessionNotifier
                             .value
                             ?.companySessionToken,
                       )
               : CustomerSessionStore.sessionRevision.value),
       _path = operatorSession
           ? '/company/official-address-search'
           : '/public/customer/official-address-search',
       super(token: '');
  final Uri _base;
  final String _path;
  final http.Client _http;
  final Future<String> Function() _tokenLoader;
  final int Function() _revision;
  static const schema = 'fluxidi-official-address-text-v1';
  @override
  bool get requiresOfficialSelection => true;

  Future<Map<String, dynamic>> _post(Map<String, dynamic> body) async {
    final token = await _tokenLoader();
    final revision = _revision();
    if (token.isEmpty) throw StateError('official_address_session');
    if (_base.scheme != 'https' ||
        _base.host.isEmpty ||
        _base.userInfo.isNotEmpty)
      throw StateError('official_address_endpoint');
    final encoded = jsonEncode(body);
    if (utf8.encode(encoded).length > 2048)
      throw StateError('official_address_input');
    final request = http.Request('POST', _base.resolve(_path))
      ..followRedirects = false
      ..headers.addAll({
        'authorization': 'Bearer $token',
        'content-type': 'application/json',
      })
      ..body = encoded;
    final streamed = await _http
        .send(request)
        .timeout(const Duration(seconds: 7));
    final bytes = <int>[];
    await for (final part in streamed.stream.timeout(
      const Duration(seconds: 7),
    )) {
      bytes.addAll(part);
      if (bytes.length > 100000) throw StateError('official_address_response');
    }
    final currentToken = await _tokenLoader();
    if (revision != _revision() || token != currentToken)
      throw StateError('official_address_session');
    if (streamed.statusCode != 200)
      throw StateError('official_address_http_${streamed.statusCode}');
    final raw = jsonDecode(utf8.decode(bytes));
    if (raw is! Map ||
        raw['schema'] != schema ||
        raw['accessProven'] != false ||
        raw['routeProven'] != false)
      throw StateError('official_address_response');
    return Map<String, dynamic>.from(raw);
  }

  LimousinePlaceSuggestion _candidate(Object? raw, String revision) {
    if (raw is! Map) throw StateError('official_address_response');
    final identity = OfficialAddressIdentity.fromJson(raw['official_address']);
    if (identity == null ||
        identity.indexRevision != revision ||
        raw['canonical_label'] is! String ||
        (raw['canonical_label'] as String).trim().isEmpty ||
        raw['address'] is! Map ||
        !['BE', 'NL'].contains(raw['address']['country']) ||
        raw['accessProven'] != false ||
        raw['routeProven'] != false ||
        raw['routing_access'] != 'not_evaluated')
      throw StateError('official_address_response');
    final position = raw['position'];
    double? lat, lon;
    if (position != null) {
      if (position is! Map ||
          position['latitude'] is! num ||
          position['longitude'] is! num)
        throw StateError('official_address_response');
      lat = (position['latitude'] as num).toDouble();
      lon = (position['longitude'] as num).toDouble();
      if (!limousineCoordinatesAreValid(lat, lon))
        throw StateError('official_address_response');
    }
    final usable =
        // Current official identity may be selected even when its source does
        // not publish assignment status. Access and routes remain unproven.
        ((raw['identity_status'] == 'identity_resolved' &&
                raw['officially_assigned'] == true) ||
            (raw['identity_status'] == 'official_assignment_unknown' &&
                raw['officially_assigned'] == null)) &&
        raw['source_status'] == 'current' &&
        raw['position_status'] == 'official_source_position' &&
        lat != null &&
        lon != null &&
        (lat != 0 || lon != 0);
    return LimousinePlaceSuggestion(
      label: raw['canonical_label'],
      lat: lat,
      lon: lon,
      officialAddress: identity,
      officialUsable: usable,
      placeType: 'address',
      postcode: (raw['address']['postcode'] ?? '').toString(),
      locality: (raw['address']['municipality'] ?? '').toString(),
      country: raw['address']['country'],
    );
  }

  @override
  Future<LimousinePlaceLookupResult> search(
    String rawQuery, {
    String language = 'nl',
    double? proximityLat,
    double? proximityLon,
    String? contextCountry,
  }) async {
    final query = rawQuery;
    if (query.trim().length < 3) return const LimousinePlaceLookupResult();
    final body = await _post({
      'schema': schema,
      'mode': 'suggest',
      'query': query.trim(),
      'language': language,
      'limit': 6,
    });
    if (body['status'] == 'needs_refinement')
      return const LimousinePlaceLookupResult(hadError: true);
    if (body['ok'] != true ||
        !['suggestions', 'no_matches'].contains(body['status']) ||
        body['candidates'] is! List ||
        (body['candidates'] as List).length > 20 ||
        body['index_revision'] is! String)
      throw StateError('official_address_response');
    if ((body['status'] == 'no_matches') !=
        (body['candidates'] as List).isEmpty)
      throw StateError('official_address_response');
    return LimousinePlaceLookupResult(
      suggestions: [
        for (final c in body['candidates'])
          _candidate(c, body['index_revision']),
      ],
    );
  }

  Future<LimousinePlaceSuggestion> _verify(
    LimousinePlaceSuggestion candidate,
    String mode,
  ) async {
    final ref = candidate.officialAddress;
    if (ref == null) throw StateError('official_address_selection');
    final body = await _post({
      'schema': schema,
      'mode': mode,
      'official_address': ref.toJson(),
    });
    if (body['ok'] != true || body['index_revision'] != ref.indexRevision)
      throw StateError('official_address_changed');
    final verified = _candidate(body['candidate'], ref.indexRevision);
    if (jsonEncode(verified.officialAddress!.toJson()) !=
        jsonEncode(ref.toJson()))
      throw StateError('official_address_changed');
    return verified;
  }

  @override
  Future<LimousinePlaceSuggestion> verifySuggestion(
    LimousinePlaceSuggestion suggestion,
  ) => _verify(suggestion, 'select');

  /// Existing records may need coordinates, but a ranked first suggestion is
  /// not an exact address. Resolve only one equal complete official label.
  Future<LimousinePlaceSuggestion> resolveExactLabel(String label, {String language = 'nl'}) async {
    String normalized(String value) => value.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
    final result = await search(label, language: language);
    final matches = result.suggestions.where((s) => s.officialUsable && s.hasCoordinates && normalized(s.label) == normalized(label)).toList();
    if (result.hadError || matches.length != 1) throw StateError('official_address_selection_required');
    final verified = await verifySuggestion(matches.single);
    if (!verified.officialUsable || !verified.hasCoordinates) throw StateError('official_address_not_usable');
    return verified;
  }
  @override
  Future<void> reverifyAddress(LimousineAddressValue value) async {
    final verified = await _verify(
      LimousinePlaceSuggestion(
        label: value.displayText,
        officialAddress: value.officialAddress,
      ),
      'reverify',
    );
    if (!verified.officialUsable)
      throw StateError('official_address_not_usable');
  }

  @override
  Future<LimousinePlaceLookupResult> reverseGeocode(
    double lat,
    double lon, {
    String language = 'nl',
  }) async => const LimousinePlaceLookupResult(hadError: true);
  @override
  void dispose() {
    _http.close();
    super.dispose();
  }
}
